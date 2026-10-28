"""Public fixture staging workflow orchestration."""

from __future__ import annotations

import os
import stat
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Mapping, Sequence

from scripts.android_qualification.fixture_staging_contract import (
    DEFAULT_MINIMUM_FREE_BYTES,
    StagingResult,
    _StagingFailure,
    default_staging_root,
)
from scripts.android_qualification.fixture_staging_files import (
    _check_capacity,
    _copy_file,
    _path_overlaps,
    _source_tree,
    _validate_destination_ancestors,
    _validate_structure,
    _verify_published,
)
from scripts.android_qualification.fixture_staging_manifest import (
    _parse_manifest,
    _selected_fixtures,
)
from scripts.android_qualification.fixture_staging_runs import (
    _record_fixtures,
    _result,
    _write_record,
)


def stage_fixtures(
    manifest: object,
    sources: Mapping[str, str | Path],
    *,
    selected_fixture_ids: Sequence[str],
    owner_approved: bool,
    staging_root: str | Path | None = None,
    minimum_free_bytes: int = DEFAULT_MINIMUM_FREE_BYTES,
) -> StagingResult:
    """Copy, verify, and publish the explicitly approved fixture selection."""

    if owner_approved is not True:
        return StagingResult(status="failed", error_code="OWNER_APPROVAL_REQUIRED")
    run_directory: Path | None = None
    record: dict[str, object] | None = None
    copied_bytes = 0
    copied_files = 0
    try:
        plan = _parse_manifest(manifest)
        fixtures = plan.fixtures
        selected = _selected_fixtures(
            plan.required_fixture_ids,
            selected_fixture_ids,
            plan.coverage_mode,
            plan.mandatory_fixture_ids,
        )
        if not isinstance(sources, Mapping) or set(sources) != set(selected):
            raise _StagingFailure("SOURCE_SELECTION_MISMATCH")
        if type(minimum_free_bytes) is not int or minimum_free_bytes < 0:
            raise _StagingFailure("CAPACITY_CONFIGURATION_INVALID")
        destination_root = Path(staging_root).expanduser() if staging_root is not None else default_staging_root()
        _validate_destination_ancestors(destination_root)
        try:
            destination_root = destination_root.resolve(strict=False)
        except (OSError, RuntimeError):
            raise _StagingFailure("DESTINATION_UNSAFE") from None
        _validate_destination_ancestors(destination_root)
        resolved_sources = {}
        for fixture_id in selected:
            resolved_sources[fixture_id] = _source_tree(sources[fixture_id], fixtures[fixture_id])
            if _path_overlaps(destination_root, resolved_sources[fixture_id]):
                raise _StagingFailure("SOURCE_DESTINATION_OVERLAP")
        file_specs = [item for fixture_id in selected for item in fixtures[fixture_id].files]
        expected_bytes = sum(item.size for item in file_specs)
        _check_capacity(destination_root, expected_bytes + minimum_free_bytes)
        destination_root.mkdir(parents=True, exist_ok=True, mode=0o700)
        _validate_destination_ancestors(destination_root)
        root_info = destination_root.lstat()
        if (
            stat.S_ISLNK(root_info.st_mode) or not stat.S_ISDIR(root_info.st_mode)
            or root_info.st_uid != os.getuid() or stat.S_IMODE(root_info.st_mode) & 0o077
        ):
            raise _StagingFailure("DESTINATION_UNSAFE")
        run_id = uuid.uuid4().hex
        run_directory = destination_root / run_id
        run_directory.mkdir(mode=0o700)
        record = {
            "schema_version": 1,
            "run_id": run_id,
            "status": "staging",
            "created_at": datetime.now(timezone.utc).isoformat(),
            "manifest_sha256": plan.manifest_sha256,
            "selected_fixture_ids": list(selected),
            "fixtures": _record_fixtures(fixtures, selected),
            "owner_approved": True,
            "minimum_free_bytes": minimum_free_bytes,
            "file_count": 0,
            "byte_count": 0,
        }
        _write_record(run_directory, record)
        incomplete = run_directory / "incomplete"
        incomplete.mkdir(mode=0o700)
        remaining = expected_bytes
        for fixture_id in selected:
            fixture_root = incomplete / fixture_id
            fixture_root.mkdir(mode=0o700)
            for item in fixtures[fixture_id].files:
                count, remaining = _copy_file(
                    resolved_sources[fixture_id] / item.path,
                    fixture_root / item.path,
                    item,
                    destination_root,
                    remaining,
                    minimum_free_bytes,
                )
                copied_bytes += count
                copied_files += 1
                record["file_count"] = copied_files
                record["byte_count"] = copied_bytes
        _check_capacity(destination_root, minimum_free_bytes)
        copied_count, verified_bytes = _verify_published(incomplete, record["fixtures"])
        if copied_count != len(file_specs) or verified_bytes != expected_bytes:
            raise _StagingFailure("PUBLISHED_SET_INCOMPLETE")
        for fixture in record["fixtures"]:
            _validate_structure(incomplete / fixture["fixture_id"], fixture)
        record["file_count"] = copied_count
        record["byte_count"] = verified_bytes
        record["updated_at"] = datetime.now(timezone.utc).isoformat()
        _write_record(run_directory, record)
        (run_directory / "incomplete").rename(run_directory / "published")
        record["status"] = "verified"
        record["updated_at"] = datetime.now(timezone.utc).isoformat()
        _write_record(run_directory, record)
        return _result(record, run_directory)
    except _StagingFailure as failure:
        if run_directory is not None and record is not None:
            record["status"] = "failed"
            record["error_code"] = failure.code
            record["file_count"] = copied_files
            record["byte_count"] = copied_bytes
            try:
                _write_record(run_directory, record)
            except _StagingFailure:
                pass
            return _result(record, run_directory, error_code=failure.code)
        return StagingResult(status="failed", error_code=failure.code)
    except OSError:
        if run_directory is not None and record is not None:
            record["status"] = "failed"
            record["error_code"] = "FILESYSTEM_ERROR"
            try:
                _write_record(run_directory, record)
            except _StagingFailure:
                pass
            return _result(record, run_directory, error_code="FILESYSTEM_ERROR")
        return StagingResult(status="failed", error_code="FILESYSTEM_ERROR")
    except (TypeError, ValueError, RuntimeError):
        return StagingResult(status="failed", error_code="FILESYSTEM_ERROR")
