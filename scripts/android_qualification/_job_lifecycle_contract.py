"""Closed host-side contract for the Issue #28 Android job lifecycle scenarios.

This module owns the private operation vocabulary and canonical plan digest for
AND-04 and AND-05. It contains no device transport, no ADB invocation, and no
owner verdict. The manifest and admission modules bind the authorization to
the exact values exported here.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
import hashlib
import json
from typing import Iterable


JOB_LIFECYCLE_CONTRACT_VERSION = 5
JOB_LIFECYCLE_CAPABILITY_VERSION = 4
JOB_LIFECYCLE_ORACLE_VERSION = 7
JOB_LIFECYCLE_QUALIFICATION_PACKAGE = "com.argusromtoolkit.argus.qualification"
JOB_LIFECYCLE_SCENARIO_AND_04 = "AND-04"
JOB_LIFECYCLE_SCENARIO_AND_05 = "AND-05"
JOB_LIFECYCLE_SCENARIOS = (
    JOB_LIFECYCLE_SCENARIO_AND_04,
    JOB_LIFECYCLE_SCENARIO_AND_05,
)

JOB_LIFECYCLE_SESSION_SECONDS = {
    JOB_LIFECYCLE_SCENARIO_AND_04: 900,
    JOB_LIFECYCLE_SCENARIO_AND_05: 1280,
}
JOB_LIFECYCLE_CLOSURE_SECONDS = 120
JOB_LIFECYCLE_LATEST_ADMISSION_SECONDS = 60
JOB_LIFECYCLE_RAW_TIMEOUT_SECONDS = {
    JOB_LIFECYCLE_SCENARIO_AND_04: 575,
    JOB_LIFECYCLE_SCENARIO_AND_05: 880,
}
JOB_LIFECYCLE_REQUIRED_SPAN_SECONDS = {
    JOB_LIFECYCLE_SCENARIO_AND_04: 771,
    JOB_LIFECYCLE_SCENARIO_AND_05: 1135,
}
JOB_LIFECYCLE_RESERVE_SECONDS = {
    JOB_LIFECYCLE_SCENARIO_AND_04: {
        "operation_floor": 31,
        "evidence": 90,
        "state_check": 45,
        "restoration": 30,
    },
    JOB_LIFECYCLE_SCENARIO_AND_05: {
        "operation_floor": 45,
        "evidence": 120,
        "state_check": 60,
        "restoration": 30,
    },
}

_CAPABILITY_DECLARATION = {
    "version": JOB_LIFECYCLE_CAPABILITY_VERSION,
    "identity_model": {
        "parent": "one_library_refresh_jobrun",
        "per_root": "scan_run_owned_by_parent",
        "relationship_fields": (
            "parent_job_run_id",
            "scan_run_id",
            "library_root_id",
        ),
        "scope_fields": (
            "requested_root_ids",
            "admitted_root_ids",
            "excluded_root_ids",
        ),
        "library_game_identity": "exact_gameid_sets_with_continuity_query_scope",
    },
    "scenarios": {
        JOB_LIFECYCLE_SCENARIO_AND_04: {
            "operations": 31,
            "screen": "refresh detail",
            "progress_fields": (
                "phase",
                "completed_units",
                "total_units",
                "status_key",
                "issue_count",
            ),
        },
        JOB_LIFECYCLE_SCENARIO_AND_05: {
            "operations": 45,
            "screen": "refresh detail",
            "progress_fields": (
                "phase",
                "completed_units",
                "total_units",
                "status_key",
                "issue_count",
            ),
            "retry_precondition": (
                "fresh_parent_scope_scan_relations_and_empty_retry_relation"
            ),
            "retry_source_binding": (
                "same_captured_parent_root_partition_and_scanrun_set"
            ),
            "retry_successor_admission": (
                "same_requested_roots_rechecked_with_current_admitted_excluded_partition"
            ),
            "retry_exclusion_reasons": (
                "already_scanning",
                "no_longer_configured",
                "invalid_configuration",
            ),
            "retry_successor": "distinct_jobrun_with_exact_per_root_scan_runs",
            "root_detail": "view_job_targets_parent_jobrun",
            "scan_run_detail": "owner_refresh_detail",
        },
    },
}


def _canonical_bytes(value: object) -> bytes:
    return json.dumps(
        value,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
        allow_nan=False,
    ).encode("utf-8")


def _sha256(value: object) -> str:
    return hashlib.sha256(_canonical_bytes(value)).hexdigest()


JOB_LIFECYCLE_CAPABILITY_SHA256 = _sha256(_CAPABILITY_DECLARATION)

_LATENCY_POLICY_DECLARATION = {
    "warmup_cycles": {"exact_type": "int", "value": 5},
    "measured_cycles": {"exact_type": "int", "value": 20},
    "per_cycle_timeout_seconds": {"exact_type": "int", "minimum": 1},
    "percentile_95_ceiling_milliseconds": {"exact_type": "int", "minimum": 0},
    "elapsed_milliseconds": {"exact_type": "int", "minimum": 0},
    "boolean_observations": {
        "exact_type": "bool",
        "fields": ("active_overlap_confirmed", "warmup", "return_completed"),
    },
    "action_ids": {
        "exact_type": "tuple",
        "nonempty": True,
        "unique": True,
        "item_exact_type": "str",
        "minimum_length": 1,
        "maximum_length": 64,
        "grammar": r"[a-z][a-z0-9_-]{0,63}",
    },
    "references": {
        "exact_type": "str",
        "minimum_length": 1,
        "maximum_length": 256,
        "nonblank_after_strip": True,
    },
    "rule_sha256": {"exact_type": "str", "grammar": r"[0-9a-f]{64}"},
    "cycle_evidence_references": {"reference_policy": "references", "unique": True},
    "malformed_criteria_or_evidence": "BLOCKED",
    "measured_timeout_exceeded": "FAILED",
    "percentile_95": "nearest_rank",
    "percentile_95_exceeded": "FAILED",
}

JOB_LIFECYCLE_ORACLE_SHA256 = _sha256({
    "contract_version": JOB_LIFECYCLE_CONTRACT_VERSION,
    "oracle_version": JOB_LIFECYCLE_ORACLE_VERSION,
    "capability_sha256": JOB_LIFECYCLE_CAPABILITY_SHA256,
    "progress_fields": (
        "phase",
        "completed_units",
        "total_units",
        "status_key",
        "issue_count",
    ),
    "identity_policy": {
        "scan_run_relation": (
            "parent_job_run_id",
            "scan_run_id",
            "library_root_id",
        ),
        "requested_admitted_excluded_partition": True,
        "scan_run_ids_unique": True,
        "one_scan_run_per_admitted_root": True,
        "view_job_is_jobrun_not_scanrun": True,
        "source_and_successor_scan_run_ids_are_disjoint": True,
        "pre_retry_requires_empty_retry_relation": True,
        "source_root_partitions_match_captured_scope": True,
        "retry_outcome_binds_captured_source_scope_and_scan_runs": True,
        "successor_requested_roots_match_source_intent": True,
        "successor_scan_runs_match_current_admitted_roots": True,
        "successor_exclusions_are_typed_and_exact": True,
        "missing_identity": "BLOCKED",
        "valid_foreign_identity": "FAILED",
    },
    "library_identity_policy": {
        "identity": "GameId",
        "complete_page_required": True,
        "exact_unique_set_required": True,
        "additions_do_not_mask_loss": True,
        "missing_identity_without_continuity_proof": "BLOCKED",
        "missing_identity_without_redirect_after_complete_lookup": "FAILED",
        "authorized_redirect_must_bind_to_jobrun": True,
        "continuity_query_scope_covers_all_missing_game_ids": True,
        "missing_game_id_without_query_coverage": "BLOCKED",
        "all_reported_redirect_sources_must_be_queried": True,
        "used_redirect_targets_must_be_current_members": True,
        "transitive_redirect_resolution": "BLOCKED",
    },
    "latency_policy": _LATENCY_POLICY_DECLARATION,
})


class JobLifecycleSurface(str, Enum):
    """Surfaces a lifecycle observation is allowed to inspect."""

    LIBRARY = "library"
    JOBS = "jobs"
    REFRESH_DETAIL = "refresh_detail"
    SCAN_ROOT_DETAIL = "scan_root_detail"
    SCAN_JOB_DETAIL = "scan_job_detail"


class ScanRootPresentation(str, Enum):
    """The production root-detail presentation that supplied a scan fact."""

    ACTIVE_SCAN = "active_scan"
    HISTORICAL_LAST_SCAN = "historical_last_scan"
    UNIDENTIFIED = "unidentified"


ROOT_HISTORICAL_SCAN_STATES = frozenset({
    "complete",
    "partial",
    "unavailable",
    "cancelled",
    "failed",
    "abandoned",
})


class ProcessState(str, Enum):
    """Independent process-observer result."""

    PRESENT = "present"
    ABSENT = "absent"
    UNKNOWN = "unknown"


class RecoveryState(str, Enum):
    """Durable parent job state relevant to recovery classification."""

    ACTIVE = "active"
    COMPLETED = "completed"
    COMPLETED_WITH_ISSUES = "completed_with_issues"
    FAILED = "failed"
    CANCELLED = "cancelled"
    ABANDONED = "abandoned"
    INTERRUPTED = "interrupted"


class LibraryScanChildCompletion(str, Enum):
    """Terminal child outcome used by LibraryScan parent aggregation."""

    COMPLETE = "complete"
    PARTIAL = "partial"
    FAILED = "failed"
    CANCELLED = "cancelled"
    ABANDONED = "abandoned"


@dataclass(frozen=True)
class JobLifecycleOperationSpec:
    """One exact operation in a closed scenario layout."""

    index: int
    category: str
    argument_key: str
    value: str
    phase: str
    timeout_seconds: int
    handler: str = ""


def _obs(
    index: int, value: str, timeout: int, *, handler: str | None = None
) -> JobLifecycleOperationSpec:
    return JobLifecycleOperationSpec(
        index,
        "read_only",
        "observation",
        value,
        "qualification",
        timeout,
        handler or value,
    )


def _nav(
    index: int, value: str, timeout: int = 10, *, handler: str | None = None
) -> JobLifecycleOperationSpec:
    return JobLifecycleOperationSpec(
        index,
        "navigation",
        "action",
        value,
        "qualification",
        timeout,
        handler or value,
    )


def _refresh(
    index: int, value: str, timeout: int, *, handler: str | None = None
) -> JobLifecycleOperationSpec:
    return JobLifecycleOperationSpec(
        index,
        "refresh",
        "action",
        value,
        "qualification",
        timeout,
        handler or value,
    )


def _launch(
    index: int, value: str, timeout: int, *, handler: str | None = None
) -> JobLifecycleOperationSpec:
    return JobLifecycleOperationSpec(
        index,
        "launch",
        "action",
        value,
        "qualification",
        timeout,
        handler or value,
    )


AND_04_OPERATIONS = (
    _obs(1, "no_reset_baseline", 30, handler="baseline"),
    _nav(2, "navigate_library"),
    _obs(3, "library_ready", 20),
    _nav(4, "navigate_jobs"),
    _obs(5, "jobs_preflight", 20),
    _nav(6, "navigate_library"),
    _refresh(7, "start_library_refresh", 30, handler="start_refresh"),
    _obs(8, "refresh_arrival", 20),
    _obs(9, "refresh_progress", 30, handler="refresh_progress_initial"),
    _obs(10, "refresh_progress", 30, handler="refresh_progress_repeat"),
    _nav(11, "navigate_jobs"),
    _obs(12, "jobs_active", 20),
    _nav(13, "open_refresh_detail"),
    _obs(14, "refresh_detail", 20),
    _obs(15, "parent_child_identity", 15),
    _nav(16, "navigate_library"),
    _obs(17, "library_active", 20),
    _launch(18, "background_qualification_package", 10, handler="background"),
    _obs(19, "process_foreground", 15, handler="process_backgrounded"),
    _launch(
        20,
        "return_existing_qualification_task",
        30,
        handler="return_existing_task",
    ),
    _obs(21, "foreground_surface", 15, handler="foreground_restored"),
    _nav(22, "navigate_jobs"),
    _obs(23, "jobs_returned", 20),
    _nav(24, "open_refresh_detail"),
    _obs(25, "recovered_lifecycle", 60),
    _nav(26, "navigate_sources"),
    _nav(27, "open_scan_root"),
    _obs(28, "scan_root_state", 20),
    _nav(29, "open_scan_job_detail", handler="open_owner_refresh_detail"),
    _obs(30, "scan_job_lifecycle", 20, handler="scan_run_lifecycle"),
    _launch(31, "restore_qualification_foreground", 20, handler="restore_foreground"),
)

AND_05_OPERATIONS = (
    _obs(1, "no_reset_baseline", 30, handler="baseline"),
    _nav(2, "navigate_library"),
    _obs(3, "library_ready", 20),
    _nav(4, "navigate_jobs"),
    _obs(5, "jobs_preflight", 20),
    _nav(6, "navigate_library"),
    _refresh(7, "start_library_refresh", 30, handler="start_refresh"),
    _obs(8, "refresh_arrival", 20),
    _obs(9, "refresh_progress", 30, handler="refresh_progress_initial"),
    _obs(10, "refresh_progress", 30, handler="refresh_progress_repeat"),
    _nav(11, "navigate_library"),
    _obs(12, "library_preloss", 20),
    _nav(13, "navigate_sources"),
    _nav(14, "open_scan_root"),
    _obs(15, "scan_root_preloss", 20),
    _nav(16, "navigate_jobs"),
    _nav(17, "open_refresh_detail"),
    _obs(18, "refresh_detail", 20),
    _obs(19, "parent_child_identity", 15),
    _obs(20, "pre_stop_guard", 20),
    JobLifecycleOperationSpec(
        21,
        "force_stop",
        "action",
        "force_stop_qualification_package",
        "qualification",
        10,
        "force_stop",
    ),
    _obs(22, "process_foreground", 15, handler="process_absent"),
    _launch(23, "launch_qualification_package", 30, handler="launch"),
    _obs(24, "foreground_surface", 15, handler="foreground_launched"),
    _nav(25, "navigate_sources"),
    _nav(26, "open_scan_root"),
    _obs(27, "scan_root_recovered", 20),
    _nav(28, "navigate_library"),
    _obs(29, "library_recovered", 30),
    _nav(30, "navigate_jobs"),
    _obs(31, "jobs_recovered", 20),
    _nav(32, "open_refresh_detail"),
    _obs(33, "recovered_lifecycle", 60),
    _obs(34, "retry_eligibility", 20),
    _refresh(35, "retry_library_refresh", 60, handler="retry"),
    _obs(36, "retry_outcome", 30),
    _obs(37, "retry_relation", 15),
    _nav(38, "navigate_library"),
    _obs(39, "library_persisted", 20),
    _nav(40, "navigate_sources"),
    _nav(41, "open_scan_root"),
    _obs(42, "scan_root_state", 20, handler="scan_root_state_post_retry"),
    _nav(43, "navigate_jobs"),
    _nav(44, "open_retry_successor_detail", handler="open_successor_detail"),
    _obs(45, "retry_successor_terminal", 60, handler="successor_terminal"),
)

JOB_LIFECYCLE_OPERATIONS = {
    JOB_LIFECYCLE_SCENARIO_AND_04: AND_04_OPERATIONS,
    JOB_LIFECYCLE_SCENARIO_AND_05: AND_05_OPERATIONS,
}


def operation_count(scenario_id: str) -> int:
    """Return the exact operation count for one public scenario identity."""
    try:
        return len(JOB_LIFECYCLE_OPERATIONS[scenario_id])
    except KeyError:
        raise ValueError("unsupported job lifecycle scenario") from None


def raw_timeout_sum(scenario_id: str) -> int:
    """Return the frozen sum of operation timeout envelopes."""
    return sum(spec.timeout_seconds for spec in JOB_LIFECYCLE_OPERATIONS[scenario_id])


def required_session_span(scenario_id: str) -> int:
    """Return effect timeouts plus all positive execution reserves."""
    reserves = JOB_LIFECYCLE_RESERVE_SECONDS[scenario_id]
    return raw_timeout_sum(scenario_id) + sum(reserves.values())


def operation_arguments(spec: JobLifecycleOperationSpec) -> dict[str, str]:
    """Return the closed authorization arguments for one operation."""
    arguments = {
        spec.argument_key: spec.value,
        "oracle_sha256": JOB_LIFECYCLE_ORACLE_SHA256,
        "oracle_version": str(JOB_LIFECYCLE_ORACLE_VERSION),
    }
    return arguments


def plan_digest_document(
    *,
    scenario_id: str,
    application_package: str,
    apk_sha256: str,
    certificate_sha256: str,
    source_revision: str,
    version_code: int,
    rules_sha256: str,
    operations: Iterable[tuple[str, str, str, int, tuple[tuple[str, str], ...]]],
) -> dict[str, object]:
    """Build the independently hashed lifecycle-plan declaration."""
    return {
        "contract_version": JOB_LIFECYCLE_CONTRACT_VERSION,
        "scenario_id": scenario_id,
        "application_package": application_package,
        "apk_sha256": apk_sha256,
        "certificate_sha256": certificate_sha256,
        "source_revision": source_revision,
        "version_code": version_code,
        "rules_sha256": rules_sha256,
        "capability_sha256": JOB_LIFECYCLE_CAPABILITY_SHA256,
        "oracle_sha256": JOB_LIFECYCLE_ORACLE_SHA256,
        "session_seconds": JOB_LIFECYCLE_SESSION_SECONDS[scenario_id],
        "closure_seconds": JOB_LIFECYCLE_CLOSURE_SECONDS,
        "raw_timeout_seconds": raw_timeout_sum(scenario_id),
        "required_span_seconds": required_session_span(scenario_id),
        "operations": tuple(
            {
                "operation_id": operation_id,
                "category": category,
                "phase": phase,
                "timeout_seconds": timeout_seconds,
                "arguments": arguments,
            }
            for operation_id, category, phase, timeout_seconds, arguments in operations
        ),
    }


def digest_for_document(document: dict[str, object]) -> str:
    """Return the canonical SHA-256 of a lifecycle plan declaration."""
    return _sha256(document)


def plan_digest_for_authorization(authorization: object) -> str | None:
    """Compute the lifecycle plan digest from a loaded session authorization."""
    scenario_ids = getattr(authorization, "scenario_ids", None)
    operations = getattr(authorization, "operations", None)
    if (
        type(scenario_ids) is not tuple
        or len(scenario_ids) != 1
        or scenario_ids[0] not in JOB_LIFECYCLE_SCENARIOS
        or type(operations) is not tuple
    ):
        return None
    try:
        document = plan_digest_document(
            scenario_id=scenario_ids[0],
            application_package=authorization.application_package,
            apk_sha256=authorization.apk_sha256,
            certificate_sha256=authorization.certificate_sha256,
            source_revision=authorization.source_revision,
            version_code=authorization.version_code,
            rules_sha256=authorization.rules_sha256,
            operations=(
                (
                    operation.operation_id,
                    operation.category.value,
                    operation.phase,
                    operation.timeout_seconds,
                    operation.arguments,
                )
                for operation in operations
            ),
        )
        return digest_for_document(document)
    except (AttributeError, TypeError, ValueError):
        return None


def validate_job_lifecycle_authorization(authorization: object) -> bool:
    """Validate exact layout, scenario, deadlines, reserves, and plan digest."""
    scenario_ids = getattr(authorization, "scenario_ids", None)
    if type(scenario_ids) is not tuple or len(scenario_ids) != 1:
        return False
    scenario_id = scenario_ids[0]
    if scenario_id not in JOB_LIFECYCLE_SCENARIOS:
        return False
    state_mode = getattr(authorization, "state_mode", None)
    if getattr(state_mode, "value", state_mode) != "no-reset":
        return False
    issued_at = getattr(authorization, "issued_at", None)
    session_deadline = getattr(authorization, "session_deadline", None)
    cleanup_deadline = getattr(authorization, "cleanup_deadline", None)
    try:
        session_seconds = (session_deadline - issued_at).total_seconds()
        closure_seconds = (cleanup_deadline - session_deadline).total_seconds()
    except (AttributeError, TypeError):
        return False
    if (
        session_seconds != JOB_LIFECYCLE_SESSION_SECONDS[scenario_id]
        or closure_seconds != JOB_LIFECYCLE_CLOSURE_SECONDS
        or authorization.cleanup_reserve_seconds != JOB_LIFECYCLE_CLOSURE_SECONDS
        or authorization.approved_remediation != ()
        or authorization.application_package != JOB_LIFECYCLE_QUALIFICATION_PACKAGE
        or raw_timeout_sum(scenario_id) != JOB_LIFECYCLE_RAW_TIMEOUT_SECONDS[scenario_id]
        or required_session_span(scenario_id) != JOB_LIFECYCLE_REQUIRED_SPAN_SECONDS[scenario_id]
    ):
        return False
    operations = getattr(authorization, "operations", None)
    specs = JOB_LIFECYCLE_OPERATIONS[scenario_id]
    if type(operations) is not tuple or len(operations) != len(specs):
        return False
    for operation, spec in zip(operations, specs, strict=True):
        expected_arguments = operation_arguments(spec)
        if (
            operation.operation_id != f"{scenario_id.lower()}-{spec.index:02d}"
            or operation.category.value != spec.category
            or operation.phase != spec.phase
            or operation.timeout_seconds != spec.timeout_seconds
            or operation.package_name != JOB_LIFECYCLE_QUALIFICATION_PACKAGE
            or operation.permission_name is not None
            or operation.expected_prior_state is not None
            or operation.desired_state is not None
            or operation.restoration is not None
            or dict(operation.arguments) != expected_arguments
        ):
            return False
    return plan_digest_for_authorization(authorization) == authorization.plan_sha256


def expected_operation_arguments(scenario_id: str, index: int) -> dict[str, str]:
    """Return exact arguments for a scenario operation number."""
    return operation_arguments(JOB_LIFECYCLE_OPERATIONS[scenario_id][index - 1])


class JobLifecycleObservationError(ValueError):
    """A typed observation is malformed or unavailable."""


@dataclass(frozen=True)
class RefreshProgressFacts:
    """Committed parent LibraryRefresh progress exposed by refresh detail."""

    phase: str | None
    completed_units: int | None
    total_units: int | None
    status_key: str | None
    issue_count: int | None
    parent_run_ref: str | None = None

    def has_committed_progress(self) -> bool:
        """Return whether this observation contains a committed unit fact."""
        return (
            type(self.completed_units) is int
            and self.completed_units > 0
            and (self.total_units is None or (type(self.total_units) is int and self.total_units >= 0))
        )

    def digest(self) -> str:
        """Return a sanitized digest for evidence binding."""
        return _sha256({
            "phase": self.phase,
            "completed_units": self.completed_units,
            "total_units": self.total_units,
            "status_key": self.status_key,
            "issue_count": self.issue_count,
            "parent_run_ref": self.parent_run_ref,
        })


@dataclass(frozen=True)
class JobLifecycleBaselineObservation:
    """Independent no-reset baseline facts; owner text is not substituted."""

    connected_serials: tuple[str, ...] | None
    android_api_level: int | None
    abi: str | None
    capabilities: frozenset[str] | None
    package_name: str | None
    version_code: int | None
    certificate_sha256: str | None
    artifact_sha256: str | None
    foreground_package: str | None
    interference_free: bool | None
    available_storage_bytes: int | None
    library_membership_count: int | None
    selected_root_ref: str | None
    last_scan_state: str | None
    visible_refresh_row_count: int | None
    active_refresh_row_count: int | None
    pending_cleanup_refs: tuple[str, ...] | None
    pending_restoration_refs: tuple[str, ...] | None
    refresh_control_present: bool | None
    jobs_navigation_present: bool | None
    task_continuity_ref: str | None
    observer_ref: str | None
    observer_receipt_sha256: str | None
    library_membership_ids: tuple[str, ...] | None = None
    selected_root_id: str | None = None
    job_states: tuple[tuple[str, str], ...] | None = None
    jobs_history_complete: bool | None = None
    terminal_refresh_run_refs: tuple[str, ...] | None = None

    def digest(self) -> str:
        """Return a stable digest without exposing private reference values."""
        return _sha256({
            "connected": self.connected_serials is not None,
            "api": self.android_api_level,
            "abi": self.abi,
            "capabilities": sorted(self.capabilities or ()),
            "package": self.package_name,
            "version": self.version_code,
            "certificate": self.certificate_sha256,
            "artifact": self.artifact_sha256,
            "foreground": self.foreground_package,
            "interference": self.interference_free,
            "storage": self.available_storage_bytes,
            "library_count": self.library_membership_count,
            "library_ids": None if self.library_membership_ids is None else sorted(self.library_membership_ids),
            "root_ref": self.selected_root_ref,
            "root_id": self.selected_root_id,
            "last_scan": self.last_scan_state,
            "rows": self.visible_refresh_row_count,
            "active_rows": self.active_refresh_row_count,
            "job_states": None if self.job_states is None else sorted(self.job_states),
            "jobs_history_complete": self.jobs_history_complete,
            "terminal_refs": None if self.terminal_refresh_run_refs is None else sorted(self.terminal_refresh_run_refs),
            "cleanup_count": None if self.pending_cleanup_refs is None else len(self.pending_cleanup_refs),
            "restoration_count": None if self.pending_restoration_refs is None else len(self.pending_restoration_refs),
            "refresh_control": self.refresh_control_present,
            "jobs_nav": self.jobs_navigation_present,
            "task": self.task_continuity_ref,
            "observer": self.observer_ref,
            "receipt": self.observer_receipt_sha256,
        })


@dataclass(frozen=True)
class ProcessAndForegroundObservation:
    """Independent process and foreground facts from one authorized observer."""

    process_state: ProcessState
    package_name: str
    foreground_package: str | None
    task_continuity_ref: str | None
    observer_ref: str | None

    def digest(self) -> str:
        """Return a sanitized evidence digest."""
        return _sha256({
            "process": _process_state_value(self.process_state),
            "package": self.package_name,
            "foreground": self.foreground_package,
            "task": self.task_continuity_ref,
            "observer": self.observer_ref,
        })


@dataclass(frozen=True)
class ScanRunRelation:
    """One per-root ScanRun owned by its LibraryRefresh JobRun."""

    scan_run_ref: str | None
    parent_run_ref: str | None
    root_ref: str | None

    def established(self) -> bool:
        """Require the complete typed ScanRun attribution tuple."""
        return all(
            type(value) is str
            and 1 <= len(value) <= 256
            and bool(value.strip())
            for value in (self.scan_run_ref, self.parent_run_ref, self.root_ref)
        )

    def digest(self) -> str:
        """Return a digest of the exact run/root relation."""
        return _sha256({
            "scan_run": self.scan_run_ref,
            "parent_run": self.parent_run_ref,
            "root": self.root_ref,
        })


class RootExclusionReason(str, Enum):
    """Typed SPEC-BE-013 reason that a requested root was not admitted."""

    ALREADY_SCANNING = "already_scanning"
    NO_LONGER_CONFIGURED = "no_longer_configured"
    INVALID_CONFIGURATION = "invalid_configuration"


@dataclass(frozen=True)
class RootExclusionObservation:
    """One successor root exclusion with its authoritative typed reason."""

    root_ref: str | None
    reason: RootExclusionReason | None

    def established(self) -> bool:
        """Require a bounded root identity and a recognized exclusion reason."""
        return (
            type(self.root_ref) is str
            and 1 <= len(self.root_ref) <= 256
            and bool(self.root_ref.strip())
            and type(self.reason) is RootExclusionReason
        )

    def digest(self) -> str:
        """Hash the excluded root and its typed reason for private evidence."""
        return _sha256({
            "root": self.root_ref,
            "reason": self.reason.value if type(self.reason) is RootExclusionReason else None,
        })


def _root_scope_partition_complete(
    requested_root_refs: object,
    admitted_root_refs: object,
    excluded_root_refs: object,
) -> bool:
    """Require a nonempty requested-root set split exactly into admitted/excluded roots."""
    scopes = (requested_root_refs, admitted_root_refs, excluded_root_refs)
    if any(
        type(scope) is not tuple
        or any(
            type(value) is not str
            or not 1 <= len(value) <= 256
            or not value.strip()
            for value in scope
        )
        or len(set(scope)) != len(scope)
        for scope in scopes
    ):
        return False
    requested, admitted, excluded = scopes
    return (
        bool(requested)
        and not set(admitted).intersection(excluded)
        and set(requested) == set(admitted).union(excluded)
    )


@dataclass(frozen=True)
class JobIdentityObservation:
    """Owner-private parent scope and per-root ScanRun relations."""

    parent_run_ref: str | None
    scan_run_relations: tuple[ScanRunRelation, ...] | None
    requested_root_refs: tuple[str, ...] | None
    admitted_root_refs: tuple[str, ...] | None
    excluded_root_refs: tuple[str, ...] | None
    frozen_scope_ref: str | None
    observer_ref: str | None
    parent_state: RecoveryState | None = None
    source_run_ref: str | None = None
    successor_run_ref: str | None = None
    successor_scan_run_relations: tuple[ScanRunRelation, ...] | None = None
    successor_scope_ref: str | None = None
    successor_requested_root_refs: tuple[str, ...] | None = None
    successor_admitted_root_refs: tuple[str, ...] | None = None
    successor_excluded_root_refs: tuple[str, ...] | None = None
    successor_exclusions: tuple[RootExclusionObservation, ...] | None = None
    retry_relation_lookup_completed: bool | None = None
    retry_lookup_source_run_ref: str | None = None

    def root_scope_complete(self) -> bool:
        """Require exact, unique requested/admitted/excluded root partitions."""
        return (
            _root_scope_partition_complete(
                self.requested_root_refs,
                self.admitted_root_refs,
                self.excluded_root_refs,
            )
            and type(self.frozen_scope_ref) is str
            and 1 <= len(self.frozen_scope_ref) <= 256
            and bool(self.frozen_scope_ref.strip())
        )

    def root_scope_matches(
        self,
        expected_requested_root_refs: object,
        expected_admitted_root_refs: object,
        expected_excluded_root_refs: object,
    ) -> bool:
        """Require the same exact requested/admitted/excluded root identity sets."""
        return (
            self.root_scope_complete()
            and _root_scope_partition_complete(
                expected_requested_root_refs,
                expected_admitted_root_refs,
                expected_excluded_root_refs,
            )
            and set(self.requested_root_refs)
            == set(expected_requested_root_refs)
            and set(self.admitted_root_refs)
            == set(expected_admitted_root_refs)
            and set(self.excluded_root_refs)
            == set(expected_excluded_root_refs)
        )

    def parent_identity_complete(self) -> bool:
        """Validate the parent identity and its frozen root-scope snapshot."""
        return (
            type(self.parent_run_ref) is str
            and 1 <= len(self.parent_run_ref) <= 256
            and bool(self.parent_run_ref.strip())
            and self.root_scope_complete()
            and type(self.observer_ref) is str
            and bool(self.observer_ref)
            and (self.parent_state is None or type(self.parent_state) is RecoveryState)
        )

    def scan_relationships_complete(self) -> bool:
        """Require exactly one correctly owned ScanRun for every admitted root."""
        if not self.parent_identity_complete():
            return False
        return _scan_run_relations_complete(
            self.scan_run_relations,
            expected_parent_ref=self.parent_run_ref,
            expected_root_refs=self.admitted_root_refs,
        )

    def successor_root_scope_complete(self) -> bool:
        """Require Retry to preserve requested roots and report its current partition."""
        exclusions = self.successor_exclusions
        return (
            self.root_scope_complete()
            and _root_scope_partition_complete(
                self.successor_requested_root_refs,
                self.successor_admitted_root_refs,
                self.successor_excluded_root_refs,
            )
            and set(self.successor_requested_root_refs)
            == set(self.requested_root_refs)
            and type(exclusions) is tuple
            and all(
                type(exclusion) is RootExclusionObservation
                and exclusion.established()
                for exclusion in exclusions
            )
            and len({exclusion.root_ref for exclusion in exclusions})
            == len(exclusions)
            and {exclusion.root_ref for exclusion in exclusions}
            == set(self.successor_excluded_root_refs)
        )

    def successor_root_scope_matches(
        self,
        expected_requested_root_refs: object,
        expected_admitted_root_refs: object,
        expected_excluded_root_refs: object,
        expected_exclusions: object,
    ) -> bool:
        """Require a later observation to preserve the admitted Retry partition."""
        return (
            self.successor_root_scope_complete()
            and _root_scope_partition_complete(
                expected_requested_root_refs,
                expected_admitted_root_refs,
                expected_excluded_root_refs,
            )
            and set(self.successor_requested_root_refs)
            == set(expected_requested_root_refs)
            and set(self.successor_admitted_root_refs)
            == set(expected_admitted_root_refs)
            and set(self.successor_excluded_root_refs)
            == set(expected_excluded_root_refs)
            and type(expected_exclusions) is tuple
            and all(
                type(exclusion) is RootExclusionObservation
                and exclusion.established()
                for exclusion in expected_exclusions
            )
            and set(self.successor_exclusions) == set(expected_exclusions)
        )

    def retry_complete(self) -> bool:
        """Require distinct runs and an exact current-eligibility successor partition."""
        return (
            self.scan_relationships_complete()
            and type(self.source_run_ref) is str
            and self.source_run_ref == self.parent_run_ref
            and type(self.successor_run_ref) is str
            and 1 <= len(self.successor_run_ref) <= 256
            and bool(self.successor_run_ref.strip())
            and self.successor_run_ref != self.source_run_ref
            and self.successor_root_scope_complete()
            and _scan_run_relations_complete(
                self.successor_scan_run_relations,
                expected_parent_ref=self.successor_run_ref,
                expected_root_refs=self.successor_admitted_root_refs,
            )
            and {
                relation.scan_run_ref
                for relation in self.scan_run_relations or ()
            }.isdisjoint(
                relation.scan_run_ref
                for relation in self.successor_scan_run_relations or ()
            )
            and type(self.successor_scope_ref) is str
            and self.successor_scope_ref == self.frozen_scope_ref
        )

    def digest(self) -> str:
        """Hash the relation and root scope without exposing raw identifiers."""
        return _sha256({
            "parent": self.parent_run_ref,
            "scan_run_relations": (
                None
                if self.scan_run_relations is None
                else tuple(relation.digest() for relation in self.scan_run_relations)
            ),
            "requested_roots": self.requested_root_refs,
            "admitted_roots": self.admitted_root_refs,
            "excluded_roots": self.excluded_root_refs,
            "scope": self.frozen_scope_ref,
            "observer": self.observer_ref,
            "parent_state": _recovery_state_value(self.parent_state),
            "source": self.source_run_ref,
            "successor": self.successor_run_ref,
            "successor_scan_run_relations": (
                None
                if self.successor_scan_run_relations is None
                else tuple(
                    relation.digest()
                    for relation in self.successor_scan_run_relations
                    if type(relation) is ScanRunRelation
                )
            ),
            "successor_scope": self.successor_scope_ref,
            "successor_requested_roots": self.successor_requested_root_refs,
            "successor_admitted_roots": self.successor_admitted_root_refs,
            "successor_excluded_roots": self.successor_excluded_root_refs,
            "successor_exclusions": (
                None
                if self.successor_exclusions is None
                else tuple(
                    exclusion.digest()
                    for exclusion in self.successor_exclusions
                    if type(exclusion) is RootExclusionObservation
                )
            ),
            "retry_lookup_completed": self.retry_relation_lookup_completed,
            "retry_lookup_source": self.retry_lookup_source_run_ref,
        })


@dataclass(frozen=True)
class LatencyCycle:
    """One independently timed latency cycle."""

    action_id: str
    warmup: bool
    elapsed_milliseconds: int
    return_completed: bool
    evidence_ref: str


@dataclass(frozen=True)
class LatencyCriterion:
    """Owner-approved performance rule required before a latency verdict."""

    workload_ref: str | None
    environment_ref: str | None
    rule_sha256: str | None
    per_cycle_timeout_seconds: int | None
    percentile_95_ceiling_milliseconds: int | None
    action_ids: tuple[str, ...]
    warmup_cycles: int = 5
    measured_cycles: int = 20


ACTIVE_STATES = frozenset({RecoveryState.ACTIVE})
TERMINAL_STATES = frozenset({
    RecoveryState.COMPLETED,
    RecoveryState.COMPLETED_WITH_ISSUES,
    RecoveryState.FAILED,
    RecoveryState.CANCELLED,
    RecoveryState.ABANDONED,
    RecoveryState.INTERRUPTED,
})


def _optional_count(value: object) -> bool:
    return value is None or (type(value) is int and value >= 0)


def _recovery_state_value(value: object) -> str | None:
    return value.value if type(value) is RecoveryState else None


def _process_state_value(value: object) -> str | None:
    return value.value if type(value) is ProcessState else None


def _optional_ref(value: object) -> bool:
    return value is None or (type(value) is str and 1 <= len(value) <= 256)


def _scan_run_relations_complete(
    relations: object,
    *,
    expected_parent_ref: object,
    expected_root_refs: object,
) -> bool:
    """Validate one exact owner-bound ScanRun relation for each admitted root."""
    if (
        type(expected_parent_ref) is not str
        or not 1 <= len(expected_parent_ref) <= 256
        or not expected_parent_ref.strip()
        or type(expected_root_refs) is not tuple
        or not expected_root_refs
        or type(relations) is not tuple
        or any(
            type(relation) is not ScanRunRelation or not relation.established()
            for relation in relations
        )
    ):
        return False
    scan_ids = tuple(relation.scan_run_ref for relation in relations)
    parent_ids = tuple(relation.parent_run_ref for relation in relations)
    roots = tuple(relation.root_ref for relation in relations)
    return (
        len(scan_ids) == len(expected_root_refs)
        and len(set(scan_ids)) == len(scan_ids)
        and len(set(roots)) == len(roots)
        and all(parent == expected_parent_ref for parent in parent_ids)
        and set(roots) == set(expected_root_refs)
    )


@dataclass(frozen=True)
class GameIdRedirect:
    """One independently observed GameId continuity edge."""

    source_game_id: str | None
    canonical_game_id: str | None
    job_run_ref: str | None

    def established(self) -> bool:
        """Require the redirect to name exact identities and its owning run."""
        return all(
            type(value) is str and 1 <= len(value) <= 256 and bool(value.strip())
            for value in (
                self.source_game_id,
                self.canonical_game_id,
                self.job_run_ref,
            )
        ) and self.source_game_id != self.canonical_game_id

    def digest(self) -> str:
        """Return a digest of the exact continuity edge."""
        return _sha256({
            "source": self.source_game_id,
            "canonical": self.canonical_game_id,
            "job_run": self.job_run_ref,
        })


@dataclass(frozen=True)
class GameIdContinuityObservation:
    """Complete, run-bound redirect lookup with its exact queried GameIds."""

    job_run_ref: str | None
    redirects: tuple[GameIdRedirect, ...] | None
    complete: bool | None
    observer_ref: str | None
    queried_game_ids: tuple[str, ...] | None

    def established(self) -> bool:
        """Require complete redirect evidence and a bounded unique query scope."""
        return (
            type(self.job_run_ref) is str
            and 1 <= len(self.job_run_ref) <= 256
            and bool(self.job_run_ref.strip())
            and type(self.redirects) is tuple
            and all(
                type(redirect) is GameIdRedirect and redirect.established()
                for redirect in self.redirects
            )
            and all(
                redirect.job_run_ref == self.job_run_ref
                for redirect in self.redirects
            )
            and len({redirect.source_game_id for redirect in self.redirects})
            == len(self.redirects)
            and type(self.queried_game_ids) is tuple
            and all(
                type(game_id) is str
                and 1 <= len(game_id) <= 256
                and bool(game_id.strip())
                for game_id in self.queried_game_ids
            )
            and len(set(self.queried_game_ids)) == len(self.queried_game_ids)
            and all(
                redirect.source_game_id in self.queried_game_ids
                for redirect in self.redirects
            )
            and self.complete is True
            and type(self.observer_ref) is str
            and bool(self.observer_ref)
        )

    def digest(self) -> str:
        """Return a digest without exposing raw GameIds or observer references."""
        return _sha256({
            "job_run": self.job_run_ref,
            "redirects": (
                None
                if self.redirects is None
                else tuple(redirect.digest() for redirect in self.redirects)
            ),
            "complete": self.complete,
            "queried_game_ids": self.queried_game_ids,
            "observer": self.observer_ref,
        })


@dataclass(frozen=True)
class LibrarySurfaceObservation:
    """Library facts available on the verified Library surface."""

    surface: JobLifecycleSurface | None
    membership_count: int | None
    refresh_control_present: bool | None
    refresh_active: bool | None
    observer_ref: str | None
    membership_ids: tuple[str, ...] | None = None
    next_page_available: bool | None = None
    identity_continuity: GameIdContinuityObservation | None = None

    def established(self) -> bool:
        """Return whether the Library surface and its fixed controls are proven."""
        return (
            self.surface is JobLifecycleSurface.LIBRARY
            and type(self.membership_count) is int
            and self.membership_count >= 0
            and self.refresh_control_present is True
            and type(self.refresh_active) is bool
            and type(self.observer_ref) is str
            and bool(self.observer_ref)
        )

    def membership_identity_complete(self) -> bool:
        """Return whether this one result covers the exact complete GameId set."""
        return (
            type(self.membership_ids) is tuple
            and all(
                type(value) is str
                and 1 <= len(value) <= 256
                and bool(value.strip())
                for value in self.membership_ids
            )
            and len(set(self.membership_ids)) == len(self.membership_ids)
            and type(self.membership_count) is int
            and self.membership_count == len(self.membership_ids)
            and self.next_page_available is False
        )

    def digest(self) -> str:
        """Return a sanitized evidence digest."""
        return _sha256({
            "surface": None if self.surface is None else self.surface.value,
            "membership": self.membership_count,
            "membership_ids": (
                None
                if self.membership_ids is None
                else sorted(self.membership_ids)
            ),
            "next_page_available": self.next_page_available,
            "identity_continuity": (
                None
                if type(self.identity_continuity) is not GameIdContinuityObservation
                else self.identity_continuity.digest()
            ),
            "refresh_control": self.refresh_control_present,
            "refresh_active": self.refresh_active,
            "observer": self.observer_ref,
        })


@dataclass(frozen=True)
class JobsSurfaceObservation:
    """Jobs facts available on the verified Jobs surface."""

    surface: JobLifecycleSurface | None
    parent_run_ref: str | None
    state: RecoveryState | None
    refresh_row_count: int | None
    active_refresh_row_count: int | None
    jobs_navigation_present: bool | None
    observer_ref: str | None
    history_complete: bool | None = None
    terminal_refresh_run_refs: tuple[str, ...] | None = None

    def established(self) -> bool:
        """Return whether the Jobs surface is proven for a read-only observation."""
        return (
            self.surface is JobLifecycleSurface.JOBS
            and (self.state is None or type(self.state) is RecoveryState)
            and self.jobs_navigation_present is True
            and _optional_count(self.refresh_row_count)
            and _optional_count(self.active_refresh_row_count)
            and type(self.observer_ref) is str
            and bool(self.observer_ref)
            and self.history_complete is True
            and type(self.terminal_refresh_run_refs) is tuple
            and all(
                type(value) is str and 1 <= len(value) <= 256
                for value in self.terminal_refresh_run_refs
            )
            and len(set(self.terminal_refresh_run_refs))
            == len(self.terminal_refresh_run_refs)
            and self.refresh_row_count
            == self.active_refresh_row_count + len(self.terminal_refresh_run_refs)
        )

    def digest(self) -> str:
        """Return a sanitized evidence digest."""
        return _sha256({
            "surface": None if self.surface is None else self.surface.value,
            "parent": self.parent_run_ref,
            "state": _recovery_state_value(self.state),
            "rows": self.refresh_row_count,
            "active_rows": self.active_refresh_row_count,
            "history_complete": self.history_complete,
            "terminal_refs": None if self.terminal_refresh_run_refs is None else sorted(self.terminal_refresh_run_refs),
            "jobs_nav": self.jobs_navigation_present,
            "observer": self.observer_ref,
        })


@dataclass(frozen=True)
class RefreshDetailObservation:
    """Library Refresh detail facts from the verified detail surface."""

    parent_run_ref: str | None
    state: RecoveryState | None
    progress: RefreshProgressFacts | None
    retry_control_count: int | None
    retry_source_run_ref: str | None
    retry_successor_run_ref: str | None
    cancellation_requested: bool | None
    observer_ref: str | None

    def established(self) -> bool:
        """Return whether identity, state, and progress are all readable."""
        return (
            type(self.parent_run_ref) is str
            and bool(self.parent_run_ref)
            and type(self.state) is RecoveryState
            and self.state in ACTIVE_STATES | TERMINAL_STATES
            and type(self.progress) is RefreshProgressFacts
            and _optional_count(self.retry_control_count)
            and _optional_ref(self.retry_source_run_ref)
            and _optional_ref(self.retry_successor_run_ref)
            and type(self.cancellation_requested) is bool
            and type(self.observer_ref) is str
            and bool(self.observer_ref)
        )

    def digest(self) -> str:
        """Return a sanitized evidence digest."""
        return _sha256({
            "parent": self.parent_run_ref,
            "state": _recovery_state_value(self.state),
            "progress": None if self.progress is None else self.progress.digest(),
            "retry_controls": self.retry_control_count,
            "source": self.retry_source_run_ref,
            "successor": self.retry_successor_run_ref,
            "cancellation": self.cancellation_requested,
            "observer": self.observer_ref,
        })


@dataclass(frozen=True)
class ScanRootObservation:
    """Sources root-detail scan identity, distinct from View Job navigation."""

    surface: JobLifecycleSurface | None
    root_ref: str | None
    last_scan_state: str | None
    view_job_control_count: int | None
    view_job_run_ref: str | None
    observer_ref: str | None
    presentation: ScanRootPresentation | None = None
    scan_run_ref: str | None = None
    scan_parent_run_ref: str | None = None

    def established(self) -> bool:
        """Return whether the root identity and last-scan state are proven."""
        return (
            self.surface is JobLifecycleSurface.SCAN_ROOT_DETAIL
            and type(self.root_ref) is str
            and bool(self.root_ref)
            and type(self.last_scan_state) is str
            and bool(self.last_scan_state)
            and _optional_count(self.view_job_control_count)
            and _optional_ref(self.view_job_run_ref)
            and type(self.scan_run_ref) is str
            and 1 <= len(self.scan_run_ref) <= 256
            and bool(self.scan_run_ref.strip())
            and type(self.scan_parent_run_ref) is str
            and 1 <= len(self.scan_parent_run_ref) <= 256
            and bool(self.scan_parent_run_ref.strip())
            and type(self.observer_ref) is str
            and bool(self.observer_ref)
        )

    def _surface_identified(self) -> bool:
        """Return whether the root ScanRun presentation is independently identified."""
        return (
            self.surface is JobLifecycleSurface.SCAN_ROOT_DETAIL
            and type(self.root_ref) is str
            and bool(self.root_ref)
            and _optional_count(self.view_job_control_count)
            and _optional_ref(self.view_job_run_ref)
            and type(self.scan_run_ref) is str
            and 1 <= len(self.scan_run_ref) <= 256
            and bool(self.scan_run_ref.strip())
            and type(self.scan_parent_run_ref) is str
            and 1 <= len(self.scan_parent_run_ref) <= 256
            and bool(self.scan_parent_run_ref.strip())
            and type(self.observer_ref) is str
            and bool(self.observer_ref)
        )

    def active_scan_identified(self) -> bool:
        """Return whether the active-scan presentation is independently named."""
        return (
            self._surface_identified()
            and self.presentation is ScanRootPresentation.ACTIVE_SCAN
            and self.last_scan_state is None
        )

    def historical_last_scan_identified(self) -> bool:
        """Return whether a historical last-scan presentation is independently named."""
        return (
            self._surface_identified()
            and self.presentation is ScanRootPresentation.HISTORICAL_LAST_SCAN
            and self.last_scan_state in ROOT_HISTORICAL_SCAN_STATES
        )

    def digest(self) -> str:
        """Return a sanitized evidence digest."""
        return _sha256({
            "surface": None if self.surface is None else self.surface.value,
            "root": self.root_ref,
            "last_scan": self.last_scan_state,
            "presentation": None if self.presentation is None else self.presentation.value,
            "view_job_controls": self.view_job_control_count,
            "view_job_run": self.view_job_run_ref,
            "scan_run": self.scan_run_ref,
            "scan_parent_run": self.scan_parent_run_ref,
            "observer": self.observer_ref,
        })


@dataclass(frozen=True)
class ScanRunObservation:
    """One per-root ScanRun row from its owning LibraryRefresh detail."""

    surface: JobLifecycleSurface | None
    parent_run_ref: str | None
    scan_run_ref: str | None
    root_ref: str | None
    parent_state: RecoveryState | None
    scan_state: str | None
    observer_ref: str | None

    def established(self) -> bool:
        """Require exact parent/ScanRun/root identity and typed lifecycle facts."""
        return (
            self.surface is JobLifecycleSurface.REFRESH_DETAIL
            and all(
                type(value) is str
                and 1 <= len(value) <= 256
                and bool(value.strip())
                for value in (
                    self.parent_run_ref,
                    self.scan_run_ref,
                    self.root_ref,
                )
            )
            and type(self.parent_state) is RecoveryState
            and self.parent_state in ACTIVE_STATES | TERMINAL_STATES
            and type(self.scan_state) is str
            and self.scan_state in ROOT_HISTORICAL_SCAN_STATES | {"scanning"}
            and type(self.observer_ref) is str
            and bool(self.observer_ref)
        )

    def digest(self) -> str:
        """Return a sanitized evidence digest."""
        return _sha256({
            "surface": None if self.surface is None else self.surface.value,
            "parent_run": self.parent_run_ref,
            "scan_run": self.scan_run_ref,
            "root": self.root_ref,
            "parent_state": _recovery_state_value(self.parent_state),
            "scan_state": self.scan_state,
            "observer": self.observer_ref,
        })
