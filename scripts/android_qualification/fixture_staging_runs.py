"""Run metadata, inspection, and best-effort cleanup."""

from __future__ import annotations

import hashlib
import json
import os
import re
import stat
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Mapping, Sequence

from scripts.android_qualification import fixture_oracle
from scripts.android_qualification.fixture_staging_contract import (
    CleanupResult,
    FixtureAssessment,
    FixtureSpec,
    StagingResult,
    _StagingFailure,
    default_staging_root,
)
from scripts.android_qualification.fixture_staging_files import (
    COPY_CHUNK_BYTES,
    _open_readonly,
    _validate_destination_ancestors,
    _validate_structure,
    _verify_published,
)
from scripts.android_qualification.fixture_staging_manifest import (
    _digest,
    _document,
    _graph_reaches_all,
    _identifier,
    _relative_path,
    _text,
)


RUN_RECORD_NAME = "run.json"

_RUN_ID = re.compile(r"[0-9a-f]{32}\Z")

def _record_fixtures(
    fixtures: Mapping[str, FixtureSpec], selected: Sequence[str]
) -> list[dict[str, object]]:
    records = []
    for fixture_id in selected:
        fixture = fixtures[fixture_id]
        records.append({
            "fixture_id": fixture_id,
            "entrypoint": fixture.entrypoint,
            "structural_expectations": dict(fixture.structural_expectations),
            "files": [
                {
                    "path": item.path,
                    "role": item.role,
                    "size": item.size,
                    "sha256": item.sha256,
                }
                for item in fixture.files
            ],
            "companions": [
                {"source": edge.source, "target": edge.target}
                for edge in fixture.companions
            ],
            "expected_identity": dict(fixture.expected_identity),
            "identity_evidence": (
                dict(fixture.identity_evidence)
                if fixture.identity_evidence is not None
                else None
            ),
            "identity_support": fixture.identity_support,
            "qualification_status": fixture.qualification_status,
        })
    return records

def _write_record(run_directory: Path, record: dict[str, object]) -> None:
    temporary = run_directory / f".{RUN_RECORD_NAME}.{uuid.uuid4().hex}.tmp"
    try:
        payload = (json.dumps(record, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode("utf-8")
        descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "wb") as writer:
            writer.write(payload)
            writer.flush()
            os.fsync(writer.fileno())
        os.replace(temporary, run_directory / RUN_RECORD_NAME)
        try:
            directory_fd = os.open(run_directory, os.O_RDONLY)
            try:
                os.fsync(directory_fd)
            finally:
                os.close(directory_fd)
        except OSError:
            pass
    except (OSError, TypeError, ValueError):
        try:
            temporary.unlink(missing_ok=True)
        except OSError:
            pass
        raise _StagingFailure("RUN_RECORD_WRITE_FAILED") from None

def _assessments(record: Mapping[str, object], *, verified: bool) -> tuple[FixtureAssessment, ...]:
    assessments = []
    for fixture in record.get("fixtures", []):
        assessments.append(FixtureAssessment(
            fixture_id=fixture["fixture_id"],
            byte_integrity="verified" if verified else "not_verified",
            structural_expectations="validated" if verified else "not_verified",
            identity_support=fixture["identity_support"],
            owner_approval="approved" if record.get("owner_approved") is True else "not_approved",
            qualification_status=fixture["qualification_status"],
        ))
    return tuple(assessments)

def _result(
    record: Mapping[str, object], run_directory: Path, *,
    error_code: str | None = None, status_override: str | None = None,
) -> StagingResult:
    record_status = record.get("status", "failed")
    status = status_override or record_status
    published = run_directory / "published" if status == "verified" else None
    effective_error = record.get("error_code") if status_override is None else error_code
    return StagingResult(
        status=status,
        run_id=record.get("run_id"),
        run_directory=run_directory,
        published_path=published,
        manifest_sha256=record.get("manifest_sha256"),
        fixture_ids=tuple(record.get("selected_fixture_ids", ())),
        file_count=record.get("file_count", 0),
        byte_count=record.get("byte_count", 0),
        assessments=_assessments(record, verified=status == "verified"),
        error_code=effective_error,
    )

def _validate_run_record(record: object, run_id: str) -> dict[str, object]:
    """Validate the persisted run contract before inspection or cleanup.

    The original manifest is not stored with a run. Revalidate its persisted
    identity, path, file, and companion claims so later operations can reject a
    damaged record without relying on the manifest that created it. The saved
    record has a smaller schema and must remain independently inspectable.
    """

    if type(record) is not dict:
        raise _StagingFailure("RUN_RECORD_INVALID")
    required = {
        "schema_version", "run_id", "status", "created_at", "manifest_sha256",
        "selected_fixture_ids", "fixtures", "owner_approved", "minimum_free_bytes",
        "file_count", "byte_count",
    }
    if not required <= set(record) or set(record) - required - {"updated_at", "error_code"}:
        raise _StagingFailure("RUN_RECORD_INVALID")
    if (
        type(record["schema_version"]) is not int or record["schema_version"] != 1
        or record["run_id"] != run_id
        or type(record["status"]) is not str
        or record["status"] not in {"staging", "verified", "failed", "cleanup_pending", "cleaned"}
        or record["owner_approved"] is not True
    ):
        raise _StagingFailure("RUN_RECORD_INVALID")
    try:
        _text(record["created_at"], limit=128)
        _digest(record["manifest_sha256"])
        if "updated_at" in record:
            _text(record["updated_at"], limit=128)
        if "error_code" in record:
            _text(record["error_code"], limit=128)
        minimum_free = record["minimum_free_bytes"]
        file_count = record["file_count"]
        byte_count = record["byte_count"]
        if (
            type(minimum_free) is not int or minimum_free < 0
            or type(file_count) is not int or file_count < 0
            or type(byte_count) is not int or byte_count < 0
        ):
            raise _StagingFailure("RUN_RECORD_INVALID")
        selected_value = record["selected_fixture_ids"]
        fixture_value = record["fixtures"]
        if type(selected_value) is not list or not selected_value or type(fixture_value) is not list:
            raise _StagingFailure("RUN_RECORD_INVALID")
        selected = [_identifier(value) for value in selected_value]
        if len(set(selected)) != len(selected) or len(selected) != len(fixture_value):
            raise _StagingFailure("RUN_RECORD_INVALID")
        fixture_ids = []
        for fixture in fixture_value:
            if type(fixture) is not dict or set(fixture) != {
                "fixture_id", "entrypoint", "structural_expectations", "files",
                "companions", "expected_identity", "identity_evidence",
                "identity_support", "qualification_status",
            }:
                raise _StagingFailure("RUN_RECORD_INVALID")
            fixture_id = _identifier(fixture["fixture_id"])
            fixture_ids.append(fixture_id)
            entrypoint = _relative_path(fixture["entrypoint"])
            expectations = fixture["structural_expectations"]
            if type(expectations) is not dict or not expectations:
                raise _StagingFailure("RUN_RECORD_INVALID")
            for key, value in expectations.items():
                _text(key, limit=128)
                if type(value) not in {str, int, bool} or (type(value) is str and not value):
                    raise _StagingFailure("RUN_RECORD_INVALID")
            expected_identity = fixture["expected_identity"]
            if type(expected_identity) is not dict or not expected_identity:
                raise _StagingFailure("RUN_RECORD_INVALID")
            for key, value in expected_identity.items():
                _text(key, limit=128)
                if type(value) not in {str, int, bool} or (type(value) is str and not value):
                    raise _StagingFailure("RUN_RECORD_INVALID")
            try:
                identity_assessment = fixture_oracle.assess_identity_evidence(
                    expected_identity,
                    fixture["identity_evidence"],
                )
            except fixture_oracle.OracleError:
                raise _StagingFailure("RUN_RECORD_INVALID") from None
            if (
                type(fixture["identity_support"]) is not str
                or fixture["identity_support"] not in {
                    "not_independently_verified", "synthetic_only", "pinned_unverified",
                }
                or fixture["identity_support"] != identity_assessment.identity_support
                or fixture["qualification_status"] != "not_qualified"
            ):
                raise _StagingFailure("RUN_RECORD_INVALID")
            files = fixture["files"]
            if type(files) is not list or not files:
                raise _StagingFailure("RUN_RECORD_INVALID")
            paths = set()
            folded_components: dict[str, str] = {}
            for item in files:
                if type(item) is not dict or set(item) != {"path", "role", "size", "sha256"}:
                    raise _StagingFailure("RUN_RECORD_INVALID")
                path = _relative_path(item["path"])
                _text(item["role"], limit=64)
                size = item["size"]
                if type(size) is not int or size < 0 or path in paths:
                    raise _StagingFailure("RUN_RECORD_INVALID")
                paths.add(path)
                _digest(item["sha256"])
                parts = path.split("/")
                for index in range(1, len(parts) + 1):
                    prefix = "/".join(parts[:index])
                    prior = folded_components.setdefault(prefix.casefold(), prefix)
                    if prior != prefix:
                        raise _StagingFailure("RUN_RECORD_INVALID")
            if any(
                "/".join(path.split("/")[:index]) in paths
                for path in paths
                for index in range(1, len(path.split("/")))
            ) or entrypoint not in paths:
                raise _StagingFailure("RUN_RECORD_INVALID")
            companions = fixture["companions"]
            if type(companions) is not list:
                raise _StagingFailure("RUN_RECORD_INVALID")
            adjacency = {path: [] for path in paths}
            seen_edges = set()
            for edge in companions:
                if type(edge) is not dict or set(edge) != {"source", "target"}:
                    raise _StagingFailure("RUN_RECORD_INVALID")
                source = _relative_path(edge["source"])
                target = _relative_path(edge["target"])
                if source not in paths or target not in paths or (source, target) in seen_edges:
                    raise _StagingFailure("RUN_RECORD_INVALID")
                seen_edges.add((source, target))
                adjacency[source].append(target)
            if not _graph_reaches_all(entrypoint, paths, adjacency):
                raise _StagingFailure("RUN_RECORD_INVALID")
        if fixture_ids != selected:
            raise _StagingFailure("RUN_RECORD_INVALID")
    except _StagingFailure as failure:
        if failure.code == "RUN_RECORD_INVALID":
            raise
        raise _StagingFailure("RUN_RECORD_INVALID") from None
    return record

def _run_directory(run_id: object, staging_root: str | Path | None) -> tuple[str, Path]:
    if type(run_id) is not str or _RUN_ID.fullmatch(run_id) is None:
        raise _StagingFailure("RUN_ID_INVALID")
    try:
        root = Path(staging_root).expanduser() if staging_root is not None else default_staging_root()
        _validate_destination_ancestors(root)
        run_directory = root / run_id
        root_info = root.lstat()
        directory_info = run_directory.lstat()
    except (OSError, TypeError, ValueError):
        raise _StagingFailure("RUN_NOT_FOUND") from None
    if (
        stat.S_ISLNK(root_info.st_mode) or not stat.S_ISDIR(root_info.st_mode)
        or stat.S_ISLNK(directory_info.st_mode) or not stat.S_ISDIR(directory_info.st_mode)
        or root_info.st_uid != os.getuid() or directory_info.st_uid != os.getuid()
        or stat.S_IMODE(root_info.st_mode) & 0o077
        or stat.S_IMODE(directory_info.st_mode) & 0o077
    ):
        raise _StagingFailure("RUN_UNSAFE")
    return run_id, run_directory

def _load_run_record(run_directory: Path, run_id: str) -> dict[str, object]:
    marker = run_directory / RUN_RECORD_NAME
    try:
        marker_info = marker.lstat()
        if stat.S_ISLNK(marker_info.st_mode) or not stat.S_ISREG(marker_info.st_mode):
            raise _StagingFailure("RUN_RECORD_INVALID")
        record = _document(marker)
        return _validate_run_record(record, run_id)
    except _StagingFailure as failure:
        if failure.code == "MANIFEST_UNAVAILABLE":
            raise _StagingFailure("RUN_RECORD_INVALID") from None
        if failure.code in {"MANIFEST_INVALID", "RUN_RECORD_INVALID"}:
            raise _StagingFailure("RUN_RECORD_INVALID") from None
        raise
    except OSError:
        raise _StagingFailure("RUN_RECORD_INVALID") from None

def _recognized_run_entries(run_directory: Path, record: Mapping[str, object]) -> bool:
    allowed = {RUN_RECORD_NAME}
    if record["status"] in {"staging", "verified", "failed", "cleanup_pending"}:
        allowed.add("published")
    if record["status"] in {"staging", "failed", "cleanup_pending"}:
        allowed.add("incomplete")
    try:
        entries = {entry.name for entry in run_directory.iterdir()}
    except OSError:
        raise _StagingFailure("RUN_UNAVAILABLE") from None
    return entries <= allowed

def inspect_staging(run_id: str, *, staging_root: str | Path | None = None) -> StagingResult:
    """Inspect a run marker and independently rehash any published fixture set."""

    run_directory: Path | None = None
    try:
        normalized_id, run_directory = _run_directory(run_id, staging_root)
        record = _load_run_record(run_directory, normalized_id)
        if not _recognized_run_entries(run_directory, record):
            raise _StagingFailure("RUN_CONTENT_MISMATCH")
        published = run_directory / "published"
        if record["status"] == "verified":
            file_count, byte_count = _verify_published(published, record["fixtures"])
            if file_count != record["file_count"] or byte_count != record["byte_count"]:
                raise _StagingFailure("RUN_RECORD_MISMATCH")
            for fixture in record["fixtures"]:
                _validate_structure(published / fixture["fixture_id"], fixture)
            return _result(record, run_directory)
        if record["status"] == "staging":
            if published.exists():
                return _result(
                    record, run_directory, error_code="FINALIZATION_INTERRUPTED",
                    status_override="incomplete",
                )
            return _result(
                record, run_directory, error_code="STAGING_INTERRUPTED",
                status_override="incomplete",
            )
        if record["status"] == "cleanup_pending":
            return _result(record, run_directory, error_code=record.get("error_code"))
        return _result(record, run_directory)
    except _StagingFailure as failure:
        return StagingResult(
            status="failed", run_id=run_id if type(run_id) is str else None,
            run_directory=run_directory, error_code=failure.code,
        )
    except (OSError, TypeError, ValueError, RuntimeError):
        return StagingResult(
            status="failed", run_id=run_id if type(run_id) is str else None,
            run_directory=run_directory, error_code="RUN_UNAVAILABLE",
        )

def _remove_recognized_tree(root: Path, fixture_records: Sequence[Mapping[str, object]]) -> tuple[int, bool]:
    expected_files = {
        f'{fixture["fixture_id"]}/{item["path"]}': item
        for fixture in fixture_records for item in fixture["files"]
    }
    expected_directories = set()
    for relative in expected_files:
        parts = relative.split("/")
        for index in range(1, len(parts)):
            expected_directories.add("/".join(parts[:index]))
    if not root.exists() and not root.is_symlink():
        return 0, False
    try:
        root_info = root.lstat()
    except OSError:
        return 0, True
    if stat.S_ISLNK(root_info.st_mode) or not stat.S_ISDIR(root_info.st_mode):
        return 0, True
    removed = 0
    unrecognized = False
    directories: list[Path] = []
    for directory, names, files in os.walk(root, topdown=True, followlinks=False):
        current = Path(directory)
        directories.append(current)
        retained = []
        for name in names:
            child = current / name
            relative = child.relative_to(root).as_posix()
            try:
                info = child.lstat()
            except OSError:
                unrecognized = True
                continue
            if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
                unrecognized = True
                continue
            if relative not in expected_directories:
                unrecognized = True
                continue
            retained.append(name)
        names[:] = retained
        for name in files:
            child = current / name
            relative = child.relative_to(root).as_posix()
            try:
                info = child.lstat()
                expected = expected_files.get(relative)
                if expected is None or not stat.S_ISREG(info.st_mode):
                    unrecognized = True
                    continue
                if not _matches_file_spec(child, expected, info):
                    unrecognized = True
                    continue
                child.unlink()
                removed += 1
            except OSError:
                unrecognized = True
    for directory in reversed(directories):
        if directory == root:
            continue
        try:
            directory.rmdir()
        except OSError:
            pass
    try:
        root.rmdir()
    except OSError:
        try:
            remains = any(root.iterdir())
        except OSError:
            remains = True
        if remains:
            unrecognized = True
    return removed, unrecognized

def _matches_file_spec(path: Path, expected: Mapping[str, object], before: os.stat_result) -> bool:
    if before.st_size != expected["size"]:
        return False
    digest = hashlib.sha256()
    count = 0
    try:
        with _open_readonly(path) as reader:
            while True:
                chunk = reader.read(COPY_CHUNK_BYTES)
                if not chunk:
                    break
                digest.update(chunk)
                count += len(chunk)
                if count > expected["size"]:
                    return False
    except OSError:
        return False
    return count == expected["size"] and digest.hexdigest() == expected["sha256"]

def cleanup_staging(run_id: str, *, staging_root: str | Path | None = None) -> CleanupResult:
    """Remove only manifest-listed regular files and preserve the run tombstone."""

    run_directory: Path | None = None
    removed_files = 0
    try:
        normalized_id, run_directory = _run_directory(run_id, staging_root)
        record = _load_run_record(run_directory, normalized_id)
        unexpected_entries = {entry.name for entry in run_directory.iterdir()} - {
            RUN_RECORD_NAME, "published", "incomplete"
        }
        unrecognized = bool(unexpected_entries)
        for name in ("published", "incomplete"):
            removed, found_unrecognized = _remove_recognized_tree(
                run_directory / name, record["fixtures"],
            )
            removed_files += removed
            unrecognized = unrecognized or found_unrecognized
        record["updated_at"] = datetime.now(timezone.utc).isoformat()
        if unrecognized:
            record["status"] = "cleanup_pending"
            record["error_code"] = "UNRECOGNIZED_CONTENT"
            _write_record(run_directory, record)
            return CleanupResult(
                status="cleanup_pending", run_id=normalized_id,
                removed_files=removed_files, error_code="UNRECOGNIZED_CONTENT",
            )
        record["status"] = "cleaned"
        record.pop("error_code", None)
        _write_record(run_directory, record)
        return CleanupResult(status="cleaned", run_id=normalized_id, removed_files=removed_files)
    except _StagingFailure as failure:
        return CleanupResult(
            status="failed", run_id=run_id if type(run_id) is str else "",
            removed_files=removed_files, error_code=failure.code,
        )
    except (OSError, TypeError, ValueError, RuntimeError):
        return CleanupResult(
            status="failed", run_id=run_id if type(run_id) is str else "",
            removed_files=removed_files, error_code="RUN_UNAVAILABLE",
        )
