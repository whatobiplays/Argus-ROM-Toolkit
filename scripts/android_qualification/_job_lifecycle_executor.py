"""Private Issue #28 executor for the closed Android job lifecycle plans.

The module runs AND-04 and AND-05 from an exact admitted session. It owns its
operation dispatch, typed observations, recovery classification, and evidence
writing. It does not inherit the Issue #26 scan/fixture executor, does not
invoke ADB, and never infers job identity from presentation order or timing.

The executor is loaded lazily only after admission checks the exact private
executor type. A fake transport can prove host harness behavior. Nothing here
can establish physical Android qualification or issue an owner verdict.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
import time
from typing import Protocol

from . import admission as _admission
from . import evidence
from ._job_lifecycle_contract import (
    ACTIVE_STATES,
    TERMINAL_STATES,
    JOB_LIFECYCLE_CLOSURE_SECONDS,
    JOB_LIFECYCLE_OPERATIONS,
    JOB_LIFECYCLE_QUALIFICATION_PACKAGE,
    JOB_LIFECYCLE_SCENARIO_AND_04,
    JOB_LIFECYCLE_SCENARIO_AND_05,
    JOB_LIFECYCLE_SCENARIOS,
    JOB_LIFECYCLE_SESSION_SECONDS,
    ROOT_HISTORICAL_SCAN_STATES,
    JobIdentityObservation,
    JobLifecycleBaselineObservation,
    JobLifecycleOperationSpec,
    JobsSurfaceObservation,
    LibrarySurfaceObservation,
    ProcessAndForegroundObservation,
    ProcessState,
    RecoveryState,
    RefreshDetailObservation,
    RefreshProgressFacts,
    ScanJobObservation,
    ScanRootObservation,
    ScanRootPresentation,
    plan_digest_for_authorization,
    required_session_span,
    validate_job_lifecycle_authorization,
)
from ._job_lifecycle_oracle import (
    OracleResult,
    evaluate_latency,
    latency_execution_status,
    recovery_consistency,
    recovery_terminal_consistency,
    retry_eligibility,
    retry_outcome,
    retry_success_acceptance,
    terminal_successor,
    library_post_retry_integrity,
    library_recovery_persistence,
    scan_root_recovery_persistence,
    validate_active_progress_pair,
    validate_identity,
    validate_process_observation,
    validate_retry_precondition,
    validate_refresh_progress,
    validate_scan_root_post_retry,
    validate_scan_root_preloss,
)
from .manifest import (
    OperationAuthorization,
    OperationCategory,
    SessionStateMode,
)

_AddScanScopeExtension = _admission.AddScanScopeExtension
_AddScanStop = _admission._AddScanStop
_CallBudget = _admission._CallBudget
_DEVICE_SAFETY_PATH = _admission._DEVICE_SAFETY_PATH
_OperationDeadlineExpired = _admission._OperationDeadlineExpired
_SessionIntegrityError = _admission._SessionIntegrityError
_add_scan_alias = _admission._add_scan_alias
_add_scan_timestamp = _admission._add_scan_timestamp
_authorized_transport_call = _admission._authorized_transport_call
_admitted_session_binding = _admission._admitted_session_binding
_finish_admitted_session = _admission._finish_admitted_session
_now_is_utc = _admission._now_is_utc
_pending_for_device = _admission.pending_for_device
_validate_approval = _admission._validate_approval
SafetyStateError = _admission.SafetyStateError

SESSION_NAMESPACE = "argus-job-lifecycle"
_TERMINAL_ORACLE_CODE = "successor_terminal_observed"

class JobLifecycleTransport(Protocol):
    """Approved UI mutation and observation port for one pinned application."""

    def verify_target(
        self,
        serial: str,
        target_ref: str,
        timeout: int,
        *,
        action: str | None = None,
        package: str | None = None,
    ) -> bool:
        """Return whether the exact admitted device and target remain selected."""

    def navigate(
        self,
        action: str,
        timeout: int,
        *,
        expected_run_ref: str | None = None,
        expected_root_ref: str | None = None,
    ) -> bool:
        """Perform one exact shell or surface navigation and confirm the route."""

    def observe_library(self, timeout: int) -> LibrarySurfaceObservation:
        """Read the current Library surface."""

    def observe_jobs(self, timeout: int) -> JobsSurfaceObservation:
        """Read the current Jobs surface."""

    def observe_refresh_detail(
        self, parent_ref: str, timeout: int
    ) -> RefreshDetailObservation:
        """Read the named Library Refresh detail surface."""

    def observe_refresh_progress(
        self, parent_ref: str, timeout: int
    ) -> RefreshProgressFacts:
        """Read committed parent refresh progress through an approved observer."""

    def observe_scan_root(self, root_ref: str, timeout: int) -> ScanRootObservation:
        """Read the named Sources root detail."""

    def observe_scan_job(
        self, run_ref: str | None, timeout: int
    ) -> ScanJobObservation:
        """Read the current Library Scan job detail."""

    def start_refresh(self, timeout: int) -> None:
        """Perform the single approved Library Refresh start effect."""

    def retry_refresh(self, timeout: int) -> None:
        """Perform the single approved Retry effect on the source run."""

    def background_package(self, package: str, timeout: int) -> None:
        """Move the qualification task to the background."""

    def return_existing_task(self, package: str, task_ref: str, timeout: int) -> None:
        """Return the exact existing qualification task to the foreground."""

    def launch_package(self, package: str, timeout: int) -> None:
        """Launch the qualification package after proven process loss."""

    def force_stop_package(self, package: str, timeout: int) -> None:
        """Force-stop only the qualification package process."""

    def restore_foreground(self, package: str, task_ref: str, timeout: int) -> None:
        """Return the qualification task to the foreground as restoration only."""


class JobLifecycleObserver(Protocol):
    """Independent durable/process observer, separate from UI automation."""

    def observe_baseline(self, timeout: int) -> JobLifecycleBaselineObservation:
        """Read the authorized no-reset baseline facts."""

    def observe_identity(
        self, parent_ref: str | None, timeout: int
    ) -> JobIdentityObservation:
        """Read durable parent/child or retry identity relations."""

    def observe_process(
        self, package: str, timeout: int
    ) -> ProcessAndForegroundObservation:
        """Read process presence, foreground package, and task continuity."""


@dataclass(frozen=True)
class JobLifecycleExecutionResult:
    """Bounded host-side outcome of one lifecycle execution."""

    scenario_id: str
    status: str
    workflow_completed: bool
    completed_operations: int
    total_operations: int
    recovery_state: RecoveryState | None
    latency_status: str
    blocker: str
    scope_extensions: tuple[object, ...]
    execution_manifest_sha256: str | None = None


class _JobLifecycleStop(Exception):
    """Stop before another effect and retain one bounded reason."""

    def __init__(self, reason: str, *, failed: bool = False) -> None:
        self.reason = reason
        self.failed = failed
        super().__init__(reason)


class _OperationOutcomeJournal:
    """Track durable categorical outcomes and uncertain appends for one step."""

    def __init__(self) -> None:
        self._latest_persisted: evidence.AssertionOutcome | None = None
        self._append_uncertain = False

    def reset(self) -> None:
        self._latest_persisted = None
        self._append_uncertain = False

    def begin_append(self) -> None:
        self._append_uncertain = True

    def append_succeeded(self, outcome: evidence.AssertionOutcome) -> None:
        self._latest_persisted = outcome
        self._append_uncertain = False

    @property
    def has_persisted_outcome(self) -> bool:
        return self._latest_persisted is not None

    @property
    def can_append_fallback(self) -> bool:
        nonpassing = {
            evidence.AssertionOutcome.BLOCKED,
            evidence.AssertionOutcome.FAILED,
        }
        return not self._append_uncertain and self._latest_persisted not in nonpassing


def _valid_ref(value: object) -> bool:
    return type(value) is str and 1 <= len(value) <= 256


class _JobLifecycleOperationExecutor:
    """Run one exact AND-04 or AND-05 plan with typed fail-closed steps."""

    def __init__(
        self,
        *,
        session: _admission.AdmittedSession,
        transport: JobLifecycleTransport,
        observer: JobLifecycleObserver,
        writer: evidence.ExecutionWriter,
        evidence_spec: evidence.SessionSpec,
        monotonic=time.monotonic,
        sleeper=time.sleep,
    ) -> None:
        self._session = session
        self._transport = transport
        self._observer = observer
        self._writer = writer
        self._spec = evidence_spec
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
        self._execution_manifest_sha256: str | None = None
        self._evidence_refs: tuple[str, ...] = ()
        self._scenario_id = ""
        self._baseline: JobLifecycleBaselineObservation | None = None
        self._baseline_binding_sha256: str | None = None
        self._task_ref: str | None = None
        self._parent_ref: str | None = None
        self._scope_ref: str | None = None
        self._parent_state: RecoveryState | None = None
        self._first_progress: RefreshProgressFacts | None = None
        self._library_count: int | None = None
        self._preloss_library_ids: tuple[str, ...] | None = None
        self._recovered_library_ids: tuple[str, ...] | None = None
        self._scan_root_ref: str | None = None
        self._preloss_root: ScanRootObservation | None = None
        self._child_refs: tuple[str, ...] = ()
        self._root_last_scan_ref: str | None = None
        self._scan_job_ref: str | None = None
        self._successor_ref: str | None = None
        self._successor_state: RecoveryState | None = None
        self._refresh_attempted = False
        self._refresh_started = False
        self._force_stop_observed = False
        self._retry_dispatched = False
        self._retry_observed = False
        self._root_persistence_verified = False
        self._library_persistence_verified = False
        self._completed_operations = 0
        self._workflow_completed = False
        self._assertion_failed = False
        self._blocker = ""
        self._interrupted = False
        self._scope_extensions: list[object] = []
        self._planned_operations: tuple[OperationAuthorization, ...] = ()
        self._attempted_index: int | None = None
        self._attempted_operation: OperationAuthorization | None = None
        self._attempted_outcome = _OperationOutcomeJournal()

    # -- shared primitives -------------------------------------------------

    def _logical_now(self) -> datetime:
        assert self._base_time is not None
        return self._base_time + timedelta(
            seconds=max(0.0, self._monotonic() - self._started)
        )

    def _current_operation(self, operation: OperationAuthorization) -> None:
        authorization = self._session.authorization
        instant = self._logical_now()
        deadline = authorization.session_deadline
        if (
            not _now_is_utc(instant)
            or instant >= deadline
            or instant >= self._session.approval.valid_until
            or not _validate_approval(authorization, self._session.approval, instant)
        ):
            raise _JobLifecycleStop("The approved session or approval deadline expired.")
        remaining = (deadline - instant).total_seconds()
        if remaining < 1:
            raise _JobLifecycleStop("The approved operation deadline expired.")
        self._operation_timeout = min(operation.timeout_seconds, int(remaining))
        self._operation_deadline = deadline
        self._operation_monotonic_deadline = (
            self._monotonic() + self._operation_timeout
        )
        try:
            self._active_budget = _CallBudget(self._operation_timeout)
        except _OperationDeadlineExpired:
            raise _JobLifecycleStop(
                "The approved operation deadline expired."
            ) from None

    def _budget(self) -> _CallBudget:
        if (
            self._operation_deadline is None
            or self._base_time is None
            or self._active_budget is None
        ):
            raise _JobLifecycleStop("The operation is not bound to an approved deadline.")
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
            raise _JobLifecycleStop("The approved operation deadline expired.")
        return self._active_budget

    def _call(
        self,
        operation,
        *,
        failure: str = "A typed lifecycle call failed or returned an uncertain outcome.",
    ):
        budget = self._budget()
        try:
            return _authorized_transport_call(self._session, budget, operation)
        except _SessionIntegrityError:
            raise _JobLifecycleStop(
                "The admitted session binding changed during transport."
            ) from None
        except _OperationDeadlineExpired:
            raise _JobLifecycleStop("The approved operation deadline expired.") from None
        except InterruptedError:
            raise KeyboardInterrupt from None
        except KeyboardInterrupt:
            raise
        except Exception:
            raise _JobLifecycleStop(failure) from None

    def _verify_effect_target(
        self,
        operation: OperationAuthorization,
        action: str,
        *,
        expected_process: ProcessState | None = None,
        require_foreground: bool = False,
    ) -> None:
        """Reject a changed target before dispatching one authorized effect."""
        authorization = self._session.authorization
        verified = self._call(
            lambda timeout: self._transport.verify_target(
                authorization.target_serial,
                authorization.target_ref,
                timeout,
                action=action,
                package=JOB_LIFECYCLE_QUALIFICATION_PACKAGE,
            ),
            failure="The authorized device or target could not be reverified.",
        )
        if verified is not True:
            self._record_blocked(operation, "target_changed")
            self._request_scope_extension(
                "exact target reverification",
                "The admitted device or target changed before the authorized effect.",
                "An owner-authorized observer restores the exact admitted target.",
            )
            raise _JobLifecycleStop(
                "The authorized device or target changed before the effect."
            )
        if expected_process is None:
            return
        observed = self._observe_process(operation)
        if (
            observed.process_state is not expected_process
            or observed.package_name != JOB_LIFECYCLE_QUALIFICATION_PACKAGE
            or (
                require_foreground
                and observed.foreground_package
                != JOB_LIFECYCLE_QUALIFICATION_PACKAGE
            )
        ):
            self._record_blocked(operation, "target_process_changed")
            self._request_scope_extension(
                "target process state",
                "The qualification package state changed before the authorized effect.",
                "An owner-authorized observer establishes the exact package state.",
            )
            raise _JobLifecycleStop(
                "The qualification package state changed before the effect."
            )

    def _request(self, key: str) -> evidence.WriteRequest:
        return evidence.WriteRequest(
            operation_id=_add_scan_alias(
                "operation", f"{self._spec.session_id}:{key}"
            ),
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
        attempted_categorical = (
            self._attempted_operation is not None
            and outcome
            in {
                evidence.AssertionOutcome.PASSED,
                evidence.AssertionOutcome.BLOCKED,
                evidence.AssertionOutcome.FAILED,
            }
        )
        if attempted_categorical:
            self._attempted_outcome.begin_append()
        try:
            self._writer.append_assertion(
                self._spec.session_id,
                evidence.AssertionObservation(
                    assertion_ref=_add_scan_alias(
                        "assertion", f"{self._spec.session_id}:{key}"
                    ),
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
        except Exception:
            if attempted_categorical:
                self._blocker = (
                    "The attempted operation outcome could not be durably appended; "
                    "evidence integrity is uncertain and owner recovery is required."
                )
            raise
        if attempted_categorical:
            self._attempted_outcome.append_succeeded(outcome)

    def _step_key(self, operation: OperationAuthorization) -> str:
        return operation.operation_id

    def _record_intent(self, operation: OperationAuthorization) -> None:
        self._append_assertion(
            self._step_key(operation) + ":intent",
            evidence.AssertionOutcome.NOT_RUN,
        )

    def _record_result(
        self, operation: OperationAuthorization, passed: bool
    ) -> None:
        if not passed:
            self._assertion_failed = True
        self._append_assertion(
            self._step_key(operation) + ":result",
            evidence.AssertionOutcome.PASSED
            if passed
            else evidence.AssertionOutcome.FAILED,
        )

    def _record_blocked(self, operation: OperationAuthorization, code: str) -> None:
        self._append_assertion(
            self._step_key(operation) + ":" + code,
            evidence.AssertionOutcome.BLOCKED,
        )

    def _record_operation_fallback(
        self,
        operation: OperationAuthorization,
        outcome: evidence.AssertionOutcome,
    ) -> None:
        """Persist a fallback unless the abort already has a durable non-pass."""
        if not self._attempted_outcome.can_append_fallback:
            # The failed append has uncertain durability; do not retry it.
            return
        try:
            self._append_assertion(
                self._step_key(operation) + ":operation-outcome-unrecorded",
                outcome,
            )
        except Exception:
            self._blocker = (
                "The attempted operation outcome could not be durably appended; "
                "evidence integrity is uncertain and owner recovery is required."
            )
            raise _JobLifecycleStop(self._blocker) from None

    def _request_scope_extension(
        self,
        area: str,
        reason: str,
        required_outcome: str,
    ) -> None:
        request = _AddScanScopeExtension(area, reason, required_outcome)
        if request not in self._scope_extensions:
            self._scope_extensions.append(request)

    def _uncertain_effect(self, operation: OperationAuthorization, area: str) -> None:
        self._blocker = (
            f"The {area} effect has an uncertain outcome; no retry is permitted."
        )
        self._request_scope_extension(
            area + " recovery",
            "The approved effect was sent but its exact result is unproven.",
            "An owner-authorized observer establishes the actual state before any recovery or continuation.",
        )
        self._record_blocked(operation, "uncertain")
        raise _JobLifecycleStop(self._blocker)

    def _require(self, condition: bool, reason: str, *, failed: bool = False) -> None:
        if not condition:
            raise _JobLifecycleStop(reason, failed=failed)

    # -- execution lifecycle ----------------------------------------------

    def execute(self, *, now: datetime | None = None) -> JobLifecycleExecutionResult:
        return _admission._execute_closed_admitted_session(self, now=now)

    def _validate_inputs(self) -> None:
        binding = _admission._job_lifecycle_admission_binding(self._session)
        self._binding = binding
        authorization = self._session.authorization
        self._scenario_id = authorization.scenario_ids[0]
        if (
            self._session.lifecycle is not _admission.SessionLifecycle.ACTIVE
            or self._session.execution_phase is not _admission.SessionExecutionPhase.ADMITTED
            or authorization.application_package != JOB_LIFECYCLE_QUALIFICATION_PACKAGE
            or authorization.state_mode is not SessionStateMode.NO_RESET
            or type(self._spec) is not evidence.SessionSpec
            or binding is None
            or binding.plan_sha256 != authorization.plan_sha256
            or not validate_job_lifecycle_authorization(authorization)
        ):
            raise _JobLifecycleStop(
                "The artifact, plan, target, baseline, or evidence pins do not match."
            )
        expected_session_id = _add_scan_alias(
            "session",
            f"{SESSION_NAMESPACE}:{authorization.authorization_id}:"
            f"{authorization.canonical_sha256}",
        )
        expected_evidence_refs = self._spec.review_requirements.required_evidence_refs
        if (
            self._spec.session_id != expected_session_id
            or self._spec.scenario_id
            != _add_scan_alias("scenario", self._scenario_id)
            or self._spec.artifact.artifact_sha256 != authorization.apk_sha256
            or self._spec.artifact.artifact_ref
            != _add_scan_alias("artifact", authorization.apk_sha256)
            or self._spec.authorization.manifest_sha256
            != authorization.canonical_sha256
            or self._spec.authorization.manifest_version != 1
            or self._spec.fixtures.manifest_sha256
            != authorization.fixture_manifest_sha256
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
            or self._spec.artifact.artifact_class
            is not evidence.ArtifactClass.QUALIFICATION_VARIANT
            or not expected_evidence_refs
        ):
            raise _JobLifecycleStop(
                "The artifact, plan, target, baseline, or evidence pins do not match."
            )
        if (
            plan_digest_for_authorization(authorization) != authorization.plan_sha256
            or binding.plan_sha256 != authorization.plan_sha256
        ):
            raise _JobLifecycleStop("The independently computed plan digest changed.")
        instant = self._logical_now()
        if (
            not _validate_approval(authorization, self._session.approval, instant)
            or instant >= authorization.session_deadline
            or instant
            + timedelta(seconds=required_session_span(self._scenario_id))
            > authorization.session_deadline
        ):
            raise _JobLifecycleStop(
                "The owner approval, session deadline, or positive reserve expired."
            )
        try:
            pending = _pending_for_device(
                authorization.target_serial,
                path=_DEVICE_SAFETY_PATH,
            )
        except SafetyStateError:
            raise _JobLifecycleStop(
                "Device restoration state is unavailable."
            ) from None
        if pending is not None:
            raise _JobLifecycleStop(
                "An unresolved restoration obligation blocks lifecycle operations."
            )
        self._evidence_refs = expected_evidence_refs
        self._baseline = binding.baseline
        self._baseline_binding_sha256 = binding.baseline_sha256
        self._task_ref = binding.task_continuity_ref

    def _plan_operations(self) -> tuple[OperationAuthorization, ...]:
        authorization = self._session.authorization
        if not validate_job_lifecycle_authorization(authorization):
            raise _JobLifecycleStop(
                "The approved operation plan is not the closed lifecycle sequence."
            )
        operations = authorization.operations
        specs = JOB_LIFECYCLE_OPERATIONS[self._scenario_id]
        if len(operations) != len(specs):
            raise _JobLifecycleStop(
                "The approved operation plan is not the closed lifecycle sequence."
            )
        for operation, spec in zip(operations, specs, strict=True):
            if (
                operation.operation_id != f"{self._scenario_id.lower()}-{spec.index:02d}"
                or operation.phase != "qualification"
            ):
                raise _JobLifecycleStop(
                    "The approved operation plan is not the closed lifecycle sequence."
                )
        return operations

    def _dispatch(
        self, operation: OperationAuthorization, spec: JobLifecycleOperationSpec
    ) -> None:
        if type(spec) is not JobLifecycleOperationSpec or not spec.handler:
            raise _JobLifecycleStop("The plan contains an unsupported lifecycle step.")
        handler = getattr(self, "_step_" + spec.handler, None)
        if handler is None:
            raise _JobLifecycleStop("The plan contains an unsupported lifecycle step.")
        self._current_operation(operation)
        handler(operation, spec)

    def _dispatch_all(self, operations: tuple[OperationAuthorization, ...]) -> None:
        specs = JOB_LIFECYCLE_OPERATIONS[self._scenario_id]
        for operation, spec in zip(operations, specs, strict=True):
            self._attempted_index = spec.index - 1
            self._attempted_operation = operation
            self._attempted_outcome.reset()
            try:
                self._dispatch(operation, spec)
            except _JobLifecycleStop as stop:
                self._record_operation_fallback(
                    operation,
                    evidence.AssertionOutcome.FAILED
                    if stop.failed
                    else evidence.AssertionOutcome.BLOCKED,
                )
                raise
            except KeyboardInterrupt:
                self._record_operation_fallback(
                    operation, evidence.AssertionOutcome.BLOCKED
                )
                raise
            except Exception:
                self._record_operation_fallback(
                    operation, evidence.AssertionOutcome.BLOCKED
                )
                raise _JobLifecycleStop(
                    "The operation failed before recording a categorical outcome."
                ) from None
            else:
                if not self._attempted_outcome.has_persisted_outcome:
                    self._record_operation_fallback(
                        operation, evidence.AssertionOutcome.BLOCKED
                    )
                    raise _JobLifecycleStop(
                        "The attempted lifecycle operation returned without a durable categorical outcome."
                    )
                self._completed_operations += 1
            finally:
                self._attempted_operation = None
        self._workflow_completed = True

    # -- observation helpers ----------------------------------------------

    def _observe_baseline(self, operation: OperationAuthorization) -> JobLifecycleBaselineObservation:
        value = self._call(lambda timeout: self._observer.observe_baseline(timeout))
        self._require(
            type(value) is JobLifecycleBaselineObservation,
            "The independent baseline observation is unavailable.",
        )
        return value

    def _observe_process(
        self, operation: OperationAuthorization
    ) -> ProcessAndForegroundObservation:
        value = self._call(
            lambda timeout: self._observer.observe_process(
                JOB_LIFECYCLE_QUALIFICATION_PACKAGE, timeout
            )
        )
        self._require(
            type(value) is ProcessAndForegroundObservation,
            "The independent process observation is unavailable.",
        )
        return value

    def _observe_library(self, operation: OperationAuthorization) -> LibrarySurfaceObservation:
        value = self._call(lambda timeout: self._transport.observe_library(timeout))
        self._require(
            type(value) is LibrarySurfaceObservation,
            "The Library surface observation is unavailable.",
        )
        return value

    def _observe_library_value(self, operation: OperationAuthorization):
        """Return a raw Library observation so the oracle can record BLOCKED."""
        return self._call(lambda timeout: self._transport.observe_library(timeout))

    def _observe_jobs(self, operation: OperationAuthorization) -> JobsSurfaceObservation:
        value = self._call(lambda timeout: self._transport.observe_jobs(timeout))
        self._require(
            type(value) is JobsSurfaceObservation,
            "The Jobs surface observation is unavailable.",
        )
        return value

    def _observe_detail(
        self, operation: OperationAuthorization, parent_ref: str
    ) -> RefreshDetailObservation:
        value = self._call(
            lambda timeout: self._transport.observe_refresh_detail(
                parent_ref, timeout
            )
        )
        self._require(
            type(value) is RefreshDetailObservation,
            "The Library Refresh detail observation is unavailable.",
        )
        return value

    def _observe_progress(
        self, operation: OperationAuthorization, parent_ref: str
    ) -> RefreshProgressFacts:
        value = self._call(
            lambda timeout: self._transport.observe_refresh_progress(
                parent_ref, timeout
            ),
            failure="Committed parent refresh progress is unavailable.",
        )
        self._require(
            type(value) is RefreshProgressFacts,
            "Committed parent refresh progress is unavailable.",
        )
        return value

    def _record_oracle(
        self, operation: OperationAuthorization, result: OracleResult
    ) -> None:
        if result.outcome is evidence.AssertionOutcome.PASSED:
            self._append_assertion(
                self._step_key(operation) + ":result",
                evidence.AssertionOutcome.PASSED,
            )
            return
        if result.outcome is evidence.AssertionOutcome.NOT_RUN:
            self._append_assertion(
                self._step_key(operation) + ":result",
                evidence.AssertionOutcome.NOT_RUN,
            )
            raise _JobLifecycleStop(result.code)
        if result.outcome is evidence.AssertionOutcome.FAILED:
            self._assertion_failed = True
            self._append_assertion(
                self._step_key(operation) + ":result",
                evidence.AssertionOutcome.FAILED,
            )
            raise _JobLifecycleStop(result.code, failed=True)
        self._record_blocked(operation, result.code)
        raise _JobLifecycleStop(result.code)

    # -- generic navigation ------------------------------------------------

    def _navigate(
        self,
        operation: OperationAuthorization,
        action: str,
        *,
        expected_run_ref: str | None = None,
        expected_root_ref: str | None = None,
    ) -> None:
        self._verify_effect_target(operation, action)
        try:
            self._record_intent(operation)
        except Exception:
            self._blocker = (
                "The lifecycle navigation intent could not be durably appended; "
                "no effect was dispatched and owner recovery is required."
            )
            raise
        try:
            ok = self._call(
                lambda timeout: self._transport.navigate(
                    action,
                    timeout,
                    expected_run_ref=expected_run_ref,
                    expected_root_ref=expected_root_ref,
                )
            )
        except _JobLifecycleStop:
            self._uncertain_effect(operation, f"{action} navigation")
        if ok is not True:
            self._uncertain_effect(operation, f"{action} navigation")
        try:
            self._record_result(operation, True)
        except Exception:
            self._blocker = (
                "The lifecycle navigation result could not be durably appended; "
                "no replay is permitted and owner recovery is required."
            )
            raise

    def _step_navigate_library(self, operation, spec) -> None:
        self._navigate(operation, "navigate_library")

    def _step_navigate_jobs(self, operation, spec) -> None:
        self._navigate(operation, "navigate_jobs")

    def _step_navigate_sources(self, operation, spec) -> None:
        self._navigate(operation, "navigate_sources")

    def _step_open_refresh_detail(self, operation, spec) -> None:
        self._require(
            _valid_ref(self._parent_ref),
            "The observed parent refresh identity is unavailable.",
        )
        self._navigate(
            operation,
            "open_refresh_detail",
            expected_run_ref=self._parent_ref,
        )

    def _step_open_scan_root(self, operation, spec) -> None:
        root_ref = (
            self._scan_root_ref
            or (None if self._baseline is None else self._baseline.selected_root_ref)
        )
        self._require(_valid_ref(root_ref), "The authorized Sources root is unavailable.")
        self._scan_root_ref = root_ref
        self._navigate(
            operation,
            "open_scan_root",
            expected_root_ref=root_ref,
        )

    def _step_open_scan_job_detail(self, operation, spec) -> None:
        self._require(
            _valid_ref(self._root_last_scan_ref),
            "A uniquely observed Sources last-scan identity is unavailable.",
        )
        self._navigate(
            operation,
            "open_scan_job_detail",
            expected_run_ref=self._root_last_scan_ref,
        )

    def _step_open_successor_detail(self, operation, spec) -> None:
        self._require(
            _valid_ref(self._successor_ref),
            "A uniquely verified retry successor identity is unavailable.",
        )
        self._navigate(
            operation,
            "open_retry_successor_detail",
            expected_run_ref=self._successor_ref,
        )

    # -- steps -------------------------------------------------------------

    def _step_baseline(self, operation, spec) -> None:
        observed = self._observe_baseline(operation)
        if (
            observed.digest() != self._baseline_binding_sha256
            or observed.connected_serials != (self._session.authorization.target_serial,)
        ):
            self._record_result(operation, False)
            raise _JobLifecycleStop(
                "The no-reset starting state changed from the admitted baseline.",
                failed=True,
            )
        self._require(
            observed.interference_free is True
            and _valid_ref(observed.selected_root_ref)
            and _valid_ref(observed.task_continuity_ref)
            and observed.pending_cleanup_refs == ()
            and observed.pending_restoration_refs == (),
            "The independent no-reset baseline is incomplete.",
        )
        self._task_ref = observed.task_continuity_ref
        self._record_result(operation, True)

    def _step_library_ready(self, operation, spec) -> None:
        observed = self._observe_library(operation)
        if not observed.established():
            self._record_blocked(operation, "library_surface_unavailable")
            raise _JobLifecycleStop("The Library surface is not proven.")
        self._library_count = observed.membership_count
        self._record_result(operation, True)

    def _step_jobs_preflight(self, operation, spec) -> None:
        observed = self._observe_jobs(operation)
        if not observed.established():
            self._record_blocked(operation, "jobs_surface_unavailable")
            raise _JobLifecycleStop("The Jobs surface is not proven.")
        if observed.history_complete is not True:
            self._record_blocked(operation, "jobs_history_incomplete")
            raise _JobLifecycleStop(
                "The Jobs history is paginated or incomplete."
            )
        if observed.active_refresh_row_count != 0:
            self._record_blocked(operation, "jobs_active_refresh_conflict")
            raise _JobLifecycleStop(
                "The no-reset baseline contains conflicting active refresh work."
            )
        if observed.parent_run_ref is not None or observed.state is not None:
            self._record_blocked(operation, "jobs_history_ambiguous")
            raise _JobLifecycleStop(
                "The preflight Jobs surface reports an ambiguous active identity."
            )
        baseline = self._baseline
        if (
            baseline is None
            or type(baseline.terminal_refresh_run_refs) is not tuple
            or type(baseline.visible_refresh_row_count) is not int
            or baseline.active_refresh_row_count != 0
        ):
            self._record_blocked(operation, "jobs_baseline_history_unavailable")
            raise _JobLifecycleStop(
                "The admitted Jobs history is unavailable for the preflight match."
            )
        expected = baseline.terminal_refresh_run_refs
        if len(set(expected)) != len(expected):
            self._record_blocked(operation, "jobs_baseline_history_ambiguous")
            raise _JobLifecycleStop(
                "The admitted Jobs history contains ambiguous identities."
            )
        if (
            observed.terminal_refresh_run_refs is None
            or len(set(observed.terminal_refresh_run_refs))
            != len(observed.terminal_refresh_run_refs)
            or tuple(sorted(observed.terminal_refresh_run_refs))
            != tuple(sorted(expected))
            or observed.refresh_row_count != baseline.visible_refresh_row_count
        ):
            self._record_blocked(operation, "jobs_history_baseline_mismatch")
            raise _JobLifecycleStop(
                "The preflight Jobs history does not match the admitted baseline."
            )
        self._record_result(operation, True)

    def _step_start_refresh(self, operation, spec) -> None:
        self._verify_effect_target(
            operation,
            "start_library_refresh",
            expected_process=ProcessState.PRESENT,
            require_foreground=True,
        )
        self._record_intent(operation)
        self._refresh_attempted = True
        try:
            self._call(lambda timeout: self._transport.start_refresh(timeout))
        except _JobLifecycleStop:
            self._uncertain_effect(operation, "Library Refresh start")
        self._refresh_started = True
        self._record_result(operation, True)

    def _step_refresh_arrival(self, operation, spec) -> None:
        identity = self._call(
            lambda timeout: self._observer.observe_identity(None, timeout)
        )
        self._require(
            type(identity) is JobIdentityObservation
            and identity.parent_child_complete()
            and identity.parent_state in ACTIVE_STATES,
            "A new active parent refresh identity was not observed.",
        )
        self._parent_ref = identity.parent_run_ref
        self._scope_ref = identity.frozen_scope_ref
        self._parent_state = identity.parent_state
        self._record_result(operation, True)

    def _step_refresh_progress_initial(self, operation, spec) -> None:
        self._require(_valid_ref(self._parent_ref), "The parent refresh identity is unavailable.")
        progress = self._observe_progress(operation, self._parent_ref)
        result = validate_refresh_progress(progress)
        self._record_oracle(operation, result)
        self._first_progress = progress

    def _step_refresh_progress_repeat(self, operation, spec) -> None:
        self._require(_valid_ref(self._parent_ref), "The parent refresh identity is unavailable.")
        progress = self._observe_progress(operation, self._parent_ref)
        result = validate_active_progress_pair(
            self._first_progress,
            progress,
            expected_parent_ref=self._parent_ref,
        )
        self._record_oracle(operation, result)

    def _step_jobs_active(self, operation, spec) -> None:
        observed = self._observe_jobs(operation)
        if not observed.established():
            self._record_blocked(operation, "jobs_surface_unavailable")
            raise _JobLifecycleStop("The Jobs surface is not proven.")
        if (
            observed.parent_run_ref != self._parent_ref
            or observed.state not in ACTIVE_STATES
            or observed.active_refresh_row_count != 1
        ):
            self._record_result(operation, False)
            raise _JobLifecycleStop(
                "The active Jobs row does not match the observed parent refresh.",
                failed=True,
            )
        self._record_result(operation, True)

    def _step_refresh_detail(self, operation, spec) -> None:
        self._require(_valid_ref(self._parent_ref), "The parent refresh identity is unavailable.")
        observed = self._observe_detail(operation, self._parent_ref)
        if (
            observed.parent_run_ref != self._parent_ref
            or observed.state is None
            or observed.state not in ACTIVE_STATES | TERMINAL_STATES
        ):
            self._record_result(operation, False)
            raise _JobLifecycleStop(
                "The refresh detail identity or lifecycle contradicts the observed parent.",
                failed=True,
            )
        if (
            observed.progress is not None
            and observed.progress.parent_run_ref != self._parent_ref
        ):
            self._record_blocked(operation, "refresh_progress_parent_mismatch")
            raise _JobLifecycleStop(
                "The refresh progress names a different parent refresh."
            )
        progress_result = validate_refresh_progress(observed.progress)
        if progress_result.outcome is not evidence.AssertionOutcome.PASSED:
            self._record_oracle(operation, progress_result)
        self._parent_state = observed.state
        self._record_result(operation, True)

    def _step_parent_child_identity(self, operation, spec) -> None:
        self._require(_valid_ref(self._parent_ref), "The parent refresh identity is unavailable.")
        identity = self._call(
            lambda timeout: self._observer.observe_identity(self._parent_ref, timeout)
        )
        self._require(
            type(identity) is JobIdentityObservation,
            "The child attribution observation is unavailable.",
        )
        if identity.parent_run_ref != self._parent_ref:
            self._record_result(operation, False)
            raise _JobLifecycleStop(
                "The child attribution names a different parent refresh.",
                failed=True,
            )
        result = validate_identity(identity)
        if result.outcome is evidence.AssertionOutcome.PASSED:
            self._child_refs = identity.child_run_refs or ()
            self._append_assertion(
                self._step_key(operation) + ":result",
                evidence.AssertionOutcome.PASSED,
            )
            return
        self._record_blocked(operation, "parent_child_attribution_unavailable")
        self._request_scope_extension(
            "parent refresh child attribution",
            "The UI surface does not expose the parent JobRunId or child ownership.",
            "An owner-authorized observer binds the exact parent run to its committed child work.",
        )
        raise _JobLifecycleStop("Parent-child attribution is BLOCKED.")

    def _step_library_active(self, operation, spec) -> None:
        observed = self._observe_library(operation)
        if (
            not observed.established()
            or observed.membership_count is None
            or observed.refresh_active is not True
        ):
            self._record_blocked(operation, "library_surface_unavailable")
            raise _JobLifecycleStop(
                "The Library surface or its active refresh is not proven."
            )
        self._record_result(operation, True)

    def _step_background(self, operation, spec) -> None:
        self._verify_effect_target(
            operation,
            "background_qualification_package",
            expected_process=ProcessState.PRESENT,
            require_foreground=True,
        )
        self._record_intent(operation)
        try:
            self._call(
                lambda timeout: self._transport.background_package(
                    JOB_LIFECYCLE_QUALIFICATION_PACKAGE, timeout
                )
            )
        except _JobLifecycleStop:
            self._uncertain_effect(operation, "background transition")
        self._record_result(operation, True)

    def _step_process_backgrounded(self, operation, spec) -> None:
        observed = self._observe_process(operation)
        result = validate_process_observation(
            observed,
            expected_state=ProcessState.PRESENT,
            expected_package=JOB_LIFECYCLE_QUALIFICATION_PACKAGE,
        )
        if result.outcome is not evidence.AssertionOutcome.PASSED:
            self._record_blocked(operation, result.code)
            raise _JobLifecycleStop("The background process state is not proven.")
        if type(observed.foreground_package) is not str or not observed.foreground_package:
            self._record_blocked(operation, "foreground_package_unidentified")
            raise _JobLifecycleStop("The background foreground identity is unavailable.")
        if observed.foreground_package == JOB_LIFECYCLE_QUALIFICATION_PACKAGE:
            self._record_result(operation, False)
            raise _JobLifecycleStop(
                "The qualification package remains in the foreground.",
                failed=True,
            )
        self._record_result(operation, True)

    def _step_return_existing_task(self, operation, spec) -> None:
        self._require(_valid_ref(self._task_ref), "The qualification task identity is unavailable.")
        self._verify_effect_target(
            operation,
            "return_existing_qualification_task",
            expected_process=ProcessState.PRESENT,
        )
        self._record_intent(operation)
        try:
            self._call(
                lambda timeout: self._transport.return_existing_task(
                    JOB_LIFECYCLE_QUALIFICATION_PACKAGE,
                    self._task_ref,
                    timeout,
                )
            )
        except _JobLifecycleStop:
            self._uncertain_effect(operation, "foreground return")
        self._record_result(operation, True)

    def _step_foreground_restored(self, operation, spec) -> None:
        observed = self._observe_process(operation)
        result = validate_process_observation(
            observed,
            expected_state=ProcessState.PRESENT,
            expected_package=JOB_LIFECYCLE_QUALIFICATION_PACKAGE,
        )
        if result.outcome is not evidence.AssertionOutcome.PASSED:
            self._record_blocked(operation, result.code)
            raise _JobLifecycleStop("The foreground process state is not proven.")
        if (
            observed.foreground_package != JOB_LIFECYCLE_QUALIFICATION_PACKAGE
            or observed.task_continuity_ref != self._task_ref
        ):
            self._record_result(operation, False)
            raise _JobLifecycleStop(
                "The original qualification task continuity was not preserved.",
                failed=True,
            )
        self._record_result(operation, True)

    def _step_jobs_returned(self, operation, spec) -> None:
        observed = self._observe_jobs(operation)
        if not observed.established():
            self._record_blocked(operation, "jobs_surface_unavailable")
            raise _JobLifecycleStop("The Jobs surface is not proven.")
        if (
            observed.parent_run_ref != self._parent_ref
            or observed.state is None
        ):
            self._record_blocked(operation, "parent_run_not_visible")
            raise _JobLifecycleStop("The original parent refresh is not visible on Jobs.")
        self._parent_state = observed.state
        self._record_result(operation, True)

    def _step_recovered_lifecycle(self, operation, spec) -> None:
        self._require(_valid_ref(self._parent_ref), "The parent refresh identity is unavailable.")
        observed = self._observe_detail(operation, self._parent_ref)
        if observed.parent_run_ref != self._parent_ref or observed.state is None:
            self._record_result(operation, False)
            raise _JobLifecycleStop(
                "The recovered refresh detail contradicts the parent identity.",
                failed=True,
            )
        self._parent_state = observed.state
        if self._scenario_id == JOB_LIFECYCLE_SCENARIO_AND_05:
            classification = recovery_consistency(
                observed.state,
                force_stop_observed=self._force_stop_observed,
                durable_cancellation_intent=observed.cancellation_requested is True,
            )
            if classification.outcome is evidence.AssertionOutcome.BLOCKED:
                if classification.code == "terminal_before_process_loss_proven":
                    consistency = recovery_terminal_consistency(observed.state)
                    if consistency.outcome is evidence.AssertionOutcome.PASSED:
                        self._append_assertion(
                            self._step_key(operation) + ":recovery-consistency",
                            evidence.AssertionOutcome.PASSED,
                        )
                    self._blocker = (
                        "The refresh reached a supported terminal state before "
                        "process loss was proven (terminal_before_process_loss_proven); "
                        "the process-loss scenario is BLOCKED and dependent retry "
                        "obligations are NOT_RUN."
                    )
                self._record_blocked(operation, classification.code)
                raise _JobLifecycleStop(classification.code)
            if classification.outcome is evidence.AssertionOutcome.FAILED:
                self._record_result(operation, False)
                raise _JobLifecycleStop(classification.code, failed=True)
            self._record_result(operation, True)
            return
        self._record_result(operation, True)

    # AND-05 recovery and retry steps --------------------------------------

    def _step_scan_root_preloss(self, operation, spec) -> None:
        root_ref = (
            self._scan_root_ref
            or (None if self._baseline is None else self._baseline.selected_root_ref)
        )
        self._require(_valid_ref(root_ref), "The authorized Sources root is unavailable.")
        self._scan_root_ref = root_ref
        observed = self._call(
            lambda timeout: self._transport.observe_scan_root(root_ref, timeout)
        )
        result = validate_scan_root_preloss(observed, expected_root_ref=root_ref)
        if result.outcome is evidence.AssertionOutcome.PASSED:
            self._preloss_root = observed
            self._record_result(operation, True)
            self._append_assertion(
                self._step_key(operation) + ":root-preloss",
                evidence.AssertionOutcome.PASSED,
            )
            return
        if result.outcome is evidence.AssertionOutcome.FAILED:
            self._record_result(operation, False)
            raise _JobLifecycleStop(result.code, failed=True)
        self._record_blocked(operation, result.code)
        self._append_assertion(
            self._step_key(operation) + ":root-preloss",
            evidence.AssertionOutcome.BLOCKED,
        )
        self._request_scope_extension(
            "pre-loss Sources root observation",
            "The root-detail presentation, exact run identity, or last-scan state is not independently identified.",
            "An owner-authorized observer establishes the exact Sources root and scan presentation before any process stop.",
        )
        self._blocker = (
            "The pre-loss Sources root state is BLOCKED; no process stop is permitted."
        )
        raise _JobLifecycleStop(self._blocker)

    def _step_scan_root_recovered(self, operation, spec) -> None:
        self._require(
            self._preloss_root is not None,
            "The pre-loss Sources root observation is unavailable.",
        )
        self._require(_valid_ref(self._scan_root_ref), "The Sources root identity is unavailable.")
        observed = self._call(
            lambda timeout: self._transport.observe_scan_root(
                self._scan_root_ref, timeout
            )
        )
        result = scan_root_recovery_persistence(self._preloss_root, observed)
        if result.outcome is evidence.AssertionOutcome.PASSED:
            self._root_persistence_verified = True
            self._record_result(operation, True)
            self._append_assertion(
                self._step_key(operation) + ":root-recovery-persistence",
                evidence.AssertionOutcome.PASSED,
            )
            child_refs = self._child_refs
            if (
                type(observed) is ScanRootObservation
                and observed.view_job_run_ref in child_refs
            ):
                self._append_assertion(
                    self._step_key(operation) + ":refresh-child-attribution",
                    evidence.AssertionOutcome.PASSED,
                )
            else:
                self._append_assertion(
                    self._step_key(operation) + ":refresh-child-attribution",
                    evidence.AssertionOutcome.BLOCKED,
                )
            return
        if result.outcome is evidence.AssertionOutcome.FAILED:
            self._record_result(operation, False)
            raise _JobLifecycleStop(result.code, failed=True)
        self._record_blocked(operation, result.code)
        self._append_assertion(
            self._step_key(operation) + ":root-recovery-persistence",
            evidence.AssertionOutcome.BLOCKED,
        )
        self._request_scope_extension(
            "recovered Sources root persistence",
            "The root presentation, exact last-scan run identity, or terminal transition is not independently established.",
            "An owner-authorized observer resolves the exact Sources root and last-scan state before Retry.",
        )
        self._blocker = (
            "The recovered Sources root state is BLOCKED; Retry is not permitted."
        )
        raise _JobLifecycleStop(self._blocker)

    def _step_library_recovered(self, operation, spec) -> None:
        self._require(
            self._preloss_library_ids is not None,
            "The pre-loss Library identity snapshot is unavailable.",
        )
        observed = self._observe_library_value(operation)
        result = library_recovery_persistence(
            self._preloss_library_ids,
            observed,
        )
        if result.outcome is evidence.AssertionOutcome.PASSED:
            self._recovered_library_ids = observed.membership_ids
            self._library_count = observed.membership_count
            self._library_persistence_verified = True
            self._record_result(operation, True)
            self._append_assertion(
                self._step_key(operation) + ":process-recovery-persistence",
                evidence.AssertionOutcome.PASSED,
            )
            return
        if result.outcome is evidence.AssertionOutcome.FAILED:
            self._record_result(operation, False)
            self._append_assertion(
                self._step_key(operation) + ":process-recovery-persistence",
                evidence.AssertionOutcome.FAILED,
            )
            self._request_scope_extension(
                "committed Library asset recovery",
                "An independently identity-bound committed Library asset disappeared during process recovery.",
                "The owner assesses the lost committed asset; no repair or Retry is permitted.",
            )
            self._blocker = (
                "A committed Library asset disappeared during recovery; Retry is not permitted."
            )
            raise _JobLifecycleStop(result.code, failed=True)
        self._record_blocked(operation, result.code)
        self._append_assertion(
            self._step_key(operation) + ":process-recovery-persistence",
            evidence.AssertionOutcome.BLOCKED,
        )
        self._request_scope_extension(
            "recovered Library identity",
            "The exact committed Library asset identities are missing or ambiguous after relaunch.",
            "An owner-authorized observer establishes every captured committed identity before Retry.",
        )
        self._blocker = (
            "The recovered Library asset identities are BLOCKED; Retry is not permitted."
        )
        raise _JobLifecycleStop(self._blocker)

    def _step_library_preloss(self, operation, spec) -> None:
        observed = self._observe_library(operation)
        if (
            not observed.established()
            or observed.refresh_active is not True
            or not observed.membership_identity_complete()
        ):
            self._record_blocked(operation, "library_membership_identity_unavailable")
            raise _JobLifecycleStop(
                "The pre-loss Library state, active refresh, or committed "
                "asset identities are not proven."
            )
        admitted = (
            None if self._baseline is None else self._baseline.library_membership_ids
        )
        if type(admitted) is not tuple or not admitted:
            self._record_blocked(operation, "library_admitted_identity_unavailable")
            raise _JobLifecycleStop(
                "The admitted committed Library asset identities are unavailable."
            )
        present = frozenset(observed.membership_ids)
        if any(identity not in present for identity in admitted):
            self._record_result(operation, False)
            raise _JobLifecycleStop(
                "An admitted committed Library asset was already missing before "
                "the controlled interruption.",
                failed=True,
            )
        self._library_count = observed.membership_count
        self._preloss_library_ids = observed.membership_ids
        self._record_result(operation, True)

    def _step_pre_stop_guard(self, operation, spec) -> None:
        self._require(_valid_ref(self._parent_ref), "The parent refresh identity is unavailable.")
        observed = self._observe_detail(operation, self._parent_ref)
        if observed.state is None:
            self._record_blocked(operation, "parent_state_unavailable")
            raise _JobLifecycleStop("The pre-stop parent state is not proven.")
        if observed.state in TERMINAL_STATES:
            self._record_blocked(operation, "refresh_completed_before_stop")
            self._blocker = (
                "The refresh reached a terminal state before the controlled "
                "interruption; process-loss is BLOCKED and dependent retry "
                "obligations are NOT_RUN."
            )
            raise _JobLifecycleStop(self._blocker)
        if observed.state is not RecoveryState.ACTIVE:
            self._record_blocked(operation, "refresh_not_active_before_stop")
            raise _JobLifecycleStop("The refresh is not actively running before the stop.")
        process = self._observe_process(operation)
        if (
            process.process_state is not ProcessState.PRESENT
            or process.foreground_package != JOB_LIFECYCLE_QUALIFICATION_PACKAGE
        ):
            self._record_blocked(operation, "process_presence_unproven")
            raise _JobLifecycleStop("The qualification process is not proven in front.")
        self._record_result(operation, True)

    def _step_force_stop(self, operation, spec) -> None:
        self._verify_effect_target(
            operation,
            "force_stop_qualification_package",
            expected_process=ProcessState.PRESENT,
            require_foreground=True,
        )
        self._record_intent(operation)
        try:
            self._call(
                lambda timeout: self._transport.force_stop_package(
                    JOB_LIFECYCLE_QUALIFICATION_PACKAGE, timeout
                )
            )
        except _JobLifecycleStop:
            self._uncertain_effect(operation, "qualification process stop")
        self._record_result(operation, True)

    def _step_process_absent(self, operation, spec) -> None:
        observed = self._observe_process(operation)
        result = validate_process_observation(
            observed,
            expected_state=ProcessState.ABSENT,
            expected_package=JOB_LIFECYCLE_QUALIFICATION_PACKAGE,
        )
        if (
            result.outcome is evidence.AssertionOutcome.PASSED
            and observed.foreground_package != JOB_LIFECYCLE_QUALIFICATION_PACKAGE
        ):
            self._force_stop_observed = True
            self._record_result(operation, True)
            return
        self._record_blocked(operation, "process_loss_unproven")
        self._request_scope_extension(
            "qualification process stop verification",
            "The process stop was requested but absence or foreground loss is unproven.",
            "An owner-authorized observer establishes absence before relaunch or cleanup.",
        )
        raise _JobLifecycleStop(
            "The qualification process absence is unproven; no relaunch is permitted."
        )

    def _step_launch(self, operation, spec) -> None:
        self._verify_effect_target(
            operation,
            "launch_qualification_package",
            expected_process=ProcessState.ABSENT,
        )
        self._record_intent(operation)
        try:
            self._call(
                lambda timeout: self._transport.launch_package(
                    JOB_LIFECYCLE_QUALIFICATION_PACKAGE, timeout
                )
            )
        except _JobLifecycleStop:
            self._uncertain_effect(operation, "qualification relaunch")
        self._record_result(operation, True)

    def _step_foreground_launched(self, operation, spec) -> None:
        observed = self._observe_process(operation)
        if (
            observed.process_state is ProcessState.PRESENT
            and observed.foreground_package == JOB_LIFECYCLE_QUALIFICATION_PACKAGE
        ):
            self._record_result(operation, True)
            return
        self._record_blocked(operation, "foreground_launch_unproven")
        raise _JobLifecycleStop(
            "The relaunched qualification shell is not proven in the foreground."
        )

    def _step_jobs_recovered(self, operation, spec) -> None:
        observed = self._observe_jobs(operation)
        if not observed.established() or observed.parent_run_ref is None:
            self._record_blocked(operation, "recovered_parent_unavailable")
            raise _JobLifecycleStop("The recovered Jobs state is not proven.")
        if observed.parent_run_ref != self._parent_ref:
            self._record_result(operation, False)
            raise _JobLifecycleStop(
                "Recovery created a different or duplicate refresh attempt.",
                failed=True,
            )
        if observed.state is None:
            self._record_blocked(operation, "recovered_state_unavailable")
            raise _JobLifecycleStop("The recovered parent state is unavailable.")
        self._parent_state = observed.state
        self._record_result(operation, True)

    def _step_retry_eligibility(self, operation, spec) -> None:
        self._require(self._parent_state is not None, "The parent state is unavailable.")
        result = retry_eligibility(self._parent_state)
        if result.outcome is evidence.AssertionOutcome.NOT_RUN:
            self._record_oracle(operation, result)
        if result.outcome is not evidence.AssertionOutcome.PASSED:
            self._record_blocked(operation, result.code)
            raise _JobLifecycleStop(result.code)
        self._require(_valid_ref(self._parent_ref), "The source run identity is unavailable.")
        observed = self._observe_detail(operation, self._parent_ref)
        if observed.retry_control_count != 1:
            self._record_blocked(operation, "retry_control_unavailable")
            raise _JobLifecycleStop("A unique retry control is unavailable.")
        self._record_result(operation, True)

    def _step_retry(self, operation, spec) -> None:
        if not (
            self._root_persistence_verified
            and self._library_persistence_verified
        ):
            self._record_blocked(operation, "pre_retry_persistence_unverified")
            self._blocker = (
                "Both pre-Retry persistence checks must pass before Retry; "
                "no Retry effect was dispatched."
            )
            raise _JobLifecycleStop(self._blocker)
        self._require(_valid_ref(self._parent_ref), "The source run identity is unavailable.")
        self._require(self._parent_state is not None, "The source state is unavailable.")
        try:
            identity = self._call(
                lambda timeout: self._observer.observe_identity(
                    self._parent_ref, timeout
                )
            )
        except Exception:
            self._record_blocked(operation, "retry_pre_dispatch_identity_unavailable")
            self._blocker = (
                "The fresh Retry relationship lookup failed; owner recovery is required."
            )
            raise _JobLifecycleStop(self._blocker) from None
        precondition = validate_retry_precondition(
            identity,
            expected_parent_ref=self._parent_ref,
            expected_scope_ref=self._scope_ref,
            expected_state=self._parent_state,
            expected_child_refs=self._child_refs,
        )
        if precondition.outcome is not evidence.AssertionOutcome.PASSED:
            self._record_blocked(operation, precondition.code)
            raise _JobLifecycleStop(
                "The pre-Retry relationship proof is unavailable, ambiguous, or already "
                "contains a retry successor."
            )
        self._verify_effect_target(
            operation,
            "retry_library_refresh",
            expected_process=ProcessState.PRESENT,
            require_foreground=True,
        )
        self._record_intent(operation)
        self._retry_dispatched = True
        try:
            self._call(lambda timeout: self._transport.retry_refresh(timeout))
        except _JobLifecycleStop:
            self._uncertain_effect(operation, "explicit retry")
        self._record_result(operation, True)

    def _step_retry_outcome(self, operation, spec) -> None:
        self._require(
            not self._retry_observed,
            "A second retry would be required; that is not authorized.",
        )
        identity = self._call(
            lambda timeout: self._observer.observe_identity(self._parent_ref, timeout)
        )
        result = retry_outcome(
            source_state=self._parent_state,
            dispatched=self._retry_dispatched,
            already_retried=False,
        parent_ref=self._parent_ref,
        frozen_scope_ref=self._scope_ref,
            successor_identity=identity if type(identity) is JobIdentityObservation else None,
        )
        if result.outcome is evidence.AssertionOutcome.PASSED:
            assert isinstance(identity, JobIdentityObservation)
            self._successor_ref = identity.successor_run_ref
            self._record_result(operation, True)
            return
        if result.outcome is evidence.AssertionOutcome.NOT_RUN:
            self._record_oracle(operation, result)
        self._record_blocked(operation, result.code)
        raise _JobLifecycleStop(result.code)

    def _step_retry_relation(self, operation, spec) -> None:
        self._require(
            _valid_ref(self._successor_ref)
            and _valid_ref(self._parent_ref)
            and _valid_ref(self._scope_ref),
            "The retry successor, source, or scope identity is unavailable.",
        )
        self._require(
            self._successor_ref != self._parent_ref,
            "The retry successor reuses the source identity.",
        )
        identity = self._call(
            lambda timeout: self._observer.observe_identity(self._parent_ref, timeout)
        )
        if (
            type(identity) is not JobIdentityObservation
            or identity.parent_run_ref != self._parent_ref
            or identity.source_run_ref != self._parent_ref
            or identity.frozen_scope_ref != self._scope_ref
            or identity.successor_scope_ref != self._scope_ref
            or identity.successor_run_ref != self._successor_ref
        ):
            self._record_blocked(operation, "retry_successor_scope_mismatch")
            raise _JobLifecycleStop(
                "The retry successor identity is not bound to the observed source and scope."
            )
        observed = self._observe_detail(operation, self._successor_ref)
        if (
            observed.parent_run_ref != self._successor_ref
            or observed.retry_source_run_ref != self._parent_ref
        ):
            self._record_result(operation, False)
            raise _JobLifecycleStop(
                "The retry detail does not link the same source and successor identity.",
                failed=True,
            )
        self._retry_observed = True
        self._record_result(operation, True)

    def _step_library_persisted(self, operation, spec) -> None:
        observed = self._observe_library_value(operation)
        result = library_post_retry_integrity(
            self._recovered_library_ids,
            observed,
        )
        if result.outcome is evidence.AssertionOutcome.PASSED:
            self._library_count = observed.membership_count
            self._record_result(operation, True)
            self._append_assertion(
                self._step_key(operation) + ":post-retry-integrity",
                evidence.AssertionOutcome.PASSED,
            )
            return
        if result.outcome is evidence.AssertionOutcome.FAILED:
            self._record_result(operation, False)
            self._append_assertion(
                self._step_key(operation) + ":post-retry-integrity",
                evidence.AssertionOutcome.FAILED,
            )
            self._request_scope_extension(
                "post-Retry Library integrity",
                "A committed Library asset present before Retry disappeared after Retry.",
                "The owner assesses the Retry mutation; no second Retry is permitted.",
            )
            self._blocker = (
                "A committed Library asset disappeared after Retry; no second Retry is permitted."
            )
            raise _JobLifecycleStop(result.code, failed=True)
        self._record_blocked(operation, result.code)
        self._append_assertion(
            self._step_key(operation) + ":post-retry-integrity",
            evidence.AssertionOutcome.BLOCKED,
        )
        self._request_scope_extension(
            "post-Retry Library identity",
            "The exact committed Library identities are missing or ambiguous after Retry.",
            "An owner-authorized observer establishes the post-Retry Library state before cleanup.",
        )
        self._blocker = (
            "The post-Retry Library identities are BLOCKED; no second Retry is permitted."
        )
        raise _JobLifecycleStop(self._blocker)

    def _step_scan_root_state_post_retry(self, operation, spec) -> None:
        self._require(_valid_ref(self._scan_root_ref), "The Sources root is unavailable.")
        self._require(
            _valid_ref(self._successor_ref),
            "The verified retry successor identity is unavailable.",
        )
        observed = self._call(
            lambda timeout: self._transport.observe_scan_root(
                self._scan_root_ref, timeout
            )
        )
        result = validate_scan_root_post_retry(
            observed,
            expected_root_ref=self._scan_root_ref,
            expected_successor_run_ref=self._successor_ref,
        )
        if result.outcome is evidence.AssertionOutcome.PASSED:
            historical = (
                type(observed) is ScanRootObservation
                and observed.historical_last_scan_identified()
            )
            if historical:
                self._root_last_scan_ref = observed.view_job_run_ref
            self._record_result(operation, True)
            self._append_assertion(
                self._step_key(operation) + ":root-post-retry-integrity",
                evidence.AssertionOutcome.PASSED,
            )
            if not historical:
                self._append_assertion(
                    self._step_key(operation) + ":root-post-retry-active-scan",
                    evidence.AssertionOutcome.PASSED,
                )
            return
        if result.outcome is evidence.AssertionOutcome.FAILED:
            self._record_result(operation, False)
            raise _JobLifecycleStop(result.code, failed=True)
        self._record_blocked(operation, result.code)
        self._append_assertion(
            self._step_key(operation) + ":root-post-retry-integrity",
            evidence.AssertionOutcome.BLOCKED,
        )
        self._request_scope_extension(
            "post-Retry Sources root integrity",
            "The post-Retry root presentation, successor ownership, or last-scan "
            "state is not independently established.",
            "An owner-authorized observer establishes post-Retry Sources root "
            "ownership before cleanup.",
        )
        self._blocker = (
            "The post-Retry Sources root state is BLOCKED; no second Retry is permitted."
        )
        raise _JobLifecycleStop(self._blocker)

    def _step_scan_root_state(self, operation, spec) -> None:
        self._require(_valid_ref(self._scan_root_ref), "The Sources root is unavailable.")
        observed = self._call(
            lambda timeout: self._transport.observe_scan_root(
                self._scan_root_ref, timeout
            )
        )
        if (
            type(observed) is not ScanRootObservation
            or not observed.established()
            or observed.root_ref != self._scan_root_ref
            or not observed.historical_last_scan_identified()
            or observed.last_scan_state not in ROOT_HISTORICAL_SCAN_STATES
        ):
            self._record_blocked(operation, "scan_root_state_unavailable")
            raise _JobLifecycleStop("The Sources root last-scan state is not proven.")
        self._root_last_scan_ref = observed.view_job_run_ref
        self._record_result(operation, True)

    def _step_scan_job_lifecycle(self, operation, spec) -> None:
        observed = self._call(
            lambda timeout: self._transport.observe_scan_job(
                self._root_last_scan_ref, timeout
            )
        )
        if type(observed) is not ScanJobObservation or not observed.established():
            self._record_blocked(operation, "scan_job_state_unavailable")
            raise _JobLifecycleStop("The Library Scan job state is not proven.")
        if (
            self._root_last_scan_ref is not None
            and observed.run_ref != self._root_last_scan_ref
        ):
            self._record_result(operation, False)
            raise _JobLifecycleStop(
                "The Scan detail names a different run than the root View Job control.",
                failed=True,
            )
        self._scan_job_ref = observed.run_ref
        self._append_assertion(
            self._step_key(operation) + ":result",
            evidence.AssertionOutcome.PASSED,
        )
        self._append_assertion(
            self._step_key(operation) + ":refresh-child-attribution",
            evidence.AssertionOutcome.BLOCKED,
        )
        self._request_scope_extension(
            "refresh child attribution from Sources",
            "The Sources root View Job control references the root's last scan, "
            "which is not independently linked to the tested LibraryRefresh.",
            "An owner-authorized observer links the exact refresh run to a child scan run.",
        )

    def _step_restore_foreground(self, operation, spec) -> None:
        self._require(_valid_ref(self._task_ref), "The qualification task identity is unavailable.")
        self._verify_effect_target(
            operation,
            "restore_qualification_foreground",
            expected_process=ProcessState.PRESENT,
            require_foreground=True,
        )
        self._record_intent(operation)
        try:
            self._call(
                lambda timeout: self._transport.restore_foreground(
                    JOB_LIFECYCLE_QUALIFICATION_PACKAGE,
                    self._task_ref,
                    timeout,
                )
            )
        except _JobLifecycleStop:
            self._uncertain_effect(operation, "restoration foreground return")
        observed = self._observe_process(operation)
        if (
            observed.process_state is ProcessState.PRESENT
            and observed.foreground_package == JOB_LIFECYCLE_QUALIFICATION_PACKAGE
            and observed.task_continuity_ref == self._task_ref
        ):
            self._record_result(operation, True)
            return
        self._record_blocked(operation, "restoration_foreground_unproven")
        raise _JobLifecycleStop(
            "Foreground restoration is unproven; owner recovery remains required."
        )

    def _step_successor_terminal(self, operation, spec) -> None:
        self._require(_valid_ref(self._successor_ref), "The retry successor identity is unavailable.")
        deadline = (
            None
            if self._operation_monotonic_deadline is None
            else self._operation_monotonic_deadline
        )
        saw_active = False
        saw_unavailable = False
        while True:
            if deadline is not None and self._monotonic() >= deadline:
                break
            observed = self._observe_detail(operation, self._successor_ref)
            if observed.state in ACTIVE_STATES:
                saw_active = True
            elif observed.state not in TERMINAL_STATES:
                saw_unavailable = True
            terminal = (
                observed.parent_run_ref == self._successor_ref
                and observed.state in TERMINAL_STATES
            )
            if terminal:
                if deadline is not None and self._monotonic() >= deadline:
                    break
                process = self._observe_process(operation)
                if (
                    process.process_state is not ProcessState.PRESENT
                    or process.foreground_package
                    != JOB_LIFECYCLE_QUALIFICATION_PACKAGE
                ):
                    self._record_blocked(operation, "successor_foreground_unproven")
                    raise _JobLifecycleStop(
                        "The successor terminal state was observed without the "
                        "expected qualification foreground."
                    )
                self._budget()
                terminal_result = terminal_successor(observed)
                if terminal_result.outcome is not evidence.AssertionOutcome.PASSED:
                    self._record_blocked(operation, terminal_result.code)
                    raise _JobLifecycleStop(
                        "The retry successor terminal observation is unavailable."
                    )
                self._successor_state = observed.state
                self._append_assertion(
                    self._step_key(operation) + ":terminal",
                    evidence.AssertionOutcome.PASSED,
                )
                acceptance = retry_success_acceptance(observed.state)
                if acceptance.outcome is evidence.AssertionOutcome.PASSED:
                    self._record_result(operation, True)
                    return
                if acceptance.outcome is evidence.AssertionOutcome.FAILED:
                    self._record_result(operation, False)
                    raise _JobLifecycleStop(
                        "The retry successor reached a terminal state that "
                        "disproves Retry success.",
                        failed=True,
                    )
                self._record_blocked(operation, acceptance.code)
                raise _JobLifecycleStop(
                    "The retry successor reached a terminal state, but Retry "
                    "success remains undecided without a pinned acceptance "
                    "criterion; recovery remains with the owner."
                )
            if observed.parent_run_ref != self._successor_ref:
                self._record_result(operation, False)
                raise _JobLifecycleStop(
                    "The successor detail identity changed during terminal observation.",
                    failed=True,
                )
            if deadline is None or self._monotonic() >= deadline:
                break
            self._sleeper(1.0)
        if saw_unavailable and not saw_active:
            self._record_blocked(operation, "successor_terminal_unavailable")
            raise _JobLifecycleStop(
                "The retry successor terminal state was unavailable at its "
                "bounded deadline; the outcome is BLOCKED and recovery remains "
                "with the owner."
            )
        self._record_blocked(operation, "successor_still_active")
        raise _JobLifecycleStop(
            "The retry successor remained active at its bounded deadline; "
            "the outcome is BLOCKED and recovery remains with the owner."
        )

    # -- finalization ------------------------------------------------------

    def _append_skipped_not_run(self) -> bool:
        """Record every frozen-plan operation that never dispatched an effect."""
        if self._workflow_completed:
            return True
        start = (
            self._attempted_index + 1
            if self._attempted_index is not None
            else self._completed_operations
        )
        try:
            for operation in self._planned_operations[start:]:
                self._append_assertion(
                    operation.operation_id + ":not-run",
                    evidence.AssertionOutcome.NOT_RUN,
                )
        except Exception:
            self._blocker = self._blocker or (
                "Skipped lifecycle operations could not be durably recorded; "
                "owner recovery is required."
            )
            return False
        return True

    def _append_final_assertions(self) -> bool:
        if not self._append_skipped_not_run():
            return False
        try:
            self._append_assertion(
                "scenario-outcome",
                evidence.AssertionOutcome.BLOCKED,
            )
            self._append_assertion(
                "independent-physical-qualification",
                evidence.AssertionOutcome.BLOCKED,
            )
            latency = latency_execution_status()
            self._append_assertion(
                "latency-execution",
                latency.outcome,
            )
            if self._scenario_id == JOB_LIFECYCLE_SCENARIO_AND_05:
                self._append_assertion(
                    "owner-recovery-obligation",
                    evidence.AssertionOutcome.BLOCKED
                    if (
                        self._blocker
                        or self._successor_ref is not None
                        and self._successor_state is None
                    )
                    else evidence.AssertionOutcome.NOT_RUN,
                )
        except Exception:
            self._blocker = (
                self._blocker
                or "Mandatory lifecycle assertions could not be durably appended; "
                "owner recovery is required."
            )
            return False
        return True

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
                self._blocker = (
                    "The terminal evidence receipt did not match the approved session."
                )
        except Exception:
            self._blocker = (
                self._blocker
                or "Append-only terminal evidence could not be finalized; "
                "owner recovery is required."
            )

    def _result(self, blocker: str) -> JobLifecycleExecutionResult:
        latency = latency_execution_status()
        return JobLifecycleExecutionResult(
            scenario_id=self._scenario_id,
            status=(
                "failed"
                if self._assertion_failed
                else "interrupted"
                if self._interrupted
                else "blocked"
            ),
            workflow_completed=self._workflow_completed,
            completed_operations=self._completed_operations,
            total_operations=len(JOB_LIFECYCLE_OPERATIONS.get(self._scenario_id, ())),
            recovery_state=self._parent_state,
            latency_status=latency.code,
            blocker=blocker,
            scope_extensions=tuple(self._scope_extensions),
            execution_manifest_sha256=self._execution_manifest_sha256,
        )


def _execute_job_lifecycle_session(
    executor: _JobLifecycleOperationExecutor,
    *,
    now: datetime | None = None,
) -> JobLifecycleExecutionResult:
    """Run one exact admitted lifecycle plan through the shared fail-closed shell."""
    instant = now or datetime.now(timezone.utc)
    executor._base_time = instant
    if not _now_is_utc(instant):
        return executor._result("Execution time must be UTC.")
    if not executor._session.reserve_operation():
        return executor._result("Another operation is in progress for this session.")
    executor._completed_operations = 0
    executor._workflow_completed = False
    executor._blocker = ""
    executor._assertion_failed = False
    operations: tuple[OperationAuthorization, ...] = ()
    claimed = False
    try:
        if not _admission._claim_job_lifecycle_execution(executor._session):
            executor._blocker = (
                "The admitted private lifecycle capability is unavailable or already used."
            )
            return executor._result(executor._blocker)
        claimed = True
        executor._started = executor._monotonic()
        try:
            executor._validate_inputs()
            operations = executor._plan_operations()
            executor._planned_operations = operations
            executor._writer.open_session(
                executor._spec,
                executor._request("session-open"),
            )
            executor._evidence_open = True
            executor._append_lifecycle(
                evidence.Lifecycle.PREPARATION_STARTED,
                "preparation-started",
            )
            executor._append_lifecycle(
                evidence.Lifecycle.EXECUTION_STARTED,
                "execution-started",
            )
            executor._dispatch_all(operations)
        except KeyboardInterrupt:
            executor._interrupted = True
            executor._blocker = (
                "Execution was interrupted; no product mutation was retried."
            )
        except _JobLifecycleStop as stop:
            if stop.failed:
                executor._assertion_failed = True
            executor._blocker = executor._blocker or stop.reason
        except Exception:
            executor._blocker = executor._blocker or (
                "Evidence persistence or an internal lifecycle assertion failed; "
                "owner recovery is required."
            )
        finally:
            if executor._evidence_open:
                executor._append_final_assertions()
                executor._finalize(
                    reason=(
                        evidence.TerminalReason.OPERATOR_TERMINATED
                        if executor._interrupted
                        else evidence.TerminalReason.ASSERTION_FAILED
                        if executor._assertion_failed
                        else evidence.TerminalReason.PREREQUISITE_BLOCKED
                        )
                    )
    finally:
        if claimed and _admitted_session_binding(executor._session) is not None:
            _finish_admitted_session(executor._session, blocked=True)
        executor._session.release_operation()
    executor._blocker = executor._blocker or (
        "Host simulation cannot establish physical Android job lifecycle qualification."
    )
    return executor._result(executor._blocker)
