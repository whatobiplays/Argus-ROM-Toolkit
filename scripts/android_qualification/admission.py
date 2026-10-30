"""Public host-only validation and internal typed session controls.

admit_host_only validates only the version-1 structural manifest. The separate
admit_session API accepts injected observations; no public command supplies a
live transport or invokes the permission-operation adapter.
"""

from __future__ import annotations

import fcntl
import hashlib
import json
import os
import re
import secrets
import stat
import threading
import time
import weakref
from contextlib import contextmanager
from dataclasses import dataclass, replace
from datetime import datetime, timedelta, timezone
from enum import Enum
from pathlib import Path
from typing import Iterator, NoReturn, Protocol

from . import evidence
from .manifest import (
    ApprovalError,
    ApprovalErrorCode,
    MANAGE_EXTERNAL_STORAGE,
    ORDINARY_PACKAGE,
    QUALIFICATION_PACKAGE,
    OperationAuthorization,
    OperationCategory,
    OwnerApproval,
    QualificationManifest,
    SessionAuthorization,
    SessionStateMode,
    StateMode,
    _is_loaded_owner_approval,
    _is_loaded_restoration_approval,
    _is_loaded_session_authorization,
    _loaded_owner_approval_source_details,
    _owner_approval_source_matches,
    _RestorationApprovalContext,
    load_manifest,
    load_owner_approval_for_restoration,
)


class EffectiveAccess(str, Enum):
    """Observed result of asking whether the app can manage external storage."""

    ALLOWED = "allowed"
    DENIED = "denied"


class AppOpMode(str, Enum):
    """Stored Android app-op mode, including the unset default mode."""

    DEFAULT = "default"
    ALLOWED = "allow"
    DENIED = "deny"
    IGNORED = "ignore"
    ERRORED = "errored"
    FOREGROUND = "foreground"


@dataclass(frozen=True)
class StoredAppOpConfiguration:
    """The persisted app-op mode and whether a package override is present."""

    mode: AppOpMode | None
    override_present: bool | None


@dataclass(frozen=True)
class PermissionConfigurationSnapshot:
    """Separate observed access from the exact stored app-op configuration.

    The effective access check and stored app-op read are independent inputs.
    Either can be unknown; callers must reject incomplete snapshots before
    changing device state.
    """

    effective_access: EffectiveAccess | None
    stored_configuration: StoredAppOpConfiguration | None


def is_exact_snapshot(value: object) -> bool:
    """Return whether a snapshot contains every independently observed field."""
    if type(value) is not PermissionConfigurationSnapshot:
        return False
    if type(value.effective_access) is not EffectiveAccess:
        return False
    stored = value.stored_configuration
    if type(stored) is not StoredAppOpConfiguration:
        return False
    if type(stored.mode) is not AppOpMode or type(stored.override_present) is not bool:
        return False
    return (stored.mode is AppOpMode.DEFAULT) is (stored.override_present is False)


def configuration_for_access(access: EffectiveAccess) -> StoredAppOpConfiguration:
    """Return the explicit app-op setting used by an authorized transition."""
    if type(access) is not EffectiveAccess:
        raise ValueError("unsupported effective access state")
    mode = AppOpMode.ALLOWED if access is EffectiveAccess.ALLOWED else AppOpMode.DENIED
    return StoredAppOpConfiguration(mode=mode, override_present=True)


DEFAULT_STATE_PATH = Path.home() / ".argus-rom-toolkit" / "device-restoration.json"
_LOCK_NAME = "device-restoration.lock"
_MAX_BYTES = 64 * 1024
_MAX_RECORDS = 128
_SHA256 = frozenset("0123456789abcdef")
_DEVICE_SAFETY_SCHEMA_VERSION = 2


class SafetyStateError(Exception):
    """A sanitized failure to read or durably update owner safety state."""

    def __init__(self) -> None:
        super().__init__("owner-private device safety state is unavailable or invalid")


class DeviceRestorationPending(SafetyStateError):
    """The target already has an unresolved permission-restoration record."""

    def __init__(self) -> None:
        super().__init__()


@dataclass(frozen=True)
class PendingRestoration:
    """The exact approved restoration obligation saved before a setter call."""

    authorization_id: str
    authorization_sha256: str
    operation_id: str
    restoration_operation_id: str
    target_serial: str
    package_name: str
    permission_name: str
    snapshot: PermissionConfigurationSnapshot
    approval_sidecar_path: Path
    approval_directory_identity: tuple[int, int]
    approval_file_identity: tuple[int, int]
    approval_sidecar_sha256: str
    recovery_setter_attempted: bool = False


def _private_directory(metadata: os.stat_result) -> bool:
    return (
        stat.S_ISDIR(metadata.st_mode)
        and metadata.st_uid == os.geteuid()
        and stat.S_IMODE(metadata.st_mode) == 0o700
    )


def _private_file(metadata: os.stat_result, *, empty: bool = False) -> bool:
    return (
        stat.S_ISREG(metadata.st_mode)
        and metadata.st_uid == os.geteuid()
        and stat.S_IMODE(metadata.st_mode) == 0o600
        and (not empty or metadata.st_size == 0)
    )


def _valid_text(value: object, *, maximum: int = 512) -> bool:
    return (
        type(value) is str
        and 1 <= len(value) <= maximum
        and value == value.strip()
        and not any(ord(character) < 0x20 or ord(character) == 0x7F for character in value)
    )


def _record_is_valid(record: PendingRestoration) -> bool:
    return (
        type(record) is PendingRestoration
        and _valid_text(record.authorization_id)
        and _valid_text(record.authorization_sha256, maximum=64)
        and len(record.authorization_sha256) == 64
        and set(record.authorization_sha256) <= _SHA256
        and _valid_text(record.operation_id)
        and _valid_text(record.restoration_operation_id)
        and _valid_text(record.target_serial)
        and record.package_name == QUALIFICATION_PACKAGE
        and record.permission_name == MANAGE_EXTERNAL_STORAGE
        and is_exact_snapshot(record.snapshot)
        and isinstance(record.approval_sidecar_path, Path)
        and record.approval_sidecar_path.is_absolute()
        and _valid_text(str(record.approval_sidecar_path), maximum=4096)
        and type(record.approval_directory_identity) is tuple
        and len(record.approval_directory_identity) == 2
        and all(type(value) is int and value >= 0 for value in record.approval_directory_identity)
        and type(record.approval_file_identity) is tuple
        and len(record.approval_file_identity) == 2
        and all(type(value) is int and value >= 0 for value in record.approval_file_identity)
        and type(record.approval_sidecar_sha256) is str
        and len(record.approval_sidecar_sha256) == 64
        and set(record.approval_sidecar_sha256) <= _SHA256
        and type(record.recovery_setter_attempted) is bool
    )


def _snapshot_to_document(snapshot: PermissionConfigurationSnapshot) -> dict[str, object]:
    stored = snapshot.stored_configuration
    if stored is None:
        raise SafetyStateError
    return {
        "effective_access": snapshot.effective_access.value,
        "app_op_mode": stored.mode.value,
        "override_present": stored.override_present,
    }


def _snapshot_sha256(snapshot: PermissionConfigurationSnapshot) -> str:
    """Hash the canonical typed snapshot used to authorize one restoration."""
    encoded = json.dumps(
        _snapshot_to_document(snapshot),
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=True,
        allow_nan=False,
    ).encode("ascii")
    return hashlib.sha256(encoded).hexdigest()


def _record_to_document(record: PendingRestoration) -> dict[str, object]:
    if not _record_is_valid(record):
        raise SafetyStateError
    return {
        "authorization_id": record.authorization_id,
        "authorization_sha256": record.authorization_sha256,
        "operation_id": record.operation_id,
        "restoration_operation_id": record.restoration_operation_id,
        "target_serial": record.target_serial,
        "package_name": record.package_name,
        "permission_name": record.permission_name,
        "snapshot": _snapshot_to_document(record.snapshot),
        "approval_sidecar_path": str(record.approval_sidecar_path),
        "approval_directory_identity": list(record.approval_directory_identity),
        "approval_file_identity": list(record.approval_file_identity),
        "approval_sidecar_sha256": record.approval_sidecar_sha256,
        "recovery_setter_attempted": record.recovery_setter_attempted,
    }


def _pairs_without_duplicates(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError
        result[key] = value
    return result


def _parse_record(value: object) -> PendingRestoration:
    fields = {
        "authorization_id",
        "authorization_sha256",
        "operation_id",
        "restoration_operation_id",
        "target_serial",
        "package_name",
        "permission_name",
        "snapshot",
        "approval_sidecar_path",
        "approval_directory_identity",
        "approval_file_identity",
        "approval_sidecar_sha256",
        "recovery_setter_attempted",
    }
    if type(value) is not dict or value.keys() != fields:
        raise SafetyStateError
    raw_snapshot = value["snapshot"]
    if type(raw_snapshot) is not dict or raw_snapshot.keys() != {
        "effective_access",
        "app_op_mode",
        "override_present",
    }:
        raise SafetyStateError
    try:
        snapshot = PermissionConfigurationSnapshot(
            effective_access=EffectiveAccess(raw_snapshot["effective_access"]),
            stored_configuration=StoredAppOpConfiguration(
                mode=AppOpMode(raw_snapshot["app_op_mode"]),
                override_present=raw_snapshot["override_present"],
            ),
        )
    except (TypeError, ValueError):
        raise SafetyStateError from None
    try:
        if (
            type(value["approval_sidecar_path"]) is not str
            or type(value["approval_directory_identity"]) is not list
            or type(value["approval_file_identity"]) is not list
            or type(value["recovery_setter_attempted"]) is not bool
        ):
            raise ValueError
        directory_identity = tuple(value["approval_directory_identity"])
        file_identity = tuple(value["approval_file_identity"])
        record = PendingRestoration(
            authorization_id=value["authorization_id"],
            authorization_sha256=value["authorization_sha256"],
            operation_id=value["operation_id"],
            restoration_operation_id=value["restoration_operation_id"],
            target_serial=value["target_serial"],
            package_name=value["package_name"],
            permission_name=value["permission_name"],
            snapshot=snapshot,
            approval_sidecar_path=Path(value["approval_sidecar_path"]),
            approval_directory_identity=directory_identity,
            approval_file_identity=file_identity,
            approval_sidecar_sha256=value["approval_sidecar_sha256"],
            recovery_setter_attempted=value["recovery_setter_attempted"],
        )
    except (TypeError, ValueError):
        raise SafetyStateError from None
    if not _record_is_valid(record):
        raise SafetyStateError
    return record


def _parse_document(encoded: bytes) -> list[PendingRestoration]:
    try:
        value = json.loads(encoded.decode("utf-8"), object_pairs_hook=_pairs_without_duplicates)
    except (UnicodeDecodeError, ValueError, RecursionError):
        raise SafetyStateError from None
    if type(value) is not dict or value.keys() != {"schema_version", "pending"}:
        raise SafetyStateError
    records = value["pending"]
    if (
        type(value["schema_version"]) is not int
        or value["schema_version"] != _DEVICE_SAFETY_SCHEMA_VERSION
    ):
        raise SafetyStateError
    if type(records) is not list or len(records) > _MAX_RECORDS:
        raise SafetyStateError
    parsed = [_parse_record(item) for item in records]
    serials = [item.target_serial for item in parsed]
    if len(serials) != len(set(serials)):
        raise SafetyStateError
    return parsed


def _read_records(directory: int, filename: str) -> list[PendingRestoration]:
    no_follow = getattr(os, "O_NOFOLLOW", None)
    if no_follow is None:
        raise SafetyStateError
    expected_identity: tuple[int, int] | None = None
    try:
        before = os.stat(filename, dir_fd=directory, follow_symlinks=False)
    except FileNotFoundError:
        return []
    except OSError:
        raise SafetyStateError from None
    if not _private_file(before) or before.st_size > _MAX_BYTES:
        raise SafetyStateError
    try:
        descriptor = os.open(filename, os.O_RDONLY | no_follow, dir_fd=directory)
    except OSError:
        raise SafetyStateError from None
    try:
        opened = os.fstat(descriptor)
        if (
            not _private_file(opened)
            or (opened.st_dev, opened.st_ino) != (before.st_dev, before.st_ino)
            or opened.st_size > _MAX_BYTES
        ):
            raise SafetyStateError
        chunks: list[bytes] = []
        remaining = _MAX_BYTES + 1
        while remaining:
            chunk = os.read(descriptor, min(8192, remaining))
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        encoded = b"".join(chunks)
        after = os.fstat(descriptor)
        current = os.stat(filename, dir_fd=directory, follow_symlinks=False)
        if (
            len(encoded) > _MAX_BYTES
            or (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns)
            != (opened.st_dev, opened.st_ino, opened.st_size, opened.st_mtime_ns)
            or (current.st_dev, current.st_ino) != (opened.st_dev, opened.st_ino)
        ):
            raise SafetyStateError
        return _parse_document(encoded)
    except OSError:
        raise SafetyStateError from None
    finally:
        os.close(descriptor)


def _open_lock(directory: int) -> int:
    no_follow = getattr(os, "O_NOFOLLOW", None)
    if no_follow is None:
        raise SafetyStateError
    expected_identity: tuple[int, int] | None = None
    descriptor = -1
    try:
        before = os.stat(_LOCK_NAME, dir_fd=directory, follow_symlinks=False)
    except FileNotFoundError:
        try:
            descriptor = os.open(
                _LOCK_NAME,
                os.O_RDWR | os.O_CREAT | os.O_EXCL | no_follow,
                0o600,
                dir_fd=directory,
            )
            os.fchmod(descriptor, 0o600)
        except OSError:
            if descriptor >= 0:
                os.close(descriptor)
            raise SafetyStateError from None
    except OSError:
        raise SafetyStateError from None
    else:
        if not _private_file(before, empty=True):
            raise SafetyStateError
        expected_identity = (before.st_dev, before.st_ino)
        try:
            descriptor = os.open(_LOCK_NAME, os.O_RDWR | no_follow, dir_fd=directory)
        except OSError:
            raise SafetyStateError from None
    try:
        metadata = os.fstat(descriptor)
        current = os.stat(_LOCK_NAME, dir_fd=directory, follow_symlinks=False)
        if (
            not _private_file(metadata, empty=True)
            or (metadata.st_dev, metadata.st_ino) != (current.st_dev, current.st_ino)
            or (
                expected_identity is not None
                and (metadata.st_dev, metadata.st_ino) != expected_identity
            )
        ):
            raise SafetyStateError
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        return descriptor
    except SafetyStateError:
        if descriptor >= 0:
            os.close(descriptor)
        raise
    except OSError:
        if descriptor >= 0:
            os.close(descriptor)
        raise SafetyStateError from None


@contextmanager
def _locked_directory(path: Path, *, create: bool) -> Iterator[int | None]:
    if os.name != "posix" or not hasattr(os, "O_DIRECTORY") or not hasattr(os, "O_NOFOLLOW"):
        raise SafetyStateError
    parent = path.absolute().parent
    try:
        before = parent.lstat()
    except FileNotFoundError:
        if not create:
            yield None
            return
        try:
            parent.mkdir(mode=0o700)
            before = parent.lstat()
        except OSError:
            raise SafetyStateError from None
    except OSError:
        raise SafetyStateError from None
    if not _private_directory(before):
        raise SafetyStateError
    try:
        directory = os.open(parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    except OSError:
        raise SafetyStateError from None
    lock = -1
    try:
        opened = os.fstat(directory)
        if (
            not _private_directory(opened)
            or (opened.st_dev, opened.st_ino) != (before.st_dev, before.st_ino)
        ):
            raise SafetyStateError
        lock = _open_lock(directory)
        yield directory
    finally:
        if lock >= 0:
            try:
                fcntl.flock(lock, fcntl.LOCK_UN)
            except OSError:
                pass
            os.close(lock)
        os.close(directory)


def _write_records(directory: int, filename: str, records: list[PendingRestoration]) -> None:
    if len(records) > _MAX_RECORDS:
        raise SafetyStateError
    document = {
        "schema_version": _DEVICE_SAFETY_SCHEMA_VERSION,
        "pending": [_record_to_document(record) for record in records],
    }
    try:
        encoded = json.dumps(
            document,
            sort_keys=True,
            separators=(",", ":"),
            ensure_ascii=True,
            allow_nan=False,
        ).encode("ascii")
    except (TypeError, ValueError):
        raise SafetyStateError from None
    if len(encoded) > _MAX_BYTES:
        raise SafetyStateError

    no_follow = getattr(os, "O_NOFOLLOW", None)
    if no_follow is None:
        raise SafetyStateError
    temporary_name: str | None = None
    descriptor = -1
    try:
        for _ in range(8):
            candidate = f".device-restoration-{secrets.token_hex(12)}.tmp"
            try:
                descriptor = os.open(
                    candidate,
                    os.O_WRONLY | os.O_CREAT | os.O_EXCL | no_follow,
                    0o600,
                    dir_fd=directory,
                )
                temporary_name = candidate
                break
            except FileExistsError:
                continue
        if descriptor < 0 or temporary_name is None:
            raise SafetyStateError
        os.fchmod(descriptor, 0o600)
        if not _private_file(os.fstat(descriptor)):
            raise SafetyStateError
        offset = 0
        while offset < len(encoded):
            written = os.write(descriptor, encoded[offset:])
            if written <= 0:
                raise SafetyStateError
            offset += written
        os.fsync(descriptor)
        os.close(descriptor)
        descriptor = -1
        os.replace(
            temporary_name,
            filename,
            src_dir_fd=directory,
            dst_dir_fd=directory,
        )
        temporary_name = None
        os.fsync(directory)
    except SafetyStateError:
        raise
    except OSError:
        raise SafetyStateError from None
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        if temporary_name is not None:
            try:
                os.unlink(temporary_name, dir_fd=directory)
            except OSError:
                pass


def pending_for_device(target_serial: str, *, path: Path = DEFAULT_STATE_PATH) -> PendingRestoration | None:
    """Read the unresolved restoration for a target without exposing its identity."""
    if not _valid_text(target_serial):
        raise SafetyStateError
    with _locked_directory(path, create=False) as directory:
        if directory is None:
            return None
        records = _read_records(directory, path.name)
        return next((record for record in records if record.target_serial == target_serial), None)


def persist_pending(record: PendingRestoration, *, path: Path = DEFAULT_STATE_PATH) -> None:
    """Atomically persist a restoration obligation before a product setter runs."""
    if not _record_is_valid(record):
        raise SafetyStateError
    with _locked_directory(path, create=True) as directory:
        if directory is None:
            raise SafetyStateError
        records = _read_records(directory, path.name)
        if any(item.target_serial == record.target_serial for item in records):
            raise DeviceRestorationPending
        records.append(record)
        _write_records(directory, path.name, records)


def _claim_recovery_setter(
    record: PendingRestoration,
    *,
    path: Path = DEFAULT_STATE_PATH,
) -> PendingRestoration:
    """Durably consume the single explicit recovery setter before calling it."""
    if not _record_is_valid(record) or record.recovery_setter_attempted:
        raise SafetyStateError
    with _locked_directory(path, create=False) as directory:
        if directory is None:
            raise SafetyStateError
        records = _read_records(directory, path.name)
        matches = [index for index, item in enumerate(records) if item.target_serial == record.target_serial]
        if len(matches) != 1 or records[matches[0]] != record:
            raise SafetyStateError
        claimed = replace(record, recovery_setter_attempted=True)
        records[matches[0]] = claimed
        _write_records(directory, path.name, records)
        return claimed


def clear_pending(record: PendingRestoration, *, path: Path = DEFAULT_STATE_PATH) -> None:
    """Remove a matching obligation only after its exact snapshot is verified."""
    if not _record_is_valid(record):
        raise SafetyStateError
    with _locked_directory(path, create=False) as directory:
        if directory is None:
            raise SafetyStateError
        records = _read_records(directory, path.name)
        matches = [item for item in records if item == record]
        if len(matches) != 1:
            raise SafetyStateError
        _write_records(directory, path.name, [item for item in records if item != record])




_SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
_SESSION_REGISTRY_PATH = Path.home() / ".argus-rom-toolkit" / "session-registry.json"
_SESSION_REGISTRY_LOCK_NAME = "session-registry.lock"
_SESSION_REGISTRY_MAX_BYTES = 1024 * 1024
_SESSION_REGISTRY_MAX_SESSIONS = 2048
_DEVICE_SAFETY_PATH = DEFAULT_STATE_PATH


@dataclass(frozen=True)
class HostValidationResult:
    """A structurally valid manifest; no session has been admitted."""

    manifest: QualificationManifest


class LiveExecutionBlocked(Exception):
    """Raised when execution is requested before live admission exists."""

    def __init__(self) -> None:
        super().__init__("live authorization/device admission not implemented")


def admit_host_only(
    manifest_path: Path,
    expected_state_mode: StateMode,
) -> HostValidationResult:
    """Perform structural host validation only.

    `HOST_VALIDATED` does not establish session authorization or admission
    under SPEC-X-003 and does not begin a qualification session.
    """

    return HostValidationResult(
        manifest=load_manifest(manifest_path, expected_state_mode)
    )


def request_live_execution(_validation: HostValidationResult) -> NoReturn:
    """Refuse live execution until the later admission controls are implemented."""

    raise LiveExecutionBlocked()


# Internal read-only admission contract for one fresh session.
class AdmissionStatus(str, Enum):
    ADMITTED = "ADMITTED"
    BLOCKED = "BLOCKED"


class AdmissionCode(str, Enum):
    ADMITTED = "SESSION_ADMITTED"
    SESSION_ALREADY_USED = "SESSION_ALREADY_USED"
    SESSION_STATE_UNAVAILABLE = "SESSION_STATE_UNAVAILABLE"
    DEVICE_RESTORATION_PENDING = "DEVICE_RESTORATION_PENDING"
    DEVICE_SAFETY_STATE_UNAVAILABLE = "DEVICE_SAFETY_STATE_UNAVAILABLE"
    APPROVAL_INVALID = "OWNER_APPROVAL_INVALID"
    SESSION_EXPIRED = "SESSION_EXPIRED"
    ADD_SCAN_PLAN_INVALID = "ADD_SCAN_OPERATION_PLAN_INVALID"
    NO_RESET_OBSERVATION_UNAVAILABLE = "NO_RESET_BASELINE_OBSERVER_UNAVAILABLE"
    ARTIFACT_MISMATCH = "HOST_ARTIFACT_MISMATCH"
    OBSERVATION_UNAVAILABLE = "DEVICE_OBSERVATION_UNAVAILABLE"
    NO_TARGET = "NO_CONNECTED_TARGET"
    AMBIGUOUS_TARGET = "MULTIPLE_CONNECTED_TARGETS"
    TARGET_MISMATCH = "TARGET_IDENTITY_MISMATCH"
    DEVICE_PROFILE_UNAVAILABLE = "DEVICE_PROFILE_UNAVAILABLE"
    OS_UNSUPPORTED = "ANDROID_API_UNSUPPORTED"
    ABI_MISMATCH = "DEVICE_ABI_MISMATCH"
    CAPABILITY_UNAVAILABLE = "REQUIRED_CAPABILITY_UNAVAILABLE"
    INSTALLATION_OBSERVATION_UNAVAILABLE = "INSTALLATION_OBSERVATION_UNAVAILABLE"
    QUALIFICATION_APP_ABSENT = "QUALIFICATION_APP_ABSENT"
    QUALIFICATION_APP_INCOMPATIBLE = "QUALIFICATION_APP_INCOMPATIBLE"
    FOREGROUND_UNAVAILABLE = "FOREGROUND_OBSERVATION_UNAVAILABLE"
    FOREGROUND_MISMATCH = "FOREGROUND_PACKAGE_MISMATCH"
    INTERFERENCE_UNKNOWN = "INTERFERENCE_STATUS_UNAVAILABLE"
    INTERFERENCE_DETECTED = "SESSION_INTERFERENCE_DETECTED"
    STORAGE_OBSERVATION_UNAVAILABLE = "STORAGE_OBSERVATION_UNAVAILABLE"
    STORAGE_RESERVE_UNAVAILABLE = "STORAGE_RESERVE_UNAVAILABLE"


_ADMISSION_MESSAGES = {
    code: ("Session admitted based on the supplied observations" if code is AdmissionCode.ADMITTED else "Session admission is blocked")
    for code in AdmissionCode
}


class SessionLifecycle(str, Enum):
    ACTIVE = "active"
    RESTORE_ONLY = "restore_only"
    COMPLETED = "completed"
    BLOCKED = "blocked"


class SessionExecutionPhase(str, Enum):
    """Trusted execution phase recorded for one admitted session."""

    ADMITTED = "admitted"
    QUALIFICATION = "qualification"


@dataclass(frozen=True)
class AdmissionResult:
    status: AdmissionStatus
    code: AdmissionCode
    message: str
    session: AdmittedSession | None = None


@dataclass(frozen=True)
class HostArtifactFacts:
    """Properties extracted by host APK inspection, not device measurements."""

    apk_sha256: str | None
    package_name: str | None
    version_code: int | None
    signature_verified: bool
    signer_count: int
    certificate_sha256: str | None
    source_revision: str | None
    declared_permissions: frozenset[str]
    source_dirty: bool | None = None


def host_artifact_facts(apk_facts: object) -> HostArtifactFacts:
    """Copy only facts available from the existing host APK inspector."""
    try:
        record_source = apk_facts.build_record.get("source")
        source_revision = record_source.get("revision") if isinstance(record_source, dict) else None
        signatures = apk_facts.signatures
        return HostArtifactFacts(
            apk_sha256=apk_facts.sha256,
            package_name=apk_facts.badging.package_id,
            version_code=apk_facts.badging.version_code,
            signature_verified=signatures.verified,
            signer_count=signatures.signer_count,
            certificate_sha256=signatures.certificate_sha256,
            source_revision=source_revision,
            declared_permissions=frozenset(apk_facts.manifest.permissions),
            source_dirty=(record_source.get("dirty") if isinstance(record_source, dict) else None),
        )
    except (AttributeError, TypeError, ValueError):
        return HostArtifactFacts(None, None, None, False, 0, None, None, frozenset())


class InstallationStatus(str, Enum):
    PRESENT = "present"
    ABSENT = "absent"
    UNKNOWN = "unknown"


@dataclass(frozen=True)
class InstallationObservation:
    """Independent package-manager observation for the qualifier package."""

    status: InstallationStatus
    package_name: str | None = None
    version_code: int | None = None
    certificate_sha256: str | None = None
    artifact_sha256: str | None = None

    @classmethod
    def absent(cls) -> InstallationObservation:
        return cls(InstallationStatus.ABSENT)


@dataclass(frozen=True)
class FreshAdmissionObservation:
    """Read-only target, package, foreground, interference, and reserve facts."""

    connected_serials: tuple[str, ...] | None
    android_api_level: int | None
    abi: str | None
    capabilities: frozenset[str] | None
    installation: InstallationObservation | None
    foreground_package: str | None
    interference_free: bool | None
    available_storage_bytes: int | None


class FreshAdmissionTransport(Protocol):
    """Read-only interface required for fresh-state admission."""

    def observe_fresh_admission(self) -> FreshAdmissionObservation:
        """Return independent observations or raise when any are unavailable."""


def _private_session_file(metadata: os.stat_result) -> bool:
    return (
        stat.S_ISREG(metadata.st_mode)
        and metadata.st_uid == os.geteuid()
        and stat.S_IMODE(metadata.st_mode) == 0o600
    )


def _private_session_directory(metadata: os.stat_result) -> bool:
    return (
        stat.S_ISDIR(metadata.st_mode)
        and metadata.st_uid == os.geteuid()
        and stat.S_IMODE(metadata.st_mode) == 0o700
    )


def _registry_pairs_without_duplicates(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate registry key")
        result[key] = value
    return result


def _registry_constant(_value: str) -> NoReturn:
    raise ValueError("invalid registry constant")


def _parse_session_registry(encoded: bytes) -> list[dict[str, str]] | None:
    if len(encoded) > _SESSION_REGISTRY_MAX_BYTES:
        return None
    try:
        document = json.loads(
            encoded.decode("utf-8"),
            object_pairs_hook=_registry_pairs_without_duplicates,
            parse_constant=_registry_constant,
        )
    except (UnicodeDecodeError, ValueError, RecursionError):
        return None
    if (
        type(document) is not dict
        or document.keys() != {"schema_version", "sessions"}
        or type(document["schema_version"]) is not int
        or document["schema_version"] != 1
        or type(document["sessions"]) is not list
        or len(document["sessions"]) > _SESSION_REGISTRY_MAX_SESSIONS
    ):
        return None

    sessions: list[dict[str, str]] = []
    authorization_ids: set[str] = set()
    digests: set[str] = set()
    for item in document["sessions"]:
        if (
            type(item) is not dict
            or item.keys() != {"authorization_id", "authorization_sha256"}
        ):
            return None
        authorization_id = item["authorization_id"]
        digest = item["authorization_sha256"]
        if (
            type(authorization_id) is not str
            or not 1 <= len(authorization_id) <= 512
            or authorization_id != authorization_id.strip()
            or any(ord(character) < 0x20 or ord(character) == 0x7f for character in authorization_id)
            or type(digest) is not str
            or _SHA256_RE.fullmatch(digest) is None
            or authorization_id in authorization_ids
            or digest in digests
        ):
            return None
        authorization_ids.add(authorization_id)
        digests.add(digest)
        sessions.append(
            {
                "authorization_id": authorization_id,
                "authorization_sha256": digest,
            }
        )
    return sessions


def _read_session_registry(directory_descriptor: int) -> list[dict[str, str]] | None:
    no_follow = getattr(os, "O_NOFOLLOW", None)
    if no_follow is None:
        return None
    try:
        before = os.stat(
            _SESSION_REGISTRY_PATH.name,
            dir_fd=directory_descriptor,
            follow_symlinks=False,
        )
    except FileNotFoundError:
        return []
    except OSError:
        return None
    if not _private_session_file(before) or before.st_size > _SESSION_REGISTRY_MAX_BYTES:
        return None
    try:
        descriptor = os.open(
            _SESSION_REGISTRY_PATH.name,
            os.O_RDONLY | no_follow,
            dir_fd=directory_descriptor,
        )
    except OSError:
        return None
    try:
        opened = os.fstat(descriptor)
        if (
            not _private_session_file(opened)
            or (opened.st_dev, opened.st_ino) != (before.st_dev, before.st_ino)
            or opened.st_size > _SESSION_REGISTRY_MAX_BYTES
        ):
            return None
        chunks: list[bytes] = []
        remaining = _SESSION_REGISTRY_MAX_BYTES + 1
        while remaining:
            chunk = os.read(descriptor, min(8192, remaining))
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        encoded = b"".join(chunks)
        after = os.fstat(descriptor)
        current_path = os.stat(
            _SESSION_REGISTRY_PATH.name,
            dir_fd=directory_descriptor,
            follow_symlinks=False,
        )
        if (
            len(encoded) > _SESSION_REGISTRY_MAX_BYTES
            or not _private_session_file(after)
            or (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns)
            != (opened.st_dev, opened.st_ino, opened.st_size, opened.st_mtime_ns)
            or (current_path.st_dev, current_path.st_ino)
            != (opened.st_dev, opened.st_ino)
        ):
            return None
        return _parse_session_registry(encoded)
    except OSError:
        return None
    finally:
        os.close(descriptor)


def _open_session_registry_lock(directory_descriptor: int) -> int | None:
    no_follow = getattr(os, "O_NOFOLLOW", None)
    if no_follow is None:
        return None
    try:
        before = os.stat(
            _SESSION_REGISTRY_LOCK_NAME,
            dir_fd=directory_descriptor,
            follow_symlinks=False,
        )
    except FileNotFoundError:
        try:
            descriptor = os.open(
                _SESSION_REGISTRY_LOCK_NAME,
                os.O_RDWR | os.O_CREAT | os.O_EXCL | no_follow,
                0o600,
                dir_fd=directory_descriptor,
            )
        except FileExistsError:
            try:
                descriptor = os.open(
                    _SESSION_REGISTRY_LOCK_NAME,
                    os.O_RDWR | no_follow,
                    dir_fd=directory_descriptor,
                )
                metadata = os.fstat(descriptor)
                current = os.stat(
                    _SESSION_REGISTRY_LOCK_NAME,
                    dir_fd=directory_descriptor,
                    follow_symlinks=False,
                )
            except OSError:
                return None
            if (
                not _private_session_file(metadata)
                or metadata.st_size != 0
                or (metadata.st_dev, metadata.st_ino) != (current.st_dev, current.st_ino)
            ):
                os.close(descriptor)
                return None
            return descriptor
        except OSError:
            return None
        try:
            os.fchmod(descriptor, 0o600)
            metadata = os.fstat(descriptor)
            if not _private_session_file(metadata) or metadata.st_size != 0:
                os.close(descriptor)
                return None
            return descriptor
        except OSError:
            os.close(descriptor)
            return None
    except OSError:
        return None
    if not _private_session_file(before) or before.st_size != 0:
        return None
    try:
        descriptor = os.open(
            _SESSION_REGISTRY_LOCK_NAME,
            os.O_RDWR | no_follow,
            dir_fd=directory_descriptor,
        )
    except OSError:
        return None
    metadata = os.fstat(descriptor)
    if (
        not _private_session_file(metadata)
        or metadata.st_size != 0
        or (metadata.st_dev, metadata.st_ino) != (before.st_dev, before.st_ino)
    ):
        os.close(descriptor)
        return None
    return descriptor


def _write_session_registry(
    directory_descriptor: int,
    sessions: list[dict[str, str]],
) -> bool:
    if len(sessions) > _SESSION_REGISTRY_MAX_SESSIONS:
        return False
    encoded = json.dumps(
        {"schema_version": 1, "sessions": sessions},
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=True,
        allow_nan=False,
    ).encode("ascii")
    if len(encoded) > _SESSION_REGISTRY_MAX_BYTES:
        return False

    no_follow = getattr(os, "O_NOFOLLOW", None)
    if no_follow is None:
        return False
    temporary_name: str | None = None
    descriptor = -1
    try:
        for _ in range(8):
            candidate = f".session-registry-{secrets.token_hex(12)}.tmp"
            try:
                descriptor = os.open(
                    candidate,
                    os.O_WRONLY | os.O_CREAT | os.O_EXCL | no_follow,
                    0o600,
                    dir_fd=directory_descriptor,
                )
                temporary_name = candidate
                break
            except FileExistsError:
                continue
        if descriptor < 0 or temporary_name is None:
            return False
        os.fchmod(descriptor, 0o600)
        if not _private_session_file(os.fstat(descriptor)):
            return False
        written = 0
        while written < len(encoded):
            count = os.write(descriptor, encoded[written:])
            if count <= 0:
                return False
            written += count
        os.fsync(descriptor)
        os.close(descriptor)
        descriptor = -1
        os.replace(
            temporary_name,
            _SESSION_REGISTRY_PATH.name,
            src_dir_fd=directory_descriptor,
            dst_dir_fd=directory_descriptor,
        )
        temporary_name = None
        os.fsync(directory_descriptor)
        return True
    except OSError:
        return False
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        if temporary_name is not None:
            try:
                os.unlink(temporary_name, dir_fd=directory_descriptor)
            except OSError:
                pass


def _claim_approval_once(
    approval: OwnerApproval,
    authorization_id: str,
    digest: str,
) -> bool | None:
    """Persist one-use state in the owner-private host registry."""
    if (
        not _is_loaded_owner_approval(approval)
        or not _owner_approval_source_matches(approval)
        or type(authorization_id) is not str
        or not 1 <= len(authorization_id) <= 512
        or authorization_id != authorization_id.strip()
        or type(digest) is not str
        or _SHA256_RE.fullmatch(digest) is None
        or os.name != "posix"
    ):
        return None
    no_follow = getattr(os, "O_NOFOLLOW", None)
    directory_flag = getattr(os, "O_DIRECTORY", None)
    if no_follow is None or directory_flag is None:
        return None

    directory_descriptor = -1
    lock_descriptor = -1
    try:
        directory_path = _SESSION_REGISTRY_PATH.parent
        try:
            os.mkdir(directory_path, 0o700)
        except FileExistsError:
            pass
        before_directory = directory_path.lstat()
        if not _private_session_directory(before_directory):
            return None
        directory_descriptor = os.open(
            directory_path,
            os.O_RDONLY | directory_flag | no_follow,
        )
        opened_directory = os.fstat(directory_descriptor)
        if (
            not _private_session_directory(opened_directory)
            or (opened_directory.st_dev, opened_directory.st_ino)
            != (before_directory.st_dev, before_directory.st_ino)
        ):
            return None

        opened_lock_descriptor = _open_session_registry_lock(directory_descriptor)
        if opened_lock_descriptor is None:
            return None
        lock_descriptor = opened_lock_descriptor
        fcntl.flock(lock_descriptor, fcntl.LOCK_EX)
        sessions = _read_session_registry(directory_descriptor)
        if sessions is None:
            return None
        if any(
            item["authorization_sha256"] == digest
            or item["authorization_id"] == authorization_id
            for item in sessions
        ):
            return False
        sessions.append(
            {
                "authorization_id": authorization_id,
                "authorization_sha256": digest,
            }
        )
        sessions.sort(key=lambda item: item["authorization_sha256"])
        if not _write_session_registry(directory_descriptor, sessions):
            return None
        return True
    except (OSError, TypeError, ValueError, RecursionError):
        return None
    finally:
        if lock_descriptor >= 0:
            try:
                fcntl.flock(lock_descriptor, fcntl.LOCK_UN)
            except OSError:
                pass
            os.close(lock_descriptor)
        if directory_descriptor >= 0:
            os.close(directory_descriptor)


class AdmittedSession:
    """One admitted session with terminal and restoration-only transitions."""

    def __init__(self, authorization: SessionAuthorization, approval: OwnerApproval) -> None:
        self.authorization = authorization
        self.approval = approval
        self.lifecycle = SessionLifecycle.ACTIVE
        self.execution_phase = SessionExecutionPhase.ADMITTED
        self.phase_operation_id: str | None = None
        self.permission_operation_id: str | None = None
        self.permission_snapshot: PermissionConfigurationSnapshot | None = None
        self.failure_pending = False
        self._operation_lock = threading.Lock()

    def reserve_operation(self) -> bool:
        """Reserve the session so only one product or restoration call runs."""
        return self._operation_lock.acquire(blocking=False)

    def release_operation(self) -> None:
        """Release the reservation after the operation reaches a stable state."""
        self._operation_lock.release()

    def enter_restore_only(
        self,
        operation_id: str,
        snapshot: PermissionConfigurationSnapshot,
        *,
        failed: bool,
    ) -> None:
        if self.lifecycle is not SessionLifecycle.ACTIVE:
            raise RuntimeError("session is not active")
        self.permission_operation_id = operation_id
        self.permission_snapshot = snapshot
        self.failure_pending = failed
        self.lifecycle = SessionLifecycle.RESTORE_ONLY

    def finish(self, *, blocked: bool) -> None:
        if self.lifecycle not in {SessionLifecycle.ACTIVE, SessionLifecycle.RESTORE_ONLY}:
            raise RuntimeError("session is already terminal")
        self.lifecycle = SessionLifecycle.BLOCKED if blocked else SessionLifecycle.COMPLETED


@dataclass(frozen=True)
class _AdmittedSessionBinding:
    """Snapshot the exact loader-approved objects and executor-owned session state."""

    authorization: SessionAuthorization
    approval: OwnerApproval
    lifecycle: SessionLifecycle
    execution_phase: SessionExecutionPhase
    phase_operation_id: str | None
    permission_operation_id: str | None
    permission_snapshot: PermissionConfigurationSnapshot | None
    failure_pending: bool
    operation_lock: object


_ADMITTED_SESSION_BINDINGS: weakref.WeakKeyDictionary[
    AdmittedSession,
    _AdmittedSessionBinding,
] = weakref.WeakKeyDictionary()
_ADMITTED_SESSION_BINDINGS_LOCK = threading.Lock()


@dataclass(frozen=True)
class _FirstAddScanAdmissionBinding:
    """Prove that a session came through the one fresh Add & Scan admission."""

    artifact: HostArtifactFacts
    plan_sha256: str


_FIRST_ADD_SCAN_BINDINGS: weakref.WeakKeyDictionary[
    AdmittedSession, _FirstAddScanAdmissionBinding
] = weakref.WeakKeyDictionary()
_FIRST_ADD_SCAN_CLAIMS: weakref.WeakSet[AdmittedSession] = weakref.WeakSet()
_FIRST_ADD_SCAN_BINDINGS_LOCK = threading.Lock()


def _session_binding_matches(
    session: AdmittedSession,
    binding: _AdmittedSessionBinding,
) -> bool:
    """Check loader evidence, object identity, and every protected session field."""
    try:
        return (
            type(session) is AdmittedSession
            and session.authorization is binding.authorization
            and session.approval is binding.approval
            and _is_loaded_session_authorization(binding.authorization)
            and _is_loaded_owner_approval(binding.approval)
            and type(session.lifecycle) is SessionLifecycle
            and session.lifecycle is binding.lifecycle
            and type(session.execution_phase) is SessionExecutionPhase
            and session.execution_phase is binding.execution_phase
            and type(session.phase_operation_id) in (str, type(None))
            and session.phase_operation_id == binding.phase_operation_id
            and type(session.permission_operation_id) in (str, type(None))
            and session.permission_operation_id == binding.permission_operation_id
            and type(session.permission_snapshot)
            in (PermissionConfigurationSnapshot, type(None))
            and session.permission_snapshot == binding.permission_snapshot
            and type(session.failure_pending) is bool
            and session.failure_pending is binding.failure_pending
            and session._operation_lock is binding.operation_lock
        )
    except Exception:
        return False


def _revoke_admitted_session(session: object) -> None:
    if type(session) is not AdmittedSession:
        return
    with _ADMITTED_SESSION_BINDINGS_LOCK:
        _ADMITTED_SESSION_BINDINGS.pop(session, None)


def _admitted_session_binding(session: object) -> _AdmittedSessionBinding | None:
    """Return the binding only for the unchanged object created by admission."""
    if type(session) is not AdmittedSession:
        return None
    with _ADMITTED_SESSION_BINDINGS_LOCK:
        binding = _ADMITTED_SESSION_BINDINGS.get(session)
    if binding is None:
        return None
    if not _session_binding_matches(session, binding):
        _revoke_admitted_session(session)
        return None
    return binding


def _register_admitted_session(session: AdmittedSession) -> bool:
    """Bind a newly admitted session to its exact loader-validated inputs."""
    if (
        type(session) is not AdmittedSession
        or not _is_loaded_session_authorization(session.authorization)
        or not _is_loaded_owner_approval(session.approval)
    ):
        return False
    binding = _AdmittedSessionBinding(
        authorization=session.authorization,
        approval=session.approval,
        lifecycle=SessionLifecycle.ACTIVE,
        execution_phase=SessionExecutionPhase.ADMITTED,
        phase_operation_id=None,
        permission_operation_id=None,
        permission_snapshot=None,
        failure_pending=False,
        operation_lock=session._operation_lock,
    )
    if not _session_binding_matches(session, binding):
        return False
    with _ADMITTED_SESSION_BINDINGS_LOCK:
        if session in _ADMITTED_SESSION_BINDINGS:
            return False
        _ADMITTED_SESSION_BINDINGS[session] = binding
    return True


def _register_first_add_scan_session(
    session: AdmittedSession,
    artifact: HostArtifactFacts,
) -> bool:
    """Bind host-inspected artifact facts to one first-scan admission."""
    if (
        _admitted_session_binding(session) is None
        or not _validate_host_artifact(session.authorization, artifact)
        or _first_add_scan_plan(session.authorization) is None
            or artifact.source_dirty is not False
    ):
        return False
    binding = _FirstAddScanAdmissionBinding(
        artifact=artifact,
        plan_sha256=session.authorization.plan_sha256,
    )
    with _FIRST_ADD_SCAN_BINDINGS_LOCK:
        if session in _FIRST_ADD_SCAN_BINDINGS or session in _FIRST_ADD_SCAN_CLAIMS:
            return False
        _FIRST_ADD_SCAN_BINDINGS[session] = binding
    return True


def _first_add_scan_admission_binding(
    session: object,
) -> _FirstAddScanAdmissionBinding | None:
    """Return the one-use Add & Scan binding for an intact admitted session."""
    if type(session) is not AdmittedSession or _admitted_session_binding(session) is None:
        return None
    with _FIRST_ADD_SCAN_BINDINGS_LOCK:
        binding = _FIRST_ADD_SCAN_BINDINGS.get(session)
    if (
        binding is None
        or binding.plan_sha256 != session.authorization.plan_sha256
        or not _validate_host_artifact(session.authorization, binding.artifact)
        or binding.artifact.source_dirty is not False
        or _first_add_scan_plan(session.authorization) is None
    ):
        return None
    return binding


def _claim_first_add_scan_execution(session: AdmittedSession) -> bool:
    """Consume the in-memory executor capability before its first operation."""
    if _first_add_scan_admission_binding(session) is None:
        return False
    with _FIRST_ADD_SCAN_BINDINGS_LOCK:
        if session not in _FIRST_ADD_SCAN_BINDINGS or session in _FIRST_ADD_SCAN_CLAIMS:
            return False
        _FIRST_ADD_SCAN_CLAIMS.add(session)
    return True


def _enter_qualification_phase(session: AdmittedSession, operation_id: str) -> bool:
    """Record the trusted qualification transition for one approved operation."""
    previous = _admitted_session_binding(session)
    if (
        previous is None
        or previous.lifecycle is not SessionLifecycle.ACTIVE
        or previous.execution_phase is not SessionExecutionPhase.ADMITTED
        or type(operation_id) is not str
    ):
        return False
    operation = next(
        (
            item
            for item in previous.authorization.operations
            if item.operation_id == operation_id
        ),
        None,
    )
    if (
        operation is None
        or operation.category is not OperationCategory.PERMISSION_APP_OP
        or operation.phase != SessionExecutionPhase.QUALIFICATION.value
        or operation.permission_name != MANAGE_EXTERNAL_STORAGE
        or operation.target_serial != previous.authorization.target_serial
        or operation.package_name != QUALIFICATION_PACKAGE
    ):
        return False
    session.execution_phase = SessionExecutionPhase.QUALIFICATION
    session.phase_operation_id = operation_id
    return _advance_admitted_session_binding(
        session,
        previous,
        lifecycle=previous.lifecycle,
        execution_phase=SessionExecutionPhase.QUALIFICATION,
        phase_operation_id=operation_id,
        permission_operation_id=previous.permission_operation_id,
        permission_snapshot=previous.permission_snapshot,
        failure_pending=previous.failure_pending,
    )


def _advance_admitted_session_binding(
    session: AdmittedSession,
    previous: _AdmittedSessionBinding,
    *,
    lifecycle: SessionLifecycle,
    execution_phase: SessionExecutionPhase,
    phase_operation_id: str | None,
    permission_operation_id: str | None,
    permission_snapshot: PermissionConfigurationSnapshot | None,
    failure_pending: bool,
) -> bool:
    """Record a state transition performed by the trusted executor path."""
    binding = _AdmittedSessionBinding(
        authorization=previous.authorization,
        approval=previous.approval,
        lifecycle=lifecycle,
        execution_phase=execution_phase,
        phase_operation_id=phase_operation_id,
        permission_operation_id=permission_operation_id,
        permission_snapshot=permission_snapshot,
        failure_pending=failure_pending,
        operation_lock=previous.operation_lock,
    )
    if not _session_binding_matches(session, binding):
        _revoke_admitted_session(session)
        return False
    with _ADMITTED_SESSION_BINDINGS_LOCK:
        if _ADMITTED_SESSION_BINDINGS.get(session) is not previous:
            _ADMITTED_SESSION_BINDINGS.pop(session, None)
            return False
        _ADMITTED_SESSION_BINDINGS[session] = binding
    return True


def _enter_restore_only(
    session: AdmittedSession,
    operation_id: str,
    snapshot: PermissionConfigurationSnapshot,
    *,
    failed: bool,
) -> bool:
    previous = _admitted_session_binding(session)
    if previous is None:
        return False
    try:
        session.enter_restore_only(operation_id, snapshot, failed=failed)
    except Exception:
        _revoke_admitted_session(session)
        return False
    return _advance_admitted_session_binding(
        session,
        previous,
        lifecycle=SessionLifecycle.RESTORE_ONLY,
        execution_phase=previous.execution_phase,
        phase_operation_id=previous.phase_operation_id,
        permission_operation_id=operation_id,
        permission_snapshot=snapshot,
        failure_pending=failed,
    )


def _finish_admitted_session(session: AdmittedSession, *, blocked: bool) -> bool:
    previous = _admitted_session_binding(session)
    if previous is None:
        return False
    try:
        session.finish(blocked=blocked)
    except Exception:
        _revoke_admitted_session(session)
        return False
    return _advance_admitted_session_binding(
        session,
        previous,
        lifecycle=SessionLifecycle.BLOCKED if blocked else SessionLifecycle.COMPLETED,
        execution_phase=previous.execution_phase,
        phase_operation_id=previous.phase_operation_id,
        permission_operation_id=previous.permission_operation_id,
        permission_snapshot=previous.permission_snapshot,
        failure_pending=previous.failure_pending,
    )


def _mark_session_failure_pending(session: AdmittedSession) -> bool:
    previous = _admitted_session_binding(session)
    if previous is None or previous.lifecycle is not SessionLifecycle.RESTORE_ONLY:
        return False
    session.failure_pending = True
    return _advance_admitted_session_binding(
        session,
        previous,
        lifecycle=previous.lifecycle,
        execution_phase=previous.execution_phase,
        phase_operation_id=previous.phase_operation_id,
        permission_operation_id=previous.permission_operation_id,
        permission_snapshot=previous.permission_snapshot,
        failure_pending=True,
    )


@dataclass(frozen=True)
class _Blocked:
    code: AdmissionCode


def _result(code: AdmissionCode, session: AdmittedSession | None = None) -> AdmissionResult:
    if code is AdmissionCode.ADMITTED and session is not None:
        return AdmissionResult(AdmissionStatus.ADMITTED, code, _ADMISSION_MESSAGES[code], session)
    return AdmissionResult(AdmissionStatus.BLOCKED, code, _ADMISSION_MESSAGES[code], None)


def _validate_host_artifact(
    authorization: SessionAuthorization,
    facts: HostArtifactFacts,
) -> bool:
    return (
        type(facts.apk_sha256) is str
        and facts.apk_sha256 == authorization.apk_sha256
        and facts.package_name == QUALIFICATION_PACKAGE == authorization.application_package
        and type(facts.package_name) is str
        and type(facts.version_code) is int
        and facts.version_code == authorization.version_code
        and facts.signature_verified is True
        and type(facts.signer_count) is int
        and facts.signer_count == 1
        and type(facts.certificate_sha256) is str
        and facts.certificate_sha256 == authorization.certificate_sha256
        and type(facts.source_revision) is str
        and facts.source_revision == authorization.source_revision
        and type(facts.declared_permissions) is frozenset
        and all(type(permission) is str for permission in facts.declared_permissions)
        and facts.declared_permissions == authorization.declared_permissions
        and _SHA256_RE.fullmatch(facts.apk_sha256) is not None
        and _SHA256_RE.fullmatch(facts.certificate_sha256) is not None
        and facts.package_name != ORDINARY_PACKAGE
    )


def _validate_approval(
    authorization: SessionAuthorization,
    approval: OwnerApproval,
    now: datetime,
) -> bool:
    return (
        _is_loaded_owner_approval(approval)
        and now.tzinfo is not None
        and now.utcoffset() == timezone.utc.utcoffset(now)
        and approval.authorization_sha256 == authorization.canonical_sha256
        and approval.owner_identity == authorization.owner_identity
        and authorization.issued_at <= approval.valid_from < approval.valid_until <= authorization.session_deadline
        and approval.valid_from <= now < approval.valid_until
        and authorization.issued_at <= now < authorization.session_deadline
    )


def _check_observation(
    authorization: SessionAuthorization,
    observation: FreshAdmissionObservation,
) -> AdmissionCode:
    serials = observation.connected_serials
    if serials is None:
        return AdmissionCode.OBSERVATION_UNAVAILABLE
    if type(serials) is not tuple or any(type(serial) is not str or not serial for serial in serials):
        return AdmissionCode.OBSERVATION_UNAVAILABLE
    if not serials:
        return AdmissionCode.NO_TARGET
    if len(serials) != 1:
        return AdmissionCode.AMBIGUOUS_TARGET
    if serials[0] != authorization.target_serial:
        return AdmissionCode.TARGET_MISMATCH

    api = observation.android_api_level
    if type(api) is not int or type(observation.abi) is not str or not observation.abi:
        return AdmissionCode.DEVICE_PROFILE_UNAVAILABLE
    if api < authorization.minimum_android_api:
        return AdmissionCode.OS_UNSUPPORTED
    if observation.abi != authorization.required_abi:
        return AdmissionCode.ABI_MISMATCH
    capabilities = observation.capabilities
    if (
        type(capabilities) is not frozenset
        or any(type(capability) is not str for capability in capabilities)
        or not authorization.required_capabilities.issubset(capabilities)
    ):
        return AdmissionCode.CAPABILITY_UNAVAILABLE

    installation = observation.installation
    if type(installation) is not InstallationObservation:
        return AdmissionCode.INSTALLATION_OBSERVATION_UNAVAILABLE
    if type(installation.status) is not InstallationStatus or installation.status is InstallationStatus.UNKNOWN:
        return AdmissionCode.INSTALLATION_OBSERVATION_UNAVAILABLE
    if installation.status is InstallationStatus.ABSENT:
        return AdmissionCode.QUALIFICATION_APP_ABSENT
    if (
        installation.status is not InstallationStatus.PRESENT
        or installation.package_name != authorization.application_package
        or type(installation.version_code) is not int
        or installation.version_code != authorization.version_code
        or installation.certificate_sha256 != authorization.certificate_sha256
    ):
        return AdmissionCode.QUALIFICATION_APP_INCOMPATIBLE

    if observation.foreground_package is None:
        return AdmissionCode.FOREGROUND_UNAVAILABLE
    if observation.foreground_package != authorization.application_package:
        return AdmissionCode.FOREGROUND_MISMATCH
    if observation.interference_free is None:
        return AdmissionCode.INTERFERENCE_UNKNOWN
    if observation.interference_free is not True:
        return AdmissionCode.INTERFERENCE_DETECTED
    available = observation.available_storage_bytes
    if type(available) is not int:
        return AdmissionCode.STORAGE_OBSERVATION_UNAVAILABLE
    if available < authorization.storage_reserve_bytes:
        return AdmissionCode.STORAGE_RESERVE_UNAVAILABLE
    return AdmissionCode.ADMITTED


def admit_session(
    authorization: SessionAuthorization,
    approval: OwnerApproval,
    artifact: HostArtifactFacts,
    transport: FreshAdmissionTransport,
    *,
    now: datetime | None = None,
) -> AdmissionResult:
    """Admit only an exact, read-only-observed fresh session.

    The authorization must come directly from ``load_authorization`` and remain
    unchanged. No-reset sessions remain blocked because this repository has no
    independent observer for the owner-approved Library, job, and cleanup
    baseline.
    """
    instant = now or datetime.now(timezone.utc)
    if not _is_loaded_session_authorization(authorization):
        return _result(AdmissionCode.APPROVAL_INVALID)
    if (
        isinstance(instant, datetime)
        and instant.tzinfo is not None
        and instant.utcoffset() == timezone.utc.utcoffset(instant)
        and instant >= authorization.session_deadline
    ):
        return _result(AdmissionCode.SESSION_EXPIRED)
    if not _validate_approval(authorization, approval, instant):
        return _result(AdmissionCode.APPROVAL_INVALID)
    try:
        pending = pending_for_device(
            authorization.target_serial,
            path=_DEVICE_SAFETY_PATH,
        )
    except SafetyStateError:
        return _result(AdmissionCode.DEVICE_SAFETY_STATE_UNAVAILABLE)
    if pending is not None:
        return _result(AdmissionCode.DEVICE_RESTORATION_PENDING)
    claim = _claim_approval_once(
        approval,
        authorization.authorization_id,
        authorization.canonical_sha256,
    )
    if claim is None:
        return _result(AdmissionCode.SESSION_STATE_UNAVAILABLE)
    if not claim:
        return _result(AdmissionCode.SESSION_ALREADY_USED)
    if authorization.state_mode is SessionStateMode.NO_RESET:
        return _result(AdmissionCode.NO_RESET_OBSERVATION_UNAVAILABLE)
    if not _validate_host_artifact(authorization, artifact):
        return _result(AdmissionCode.ARTIFACT_MISMATCH)
    try:
        observation = transport.observe_fresh_admission()
    except (KeyboardInterrupt, Exception):
        return _result(AdmissionCode.OBSERVATION_UNAVAILABLE)
    if not isinstance(observation, FreshAdmissionObservation):
        return _result(AdmissionCode.OBSERVATION_UNAVAILABLE)
    code = _check_observation(authorization, observation)
    if code is not AdmissionCode.ADMITTED:
        return _result(code)
    session = AdmittedSession(authorization, approval)
    if not _register_admitted_session(session):
        return _result(AdmissionCode.SESSION_STATE_UNAVAILABLE)
    return _result(AdmissionCode.ADMITTED, session)


def _first_add_scan_plan(
    authorization: SessionAuthorization,
) -> tuple[OperationAuthorization, ...] | None:
    """Validate the exact closed operation sequence for the first fresh scan."""
    if (
        authorization.state_mode is not SessionStateMode.FRESH
        or authorization.application_package != QUALIFICATION_PACKAGE
        or not authorization.operations
    ):
        return None
    operations = authorization.operations
    if any(
        operation.category in {
            OperationCategory.PERMISSION_APP_OP,
            OperationCategory.PERMISSION_APP_OP_RESTORE,
            OperationCategory.REINSTALL,
            OperationCategory.FORCE_STOP,
            OperationCategory.REFRESH,
            OperationCategory.SHELL,
            OperationCategory.PATH_MUTATION,
        }
        for operation in operations
    ):
        return None
    if len(operations) != 19:
        return None
    install_or_reset = operations[0]
    if install_or_reset.category not in {
        OperationCategory.INSTALL_ABSENT,
        OperationCategory.RESET_DATA,
    }:
        return None
    expected = [
        (OperationCategory.FIXTURE_STAGING, "stage_approved_fixture_set", "qualification", "action"),
        (OperationCategory.LAUNCH, "launch_qualification_main", "qualification", "action"),
    ]
    expected.extend(
        (OperationCategory.NAVIGATION, action, "qualification", "action")
        for action in (
            "accept_terms", "preferences", "skip_provider", "add_root", "storage_root",
            "open_qualification_root", "open_fixture_root", "select_folder", "add_and_scan",
        )
    )
    expected.extend((
        (OperationCategory.READ_ONLY, "scan_admission", "qualification", "observation"),
        (OperationCategory.NAVIGATION, "view_job", "qualification", "action"),
        (OperationCategory.READ_ONLY, "job_status", "qualification", "observation"),
        (OperationCategory.READ_ONLY, "terminal_scan", "qualification", "observation"),
        (OperationCategory.NAVIGATION, "library_navigation", "qualification", "action"),
        (OperationCategory.READ_ONLY, "fixture_library", "qualification", "observation"),
        (OperationCategory.FIXTURE_STAGING, "remove_session_owned_fixture_set", "cleanup", "action"),
    ))
    for operation, (category, value, phase, argument_name) in zip(
        operations[1:], expected, strict=True
    ):
        arguments = dict(operation.arguments)
        if (
            operation.category is not category
            or operation.phase != phase
            or arguments.get(argument_name) != value
        ):
            return None
    first_arguments = dict(install_or_reset.arguments)
    if install_or_reset.category is OperationCategory.INSTALL_ABSENT:
        if (
            install_or_reset.phase != "admission"
            or first_arguments.get("action") != "install_qualification_apk"
            or first_arguments.get("artifact_sha256") != authorization.apk_sha256
        ):
            return None
        foreground_after_setup = first_arguments.get("expected_foreground_package")
    elif (
        install_or_reset.phase != "admission"
        or first_arguments.get("action") != "clear_qualification_data"
        or first_arguments.get("expected_foreground_package") != QUALIFICATION_PACKAGE
    ):
        return None
    else:
        foreground_after_setup = first_arguments.get("expected_foreground_after")
    if (
        not foreground_after_setup
        or dict(operations[1].arguments).get("expected_foreground_package")
        != foreground_after_setup
        or dict(operations[2].arguments).get("expected_foreground_package")
        != foreground_after_setup
        or dict(operations[-1].arguments).get("expected_foreground_package")
        != QUALIFICATION_PACKAGE
    ):
        return None
    return operations


def _check_first_add_scan_observation(
    authorization: SessionAuthorization,
    observation: FreshAdmissionObservation,
    operations: tuple[OperationAuthorization, ...],
) -> AdmissionCode:
    """Accept only absent-plus-install or compatible-plus-reset observations."""
    code = _check_observation(authorization, observation)
    installation = observation.installation
    first = operations[0]
    if code is AdmissionCode.QUALIFICATION_APP_ABSENT:
        if (
            type(installation) is not InstallationObservation
            or installation.package_name is not None
            or installation.version_code is not None
            or installation.certificate_sha256 is not None
            or installation.artifact_sha256 is not None
        ):
            return AdmissionCode.INSTALLATION_OBSERVATION_UNAVAILABLE
        if first.category is not OperationCategory.INSTALL_ABSENT:
            return AdmissionCode.ADD_SCAN_PLAN_INVALID
        expected_foreground = dict(first.arguments).get("expected_foreground_package")
        if observation.foreground_package is None:
            return AdmissionCode.FOREGROUND_UNAVAILABLE
        if observation.foreground_package != expected_foreground:
            return AdmissionCode.FOREGROUND_MISMATCH
        if observation.interference_free is None:
            return AdmissionCode.INTERFERENCE_UNKNOWN
        if observation.interference_free is not True:
            return AdmissionCode.INTERFERENCE_DETECTED
        if type(observation.available_storage_bytes) is not int:
            return AdmissionCode.STORAGE_OBSERVATION_UNAVAILABLE
        if observation.available_storage_bytes < authorization.storage_reserve_bytes:
            return AdmissionCode.STORAGE_RESERVE_UNAVAILABLE
        return AdmissionCode.ADMITTED
    if code is AdmissionCode.ADMITTED:
        if (
            first.category is not OperationCategory.RESET_DATA
            or type(installation) is not InstallationObservation
            or installation.status is not InstallationStatus.PRESENT
            or installation.artifact_sha256 != authorization.apk_sha256
        ):
            return (
                AdmissionCode.QUALIFICATION_APP_INCOMPATIBLE
                if first.category is OperationCategory.RESET_DATA
                else AdmissionCode.ADD_SCAN_PLAN_INVALID
            )
        return AdmissionCode.ADMITTED
    return code


def admit_first_add_scan_session(
    authorization: SessionAuthorization,
    approval: OwnerApproval,
    artifact: HostArtifactFacts,
    transport: FreshAdmissionTransport,
    *,
    now: datetime | None = None,
) -> AdmissionResult:
    """Admit the first fresh Add & Scan plan for an absent or compatible app.

    This private path adds only the one-use installation/reset choice needed by
    the first scan. It shares the existing authorization loader, owner approval,
    safety-state registry, target profile checks, and admitted-session binding.
    Incompatible installations and no-reset requests remain blocked.
    """
    instant = now or datetime.now(timezone.utc)
    if not _is_loaded_session_authorization(authorization):
        return _result(AdmissionCode.APPROVAL_INVALID)
    if (
        not _now_is_utc(instant)
        or instant >= authorization.session_deadline
        or not _validate_approval(authorization, approval, instant)
    ):
        return _result(AdmissionCode.APPROVAL_INVALID)
    operations = _first_add_scan_plan(authorization)
    if operations is None:
        return _result(AdmissionCode.ADD_SCAN_PLAN_INVALID)
    if authorization.state_mode is SessionStateMode.NO_RESET:
        return _result(AdmissionCode.NO_RESET_OBSERVATION_UNAVAILABLE)
    if not _validate_host_artifact(authorization, artifact) or artifact.source_dirty is not False:
        return _result(AdmissionCode.ARTIFACT_MISMATCH)
    session_seconds = sum(
        operation.timeout_seconds for operation in operations
        if operation.phase != "cleanup"
    )
    cleanup_seconds = sum(
        operation.timeout_seconds for operation in operations
        if operation.phase == "cleanup"
    )
    if (
        instant + timedelta(seconds=session_seconds) > authorization.session_deadline
        or instant + timedelta(seconds=session_seconds + cleanup_seconds)
        > authorization.cleanup_deadline
        or instant + timedelta(seconds=session_seconds + cleanup_seconds)
        > approval.valid_until
        or cleanup_seconds > authorization.cleanup_reserve_seconds
    ):
        return _result(AdmissionCode.ADD_SCAN_PLAN_INVALID)
    try:
        pending = pending_for_device(
            authorization.target_serial,
            path=_DEVICE_SAFETY_PATH,
        )
    except SafetyStateError:
        return _result(AdmissionCode.DEVICE_SAFETY_STATE_UNAVAILABLE)
    if pending is not None:
        return _result(AdmissionCode.DEVICE_RESTORATION_PENDING)
    claim = _claim_approval_once(
        approval,
        authorization.authorization_id,
        authorization.canonical_sha256,
    )
    if claim is None:
        return _result(AdmissionCode.SESSION_STATE_UNAVAILABLE)
    if not claim:
        return _result(AdmissionCode.SESSION_ALREADY_USED)
    try:
        observation = transport.observe_fresh_admission()
    except (KeyboardInterrupt, Exception):
        return _result(AdmissionCode.OBSERVATION_UNAVAILABLE)
    if type(observation) is not FreshAdmissionObservation:
        return _result(AdmissionCode.OBSERVATION_UNAVAILABLE)
    code = _check_first_add_scan_observation(authorization, observation, operations)
    if code is not AdmissionCode.ADMITTED:
        return _result(code)
    session = AdmittedSession(authorization, approval)
    if not _register_admitted_session(session):
        return _result(AdmissionCode.SESSION_STATE_UNAVAILABLE)
    if not _register_first_add_scan_session(session, artifact):
        _revoke_admitted_session(session)
        with _FIRST_ADD_SCAN_BINDINGS_LOCK:
            _FIRST_ADD_SCAN_BINDINGS.pop(session, None)
            _FIRST_ADD_SCAN_CLAIMS.discard(session)
        return _result(AdmissionCode.SESSION_STATE_UNAVAILABLE)
    return _result(AdmissionCode.ADMITTED, session)


# Typed permission mutation and exact restoration.
class OperationStatus(str, Enum):
    RESTORE_REQUIRED = "RESTORE_REQUIRED"
    RESTORED = "RESTORED"
    NO_CHANGE = "NO_CHANGE"
    BLOCKED = "BLOCKED"


class OperationCode(str, Enum):
    PERMISSION_CHANGED = "PERMISSION_CHANGED_RESTORE_REQUIRED"
    PERMISSION_RESTORED = "PERMISSION_RESTORED"
    NO_CHANGE_REQUIRED = "PERMISSION_ALREADY_AT_REQUESTED_STATE"
    SESSION_FAILED_RESTORED = "SESSION_FAILED_STATE_RESTORED"
    OPERATION_UNAUTHORIZED = "OPERATION_NOT_AUTHORIZED"
    OPERATION_UNSUPPORTED = "OPERATION_CATEGORY_UNSUPPORTED"
    QUALIFICATION_PHASE_NOT_ENTERED = "QUALIFICATION_PHASE_NOT_ENTERED"
    OPERATION_IN_PROGRESS = "SESSION_OPERATION_ALREADY_IN_PROGRESS"
    SESSION_NOT_ACTIVE = "SESSION_NOT_ACTIVE"
    SESSION_EXPIRED = "SESSION_DEADLINE_EXPIRED"
    APPROVAL_EXPIRED = "OWNER_APPROVAL_EXPIRED"
    TARGET_IDENTITY_CHANGED = "TARGET_IDENTITY_CHANGED"
    FOREGROUND_IDENTITY_CHANGED = "FOREGROUND_IDENTITY_CHANGED"
    PACKAGE_IDENTITY_CHANGED = "PACKAGE_IDENTITY_CHANGED"
    PERMISSION_STATE_UNKNOWN = "PERMISSION_STATE_UNAVAILABLE"
    PERMISSION_BASELINE_MISMATCH = "PERMISSION_BASELINE_MISMATCH"
    DEVICE_RESTORATION_PENDING = "DEVICE_RESTORATION_PENDING"
    DEVICE_SAFETY_STATE_UNAVAILABLE = "DEVICE_SAFETY_STATE_UNAVAILABLE"
    MUTATION_FAILED = "PERMISSION_CHANGE_FAILED_RESTORE_REQUIRED"
    MUTATION_UNVERIFIED = "PERMISSION_CHANGE_UNVERIFIED_RESTORE_REQUIRED"
    RESTORATION_NOT_AUTHORIZED = "RESTORATION_NOT_AUTHORIZED"
    RESTORATION_WINDOW_CLOSED = "RESTORATION_WINDOW_CLOSED"
    RESTORATION_FAILED = "RESTORATION_FAILED_OWNER_INTERVENTION_REQUIRED"
    SESSION_TERMINAL = "SESSION_TERMINAL"


_OPERATION_MESSAGES = {
    OperationCode.PERMISSION_CHANGED: "Permission state changed; exact restoration is required",
    OperationCode.PERMISSION_RESTORED: "The captured permission state was restored and verified",
    OperationCode.NO_CHANGE_REQUIRED: "Permission already has the authorized state",
    OperationCode.SESSION_FAILED_RESTORED: "The captured permission state was restored after a session failure",
    OperationCode.OPERATION_UNAUTHORIZED: "Requested operation is not authorized",
    OperationCode.OPERATION_UNSUPPORTED: "Operation category is not supported by this implementation",
    OperationCode.QUALIFICATION_PHASE_NOT_ENTERED: "Trusted qualification phase has not been entered",
    OperationCode.OPERATION_IN_PROGRESS: "Another operation is already in progress for this session",
    OperationCode.SESSION_NOT_ACTIVE: "Session is not active for a product operation",
    OperationCode.SESSION_EXPIRED: "Session deadline has expired",
    OperationCode.APPROVAL_EXPIRED: "Owner approval window has expired",
    OperationCode.TARGET_IDENTITY_CHANGED: "Target identity could not be reverified",
    OperationCode.FOREGROUND_IDENTITY_CHANGED: "Foreground package could not be reverified",
    OperationCode.PACKAGE_IDENTITY_CHANGED: "Qualification package identity could not be reverified",
    OperationCode.PERMISSION_STATE_UNKNOWN: "Permission state could not be observed exactly",
    OperationCode.PERMISSION_BASELINE_MISMATCH: "Permission state differs from the owner-approved prior state",
    OperationCode.DEVICE_RESTORATION_PENDING: "An unresolved restoration blocks this device",
    OperationCode.DEVICE_SAFETY_STATE_UNAVAILABLE: "Owner-private device safety state is unavailable",
    OperationCode.MUTATION_FAILED: "Permission change failed; only restoration may be attempted",
    OperationCode.MUTATION_UNVERIFIED: "Permission change could not be verified; only restoration may be attempted",
    OperationCode.RESTORATION_NOT_AUTHORIZED: "Only the exact approved restoration operation may run",
    OperationCode.RESTORATION_WINDOW_CLOSED: "The approved restoration window is closed or too short",
    OperationCode.RESTORATION_FAILED: "Permission restoration could not be verified; owner intervention is required",
    OperationCode.SESSION_TERMINAL: "Session is terminal and cannot be resumed",
}


@dataclass(frozen=True)
class OperationResult:
    status: OperationStatus
    code: OperationCode
    message: str
    restoration_permitted: bool = False


class PermissionOperationTransport(Protocol):
    """Narrow typed boundary used by a simulated or separately reviewed adapter."""

    def verify_target(self, serial: str, target_ref: str, timeout_seconds: int) -> bool:
        """Recheck the exact selected target immediately before an operation."""

    def verify_foreground(self, package_name: str, timeout_seconds: int) -> bool:
        """Recheck the expected foreground package before changing its setting."""

    def verify_installed_package(
        self,
        serial: str,
        package_name: str,
        version_code: int,
        certificate_sha256: str,
        timeout_seconds: int,
    ) -> bool:
        """Recheck package-manager identity before permission restoration."""

    def read_permission_state(
        self,
        serial: str,
        package_name: str,
        permission_name: str,
        timeout_seconds: int,
    ) -> PermissionConfigurationSnapshot | None:
        """Observe effective access and exact stored state for the one app-op."""

    def set_permission_state(
        self,
        serial: str,
        package_name: str,
        permission_name: str,
        configuration: StoredAppOpConfiguration,
        timeout_seconds: int,
    ) -> None:
        """Set only the named permission's app-op mode; never retry it."""


class _OperationDeadlineExpired(Exception):
    """Signal that a bounded operation no longer has time for another call."""


class _CallBudget:
    """Apply one cumulative monotonic budget to every transport call."""

    def __init__(self, seconds: float) -> None:
        if seconds <= 0:
            raise _OperationDeadlineExpired
        self._deadline = time.monotonic() + seconds

    def call(self, operation):
        remaining = self._deadline - time.monotonic()
        if remaining < 1:
            raise _OperationDeadlineExpired
        timeout_seconds = int(remaining)
        try:
            result = operation(timeout_seconds)
        except (KeyboardInterrupt, Exception):
            if self._deadline - time.monotonic() <= 0:
                raise _OperationDeadlineExpired from None
            raise
        if self._deadline - time.monotonic() <= 0:
            raise _OperationDeadlineExpired
        return result


class _SessionIntegrityError(Exception):
    """Stop an operation when its admitted session no longer matches its binding."""


def _authorized_transport_call(session: AdmittedSession, budget: _CallBudget, operation):
    """Check the admitted object before and after each external transport call."""
    if _admitted_session_binding(session) is None:
        raise _SessionIntegrityError
    try:
        result = budget.call(operation)
    except (KeyboardInterrupt, Exception):
        if _admitted_session_binding(session) is None:
            raise _SessionIntegrityError from None
        raise
    if _admitted_session_binding(session) is None:
        raise _SessionIntegrityError
    return result


def _blocked(code: OperationCode, *, restoration_permitted: bool = False) -> OperationResult:
    return OperationResult(OperationStatus.BLOCKED, code, _OPERATION_MESSAGES[code], restoration_permitted)


def _now_is_utc(now: datetime) -> bool:
    return now.tzinfo is not None and now.utcoffset() == timedelta(0)


def _find_operation(session: AdmittedSession, operation_id: str) -> OperationAuthorization | None:
    return next(
        (operation for operation in session.authorization.operations if operation.operation_id == operation_id),
        None,
    )


def _effective_access(value: object) -> EffectiveAccess | None:
    if type(value) is not str:
        return None
    try:
        return EffectiveAccess(value)
    except ValueError:
        return None


def _pending_restoration_record(
    authorization: SessionAuthorization,
    approval: OwnerApproval,
    operation: OperationAuthorization,
    snapshot: PermissionConfigurationSnapshot,
) -> PendingRestoration:
    restoration = operation.restoration
    source_details = _loaded_owner_approval_source_details(approval)
    if (
        restoration is None
        or operation.permission_name != MANAGE_EXTERNAL_STORAGE
        or operation.package_name != QUALIFICATION_PACKAGE
        or operation.target_serial != authorization.target_serial
        or not is_exact_snapshot(snapshot)
        or source_details is None
    ):
        raise ValueError("invalid approved restoration record")
    sidecar_path, directory_identity, file_identity, sidecar_sha256 = source_details
    return PendingRestoration(
        authorization_id=authorization.authorization_id,
        authorization_sha256=authorization.canonical_sha256,
        operation_id=operation.operation_id,
        restoration_operation_id=restoration.operation_id,
        target_serial=operation.target_serial,
        package_name=operation.package_name,
        permission_name=MANAGE_EXTERNAL_STORAGE,
        snapshot=snapshot,
        approval_sidecar_path=sidecar_path,
        approval_directory_identity=directory_identity,
        approval_file_identity=file_identity,
        approval_sidecar_sha256=sidecar_sha256,
    )


def _restoration_approval_context(
    authorization: SessionAuthorization,
    pending: PendingRestoration,
) -> _RestorationApprovalContext:
    """Bind the original sidecar to the exact approved pending snapshot."""
    if (
        not _is_loaded_session_authorization(authorization)
        or not _record_is_valid(pending)
        or pending.authorization_id != authorization.authorization_id
        or pending.authorization_sha256 != authorization.canonical_sha256
        or pending.target_serial != authorization.target_serial
    ):
        raise ApprovalError(ApprovalErrorCode.INVALID_VALUE)
    operation = next(
        (item for item in authorization.operations if item.operation_id == pending.operation_id),
        None,
    )
    restoration = operation.restoration if operation is not None else None
    if (
        operation is None
        or operation.category is not OperationCategory.PERMISSION_APP_OP
        or operation.phase != SessionExecutionPhase.QUALIFICATION.value
        or operation.target_serial != pending.target_serial
        or operation.package_name != QUALIFICATION_PACKAGE
        or operation.permission_name != MANAGE_EXTERNAL_STORAGE
        or restoration is None
        or restoration.operation_id != pending.restoration_operation_id
        or restoration.target_serial != pending.target_serial
        or restoration.package_name != QUALIFICATION_PACKAGE
        or restoration.permission_name != MANAGE_EXTERNAL_STORAGE
        or restoration.deadline > authorization.cleanup_deadline
    ):
        raise ApprovalError(ApprovalErrorCode.INVALID_VALUE)
    return _RestorationApprovalContext(
        authorization_id=pending.authorization_id,
        authorization_sha256=pending.authorization_sha256,
        target_serial=pending.target_serial,
        operation_id=pending.operation_id,
        restoration_operation_id=pending.restoration_operation_id,
        package_name=pending.package_name,
        permission_name=pending.permission_name,
        snapshot_sha256=_snapshot_sha256(pending.snapshot),
        sidecar_path=pending.approval_sidecar_path,
        sidecar_directory_identity=pending.approval_directory_identity,
        sidecar_file_identity=pending.approval_file_identity,
        sidecar_sha256=pending.approval_sidecar_sha256,
    )


def load_pending_restoration_approval(
    authorization: SessionAuthorization,
    *,
    now: datetime | None = None,
) -> OwnerApproval:
    """Load an owner approval with authority limited to one pending restoration."""
    if not _is_loaded_session_authorization(authorization):
        raise ApprovalError(ApprovalErrorCode.INVALID_VALUE)
    try:
        pending = pending_for_device(
            authorization.target_serial,
            path=_DEVICE_SAFETY_PATH,
        )
    except SafetyStateError:
        raise ApprovalError(ApprovalErrorCode.INVALID_VALUE) from None
    if pending is None:
        raise ApprovalError(ApprovalErrorCode.INVALID_VALUE)
    context = _restoration_approval_context(authorization, pending)
    return load_owner_approval_for_restoration(
        context.sidecar_path,
        authorization,
        context=context,
        now=now,
    )


def _stop_session(session: AdmittedSession) -> None:
    binding = _admitted_session_binding(session)
    if binding is not None and binding.lifecycle in {
        SessionLifecycle.ACTIVE,
        SessionLifecycle.RESTORE_ONLY,
    }:
        _finish_admitted_session(session, blocked=True)


class PermissionOperationExecutor:
    """Execute the one supported permission mutation and its exact restoration."""

    def __init__(self, session: AdmittedSession, transport: PermissionOperationTransport) -> None:
        self._session = session
        self._transport = transport

    def enter_qualification_phase(self, operation_id: str) -> bool:
        """Record the explicit trusted phase transition for an approved operation."""
        return _enter_qualification_phase(self._session, operation_id)

    def execute(self, operation_id: str, *, now: datetime | None = None) -> OperationResult:
        binding = _admitted_session_binding(self._session)
        if binding is None:
            return _blocked(OperationCode.OPERATION_UNAUTHORIZED)
        if not binding.operation_lock.acquire(blocking=False):
            return _blocked(OperationCode.OPERATION_IN_PROGRESS)
        try:
            if _admitted_session_binding(self._session) is None:
                return _blocked(OperationCode.OPERATION_UNAUTHORIZED)
            return self._execute_reserved(operation_id, now=now)
        finally:
            binding.operation_lock.release()

    def _execute_reserved(self, operation_id: str, *, now: datetime | None = None) -> OperationResult:
        """Run one authorized permission change, snapshotting before mutation."""
        if _admitted_session_binding(self._session) is None:
            return _blocked(OperationCode.OPERATION_UNAUTHORIZED)
        instant = now or datetime.now(timezone.utc)
        if self._session.lifecycle is not SessionLifecycle.ACTIVE:
            return _blocked(OperationCode.SESSION_NOT_ACTIVE, restoration_permitted=self._session.lifecycle is SessionLifecycle.RESTORE_ONLY)
        operation = _find_operation(self._session, operation_id)
        if operation is None:
            _stop_session(self._session)
            return _blocked(OperationCode.OPERATION_UNAUTHORIZED)
        if (
            operation.category is not OperationCategory.PERMISSION_APP_OP
            or operation.permission_name != MANAGE_EXTERNAL_STORAGE
            or operation.package_name != QUALIFICATION_PACKAGE
            or operation.target_serial != self._session.authorization.target_serial
        ):
            _stop_session(self._session)
            return _blocked(OperationCode.OPERATION_UNSUPPORTED)
        binding = _admitted_session_binding(self._session)
        if (
            binding is None
            or binding.execution_phase is not SessionExecutionPhase.QUALIFICATION
            or binding.phase_operation_id != operation_id
            or operation.phase != SessionExecutionPhase.QUALIFICATION.value
        ):
            return _blocked(OperationCode.QUALIFICATION_PHASE_NOT_ENTERED)
        if not _now_is_utc(instant):
            _stop_session(self._session)
            return _blocked(OperationCode.SESSION_EXPIRED)
        authorization = self._session.authorization
        approval = self._session.approval
        if instant >= authorization.session_deadline or instant + timedelta(seconds=operation.timeout_seconds) > authorization.session_deadline:
            _stop_session(self._session)
            return _blocked(OperationCode.SESSION_EXPIRED)
        if not approval.valid_from <= instant < approval.valid_until:
            _stop_session(self._session)
            return _blocked(OperationCode.APPROVAL_EXPIRED)

        budget_seconds = min(
            float(operation.timeout_seconds),
            (approval.valid_until - instant).total_seconds(),
        )
        try:
            budget = _CallBudget(budget_seconds)
        except _OperationDeadlineExpired:
            _stop_session(self._session)
            return _blocked(OperationCode.APPROVAL_EXPIRED)

        try:
            pending = pending_for_device(
                operation.target_serial,
                path=_DEVICE_SAFETY_PATH,
            )
        except SafetyStateError:
            _stop_session(self._session)
            return _blocked(OperationCode.DEVICE_SAFETY_STATE_UNAVAILABLE)
        if pending is not None:
            _stop_session(self._session)
            return _blocked(OperationCode.DEVICE_RESTORATION_PENDING)

        try:
            if not _authorized_transport_call(
                self._session,
                budget,
                lambda timeout: self._transport.verify_target(
                    operation.target_serial,
                    authorization.target_ref,
                    timeout,
                )
            ):
                _stop_session(self._session)
                return _blocked(OperationCode.TARGET_IDENTITY_CHANGED)
            if not _authorized_transport_call(
                self._session,
                budget,
                lambda timeout: self._transport.verify_foreground(operation.package_name, timeout)
            ):
                _stop_session(self._session)
                return _blocked(OperationCode.FOREGROUND_IDENTITY_CHANGED)
            if not _authorized_transport_call(
                self._session,
                budget,
                lambda timeout: self._transport.verify_installed_package(
                    operation.target_serial,
                    operation.package_name,
                    authorization.version_code,
                    authorization.certificate_sha256,
                    timeout,
                )
            ):
                _stop_session(self._session)
                return _blocked(OperationCode.PACKAGE_IDENTITY_CHANGED)
            previous_state = _authorized_transport_call(
                self._session,
                budget,
                lambda timeout: self._transport.read_permission_state(
                    operation.target_serial,
                    operation.package_name,
                    operation.permission_name or "",
                    timeout,
                )
            )
        except _SessionIntegrityError:
            return _blocked(OperationCode.OPERATION_UNAUTHORIZED)
        except _OperationDeadlineExpired:
            _stop_session(self._session)
            return _blocked(OperationCode.SESSION_EXPIRED)
        except (KeyboardInterrupt, Exception):
            _stop_session(self._session)
            return _blocked(OperationCode.PERMISSION_STATE_UNKNOWN)
        if not is_exact_snapshot(previous_state):
            _stop_session(self._session)
            return _blocked(OperationCode.PERMISSION_STATE_UNKNOWN)
        expected_prior = _effective_access(operation.expected_prior_state)
        desired_access = _effective_access(operation.desired_state)
        if expected_prior is None or desired_access is None:
            _stop_session(self._session)
            return _blocked(OperationCode.OPERATION_UNAUTHORIZED)
        if previous_state.effective_access is not expected_prior:
            _stop_session(self._session)
            return _blocked(OperationCode.PERMISSION_BASELINE_MISMATCH)
        if previous_state.effective_access is desired_access:
            if not _finish_admitted_session(self._session, blocked=False):
                return _blocked(OperationCode.OPERATION_UNAUTHORIZED)
            return OperationResult(
                OperationStatus.NO_CHANGE,
                OperationCode.NO_CHANGE_REQUIRED,
                _OPERATION_MESSAGES[OperationCode.NO_CHANGE_REQUIRED],
            )

        if not _enter_restore_only(
            self._session,
            operation.operation_id,
            previous_state,
            failed=False,
        ):
            return _blocked(OperationCode.OPERATION_UNAUTHORIZED)
        restoration = operation.restoration
        if restoration is None:
            _stop_session(self._session)
            return _blocked(OperationCode.RESTORATION_NOT_AUTHORIZED)
        try:
            pending_record = _pending_restoration_record(
                self._session.authorization,
                self._session.approval,
                operation,
                previous_state,
            )
        except ValueError:
            _stop_session(self._session)
            return _blocked(OperationCode.OPERATION_UNAUTHORIZED)
        try:
            persist_pending(pending_record, path=_DEVICE_SAFETY_PATH)
        except DeviceRestorationPending:
            _stop_session(self._session)
            return _blocked(OperationCode.DEVICE_RESTORATION_PENDING)
        except SafetyStateError:
            _stop_session(self._session)
            return _blocked(OperationCode.DEVICE_SAFETY_STATE_UNAVAILABLE)

        target_configuration = configuration_for_access(desired_access)
        target_snapshot = PermissionConfigurationSnapshot(
            effective_access=desired_access,
            stored_configuration=target_configuration,
        )
        try:
            _authorized_transport_call(
                self._session,
                budget,
                lambda timeout: self._transport.set_permission_state(
                    operation.target_serial,
                    operation.package_name,
                    MANAGE_EXTERNAL_STORAGE,
                    target_configuration,
                    timeout,
                )
            )
        except _SessionIntegrityError:
            return _blocked(OperationCode.OPERATION_UNAUTHORIZED)
        except _OperationDeadlineExpired:
            return self._restore_after_uncertain_mutation(
                operation,
                cleanup_now=instant if now is not None else None,
            )
        except BaseException:
            return self._restore_after_uncertain_mutation(
                operation,
                cleanup_now=instant if now is not None else None,
            )
        try:
            resulting_state = _authorized_transport_call(
                self._session,
                budget,
                lambda timeout: self._transport.read_permission_state(
                    operation.target_serial,
                    operation.package_name,
                    MANAGE_EXTERNAL_STORAGE,
                    timeout,
                )
            )
        except _SessionIntegrityError:
            return _blocked(OperationCode.OPERATION_UNAUTHORIZED)
        except _OperationDeadlineExpired:
            return self._restore_after_uncertain_mutation(
                operation,
                cleanup_now=instant if now is not None else None,
            )
        except BaseException:
            return self._restore_after_uncertain_mutation(
                operation,
                cleanup_now=instant if now is not None else None,
            )
        if resulting_state != target_snapshot:
            return self._restore_after_uncertain_mutation(
                operation,
                cleanup_now=instant if now is not None else None,
            )
        return OperationResult(
            OperationStatus.RESTORE_REQUIRED,
            OperationCode.PERMISSION_CHANGED,
            _OPERATION_MESSAGES[OperationCode.PERMISSION_CHANGED],
            restoration_permitted=True,
        )

    def _restore_after_uncertain_mutation(
        self,
        operation: OperationAuthorization,
        *,
        cleanup_now: datetime | None,
    ) -> OperationResult:
        """Attempt the one approved restoration after an uncertain setter result."""
        if not _mark_session_failure_pending(self._session):
            return _blocked(OperationCode.OPERATION_UNAUTHORIZED)
        restoration = operation.restoration
        if restoration is None:
            _stop_session(self._session)
            return _blocked(OperationCode.RESTORATION_NOT_AUTHORIZED)
        return self._restore_reserved(restoration.operation_id, now=cleanup_now)

    def restore(self, restoration_operation_id: str, *, now: datetime | None = None) -> OperationResult:
        binding = _admitted_session_binding(self._session)
        if binding is None:
            return _blocked(OperationCode.OPERATION_UNAUTHORIZED)
        if not binding.operation_lock.acquire(blocking=False):
            return _blocked(OperationCode.OPERATION_IN_PROGRESS)
        try:
            if _admitted_session_binding(self._session) is None:
                return _blocked(OperationCode.OPERATION_UNAUTHORIZED)
            return self._restore_reserved(restoration_operation_id, now=now)
        finally:
            binding.operation_lock.release()

    def _restore_reserved(
        self,
        restoration_operation_id: str,
        *,
        now: datetime | None = None,
    ) -> OperationResult:
        """Restore only the captured state, once, within its separate deadline."""
        if _admitted_session_binding(self._session) is None:
            return _blocked(OperationCode.OPERATION_UNAUTHORIZED)
        if self._session.lifecycle is SessionLifecycle.BLOCKED or self._session.lifecycle is SessionLifecycle.COMPLETED:
            return _blocked(OperationCode.SESSION_TERMINAL)
        if self._session.lifecycle is not SessionLifecycle.RESTORE_ONLY:
            _stop_session(self._session)
            return _blocked(OperationCode.RESTORATION_NOT_AUTHORIZED)
        operation = _find_operation(self._session, self._session.permission_operation_id or "")
        restoration = operation.restoration if operation is not None else None
        if (
            operation is None
            or operation.category is not OperationCategory.PERMISSION_APP_OP
            or operation.permission_name != MANAGE_EXTERNAL_STORAGE
            or operation.package_name != QUALIFICATION_PACKAGE
            or restoration is None
            or restoration.permission_name != MANAGE_EXTERNAL_STORAGE
            or restoration.package_name != QUALIFICATION_PACKAGE
            or restoration.target_serial != self._session.authorization.target_serial
            or not is_exact_snapshot(self._session.permission_snapshot)
        ):
            _stop_session(self._session)
            return _blocked(OperationCode.RESTORATION_NOT_AUTHORIZED)
        if type(restoration_operation_id) is not str or restoration.operation_id != restoration_operation_id:
            return _blocked(OperationCode.RESTORATION_NOT_AUTHORIZED)
        try:
            pending_record = _pending_restoration_record(
                self._session.authorization,
                self._session.approval,
                operation,
                self._session.permission_snapshot,
            )
        except ValueError:
            _stop_session(self._session)
            return _blocked(OperationCode.OPERATION_UNAUTHORIZED)
        try:
            pending = pending_for_device(
                restoration.target_serial,
                path=_DEVICE_SAFETY_PATH,
            )
        except SafetyStateError:
            _stop_session(self._session)
            return _blocked(OperationCode.DEVICE_SAFETY_STATE_UNAVAILABLE)
        if pending != pending_record:
            _stop_session(self._session)
            return _blocked(OperationCode.DEVICE_RESTORATION_PENDING)
        instant = now or datetime.now(timezone.utc)
        if not _now_is_utc(instant):
            _stop_session(self._session)
            return _blocked(OperationCode.RESTORATION_WINDOW_CLOSED)
        timeout = restoration.timeout_seconds
        if (
            instant >= restoration.deadline
            or instant + timedelta(seconds=timeout) > restoration.deadline
            or instant + timedelta(seconds=timeout) > self._session.authorization.cleanup_deadline
            or instant >= self._session.authorization.cleanup_deadline
            or restoration.deadline > self._session.authorization.cleanup_deadline
        ):
            _stop_session(self._session)
            return _blocked(OperationCode.RESTORATION_WINDOW_CLOSED)
        budget_seconds = min(
            float(timeout),
            (restoration.deadline - instant).total_seconds(),
            (self._session.authorization.cleanup_deadline - instant).total_seconds(),
        )
        try:
            budget = _CallBudget(budget_seconds)
        except _OperationDeadlineExpired:
            _stop_session(self._session)
            return _blocked(OperationCode.RESTORATION_WINDOW_CLOSED)
        authorization = self._session.authorization
        try:
            if not _authorized_transport_call(
                self._session,
                budget,
                lambda remaining: self._transport.verify_target(
                    restoration.target_serial,
                    authorization.target_ref,
                    remaining,
                )
            ):
                _stop_session(self._session)
                return _blocked(OperationCode.TARGET_IDENTITY_CHANGED)
            if not _authorized_transport_call(
                self._session,
                budget,
                lambda remaining: self._transport.verify_installed_package(
                    restoration.target_serial,
                    restoration.package_name,
                    authorization.version_code,
                    authorization.certificate_sha256,
                    remaining,
                )
            ):
                _stop_session(self._session)
                return _blocked(OperationCode.PACKAGE_IDENTITY_CHANGED)
        except _SessionIntegrityError:
            return _blocked(OperationCode.OPERATION_UNAUTHORIZED)
        except _OperationDeadlineExpired:
            _stop_session(self._session)
            return _blocked(OperationCode.RESTORATION_WINDOW_CLOSED)
        except (KeyboardInterrupt, Exception):
            _stop_session(self._session)
            return _blocked(OperationCode.RESTORATION_FAILED)

        snapshot = self._session.permission_snapshot
        current_state: PermissionConfigurationSnapshot | None = None
        try:
            observed = _authorized_transport_call(
                self._session,
                budget,
                lambda remaining: self._transport.read_permission_state(
                    restoration.target_serial,
                    restoration.package_name,
                    MANAGE_EXTERNAL_STORAGE,
                    remaining,
                ),
            )
            if is_exact_snapshot(observed):
                current_state = observed
        except _SessionIntegrityError:
            return _blocked(OperationCode.OPERATION_UNAUTHORIZED)
        except (_OperationDeadlineExpired, KeyboardInterrupt, Exception):
            current_state = None

        if current_state != snapshot:
            try:
                _authorized_transport_call(
                    self._session,
                    budget,
                    lambda remaining: self._transport.set_permission_state(
                        restoration.target_serial,
                        restoration.package_name,
                        MANAGE_EXTERNAL_STORAGE,
                        snapshot.stored_configuration,
                        remaining,
                    )
                )
            except _SessionIntegrityError:
                return _blocked(OperationCode.OPERATION_UNAUTHORIZED)
            except (_OperationDeadlineExpired, KeyboardInterrupt, Exception):
                pass
        try:
            restored_state = _authorized_transport_call(
                self._session,
                budget,
                lambda remaining: self._transport.read_permission_state(
                    restoration.target_serial,
                    restoration.package_name,
                    MANAGE_EXTERNAL_STORAGE,
                    remaining,
                )
            )
        except _SessionIntegrityError:
            return _blocked(OperationCode.OPERATION_UNAUTHORIZED)
        except _OperationDeadlineExpired:
            _stop_session(self._session)
            return _blocked(OperationCode.RESTORATION_FAILED)
        except (KeyboardInterrupt, Exception):
            _stop_session(self._session)
            return _blocked(OperationCode.RESTORATION_FAILED)
        if not is_exact_snapshot(restored_state) or restored_state != snapshot:
            _stop_session(self._session)
            return _blocked(OperationCode.RESTORATION_FAILED)

        try:
            clear_pending(pending_record, path=_DEVICE_SAFETY_PATH)
        except SafetyStateError:
            _stop_session(self._session)
            return _blocked(OperationCode.DEVICE_SAFETY_STATE_UNAVAILABLE)

        failed_session = self._session.failure_pending
        if not _finish_admitted_session(self._session, blocked=failed_session):
            return _blocked(OperationCode.OPERATION_UNAUTHORIZED)
        if failed_session:
            return _blocked(OperationCode.SESSION_FAILED_RESTORED)
        return OperationResult(
            OperationStatus.RESTORED,
            OperationCode.PERMISSION_RESTORED,
            _OPERATION_MESSAGES[OperationCode.PERMISSION_RESTORED],
        )


def recover_pending_restoration(
    authorization: SessionAuthorization,
    approval: OwnerApproval,
    restoration_operation_id: str,
    transport: PermissionOperationTransport,
    *,
    now: datetime | None = None,
) -> OperationResult:
    """Restore only one exact pending snapshot under its owner sidecar.

    A durable one-shot claim precedes the manual restoration setter. Later
    recovery calls can verify an already-restored snapshot, but cannot call
    that setter again or resume the qualification session.
    """
    instant = now or datetime.now(timezone.utc)
    if not _is_loaded_session_authorization(authorization):
        return _blocked(OperationCode.OPERATION_UNAUTHORIZED)
    try:
        pending = pending_for_device(
            authorization.target_serial,
            path=_DEVICE_SAFETY_PATH,
        )
    except SafetyStateError:
        return _blocked(OperationCode.DEVICE_SAFETY_STATE_UNAVAILABLE)
    if pending is None:
        return _blocked(OperationCode.RESTORATION_NOT_AUTHORIZED)
    try:
        context = _restoration_approval_context(authorization, pending)
    except ApprovalError:
        return _blocked(OperationCode.OPERATION_UNAUTHORIZED)
    if not _is_loaded_restoration_approval(approval, context):
        return _blocked(OperationCode.OPERATION_UNAUTHORIZED)
    operation = next(
        (
            item
            for item in authorization.operations
            if item.operation_id == pending.operation_id
        ),
        None,
    )
    restoration = operation.restoration if operation is not None else None
    if (
        type(restoration_operation_id) is not str
        or operation is None
        or operation.category is not OperationCategory.PERMISSION_APP_OP
        or operation.phase != SessionExecutionPhase.QUALIFICATION.value
        or operation.permission_name != MANAGE_EXTERNAL_STORAGE
        or operation.package_name != QUALIFICATION_PACKAGE
        or operation.target_serial != authorization.target_serial
        or restoration is None
        or restoration.operation_id != restoration_operation_id
        or pending.operation_id != operation.operation_id
        or pending.restoration_operation_id != restoration.operation_id
        or pending.target_serial != restoration.target_serial
        or pending.package_name != QUALIFICATION_PACKAGE
        or pending.permission_name != MANAGE_EXTERNAL_STORAGE
        or not is_exact_snapshot(pending.snapshot)
        or context.snapshot_sha256 != _snapshot_sha256(pending.snapshot)
    ):
        return _blocked(OperationCode.RESTORATION_NOT_AUTHORIZED)
    if not _now_is_utc(instant):
        return _blocked(OperationCode.RESTORATION_WINDOW_CLOSED)
    timeout = restoration.timeout_seconds
    if (
        instant >= restoration.deadline
        or instant + timedelta(seconds=timeout) > restoration.deadline
        or instant + timedelta(seconds=timeout) > authorization.cleanup_deadline
        or restoration.deadline > authorization.cleanup_deadline
    ):
        return _blocked(OperationCode.RESTORATION_WINDOW_CLOSED)
    try:
        budget = _CallBudget(
            min(
                float(timeout),
                (restoration.deadline - instant).total_seconds(),
                (authorization.cleanup_deadline - instant).total_seconds(),
            )
        )
    except _OperationDeadlineExpired:
        return _blocked(OperationCode.RESTORATION_WINDOW_CLOSED)

    def call(operation_call):
        if (
            not _is_loaded_session_authorization(authorization)
            or not _is_loaded_restoration_approval(approval, context)
        ):
            raise _SessionIntegrityError
        try:
            result = budget.call(operation_call)
        except (KeyboardInterrupt, Exception):
            if (
                not _is_loaded_session_authorization(authorization)
                or not _is_loaded_restoration_approval(approval, context)
            ):
                raise _SessionIntegrityError from None
            raise
        if (
            not _is_loaded_session_authorization(authorization)
            or not _is_loaded_restoration_approval(approval, context)
        ):
            raise _SessionIntegrityError
        return result

    try:
        if not call(
            lambda remaining: transport.verify_target(
                restoration.target_serial,
                authorization.target_ref,
                remaining,
            )
        ):
            return _blocked(OperationCode.TARGET_IDENTITY_CHANGED)
        if not call(
            lambda remaining: transport.verify_installed_package(
                restoration.target_serial,
                restoration.package_name,
                authorization.version_code,
                authorization.certificate_sha256,
                remaining,
            )
        ):
            return _blocked(OperationCode.PACKAGE_IDENTITY_CHANGED)
    except _SessionIntegrityError:
        return _blocked(OperationCode.OPERATION_UNAUTHORIZED)
    except _OperationDeadlineExpired:
        return _blocked(OperationCode.RESTORATION_WINDOW_CLOSED)
    except (KeyboardInterrupt, Exception):
        return _blocked(OperationCode.RESTORATION_FAILED)

    current_state: PermissionConfigurationSnapshot | None = None
    try:
        observed = call(
            lambda remaining: transport.read_permission_state(
                restoration.target_serial,
                restoration.package_name,
                MANAGE_EXTERNAL_STORAGE,
                remaining,
            )
        )
        if is_exact_snapshot(observed):
            current_state = observed
    except _SessionIntegrityError:
        return _blocked(OperationCode.OPERATION_UNAUTHORIZED)
    except (_OperationDeadlineExpired, KeyboardInterrupt, Exception):
        current_state = None

    if current_state == pending.snapshot:
        try:
            clear_pending(pending, path=_DEVICE_SAFETY_PATH)
        except SafetyStateError:
            return _blocked(OperationCode.DEVICE_SAFETY_STATE_UNAVAILABLE)
        return OperationResult(
            OperationStatus.RESTORED,
            OperationCode.PERMISSION_RESTORED,
            _OPERATION_MESSAGES[OperationCode.PERMISSION_RESTORED],
        )

    if pending.recovery_setter_attempted:
        return _blocked(OperationCode.RESTORATION_FAILED)
    try:
        claimed_pending = _claim_recovery_setter(
            pending,
            path=_DEVICE_SAFETY_PATH,
        )
    except SafetyStateError:
        return _blocked(OperationCode.DEVICE_SAFETY_STATE_UNAVAILABLE)
    try:
        call(
            lambda remaining: transport.set_permission_state(
                restoration.target_serial,
                restoration.package_name,
                MANAGE_EXTERNAL_STORAGE,
                claimed_pending.snapshot.stored_configuration,
                remaining,
            )
        )
    except _SessionIntegrityError:
        return _blocked(OperationCode.OPERATION_UNAUTHORIZED)
    except (_OperationDeadlineExpired, KeyboardInterrupt, Exception):
        pass

    try:
        restored_state = call(
            lambda remaining: transport.read_permission_state(
                restoration.target_serial,
                restoration.package_name,
                MANAGE_EXTERNAL_STORAGE,
                remaining,
            )
        )
    except _SessionIntegrityError:
        return _blocked(OperationCode.OPERATION_UNAUTHORIZED)
    except (_OperationDeadlineExpired, KeyboardInterrupt, Exception):
        return _blocked(OperationCode.RESTORATION_FAILED)
    if not is_exact_snapshot(restored_state) or restored_state != pending.snapshot:
        return _blocked(OperationCode.RESTORATION_FAILED)
    try:
        clear_pending(claimed_pending, path=_DEVICE_SAFETY_PATH)
    except SafetyStateError:
        return _blocked(OperationCode.DEVICE_SAFETY_STATE_UNAVAILABLE)
    return OperationResult(
        OperationStatus.RESTORED,
        OperationCode.PERMISSION_RESTORED,
        _OPERATION_MESSAGES[OperationCode.PERMISSION_RESTORED],
    )


# The first-session Add & Scan adapter is intentionally private. It accepts an
# injected typed transport for host simulation, but no public CLI or production
# device transport constructs it.
@dataclass(frozen=True)
class FixtureTransferPlan:
    """Opaque aggregate facts for the one approved fixture set."""

    fixture_manifest_sha256: str
    file_count: int
    byte_count: int
    content_sha256: str


@dataclass(frozen=True)
class FixtureStageReceipt:
    """Receipt proving which session-owned fixture set was staged."""

    session_id: str
    fixture_manifest_sha256: str
    file_count: int
    byte_count: int
    content_sha256: str


QUALIFICATION_CAPTURE_SLOT = "qualification_ui_capture"


@dataclass(frozen=True)
class FixtureCleanupReceipt:
    """Exact cleanup observation for the session-owned fixture set."""

    session_id: str
    fixture_manifest_sha256: str
    removed_file_count: int
    remaining_file_count: int


class AddScanExecutionStatus(str, Enum):
    BLOCKED = "BLOCKED"


_ADD_SCAN_JOB_STATUS_POLL_INTERVAL_SECONDS = 0.25


@dataclass(frozen=True)
class AddScanScopeExtension:
    """A bounded outcome that requires owner validation outside host tests."""

    area: str
    reason: str
    required_outcome: str


@dataclass(frozen=True)
class AddScanExecutionResult:
    """Safe outcome of one simulated first Add & Scan session."""

    status: AddScanExecutionStatus
    workflow_completed: bool
    scan_admission: str | None
    job_status: str | None
    terminal_scan_status: str | None
    fixture_result_indices: tuple[int, ...]
    cleanup_status: str
    blocker: str
    scope_extensions: tuple[AddScanScopeExtension, ...]
    execution_manifest_sha256: str | None = None


class _AddScanStop(Exception):
    """Stop before another product operation and retain a bounded reason."""

    def __init__(self, reason: str, *, interrupted: bool = False) -> None:
        self.reason = reason
        self.interrupted = interrupted
        super().__init__(reason)


class _AddScanTransport(Protocol):
    """Typed, injected boundary for the private host-simulation adapter.

    Accessibility captures are temporary UI evidence and must be stored outside
    ``/sdcard/ArgusQualification/fixtures``. Implementations must never stage
    capture files, logs, or working artifacts into the approved fixture root.
    """

    def verify_target(self, serial: str, target_ref: str, timeout_seconds: int) -> bool: ...
    def verify_foreground(self, package_name: str, timeout_seconds: int) -> bool: ...
    def observe_installed_package(
        self, serial: str, package_name: str, version_code: int,
        certificate_sha256: str, timeout_seconds: int,
    ) -> InstallationObservation: ...
    def install_qualification_artifact(
        self, serial: str, package_name: str, apk_sha256: str,
        certificate_sha256: str, version_code: int, timeout_seconds: int,
    ) -> None: ...
    def reset_qualification_data(
        self, serial: str, package_name: str, timeout_seconds: int,
    ) -> bool: ...
    def stage_approved_fixture_set(
        self, serial: str, package_name: str, session_id: str,
        fixture_plan: FixtureTransferPlan, destination: str, timeout_seconds: int,
    ) -> FixtureStageReceipt: ...
    def launch_qualification_main(
        self, serial: str, package_name: str, timeout_seconds: int,
    ) -> None: ...
    def capture_accessibility(
        self, serial: str, package_name: str, session_id: str,
        capture_slot: str, timeout_seconds: int,
    ) -> str: ...
    def tap_accessibility_control(
        self, serial: str, package_name: str, action: str,
        bounds: tuple[int, int, int, int], timeout_seconds: int,
    ) -> None: ...
    def cleanup_session_fixture_set(
        self, serial: str, package_name: str, session_id: str,
        fixture_manifest_sha256: str, destination: str, timeout_seconds: int,
    ) -> FixtureCleanupReceipt: ...


def _add_scan_alias(kind: str, value: str) -> str:
    return f"{kind}-{hashlib.sha256(f'{kind}:{value}'.encode()).hexdigest()[:32]}"


def _add_scan_timestamp(value: datetime) -> str:
    return value.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


class _AddScanOperationExecutor:
    """Run one exact, admitted Add & Scan plan through an injected transport.

    Every call is bound to the loader-approved session and operation list. The
    executor writes a durable intent before each product mutation, verifies the
    result once, and never retries a product mutation. Host simulation always
    returns ``BLOCKED`` because synthetic observations cannot establish game
    identity or physical qualification.
    """

    def __init__(
        self,
        *,
        session: AdmittedSession,
        transport: _AddScanTransport,
        writer: evidence.ExecutionWriter,
        evidence_spec: evidence.SessionSpec,
        fixture_plan: FixtureTransferPlan,
        library_expectations: tuple[object, ...],
        monotonic=time.monotonic,
        sleeper=time.sleep,
    ) -> None:
        self._session = session
        self._transport = transport
        self._writer = writer
        self._spec = evidence_spec
        self._fixture_plan = fixture_plan
        self._expectations = library_expectations
        self._monotonic = monotonic
        self._sleeper = sleeper
        self._started = 0.0
        self._base_time: datetime | None = None
        self._operation_timeout = 0
        self._operation_deadline: datetime | None = None
        self._operation_monotonic_deadline: float | None = None
        self._active_budget: _CallBudget | None = None
        self._evidence_open = False
        self._terminal_written = False
        self._staged = False
        self._stage_receipt: FixtureStageReceipt | None = None
        self._scan_action_attempted = False
        self._view_job_navigation_attempted = False
        self._view_job_navigation_verified = False
        self._terminal_job_observation = None
        self._uncertain_add_scan_tap = False
        self._scan_admission_confirmed_no_job = False
        self._terminal_scan_observed = False
        self._cleanup_attempted = False
        self._cleanup_plan_entered = False
        self._admission: str | None = None
        self._job_status: str | None = None
        self._terminal_scan: str | None = None
        self._fixture_results: tuple[int, ...] = ()
        self._cleanup_status = "not_attempted"
        self._workflow_completed = False
        self._assertion_failed = False
        self._blocker = ""
        self._interrupted = False
        self._execution_manifest_sha256: str | None = None
        self._evidence_refs: tuple[str, ...] = ()
        self._scope_extensions: list[AddScanScopeExtension] = []

    def _request_scope_extension(
        self,
        area: str,
        reason: str,
        required_outcome: str,
    ) -> None:
        request = AddScanScopeExtension(area, reason, required_outcome)
        if request not in self._scope_extensions:
            self._scope_extensions.append(request)

    def _request_scan_recovery_if_unresolved(self) -> None:
        """Defer an uncertain Add & Scan recovery request until state observation.

        Admission observation can prove that no job started, while a terminal
        parent and child observation can prove that the admitted job finished.
        In either case the single tap's uncertain transport response no longer
        requires a separate recovery capability.
        """
        if (
            not self._uncertain_add_scan_tap
            or self._scan_admission_confirmed_no_job
            or self._terminal_scan_observed
        ):
            return
        reason = "Read-only observations did not resolve the single Add & Scan tap outcome."
        self._blocker = self._blocker or reason
        self._request_scope_extension(
            "uncertain Add & Scan tap recovery",
            reason,
            "An owner-authorized observer establishes whether this session started a scan and, if so, observes its terminal parent and child states before cleanup.",
        )

    def _logical_now(self) -> datetime:
        assert self._base_time is not None
        return self._base_time + timedelta(seconds=max(0.0, self._monotonic() - self._started))

    def _current_operation(self, operation: OperationAuthorization, *, cleanup: bool = False) -> None:
        authorization = self._session.authorization
        instant = self._logical_now()
        deadline = authorization.cleanup_deadline if cleanup else authorization.session_deadline
        if (
            not _now_is_utc(instant)
            or instant >= deadline
            or instant >= self._session.approval.valid_until
            or not _validate_approval(authorization, self._session.approval, instant)
        ):
            raise _AddScanStop("The approved session or cleanup deadline expired.")
        remaining = (deadline - instant).total_seconds()
        if remaining < 1:
            raise _AddScanStop("The approved operation deadline expired.")
        self._operation_timeout = min(operation.timeout_seconds, int(remaining))
        self._operation_deadline = deadline
        self._operation_monotonic_deadline = self._monotonic() + self._operation_timeout
        try:
            self._active_budget = _CallBudget(self._operation_timeout)
        except _OperationDeadlineExpired:
            raise _AddScanStop("The approved operation deadline expired.") from None

    def _budget(self) -> _CallBudget:
        if (
            self._operation_deadline is None
            or self._base_time is None
            or self._active_budget is None
        ):
            raise _AddScanStop("The operation is not bound to an approved deadline.")
        instant = self._logical_now()
        if (
            instant >= self._operation_deadline
            or instant >= self._session.approval.valid_until
            or not _validate_approval(
                self._session.authorization,
                self._session.approval,
                instant,
            )
        ):
            raise _AddScanStop("The approved operation deadline expired.") from None
        return self._active_budget

    def _call(self, operation):
        try:
            return _authorized_transport_call(self._session, self._budget(), operation)
        except _SessionIntegrityError:
            raise _AddScanStop("The admitted session binding changed during transport.") from None
        except _OperationDeadlineExpired:
            raise _AddScanStop("The approved operation deadline expired.") from None
        except InterruptedError:
            # Device transports can report an interrupted call as OSError;
            # route it through the same fail-closed handling as Ctrl-C.
            raise KeyboardInterrupt from None
        except KeyboardInterrupt:
            raise
        except Exception:
            raise _AddScanStop("A typed transport call failed or returned an uncertain outcome.") from None

    def _request(self, key: str) -> evidence.WriteRequest:
        return evidence.WriteRequest(
            operation_id=_add_scan_alias("operation", f"{self._spec.session_id}:{key}"),
            occurred_at=_add_scan_timestamp(self._logical_now()),
        )

    def _append_lifecycle(self, lifecycle: evidence.Lifecycle, key: str) -> None:
        self._writer.append_lifecycle(
            self._spec.session_id,
            evidence.LifecycleObservation(lifecycle, self._evidence_refs),
            self._request(key),
        )

    def _append_assertion(
        self,
        key: str,
        outcome: evidence.AssertionOutcome,
        *,
        measurements: tuple[evidence.Measurement, ...] = (),
    ) -> None:
        self._writer.append_assertion(
            self._spec.session_id,
            evidence.AssertionObservation(
                assertion_ref=_add_scan_alias("assertion", f"{self._spec.session_id}:{key}"),
                rules_ref=self._spec.rules.rules_ref,
                rules_version=self._spec.rules.rules_version,
                rules_sha256=self._spec.rules.rules_sha256,
                observed_at=_add_scan_timestamp(self._logical_now()),
                expected_outcome=evidence.AssertionOutcome.PASSED,
                actual_outcome=outcome,
                evidence_refs=self._evidence_refs,
                measurements=measurements,
            ),
            self._request(key),
        )

    def _record_intent(self, key: str) -> None:
        self._append_assertion(key + ":intent", evidence.AssertionOutcome.NOT_RUN)

    def _record_result(
        self,
        key: str,
        passed: bool,
        *,
        measurements: tuple[evidence.Measurement, ...] = (),
    ) -> None:
        self._append_assertion(
            key + ":result",
            evidence.AssertionOutcome.PASSED if passed else evidence.AssertionOutcome.FAILED,
            measurements=measurements,
        )

    def _record_blocked(self, key: str) -> None:
        self._append_assertion(key + ":blocked", evidence.AssertionOutcome.BLOCKED)

    def _record_uncertain_mutation(
        self,
        operation_id: str,
        *,
        area: str,
        reason: str,
        required_outcome: str,
    ) -> None:
        """Persist an unknown post-intent mutation and request owner recovery.

        Transport errors, identity mismatches after install/reset, and invalid
        staging receipts do not establish whether the requested state change
        completed. The executor records one blocked result, never retries the
        mutation, and leaves recovery to an owner-authorized path.
        """
        self._blocker = self._blocker or reason
        self._request_scope_extension(area, reason, required_outcome)
        try:
            self._record_blocked(operation_id + ":uncertain")
        except Exception:
            self._blocker = (
                "A product mutation has an uncertain outcome and its blocked result "
                "could not be durably appended; owner recovery is required."
            )

    def _verify_target_foreground(
        self,
        operation: OperationAuthorization,
        expected_foreground: str,
        *,
        cleanup: bool = False,
    ) -> None:
        self._current_operation(operation, cleanup=cleanup)
        authorization = self._session.authorization
        target_ok = self._call(lambda timeout: self._transport.verify_target(
            authorization.target_serial, authorization.target_ref, timeout,
        ))
        if target_ok is not True:
            raise _AddScanStop("The exact approved target could not be reverified.")
        foreground_ok = self._call(lambda timeout: self._transport.verify_foreground(
            expected_foreground, timeout,
        ))
        if foreground_ok is not True:
            raise _AddScanStop("The expected foreground package changed.")

    def _observe_package(
        self,
        operation: OperationAuthorization,
        *,
        absent: bool = False,
        cleanup: bool = False,
    ) -> InstallationObservation:
        authorization = self._session.authorization
        observed = self._call(lambda timeout: self._transport.observe_installed_package(
            authorization.target_serial,
            QUALIFICATION_PACKAGE,
            authorization.version_code,
            authorization.certificate_sha256,
            timeout,
        ))
        if type(observed) is not InstallationObservation:
            raise _AddScanStop("Qualification package identity is unavailable or ambiguous.")
        if absent:
            if observed.status is not InstallationStatus.ABSENT:
                raise _AddScanStop("The qualification package is no longer absent.")
        elif (
            observed.status is not InstallationStatus.PRESENT
            or observed.package_name != QUALIFICATION_PACKAGE
            or observed.version_code != authorization.version_code
            or observed.certificate_sha256 != authorization.certificate_sha256
            or observed.artifact_sha256 != authorization.apk_sha256
        ):
            raise _AddScanStop("Qualification package bytes, version, or signer do not match the approved artifact.")
        return observed

    def _validate_stage_receipt(self, receipt: object) -> bool:
        plan = self._fixture_plan
        return (
            type(receipt) is FixtureStageReceipt
            and receipt.session_id == self._spec.session_id
            and receipt.fixture_manifest_sha256 == plan.fixture_manifest_sha256
            and receipt.file_count == plan.file_count
            and receipt.byte_count == plan.byte_count
            and receipt.content_sha256 == plan.content_sha256
        )

    def _run_setup(self, operation: OperationAuthorization) -> None:
        authorization = self._session.authorization
        arguments = dict(operation.arguments)
        expected_foreground = arguments.get("expected_foreground_package")
        if operation.category is OperationCategory.INSTALL_ABSENT:
            if (
                arguments.get("action") != "install_qualification_apk"
                or arguments.get("artifact_sha256") != authorization.apk_sha256
                or self._first_binding.artifact.apk_sha256 != authorization.apk_sha256
            ):
                raise _AddScanStop("The install operation is not bound to the approved APK.")
            assert expected_foreground is not None
            self._verify_target_foreground(operation, expected_foreground)
            self._observe_package(operation, absent=True)
            self._record_intent(operation.operation_id)
            try:
                self._call(lambda timeout: self._transport.install_qualification_artifact(
                    authorization.target_serial,
                    QUALIFICATION_PACKAGE,
                    authorization.apk_sha256,
                    authorization.certificate_sha256,
                    authorization.version_code,
                    timeout,
                ))
                self._observe_package(operation)
                if self._call(lambda timeout: self._transport.verify_foreground(
                    expected_foreground, timeout,
                )) is not True:
                    raise _AddScanStop("The expected launcher foreground changed after installation.")
            except KeyboardInterrupt:
                self._record_uncertain_mutation(
                    operation.operation_id,
                    area="qualification APK installation outcome",
                    reason="The one approved install call was interrupted or its identity could not be verified.",
                    required_outcome="An owner-authorized recovery verifies the isolated package identity and approved artifact state.",
                )
                raise
            except Exception:
                self._record_uncertain_mutation(
                    operation.operation_id,
                    area="qualification APK installation outcome",
                    reason="The one approved install call or its identity verification has an uncertain outcome.",
                    required_outcome="An owner-authorized recovery verifies the isolated package identity and approved artifact state.",
                )
                raise _AddScanStop("Qualification installation outcome is uncertain; it will not be retried.") from None
            try:
                self._record_result(operation.operation_id, True)
            except Exception:
                self._record_uncertain_mutation(
                    operation.operation_id,
                    area="qualification APK installation evidence",
                    reason="Installation was attempted, but its exact result could not be durably recorded.",
                    required_outcome="An owner-authorized recovery verifies the isolated package identity and reviews the incomplete evidence chain.",
                )
                raise _AddScanStop("Installation result evidence could not be durably recorded.") from None
            return

        if operation.category is not OperationCategory.RESET_DATA:
            raise _AddScanStop("The first operation is outside the approved install/reset set.")
        if (
            arguments.get("action") != "clear_qualification_data"
            or expected_foreground != QUALIFICATION_PACKAGE
        ):
            raise _AddScanStop("The reset operation is not bound to the qualification package.")
        self._verify_target_foreground(operation, expected_foreground)
        self._observe_package(operation)
        self._record_intent(operation.operation_id)
        try:
            reset_ok = self._call(lambda timeout: self._transport.reset_qualification_data(
                authorization.target_serial, QUALIFICATION_PACKAGE, timeout,
            ))
            if reset_ok is not True:
                raise _AddScanStop("The authorized qualification data reset is uncertain.")
            self._observe_package(operation)
            foreground_after = arguments.get("expected_foreground_after")
            if not foreground_after or self._call(lambda timeout: self._transport.verify_foreground(
                foreground_after, timeout,
            )) is not True:
                raise _AddScanStop("The reset foreground result did not match the approved state.")
        except KeyboardInterrupt:
            self._record_uncertain_mutation(
                operation.operation_id,
                area="qualification package reset outcome",
                reason="The one authorized reset call was interrupted or its resulting state could not be verified.",
                required_outcome="An owner-authorized recovery observes the isolated qualification package state and resolves the reset outcome.",
            )
            raise
        except Exception:
            self._record_uncertain_mutation(
                operation.operation_id,
                area="qualification package reset outcome",
                reason="The one authorized reset call or its resulting state verification has an uncertain outcome.",
                required_outcome="An owner-authorized recovery observes the isolated qualification package state and resolves the reset outcome.",
            )
            raise _AddScanStop("Qualification reset outcome is uncertain; it will not be retried.") from None
        try:
            self._record_result(operation.operation_id, True)
        except Exception:
            self._record_uncertain_mutation(
                operation.operation_id,
                area="qualification reset evidence durability",
                reason="The authorized reset was attempted, but its exact result could not be durably recorded.",
                required_outcome="An owner-authorized recovery verifies the isolated package state and reviews the incomplete evidence chain.",
            )
            raise _AddScanStop("Reset result evidence could not be durably recorded.") from None

    def _run_stage(self, operation: OperationAuthorization) -> None:
        authorization = self._session.authorization
        arguments = dict(operation.arguments)
        expected = arguments.get("expected_foreground_package")
        if (
            arguments.get("action") != "stage_approved_fixture_set"
            or arguments.get("destination") != "qualification_fixture_root"
            or arguments.get("fixture_manifest_sha256") != authorization.fixture_manifest_sha256
            or self._fixture_plan.fixture_manifest_sha256 != authorization.fixture_manifest_sha256
            or expected is None
        ):
            raise _AddScanStop("Fixture staging is not bound to the approved set and isolated destination.")
        self._verify_target_foreground(operation, expected)
        self._observe_package(operation)
        self._record_intent(operation.operation_id)
        try:
            receipt = self._call(lambda timeout: self._transport.stage_approved_fixture_set(
                authorization.target_serial,
                QUALIFICATION_PACKAGE,
                self._spec.session_id,
                self._fixture_plan,
                "qualification_fixture_root",
                timeout,
            ))
        except KeyboardInterrupt:
            self._cleanup_status = "blocked"
            self._record_uncertain_mutation(
                operation.operation_id,
                area="fixture staging ownership and cleanup",
                reason="The one fixture staging call was interrupted before ownership could be verified.",
                required_outcome="An owner-authorized recovery determines the exact session-owned files and removes only that set.",
            )
            raise
        except Exception:
            self._cleanup_status = "blocked"
            self._record_uncertain_mutation(
                operation.operation_id,
                area="fixture staging ownership and cleanup",
                reason="Fixture staging ownership is uncertain because its one call failed before receipt verification.",
                required_outcome="An owner-authorized recovery determines the exact session-owned files and removes only that set.",
            )
            raise _AddScanStop(
                "Fixture staging ownership is uncertain; it will not be retried or cleaned blindly."
            ) from None
        if not self._validate_stage_receipt(receipt):
            self._cleanup_status = "blocked"
            self._record_uncertain_mutation(
                operation.operation_id,
                area="fixture staging ownership and cleanup",
                reason="The staging receipt did not match the session, fixture manifest, count, and content digest.",
                required_outcome="An owner-authorized recovery determines the exact session-owned files and removes only that set.",
            )
            raise _AddScanStop("Fixture staging ownership or byte identity is uncertain.")
        self._stage_receipt = receipt
        self._staged = True
        try:
            self._record_result(operation.operation_id, True)
        except Exception:
            self._staged = False
            self._cleanup_status = "blocked"
            self._record_uncertain_mutation(
                operation.operation_id,
                area="fixture staging evidence durability",
                reason="The staging receipt matched, but its exact result could not be durably recorded.",
                required_outcome="An owner-authorized recovery verifies and removes only the session-owned fixture files.",
            )
            raise _AddScanStop("Fixture staging result evidence could not be durably recorded.") from None

    def _run_launch(self, operation: OperationAuthorization) -> None:
        authorization = self._session.authorization
        expected = dict(operation.arguments).get("expected_foreground_package")
        if (
            operation.category is not OperationCategory.LAUNCH
            or dict(operation.arguments).get("action") != "launch_qualification_main"
            or expected is None
        ):
            raise _AddScanStop("The launch operation is outside the approved qualification action.")
        self._verify_target_foreground(operation, expected)
        self._observe_package(operation)
        self._record_intent(operation.operation_id)
        try:
            self._call(lambda timeout: self._transport.launch_qualification_main(
                authorization.target_serial, QUALIFICATION_PACKAGE, timeout,
            ))
            if self._call(lambda timeout: self._transport.verify_foreground(
                QUALIFICATION_PACKAGE, timeout,
            )) is not True:
                raise _AddScanStop("The qualification package did not become the foreground app.")
        except KeyboardInterrupt:
            self._record_uncertain_mutation(
                operation.operation_id,
                area="qualification application launch outcome",
                reason="The one qualification launch call was interrupted before foreground state could be verified.",
                required_outcome="An owner-authorized recovery observes the isolated qualification package and resolves the launch outcome.",
            )
            raise
        except Exception:
            self._record_uncertain_mutation(
                operation.operation_id,
                area="qualification application launch outcome",
                reason="The one qualification launch call or foreground verification has an uncertain outcome.",
                required_outcome="An owner-authorized recovery observes the isolated qualification package and resolves the launch outcome.",
            )
            raise _AddScanStop("Qualification launch outcome is uncertain; it will not be retried.") from None
        try:
            self._record_result(operation.operation_id, True)
        except Exception:
            self._record_uncertain_mutation(
                operation.operation_id,
                area="qualification launch evidence durability",
                reason="The launch was attempted, but its exact result could not be durably recorded.",
                required_outcome="An owner-authorized recovery observes the isolated qualification package and reviews the incomplete evidence chain.",
            )
            raise _AddScanStop("Launch result evidence could not be durably recorded.") from None

    def _capture_nodes(self, operation: OperationAuthorization):
        from .physical import ui

        authorization = self._session.authorization
        xml = self._call(lambda timeout: self._transport.capture_accessibility(
            authorization.target_serial,
            QUALIFICATION_PACKAGE,
            self._spec.session_id,
            QUALIFICATION_CAPTURE_SLOT,
            timeout,
        ))
        if type(xml) is not str:
            raise _AddScanStop("The temporary qualification UI capture is unavailable.")
        try:
            return ui.parse_ui(
                xml,
                expected_package=QUALIFICATION_PACKAGE,
                library_expectations=self._expectations,
            )
        except Exception:
            self._record_blocked(operation.operation_id + ":ui-surface")
            raise _AddScanStop("The qualification UI surface is ambiguous or lacks approved semantics.") from None

    def _job_poll_remaining(self) -> float:
        """Return the remaining bound across operation, session, and approval."""
        authorization = self._session.authorization
        if self._operation_monotonic_deadline is None:
            raise _AddScanStop("The job observation is not bound to an operation deadline.")
        now = self._logical_now()
        approval_deadline = self._session.approval.valid_until
        session_deadline = authorization.session_deadline
        if (
            not _now_is_utc(now)
            or now >= approval_deadline
            or now >= session_deadline
            or not _validate_approval(authorization, self._session.approval, now)
        ):
            raise _AddScanStop("The approved job observation deadline expired.")
        monotonic_remaining = self._operation_monotonic_deadline - self._monotonic()
        logical_remaining = min(
            (approval_deadline - now).total_seconds(),
            (session_deadline - now).total_seconds(),
        )
        remaining = min(monotonic_remaining, logical_remaining)
        if remaining <= 0:
            raise _AddScanStop("The approved job observation deadline expired.")
        return remaining

    def _poll_job_status(self, operation: OperationAuthorization, ui):
        """Poll only the exact job-detail loading or active states.

        Each attempt captures one accessibility snapshot and derives both the
        parent and child states from that same snapshot. The operation's
        monotonic budget and the logical session and approval deadlines all
        bound the wait. A terminal pair is retained for the next typed
        observation; no second capture can replace it with a stale pair.
        """
        if (
            self._admission != "admitted"
            or not self._scan_action_attempted
            or not self._view_job_navigation_verified
        ):
            raise _AddScanStop("The job route is not bound to this session's unique admitted scan.")

        while True:
            self._job_poll_remaining()
            nodes = self._capture_nodes(operation)
            observation = ui.observe_scan_job_detail(nodes)
            if observation.job_status != "loading":
                self._job_status = observation.job_status
            if observation.job_status in {"queued", "preparing", "running", "loading"}:
                try:
                    remaining = self._job_poll_remaining()
                    delay = min(_ADD_SCAN_JOB_STATUS_POLL_INTERVAL_SECONDS, remaining)
                    if delay <= 0:
                        raise _AddScanStop("The approved job observation deadline expired.")
                    self._sleeper(delay)
                except InterruptedError:
                    raise KeyboardInterrupt from None
                continue
            self._terminal_job_observation = observation
            return observation

    def _record_uncertain_navigation(self, operation_id: str, action: str) -> None:
        if action != "add_and_scan":
            self._record_uncertain_mutation(
                operation_id,
                area="qualification UI navigation outcome",
                reason="The one UI navigation tap has an uncertain outcome; it will not be repeated.",
                required_outcome="An owner-authorized recovery observes the qualification UI state before any further action.",
            )
            return
        self._uncertain_add_scan_tap = True
        try:
            self._record_blocked(operation_id + ":uncertain")
        except Exception:
            self._record_uncertain_mutation(
                operation_id,
                area="uncertain Add & Scan evidence durability",
                reason="The Add & Scan tap outcome is uncertain and its blocked operation result could not be durably appended.",
                required_outcome="An owner-authorized recovery establishes scan admission and terminal job state before cleanup.",
            )

    def _run_navigation(self, operation: OperationAuthorization) -> None:
        from .physical import ui

        authorization = self._session.authorization
        action = dict(operation.arguments).get("action")
        if action is None:
            raise _AddScanStop("A navigation operation has no closed action.")
        if action == "view_job":
            if (
                not self._scan_action_attempted
                or self._admission != "admitted"
                or self._view_job_navigation_attempted
            ):
                raise _AddScanStop("The View Job route is not the unique route for this admitted scan.")
            self._view_job_navigation_attempted = True
        self._verify_target_foreground(operation, QUALIFICATION_PACKAGE)
        self._observe_package(operation)
        nodes = self._capture_nodes(operation)
        if any(node.key == "product_failure" for node in nodes):
            self._assertion_failed = True
            self._append_assertion(
                operation.operation_id + ":product-failure",
                evidence.AssertionOutcome.FAILED,
            )
            raise _AddScanStop("The qualification UI explicitly reported a product failure.")
        try:
            control = ui.navigation_control(nodes, action)
        except Exception:
            self._record_blocked(operation.operation_id + ":control")
            raise _AddScanStop("The exact Add & Scan workflow control is missing or ambiguous.") from None
        if action == "add_and_scan":
            self._scan_action_attempted = True
        self._record_intent(operation.operation_id)
        try:
            self._call(lambda timeout: self._transport.tap_accessibility_control(
                authorization.target_serial,
                QUALIFICATION_PACKAGE,
                action,
                control.bounds,
                timeout,
            ))
        except KeyboardInterrupt:
            self._record_uncertain_navigation(operation.operation_id, action)
            raise
        except Exception:
            if action == "add_and_scan":
                # The single tap may have reached the product. Read-only
                # observations continue, but no tap is repeated.
                self._record_uncertain_navigation(operation.operation_id, action)
                return
            self._record_uncertain_navigation(operation.operation_id, action)
            raise _AddScanStop("The navigation tap outcome is uncertain; it will not be repeated.") from None
        try:
            self._record_result(operation.operation_id, True)
        except Exception:
            if action == "add_and_scan":
                self._record_uncertain_navigation(operation.operation_id, action)
                return
            self._record_uncertain_mutation(
                operation.operation_id,
                area="qualification UI navigation evidence durability",
                reason="The UI navigation tap was attempted, but its exact result could not be durably recorded.",
                required_outcome="An owner-authorized recovery observes the qualification UI state and reviews the incomplete evidence chain.",
            )
            raise _AddScanStop("Navigation result evidence could not be durably recorded.") from None
        if action == "view_job":
            self._view_job_navigation_verified = True

    def _run_read_only(self, operation: OperationAuthorization) -> None:
        from .physical import ui

        authorization = self._session.authorization
        observation = dict(operation.arguments).get("observation")
        if observation == "job_status" and (
            self._admission != "admitted"
            or not self._scan_action_attempted
            or not self._view_job_navigation_verified
        ):
            raise _AddScanStop("The job detail observation is outside the unique admitted scan route.")
        self._verify_target_foreground(operation, QUALIFICATION_PACKAGE)
        self._observe_package(operation)
        self._record_intent(operation.operation_id)
        nodes = (
            None
            if observation in {"job_status", "terminal_scan"}
            else self._capture_nodes(operation)
        )
        try:
            if observation == "scan_admission":
                result = ui.observe_scan_admission(nodes)
                self._admission = result.status
                passed = result.status == "admitted" and result.view_job_actionable
                self._scan_admission_confirmed_no_job = result.status == "not_admitted"
                measurements = (evidence.Measurement(
                    _add_scan_alias("measurement", "scan-admission"),
                    1 if passed else 0,
                    evidence.MeasurementUnit.COUNT,
                ),)
            elif observation == "job_status":
                try:
                    job_observation = self._poll_job_status(operation, ui)
                except _AddScanStop:
                    self._record_blocked(operation.operation_id + ":observation")
                    raise
                self._job_status = job_observation.job_status
                passed = self._job_status in _JOB_STATUS_VALUES
                measurements = (evidence.Measurement(
                    _add_scan_alias("measurement", "job-status-code"),
                    _job_status_code(self._job_status),
                    evidence.MeasurementUnit.COUNT,
                ),)
            elif observation == "terminal_scan":
                job_observation = self._terminal_job_observation
                if job_observation is None or self._job_status is None:
                    raise _AddScanStop("Terminal outcome must use the terminal pair from the job-status snapshot.")
                ui.require_terminal_scan_outcome(job_observation)
                self._terminal_scan = job_observation.scan_status
                self._terminal_scan_observed = True
                passed = (
                    self._job_status == "completed"
                    and self._terminal_scan == "complete"
                )
                self._terminal_job_observation = None
                measurements = (evidence.Measurement(
                    _add_scan_alias("measurement", "terminal-scan-code"),
                    _terminal_scan_code(self._terminal_scan),
                    evidence.MeasurementUnit.COUNT,
                ),)
            elif observation == "fixture_library":
                self._fixture_results = ui.observe_fixture_library_results(
                    nodes, self._expectations,
                )
                expected_indices = tuple(range(len(self._expectations)))
                passed = self._fixture_results == expected_indices
                measurements = (evidence.Measurement(
                    _add_scan_alias("measurement", "fixture-library-result-count"),
                    len(self._fixture_results),
                    evidence.MeasurementUnit.COUNT,
                ),)
            else:
                raise _AddScanStop("The read-only observation is outside the four Add & Scan gates.")
        except _AddScanStop:
            raise
        except ui.UIFailed:
            self._assertion_failed = True
            self._append_assertion(
                operation.operation_id + ":product-failure",
                evidence.AssertionOutcome.FAILED,
            )
            self._blocker = self._blocker or "The qualification UI explicitly reported a product failure."
            raise _AddScanStop(self._blocker) from None
        except ui.UIBlocked:
            self._record_blocked(operation.operation_id + ":observation")
            self._blocker = self._blocker or "A required Add & Scan observation was ambiguous or unavailable."
            raise _AddScanStop(self._blocker) from None
        except Exception:
            self._record_blocked(operation.operation_id + ":observation")
            raise _AddScanStop("A required Add & Scan observation failed or remained ambiguous.") from None
        self._record_result(operation.operation_id, passed, measurements=measurements)
        if not passed:
            self._assertion_failed = True
            self._blocker = self._blocker or (
                "A required Add & Scan observation did not meet its approved expectation."
            )
        if observation == "fixture_library":
            for index in range(len(self._expectations)):
                actual = (
                    evidence.AssertionOutcome.PASSED
                    if index in self._fixture_results
                    else evidence.AssertionOutcome.FAILED
                )
                self._append_assertion(
                    f"fixture-result-{index:03d}",
                    actual,
                )
        if observation == "scan_admission" and not passed:
            raise _AddScanStop("Add & Scan explicitly did not admit a scan job.")
        if observation == "terminal_scan" and not passed:
            raise _AddScanStop("The observed terminal scan result failed the approved expectation.")

    def _run_cleanup(self, operation: OperationAuthorization) -> None:
        authorization = self._session.authorization
        if self._cleanup_plan_entered:
            raise _AddScanStop("The approved cleanup operation was already entered and will not be repeated.")
        self._cleanup_plan_entered = True
        arguments = dict(operation.arguments)
        if (
            not self._staged
            or self._stage_receipt is None
            or arguments.get("action") != "remove_session_owned_fixture_set"
            or arguments.get("destination") != "qualification_fixture_root"
            or arguments.get("fixture_manifest_sha256") != authorization.fixture_manifest_sha256
            or arguments.get("expected_foreground_package") != QUALIFICATION_PACKAGE
            or (
                self._scan_action_attempted
                and not self._terminal_scan_observed
                and not self._scan_admission_confirmed_no_job
            )
        ):
            raise _AddScanStop("Fixture cleanup is not proven safe for the session-owned set.")
        self._verify_target_foreground(operation, QUALIFICATION_PACKAGE, cleanup=True)
        self._observe_package(operation, cleanup=True)
        self._append_lifecycle(evidence.Lifecycle.CLEANUP_STARTED, "cleanup-started")
        self._record_intent(operation.operation_id)
        self._cleanup_attempted = True
        self._cleanup_status = "blocked"
        try:
            receipt = self._call(lambda timeout: self._transport.cleanup_session_fixture_set(
                authorization.target_serial,
                QUALIFICATION_PACKAGE,
                self._spec.session_id,
                authorization.fixture_manifest_sha256,
                "qualification_fixture_root",
                timeout,
            ))
        except _AddScanStop:
            self._request_scope_extension(
                "uncertain session-owned fixture cleanup",
                "The one cleanup call may have changed device state, but its result is unknown.",
                "An owner-authorized recovery independently observes and resolves only this session-owned fixture set.",
            )
            raise
        valid = (
            type(receipt) is FixtureCleanupReceipt
            and receipt.session_id == self._spec.session_id
            and receipt.fixture_manifest_sha256 == authorization.fixture_manifest_sha256
            and receipt.removed_file_count == self._fixture_plan.file_count
            and receipt.remaining_file_count == 0
        )
        try:
            self._record_result(operation.operation_id, valid)
        except Exception:
            self._request_scope_extension(
                "cleanup evidence durability",
                "The device returned a cleanup receipt but its append-only result could not be recorded.",
                "An owner reviews the incomplete evidence chain and independently verifies the session-owned fixture state.",
            )
            raise
        self._cleanup_status = "verified" if valid else "blocked"
        if not valid:
            self._request_scope_extension(
                "session-owned fixture cleanup",
                "The cleanup receipt did not verify removal of the exact approved set.",
                "An owner-authorized recovery path verifies and removes only the session-owned fixture files.",
            )
            raise _AddScanStop("Session-owned fixture cleanup could not be verified exactly.")
        self._staged = False
        self._append_lifecycle(evidence.Lifecycle.CLEANUP_COMPLETED, "cleanup-completed")

    def _validate_inputs(self) -> None:
        authorization = self._session.authorization
        binding = _first_add_scan_admission_binding(self._session)
        if binding is None:
            raise _AddScanStop("The session was not created by the first Add & Scan admission path.")
        self._first_binding = binding
        expected_session_id = hashlib.sha256(
            f"argus-add-scan:{authorization.authorization_id}:{authorization.canonical_sha256}".encode()
        ).hexdigest()[:32]
        expected_evidence_refs = self._spec.review_requirements.required_evidence_refs
        if (
            self._session.lifecycle is not SessionLifecycle.ACTIVE
            or self._session.execution_phase is not SessionExecutionPhase.ADMITTED
            or authorization.application_package != QUALIFICATION_PACKAGE
            or binding.plan_sha256 != authorization.plan_sha256
            or type(self._spec) is not evidence.SessionSpec
            or self._spec.session_id != expected_session_id
            or self._spec.scenario_id
            != _add_scan_alias("scenario", authorization.scenario_ids[0])
            or self._spec.artifact.artifact_sha256 != authorization.apk_sha256
            or self._spec.artifact.artifact_ref
            != _add_scan_alias("artifact", authorization.apk_sha256)
            or self._spec.authorization.manifest_sha256 != authorization.canonical_sha256
            or self._spec.authorization.manifest_version != 1
            or self._spec.fixtures.manifest_sha256 != authorization.fixture_manifest_sha256
            or self._spec.fixtures.corpus_ref
            != _add_scan_alias("corpus", authorization.fixture_manifest_sha256)
            or self._spec.plan.plan_sha256 != authorization.plan_sha256
            or self._spec.plan.plan_ref
            != _add_scan_alias("plan", authorization.plan_sha256)
            or self._spec.rules.rules_sha256 != authorization.rules_sha256
            or self._spec.rules.rules_ref
            != _add_scan_alias("rules", authorization.rules_sha256)
            or self._spec.environment.target_ref
            != _add_scan_alias("target", authorization.target_ref)
            or self._spec.environment.platform is not evidence.Platform.ANDROID
            or self._spec.artifact.artifact_class is not evidence.ArtifactClass.QUALIFICATION_VARIANT
            or self._spec.plan.plan_version != 1
            or self._fixture_plan.fixture_manifest_sha256 != authorization.fixture_manifest_sha256
            or type(self._fixture_plan.file_count) is not int
            or self._fixture_plan.file_count <= 0
            or type(self._fixture_plan.byte_count) is not int
            or self._fixture_plan.byte_count <= 0
            or not re.fullmatch(r"[0-9a-f]{64}", self._fixture_plan.content_sha256)
            or type(self._expectations) is not tuple
            or not self._expectations
            or not self._spec.review_requirements.required_evidence_refs
            or any(type(ref) is not str or not re.fullmatch(r"evidence-[0-9a-f]{32}", ref)
                   for ref in expected_evidence_refs)
        ):
            raise _AddScanStop("The artifact, fixture, plan, target, or evidence pins do not match.")
        self._evidence_refs = self._spec.review_requirements.required_evidence_refs
        if (
            not _validate_approval(authorization, self._session.approval, self._logical_now())
            or self._logical_now() >= authorization.session_deadline
        ):
            raise _AddScanStop("The owner approval or session deadline is no longer valid.")
        try:
            pending = pending_for_device(authorization.target_serial, path=_DEVICE_SAFETY_PATH)
        except SafetyStateError:
            raise _AddScanStop("Device restoration state is unavailable.") from None
        if pending is not None:
            raise _AddScanStop("An unresolved Issue #23 restoration blocks product operations.")

    def _plan_operations(self) -> tuple[OperationAuthorization, ...]:
        operations = _first_add_scan_plan(self._session.authorization)
        if operations is None or operations != self._session.authorization.operations:
            raise _AddScanStop("The approved operation plan changed or is not the closed first-scan plan.")
        return operations

    def _finalize(self, *, reason: evidence.TerminalReason) -> None:
        if not self._evidence_open or self._terminal_written:
            return
        outcome = (
            evidence.TerminalOutcome.FAILED
            if self._assertion_failed
            else evidence.TerminalOutcome.INTERRUPTED
            if self._interrupted
            else evidence.TerminalOutcome.BLOCKED
        )
        try:
            receipt = self._writer.append_terminal(
                self._spec.session_id,
                evidence.TerminalObservation(
                    outcome=outcome,
                    reason=reason,
                    ended_at=_add_scan_timestamp(self._logical_now()),
                    evidence_refs=self._evidence_refs,
                ),
                self._request("terminal"),
            )
            self._terminal_written = True
            self._execution_manifest_sha256 = self._writer.verify_execution(
                self._spec.session_id
            ).manifest_sha256
            if receipt.session_id != self._spec.session_id:
                self._blocker = "The terminal evidence receipt did not match the approved session."
        except Exception:
            self._blocker = self._blocker or "Append-only terminal evidence could not be finalized."

    def _record_cleanup_recovery(self) -> None:
        """Append a distinct blocked assertion for an unresolved cleanup attempt."""
        try:
            self._record_blocked("cleanup-recovery")
        except BaseException:
            # A failed follow-up append must not replace the earlier product
            # failure or cleanup exception with a less informative outcome.
            self._blocker = self._blocker or (
                "Cleanup recovery evidence could not be appended; owner recovery is required."
            )

    def _attempt_owned_cleanup(self, operations: tuple[OperationAuthorization, ...]) -> None:
        if not self._staged or self._cleanup_attempted:
            return
        if self._cleanup_plan_entered:
            self._cleanup_status = "blocked"
            self._request_scope_extension(
                "session-owned fixture cleanup",
                "The one approved cleanup operation stopped before an exact verified result.",
                "An owner-authorized recovery independently verifies and resolves the session-owned fixture set.",
            )
            self._record_cleanup_recovery()
            return
        if (
            self._scan_action_attempted
            and not self._terminal_scan_observed
            and not self._scan_admission_confirmed_no_job
        ):
            self._cleanup_status = "blocked"
            self._blocker = self._blocker or "Fixture cleanup is unsafe while Add & Scan outcome is uncertain."
            self._request_scope_extension(
                "fixture cleanup after uncertain scan admission",
                "The Add & Scan action may have started a scan and no terminal job outcome was observed.",
                "An owner-authorized recovery independently establishes a terminal outcome before removing the session-owned fixture set.",
            )
            return
        cleanup = operations[-1]
        try:
            self._run_cleanup(cleanup)
        except KeyboardInterrupt:
            self._interrupted = True
            self._cleanup_status = "blocked"
            self._blocker = self._blocker or "Cleanup was interrupted; owner recovery is required."
            self._request_scope_extension(
                "interrupted fixture cleanup",
                "Cleanup was interrupted after the session staged its fixture set.",
                "An owner-authorized recovery verifies the session identity and removes only its fixture set.",
            )
            self._record_cleanup_recovery()
        except Exception:
            self._cleanup_status = "blocked"
            self._blocker = self._blocker or "Session-owned fixture cleanup failed or could not be recorded."
            self._request_scope_extension(
                "session-owned fixture cleanup",
                "The session could not establish a durable, exact cleanup result.",
                "An owner-authorized recovery verifies and removes only the session-owned fixture files.",
            )
            self._record_cleanup_recovery()

    def execute(self, *, now: datetime | None = None) -> AddScanExecutionResult:
        authorization = self._session.authorization
        self._base_time = now or datetime.now(timezone.utc)
        if not _now_is_utc(self._base_time):
            return self._result("Execution time must be UTC.")
        if not self._session.reserve_operation():
            return self._result("Another operation is in progress for this session.")
        operations: tuple[OperationAuthorization, ...] = ()
        try:
            if not _claim_first_add_scan_execution(self._session):
                self._blocker = "The admitted first Add & Scan capability is unavailable or already used."
                return self._result(self._blocker)
            self._started = self._monotonic()
            try:
                self._validate_inputs()
                operations = self._plan_operations()
                self._writer.open_session(self._spec, self._request("session-open"))
                self._evidence_open = True
                self._append_lifecycle(evidence.Lifecycle.PREPARATION_STARTED, "preparation-started")
                for operation in operations:
                    if operation.category in {OperationCategory.INSTALL_ABSENT, OperationCategory.RESET_DATA}:
                        self._run_setup(operation)
                    elif dict(operation.arguments).get("action") == "stage_approved_fixture_set":
                        self._run_stage(operation)
                        self._append_lifecycle(evidence.Lifecycle.PREPARATION_COMPLETED, "preparation-completed")
                        self._append_lifecycle(evidence.Lifecycle.EXECUTION_STARTED, "execution-started")
                    elif operation.category is OperationCategory.LAUNCH:
                        self._run_launch(operation)
                    elif operation.category is OperationCategory.NAVIGATION:
                        self._run_navigation(operation)
                    elif operation.category is OperationCategory.READ_ONLY:
                        self._run_read_only(operation)
                    elif dict(operation.arguments).get("action") == "remove_session_owned_fixture_set":
                        self._run_cleanup(operation)
                    else:
                        raise _AddScanStop("The plan contains an unsupported operation category.")
                self._workflow_completed = (
                    self._admission == "admitted"
                    and self._job_status == "completed"
                    and self._terminal_scan == "complete"
                    and self._fixture_results == tuple(range(len(self._expectations)))
                    and self._cleanup_status == "verified"
                )
                self._append_assertion("independent-game-identity", evidence.AssertionOutcome.BLOCKED)
                self._blocker = self._blocker or (
                "Host simulation cannot establish independently owner-validated game identity or physical Add & Scan qualification."
                )
            except KeyboardInterrupt:
                self._interrupted = True
                self._blocker = "Execution was interrupted; no product mutation was retried."
            except _AddScanStop as stop:
                self._blocker = self._blocker or stop.reason
            except Exception:
                self._blocker = self._blocker or "Evidence persistence or an internal assertion failed."
            finally:
                if self._evidence_open and operations:
                    self._request_scan_recovery_if_unresolved()
                    self._attempt_owned_cleanup(operations)
                    self._finalize(
                        reason=(
                            evidence.TerminalReason.OPERATOR_TERMINATED
                            if self._interrupted
                            else evidence.TerminalReason.ASSERTION_FAILED
                            if self._assertion_failed
                            else evidence.TerminalReason.PREREQUISITE_BLOCKED
                        )
                    )
        finally:
            if _admitted_session_binding(self._session) is not None:
                _finish_admitted_session(self._session, blocked=True)
            self._session.release_operation()
        if self._workflow_completed and self._cleanup_status == "verified":
            self._blocker = self._blocker or (
                "The workflow was simulated with host fixtures; physical and owner identity gates remain unverified."
            )
        return self._result(self._blocker or "The Add & Scan workflow did not complete.")

    def _result(self, blocker: str) -> AddScanExecutionResult:
        return AddScanExecutionResult(
            status=AddScanExecutionStatus.BLOCKED,
            workflow_completed=self._workflow_completed,
            scan_admission=self._admission,
            job_status=self._job_status,
            terminal_scan_status=self._terminal_scan,
            fixture_result_indices=self._fixture_results,
            cleanup_status=self._cleanup_status,
            blocker=blocker,
            scope_extensions=tuple(self._scope_extensions),
            execution_manifest_sha256=self._execution_manifest_sha256,
        )


def _job_status_code(value: str) -> int:
    return _JOB_STATUS_VALUES.index(value) if value in _JOB_STATUS_VALUES else 0


_JOB_STATUS_VALUES = (
    "queued", "preparing", "running", "completed", "completed_with_issues",
    "failed", "cancelled", "interrupted", "abandoned",
)


def _terminal_scan_code(value: str) -> int:
    statuses = ("complete", "partial", "failed", "cancelled", "abandoned")
    return statuses.index(value) if value in statuses else 0
