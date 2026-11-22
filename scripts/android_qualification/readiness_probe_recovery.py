"""Recover cleanup of a pinned Readiness install after its host process exits."""

from __future__ import annotations

import hashlib
import json
import os
import secrets
import stat
import time
from collections.abc import Mapping
from datetime import datetime, timezone
from pathlib import Path

from . import _evidence_storage
from . import adb_forward
from . import q7_exploratory_acquisition as q7
from .readiness_probe import ProbeError


_INSTALL_RECORD_SCHEMA = "argus-issue-74-b1-preparation-observation-v1"
_OUTCOME_SCHEMA = "argus-issue-74-b1-cleanup-recovery-v1"
_COMMAND_CATEGORIES = (
    "get_state",
    "fingerprint",
    "current_user",
    "package_state",
    "package_uninstall",
)
_MAX_JSON_RECORD_BYTES = 1024 * 1024


def _object_without_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON object key")
        result[key] = value
    return result


def _reject_non_finite(value):
    raise ValueError("non-finite JSON value")


def _parse_private_json(raw):
    return json.loads(
        raw.decode("utf-8", errors="strict"),
        object_pairs_hook=_object_without_duplicate_keys,
        parse_constant=_reject_non_finite,
    )


def _parse_utc_timestamp(value):
    """Parse the canonical UTC timestamp used to order private evidence records."""
    if type(value) is not str:
        return None
    try:
        parsed = datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError:
        return None
    if parsed.strftime("%Y-%m-%dT%H:%M:%SZ") != value:
        return None
    return parsed.replace(tzinfo=timezone.utc)


def _parse_utc_timestamp_for_stale_resolution(value):
    """Parse a fractional UTC timestamp when comparing an install with cleanup."""
    if type(value) is not str or not value.endswith("Z"):
        return None
    timestamp_text = value[:-1]
    timestamp_base, separator, fraction = timestamp_text.partition(".")
    if (
        not separator
        or not 1 <= len(fraction) <= 6
        or not fraction.isascii()
        or not fraction.isdigit()
    ):
        return None
    try:
        parsed = datetime.strptime(value, "%Y-%m-%dT%H:%M:%S.%fZ")
    except ValueError:
        return None
    if parsed.strftime("%Y-%m-%dT%H:%M:%S") != timestamp_base:
        return None
    return parsed.replace(tzinfo=timezone.utc)


def _valid_source_identity(value):
    if not isinstance(value, Mapping):
        return False
    for name in ("adb_forward_sha256", "recovery_sha256"):
        digest = value.get(name)
        if (
            type(digest) is not str
            or len(digest) != 64
            or any(character not in "0123456789abcdef" for character in digest)
        ):
            return False
    return True


def _legacy_install_preceded_cleanup(candidate_index, candidates, cleanup_metadata):
    """Resolve a legacy record only when it was the sole earlier install record."""
    earlier_candidates = [
        index
        for index, (_, metadata) in enumerate(candidates)
        if metadata.st_ctime_ns < cleanup_metadata.st_ctime_ns
        and metadata.st_mtime_ns < cleanup_metadata.st_mtime_ns
    ]
    return earlier_candidates == [candidate_index]


def _valid_install_record(record, target_reference):
    if not isinstance(record, Mapping):
        return False
    identity = record.get("identity_private")
    artifact = record.get("artifact")
    if not isinstance(identity, Mapping) or not isinstance(artifact, Mapping):
        return False
    serial = identity.get("serial")
    fingerprint = identity.get("build_fingerprint")
    user_id = record.get("android_user_private")
    package_uid = record.get("package_uid_private")
    return (
        record.get("schema") == _INSTALL_RECORD_SCHEMA
        and record.get("target_reference") == target_reference
        and record.get("identity_preflight_record_bound") is True
        and record.get("identity_match") is True
        and record.get("qualification_assertions_passed") is False
        and record.get("install_status") == "installed"
        and _parse_utc_timestamp(record.get("acquired_at_utc")) is not None
        and record.get("package_baseline_absent") is True
        and adb_forward._valid_target(serial)
        and type(fingerprint) is str
        and adb_forward._BUILD_PATTERN.fullmatch(fingerprint) is not None
        and artifact.get("package") == adb_forward._READINESS_PROBE_PACKAGE
        and artifact.get("sha256") == adb_forward._READINESS_PROBE_APK_SHA256
        and type(artifact.get("version_code")) is int
        and artifact.get("version_code") == adb_forward._READINESS_PROBE_VERSION_CODE
        and type(user_id) is int
        and 0 <= user_id <= (1 << 31) - 1
        and type(package_uid) is int
        and 0 < package_uid <= (1 << 31) - 1
    )


def _read_install_record(outcomes_directory, target_reference):
    directory = Path(outcomes_directory)
    try:
        directory_fd = _evidence_storage._directory_descriptor(directory)
    except Exception:
        raise ProbeError("UnauthorizedPeer", "Transport") from None
    candidates = []
    cleanup_outcomes = []
    try:
        names = os.listdir(directory_fd)
        if len(names) > 256:
            raise ProbeError("ResourceLimitExceeded", "Transport")
        for name in names:
            try:
                metadata = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
            except OSError:
                raise ProbeError("IncompleteEvidence", "Transport") from None
            if stat.S_ISLNK(metadata.st_mode):
                raise ProbeError("UnauthorizedPeer", "Transport")
            if not stat.S_ISREG(metadata.st_mode) or not name.lower().endswith(".json"):
                continue
            if (
                metadata.st_uid != os.geteuid()
                or stat.S_IMODE(metadata.st_mode) != 0o600
                or metadata.st_nlink != 1
            ):
                raise ProbeError("UnauthorizedPeer", "Transport")
            if metadata.st_size < 0 or metadata.st_size > _MAX_JSON_RECORD_BYTES:
                raise ProbeError("ResourceLimitExceeded", "Transport")
            try:
                raw = _evidence_storage._read_private_file(directory, name)
            except Exception:
                raise ProbeError("UnauthorizedPeer", "Transport") from None
            try:
                record = _parse_private_json(raw)
            except Exception:
                known_schema_markers = (
                    _INSTALL_RECORD_SCHEMA.encode("ascii"),
                    _OUTCOME_SCHEMA.encode("ascii"),
                )
                if any(marker in raw for marker in known_schema_markers):
                    raise ProbeError("IncompleteEvidence", "Transport") from None
                continue
            if (
                isinstance(record, Mapping)
                and record.get("schema") == _INSTALL_RECORD_SCHEMA
                and record.get("target_reference") == target_reference
            ):
                candidates.append((record, metadata))
            elif (
                isinstance(record, Mapping)
                and record.get("schema") == _OUTCOME_SCHEMA
                and record.get("target_reference") == target_reference
            ):
                cleanup_outcomes.append((record, metadata))
    except ProbeError:
        raise
    except Exception:
        raise ProbeError("IncompleteEvidence", "Transport") from None
    finally:
        os.close(directory_fd)

    successful_cleanups = []
    for outcome, metadata in cleanup_outcomes:
        if outcome.get("classification") != "cleanup_complete":
            continue
        finished_at = _parse_utc_timestamp(outcome.get("finished_at_utc"))
        if (
            finished_at is None
            or outcome.get("failure_code") is not None
            or outcome.get("cleanup_state") not in {"uninstalled", "already_absent"}
            or outcome.get("readback_state") != "absent"
            or outcome.get("raw_output_retained") is not False
            or outcome.get("stdout_retained") is not False
            or outcome.get("stderr_retained") is not False
            or outcome.get("qualification_assertions_passed") is not False
            or not _valid_source_identity(outcome.get("source_identity"))
        ):
            raise ProbeError("IncompleteEvidence", "Transport")
        successful_cleanups.append((finished_at, metadata))

    unresolved_candidates = []
    for index, (record, metadata) in enumerate(candidates):
        if "acquired_at_utc" in record:
            acquired_at = _parse_utc_timestamp(record.get("acquired_at_utc"))
            if acquired_at is None:
                acquired_at = _parse_utc_timestamp_for_stale_resolution(
                    record.get("acquired_at_utc")
                )
                if acquired_at is None:
                    raise ProbeError("IncompleteEvidence", "Transport")
                matching_cleanups = [
                    finished_at
                    for finished_at, cleanup_metadata in successful_cleanups
                    if finished_at > acquired_at
                    and _legacy_install_preceded_cleanup(
                        index, candidates, cleanup_metadata
                    )
                ]
                if len(matching_cleanups) > 1:
                    raise ProbeError("IntegrityConflict", "Transport")
                if not matching_cleanups:
                    raise ProbeError("IncompleteEvidence", "Transport")
                resolved = True
            else:
                resolved = any(
                    finished_at > acquired_at
                    for finished_at, _ in successful_cleanups
                )
        else:
            resolved = any(
                _legacy_install_preceded_cleanup(index, candidates, cleanup_metadata)
                for _, cleanup_metadata in successful_cleanups
            )
        if not resolved:
            unresolved_candidates.append(record)
    if len(unresolved_candidates) != 1 or not _valid_install_record(
        unresolved_candidates[0], target_reference
    ):
        raise ProbeError("IntegrityConflict", "Transport")
    return unresolved_candidates[0]


class _CommandCounter:
    def __init__(self, runner):
        self._runner = runner
        self.counts = {name: 0 for name in _COMMAND_CATEGORIES}

    @staticmethod
    def _category(argv):
        command = tuple(argv[3:])
        if command == ("get-state",):
            return "get_state"
        if command == ("shell", "getprop", "ro.build.fingerprint"):
            return "fingerprint"
        if command == ("shell", "am", "get-current-user"):
            return "current_user"
        if command[:4] == ("shell", "pm", "list", "packages"):
            return "package_state"
        if command[:3] == ("shell", "pm", "uninstall"):
            return "package_uninstall"
        return None

    def run(self, argv, deadline):
        category = self._category(argv)
        if category is None:
            raise ProbeError("MalformedRequest", "Transport")
        self.counts[category] += 1
        return self._runner.run(argv, deadline)


def _timestamp(utc_clock):
    value = utc_clock()
    if not isinstance(value, datetime) or value.tzinfo is None:
        raise ProbeError("IncompleteEvidence", "Transport")
    return value.astimezone(timezone.utc).isoformat(timespec="seconds").replace(
        "+00:00", "Z"
    )


def _source_hash(path):
    try:
        return hashlib.sha256(Path(path).read_bytes()).hexdigest()
    except OSError:
        raise ProbeError("IncompleteEvidence", "Transport") from None


def _write_private_outcome(outcomes_directory, record):
    directory = Path(outcomes_directory)
    try:
        directory_fd = _evidence_storage._directory_descriptor(directory)
    except Exception:
        raise ProbeError("UnauthorizedPeer", "Transport") from None
    previous_umask = os.umask(0o077)
    descriptor = -1
    try:
        name = f"readiness-cleanup-recovery-{secrets.token_hex(8)}.json"
        descriptor = os.open(
            name,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0),
            0o600,
            dir_fd=directory_fd,
        )
        metadata = os.fstat(descriptor)
        if (
            not stat.S_ISREG(metadata.st_mode)
            or metadata.st_uid != os.geteuid()
            or stat.S_IMODE(metadata.st_mode) != 0o600
            or metadata.st_nlink != 1
        ):
            raise ProbeError("UnauthorizedPeer", "Transport")
        payload = (json.dumps(record, allow_nan=False, sort_keys=True) + "\n").encode(
            "utf-8"
        )
        if len(payload) > _MAX_JSON_RECORD_BYTES:
            raise ProbeError("ResourceLimitExceeded", "Transport")
        view = memoryview(payload)
        while view:
            written = os.write(descriptor, view)
            if written <= 0:
                raise ProbeError("IncompleteEvidence", "Transport")
            view = view[written:]
        os.fsync(descriptor)
        os.fsync(directory_fd)
    except ProbeError:
        raise
    except OSError:
        raise ProbeError("IncompleteEvidence", "Transport") from None
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        os.umask(previous_umask)
        os.close(directory_fd)


def recover_installed_readiness_probe(
    outcomes_directory,
    *,
    target_reference,
    runner=None,
    clock=time.monotonic,
    utc_clock=lambda: datetime.now(timezone.utc),
    deadline_seconds=30,
):
    """Verify the recorded install, remove it through the adapter, and record cleanup."""
    started = clock()
    started_at = _timestamp(utc_clock)
    counts = {name: 0 for name in _COMMAND_CATEGORIES}
    result = {
        "schema": _OUTCOME_SCHEMA,
        "target_reference": q7.TARGET_REFERENCE,
        "classification": "blocked",
        "failure_code": None,
        "cleanup_state": None,
        "readback_state": None,
        "adb_command_counts": counts,
        "adb_command_total": 0,
        "started_at_utc": started_at,
        "finished_at_utc": None,
        "duration_seconds": None,
        "source_identity": {},
        "raw_output_retained": False,
        "stdout_retained": False,
        "stderr_retained": False,
        "qualification_assertions_passed": False,
    }
    try:
        if (
            target_reference != q7.TARGET_REFERENCE
            or type(deadline_seconds) is not int
            or not 1 <= deadline_seconds <= 60
        ):
            raise ProbeError("MalformedRequest", "Transport")
        result["source_identity"] = {
            "adb_forward_sha256": _source_hash(adb_forward.__file__),
            "recovery_sha256": _source_hash(__file__),
        }
        record = _read_install_record(outcomes_directory, target_reference)
        target = record["identity_private"]["serial"]
        counter = _CommandCounter(
            runner if runner is not None else adb_forward._AdbCommandRunner(clock=clock)
        )
        adapter = adb_forward.AdbForwardAdapter(runner=counter, clock=clock)
        bound_identity = adapter.identity(target, deadline=started + deadline_seconds)
        if bound_identity[1] != record["identity_private"]["build_fingerprint"]:
            raise ProbeError("IntegrityConflict", "Transport")
        cleanup = adapter.recover_readiness_cleanup(
            target, record, deadline=started + deadline_seconds
        )
        result["classification"] = "cleanup_complete"
        result["cleanup_state"] = cleanup["state"]
        result["readback_state"] = cleanup["readback"]
        result["failure_code"] = None
        counts = counter.counts
    except ProbeError as exc:
        result["failure_code"] = exc.code
        if "counter" in locals():
            counts = counter.counts
    except Exception:
        result["failure_code"] = "IncompleteEvidence"
        if "counter" in locals():
            counts = counter.counts
    result["adb_command_counts"] = counts
    result["adb_command_total"] = sum(counts.values())
    finished = clock()
    result["duration_seconds"] = max(0.0, finished - started)
    try:
        result["finished_at_utc"] = _timestamp(utc_clock)
    except ProbeError:
        result["finished_at_utc"] = None
        if result["classification"] == "cleanup_complete":
            result["classification"] = "cleanup_verified_unrecorded"
            result["failure_code"] = "IncompleteEvidence"
    try:
        _write_private_outcome(outcomes_directory, result)
    except ProbeError as exc:
        result["outcome_written"] = False
        if result["classification"] == "cleanup_complete":
            result["classification"] = "cleanup_verified_unrecorded"
            result["failure_code"] = exc.code
    else:
        result["outcome_written"] = True
    return result
