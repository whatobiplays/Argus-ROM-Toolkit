"""Coordinate host-only fixture staging and explicitly authorized cleanup."""

from __future__ import annotations
from datetime import datetime
from pathlib import Path
import re
import time
from ._fixture_staging_model import FixtureCleanupResult, FixtureStagingError, FixtureStagingErrorCode, FixtureStagingGrant, FixtureStagingResult, IdentityEvidenceKind, _new_operation_timing
from . import _fixture_staging_manifest as _authority
from ._fixture_staging_manifest import _validate_grant_for_use
from ._fixture_staging_transfer import (
    _ensure_capacity,
    _preflight_staging_sources,
    _staging_deadline_checker,
    _transfer_and_verify_fixture_set,
)
from ._fixture_staging_destination import (
    FilesystemFixtureDestination,
    _admit_production_staging_namespace,
)
from ._fixture_staging_ownership import _exists_nofollow, _validate_session_id
from . import _fixture_staging_ownership as staging_ownership


def _blocked_result(
    destination: FilesystemFixtureDestination,
    session_id: str,
    code: FixtureStagingErrorCode,
    *,
    fixture_count: int,
    file_count: int,
    verified_bytes: int,
    coverage_mode: str,
    required_fixture_count: int,
) -> FixtureStagingResult:
    """Build an in-memory blocker result without destination mutation."""

    return FixtureStagingResult(
        "BLOCKED",
        "HOST_PREPARATION_ONLY",
        "BLOCKED_UNVERIFIED",
        code.value,
        session_id,
        fixture_count,
        file_count,
        verified_bytes,
        IdentityEvidenceKind.UNVERIFIED.value,
        coverage_mode,
        required_fixture_count,
        fixture_count,
    )


def _blocked_production_staging_result(
    code: FixtureStagingErrorCode,
) -> FixtureStagingResult:
    """Return a production blocker without inspecting any caller argument.

    Production exclusivity is unsupported on this host, so the result cannot
    safely derive counts or coverage from a grant that has not been validated.
    The zero-valued fields explicitly represent that unavailable evidence.
    """

    return FixtureStagingResult(
        "BLOCKED",
        "HOST_PREPARATION_ONLY",
        "BLOCKED_UNVERIFIED",
        code.value,
        "",
        0,
        0,
        0,
        IdentityEvidenceKind.UNVERIFIED.value,
        "",
        0,
        0,
    )


def _stage_fixtures_impl(
    grant: FixtureStagingGrant,
    *,
    source_roots: dict[str, Path],
    destination: FilesystemFixtureDestination,
    cancellation=None,
) -> FixtureStagingResult:
    """Fail production staging before inspecting any caller-supplied value.

    The host does not provide kernel-enforced destination exclusivity. The
    public entry point reaches this function without touching its arguments,
    and the admission check must therefore be the first operation here. If a
    future host supplies an admitted production namespace, the existing grant
    validation, destination rebuilding, source preflight, and mutation checks
    remain as defense in depth.
    """

    try:
        _admit_production_staging_namespace()
    except FixtureStagingError as error:
        return _blocked_production_staging_result(error.code)

    grant = _validate_grant_for_use(grant, _authority._utc_now())
    if type(destination) is not FilesystemFixtureDestination:
        raise FixtureStagingError(
            FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY
        )
    root = object.__getattribute__(destination, "root")
    if not isinstance(root, Path):
        raise FixtureStagingError(FixtureStagingErrorCode.DESTINATION_UNSAFE)
    destination = FilesystemFixtureDestination(root)
    fixture_count = len(grant._fixture_expectations)
    file_count = sum(len(item.files) for item in grant._fixture_expectations)
    required_fixture_count = len(grant.required_fixture_ids)

    try:
        _preflight_staging_sources(
            destination,
            grant,
            source_roots,
            capability=None,
            capacity_access_admission=_admit_production_staging_namespace,
        )
    except FixtureStagingError as error:
        return _blocked_result(
            destination,
            "",
            error.code,
            fixture_count=fixture_count,
            file_count=file_count,
            verified_bytes=0,
            coverage_mode=grant.coverage_mode,
            required_fixture_count=required_fixture_count,
        )
    except (InterruptedError, KeyboardInterrupt):
        return _blocked_result(
            destination,
            "",
            FixtureStagingErrorCode.COPY_INVALID,
            fixture_count=fixture_count,
            file_count=file_count,
            verified_bytes=0,
            coverage_mode=grant.coverage_mode,
            required_fixture_count=required_fixture_count,
        )
    except Exception:
        return _blocked_result(
            destination,
            "",
            FixtureStagingErrorCode.OPERATION_TIMEOUT,
            fixture_count=fixture_count,
            file_count=file_count,
            verified_bytes=0,
            coverage_mode=grant.coverage_mode,
            required_fixture_count=required_fixture_count,
        )

    raise AssertionError("production admission must fail closed")


def _stage_fixtures_with_capability(
    grant: FixtureStagingGrant,
    *,
    source_roots: dict[str, Path],
    destination: FilesystemFixtureDestination,
    capability,
    cancellation=None,
) -> FixtureStagingResult:
    """Stream, verify and atomically publish a complete host-only fixture set.

    All source and destination access is performed through local filesystem
    handles. A future device adapter is intentionally outside this contract.
    """

    staging_ownership._require_namespace_capability(capability, origin="synthetic")
    destination._require_admitted_capability(capability)
    instant = _authority._utc_now()
    grant = _validate_grant_for_use(grant, instant)
    fixture_count = len(grant._fixture_expectations)
    file_count = sum(len(item.files) for item in grant._fixture_expectations)
    required_fixture_count = len(grant.required_fixture_ids)
    clock = capability.monotonic_clock or staging_ownership._monotonic_now
    try:
        operation_timing = _new_operation_timing(grant, instant, clock)
        check_deadline = _staging_deadline_checker(
            grant,
            instant,
            clock,
            operation_timing=operation_timing,
        )
    except FixtureStagingError as error:
        return _blocked_result(
            destination,
            "",
            error.code,
            fixture_count=fixture_count,
            file_count=file_count,
            verified_bytes=0,
            coverage_mode=grant.coverage_mode,
            required_fixture_count=required_fixture_count,
        )
    except Exception:
        return _blocked_result(
            destination,
            "",
            FixtureStagingErrorCode.OPERATION_TIMEOUT,
            fixture_count=fixture_count,
            file_count=file_count,
            verified_bytes=0,
            coverage_mode=grant.coverage_mode,
            required_fixture_count=required_fixture_count,
        )

    def admit_capacity_access():
        """Return the explicit mechanics capability after read-only preflight."""

        destination._require_admitted_capability(capability)
        return capability

    try:
        snapshots, total_bytes, capability = _preflight_staging_sources(
            destination,
            grant,
            source_roots,
            capability=capability,
            capacity_access_admission=admit_capacity_access,
        )
    except FixtureStagingError as error:
        return _blocked_result(
            destination,
            "",
            error.code,
            fixture_count=fixture_count,
            file_count=file_count,
            verified_bytes=0,
            coverage_mode=grant.coverage_mode,
            required_fixture_count=required_fixture_count,
        )
    except (InterruptedError, KeyboardInterrupt):
        return _blocked_result(
            destination,
            "",
            FixtureStagingErrorCode.COPY_INVALID,
            fixture_count=fixture_count,
            file_count=file_count,
            verified_bytes=0,
            coverage_mode=grant.coverage_mode,
            required_fixture_count=required_fixture_count,
        )

    session_id = ""
    token = ""
    copied_bytes = [0]
    verified_bytes = [0]
    try:
        _ensure_capacity(
            destination,
            grant,
            total_bytes,
            check_deadline=check_deadline,
            capability=capability,
        )
        check_deadline()
        session_id, token = destination._ownership.reserve_session(
            grant,
            capability=capability,
        )
        check_deadline()
        if _exists_nofollow(
            destination._ownership.final_root(session_id)
        ) or _exists_nofollow(
            destination._ownership.temporary_root(session_id)
        ):
            raise FixtureStagingError(FixtureStagingErrorCode.DESTINATION_UNSAFE)
        destination._create_quarantine(
            session_id,
            token,
            grant,
            capability=capability,
        )
        check_deadline()
        _transfer_and_verify_fixture_set(
            snapshots,
            destination=destination,
            grant=grant,
            session_id=session_id,
            ownership_token=token,
            total_bytes=total_bytes,
            copied_bytes=copied_bytes,
            verified_bytes=verified_bytes,
            check_deadline=check_deadline,
            cancellation=cancellation,
            capability=capability,
        )
        destination._publish_and_confirm(
            session_id,
            token,
            grant=grant,
            capability=capability,
        )
    except FixtureStagingError as error:
        blocker_code = error.code
        if session_id and token:
            blocker_code = destination._ownership.mark_blocked_or_destination_unsafe(
                session_id,
                token,
                error.code,
                capability=capability,
            )
        return _blocked_result(
            destination,
            session_id,
            blocker_code,
            fixture_count=fixture_count,
            file_count=file_count,
            verified_bytes=verified_bytes[0],
            coverage_mode=grant.coverage_mode,
            required_fixture_count=required_fixture_count,
        )
    except (InterruptedError, KeyboardInterrupt):
        blocker_code = FixtureStagingErrorCode.COPY_INVALID
        if session_id and token:
            blocker_code = destination._ownership.mark_blocked_or_destination_unsafe(
                session_id,
                token,
                blocker_code,
                capability=capability,
            )
        return _blocked_result(
            destination,
            session_id,
            blocker_code,
            fixture_count=fixture_count,
            file_count=file_count,
            verified_bytes=verified_bytes[0],
            coverage_mode=grant.coverage_mode,
            required_fixture_count=required_fixture_count,
        )
    except Exception:
        blocker_code = FixtureStagingErrorCode.COPY_INVALID
        if session_id and token:
            blocker_code = destination._ownership.mark_blocked_or_destination_unsafe(
                session_id,
                token,
                blocker_code,
                capability=capability,
            )
        return _blocked_result(
            destination,
            session_id,
            blocker_code,
            fixture_count=fixture_count,
            file_count=file_count,
            verified_bytes=verified_bytes[0],
            coverage_mode=grant.coverage_mode,
            required_fixture_count=required_fixture_count,
        )
    return FixtureStagingResult(
        "VERIFIED_FIXTURE",
        "HOST_PREPARATION_ONLY",
        "SYNTHETIC_SIMULATION",
        None,
        session_id,
        fixture_count,
        file_count,
        verified_bytes[0],
        IdentityEvidenceKind.OWNER_APPROVED_EXPECTATION_MATCH.value,
        grant.coverage_mode,
        required_fixture_count,
        fixture_count,
    )


def stage_fixtures(
    grant: FixtureStagingGrant,
    *,
    source_roots: dict[str, Path],
    destination: FilesystemFixtureDestination,
    now: datetime | None = None,
    cancellation=None,
) -> FixtureStagingResult:
    """Stage a complete fixture set only behind kernel-enforced isolation.

    On hosts without that isolation, return ``BLOCKED_UNSUPPORTED_EXCLUSIVITY``
    without reading the grant, converting source paths, consulting the
    destination, invoking callbacks, creating locks or state, or mutating the
    filesystem. A future admitted implementation retains source and capacity
    preflight plus mutation checks as defense in depth.
    """

    return _stage_fixtures_impl(
        grant,
        source_roots=source_roots,
        destination=destination,
        cancellation=cancellation,
    )


def _cleanup_fixture_staging_impl(
    grant: FixtureStagingGrant,
    *,
    destination: FilesystemFixtureDestination,
    session_id: str,
    now: datetime | None = None,
) -> FixtureCleanupResult:
    """Refuse production cleanup before inspecting grant or destination."""
    try:
        _admit_production_staging_namespace()
    except FixtureStagingError as error:
        return FixtureCleanupResult("BLOCKED", error.code.value, session_id, False)

    try:
        grant = _validate_grant_for_use(
            grant,
            _authority._utc_now(),
            cleanup_window=True,
        )
    except FixtureStagingError as error:
        return FixtureCleanupResult("BLOCKED", error.code.value, session_id, False)
    if not grant.cleanup_authorized:
        return FixtureCleanupResult(
            "BLOCKED",
            FixtureStagingErrorCode.CLEANUP_UNAUTHORIZED.value,
            session_id,
            False,
        )
    if type(destination) is not FilesystemFixtureDestination:
        return FixtureCleanupResult(
            "BLOCKED",
            FixtureStagingErrorCode.DESTINATION_UNSAFE.value,
            session_id,
            False,
        )
    root = object.__getattribute__(destination, "root")
    if not isinstance(root, Path):
        return FixtureCleanupResult(
            "BLOCKED",
            FixtureStagingErrorCode.DESTINATION_UNSAFE.value,
            session_id,
            False,
        )
    FilesystemFixtureDestination(root)
    raise AssertionError("production cleanup admission must fail closed")


def cleanup_fixture_staging(
    grant: FixtureStagingGrant,
    *,
    destination: FilesystemFixtureDestination,
    session_id: str,
    now: datetime | None = None,
) -> FixtureCleanupResult:
    """Clean up only behind production exclusivity and pinned authorization.

    Production cleanup currently returns ``BLOCKED_UNSUPPORTED_EXCLUSIVITY``
    before reading the grant or destination. The legacy ``now`` argument
    remains accepted for call compatibility; any future admitted deletion uses
    the trusted UTC clock throughout.
    """

    return _cleanup_fixture_staging_impl(
        grant,
        destination=destination,
        session_id=session_id,
        now=now,
    )


def _cleanup_fixture_staging_with_capability(
    grant: FixtureStagingGrant,
    *,
    destination: FilesystemFixtureDestination,
    session_id: str,
    capability,
) -> FixtureCleanupResult:
    """Validate authority and enforce isolation before mutation."""

    try:
        staging_ownership._require_namespace_capability(capability, origin="synthetic")
        destination._require_admitted_capability(capability)
    except FixtureStagingError as error:
        return FixtureCleanupResult("BLOCKED", error.code.value, session_id, False)
    try:
        grant = _validate_grant_for_use(
            grant, _authority._utc_now(), cleanup_window=True
        )
    except FixtureStagingError as error:
        return FixtureCleanupResult("BLOCKED", error.code.value, session_id, False)
    if not grant.cleanup_authorized:
        return FixtureCleanupResult(
            "BLOCKED", FixtureStagingErrorCode.CLEANUP_UNAUTHORIZED.value, session_id, False
        )
    try:
        with destination._ownership.coordination_lock(
            create_state_directory=True,
            capability=capability,
        ):
            return _cleanup_fixture_staging_locked(
                grant,
                destination=destination,
                session_id=session_id,
                capability=capability,
            )
    except FixtureStagingError as error:
        return FixtureCleanupResult("BLOCKED", error.code.value, session_id, False)


def _cleanup_fixture_staging_locked(
    grant: FixtureStagingGrant,
    *,
    destination: FilesystemFixtureDestination,
    session_id: str,
    capability,
) -> FixtureCleanupResult:
    """Validate and update one recovery record under the destination lock."""

    try:
        _validate_session_id(session_id)
        record = destination._ownership._load_state(session_id)
        if (
            record.get("authorization_sha256") != grant.authorization_sha256
            or record.get("plan_sha256") != grant.plan_sha256
            or record.get("fixture_manifest_sha256") != grant.fixture_manifest_sha256
            or record.get("state")
            not in {
                "published",
                "publication_pending",
                "blocked",
                "preparing",
                "cleanup_in_progress",
            }
        ):
            raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
        token = record.get("ownership_token")
        if type(token) is not str:
            raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
        destination._ownership.remove_owned_session(
            session_id,
            token,
            grant=grant,
            capability=capability,
        )
    except FixtureStagingError as error:
        blocker_code = error.code
        try:
            if type(session_id) is str and re.fullmatch(r"[0-9a-f]{32}", session_id):
                record = destination._ownership._load_state(session_id)
                token = record.get("ownership_token")
                if type(token) is str:
                    blocker_code = destination._ownership.mark_blocked_or_destination_unsafe(
                        session_id,
                        token,
                        error.code,
                        capability=capability,
                    )
        except FixtureStagingError:
            pass
        return FixtureCleanupResult("BLOCKED", blocker_code.value, session_id, False)
    return FixtureCleanupResult("CLEANUP_COMPLETE", None, session_id, True)
