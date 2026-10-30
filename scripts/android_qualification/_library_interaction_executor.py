"""Private Issue #27 executor for the closed Library interaction plan.

The module is loaded lazily by the shared internal lifecycle after the exact
executor type is checked. Importing the legacy admission module does not load
this Issue #27 executor or its oracle and UI observation code.
"""

from __future__ import annotations

import time
from typing import TYPE_CHECKING

from . import admission as _admission
from . import evidence
from ._library_interaction_contract import LIBRARY_INTERACTION_CASE_IDS
from .manifest import OperationAuthorization, OperationCategory, QUALIFICATION_PACKAGE

_AddScanOperationPrimitives = _admission._AddScanOperationPrimitives
_AddScanStop = _admission._AddScanStop
_AddScanTransport = _admission._AddScanTransport
AdmittedSession = _admission.AdmittedSession
AddScanExecutionResult = _admission.AddScanExecutionResult
FixtureTransferPlan = _admission.FixtureTransferPlan
_library_interaction_admission_binding = _admission._library_interaction_admission_binding
_library_interaction_plan = _admission._library_interaction_plan
_validate_executor_session_inputs = _admission._validate_executor_session_inputs

if TYPE_CHECKING:
    from ._library_interaction_oracle import LibraryInteractionOracle


class _LibraryInteractionOperationExecutor(_AddScanOperationPrimitives):
    """Run the closed Issue #27 plan around private Add & Scan primitives.

    This executor owns Issue #27 admission claims, oracle validation, operation
    ordering, and per-case evidence. It shares only plan-free operation
    primitives with the closed Issue #26 executor. It never invokes that
    executor's workflow or exposes Library actions through its legacy selector.

    The pinned Release accessibility surface cannot prove completed Library
    traversal or backend pagination. Membership is therefore BLOCKED,
    dependent interaction cases are NOT_RUN, and the existing cleanup-last path
    runs once only after scan terminalization makes it safe.
    """

    _LIBRARY_ACTIONS = frozenset({
        "library_search_exact", "library_search_partial", "library_search_empty",
        "library_search_clear", "library_filter_platform", "library_filter_region",
        "library_filter_hydration", "library_filter_availability", "library_filter_reset",
        "library_select_game", "library_sort_title", "library_sort_ascending",
        "library_sort_descending", "library_sort_platform", "library_view_list",
        "library_view_grid", "library_search_after_selection",
        "library_open_game_detail", "library_return_to_library",
    })

    def __init__(
        self,
        *,
        session: AdmittedSession,
        transport: _AddScanTransport,
        writer: evidence.ExecutionWriter,
        evidence_spec: evidence.SessionSpec,
        fixture_plan: FixtureTransferPlan,
        oracle: LibraryInteractionOracle,
        monotonic=time.monotonic,
        sleeper=time.sleep,
    ) -> None:
        from . import _library_interaction_oracle

        expectations = (
            oracle.fixture_expectations
            if type(oracle) is _library_interaction_oracle.LibraryInteractionOracle
            else ()
        )
        super().__init__(
            session=session,
            transport=transport,
            writer=writer,
            evidence_spec=evidence_spec,
            fixture_plan=fixture_plan,
            library_expectations=expectations,
            monotonic=monotonic,
            sleeper=sleeper,
        )
        self._oracle = oracle
        self._library_membership_attempted = False
        self._library_membership_result_recorded = False
        self._interaction_case_append_failed = False
        self._interaction_case_outcomes_complete = False

    def _validate_inputs(self) -> None:
        from . import _library_interaction_oracle

        binding = _library_interaction_admission_binding(self._session)
        self._first_binding = binding
        self._evidence_refs = _validate_executor_session_inputs(
            session=self._session,
            evidence_spec=self._spec,
            fixture_plan=self._fixture_plan,
            expectations=self._expectations,
            binding=binding,
            session_namespace="argus-library-interactions",
            instant=self._logical_now(),
        )
        if (
            binding is None
            or not _library_interaction_oracle.validate_oracle(
                self._oracle,
                self._session.authorization,
                self._spec,
                binding.oracle_sha256,
            )
        ):
            raise _AddScanStop(
                "The private Library oracle does not match the approved session pins."
            )

    def _plan_operations(self) -> tuple[OperationAuthorization, ...]:
        operations = _library_interaction_plan(self._session.authorization)
        if operations is None or operations != self._session.authorization.operations:
            raise _AddScanStop(
                "The approved operation plan is not the closed Issue #27 sequence."
            )
        return operations

    def _interaction_case_key(self, index: int) -> str:
        return f"library-interaction-case-{index:02d}"

    def _capture_issue27_library_nodes(self, operation: OperationAuthorization):
        from .physical import _library_interaction_ui as library_ui
        from .physical import ui

        try:
            return library_ui.parse_issue27_library_ui(
                self._capture_accessibility_xml(operation),
                expected_package=QUALIFICATION_PACKAGE,
                library_expectations=self._expectations,
            )
        except ui.UIFailed:
            raise
        except Exception:
            self._record_blocked(operation.operation_id + ":ui-surface")
            raise _AddScanStop(
                "The qualification UI surface is ambiguous or lacks approved semantics."
            ) from None

    def _record_interaction_case(
        self,
        index: int,
        outcome: evidence.AssertionOutcome,
    ) -> None:
        try:
            self._append_assertion(
                self._interaction_case_key(index) + ":result",
                outcome,
            )
        except KeyboardInterrupt:
            self._interaction_case_append_failed = True
            self._interrupted = True
            raise
        except Exception:
            self._interaction_case_append_failed = True
            raise

    def _record_interaction_cases_before_cleanup(self) -> None:
        if self._interaction_case_append_failed:
            raise _AddScanStop(
                "A required Issue #27 case outcome could not be durably appended."
            )
        case_count = len(LIBRARY_INTERACTION_CASE_IDS)
        for index in range(case_count):
            if index == 0 and self._library_membership_result_recorded:
                continue
            outcome = (
                evidence.AssertionOutcome.BLOCKED
                if index == 0 and self._library_membership_attempted
                else evidence.AssertionOutcome.NOT_RUN
            )
            self._record_interaction_case(index, outcome)
            if index == 0 and self._library_membership_attempted:
                self._library_membership_result_recorded = True
        self._interaction_case_outcomes_complete = True

    def _withhold_cleanup_for_incomplete_case_evidence(self) -> None:
        if not self._staged:
            return
        self._cleanup_status = "blocked"
        cleanup_blocker = (
            "Fixture cleanup was withheld because not all Issue #27 case outcomes were durably recorded."
        )
        self._blocker = (
            f"{cleanup_blocker} {self._blocker}" if self._blocker else cleanup_blocker
        )
        self._request_scope_extension(
            "fixture cleanup withheld after incomplete interaction evidence",
            "The session could not append all required Issue #27 case outcomes before cleanup.",
            "An owner-authorized recovery verifies the session identity and resolves only its session-owned fixture set.",
        )

    def _run_navigation(self, operation: OperationAuthorization) -> None:
        action = dict(operation.arguments).get("action")
        if action == "library_navigation" and (
            not self._terminal_scan_observed
            or self._terminal_scan != "complete"
        ):
            raise _AddScanStop(
                "The Library route requires a positively observed complete terminal scan."
            )
        if action in self._LIBRARY_ACTIONS:
            raise _AddScanStop(
                "Dependent Library actions remain unattempted without complete membership proof."
            )
        super()._run_navigation(operation)

    def _run_read_only(self, operation: OperationAuthorization) -> None:
        observation = dict(operation.arguments).get("observation")
        if observation in {"scan_admission", "job_status", "terminal_scan"}:
            super()._run_read_only(operation)
            return
        if observation != "library_complete_membership":
            raise _AddScanStop(
                "Dependent Library observations remain unattempted without complete membership proof."
            )

        from .physical import _library_interaction_ui as library_ui
        from .physical import ui

        self._library_membership_attempted = True
        case_key = self._interaction_case_key(0)
        self._record_intent(case_key)
        try:
            if not self._terminal_scan_observed or self._terminal_scan != "complete":
                raise ui.UIBlocked(
                    "Library membership observation requires a terminal successful scan."
                )
            self._verify_target_foreground(operation, QUALIFICATION_PACKAGE)
            self._observe_package(operation)
            nodes = self._capture_issue27_library_nodes(operation)
            visible = library_ui.observe_issue27_fixture_library_results(
                nodes,
                self._expectations,
            )
            library_ui.require_verified_fixture_library_exhaustion(
                nodes,
                self._expectations,
                snapshots=(visible.fixture_ordinals,),
            )
        except ui.UIFailed:
            self._blocker = self._blocker or (
                "The qualification UI explicitly reported a Library product failure."
            )
            self._assertion_failed = True
            self._record_interaction_case(0, evidence.AssertionOutcome.FAILED)
            self._library_membership_result_recorded = True
            raise _AddScanStop(self._blocker) from None
        except Exception:
            self._blocker = self._blocker or (
                "The pinned Release accessibility contract cannot prove complete Library membership and pagination."
            )
            self._record_interaction_case(0, evidence.AssertionOutcome.BLOCKED)
            self._library_membership_result_recorded = True
            raise _AddScanStop(self._blocker) from None
        self._blocker = self._blocker or (
            "The pinned Release accessibility contract cannot prove complete Library membership and pagination."
        )
        self._record_interaction_case(0, evidence.AssertionOutcome.BLOCKED)
        self._library_membership_result_recorded = True
        raise _AddScanStop(self._blocker)

    def execute(self, *, now: datetime | None = None) -> AddScanExecutionResult:
        return _admission._execute_closed_admitted_session(self, now=now)


def _dispatch_library_interaction_operation(
    executor: _LibraryInteractionOperationExecutor,
    operation: OperationAuthorization,
) -> None:
    """Dispatch only operations accepted by the distinct Issue #27 validator."""
    action = dict(operation.arguments).get("action")
    if operation.category in {
        OperationCategory.INSTALL_ABSENT,
        OperationCategory.RESET_DATA,
    }:
        executor._run_setup(operation)
    elif action == "stage_approved_fixture_set":
        executor._run_stage(operation)
        executor._append_lifecycle(
            evidence.Lifecycle.PREPARATION_COMPLETED,
            "preparation-completed",
        )
        executor._append_lifecycle(
            evidence.Lifecycle.EXECUTION_STARTED,
            "execution-started",
        )
    elif operation.category is OperationCategory.LAUNCH:
        executor._run_launch(operation)
    elif operation.category is OperationCategory.NAVIGATION:
        executor._run_navigation(operation)
    elif operation.category is OperationCategory.READ_ONLY:
        executor._run_read_only(operation)
    elif action == "remove_session_owned_fixture_set":
        raise _AddScanStop(
            "The Issue #27 cleanup operation is handled only after all case outcomes are recorded."
        )
    else:
        raise _AddScanStop("The plan contains an unsupported operation category.")


def _finalize_library_interaction_execution(
    executor: _LibraryInteractionOperationExecutor,
    operations: tuple[OperationAuthorization, ...],
) -> None:
    """Append all Issue #27 case outcomes before its one cleanup attempt."""
    executor._request_scan_recovery_if_unresolved()
    try:
        executor._record_interaction_cases_before_cleanup()
    except KeyboardInterrupt:
        executor._interrupted = True
        executor._interaction_case_append_failed = True
        executor._blocker = executor._blocker or (
            "Execution was interrupted while recording required Issue #27 case outcomes."
        )
    except Exception:
        executor._blocker = executor._blocker or (
            "A dependent assertion could not be durably recorded."
        )
    if executor._interaction_case_outcomes_complete:
        executor._attempt_owned_cleanup(operations)
    else:
        executor._withhold_cleanup_for_incomplete_case_evidence()
