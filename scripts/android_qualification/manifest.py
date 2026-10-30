"""Validate host manifests and private Android session authorization.

The public version-1 manifest remains a structural host-validation envelope.
The separate SessionAuthorization contract binds one owner-approved session;
the public commands do not connect it to a live device transport.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import stat
import weakref
from datetime import datetime, timedelta, timezone
from dataclasses import dataclass, field, fields as dataclass_fields, is_dataclass
from enum import Enum
from pathlib import Path
from typing import Any, NoReturn


SCHEMA_VERSION = 1
MAX_MANIFEST_BYTES = 64 * 1024
MAX_REFERENCE_CHARS = 256

REFERENCE_FIELDS = (
    "authorization_ref",
    "target_ref",
    "artifact_ref",
    "plan_ref",
    "scope_ref",
)
REQUIRED_FIELDS = (
    "schema_version",
    *REFERENCE_FIELDS,
    "state_mode",
    "inherited_state_session_ref",
)


class StateMode(str, Enum):
    """The two separately invocable qualification state modes."""

    FRESH = "fresh"
    NO_RESET = "no-reset"


class ManifestErrorCode(str, Enum):
    """Stable error codes returned without manifest values or paths."""

    UNAVAILABLE = "MANIFEST_UNAVAILABLE"
    NOT_REGULAR_FILE = "MANIFEST_NOT_REGULAR_FILE"
    TOO_LARGE = "MANIFEST_TOO_LARGE"
    ENCODING_INVALID = "MANIFEST_ENCODING_INVALID"
    JSON_INVALID = "MANIFEST_JSON_INVALID"
    DUPLICATE_KEY = "MANIFEST_DUPLICATE_KEY"
    ROOT_INVALID = "MANIFEST_ROOT_INVALID"
    MISSING_FIELD = "MANIFEST_MISSING_FIELD"
    UNKNOWN_FIELD = "MANIFEST_UNKNOWN_FIELD"
    SCHEMA_VERSION_UNSUPPORTED = "MANIFEST_SCHEMA_VERSION_UNSUPPORTED"
    INVALID_REFERENCE = "MANIFEST_INVALID_REFERENCE"
    INVALID_STATE_MODE = "MANIFEST_INVALID_STATE_MODE"
    STATE_MODE_MISMATCH = "MANIFEST_STATE_MODE_MISMATCH"
    INHERITED_STATE_REQUIRED = "MANIFEST_INHERITED_STATE_REQUIRED"
    INHERITED_STATE_UNEXPECTED = "MANIFEST_INHERITED_STATE_UNEXPECTED"


_ERROR_MESSAGES = {
    ManifestErrorCode.UNAVAILABLE: "Qualification manifest is unavailable",
    ManifestErrorCode.NOT_REGULAR_FILE: "Qualification manifest is not a regular file",
    ManifestErrorCode.TOO_LARGE: "Qualification manifest exceeds the supported size",
    ManifestErrorCode.ENCODING_INVALID: "Qualification manifest is not valid UTF-8",
    ManifestErrorCode.JSON_INVALID: "Qualification manifest is not valid JSON",
    ManifestErrorCode.DUPLICATE_KEY: "Qualification manifest contains duplicate keys",
    ManifestErrorCode.ROOT_INVALID: "Qualification manifest must be a JSON object",
    ManifestErrorCode.MISSING_FIELD: "Qualification manifest is missing a required field",
    ManifestErrorCode.UNKNOWN_FIELD: "Qualification manifest contains an unknown field",
    ManifestErrorCode.SCHEMA_VERSION_UNSUPPORTED: "Qualification manifest schema version is unsupported",
    ManifestErrorCode.INVALID_REFERENCE: "Qualification manifest contains an invalid identity reference",
    ManifestErrorCode.INVALID_STATE_MODE: "Qualification manifest state mode is invalid",
    ManifestErrorCode.STATE_MODE_MISMATCH: "Qualification manifest does not match the selected entrypoint",
    ManifestErrorCode.INHERITED_STATE_REQUIRED: "No-reset qualification requires an inherited session reference",
    ManifestErrorCode.INHERITED_STATE_UNEXPECTED: "Fresh qualification must not name an inherited session",
}


class ManifestError(Exception):
    """A bounded manifest error that never includes private input values."""

    def __init__(self, code: ManifestErrorCode) -> None:
        self.code = code
        super().__init__(_ERROR_MESSAGES[code])


@dataclass(frozen=True)
class QualificationManifest:
    """The minimal version-1 host-validation envelope."""

    schema_version: int
    authorization_ref: str
    target_ref: str
    artifact_ref: str
    plan_ref: str
    scope_ref: str
    state_mode: StateMode
    inherited_state_session_ref: str | None


class _DuplicateKey(ValueError):
    pass


class _NonFiniteConstant(ValueError):
    pass


def _object_without_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    document: dict[str, Any] = {}
    for key, value in pairs:
        if key in document:
            raise _DuplicateKey
        document[key] = value
    return document


def _reject_non_finite_constant(_value: str) -> NoReturn:
    raise _NonFiniteConstant


def _invalid_reference() -> NoReturn:
    raise ManifestError(ManifestErrorCode.INVALID_REFERENCE)


def _validate_reference(value: object) -> str:
    if type(value) is not str or not 1 <= len(value) <= MAX_REFERENCE_CHARS:
        _invalid_reference()
    if value != value.strip() or any(ord(character) < 0x20 or ord(character) == 0x7F for character in value):
        _invalid_reference()
    return value


def _parse_state_mode(value: object) -> StateMode:
    if type(value) is not str:
        raise ManifestError(ManifestErrorCode.INVALID_STATE_MODE)
    try:
        return StateMode(value)
    except ValueError:
        raise ManifestError(ManifestErrorCode.INVALID_STATE_MODE) from None


def _validate_document(
    document: object,
    expected_state_mode: StateMode,
) -> QualificationManifest:
    if type(document) is not dict:
        raise ManifestError(ManifestErrorCode.ROOT_INVALID)

    supplied_fields = set(document)
    required_fields = set(REQUIRED_FIELDS)
    if required_fields - supplied_fields:
        raise ManifestError(ManifestErrorCode.MISSING_FIELD)
    if supplied_fields - required_fields:
        raise ManifestError(ManifestErrorCode.UNKNOWN_FIELD)

    version = document["schema_version"]
    if type(version) is not int or version != SCHEMA_VERSION:
        raise ManifestError(ManifestErrorCode.SCHEMA_VERSION_UNSUPPORTED)

    state_mode = _parse_state_mode(document["state_mode"])
    if state_mode is not expected_state_mode:
        raise ManifestError(ManifestErrorCode.STATE_MODE_MISMATCH)

    references = {field: _validate_reference(document[field]) for field in REFERENCE_FIELDS}

    inherited_reference = document["inherited_state_session_ref"]
    if state_mode is StateMode.FRESH:
        if inherited_reference is not None:
            raise ManifestError(ManifestErrorCode.INHERITED_STATE_UNEXPECTED)
        inherited_session: str | None = None
    else:
        if inherited_reference is None:
            raise ManifestError(ManifestErrorCode.INHERITED_STATE_REQUIRED)
        inherited_session = _validate_reference(inherited_reference)

    return QualificationManifest(
        schema_version=SCHEMA_VERSION,
        authorization_ref=references["authorization_ref"],
        target_ref=references["target_ref"],
        artifact_ref=references["artifact_ref"],
        plan_ref=references["plan_ref"],
        scope_ref=references["scope_ref"],
        state_mode=state_mode,
        inherited_state_session_ref=inherited_session,
    )


def load_manifest(
    manifest_path: Path,
    expected_state_mode: StateMode,
) -> QualificationManifest:
    """Load and structurally validate one owner-private manifest.

    Only a readable regular file is accepted. The file is bounded before
    parsing, and all failures omit its path, contents, and arbitrary parser
    output.
    """

    if type(expected_state_mode) is not StateMode:
        raise TypeError("expected_state_mode must be a StateMode")

    try:
        file_status = manifest_path.stat()
    except OSError:
        raise ManifestError(ManifestErrorCode.UNAVAILABLE) from None

    if not stat.S_ISREG(file_status.st_mode):
        raise ManifestError(ManifestErrorCode.NOT_REGULAR_FILE)
    if file_status.st_size > MAX_MANIFEST_BYTES:
        raise ManifestError(ManifestErrorCode.TOO_LARGE)

    try:
        with manifest_path.open("rb") as stream:
            encoded = stream.read(MAX_MANIFEST_BYTES + 1)
    except OSError:
        raise ManifestError(ManifestErrorCode.UNAVAILABLE) from None
    if len(encoded) > MAX_MANIFEST_BYTES:
        raise ManifestError(ManifestErrorCode.TOO_LARGE)

    try:
        text = encoded.decode("utf-8")
    except UnicodeDecodeError:
        raise ManifestError(ManifestErrorCode.ENCODING_INVALID) from None

    try:
        document = json.loads(
            text,
            object_pairs_hook=_object_without_duplicate_keys,
            parse_constant=_reject_non_finite_constant,
        )
    except _DuplicateKey:
        raise ManifestError(ManifestErrorCode.DUPLICATE_KEY) from None
    except (json.JSONDecodeError, ValueError):
        raise ManifestError(ManifestErrorCode.JSON_INVALID) from None

    return _validate_document(document, expected_state_mode)


# Versioned owner-private session authorization and approval.
SESSION_AUTH_SCHEMA_VERSION = 1
MAX_SESSION_AUTH_INPUT_BYTES = 64 * 1024
QUALIFICATION_PACKAGE = "com.argusromtoolkit.argus.qualification"
ORDINARY_PACKAGE = "com.argusromtoolkit.argus"
MANAGE_EXTERNAL_STORAGE = "android.permission.MANAGE_EXTERNAL_STORAGE"
_SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
_REVISION_RE = re.compile(r"^(?:[0-9a-f]{40}|[0-9a-f]{64})$")
_PACKAGE_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+$")


class SessionStateMode(str, Enum):
    FRESH = "fresh"
    NO_RESET = "no-reset"


class OperationCategory(str, Enum):
    """Typed operation vocabulary; executor support remains category-specific."""

    READ_ONLY = "read_only"
    PERMISSION_APP_OP = "permission_app_op"
    PERMISSION_APP_OP_RESTORE = "permission_app_op_restore"
    INSTALL_ABSENT = "install_absent"
    RESET_DATA = "reset_data"
    REINSTALL = "reinstall"
    LAUNCH = "launch"
    FORCE_STOP = "force_stop"
    NAVIGATION = "navigation"
    REFRESH = "refresh"
    FIXTURE_STAGING = "fixture_staging"
    SHELL = "shell"
    PATH_MUTATION = "path_mutation"


class AuthorizationErrorCode(str, Enum):
    UNAVAILABLE = "AUTHORIZATION_UNAVAILABLE"
    UNSAFE_FILE = "AUTHORIZATION_FILE_UNSAFE"
    TOO_LARGE = "AUTHORIZATION_TOO_LARGE"
    ENCODING_INVALID = "AUTHORIZATION_ENCODING_INVALID"
    JSON_INVALID = "AUTHORIZATION_JSON_INVALID"
    DUPLICATE_KEY = "AUTHORIZATION_DUPLICATE_KEY"
    FLOAT_NOT_ALLOWED = "AUTHORIZATION_FLOAT_NOT_ALLOWED"
    ROOT_INVALID = "AUTHORIZATION_ROOT_INVALID"
    MISSING_FIELD = "AUTHORIZATION_MISSING_FIELD"
    UNKNOWN_FIELD = "AUTHORIZATION_UNKNOWN_FIELD"
    SCHEMA_UNSUPPORTED = "AUTHORIZATION_SCHEMA_UNSUPPORTED"
    INVALID_VALUE = "AUTHORIZATION_INVALID_VALUE"


class ApprovalErrorCode(str, Enum):
    UNAVAILABLE = "OWNER_APPROVAL_UNAVAILABLE"
    UNSAFE_FILE = "OWNER_APPROVAL_FILE_UNSAFE"
    TOO_LARGE = "OWNER_APPROVAL_TOO_LARGE"
    ENCODING_INVALID = "OWNER_APPROVAL_ENCODING_INVALID"
    JSON_INVALID = "OWNER_APPROVAL_JSON_INVALID"
    DUPLICATE_KEY = "OWNER_APPROVAL_DUPLICATE_KEY"
    FLOAT_NOT_ALLOWED = "OWNER_APPROVAL_FLOAT_NOT_ALLOWED"
    ROOT_INVALID = "OWNER_APPROVAL_ROOT_INVALID"
    MISSING_FIELD = "OWNER_APPROVAL_MISSING_FIELD"
    UNKNOWN_FIELD = "OWNER_APPROVAL_UNKNOWN_FIELD"
    SCHEMA_UNSUPPORTED = "OWNER_APPROVAL_SCHEMA_UNSUPPORTED"
    INVALID_VALUE = "OWNER_APPROVAL_INVALID_VALUE"
    DIGEST_MISMATCH = "OWNER_APPROVAL_DIGEST_MISMATCH"
    OWNER_MISMATCH = "OWNER_APPROVAL_OWNER_MISMATCH"
    WINDOW_INVALID = "OWNER_APPROVAL_WINDOW_INVALID"
    WINDOW_CLOSED = "OWNER_APPROVAL_WINDOW_CLOSED"


_AUTH_MESSAGES = {
    code: "Private session authorization is unavailable or invalid" for code in AuthorizationErrorCode
}
_APPROVAL_MESSAGES = {
    code: "Separate owner approval is unavailable or invalid" for code in ApprovalErrorCode
}


class AuthorizationError(Exception):
    """A sanitized authorization input error."""

    def __init__(self, code: AuthorizationErrorCode) -> None:
        self.code = code
        super().__init__(_AUTH_MESSAGES[code])


class ApprovalError(Exception):
    """A sanitized owner-approval input error."""

    def __init__(self, code: ApprovalErrorCode) -> None:
        self.code = code
        super().__init__(_APPROVAL_MESSAGES[code])


@dataclass(frozen=True)
class NoResetBaseline:
    """Private owner-approved values that require an independent observer."""

    library_fixture_ids: tuple[str, ...]
    job_states: tuple[tuple[str, str], ...]
    pending_cleanup_ids: tuple[str, ...]


@dataclass(frozen=True)
class RestorationAuthorization:
    """Exact permission restoration operation reserved for cleanup."""

    operation_id: str
    target_serial: str
    package_name: str
    permission_name: str
    deadline: datetime
    timeout_seconds: int


@dataclass(frozen=True)
class OperationAuthorization:
    """One owner-authorized operation and its exact execution constraints."""

    operation_id: str
    category: OperationCategory
    phase: str
    target_serial: str
    package_name: str
    timeout_seconds: int
    permission_name: str | None
    expected_prior_state: str | None
    desired_state: str | None
    restoration: RestorationAuthorization | None
    arguments: tuple[tuple[str, str], ...] = ()


@dataclass(frozen=True)
class SessionAuthorization:
    """Validated, private authorization for one bounded qualification session."""

    authorization_id: str
    owner_identity: str
    issued_at: datetime
    session_deadline: datetime
    cleanup_deadline: datetime
    target_serial: str
    target_alias: str
    target_ref: str
    minimum_android_api: int
    required_abi: str
    required_capabilities: frozenset[str]
    application_package: str
    apk_sha256: str
    certificate_sha256: str
    source_revision: str
    version_code: int
    declared_permissions: frozenset[str]
    plan_sha256: str
    rules_sha256: str
    scenario_ids: tuple[str, ...]
    fixture_manifest_sha256: str
    state_mode: SessionStateMode
    inherited_state_session_id: str | None
    no_reset_baseline: NoResetBaseline | None
    operations: tuple[OperationAuthorization, ...]
    approved_remediation: tuple[str, ...]
    storage_reserve_bytes: int
    cleanup_reserve_seconds: int
    canonical_sha256: str


@dataclass(frozen=True)
class OwnerApproval:
    """A separately loaded owner approval bound to one exact authorization."""

    authorization_sha256: str
    owner_identity: str
    valid_from: datetime
    valid_until: datetime
    _source_path: Path | None = field(default=None, repr=False, compare=False, init=False)
    _source_directory_identity: tuple[int, int] | None = field(default=None, repr=False, compare=False, init=False)
    _source_file_identity: tuple[int, int] | None = field(default=None, repr=False, compare=False, init=False)
    _source_bytes_sha256: str | None = field(default=None, repr=False, compare=False, init=False)


@dataclass(frozen=True)
class _RestorationApprovalContext:
    """Exact owner-private pending obligation that limits restoration authority."""

    authorization_id: str
    authorization_sha256: str
    target_serial: str
    operation_id: str
    restoration_operation_id: str
    package_name: str
    permission_name: str
    snapshot_sha256: str
    sidecar_path: Path
    sidecar_directory_identity: tuple[int, int]
    sidecar_file_identity: tuple[int, int]
    sidecar_sha256: str


@dataclass(frozen=True)
class _OwnerApprovalBinding:
    """Private loader evidence bound to one exact owner-approval object."""

    reference: weakref.ReferenceType[OwnerApproval]
    integrity: tuple[object, ...]
    source_path: Path
    source_directory_identity: tuple[int, int]
    source_file_identity: tuple[int, int]
    source_bytes_sha256: str
    restoration_context: _RestorationApprovalContext | None


_OWNER_APPROVAL_BINDINGS: dict[int, _OwnerApprovalBinding] = {}


_SESSION_AUTHORIZATION_BINDINGS: dict[
    int,
    tuple[weakref.ReferenceType[SessionAuthorization], tuple[object, ...]],
] = {}


def _authorization_integrity_value(value: object) -> object | None:
    """Create a typed, immutable snapshot of validated authorization data."""
    if isinstance(value, Enum):
        enum_value = _authorization_integrity_value(value.value)
        return None if enum_value is None else ("enum", type(value), enum_value)
    if type(value) is datetime:
        return ("datetime", value.isoformat(), value.fold, type(value.tzinfo), repr(value.tzinfo))
    if type(value) in (str, int, bool, type(None)):
        return (type(value), value)
    if type(value) is tuple:
        items = tuple(_authorization_integrity_value(item) for item in value)
        return None if any(item is None for item in items) else (tuple, items)
    if type(value) is frozenset:
        items = tuple(_authorization_integrity_value(item) for item in value)
        if any(item is None for item in items):
            return None
        return (frozenset, tuple(sorted(items, key=repr)))
    if is_dataclass(value) and not isinstance(value, type):
        members = []
        for member in dataclass_fields(value):
            if not member.init:
                continue
            item = _authorization_integrity_value(getattr(value, member.name))
            if item is None:
                return None
            members.append((member.name, item))
        return (type(value), tuple(members))
    return None


def _owner_approval_binding(approval: object) -> _OwnerApprovalBinding | None:
    """Return the loader binding only while the exact approval fields are intact."""
    if type(approval) is not OwnerApproval:
        return None
    binding = _OWNER_APPROVAL_BINDINGS.get(id(approval))
    if binding is None or binding.reference() is not approval:
        return None
    try:
        current_integrity = _authorization_integrity_value(approval)
    except RecursionError:
        return None
    if (
        current_integrity is None
        or current_integrity != binding.integrity
        or approval._source_path != binding.source_path
        or approval._source_directory_identity != binding.source_directory_identity
        or approval._source_file_identity != binding.source_file_identity
        or approval._source_bytes_sha256 != binding.source_bytes_sha256
    ):
        return None
    return binding


def _is_loaded_owner_approval(approval: object) -> bool:
    """Return whether this exact sidecar-loaded approval remains unchanged."""
    binding = _owner_approval_binding(approval)
    return binding is not None and binding.restoration_context is None


def _is_loaded_restoration_approval(
    approval: object,
    context: _RestorationApprovalContext,
) -> bool:
    """Return whether an approval is bound only to this exact restoration."""
    binding = _owner_approval_binding(approval)
    return (
        binding is not None
        and binding.restoration_context == context
        and _owner_approval_source_matches(approval)
    )


def _register_loaded_owner_approval(
    approval: OwnerApproval,
    *,
    restoration_context: _RestorationApprovalContext | None = None,
) -> bool:
    """Record validated approval fields and sidecar identity outside the object."""
    if (
        type(approval) is not OwnerApproval
        or not isinstance(approval._source_path, Path)
        or not approval._source_path.is_absolute()
        or type(approval._source_directory_identity) is not tuple
        or len(approval._source_directory_identity) != 2
        or any(type(value) is not int for value in approval._source_directory_identity)
        or type(approval._source_file_identity) is not tuple
        or len(approval._source_file_identity) != 2
        or any(type(value) is not int for value in approval._source_file_identity)
        or type(approval._source_bytes_sha256) is not str
        or _SHA256_RE.fullmatch(approval._source_bytes_sha256) is None
    ):
        return False
    integrity = _authorization_integrity_value(approval)
    if type(integrity) is not tuple:
        return False

    identity = id(approval)

    def discard(reference: weakref.ReferenceType[OwnerApproval]) -> None:
        current = _OWNER_APPROVAL_BINDINGS.get(identity)
        if current is not None and current.reference is reference:
            del _OWNER_APPROVAL_BINDINGS[identity]

    reference = weakref.ref(approval, discard)
    _OWNER_APPROVAL_BINDINGS[identity] = _OwnerApprovalBinding(
        reference=reference,
        integrity=integrity,
        source_path=approval._source_path,
        source_directory_identity=approval._source_directory_identity,
        source_file_identity=approval._source_file_identity,
        source_bytes_sha256=approval._source_bytes_sha256,
        restoration_context=restoration_context,
    )
    return True


def _is_loaded_session_authorization(authorization: object) -> bool:
    """Return whether authorization is loader-created and its fields are intact."""
    if type(authorization) is not SessionAuthorization:
        return False
    binding = _SESSION_AUTHORIZATION_BINDINGS.get(id(authorization))
    if binding is None or binding[0]() is not authorization:
        return False
    try:
        current_integrity = _authorization_integrity_value(authorization)
    except RecursionError:
        return False
    return current_integrity is not None and current_integrity == binding[1]


def _register_loaded_session_authorization(
    authorization: SessionAuthorization,
    integrity: tuple[object, ...],
) -> None:
    """Bind one loader-created object to its private integrity snapshot."""
    identity = id(authorization)

    def discard(reference: weakref.ReferenceType[SessionAuthorization]) -> None:
        current = _SESSION_AUTHORIZATION_BINDINGS.get(identity)
        if current is not None and current[0] is reference:
            del _SESSION_AUTHORIZATION_BINDINGS[identity]

    reference = weakref.ref(authorization, discard)
    _SESSION_AUTHORIZATION_BINDINGS[identity] = (reference, integrity)


class _AuthorizationDuplicateKey(ValueError):
    pass


class _FloatValue(ValueError):
    pass


def _without_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise _AuthorizationDuplicateKey
        result[key] = value
    return result


def _reject_float(_value: str) -> NoReturn:
    raise _FloatValue


def _reject_constant(_value: str) -> NoReturn:
    raise _FloatValue


def _parse_json(encoded: bytes, error_type: type[AuthorizationError] | type[ApprovalError]) -> object:
    invalid = AuthorizationErrorCode.JSON_INVALID if error_type is AuthorizationError else ApprovalErrorCode.JSON_INVALID
    duplicate = AuthorizationErrorCode.DUPLICATE_KEY if error_type is AuthorizationError else ApprovalErrorCode.DUPLICATE_KEY
    float_code = AuthorizationErrorCode.FLOAT_NOT_ALLOWED if error_type is AuthorizationError else ApprovalErrorCode.FLOAT_NOT_ALLOWED
    encoding = AuthorizationErrorCode.ENCODING_INVALID if error_type is AuthorizationError else ApprovalErrorCode.ENCODING_INVALID
    try:
        text = encoded.decode("utf-8")
    except UnicodeDecodeError:
        raise error_type(encoding) from None
    try:
        return json.loads(
            text,
            object_pairs_hook=_without_duplicate_keys,
            parse_float=_reject_float,
            parse_constant=_reject_constant,
        )
    except _AuthorizationDuplicateKey:
        raise error_type(duplicate) from None
    except _FloatValue:
        raise error_type(float_code) from None
    except (ValueError, RecursionError):
        raise error_type(invalid) from None


def _read_private_file(
    path: Path,
    error_type: type[AuthorizationError] | type[ApprovalError],
) -> bytes:
    unavailable = AuthorizationErrorCode.UNAVAILABLE if error_type is AuthorizationError else ApprovalErrorCode.UNAVAILABLE
    unsafe = AuthorizationErrorCode.UNSAFE_FILE if error_type is AuthorizationError else ApprovalErrorCode.UNSAFE_FILE
    too_large = AuthorizationErrorCode.TOO_LARGE if error_type is AuthorizationError else ApprovalErrorCode.TOO_LARGE
    try:
        before = path.lstat()
    except OSError:
        raise error_type(unavailable) from None
    if not stat.S_ISREG(before.st_mode):
        raise error_type(unsafe)

    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(path, flags)
    except OSError:
        raise error_type(unsafe) from None
    try:
        opened = os.fstat(descriptor)
        if (
            not stat.S_ISREG(opened.st_mode)
            or (opened.st_dev, opened.st_ino) != (before.st_dev, before.st_ino)
            or (os.name == "posix" and opened.st_uid != os.geteuid())
            or (os.name == "posix" and stat.S_IMODE(opened.st_mode) & 0o077 != 0)
        ):
            raise error_type(unsafe)
        if opened.st_size > MAX_SESSION_AUTH_INPUT_BYTES:
            raise error_type(too_large)
        chunks: list[bytes] = []
        remaining = MAX_SESSION_AUTH_INPUT_BYTES + 1
        while remaining:
            chunk = os.read(descriptor, min(8192, remaining))
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        encoded = b"".join(chunks)
        if len(encoded) > MAX_SESSION_AUTH_INPUT_BYTES:
            raise error_type(too_large)
        return encoded
    except OSError:
        raise error_type(unavailable) from None
    finally:
        os.close(descriptor)


def _read_private_approval_file(
    path: Path,
) -> tuple[bytes, tuple[int, int], tuple[int, int]]:
    """Read a private sidecar relative to its verified private directory."""
    no_follow = getattr(os, "O_NOFOLLOW", None)
    directory_flag = getattr(os, "O_DIRECTORY", None)
    if os.name != "posix" or no_follow is None or directory_flag is None:
        raise ApprovalError(ApprovalErrorCode.UNSAFE_FILE)

    approval_path = Path(path).absolute()
    directory_path = approval_path.parent
    directory_descriptor = -1
    file_descriptor = -1
    try:
        before = directory_path.lstat()
        if (
            not stat.S_ISDIR(before.st_mode)
            or before.st_uid != os.geteuid()
            or stat.S_IMODE(before.st_mode) & 0o077
        ):
            raise ApprovalError(ApprovalErrorCode.UNSAFE_FILE)
        directory_descriptor = os.open(
            directory_path,
            os.O_RDONLY | directory_flag | no_follow,
        )
        opened_directory = os.fstat(directory_descriptor)
        if (
            not stat.S_ISDIR(opened_directory.st_mode)
            or (opened_directory.st_dev, opened_directory.st_ino) != (before.st_dev, before.st_ino)
            or opened_directory.st_uid != os.geteuid()
            or stat.S_IMODE(opened_directory.st_mode) & 0o077
        ):
            raise ApprovalError(ApprovalErrorCode.UNSAFE_FILE)

        name = approval_path.name
        before_file = os.stat(name, dir_fd=directory_descriptor, follow_symlinks=False)
        if not stat.S_ISREG(before_file.st_mode):
            raise ApprovalError(ApprovalErrorCode.UNSAFE_FILE)
        file_descriptor = os.open(
            name,
            os.O_RDONLY | no_follow,
            dir_fd=directory_descriptor,
        )
        opened_file = os.fstat(file_descriptor)
        if (
            not stat.S_ISREG(opened_file.st_mode)
            or (opened_file.st_dev, opened_file.st_ino) != (before_file.st_dev, before_file.st_ino)
            or opened_file.st_uid != os.geteuid()
            or stat.S_IMODE(opened_file.st_mode) != 0o600
        ):
            raise ApprovalError(ApprovalErrorCode.UNSAFE_FILE)
        if opened_file.st_size > MAX_SESSION_AUTH_INPUT_BYTES:
            raise ApprovalError(ApprovalErrorCode.TOO_LARGE)

        chunks: list[bytes] = []
        remaining = MAX_SESSION_AUTH_INPUT_BYTES + 1
        while remaining:
            chunk = os.read(file_descriptor, min(8192, remaining))
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        encoded = b"".join(chunks)
        if len(encoded) > MAX_SESSION_AUTH_INPUT_BYTES:
            raise ApprovalError(ApprovalErrorCode.TOO_LARGE)
        return (
            encoded,
            (opened_directory.st_dev, opened_directory.st_ino),
            (opened_file.st_dev, opened_file.st_ino),
        )
    except ApprovalError:
        raise
    except FileNotFoundError:
        raise ApprovalError(ApprovalErrorCode.UNAVAILABLE) from None
    except OSError:
        raise ApprovalError(ApprovalErrorCode.UNSAFE_FILE) from None
    finally:
        if file_descriptor >= 0:
            os.close(file_descriptor)
        if directory_descriptor >= 0:
            os.close(directory_descriptor)


def _object(value: object, error_type: type[AuthorizationError] | type[ApprovalError]) -> dict[str, Any]:
    if type(value) is not dict:
        _invalid(error_type, "ROOT_INVALID")
    return value


def _fields(
    value: dict[str, Any],
    required: set[str],
    error_type: type[AuthorizationError] | type[ApprovalError],
) -> None:
    if required - value.keys():
        _invalid(error_type, "MISSING_FIELD")
    if value.keys() - required:
        _invalid(error_type, "UNKNOWN_FIELD")


def _invalid(error_type: type[AuthorizationError] | type[ApprovalError], code: str) -> NoReturn:
    if error_type is AuthorizationError:
        raise AuthorizationError(AuthorizationErrorCode[code])
    raise ApprovalError(ApprovalErrorCode[code])


def _string(value: object, error_type: type[AuthorizationError] | type[ApprovalError], maximum: int = 512) -> str:
    if type(value) is not str or not 1 <= len(value) <= maximum or value != value.strip():
        _invalid(error_type, "INVALID_VALUE")
    if any(ord(character) < 0x20 or ord(character) == 0x7F for character in value):
        _invalid(error_type, "INVALID_VALUE")
    return value


def _integer(value: object, error_type: type[AuthorizationError] | type[ApprovalError], minimum: int = 1) -> int:
    if type(value) is not int or value < minimum:
        _invalid(error_type, "INVALID_VALUE")
    return value


def _digest(value: object, error_type: type[AuthorizationError] | type[ApprovalError]) -> str:
    candidate = _string(value, error_type, 64)
    if not _SHA256_RE.fullmatch(candidate):
        _invalid(error_type, "INVALID_VALUE")
    return candidate


def _timestamp(value: object, error_type: type[AuthorizationError] | type[ApprovalError]) -> datetime:
    candidate = _string(value, error_type, 20)
    try:
        parsed = datetime.strptime(candidate, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError:
        _invalid(error_type, "INVALID_VALUE")
    return parsed.replace(tzinfo=timezone.utc)


def _string_list(
    value: object,
    error_type: type[AuthorizationError] | type[ApprovalError],
    *,
    allow_empty: bool = False,
) -> tuple[str, ...]:
    if type(value) is not list or (not allow_empty and not value) or len(value) > 512:
        _invalid(error_type, "INVALID_VALUE")
    items = tuple(_string(item, error_type) for item in value)
    if len(items) != len(set(items)):
        _invalid(error_type, "INVALID_VALUE")
    return items


def _reject_floats_recursively(value: object) -> None:
    if type(value) is float:
        raise AuthorizationError(AuthorizationErrorCode.FLOAT_NOT_ALLOWED)
    if type(value) is dict:
        for key, child in value.items():
            if type(key) is not str:
                raise AuthorizationError(AuthorizationErrorCode.INVALID_VALUE)
            _reject_floats_recursively(child)
    elif type(value) is list:
        for child in value:
            _reject_floats_recursively(child)


def canonical_sha256(document: object) -> str:
    """Return the digest of strict sorted compact JSON for a JSON document."""
    _reject_floats_recursively(document)
    try:
        canonical = json.dumps(
            document,
            sort_keys=True,
            separators=(",", ":"),
            ensure_ascii=False,
            allow_nan=False,
        ).encode("utf-8")
    except (TypeError, ValueError, UnicodeEncodeError):
        raise AuthorizationError(AuthorizationErrorCode.INVALID_VALUE) from None
    return hashlib.sha256(canonical).hexdigest()


def _parse_baseline(value: object, error_type: type[AuthorizationError]) -> NoResetBaseline:
    baseline = _object(value, error_type)
    _fields(baseline, {"library_fixture_ids", "job_states", "pending_cleanup_ids"}, error_type)
    fixture_ids = _string_list(baseline["library_fixture_ids"], error_type, allow_empty=True)
    cleanup_ids = _string_list(baseline["pending_cleanup_ids"], error_type, allow_empty=True)
    raw_jobs = baseline["job_states"]
    if type(raw_jobs) is not list or len(raw_jobs) > 512:
        _invalid(error_type, "INVALID_VALUE")
    jobs: list[tuple[str, str]] = []
    for raw_job in raw_jobs:
        job = _object(raw_job, error_type)
        _fields(job, {"job_id", "state"}, error_type)
        jobs.append((_string(job["job_id"], error_type), _string(job["state"], error_type)))
    if len({job_id for job_id, _ in jobs}) != len(jobs):
        _invalid(error_type, "INVALID_VALUE")
    return NoResetBaseline(fixture_ids, tuple(jobs), cleanup_ids)


def _parse_operation(
    value: object,
    target_serial: str,
    package_name: str,
    permissions: frozenset[str],
    apk_sha256: str,
    fixture_manifest_sha256: str,
    session_deadline: datetime,
    cleanup_deadline: datetime,
    cleanup_reserve_seconds: int,
) -> OperationAuthorization:
    error_type = AuthorizationError
    operation = _object(value, error_type)
    required_fields = {
        "operation_id", "category", "phase", "target_serial", "package_name",
        "timeout_seconds", "permission_name", "expected_prior_state",
        "desired_state", "restoration",
    }
    if required_fields - operation.keys():
        _invalid(error_type, "MISSING_FIELD")
    if operation.keys() - (required_fields | {"arguments"}):
        _invalid(error_type, "UNKNOWN_FIELD")
    operation_id = _string(operation["operation_id"], error_type)
    try:
        category = OperationCategory(_string(operation["category"], error_type))
    except ValueError:
        _invalid(error_type, "INVALID_VALUE")
    phase = _string(operation["phase"], error_type, 64)
    serial = _string(operation["target_serial"], error_type)
    package = _string(operation["package_name"], error_type, 255)
    timeout = _integer(operation["timeout_seconds"], error_type)
    if timeout > 3600 or serial != target_serial or package != package_name or package == ORDINARY_PACKAGE:
        _invalid(error_type, "INVALID_VALUE")

    permission = operation["permission_name"]
    expected_prior = operation["expected_prior_state"]
    desired = operation["desired_state"]
    raw_restore = operation["restoration"]
    raw_arguments = operation.get("arguments")
    if category is OperationCategory.PERMISSION_APP_OP:
        if raw_arguments is not None:
            _invalid(error_type, "INVALID_VALUE")
        if phase != "qualification":
            _invalid(error_type, "INVALID_VALUE")
        if (
            _string(permission, error_type, 255) != MANAGE_EXTERNAL_STORAGE
            or MANAGE_EXTERNAL_STORAGE not in permissions
            or type(expected_prior) is not str
            or expected_prior not in ("allowed", "denied")
            or desired not in ("allowed", "denied")
            or type(desired) is not str
        ):
            _invalid(error_type, "INVALID_VALUE")
        restoration = _parse_restoration(
            raw_restore,
            operation_id,
            target_serial,
            package_name,
            MANAGE_EXTERNAL_STORAGE,
            session_deadline,
            cleanup_deadline,
            cleanup_reserve_seconds,
        )
        return OperationAuthorization(
            operation_id,
            category,
            phase,
            serial,
            package,
            timeout,
            MANAGE_EXTERNAL_STORAGE,
            expected_prior,
            desired,
            restoration,
            (),
        )
    if permission is not None or expected_prior is not None or desired is not None or raw_restore is not None:
        _invalid(error_type, "INVALID_VALUE")
    arguments = _parse_add_scan_operation_arguments(
        raw_arguments,
        category=category,
        phase=phase,
        package_name=package,
        apk_sha256=apk_sha256,
        fixture_manifest_sha256=fixture_manifest_sha256,
    )
    if phase not in {"admission", "qualification", "cleanup"}:
        _invalid(error_type, "INVALID_VALUE")
    return OperationAuthorization(
        operation_id, category, phase, serial, package, timeout,
        None, None, None, None, arguments,
    )


def _parse_add_scan_operation_arguments(
    value: object,
    *,
    category: OperationCategory,
    phase: str,
    package_name: str,
    apk_sha256: str,
    fixture_manifest_sha256: str,
) -> tuple[tuple[str, str], ...]:
    """Validate the closed arguments used by one first fresh Add & Scan plan."""
    if value is None:
        if category is OperationCategory.INSTALL_ABSENT:
            _invalid(AuthorizationError, "INVALID_VALUE")
        return ()
    arguments = _object(value, AuthorizationError)
    if category is OperationCategory.INSTALL_ABSENT:
        _fields(
            arguments,
            {"action", "artifact_sha256", "expected_foreground_package"},
            AuthorizationError,
        )
        foreground = _string(arguments["expected_foreground_package"], AuthorizationError, 255)
        if (
            phase != "admission"
            or package_name != QUALIFICATION_PACKAGE
            or _string(arguments["action"], AuthorizationError, 64) != "install_qualification_apk"
            or _digest(arguments["artifact_sha256"], AuthorizationError) != apk_sha256
            or not _PACKAGE_RE.fullmatch(foreground)
            or foreground in {QUALIFICATION_PACKAGE, ORDINARY_PACKAGE}
        ):
            _invalid(AuthorizationError, "INVALID_VALUE")
    elif category is OperationCategory.RESET_DATA:
        _fields(arguments, {"action", "expected_foreground_package", "expected_foreground_after"}, AuthorizationError)
        foreground = _string(arguments["expected_foreground_package"], AuthorizationError, 255)
        foreground_after = _string(arguments["expected_foreground_after"], AuthorizationError, 255)
        if (
            phase != "admission"
            or package_name != QUALIFICATION_PACKAGE
            or _string(arguments["action"], AuthorizationError, 64) != "clear_qualification_data"
            or not _PACKAGE_RE.fullmatch(foreground)
            or foreground != QUALIFICATION_PACKAGE
            or not _PACKAGE_RE.fullmatch(foreground_after)
            or foreground_after in {QUALIFICATION_PACKAGE, ORDINARY_PACKAGE}
        ):
            _invalid(AuthorizationError, "INVALID_VALUE")
    elif category is OperationCategory.FIXTURE_STAGING:
        _fields(arguments, {
            "action", "destination", "fixture_manifest_sha256", "expected_foreground_package",
        }, AuthorizationError)
        action = _string(arguments["action"], AuthorizationError, 64)
        foreground = _string(arguments["expected_foreground_package"], AuthorizationError, 255)
        expected_phase = {
            "stage_approved_fixture_set": "qualification",
            "remove_session_owned_fixture_set": "cleanup",
        }.get(action)
        if (
            package_name != QUALIFICATION_PACKAGE
            or expected_phase is None
            or phase != expected_phase
            or _string(arguments["destination"], AuthorizationError, 64) != "qualification_fixture_root"
            or _digest(arguments["fixture_manifest_sha256"], AuthorizationError)
            != fixture_manifest_sha256
            or not _PACKAGE_RE.fullmatch(foreground)
            or foreground in {ORDINARY_PACKAGE}
            or (action == "stage_approved_fixture_set" and foreground == QUALIFICATION_PACKAGE)
            or (action == "remove_session_owned_fixture_set" and foreground != QUALIFICATION_PACKAGE)
        ):
            _invalid(AuthorizationError, "INVALID_VALUE")
    elif category is OperationCategory.LAUNCH:
        _fields(arguments, {"action", "expected_foreground_package"}, AuthorizationError)
        foreground = _string(arguments["expected_foreground_package"], AuthorizationError, 255)
        if (
            phase != "qualification"
            or package_name != QUALIFICATION_PACKAGE
            or _string(arguments["action"], AuthorizationError, 64) != "launch_qualification_main"
            or not _PACKAGE_RE.fullmatch(foreground)
            or foreground in {QUALIFICATION_PACKAGE, ORDINARY_PACKAGE}
        ):
            _invalid(AuthorizationError, "INVALID_VALUE")
    elif category is OperationCategory.NAVIGATION:
        _fields(arguments, {"action"}, AuthorizationError)
        action = _string(arguments["action"], AuthorizationError, 64)
        if (
            phase != "qualification"
            or package_name != QUALIFICATION_PACKAGE
            or action not in {
                "accept_terms", "preferences", "skip_provider", "add_root",
                "storage_root", "open_qualification_root", "open_fixture_root",
                "select_folder", "add_and_scan", "view_job", "library_navigation",
            }
        ):
            _invalid(AuthorizationError, "INVALID_VALUE")
    elif category is OperationCategory.READ_ONLY:
        _fields(arguments, {"observation"}, AuthorizationError)
        if (
            phase != "qualification"
            or package_name != QUALIFICATION_PACKAGE
            or _string(arguments["observation"], AuthorizationError, 64)
            not in {"scan_admission", "job_status", "terminal_scan", "fixture_library"}
        ):
            _invalid(AuthorizationError, "INVALID_VALUE")
    else:
        _invalid(AuthorizationError, "INVALID_VALUE")
    return tuple(sorted((key, _string(item, AuthorizationError, 256))
                        for key, item in arguments.items()))


def _parse_restoration(
    value: object,
    product_operation_id: str,
    target_serial: str,
    package_name: str,
    permission_name: str,
    session_deadline: datetime,
    cleanup_deadline: datetime,
    cleanup_reserve_seconds: int,
) -> RestorationAuthorization:
    error_type = AuthorizationError
    restoration = _object(value, error_type)
    _fields(
        restoration,
        {
            "operation_id",
            "category",
            "phase",
            "target_serial",
            "package_name",
            "permission_name",
            "deadline_utc",
            "timeout_seconds",
        },
        error_type,
    )
    try:
        category = OperationCategory(_string(restoration["category"], error_type))
    except ValueError:
        _invalid(error_type, "INVALID_VALUE")
    operation_id = _string(restoration["operation_id"], error_type)
    deadline = _timestamp(restoration["deadline_utc"], error_type)
    timeout = _integer(restoration["timeout_seconds"], error_type)
    if (
        category is not OperationCategory.PERMISSION_APP_OP_RESTORE
        or operation_id == product_operation_id
        or restoration["phase"] != "cleanup"
        or restoration["target_serial"] != target_serial
        or restoration["package_name"] != package_name
        or restoration["permission_name"] != permission_name
        or deadline <= session_deadline
        or deadline > cleanup_deadline
        or timeout > cleanup_reserve_seconds
    ):
        _invalid(error_type, "INVALID_VALUE")
    return RestorationAuthorization(
        operation_id,
        target_serial,
        package_name,
        permission_name,
        deadline,
        timeout,
    )


def _validate_authorization(document: object) -> SessionAuthorization:
    error_type = AuthorizationError
    root = _object(document, error_type)
    _fields(
        root,
        {
            "schema_version",
            "authorization_id",
            "owner_identity",
            "issued_at_utc",
            "session_deadline_utc",
            "cleanup_deadline_utc",
            "target",
            "application",
            "artifact",
            "plan",
            "fixture_manifest_sha256",
            "state",
            "operations",
            "approved_remediation",
            "reserves",
        },
        error_type,
    )
    if type(root["schema_version"]) is not int or root["schema_version"] != SESSION_AUTH_SCHEMA_VERSION:
        _invalid(error_type, "SCHEMA_UNSUPPORTED")
    authorization_id = _string(root["authorization_id"], error_type)
    owner = _string(root["owner_identity"], error_type)
    issued = _timestamp(root["issued_at_utc"], error_type)
    deadline = _timestamp(root["session_deadline_utc"], error_type)
    cleanup_deadline = _timestamp(root["cleanup_deadline_utc"], error_type)
    if not issued < deadline < cleanup_deadline:
        _invalid(error_type, "INVALID_VALUE")

    target = _object(root["target"], error_type)
    _fields(
        target,
        {
            "device_serial",
            "device_alias",
            "target_ref",
            "minimum_android_api",
            "required_abi",
            "required_capabilities",
        },
        error_type,
    )
    serial = _string(target["device_serial"], error_type)
    alias = _string(target["device_alias"], error_type)
    target_ref = _string(target["target_ref"], error_type)
    minimum_android_api = _integer(target["minimum_android_api"], error_type)
    if minimum_android_api > 100:
        _invalid(error_type, "INVALID_VALUE")
    required_abi = _string(target["required_abi"], error_type, 64)
    required_capabilities = frozenset(_string_list(target["required_capabilities"], error_type))

    application = _object(root["application"], error_type)
    _fields(application, {"package_name"}, error_type)
    package = _string(application["package_name"], error_type, 255)
    if package != QUALIFICATION_PACKAGE:
        _invalid(error_type, "INVALID_VALUE")

    artifact = _object(root["artifact"], error_type)
    _fields(
        artifact,
        {"apk_sha256", "certificate_sha256", "source_revision", "version_code", "declared_permissions"},
        error_type,
    )
    apk_sha = _digest(artifact["apk_sha256"], error_type)
    certificate_sha = _digest(artifact["certificate_sha256"], error_type)
    revision = _string(artifact["source_revision"], error_type, 64)
    if not _REVISION_RE.fullmatch(revision):
        _invalid(error_type, "INVALID_VALUE")
    version_code = _integer(artifact["version_code"], error_type)
    permissions = frozenset(_string_list(artifact["declared_permissions"], error_type, allow_empty=True))

    plan = _object(root["plan"], error_type)
    _fields(plan, {"plan_sha256", "rules_sha256", "scenario_ids"}, error_type)
    plan_sha = _digest(plan["plan_sha256"], error_type)
    rules_sha = _digest(plan["rules_sha256"], error_type)
    scenario_ids = _string_list(plan["scenario_ids"], error_type)
    fixture_sha = _digest(root["fixture_manifest_sha256"], error_type)

    state = _object(root["state"], error_type)
    _fields(state, {"mode", "inherited_state_session_id", "no_reset_baseline"}, error_type)
    try:
        state_mode = SessionStateMode(_string(state["mode"], error_type, 32))
    except ValueError:
        _invalid(error_type, "INVALID_VALUE")
    inherited = state["inherited_state_session_id"]
    baseline_value = state["no_reset_baseline"]
    if state_mode is SessionStateMode.FRESH:
        if inherited is not None or baseline_value is not None:
            _invalid(error_type, "INVALID_VALUE")
        inherited_id = None
        baseline = None
    else:
        inherited_id = _string(inherited, error_type)
        baseline = _parse_baseline(baseline_value, error_type)

    reserves = _object(root["reserves"], error_type)
    _fields(reserves, {"storage_bytes", "cleanup_seconds"}, error_type)
    storage_reserve = _integer(reserves["storage_bytes"], error_type)
    cleanup_reserve = _integer(reserves["cleanup_seconds"], error_type)
    if cleanup_reserve > 3600:
        _invalid(error_type, "INVALID_VALUE")

    raw_operations = root["operations"]
    if type(raw_operations) is not list or not raw_operations or len(raw_operations) > 32:
        _invalid(error_type, "INVALID_VALUE")
    operations = tuple(
        _parse_operation(
            operation,
            serial,
            package,
            permissions,
            apk_sha,
            fixture_sha,
            deadline,
            cleanup_deadline,
            cleanup_reserve,
        )
        for operation in raw_operations
    )
    operation_ids: list[str] = []
    for operation in operations:
        operation_ids.append(operation.operation_id)
        if operation.restoration is not None:
            operation_ids.append(operation.restoration.operation_id)
    if len(operation_ids) != len(set(operation_ids)):
        _invalid(error_type, "INVALID_VALUE")
    if sum(op.category is OperationCategory.PERMISSION_APP_OP for op in operations) > 1:
        _invalid(error_type, "INVALID_VALUE")

    remediation = _string_list(root["approved_remediation"], error_type, allow_empty=True)
    has_permission_op = any(op.category is OperationCategory.PERMISSION_APP_OP for op in operations)
    if remediation != (("restore_permission_snapshot",) if has_permission_op else ()):
        _invalid(error_type, "INVALID_VALUE")

    return SessionAuthorization(
        authorization_id,
        owner,
        issued,
        deadline,
        cleanup_deadline,
        serial,
        alias,
        target_ref,
        minimum_android_api,
        required_abi,
        required_capabilities,
        package,
        apk_sha,
        certificate_sha,
        revision,
        version_code,
        permissions,
        plan_sha,
        rules_sha,
        scenario_ids,
        fixture_sha,
        state_mode,
        inherited_id,
        baseline,
        operations,
        remediation,
        storage_reserve,
        cleanup_reserve,
        canonical_sha256(document),
    )


def load_authorization(path: Path) -> SessionAuthorization:
    """Load one strict, owner-private, session-specific authorization file."""
    document = _parse_json(_read_private_file(path, AuthorizationError), AuthorizationError)
    authorization = _validate_authorization(document)
    integrity = _authorization_integrity_value(authorization)
    if type(integrity) is not tuple:
        raise AuthorizationError(AuthorizationErrorCode.INVALID_VALUE)
    _register_loaded_session_authorization(authorization, integrity)
    return authorization


def _restoration_context_matches(
    context: _RestorationApprovalContext,
    session: SessionAuthorization,
    now: datetime,
    source_path: Path,
    source_directory_identity: tuple[int, int],
    source_file_identity: tuple[int, int],
    source_bytes_sha256: str,
) -> bool:
    """Check a private pending record against one approved restoration."""
    if (
        type(context) is not _RestorationApprovalContext
        or not _is_loaded_session_authorization(session)
        or type(context.authorization_id) is not str
        or context.authorization_id != session.authorization_id
        or context.authorization_sha256 != session.canonical_sha256
        or context.target_serial != session.target_serial
        or type(context.operation_id) is not str
        or type(context.restoration_operation_id) is not str
        or context.package_name != QUALIFICATION_PACKAGE
        or context.permission_name != MANAGE_EXTERNAL_STORAGE
        or type(context.snapshot_sha256) is not str
        or _SHA256_RE.fullmatch(context.snapshot_sha256) is None
        or not isinstance(context.sidecar_path, Path)
        or not context.sidecar_path.is_absolute()
        or context.sidecar_path != source_path
        or type(context.sidecar_directory_identity) is not tuple
        or len(context.sidecar_directory_identity) != 2
        or any(type(value) is not int for value in context.sidecar_directory_identity)
        or context.sidecar_directory_identity != source_directory_identity
        or type(context.sidecar_file_identity) is not tuple
        or len(context.sidecar_file_identity) != 2
        or any(type(value) is not int for value in context.sidecar_file_identity)
        or context.sidecar_file_identity != source_file_identity
        or type(context.sidecar_sha256) is not str
        or _SHA256_RE.fullmatch(context.sidecar_sha256) is None
        or context.sidecar_sha256 != source_bytes_sha256
        or now.tzinfo is None
        or now.utcoffset() != timedelta(0)
        or now < session.issued_at
    ):
        return False

    operation = next(
        (item for item in session.operations if item.operation_id == context.operation_id),
        None,
    )
    restoration = operation.restoration if operation is not None else None
    if (
        operation is None
        or operation.category is not OperationCategory.PERMISSION_APP_OP
        or operation.phase != "qualification"
        or operation.target_serial != context.target_serial
        or operation.package_name != QUALIFICATION_PACKAGE
        or operation.permission_name != MANAGE_EXTERNAL_STORAGE
        or restoration is None
        or restoration.operation_id != context.restoration_operation_id
        or restoration.target_serial != context.target_serial
        or restoration.package_name != QUALIFICATION_PACKAGE
        or restoration.permission_name != MANAGE_EXTERNAL_STORAGE
        or restoration.deadline > session.cleanup_deadline
        or now >= restoration.deadline
        or now >= session.cleanup_deadline
    ):
        return False
    try:
        finish = now + timedelta(seconds=restoration.timeout_seconds)
    except (OverflowError, TypeError, ValueError):
        return False
    return finish <= restoration.deadline and finish <= session.cleanup_deadline


def _validate_approval(
    document: object,
    session: SessionAuthorization,
    now: datetime,
    source_path: Path,
    source_directory_identity: tuple[int, int],
    source_file_identity: tuple[int, int],
    source_bytes_sha256: str,
    *,
    restoration_context: _RestorationApprovalContext | None = None,
) -> OwnerApproval:
    error_type = ApprovalError
    root = _object(document, error_type)
    _fields(root, {"schema_version", "authorization_sha256", "owner_identity", "valid_from_utc", "valid_until_utc"}, error_type)
    if type(root["schema_version"]) is not int or root["schema_version"] != SESSION_AUTH_SCHEMA_VERSION:
        _invalid(error_type, "SCHEMA_UNSUPPORTED")
    digest = _digest(root["authorization_sha256"], error_type)
    owner = _string(root["owner_identity"], error_type)
    valid_from = _timestamp(root["valid_from_utc"], error_type)
    valid_until = _timestamp(root["valid_until_utc"], error_type)
    if digest != session.canonical_sha256:
        raise ApprovalError(ApprovalErrorCode.DIGEST_MISMATCH)
    if owner != session.owner_identity:
        raise ApprovalError(ApprovalErrorCode.OWNER_MISMATCH)
    if not session.issued_at <= valid_from < valid_until <= session.session_deadline:
        raise ApprovalError(ApprovalErrorCode.WINDOW_INVALID)
    if now.tzinfo is None or now.utcoffset() != timedelta(0):
        raise ApprovalError(ApprovalErrorCode.WINDOW_INVALID)
    if restoration_context is None and not valid_from <= now < valid_until:
        raise ApprovalError(ApprovalErrorCode.WINDOW_CLOSED)
    if restoration_context is not None and (
        now < valid_from
        or not _restoration_context_matches(
            restoration_context,
            session,
            now,
            source_path,
            source_directory_identity,
            source_file_identity,
            source_bytes_sha256,
        )
    ):
        raise ApprovalError(ApprovalErrorCode.WINDOW_CLOSED)
    approval = OwnerApproval(digest, owner, valid_from, valid_until)
    object.__setattr__(approval, "_source_path", source_path)
    object.__setattr__(approval, "_source_directory_identity", source_directory_identity)
    object.__setattr__(approval, "_source_file_identity", source_file_identity)
    object.__setattr__(approval, "_source_bytes_sha256", source_bytes_sha256)
    if not _register_loaded_owner_approval(
        approval,
        restoration_context=restoration_context,
    ):
        _invalid(error_type, "INVALID_VALUE")
    return approval


def load_owner_approval(
    path: Path,
    session: SessionAuthorization,
    *,
    now: datetime | None = None,
) -> OwnerApproval:
    """Load the separately provisioned sidecar and verify its exact binding."""
    instant = now or datetime.now(timezone.utc)
    source_path = Path(path).absolute()
    encoded, directory_identity, file_identity = _read_private_approval_file(source_path)
    document = _parse_json(encoded, ApprovalError)
    return _validate_approval(
        document,
        session,
        instant,
        source_path,
        directory_identity,
        file_identity,
        hashlib.sha256(encoded).hexdigest(),
    )


def load_owner_approval_for_restoration(
    path: Path,
    session: SessionAuthorization,
    *,
    context: _RestorationApprovalContext,
    now: datetime | None = None,
) -> OwnerApproval:
    """Load an expired approval only for its exact durable restoration record."""
    instant = now or datetime.now(timezone.utc)
    if not _is_loaded_session_authorization(session):
        raise ApprovalError(ApprovalErrorCode.INVALID_VALUE)
    source_path = Path(path).absolute()
    encoded, directory_identity, file_identity = _read_private_approval_file(source_path)
    source_bytes_sha256 = hashlib.sha256(encoded).hexdigest()
    if not _restoration_context_matches(
        context,
        session,
        instant,
        source_path,
        directory_identity,
        file_identity,
        source_bytes_sha256,
    ):
        raise ApprovalError(ApprovalErrorCode.INVALID_VALUE)
    document = _parse_json(encoded, ApprovalError)
    return _validate_approval(
        document,
        session,
        instant,
        source_path,
        directory_identity,
        file_identity,
        source_bytes_sha256,
        restoration_context=context,
    )


def _owner_approval_source_matches(approval: object) -> bool:
    """Verify a loaded approval still matches its exact private sidecar bytes."""
    binding = _owner_approval_binding(approval)
    if binding is None:
        return False
    try:
        encoded, directory_identity, file_identity = _read_private_approval_file(binding.source_path)
    except ApprovalError:
        return False
    return (
        directory_identity == binding.source_directory_identity
        and file_identity == binding.source_file_identity
        and hashlib.sha256(encoded).hexdigest() == binding.source_bytes_sha256
    )


def _loaded_owner_approval_source_details(
    approval: object,
) -> tuple[Path, tuple[int, int], tuple[int, int], str] | None:
    """Return exact sidecar provenance for an unchanged ordinary approval."""
    binding = _owner_approval_binding(approval)
    if (
        binding is None
        or binding.restoration_context is not None
        or not _owner_approval_source_matches(approval)
    ):
        return None
    return (
        binding.source_path,
        binding.source_directory_identity,
        binding.source_file_identity,
        binding.source_bytes_sha256,
    )
