"""Recover cleanup of a pinned Readiness install after its host process exits."""

from __future__ import annotations

import hashlib
import json
import os
import re
import secrets
import stat
import time
from collections.abc import Mapping
from datetime import datetime, timezone
from pathlib import Path

from . import _evidence_storage
from . import adb_forward
from . import readiness_probe_install_journal
from . import q7_exploratory_acquisition as q7
from .readiness_probe import ProbeError


_LEGACY_INSTALL_RECORD_SCHEMA = adb_forward._READINESS_INSTALL_RECORD_V1_SCHEMA
_INSTALL_RECORD_SCHEMA = adb_forward._READINESS_INSTALL_RECORD_V2_SCHEMA
_LEGACY_OUTCOME_SCHEMA = "argus-issue-74-b1-cleanup-recovery-v1"
_OUTCOME_SCHEMA = "argus-issue-74-b1-cleanup-recovery-v2"
_INSTALL_JOURNAL_SCHEMA = (
    readiness_probe_install_journal.INSTALL_JOURNAL_SCHEMA
)
_COMMAND_CATEGORIES = (
    "get_state",
    "fingerprint",
    "current_user",
    "android_users",
    "package_state",
    "install_sessions",
    "install_create",
    "install_write",
    "install_commit",
    "install_abandon",
    "package_path",
    "installed_apk_readback",
    "package_uninstall",
)
_MAX_JSON_RECORD_BYTES = 1024 * 1024
_CLEANUP_ATTEMPT_ID_PATTERN = re.compile(r"[0-9a-f]{32}\Z")
_INSTALL_ATTEMPT_ID_PATTERN = re.compile(r"[0-9a-f]{32}\Z")
_INSTALL_RECORD_SHA256_PATTERN = re.compile(r"[0-9a-f]{64}\Z")


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
    journal_digest = value.get("install_journal_sha256")
    if journal_digest is not None and (
        type(journal_digest) is not str
        or len(journal_digest) != 64
        or any(character not in "0123456789abcdef" for character in journal_digest)
    ):
        return False
    return True


def _stat_private_entry(directory_fd, name):
    """Read entry metadata without following a symbolic link."""
    return os.stat(name, dir_fd=directory_fd, follow_symlinks=False)


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
    install_attempt_id = record.get("install_attempt_id")
    if record.get("schema") == _INSTALL_JOURNAL_SCHEMA:
        state = record.get("state")
        phase = record.get("phase")
        expected_status = {
            "pending": "pending",
            "attempted": "attempted",
            "completed": "installed",
            "cleaned_up": "cleaned_up",
        }.get(state)
        session_id = record.get("remote_session_id")
        package_uid = record.get("package_uid_private")
        installed_sha256 = record.get("installed_apk_sha256")
        baseline_ids = record.get("baseline_package_session_ids")
        return (
            isinstance(install_attempt_id, str)
            and _INSTALL_ATTEMPT_ID_PATTERN.fullmatch(install_attempt_id) is not None
            and record.get("target_reference") == target_reference
            and record.get("identity_preflight_record_bound") is True
            and record.get("identity_match") is True
            and record.get("qualification_assertions_passed") is False
            and record.get("package_baseline_absent") is True
            and record.get("install_status") == expected_status
            and _parse_utc_timestamp(record.get("acquired_at_utc")) is not None
            and adb_forward._valid_target(serial)
            and type(fingerprint) is str
            and adb_forward._BUILD_PATTERN.fullmatch(fingerprint) is not None
            and artifact.get("package") == adb_forward._READINESS_PROBE_PACKAGE
            and artifact.get("sha256") == adb_forward._READINESS_PROBE_APK_SHA256
            and type(artifact.get("version_code")) is int
            and artifact.get("version_code") == adb_forward._READINESS_PROBE_VERSION_CODE
            and type(artifact.get("size_bytes")) is int
            and 0 < artifact.get("size_bytes") <= adb_forward._MAX_READINESS_PROBE_APK_BYTES
            and type(user_id) is int
            and 0 <= user_id <= (1 << 31) - 1
            and type(record.get("event_sequence")) is int
            and record.get("event_sequence") > 0
            and re.fullmatch(r"[0-9a-f]{64}", record.get("event_sha256", "")) is not None
            and isinstance(baseline_ids, list)
            and all(type(item) is int and 0 < item <= (1 << 31) - 1 for item in baseline_ids)
            and baseline_ids == sorted(set(baseline_ids))
            and (
                session_id is None
                or (type(session_id) is int and 0 < session_id <= (1 << 31) - 1)
            )
            and (
                package_uid is None
                or (type(package_uid) is int and 0 < package_uid <= (1 << 31) - 1)
            )
            and (
                installed_sha256 is None
                or re.fullmatch(r"[0-9a-f]{64}", installed_sha256) is not None
            )
            and (
                (state == "pending" and phase == "before_install")
                or (state == "attempted" and phase in {
                    "create_started", "session_created", "write_started",
                    "payload_written", "commit_started", "abandon_started",
                    "cleanup_started",
                })
                or (state == "completed" and phase == "installed")
                or (state == "cleaned_up" and phase in {
                    "verified_absent", "session_abandoned", "package_uninstalled",
                })
            )
        )
    install_identity_valid = (
        record.get("schema") == _LEGACY_INSTALL_RECORD_SCHEMA
        and "install_attempt_id" not in record
    ) or (
        record.get("schema") == _INSTALL_RECORD_SCHEMA
        and isinstance(install_attempt_id, str)
        and _INSTALL_ATTEMPT_ID_PATTERN.fullmatch(install_attempt_id) is not None
    )
    return (
        install_identity_valid
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


def _legacy_install_identity(record, target_reference):
    """Return stable ownership facts used to detect duplicate legacy records."""
    if not _valid_install_record(record, target_reference):
        return None
    identity = record["identity_private"]
    artifact = record["artifact"]
    return (
        record["target_reference"],
        identity["serial"],
        identity["build_fingerprint"],
        record["android_user_private"],
        record["package_uid_private"],
        artifact["package"],
        artifact["sha256"],
        artifact["version_code"],
    )


def _read_install_record(outcomes_directory, target_reference, *, allow_no_active=False):
    """Select one active install through explicit attempt and cleanup lineage.

    V2 install records carry a unique attempt ID, and v2 cleanup outcomes bind
    that ID to the exact install-record bytes. Legacy records lack that ID, so
    repeated ownership facts remain ambiguous even when one copy has cleanup.
    Earlier cleanup outcomes have no lineage and cannot establish ownership.
    """
    directory = Path(outcomes_directory)
    try:
        directory_fd = _evidence_storage._directory_descriptor(directory)
    except Exception:
        raise ProbeError("UnauthorizedPeer", "Transport") from None
    candidates = []
    cleanup_outcomes = []
    cleanup_attempt_ids = set()
    try:
        names = os.listdir(directory_fd)
        if len(names) > 256:
            raise ProbeError("ResourceLimitExceeded", "Transport")
        for name in names:
            try:
                metadata = _stat_private_entry(directory_fd, name)
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
                    _LEGACY_INSTALL_RECORD_SCHEMA.encode("ascii"),
                    _INSTALL_RECORD_SCHEMA.encode("ascii"),
                    _INSTALL_JOURNAL_SCHEMA.encode("ascii"),
                    _LEGACY_OUTCOME_SCHEMA.encode("ascii"),
                    _OUTCOME_SCHEMA.encode("ascii"),
                )
                if any(marker in raw for marker in known_schema_markers):
                    raise ProbeError("IncompleteEvidence", "Transport") from None
                continue
            if (
                isinstance(record, Mapping)
                and record.get("schema")
                in {_LEGACY_INSTALL_RECORD_SCHEMA, _INSTALL_RECORD_SCHEMA}
                and record.get("target_reference") == target_reference
            ):
                install_attempt_id = (
                    record.get("install_attempt_id")
                    if record.get("schema") == _INSTALL_RECORD_SCHEMA
                    else None
                )
                candidates.append(
                    (record, hashlib.sha256(raw).hexdigest(), install_attempt_id)
                )
            elif (
                isinstance(record, Mapping)
                and record.get("schema")
                in {_LEGACY_OUTCOME_SCHEMA, _OUTCOME_SCHEMA}
            ):
                if record.get("schema") == _OUTCOME_SCHEMA:
                    cleanup_attempt_id = record.get("cleanup_attempt_id")
                    if isinstance(cleanup_attempt_id, str) and (
                        _CLEANUP_ATTEMPT_ID_PATTERN.fullmatch(cleanup_attempt_id)
                        is not None
                    ):
                        if cleanup_attempt_id in cleanup_attempt_ids:
                            raise ProbeError("IntegrityConflict", "Transport")
                        cleanup_attempt_ids.add(cleanup_attempt_id)
                    elif record.get("target_reference") == target_reference:
                        raise ProbeError("IncompleteEvidence", "Transport")
                if record.get("target_reference") == target_reference:
                    cleanup_outcomes.append(record)
    except ProbeError:
        raise
    except Exception:
        raise ProbeError("IncompleteEvidence", "Transport") from None
    finally:
        os.close(directory_fd)

    journal_attempts = readiness_probe_install_journal.read_install_journal_events(
        directory, target_reference=target_reference
    )
    for attempt_id, events in journal_attempts.items():
        if any(not _valid_install_record(event, target_reference) for event in events):
            raise ProbeError("IncompleteEvidence", "Transport")
        latest = events[-1]
        if latest.get("state") == "cleaned_up":
            continue
        latest_name = (
            f"readiness-install-attempt-{attempt_id}-"
            f"{latest['event_sequence']:04d}.json"
        )
        try:
            latest_raw = _evidence_storage._read_private_file(directory, latest_name)
        except Exception:
            raise ProbeError("UnauthorizedPeer", "Transport") from None
        candidates.append(
            (latest, hashlib.sha256(latest_raw).hexdigest(), attempt_id)
        )

    candidate_digests = [record_digest for _, record_digest, _ in candidates]
    if len(candidate_digests) != len(set(candidate_digests)):
        raise ProbeError("IntegrityConflict", "Transport")

    install_attempt_ids = [
        install_attempt_id
        for record, _, install_attempt_id in candidates
        if record.get("schema") == _INSTALL_RECORD_SCHEMA
    ]
    if any(
        not isinstance(install_attempt_id, str)
        or not _INSTALL_ATTEMPT_ID_PATTERN.fullmatch(install_attempt_id)
        for install_attempt_id in install_attempt_ids
    ):
        raise ProbeError("IncompleteEvidence", "Transport")
    if len(install_attempt_ids) != len(set(install_attempt_ids)):
        raise ProbeError("IntegrityConflict", "Transport")

    legacy_install_identities = []
    for record, _, _ in candidates:
        if record.get("schema") != _LEGACY_INSTALL_RECORD_SCHEMA:
            continue
        identity = _legacy_install_identity(record, target_reference)
        if identity is None:
            continue
        if identity in legacy_install_identities:
            raise ProbeError("IntegrityConflict", "Transport")
        legacy_install_identities.append(identity)

    successful_cleanups = {}
    for outcome in cleanup_outcomes:
        outcome_schema = outcome.get("schema")
        install_record_sha256 = outcome.get("install_record_sha256")
        install_attempt_id = outcome.get("install_attempt_id")
        if outcome_schema == _OUTCOME_SCHEMA:
            cleanup_attempt_id = outcome.get("cleanup_attempt_id")
            if (
                not isinstance(cleanup_attempt_id, str)
                or not _CLEANUP_ATTEMPT_ID_PATTERN.fullmatch(cleanup_attempt_id)
            ):
                raise ProbeError("IncompleteEvidence", "Transport")
            if "install_attempt_id" not in outcome:
                raise ProbeError("IncompleteEvidence", "Transport")
            if install_attempt_id is not None and (
                not isinstance(install_attempt_id, str)
                or not _INSTALL_ATTEMPT_ID_PATTERN.fullmatch(install_attempt_id)
            ):
                raise ProbeError("IncompleteEvidence", "Transport")
            if install_record_sha256 is not None and (
                not isinstance(install_record_sha256, str)
                or not _INSTALL_RECORD_SHA256_PATTERN.fullmatch(
                    install_record_sha256
                )
            ):
                raise ProbeError("IncompleteEvidence", "Transport")

        if outcome.get("classification") != "cleanup_complete":
            continue
        if (
            _parse_utc_timestamp(outcome.get("finished_at_utc")) is None
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
        if outcome_schema != _OUTCOME_SCHEMA:
            continue
        if (
            not isinstance(install_record_sha256, str)
            or not _INSTALL_RECORD_SHA256_PATTERN.fullmatch(install_record_sha256)
        ):
            raise ProbeError("IncompleteEvidence", "Transport")
        successful_cleanups.setdefault(
            (install_record_sha256, install_attempt_id), []
        ).append(outcome)

    if any(len(matches) > 1 for matches in successful_cleanups.values()):
        raise ProbeError("IntegrityConflict", "Transport")

    candidate_ids_by_digest = {
        record_digest: install_attempt_id
        for _, record_digest, install_attempt_id in candidates
    }
    candidate_digests_by_id = {
        install_attempt_id: record_digest
        for _, record_digest, install_attempt_id in candidates
        if install_attempt_id is not None
    }
    for record_digest, install_attempt_id in successful_cleanups:
        if (
            record_digest in candidate_ids_by_digest
            and candidate_ids_by_digest[record_digest] != install_attempt_id
        ):
            raise ProbeError("IntegrityConflict", "Transport")
        if (
            install_attempt_id in candidate_digests_by_id
            and candidate_digests_by_id[install_attempt_id] != record_digest
        ):
            raise ProbeError("IntegrityConflict", "Transport")

    unresolved_candidates = []
    unresolved_identities = []
    for record, record_digest, install_attempt_id in candidates:
        if (record_digest, install_attempt_id) in successful_cleanups:
            continue
        if "acquired_at_utc" in record and _parse_utc_timestamp(
            record.get("acquired_at_utc")
        ) is None:
            raise ProbeError("IncompleteEvidence", "Transport")
        unresolved_candidates.append(record)
        unresolved_identities.append((record_digest, install_attempt_id))
    if not unresolved_candidates and allow_no_active:
        return None
    if len(unresolved_candidates) != 1 or not _valid_install_record(
        unresolved_candidates[0], target_reference
    ):
        raise ProbeError("IntegrityConflict", "Transport")
    return unresolved_candidates[0], *unresolved_identities[0]


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
        if command == ("shell", "pm", "list", "users"):
            return "android_users"
        if command[:4] == ("shell", "pm", "list", "packages"):
            return "package_state"
        if command == adb_forward._INSTALL_SESSIONS_COMMAND:
            return "install_sessions"
        if command[:3] == ("shell", "pm", "install-create"):
            return "install_create"
        if command[:3] == ("shell", "pm", "install-write"):
            return "install_write"
        if command[:3] == ("shell", "pm", "install-commit"):
            return "install_commit"
        if command[:3] == ("shell", "pm", "install-abandon"):
            return "install_abandon"
        if command == ("shell", "pm", "path", adb_forward._READINESS_PROBE_PACKAGE):
            return "package_path"
        if command[:2] == ("exec-out", "cat"):
            return "installed_apk_readback"
        if command[:3] == ("shell", "pm", "uninstall"):
            return "package_uninstall"
        return None

    def run(self, argv, deadline, *, input_fd=None, input_size=None):
        category = self._category(argv)
        if category is None:
            raise ProbeError("MalformedRequest", "Transport")
        self.counts[category] += 1
        if input_fd is None:
            return self._runner.run(argv, deadline)
        return self._runner.run(
            argv, deadline, input_fd=input_fd, input_size=input_size
        )

    def run_install_sessions(self, target, stdout_consumer, *, deadline):
        self.counts["install_sessions"] += 1
        return self._runner.run_install_sessions(target, stdout_consumer, deadline=deadline)

    def run_bounded_stream(
        self, argv, deadline, *, output_limit, stdout_consumer, line_limit=None
    ):
        category = self._category(argv)
        if category is None:
            raise ProbeError("MalformedRequest", "Transport")
        self.counts[category] += 1
        stream = getattr(self._runner, "run_bounded_stream", None)
        if callable(stream):
            return stream(
                argv,
                deadline,
                output_limit=output_limit,
                stdout_consumer=stdout_consumer,
                line_limit=line_limit,
            )
        output = self._runner.run(argv, deadline)
        if len(output) > output_limit:
            raise ProbeError("ResourceLimitExceeded", "Transport")
        stdout_consumer(output)
        return {
            "stdout_bytes": len(output),
            "total_output_bytes": len(output),
            "exit_code": 0,
        }


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
    """Verify an install and privately bind its cleanup result to that record."""
    started = clock()
    started_at = _timestamp(utc_clock)
    counts = {name: 0 for name in _COMMAND_CATEGORIES}
    cleanup_attempt_id = secrets.token_hex(16)
    install_record_sha256 = None
    install_attempt_id = None
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
            "install_journal_sha256": _source_hash(
                readiness_probe_install_journal.__file__
            ),
        }
        record, install_record_sha256, install_attempt_id = _read_install_record(
            outcomes_directory, target_reference
        )
        install_journal = None
        if record.get("schema") == _INSTALL_JOURNAL_SCHEMA:
            attempts = readiness_probe_install_journal.read_install_journal_events(
                outcomes_directory,
                target_reference=target_reference,
                attempt_id=install_attempt_id,
            )
            events = attempts.get(install_attempt_id)
            if not events:
                raise ProbeError("IntegrityConflict", "Transport")
            latest = events[-1]
            latest_name = (
                f"readiness-install-attempt-{install_attempt_id}-"
                f"{latest['event_sequence']:04d}.json"
            )
            latest_raw = _evidence_storage._read_private_file(
                outcomes_directory, latest_name
            )
            if (
                hashlib.sha256(latest_raw).hexdigest() != install_record_sha256
                or latest.get("event_sha256") != record.get("event_sha256")
            ):
                raise ProbeError("IntegrityConflict", "Transport")
            install_journal = readiness_probe_install_journal.ReadinessInstallJournal.resume(
                outcomes_directory, events
            )
        target = record["identity_private"]["serial"]
        counter = _CommandCounter(
            runner if runner is not None else adb_forward._AdbCommandRunner(clock=clock)
        )
        adapter = adb_forward.AdbForwardAdapter(runner=counter, clock=clock)
        bound_identity = adapter.identity(target, deadline=started + deadline_seconds)
        if bound_identity[1] != record["identity_private"]["build_fingerprint"]:
            raise ProbeError("IntegrityConflict", "Transport")
        cleanup = adapter.recover_readiness_cleanup(
            target,
            record,
            deadline=started + deadline_seconds,
            install_journal=install_journal,
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
        private_record = {
            **result,
            "cleanup_attempt_id": cleanup_attempt_id,
            "install_attempt_id": install_attempt_id,
            "install_record_sha256": install_record_sha256,
        }
        _write_private_outcome(outcomes_directory, private_record)
    except ProbeError as exc:
        result["outcome_written"] = False
        if result["classification"] == "cleanup_complete":
            result["classification"] = "cleanup_verified_unrecorded"
            result["failure_code"] = exc.code
    else:
        result["outcome_written"] = True
    return result
