"""Issue #28 host-only lifecycle contract, admission, oracle, and executor tests."""

from __future__ import annotations

from dataclasses import replace
from datetime import datetime, timedelta, timezone
import hashlib
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

from scripts.android_qualification import _job_lifecycle_contract as contract
from scripts.android_qualification import _job_lifecycle_executor as lifecycle_executor
from scripts.android_qualification import _job_lifecycle_oracle as oracle
from scripts.android_qualification import admission, evidence, manifest
from scripts.android_qualification.manifest import (
    OperationCategory,
    QUALIFICATION_PACKAGE,
    SessionStateMode,
)
from scripts.android_qualification.test_manifest import (
    MANAGE_EXTERNAL_STORAGE,
    NOW,
    approval_document,
    authorization_document,
    write_private_json,
)

_SERIAL = "private-serial-synthetic"
_APK_SHA256 = "a" * 64
_CERTIFICATE_SHA256 = "b" * 64
_REVISION = "c" * 40
_RULES_SHA256 = "e" * 64
_FIXTURE_SHA256 = "f" * 64
_CAPABILITIES = frozenset({
    "foreground_package_observation",
    "installed_signer_observation",
    "permission_app_op_observation",
    "permission_app_op_mutation",
    "storage_reserve_observation",
})
_EVIDENCE_REF = "evidence-" + "1" * 32


def alias(kind: str, value: str) -> str:
    return f"{kind}-{hashlib.sha256(f'{kind}:{value}'.encode()).hexdigest()[:32]}"


def _baseline(**overrides) -> contract.JobLifecycleBaselineObservation:
    values = dict(
        connected_serials=(_SERIAL,),
        android_api_level=35,
        abi="arm64-v8a",
        capabilities=_CAPABILITIES,
        package_name=QUALIFICATION_PACKAGE,
        version_code=123,
        certificate_sha256=_CERTIFICATE_SHA256,
        artifact_sha256=_APK_SHA256,
        foreground_package=QUALIFICATION_PACKAGE,
        interference_free=True,
        available_storage_bytes=2_000_000_000,
        library_membership_count=1,
        selected_root_ref="root-ref-synthetic",
        last_scan_state="complete",
        visible_refresh_row_count=0,
        active_refresh_row_count=0,
        pending_cleanup_refs=(),
        pending_restoration_refs=(),
        refresh_control_present=True,
        jobs_navigation_present=True,
        task_continuity_ref="task-ref-synthetic",
        observer_ref="observer-ref-synthetic",
        observer_receipt_sha256="2" * 64,
        library_membership_ids=("fixture-synthetic",),
        selected_root_id="root-private-synthetic",
        job_states=(),
        jobs_history_complete=True,
        terminal_refresh_run_refs=(),
    )
    values.update(overrides)
    return contract.JobLifecycleBaselineObservation(**values)


def _artifact() -> admission.HostArtifactFacts:
    return admission.HostArtifactFacts(
        apk_sha256=_APK_SHA256,
        package_name=QUALIFICATION_PACKAGE,
        version_code=123,
        signature_verified=True,
        signer_count=1,
        certificate_sha256=_CERTIFICATE_SHA256,
        source_revision=_REVISION,
        declared_permissions=frozenset({MANAGE_EXTERNAL_STORAGE}),
        source_dirty=False,
    )


def _authorization_document(
    scenario_id: str = contract.JOB_LIFECYCLE_SCENARIO_AND_04,
    *,
    session_seconds: int | None = None,
    job_states=None,
) -> dict:
    document = authorization_document()
    document["state"] = {
        "mode": "no-reset",
        "inherited_state_session_id": "session-inherited-synthetic",
        "no_reset_baseline": {
            "library_fixture_ids": ["fixture-synthetic"],
            "job_states": [
                {"job_id": job_id, "state": state}
                for job_id, state in (job_states or ())
            ],
            "pending_cleanup_ids": [],
            "root_id": "root-private-synthetic",
            "pending_restoration_ids": [],
        },
    }
    document["plan"]["scenario_ids"] = [scenario_id]
    session_seconds = (
        contract.JOB_LIFECYCLE_SESSION_SECONDS[scenario_id]
        if session_seconds is None
        else session_seconds
    )
    issued_at = datetime.strptime(
        document["issued_at_utc"], "%Y-%m-%dT%H:%M:%SZ"
    ).replace(tzinfo=timezone.utc)
    document["session_deadline_utc"] = (
        issued_at + timedelta(seconds=session_seconds)
    ).strftime("%Y-%m-%dT%H:%M:%SZ")
    document["cleanup_deadline_utc"] = (
        issued_at + timedelta(seconds=session_seconds + contract.JOB_LIFECYCLE_CLOSURE_SECONDS)
    ).strftime("%Y-%m-%dT%H:%M:%SZ")
    document["reserves"]["cleanup_seconds"] = contract.JOB_LIFECYCLE_CLOSURE_SECONDS
    document["approved_remediation"] = []
    document["operations"] = [
        {
            "operation_id": f"{scenario_id.lower()}-{spec.index:02d}",
            "category": spec.category,
            "phase": "qualification",
            "target_serial": _SERIAL,
            "package_name": QUALIFICATION_PACKAGE,
            "timeout_seconds": spec.timeout_seconds,
            "permission_name": None,
            "expected_prior_state": None,
            "desired_state": None,
            "restoration": None,
            "arguments": contract.operation_arguments(spec),
        }
        for spec in contract.JOB_LIFECYCLE_OPERATIONS[scenario_id]
    ]
    return document


def _load_lifecycle_authorization(directory: Path, document: dict):
    """Load once, pin the independently computed plan digest, then reload."""
    provisional = manifest._load_authorization_for_profile(
        write_private_json(directory, "authorization-draft.json", document),
        manifest._AuthorizationProfile.JOB_LIFECYCLE,
    )
    digest = contract.plan_digest_for_authorization(provisional)
    assert digest is not None
    document["plan"]["plan_sha256"] = digest
    return manifest._load_job_lifecycle_authorization(
        write_private_json(directory, "authorization.json", document)
    )


def _load_approval(directory: Path, authorization, *, valid_until=None):
    document = approval_document(authorization.canonical_sha256)
    document["valid_from_utc"] = authorization.issued_at.strftime("%Y-%m-%dT%H:%M:%SZ")
    limit = authorization.session_deadline if valid_until is None else valid_until
    document["valid_until_utc"] = limit.strftime("%Y-%m-%dT%H:%M:%SZ")
    return manifest.load_owner_approval(
        write_private_json(directory, "approval.json", document),
        authorization,
        now=NOW,
    )


def session_spec(authorization) -> evidence.SessionSpec:
    return evidence.SessionSpec(
        session_id=alias(
            "session",
            f"argus-job-lifecycle:{authorization.authorization_id}:"
            f"{authorization.canonical_sha256}",
        ),
        scenario_id=alias("scenario", authorization.scenario_ids[0]),
        artifact=evidence.ArtifactPin(
            alias("artifact", authorization.apk_sha256),
            authorization.apk_sha256,
            evidence.ArtifactClass.QUALIFICATION_VARIANT,
        ),
        authorization=evidence.AuthorizationPin(1, authorization.canonical_sha256),
        fixtures=evidence.FixturePin(
            1,
            authorization.fixture_manifest_sha256,
            alias("corpus", authorization.fixture_manifest_sha256),
        ),
        plan=evidence.PlanPin(
            alias("plan", authorization.plan_sha256), 1, authorization.plan_sha256
        ),
        rules=evidence.AcceptanceRulesPin(
            alias("rules", authorization.rules_sha256), "1.0.0", authorization.rules_sha256
        ),
        environment=evidence.EnvironmentPin(
            evidence.Platform.ANDROID,
            alias("platform-version", "api-35"),
            alias("environment", "synthetic-api-35"),
            alias("target", authorization.target_ref),
        ),
        review_requirements=evidence.ReviewRequirements(
            required_evidence_refs=(_EVIDENCE_REF,),
            objective_review_allowed=True,
            direct_owner_observation_allowed=True,
            retrospective_allowed=False,
        ),
    )


class FakeBaselineTransport:
    def __init__(self, baseline=None):
        self.baseline = baseline or _baseline()
        self.calls = 0

    def observe_baseline(self, timeout):
        self.calls += 1
        return self.baseline


class _Clock:
    def __init__(self, values=None, step=1.0):
        self.value = 0.0
        self.step = step
        self.values = list(values or [])

    def monotonic(self):
        if self.values:
            self.value = self.values.pop(0)
        return self.value

    def sleep(self, seconds):
        self.value += self.step


_UNSET = object()


def _library(
    membership=1,
    active=False,
    surface=contract.JobLifecycleSurface.LIBRARY,
    membership_ids=_UNSET,
    next_page_available=False,
    identity_continuity=None,
):
    if membership_ids is _UNSET:
        membership_ids = (
            (
                ("fixture-synthetic",)
                if membership == 1
                else tuple(
                    f"fixture-synthetic-{index}" for index in range(membership)
                )
            )
            if type(membership) is int
            else None
        )
    return contract.LibrarySurfaceObservation(
        surface=surface,
        membership_count=membership,
        refresh_control_present=True,
        refresh_active=active,
        observer_ref="library-observer",
        membership_ids=membership_ids,
        next_page_available=next_page_available,
        identity_continuity=identity_continuity,
    )


def _jobs(parent=None, state=None, rows=0, active=0, *, history_complete=True):
    terminal_refs = tuple(
        f"terminal-ref-{index}" for index in range(max(0, rows - active))
    )
    return contract.JobsSurfaceObservation(
        surface=contract.JobLifecycleSurface.JOBS,
        parent_run_ref=parent,
        state=state,
        refresh_row_count=rows,
        active_refresh_row_count=active,
        jobs_navigation_present=True,
        observer_ref="jobs-observer",
        history_complete=history_complete,
        terminal_refresh_run_refs=terminal_refs,
    )


def _progress(completed, total=3, phase="scan", parent="parent-run"):
    return contract.RefreshProgressFacts(
        phase=phase,
        completed_units=completed,
        total_units=total,
        status_key="library_refresh.scanning",
        issue_count=0,
        parent_run_ref=parent,
    )


def _detail(parent, state, *, progress=None, retry=0, source=None, successor=None):
    return contract.RefreshDetailObservation(
        parent_run_ref=parent,
        state=state,
        progress=progress or _progress(1),
        retry_control_count=retry,
        retry_source_run_ref=source,
        retry_successor_run_ref=successor,
        cancellation_requested=False,
        observer_ref="detail-observer",
    )


def _identity(parent, scan_run_ids=("scan-run-root",), state=contract.RecoveryState.ACTIVE,
              source=None, successor=None, scope="scope-ref", retry_lookup=None,
              successor_scope=None, lookup_source=None,
              successor_scan_run_ids=_UNSET,
              successor_requested_root_refs=_UNSET,
              successor_admitted_root_refs=_UNSET,
              successor_excluded_root_refs=_UNSET,
              successor_exclusions=_UNSET):
    scan_run_ids = tuple(scan_run_ids)
    admitted_roots = tuple(
        "root-ref-synthetic" if len(scan_run_ids) == 1 else f"root-ref-{index}"
        for index in range(len(scan_run_ids))
    )
    excluded_roots = () if scope == "scope-ref" else ("excluded-root-synthetic",)
    requested_roots = admitted_roots + excluded_roots
    frozen_scope = scope
    successor_requested_roots = (
        requested_roots
        if successor is not None and successor_requested_root_refs is _UNSET
        else None
        if successor_requested_root_refs is _UNSET
        else tuple(successor_requested_root_refs)
    )
    successor_admitted_roots = (
        admitted_roots
        if successor is not None and successor_admitted_root_refs is _UNSET
        else None
        if successor_admitted_root_refs is _UNSET
        else tuple(successor_admitted_root_refs)
    )
    successor_excluded_roots = (
        excluded_roots
        if successor is not None and successor_excluded_root_refs is _UNSET
        else None
        if successor_excluded_root_refs is _UNSET
        else tuple(successor_excluded_root_refs)
    )
    source_scan_by_root = dict(zip(admitted_roots, scan_run_ids, strict=True))
    relations = tuple(
        contract.ScanRunRelation(
            parent_run_ref=parent,
            scan_run_ref=scan_run_id,
            root_ref=root_ref,
        )
        for scan_run_id, root_ref in zip(scan_run_ids, admitted_roots, strict=True)
    )
    successor_scan_ids = (
        tuple(
            f"{source_scan_by_root[root_ref]}-successor"
            if root_ref in source_scan_by_root
            else f"successor-scan-run-{index}"
            for index, root_ref in enumerate(successor_admitted_roots or ())
        )
        if successor is not None and successor_scan_run_ids is _UNSET
        else ()
        if retry_lookup is True and successor_scan_run_ids is _UNSET
        else None
        if successor_scan_run_ids is _UNSET
        else tuple(successor_scan_run_ids)
    )
    successor_relations = (
        None
        if successor_scan_ids is None
        else tuple(
            contract.ScanRunRelation(
                parent_run_ref=successor,
                scan_run_ref=scan_run_id,
                root_ref=root_ref,
            )
            for scan_run_id, root_ref in zip(
                successor_scan_ids, successor_admitted_roots or (), strict=True
            )
        )
    )
    successor_exclusion_observations = (
        tuple(
            contract.RootExclusionObservation(
                root_ref,
                contract.RootExclusionReason.NO_LONGER_CONFIGURED,
            )
            for root_ref in successor_excluded_roots or ()
        )
        if successor is not None and successor_exclusions is _UNSET
        else None
        if successor_exclusions is _UNSET
        else tuple(successor_exclusions)
    )
    return contract.JobIdentityObservation(
        parent_run_ref=parent,
        scan_run_relations=relations,
        requested_root_refs=requested_roots,
        admitted_root_refs=admitted_roots,
        excluded_root_refs=excluded_roots,
        frozen_scope_ref=frozen_scope,
        observer_ref="identity-observer",
        parent_state=state,
        source_run_ref=(parent if successor is not None and source is None else source),
        successor_run_ref=successor,
        successor_scan_run_relations=successor_relations,
        successor_scope_ref=(
            frozen_scope if successor is not None else successor_scope
        ),
        successor_requested_root_refs=successor_requested_roots,
        successor_admitted_root_refs=successor_admitted_roots,
        successor_excluded_root_refs=successor_excluded_roots,
        successor_exclusions=successor_exclusion_observations,
        retry_relation_lookup_completed=retry_lookup,
        retry_lookup_source_run_ref=lookup_source,
    )


def _evaluate_retry_outcome(**kwargs):
    """Bind oracle tests to the source identity they use as their fixture."""
    kwargs.setdefault("expected_source_identity", kwargs.get("successor_identity"))
    return oracle.retry_outcome(**kwargs)


def _complete_no_redirect(run_ref, queried_game_ids):
    return contract.GameIdContinuityObservation(
        job_run_ref=run_ref,
        redirects=(),
        complete=True,
        observer_ref="continuity-observer",
        queried_game_ids=queried_game_ids,
    )


def _process(state, foreground, task="task-ref-synthetic"):
    return contract.ProcessAndForegroundObservation(
        process_state=state,
        package_name=QUALIFICATION_PACKAGE,
        foreground_package=foreground,
        task_continuity_ref=task,
        observer_ref="process-observer",
    )


class ScriptedTransport:
    """Deterministic fake for the exact lifecycle surface transitions."""

    def __init__(self, scenario_id):
        self.scenario_id = scenario_id
        self.parent = "parent-run"
        self.successor = "successor-run"
        self.foreground = QUALIFICATION_PACKAGE
        self.process_state = contract.ProcessState.PRESENT
        self.detail_state = contract.RecoveryState.ACTIVE
        self.successor_state = contract.RecoveryState.COMPLETED
        self.progress_calls = 0
        self.force_stop_calls = 0
        self.start_refresh_calls = 0
        self.background_calls = 0
        self.background_foreground = "com.android.launcher3"
        self.return_calls = 0
        self.restore_calls = 0
        self.retry_calls = 0
        self.launch_calls = 0
        self.navigations: list[str] = []
        self.return_task_ref = "task-ref-synthetic"
        self.identity_available = True
        self.progress_available = True
        self.jobs_preflight_rows = 0
        self.jobs_preflight_active = 0
        self.jobs_preflight_history_complete = True
        self.fail_foreground_continuity = False
        self.force_stop_verified_absent = True
        self.successor_stays_active = False
        self.complete_before_stop = False
        self.library_calls = 0
        self.already_retried = False
        self.retry_source_override = None
        self.fail_successor_foreground = False
        self.scan_run_id_override = None
        self.library_memberships = None
        self.library_membership_ids = ("fixture-synthetic",)
        self.library_membership_ids_after_stop = None
        self.library_membership_ids_after_retry = None
        self.library_identity_continuity_before_stop = None
        self.library_identity_continuity_after_stop = None
        self.library_identity_continuity_after_retry = None
        self.library_observations_after_stop = 0
        self.membership_identity_available = True
        self.scan_root_preloss_presentation = (
            contract.ScanRootPresentation.ACTIVE_SCAN
            if scenario_id == contract.JOB_LIFECYCLE_SCENARIO_AND_05
            else contract.ScanRootPresentation.HISTORICAL_LAST_SCAN
        )
        self.scan_root_preloss_state = (
            None
            if self.scan_root_preloss_presentation
            is contract.ScanRootPresentation.ACTIVE_SCAN
            else "complete"
        )
        self.scan_root_recovered_presentation = (
            contract.ScanRootPresentation.HISTORICAL_LAST_SCAN
        )
        self.scan_root_recovered_state = "complete"
        self.scan_root_run_ref = "scan-run-root"
        self.scan_root_recovered_run_ref = None
        self.scan_root_ref_override = None
        self.scan_root_presentation_override = _UNSET
        self.scan_root_state_override = _UNSET
        self.post_stop_root_observations = 0
        self.scan_root_post_retry_presentation = (
            contract.ScanRootPresentation.HISTORICAL_LAST_SCAN
        )
        self.scan_root_post_retry_state = "complete"
        self.scan_root_post_retry_run_ref = _UNSET
        self.scan_root_post_retry_view_job_control_count = 1
        self.scan_root_post_retry_root_ref = _UNSET
        self.successor_detail_observations = 0
        self.successor_completes_after = None
        self.verify_target_actions = []
        self.verify_target_calls = []
        self.fail_verify_action = None
        self.expected_target_ref = None
        self.expected_root_ref = "root-ref-synthetic"
        self.navigation_expectations = []

    def verify_target(
        self,
        serial,
        target_ref,
        timeout,
        *,
        action=None,
        package=None,
    ):
        self.verify_target_actions.append(action)
        self.verify_target_calls.append((serial, target_ref, action, package))
        if action == self.fail_verify_action:
            return False
        if self.expected_target_ref is not None and target_ref != self.expected_target_ref:
            return False
        return (
            serial == _SERIAL
            and bool(target_ref)
            and package == QUALIFICATION_PACKAGE
        )

    def navigate(
        self,
        action,
        timeout,
        *,
        expected_run_ref=None,
        expected_root_ref=None,
    ):
        self.navigations.append(action)
        self.navigation_expectations.append(
            (action, expected_run_ref, expected_root_ref)
        )
        if action == "open_refresh_detail" and expected_run_ref != self.parent:
            return False
        if action == "open_scan_root" and expected_root_ref != self.expected_root_ref:
            return False
        if action == "open_scan_job_detail" and expected_run_ref is None:
            return False
        if action == "open_retry_successor_detail" and expected_run_ref != self.successor:
            return False
        return True

    def observe_library(self, timeout):
        membership = 1
        if self.library_memberships:
            membership = self.library_memberships.pop(0)
        identities = (
            self.library_membership_ids_after_stop
            if self.force_stop_calls and self.library_membership_ids_after_stop is not None
            else self.library_membership_ids
        )
        if not self.membership_identity_available:
            identities = None
        observed = _library(
            membership=membership,
            active=self.detail_state is contract.RecoveryState.ACTIVE,
            membership_ids=identities,
            identity_continuity=(
                self.library_identity_continuity_after_retry
                if self.retry_calls
                else self.library_identity_continuity_after_stop
                if self.force_stop_calls
                else self.library_identity_continuity_before_stop
            ),
        )
        self.library_calls += 1
        if self.force_stop_calls:
            self.library_observations_after_stop += 1
        if self.complete_before_stop and self.library_calls == 2:
            self.detail_state = contract.RecoveryState.COMPLETED
        return observed

    def observe_jobs(self, timeout):
        if self.scenario_id == contract.JOB_LIFECYCLE_SCENARIO_AND_05 and self.force_stop_calls == 0 and self.progress_calls == 0:
            return _jobs()
        if self.progress_calls == 0 and self.force_stop_calls == 0:
            return _jobs(
                rows=self.jobs_preflight_rows,
                active=self.jobs_preflight_active,
                history_complete=self.jobs_preflight_history_complete,
            )
        return _jobs(parent=self.parent, state=self.detail_state, rows=1, active=1 if self.detail_state is contract.RecoveryState.ACTIVE else 0)

    def observe_refresh_detail(self, parent_ref, timeout):
        if parent_ref == self.successor or (
            self.scenario_id == contract.JOB_LIFECYCLE_SCENARIO_AND_05
            and self.retry_calls
            and parent_ref == self.successor
        ):
            self.successor_detail_observations += 1
            successor_state = (
                contract.RecoveryState.ACTIVE
                if self.successor_stays_active
                else self.successor_state
            )
            if (
                self.successor_completes_after is not None
                and self.successor_detail_observations < self.successor_completes_after
            ):
                successor_state = contract.RecoveryState.ACTIVE
            return _detail(
                self.successor,
                successor_state,
                progress=_progress(3, parent=self.successor),
                retry=0,
                source=self.retry_source_override or self.parent,
            )
        return _detail(
            self.parent,
            self.detail_state,
            progress=_progress(
                2 if self.progress_calls else 1,
                parent=self.parent,
            ),
            retry=1 if self.detail_state in oracle.RETRY_ELIGIBLE_STATES else 0,
        )

    def observe_refresh_progress(self, parent_ref, timeout):
        if not self.progress_available:
            raise RuntimeError("progress unavailable")
        self.progress_calls += 1
        return _progress(self.progress_calls, parent=parent_ref)

    def observe_scan_root(self, root_ref, timeout):
        before_stop = self.force_stop_calls == 0
        root_override = None
        if before_stop:
            presentation = self.scan_root_preloss_presentation
            state = self.scan_root_preloss_state
            scan_run_ref = self.scan_root_run_ref
            parent_run_ref = self.parent
            view_job_run_ref = self.parent
            controls = 1
        else:
            self.post_stop_root_observations += 1
            if self.post_stop_root_observations >= 2:
                presentation = self.scan_root_post_retry_presentation
                state = self.scan_root_post_retry_state
                scan_run_ref = (
                    "scan-run-root-successor"
                    if self.scan_root_post_retry_run_ref is _UNSET
                    else self.scan_root_post_retry_run_ref
                )
                parent_run_ref = self.successor
                view_job_run_ref = self.successor
                controls = self.scan_root_post_retry_view_job_control_count
                if self.scan_root_post_retry_root_ref is not _UNSET:
                    root_override = self.scan_root_post_retry_root_ref
            else:
                presentation = self.scan_root_recovered_presentation
                state = self.scan_root_recovered_state
                scan_run_ref = self.scan_root_run_ref
                parent_run_ref = self.parent
                view_job_run_ref = self.parent
                if self.scan_root_recovered_run_ref is not None:
                    scan_run_ref = self.scan_root_recovered_run_ref
                controls = 1
        if self.scan_root_presentation_override is not _UNSET:
            presentation = self.scan_root_presentation_override
        if self.scan_root_state_override is not _UNSET:
            state = self.scan_root_state_override
        return contract.ScanRootObservation(
            surface=contract.JobLifecycleSurface.SCAN_ROOT_DETAIL,
            root_ref=root_override or self.scan_root_ref_override or root_ref,
            last_scan_state=state,
            view_job_control_count=controls,
            view_job_run_ref=view_job_run_ref,
            observer_ref="root-observer",
            presentation=presentation,
            scan_run_ref=scan_run_ref,
            scan_parent_run_ref=parent_run_ref,
        )

    def observe_scan_run(self, parent_ref, scan_run_ref, root_ref, timeout):
        if self.scan_run_id_override is not None:
            scan_run_ref = self.scan_run_id_override
        return contract.ScanRunObservation(
            surface=contract.JobLifecycleSurface.REFRESH_DETAIL,
            parent_run_ref=parent_ref,
            scan_run_ref=scan_run_ref,
            root_ref=root_ref,
            parent_state=contract.RecoveryState.COMPLETED,
            scan_state="complete",
            observer_ref="scan-observer",
        )

    def start_refresh(self, timeout):
        self.start_refresh_calls += 1
        self.progress_calls = 0
        self.detail_state = contract.RecoveryState.ACTIVE

    def retry_refresh(self, timeout):
        self.retry_calls += 1
        self.detail_state = contract.RecoveryState.FAILED
        if self.library_membership_ids_after_retry is not None:
            self.library_membership_ids_after_stop = (
                self.library_membership_ids_after_retry
            )

    def background_package(self, package, timeout):
        self.background_calls += 1
        self.foreground = self.background_foreground

    def return_existing_task(self, package, task_ref, timeout):
        self.return_calls += 1
        self.foreground = package
        if (
            self.scenario_id == "AND-04"
            and self.detail_state is contract.RecoveryState.ACTIVE
        ):
            self.detail_state = contract.RecoveryState.COMPLETED

    def launch_package(self, package, timeout):
        self.launch_calls += 1
        self.foreground = package
        self.process_state = contract.ProcessState.PRESENT

    def force_stop_package(self, package, timeout):
        self.force_stop_calls += 1
        if self.force_stop_verified_absent:
            self.process_state = contract.ProcessState.ABSENT
            self.foreground = "com.android.launcher3"
        else:
            self.process_state = contract.ProcessState.UNKNOWN

    def restore_foreground(self, package, task_ref, timeout):
        self.restore_calls += 1
        self.foreground = package


class ScriptedObserver:
    def __init__(self, transport, baseline=None):
        self.transport = transport
        self.baseline = baseline or _baseline()

    def observe_baseline(self, timeout):
        return self.baseline

    def observe_identity(self, parent_ref, timeout):
        transport = self.transport
        if not transport.identity_available:
            return _identity(None, scan_run_ids=())
        if parent_ref is None:
            return _identity(transport.parent, state=contract.RecoveryState.ACTIVE)
        if transport.already_retried and parent_ref == transport.parent:
            return _identity(
                transport.parent,
                state=contract.RecoveryState.FAILED,
                source=transport.parent,
                successor=transport.successor,
                retry_lookup=True,
                lookup_source=transport.parent,
                successor_scan_run_ids=("scan-run-root-successor",),
            )
        if transport.retry_calls and parent_ref == transport.parent:
            return _identity(
                transport.parent,
                state=contract.RecoveryState.FAILED,
                source=transport.parent,
                successor=transport.successor,
                retry_lookup=True,
                lookup_source=transport.parent,
                successor_scan_run_ids=("scan-run-root-successor",),
            )
        if transport.force_stop_calls and parent_ref == transport.parent:
            return _identity(
                transport.parent,
                scan_run_ids=("scan-run-root",),
                state=transport.detail_state,
                scope="scope-ref",
                retry_lookup=True,
                lookup_source=transport.parent,
            )
        return _identity(parent_ref, state=transport.detail_state)

    def observe_process(self, package, timeout):
        transport = self.transport
        foreground = (
            "com.android.launcher3"
            if transport.fail_successor_foreground and transport.retry_calls
            else transport.foreground
        )
        task = (
            "task-ref-other"
            if transport.fail_foreground_continuity
            else "task-ref-synthetic"
        )
        return contract.ProcessAndForegroundObservation(
            process_state=transport.process_state,
            package_name=package,
            foreground_package=foreground,
            task_continuity_ref=task,
            observer_ref="process-observer",
        )


class RecordingWriter:
    def __init__(self):
        self.events = []
        self.assertion_keys: list[tuple[str, str]] = []
        self.terminal = None
        self.fail_assertion = False
        self.fail_assertion_after = None
        self.assertion_count = 0
        self.fail_terminal = False
        self.terminal_session_id = None
        self.fail_next_assertion = False

    def open_session(self, spec, request):
        self.events.append(("open", request.operation_id))
        return SimpleReceipt(spec.session_id, 1)

    def append_lifecycle(self, session_id, observation, request):
        self.events.append(("lifecycle", observation.lifecycle.value))
        return SimpleReceipt(session_id, len(self.events))

    def append_assertion(self, session_id, observation, request):
        self.assertion_count += 1
        if self.fail_next_assertion:
            self.fail_next_assertion = False
            raise RuntimeError("evidence append failed")
        if self.fail_assertion or (
            self.fail_assertion_after is not None
            and self.assertion_count > self.fail_assertion_after
        ):
            raise RuntimeError("evidence append failed")
        self.events.append(("assertion", observation.actual_outcome.value))
        self.assertion_keys.append(
            (request.operation_id, observation.actual_outcome.value)
        )
        return SimpleReceipt(session_id, len(self.events))

    def append_terminal(self, session_id, observation, request):
        if self.fail_terminal:
            raise RuntimeError("terminal evidence append failed")
        if self.terminal is not None:
            raise RuntimeError("already terminal")
        self.terminal = observation
        self.events.append(("terminal", observation.outcome.value))
        return SimpleReceipt(self.terminal_session_id or session_id, len(self.events))

    def verify_execution(self, session_id):
        return SimpleNamespace(manifest_sha256="3" * 64)


class SimpleReceipt:
    def __init__(self, session_id, sequence):
        self.session_id = session_id
        self.sequence = sequence


class SimpleNamespace:
    def __init__(self, **values):
        self.__dict__.update(values)


class _EqualityImpersonatingReference:
    def __init__(self, expected: str):
        self.expected = expected

    def __eq__(self, other):
        return other == self.expected

    def __ne__(self, other):
        return not self.__eq__(other)


class _EqualityImpersonatingString(str):
    def __new__(cls, value: str, expected: str):
        instance = super().__new__(cls, value)
        instance.expected = expected
        return instance

    def __eq__(self, other):
        return other == self.expected

    def __ne__(self, other):
        return not self.__eq__(other)


class ContractTests(unittest.TestCase):
    def test_exact_operation_counts_and_timeout_sums(self):
        self.assertEqual(contract.JOB_LIFECYCLE_CONTRACT_VERSION, 5)
        self.assertEqual(contract.JOB_LIFECYCLE_CAPABILITY_VERSION, 4)
        self.assertEqual(contract.JOB_LIFECYCLE_ORACLE_VERSION, 9)
        self.assertEqual(
            contract.JOB_LIFECYCLE_CAPABILITY_SHA256,
            "919d3bcf6e692a2936c53af929334326b54df60cd3c7089e0a5083fb7c691644",
        )
        self.assertEqual(
            contract.JOB_LIFECYCLE_ORACLE_SHA256,
            "ffada5ef446923dfba24aaf8dd3b2dc7cb483e749aa5480cd23431ef5bf4be4f",
        )
        self.assertEqual(contract.operation_count("AND-04"), 31)
        self.assertEqual(contract.operation_count("AND-05"), 45)
        self.assertEqual(contract.raw_timeout_sum("AND-04"), 575)
        self.assertEqual(contract.raw_timeout_sum("AND-05"), 880)
        self.assertEqual(contract.required_session_span("AND-04"), 771)
        self.assertEqual(contract.required_session_span("AND-05"), 1135)
        self.assertEqual(900 - 60 - 771, 69)
        self.assertEqual(1280 - 60 - 1135, 85)

    def test_latency_policy_pins_exact_input_constraints(self):
        policy = contract._LATENCY_POLICY_DECLARATION
        self.assertEqual(policy["warmup_cycles"], {"exact_type": "int", "value": 5})
        self.assertEqual(policy["measured_cycles"], {"exact_type": "int", "value": 20})
        self.assertEqual(
            policy["per_cycle_timeout_seconds"],
            {"exact_type": "int", "minimum": 1},
        )
        self.assertEqual(
            policy["percentile_95_ceiling_milliseconds"],
            {"exact_type": "int", "minimum": 0},
        )
        self.assertEqual(
            policy["elapsed_milliseconds"],
            {"exact_type": "int", "minimum": 0},
        )
        self.assertEqual(
            policy["boolean_observations"],
            {
                "exact_type": "bool",
                "fields": ("active_overlap_confirmed", "warmup", "return_completed"),
            },
        )
        self.assertEqual(
            policy["references"],
            {
                "exact_type": "str",
                "minimum_length": 1,
                "maximum_length": 256,
                "nonblank_after_strip": True,
            },
        )
        self.assertEqual(
            policy["action_ids"],
            {
                "exact_type": "tuple",
                "nonempty": True,
                "unique": True,
                "item_exact_type": "str",
                "minimum_length": 1,
                "maximum_length": 64,
                "grammar": r"[a-z][a-z0-9_-]{0,63}",
            },
        )
        self.assertEqual(
            policy["rule_sha256"],
            {"exact_type": "str", "grammar": r"[0-9a-f]{64}"},
        )
        self.assertEqual(
            policy["cycle_evidence_references"],
            {"reference_policy": "references", "unique": True},
        )

    def test_operation_ids_and_categories_are_closed(self):
        for scenario_id, scenarios in contract.JOB_LIFECYCLE_OPERATIONS.items():
            for spec in scenarios:
                self.assertEqual(
                    spec.index,
                    scenarios.index(spec) + 1,
                )
                self.assertIn(
                    spec.category,
                    {"read_only", "navigation", "refresh", "launch", "force_stop"},
                )
                arguments = contract.operation_arguments(spec)
                self.assertEqual(
                    set(arguments),
                    {spec.argument_key, "oracle_sha256", "oracle_version"},
                )

    def test_every_operation_binds_one_existing_private_handler(self):
        executor_type = lifecycle_executor._JobLifecycleOperationExecutor
        for scenario_id, scenarios in contract.JOB_LIFECYCLE_OPERATIONS.items():
            for spec in scenarios:
                self.assertRegex(spec.handler, r"^[a-z][a-z0-9_]*$")
                self.assertTrue(
                    callable(getattr(executor_type, "_step_" + spec.handler, None)),
                    msg=(
                        f"{scenario_id} operation {spec.index} does not bind an "
                        "existing private handler"
                    ),
                )

    def test_dispatch_rejects_an_unknown_handler_before_any_effect(self):
        executor = object.__new__(lifecycle_executor._JobLifecycleOperationExecutor)
        spec = contract.JOB_LIFECYCLE_OPERATIONS["AND-04"][0]
        invalid_specs = (
            replace(spec, handler=""),
            replace(spec, handler="not_a_step"),
            object(),
        )
        for invalid in invalid_specs:
            with self.assertRaises(lifecycle_executor._JobLifecycleStop):
                executor._dispatch(object(), invalid)

    def test_plan_digest_is_deterministic_and_private(self):
        value = _baseline().digest()
        self.assertRegex(value, r"^[0-9a-f]{64}$")
        self.assertNotIn("task-ref-synthetic", value)
        self.assertNotIn(_SERIAL, value)

    def test_contract_rejects_unknown_scenarios_and_objects(self):
        with self.assertRaises(ValueError):
            contract.operation_count("AND-99")
        self.assertIsNone(contract.plan_digest_for_authorization(object()))
        self.assertFalse(contract.validate_job_lifecycle_authorization(object()))
        self.assertEqual(
            contract.expected_operation_arguments("AND-04", 1)["observation"],
            "no_reset_baseline",
        )

    def test_malformed_lifecycle_authorization_shapes_are_rejected(self):
        digest = contract.plan_digest_for_authorization(
            SimpleNamespace(
                scenario_ids=("AND-04",),
                operations=(object(),),
                application_package=QUALIFICATION_PACKAGE,
                apk_sha256=_APK_SHA256,
                certificate_sha256=_CERTIFICATE_SHA256,
                source_revision=_REVISION,
                version_code=123,
                rules_sha256=_RULES_SHA256,
            )
        )
        self.assertIsNone(digest)
        self.assertFalse(
            contract.validate_job_lifecycle_authorization(
                SimpleNamespace(scenario_ids=("AND-99",))
            )
        )
        self.assertFalse(
            contract.validate_job_lifecycle_authorization(
                SimpleNamespace(scenario_ids=("AND-04",), state_mode="reset")
            )
        )
        self.assertFalse(
            contract.validate_job_lifecycle_authorization(
                SimpleNamespace(
                    scenario_ids=("AND-04",),
                    state_mode="no-reset",
                    issued_at="not-a-time",
                    session_deadline=NOW,
                    cleanup_deadline=NOW,
                )
            )
        )
        issued_at = datetime(2030, 1, 1, tzinfo=timezone.utc)
        session_deadline = issued_at + timedelta(seconds=900)
        self.assertFalse(
            contract.validate_job_lifecycle_authorization(
                SimpleNamespace(
                    scenario_ids=("AND-04",),
                    state_mode="no-reset",
                    issued_at=issued_at,
                    session_deadline=session_deadline,
                    cleanup_deadline=session_deadline
                    + timedelta(seconds=contract.JOB_LIFECYCLE_CLOSURE_SECONDS),
                    cleanup_reserve_seconds=contract.JOB_LIFECYCLE_CLOSURE_SECONDS,
                    approved_remediation=(),
                    application_package=QUALIFICATION_PACKAGE,
                    operations=(),
                )
            )
        )

    def test_typed_observation_digests_and_established_guards(self):
        library = _library()
        jobs = _jobs(parent="parent", state=contract.RecoveryState.ACTIVE, rows=1, active=1)
        detail = _detail("parent", contract.RecoveryState.ACTIVE)
        root = contract.ScanRootObservation(
            contract.JobLifecycleSurface.SCAN_ROOT_DETAIL,
            "root",
            "complete",
            1,
            "run",
            "observer",
            contract.ScanRootPresentation.HISTORICAL_LAST_SCAN,
            "scan-run",
            "parent",
        )
        scan = contract.ScanRunObservation(
            contract.JobLifecycleSurface.REFRESH_DETAIL,
            "parent",
            "scan-run",
            "root",
            contract.RecoveryState.COMPLETED,
            "complete",
            "observer",
        )
        process = _process(contract.ProcessState.PRESENT, QUALIFICATION_PACKAGE)
        identity = _identity("parent")
        for value in (library, jobs, detail, root, scan, process, identity, _progress(1)):
            with self.subTest(value=type(value).__name__):
                self.assertRegex(value.digest(), r"^[0-9a-f]{64}$")
        self.assertTrue(library.established())
        self.assertTrue(jobs.established())
        self.assertTrue(detail.established())
        self.assertTrue(root.established())
        self.assertTrue(scan.established())
        self.assertNotEqual(
            replace(library, membership_ids=("asset-a",)).digest(),
            replace(library, membership_ids=("asset-b",)).digest(),
        )
        self.assertNotEqual(
            _identity("parent", retry_lookup=True).digest(),
            _identity("parent", retry_lookup=False).digest(),
        )
        self.assertFalse(
            replace(library, surface=None).established()
        )
        self.assertFalse(replace(detail, progress=None).established())
        self.assertFalse(replace(root, view_job_control_count=-1).established())
        self.assertFalse(replace(scan, scan_state="").established())
        self.assertFalse(
            contract.RefreshProgressFacts(None, None, None, "library_refresh.x", 0)
            .has_committed_progress()
        )

    def test_library_identity_requires_a_complete_unpaginated_result(self):
        page = contract.LibrarySurfaceObservation(
            surface=contract.JobLifecycleSurface.LIBRARY,
            membership_count=1,
            refresh_control_present=True,
            refresh_active=False,
            observer_ref="library-observer",
            membership_ids=("game-a",),
        )
        self.assertFalse(page.membership_identity_complete())

    def test_recovery_state_fields_reject_string_enum_impostors_safely(self):
        jobs = replace(_jobs(), state="active")
        detail = replace(_detail("parent", contract.RecoveryState.ACTIVE), state="active")
        identity = replace(_identity("parent"), parent_state="active")
        scan = contract.ScanRunObservation(
            contract.JobLifecycleSurface.REFRESH_DETAIL,
            "parent",
            "scan-run",
            "root",
            "completed",
            "complete",
            "scan-observer",
        )

        self.assertFalse(jobs.established())
        self.assertFalse(detail.established())
        self.assertFalse(identity.parent_identity_complete())
        self.assertFalse(scan.established())
        self.assertFalse(replace(detail, state=None).established())
        self.assertFalse(replace(scan, parent_state=None).established())
        for observation in (jobs, detail, identity, scan):
            with self.subTest(observation=type(observation).__name__):
                self.assertRegex(observation.digest(), r"^[0-9a-f]{64}$")

        self.assertTrue(_jobs(parent=None, state=None).established())
        self.assertTrue(replace(_identity("parent"), parent_state=None).scan_relationships_complete())

    def test_scanrun_relation_requires_keyword_only_fields_and_preserves_digest(self):
        with self.assertRaises(TypeError):
            contract.ScanRunRelation("scan-run", "parent-run", "root-ref")

        relation = contract.ScanRunRelation(
            parent_run_ref="parent",
            scan_run_ref="scan",
            root_ref="root",
        )
        self.assertTrue(relation.established())
        self.assertEqual(
            (relation.parent_run_ref, relation.scan_run_ref, relation.root_ref),
            ("parent", "scan", "root"),
        )
        self.assertEqual(
            relation.digest(),
            "111e190e2d8c5409a742544212b8b1f529c83af12a07fd24578ce5e1a514640b",
        )

    def test_job_and_continuity_observers_require_bounded_nonblank_provenance(self):
        invalid_refs = (None, "", " \t ", "o" * 257, 42)
        identity = _identity(
            "parent-run", scan_run_ids=("scan-run",), scope="scope-ref"
        )
        continuity = _complete_no_redirect("parent-run", ("game-id",))

        self.assertTrue(identity.parent_identity_complete())
        self.assertTrue(identity.scan_relationships_complete())
        self.assertTrue(continuity.established())
        self.assertTrue(replace(identity, observer_ref="o").parent_identity_complete())
        self.assertTrue(
            replace(identity, observer_ref="o" * 256).parent_identity_complete()
        )
        self.assertTrue(replace(continuity, observer_ref="o").established())
        self.assertTrue(
            replace(continuity, observer_ref="o" * 256).established()
        )

        for observer_ref in invalid_refs:
            with self.subTest(observer_ref=observer_ref):
                unproven_identity = replace(identity, observer_ref=observer_ref)
                self.assertFalse(unproven_identity.parent_identity_complete())
                self.assertFalse(unproven_identity.scan_relationships_complete())
                self.assertFalse(
                    replace(continuity, observer_ref=observer_ref).established()
                )

    def test_scanrun_identity_requires_unique_exact_runs(self):
        multiple = _identity("parent", scan_run_ids=("scan-a", "scan-b"))
        self.assertTrue(multiple.scan_relationships_complete())
        self.assertEqual(
            oracle.validate_identity(multiple).outcome,
            evidence.AssertionOutcome.PASSED,
        )
        self.assertEqual(
            {
                (relation.parent_run_ref, relation.scan_run_ref, relation.root_ref)
                for relation in multiple.scan_run_relations
            },
            {
                ("parent", "scan-a", "root-ref-0"),
                ("parent", "scan-b", "root-ref-1"),
            },
        )

        missing_relation = replace(
            multiple,
            scan_run_relations=multiple.scan_run_relations[:1],
        )
        self.assertEqual(
            oracle.validate_identity(missing_relation).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )

        duplicate = _identity("parent", scan_run_ids=("scan-run", "scan-run"))
        self.assertFalse(duplicate.scan_relationships_complete())
        self.assertEqual(
            oracle.validate_identity(duplicate).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )

        foreign_parent = _identity(
            "foreign-parent", scan_run_ids=("scan-a", "scan-b")
        )
        self.assertEqual(
            oracle.validate_identity(
                foreign_parent,
                expected_parent_ref="parent",
            ).outcome,
            evidence.AssertionOutcome.FAILED,
        )

        foreign_root = replace(
            multiple,
            scan_run_relations=(
                replace(multiple.scan_run_relations[0], root_ref="other-root"),
                multiple.scan_run_relations[1],
            ),
        )
        self.assertEqual(
            oracle.validate_identity(foreign_root).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )

    def test_identity_contract_names_scan_runs_instead_of_child_jobs(self):
        fields = contract.JobIdentityObservation.__dataclass_fields__
        self.assertNotIn("child_run_refs", fields)
        self.assertIn("scan_run_relations", fields)
        self.assertTrue(
            {
                "requested_root_refs",
                "admitted_root_refs",
                "excluded_root_refs",
                "observer_ref",
            }.issubset(fields)
        )

        retry_duplicate = _identity(
            "parent",
            scan_run_ids=("scan-run-a", "scan-run-b"),
            state=contract.RecoveryState.FAILED,
            source="parent",
            successor="successor",
            retry_lookup=True,
            lookup_source="parent",
            successor_scan_run_ids=("successor-scan-a", "successor-scan-a"),
        )
        self.assertFalse(retry_duplicate.retry_complete())
        self.assertEqual(
            oracle.validate_identity(retry_duplicate, retry=True).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )

    def test_parent_jobrun_is_not_fabricated_as_a_child_jobrun(self):
        identity = _identity("parent", scan_run_ids=("scan-run",))
        self.assertTrue(identity.scan_relationships_complete())
        self.assertEqual(identity.scan_run_relations[0].parent_run_ref, "parent")
        self.assertEqual(identity.scan_run_relations[0].scan_run_ref, "scan-run")

    def test_retry_scanrun_relation_must_belong_to_successor_jobrun(self):
        successor_identity = _identity(
            "parent",
            scan_run_ids=("successor",),
            state=contract.RecoveryState.FAILED,
            source="parent",
            successor="successor",
            retry_lookup=True,
            lookup_source="parent",
        )
        self.assertTrue(successor_identity.retry_complete())
        wrong_owner = replace(
            successor_identity,
            successor_scan_run_relations=(
                contract.ScanRunRelation(
                    parent_run_ref="parent",
                    scan_run_ref="successor",
                    root_ref="root-ref-synthetic",
                ),
            ),
        )
        self.assertFalse(wrong_owner.retry_complete())
        self.assertEqual(
            oracle.validate_identity(wrong_owner, retry=True).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )

        reused_scanrun = replace(
            successor_identity,
            successor_scan_run_relations=(
                contract.ScanRunRelation(
                    parent_run_ref="successor",
                    scan_run_ref="successor",
                    root_ref="root-ref-synthetic",
                ),
            ),
        )
        self.assertFalse(reused_scanrun.retry_complete())
        self.assertEqual(
            oracle.validate_identity(reused_scanrun, retry=True).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )

    def test_retry_rechecks_originally_excluded_root_eligibility(self):
        successor_identity = _identity(
            "parent",
            scan_run_ids=("source-scan-run",),
            state=contract.RecoveryState.FAILED,
            source="parent",
            successor="successor",
            scope="scope-with-excluded-root",
            retry_lookup=True,
            lookup_source="parent",
            successor_scan_run_ids=(
                "successor-scan-originally-admitted",
                "successor-scan-newly-eligible",
            ),
            successor_requested_root_refs=(
                "root-ref-synthetic",
                "excluded-root-synthetic",
            ),
            successor_admitted_root_refs=(
                "root-ref-synthetic",
                "excluded-root-synthetic",
            ),
            successor_excluded_root_refs=(),
        )

        self.assertTrue(successor_identity.retry_complete())
        self.assertEqual(
            _evaluate_retry_outcome(
                source_state=contract.RecoveryState.FAILED,
                dispatched=True,
                already_retried=False,
                parent_ref="parent",
                frozen_scope_ref="scope-with-excluded-root",
                successor_identity=successor_identity,
            ).outcome,
            evidence.AssertionOutcome.PASSED,
        )

    def test_partial_retry_binds_current_admissions_and_typed_exclusions(self):
        partial = _identity(
            "parent",
            scan_run_ids=("source-scan-a", "source-scan-b"),
            state=contract.RecoveryState.FAILED,
            source="parent",
            successor="successor",
            retry_lookup=True,
            lookup_source="parent",
            successor_scan_run_ids=("successor-scan-a",),
            successor_requested_root_refs=("root-ref-0", "root-ref-1"),
            successor_admitted_root_refs=("root-ref-0",),
            successor_excluded_root_refs=("root-ref-1",),
            successor_exclusions=(
                contract.RootExclusionObservation(
                    "root-ref-1",
                    contract.RootExclusionReason.ALREADY_SCANNING,
                ),
            ),
        )
        self.assertTrue(partial.retry_complete())
        self.assertTrue(
            partial.successor_root_scope_matches(
                partial.successor_requested_root_refs,
                partial.successor_admitted_root_refs,
                partial.successor_excluded_root_refs,
                partial.successor_exclusions,
            )
        )
        self.assertEqual(
            _evaluate_retry_outcome(
                source_state=contract.RecoveryState.FAILED,
                dispatched=True,
                already_retried=False,
                parent_ref="parent",
                frozen_scope_ref="scope-ref",
                successor_identity=partial,
            ).outcome,
            evidence.AssertionOutcome.PASSED,
        )
        missing_exclusion_reason = replace(partial, successor_exclusions=())
        self.assertFalse(missing_exclusion_reason.retry_complete())
        self.assertEqual(
            _evaluate_retry_outcome(
                source_state=contract.RecoveryState.FAILED,
                dispatched=True,
                already_retried=False,
                parent_ref="parent",
                frozen_scope_ref="scope-ref",
                successor_identity=missing_exclusion_reason,
            ).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        changed_reason = replace(
            partial,
            successor_exclusions=(
                contract.RootExclusionObservation(
                    "root-ref-1",
                    contract.RootExclusionReason.NO_LONGER_CONFIGURED,
                ),
            ),
        )
        self.assertNotEqual(partial.digest(), changed_reason.digest())
        self.assertNotEqual(
            partial.digest(),
            replace(
                partial,
                successor_requested_root_refs=(
                    *partial.successor_requested_root_refs,
                    "another-requested-root",
                ),
            ).digest(),
        )
        self.assertFalse(
            changed_reason.successor_root_scope_matches(
                partial.successor_requested_root_refs,
                partial.successor_admitted_root_refs,
                partial.successor_excluded_root_refs,
                partial.successor_exclusions,
            )
        )
        relation_to_excluded_root = replace(
            partial,
            successor_scan_run_relations=(
                *partial.successor_scan_run_relations,
                contract.ScanRunRelation(
                    parent_run_ref="successor",
                    scan_run_ref="successor-scan-b",
                    root_ref="root-ref-1",
                ),
            ),
        )
        self.assertEqual(
            _evaluate_retry_outcome(
                source_state=contract.RecoveryState.FAILED,
                dispatched=True,
                already_retried=False,
                parent_ref="parent",
                frozen_scope_ref="scope-ref",
                successor_identity=relation_to_excluded_root,
            ).outcome,
            evidence.AssertionOutcome.FAILED,
        )
        self.assertFalse(
            replace(
                partial,
                successor_requested_root_refs=(
                    "root-ref-0",
                    "root-ref-1",
                    "unrequested-root",
                ),
                successor_admitted_root_refs=("root-ref-0", "unrequested-root"),
                successor_scan_run_relations=(
                    contract.ScanRunRelation(
                        parent_run_ref="successor",
                        scan_run_ref="successor-scan-a",
                        root_ref="root-ref-0",
                    ),
                    contract.ScanRunRelation(
                        parent_run_ref="successor",
                        scan_run_ref="successor-scan-unrequested",
                        root_ref="unrequested-root",
                    ),
                ),
                successor_excluded_root_refs=("root-ref-1",),
                successor_exclusions=(
                    contract.RootExclusionObservation(
                        "root-ref-1",
                        contract.RootExclusionReason.NO_LONGER_CONFIGURED,
                    ),
                ),
            ).retry_complete()
        )

    def test_interrupted_is_terminal_but_not_active(self):
        self.assertNotIn(contract.RecoveryState.INTERRUPTED, contract.ACTIVE_STATES)
        self.assertIn(contract.RecoveryState.INTERRUPTED, contract.TERMINAL_STATES)


class ManifestLifecycleTests(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.directory = Path(self.temporary_directory.name)

    def _load(self, document):
        return _load_lifecycle_authorization(self.directory, document)

    def test_lifecycle_profile_loads_exact_plan(self):
        authorization = self._load(_authorization_document())
        self.assertEqual(authorization.scenario_ids, ("AND-04",))
        self.assertEqual(authorization.state_mode, SessionStateMode.NO_RESET)
        self.assertEqual(len(authorization.operations), 31)
        self.assertEqual(
            contract.plan_digest_for_authorization(authorization),
            authorization.plan_sha256,
        )

    def test_published_v7_plan_digests_are_rejected_with_current_oracle(self):
        published_v7_plan_digests = {
            "AND-04": "71c13ba6d003787d212be1d7283969b42735bb5a192cd7c133028d306d974e13",
            "AND-05": "d2898f073a89730619bdad4bc028ec935cbf0322c76fdcd7e9b7ae7e58896ad4",
        }
        for scenario, old_plan_digest in published_v7_plan_digests.items():
            with self.subTest(scenario=scenario):
                document = _authorization_document(scenario)
                document["plan"]["plan_sha256"] = old_plan_digest
                with self.assertRaises(manifest.AuthorizationError):
                    manifest._load_job_lifecycle_authorization(
                        write_private_json(
                            self.directory,
                            f"published-v7-plan-{scenario}.json",
                            document,
                        )
                    )

    def test_lifecycle_authorization_requires_current_oracle_revision(self):
        published_v8_plan_digests = {
            "AND-04": "5be168cf38cfd13288cdbd9536247f1d9d630245c4ab2ed38aa49b0229c04c41",
            "AND-05": "dddbaa166f5d5b06f109445b199692b7f22fa95ed98ed63871683b9e291263d6",
        }
        for scenario, old_plan_digest in published_v8_plan_digests.items():
            with self.subTest(published_revision="oracle-v8", scenario=scenario):
                document = _authorization_document(scenario)
                document["plan"]["plan_sha256"] = old_plan_digest
                for operation in document["operations"]:
                    operation["arguments"]["oracle_version"] = "8"
                    operation["arguments"]["oracle_sha256"] = (
                        "c15ee6d1d46043739d539367f16dd550e0c5b2e53708b5b30083551a42fe9e38"
                    )
                with self.assertRaises(manifest.AuthorizationError):
                    manifest._load_job_lifecycle_authorization(
                        write_private_json(
                            self.directory,
                            f"published-v8-{scenario}.json",
                            document,
                        )
                    )

        published_v7_plan_digests = {
            "AND-04": "71c13ba6d003787d212be1d7283969b42735bb5a192cd7c133028d306d974e13",
            "AND-05": "d2898f073a89730619bdad4bc028ec935cbf0322c76fdcd7e9b7ae7e58896ad4",
        }
        for scenario, old_plan_digest in published_v7_plan_digests.items():
            with self.subTest(published_revision="oracle-v7", scenario=scenario):
                document = _authorization_document(scenario)
                document["plan"]["plan_sha256"] = old_plan_digest
                for operation in document["operations"]:
                    operation["arguments"]["oracle_version"] = "7"
                    operation["arguments"]["oracle_sha256"] = (
                        "3f035f161cbb5d1cb3edd88b29069a12c2bc8dd2fc72c5783f39279c9243698a"
                    )
                with self.assertRaises(manifest.AuthorizationError):
                    manifest._load_job_lifecycle_authorization(
                        write_private_json(
                            self.directory,
                            f"published-v7-{scenario}.json",
                            document,
                        )
                    )
        # Historical bindings and the earlier v7 policy digest must be rejected.
        # Plan digests come from those exact revisions rather than stale fields
        # pasted onto a current plan.
        stale_revisions = (
            (
                "v5/v4/v8",
                "8",
                "c15ee6d1d46043739d539367f16dd550e0c5b2e53708b5b30083551a42fe9e38",
                {
                    "AND-04": "5be168cf38cfd13288cdbd9536247f1d9d630245c4ab2ed38aa49b0229c04c41",
                    "AND-05": "dddbaa166f5d5b06f109445b199692b7f22fa95ed98ed63871683b9e291263d6",
                },
            ),
            (
                "v5/v4/v7 pre-direct-redirect-policy",
                "7",
                "2f92ec64bc2520e5347eb081c642aa3438452625d4a8a5df7e916f638c2cf5cd",
                {
                    "AND-04": "1f20ff7af9514c792598b41b8c81d96f0ed3b917f79a398f6cdbdbf692e425ec",
                    "AND-05": "8cdad38d64a3ffaa69265c9ea830f5dbb2957b6181e3bab14477a1c26e1177e5",
                },
            ),
            (
                "v3/v3/v4",
                "4",
                "f9ec811db76f245463a93c8260bdd6d347b96071fc3337dccf772f429f416405",
                {
                    "AND-04": "ea7515a7d9cacb862a1057d4712e50f859ecfcab9ebb66c1a0c19d486b1e74f7",
                    "AND-05": "4fdb2e9a8ed1b46afa67ee6ac895f8bd3214e83b8fcc9d7ac9ab9c9c9cfeb9ee",
                },
            ),
            (
                "v2/v2/v3",
                "3",
                "1e15ecbb39072f34043e1721a4099b1826320af06b277a0bd20973035c11366d",
                {
                    "AND-04": "8864bd6afecb75ab8a074fd88f09238124cc527174a215671a42c5e2affad189",
                    "AND-05": "104cea54d798e577e97a1bb5e9c8631c28d775dd6c8a0243c7ab7623f9b89c40",
                },
            ),
            (
                "v4/v3/v5",
                "5",
                "22daf4e6f1de6a17f61523c9680e2491745ee0ece0074eb58966e602d9d99181",
                {
                    "AND-04": "20882c2555dc7050bde3f8f5495e026c2bddeb39ca0096ce5bbc2df096b767fe",
                    "AND-05": "f19fde67ecd9c82e9b492609138210ea04057550646f11a2ff6536357e927700",
                },
            ),
            (
                "v4/v3/v6",
                "6",
                "2ef54c98c518e0625e50c38b1225af96128eee7ed2ffd2524a6c62262c8d5894",
                {
                    "AND-04": "d15692d43b3e840996ddfa24b8f04ea9405c6f6b347ebe11be343e1963381c79",
                    "AND-05": "a289078418a684f22a571f4ebe2e5d5ba98d67b927f8740200dd4fd2a652ad09",
                },
            ),
        )
        for _, _, digest, _ in stale_revisions:
            self.assertNotEqual(digest, contract.JOB_LIFECYCLE_ORACLE_SHA256)
        for scenario in ("AND-04", "AND-05"):
            with self.subTest(scenario=scenario):
                accepted = self._load(_authorization_document(scenario))
                self.assertEqual(
                    accepted.plan_sha256,
                    contract.plan_digest_for_authorization(accepted),
                )
                self.assertEqual(
                    accepted.plan_sha256,
                    {
                        "AND-04": "437698c1128d0bd1096c6a6d87a7776ee048b83a35043723eb5b047b34fb7c81",
                        "AND-05": "cd2a90e18a32856a2c097de5a937816030194a2645cf54187c9e71fc6faa1a04",
                    }[scenario],
                )
                for label, stale_version, stale_digest, stale_plan_digests in stale_revisions:
                    with self.subTest(revision=label):
                        stale = _authorization_document(scenario)
                        stale["plan"]["plan_sha256"] = stale_plan_digests[scenario]
                        for operation in stale["operations"]:
                            operation["arguments"]["oracle_version"] = stale_version
                            operation["arguments"]["oracle_sha256"] = stale_digest
                        with tempfile.TemporaryDirectory() as directory:
                            with self.assertRaises(manifest.AuthorizationError):
                                manifest._load_job_lifecycle_authorization(
                                    write_private_json(
                                        Path(directory),
                                        f"historical-{label.replace('/', '-')}-{scenario}.json",
                                        stale,
                                    )
                                )

    def test_lifecycle_parser_rejects_obsolete_oracle_pins(self):
        obsolete_oracles = (
            (
                "oracle-v8",
                "8",
                "c15ee6d1d46043739d539367f16dd550e0c5b2e53708b5b30083551a42fe9e38",
            ),
            (
                "oracle-v5",
                "5",
                "22daf4e6f1de6a17f61523c9680e2491745ee0ece0074eb58966e602d9d99181",
            ),
            (
                "oracle-v4",
                "4",
                "f9ec811db76f245463a93c8260bdd6d347b96071fc3337dccf772f429f416405",
            ),
            (
                "oracle-v3",
                "3",
                "1e15ecbb39072f34043e1721a4099b1826320af06b277a0bd20973035c11366d",
            ),
        )
        scenarios = (
            contract.JOB_LIFECYCLE_SCENARIO_AND_04,
            contract.JOB_LIFECYCLE_SCENARIO_AND_05,
        )
        for scenario in scenarios:
            spec = next(
                operation
                for operation in contract.JOB_LIFECYCLE_OPERATIONS[scenario]
                if operation.category == OperationCategory.READ_ONLY.value
            )
            current_arguments = contract.operation_arguments(spec)

            def parse(arguments):
                return manifest._parse_job_lifecycle_operation_arguments(
                    arguments,
                    category=OperationCategory(spec.category),
                    phase="qualification",
                    package_name=contract.JOB_LIFECYCLE_QUALIFICATION_PACKAGE,
                )

            with self.subTest(scenario=scenario, oracle="current"):
                self.assertEqual(
                    parse(current_arguments),
                    tuple(sorted(current_arguments.items())),
                )

            for revision, obsolete_version, obsolete_digest in obsolete_oracles:
                with self.subTest(
                    scenario=scenario,
                    revision=revision,
                    field="oracle_version",
                ):
                    stale_version_arguments = dict(current_arguments)
                    stale_version_arguments["oracle_version"] = obsolete_version
                    self.assertEqual(
                        stale_version_arguments["oracle_sha256"],
                        current_arguments["oracle_sha256"],
                    )
                    with self.assertRaises(manifest.AuthorizationError) as raised:
                        parse(stale_version_arguments)
                    self.assertIs(
                        raised.exception.code,
                        manifest.AuthorizationErrorCode.INVALID_VALUE,
                    )

                with self.subTest(
                    scenario=scenario,
                    revision=revision,
                    field="oracle_sha256",
                ):
                    stale_digest_arguments = dict(current_arguments)
                    stale_digest_arguments["oracle_sha256"] = obsolete_digest
                    self.assertEqual(
                        stale_digest_arguments["oracle_version"],
                        current_arguments["oracle_version"],
                    )
                    with self.assertRaises(manifest.AuthorizationError) as raised:
                        parse(stale_digest_arguments)
                    self.assertIs(
                        raised.exception.code,
                        manifest.AuthorizationErrorCode.INVALID_VALUE,
                    )

    def test_lifecycle_authorization_rejects_mismatched_plan_digest(self):
        for scenario in ("AND-04", "AND-05"):
            with self.subTest(scenario=scenario):
                document = _authorization_document(scenario)
                authorization = _load_lifecycle_authorization(self.directory, document)
                self.assertRegex(authorization.plan_sha256, r"^[0-9a-f]{64}$")
                document["plan"]["plan_sha256"] = "0" * 64
                with self.assertRaises(manifest.AuthorizationError):
                    manifest._load_job_lifecycle_authorization(
                        write_private_json(
                            self.directory,
                            f"mismatched-plan-{scenario}.json",
                            document,
                        )
                    )

    def test_owner_approval_rejects_mismatched_authorization_digest(self):
        for scenario in ("AND-04", "AND-05"):
            with self.subTest(scenario=scenario):
                authorization = _load_lifecycle_authorization(
                    self.directory, _authorization_document(scenario)
                )
                approval = approval_document(authorization.canonical_sha256)
                approval["authorization_sha256"] = "0" * 64
                approval["valid_from_utc"] = authorization.issued_at.strftime(
                    "%Y-%m-%dT%H:%M:%SZ"
                )
                approval["valid_until_utc"] = authorization.session_deadline.strftime(
                    "%Y-%m-%dT%H:%M:%SZ"
                )
                with self.assertRaises(manifest.ApprovalError):
                    manifest.load_owner_approval(
                        write_private_json(
                            self.directory,
                            f"mismatched-approval-{scenario}.json",
                            approval,
                        ),
                        authorization,
                        now=NOW,
                    )

    def test_baseline_schema_is_exact_for_each_profile(self):
        legacy = {
            "library_fixture_ids": ["fixture"],
            "job_states": [],
            "pending_cleanup_ids": [],
        }
        for profile in (
            manifest._AuthorizationProfile.LEGACY,
            manifest._AuthorizationProfile.LIBRARY_INTERACTIONS,
        ):
            with self.subTest(profile=profile):
                parsed = manifest._parse_baseline(
                    legacy,
                    manifest.AuthorizationError,
                    profile,
                )
                self.assertEqual(parsed.root_id, "")
                self.assertEqual(parsed.pending_restoration_ids, ())
                with self.assertRaises(manifest.AuthorizationError):
                    manifest._parse_baseline(
                        {
                            **legacy,
                            "root_id": "root",
                            "pending_restoration_ids": [],
                        },
                        manifest.AuthorizationError,
                        profile,
                    )
        with self.assertRaises(manifest.AuthorizationError):
            manifest._parse_baseline(
                legacy,
                manifest.AuthorizationError,
                manifest._AuthorizationProfile.JOB_LIFECYCLE,
            )
        lifecycle = {
            **legacy,
            "root_id": "root",
            "pending_restoration_ids": [],
        }
        parsed = manifest._parse_baseline(
            lifecycle,
            manifest.AuthorizationError,
            manifest._AuthorizationProfile.JOB_LIFECYCLE,
        )
        self.assertEqual(parsed.root_id, "root")
        self.assertEqual(parsed.pending_restoration_ids, ())

    def test_lifecycle_baseline_requires_expanded_fields(self):
        document = _authorization_document()
        del document["state"]["no_reset_baseline"]["root_id"]
        with self.assertRaises(manifest.AuthorizationError):
            self._load(document)

    def test_plan_digest_mismatch_is_rejected(self):
        document = _authorization_document()
        document["plan"]["plan_sha256"] = "0" * 64
        with self.assertRaises(manifest.AuthorizationError):
            manifest._load_job_lifecycle_authorization(
                write_private_json(self.directory, "bad-plan.json", document)
            )

    def test_legacy_loader_rejects_lifecycle_scenario(self):
        document = _authorization_document()
        provisional = manifest._load_authorization_for_profile(
            write_private_json(self.directory, "legacy-draft.json", document),
            manifest._AuthorizationProfile.JOB_LIFECYCLE,
        )
        document["plan"]["plan_sha256"] = contract.plan_digest_for_authorization(
            provisional
        )
        with self.assertRaises(manifest.AuthorizationError):
            manifest.load_authorization(
                write_private_json(self.directory, "legacy.json", document)
            )

    def test_reordered_operation_is_rejected(self):
        document = _authorization_document()
        document["operations"][3], document["operations"][4] = (
            document["operations"][4],
            document["operations"][3],
        )
        provisional = manifest._load_authorization_for_profile(
            write_private_json(self.directory, "draft.json", document),
            manifest._AuthorizationProfile.JOB_LIFECYCLE,
        )
        document["plan"]["plan_sha256"] = contract.plan_digest_for_authorization(
            provisional
        )
        with self.assertRaises(manifest.AuthorizationError):
            manifest._load_job_lifecycle_authorization(
                write_private_json(self.directory, "reordered.json", document)
            )

    def test_missing_extra_or_invented_operations_are_rejected(self):
        missing = _authorization_document()
        missing["operations"].pop()
        with self.assertRaises(manifest.AuthorizationError):
            self._load(missing)

        extra = _authorization_document()
        extra["operations"].append(dict(extra["operations"][-1]))
        with self.assertRaises(manifest.AuthorizationError):
            self._load(extra)

        invented = _authorization_document()
        invented["operations"][1]["arguments"]["action"] = "open_retry_successor_detail"
        with self.assertRaises(manifest.AuthorizationError):
            self._load(invented)

    def test_old_37_operation_and_05_document_is_rejected(self):
        document = _authorization_document("AND-05")
        document["operations"] = document["operations"][:37]
        with self.assertRaises(manifest.AuthorizationError):
            self._load(document)

    def test_authorization_digest_and_plan_digest_are_distinct_bindings(self):
        authorization = self._load(_authorization_document())
        approval = _load_approval(self.directory, authorization)
        self.assertEqual(approval.authorization_sha256, authorization.canonical_sha256)
        self.assertNotEqual(authorization.plan_sha256, authorization.canonical_sha256)

        document = _authorization_document()
        document["plan"]["plan_sha256"] = authorization.canonical_sha256
        with self.assertRaises(manifest.AuthorizationError):
            manifest._load_job_lifecycle_authorization(
                write_private_json(self.directory, "wrong-plan.json", document)
            )

    def test_cleanup_deadline_must_equal_the_pinned_closure_window(self):
        document = _authorization_document()
        document["cleanup_deadline_utc"] = (
            datetime.strptime(
                document["session_deadline_utc"], "%Y-%m-%dT%H:%M:%SZ"
            ).replace(tzinfo=timezone.utc)
            + timedelta(seconds=contract.JOB_LIFECYCLE_CLOSURE_SECONDS + 1)
        ).strftime("%Y-%m-%dT%H:%M:%SZ")
        with self.assertRaises(manifest.AuthorizationError):
            self._load(document)

    def test_session_deadline_must_equal_the_pinned_scenario_span(self):
        document = _authorization_document()
        document["session_deadline_utc"] = (
            datetime.strptime(
                document["issued_at_utc"], "%Y-%m-%dT%H:%M:%SZ"
            ).replace(tzinfo=timezone.utc)
            + timedelta(
                seconds=contract.JOB_LIFECYCLE_SESSION_SECONDS["AND-04"] + 1
            )
        ).strftime("%Y-%m-%dT%H:%M:%SZ")
        with self.assertRaises(manifest.AuthorizationError):
            self._load(document)


class AdmissionLifecycleTests(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.directory = Path(self.temporary_directory.name)
        self.registry_patch = mock.patch.object(
            admission,
            "_SESSION_REGISTRY_PATH",
            self.directory / "host-state" / "session-registry.json",
            create=True,
        )
        self.registry_patch.start()
        self.addCleanup(self.registry_patch.stop)

    def _admitted(
        self,
        scenario="AND-04",
        *,
        transport=None,
        monotonic=None,
        authorization_id=None,
    ):
        document = _authorization_document(scenario)
        if authorization_id is not None:
            document["authorization_id"] = authorization_id
        authorization = _load_lifecycle_authorization(self.directory, document)
        approval = _load_approval(self.directory, authorization)
        transport = transport or FakeBaselineTransport()
        result = admission._admit_job_lifecycle_session(
            authorization,
            approval,
            _artifact(),
            transport,
            now=NOW,
            monotonic=monotonic,
        )
        return result, authorization, approval

    def _result_for(
        self,
        *,
        baseline=None,
        artifact=None,
        now=NOW,
        valid_until=None,
        authorization_id=None,
        scenario="AND-04",
        transport=None,
        monotonic=None,
    ):
        document = _authorization_document(scenario)
        if authorization_id is not None:
            document["authorization_id"] = authorization_id
        authorization = _load_lifecycle_authorization(self.directory, document)
        approval = _load_approval(
            self.directory,
            authorization,
            valid_until=valid_until,
        )
        transport = transport or FakeBaselineTransport(baseline or _baseline())
        return admission._admit_job_lifecycle_session(
            authorization,
            approval,
            artifact or _artifact(),
            transport,
            now=now,
            monotonic=monotonic,
        )

    def test_admits_valid_no_reset_baseline(self):
        result, _, _ = self._admitted()
        self.assertEqual(result.status, admission.AdmissionStatus.ADMITTED)
        self.assertIsNotNone(result.session)

    def test_both_scenarios_admit_valid_no_reset_baseline(self):
        for scenario in ("AND-04", "AND-05"):
            with self.subTest(scenario=scenario):
                clock = _Clock(values=[0.0, 0.0])
                result, _, _ = self._admitted(
                    scenario,
                    monotonic=clock.monotonic,
                    authorization_id=f"session-{scenario}",
                )
                self.assertEqual(result.status, admission.AdmissionStatus.ADMITTED)
                self.assertIsNotNone(result.session)

    def test_baseline_observation_within_timeout_is_admitted(self):
        clock = _Clock(values=[100.0, 129.999])
        result = self._result_for(monotonic=clock.monotonic)
        self.assertEqual(result.status, admission.AdmissionStatus.ADMITTED)
        self.assertIsNotNone(result.session)

    def test_baseline_observation_after_timeout_blocks(self):
        clock = _Clock(values=[100.0, 130.001])
        result = self._result_for(monotonic=clock.monotonic)
        self.assertEqual(result.status, admission.AdmissionStatus.BLOCKED)
        self.assertEqual(
            result.code,
            admission.AdmissionCode.OBSERVATION_UNAVAILABLE,
        )
        self.assertIsNone(result.session)

    def test_baseline_observation_at_timeout_boundary_blocks(self):
        clock = _Clock(values=[100.0, 130.0])
        result = self._result_for(monotonic=clock.monotonic)
        self.assertEqual(result.status, admission.AdmissionStatus.BLOCKED)
        self.assertEqual(
            result.code,
            admission.AdmissionCode.OBSERVATION_UNAVAILABLE,
        )
        self.assertIsNone(result.session)

    def test_baseline_observer_failure_and_unavailable_result_block(self):
        class RaisingTransport:
            def observe_baseline(self, timeout):
                raise RuntimeError("observer unavailable")

        class NoneTransport:
            def observe_baseline(self, timeout):
                return None

        for label, transport in (
            ("raises", RaisingTransport()),
            ("returns-none", NoneTransport()),
        ):
            with self.subTest(label=label):
                result = self._result_for(transport=transport)
                self.assertEqual(result.status, admission.AdmissionStatus.BLOCKED)
                self.assertEqual(
                    result.code,
                    admission.AdmissionCode.OBSERVATION_UNAVAILABLE,
                )

    def test_timed_out_observation_does_not_consume_capability(self):
        document = _authorization_document()
        authorization = _load_lifecycle_authorization(self.directory, document)
        approval = _load_approval(self.directory, authorization)
        timed_out_clock = _Clock(values=[0.0, 31.0])
        timed_out = admission._admit_job_lifecycle_session(
            authorization,
            approval,
            _artifact(),
            FakeBaselineTransport(),
            now=NOW,
            monotonic=timed_out_clock.monotonic,
        )
        self.assertEqual(timed_out.status, admission.AdmissionStatus.BLOCKED)
        self.assertIsNone(timed_out.session)

        admitted_clock = _Clock(values=[0.0, 1.0])
        admitted = admission._admit_job_lifecycle_session(
            authorization,
            approval,
            _artifact(),
            FakeBaselineTransport(),
            now=NOW,
            monotonic=admitted_clock.monotonic,
        )
        self.assertEqual(admitted.status, admission.AdmissionStatus.ADMITTED)
        self.assertIsNotNone(admitted.session)

    def test_late_admission_is_rejected(self):
        result = self._result_for(now=NOW + timedelta(seconds=1))
        self.assertEqual(result.status, admission.AdmissionStatus.BLOCKED)
        self.assertEqual(result.code, admission.AdmissionCode.SESSION_EXPIRED)

    def test_second_admission_is_blocked(self):
        result, authorization, approval = self._admitted()
        self.assertEqual(result.status, admission.AdmissionStatus.ADMITTED)
        again = admission._admit_job_lifecycle_session(
            authorization,
            approval,
            _artifact(),
            FakeBaselineTransport(),
            now=NOW,
        )
        self.assertEqual(again.status, admission.AdmissionStatus.BLOCKED)

    def test_approval_bound_to_another_authorization_is_rejected(self):
        document = _authorization_document()
        authorization = _load_lifecycle_authorization(self.directory, document)
        other_document = _authorization_document()
        other_document["authorization_id"] = "session-synthetic-other"
        other = _load_lifecycle_authorization(self.directory, other_document)
        approval = _load_approval(self.directory, other)
        result = admission._admit_job_lifecycle_session(
            authorization, approval, _artifact(), FakeBaselineTransport(), now=NOW
        )
        self.assertEqual(result.status, admission.AdmissionStatus.BLOCKED)

    def test_membership_mismatch_blocks(self):
        result, _, _ = self._admitted(
            transport=FakeBaselineTransport(_baseline(library_membership_count=2))
        )
        self.assertEqual(result.status, admission.AdmissionStatus.BLOCKED)

    def test_pending_cleanup_blocks(self):
        result, _, _ = self._admitted(
            transport=FakeBaselineTransport(_baseline(pending_cleanup_refs=("cleanup",)))
        )
        self.assertEqual(result.status, admission.AdmissionStatus.BLOCKED)

    def test_interference_blocks(self):
        result, _, _ = self._admitted(
            transport=FakeBaselineTransport(_baseline(interference_free=False))
        )
        self.assertEqual(result.status, admission.AdmissionStatus.BLOCKED)

    def test_short_session_rejects_positive_reserve(self):
        document = _authorization_document(
            "AND-05", session_seconds=contract.JOB_LIFECYCLE_SESSION_SECONDS["AND-05"] - 1
        )
        with self.assertRaises(manifest.AuthorizationError):
            _load_lifecycle_authorization(self.directory, document)

    def test_artifact_and_source_identity_mismatches_block(self):
        cases = {
            "version": replace(_artifact(), version_code=999),
            "package": replace(_artifact(), package_name="com.example.foreign"),
            "apk": replace(_artifact(), apk_sha256="9" * 64),
            "certificate": replace(_artifact(), certificate_sha256="9" * 64),
            "revision": replace(_artifact(), source_revision="9" * 40),
            "signature": replace(_artifact(), signature_verified=False),
            "signers": replace(_artifact(), signer_count=2),
            "permissions": replace(_artifact(), declared_permissions=frozenset()),
            "dirty": replace(_artifact(), source_dirty=True),
        }
        for name, artifact in cases.items():
            with self.subTest(case=name):
                result = self._result_for(
                    artifact=artifact,
                    authorization_id=f"session-artifact-{name}",
                )
                self.assertEqual(result.status, admission.AdmissionStatus.BLOCKED)

    def test_no_reset_baseline_matrix_blocks_until_every_fact_matches(self):
        cases = {
            "serial-count": _baseline(connected_serials=(_SERIAL, "other")),
            "serial-target": _baseline(connected_serials=("other",)),
            "api": _baseline(android_api_level=20),
            "abi": _baseline(abi="x86_64"),
            "capabilities": _baseline(capabilities=frozenset()),
            "package": _baseline(package_name="com.example.foreign"),
            "version": _baseline(version_code=999),
            "certificate": _baseline(certificate_sha256="9" * 64),
            "artifact": _baseline(artifact_sha256="9" * 64),
            "foreground": _baseline(foreground_package="com.android.launcher3"),
            "interference": _baseline(interference_free=None),
            "storage": _baseline(available_storage_bytes=None),
            "membership": _baseline(library_membership_count=0),
            "membership-count": _baseline(library_membership_count=2),
            "membership-ids": _baseline(
                library_membership_ids=("different-fixture",)
            ),
            "membership-duplicate": _baseline(
                library_membership_count=2,
                library_membership_ids=(
                    "fixture-synthetic",
                    "fixture-synthetic",
                ),
            ),
            "root": _baseline(selected_root_ref=""),
            "root-id": _baseline(selected_root_id="different-root"),
            "job-states": _baseline(
                job_states=(("job-private", "failed"),)
            ),
            "scan": _baseline(last_scan_state="unknown"),
            "scan-type": _baseline(last_scan_state=[]),
            "active-row": _baseline(active_refresh_row_count=1),
            "history": _baseline(jobs_history_complete=False),
            "terminal-count": _baseline(
                terminal_refresh_run_refs=("terminal-ref",)
            ),
        "terminal-duplicate": _baseline(
            visible_refresh_row_count=2,
            terminal_refresh_run_refs=("terminal-ref", "terminal-ref"),
        ),
            "cleanup": _baseline(pending_cleanup_refs=("cleanup",)),
            "restoration": _baseline(pending_restoration_refs=("restore",)),
            "refresh-control": _baseline(refresh_control_present=False),
            "jobs-nav": _baseline(jobs_navigation_present=False),
            "task": _baseline(task_continuity_ref=""),
            "observer": _baseline(observer_ref=""),
            "receipt": _baseline(observer_receipt_sha256="not-a-digest"),
        }
        for name, baseline in cases.items():
            with self.subTest(case=name):
                result = self._result_for(
                    baseline=baseline,
                    authorization_id=f"session-baseline-{name}",
                )
                self.assertEqual(result.status, admission.AdmissionStatus.BLOCKED)

    def test_invalid_baseline_does_not_consume_owner_approval(self):
        document = _authorization_document()
        authorization = _load_lifecycle_authorization(self.directory, document)
        approval = _load_approval(self.directory, authorization)
        invalid = admission._admit_job_lifecycle_session(
            authorization,
            approval,
            _artifact(),
            FakeBaselineTransport(
                _baseline(library_membership_ids=("different-fixture",))
            ),
            now=NOW,
        )
        self.assertEqual(invalid.status, admission.AdmissionStatus.BLOCKED)
        admitted = admission._admit_job_lifecycle_session(
            authorization,
            approval,
            _artifact(),
            FakeBaselineTransport(),
            now=NOW,
        )
        self.assertEqual(admitted.status, admission.AdmissionStatus.ADMITTED)

    def test_expired_approval_after_observation_does_not_consume_claim(self):
        document = _authorization_document()
        authorization = _load_lifecycle_authorization(self.directory, document)
        approval = _load_approval(self.directory, authorization)
        expired = admission._admit_job_lifecycle_session(
            authorization,
            approval,
            _artifact(),
            FakeBaselineTransport(),
            now=NOW,
            clock=lambda: NOW + timedelta(hours=2),
        )
        self.assertEqual(expired.status, admission.AdmissionStatus.BLOCKED)
        self.assertEqual(expired.code, admission.AdmissionCode.APPROVAL_INVALID)
        admitted = admission._admit_job_lifecycle_session(
            authorization,
            approval,
            _artifact(),
            FakeBaselineTransport(),
            now=NOW,
        )
        self.assertEqual(admitted.status, admission.AdmissionStatus.ADMITTED)

    def test_latest_admission_bound_is_rechecked_after_observation(self):
        document = _authorization_document()
        authorization = _load_lifecycle_authorization(self.directory, document)
        approval = _load_approval(self.directory, authorization)
        result = admission._admit_job_lifecycle_session(
            authorization,
            approval,
            _artifact(),
            FakeBaselineTransport(),
            now=NOW,
            clock=lambda: NOW + timedelta(
                seconds=contract.JOB_LIFECYCLE_LATEST_ADMISSION_SECONDS + 1
            ),
        )
        self.assertEqual(result.status, admission.AdmissionStatus.BLOCKED)
        self.assertEqual(result.code, admission.AdmissionCode.SESSION_EXPIRED)

    def test_concurrent_claim_admits_at_most_one_session(self):
        import threading

        document = _authorization_document()
        authorization = _load_lifecycle_authorization(self.directory, document)
        approval = _load_approval(self.directory, authorization)
        barrier = threading.Barrier(2)
        results = []

        def admit():
            barrier.wait()
            results.append(
                admission._admit_job_lifecycle_session(
                    authorization,
                    approval,
                    _artifact(),
                    FakeBaselineTransport(),
                    now=NOW,
                )
            )

        threads = [threading.Thread(target=admit) for _ in range(2)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()

        self.assertEqual(
            sum(
                result.status is admission.AdmissionStatus.ADMITTED
                for result in results
            ),
            1,
        )
        self.assertIn(
            admission.AdmissionCode.SESSION_ALREADY_USED,
            {result.code for result in results},
        )

    def test_expired_approval_and_session_deadline_block(self):
        expired = self._result_for(
            valid_until=NOW + timedelta(seconds=1),
            now=NOW + timedelta(seconds=1),
            authorization_id="session-expired-approval",
        )
        self.assertEqual(expired.status, admission.AdmissionStatus.BLOCKED)

        at_deadline = self._result_for(
            now=datetime(2030, 1, 1, 0, 15, tzinfo=timezone.utc),
            authorization_id="session-expired-deadline",
        )
        self.assertEqual(at_deadline.status, admission.AdmissionStatus.BLOCKED)


class OracleTests(unittest.TestCase):
    def test_refresh_progress_uses_parent_fields_only(self):
        result = oracle.validate_refresh_progress(_progress(2))
        self.assertEqual(result.outcome, evidence.AssertionOutcome.PASSED)
        missing = oracle.validate_refresh_progress(
            contract.RefreshProgressFacts(None, None, None, "library_refresh.queued", None)
        )
        self.assertEqual(missing.outcome, evidence.AssertionOutcome.BLOCKED)

    def test_progress_contradiction_is_failed(self):
        result = oracle.validate_refresh_progress(_progress(4, total=3))
        self.assertEqual(result.outcome, evidence.AssertionOutcome.FAILED)

    def test_progress_pair_requires_change(self):
        result = oracle.validate_active_progress_pair(_progress(1), _progress(1))
        self.assertEqual(result.outcome, evidence.AssertionOutcome.BLOCKED)
        result = oracle.validate_active_progress_pair(_progress(1), _progress(2))
        self.assertEqual(result.outcome, evidence.AssertionOutcome.PASSED)
        first_invalid = oracle.validate_active_progress_pair(None, _progress(1))
        self.assertEqual(first_invalid.code, "refresh_progress_unavailable")
        second_invalid = oracle.validate_active_progress_pair(_progress(1), None)
        self.assertEqual(second_invalid.code, "refresh_progress_unavailable")

    def test_completed_state_does_not_prove_process_loss(self):
        result = oracle.recovery_consistency(
            contract.RecoveryState.COMPLETED,
            force_stop_observed=True,
            durable_cancellation_intent=False,
        )
        self.assertEqual(result.outcome, evidence.AssertionOutcome.BLOCKED)

    def test_cancelled_requires_durable_intent(self):
        result = oracle.recovery_consistency(
            contract.RecoveryState.CANCELLED,
            force_stop_observed=True,
            durable_cancellation_intent=False,
        )
        self.assertEqual(result.outcome, evidence.AssertionOutcome.FAILED)

    def test_abandoned_after_observed_stop_passes_consistency(self):
        result = oracle.recovery_consistency(
            contract.RecoveryState.ABANDONED,
            force_stop_observed=True,
            durable_cancellation_intent=False,
        )
        self.assertEqual(result.outcome, evidence.AssertionOutcome.PASSED)

    def test_state_oracles_require_exact_recovery_enum_values(self):
        self.assertEqual(
            oracle.retry_eligibility("failed").outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        self.assertEqual(
            oracle.recovery_consistency(
                "active",
                force_stop_observed=True,
                durable_cancellation_intent=False,
            ).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        self.assertEqual(
            _evaluate_retry_outcome(
                source_state="failed",
                dispatched=True,
                already_retried=False,
                parent_ref="parent",
                frozen_scope_ref="scope-ref",
                successor_identity=_identity(
                    "parent",
                    state=contract.RecoveryState.FAILED,
                    source="parent",
                    successor="successor",
                    retry_lookup=True,
                    lookup_source="parent",
                ),
            ).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        self.assertEqual(
            oracle.terminal_successor(_detail("successor", "completed")).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )

    def test_process_observation_validation_preserves_categories(self):
        valid = _process(contract.ProcessState.PRESENT, QUALIFICATION_PACKAGE)
        self.assertEqual(
            oracle.validate_process_observation(
                valid,
                expected_state=contract.ProcessState.PRESENT,
                expected_package=QUALIFICATION_PACKAGE,
            ).outcome,
            evidence.AssertionOutcome.PASSED,
        )
        malformed_state = replace(valid, process_state="present")
        missing_observer = replace(valid, observer_ref=None)
        missing_package = replace(valid, package_name=None)
        foreign_package = replace(valid, package_name="com.example.foreign")
        contradictory_state = replace(valid, process_state=contract.ProcessState.ABSENT)
        for observation in (malformed_state, missing_observer, missing_package):
            with self.subTest(observation=observation):
                self.assertEqual(
                    oracle.validate_process_observation(
                        observation,
                        expected_state=contract.ProcessState.PRESENT,
                        expected_package=QUALIFICATION_PACKAGE,
                    ).outcome,
                    evidence.AssertionOutcome.BLOCKED,
                )
        for observation in (foreign_package, contradictory_state):
            with self.subTest(observation=observation):
                self.assertEqual(
                    oracle.validate_process_observation(
                        observation,
                        expected_state=contract.ProcessState.PRESENT,
                        expected_package=QUALIFICATION_PACKAGE,
                    ).outcome,
                    evidence.AssertionOutcome.FAILED,
                )

    def test_interrupted_successor_is_terminal_but_cannot_pass_retry(self):
        state = contract.RecoveryState.INTERRUPTED
        self.assertEqual(
            oracle.retry_eligibility(state).outcome,
            evidence.AssertionOutcome.NOT_RUN,
        )
        self.assertEqual(
            oracle.recovery_consistency(
                state,
                force_stop_observed=True,
                durable_cancellation_intent=False,
            ).outcome,
            evidence.AssertionOutcome.FAILED,
        )
        self.assertEqual(
            oracle.terminal_successor(_detail("successor", state)).outcome,
            evidence.AssertionOutcome.PASSED,
        )
        self.assertEqual(
            oracle.retry_success_acceptance(
                state,
                accepted_states=frozenset({state}),
            ).outcome,
            evidence.AssertionOutcome.FAILED,
        )

    def test_retry_eligibility_and_already_retried(self):
        self.assertEqual(
            oracle.retry_eligibility(contract.RecoveryState.FAILED).outcome,
            evidence.AssertionOutcome.PASSED,
        )
        self.assertEqual(
            oracle.retry_eligibility(contract.RecoveryState.COMPLETED).outcome,
            evidence.AssertionOutcome.NOT_RUN,
        )
        result = _evaluate_retry_outcome(
            source_state=contract.RecoveryState.FAILED,
            dispatched=True,
            already_retried=True,
            parent_ref="parent",
            frozen_scope_ref="scope-ref",
            successor_identity=None,
        )
        self.assertEqual(result.outcome, evidence.AssertionOutcome.BLOCKED)
        self.assertEqual(
            oracle.retry_eligibility("unknown").outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        self.assertEqual(
            oracle.recovery_consistency(
                "unknown",
                force_stop_observed=True,
                durable_cancellation_intent=False,
            ).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )

    def test_latency_requires_owner_rule_and_authorization(self):
        result = oracle.evaluate_latency(None, (), active_overlap_confirmed=False)
        self.assertEqual(result.outcome, evidence.AssertionOutcome.BLOCKED)
        self.assertEqual(
            oracle.latency_execution_status().outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        self.assertEqual(oracle.nearest_rank_percentile_95(tuple(range(1, 21))), 19)

    def test_progress_validation_matrix(self):
        blocked = (
            contract.RefreshProgressFacts(
                None, None, None, "library_refresh.queued", None, "parent-run"
            ),
            contract.RefreshProgressFacts(
                "", 0, 1, "library_refresh.running", 0, "parent-run"
            ),
            contract.RefreshProgressFacts(
                "scan", -1, 1, "library_refresh.running", 0, "parent-run"
            ),
            contract.RefreshProgressFacts(
                "scan", 0, -1, "library_refresh.running", 0, "parent-run"
            ),
            contract.RefreshProgressFacts(
                "scan", 0, 1, "not-a-refresh-key", 0, "parent-run"
            ),
            contract.RefreshProgressFacts(
                "scan", 0, 1, "library_refresh.running", -1, "parent-run"
            ),
            contract.RefreshProgressFacts(
                "scan", 0, 1, None, 0, "parent-run"
            ),
            contract.RefreshProgressFacts(
                "scan", 0, 1, "library_refresh.running", 0, None
            ),
        )
        for facts in blocked:
            with self.subTest(facts=facts):
                self.assertEqual(
                    oracle.validate_refresh_progress(facts).outcome,
                    evidence.AssertionOutcome.BLOCKED,
                )
        self.assertEqual(
            oracle.validate_refresh_progress(
                contract.RefreshProgressFacts(
                    "scan", 2, 1, "library_refresh.running", 0, "parent-run"
                )
            ).outcome,
            evidence.AssertionOutcome.FAILED,
        )
        self.assertEqual(
            oracle.validate_active_progress_pair(
                _progress(1),
                contract.RefreshProgressFacts(
                    "enrich", 1, 3, "library_refresh.enriching", 0, "parent-run"
                ),
            ).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )

    def test_issue_count_without_committed_parent_progress_is_blocked(self):
        issues_only = contract.RefreshProgressFacts(
            "scan",
            None,
            None,
            "library_refresh.failed",
            2,
            "parent-run",
        )
        self.assertFalse(issues_only.has_committed_progress())
        self.assertEqual(
            oracle.validate_refresh_progress(issues_only).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        self.assertEqual(
            oracle.validate_active_progress_pair(_progress(2), _progress(1)).outcome,
            evidence.AssertionOutcome.FAILED,
        )
        self.assertEqual(
            oracle.validate_active_progress_pair(
                _progress(1),
                _progress(1, phase="enrich"),
            ).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        self.assertEqual(
            oracle.validate_active_progress_pair(
                _progress(1),
                _progress(1, parent="other-parent"),
            ).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        self.assertEqual(
            oracle.validate_active_progress_pair(
                _progress(1),
                _progress(2),
                expected_parent_ref="parent-run",
            ).outcome,
            evidence.AssertionOutcome.PASSED,
        )
        self.assertEqual(
            oracle.validate_active_progress_pair(
                _progress(1),
                _progress(2),
                expected_parent_ref="different-parent",
            ).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        self.assertFalse(
            contract.RefreshProgressFacts(
                "scan", 0, 3, "library_refresh.running", 0, "parent-run"
            ).has_committed_progress()
        )
        self.assertEqual(
            oracle.validate_active_progress_pair(
                _progress(1),
                replace(
                    _progress(1),
                    status_key="library_refresh.enriching",
                    issue_count=2,
                ),
            ).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )

    def test_identity_and_process_validation_matrix(self):
        self.assertEqual(
            oracle.validate_identity(None).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        self.assertEqual(
            oracle.validate_identity(
                _identity("parent", scan_run_ids=())
            ).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        self.assertEqual(
            oracle.validate_identity(
                _identity("parent", source="parent", successor="parent"),
                retry=True,
            ).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        self.assertEqual(
            oracle.validate_identity(
                _identity("parent", source="parent", successor="successor"),
                retry=True,
            ).outcome,
            evidence.AssertionOutcome.PASSED,
        )
        self.assertEqual(
            oracle.validate_process_observation(
                None,
                expected_state=contract.ProcessState.PRESENT,
                expected_package=QUALIFICATION_PACKAGE,
            ).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        self.assertEqual(
            oracle.validate_process_observation(
                _process(contract.ProcessState.UNKNOWN, QUALIFICATION_PACKAGE),
                expected_state=contract.ProcessState.PRESENT,
                expected_package=QUALIFICATION_PACKAGE,
            ).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        self.assertEqual(
            oracle.validate_process_observation(
                _process(contract.ProcessState.PRESENT, QUALIFICATION_PACKAGE),
                expected_state=contract.ProcessState.ABSENT,
                expected_package=QUALIFICATION_PACKAGE,
            ).outcome,
            evidence.AssertionOutcome.FAILED,
        )
        missing_observer = replace(
            _process(contract.ProcessState.PRESENT, QUALIFICATION_PACKAGE),
            observer_ref="",
        )
        self.assertEqual(
            oracle.validate_process_observation(
                missing_observer,
                expected_state=contract.ProcessState.PRESENT,
                expected_package=QUALIFICATION_PACKAGE,
            ).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )

    def test_recovery_child_state_precedence(self):
        child = contract.LibraryScanChildCompletion
        cases = (
            ((child.COMPLETE, child.CANCELLED), 2, 2, contract.RecoveryState.CANCELLED),
            ((child.COMPLETE, child.ABANDONED), 2, 2, contract.RecoveryState.ABANDONED),
            ((child.COMPLETE, child.COMPLETE), 2, 2, contract.RecoveryState.COMPLETED),
            ((child.COMPLETE, child.PARTIAL), 2, 2, contract.RecoveryState.COMPLETED_WITH_ISSUES),
            ((child.PARTIAL, child.PARTIAL), 2, 2, contract.RecoveryState.COMPLETED_WITH_ISSUES),
            ((child.COMPLETE, child.FAILED), 2, 2, contract.RecoveryState.COMPLETED_WITH_ISSUES),
            ((child.FAILED, child.FAILED), 2, 2, contract.RecoveryState.FAILED),
            ((child.FAILED,), 2, 1, contract.RecoveryState.FAILED),
            ((child.PARTIAL,), 2, 1, contract.RecoveryState.COMPLETED_WITH_ISSUES),
            ((child.COMPLETE,), 2, 1, contract.RecoveryState.COMPLETED_WITH_ISSUES),
            ((child.COMPLETE, child.COMPLETE), 3, 2, contract.RecoveryState.COMPLETED_WITH_ISSUES),
            ((), 1, 1, contract.RecoveryState.FAILED),
            ((), 0, 0, contract.RecoveryState.COMPLETED),
        )
        for children, requested, admitted, expected in cases:
            with self.subTest(scan_run_ids=children, requested=requested, admitted=admitted):
                self.assertIs(
                    oracle.classify_recovery_child_states(
                        children,
                        requested_count=requested,
                        admitted_count=admitted,
                    ),
                    expected,
                )
        with self.assertRaises(ValueError):
            oracle.classify_recovery_child_states(
                ("completed",),
                requested_count=1,
                admitted_count=1,
            )

    def test_recovery_consistency_matrix(self):
        failed = (
            (contract.RecoveryState.INTERRUPTED, True, False),
            (contract.RecoveryState.ACTIVE, True, False),
            (contract.RecoveryState.CANCELLED, True, False),
        )
        for state, stopped, intent in failed:
            with self.subTest(state=state):
                self.assertEqual(
                    oracle.recovery_consistency(
                        state,
                        force_stop_observed=stopped,
                        durable_cancellation_intent=intent,
                    ).outcome,
                    evidence.AssertionOutcome.FAILED,
                )
        self.assertEqual(
            oracle.recovery_consistency(
                contract.RecoveryState.FAILED,
                force_stop_observed=False,
                durable_cancellation_intent=False,
            ).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        for state in (
            contract.RecoveryState.FAILED,
            contract.RecoveryState.CANCELLED,
            contract.RecoveryState.ABANDONED,
        ):
            with self.subTest(state=state):
                self.assertEqual(
                    oracle.recovery_consistency(
                        state,
                        force_stop_observed=True,
                        durable_cancellation_intent=True,
                    ).outcome,
                    evidence.AssertionOutcome.PASSED,
                )

    def test_terminal_recovery_consistency_is_not_process_loss_proof(self):
        for state in (
            contract.RecoveryState.COMPLETED,
            contract.RecoveryState.COMPLETED_WITH_ISSUES,
        ):
            with self.subTest(state=state):
                result = oracle.recovery_consistency(
                    state,
                    force_stop_observed=True,
                    durable_cancellation_intent=False,
                )
                self.assertEqual(result.outcome, evidence.AssertionOutcome.BLOCKED)
                self.assertEqual(
                    result.code,
                    "terminal_before_process_loss_proven",
                )
                self.assertEqual(
                    oracle.recovery_terminal_consistency(state).outcome,
                    evidence.AssertionOutcome.PASSED,
                )
        self.assertEqual(
            oracle.recovery_terminal_consistency(
                contract.RecoveryState.FAILED
            ).outcome,
            evidence.AssertionOutcome.NOT_RUN,
        )
        self.assertEqual(
            oracle.recovery_terminal_consistency("completed").outcome,
            evidence.AssertionOutcome.BLOCKED,
        )

    def test_retry_outcome_matrix(self):
        self.assertEqual(
            _evaluate_retry_outcome(
                source_state=contract.RecoveryState.COMPLETED,
                dispatched=False,
                already_retried=False,
                parent_ref="parent",
                frozen_scope_ref="scope-ref",
                successor_identity=None,
            ).outcome,
            evidence.AssertionOutcome.NOT_RUN,
        )
        self.assertEqual(
            _evaluate_retry_outcome(
                source_state=contract.RecoveryState.COMPLETED,
                dispatched=True,
                already_retried=False,
                parent_ref="parent",
                frozen_scope_ref="scope-ref",
                successor_identity=None,
            ).outcome,
            evidence.AssertionOutcome.FAILED,
        )
        self.assertEqual(
            _evaluate_retry_outcome(
                source_state=contract.RecoveryState.FAILED,
                dispatched=True,
                already_retried=True,
                parent_ref="parent",
                frozen_scope_ref="scope-ref",
                successor_identity=None,
            ).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        self.assertEqual(
            _evaluate_retry_outcome(
                source_state=contract.RecoveryState.FAILED,
                dispatched=False,
                already_retried=False,
                parent_ref="parent",
                frozen_scope_ref="scope-ref",
                successor_identity=None,
            ).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        self.assertEqual(
            _evaluate_retry_outcome(
                source_state=contract.RecoveryState.FAILED,
                dispatched=True,
                already_retried=False,
                parent_ref="parent",
                frozen_scope_ref="scope-ref",
                successor_identity=None,
            ).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        self.assertEqual(
            _evaluate_retry_outcome(
                source_state=contract.RecoveryState.FAILED,
                dispatched=True,
                already_retried=False,
                parent_ref="parent",
                frozen_scope_ref="scope-ref",
                successor_identity=_identity(None, scan_run_ids=()),
            ).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        self.assertEqual(
            _evaluate_retry_outcome(
                source_state=contract.RecoveryState.FAILED,
                dispatched=True,
                already_retried=False,
                parent_ref="parent",
                frozen_scope_ref="scope-ref",
                successor_identity=_identity(
                    "parent",
                    source="parent",
                    successor="successor",
                    retry_lookup=True,
                    lookup_source="parent",
                ),
            ).outcome,
            evidence.AssertionOutcome.PASSED,
        )

    def test_retry_outcome_requires_completed_lookup_bound_to_source(self):
        source = _identity(
            "parent-run", scan_run_ids=("source-scan",), scope="scope-ref"
        )
        valid = _identity(
            "parent-run",
            scan_run_ids=("source-scan",),
            state=contract.RecoveryState.ABANDONED,
            scope="scope-ref",
            successor="retry-run",
            successor_scan_run_ids=("retry-scan",),
            retry_lookup=True,
            lookup_source="parent-run",
        )

        def evaluate(identity):
            return oracle.retry_outcome(
                source_state=contract.RecoveryState.ABANDONED,
                dispatched=True,
                already_retried=False,
                parent_ref="parent-run",
                frozen_scope_ref="scope-ref",
                expected_source_identity=source,
                successor_identity=identity,
            )

        self.assertEqual(
            evaluate(valid).outcome, evidence.AssertionOutcome.PASSED
        )
        invalid_observations = (
            replace(valid, retry_relation_lookup_completed=None),
            replace(valid, retry_relation_lookup_completed=False),
            replace(valid, retry_relation_lookup_completed=1),
            replace(valid, retry_lookup_source_run_ref="foreign-parent"),
        )
        for observation in invalid_observations:
            with self.subTest(observation=observation):
                result = evaluate(observation)
                self.assertEqual(result.outcome, evidence.AssertionOutcome.BLOCKED)
                self.assertEqual(result.code, "retry_successor_lookup_unavailable")

        proven_foreign_identity = replace(
            valid,
            parent_run_ref="foreign-parent",
            source_run_ref="foreign-parent",
            retry_relation_lookup_completed=None,
            retry_lookup_source_run_ref=None,
        )
        contradiction = evaluate(proven_foreign_identity)
        self.assertEqual(contradiction.outcome, evidence.AssertionOutcome.FAILED)
        self.assertEqual(contradiction.code, "retry_identity_source_mismatch")

    def test_retry_outcome_binds_captured_source_scanrun_set(self):
        captured_source = _identity(
            "parent",
            scan_run_ids=("captured-source-scan",),
            state=contract.RecoveryState.FAILED,
        )
        changed_source = _identity(
            "parent",
            scan_run_ids=("changed-source-scan",),
            state=contract.RecoveryState.FAILED,
            source="parent",
            successor="successor",
            retry_lookup=True,
            lookup_source="parent",
        )

        result = oracle.retry_outcome(
            source_state=contract.RecoveryState.FAILED,
            dispatched=True,
            already_retried=False,
            parent_ref="parent",
            frozen_scope_ref="scope-ref",
            expected_source_identity=captured_source,
            successor_identity=changed_source,
        )

        self.assertEqual(result.outcome, evidence.AssertionOutcome.BLOCKED)
        self.assertEqual(result.code, "scan_run_relationship_ambiguous")

    def test_pre_retry_identity_requires_fresh_exact_empty_relation(self):
        valid = _identity(
            "parent",
            scan_run_ids=("scan-run-a", "scan-run-b"),
            state=contract.RecoveryState.FAILED,
            scope="scope-ref",
            retry_lookup=True,
            lookup_source="parent",
        )
        self.assertEqual(
            oracle.validate_retry_precondition(
                valid,
                expected_parent_ref="parent",
                expected_scope_ref="scope-ref",
                expected_requested_root_refs=valid.requested_root_refs,
                expected_admitted_root_refs=valid.admitted_root_refs,
                expected_excluded_root_refs=valid.excluded_root_refs,
                expected_state=contract.RecoveryState.FAILED,
                expected_scan_run_relations=valid.scan_run_relations,
            ).outcome,
            evidence.AssertionOutcome.PASSED,
        )
        invalid = (
            None,
            object(),
            _identity("parent", scan_run_ids=("scan-run-a",), state=contract.RecoveryState.FAILED,
                      scope="scope-ref", retry_lookup=True),
            _identity("other", scan_run_ids=("scan-run-a", "scan-run-b"), state=contract.RecoveryState.FAILED,
                      scope="scope-ref", retry_lookup=True),
            _identity("parent", scan_run_ids=("scan-run-a", "scan-run-b"), state=contract.RecoveryState.FAILED,
                      scope="other-scope", retry_lookup=True),
            _identity("parent", scan_run_ids=("scan-run-a", "scan-run-b"), state=contract.RecoveryState.ACTIVE,
                      scope="scope-ref", retry_lookup=True),
            _identity("parent", scan_run_ids=("scan-run-a", "scan-run-a"), state=contract.RecoveryState.FAILED,
                      scope="scope-ref", retry_lookup=True),
            _identity("parent", scan_run_ids=("scan-run-a", "foreign-scan-run"), state=contract.RecoveryState.FAILED,
                      scope="scope-ref", retry_lookup=True),
            _identity("parent", scan_run_ids=(), state=contract.RecoveryState.FAILED,
                      scope="scope-ref", retry_lookup=True),
            _identity("parent", scan_run_ids=("scan-run-a", "scan-run-b"), state=contract.RecoveryState.FAILED,
                      scope="scope-ref", retry_lookup=None),
            _identity("parent", scan_run_ids=("scan-run-a", "scan-run-b"), state=contract.RecoveryState.FAILED,
                      scope="scope-ref", retry_lookup=False),
            _identity("parent", scan_run_ids=("scan-run-a", "scan-run-b"), state=contract.RecoveryState.FAILED,
                      scope="scope-ref", retry_lookup=True, successor="successor"),
            replace(valid, successor_scan_run_relations=None),
            _identity("parent", scan_run_ids=("scan-run-a", "scan-run-b"), state=contract.RecoveryState.FAILED,
                      scope="scope-ref", retry_lookup=True, successor_scope="scope-ref"),
            replace(
                valid,
                successor_scan_run_relations=(
                    contract.ScanRunRelation(
                        parent_run_ref="unidentified-successor",
                        scan_run_ref="orphan-successor-scan",
                        root_ref="root-ref-0",
                    ),
                ),
            ),
            _identity("parent", scan_run_ids=("scan-run-a", "scan-run-b"), state=contract.RecoveryState.FAILED,
                      scope="scope-ref", retry_lookup=True, lookup_source="other-parent"),
        )
        for observation in invalid:
            with self.subTest(observation=observation):
                expected = (
                    evidence.AssertionOutcome.FAILED
                    if type(observation) is contract.JobIdentityObservation
                    and observation.parent_run_ref == "other"
                    else evidence.AssertionOutcome.BLOCKED
                )
                self.assertEqual(
                    oracle.validate_retry_precondition(
                        observation,
                        expected_parent_ref="parent",
                        expected_scope_ref="scope-ref",
                        expected_requested_root_refs=valid.requested_root_refs,
                        expected_admitted_root_refs=valid.admitted_root_refs,
                        expected_excluded_root_refs=valid.excluded_root_refs,
                        expected_state=contract.RecoveryState.FAILED,
                        expected_scan_run_relations=valid.scan_run_relations,
                    ).outcome,
                    expected,
                )

    def test_pre_retry_lookup_source_requires_bounded_exact_nonblank_string(self):
        valid = _identity(
            "parent",
            scan_run_ids=("scan-run-a", "scan-run-b"),
            state=contract.RecoveryState.FAILED,
            scope="scope-ref",
            retry_lookup=True,
            lookup_source="parent",
        )

        def validate(observation, expected_parent_ref="parent"):
            return oracle.validate_retry_precondition(
                observation,
                expected_parent_ref=expected_parent_ref,
                expected_scope_ref="scope-ref",
                expected_requested_root_refs=valid.requested_root_refs,
                expected_admitted_root_refs=valid.admitted_root_refs,
                expected_excluded_root_refs=valid.excluded_root_refs,
                expected_state=contract.RecoveryState.FAILED,
                expected_scan_run_relations=valid.scan_run_relations,
            )

        self.assertEqual(validate(valid).outcome, evidence.AssertionOutcome.PASSED)
        invalid_sources = (
            _EqualityImpersonatingReference("parent"),
            _EqualityImpersonatingString("different", "parent"),
            None,
            True,
            1,
            1.0,
            object(),
            "",
            " \t\n",
            "p" * 257,
            "another-parent",
        )
        for source in invalid_sources:
            with self.subTest(source_type=type(source).__name__, source=source):
                result = validate(
                    replace(valid, retry_lookup_source_run_ref=source)
                )
                self.assertEqual(result.outcome, evidence.AssertionOutcome.BLOCKED)
                self.assertEqual(
                    result.code,
                    "retry_pre_dispatch_identity_ambiguous",
                )

        for parent_ref in ("p", "p" * 256):
            with self.subTest(parent_ref_length=len(parent_ref)):
                boundary_identity = _identity(
                    parent_ref,
                    scan_run_ids=("scan-run-a", "scan-run-b"),
                    state=contract.RecoveryState.FAILED,
                    scope="scope-ref",
                    retry_lookup=True,
                    lookup_source=parent_ref,
                )
                result = oracle.validate_retry_precondition(
                    boundary_identity,
                    expected_parent_ref=parent_ref,
                    expected_scope_ref="scope-ref",
                    expected_requested_root_refs=boundary_identity.requested_root_refs,
                    expected_admitted_root_refs=boundary_identity.admitted_root_refs,
                    expected_excluded_root_refs=boundary_identity.excluded_root_refs,
                    expected_state=contract.RecoveryState.FAILED,
                    expected_scan_run_relations=boundary_identity.scan_run_relations,
                )
                self.assertEqual(result.outcome, evidence.AssertionOutcome.PASSED)
        for mismatched, expected in (
            (
                _identity("other-parent", source="other-parent", successor="successor"),
                evidence.AssertionOutcome.FAILED,
            ),
            (
                _identity("parent", source="other-parent", successor="successor"),
                evidence.AssertionOutcome.FAILED,
            ),
            (
                _identity(
                    "parent",
                    source="parent",
                    successor="successor",
                    scope="other-scope",
                ),
                evidence.AssertionOutcome.BLOCKED,
            ),
        ):
            with self.subTest(identity=mismatched):
                result = _evaluate_retry_outcome(
                    source_state=contract.RecoveryState.FAILED,
                    dispatched=True,
                    already_retried=False,
                    parent_ref="parent",
                    frozen_scope_ref="scope-ref",
                    successor_identity=mismatched,
                )
                self.assertEqual(result.outcome, expected)

    def test_latency_rule_and_cycle_matrix(self):
        criterion = contract.LatencyCriterion(
            workload_ref="workload",
            environment_ref="environment",
            rule_sha256="a" * 64,
            per_cycle_timeout_seconds=2,
            percentile_95_ceiling_milliseconds=1500,
            action_ids=("open_jobs",),
        )

        def cycles(*, warmups=5, measured=20, elapsed=100, completed=True, evidence_ref="e"):
            return tuple(
                contract.LatencyCycle(
                    "open_jobs",
                    True,
                    elapsed,
                    completed,
                    evidence_ref if evidence_ref == "" else f"{evidence_ref}-{index}",
                )
                for index in range(warmups)
            ) + tuple(
                contract.LatencyCycle(
                    "open_jobs",
                    False,
                    elapsed,
                    completed,
                    evidence_ref if evidence_ref == "" else f"{evidence_ref}-{warmups + index}",
                )
                for index in range(measured)
            )

        self.assertEqual(
            oracle.evaluate_latency(criterion, cycles(), active_overlap_confirmed=True).outcome,
            evidence.AssertionOutcome.PASSED,
        )
        self.assertEqual(
            oracle.evaluate_latency(criterion, cycles(), active_overlap_confirmed=False).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        self.assertEqual(
            oracle.evaluate_latency(
                criterion,
                [object()],
                active_overlap_confirmed=True,
            ).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        self.assertEqual(
            oracle.evaluate_latency(criterion, (), active_overlap_confirmed=True).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        self.assertEqual(
            oracle.evaluate_latency(
                replace(criterion, percentile_95_ceiling_milliseconds=None),
                cycles(),
                active_overlap_confirmed=True,
            ).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        self.assertEqual(
            oracle.evaluate_latency(
                replace(criterion, per_cycle_timeout_seconds=0),
                cycles(),
                active_overlap_confirmed=True,
            ).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        self.assertEqual(
            oracle.evaluate_latency(
                criterion,
                cycles(warmups=4),
                active_overlap_confirmed=True,
            ).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        self.assertEqual(
            oracle.evaluate_latency(
                criterion,
                cycles(completed=False),
                active_overlap_confirmed=True,
            ).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        self.assertEqual(
            oracle.evaluate_latency(
                criterion,
                cycles(evidence_ref=""),
                active_overlap_confirmed=True,
            ).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        self.assertEqual(
            oracle.evaluate_latency(
                criterion,
                cycles(elapsed=2001),
                active_overlap_confirmed=True,
            ).outcome,
            evidence.AssertionOutcome.FAILED,
        )
        self.assertEqual(
            oracle.evaluate_latency(
                criterion,
                cycles(elapsed=1600),
                active_overlap_confirmed=True,
            ).outcome,
            evidence.AssertionOutcome.FAILED,
        )
        for bad in ((), tuple(range(19)), tuple(range(20)) + (-1,)):
            with self.assertRaises(ValueError):
                oracle.nearest_rank_percentile_95(bad)

    def test_latency_action_and_reference_boundaries_are_exact(self):
        def evaluate(
            *,
            action_id="open_jobs",
            workload_ref="workload",
            environment_ref="environment",
            evidence_refs=None,
        ):
            criterion = contract.LatencyCriterion(
                workload_ref=workload_ref,
                environment_ref=environment_ref,
                rule_sha256="a" * 64,
                per_cycle_timeout_seconds=2,
                percentile_95_ceiling_milliseconds=1500,
                action_ids=(action_id,),
            )
            references = evidence_refs or [f"evidence-{index}" for index in range(25)]
            cycles = tuple(
                contract.LatencyCycle(
                    action_id,
                    index < 5,
                    100,
                    True,
                    references[index],
                )
                for index in range(25)
            )
            return oracle.evaluate_latency(
                criterion,
                cycles,
                active_overlap_confirmed=True,
            )

        for action_id in ("a", "a0_b-z", "a" + "0_-" * 21):
            with self.subTest(valid_action_id=action_id):
                self.assertEqual(
                    evaluate(action_id=action_id).outcome,
                    evidence.AssertionOutcome.PASSED,
                )

        for action_id in (
            "a" + "b" * 64,
            "Open_jobs",
            "1open_jobs",
            "a.open",
            "aé",
        ):
            with self.subTest(invalid_action_id=action_id):
                result = evaluate(action_id=action_id)
                self.assertEqual(result.outcome, evidence.AssertionOutcome.BLOCKED)
                self.assertEqual(result.code, "latency_criterion_malformed")

        self.assertEqual(
            evaluate(
                workload_ref="w" * 256,
                environment_ref=" " + "e" * 254 + " ",
                evidence_refs=["r" * 256, *(f"evidence-{index}" for index in range(1, 25))],
            ).outcome,
            evidence.AssertionOutcome.PASSED,
        )
        self.assertEqual(
            evaluate(
                workload_ref="w",
                environment_ref="e",
                evidence_refs=["r", *(f"evidence-{index}" for index in range(1, 25))],
            ).outcome,
            evidence.AssertionOutcome.PASSED,
        )

        for workload_ref, environment_ref in (
            ("w" * 257, "environment"),
            ("", "environment"),
            (" " * 3, "environment"),
            ("workload", "e" * 257),
            ("workload", ""),
            ("workload", " " * 3),
        ):
            with self.subTest(workload_ref=workload_ref, environment_ref=environment_ref):
                result = evaluate(
                    workload_ref=workload_ref,
                    environment_ref=environment_ref,
                )
                self.assertEqual(result.outcome, evidence.AssertionOutcome.BLOCKED)
                self.assertEqual(result.code, "latency_criterion_malformed")

        for invalid_reference in ("x" * 257, " " * 3):
            with self.subTest(invalid_evidence_reference=invalid_reference):
                references = [f"evidence-{index}" for index in range(25)]
                references[0] = invalid_reference
                result = evaluate(evidence_refs=references)
                self.assertEqual(result.outcome, evidence.AssertionOutcome.BLOCKED)
                self.assertEqual(result.code, "latency_cycle_evidence_malformed")

    def test_latency_blocks_malformed_elapsed_samples_in_warmups_and_measurements(self):
        criterion = contract.LatencyCriterion(
            workload_ref="workload",
            environment_ref="environment",
            rule_sha256="a" * 64,
            per_cycle_timeout_seconds=2,
            percentile_95_ceiling_milliseconds=1500,
            action_ids=("open_jobs",),
        )
        valid_cycles = tuple(
            contract.LatencyCycle("open_jobs", index < 5, 100, True, f"sample-{index}")
            for index in range(25)
        )
        malformed_values = (-1, True, 1.5, float("nan"), float("inf"), "100", None)

        for sample_index in (0, 5):
            for malformed in malformed_values:
                with self.subTest(sample_index=sample_index, value=repr(malformed)):
                    changed = list(valid_cycles)
                    changed[sample_index] = replace(
                        changed[sample_index], elapsed_milliseconds=malformed
                    )
                    try:
                        result = oracle.evaluate_latency(
                            criterion, tuple(changed), active_overlap_confirmed=True
                        )
                    except (TypeError, ValueError):
                        result = None
                    self.assertIsNotNone(
                        result,
                        "malformed samples must return a categorical result, not raise",
                    )
                    self.assertEqual(result.outcome, evidence.AssertionOutcome.BLOCKED)
                    self.assertEqual(result.code, "latency_cycle_evidence_malformed")

    def test_latency_blocks_malformed_cycle_identity_and_provenance(self):
        criterion = contract.LatencyCriterion(
            workload_ref="workload",
            environment_ref="environment",
            rule_sha256="a" * 64,
            per_cycle_timeout_seconds=2,
            percentile_95_ceiling_milliseconds=1500,
            action_ids=("open_jobs",),
        )
        valid_cycles = tuple(
            contract.LatencyCycle("open_jobs", index < 5, 100, True, f"sample-{index}")
            for index in range(25)
        )
        malformed_cases = []
        for field, value in (
            ("warmup", 1),
            ("return_completed", 1),
            ("evidence_ref", object()),
            ("evidence_ref", "   "),
            ("action_id", "Open Jobs"),
        ):
            changed = list(valid_cycles)
            changed[0] = replace(changed[0], **{field: value})
            malformed_cases.append((field, value, tuple(changed), criterion))

        duplicate_refs = list(valid_cycles)
        duplicate_refs[1] = replace(
            duplicate_refs[1], evidence_ref=duplicate_refs[0].evidence_ref
        )
        malformed_cases.append(("duplicate_evidence_ref", None, tuple(duplicate_refs), criterion))

        invalid_action_cycles = tuple(
            replace(cycle, action_id="Open Jobs") for cycle in valid_cycles
        )
        malformed_cases.append(
            ("invalid_action_identifier", None, invalid_action_cycles,
             replace(criterion, action_ids=("Open Jobs",)))
        )

        unexpected = valid_cycles + (
            contract.LatencyCycle("unexpected_action", False, 100, True, "extra-cycle"),
        )
        malformed_cases.append(("unexpected_action_cycle", None, unexpected, criterion))

        for label, _, cycles, selected_criterion in malformed_cases:
            with self.subTest(case=label):
                result = oracle.evaluate_latency(
                    selected_criterion, cycles, active_overlap_confirmed=True
                )
                self.assertEqual(result.outcome, evidence.AssertionOutcome.BLOCKED)
                if label == "unexpected_action_cycle":
                    expected_code = "latency_cycle_set_mismatch"
                elif label == "invalid_action_identifier":
                    expected_code = "latency_criterion_malformed"
                else:
                    expected_code = "latency_cycle_evidence_malformed"
                self.assertEqual(result.code, expected_code)

    def test_latency_blocks_malformed_criteria_and_overlap_type(self):
        criterion = contract.LatencyCriterion(
            workload_ref="workload",
            environment_ref="environment",
            rule_sha256="a" * 64,
            per_cycle_timeout_seconds=2,
            percentile_95_ceiling_milliseconds=1500,
            action_ids=("open_jobs",),
        )
        valid_cycles = tuple(
            contract.LatencyCycle("open_jobs", index < 5, 100, True, f"sample-{index}")
            for index in range(25)
        )
        malformed_criteria = (
            replace(criterion, workload_ref=7),
            replace(criterion, environment_ref=object()),
            replace(criterion, rule_sha256="not-a-digest"),
            replace(criterion, per_cycle_timeout_seconds=True),
            replace(criterion, per_cycle_timeout_seconds=0),
            replace(criterion, percentile_95_ceiling_milliseconds=1500.0),
            replace(criterion, percentile_95_ceiling_milliseconds=-1),
            replace(criterion, warmup_cycles=5.0),
            replace(criterion, measured_cycles=20.0),
            replace(criterion, action_ids=["open_jobs"]),
            replace(criterion, action_ids=("open_jobs", "open_jobs")),
        )
        for malformed in malformed_criteria:
            with self.subTest(criterion=malformed):
                result = oracle.evaluate_latency(
                    malformed, valid_cycles, active_overlap_confirmed=True
                )
                self.assertEqual(result.outcome, evidence.AssertionOutcome.BLOCKED)
                self.assertEqual(result.code, "latency_criterion_malformed")

        overlap = oracle.evaluate_latency(
            criterion, valid_cycles, active_overlap_confirmed=1
        )
        self.assertEqual(overlap.outcome, evidence.AssertionOutcome.BLOCKED)
        self.assertEqual(overlap.code, "latency_active_overlap_unavailable")

    def test_latency_preserves_nearest_rank_percentile_95_and_owner_failures(self):
        criterion = contract.LatencyCriterion(
            workload_ref="workload",
            environment_ref="environment",
            rule_sha256="a" * 64,
            per_cycle_timeout_seconds=2,
            percentile_95_ceiling_milliseconds=19,
            action_ids=("open_jobs",),
        )
        cycles = tuple(
            contract.LatencyCycle("open_jobs", True, 0, True, f"warmup-{index}")
            for index in range(5)
        ) + tuple(
            contract.LatencyCycle("open_jobs", False, index, True, f"measured-{index}")
            for index in range(1, 21)
        )
        self.assertEqual(
            oracle.evaluate_latency(criterion, cycles, active_overlap_confirmed=True),
            oracle.OracleResult(evidence.AssertionOutcome.PASSED, "latency_rule_satisfied"),
        )
        self.assertEqual(
            oracle.evaluate_latency(
                replace(criterion, percentile_95_ceiling_milliseconds=18),
                cycles,
                active_overlap_confirmed=True,
            ).outcome,
            evidence.AssertionOutcome.FAILED,
        )
        self.assertEqual(
            oracle.evaluate_latency(
                replace(criterion, percentile_95_ceiling_milliseconds=-1),
                cycles,
                active_overlap_confirmed=True,
            ).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )

    def test_terminal_successor_and_oracle_identity(self):
        self.assertEqual(
            oracle.terminal_successor(None).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        self.assertEqual(
            oracle.terminal_successor(
                replace(_detail("successor", contract.RecoveryState.COMPLETED), progress=None)
            ).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        self.assertEqual(
            oracle.terminal_successor(_detail("successor", contract.RecoveryState.ACTIVE)).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        self.assertEqual(
            oracle.terminal_successor(
                _detail("successor", "unknown")
            ).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        self.assertEqual(
            oracle.terminal_successor(
                _detail("successor", contract.RecoveryState.COMPLETED)
            ).outcome,
            evidence.AssertionOutcome.PASSED,
        )
        for state, expected in (
            (contract.RecoveryState.COMPLETED, evidence.AssertionOutcome.PASSED),
            (
                contract.RecoveryState.COMPLETED_WITH_ISSUES,
                evidence.AssertionOutcome.BLOCKED,
            ),
            (contract.RecoveryState.FAILED, evidence.AssertionOutcome.FAILED),
            (contract.RecoveryState.CANCELLED, evidence.AssertionOutcome.FAILED),
            (contract.RecoveryState.ABANDONED, evidence.AssertionOutcome.FAILED),
            (contract.RecoveryState.ACTIVE, evidence.AssertionOutcome.BLOCKED),
            ("unknown", evidence.AssertionOutcome.BLOCKED),
        ):
            self.assertEqual(
                oracle.retry_success_acceptance(state).outcome,
                expected,
            )
        self.assertEqual(
            oracle.retry_success_acceptance(
                contract.RecoveryState.COMPLETED_WITH_ISSUES,
                accepted_states=frozenset({contract.RecoveryState.COMPLETED_WITH_ISSUES}),
            ).outcome,
            evidence.AssertionOutcome.PASSED,
        )
        self.assertEqual(
            oracle.retry_success_acceptance(
                contract.RecoveryState.FAILED,
                accepted_states=frozenset({contract.RecoveryState.FAILED}),
            ).outcome,
            evidence.AssertionOutcome.FAILED,
        )
        self.assertRegex(oracle.oracle_sha256(), r"^[0-9a-f]{64}$")
        self.assertEqual(oracle.oracle_version(), "9")
        self.assertEqual(
            oracle.validate_refresh_progress(None).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        self.assertEqual(
            oracle.validate_process_observation(
                replace(
                    _process(contract.ProcessState.PRESENT, QUALIFICATION_PACKAGE),
                    package_name="com.example.foreign",
                ),
                expected_state=contract.ProcessState.PRESENT,
                expected_package=QUALIFICATION_PACKAGE,
            ).outcome,
            evidence.AssertionOutcome.FAILED,
        )
        self.assertEqual(
            oracle.retry_eligibility(contract.RecoveryState.INTERRUPTED).outcome,
            evidence.AssertionOutcome.NOT_RUN,
        )
        with mock.patch.object(oracle, "LATENCY_EXECUTION_ENABLED", True):
            self.assertEqual(
                oracle.latency_execution_status().code,
                "latency_owner_authorization_unavailable",
            )

    def test_post_retry_root_requires_scanrun_tuple_and_separates_view_job(self):
        successor = contract.ScanRootObservation(
            contract.JobLifecycleSurface.SCAN_ROOT_DETAIL,
            "root",
            None,
            1,
            "retry-successor",
            "observer",
            contract.ScanRootPresentation.ACTIVE_SCAN,
            "scan-successor",
            "retry-successor",
        )
        historical = replace(
            successor,
            last_scan_state="complete",
            presentation=contract.ScanRootPresentation.HISTORICAL_LAST_SCAN,
        )
        for observation in (successor, historical):
            self.assertEqual(
                oracle.validate_scan_root_post_retry(
                    observation,
                    expected_root_ref="root",
                    expected_successor_run_ref="retry-successor",
                    expected_scan_run_ref="scan-successor",
                ).outcome,
                evidence.AssertionOutcome.PASSED,
            )
        self.assertEqual(
            oracle.validate_scan_root_post_retry(
                replace(successor, view_job_run_ref="unrelated-job-run"),
                expected_root_ref="root",
                expected_successor_run_ref="retry-successor",
                expected_scan_run_ref="scan-successor",
            ).outcome,
            evidence.AssertionOutcome.PASSED,
        )
        self.assertEqual(
            oracle.validate_scan_root_post_retry(
                replace(successor, view_job_control_count=None, view_job_run_ref=None),
                expected_root_ref="root",
                expected_successor_run_ref="retry-successor",
                expected_scan_run_ref="scan-successor",
            ).outcome,
            evidence.AssertionOutcome.PASSED,
        )
        cases = (
            (replace(successor, root_ref="other-root"), evidence.AssertionOutcome.BLOCKED),
            (replace(successor, scan_parent_run_ref="other-parent"), evidence.AssertionOutcome.FAILED),
            (replace(successor, scan_run_ref="other-scan"), evidence.AssertionOutcome.BLOCKED),
            (replace(successor, scan_run_ref=None), evidence.AssertionOutcome.BLOCKED),
            (replace(successor, scan_parent_run_ref=None), evidence.AssertionOutcome.BLOCKED),
            (replace(successor, presentation=contract.ScanRootPresentation.UNIDENTIFIED), evidence.AssertionOutcome.BLOCKED),
            (replace(successor, last_scan_state="complete"), evidence.AssertionOutcome.BLOCKED),
        )
        for observation, expected_outcome in cases:
            with self.subTest(observation=observation):
                result = oracle.validate_scan_root_post_retry(
                    observation,
                    expected_root_ref="root",
                    expected_successor_run_ref="retry-successor",
                    expected_scan_run_ref="scan-successor",
                )
                self.assertEqual(result.outcome, expected_outcome)
        self.assertEqual(
            oracle.validate_scan_root_post_retry(
                successor,
                expected_root_ref="root",
                expected_successor_run_ref="retry-successor",
                expected_scan_run_ref=None,
            ).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )

    def test_view_job_jobrun_id_alone_cannot_prove_scanrun_ownership(self):
        observation = contract.ScanRootObservation(
            contract.JobLifecycleSurface.SCAN_ROOT_DETAIL,
            "root",
            None,
            1,
            "retry-successor",
            "observer",
            contract.ScanRootPresentation.ACTIVE_SCAN,
        )
        result = oracle.validate_scan_root_post_retry(
            observation,
            expected_root_ref="root",
            expected_successor_run_ref="retry-successor",
            expected_scan_run_ref="scan-successor",
        )
        self.assertEqual(result.outcome, evidence.AssertionOutcome.BLOCKED)

    def test_recovery_persistence_blocks_unqueried_intermediate_redirect(self):
        observation = _library(
            membership=1,
            membership_ids=("present-game",),
            identity_continuity=contract.GameIdContinuityObservation(
                "parent-run",
                (
                    contract.GameIdRedirect(
                        "missing-game", "unqueried-intermediate", "parent-run"
                    ),
                    contract.GameIdRedirect(
                        "unqueried-intermediate", "present-game", "parent-run"
                    ),
                ),
                True,
                "continuity-observer",
                ("missing-game",),
            ),
        )

        result = oracle.library_recovery_persistence(
            ("missing-game",), observation, expected_job_run_ref="parent-run"
        )

        self.assertEqual(result.outcome, evidence.AssertionOutcome.BLOCKED)

    def test_missing_game_id_with_unverified_grouping_continuity_is_blocked(self):
        recovered = _library(
            membership=1,
            membership_ids=("new-canonical-game",),
        )
        result = oracle.library_recovery_persistence(
            ("preloss-game",),
            recovered,
        )
        self.assertEqual(result.outcome, evidence.AssertionOutcome.BLOCKED)

    def test_recovery_persistence_oracles(self):
        active = contract.ScanRootObservation(
            contract.JobLifecycleSurface.SCAN_ROOT_DETAIL,
            "root",
            None,
            1,
            "parent-job",
            "observer",
            contract.ScanRootPresentation.ACTIVE_SCAN,
            "scan-run-a",
            "parent-job",
        )
        historical = replace(
            active,
            last_scan_state="abandoned",
            presentation=contract.ScanRootPresentation.HISTORICAL_LAST_SCAN,
        )
        self.assertEqual(
            oracle.validate_scan_root_preloss(active, expected_root_ref="root").outcome,
            evidence.AssertionOutcome.PASSED,
        )
        self.assertEqual(
            oracle.validate_scan_root_preloss(
                replace(active, view_job_control_count=None, view_job_run_ref=None),
                expected_root_ref="root",
            ).outcome,
            evidence.AssertionOutcome.PASSED,
        )
        self.assertEqual(
            oracle.validate_scan_root_preloss(
                replace(active, root_ref="other-root"), expected_root_ref="root"
            ).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        self.assertEqual(
            oracle.validate_scan_root_preloss(
                replace(active, scan_run_ref=None), expected_root_ref="root"
            ).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        source_relation = contract.ScanRunRelation(
            parent_run_ref="parent-job",
            scan_run_ref="scan-run-a",
            root_ref="root",
        )
        self.assertEqual(
            oracle.validate_scan_root_relation(
                replace(active, scan_parent_run_ref=None),
                expected_relation=source_relation,
            ).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        self.assertEqual(
            oracle.scan_root_recovery_persistence(active, historical).outcome,
            evidence.AssertionOutcome.PASSED,
        )
        self.assertEqual(
            oracle.scan_root_recovery_persistence(
                active, replace(active, view_job_run_ref="another-job")
            ).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        self.assertEqual(
            oracle.scan_root_recovery_persistence(
                historical, replace(historical, scan_run_ref="different-scan")
            ).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        self.assertEqual(
            oracle.scan_root_recovery_persistence(
                historical, replace(historical, last_scan_state="complete")
            ).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        self.assertEqual(
            oracle.scan_root_recovery_persistence(active, active).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        self.assertEqual(
            oracle.validate_scan_root_post_retry(
                historical,
                expected_root_ref="root",
                expected_successor_run_ref="parent-job",
                expected_scan_run_ref="scan-run-a",
            ).outcome,
            evidence.AssertionOutcome.PASSED,
        )
        self.assertEqual(
            oracle.validate_scan_root_post_retry(
                historical,
                expected_root_ref="other-root",
                expected_successor_run_ref="parent-job",
                expected_scan_run_ref="scan-run-a",
            ).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        self.assertEqual(
            oracle.validate_scan_root_post_retry(
                historical,
                expected_root_ref="root",
                expected_successor_run_ref="stale-parent",
                expected_scan_run_ref="scan-run-a",
            ).outcome,
            evidence.AssertionOutcome.FAILED,
        )

        preloss = ("asset-a", "asset-b")
        complete_no_redirect = contract.GameIdContinuityObservation(
            "parent-run", (), True, "continuity-observer", ("asset-b",)
        )
        self.assertNotEqual(
            complete_no_redirect.digest(),
            replace(complete_no_redirect, queried_game_ids=()).digest(),
        )
        exact_recovered = _library(membership=2, membership_ids=preloss)
        self.assertEqual(
            oracle.library_recovery_persistence(preloss, exact_recovered).outcome,
            evidence.AssertionOutcome.PASSED,
        )
        self.assertEqual(
            oracle.library_recovery_persistence(
                preloss,
                _library(membership=3, membership_ids=preloss + ("asset-c",)),
            ).outcome,
            evidence.AssertionOutcome.PASSED,
        )
        missing_but_unproven = _library(membership=1, membership_ids=("asset-a",))
        self.assertEqual(
            oracle.library_recovery_persistence(
                preloss, missing_but_unproven, expected_job_run_ref="parent-run"
            ).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        incomplete_lookup = contract.GameIdContinuityObservation(
            "parent-run", (), True, "continuity-observer", ("asset-a",)
        )
        uncovered_missing_id = replace(
            missing_but_unproven,
            identity_continuity=incomplete_lookup,
        )
        self.assertEqual(
            oracle.library_recovery_persistence(
                preloss,
                uncovered_missing_id,
                expected_job_run_ref="parent-run",
            ).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        duplicate_query_scope = replace(
            incomplete_lookup,
            queried_game_ids=("asset-b", "asset-b"),
        )
        self.assertEqual(
            oracle.library_recovery_persistence(
                preloss,
                replace(
                    missing_but_unproven,
                    identity_continuity=duplicate_query_scope,
                ),
                expected_job_run_ref="parent-run",
            ).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        missing_proven = replace(
            missing_but_unproven,
            identity_continuity=complete_no_redirect,
        )
        self.assertEqual(
            oracle.library_recovery_persistence(
                preloss, missing_proven, expected_job_run_ref="parent-run"
            ).outcome,
            evidence.AssertionOutcome.FAILED,
        )
        loss_with_unrelated_addition = _library(
            membership=2,
            membership_ids=("asset-a", "unrelated-new-asset"),
            identity_continuity=complete_no_redirect,
        )
        self.assertEqual(
            oracle.library_recovery_persistence(
                preloss,
                loss_with_unrelated_addition,
                expected_job_run_ref="parent-run",
            ).outcome,
            evidence.AssertionOutcome.FAILED,
        )
        redirected = _library(
            membership=2,
            membership_ids=("canonical-game", "new-game"),
            identity_continuity=contract.GameIdContinuityObservation(
                "parent-run",
                (contract.GameIdRedirect("asset-a", "canonical-game", "parent-run"),
                 contract.GameIdRedirect("asset-b", "canonical-game", "parent-run")),
                True,
                "continuity-observer",
            ("asset-a", "asset-b"),
            ),
        )
        self.assertEqual(
            oracle.library_recovery_persistence(
                preloss, redirected, expected_job_run_ref="parent-run"
            ).outcome,
            evidence.AssertionOutcome.PASSED,
        )
        redirect_chain = _library(
            membership=2,
            membership_ids=("canonical-final", "new-game"),
            identity_continuity=contract.GameIdContinuityObservation(
                "parent-run",
                (
                    contract.GameIdRedirect("asset-a", "canonical-middle", "parent-run"),
                    contract.GameIdRedirect("canonical-middle", "canonical-final", "parent-run"),
                    contract.GameIdRedirect("asset-b", "canonical-final", "parent-run"),
                ),
                True,
                "continuity-observer",
            ("asset-a", "asset-b"),
            ),
        )
        self.assertEqual(
            oracle.library_recovery_persistence(
                preloss, redirect_chain, expected_job_run_ref="parent-run"
            ).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        ambiguous_split = _library(
            membership=3,
            membership_ids=("asset-a", "canonical-one", "canonical-two"),
            identity_continuity=contract.GameIdContinuityObservation(
                "parent-run",
                (
                    contract.GameIdRedirect("asset-b", "canonical-one", "parent-run"),
                    contract.GameIdRedirect("asset-b", "canonical-two", "parent-run"),
                ),
                True,
                "continuity-observer",
            ("asset-b",),
            ),
        )
        self.assertEqual(
            oracle.library_recovery_persistence(
                preloss, ambiguous_split, expected_job_run_ref="parent-run"
            ).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        foreign_continuity = _library(
            membership=1,
            membership_ids=("canonical-game",),
            identity_continuity=contract.GameIdContinuityObservation(
                "foreign-run",
                (contract.GameIdRedirect("asset-b", "canonical-game", "foreign-run"),),
                True,
                "continuity-observer",
                ("asset-a", "asset-b"),
            ),
        )
        self.assertEqual(
            oracle.library_recovery_persistence(
                preloss, foreign_continuity, expected_job_run_ref="parent-run"
            ).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        self.assertEqual(
            oracle.library_recovery_persistence(
                ("asset-a", "asset-c"),
                _library(membership=1, membership_ids=("canonical-game",),
                    identity_continuity=contract.GameIdContinuityObservation(
                        "successor-run",
                        (contract.GameIdRedirect("asset-a", "canonical-game", "successor-run"),),
                        True,
                        "continuity-observer",
                ("asset-a", "asset-c"),
                    )),
                expected_job_run_ref="successor-run",
            ).outcome,
            evidence.AssertionOutcome.FAILED,
        )
        self.assertEqual(
            oracle.library_recovery_persistence(
                preloss,
                _library(membership=2, membership_ids=None),
            ).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )
        self.assertEqual(
            oracle.library_post_retry_integrity(
                ("asset-a", "asset-c"),
                _library(membership=2, membership_ids=("asset-a", "asset-c")),
                expected_job_run_ref="successor-run",
            ).outcome,
            evidence.AssertionOutcome.PASSED,
        )
        self.assertEqual(
            oracle.library_post_retry_integrity(
                ("asset-a", "asset-c"),
                _library(
                    membership=1,
                    membership_ids=("canonical-game",),
                    identity_continuity=contract.GameIdContinuityObservation(
                        "successor-run",
                        (contract.GameIdRedirect("asset-a", "canonical-game", "successor-run"),),
                        True,
                        "continuity-observer",
                        ("asset-a", "asset-c"),
                    ),
                ),
                expected_job_run_ref="successor-run",
            ).outcome,
            evidence.AssertionOutcome.FAILED,
        )

    def test_recovery_persistence_blocks_cycles_and_missing_provenance(self):
        cycle = contract.GameIdContinuityObservation(
            "parent-run",
            (
                contract.GameIdRedirect("missing-a", "missing-b", "parent-run"),
                contract.GameIdRedirect("missing-b", "missing-a", "parent-run"),
            ),
            True,
            "continuity-observer",
            ("missing-a", "missing-b"),
        )
        cycle_result = oracle.library_recovery_persistence(
            ("missing-a",),
            _library(
                membership=1,
                membership_ids=("present-game",),
                identity_continuity=cycle,
            ),
            expected_job_run_ref="parent-run",
        )
        self.assertEqual(cycle_result.outcome, evidence.AssertionOutcome.BLOCKED)

        missing_provenance = contract.GameIdContinuityObservation(
            "parent-run",
            (contract.GameIdRedirect("missing-game", "present-game", "parent-run"),),
            True,
            None,
            ("missing-game",),
        )
        provenance_result = oracle.library_recovery_persistence(
            ("missing-game",),
            _library(
                membership=1,
                membership_ids=("present-game",),
                identity_continuity=missing_provenance,
            ),
            expected_job_run_ref="parent-run",
        )
        self.assertEqual(
            provenance_result.outcome, evidence.AssertionOutcome.BLOCKED
        )

    def test_whitespace_continuity_provenance_blocks_recovery_and_post_retry_integrity(self):
        continuity = replace(
            _complete_no_redirect("parent-run", ("missing-game",)),
            observer_ref=" \t ",
        )
        library = _library(
            membership=1,
            membership_ids=("present-game",),
            identity_continuity=continuity,
        )

        recovery = oracle.library_recovery_persistence(
            ("missing-game",), library, expected_job_run_ref="parent-run"
        )
        post_retry = oracle.library_post_retry_integrity(
            ("missing-game",), library, expected_job_run_ref="parent-run"
        )

        self.assertEqual(recovery.outcome, evidence.AssertionOutcome.BLOCKED)
        self.assertEqual(post_retry.outcome, evidence.AssertionOutcome.BLOCKED)

    def test_post_retry_integrity_accepts_direct_and_blocks_intermediate_redirects(self):
        direct = contract.GameIdContinuityObservation(
            "retry-run",
            (contract.GameIdRedirect("missing-game", "present-game", "retry-run"),),
            True,
            "continuity-observer",
            ("missing-game",),
        )
        self.assertEqual(
            oracle.library_post_retry_integrity(
                ("missing-game",),
                _library(
                    membership=1,
                    membership_ids=("present-game",),
                    identity_continuity=direct,
                ),
                expected_job_run_ref="retry-run",
            ).outcome,
            evidence.AssertionOutcome.PASSED,
        )

        queried_chain = contract.GameIdContinuityObservation(
            "retry-run",
            (
                contract.GameIdRedirect(
                    "missing-game", "intermediate-game", "retry-run"
                ),
                contract.GameIdRedirect(
                    "intermediate-game", "present-game", "retry-run"
                ),
            ),
            True,
            "continuity-observer",
            ("missing-game", "intermediate-game"),
        )
        self.assertEqual(
            oracle.library_post_retry_integrity(
                ("missing-game",),
                _library(
                    membership=1,
                    membership_ids=("present-game",),
                    identity_continuity=queried_chain,
                ),
                expected_job_run_ref="retry-run",
            ).outcome,
            evidence.AssertionOutcome.BLOCKED,
        )


class ExecutorLifecycleTests(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.directory = Path(self.temporary_directory.name)
        self.registry_patch = mock.patch.object(
            admission,
            "_SESSION_REGISTRY_PATH",
            self.directory / "host-state" / "session-registry.json",
            create=True,
        )
        self.registry_patch.start()
        self.addCleanup(self.registry_patch.stop)

    def _executor(
        self,
        scenario="AND-04",
        *,
        directory: Path | None = None,
        authorization_id=None,
        baseline=None,
        baseline_job_states=None,
        transport=None,
        writer=None,
        observer=None,
        monotonic=None,
        sleeper=None,
    ):
        active_directory = self.directory if directory is None else directory
        document = _authorization_document(scenario, job_states=baseline_job_states)
        if authorization_id is not None:
            document["authorization_id"] = authorization_id
        authorization = _load_lifecycle_authorization(active_directory, document)
        approval = _load_approval(active_directory, authorization)
        transport = transport or ScriptedTransport(scenario)
        result = admission._admit_job_lifecycle_session(
            authorization,
            approval,
            _artifact(),
            FakeBaselineTransport(baseline),
            now=NOW,
        )
        self.assertEqual(result.status, admission.AdmissionStatus.ADMITTED)
        writer = writer or RecordingWriter()
        executor = lifecycle_executor._JobLifecycleOperationExecutor(
            session=result.session,
            transport=transport,
            observer=observer or ScriptedObserver(transport, baseline),
            writer=writer,
            evidence_spec=session_spec(authorization),
            monotonic=monotonic or time.monotonic,
            sleeper=sleeper or time.sleep,
        )
        return executor, transport, writer

    def _force_stop_into(
        self,
        transport: ScriptedTransport,
        state: contract.RecoveryState,
    ) -> None:
        def force_stop(package, timeout):
            transport.force_stop_calls += 1
            transport.process_state = contract.ProcessState.ABSENT
            transport.foreground = "com.android.launcher3"
            transport.detail_state = state

        transport.force_stop_package = force_stop

    def _operation_id_for_handler(self, scenario, handler):
        spec = next(
            item
            for item in contract.JOB_LIFECYCLE_OPERATIONS[scenario]
            if item.handler == handler
        )
        return f"{scenario.lower()}-{spec.index:02d}"

    def _override_process_for_operation(
        self, executor, observer, operation_id, replacement, *, occurrence=1
    ):
        original = observer.observe_process
        seen = 0

        def observe(package, timeout):
            nonlocal seen
            observed = original(package, timeout)
            attempted = executor._attempted_operation
            if attempted is not None and attempted.operation_id == operation_id:
                seen += 1
                if seen == occurrence:
                    return replacement(observed)
            return observed

        observer.observe_process = observe

    def _override_detail_for_operation(
        self, executor, operation_id, replacement
    ):
        original = executor._observe_detail

        def observe(operation, parent_ref):
            detail = original(operation, parent_ref)
            if operation.operation_id == operation_id:
                return replacement(detail)
            return detail

        executor._observe_detail = observe

    def test_and_04_completes_host_workflow_but_stays_blocked(self):
        executor, transport, writer = self._executor()
        result = executor.execute(now=NOW)
        self.assertTrue(result.workflow_completed)
        self.assertEqual(result.completed_operations, 31)
        self.assertEqual(result.total_operations, 31)
        self.assertEqual(result.status, "blocked")
        self.assertIn("physical", result.blocker)
        self.assertEqual(writer.terminal.outcome, evidence.TerminalOutcome.BLOCKED)
        self.assertEqual(
            transport.navigations[-3:],
            ["navigate_sources", "open_scan_root", "open_scan_job_detail"],
        )

    def test_and_04_recovered_lifecycle_waits_for_terminal_parent(self):
        transport = ScriptedTransport("AND-04")
        observer = ScriptedObserver(transport)
        clock = _Clock(step=1.0)
        state = {"executor": None, "calls": 0}
        original = transport.observe_refresh_detail

        def detail(parent_ref, timeout):
            executor = state["executor"]
            attempted = None if executor is None else executor._attempted_operation
            if attempted is not None and attempted.operation_id == "and-04-25":
                state["calls"] += 1
                lifecycle = (
                    contract.RecoveryState.ACTIVE
                    if state["calls"] == 1
                    else contract.RecoveryState.COMPLETED
                )
                return replace(original(parent_ref, timeout), state=lifecycle)
            return original(parent_ref, timeout)

        transport.observe_refresh_detail = detail
        executor, _, _ = self._executor(
            transport=transport,
            observer=observer,
            monotonic=clock.monotonic,
            sleeper=clock.sleep,
        )
        state["executor"] = executor

        result = executor.execute(now=NOW)

        self.assertTrue(result.workflow_completed)
        self.assertEqual(result.completed_operations, 31)
        self.assertEqual(state["calls"], 2)
        self.assertEqual(executor._parent_state, contract.RecoveryState.COMPLETED)

    def test_and_04_active_recovery_at_observation_deadline_blocks(self):
        transport = ScriptedTransport("AND-04")
        observer = ScriptedObserver(transport)
        clock = _Clock(step=5.0)
        state = {"executor": None, "calls": 0}
        original = transport.observe_refresh_detail

        def detail(parent_ref, timeout):
            executor = state["executor"]
            attempted = None if executor is None else executor._attempted_operation
            if attempted is not None and attempted.operation_id == "and-04-25":
                state["calls"] += 1
                return replace(
                    original(parent_ref, timeout),
                    state=contract.RecoveryState.ACTIVE,
                )
            return original(parent_ref, timeout)

        transport.observe_refresh_detail = detail
        executor, _, _ = self._executor(
            transport=transport,
            observer=observer,
            monotonic=clock.monotonic,
            sleeper=clock.sleep,
        )
        state["executor"] = executor

        result = executor.execute(now=NOW)

        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 24)
        self.assertIn("remained active", result.blocker)
        self.assertGreater(state["calls"], 1)
        self.assertNotIn("navigate_sources", transport.navigations)

    def test_and_04_terminal_detail_returned_after_operation_deadline_blocks(self):
        transport = ScriptedTransport("AND-04")
        observer = ScriptedObserver(transport)
        clock = _Clock()
        state = {"executor": None, "calls": 0}
        original = transport.observe_refresh_detail

        def detail(parent_ref, timeout):
            executor = state["executor"]
            attempted = None if executor is None else executor._attempted_operation
            if attempted is not None and attempted.operation_id == "and-04-25":
                state["calls"] += 1
                deadline = executor._operation_monotonic_deadline
                self.assertIsNotNone(deadline)
                clock.value = deadline + 0.001
                return replace(
                    original(parent_ref, timeout),
                    state=contract.RecoveryState.COMPLETED,
                )
            return original(parent_ref, timeout)

        transport.observe_refresh_detail = detail
        executor, _, _ = self._executor(
            transport=transport,
            observer=observer,
            monotonic=clock.monotonic,
            sleeper=clock.sleep,
        )
        state["executor"] = executor

        result = executor.execute(now=NOW)

        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 24)
        self.assertEqual(state["calls"], 1)
        self.assertNotIn("navigate_sources", transport.navigations)

    def test_and_05_completes_host_workflow_but_stays_blocked(self):
        executor, transport, writer = self._executor("AND-05")
        transport.detail_state = contract.RecoveryState.ACTIVE
        def force_stop(package, timeout):
            transport.force_stop_calls += 1
            transport.process_state = contract.ProcessState.ABSENT
            transport.foreground = "com.android.launcher3"
            transport.detail_state = contract.RecoveryState.ABANDONED
        transport.force_stop_package = force_stop
        transport.observe_jobs = lambda timeout: _jobs(
            parent=transport.parent,
            state=transport.detail_state,
            rows=1,
            active=1 if transport.detail_state is contract.RecoveryState.ACTIVE else 0,
        ) if transport.progress_calls else _jobs()
        result = executor.execute(now=NOW)
        self.assertEqual(result.completed_operations, 45)
        self.assertEqual(result.total_operations, 45)
        self.assertTrue(result.workflow_completed)
        self.assertEqual(transport.retry_calls, 1)
        self.assertEqual(writer.terminal.outcome, evidence.TerminalOutcome.BLOCKED)

    def _successor_terminal_keys(self, executor, writer, suffix):
        operation = executor._planned_operations[-1]
        key = admission._add_scan_alias(
            "operation",
            f"{executor._spec.session_id}:{operation.operation_id}:{suffix}",
        )
        return any(observed == key for observed, _ in writer.assertion_keys)

    def _assertion_recorded(self, executor, writer, operation_id, suffix, outcome):
        key = admission._add_scan_alias(
            "operation",
            f"{executor._spec.session_id}:{operation_id}:{suffix}",
        )
        return (key, outcome.value) in writer.assertion_keys

    def test_successor_completed_passes_retry_success_assertion(self):
        executor, transport, writer = self._executor("AND-05")
        self._run_and_05_with_force_stop(transport)
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 45)
        self.assertTrue(result.workflow_completed)
        self.assertTrue(
            self._successor_terminal_keys(executor, writer, "terminal")
        )
        self.assertTrue(
            self._successor_terminal_keys(executor, writer, "result")
        )

    def _post_retry_scanrun_attribution_recorded(self, executor, writer):
        key = admission._add_scan_alias(
            "operation",
            f"{executor._spec.session_id}:and-05-42:refresh-scanrun-attribution",
        )
        return any(recorded == key for recorded, _ in writer.assertion_keys)

    def test_active_retry_scan_at_post_retry_root_reaches_terminal_success(self):
        executor, transport, writer = self._executor("AND-05")
        transport.scan_root_post_retry_presentation = (
            contract.ScanRootPresentation.ACTIVE_SCAN
        )
        transport.scan_root_post_retry_state = None
        transport.successor_completes_after = 2
        self._run_and_05_with_force_stop(transport)
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 45)
        self.assertTrue(result.workflow_completed)
        self.assertEqual(transport.retry_calls, 1)
        self.assertTrue(
            self._assertion_recorded(
                executor,
                writer,
                "and-05-42",
                "root-post-retry-integrity",
                evidence.AssertionOutcome.PASSED,
            )
        )
        self.assertTrue(
            self._assertion_recorded(
                executor,
                writer,
                "and-05-42",
                "root-post-retry-active-scan",
                evidence.AssertionOutcome.PASSED,
            )
        )
        self.assertTrue(self._successor_terminal_keys(executor, writer, "terminal"))
        self.assertIsNone(executor._scan_run_ref)
        self.assertFalse(self._post_retry_scanrun_attribution_recorded(executor, writer))

    def test_historical_post_retry_root_records_successor_last_scan(self):
        executor, transport, writer = self._executor("AND-05")
        self._run_and_05_with_force_stop(transport)
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 45)
        self.assertTrue(result.workflow_completed)
        self.assertTrue(
            self._assertion_recorded(
                executor,
                writer,
                "and-05-42",
                "root-post-retry-integrity",
                evidence.AssertionOutcome.PASSED,
            )
        )
        self.assertFalse(
            self._assertion_recorded(
                executor,
                writer,
                "and-05-42",
                "root-post-retry-active-scan",
                evidence.AssertionOutcome.PASSED,
            )
        )
        self.assertEqual(executor._scan_run_ref, "scan-run-root-successor")
        self.assertFalse(self._post_retry_scanrun_attribution_recorded(executor, writer))

    def test_post_retry_root_active_owned_by_unrelated_job_blocks(self):
        executor, transport, _ = self._executor("AND-05")
        transport.scan_root_post_retry_presentation = (
            contract.ScanRootPresentation.ACTIVE_SCAN
        )
        transport.scan_root_post_retry_state = None
        transport.scan_root_post_retry_run_ref = "unrelated-run"
        self._run_and_05_with_force_stop(transport)
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 41)
        self.assertEqual(transport.retry_calls, 1)
        self.assertIn("post-Retry Sources root", result.blocker)

    def test_post_retry_root_stale_historical_scan_blocks(self):
        executor, transport, _ = self._executor("AND-05")
        transport.scan_root_post_retry_presentation = (
            contract.ScanRootPresentation.HISTORICAL_LAST_SCAN
        )
        transport.scan_root_post_retry_state = "abandoned"
        transport.scan_root_post_retry_run_ref = "root-last-scan-run"
        self._run_and_05_with_force_stop(transport)
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 41)
        self.assertEqual(transport.retry_calls, 1)
        self.assertIn("post-Retry Sources root", result.blocker)

    def test_post_retry_root_foreign_identity_blocks(self):
        executor, transport, _ = self._executor("AND-05")
        transport.scan_root_post_retry_root_ref = "different-root"
        self._run_and_05_with_force_stop(transport)
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 41)
        self.assertIn("post-Retry Sources root", result.blocker)

    def test_successor_completed_with_issues_blocks_retry_acceptance(self):
        executor, transport, writer = self._executor("AND-05")
        transport.successor_state = contract.RecoveryState.COMPLETED_WITH_ISSUES
        self._run_and_05_with_force_stop(transport)
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 44)
        self.assertFalse(result.workflow_completed)
        self.assertIn("undecided", result.blocker)
        self.assertTrue(
            self._successor_terminal_keys(executor, writer, "terminal")
        )

    def test_successor_failed_disproves_retry_success(self):
        executor, transport, writer = self._executor("AND-05")
        transport.successor_state = contract.RecoveryState.FAILED
        self._run_and_05_with_force_stop(transport)
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "failed")
        self.assertEqual(result.completed_operations, 44)
        self.assertIn("disproves Retry success", result.blocker)
        self.assertTrue(
            self._successor_terminal_keys(executor, writer, "terminal")
        )
        self.assertTrue(
            self._successor_terminal_keys(executor, writer, "result")
        )

    def test_successor_cancelled_disproves_retry_success(self):
        executor, transport, _ = self._executor("AND-05")
        transport.successor_state = contract.RecoveryState.CANCELLED
        self._run_and_05_with_force_stop(transport)
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "failed")
        self.assertEqual(result.completed_operations, 44)

    def test_interrupted_retry_successor_is_terminal_and_failed_without_second_retry(self):
        executor, transport, writer = self._executor("AND-05")
        transport.successor_state = contract.RecoveryState.INTERRUPTED
        self._run_and_05_with_force_stop(transport)
        result = executor.execute(now=NOW)

        self.assertEqual(result.status, "failed")
        self.assertEqual(result.completed_operations, 44)
        self.assertEqual(transport.retry_calls, 1)
        self.assertTrue(
            self._assertion_recorded(
                executor,
                writer,
                "and-05-45",
                "terminal",
                evidence.AssertionOutcome.PASSED,
            )
        )
        self.assertTrue(
            self._assertion_recorded(
                executor,
                writer,
                "and-05-45",
                "result",
                evidence.AssertionOutcome.FAILED,
            )
        )

    def test_missing_progress_blocks_and_skips_dependents(self):
        executor, transport, writer = self._executor()
        transport.progress_available = False
        result = executor.execute(now=NOW)
        self.assertFalse(result.workflow_completed)
        self.assertEqual(result.completed_operations, 8)
        self.assertIn("progress", result.blocker)
        self.assertTrue(any(
            event == ("assertion", "not_run") for event in writer.events
        ))

    def test_and_05_missing_or_unchanged_progress_prevents_dependent_effects(self):
        for label, progress in (
            ("unavailable", None),
            (
                "unchanged",
                lambda parent_ref: _progress(1, parent=parent_ref),
            ),
            (
                "mismatched-parent",
                lambda parent_ref: _progress(1, parent="different-parent"),
            ),
        ):
            with self.subTest(label=label):
                executor, transport, _ = self._executor(
                    "AND-05",
                    authorization_id=f"session-progress-{label}",
                )
                if progress is None:
                    transport.progress_available = False
                else:
                    transport.observe_refresh_progress = (
                        lambda parent_ref, timeout, make=progress: make(parent_ref)
                    )
                result = executor.execute(now=NOW)
                self.assertEqual(result.status, "blocked")
                self.assertEqual(transport.force_stop_calls, 0)
                self.assertEqual(transport.retry_calls, 0)

    def test_issue_only_progress_cannot_authorize_process_loss_or_retry(self):
        executor, transport, _ = self._executor("AND-05")
        transport.observe_refresh_progress = lambda parent_ref, timeout: (
            contract.RefreshProgressFacts(
                "scan",
                None,
                None,
                "library_refresh.failed",
                2,
                parent_ref,
            )
        )
        result = executor.execute(now=NOW)

        self.assertEqual(result.status, "blocked")
        self.assertEqual(transport.force_stop_calls, 0)
        self.assertEqual(transport.retry_calls, 0)

    def test_scan_attribution_uses_parent_and_scanrun_not_view_job_as_scanrun(self):
        transport = ScriptedTransport("AND-04")
        # The root's View Job control targets the owning LibraryRefresh JobRun.
        executor, _, writer = self._executor(
            "AND-04",
            transport=transport,
        )

        executor.execute(now=NOW)

        self.assertTrue(
            self._assertion_recorded(
                executor,
                writer,
                "and-04-30",
                "refresh-scanrun-attribution",
                evidence.AssertionOutcome.PASSED,
            )
        )
        self.assertIn(
            ("open_scan_job_detail", transport.parent, None),
            transport.navigation_expectations,
        )

    def test_missing_identity_blocks_parent_scanrun_claim(self):
        executor, transport, writer = self._executor()
        original = ScriptedObserver.observe_identity
        def identity(observer, parent_ref, timeout):
            if parent_ref is None:
                return _identity(transport.parent)
            return _identity(None, scan_run_ids=())
        transport._identity_hook = identity
        observer = ScriptedObserver(transport)
        observer.observe_identity = lambda parent_ref, timeout: identity(observer, parent_ref, timeout)
        executor._observer = observer
        result = executor.execute(now=NOW)
        self.assertEqual(result.completed_operations, 14)
        self.assertIn("ScanRun scope is ambiguous", result.blocker)

    def test_duplicate_scanrun_blocks_initial_parent_attribution(self):
        transport = ScriptedTransport("AND-04")
        observer = ScriptedObserver(transport)
        original = observer.observe_identity

        def identity(parent_ref, timeout):
            observed = original(parent_ref, timeout)
            if parent_ref == transport.parent:
                relation = observed.scan_run_relations[0]
                return replace(
                    observed,
                    scan_run_relations=(relation, relation),
                )
            return observed

        observer.observe_identity = identity
        executor, _, _ = self._executor(
            "AND-04", transport=transport, observer=observer
        )
        result = executor.execute(now=NOW)

        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 14)
        self.assertEqual(transport.background_calls, 0)
        self.assertEqual(transport.force_stop_calls, 0)
        self.assertEqual(transport.retry_calls, 0)
        self.assertIn("attribution", result.blocker)

    def test_reused_terminal_baseline_job_id_blocks_new_refresh_dependents(self):
        baseline = _baseline(
            visible_refresh_row_count=1,
            terminal_refresh_run_refs=("parent-run",),
            job_states=(("parent-run", "completed"),),
        )
        transport = ScriptedTransport("AND-04")
        observer = ScriptedObserver(transport, baseline)

        def jobs(timeout):
            if not transport.start_refresh_calls:
                return replace(
                    _jobs(rows=1),
                    terminal_refresh_run_refs=("parent-run",),
                )
            return _jobs(
                parent=transport.parent,
                state=contract.RecoveryState.ACTIVE,
                rows=1,
                active=1,
            )

        transport.observe_jobs = jobs
        executor, _, _ = self._executor(
            "AND-04",
            baseline=baseline,
            baseline_job_states=(("parent-run", "completed"),),
            transport=transport,
            observer=observer,
        )
        result = executor.execute(now=NOW)

        self.assertEqual(result.status, "blocked")
        self.assertEqual(transport.start_refresh_calls, 1)
        self.assertEqual(transport.background_calls, 0)
        self.assertEqual(transport.force_stop_calls, 0)
        self.assertEqual(transport.retry_calls, 0)
        self.assertIsNone(executor._parent_ref)
        self.assertIn("ambiguous", result.blocker)

    def test_malformed_process_state_blocks_before_refresh_effect(self):
        transport = ScriptedTransport("AND-04")
        observer = ScriptedObserver(transport)
        executor, _, writer = self._executor(
            "AND-04", transport=transport, observer=observer
        )
        operation_id = self._operation_id_for_handler("AND-04", "start_refresh")
        self._override_process_for_operation(
            executor,
            observer,
            operation_id,
            lambda observed: replace(observed, process_state="present"),
        )
        result = executor.execute(now=NOW)

        self.assertEqual(result.status, "blocked")
        self.assertEqual(transport.start_refresh_calls, 0)
        self.assertFalse(
            self._assertion_recorded(
                executor,
                writer,
                operation_id,
                "intent",
                evidence.AssertionOutcome.NOT_RUN,
            )
        )

    def test_foreign_process_before_force_stop_is_failed_without_effect(self):
        transport = ScriptedTransport("AND-05")
        observer = ScriptedObserver(transport)
        executor, _, writer = self._executor(
            "AND-05", transport=transport, observer=observer
        )
        operation_id = self._operation_id_for_handler("AND-05", "pre_stop_guard")
        self._override_process_for_operation(
            executor,
            observer,
            operation_id,
            lambda observed: replace(observed, package_name="com.example.foreign"),
        )
        result = executor.execute(now=NOW)

        self.assertEqual(result.status, "failed")
        self.assertEqual(transport.force_stop_calls, 0)
        self.assertEqual(transport.retry_calls, 0)
        self.assertFalse(
            self._assertion_recorded(
                executor,
                writer,
                operation_id,
                "intent",
                evidence.AssertionOutcome.NOT_RUN,
            )
        )

    def test_pre_stop_guard_requires_exact_parent_detail_identity(self):
        cases = (
            ("missing", None, "blocked"),
            ("malformed", 123, "blocked"),
            ("different_valid", "different-parent", "failed"),
        )
        for case_name, parent_identity, expected_status in cases:
            with self.subTest(case=case_name):
                executor, transport, writer = self._executor(
                    "AND-05", authorization_id=f"pre-stop-parent-{case_name}"
                )
                guard_id = self._operation_id_for_handler(
                    "AND-05", "pre_stop_guard"
                )
                force_stop_id = self._operation_id_for_handler(
                    "AND-05", "force_stop"
                )
                self._override_detail_for_operation(
                    executor,
                    guard_id,
                    lambda detail: replace(
                        detail, parent_run_ref=parent_identity
                    ),
                )

                result = executor.execute(now=NOW)

                self.assertEqual(result.status, expected_status)
                self.assertEqual(result.completed_operations, 19)
                self.assertEqual(transport.force_stop_calls, 0)
                self.assertEqual(transport.retry_calls, 0)
                self.assertFalse(
                    self._assertion_recorded(
                        executor,
                        writer,
                        force_stop_id,
                        "intent",
                        evidence.AssertionOutcome.NOT_RUN,
                    )
                )
                if expected_status == "blocked":
                    self.assertTrue(
                        self._assertion_recorded(
                            executor,
                            writer,
                            guard_id,
                            "pre_stop_parent_identity_unavailable",
                            evidence.AssertionOutcome.BLOCKED,
                        )
                    )
                else:
                    self.assertTrue(
                        self._assertion_recorded(
                            executor,
                            writer,
                            guard_id,
                            "result",
                            evidence.AssertionOutcome.FAILED,
                        )
                    )

    def test_foreground_launch_requires_typed_process_observation(self):
        transport = ScriptedTransport("AND-05")
        observer = ScriptedObserver(transport)
        executor, _, _ = self._executor(
            "AND-05", transport=transport, observer=observer
        )
        operation_id = self._operation_id_for_handler("AND-05", "foreground_launched")
        self._override_process_for_operation(
            executor,
            observer,
            operation_id,
            lambda observed: replace(observed, process_state="present"),
        )
        result = executor.execute(now=NOW)

        self.assertEqual(result.status, "blocked")
        self.assertEqual(transport.launch_calls, 1)
        self.assertEqual(transport.retry_calls, 0)

    def test_restore_foreground_classifies_post_effect_process_contradiction(self):
        transport = ScriptedTransport("AND-04")
        observer = ScriptedObserver(transport)
        executor, _, _ = self._executor(
            "AND-04", transport=transport, observer=observer
        )
        operation_id = self._operation_id_for_handler("AND-04", "restore_foreground")
        self._override_process_for_operation(
            executor,
            observer,
            operation_id,
            lambda observed: replace(observed, package_name="com.example.foreign"),
            occurrence=2,
        )
        result = executor.execute(now=NOW)

        self.assertEqual(result.status, "failed")
        self.assertEqual(transport.restore_calls, 1)

    def test_successor_terminal_requires_valid_process_observation(self):
        transport = ScriptedTransport("AND-05")
        transport.successor_state = contract.RecoveryState.COMPLETED
        observer = ScriptedObserver(transport)
        executor, _, writer = self._executor(
            "AND-05", transport=transport, observer=observer
        )
        operation_id = self._operation_id_for_handler("AND-05", "successor_terminal")
        self._override_process_for_operation(
            executor,
            observer,
            operation_id,
            lambda observed: replace(observed, package_name="com.example.foreign"),
        )
        self._run_and_05_with_force_stop(transport)
        result = executor.execute(now=NOW)

        self.assertEqual(result.status, "failed")
        self.assertEqual(transport.retry_calls, 1)
        self.assertFalse(
            self._assertion_recorded(
                executor,
                writer,
                operation_id,
                "terminal",
                evidence.AssertionOutcome.PASSED,
            )
        )

    def test_foreground_task_continuity_mismatch_fails(self):
        executor, transport, writer = self._executor()
        transport.fail_foreground_continuity = True
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "failed")
        self.assertEqual(result.completed_operations, 20)

    def test_and_05_completed_before_stop_blocks_without_effects(self):
        executor, transport, writer = self._executor("AND-05")
        transport.complete_before_stop = True
        result = executor.execute(now=NOW)
        self.assertEqual(result.completed_operations, 19)
        self.assertIn("terminal", result.blocker)
        self.assertEqual(transport.force_stop_calls, 0)
        self.assertEqual(transport.retry_calls, 0)

    def test_and_05_unproven_process_absence_prevents_relaunch(self):
        executor, transport, writer = self._executor("AND-05")
        transport.force_stop_verified_absent = False
        result = executor.execute(now=NOW)
        self.assertEqual(result.completed_operations, 21)
        self.assertEqual(transport.launch_calls, 0)
        self.assertIn("absence", result.blocker)

    def test_process_absent_requires_qualification_package_identity(self):
        transport = ScriptedTransport("AND-05")
        observer = ScriptedObserver(transport)
        original = observer.observe_process

        def process(package, timeout):
            observed = original(package, timeout)
            if observed.process_state is contract.ProcessState.ABSENT:
                return replace(observed, package_name="com.example.foreign")
            return observed

        observer.observe_process = process
        executor, _, _ = self._executor("AND-05", transport=transport, observer=observer)
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "failed")
        self.assertEqual(result.completed_operations, 21)
        self.assertIn("process_package_mismatch", result.blocker)
        self.assertEqual(transport.launch_calls, 0)
        self.assertEqual(transport.retry_calls, 0)

    def test_process_absent_missing_foreground_identity_blocks_relaunch(self):
        transport = ScriptedTransport("AND-05")
        observer = ScriptedObserver(transport)
        executor, _, _ = self._executor(
            "AND-05",
            transport=transport,
            observer=observer,
        )
        operation_id = self._operation_id_for_handler("AND-05", "process_absent")
        self._override_process_for_operation(
            executor,
            observer,
            operation_id,
            lambda observed: replace(observed, foreground_package=None),
        )

        self._run_and_05_with_force_stop(transport)
        result = executor.execute(now=NOW)

        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 21)
        self.assertIn("unavailable", result.blocker)
        self.assertEqual(transport.launch_calls, 0)
        self.assertEqual(transport.retry_calls, 0)

    def test_launch_requires_foreground_identity_in_fresh_process_check(self):
        transport = ScriptedTransport("AND-05")
        observer = ScriptedObserver(transport)
        executor, _, writer = self._executor(
            "AND-05",
            transport=transport,
            observer=observer,
        )
        operation_id = self._operation_id_for_handler("AND-05", "launch")
        self._override_process_for_operation(
            executor,
            observer,
            operation_id,
            lambda observed: replace(observed, foreground_package=None),
        )

        result = executor.execute(now=NOW)

        self.assertEqual(transport.force_stop_calls, 1)
        self.assertEqual(transport.launch_calls, 0)
        self.assertEqual(transport.retry_calls, 0)
        self.assertFalse(
            self._assertion_recorded(
                executor,
                writer,
                operation_id,
                "intent",
                evidence.AssertionOutcome.NOT_RUN,
            )
        )
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 22)
        self.assertIn("foreground", result.blocker)

    def test_launch_fails_if_target_remains_foreground_in_fresh_process_check(self):
        transport = ScriptedTransport("AND-05")
        observer = ScriptedObserver(transport)
        executor, _, writer = self._executor(
            "AND-05",
            transport=transport,
            observer=observer,
        )
        operation_id = self._operation_id_for_handler("AND-05", "launch")
        self._override_process_for_operation(
            executor,
            observer,
            operation_id,
            lambda observed: replace(
                observed,
                foreground_package=contract.JOB_LIFECYCLE_QUALIFICATION_PACKAGE,
            ),
        )

        result = executor.execute(now=NOW)

        self.assertEqual(transport.force_stop_calls, 1)
        self.assertEqual(transport.launch_calls, 0)
        self.assertEqual(transport.retry_calls, 0)
        self.assertFalse(
            self._assertion_recorded(
                executor,
                writer,
                operation_id,
                "intent",
                evidence.AssertionOutcome.NOT_RUN,
            )
        )
        self.assertEqual(result.status, "failed")
        self.assertEqual(result.completed_operations, 22)
        self.assertIn("remains in the foreground", result.blocker)

    def test_background_process_package_contradiction_is_failed(self):
        transport = ScriptedTransport("AND-04")
        observer = ScriptedObserver(transport)
        executor, _, _ = self._executor(
            transport=transport,
            observer=observer,
        )
        self._override_process_for_operation(
            executor,
            observer,
            "and-04-19",
            lambda observed: replace(
                observed,
                package_name="com.example.foreign",
            ),
        )

        result = executor.execute(now=NOW)

        self.assertEqual(result.status, "failed")
        self.assertEqual(result.completed_operations, 18)
        self.assertIn("process_package_mismatch", result.blocker)

    def test_foreground_restore_missing_identity_is_blocked(self):
        for field in ("foreground_package", "task_continuity_ref"):
            with self.subTest(field=field):
                transport = ScriptedTransport("AND-04")
                observer = ScriptedObserver(transport)
                executor, _, _ = self._executor(
                    authorization_id=f"foreground-identity-{field}",
                    transport=transport,
                    observer=observer,
                )
                self._override_process_for_operation(
                    executor,
                    observer,
                    "and-04-21",
                    lambda observed, field=field: replace(observed, **{field: None}),
                )

                result = executor.execute(now=NOW)

                self.assertEqual(result.status, "blocked")
                self.assertEqual(result.completed_operations, 20)
                self.assertIn("unavailable", result.blocker)

    def test_foreign_parent_blocks_before_background_effect(self):
        transport = ScriptedTransport("AND-04")
        observer = ScriptedObserver(transport)
        executor, _, _ = self._executor(
            transport=transport,
            observer=observer,
        )
        original = observer.observe_identity

        def identity(parent_ref, timeout):
            observed = original(parent_ref, timeout)
            attempted = executor._attempted_operation
            if attempted is not None and attempted.operation_id == "and-04-15":
                return _identity("other-parent")
            return observed

        observer.observe_identity = identity
        result = executor.execute(now=NOW)

        self.assertEqual(result.status, "failed")
        self.assertEqual(result.completed_operations, 14)

    def test_parent_scanrun_scope_mismatch_blocks_before_dependent_effects(self):
        for scenario in ("AND-04", "AND-05"):
            with self.subTest(scenario=scenario):
                transport = ScriptedTransport(scenario)
                observer = ScriptedObserver(transport)
                executor, _, _ = self._executor(
                    scenario,
                    authorization_id=f"scope-drift-{scenario}",
                    transport=transport,
                    observer=observer,
                )
                operation_id = self._operation_id_for_handler(
                    scenario,
                    "parent_child_identity",
                )
                original = observer.observe_identity

                def identity(parent_ref, timeout):
                    observed = original(parent_ref, timeout)
                    attempted = executor._attempted_operation
                    if (
                        attempted is not None
                        and attempted.operation_id == operation_id
                    ):
                        return replace(
                            observed,
                            frozen_scope_ref="scope-ref-changed",
                        )
                    return observed

                observer.observe_identity = identity
                result = executor.execute(now=NOW)

                expected_completed = next(
                    spec.index - 1
                    for spec in contract.JOB_LIFECYCLE_OPERATIONS[scenario]
                    if spec.handler == "parent_child_identity"
                )
                self.assertEqual(result.status, "blocked")
                self.assertEqual(result.completed_operations, expected_completed)
                self.assertIn("scope", result.blocker)
                self.assertEqual(transport.force_stop_calls, 0)
                self.assertEqual(transport.retry_calls, 0)

    def test_parent_root_partition_change_with_stable_scope_ref_blocks(self):
        for scenario in ("AND-04", "AND-05"):
            with self.subTest(scenario=scenario):
                transport = ScriptedTransport(scenario)
                observer = ScriptedObserver(transport)
                executor, _, writer = self._executor(
                    scenario,
                    authorization_id=f"root-partition-drift-{scenario}",
                    transport=transport,
                    observer=observer,
                )
                operation_id = self._operation_id_for_handler(
                    scenario,
                    "parent_child_identity",
                )
                original = observer.observe_identity

                def identity(parent_ref, timeout):
                    observed = original(parent_ref, timeout)
                    attempted = executor._attempted_operation
                    if (
                        attempted is not None
                        and attempted.operation_id == operation_id
                    ):
                        added_root = "root-ref-added-after-arrival"
                        return replace(
                            observed,
                            requested_root_refs=(
                                observed.requested_root_refs + (added_root,)
                            ),
                            excluded_root_refs=(
                                observed.excluded_root_refs + (added_root,)
                            ),
                        )
                    return observed

                observer.observe_identity = identity
                result = executor.execute(now=NOW)

                expected_completed = next(
                    spec.index - 1
                    for spec in contract.JOB_LIFECYCLE_OPERATIONS[scenario]
                    if spec.handler == "parent_child_identity"
                )
                self.assertEqual(result.status, "blocked")
                self.assertEqual(result.completed_operations, expected_completed)
                self.assertIn("scope", result.blocker)
                self.assertEqual(transport.background_calls, 0)
                self.assertEqual(transport.force_stop_calls, 0)
                self.assertEqual(transport.retry_calls, 0)
                self.assertTrue(
                    self._assertion_recorded(
                        executor,
                        writer,
                        operation_id,
                        "parent_child_scope_mismatch",
                        evidence.AssertionOutcome.BLOCKED,
                    )
                )

    def test_retry_outcome_blocks_changed_captured_source_scanrun_set(self):
        transport = ScriptedTransport("AND-05")
        observer = ScriptedObserver(transport)
        executor, _, writer = self._executor(
            "AND-05", transport=transport, observer=observer
        )
        original = observer.observe_identity

        def identity(parent_ref, timeout):
            observed = original(parent_ref, timeout)
            attempted = executor._attempted_operation
            if attempted is not None and attempted.operation_id == "and-05-36":
                return replace(
                    observed,
                    scan_run_relations=tuple(
                        replace(
                            relation,
                            scan_run_ref=relation.scan_run_ref + "-changed",
                        )
                        for relation in observed.scan_run_relations
                    ),
                )
            return observed

        observer.observe_identity = identity
        self._run_and_05_with_force_stop(transport)

        result = executor.execute(now=NOW)

        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 35)
        self.assertEqual(transport.retry_calls, 1)
        self.assertTrue(
            self._assertion_recorded(
                executor,
                writer,
                "and-05-36",
                "scan_run_relationship_ambiguous",
                evidence.AssertionOutcome.BLOCKED,
            )
        )

    def test_retry_successor_scanrun_owner_mismatch_blocks_relation(self):
        transport = ScriptedTransport("AND-05")
        observer = ScriptedObserver(transport)
        executor, _, _ = self._executor(
            "AND-05",
            transport=transport,
            observer=observer,
        )
        original = observer.observe_identity

        def identity(parent_ref, timeout):
            observed = original(parent_ref, timeout)
            attempted = executor._attempted_operation
            if attempted is not None and attempted.operation_id == "and-05-37":
                return replace(
                    observed,
                    successor_scan_run_relations=(
                        contract.ScanRunRelation(
                            parent_run_ref=transport.parent,
                            scan_run_ref="wrong-scan-run",
                            root_ref="root-ref-synthetic",
                        ),
                    ),
                )
            return observed

        observer.observe_identity = identity
        self._run_and_05_with_force_stop(transport)

        result = executor.execute(now=NOW)

        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 36)
        self.assertEqual(transport.retry_calls, 1)
        self.assertIn("successor identity", result.blocker)

    def test_evidence_append_failure_blocks_owner_recovery(self):
        executor, transport, writer = self._executor()
        writer.fail_assertion = True
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertIn("owner recovery", result.blocker)
        self.assertEqual(writer.terminal.outcome, evidence.TerminalOutcome.BLOCKED)

    def test_exact_type_gate_rejects_subclass(self):
        class Impostor(lifecycle_executor._JobLifecycleOperationExecutor):
            pass

        executor, _, _ = self._executor()
        impostor = Impostor(
            session=executor._session,
            transport=executor._transport,
            observer=executor._observer,
            writer=executor._writer,
            evidence_spec=executor._spec,
        )
        with self.assertRaises(admission._AddScanStop):
            admission._execute_closed_admitted_session(impostor, now=NOW)

    def test_unrelated_executor_is_rejected(self):
        with self.assertRaises(admission._AddScanStop):
            admission._execute_closed_admitted_session(object(), now=NOW)

    def test_baseline_change_after_admission_fails(self):
        executor, _, _ = self._executor()
        executor._observer.observe_baseline = lambda timeout: _baseline(
            selected_root_ref="changed-root"
        )
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "failed")
        self.assertEqual(result.completed_operations, 0)
        self.assertIn("baseline", result.blocker)

    def test_jobs_preflight_permits_independently_identified_terminal_history(self):
        executor, transport, _ = self._executor(
            baseline=_baseline(
                visible_refresh_row_count=1,
                terminal_refresh_run_refs=("terminal-ref-0",),
                job_states=(("terminal-ref-0", "completed"),),
            ),
            baseline_job_states=(("terminal-ref-0", "completed"),),
        )
        transport.jobs_preflight_rows = 1
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 31)

    def test_jobs_preflight_conflicting_active_refresh_blocks(self):
        executor, transport, _ = self._executor()
        transport.jobs_preflight_rows = 1
        transport.jobs_preflight_active = 1
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 4)
        self.assertIn("active refresh", result.blocker)
        self.assertEqual(transport.start_refresh_calls, 0)

    def test_jobs_preflight_incomplete_history_blocks(self):
        executor, transport, _ = self._executor(
            baseline=_baseline(
                visible_refresh_row_count=2,
                terminal_refresh_run_refs=("terminal-ref-0", "terminal-ref-1"),
            )
        )
        transport.jobs_preflight_rows = 2
        transport.jobs_preflight_history_complete = False
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 4)
        self.assertEqual(transport.start_refresh_calls, 0)

    def test_jobs_preflight_rejects_unexpected_terminal_history(self):
        executor, transport, _ = self._executor()
        transport.jobs_preflight_rows = 1
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 4)
        self.assertIn("admitted baseline", result.blocker)
        self.assertEqual(transport.start_refresh_calls, 0)

    def test_jobs_preflight_rejects_missing_terminal_history(self):
        executor, transport, _ = self._executor(
            baseline=_baseline(
                visible_refresh_row_count=1,
                terminal_refresh_run_refs=("terminal-ref-0",),
            )
        )
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 4)
        self.assertIn("admitted baseline", result.blocker)
        self.assertEqual(transport.start_refresh_calls, 0)

    def test_jobs_preflight_rejects_substituted_terminal_identity(self):
        executor, transport, _ = self._executor(
            baseline=_baseline(
                visible_refresh_row_count=1,
                terminal_refresh_run_refs=("different-terminal-ref",),
            )
        )
        transport.jobs_preflight_rows = 1
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 4)
        self.assertIn("admitted baseline", result.blocker)
        self.assertEqual(transport.start_refresh_calls, 0)

    def test_jobs_preflight_rejects_ambiguous_active_identity(self):
        executor, transport, _ = self._executor()
        transport.observe_jobs = lambda timeout: _jobs(
            parent="ghost-run",
            state=contract.RecoveryState.ACTIVE,
        )
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 4)
        self.assertIn("ambiguous", result.blocker)
        self.assertEqual(transport.start_refresh_calls, 0)

    def test_changed_target_blocks_before_each_navigation_and_effect(self):
        cases = (
            ("navigate_library", "AND-04", 1),
            ("start_library_refresh", "AND-04", 6),
            ("background_qualification_package", "AND-04", 17),
            ("return_existing_qualification_task", "AND-04", 19),
            ("navigate_sources", "AND-04", 25),
            ("open_scan_root", "AND-04", 26),
            ("open_scan_job_detail", "AND-04", 28),
            ("restore_qualification_foreground", "AND-04", 30),
            ("force_stop_qualification_package", "AND-05", 20),
            ("launch_qualification_package", "AND-05", 22),
            ("retry_library_refresh", "AND-05", 34),
            ("open_retry_successor_detail", "AND-05", 43),
        )
        for action, scenario, completed in cases:
            with self.subTest(action=action):
                executor, transport, _ = self._executor(
                    scenario,
                    authorization_id=f"session-target-{action}",
                )
                if scenario == "AND-05":
                    def force_stop(package, timeout):
                        transport.force_stop_calls += 1
                        transport.process_state = contract.ProcessState.ABSENT
                        transport.foreground = "com.android.launcher3"
                        transport.detail_state = contract.RecoveryState.ABANDONED

                    transport.force_stop_package = force_stop
                transport.fail_verify_action = action
                result = executor.execute(now=NOW)
                self.assertEqual(result.status, "blocked")
                self.assertEqual(result.completed_operations, completed)
                self.assertIn("changed", result.blocker)
                self.assertNotIn(action, transport.navigations)
        executor, transport, _ = self._executor("AND-04")
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        for serial, target_ref, _, package in transport.verify_target_calls:
            self.assertEqual(serial, _SERIAL)
            self.assertEqual(target_ref, executor._session.authorization.target_ref)
            self.assertEqual(package, QUALIFICATION_PACKAGE)
        expectations = {
            action: (expected_run_ref, expected_root_ref)
            for action, expected_run_ref, expected_root_ref
            in transport.navigation_expectations
        }
        self.assertEqual(
            expectations["open_refresh_detail"][0],
            transport.parent,
        )
        self.assertEqual(
            expectations["open_scan_root"][1],
            "root-ref-synthetic",
        )
        self.assertEqual(
            expectations["open_scan_job_detail"][0],
            transport.parent,
        )

    def test_navigation_intent_failure_prevents_dispatch(self):
        executor, transport, writer = self._executor()
        writer.fail_assertion_after = 1
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 1)
        self.assertEqual(transport.navigations, [])
        self.assertIn("could not be durably appended", result.blocker)

    def test_navigation_deadline_before_transport_is_not_uncertain(self):
        executor, transport, writer = self._executor()
        record_intent = executor._record_intent
        dispatch_patch = mock.patch.object(
            lifecycle_executor,
            "_authorized_transport_call",
            side_effect=admission._OperationDeadlineExpired,
        )

        def expire_after_intent(operation):
            record_intent(operation)
            if operation.operation_id == "and-04-02":
                dispatch_patch.start()

        executor._record_intent = expire_after_intent
        try:
            result = executor.execute(now=NOW)
        finally:
            dispatch_patch.stop()

        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 1)
        self.assertEqual(transport.navigations, [])
        self.assertIn("deadline expired", result.blocker)
        self.assertNotIn("uncertain", result.blocker)
        self.assertTrue(
            self._assertion_recorded(
                executor,
                writer,
                "and-04-02",
                "navigation_not_dispatched",
                evidence.AssertionOutcome.BLOCKED,
            )
        )

    def test_navigation_deadline_after_transport_invocation_is_uncertain(self):
        executor, transport, _ = self._executor()
        record_intent = executor._record_intent

        def expire_after_dispatch(session, budget, operation):
            operation(1)
            raise admission._OperationDeadlineExpired()

        dispatch_patch = mock.patch.object(
            lifecycle_executor,
            "_authorized_transport_call",
            side_effect=expire_after_dispatch,
        )

        def expire_after_dispatch_ready(operation):
            record_intent(operation)
            if operation.operation_id == "and-04-02":
                dispatch_patch.start()

        executor._record_intent = expire_after_dispatch_ready
        try:
            result = executor.execute(now=NOW)
        finally:
            dispatch_patch.stop()

        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 1)
        self.assertEqual(transport.navigations, ["navigate_library"])
        self.assertIn("uncertain", result.blocker)

    def test_navigation_persists_intent_before_dispatch_and_result_after(self):
        executor, transport, writer = self._executor()
        assertion_counts = []

        def navigate(action, timeout, **kwargs):
            assertion_counts.append(writer.assertion_count)
            transport.navigations.append(action)
            return True

        transport.navigate = navigate
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertGreaterEqual(assertion_counts[0], 2)
        result_key = admission._add_scan_alias(
            "operation",
            f"{executor._spec.session_id}:and-04-02:result",
        )
        intent_key = admission._add_scan_alias(
            "operation",
            f"{executor._spec.session_id}:and-04-02:intent",
        )
        keys = [key for key, _ in writer.assertion_keys]
        self.assertLess(keys.index(intent_key), keys.index(result_key))
        self.assertIn(
            (result_key, evidence.AssertionOutcome.PASSED.value),
            writer.assertion_keys,
        )

    def test_uncertain_navigation_acknowledgement_stops_without_replay(self):
        executor, transport, _ = self._executor()

        def uncertain(action, timeout, **kwargs):
            transport.navigations.append(action)
            return False

        transport.navigate = uncertain
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 1)
        self.assertEqual(transport.navigations, ["navigate_library"])
        self.assertIn("uncertain", result.blocker)

    def test_navigation_result_failure_stops_without_replay(self):
        executor, transport, writer = self._executor()
        writer.fail_assertion_after = 2
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 1)
        self.assertEqual(transport.navigations, ["navigate_library"])
        self.assertIn("result", result.blocker)

    def test_unexpected_handler_exception_records_one_blocked_attempt(self):
        executor, transport, writer = self._executor()
        def raise_before_assertion(operation, spec):
            raise ValueError("malformed observation")

        executor._step_navigate_library = raise_before_assertion
        result = executor.execute(now=NOW)

        self.assertEqual(result.status, "blocked")
        self.assertEqual(
            writer.assertion_keys[1][1], evidence.AssertionOutcome.BLOCKED.value
        )
        self.assertTrue(any(
            outcome == evidence.AssertionOutcome.NOT_RUN.value
            for _, outcome in writer.assertion_keys
        ))
        self.assertEqual(transport.navigations, [])

    def test_dispatch_guard_records_failure_before_handler_starts(self):
        executor, transport, writer = self._executor()

        def fail_current_operation(operation):
            raise ValueError("malformed operation context")

        executor._current_operation = fail_current_operation
        result = executor.execute(now=NOW)

        fallback_id = executor._request(
            "and-04-01:operation-outcome-unrecorded"
        ).operation_id
        intent_id = executor._request("and-04-01:intent").operation_id
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 0)
        self.assertEqual(transport.navigations, [])
        self.assertNotEqual(fallback_id, intent_id)
        self.assertFalse(
            any(key == intent_id for key, _ in writer.assertion_keys)
        )
        self.assertEqual(
            sum(key == fallback_id for key, _ in writer.assertion_keys), 1
        )
        self.assertEqual(
            sum(
                outcome == evidence.AssertionOutcome.BLOCKED.value
                for key, outcome in writer.assertion_keys
                if key == fallback_id
            ),
            1,
        )

    def test_unexpected_handler_with_existing_categorical_assertion_is_not_duplicated(self):
        executor, transport, writer = self._executor()
        def block_then_raise(operation, spec):
            executor._append_assertion(
                "surface_unavailable", evidence.AssertionOutcome.BLOCKED
            )
            raise ValueError("observer decode failed")

        executor._step_navigate_library = block_then_raise
        executor.execute(now=NOW)
        blocked_id = executor._request("surface_unavailable").operation_id
        fallback_id = executor._request(
            "and-04-02:operation-outcome-unrecorded"
        ).operation_id
        self.assertEqual(
            sum(key == blocked_id for key, _ in writer.assertion_keys), 1
        )
        self.assertFalse(any(key == fallback_id for key, _ in writer.assertion_keys))
        self.assertEqual(transport.navigations, [])

    def test_pass_after_block_does_not_hide_handler_abort(self):
        executor, transport, writer = self._executor()

        def block_pass_then_raise(operation, spec):
            executor._append_assertion(
                "initial_check_blocked", evidence.AssertionOutcome.BLOCKED
            )
            executor._append_assertion(
                "later_check_passed", evidence.AssertionOutcome.PASSED
            )
            raise ValueError("later operation work failed")

        executor._step_navigate_library = block_pass_then_raise
        result = executor.execute(now=NOW)

        fallback_id = executor._request(
            "and-04-02:operation-outcome-unrecorded"
        ).operation_id
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 1)
        self.assertIn(
            (fallback_id, evidence.AssertionOutcome.BLOCKED.value),
            writer.assertion_keys,
        )
        self.assertEqual(transport.navigations, [])

    def test_persisted_pass_does_not_mask_later_handler_exception(self):
        executor, transport, writer = self._executor()

        def pass_then_raise(operation, spec):
            executor._record_result(operation, True)
            raise ValueError("later observation failed")

        executor._step_navigate_library = pass_then_raise
        result = executor.execute(now=NOW)

        passed_id = executor._request("and-04-02:result").operation_id
        fallback_id = executor._request(
            "and-04-02:operation-outcome-unrecorded"
        ).operation_id
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 1)
        self.assertEqual(
            sum(key == passed_id for key, _ in writer.assertion_keys), 1
        )
        self.assertEqual(
            sum(key == fallback_id for key, _ in writer.assertion_keys), 1
        )
        self.assertIn(
            (fallback_id, evidence.AssertionOutcome.BLOCKED.value),
            writer.assertion_keys,
        )
        self.assertEqual(transport.navigations, [])

    def test_operation_fallback_append_failure_is_explicit_integrity_block(self):
        executor, _, writer = self._executor()
        def raise_before_assertion(operation, spec):
            writer.fail_next_assertion = True
            raise ValueError("malformed observation")

        executor._step_navigate_library = raise_before_assertion
        result = executor.execute(now=NOW)

        self.assertEqual(result.status, "blocked")
        self.assertIn("could not be durably appended", result.blocker)
        self.assertFalse(any(
            key == executor._request(
                "and-04-02:operation-outcome-unrecorded"
            ).operation_id
            for key, _ in writer.assertion_keys
        ))

    def test_outcome_append_failure_reports_integrity_without_retrying_append(self):
        executor, transport, writer = self._executor()

        def pass_then_fail_append(operation, spec):
            executor._record_result(operation, True)
            writer.fail_next_assertion = True
            executor._record_blocked(operation, "later_observation_failed")

        executor._step_navigate_library = pass_then_fail_append
        result = executor.execute(now=NOW)

        passed_id = executor._request("and-04-02:result").operation_id
        fallback_id = executor._request(
            "and-04-02:operation-outcome-unrecorded"
        ).operation_id
        self.assertEqual(result.status, "blocked")
        self.assertIn("could not be durably appended", result.blocker)
        self.assertEqual(
            sum(key == passed_id for key, _ in writer.assertion_keys), 1
        )
        self.assertFalse(any(key == fallback_id for key, _ in writer.assertion_keys))
        self.assertEqual(transport.navigations, [])

    def test_skipped_operations_receive_deterministic_not_run_assertions(self):
        executor, transport, writer = self._executor()
        transport.observe_library = lambda timeout: replace(
            _library(), membership_count=None
        )
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 2)
        expected = {
            admission._add_scan_alias(
                "operation",
                f"{executor._spec.session_id}:{operation.operation_id}:not-run",
            )
            for operation in executor._planned_operations[3:]
        }
        actual = {
            key
            for key, outcome in writer.assertion_keys
            if outcome == evidence.AssertionOutcome.NOT_RUN.value
        }
        self.assertTrue(expected <= actual)

    def test_uncertain_refresh_start_stops_before_progress(self):
        executor, transport, writer = self._executor()

        def fail_refresh(timeout):
            raise RuntimeError("transport failed")

        transport.start_refresh = fail_refresh
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 6)
        self.assertIn("Library Refresh start", result.blocker)
        self.assertTrue(result.scope_extensions)
        self.assertEqual(writer.terminal.outcome, evidence.TerminalOutcome.BLOCKED)

    def test_uncertain_background_stops_before_return(self):
        executor, transport, _ = self._executor()

        def fail_background(package, timeout):
            raise RuntimeError("transport failed")

        transport.background_package = fail_background
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 17)
        self.assertIn("background transition", result.blocker)

    def test_uncertain_existing_task_return_stops_before_foreground_claim(self):
        executor, transport, _ = self._executor()

        def fail_return(package, task_ref, timeout):
            raise RuntimeError("transport failed")

        transport.return_existing_task = fail_return
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 19)
        self.assertIn("foreground return", result.blocker)

    def test_restoration_foreground_mismatch_blocks(self):
        executor, transport, _ = self._executor()

        def restore_to_launcher(package, task_ref, timeout):
            transport.foreground = "com.android.launcher3"

        transport.restore_foreground = restore_to_launcher
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 30)
        self.assertIn("restoration", result.blocker)

    def test_retry_successor_already_present_does_not_dispatch(self):
        executor, transport, _ = self._executor("AND-05")
        transport.already_retried = True

        def force_stop(package, timeout):
            transport.force_stop_calls += 1
            transport.process_state = contract.ProcessState.ABSENT
            transport.foreground = "com.android.launcher3"
            transport.detail_state = contract.RecoveryState.ABANDONED

        transport.force_stop_package = force_stop
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 34)
        self.assertEqual(transport.retry_calls, 0)
        self.assertIn("retry successor", result.blocker)

    def test_retry_relation_mismatch_fails_without_second_effect(self):
        executor, transport, _ = self._executor("AND-05")
        transport.retry_source_override = "different-source"

        def force_stop(package, timeout):
            transport.force_stop_calls += 1
            transport.process_state = contract.ProcessState.ABSENT
            transport.foreground = "com.android.launcher3"
            transport.detail_state = contract.RecoveryState.ABANDONED

        transport.force_stop_package = force_stop
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "failed")
        self.assertEqual(result.completed_operations, 36)
        self.assertEqual(transport.retry_calls, 1)

    def test_retry_relation_scope_change_blocks_without_second_effect(self):
        transport = ScriptedTransport("AND-05")

        class ScopeChangingObserver(ScriptedObserver):
            def __init__(self, transport):
                super().__init__(transport)
                self.successor_calls = 0

            def observe_identity(self, parent_ref, timeout):
                value = super().observe_identity(parent_ref, timeout)
                if parent_ref == self.transport.parent and self.transport.retry_calls:
                    self.successor_calls += 1
                    if self.successor_calls >= 2:
                        return replace(value, successor_scope_ref="different-scope")
                return value

        observer = ScopeChangingObserver(transport)
        executor, transport, _ = self._executor(
            "AND-05", transport=transport, observer=observer
        )

        def force_stop(package, timeout):
            transport.force_stop_calls += 1
            transport.process_state = contract.ProcessState.ABSENT
            transport.foreground = "com.android.launcher3"
            transport.detail_state = contract.RecoveryState.ABANDONED

        transport.force_stop_package = force_stop
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 36)
        self.assertEqual(transport.retry_calls, 1)
        self.assertIn("scope", result.blocker)

    def test_retry_outcome_blocks_unproven_source_lookup_without_pass_evidence(self):
        invalid_markers = (
            ("missing", {"retry_relation_lookup_completed": None}),
            ("false", {"retry_relation_lookup_completed": False}),
            ("malformed", {"retry_relation_lookup_completed": 1}),
            ("foreign-source", {"retry_lookup_source_run_ref": "foreign-parent"}),
        )
        for label, changes in invalid_markers:
            with self.subTest(marker=label):
                executor, transport, writer = self._executor(
                    "AND-05", authorization_id=f"retry-outcome-lookup-{label}"
                )
                observer = executor._observer
                original = observer.observe_identity

                def observe_identity(parent_ref, timeout):
                    identity = original(parent_ref, timeout)
                    if transport.retry_calls:
                        return replace(identity, **changes)
                    return identity

                observer.observe_identity = observe_identity
                self._force_stop_into(transport, contract.RecoveryState.FAILED)
                result = executor.execute(now=NOW)

                self.assertEqual(result.status, "blocked")
                self.assertEqual(result.completed_operations, 35)
                self.assertEqual(transport.retry_calls, 1)
                self.assertEqual(writer.assertion_keys[-1][1], "blocked")

    def test_retry_relation_rechecks_independent_source_lookup_before_detail(self):
        invalid_markers = (
            ("missing", {"retry_relation_lookup_completed": None}),
            ("false", {"retry_relation_lookup_completed": False}),
            ("malformed", {"retry_relation_lookup_completed": 1}),
            ("foreign-source", {"retry_lookup_source_run_ref": "foreign-parent"}),
        )
        for label, changes in invalid_markers:
            with self.subTest(marker=label):
                executor, transport, writer = self._executor(
                    "AND-05", authorization_id=f"retry-relation-lookup-{label}"
                )
                observer = executor._observer
                original = observer.observe_identity
                original_detail = transport.observe_refresh_detail
                post_retry_observations = 0
                successor_detail_observations = 0

                def observe_identity(parent_ref, timeout):
                    nonlocal post_retry_observations
                    identity = original(parent_ref, timeout)
                    if transport.retry_calls:
                        post_retry_observations += 1
                        if post_retry_observations == 2:
                            return replace(identity, **changes)
                    return identity

                def observe_detail(parent_ref, timeout):
                    nonlocal successor_detail_observations
                    if parent_ref == transport.successor:
                        successor_detail_observations += 1
                    return original_detail(parent_ref, timeout)

                observer.observe_identity = observe_identity
                transport.observe_refresh_detail = observe_detail
                self._force_stop_into(transport, contract.RecoveryState.FAILED)
                result = executor.execute(now=NOW)

                self.assertEqual(result.status, "blocked")
                self.assertEqual(result.completed_operations, 36)
                self.assertEqual(post_retry_observations, 2)
                self.assertEqual(successor_detail_observations, 0)
                self.assertEqual(transport.retry_calls, 1)
                self.assertEqual(writer.assertion_keys[-1][1], "blocked")

    def test_retry_relation_observer_source_mismatch_blocks_without_terminal_claim(self):
        transport = ScriptedTransport("AND-05")

        class SourceChangingObserver(ScriptedObserver):
            def observe_identity(self, parent_ref, timeout):
                value = super().observe_identity(parent_ref, timeout)
                attempted = getattr(self, "executor", None)
                attempted = (
                    None if attempted is None else attempted._attempted_operation
                )
                if (
                    self.transport.retry_calls
                    and parent_ref == self.transport.parent
                    and attempted is not None
                    and attempted.operation_id == self.target_operation_id
                ):
                    return replace(value, source_run_ref="different-source")
                return value

        observer = SourceChangingObserver(transport)
        observer.target_operation_id = self._operation_id_for_handler(
            "AND-05", "retry_relation"
        )
        executor, transport, writer = self._executor(
            "AND-05", transport=transport, observer=observer
        )
        observer.executor = executor
        self._force_stop_into(transport, contract.RecoveryState.ABANDONED)
        relation_id = observer.target_operation_id

        result = executor.execute(now=NOW)

        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 36)
        self.assertEqual(transport.force_stop_calls, 1)
        self.assertEqual(transport.launch_calls, 1)
        self.assertEqual(transport.retry_calls, 1)
        self.assertTrue(
            self._assertion_recorded(
                executor,
                writer,
                relation_id,
                "retry_successor_scope_mismatch",
                evidence.AssertionOutcome.BLOCKED,
            )
        )

    def test_retry_relation_detail_requires_observer_provenance(self):
        transport = ScriptedTransport("AND-05")
        observer = ScriptedObserver(transport)
        executor, _, writer = self._executor(
            "AND-05", transport=transport, observer=observer
        )
        self._force_stop_into(transport, contract.RecoveryState.ABANDONED)
        relation_id = self._operation_id_for_handler("AND-05", "retry_relation")
        original_identity = observer.observe_identity

        def identity(parent_ref, timeout):
            observed = original_identity(parent_ref, timeout)
            attempted = executor._attempted_operation
            if attempted is not None and attempted.operation_id == relation_id:
                self.assertTrue(observed.retry_complete())
            return observed

        observer.observe_identity = identity
        self._override_detail_for_operation(
            executor,
            relation_id,
            lambda detail: replace(detail, observer_ref=None),
        )

        result = executor.execute(now=NOW)

        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 36)
        self.assertEqual(transport.retry_calls, 1)
        self.assertTrue(
            self._assertion_recorded(
                executor,
                writer,
                relation_id,
                "retry_successor_detail_observer_unavailable",
                evidence.AssertionOutcome.BLOCKED,
            )
        )
        self.assertFalse(
            self._assertion_recorded(
                executor,
                writer,
                relation_id,
                "result",
                evidence.AssertionOutcome.PASSED,
            )
        )

    def test_retry_relation_accepts_optional_unrelated_detail_fields(self):
        transport = ScriptedTransport("AND-05")
        executor, _, writer = self._executor("AND-05", transport=transport)
        self._force_stop_into(transport, contract.RecoveryState.ABANDONED)
        relation_id = self._operation_id_for_handler("AND-05", "retry_relation")
        self._override_detail_for_operation(
            executor,
            relation_id,
            lambda detail: replace(
                detail,
                state=None,
                progress=None,
                retry_control_count=None,
                retry_successor_run_ref=None,
                cancellation_requested=None,
            ),
        )

        result = executor.execute(now=NOW)

        self.assertEqual(transport.retry_calls, 1)
        self.assertTrue(
            self._assertion_recorded(
                executor,
                writer,
                relation_id,
                "result",
                evidence.AssertionOutcome.PASSED,
            )
        )

    def test_retry_relation_identity_contradiction_precedes_missing_provenance(self):
        cases = (
            ("foreign_parent", "different-parent", "different-source"),
            ("foreign_source", "different-parent", "different-source"),
        )
        for case_name, parent_ref, source_ref in cases:
            with self.subTest(case=case_name):
                transport = ScriptedTransport("AND-05")
                executor, _, writer = self._executor(
                    "AND-05", transport=transport,
                    authorization_id=f"retry-relation-identity-{case_name}",
                )
                self._force_stop_into(transport, contract.RecoveryState.ABANDONED)
                relation_id = self._operation_id_for_handler(
                    "AND-05", "retry_relation"
                )
                self._override_detail_for_operation(
                    executor,
                    relation_id,
                    lambda detail: replace(
                        detail,
                        parent_run_ref=(
                            parent_ref
                            if case_name == "foreign_parent"
                            else detail.parent_run_ref
                        ),
                        retry_source_run_ref=(
                            source_ref
                            if case_name == "foreign_source"
                            else detail.retry_source_run_ref
                        ),
                        observer_ref=None,
                    ),
                )

                result = executor.execute(now=NOW)

                self.assertEqual(result.status, "failed")
                self.assertEqual(result.completed_operations, 36)
                self.assertEqual(transport.retry_calls, 1)
                self.assertTrue(
                    self._assertion_recorded(
                        executor,
                        writer,
                        relation_id,
                        "result",
                        evidence.AssertionOutcome.FAILED,
                    )
                )
        self.assertFalse(
            self._successor_terminal_keys(executor, writer, "terminal")
        )

    def _run_and_05_with_force_stop(self, transport):
        def force_stop(package, timeout):
            transport.force_stop_calls += 1
            transport.process_state = contract.ProcessState.ABSENT
            transport.foreground = "com.android.launcher3"
            transport.detail_state = contract.RecoveryState.ABANDONED

        transport.force_stop_package = force_stop
        return transport

    def test_library_loss_during_recovery_fails_before_retry_can_recreate_it(self):
        executor, transport, _ = self._executor("AND-05")
        transport.library_membership_ids_after_stop = ("replacement-asset",)
        transport.library_membership_ids_after_retry = ("fixture-synthetic",)
        transport.library_identity_continuity_after_stop = _complete_no_redirect(
            transport.parent, ("fixture-synthetic",)
        )
        self._run_and_05_with_force_stop(transport)
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "failed")
        self.assertEqual(result.completed_operations, 28)
        self.assertEqual(transport.retry_calls, 0)
        self.assertEqual(transport.library_observations_after_stop, 1)
        self.assertEqual(
            transport.library_membership_ids_after_stop,
            ("replacement-asset",),
        )
        self.assertIn("disappeared during recovery", result.blocker)

    def test_unresolved_game_id_continuity_blocks_before_retry_intent(self):
        executor, transport, writer = self._executor("AND-05")
        transport.library_membership_ids_after_stop = ("replacement-asset",)
        transport.library_identity_continuity_after_stop = (
            contract.GameIdContinuityObservation(
                transport.parent,
                (
                    contract.GameIdRedirect(
                        "fixture-synthetic", "intermediate-asset", transport.parent
                    ),
                    contract.GameIdRedirect(
                        "intermediate-asset", "replacement-asset", transport.parent
                    ),
                ),
                True,
                "continuity-observer",
                ("fixture-synthetic",),
            )
        )
        self._run_and_05_with_force_stop(transport)

        result = executor.execute(now=NOW)

        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 28)
        self.assertEqual(transport.retry_calls, 0)
        intent_key = admission._add_scan_alias(
            "operation", f"{executor._spec.session_id}:and-05-35:intent"
        )
        self.assertFalse(any(key == intent_key for key, _ in writer.assertion_keys))

    def test_scan_root_preloss_presentation_unidentified_blocks_before_stop(self):
        executor, transport, _ = self._executor("AND-05")
        transport.scan_root_presentation_override = (
            contract.ScanRootPresentation.UNIDENTIFIED
        )
        self._run_and_05_with_force_stop(transport)
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 14)
        self.assertEqual(transport.force_stop_calls, 0)
        self.assertEqual(transport.retry_calls, 0)
        self.assertIn("pre-loss Sources root", result.blocker)

    def test_scan_root_preloss_run_identity_unavailable_blocks(self):
        executor, transport, _ = self._executor("AND-05")
        transport.scan_root_run_ref = None
        self._run_and_05_with_force_stop(transport)
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 14)
        self.assertEqual(transport.force_stop_calls, 0)
        self.assertIn("pre-loss Sources root", result.blocker)

    def test_scan_root_preloss_root_identity_contradiction_blocks(self):
        executor, transport, _ = self._executor("AND-05")
        transport.scan_root_ref_override = "different-root"
        self._run_and_05_with_force_stop(transport)
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 14)
        self.assertEqual(transport.force_stop_calls, 0)
        self.assertIn("pre-loss Sources root", result.blocker)

    def test_scan_root_recovered_active_presentation_blocks_retry(self):
        executor, transport, _ = self._executor("AND-05")
        transport.scan_root_recovered_presentation = (
            contract.ScanRootPresentation.ACTIVE_SCAN
        )
        transport.scan_root_recovered_state = None
        self._run_and_05_with_force_stop(transport)
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 26)
        self.assertEqual(transport.force_stop_calls, 1)
        self.assertEqual(transport.retry_calls, 0)
        self.assertIn("recovered Sources root", result.blocker)

    def test_scan_root_recovered_contradictory_active_state_blocks(self):
        executor, transport, _ = self._executor("AND-05")
        transport.scan_root_recovered_presentation = (
            contract.ScanRootPresentation.ACTIVE_SCAN
        )
        transport.scan_root_recovered_state = "complete"
        self._run_and_05_with_force_stop(transport)
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 26)
        self.assertEqual(transport.retry_calls, 0)
        self.assertIn("scan_root_relation_unavailable", result.blocker)

    def test_scan_root_historical_preloss_persistence_is_supported(self):
        executor, transport, _ = self._executor("AND-05")
        transport.scan_root_preloss_presentation = (
            contract.ScanRootPresentation.HISTORICAL_LAST_SCAN
        )
        transport.scan_root_preloss_state = "abandoned"
        transport.scan_root_recovered_state = "abandoned"
        self._run_and_05_with_force_stop(transport)
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 45)
        self.assertTrue(result.workflow_completed)
        self.assertIn("physical", result.blocker)

    def test_preloss_root_scanrun_mismatch_blocks_before_stop(self):
        executor, transport, writer = self._executor("AND-05")
        transport.scan_root_run_ref = "unrelated-root-run"
        self._run_and_05_with_force_stop(transport)
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 19)
        self.assertEqual(transport.force_stop_calls, 0)
        self.assertEqual(transport.retry_calls, 0)
        self.assertIn("scan_run_relation_ambiguous", result.blocker)

    def test_library_equal_count_replacement_after_recovery_fails(self):
        executor, transport, _ = self._executor("AND-05")
        transport.library_membership_ids_after_stop = ("replacement-asset",)
        transport.library_identity_continuity_after_stop = _complete_no_redirect(
            transport.parent, ("fixture-synthetic",)
        )
        self._run_and_05_with_force_stop(transport)
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "failed")
        self.assertEqual(result.completed_operations, 28)
        self.assertIn("disappeared", result.blocker)

    def test_library_higher_count_replacement_after_recovery_fails(self):
        executor, transport, _ = self._executor("AND-05")
        transport.library_memberships = [1, 1, 2]
        transport.library_membership_ids_after_stop = (
            "replacement-asset-a",
            "replacement-asset-b",
        )
        transport.library_identity_continuity_after_stop = _complete_no_redirect(
            transport.parent, ("fixture-synthetic",)
        )
        self._run_and_05_with_force_stop(transport)
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "failed")
        self.assertEqual(result.completed_operations, 28)
        self.assertIn("disappeared", result.blocker)

    def test_library_missing_post_loss_identity_observation_blocks(self):
        executor, transport, _ = self._executor("AND-05")
        self._run_and_05_with_force_stop(transport)
        original = transport.observe_library

        def observe(timeout):
            observed = original(timeout)
            if transport.force_stop_calls:
                return replace(observed, membership_ids=None)
            return observed

        transport.observe_library = observe
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 28)
        self.assertEqual(transport.retry_calls, 0)
        self.assertIn("identities are BLOCKED", result.blocker)

    def test_library_missing_preloss_identity_blocks_before_process_loss(self):
        executor, transport, _ = self._executor("AND-05")
        transport.membership_identity_available = False
        self._run_and_05_with_force_stop(transport)
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 11)
        self.assertEqual(transport.force_stop_calls, 0)
        self.assertEqual(transport.retry_calls, 0)

    def test_library_missing_admitted_asset_before_stop_fails(self):
        executor, transport, _ = self._executor("AND-05")
        transport.library_membership_ids = ("replacement-asset",)
        transport.library_identity_continuity_before_stop = _complete_no_redirect(
            transport.parent, ("fixture-synthetic",)
        )
        self._run_and_05_with_force_stop(transport)
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "failed")
        self.assertEqual(result.completed_operations, 11)
        self.assertEqual(transport.force_stop_calls, 0)
        self.assertIn("already missing", result.blocker)

    def test_library_retained_identities_with_new_assets_pass(self):
        executor, transport, _ = self._executor("AND-05")
        transport.library_memberships = [1, 1, 2, 2]
        transport.library_membership_ids_after_stop = (
            "fixture-synthetic",
            "new-asset",
        )
        self._run_and_05_with_force_stop(transport)
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 45)
        self.assertIn("physical", result.blocker)

    def test_scan_run_identity_ambiguity_blocks(self):
        executor, transport, _ = self._executor()
        transport.scan_run_id_override = "different-scan-run"
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 29)
        self.assertIn("ScanRun state", result.blocker)

    def test_successor_still_active_at_deadline_blocks_without_second_retry(self):
        executor, transport, _ = self._executor("AND-05")
        transport.successor_stays_active = True

        def force_stop(package, timeout):
            transport.force_stop_calls += 1
            transport.process_state = contract.ProcessState.ABSENT
            transport.foreground = "com.android.launcher3"
            transport.detail_state = contract.RecoveryState.ABANDONED

        transport.force_stop_package = force_stop
        clock = _Clock(step=61.0)
        executor._monotonic = clock.monotonic
        executor._sleeper = clock.sleep
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 44)
        self.assertEqual(transport.retry_calls, 1)
        self.assertIn("remained active", result.blocker)

    def test_successor_state_unavailable_at_deadline_blocks(self):
        executor, transport, _ = self._executor("AND-05")
        transport.successor_state = None

        def force_stop(package, timeout):
            transport.force_stop_calls += 1
            transport.process_state = contract.ProcessState.ABSENT
            transport.foreground = "com.android.launcher3"
            transport.detail_state = contract.RecoveryState.ABANDONED

        transport.force_stop_package = force_stop
        clock = _Clock(step=61.0)
        executor._monotonic = clock.monotonic
        executor._sleeper = clock.sleep
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 44)
        self.assertEqual(transport.retry_calls, 1)
        self.assertIn("terminal state was unavailable", result.blocker)

    def test_successor_terminal_without_expected_foreground_blocks(self):
        executor, transport, _ = self._executor("AND-05")
        transport.fail_successor_foreground = True

        def force_stop(package, timeout):
            transport.force_stop_calls += 1
            transport.process_state = contract.ProcessState.ABSENT
            transport.foreground = "com.android.launcher3"
            transport.detail_state = contract.RecoveryState.ABANDONED

        transport.force_stop_package = force_stop
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 44)
        self.assertIn("qualification foreground", result.blocker)

    def test_terminal_receipt_mismatch_blocks(self):
        executor, _, writer = self._executor()
        writer.terminal_session_id = "different-session"
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertIn("receipt", result.blocker)

    def test_terminal_append_failure_requires_owner_recovery(self):
        executor, _, writer = self._executor()
        writer.fail_terminal = True
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertIn("owner recovery", result.blocker)
        self.assertIsNone(writer.terminal)

    def test_non_utc_execution_time_is_rejected(self):
        executor, _, _ = self._executor()
        result = executor.execute(now=datetime(2030, 1, 1))
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 0)
        self.assertIn("UTC", result.blocker)

    def test_expired_session_is_rejected_before_dispatch(self):
        executor, _, _ = self._executor()
        result = executor.execute(now=NOW + timedelta(seconds=900))
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 0)

    def test_wrong_evidence_spec_blocks_before_dispatch(self):
        executor, _, _ = self._executor()
        executor._spec = object()
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 0)
        self.assertIn("artifact, plan, target", result.blocker)

    def test_pending_restoration_obligation_blocks_before_dispatch(self):
        executor, _, _ = self._executor()
        with mock.patch.object(
            lifecycle_executor,
            "_pending_for_device",
            return_value=object(),
        ):
            result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 0)
        self.assertIn("unresolved restoration obligation", result.blocker)

    def test_safety_state_unavailable_blocks_before_dispatch(self):
        executor, _, _ = self._executor()
        with mock.patch.object(
            lifecycle_executor,
            "_pending_for_device",
            side_effect=lifecycle_executor.SafetyStateError(),
        ):
            result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 0)
        self.assertIn("Device restoration state", result.blocker)

    def test_second_execution_cannot_reuse_the_private_capability(self):
        executor, _, _ = self._executor()
        self.assertEqual(executor.execute(now=NOW).completed_operations, 31)
        again = executor.execute(now=NOW)
        self.assertEqual(again.status, "blocked")
        self.assertEqual(again.completed_operations, 0)
        self.assertIn("capability", again.blocker)

    def test_failed_capability_claim_does_not_close_the_admitted_session(self):
        executor, _, _ = self._executor()
        with mock.patch.object(
            admission,
            "_claim_job_lifecycle_execution",
            return_value=False,
        ):
            blocked = executor.execute(now=NOW)
        self.assertEqual(blocked.status, "blocked")
        self.assertEqual(blocked.completed_operations, 0)
        self.assertIsNotNone(
            admission._admitted_session_binding(executor._session)
        )
        completed = executor.execute(now=NOW)
        self.assertEqual(completed.completed_operations, 31)

    def test_invalid_library_observation_blocks(self):
        executor, transport, _ = self._executor()
        transport.observe_library = lambda timeout: None
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 2)

    def test_invalid_jobs_observation_blocks(self):
        executor, transport, _ = self._executor()
        transport.observe_jobs = lambda timeout: None
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 4)

    def test_active_jobs_row_must_match_the_observed_parent(self) -> None:
        executor, transport, _ = self._executor()

        def jobs(timeout):
            if transport.progress_calls == 0:
                return _jobs()
            return _jobs(
                parent="different-parent",
                state=contract.RecoveryState.ACTIVE,
                rows=1,
                active=1,
            )

        transport.observe_jobs = jobs
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "failed")
        self.assertEqual(result.completed_operations, 11)

    def test_active_jobs_malformed_parent_identity_blocks(self):
        for case_name, invalid_parent in (("empty", ""), ("wrong_type", 123)):
            with self.subTest(case=case_name):
                executor, transport, writer = self._executor(
                    authorization_id=f"active-jobs-parent-{case_name}"
                )

                def jobs(timeout):
                    if transport.progress_calls == 0:
                        return _jobs()
                    return replace(
                        _jobs(
                            parent=transport.parent,
                            state=contract.RecoveryState.ACTIVE,
                            rows=1,
                            active=1,
                        ),
                        parent_run_ref=invalid_parent,
                    )

                transport.observe_jobs = jobs
                jobs_active_id = self._operation_id_for_handler(
                    "AND-04", "jobs_active"
                )
                background_id = self._operation_id_for_handler(
                    "AND-04", "background"
                )

                result = executor.execute(now=NOW)

                self.assertEqual(result.status, "blocked")
                self.assertEqual(result.completed_operations, 11)
                self.assertEqual(transport.background_calls, 0)
                self.assertTrue(
                    self._assertion_recorded(
                        executor,
                        writer,
                        jobs_active_id,
                        "parent_state_unavailable",
                        evidence.AssertionOutcome.BLOCKED,
                    )
                )
                self.assertFalse(
                    self._assertion_recorded(
                        executor,
                        writer,
                        background_id,
                        "intent",
                        evidence.AssertionOutcome.NOT_RUN,
                    )
                )

    def test_refresh_detail_must_match_the_observed_parent(self) -> None:
        executor, transport, _ = self._executor()

        def detail(parent_ref, timeout):
            return replace(
                _detail("different-parent", contract.RecoveryState.ACTIVE),
                observer_ref=None,
            )

        transport.observe_refresh_detail = detail
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "failed")
        self.assertEqual(result.completed_operations, 13)

    def test_initial_refresh_detail_requires_observer_provenance(self):
        for scenario in ("AND-04", "AND-05"):
            with self.subTest(scenario=scenario):
                executor, _, writer = self._executor(
                    scenario, authorization_id=f"initial-detail-proof-{scenario}"
                )
                detail_id = self._operation_id_for_handler(
                    scenario, "refresh_detail"
                )
                self._override_detail_for_operation(
                    executor,
                    detail_id,
                    lambda detail: replace(detail, observer_ref=None),
                )

                result = executor.execute(now=NOW)

                detail_index = next(
                    item.index
                    for item in contract.JOB_LIFECYCLE_OPERATIONS[scenario]
                    if item.handler == "refresh_detail"
                )
                self.assertEqual(result.status, "blocked")
                self.assertEqual(result.completed_operations, detail_index - 1)
                self.assertTrue(
                    self._assertion_recorded(
                        executor,
                        writer,
                        detail_id,
                        "refresh_detail_observer_unavailable",
                        evidence.AssertionOutcome.BLOCKED,
                    )
                )
                self.assertFalse(
                    self._assertion_recorded(
                        executor,
                        writer,
                        detail_id,
                        "result",
                        evidence.AssertionOutcome.PASSED,
                    )
                )

    def test_background_must_leave_the_qualification_foreground(self) -> None:
        executor, transport, _ = self._executor()

        def no_background(package, timeout):
            return None

        transport.background_package = no_background
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "failed")
        self.assertEqual(result.completed_operations, 18)

    def test_background_without_foreground_identity_blocks(self) -> None:
        executor, transport, _ = self._executor()
        transport.background_foreground = None
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 18)
        self.assertIn("foreground identity", result.blocker)

    def test_recovered_jobs_must_keep_the_original_parent(self) -> None:
        executor, transport, _ = self._executor()
        calls = 0

        def jobs(timeout):
            nonlocal calls
            calls += 1
            if calls == 1:
                return _jobs()
            if calls == 2:
                return _jobs(
                    parent=transport.parent,
                    state=contract.RecoveryState.ACTIVE,
                    rows=1,
                    active=1,
                )
            return _jobs(
                parent="different-parent",
                state=contract.RecoveryState.ABANDONED,
                rows=1,
                active=0,
            )

        transport.observe_jobs = jobs
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 22)
        self.assertIn("parent", result.blocker)

    def test_recovered_detail_must_keep_the_original_parent(self) -> None:
        executor, transport, _ = self._executor()
        calls = 0

        def detail(parent_ref, timeout):
            nonlocal calls
            calls += 1
            state = transport.detail_state
            if calls == 1:
                return _detail(transport.parent, state, progress=_progress(2))
            return _detail("different-parent", state, progress=_progress(2))

        transport.observe_refresh_detail = detail
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "failed")
        self.assertEqual(result.completed_operations, 24)

    def test_pre_stop_detail_requires_observer_provenance_before_force_stop(self):
        executor, transport, writer = self._executor(
            "AND-05", authorization_id="pre-stop-detail-observer-proof"
        )
        guard_id = self._operation_id_for_handler("AND-05", "pre_stop_guard")
        force_stop_id = self._operation_id_for_handler("AND-05", "force_stop")
        self._override_detail_for_operation(
            executor,
            guard_id,
            lambda detail: replace(detail, observer_ref=None),
        )

        result = executor.execute(now=NOW)

        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 19)
        self.assertEqual(transport.force_stop_calls, 0)
        self.assertEqual(transport.retry_calls, 0)
        self.assertTrue(
            self._assertion_recorded(
                executor,
                writer,
                guard_id,
                "pre_stop_observer_unavailable",
                evidence.AssertionOutcome.BLOCKED,
            )
        )
        self.assertFalse(
            self._assertion_recorded(
                executor,
                writer,
                guard_id,
                "result",
                evidence.AssertionOutcome.PASSED,
            )
        )
        self.assertFalse(
            any(f":{force_stop_id}:" in key for key, _ in writer.assertion_keys)
        )

    def test_pre_stop_process_presence_is_required(self) -> None:
        transport = ScriptedTransport("AND-05")
        observer = ScriptedObserver(transport)
        original = observer.observe_process

        def process(package, timeout):
            if transport.start_refresh_calls:
                return _process(
                    contract.ProcessState.UNKNOWN,
                    "com.android.launcher3",
                )
            return original(package, timeout)

        observer.observe_process = process
        executor, _, _ = self._executor(
            "AND-05",
            transport=transport,
            observer=observer,
        )
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 19)
        self.assertIn("process", result.blocker)

    def test_invalid_scan_root_observation_blocks(self) -> None:
        executor, transport, _ = self._executor()
        transport.observe_scan_root = lambda root_ref, timeout: None
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 27)

    def test_uncertain_restoration_effect_blocks(self) -> None:
        executor, transport, _ = self._executor()

        def fail_restore(package, task_ref, timeout):
            raise RuntimeError("transport failed")

        transport.restore_foreground = fail_restore
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 30)
        self.assertIn("restoration foreground return", result.blocker)

    def test_unproven_library_surface_blocks_before_jobs(self) -> None:
        executor, transport, _ = self._executor()
        transport.observe_library = lambda timeout: replace(
            _library(), membership_count=None
        )
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 2)
        self.assertIn("Library surface", result.blocker)

    def test_unproven_jobs_surface_blocks_preflight(self) -> None:
        executor, transport, _ = self._executor()
        transport.observe_jobs = lambda timeout: replace(_jobs(), observer_ref=None)
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 4)
        self.assertIn("Jobs surface", result.blocker)

    def test_unproven_active_jobs_surface_blocks(self) -> None:
        executor, transport, _ = self._executor()
        original = transport.observe_jobs
        calls = 0

        def jobs(timeout):
            nonlocal calls
            calls += 1
            if calls == 2:
                return replace(
                    _jobs(
                        parent=transport.parent,
                        state=contract.RecoveryState.ACTIVE,
                        rows=1,
                        active=1,
                    ),
                    observer_ref=None,
                )
            return original(timeout)

        transport.observe_jobs = jobs
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 11)
        self.assertIn("Jobs surface", result.blocker)

    def test_refresh_detail_progress_contradiction_fails(self) -> None:
        executor, transport, _ = self._executor()
        transport.observe_refresh_detail = lambda parent_ref, timeout: _detail(
            transport.parent,
            contract.RecoveryState.ACTIVE,
            progress=_progress(4, total=3),
        )
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "failed")
        self.assertEqual(result.completed_operations, 13)
        self.assertIn("refresh_progress_contradiction", result.blocker)

    def test_refresh_progress_without_status_key_blocks(self) -> None:
        executor, transport, _ = self._executor()
        transport.observe_refresh_detail = lambda parent_ref, timeout: _detail(
            transport.parent,
            contract.RecoveryState.ACTIVE,
            progress=contract.RefreshProgressFacts(
                "scan", 1, 3, None, 0, transport.parent
            ),
        )
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 13)
        self.assertIn("refresh_status_key_unavailable", result.blocker)

    def test_parent_scanrun_attribution_unavailable_blocks(self) -> None:
        transport = ScriptedTransport("AND-04")
        observer = ScriptedObserver(transport)

        def identity(parent_ref, timeout):
            if parent_ref is None:
                return _identity(transport.parent, state=contract.RecoveryState.ACTIVE)
            return _identity(parent_ref, scan_run_ids=())

        observer.observe_identity = identity
        executor, _, _ = self._executor(transport=transport, observer=observer)
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 14)
        self.assertIn("ScanRun scope is ambiguous", result.blocker)
        self.assertTrue(result.scope_extensions)

    def test_parent_jobrun_identity_classifies_unavailable_and_mismatch(self):
        cases = (
            ("missing", None, "blocked"),
            ("malformed", 123, "blocked"),
            ("different_valid", "different-parent", "failed"),
        )
        for case_name, parent_identity, expected_status in cases:
            with self.subTest(case=case_name):
                transport = ScriptedTransport("AND-04")
                observer = ScriptedObserver(transport)
                original = observer.observe_identity

                def identity(parent_ref, timeout):
                    observed = original(parent_ref, timeout)
                    if parent_ref is not None:
                        return replace(observed, parent_run_ref=parent_identity)
                    return observed

                observer.observe_identity = identity
                executor, transport, writer = self._executor(
                    "AND-04",
                    authorization_id=f"child-parent-{case_name}",
                    transport=transport,
                    observer=observer,
                )
                operation_id = self._operation_id_for_handler(
                    "AND-04", "parent_child_identity"
                )

                result = executor.execute(now=NOW)

                self.assertEqual(result.status, expected_status)
                self.assertEqual(result.completed_operations, 14)
                self.assertEqual(transport.start_refresh_calls, 1)
                self.assertEqual(transport.background_calls, 0)
                self.assertEqual(transport.force_stop_calls, 0)
                self.assertEqual(transport.retry_calls, 0)
                suffix = (
                    "parent_child_attribution_unavailable"
                    if expected_status == "blocked"
                    else "result"
                )
                outcome = (
                    evidence.AssertionOutcome.BLOCKED
                    if expected_status == "blocked"
                    else evidence.AssertionOutcome.FAILED
                )
                self.assertTrue(
                    self._assertion_recorded(
                        executor, writer, operation_id, suffix, outcome
                    )
                )

    def test_library_active_refresh_unproven_blocks(self) -> None:
        executor, transport, _ = self._executor()
        transport.observe_library = lambda timeout: _library(active=False)
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 16)
        self.assertIn("active refresh", result.blocker)

    def test_background_process_state_unknown_blocks(self) -> None:
        transport = ScriptedTransport("AND-04")
        observer = ScriptedObserver(transport)
        original = observer.observe_process

        def process(package, timeout):
            if transport.start_refresh_calls:
                return _process(
                    contract.ProcessState.UNKNOWN,
                    "com.android.launcher3",
                )
            return original(package, timeout)

        observer.observe_process = process
        executor, _, _ = self._executor(transport=transport, observer=observer)
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 17)
        self.assertIn("package state", result.blocker)

    def test_foreground_return_state_unknown_blocks(self) -> None:
        executor, transport, _ = self._executor()

        def return_task(package, task_ref, timeout):
            transport.foreground = package
            transport.process_state = contract.ProcessState.UNKNOWN

        transport.return_existing_task = return_task
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 20)
        self.assertIn("foreground process state", result.blocker)

    def test_jobs_returned_surface_unproven_blocks(self) -> None:
        executor, transport, _ = self._executor()
        original = transport.observe_jobs
        calls = 0

        def jobs(timeout):
            nonlocal calls
            calls += 1
            if calls == 3:
                return replace(
                    _jobs(
                        parent=transport.parent,
                        state=contract.RecoveryState.ACTIVE,
                        rows=1,
                    ),
                    observer_ref=None,
                )
            return original(timeout)

        transport.observe_jobs = jobs
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 22)
        self.assertIn("Jobs surface", result.blocker)

    def test_completed_before_process_loss_blocks_retry_obligations(self) -> None:
        executor, transport, _ = self._executor("AND-05")
        self._force_stop_into(transport, contract.RecoveryState.COMPLETED)
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 32)
        self.assertIn("terminal_before_process_loss_proven", result.blocker)

    def test_interrupted_recovery_state_fails(self) -> None:
        executor, transport, _ = self._executor("AND-05")
        self._force_stop_into(transport, contract.RecoveryState.INTERRUPTED)
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "failed")
        self.assertEqual(result.completed_operations, 32)
        self.assertIn("unsupported_interrupted_state", result.blocker)

    def test_library_preloss_requires_active_refresh(self) -> None:
        executor, transport, _ = self._executor("AND-05")
        transport.observe_library = lambda timeout: _library(active=False)
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 11)
        self.assertIn("pre-loss Library", result.blocker)

    def test_pre_stop_parent_state_unavailable_blocks(self) -> None:
        executor, transport, _ = self._executor("AND-05")
        original = transport.observe_refresh_detail
        calls = 0

        def detail(parent_ref, timeout):
            nonlocal calls
            calls += 1
            if calls == 2:
                return _detail(transport.parent, None)
            return original(parent_ref, timeout)

        transport.observe_refresh_detail = detail
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 19)
        self.assertIn("pre-stop parent state", result.blocker)

    def test_pre_stop_unknown_state_blocks(self) -> None:
        executor, transport, _ = self._executor("AND-05")
        original = transport.observe_refresh_detail
        calls = 0

        def detail(parent_ref, timeout):
            nonlocal calls
            calls += 1
            if calls == 2:
                return _detail(transport.parent, "unknown")
            return original(parent_ref, timeout)

        transport.observe_refresh_detail = detail
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 19)
        self.assertIn("state is not proven", result.blocker)

    def test_recovered_lifecycle_missing_state_blocks_without_retry(self):
        executor, transport, _ = self._executor("AND-05")
        self._force_stop_into(transport, contract.RecoveryState.FAILED)
        original = transport.observe_refresh_detail

        def detail(parent_ref, timeout):
            if transport.force_stop_calls:
                return _detail(parent_ref, None)
            return original(parent_ref, timeout)

        transport.observe_refresh_detail = detail
        result = executor.execute(now=NOW)

        self.assertEqual(result.status, "blocked")
        self.assertEqual(transport.retry_calls, 0)
        self.assertIn("lifecycle state is unavailable", result.blocker)

    def test_and_04_terminal_detail_requires_observer_provenance(self):
        clock = _Clock(step=1.0)
        executor, _, writer = self._executor(
            "AND-04", monotonic=clock.monotonic, sleeper=clock.sleep
        )
        operation_id = self._operation_id_for_handler("AND-04", "recovered_lifecycle")
        self._override_detail_for_operation(
            executor,
            operation_id,
            lambda detail: replace(
                detail,
                state=contract.RecoveryState.COMPLETED,
                observer_ref=None,
            ),
        )

        result = executor.execute(now=NOW)

        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 24)
        self.assertTrue(
            self._assertion_recorded(
                executor,
                writer,
                operation_id,
                "recovered_state_unavailable",
                evidence.AssertionOutcome.BLOCKED,
            )
        )
        self.assertFalse(
            self._assertion_recorded(
                executor,
                writer,
                operation_id,
                "result",
                evidence.AssertionOutcome.PASSED,
            )
        )

    def test_and_05_recovered_detail_requires_observer_provenance(self):
        executor, transport, writer = self._executor("AND-05")
        self._force_stop_into(transport, contract.RecoveryState.ABANDONED)
        operation_id = self._operation_id_for_handler("AND-05", "recovered_lifecycle")
        retry_id = self._operation_id_for_handler("AND-05", "retry")
        self._override_detail_for_operation(
            executor,
            operation_id,
            lambda detail: replace(detail, observer_ref=None),
        )

        result = executor.execute(now=NOW)

        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 32)
        self.assertEqual(transport.retry_calls, 0)
        self.assertTrue(
            self._assertion_recorded(
                executor,
                writer,
                operation_id,
                "recovered_observer_unavailable",
                evidence.AssertionOutcome.BLOCKED,
            )
        )
        self.assertFalse(
            self._assertion_recorded(
                executor,
                writer,
                operation_id,
                "recovery-consistency",
                evidence.AssertionOutcome.PASSED,
            )
        )
        self.assertFalse(
            any(f":{retry_id}:" in key for key, _ in writer.assertion_keys)
        )

    def test_uncertain_force_stop_blocks_before_relaunch(self) -> None:
        executor, transport, _ = self._executor("AND-05")

        def fail_stop(package, timeout):
            transport.force_stop_calls += 1
            raise RuntimeError("stop failed")

        transport.force_stop_package = fail_stop
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 20)
        self.assertIn("qualification process stop", result.blocker)

    def test_uncertain_relaunch_blocks_before_foreground_claim(self) -> None:
        executor, transport, _ = self._executor("AND-05")

        def fail_launch(package, timeout):
            raise RuntimeError("launch failed")

        transport.launch_package = fail_launch
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 22)
        self.assertIn("qualification relaunch", result.blocker)

    def test_relaunch_without_expected_foreground_blocks(self) -> None:
        executor, transport, _ = self._executor("AND-05")

        def launch(package, timeout):
            transport.launch_calls += 1
            transport.process_state = contract.ProcessState.PRESENT
            transport.foreground = "com.android.launcher3"

        transport.launch_package = launch
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 23)
        self.assertIn("relaunched qualification shell", result.blocker)

    def test_recovered_jobs_surface_unproven_blocks(self) -> None:
        executor, transport, _ = self._executor("AND-05")
        self._force_stop_into(transport, contract.RecoveryState.FAILED)
        original = transport.observe_jobs
        calls = 0

        def jobs(timeout):
            nonlocal calls
            calls += 1
            if calls == 2:
                return replace(
                    _jobs(
                        parent=transport.parent,
                        state=contract.RecoveryState.FAILED,
                        rows=1,
                    ),
                    observer_ref=None,
                )
            return original(timeout)

        transport.observe_jobs = jobs
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 30)
        self.assertIn("recovered Jobs state", result.blocker)

    def test_recovered_jobs_state_unavailable_blocks(self) -> None:
        executor, transport, _ = self._executor("AND-05")
        self._force_stop_into(transport, contract.RecoveryState.FAILED)
        original = transport.observe_jobs
        calls = 0

        def jobs(timeout):
            nonlocal calls
            calls += 1
            if calls == 2:
                return _jobs(parent=transport.parent, state=None, rows=1)
            return original(timeout)

        transport.observe_jobs = jobs
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 30)
        self.assertIn("recovered parent state", result.blocker)

    def test_recovered_jobs_malformed_parent_identity_blocks_before_retry(self):
        for case_name, invalid_parent in (("empty", ""), ("wrong_type", 123)):
            with self.subTest(case=case_name):
                executor, transport, writer = self._executor(
                    "AND-05", authorization_id=f"recovered-jobs-parent-{case_name}"
                )
                self._force_stop_into(transport, contract.RecoveryState.FAILED)
                original = transport.observe_jobs
                calls = 0

                def jobs(timeout):
                    nonlocal calls
                    calls += 1
                    if calls == 2:
                        return replace(
                            _jobs(
                                parent=transport.parent,
                                state=contract.RecoveryState.FAILED,
                                rows=1,
                            ),
                            parent_run_ref=invalid_parent,
                        )
                    return original(timeout)

                transport.observe_jobs = jobs
                jobs_id = self._operation_id_for_handler(
                    "AND-05", "jobs_recovered"
                )
                retry_id = self._operation_id_for_handler("AND-05", "retry")

                result = executor.execute(now=NOW)

                self.assertEqual(result.status, "blocked")
                self.assertEqual(result.completed_operations, 30)
                self.assertEqual(transport.force_stop_calls, 1)
                self.assertEqual(transport.retry_calls, 0)
                self.assertTrue(
                    self._assertion_recorded(
                        executor,
                        writer,
                        jobs_id,
                        "recovered_parent_unavailable",
                        evidence.AssertionOutcome.BLOCKED,
                    )
                )
                self.assertFalse(
                    self._assertion_recorded(
                        executor,
                        writer,
                        retry_id,
                        "intent",
                        evidence.AssertionOutcome.NOT_RUN,
                    )
                )

    def test_recovered_jobs_duplicate_parent_fails(self) -> None:
        executor, transport, _ = self._executor("AND-05")
        self._force_stop_into(transport, contract.RecoveryState.FAILED)
        original = transport.observe_jobs
        calls = 0

        def jobs(timeout):
            nonlocal calls
            calls += 1
            if calls == 2:
                return _jobs(
                    parent="different-parent",
                    state=contract.RecoveryState.FAILED,
                    rows=1,
                )
            return original(timeout)

        transport.observe_jobs = jobs
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "failed")
        self.assertEqual(result.completed_operations, 30)
        self.assertIn("duplicate refresh attempt", result.blocker)

    def test_retry_control_unavailable_blocks(self) -> None:
        executor, transport, _ = self._executor("AND-05")
        self._force_stop_into(transport, contract.RecoveryState.FAILED)
        original = transport.observe_refresh_detail
        calls = 0

        def detail(parent_ref, timeout):
            nonlocal calls
            calls += 1
            if calls == 4:
                return _detail(
                    transport.parent,
                    contract.RecoveryState.FAILED,
                    progress=_progress(2),
                    retry=0,
                )
            return original(parent_ref, timeout)

        transport.observe_refresh_detail = detail
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 33)
        self.assertIn("unique retry control", result.blocker)

    def test_retry_control_boolean_or_float_count_blocks_before_effect(self):
        for case_name, retry_count in (("boolean", True), ("float", 1.0)):
            with self.subTest(case=case_name):
                executor, transport, writer = self._executor(
                    "AND-05", authorization_id=f"retry-control-count-{case_name}"
                )
                self._force_stop_into(transport, contract.RecoveryState.FAILED)
                eligibility_id = self._operation_id_for_handler(
                    "AND-05", "retry_eligibility"
                )
                retry_id = self._operation_id_for_handler("AND-05", "retry")
                self._override_detail_for_operation(
                    executor,
                    eligibility_id,
                    lambda detail: replace(
                        detail, retry_control_count=retry_count
                    ),
                )

                result = executor.execute(now=NOW)

                self.assertEqual(result.status, "blocked")
                self.assertEqual(result.completed_operations, 33)
                self.assertEqual(transport.force_stop_calls, 1)
                self.assertEqual(transport.retry_calls, 0)
                self.assertTrue(
                    self._assertion_recorded(
                        executor,
                        writer,
                        eligibility_id,
                        "retry_control_unavailable",
                        evidence.AssertionOutcome.BLOCKED,
                    )
                )
                self.assertFalse(
                    self._assertion_recorded(
                        executor,
                        writer,
                        retry_id,
                        "intent",
                        evidence.AssertionOutcome.NOT_RUN,
                    )
                )

    def test_retry_eligibility_requires_exact_parent_detail_identity(self):
        cases = (
            ("missing", None, "detail-observer", "blocked"),
            ("malformed", 123, "detail-observer", "blocked"),
            ("different_valid", "different-parent", "detail-observer", "failed"),
            ("different_unproven", "different-parent", None, "failed"),
        )
        for case_name, parent_identity, observer_ref, expected_status in cases:
            with self.subTest(case=case_name):
                executor, transport, writer = self._executor(
                    "AND-05", authorization_id=f"retry-eligibility-parent-{case_name}"
                )
                self._force_stop_into(transport, contract.RecoveryState.FAILED)
                eligibility_id = self._operation_id_for_handler(
                    "AND-05", "retry_eligibility"
                )
                retry_id = self._operation_id_for_handler("AND-05", "retry")
                self._override_detail_for_operation(
                    executor,
                    eligibility_id,
                    lambda detail: replace(
                        detail,
                        parent_run_ref=parent_identity,
                        observer_ref=observer_ref,
                    ),
                )

                result = executor.execute(now=NOW)

                self.assertEqual(result.status, expected_status)
                self.assertEqual(result.completed_operations, 33)
                self.assertEqual(transport.force_stop_calls, 1)
                self.assertEqual(transport.retry_calls, 0)
                self.assertFalse(
                    self._assertion_recorded(
                        executor,
                        writer,
                        retry_id,
                        "intent",
                        evidence.AssertionOutcome.NOT_RUN,
                    )
                )
                if expected_status == "blocked":
                    self.assertTrue(
                        self._assertion_recorded(
                            executor,
                            writer,
                            eligibility_id,
                            "retry_eligibility_parent_identity_unavailable",
                            evidence.AssertionOutcome.BLOCKED,
                        )
                    )
                else:
                    self.assertTrue(
                        self._assertion_recorded(
                            executor,
                            writer,
                            eligibility_id,
                            "result",
                            evidence.AssertionOutcome.FAILED,
                        )
                    )

    def test_retry_eligibility_requires_current_proven_detail(self):
        cases = (
            (
                "missing_observer",
                lambda detail: replace(detail, observer_ref=None),
                "retry_eligibility_observer_unavailable",
            ),
            (
                "stale_state",
                lambda detail: replace(
                    detail, state=contract.RecoveryState.COMPLETED
                ),
                "retry_eligibility_state_stale",
            ),
            (
                "malformed_state",
                lambda detail: replace(detail, state="FAILED"),
                "retry_eligibility_state_unavailable",
            ),
        )
        for case_name, replacement, blocker in cases:
            with self.subTest(case=case_name):
                executor, transport, writer = self._executor(
                    "AND-05", authorization_id=f"retry-eligibility-proof-{case_name}"
                )
                self._force_stop_into(transport, contract.RecoveryState.FAILED)
                eligibility_id = self._operation_id_for_handler(
                    "AND-05", "retry_eligibility"
                )
                retry_id = self._operation_id_for_handler("AND-05", "retry")
                self._override_detail_for_operation(
                    executor, eligibility_id, replacement
                )

                result = executor.execute(now=NOW)

                self.assertEqual(result.status, "blocked")
                self.assertEqual(result.completed_operations, 33)
                self.assertEqual(transport.retry_calls, 0)
                self.assertTrue(
                    self._assertion_recorded(
                        executor,
                        writer,
                        eligibility_id,
                        blocker,
                        evidence.AssertionOutcome.BLOCKED,
                    )
                )
                self.assertFalse(
                    self._assertion_recorded(
                        executor,
                        writer,
                        eligibility_id,
                        "result",
                        evidence.AssertionOutcome.PASSED,
                    )
                )
                self.assertFalse(
                    any(f":{retry_id}:" in key for key, _ in writer.assertion_keys)
                )

    def test_retry_eligibility_accepts_optional_unrelated_detail_fields(self):
        executor, transport, writer = self._executor(
            "AND-05", authorization_id="retry-eligibility-optional-fields"
        )
        self._force_stop_into(transport, contract.RecoveryState.FAILED)
        eligibility_id = self._operation_id_for_handler(
            "AND-05", "retry_eligibility"
        )
        self._override_detail_for_operation(
            executor,
            eligibility_id,
            lambda detail: replace(
                detail,
                progress=None,
                retry_source_run_ref=None,
                retry_successor_run_ref=None,
                cancellation_requested=None,
            ),
        )

        result = executor.execute(now=NOW)

        self.assertTrue(result.workflow_completed)
        self.assertEqual(transport.retry_calls, 1)
        self.assertTrue(
            self._assertion_recorded(
                executor,
                writer,
                eligibility_id,
                "result",
                evidence.AssertionOutcome.PASSED,
            )
        )

    def test_uncertain_retry_blocks_without_second_effect(self) -> None:
        executor, transport, _ = self._executor("AND-05")
        self._force_stop_into(transport, contract.RecoveryState.FAILED)

        def retry(timeout):
            transport.retry_calls += 1
            raise RuntimeError("retry failed")

        transport.retry_refresh = retry
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 34)
        self.assertEqual(transport.retry_calls, 1)
        self.assertIn("explicit retry", result.blocker)

    def test_unavailable_pre_retry_identity_blocks_before_retry_intent(self) -> None:
        transport = ScriptedTransport("AND-05")
        observer = ScriptedObserver(transport)
        original = observer.observe_identity

        def identity(parent_ref, timeout):
            if (
                transport.force_stop_calls
                and not transport.retry_calls
                and parent_ref == transport.parent
            ):
                return None
            return original(parent_ref, timeout)

        observer.observe_identity = identity
        executor, _, writer = self._executor(
            "AND-05", transport=transport, observer=observer
        )
        self._force_stop_into(transport, contract.RecoveryState.FAILED)
        result = executor.execute(now=NOW)

        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 34)
        self.assertEqual(transport.retry_calls, 0)
        self.assertFalse(
            self._assertion_recorded(
                executor,
                writer,
                "and-05-35",
                "intent",
                evidence.AssertionOutcome.NOT_RUN,
            )
        )

    def test_pre_retry_identity_observer_exception_blocks_before_retry_intent(self):
        transport = ScriptedTransport("AND-05")
        observer = ScriptedObserver(transport)
        original = observer.observe_identity

        def identity(parent_ref, timeout):
            if (
                transport.force_stop_calls
                and not transport.retry_calls
                and parent_ref == transport.parent
            ):
                raise ValueError("observer decode failed")
            return original(parent_ref, timeout)

        observer.observe_identity = identity
        executor, _, writer = self._executor(
            "AND-05", transport=transport, observer=observer
        )
        self._force_stop_into(transport, contract.RecoveryState.FAILED)
        result = executor.execute(now=NOW)

        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 34)
        self.assertEqual(
            result.blocker,
            "The fresh Retry relationship lookup failed; owner recovery is required.",
        )
        self.assertEqual(transport.retry_calls, 0)
        self.assertTrue(
            self._assertion_recorded(
                executor,
                writer,
                "and-05-35",
                "retry_pre_dispatch_identity_unavailable",
                evidence.AssertionOutcome.BLOCKED,
            )
        )
        intent_key = admission._add_scan_alias(
            "operation",
            f"{executor._spec.session_id}:and-05-35:intent",
        )
        self.assertFalse(any(key == intent_key for key, _ in writer.assertion_keys))

    def test_pre_retry_identity_session_binding_change_keeps_integrity_blocker(self):
        transport = ScriptedTransport("AND-05")
        observer = ScriptedObserver(transport)
        original = observer.observe_identity
        state = {"executor": None, "binding_lost": False}

        def identity(parent_ref, timeout):
            executor = state["executor"]
            if (
                executor is not None
                and executor._attempted_operation.operation_id == "and-05-35"
            ):
                state["binding_lost"] = True
            return original(parent_ref, timeout)

        observer.observe_identity = identity
        executor, _, writer = self._executor(
            "AND-05", transport=transport, observer=observer
        )
        state["executor"] = executor
        self._force_stop_into(transport, contract.RecoveryState.FAILED)
        original_binding = admission._admitted_session_binding

        def binding(session):
            if state["binding_lost"]:
                return None
            return original_binding(session)

        with mock.patch.object(admission, "_admitted_session_binding", binding):
            result = executor.execute(now=NOW)

        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 34)
        self.assertIn("admitted session binding changed during transport", result.blocker)
        self.assertEqual(transport.retry_calls, 0)
        self.assertFalse(
            self._assertion_recorded(
                executor,
                writer,
                "and-05-35",
                "intent",
                evidence.AssertionOutcome.NOT_RUN,
            )
        )
        self.assertTrue(
            self._assertion_recorded(
                executor,
                writer,
                "and-05-35",
                "operation-outcome-unrecorded",
                evidence.AssertionOutcome.BLOCKED,
            )
        )

    def test_pre_retry_identity_operation_deadline_expiry_keeps_deadline_blocker(self):
        transport = ScriptedTransport("AND-05")
        observer = ScriptedObserver(transport)
        operation_clock = _Clock()
        transport_clock = _Clock()
        state = {"executor": None, "advanced": False}
        original = observer.observe_identity

        def identity(parent_ref, timeout):
            executor = state["executor"]
            if (
                not state["advanced"]
                and executor is not None
                and executor._attempted_operation.operation_id == "and-05-35"
            ):
                state["advanced"] = True
                transport_clock.value = executor._active_budget._deadline
            return original(parent_ref, timeout)

        observer.observe_identity = identity
        executor, _, writer = self._executor(
            "AND-05",
            transport=transport,
            observer=observer,
            monotonic=operation_clock.monotonic,
            sleeper=operation_clock.sleep,
        )
        state["executor"] = executor
        self._force_stop_into(transport, contract.RecoveryState.FAILED)

        with mock.patch.object(admission.time, "monotonic", transport_clock.monotonic):
            result = executor.execute(now=NOW)

        self.assertTrue(state["advanced"])
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 34)
        self.assertIn("approved operation deadline expired", result.blocker)
        self.assertEqual(transport.retry_calls, 0)
        self.assertFalse(
            self._assertion_recorded(
                executor,
                writer,
                "and-05-35",
                "intent",
                evidence.AssertionOutcome.NOT_RUN,
            )
        )
        self.assertTrue(
            self._assertion_recorded(
                executor,
                writer,
                "and-05-35",
                "operation-outcome-unrecorded",
                evidence.AssertionOutcome.BLOCKED,
            )
        )

    def test_pre_retry_equality_impersonation_blocks_before_retry_intent(self):
        transport = ScriptedTransport("AND-05")
        observer = ScriptedObserver(transport)
        original = observer.observe_identity
        forged_lookup_calls = 0

        def observe(parent_ref, timeout):
            nonlocal forged_lookup_calls
            if (
                transport.force_stop_calls
                and not transport.retry_calls
                and parent_ref == transport.parent
            ):
                forged_lookup_calls += 1
                identity = original(parent_ref, timeout)
                return replace(
                    identity,
                    retry_lookup_source_run_ref=(
                        _EqualityImpersonatingReference(transport.parent)
                    ),
                )
            return original(parent_ref, timeout)

        observer.observe_identity = observe
        executor, _, writer = self._executor(
            "AND-05", transport=transport, observer=observer
        )
        self._force_stop_into(transport, contract.RecoveryState.FAILED)
        result = executor.execute(now=NOW)

        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 34)
        self.assertIn("pre-Retry relationship proof", result.blocker)
        self.assertEqual(transport.retry_calls, 0)
        self.assertEqual(forged_lookup_calls, 1)
        self.assertTrue(
            self._assertion_recorded(
                executor,
                writer,
                "and-05-35",
                "retry_pre_dispatch_identity_ambiguous",
                evidence.AssertionOutcome.BLOCKED,
            )
        )
        self.assertFalse(
            self._assertion_recorded(
                executor,
                writer,
                "and-05-35",
                "retry_pre_dispatch_identity_current_and_empty",
                evidence.AssertionOutcome.PASSED,
            )
        )
        intent_key = admission._add_scan_alias(
            "operation",
            f"{executor._spec.session_id}:and-05-35:intent",
        )
        self.assertFalse(any(key == intent_key for key, _ in writer.assertion_keys))

    def test_invalid_pre_retry_relations_never_dispatch_retry(self) -> None:
        valid = _identity(
            "parent-run",
            scan_run_ids=("scan-run",),
            state=contract.RecoveryState.ABANDONED,
            scope="scope-ref",
            retry_lookup=True,
            lookup_source="parent-run",
        )
        invalid = (
            None,
            replace(valid, parent_run_ref="other-parent"),
            replace(valid, frozen_scope_ref="other-scope"),
            replace(valid, parent_state=contract.RecoveryState.FAILED),
            replace(valid, scan_run_relations=()),
            replace(
                valid,
                scan_run_relations=(
                    contract.ScanRunRelation(
                        parent_run_ref="parent-run",
                        scan_run_ref="foreign-scan",
                        root_ref="root-ref-synthetic",
                    ),
                ),
            ),
            replace(
                valid,
                scan_run_relations=(
                    valid.scan_run_relations[0],
                    valid.scan_run_relations[0],
                ),
            ),
            replace(valid, retry_relation_lookup_completed=None),
            replace(valid, retry_relation_lookup_completed=False),
            replace(valid, retry_lookup_source_run_ref="other-parent"),
            replace(valid, successor_run_ref="existing-successor"),
            replace(valid, successor_scan_run_relations=None),
            replace(valid, successor_scope_ref="scope-ref"),
            replace(valid, source_run_ref="parent-run"),
        )
        for observation in invalid:
            with self.subTest(observation=observation):
                with tempfile.TemporaryDirectory() as temporary_directory:
                    directory = Path(temporary_directory)
                    with mock.patch.object(
                        admission,
                        "_SESSION_REGISTRY_PATH",
                        directory / "host-state" / "session-registry.json",
                        create=True,
                    ):
                        transport = ScriptedTransport("AND-05")
                        observer = ScriptedObserver(transport)
                        original = observer.observe_identity

                        def observe(parent_ref, timeout):
                            if (
                                transport.force_stop_calls
                                and not transport.retry_calls
                                and parent_ref == transport.parent
                            ):
                                return observation
                            return original(parent_ref, timeout)

                        observer.observe_identity = observe
                        executor, _, writer = self._executor(
                            "AND-05",
                            directory=directory,
                            transport=transport,
                            observer=observer,
                        )
                        self._run_and_05_with_force_stop(transport)
                        result = executor.execute(now=NOW)

                        expected_status = (
                            "failed"
                            if observation is not None
                            and type(getattr(observation, "parent_run_ref", None)) is str
                            and observation.parent_run_ref != transport.parent
                            else "blocked"
                        )
                        self.assertEqual(result.status, expected_status)
                        self.assertEqual(result.completed_operations, 34)
                        self.assertEqual(transport.retry_calls, 0)
                        self.assertFalse(
                            self._assertion_recorded(
                                executor,
                                writer,
                                "and-05-35",
                                "intent",
                                evidence.AssertionOutcome.NOT_RUN,
                            )
                        )

    def test_missing_pre_retry_scanrun_observation_blocks_retry_dispatch(self) -> None:
        transport = ScriptedTransport("AND-05")
        observer = ScriptedObserver(transport)
        executor, _, writer = self._executor(
            "AND-05", transport=transport, observer=observer
        )
        original = observer.observe_identity

        def observe(parent_ref, timeout):
            identity = original(parent_ref, timeout)
            attempted = executor._attempted_operation
            if (
                attempted is not None
                and attempted.operation_id == "and-05-35"
            ):
                return replace(identity, successor_scan_run_relations=None)
            return identity

        observer.observe_identity = observe
        self._run_and_05_with_force_stop(transport)
        result = executor.execute(now=NOW)

        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 34)
        self.assertEqual(transport.retry_calls, 0)
        self.assertIn("pre-Retry relationship proof", result.blocker)
        self.assertTrue(
            self._assertion_recorded(
                executor,
                writer,
                "and-05-35",
                "retry_pre_dispatch_identity_ambiguous",
                evidence.AssertionOutcome.BLOCKED,
            )
        )
        intent_key = admission._add_scan_alias(
            "operation",
            f"{executor._spec.session_id}:and-05-35:intent",
        )
        self.assertFalse(any(key == intent_key for key, _ in writer.assertion_keys))

    def test_pre_retry_successor_scanrun_relation_blocks_retry_dispatch(self) -> None:
        transport = ScriptedTransport("AND-05")
        observer = ScriptedObserver(transport)
        original = observer.observe_identity

        def observe(parent_ref, timeout):
            identity = original(parent_ref, timeout)
            if (
                transport.force_stop_calls
                and not transport.retry_calls
                and parent_ref == transport.parent
            ):
                return replace(
                    identity,
                    successor_scan_run_relations=(
                        contract.ScanRunRelation(
                            parent_run_ref="unidentified-successor",
                            scan_run_ref="orphan-successor-scan",
                            root_ref=identity.admitted_root_refs[0],
                        ),
                    ),
                )
            return identity

        observer.observe_identity = observe
        executor, _, writer = self._executor(
            "AND-05", transport=transport, observer=observer
        )
        self._run_and_05_with_force_stop(transport)
        result = executor.execute(now=NOW)

        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 34)
        self.assertEqual(transport.retry_calls, 0)
        self.assertIn("pre-Retry relationship proof is unavailable", result.blocker)
        self.assertTrue(
            self._assertion_recorded(
                executor,
                writer,
                "and-05-35",
                "retry_pre_dispatch_identity_ambiguous",
                evidence.AssertionOutcome.BLOCKED,
            )
        )
        intent_key = admission._add_scan_alias(
            "operation",
            f"{executor._spec.session_id}:and-05-35:intent",
        )
        self.assertFalse(any(key == intent_key for key, _ in writer.assertion_keys))

    def test_pre_retry_successor_partition_without_successor_run_blocks_retry(self) -> None:
        transport = ScriptedTransport("AND-05")
        observer = ScriptedObserver(transport)
        executor, _, writer = self._executor(
            "AND-05", transport=transport, observer=observer
        )
        original = observer.observe_identity

        def observe(parent_ref, timeout):
            identity = original(parent_ref, timeout)
            attempted = executor._attempted_operation
            if (
                attempted is not None
                and attempted.operation_id == "and-05-35"
            ):
                return replace(
                    identity,
                    successor_requested_root_refs=identity.requested_root_refs,
                    successor_admitted_root_refs=identity.admitted_root_refs,
                    successor_excluded_root_refs=identity.excluded_root_refs,
                    successor_exclusions=(),
                )
            return identity

        observer.observe_identity = observe
        self._run_and_05_with_force_stop(transport)
        result = executor.execute(now=NOW)

        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 34)
        self.assertEqual(transport.retry_calls, 0)
        self.assertIn("pre-Retry relationship proof is unavailable", result.blocker)
        self.assertTrue(
            self._assertion_recorded(
                executor,
                writer,
                "and-05-35",
                "retry_pre_dispatch_identity_ambiguous",
                evidence.AssertionOutcome.BLOCKED,
            )
        )
        intent_key = admission._add_scan_alias(
            "operation",
            f"{executor._spec.session_id}:and-05-35:intent",
        )
        self.assertFalse(any(key == intent_key for key, _ in writer.assertion_keys))

    def test_pre_retry_rejects_root_partition_drift_with_stable_scope_ref(self) -> None:
        transport = ScriptedTransport("AND-05")
        observer = ScriptedObserver(transport)
        executor, _, writer = self._executor(
            "AND-05", transport=transport, observer=observer
        )
        original = observer.observe_identity

        def observe(parent_ref, timeout):
            identity = original(parent_ref, timeout)
            attempted = executor._attempted_operation
            if (
                attempted is not None
                and attempted.operation_id == "and-05-35"
            ):
                added_root = "root-ref-added-before-retry"
                return replace(
                    identity,
                    requested_root_refs=(
                        identity.requested_root_refs + (added_root,)
                    ),
                    excluded_root_refs=(
                        identity.excluded_root_refs + (added_root,)
                    ),
                )
            return identity

        observer.observe_identity = observe
        self._run_and_05_with_force_stop(transport)
        result = executor.execute(now=NOW)

        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 34)
        self.assertEqual(transport.retry_calls, 0)
        self.assertIn("pre-Retry relationship proof", result.blocker)
        self.assertTrue(
            self._assertion_recorded(
                executor,
                writer,
                "and-05-35",
                "retry_pre_dispatch_scope_stale",
                evidence.AssertionOutcome.BLOCKED,
            )
        )
        intent_key = admission._add_scan_alias(
            "operation",
            f"{executor._spec.session_id}:and-05-35:intent",
        )
        self.assertFalse(any(key == intent_key for key, _ in writer.assertion_keys))

    def test_retry_successor_identity_unavailable_blocks(self) -> None:
        transport = ScriptedTransport("AND-05")
        observer = ScriptedObserver(transport)
        original = observer.observe_identity

        def identity(parent_ref, timeout):
            if parent_ref == transport.parent and transport.retry_calls:
                return None
            return original(parent_ref, timeout)

        observer.observe_identity = identity
        executor, _, _ = self._executor("AND-05", transport=transport, observer=observer)
        self._force_stop_into(transport, contract.RecoveryState.FAILED)
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 35)
        self.assertIn("retry_successor_identity_unavailable", result.blocker)

    def test_committed_library_state_unavailable_blocks(self) -> None:
        executor, transport, _ = self._executor("AND-05")
        self._force_stop_into(transport, contract.RecoveryState.FAILED)
        original = transport.observe_library
        calls = 0

        def library(timeout):
            nonlocal calls
            calls += 1
            if calls == 3:
                return replace(_library(), observer_ref=None)
            return original(timeout)

        transport.observe_library = library
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 28)
        self.assertEqual(transport.retry_calls, 0)
        self.assertIn("identities are BLOCKED", result.blocker)

    def test_scanning_scanrun_without_expected_state_stays_blocked(self) -> None:
        relation = contract.ScanRunRelation(
            parent_run_ref="parent",
            scan_run_ref="scan-run",
            root_ref="root-ref-synthetic",
        )
        observation = contract.ScanRunObservation(
            surface=contract.JobLifecycleSurface.REFRESH_DETAIL,
            parent_run_ref="parent",
            scan_run_ref="scan-run",
            root_ref="root-ref-synthetic",
            parent_state=contract.RecoveryState.ACTIVE,
            scan_state="scanning",
            observer_ref="refresh-detail-observer",
        )

        result = oracle.validate_scan_run_observation(
            observation,
            expected_relation=relation,
        )

        self.assertEqual(result.outcome, evidence.AssertionOutcome.BLOCKED)
        self.assertEqual(result.code, "scan_run_terminal_state_unavailable")

    def test_scan_run_observation_unavailable_blocks(self) -> None:
        executor, transport, _ = self._executor()
        transport.observe_scan_run = lambda parent_ref, scan_run_ref, root_ref, timeout: None
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 29)
        self.assertIn("owning refresh ScanRun state", result.blocker)

    def test_session_deadline_expires_during_dispatch(self) -> None:
        clock = _Clock()
        executor, transport, _ = self._executor(
            monotonic=clock.monotonic, sleeper=clock.sleep
        )

        def library(timeout):
            clock.value = 840.0
            return _library()

        transport.observe_library = library
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 3)
        self.assertIn("session or approval deadline", result.blocker)

    def test_operation_remaining_deadline_expires_during_dispatch(self) -> None:
        clock = _Clock()
        executor, transport, _ = self._executor(
            monotonic=clock.monotonic, sleeper=clock.sleep
        )

        def library(timeout):
            clock.value = 839.5
            return _library()

        transport.observe_library = library
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 3)
        self.assertIn("operation deadline", result.blocker)

    def test_budget_requires_a_current_operation(self) -> None:
        executor, _, _ = self._executor()
        with self.assertRaises(lifecycle_executor._JobLifecycleStop) as caught:
            executor._budget()
        self.assertIn("not bound", str(caught.exception))

    def test_session_deadline_expires_between_restoration_calls(self) -> None:
        clock = _Clock()
        executor, transport, _ = self._executor(
            monotonic=clock.monotonic, sleeper=clock.sleep
        )

        def restore(package, task_ref, timeout):
            transport.foreground = package
            clock.value = 840.0

        transport.restore_foreground = restore
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 30)
        self.assertIn("operation deadline", result.blocker)

    def test_transport_binding_change_is_fail_closed(self) -> None:
        executor, _, _ = self._executor()
        with mock.patch.object(
            lifecycle_executor,
            "_authorized_transport_call",
            side_effect=admission._SessionIntegrityError(),
        ):
            result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 0)
        self.assertIn("binding changed", result.blocker)

    def test_transport_budget_expiry_is_fail_closed(self) -> None:
        executor, _, _ = self._executor()
        with mock.patch.object(
            lifecycle_executor,
            "_authorized_transport_call",
            side_effect=admission._OperationDeadlineExpired(),
        ):
            result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 0)
        self.assertIn("operation deadline", result.blocker)

    def test_transport_interrupted_error_is_terminal(self) -> None:
        executor, _, writer = self._executor()
        with mock.patch.object(
            lifecycle_executor,
            "_authorized_transport_call",
            side_effect=InterruptedError(),
        ):
            result = executor.execute(now=NOW)
        self.assertEqual(result.status, "interrupted")
        self.assertEqual(result.completed_operations, 0)
        self.assertEqual(
            writer.terminal.outcome,
            evidence.TerminalOutcome.INTERRUPTED,
        )

    def test_blocked_assertion_append_failure_requires_owner_recovery(self) -> None:
        executor, transport, writer = self._executor()
        transport.observe_library = lambda timeout: replace(
            _library(), membership_count=None
        )
        writer.fail_assertion_after = 1
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 1)
        self.assertIn("owner recovery", result.blocker)

    def test_finalize_is_idempotent_after_terminal(self) -> None:
        executor, _, writer = self._executor()
        executor.execute(now=NOW)
        terminal = writer.terminal
        events = list(writer.events)
        executor._finalize(reason=evidence.TerminalReason.PREREQUISITE_BLOCKED)
        self.assertIs(writer.terminal, terminal)
        self.assertEqual(writer.events, events)

    def test_busy_session_rejects_reentrant_execution(self) -> None:
        executor, _, _ = self._executor()
        self.assertTrue(executor._session.reserve_operation())
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 0)
        self.assertIn("Another operation", result.blocker)

    def test_oracle_not_run_and_blocked_outcomes_are_durably_recorded(self) -> None:
        executor, _, writer = self._executor("AND-05")
        executor._base_time = NOW
        executor._started = executor._monotonic()
        operation = executor._session.authorization.operations[0]
        with self.assertRaises(lifecycle_executor._JobLifecycleStop):
            executor._record_oracle(
                operation,
                oracle.OracleResult(
                    evidence.AssertionOutcome.NOT_RUN,
                    "retry_not_eligible",
                ),
            )
        self.assertEqual(writer.events[-1], ("assertion", "not_run"))
        with self.assertRaises(lifecycle_executor._JobLifecycleStop):
            executor._record_oracle(
                operation,
                oracle.OracleResult(
                    evidence.AssertionOutcome.BLOCKED,
                    "retry_eligibility_unavailable",
                ),
            )
        self.assertEqual(writer.events[-1], ("assertion", "blocked"))

    def test_retry_eligibility_unexpected_oracle_outcomes_fail_closed(self) -> None:
        executor, _, writer = self._executor("AND-05")
        executor._base_time = NOW
        executor._started = executor._monotonic()
        operation = executor._session.authorization.operations[25]
        spec = contract.JOB_LIFECYCLE_OPERATIONS["AND-05"][25]
        executor._parent_state = contract.RecoveryState.COMPLETED
        with self.assertRaises(lifecycle_executor._JobLifecycleStop):
            executor._step_retry_eligibility(operation, spec)
        self.assertEqual(writer.events[-1], ("assertion", "not_run"))
        executor._parent_state = "unknown"
        with self.assertRaises(lifecycle_executor._JobLifecycleStop):
            executor._step_retry_eligibility(operation, spec)
        self.assertEqual(writer.events[-1], ("assertion", "blocked"))

    def test_keyboard_interrupt_is_terminal_and_never_retried(self):
        executor, transport, writer = self._executor()

        def interrupt(timeout):
            raise KeyboardInterrupt

        transport.start_refresh = interrupt
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "interrupted")
        self.assertEqual(result.completed_operations, 6)
        self.assertEqual(
            writer.terminal.outcome,
            evidence.TerminalOutcome.INTERRUPTED,
        )

    def test_successor_identity_change_during_terminal_observation_fails(self):
        executor, transport, _ = self._executor("AND-05")
        successor_calls = 0
        original = transport.observe_refresh_detail

        def detail(parent_ref, timeout):
            nonlocal successor_calls
            if parent_ref == transport.successor:
                successor_calls += 1
                if successor_calls > 1:
                    return _detail(
                        "different-successor",
                        contract.RecoveryState.COMPLETED,
                        progress=_progress(3),
                    )
            return original(parent_ref, timeout)

        def force_stop(package, timeout):
            transport.force_stop_calls += 1
            transport.process_state = contract.ProcessState.ABSENT
            transport.foreground = "com.android.launcher3"
            transport.detail_state = contract.RecoveryState.ABANDONED

        transport.force_stop_package = force_stop
        transport.observe_refresh_detail = detail
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, "failed")
        self.assertEqual(result.completed_operations, 44)

    def test_retry_detail_missing_parent_or_source_blocks_relation(self):
        invalid_identity_cases = (
            ("missing_parent", "parent_run_ref", None),
            ("missing_source", "retry_source_run_ref", None),
            ("malformed_parent", "parent_run_ref", 123),
            ("malformed_source", "retry_source_run_ref", ""),
        )
        for case_name, field, invalid_value in invalid_identity_cases:
            with self.subTest(case=case_name):
                executor, transport, writer = self._executor(
                    "AND-05", authorization_id=f"retry-relation-{case_name}"
                )
                successor_calls = 0
                original = transport.observe_refresh_detail

                def detail(parent_ref, timeout):
                    nonlocal successor_calls
                    if parent_ref == transport.successor:
                        successor_calls += 1
                        if successor_calls == 1:
                            return replace(
                                original(parent_ref, timeout),
                                **{field: invalid_value},
                            )
                    return original(parent_ref, timeout)

                def force_stop(package, timeout):
                    transport.force_stop_calls += 1
                    transport.process_state = contract.ProcessState.ABSENT
                    transport.foreground = "com.android.launcher3"
                    transport.detail_state = contract.RecoveryState.ABANDONED

                transport.force_stop_package = force_stop
                transport.observe_refresh_detail = detail
                operation_id = self._operation_id_for_handler(
                    "AND-05", "retry_relation"
                )

                result = executor.execute(now=NOW)

                self.assertEqual(result.status, "blocked")
                self.assertEqual(result.completed_operations, 36)
                self.assertIn("identity is unavailable", result.blocker)
                self.assertEqual(transport.force_stop_calls, 1)
                self.assertEqual(transport.launch_calls, 1)
                self.assertEqual(transport.retry_calls, 1)
                self.assertTrue(
                    self._assertion_recorded(
                        executor,
                        writer,
                        operation_id,
                        "retry_successor_detail_identity_unavailable",
                        evidence.AssertionOutcome.BLOCKED,
                    )
                )
                self.assertFalse(
                    self._successor_terminal_keys(executor, writer, "terminal")
                )

    def test_retry_detail_different_valid_parent_or_source_fails_relation(self):
        different_identity_cases = (
            ("different_parent", "parent_run_ref"),
            ("different_source", "retry_source_run_ref"),
        )
        for case_name, field in different_identity_cases:
            with self.subTest(case=case_name):
                executor, transport, writer = self._executor(
                    "AND-05", authorization_id=f"retry-relation-{case_name}"
                )
                successor_calls = 0
                original = transport.observe_refresh_detail

                def detail(parent_ref, timeout):
                    nonlocal successor_calls
                    if parent_ref == transport.successor:
                        successor_calls += 1
                        if successor_calls == 1:
                            return replace(
                                original(parent_ref, timeout),
                                **{field: f"different-{case_name}"},
                            )
                    return original(parent_ref, timeout)

                def force_stop(package, timeout):
                    transport.force_stop_calls += 1
                    transport.process_state = contract.ProcessState.ABSENT
                    transport.foreground = "com.android.launcher3"
                    transport.detail_state = contract.RecoveryState.ABANDONED

                transport.force_stop_package = force_stop
                transport.observe_refresh_detail = detail
                operation_id = self._operation_id_for_handler(
                    "AND-05", "retry_relation"
                )

                result = executor.execute(now=NOW)

                self.assertEqual(result.status, "failed")
                self.assertEqual(result.completed_operations, 36)
                self.assertEqual(transport.force_stop_calls, 1)
                self.assertEqual(transport.launch_calls, 1)
                self.assertEqual(transport.retry_calls, 1)
                self.assertTrue(
                    self._assertion_recorded(
                        executor,
                        writer,
                        operation_id,
                        "result",
                        evidence.AssertionOutcome.FAILED,
                    )
                )
                self.assertFalse(
                    self._successor_terminal_keys(executor, writer, "terminal")
                )

    def test_missing_successor_identity_during_terminal_observation_blocks(self):
        clock = _Clock(step=60.0)
        executor, transport, writer = self._executor(
            "AND-05",
            monotonic=clock.monotonic,
            sleeper=clock.sleep,
        )
        successor_calls = 0
        original = transport.observe_refresh_detail

        def detail(parent_ref, timeout):
            nonlocal successor_calls
            if parent_ref == transport.successor:
                successor_calls += 1
                if successor_calls > 1:
                    return _detail(
                        None,
                        contract.RecoveryState.COMPLETED,
                        progress=_progress(3),
                    )
            return original(parent_ref, timeout)

        def force_stop(package, timeout):
            transport.force_stop_calls += 1
            transport.process_state = contract.ProcessState.ABSENT
            transport.foreground = "com.android.launcher3"
            transport.detail_state = contract.RecoveryState.ABANDONED

        transport.force_stop_package = force_stop
        transport.observe_refresh_detail = detail

        result = executor.execute(now=NOW)

        self.assertEqual(result.status, "blocked")
        self.assertEqual(result.completed_operations, 44)
        self.assertIn("unavailable", result.blocker)
        self.assertEqual(transport.force_stop_calls, 1)
        self.assertEqual(transport.launch_calls, 1)
        self.assertEqual(transport.retry_calls, 1)
        self.assertFalse(self._successor_terminal_keys(executor, writer, "terminal"))


if __name__ == "__main__":
    unittest.main()
