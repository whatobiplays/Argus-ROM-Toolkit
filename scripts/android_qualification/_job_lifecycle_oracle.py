"""Pure Issue #28 lifecycle classification and latency contract.

The oracle consumes typed observations. It cannot read a device, append
evidence, issue an owner verdict, or infer job identity from presentation
order. Missing or conflicting facts become BLOCKED; only a proven product
contradiction becomes FAILED.
"""

from __future__ import annotations

from dataclasses import dataclass
import math
import re

from . import evidence
from ._job_lifecycle_contract import (
    ACTIVE_STATES,
    ROOT_HISTORICAL_SCAN_STATES,
    JOB_LIFECYCLE_ORACLE_SHA256,
    JOB_LIFECYCLE_ORACLE_VERSION,
    LibrarySurfaceObservation,
    LibraryScanChildCompletion,
    TERMINAL_STATES,
    JobIdentityObservation,
    GameIdContinuityObservation,
    GameIdRedirect,
    LatencyCriterion,
    LatencyCycle,
    _LATENCY_POLICY_DECLARATION,
    ProcessAndForegroundObservation,
    ProcessState,
    RecoveryState,
    RefreshDetailObservation,
    RefreshProgressFacts,
    ScanRootObservation,
    ScanRunObservation,
    ScanRunRelation,
    ScanRootPresentation,
)


RETRY_ELIGIBLE_STATES = frozenset({
    RecoveryState.COMPLETED_WITH_ISSUES,
    RecoveryState.FAILED,
    RecoveryState.CANCELLED,
    RecoveryState.ABANDONED,
})

RETRY_SUCCESS_ACCEPTED_STATES = frozenset({RecoveryState.COMPLETED})

# Physical latency execution needs its own session authorization, per-cycle
# grants, and an owner-pinned numerical rule. The host-only implementation ships the
# typed contract with execution disabled.
LATENCY_EXECUTION_ENABLED = False


@dataclass(frozen=True)
class OracleResult:
    """One categorical, sanitized oracle result."""

    outcome: evidence.AssertionOutcome
    code: str


def oracle_sha256() -> str:
    """Return the immutable lifecycle oracle digest."""
    return JOB_LIFECYCLE_ORACLE_SHA256


def oracle_version() -> str:
    """Return the lifecycle oracle version as an evidence string."""
    return str(JOB_LIFECYCLE_ORACLE_VERSION)


def validate_refresh_progress(facts: object) -> OracleResult:
    """Validate actual parent refresh progress fields without child counters."""
    if type(facts) is not RefreshProgressFacts:
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "refresh_progress_unavailable")
    if (
        type(facts.parent_run_ref) is not str
        or not 1 <= len(facts.parent_run_ref) <= 256
    ):
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "refresh_parent_unavailable")
    if facts.phase is not None and (
        type(facts.phase) is not str or not 1 <= len(facts.phase) <= 96
    ):
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "refresh_phase_ambiguous")
    if facts.completed_units is not None and (
        type(facts.completed_units) is not int or facts.completed_units < 0
    ):
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "refresh_completed_units_invalid")
    if facts.total_units is not None and (
        type(facts.total_units) is not int or facts.total_units < 0
    ):
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "refresh_total_units_invalid")
    if type(facts.completed_units) is not int:
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "refresh_completed_units_unavailable")
    if (
        facts.completed_units is not None
        and facts.total_units is not None
        and facts.completed_units > facts.total_units
    ):
        return OracleResult(evidence.AssertionOutcome.FAILED, "refresh_progress_contradiction")
    if facts.status_key is not None and (
        type(facts.status_key) is not str
        or not 1 <= len(facts.status_key) <= 128
        or not facts.status_key.startswith("library_refresh.")
    ):
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "refresh_status_key_ambiguous")
    if facts.issue_count is not None and (
        type(facts.issue_count) is not int or facts.issue_count < 0
    ):
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "refresh_issue_count_invalid")
    if facts.status_key is None:
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "refresh_status_key_unavailable")
    return OracleResult(evidence.AssertionOutcome.PASSED, "refresh_progress_observed")


def validate_active_progress_pair(
    first: object,
    second: object,
    *,
    expected_parent_ref: str | None = None,
) -> OracleResult:
    """Require two coherent active snapshots with a positive committed increase."""
    first_result = validate_refresh_progress(first)
    second_result = validate_refresh_progress(second)
    if first_result.outcome is not evidence.AssertionOutcome.PASSED:
        return first_result
    if second_result.outcome is not evidence.AssertionOutcome.PASSED:
        return second_result
    assert isinstance(first, RefreshProgressFacts)
    assert isinstance(second, RefreshProgressFacts)
    if first.parent_run_ref != second.parent_run_ref:
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "refresh_parent_changed")
    if (
        expected_parent_ref is not None
        and first.parent_run_ref != expected_parent_ref
    ):
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "refresh_parent_mismatch")
    if first.phase != second.phase:
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "refresh_phase_changed_between_snapshots")
    if type(first.completed_units) is not int or type(second.completed_units) is not int:
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "committed_progress_unavailable")
    if second.completed_units < first.completed_units:
        return OracleResult(evidence.AssertionOutcome.FAILED, "refresh_progress_regressed")
    if second.completed_units <= first.completed_units:
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "refresh_active_interval_not_established")
    return OracleResult(evidence.AssertionOutcome.PASSED, "refresh_active_interval_observed")


def validate_identity(
    observation: object,
    *,
    retry: bool = False,
    expected_parent_ref: str | None = None,
    expected_scope_ref: str | None = None,
    expected_scan_run_relations: tuple[ScanRunRelation, ...] | None = None,
    require_scan_relationships: bool = True,
) -> OracleResult:
    """Require a complete parent/root scope and exact per-root ScanRun relation."""
    if type(observation) is not JobIdentityObservation:
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "job_identity_unavailable")
    if (
        expected_parent_ref is not None
        and type(observation.parent_run_ref) is str
        and observation.parent_run_ref
        and observation.parent_run_ref != expected_parent_ref
    ):
        return OracleResult(evidence.AssertionOutcome.FAILED, "job_parent_identity_mismatch")
    if expected_scan_run_relations is not None:
        valid_expected = (
            type(expected_scan_run_relations) is tuple
            and all(
                type(relation) is ScanRunRelation and relation.established()
                for relation in expected_scan_run_relations
            )
        )
        if not valid_expected:
            return OracleResult(
                evidence.AssertionOutcome.BLOCKED,
                "expected_scan_run_scope_unavailable",
            )
        expected_relations = set(expected_scan_run_relations)
        if type(observation.scan_run_relations) is tuple and any(
            type(relation) is ScanRunRelation
            and relation.established()
            and relation not in expected_relations
            for relation in observation.scan_run_relations
        ):
            return OracleResult(
                evidence.AssertionOutcome.BLOCKED,
                "scan_run_relationship_ambiguous",
            )
    if not observation.parent_identity_complete():
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "job_identity_incomplete")
    if (
        expected_scope_ref is not None
        and observation.frozen_scope_ref != expected_scope_ref
    ):
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "job_scope_identity_stale")
    if retry:
        if not observation.retry_complete():
            return OracleResult(evidence.AssertionOutcome.BLOCKED, "retry_identity_incomplete")
    elif require_scan_relationships and not observation.scan_relationships_complete():
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "scan_run_relationships_incomplete")
    if expected_scan_run_relations is not None:
        if not observation.scan_relationships_complete():
            return OracleResult(evidence.AssertionOutcome.BLOCKED, "scan_run_relationships_incomplete")
        if set(observation.scan_run_relations) != set(expected_scan_run_relations):
            return OracleResult(evidence.AssertionOutcome.BLOCKED, "scan_run_relationship_ambiguous")
    return OracleResult(evidence.AssertionOutcome.PASSED, "job_identity_observed")


def validate_retry_precondition(
    observation: object,
    *,
    expected_parent_ref: str | None,
    expected_scope_ref: str | None,
    expected_requested_root_refs: tuple[str, ...] | None,
    expected_admitted_root_refs: tuple[str, ...] | None,
    expected_excluded_root_refs: tuple[str, ...] | None,
    expected_state: RecoveryState | None,
    expected_scan_run_relations: tuple[ScanRunRelation, ...] | None,
) -> OracleResult:
    """Require a fresh exact source/scope/ScanRun lookup with no successor."""
    if type(observation) is not JobIdentityObservation:
        return OracleResult(
            evidence.AssertionOutcome.BLOCKED,
            "retry_pre_dispatch_identity_unavailable",
        )
    if (
        type(expected_parent_ref) is not str
        or not 1 <= len(expected_parent_ref) <= 256
        or not expected_parent_ref.strip()
        or type(expected_scope_ref) is not str
        or not 1 <= len(expected_scope_ref) <= 256
        or type(expected_state) is not RecoveryState
        or expected_state not in RETRY_ELIGIBLE_STATES
        or type(expected_scan_run_relations) is not tuple
        or not expected_scan_run_relations
        or any(
            type(relation) is not ScanRunRelation or not relation.established()
            for relation in expected_scan_run_relations
        )
    ):
        return OracleResult(
            evidence.AssertionOutcome.BLOCKED,
            "retry_pre_dispatch_identity_unavailable",
        )
    if (
        type(observation.parent_run_ref) is str
        and observation.parent_run_ref
        and observation.parent_run_ref != expected_parent_ref
    ):
        return OracleResult(
            evidence.AssertionOutcome.FAILED,
            "retry_pre_dispatch_parent_mismatch",
        )
    if not observation.parent_identity_complete():
        return OracleResult(
            evidence.AssertionOutcome.BLOCKED,
            "retry_pre_dispatch_identity_ambiguous",
        )
    if observation.frozen_scope_ref != expected_scope_ref:
        return OracleResult(
            evidence.AssertionOutcome.BLOCKED,
            "retry_pre_dispatch_scope_stale",
        )
    if not observation.root_scope_matches(
        expected_requested_root_refs,
        expected_admitted_root_refs,
        expected_excluded_root_refs,
    ):
        return OracleResult(
            evidence.AssertionOutcome.BLOCKED,
            "retry_pre_dispatch_scope_stale",
        )
    if observation.parent_state is not expected_state:
        return OracleResult(
            evidence.AssertionOutcome.BLOCKED,
            "retry_pre_dispatch_state_stale",
        )
    if not observation.scan_relationships_complete():
        return OracleResult(
            evidence.AssertionOutcome.BLOCKED,
            "retry_pre_dispatch_scan_relations_incomplete",
        )
    if set(observation.scan_run_relations) != set(expected_scan_run_relations):
        return OracleResult(
            evidence.AssertionOutcome.BLOCKED,
            "retry_pre_dispatch_scan_relations_ambiguous",
        )
    lookup_source_ref = observation.retry_lookup_source_run_ref
    if (
        type(lookup_source_ref) is not str
        or not 1 <= len(lookup_source_ref) <= 256
        or not lookup_source_ref.strip()
    ):
        return OracleResult(
            evidence.AssertionOutcome.BLOCKED,
            "retry_pre_dispatch_identity_ambiguous",
        )
    successor_scan_run_relations = observation.successor_scan_run_relations
    if (
        observation.retry_relation_lookup_completed is not True
        or lookup_source_ref != expected_parent_ref
        or observation.successor_run_ref is not None
        or type(successor_scan_run_relations) is not tuple
        or bool(successor_scan_run_relations)
        or observation.successor_scope_ref is not None
        or observation.successor_requested_root_refs is not None
        or observation.successor_admitted_root_refs is not None
        or observation.successor_excluded_root_refs is not None
        or observation.successor_exclusions is not None
        or observation.source_run_ref is not None
    ):
        return OracleResult(
            evidence.AssertionOutcome.BLOCKED,
            "retry_pre_dispatch_identity_ambiguous",
        )
    return OracleResult(
        evidence.AssertionOutcome.PASSED,
        "retry_pre_dispatch_identity_current_and_empty",
    )


def validate_process_observation(
    observation: object,
    *,
    expected_state: ProcessState,
    expected_package: str,
) -> OracleResult:
    """Validate one independent process observation."""
    if type(observation) is not ProcessAndForegroundObservation:
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "process_observation_unavailable")
    if type(observation.process_state) is not ProcessState:
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "process_state_unknown")
    if observation.process_state is ProcessState.UNKNOWN:
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "process_state_unknown")
    if type(observation.observer_ref) is not str or not observation.observer_ref:
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "process_observer_identity_unavailable")
    if type(observation.package_name) is not str or not observation.package_name:
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "process_observation_unavailable")
    if observation.package_name != expected_package:
        return OracleResult(evidence.AssertionOutcome.FAILED, "process_package_mismatch")
    if observation.process_state is not expected_state:
        return OracleResult(evidence.AssertionOutcome.FAILED, "process_state_contradiction")
    return OracleResult(evidence.AssertionOutcome.PASSED, "process_state_observed")


def validate_scan_root_preloss(
    observation: object,
    *,
    expected_root_ref: str,
) -> OracleResult:
    """Validate one identified pre-loss root presentation without inventing a scan state."""
    if type(expected_root_ref) is not str or not expected_root_ref:
        return OracleResult(
            evidence.AssertionOutcome.BLOCKED,
            "scan_root_expected_identity_unavailable",
        )
    if type(observation) is not ScanRootObservation:
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "scan_root_observation_unavailable")
    identified = (
        observation.active_scan_identified()
        or observation.historical_last_scan_identified()
    )
    if not identified:
        return OracleResult(
            evidence.AssertionOutcome.BLOCKED,
            "scan_root_presentation_unidentified",
        )
    if observation.root_ref != expected_root_ref:
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "scan_root_identity_mismatch")
    if observation.presentation is ScanRootPresentation.ACTIVE_SCAN:
        return OracleResult(evidence.AssertionOutcome.PASSED, "scan_root_active_scan_observed")
    if observation.presentation is ScanRootPresentation.HISTORICAL_LAST_SCAN:
        return OracleResult(
            evidence.AssertionOutcome.PASSED,
            "scan_root_historical_scan_observed",
        )
    return OracleResult(
        evidence.AssertionOutcome.BLOCKED,
        "scan_root_presentation_unidentified",
    )


def validate_scan_root_relation(
    observation: object,
    *,
    expected_relation: ScanRunRelation,
) -> OracleResult:
    """Bind a verified Sources root presentation to its owning parent ScanRun tuple."""
    if type(observation) is not ScanRootObservation:
        return OracleResult(
            evidence.AssertionOutcome.BLOCKED,
            "scan_root_observation_unavailable",
        )
    if not (
        observation.active_scan_identified()
        or observation.historical_last_scan_identified()
    ):
        return OracleResult(
            evidence.AssertionOutcome.BLOCKED,
            "scan_root_relation_unavailable",
        )
    if type(expected_relation) is not ScanRunRelation or not expected_relation.established():
        return OracleResult(
            evidence.AssertionOutcome.BLOCKED,
            "scan_root_expected_relation_unavailable",
        )
    if observation.scan_parent_run_ref != expected_relation.parent_run_ref:
        return OracleResult(
            evidence.AssertionOutcome.FAILED,
            "scan_root_parent_jobrun_mismatch",
        )
    if (
        observation.root_ref != expected_relation.root_ref
        or observation.scan_run_ref != expected_relation.scan_run_ref
    ):
        return OracleResult(
            evidence.AssertionOutcome.BLOCKED,
            "scan_root_scan_run_relation_ambiguous",
        )
    return OracleResult(
        evidence.AssertionOutcome.PASSED,
        "scan_root_scan_run_relation_observed",
    )


def scan_root_recovery_persistence(
    preloss: object,
    recovered: object,
) -> OracleResult:
    """Compare two identified root presentations without awarding refresh attribution."""
    if type(preloss) is not ScanRootObservation or type(recovered) is not ScanRootObservation:
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "scan_root_observation_unavailable")
    if not (
        preloss.active_scan_identified()
        or preloss.historical_last_scan_identified()
    ):
        return OracleResult(
            evidence.AssertionOutcome.BLOCKED,
            "scan_root_preloss_unidentified",
        )
    if not (
        recovered.active_scan_identified()
        or recovered.historical_last_scan_identified()
    ):
        return OracleResult(
            evidence.AssertionOutcome.BLOCKED,
            "scan_root_recovery_unidentified",
        )
    if preloss.root_ref != recovered.root_ref:
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "scan_root_identity_changed")
    if preloss.scan_parent_run_ref != recovered.scan_parent_run_ref:
        return OracleResult(
            evidence.AssertionOutcome.FAILED,
            "scan_root_parent_jobrun_changed",
        )
    if preloss.scan_run_ref != recovered.scan_run_ref:
        return OracleResult(
            evidence.AssertionOutcome.BLOCKED,
            "scan_root_scan_run_identity_changed",
        )
    if preloss.presentation is ScanRootPresentation.ACTIVE_SCAN:
        if recovered.presentation is ScanRootPresentation.ACTIVE_SCAN:
            return OracleResult(evidence.AssertionOutcome.BLOCKED, "scan_root_still_active")
        return OracleResult(
            evidence.AssertionOutcome.PASSED,
            "scan_root_active_terminalized",
        )
    if recovered.presentation is ScanRootPresentation.ACTIVE_SCAN:
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "scan_root_reactivated")
    if preloss.last_scan_state != recovered.last_scan_state:
        return OracleResult(
            evidence.AssertionOutcome.BLOCKED,
            "scan_root_historical_state_changed",
        )
    return OracleResult(
        evidence.AssertionOutcome.PASSED,
        "scan_root_historical_persisted",
    )


def validate_scan_root_post_retry(
    observation: object,
    *,
    expected_root_ref: str,
    expected_successor_run_ref: str,
    expected_scan_run_ref: str | None = None,
) -> OracleResult:
    """Validate exact successor ScanRun ownership without awarding terminal completion."""
    if type(observation) is not ScanRootObservation:
        return OracleResult(
            evidence.AssertionOutcome.BLOCKED,
            "scan_root_observation_unavailable",
        )
    if (
        type(expected_root_ref) is not str
        or not expected_root_ref
        or type(expected_successor_run_ref) is not str
        or not expected_successor_run_ref
        or type(expected_scan_run_ref) is not str
        or not expected_scan_run_ref
    ):
        return OracleResult(
            evidence.AssertionOutcome.BLOCKED,
            "scan_root_post_retry_expected_identity_unavailable",
        )
    historical = observation.historical_last_scan_identified()
    active = observation.active_scan_identified()
    if not historical and not active:
        return OracleResult(
            evidence.AssertionOutcome.BLOCKED,
            "scan_root_post_retry_presentation_unidentified",
        )
    if observation.root_ref != expected_root_ref:
        return OracleResult(
            evidence.AssertionOutcome.BLOCKED,
            "scan_root_post_retry_root_mismatch",
        )
    if observation.scan_parent_run_ref != expected_successor_run_ref:
        return OracleResult(
            evidence.AssertionOutcome.FAILED,
            "scan_root_post_retry_parent_mismatch",
        )
    if observation.scan_run_ref != expected_scan_run_ref:
        return OracleResult(
            evidence.AssertionOutcome.BLOCKED,
            "scan_root_post_retry_scan_run_ambiguous",
        )
    if historical:
        return OracleResult(
            evidence.AssertionOutcome.PASSED,
            "scan_root_post_retry_historical_scan_observed",
        )
    return OracleResult(
        evidence.AssertionOutcome.PASSED,
        "scan_root_post_retry_active_scan_observed",
    )


def validate_scan_run_observation(
    observation: object,
    *,
    expected_relation: ScanRunRelation,
    expected_scan_state: str | None = None,
) -> OracleResult:
    """Validate an independently observed per-root ScanRun detail tuple."""
    if type(observation) is not ScanRunObservation or not observation.established():
        return OracleResult(
            evidence.AssertionOutcome.BLOCKED,
            "scan_run_detail_unavailable",
        )
    if type(expected_relation) is not ScanRunRelation or not expected_relation.established():
        return OracleResult(
            evidence.AssertionOutcome.BLOCKED,
            "scan_run_expected_relation_unavailable",
        )
    if observation.parent_run_ref != expected_relation.parent_run_ref:
        return OracleResult(
            evidence.AssertionOutcome.FAILED,
            "scan_run_parent_jobrun_mismatch",
        )
    if (
        observation.scan_run_ref != expected_relation.scan_run_ref
        or observation.root_ref != expected_relation.root_ref
    ):
        return OracleResult(
            evidence.AssertionOutcome.BLOCKED,
            "scan_run_relation_ambiguous",
        )
    if (
        expected_scan_state is not None
        and observation.scan_state != expected_scan_state
    ):
        return OracleResult(
            evidence.AssertionOutcome.FAILED,
            "scan_run_state_mismatch",
        )
    if observation.scan_state not in ROOT_HISTORICAL_SCAN_STATES:
        return OracleResult(
            evidence.AssertionOutcome.BLOCKED,
            "scan_run_terminal_state_unavailable",
        )
    return OracleResult(evidence.AssertionOutcome.PASSED, "scan_run_relation_observed")


def _validate_library_identity_preservation(
    expected_ids: object,
    observation: object,
    *,
    expected_job_run_ref: str | None,
    missing_code: str,
    unavailable_code: str,
    preserved_code: str,
) -> OracleResult:
    """Compare exact complete GameId sets with run-bound redirect evidence."""
    if type(observation) is not LibrarySurfaceObservation:
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "library_surface_unavailable")
    if not observation.established() or not observation.membership_identity_complete():
        return OracleResult(
            evidence.AssertionOutcome.BLOCKED,
            "library_membership_identity_unavailable",
        )
    if (
        type(expected_ids) is not tuple
        or any(
            type(value) is not str
            or not 1 <= len(value) <= 256
            or not value.strip()
            for value in expected_ids
        )
        or len(set(expected_ids)) != len(expected_ids)
    ):
        return OracleResult(
            evidence.AssertionOutcome.BLOCKED,
            unavailable_code,
        )

    current = frozenset(observation.membership_ids)
    missing = frozenset(expected_ids).difference(current)
    if not missing:
        return OracleResult(evidence.AssertionOutcome.PASSED, preserved_code)

    continuity = observation.identity_continuity
    if (
        type(expected_job_run_ref) is not str
        or not expected_job_run_ref
        or type(continuity) is not GameIdContinuityObservation
        or not continuity.established()
        or continuity.job_run_ref != expected_job_run_ref
    ):
        return OracleResult(
            evidence.AssertionOutcome.BLOCKED,
            "library_identity_continuity_unavailable",
        )
    if not missing.issubset(continuity.queried_game_ids):
        return OracleResult(
            evidence.AssertionOutcome.BLOCKED,
            "library_identity_continuity_scope_incomplete",
        )

    redirects = {
        redirect.source_game_id: redirect.canonical_game_id
        for redirect in continuity.redirects
    }
    for original_id in missing:
        canonical_id = redirects.get(original_id)
        if canonical_id is None:
            return OracleResult(
                evidence.AssertionOutcome.FAILED,
                missing_code,
            )
        if canonical_id in redirects or canonical_id not in current:
            return OracleResult(
                evidence.AssertionOutcome.BLOCKED,
                "library_identity_continuity_ambiguous",
            )

    return OracleResult(evidence.AssertionOutcome.PASSED, preserved_code)


def library_recovery_persistence(
    preloss_ids: object,
    observation: object,
    *,
    expected_job_run_ref: str | None = None,
) -> OracleResult:
    """Require every captured committed Library identity after process recovery."""
    return _validate_library_identity_preservation(
        preloss_ids,
        observation,
        expected_job_run_ref=expected_job_run_ref,
        missing_code="committed_library_asset_missing",
        unavailable_code="library_preloss_identity_unavailable",
        preserved_code="library_recovery_preserved",
    )


def library_post_retry_integrity(
    recovered_ids: object,
    observation: object,
    *,
    expected_job_run_ref: str | None = None,
) -> OracleResult:
    """Require every pre-Retry recovered identity to survive Retry unchanged."""
    return _validate_library_identity_preservation(
        recovered_ids,
        observation,
        expected_job_run_ref=expected_job_run_ref,
        missing_code="post_retry_library_asset_missing",
        unavailable_code="library_recovery_identity_unavailable",
        preserved_code="post_retry_library_integrity_preserved",
    )


def classify_recovery_child_states(
    children: tuple[LibraryScanChildCompletion, ...],
    *,
    requested_count: int,
    admitted_count: int,
) -> RecoveryState:
    """Match the Rust LibraryScan parent aggregation precedence exactly."""
    if type(children) is not tuple or any(
        type(child) is not LibraryScanChildCompletion for child in children
    ):
        raise ValueError("child completions must be typed")
    if (
        type(requested_count) is not int
        or type(admitted_count) is not int
        or requested_count < 0
        or admitted_count < 0
        or admitted_count > requested_count
    ):
        raise ValueError("requested and admitted counts must be bounded")
    if LibraryScanChildCompletion.CANCELLED in children:
        return RecoveryState.CANCELLED
    if LibraryScanChildCompletion.ABANDONED in children:
        return RecoveryState.ABANDONED
    fully_admitted = (
        admitted_count == requested_count
        and len(children) == admitted_count
    )
    if fully_admitted and all(
        child is LibraryScanChildCompletion.COMPLETE for child in children
    ):
        return RecoveryState.COMPLETED
    if any(
        child in {LibraryScanChildCompletion.COMPLETE, LibraryScanChildCompletion.PARTIAL}
        for child in children
    ):
        return RecoveryState.COMPLETED_WITH_ISSUES
    return RecoveryState.FAILED


def retry_eligibility(state: RecoveryState) -> OracleResult:
    """Return whether the backend advertises retry for the durable state."""
    if type(state) is not RecoveryState:
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "retry_eligibility_unavailable")
    if state in RETRY_ELIGIBLE_STATES:
        return OracleResult(evidence.AssertionOutcome.PASSED, "retry_eligible")
    if state in {RecoveryState.ACTIVE, RecoveryState.INTERRUPTED, RecoveryState.COMPLETED}:
        return OracleResult(evidence.AssertionOutcome.NOT_RUN, "retry_not_eligible")
    return OracleResult(evidence.AssertionOutcome.BLOCKED, "retry_eligibility_unavailable")


def recovery_consistency(
    durable_state: RecoveryState,
    *,
    force_stop_observed: bool,
    durable_cancellation_intent: bool,
) -> OracleResult:
    """Classify a post-loss state without equating consistency to process loss."""
    if type(durable_state) is not RecoveryState:
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "recovery_state_unavailable")
    if durable_state is RecoveryState.INTERRUPTED:
        return OracleResult(evidence.AssertionOutcome.FAILED, "unsupported_interrupted_state")
    if durable_state is RecoveryState.CANCELLED and not durable_cancellation_intent:
        return OracleResult(evidence.AssertionOutcome.FAILED, "cancelled_without_durable_intent")
    if durable_state in {RecoveryState.ACTIVE}:
        return OracleResult(evidence.AssertionOutcome.FAILED, "refresh_silently_resumed")
    if durable_state in {RecoveryState.COMPLETED, RecoveryState.COMPLETED_WITH_ISSUES}:
        return OracleResult(
            evidence.AssertionOutcome.BLOCKED,
            "terminal_before_process_loss_proven",
        )
    if durable_state in {RecoveryState.FAILED, RecoveryState.CANCELLED, RecoveryState.ABANDONED}:
        if not force_stop_observed:
            return OracleResult(evidence.AssertionOutcome.BLOCKED, "process_loss_unproven")
        return OracleResult(evidence.AssertionOutcome.PASSED, "recovery_state_supported")
    return OracleResult(evidence.AssertionOutcome.BLOCKED, "recovery_state_unavailable")


def retry_outcome(
    *,
    source_state: RecoveryState,
    dispatched: bool,
    already_retried: bool,
    parent_ref: str | None,
    frozen_scope_ref: str | None,
    expected_source_identity: JobIdentityObservation | None,
    successor_identity: JobIdentityObservation | None,
) -> OracleResult:
    """Validate one retry and its source/scope binding without another effect."""
    if type(source_state) is not RecoveryState:
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "recovery_state_unavailable")
    if source_state not in RETRY_ELIGIBLE_STATES:
        if dispatched or already_retried:
            return OracleResult(evidence.AssertionOutcome.FAILED, "retry_on_ineligible_source")
        return OracleResult(evidence.AssertionOutcome.NOT_RUN, "retry_not_eligible")
    if already_retried:
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "already_retried_requires_reconciliation")
    if not dispatched:
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "retry_not_admitted")
    if successor_identity is None:
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "retry_successor_identity_unavailable")
    if (
        type(successor_identity) is JobIdentityObservation
        and type(successor_identity.parent_run_ref) is str
        and successor_identity.parent_run_ref
        and successor_identity.parent_run_ref != parent_ref
    ):
        return OracleResult(
            evidence.AssertionOutcome.FAILED,
            "retry_identity_source_mismatch",
        )
    if (
        type(successor_identity) is JobIdentityObservation
        and type(successor_identity.source_run_ref) is str
        and successor_identity.source_run_ref
        and successor_identity.source_run_ref != parent_ref
    ):
        return OracleResult(
            evidence.AssertionOutcome.FAILED,
            "retry_identity_source_mismatch",
        )
    if (
        type(successor_identity) is JobIdentityObservation
        and type(successor_identity.successor_run_ref) is str
        and successor_identity.successor_run_ref
        and successor_identity.successor_run_ref == parent_ref
    ):
        return OracleResult(
            evidence.AssertionOutcome.FAILED,
            "retry_successor_reuses_source_identity",
        )
    if type(successor_identity) is not JobIdentityObservation:
        return OracleResult(
            evidence.AssertionOutcome.BLOCKED,
            "retry_successor_identity_unavailable",
        )
    if (
        successor_identity.retry_relation_lookup_completed is not True
        or type(successor_identity.retry_lookup_source_run_ref) is not str
        or successor_identity.retry_lookup_source_run_ref != parent_ref
    ):
        return OracleResult(
            evidence.AssertionOutcome.BLOCKED,
            "retry_successor_lookup_unavailable",
        )
    if (
        type(expected_source_identity) is not JobIdentityObservation
        or not expected_source_identity.scan_relationships_complete()
        or expected_source_identity.parent_run_ref != parent_ref
        or expected_source_identity.frozen_scope_ref != frozen_scope_ref
    ):
        return OracleResult(
            evidence.AssertionOutcome.BLOCKED,
            "retry_source_identity_unavailable",
        )
    if not successor_identity.root_scope_matches(
        expected_source_identity.requested_root_refs,
        expected_source_identity.admitted_root_refs,
        expected_source_identity.excluded_root_refs,
    ):
        return OracleResult(
            evidence.AssertionOutcome.BLOCKED,
            "retry_source_scope_changed",
        )
    if type(successor_identity) is JobIdentityObservation:
        successor_ref = successor_identity.successor_run_ref
        if (
            successor_identity.successor_root_scope_complete()
            and type(successor_ref) is str
            and successor_ref
            and type(successor_identity.successor_admitted_root_refs) is tuple
            and type(successor_identity.successor_scan_run_relations) is tuple
            and any(
                type(relation) is ScanRunRelation
                and relation.established()
                and (
                    relation.parent_run_ref != successor_ref
                    or relation.root_ref
                    not in successor_identity.successor_admitted_root_refs
                )
                for relation in successor_identity.successor_scan_run_relations
            )
        ):
            return OracleResult(
                evidence.AssertionOutcome.FAILED,
                "retry_successor_scan_run_owner_mismatch",
            )
    identity_result = validate_identity(
        successor_identity,
        retry=True,
        expected_parent_ref=parent_ref,
        expected_scope_ref=frozen_scope_ref,
        expected_scan_run_relations=expected_source_identity.scan_run_relations,
    )
    if identity_result.outcome is not evidence.AssertionOutcome.PASSED:
        return identity_result
    if (
        successor_identity.parent_run_ref != parent_ref
        or successor_identity.source_run_ref != parent_ref
        or successor_identity.frozen_scope_ref != frozen_scope_ref
        or successor_identity.successor_scope_ref != frozen_scope_ref
    ):
        return OracleResult(
            evidence.AssertionOutcome.BLOCKED,
            "retry_identity_relation_mismatch",
        )
    return OracleResult(evidence.AssertionOutcome.PASSED, "retry_successor_observed")


def recovery_terminal_consistency(state: object) -> OracleResult:
    """Return whether a terminal state is internally consistent, not proof of loss."""
    if type(state) is not RecoveryState:
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "recovery_state_unavailable")
    if state in {RecoveryState.COMPLETED, RecoveryState.COMPLETED_WITH_ISSUES}:
        return OracleResult(evidence.AssertionOutcome.PASSED, "terminal_state_consistent")
    return OracleResult(evidence.AssertionOutcome.NOT_RUN, "terminal_state_not_applicable")


def nearest_rank_percentile_95(samples: tuple[int, ...]) -> int:
    """Return the configured nearest-rank percentile for integer samples."""
    measured_cycles = _LATENCY_POLICY_DECLARATION["measured_cycles"]["value"]
    elapsed_milliseconds = _LATENCY_POLICY_DECLARATION["elapsed_milliseconds"]
    if (
        type(samples) is not tuple
        or len(samples) != measured_cycles
        or any(
            not _latency_exact_type(
                value,
                elapsed_milliseconds["exact_type"],
            )
            or value < elapsed_milliseconds["minimum"]
            for value in samples
        )
    ):
        raise ValueError(
            f"the 95th percentile requires {measured_cycles} nonnegative integer samples"
        )
    ordered = sorted(samples)
    rank = math.ceil(0.95 * len(ordered))
    return ordered[rank - 1]


def _latency_exact_type(value: object, declared_type: str) -> bool:
    """Match a canonical policy type tag to an exact built-in Python type."""
    expected_types = {"bool": bool, "int": int, "str": str, "tuple": tuple}
    expected_type = expected_types.get(declared_type)
    return expected_type is not None and type(value) is expected_type


def _valid_latency_reference(value: object) -> bool:
    """Return whether a workload, environment, or evidence reference is usable."""
    policy = _LATENCY_POLICY_DECLARATION["references"]
    return (
        _latency_exact_type(value, policy["exact_type"])
        and policy["minimum_length"] <= len(value) <= policy["maximum_length"]
        and (
            not policy["nonblank_after_strip"]
            or bool(value.strip())
        )
    )


def _valid_latency_action_id(value: object) -> bool:
    """Accept bounded ASCII identifiers for owner-pinned latency actions."""
    policy = _LATENCY_POLICY_DECLARATION["action_ids"]
    return (
        _latency_exact_type(value, policy["item_exact_type"])
        and policy["minimum_length"] <= len(value) <= policy["maximum_length"]
        and re.fullmatch(policy["grammar"], value) is not None
    )


def _valid_latency_rule_digest(value: object) -> bool:
    """Require a canonical lowercase SHA-256 owner-rule reference."""
    policy = _LATENCY_POLICY_DECLARATION["rule_sha256"]
    return (
        _latency_exact_type(value, policy["exact_type"])
        and re.fullmatch(policy["grammar"], value) is not None
    )


def evaluate_latency(
    criterion: object,
    cycles: object,
    *,
    active_overlap_confirmed: bool,
) -> OracleResult:
    """Evaluate the typed latency contract only when owner criteria are pinned."""
    policy = _LATENCY_POLICY_DECLARATION
    action_id_policy = policy["action_ids"]
    timeout_policy = policy["per_cycle_timeout_seconds"]
    ceiling_policy = policy["percentile_95_ceiling_milliseconds"]
    warmup_policy = policy["warmup_cycles"]
    measured_policy = policy["measured_cycles"]
    boolean_policy = policy["boolean_observations"]
    elapsed_policy = policy["elapsed_milliseconds"]
    cycle_evidence_policy = policy["cycle_evidence_references"]
    reference_policy = policy[cycle_evidence_policy["reference_policy"]]

    if type(criterion) is not LatencyCriterion:
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "latency_criterion_unavailable")
    if (
        criterion.workload_ref is None
        or criterion.environment_ref is None
        or criterion.rule_sha256 is None
        or criterion.percentile_95_ceiling_milliseconds is None
        or criterion.per_cycle_timeout_seconds is None
        or (
            _latency_exact_type(criterion.action_ids, action_id_policy["exact_type"])
            and not criterion.action_ids
        )
    ):
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "latency_owner_rule_unavailable")
    if (
        not _valid_latency_reference(criterion.workload_ref)
        or not _valid_latency_reference(criterion.environment_ref)
        or not _valid_latency_rule_digest(criterion.rule_sha256)
        or not _latency_exact_type(
            criterion.per_cycle_timeout_seconds,
            timeout_policy["exact_type"],
        )
        or not _latency_exact_type(
            criterion.percentile_95_ceiling_milliseconds,
            ceiling_policy["exact_type"],
        )
        or not _latency_exact_type(criterion.warmup_cycles, warmup_policy["exact_type"])
        or not _latency_exact_type(criterion.measured_cycles, measured_policy["exact_type"])
        or criterion.per_cycle_timeout_seconds < timeout_policy["minimum"]
        or criterion.percentile_95_ceiling_milliseconds < ceiling_policy["minimum"]
        or not _latency_exact_type(criterion.action_ids, action_id_policy["exact_type"])
        or (action_id_policy["nonempty"] and not criterion.action_ids)
        or any(not _valid_latency_action_id(action_id) for action_id in criterion.action_ids)
        or (
            action_id_policy["unique"]
            and len(set(criterion.action_ids)) != len(criterion.action_ids)
        )
    ):
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "latency_criterion_malformed")
    if (
        criterion.warmup_cycles != warmup_policy["value"]
        or criterion.measured_cycles != measured_policy["value"]
    ):
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "latency_owner_rule_unavailable")
    if not _latency_exact_type(active_overlap_confirmed, boolean_policy["exact_type"]):
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "latency_active_overlap_unavailable")
    if type(cycles) is not tuple or any(type(cycle) is not LatencyCycle for cycle in cycles):
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "latency_cycles_unavailable")

    action_ids = frozenset(criterion.action_ids)
    evidence_refs: set[str] = set()
    for cycle in cycles:
        if (
            not _valid_latency_action_id(cycle.action_id)
            or not _latency_exact_type(cycle.warmup, boolean_policy["exact_type"])
            or not _latency_exact_type(
                cycle.elapsed_milliseconds,
                elapsed_policy["exact_type"],
            )
            or cycle.elapsed_milliseconds < elapsed_policy["minimum"]
            or not _latency_exact_type(cycle.return_completed, boolean_policy["exact_type"])
            or not _latency_exact_type(cycle.evidence_ref, reference_policy["exact_type"])
        ):
            return OracleResult(
                evidence.AssertionOutcome.BLOCKED,
                "latency_cycle_evidence_malformed",
            )
        if cycle.action_id not in action_ids:
            return OracleResult(evidence.AssertionOutcome.BLOCKED, "latency_cycle_set_mismatch")
        if cycle.evidence_ref == "":
            return OracleResult(
                evidence.AssertionOutcome.BLOCKED,
                "latency_cycle_evidence_missing",
            )
        if (
            not _valid_latency_reference(cycle.evidence_ref)
            or (
                cycle_evidence_policy["unique"]
                and cycle.evidence_ref in evidence_refs
            )
        ):
            return OracleResult(
                evidence.AssertionOutcome.BLOCKED,
                "latency_cycle_evidence_malformed",
            )
        evidence_refs.add(cycle.evidence_ref)

    expected_cycles_per_action = warmup_policy["value"] + measured_policy["value"]
    if len(cycles) != len(criterion.action_ids) * expected_cycles_per_action:
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "latency_cycle_count_mismatch")
    if not active_overlap_confirmed:
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "latency_active_overlap_unproven")
    for action_id in criterion.action_ids:
        action_cycles = tuple(cycle for cycle in cycles if cycle.action_id == action_id)
        warmups = tuple(cycle for cycle in action_cycles if cycle.warmup)
        measured = tuple(cycle for cycle in action_cycles if not cycle.warmup)
        if len(warmups) != warmup_policy["value"] or len(measured) != measured_policy["value"]:
            return OracleResult(evidence.AssertionOutcome.BLOCKED, "latency_cycle_count_mismatch")
        if any(not cycle.return_completed for cycle in action_cycles):
            return OracleResult(evidence.AssertionOutcome.BLOCKED, "latency_return_incomplete")
        if any(
            cycle.elapsed_milliseconds > criterion.per_cycle_timeout_seconds * 1000
            for cycle in measured
        ):
            return OracleResult(evidence.AssertionOutcome.FAILED, "latency_cycle_timeout")
        percentile_95 = nearest_rank_percentile_95(
            tuple(cycle.elapsed_milliseconds for cycle in measured)
        )
        if percentile_95 > criterion.percentile_95_ceiling_milliseconds:
            return OracleResult(
                evidence.AssertionOutcome.FAILED,
                "latency_percentile_95_ceiling_exceeded",
            )
    return OracleResult(evidence.AssertionOutcome.PASSED, "latency_rule_satisfied")


def latency_execution_status() -> OracleResult:
    """Report the host-only latency execution gate without running any cycle."""
    if LATENCY_EXECUTION_ENABLED:
        return OracleResult(
            evidence.AssertionOutcome.BLOCKED,
            "latency_owner_authorization_unavailable",
        )
    return OracleResult(
        evidence.AssertionOutcome.BLOCKED,
        "latency_execution_not_authorized",
    )


def terminal_successor(observation: object) -> OracleResult:
    """Validate an observed retry successor without another retry effect."""
    if type(observation) is not RefreshDetailObservation:
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "successor_observation_unavailable")
    if not observation.established():
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "successor_identity_unavailable")
    if observation.state in ACTIVE_STATES:
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "successor_still_active")
    if observation.state not in TERMINAL_STATES:
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "successor_state_unavailable")
    return OracleResult(evidence.AssertionOutcome.PASSED, "successor_terminal_observed")


def retry_success_acceptance(
    state: object,
    *,
    accepted_states: frozenset[RecoveryState] | None = None,
) -> OracleResult:
    """Validate Retry success separately from the terminal observation.

    The default acceptance contract requires ``Completed``. A pinned owner
    criterion may admit other terminal states, but a proven unsuccessful
    outcome never satisfies Retry success.
    """
    if type(state) is not RecoveryState:
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "successor_state_unavailable")
    if state in ACTIVE_STATES:
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "successor_still_active")
    if state not in TERMINAL_STATES:
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "successor_state_unavailable")
    if state in {
        RecoveryState.FAILED,
        RecoveryState.CANCELLED,
        RecoveryState.ABANDONED,
        RecoveryState.INTERRUPTED,
    }:
        return OracleResult(evidence.AssertionOutcome.FAILED, "retry_outcome_unsuccessful")
    accepted = (
        RETRY_SUCCESS_ACCEPTED_STATES
        if accepted_states is None
        else accepted_states
    )
    if type(accepted) is not frozenset or any(
        type(value) is not RecoveryState for value in accepted
    ):
        return OracleResult(evidence.AssertionOutcome.BLOCKED, "retry_acceptance_unavailable")
    if state in accepted:
        return OracleResult(evidence.AssertionOutcome.PASSED, "retry_success_confirmed")
    return OracleResult(evidence.AssertionOutcome.BLOCKED, "retry_acceptance_undecided")
