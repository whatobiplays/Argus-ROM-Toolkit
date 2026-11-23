"""Persist private, append-only ownership evidence for a Readiness install."""

from __future__ import annotations

import hashlib
import json
import os
import re
import secrets
import stat
from datetime import datetime, timezone
from pathlib import Path

from . import _evidence_storage
from .readiness_probe import ProbeError


INSTALL_JOURNAL_SCHEMA = "argus-issue-74-readiness-install-lifecycle-v1"
INSTALL_ATTEMPT_ID_PATTERN = re.compile(r"[0-9a-f]{32}\Z")
TARGET_REFERENCE_PATTERN = re.compile(r"i74-tgt-[0-9a-f]{16}\Z")
SESSION_HEADER_PATTERN = re.compile(rb"\s*(?:(Active|Finalized) )?Session ([0-9]+):\s*\Z")
SESSION_FIELD_PATTERN = re.compile(rb"\s*([A-Za-z0-9_.]+)=([^\s]*)\s*\Z")
_MAX_INSTALL_SESSIONS_OUTPUT_BYTES = 1024 * 1024
_MAX_INSTALL_SESSIONS_LINE_BYTES = 16 * 1024
_MAX_JOURNAL_BYTES = 64 * 1024
_MAX_SESSION_ID = (1 << 31) - 1

_IMMUTABLE_BINDING_FIELDS = (
    "target_reference",
    "identity_preflight_record_bound",
    "identity_match",
    "identity_private",
    "artifact",
    "android_user_private",
    "package_baseline_absent",
    "baseline_package_session_ids",
    "fresh_baseline_admission",
    "qualification_assertions_passed",
)

_ALLOWED_TRANSITIONS = {
    ("pending", "before_install"): {("attempted", "create_started"), ("cleaned_up", "verified_absent")},
    ("attempted", "create_started"): {
        ("attempted", "session_created"),
        ("cleaned_up", "verified_absent"),
    },
    ("attempted", "session_created"): {
        ("attempted", "write_started"),
        ("attempted", "precommit_abandon_started"),
        ("attempted", "abandon_started"),
        ("cleaned_up", "verified_absent"),
    },
    ("attempted", "write_started"): {
        ("attempted", "payload_written"),
        ("attempted", "precommit_abandon_started"),
        ("attempted", "abandon_started"),
        ("cleaned_up", "verified_absent"),
    },
    ("attempted", "payload_written"): {
        ("attempted", "commit_started"),
        ("attempted", "precommit_abandon_started"),
        ("attempted", "abandon_started"),
        ("cleaned_up", "verified_absent"),
    },
    ("attempted", "commit_started"): {
        ("completed", "installed"),
        ("attempted", "abandon_started"),
        ("attempted", "cleanup_started"),
        ("cleaned_up", "verified_absent"),
    },
    ("completed", "installed"): {
        ("attempted", "cleanup_started"),
        ("attempted", "abandon_started"),
        ("cleaned_up", "verified_absent"),
    },
    ("attempted", "abandon_started"): {
        ("attempted", "abandon_started"),
        ("completed", "installed"),
        ("cleaned_up", "session_abandoned"),
        ("cleaned_up", "verified_absent"),
    },
    ("attempted", "precommit_abandon_started"): {
        ("attempted", "precommit_abandon_started"),
        ("cleaned_up", "verified_absent"),
    },
    ("attempted", "cleanup_started"): {
        ("attempted", "cleanup_started"),
        ("cleaned_up", "package_uninstalled"),
        ("cleaned_up", "verified_absent"),
    },
}


def _canonical_json_bytes(value):
    return (json.dumps(value, allow_nan=False, sort_keys=True) + "\n").encode(
        "utf-8"
    )


def _utc_timestamp(utc_clock):
    value = utc_clock()
    if not isinstance(value, datetime) or value.tzinfo is None:
        raise ProbeError("IncompleteEvidence", "Transport")
    return value.astimezone(timezone.utc).isoformat(timespec="seconds").replace(
        "+00:00", "Z"
    )


def _valid_baseline_ids(value):
    return (
        isinstance(value, (tuple, list))
        and all(
            type(item) is int and 0 < item <= _MAX_SESSION_ID for item in value
        )
        and len(value) == len(set(value))
        and list(value) == sorted(value)
    )


def _reject_duplicate_json_keys(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            raise ValueError("duplicate key")
        value[key] = item
    return value


def validate_event_chain(events):
    """Verify sequence, immutable binding, transitions and each event digest."""
    if not events:
        raise ProbeError("IntegrityConflict", "Transport")
    ordered = sorted(events, key=lambda item: item.get("event_sequence", -1))
    previous = None
    for sequence, event in enumerate(ordered, start=1):
        if (
            not isinstance(event, dict)
            or event.get("schema") != INSTALL_JOURNAL_SCHEMA
            or event.get("event_sequence") != sequence
            or type(event.get("install_attempt_id")) is not str
            or INSTALL_ATTEMPT_ID_PATTERN.fullmatch(event["install_attempt_id"]) is None
            or re.fullmatch(r"[0-9a-f]{64}", event.get("event_sha256", "")) is None
        ):
            raise ProbeError("IncompleteEvidence", "Transport")
        content = dict(event)
        recorded_sha256 = content.pop("event_sha256")
        if hashlib.sha256(_canonical_json_bytes(content)).hexdigest() != recorded_sha256:
            raise ProbeError("IntegrityConflict", "Transport")
        if previous is None:
            if (
                event.get("state") != "pending"
                or event.get("phase") != "before_install"
                or event.get("previous_event_sha256") is not None
                or event.get("previous_state") is not None
                or event.get("previous_phase") is not None
                or any(
                    key in event
                    for key in (
                        "remote_session_id",
                        "package_uid_private",
                        "installed_apk_sha256",
                    )
                )
            ):
                raise ProbeError("IntegrityConflict", "Transport")
        else:
            if (
                event.get("install_attempt_id") != previous["install_attempt_id"]
                or event.get("previous_event_sha256") != previous["event_sha256"]
                or event.get("previous_state") != previous["state"]
                or event.get("previous_phase") != previous["phase"]
                or any(event.get(key) != previous.get(key) for key in _IMMUTABLE_BINDING_FIELDS)
                or (event.get("state"), event.get("phase"))
                not in _ALLOWED_TRANSITIONS.get(
                    (previous["state"], previous["phase"]), set()
                )
            ):
                raise ProbeError("IntegrityConflict", "Transport")
            _validate_identity_continuity(previous, event)
        _validate_identity_fields(event)
        if not _valid_baseline_ids(event.get("baseline_package_session_ids")):
            raise ProbeError("IncompleteEvidence", "Transport")
        previous = event
    return tuple(ordered)


def _validate_identity_fields(event):
    """Require install identities only after their durable observation point."""
    if "fresh_baseline_admission" in event and event["fresh_baseline_admission"] is not True:
        raise ProbeError("IntegrityConflict", "Transport")
    if any(
        field in event and event[field] is None
        for field in (
            "remote_session_id",
            "package_uid_private",
            "installed_apk_sha256",
        )
    ):
        raise ProbeError("IntegrityConflict", "Transport")
    session_id = event.get("remote_session_id")
    if session_id is not None and (
        type(session_id) is not int or not 0 < session_id <= _MAX_SESSION_ID
    ):
        raise ProbeError("IntegrityConflict", "Transport")
    package_uid = event.get("package_uid_private")
    installed_sha256 = event.get("installed_apk_sha256")
    if package_uid is not None and (
        type(package_uid) is not int or not 0 < package_uid <= _MAX_SESSION_ID
    ):
        raise ProbeError("IntegrityConflict", "Transport")
    if installed_sha256 is not None and re.fullmatch(
        r"[0-9a-f]{64}", installed_sha256
    ) is None:
        raise ProbeError("IntegrityConflict", "Transport")
    if (package_uid is None) != (installed_sha256 is None):
        raise ProbeError("IntegrityConflict", "Transport")

    state = event.get("state")
    phase = event.get("phase")
    session_required = (
        (state, phase)
        in {
            ("attempted", "session_created"),
            ("attempted", "write_started"),
            ("attempted", "payload_written"),
            ("attempted", "commit_started"),
            ("attempted", "abandon_started"),
            ("attempted", "precommit_abandon_started"),
            ("attempted", "cleanup_started"),
            ("completed", "installed"),
            ("cleaned_up", "session_abandoned"),
            ("cleaned_up", "package_uninstalled"),
        }
    )
    if session_required and session_id is None:
        raise ProbeError("IntegrityConflict", "Transport")

    package_identity_required = (state, phase) in {
        ("completed", "installed"),
        ("attempted", "cleanup_started"),
        ("cleaned_up", "package_uninstalled"),
    }
    if package_identity_required and package_uid is None:
        raise ProbeError("IntegrityConflict", "Transport")


def _validate_identity_continuity(previous, event):
    """Prevent later journal events from dropping or replacing observed IDs."""
    for field in (
        "remote_session_id",
        "package_uid_private",
        "installed_apk_sha256",
    ):
        prior_value = previous.get(field)
        current_value = event.get(field)
        if prior_value is not None and current_value != prior_value:
            raise ProbeError("IntegrityConflict", "Transport")
        if prior_value is None and current_value is not None:
            first_observation = (
                field == "remote_session_id"
                and event.get("state") == "attempted"
                and event.get("phase") == "session_created"
            ) or (
                field in {"package_uid_private", "installed_apk_sha256"}
                and event.get("state") == "completed"
                and event.get("phase") == "installed"
            )
            if not first_observation:
                raise ProbeError("IntegrityConflict", "Transport")


def read_install_journal_events(
    outcomes_directory, *, target_reference, attempt_id=None
):
    """Read owner-private journal files and validate each complete attempt."""
    directory = Path(outcomes_directory)
    try:
        directory_fd = _evidence_storage._directory_descriptor(directory)
    except Exception:
        raise ProbeError("UnauthorizedPeer", "Transport") from None
    grouped = {}
    try:
        names = os.listdir(directory_fd)
        if len(names) > 256:
            raise ProbeError("ResourceLimitExceeded", "Transport")
        for name in names:
            if not name.startswith("readiness-install-attempt-"):
                continue
            match = re.fullmatch(
                r"readiness-install-attempt-([0-9a-f]{32})-([0-9]{4})[.]json",
                name,
            )
            if match is None:
                raise ProbeError("IncompleteEvidence", "Transport")
            if attempt_id is not None and match.group(1) != attempt_id:
                continue
            metadata = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
            if stat.S_ISLNK(metadata.st_mode):
                raise ProbeError("UnauthorizedPeer", "Transport")
            if (
                not stat.S_ISREG(metadata.st_mode)
                or metadata.st_uid != os.geteuid()
                or stat.S_IMODE(metadata.st_mode) != 0o600
                or metadata.st_nlink != 1
                or metadata.st_size < 0
                or metadata.st_size > _MAX_JOURNAL_BYTES
            ):
                raise ProbeError("UnauthorizedPeer", "Transport")
            raw = _evidence_storage._read_private_file(directory, name)
            try:
                event = json.loads(
                    raw.decode("utf-8", errors="strict"),
                    object_pairs_hook=_reject_duplicate_json_keys,
                    parse_constant=lambda _value: (_ for _ in ()).throw(ValueError()),
                )
            except Exception:
                raise ProbeError("IncompleteEvidence", "Transport") from None
            if (
                not isinstance(event, dict)
                or event.get("schema") != INSTALL_JOURNAL_SCHEMA
                or event.get("install_attempt_id") != match.group(1)
                or event.get("event_sequence") != int(match.group(2))
            ):
                raise ProbeError("IntegrityConflict", "Transport")
            if event.get("target_reference") != target_reference:
                raise ProbeError("IntegrityConflict", "Transport")
            grouped.setdefault(match.group(1), []).append(event)
    except ProbeError:
        raise
    except Exception:
        raise ProbeError("IncompleteEvidence", "Transport") from None
    finally:
        os.close(directory_fd)
    return {
        identity: validate_event_chain(events)
        for identity, events in grouped.items()
    }


class ReadinessInstallJournal:
    """Append fsynced private events before and after each install boundary.

    Every event repeats the device, build, Android user and approved artifact
    binding. Event files are created with exclusive names and linked by the
    digest of the previous event, so recovery never rewrites history.
    """

    def __init__(
        self,
        outcomes_directory,
        *,
        target_reference,
        serial,
        build_fingerprint,
        android_user_id,
        package,
        artifact_sha256,
        version_code,
        artifact_size,
        baseline_session_ids,
        attempt_id=None,
        fresh_baseline_admission=False,
        utc_clock=lambda: datetime.now(timezone.utc),
    ):
        if attempt_id is None:
            attempt_id = secrets.token_hex(16)
        if (
            type(attempt_id) is not str
            or INSTALL_ATTEMPT_ID_PATTERN.fullmatch(attempt_id) is None
            or type(target_reference) is not str
            or TARGET_REFERENCE_PATTERN.fullmatch(target_reference) is None
            or type(serial) is not str
            or not serial
            or len(serial) > 128
            or type(build_fingerprint) is not str
            or not build_fingerprint
            or len(build_fingerprint) > 256
            or type(android_user_id) is not int
            or not 0 <= android_user_id <= _MAX_SESSION_ID
            or type(package) is not str
            or not re.fullmatch(r"[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+", package)
            or type(artifact_sha256) is not str
            or re.fullmatch(r"[0-9a-f]{64}", artifact_sha256) is None
            or type(version_code) is not int
            or version_code <= 0
            or type(artifact_size) is not int
            or not 0 < artifact_size <= 32 * 1024 * 1024
            or type(fresh_baseline_admission) is not bool
            or not _valid_baseline_ids(baseline_session_ids)
        ):
            raise ProbeError("MalformedRequest", "Transport")
        self._directory = Path(outcomes_directory)
        self._utc_clock = utc_clock
        self.attempt_id = attempt_id
        self.latest = None
        self.latest_filename = None
        self.latest_sha256 = None
        self._append(
            {
                "schema": INSTALL_JOURNAL_SCHEMA,
                "install_attempt_id": attempt_id,
                "target_reference": target_reference,
                "identity_preflight_record_bound": True,
                "identity_match": True,
                "identity_private": {
                    "serial": serial,
                    "build_fingerprint": build_fingerprint,
                },
                "artifact": {
                    "package": package,
                    "sha256": artifact_sha256,
                    "version_code": version_code,
                    "size_bytes": artifact_size,
                },
                "android_user_private": android_user_id,
                "package_baseline_absent": True,
                "baseline_package_session_ids": list(baseline_session_ids),
                **({"fresh_baseline_admission": True} if fresh_baseline_admission else {}),
                "qualification_assertions_passed": False,
                "install_status": "pending",
                "state": "pending",
                "phase": "before_install",
            },
        )

    @property
    def outcomes_directory(self):
        return self._directory

    @classmethod
    def resume(cls, outcomes_directory, events, *, utc_clock=lambda: datetime.now(timezone.utc)):
        """Continue one already validated event chain without replacing it."""
        if not events:
            raise ProbeError("IntegrityConflict", "Transport")
        instance = cls.__new__(cls)
        instance._directory = Path(outcomes_directory)
        instance._utc_clock = utc_clock
        instance.attempt_id = events[-1]["install_attempt_id"]
        instance.latest = dict(events[-1])
        instance.latest_filename = (
            f"readiness-install-attempt-{instance.attempt_id}-"
            f"{instance.latest['event_sequence']:04d}.json"
        )
        instance.latest_sha256 = instance.latest["event_sha256"]
        return instance

    def checkpoint(
        self,
        state,
        phase,
        *,
        remote_session_id=None,
        package_uid_private=None,
        installed_apk_sha256=None,
    ):
        current = (self.latest["state"], self.latest["phase"])
        next_state = (state, phase)
        if next_state not in _ALLOWED_TRANSITIONS.get(current, set()):
            raise ProbeError("IntegrityConflict", "Transport")
        prior_session_id = self.latest.get("remote_session_id")
        if remote_session_id is not None and (
            type(remote_session_id) is not int
            or not 0 < remote_session_id <= _MAX_SESSION_ID
            or (prior_session_id is not None and prior_session_id != remote_session_id)
        ):
            raise ProbeError("IntegrityConflict", "Transport")
        if package_uid_private is not None and (
            type(package_uid_private) is not int
            or not 0 < package_uid_private <= _MAX_SESSION_ID
        ):
            raise ProbeError("IntegrityConflict", "Transport")
        if installed_apk_sha256 is not None and re.fullmatch(
            r"[0-9a-f]{64}", installed_apk_sha256
        ) is None:
            raise ProbeError("IntegrityConflict", "Transport")
        record = {
            key: value
            for key, value in self.latest.items()
            if key not in {"event_sequence", "previous_event_sha256", "event_sha256", "acquired_at_utc"}
        }
        record["event_sequence"] = self.latest["event_sequence"] + 1
        record["previous_event_sha256"] = self.latest_sha256
        record["previous_state"] = self.latest["state"]
        record["previous_phase"] = self.latest["phase"]
        record["state"] = state
        record["phase"] = phase
        record["install_status"] = {
            "pending": "pending",
            "attempted": "attempted",
            "completed": "installed",
            "cleaned_up": "cleaned_up",
        }[state]
        if remote_session_id is not None:
            record["remote_session_id"] = remote_session_id
        if package_uid_private is not None:
            record["package_uid_private"] = package_uid_private
        if installed_apk_sha256 is not None:
            record["installed_apk_sha256"] = installed_apk_sha256
        _validate_identity_fields(record)
        _validate_identity_continuity(self.latest, record)
        self._append(record)
        return self.latest

    def _append(self, record):
        sequence = 1 if self.latest is None else self.latest["event_sequence"] + 1
        record = dict(record)
        record["event_sequence"] = sequence
        record["previous_event_sha256"] = self.latest_sha256
        record.setdefault("previous_state", None)
        record.setdefault("previous_phase", None)
        record["acquired_at_utc"] = _utc_timestamp(self._utc_clock)
        digest = hashlib.sha256(_canonical_json_bytes(record)).hexdigest()
        record["event_sha256"] = digest
        payload = _canonical_json_bytes(record)
        if len(payload) > _MAX_JOURNAL_BYTES:
            raise ProbeError("ResourceLimitExceeded", "Transport")
        name = f"readiness-install-attempt-{self.attempt_id}-{sequence:04d}.json"
        try:
            directory_fd = _evidence_storage._directory_descriptor(self._directory)
        except Exception:
            raise ProbeError("UnauthorizedPeer", "Transport") from None
        temporary_name = f".readiness-event-{secrets.token_hex(16)}.tmp"
        previous_umask = os.umask(0o077)
        try:
            _evidence_storage._publish_no_replace(
                self._directory, temporary_name, name, payload
            )
        except Exception:
            raise ProbeError("IncompleteEvidence", "Transport") from None
        finally:
            try:
                os.unlink(temporary_name, dir_fd=directory_fd)
            except FileNotFoundError:
                pass
            finally:
                os.umask(previous_umask)
                os.close(directory_fd)
        self.latest = record
        self.latest_filename = name
        self.latest_sha256 = digest


class InstallSessionParser:
    """Keep only complete PackageInstaller records for the selected package."""

    _FIELD_NAMES = {
        b"userId": "user_id",
        b"installerPackageName": "installer_package",
        b"mInstallerUid": "installer_uid",
        b"appPackageName": "package",
        b"mCommitted": "committed",
        b"mFinalStatus": "final_status",
    }
    _SECTION_NAMES = {
        b"Active install sessions:": "active",
        b"Finalized install sessions:": "finalized",
        b"Historical install sessions:": "historical",
        b"Legacy install sessions:": "legacy",
    }
    _WRAPPED_WIDTH = 120
    _WRAPPED_ROWS = (
        (b"userId", b"installerPackageName", b"mInstallerUid", b"stageCid"),
        (b"mode", b"appPackageName", b"installerPackageName", b"rollbackDataPolicy"),
        (b"mClientProgress", b"mCommitted", b"mFinalStatus", b"mStagedSessionErrorMessage"),
    )
    _ROW_PAIR = re.compile(rb"(?:^| )([A-Za-z][A-Za-z0-9_.]*)=([^ ]*)")
    _WRAPPED_BINDING_SUFFIXES = {
        b"userId": b" mOriginalInstallerUid=",
        b"installerPackageName": b" installInitiatingPackageName=",
        b"mInstallerUid": b" createdMillis=",
        b"appPackageName": b" appIcon=",
        b"mCommitted": b" mSealed=",
        b"mFinalStatus": b" mFinalMessage=",
    }
    _ROLLBACK_FIXED_FIELDS = {
        b"mParentSessionId": b"-1",
        b"mChildSessionIds": b"[]",
        b"params.isMultiPackage": b"false",
        b"params.isStaged": b"false",
        b"mSealed": b"false",
    }
    _LIVE_PARAMS_FLAGS = {b"isMultiPackage": b"false", b"isStaged": b"false"}

    def __init__(self, package, *, expected_session_id=None, rollback_user_id=None):
        if type(package) is not str or not re.fullmatch(
            r"[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+", package
        ):
            raise ProbeError("MalformedRequest", "Transport")
        self._package = package
        self._expected_session_id = expected_session_id
        self._rollback_user_id = rollback_user_id
        self._buffer = bytearray()
        self._total = 0
        self._sections = []
        self._legacy_terminator = False
        self._current = None
        self._section = None
        self._records = []
        self._seen_ids = set()
        self._finished = False
        self._wrapped_row = bytearray()
        self._wrapped_rows_seen = 0
        self.active_layout = None
        self._rollback_seen = set()
        self._rollback_grouped = False

    def feed(self, chunk):
        if self._finished or type(chunk) is not bytes:
            raise ProbeError("IncompleteEvidence", "Transport")
        self._total += len(chunk)
        if self._total > _MAX_INSTALL_SESSIONS_OUTPUT_BYTES:
            raise ProbeError("ResourceLimitExceeded", "Transport")
        self._buffer.extend(chunk)
        while True:
            newline = self._buffer.find(b"\n")
            if newline < 0:
                if len(self._buffer) > _MAX_INSTALL_SESSIONS_LINE_BYTES:
                    raise ProbeError("ResourceLimitExceeded", "Transport")
                return
            line = bytes(self._buffer[:newline])
            del self._buffer[: newline + 1]
            if len(line) > _MAX_INSTALL_SESSIONS_LINE_BYTES:
                raise ProbeError("ResourceLimitExceeded", "Transport")
            self._consume_line(line)

    def finish(self):
        if self._finished:
            raise ProbeError("IncompleteEvidence", "Transport")
        self._finished = True
        if (
            self._buffer
            or self._current is not None
            or tuple(self._sections) != tuple(self._SECTION_NAMES.values())
            or not self._legacy_terminator
        ):
            raise ProbeError("IncompleteEvidence", "Transport")
        return tuple(self._records)

    def _consume_line(self, line):
        stripped = line.strip()
        upper = stripped.upper()
        if b"DUMP TIMEOUT" in upper or upper.startswith(
            (b"ERROR", b"FAILURE", b"PERMISSION DENIAL", b"CAN'T FIND SERVICE")
        ):
            raise ProbeError("IncompleteEvidence", "Transport")
        if stripped.endswith(b"install sessions:"):
            self._finish_session()
            section = self._SECTION_NAMES.get(stripped)
            expected = tuple(self._SECTION_NAMES.values())
            index = len(self._sections)
            if index >= len(expected) or section != expected[index]:
                raise ProbeError("IncompleteEvidence", "Transport")
            self._sections.append(section)
            self._section = section
            return
        if self._section == "legacy":
            # The observed legacy map is empty. Unrecognized trailing content
            # may describe additional sessions, so it cannot prove absence.
            if not stripped:
                return
            if stripped != b"{}" or self._legacy_terminator:
                raise ProbeError("IncompleteEvidence", "Transport")
            self._legacy_terminator = True
            return
        header = SESSION_HEADER_PATTERN.fullmatch(line)
        if header is not None:
            self._finish_session()
            prefix, session_id_text = header.groups()
            if prefix and prefix.decode("ascii").lower() != self._section:
                raise ProbeError("IncompleteEvidence", "Transport")
            session_id = int(session_id_text)
            if not 0 < session_id <= _MAX_SESSION_ID or session_id in self._seen_ids:
                raise ProbeError("IntegrityConflict", "Transport")
            self._seen_ids.add(session_id)
            self._current = {"session_id": session_id, "section": self._section}
            return
        if re.match(rb"(?:[A-Za-z]+ )?(?:Child )?Session(?:\b|[0-9])", stripped, re.I):
            raise ProbeError("IncompleteEvidence", "Transport")
        if self._current is None:
            if stripped:
                raise ProbeError("IncompleteEvidence", "Transport")
            return
        if self._is_rollback_candidate(self._current):
            if stripped:
                self._consume_rollback_line(line)
            return
        historical = self._section == "historical"
        prefix = b"      " if historical else b"    "
        starts_row = any(line.startswith(prefix + row[0] + b"=") for row in self._WRAPPED_ROWS)
        if self._wrapped_rows_seen or self._wrapped_row or (
            starts_row and (
                historical or line.endswith(b" ") or SESSION_FIELD_PATTERN.fullmatch(line) is None
            )
        ):
            if stripped or self._wrapped_row:
                self._consume_wrapped_row(line)
            elif self._wrapped_rows_seen != len(self._WRAPPED_ROWS):
                raise ProbeError("IncompleteEvidence", "Transport")
            return
        field = SESSION_FIELD_PATTERN.fullmatch(line)
        if field is None:
            if stripped.startswith(tuple(key + b"=" for key in self._FIELD_NAMES)):
                raise ProbeError("IncompleteEvidence", "Transport")
            return
        self._record_field(*field.groups())

    def _consume_wrapped_row(self, line):
        """Reassemble one Android 12 field row and project its bindings."""
        index = self._wrapped_rows_seen
        if index >= len(self._WRAPPED_ROWS) or len(line) > self._WRAPPED_WIDTH:
            raise ProbeError("IncompleteEvidence", "Transport")
        expected = self._WRAPPED_ROWS[index]
        historical = self._section == "historical"
        prefix = (b"  " if self._wrapped_row else b"      ") if historical else b"    "
        if (
            not line.startswith(prefix)
            or (not self._wrapped_row and not line.startswith(prefix + expected[0] + b"="))
            or any(byte < 32 or byte > 126 for byte in line)
        ):
            raise ProbeError("IncompleteEvidence", "Transport")
        self._wrapped_row.extend(line[len(prefix):])
        if len(self._wrapped_row) > _MAX_INSTALL_SESSIONS_LINE_BYTES:
            raise ProbeError("ResourceLimitExceeded", "Transport")
        bindings = [
            match for match in self._ROW_PAIR.finditer(self._wrapped_row)
            if match[1] in self._FIELD_NAMES or match[1] in expected
        ]
        if historical:
            if len(line) == self._WRAPPED_WIDTH:
                return
        elif not bindings or bindings[-1][1] != expected[-1] or not line.endswith(b" "):
            # The live writer can move a whole printPair call to a new line.
            if len(line) < self._WRAPPED_WIDTH and not line.endswith(b" "):
                raise ProbeError("IncompleteEvidence", "Transport")
            return
        try:
            if (
                tuple(match[1] for match in bindings) != expected
                or bindings[0].start() != 0
                or self._wrapped_row[bindings[-1].end():] != b" "
            ):
                raise ProbeError("IncompleteEvidence", "Transport")
            if not historical and index in (1, 2):
                fixed = self._LIVE_PARAMS_FLAGS if index == 1 else self._ROLLBACK_FIXED_FIELDS
                pairs = tuple(self._ROW_PAIR.finditer(self._wrapped_row))
                if any([pair[2] for pair in pairs if pair[1] == key] != [value]
                       for key, value in fixed.items()):
                    raise ProbeError("IntegrityConflict", "Transport")
            for match in bindings:
                # The Params row repeats the requested installer. The actual
                # installer belongs to the session row alongside the UID.
                if index == 1 and match[1] == b"installerPackageName":
                    continue
                suffix = self._WRAPPED_BINDING_SUFFIXES.get(match[1])
                if suffix is not None and not self._wrapped_row.startswith(suffix, match.end()):
                    raise ProbeError("IncompleteEvidence", "Transport")
                self._record_field(*match.groups())
        finally:
            self._wrapped_row.clear()
        self._wrapped_rows_seen += 1

    def _is_rollback_candidate(self, record):
        return (
            self._rollback_user_id is not None
            and record["section"] == "active"
            and record["session_id"] == self._expected_session_id
        )

    def _consume_rollback_line(self, line):
        """Check the exact live record without deriving install authority."""
        if (
            self._current.get("rollback_terminal")
            or not line.startswith(b"    ")
            or len(line) > self._WRAPPED_WIDTH
            or any(byte < 32 or byte > 126 for byte in line)
        ):
            raise ProbeError("IncompleteEvidence", "Transport")
        stripped = line.lstrip(b" ")
        scalar_field = SESSION_FIELD_PATTERN.fullmatch(line)
        self._rollback_grouped |= scalar_field is None or len(line) == self._WRAPPED_WIDTH
        if re.search(rb"(?:^| )mStagedSessionErrorMessage=[^ ]* $", stripped):
            self._current["rollback_terminal"] = True
        for match in self._ROW_PAIR.finditer(stripped):
            key, value = match.groups()
            if key in self._ROLLBACK_FIXED_FIELDS:
                if value != self._ROLLBACK_FIXED_FIELDS[key]:
                    raise ProbeError("IntegrityConflict", "Transport")
                self._remember_rollback_field(key)
            if key in self._LIVE_PARAMS_FLAGS:
                if value != self._LIVE_PARAMS_FLAGS[key]:
                    raise ProbeError("IntegrityConflict", "Transport")
                self._remember_rollback_field(key)
            if key == b"mode":
                self._remember_rollback_field(key)
                self._current["rollback_params"] = True
            if key == b"installerPackageName":
                if self._current.get("rollback_params"):
                    self._remember_rollback_field(b"params.installerPackageName")
                else:
                    self._remember_rollback_field(key)
                    if value != b"com.android.shell":
                        raise ProbeError("IntegrityConflict", "Transport")
                    self._record_field(key, value)
            if key in {b"sessionId", b"mSessionId"}:
                self._remember_rollback_field(b"sessionId")
                if value != str(self._expected_session_id).encode("ascii"):
                    raise ProbeError("IntegrityConflict", "Transport")
            if key == b"mStagedSessionErrorMessage":
                self._remember_rollback_field(key)
            if key in {b"userId", b"appPackageName", b"mInstallerUid", b"mCommitted", b"mFinalStatus"}:
                self._record_field(key, value)
                if (
                    key == b"mFinalStatus" and not self._rollback_grouped
                    and scalar_field is not None
                ):
                    self._current["rollback_terminal"] = True

    def _remember_rollback_field(self, key):
        if key in self._rollback_seen:
            raise ProbeError("IntegrityConflict", "Transport")
        self._rollback_seen.add(key)

    def _record_field(self, key, value):
        mapped = self._FIELD_NAMES.get(key)
        if mapped is None:
            return
        if mapped == "package":
            if mapped in self._current:
                raise ProbeError("IntegrityConflict", "Transport")
            if value == b"null" and self._section == "historical":
                self._current[mapped] = None
                return
            try:
                decoded = value.decode("ascii")
            except UnicodeDecodeError:
                raise ProbeError("IncompleteEvidence", "Transport") from None
            if re.fullmatch(r"[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+", decoded) is None:
                raise ProbeError("IncompleteEvidence", "Transport")
            self._current["package"] = decoded
            return
        if mapped in self._current:
            raise ProbeError("IntegrityConflict", "Transport")
        if mapped == "installer_package":
            try:
                self._current[mapped] = value.decode("ascii")
            except UnicodeDecodeError:
                self._current[mapped] = ""
            return
        if mapped == "committed":
            if value not in (b"true", b"false"):
                self._current[mapped] = None
            else:
                self._current[mapped] = value == b"true"
            return
        if mapped in {"user_id", "installer_uid", "final_status"}:
            if not re.fullmatch(rb"-?[0-9]{1,11}", value):
                self._current[mapped] = None
            else:
                self._current[mapped] = int(value)

    def _finish_session(self):
        current = self._current
        self._current = None
        if current is None:
            return
        if self._is_rollback_candidate(current):
            if (
                not current.get("rollback_terminal")
                or not self._ROLLBACK_FIXED_FIELDS.keys() <= self._rollback_seen
                or (self._rollback_grouped and not self._LIVE_PARAMS_FLAGS.keys() <= self._rollback_seen)
                or current.get("user_id") != self._rollback_user_id
                or current.get("package") != self._package
                or current.get("installer_package") != "com.android.shell"
                or current.get("installer_uid") != 2000
                or current.get("committed") is not False
                or current.get("final_status") != 0
            ):
                raise ProbeError("IntegrityConflict", "Transport")
            self._records.append({
                "session_id": current["session_id"], "section": "active", "rollback_only": True,
            })
            return
        if self._wrapped_row or self._wrapped_rows_seen not in (0, len(self._WRAPPED_ROWS)):
            raise ProbeError("IncompleteEvidence", "Transport")
        wrapped = self._wrapped_rows_seen != 0
        self._wrapped_rows_seen = 0
        expected = current["session_id"] == self._expected_session_id
        package = current.get("package")
        if "package" not in current or (expected and package is None):
            raise ProbeError("IncompleteEvidence", "Transport")
        if expected and package != self._package:
            raise ProbeError("IntegrityConflict", "Transport")
        selected = package == self._package
        required = (
            "user_id",
            "installer_package",
            "installer_uid",
            "committed",
            "final_status",
        )
        if any(name not in current or current[name] is None for name in required):
            raise ProbeError("IncompleteEvidence", "Transport")
        if current.get("section") not in {"active", "finalized", "historical"}:
            raise ProbeError("IncompleteEvidence", "Transport")
        if (
            not 0 <= current["user_id"] <= _MAX_SESSION_ID
            or not 0 <= current["installer_uid"] <= _MAX_SESSION_ID
            or not -10000 <= current["final_status"] <= _MAX_SESSION_ID
            or not re.fullmatch(r"[A-Za-z0-9_.]+", current["installer_package"])
        ):
            raise ProbeError("IncompleteEvidence", "Transport")
        if selected:
            self._records.append(dict(current))
            if expected and current["section"] == "active":
                self.active_layout = "grouped_print_pairs" if wrapped else "scalar_fields"
        else:
            self._records.append({
                "session_id": current["session_id"],
                "section": current["section"],
                "package_binding": "unattributed" if package is None else "unrelated",
            })
        current.clear()


def parse_install_sessions(data, package, *, expected_session_id=None):
    """Parse a bounded dump and keep competing or unattributed sessions opaque."""
    parser = InstallSessionParser(package, expected_session_id=expected_session_id)
    parser.feed(data)
    return parser.finish()
