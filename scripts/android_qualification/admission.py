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
