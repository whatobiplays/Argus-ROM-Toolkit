"""Coordinate host-only fixture staging and explicitly authorized cleanup."""

from __future__ import annotations
from datetime import datetime
from collections.abc import Mapping
from pathlib import Path
import os
import re
import time
from ._fixture_staging_model import FixtureCleanupResult, FixtureStagingError, FixtureStagingErrorCode, FixtureStagingGrant, FixtureStagingResult, IdentityEvidenceKind, _classify_identity_evidence, _new_operation_timing
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
from . import _fixture_staging_native
from ._fixture_staging_session import (
    AuthenticatedXPCReply,
    OwnerExportDispatch,
    OwnerSessionExportClient,
)
from ._fixture_staging_export_evidence import (
    ExportEvidenceV1,
    ProductionAdmissionIssuer,
)


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


def _consume_production_export(
    grant: FixtureStagingGrant,
    owner_export: OwnerExportDispatch,
) -> FixtureStagingResult:
    """Build an export result only from the dispatch client's verified receipt."""

    try:
        reply = owner_export.dispatch()
    except Exception:
        # The durable owner journal retains any uncertain mutation for query-only
        # recovery; convert transport or journal failures into a blocked result.
        return _blocked_production_staging_result(
            FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY
        )
    attempt = owner_export.attempt
    receipt = reply.receipt if isinstance(reply, AuthenticatedXPCReply) else None
    members = receipt.get("members") if isinstance(receipt, Mapping) else None
    if (
        not isinstance(reply, AuthenticatedXPCReply)
        or reply.service_identity
        != getattr(owner_export.client, "_service_identity", None)
        or reply.broker_identity
        != getattr(owner_export.client, "_broker_identity", None)
        or not isinstance(receipt, Mapping)
        or receipt.get("status") != "VERIFIED_RECEIVER_COMPLETION"
        or receipt.get("code") != "BROKER_RECEIVER_RECEIPT_DURABLE"
        or receipt.get("durable") is not True
        or receipt.get("request_id") != attempt.get("request_id")
        or receipt.get("session_id") != attempt.get("session_id")
        or receipt.get("service_boot_id") != attempt.get("service_boot_id")
        or receipt.get("sequence") != attempt.get("sequence")
        or receipt.get("deadline_ns") != attempt.get("deadline_ns")
        or receipt.get("manifest_sha256") != grant.fixture_manifest_sha256
        or receipt.get("generation") != attempt.get("generation")
        or receipt.get("authorization_sha256") != grant.authorization_sha256
        or not isinstance(members, list)
        or members != attempt.get("members")
        or type(receipt.get("member_count")) is not int
        or receipt.get("member_count") != len(members)
        or not isinstance(receipt.get("frame_sha256"), str)
        or not isinstance(receipt.get("receipt_sha256"), str)
        or not isinstance(receipt.get("receipt_path"), str)
        or not os.path.isabs(receipt["receipt_path"])
    ):
        raise FixtureStagingError(FixtureStagingErrorCode.INVALID_AUTHORITY)

    # Preserve the native receipt as an opaque, authenticated member of the
    # versioned owner record. The contract independently binds it to the
    # journal attempt before any production export result is constructed.
    evidence = ProductionAdmissionIssuer(owner_export.client).issue(attempt, receipt)

    fixture_count = len(grant._fixture_expectations)
    required_fixture_count = len(grant.required_fixture_ids)
    return FixtureStagingResult(
        "VERIFIED_FIXTURE",
        "PRODUCTION_NATIVE_EXPORT",
        "DURABLE_RECEIVER_COMPLETION",
        None,
        evidence.session,
        fixture_count,
        receipt["member_count"],
        sum(member["size"] for member in members),
        IdentityEvidenceKind.UNVERIFIED.value,
        grant.coverage_mode,
        required_fixture_count,
        fixture_count,
        False,
        False,
    )


def _stage_production_export(
    grant: FixtureStagingGrant,
    preparation: _fixture_staging_native.ProductionOwnerExportPreparation | None,
) -> FixtureStagingResult:
    """Bind a deferred export preparation to the grant before native work."""

    try:
        _admit_production_staging_namespace()
    except FixtureStagingError as error:
        return _blocked_production_staging_result(error.code)

    try:
        validated_grant = _validate_grant_for_use(grant, _authority._utc_now())
        if (
            not isinstance(
                preparation,
                _fixture_staging_native.ProductionOwnerExportPreparation,
            )
            or preparation._seal
            is not _fixture_staging_native._OWNER_EXPORT_PREPARATION_SEAL
            or preparation.grant is not validated_grant
            or preparation.attempt_manifest_sha256
            != validated_grant.fixture_manifest_sha256
            or preparation.attempt_authorization_sha256
            != validated_grant.authorization_sha256
        ):
            raise FixtureStagingError(FixtureStagingErrorCode.INVALID_AUTHORITY)
        _fixture_staging_native._validate_production_owner_export_preparation_inputs(
            validated_grant, preparation
        )
    except FixtureStagingError as error:
        return _blocked_production_staging_result(error.code)

    try:
        native = _fixture_staging_native.select_verified_native_installation()
    except FixtureStagingError:
        native = None
    if (
        not isinstance(native, _fixture_staging_native.VerifiedNativeInstallation)
        or not native.operation_enabled
    ):
        return _blocked_production_staging_result(
            FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY
        )

    try:
        owner_export = preparation._prepare(native)
        if (
            not isinstance(owner_export, OwnerExportDispatch)
            or not isinstance(owner_export.client, OwnerSessionExportClient)
            or owner_export.client._test_transport
            or owner_export.client._installation is not native
            or owner_export.client._installation._seal is not native._seal
        ):
            return _blocked_production_staging_result(
                FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY
            )
        if not isinstance(owner_export.attempt, Mapping):
            raise FixtureStagingError(FixtureStagingErrorCode.INVALID_AUTHORITY)
        attempt = owner_export.attempt
        if (
            attempt.get("manifest_sha256") != validated_grant.fixture_manifest_sha256
            or attempt.get("authorization_sha256")
            != validated_grant.authorization_sha256
        ):
            raise FixtureStagingError(FixtureStagingErrorCode.INVALID_AUTHORITY)
        return _consume_production_export(validated_grant, owner_export)
    except FixtureStagingError as error:
        return _blocked_production_staging_result(error.code)
    except Exception:
        return _blocked_production_staging_result(
            FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY
        )


def _stage_fixtures_impl(
    grant: FixtureStagingGrant,
    *,
    source_roots: dict[str, Path],
    destination: FilesystemFixtureDestination,
    cancellation=None,
) -> FixtureStagingResult:
    """Stage fixture files through the filesystem staging workflow."""

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
    identity_evidence = _classify_identity_evidence(
        {item.identity_evidence for item in grant._fixture_expectations}
    )
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
        identity_evidence.value,
        grant.coverage_mode,
        required_fixture_count,
        fixture_count,
    )


def stage_fixtures(
    grant: FixtureStagingGrant,
    *,
    source_roots: dict[str, Path],
    destination: FilesystemFixtureDestination | None,
    now: datetime | None = None,
    cancellation=None,
    owner_export_preparation: (
        _fixture_staging_native.ProductionOwnerExportPreparation | None
    ) = None,
) -> FixtureStagingResult:
    """Stage a complete fixture set only behind kernel-enforced isolation.

    On hosts without that isolation, return ``BLOCKED_UNSUPPORTED_EXCLUSIVITY``
    before reading the grant, export request, source descriptors, or destination.
    After admission, production export requires a sealed native installation
    and a deferred preparation bound to the exact grant and its manifest and
    authorization digests. Staging checks that binding before it invokes native
    preparation, then checks the returned attempt before dispatch. The lifecycle
    journal records the attempt before the broker attaches open source
    descriptors over XPC.
    """

    if destination is None:
        return _stage_production_export(grant, owner_export_preparation)
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
    """Refuse deletion and record a durable follow-up when exclusivity is absent."""
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
