"""Shared result, grant, error, and fixture value types for host staging."""

from __future__ import annotations

import ctypes
import math
import os
import re
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from pathlib import Path, PurePosixPath
from scripts.android_qualification import manifest


class FixtureStagingErrorCode(str, Enum):
    """Sanitized reasons why host fixture preparation was refused."""

    INVALID_AUTHORITY = "FIXTURE_AUTHORITY_INVALID"
    AUTHORIZATION_EXPIRED = "FIXTURE_AUTHORIZATION_EXPIRED"
    OPERATION_UNAUTHORIZED = "FIXTURE_OPERATION_UNAUTHORIZED"
    INPUT_UNAVAILABLE = "FIXTURE_INPUT_UNAVAILABLE"
    INPUT_UNSAFE = "FIXTURE_INPUT_UNSAFE"
    INPUT_TOO_LARGE = "FIXTURE_INPUT_TOO_LARGE"
    INPUT_INVALID = "FIXTURE_INPUT_INVALID"
    DIGEST_MISMATCH = "FIXTURE_DIGEST_MISMATCH"
    PLAN_INVALID = "FIXTURE_PLAN_INVALID"
    MANIFEST_INVALID = "FIXTURE_MANIFEST_INVALID"
    EXPECTATION_UNVERIFIED = "FIXTURE_EXPECTATION_UNVERIFIED"
    STRUCTURAL_ONLY = "FIXTURE_STRUCTURAL_ONLY"
    SOURCE_INVALID = "FIXTURE_SOURCE_INVALID"
    SOURCE_CHANGED = "FIXTURE_SOURCE_CHANGED"
    CAPACITY_UNPROVEN = "FIXTURE_CAPACITY_UNPROVEN"
    CAPACITY_INSUFFICIENT = "FIXTURE_CAPACITY_INSUFFICIENT"
    DESTINATION_UNSAFE = "FIXTURE_DESTINATION_UNSAFE"
    COPY_INVALID = "FIXTURE_COPY_INVALID"
    OWNERSHIP_UNPROVEN = "FIXTURE_OWNERSHIP_UNPROVEN"
    CLEANUP_UNAUTHORIZED = "FIXTURE_CLEANUP_UNAUTHORIZED"
    CLEANUP_BLOCKED = "FIXTURE_CLEANUP_BLOCKED"
    BLOCKED_UNSUPPORTED_EXCLUSIVITY = "BLOCKED_UNSUPPORTED_EXCLUSIVITY"
    OPERATION_TIMEOUT = "FIXTURE_OPERATION_TIMEOUT"
    TIMING_UNVERIFIED = "FIXTURE_TIMING_UNVERIFIED"


_ERROR_TEXT = {
    code: "Owner-authorized fixture preparation is blocked" for code in FixtureStagingErrorCode
}


class FixtureStagingError(Exception):
    """A bounded error that never includes private paths or fixture values."""

    def __init__(self, code: FixtureStagingErrorCode) -> None:
        self.code = code
        super().__init__(_ERROR_TEXT[code])


def _monotonic_deadline_checker(
    clock,
    deadline: float,
    *,
    error_code: FixtureStagingErrorCode = FixtureStagingErrorCode.OPERATION_TIMEOUT,
):
    """Return a fail-closed check for one operation's monotonic deadline."""

    def check() -> None:
        try:
            current = clock()
        except Exception:
            raise FixtureStagingError(FixtureStagingErrorCode.OPERATION_TIMEOUT) from None

        if (
            type(current) not in {int, float}
            or not math.isfinite(current)
        ):
            raise FixtureStagingError(FixtureStagingErrorCode.OPERATION_TIMEOUT)
        if current >= deadline:
            raise FixtureStagingError(error_code)

    return check


class CoverageMode(str, Enum):
    """The plan's explicitly pinned fixture coverage obligation."""

    MANDATORY_FULL_PLAN = "mandatory_full_plan"
    AUTHORIZED_PARTIAL_PLAN = "authorized_partial_plan"


class IdentityEvidenceKind(str, Enum):
    """Owner-approved expectations are distinct from independent game identity."""

    OWNER_APPROVED_EXPECTATION_MATCH = "owner_approved_expectation_match"
    STRUCTURAL_ONLY = "structural_only"
    UNVERIFIED = "unverified"


@dataclass(frozen=True)
class FixtureFileExpectation:
    """One source member pinned by its owner-reviewed size and digest."""

    path: str
    role: str
    size: int
    sha256: str


@dataclass(frozen=True)
class CompanionEdge:
    """A relative descriptor-to-member relationship in a fixture graph."""

    source: str
    target: str


@dataclass(frozen=True)
class FixtureExpectation:
    """Owner-approved logical expectations and exact source membership."""

    fixture_id: str
    platform: str
    representation: str
    identity: str
    group_id: str
    order: int
    entrypoint: str
    files: tuple[FixtureFileExpectation, ...]
    companions: tuple[CompanionEdge, ...]
    identity_evidence: IdentityEvidenceKind


@dataclass(frozen=True)
class FixtureCoverage:
    """Pinned selection and full-versus-partial plan requirements."""

    mode: CoverageMode
    required_fixture_ids: tuple[str, ...]
    selected_fixture_ids: tuple[str, ...]
    mandatory_fixture_ids: tuple[str, ...]
    host_reserve_bytes: int
    destination_reserve_bytes: int
    cleanup_authorized: bool


@dataclass(frozen=True)
class _PrivateInputPin:
    path: Path
    parent_device: int
    parent_inode: int
    device: int
    inode: int
    size: int
    mtime_ns: int
    ctime_ns: int
    sha256: str
    source_sha256: str


@dataclass(frozen=True)
class FixtureStagingGrant:
    """Ephemeral authority to prepare only the pinned owner fixture inputs.

    A grant is issued by :func:`authorize_fixture_staging` only when the exact
    authorization and approval objects came from their strict loaders and the
    owner-approved plan and fixture manifest still match their pinned digests.
    """

    authorization_sha256: str
    approval_sha256: str
    approval_authorization_sha256: str
    fixture_manifest_sha256: str
    plan_sha256: str
    rules_sha256: str
    operation_id: str
    operation_timeout_seconds: int
    required_fixture_ids: tuple[str, ...]
    fixture_ids: tuple[str, ...]
    coverage_mode: str
    scenario_ids: tuple[str, ...]
    host_reserve_bytes: int
    destination_reserve_bytes: int
    cleanup_authorized: bool
    _authorization: manifest.SessionAuthorization = field(repr=False, compare=False)
    _approval: manifest.OwnerApproval = field(repr=False, compare=False)
    _fixture_expectations: tuple[FixtureExpectation, ...] = field(repr=False, compare=False)
    _plan_pin: _PrivateInputPin = field(repr=False, compare=False)
    _fixture_pin: _PrivateInputPin = field(repr=False, compare=False)
    _seal: object = field(repr=False, compare=False)

    @property
    def device_admitted(self) -> bool:
        """Host preparation never constitutes device admission."""

        return False

    @property
    def session_authorization_consumed(self) -> bool:
        """Preparation leaves the later single-use admission authority intact."""

        return False

    @property
    def result_kind(self) -> str:
        """Identify the result as host preparation, never product qualification."""

        return "HOST_PREPARATION_ONLY"

    @property
    def required_fixture_count(self) -> int:
        """Return the count of plan-required fixture identifiers."""

        return len(self.required_fixture_ids)



@dataclass(frozen=True)
class CapacityObservation:
    """A single host and injected-destination free-space measurement."""

    host_free_bytes: int
    destination_free_bytes: int


@dataclass(frozen=True)
class FixtureStagingResult:
    """Sanitized host-preparation outcome for one uniquely owned session."""

    status: str
    result_kind: str
    evidence_class: str
    blocker_code: str | None
    session_id: str
    fixture_count: int
    file_count: int
    verified_bytes: int
    identity_evidence: str
    coverage_mode: str
    required_fixture_count: int
    selected_fixture_count: int
    device_admitted: bool = False
    session_authorization_consumed: bool = False


@dataclass(frozen=True)
class RecoveryObligation:
    """Private state summary for an interrupted or blocked staging session."""

    session_id: str
    state: str
    blocker_code: str | None
    ownership_proven: bool


@dataclass(frozen=True)
class FixtureCleanupResult:
    """Outcome of explicit cleanup for one proven owned staging session."""

    status: str
    blocker_code: str | None
    session_id: str
    removed: bool


_OPERATION_TIMING_SCHEMA_VERSION = 1
_OPERATION_TIMING_FIELDS = {
    "schema_version",
    "clock_kind",
    "boot_identity_kind",
    "boot_id",
    "operation_id",
    "authorization_sha256",
    "plan_sha256",
    "fixture_manifest_sha256",
    "approval_sha256",
    "monotonic_start_ns",
    "wall_time_start_ns",
    "operation_deadline_monotonic_ns",
    "staging_authorization_deadline_monotonic_ns",
    "cleanup_authorization_deadline_monotonic_ns",
    "cleanup_reserve_deadline_monotonic_ns",
}
def _datetime_ns(value: datetime) -> int:
    """Convert an aware datetime to exact integer UTC nanoseconds."""
    if type(value) is not datetime or value.tzinfo is None:
        raise FixtureStagingError(FixtureStagingErrorCode.TIMING_UNVERIFIED)
    normalized = value.astimezone(timezone.utc)
    epoch = datetime(1970, 1, 1, tzinfo=timezone.utc)
    delta = normalized - epoch
    return (
        (delta.days * 86_400 + delta.seconds) * 1_000_000_000
        + delta.microseconds * 1_000
    )


def _read_monotonic_ns(clock) -> int:
    """Read the trusted monotonic clock as integer nanoseconds."""
    try:
        value = clock()
    except Exception:
        raise FixtureStagingError(FixtureStagingErrorCode.OPERATION_TIMEOUT) from None
    if (
        type(value) not in {int, float}
        or not math.isfinite(value)
        or value < 0
    ):
        raise FixtureStagingError(FixtureStagingErrorCode.OPERATION_TIMEOUT)
    return int(value * 1_000_000_000)


def _boot_identity() -> tuple[str, str]:
    """Return a stable identifier for the current operating-system boot."""
    if sys.platform.startswith("linux"):
        try:
            with open("/proc/sys/kernel/random/boot_id", "rb") as stream:
                value = stream.read(128).decode("ascii").strip()
        except (OSError, UnicodeDecodeError):
            value = ""
        if re.fullmatch(r"[0-9a-fA-F-]{16,128}", value):
            return value.lower(), "linux-boot-id"
        raise FixtureStagingError(FixtureStagingErrorCode.TIMING_UNVERIFIED)
    if sys.platform == "darwin":
        try:
            libc = ctypes.CDLL(None)
            sysctlbyname = libc.sysctlbyname
            sysctlbyname.argtypes = [
                ctypes.c_char_p,
                ctypes.c_void_p,
                ctypes.POINTER(ctypes.c_size_t),
                ctypes.c_void_p,
                ctypes.c_size_t,
            ]
            sysctlbyname.restype = ctypes.c_int
            size = ctypes.c_size_t(0)
            name = b"kern.bootsessionuuid"
            if sysctlbyname(name, None, ctypes.byref(size), None, 0) == 0 and size.value:
                buffer = ctypes.create_string_buffer(size.value)
                if sysctlbyname(name, buffer, ctypes.byref(size), None, 0) == 0:
                    value = buffer.value.decode("ascii").strip()
                    if re.fullmatch(r"[0-9a-fA-F-]{16,128}", value):
                        return value.lower(), "macos-boot-session-uuid"
        except (OSError, UnicodeDecodeError, ValueError):
            pass
        raise FixtureStagingError(FixtureStagingErrorCode.TIMING_UNVERIFIED)
    raise FixtureStagingError(FixtureStagingErrorCode.TIMING_UNVERIFIED)


def _new_operation_timing(
    grant: FixtureStagingGrant,
    instant: datetime,
    clock,
) -> dict[str, object]:
    """Capture one immutable operation timeline before fixture mutation.

    The operation deadline is the sole end boundary for staging, cleanup, and
    recovery. The cleanup reserve identifies the final interval inside that
    same timeline; it is not an independently renewable cleanup budget.
    """
    try:
        boot_id, boot_identity_kind = _boot_identity()
        started_monotonic_ns = _read_monotonic_ns(clock)
        started_wall_ns = _datetime_ns(instant)
        staging_expiry = min(
            grant._authorization.session_deadline,
            grant._approval.valid_until,
        )
        staging_deadline_wall_ns = _datetime_ns(staging_expiry)
        cleanup_deadline_wall_ns = _datetime_ns(
            grant._authorization.cleanup_deadline
        )
        reserve_seconds = grant._authorization.cleanup_reserve_seconds
        if type(reserve_seconds) is not int or reserve_seconds <= 0:
            raise FixtureStagingError(FixtureStagingErrorCode.TIMING_UNVERIFIED)
        if (
            started_wall_ns >= staging_deadline_wall_ns
            or started_wall_ns >= cleanup_deadline_wall_ns
        ):
            raise FixtureStagingError(
                FixtureStagingErrorCode.AUTHORIZATION_EXPIRED
            )
    except FixtureStagingError:
        raise
    except Exception:
        raise FixtureStagingError(
            FixtureStagingErrorCode.TIMING_UNVERIFIED
        ) from None
    operation_deadline_monotonic_ns = (
        started_monotonic_ns
        + grant.operation_timeout_seconds * 1_000_000_000
    )
    reserve_ns = reserve_seconds * 1_000_000_000
    return {
        "schema_version": _OPERATION_TIMING_SCHEMA_VERSION,
        "clock_kind": "monotonic-since-boot",
        "boot_identity_kind": boot_identity_kind,
        "boot_id": boot_id,
        "operation_id": grant.operation_id,
        "authorization_sha256": grant.authorization_sha256,
        "plan_sha256": grant.plan_sha256,
        "fixture_manifest_sha256": grant.fixture_manifest_sha256,
        "approval_sha256": grant.approval_sha256,
        "monotonic_start_ns": started_monotonic_ns,
        "wall_time_start_ns": started_wall_ns,
        "operation_deadline_monotonic_ns": operation_deadline_monotonic_ns,
        "staging_authorization_deadline_monotonic_ns": (
            started_monotonic_ns
            + (staging_deadline_wall_ns - started_wall_ns)
        ),
        "cleanup_authorization_deadline_monotonic_ns": (
            started_monotonic_ns
            + (cleanup_deadline_wall_ns - started_wall_ns)
        ),
        # This field is retained for state-schema compatibility. Its value is
        # the start of the final reserve interval inside the original
        # operation timeline, not an earlier cleanup expiry.
        "cleanup_reserve_deadline_monotonic_ns": max(
            started_monotonic_ns,
            operation_deadline_monotonic_ns - reserve_ns,
        ),
    }


def _validate_operation_timing(value: object) -> dict[str, object]:
    """Validate persisted timing evidence without trusting caller timestamps."""
    if type(value) is not dict or set(value) != _OPERATION_TIMING_FIELDS:
        raise FixtureStagingError(FixtureStagingErrorCode.TIMING_UNVERIFIED)
    if (
        value.get("schema_version") != _OPERATION_TIMING_SCHEMA_VERSION
        or value.get("clock_kind") != "monotonic-since-boot"
        or value.get("boot_identity_kind")
        not in {"linux-boot-id", "macos-boot-session-uuid"}
        or type(value.get("boot_id")) is not str
        or re.fullmatch(r"[0-9a-f-]{16,128}", value["boot_id"]) is None
        or any(
            type(value.get(field)) is not str or not value[field]
            for field in (
                "operation_id",
                "authorization_sha256",
                "plan_sha256",
                "fixture_manifest_sha256",
                "approval_sha256",
            )
        )
    ):
        raise FixtureStagingError(FixtureStagingErrorCode.TIMING_UNVERIFIED)
    for field in (
        "monotonic_start_ns",
        "wall_time_start_ns",
        "operation_deadline_monotonic_ns",
        "staging_authorization_deadline_monotonic_ns",
        "cleanup_authorization_deadline_monotonic_ns",
        "cleanup_reserve_deadline_monotonic_ns",
    ):
        if type(value.get(field)) is not int or value[field] < 0:
            raise FixtureStagingError(
                FixtureStagingErrorCode.TIMING_UNVERIFIED
            )
    started = value["monotonic_start_ns"]
    if any(
        value[field] < started
        for field in (
            "operation_deadline_monotonic_ns",
            "staging_authorization_deadline_monotonic_ns",
            "cleanup_authorization_deadline_monotonic_ns",
            "cleanup_reserve_deadline_monotonic_ns",
        )
    ):
        raise FixtureStagingError(FixtureStagingErrorCode.TIMING_UNVERIFIED)
    return value


def _check_operation_timing(
    timing: object,
    *,
    clock,
    mode: str,
) -> None:
    """Fail closed unless persisted boot-relative timing authorizes this action.

    Wall-clock values are captured only to translate the pinned authorization
    deadlines into the boot-relative timeline. They are not consulted again,
    so a host wall-clock adjustment cannot renew or bypass the original timing.
    Cleanup and recovery remain eligible through the original operation
    deadline. The persisted reserve boundary records the final portion of that
    timeline and never shortens or extends cleanup authority.
    An elapsed authorization boundary is reported before an elapsed operation
    deadline so a resumed action cannot disguise expired authority as a timeout.
    """
    value = _validate_operation_timing(timing)
    if mode not in {"staging", "cleanup"}:
        raise FixtureStagingError(FixtureStagingErrorCode.TIMING_UNVERIFIED)
    current_boot = _boot_identity()[0]
    if current_boot != value["boot_id"]:
        raise FixtureStagingError(FixtureStagingErrorCode.TIMING_UNVERIFIED)
    current_monotonic = _read_monotonic_ns(clock)
    started = value["monotonic_start_ns"]
    if current_monotonic < started:
        raise FixtureStagingError(FixtureStagingErrorCode.TIMING_UNVERIFIED)
    if mode == "staging":
        if current_monotonic >= value["staging_authorization_deadline_monotonic_ns"]:
            raise FixtureStagingError(
                FixtureStagingErrorCode.AUTHORIZATION_EXPIRED
            )
    else:
        if current_monotonic >= value["cleanup_authorization_deadline_monotonic_ns"]:
            raise FixtureStagingError(
                FixtureStagingErrorCode.AUTHORIZATION_EXPIRED
            )
    if current_monotonic >= value["operation_deadline_monotonic_ns"]:
        raise FixtureStagingError(FixtureStagingErrorCode.OPERATION_TIMEOUT)
