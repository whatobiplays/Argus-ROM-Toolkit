"""Issue #27 plan tests use synthetic authorization operations only."""

from types import SimpleNamespace
from datetime import timedelta
from dataclasses import replace
import hashlib
import importlib.util
import inspect
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from scripts.android_qualification import _library_interaction_oracle as oracle_contract
from scripts.android_qualification import _library_interaction_executor as issue27_executor
from scripts.android_qualification import admission
from scripts.android_qualification import manifest, test_admission
from scripts.android_qualification.manifest import (
    OperationAuthorization,
    OperationCategory,
    QUALIFICATION_PACKAGE,
    SessionStateMode,
)
from scripts.android_qualification.test_manifest import (
    MANAGE_EXTERNAL_STORAGE,
    NOW,
    write_private_json,
)


_SERIAL = "private-serial-synthetic"
_APK_SHA256 = "a" * 64
_FIXTURE_SHA256 = "b" * 64
_ORACLE_SHA256 = "c" * 64
_LAUNCHER = "com.android.launcher3"


def _operation(
    index,
    category,
    value,
    *,
    phase="qualification",
    extra=None,
    timeout_seconds=10,
):
    category = OperationCategory(category)
    key = "observation" if category is OperationCategory.READ_ONLY else "action"
    arguments = {key: value, **(extra or {})}
    return OperationAuthorization(
        operation_id=f"operation-{index:02d}",
        category=category,
        phase=phase,
        target_serial=_SERIAL,
        package_name=QUALIFICATION_PACKAGE,
        timeout_seconds=timeout_seconds,
        permission_name=None,
        expected_prior_state=None,
        desired_state=None,
        restoration=None,
        arguments=tuple(sorted(arguments.items())),
    )


def _authorization_with_issue27_plan(timeout_seconds=10, cleanup_timeout_seconds=None):
    sequence = [
        (OperationCategory.INSTALL_ABSENT, "install_qualification_apk", "admission"),
        (OperationCategory.FIXTURE_STAGING, "stage_approved_fixture_set", "qualification"),
        (OperationCategory.LAUNCH, "launch_qualification_main", "qualification"),
        (OperationCategory.NAVIGATION, "accept_terms", "qualification"),
        (OperationCategory.NAVIGATION, "preferences", "qualification"),
        (OperationCategory.NAVIGATION, "skip_provider", "qualification"),
        (OperationCategory.NAVIGATION, "add_root", "qualification"),
        (OperationCategory.NAVIGATION, "storage_root", "qualification"),
        (OperationCategory.NAVIGATION, "open_qualification_root", "qualification"),
        (OperationCategory.NAVIGATION, "open_fixture_root", "qualification"),
        (OperationCategory.NAVIGATION, "select_folder", "qualification"),
        (OperationCategory.NAVIGATION, "add_and_scan", "qualification"),
        (OperationCategory.READ_ONLY, "scan_admission", "qualification"),
        (OperationCategory.NAVIGATION, "view_job", "qualification"),
        (OperationCategory.READ_ONLY, "job_status", "qualification"),
        (OperationCategory.READ_ONLY, "terminal_scan", "qualification"),
        (OperationCategory.NAVIGATION, "library_navigation", "qualification"),
        (OperationCategory.READ_ONLY, "library_complete_membership", "qualification"),
        (OperationCategory.NAVIGATION, "library_search_exact", "qualification"),
        (OperationCategory.NAVIGATION, "library_search_partial", "qualification"),
        (OperationCategory.NAVIGATION, "library_search_empty", "qualification"),
        (OperationCategory.NAVIGATION, "library_search_clear", "qualification"),
        (OperationCategory.NAVIGATION, "library_filter_platform", "qualification"),
        (OperationCategory.NAVIGATION, "library_filter_region", "qualification"),
        (OperationCategory.NAVIGATION, "library_filter_hydration", "qualification"),
        (OperationCategory.NAVIGATION, "library_filter_availability", "qualification"),
        (OperationCategory.NAVIGATION, "library_filter_reset", "qualification"),
        (OperationCategory.NAVIGATION, "library_select_game", "qualification"),
        (OperationCategory.NAVIGATION, "library_sort_title", "qualification"),
        (OperationCategory.NAVIGATION, "library_sort_ascending", "qualification"),
        (OperationCategory.NAVIGATION, "library_sort_descending", "qualification"),
        (OperationCategory.NAVIGATION, "library_sort_platform", "qualification"),
        (OperationCategory.NAVIGATION, "library_sort_ascending", "qualification"),
        (OperationCategory.NAVIGATION, "library_sort_descending", "qualification"),
        (OperationCategory.NAVIGATION, "library_view_list", "qualification"),
        (OperationCategory.NAVIGATION, "library_view_grid", "qualification"),
        (OperationCategory.NAVIGATION, "library_search_after_selection", "qualification"),
        (OperationCategory.NAVIGATION, "library_open_game_detail", "qualification"),
        (OperationCategory.READ_ONLY, "game_detail", "qualification"),
        (OperationCategory.NAVIGATION, "library_return_to_library", "qualification"),
        (OperationCategory.READ_ONLY, "library_return", "qualification"),
        (OperationCategory.FIXTURE_STAGING, "remove_session_owned_fixture_set", "cleanup"),
    ]
    operations = []
    for index, (category, value, phase) in enumerate(sequence):
        extra = {}
        if index == 0:
            extra = {"artifact_sha256": _APK_SHA256, "expected_foreground_package": _LAUNCHER}
        elif index == 1:
            extra = {
                "destination": "qualification_fixture_root",
                "fixture_manifest_sha256": _FIXTURE_SHA256,
                "expected_foreground_package": _LAUNCHER,
            }
        elif index == 2:
            extra = {"expected_foreground_package": _LAUNCHER}
        elif index == len(sequence) - 1:
            extra = {
                "destination": "qualification_fixture_root",
                "fixture_manifest_sha256": _FIXTURE_SHA256,
                "expected_foreground_package": QUALIFICATION_PACKAGE,
            }
        elif index >= 17:
            extra = {"oracle_sha256": _ORACLE_SHA256, "oracle_version": str(oracle_contract.LIBRARY_INTERACTION_CONTRACT_VERSION)}
        operations.append(_operation(
            index,
            category,
            value,
            phase=phase,
            extra=extra,
            timeout_seconds=(
                cleanup_timeout_seconds if index == len(sequence) - 1
                and cleanup_timeout_seconds is not None else timeout_seconds
            ),
        ))

    return SimpleNamespace(
        state_mode=SessionStateMode.FRESH,
        application_package=QUALIFICATION_PACKAGE,
        scenario_ids=("issue-27-library-interactions",),
        target_serial=_SERIAL,
        apk_sha256=_APK_SHA256,
        fixture_manifest_sha256=_FIXTURE_SHA256,
        operations=tuple(operations),
    )


def _issue27_authorization_document(
    *,
    timeout_seconds=10,
    cleanup_timeout_seconds=None,
    session_seconds=300,
    cleanup_deadline_seconds=600,
    cleanup_reserve_seconds=60,
):
    document = test_admission._first_add_scan_plan(installation="absent")
    authorization = _authorization_with_issue27_plan(
        timeout_seconds=timeout_seconds,
        cleanup_timeout_seconds=cleanup_timeout_seconds,
    )
    document["operations"] = [
        {
            "operation_id": operation.operation_id,
            "category": operation.category.value,
            "phase": operation.phase,
            "target_serial": operation.target_serial,
            "package_name": operation.package_name,
            "timeout_seconds": operation.timeout_seconds,
            "permission_name": operation.permission_name,
            "expected_prior_state": operation.expected_prior_state,
            "desired_state": operation.desired_state,
            "restoration": None,
            "arguments": dict(operation.arguments),
        }
        for operation in authorization.operations
    ]
    document["target"]["device_serial"] = _SERIAL
    document["fixture_manifest_sha256"] = _FIXTURE_SHA256
    document["plan"]["scenario_ids"] = ["issue-27-library-interactions"]
    document["session_deadline_utc"] = (NOW + timedelta(seconds=session_seconds)).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )
    document["cleanup_deadline_utc"] = (
        NOW + timedelta(seconds=cleanup_deadline_seconds)
    ).strftime("%Y-%m-%dT%H:%M:%SZ")
    document["reserves"]["cleanup_seconds"] = cleanup_reserve_seconds
    document["approved_remediation"] = []
    oracle = _oracle_for_pins(
        fixture_manifest_sha256=_FIXTURE_SHA256,
        artifact_sha256=_APK_SHA256,
        plan_sha256=document["plan"]["plan_sha256"],
        rules_sha256=document["plan"]["rules_sha256"],
    )
    for operation in document["operations"][17:-1]:
        operation["arguments"]["oracle_sha256"] = oracle.oracle_sha256
    return document


def _artifact_facts():
    return admission.HostArtifactFacts(
        apk_sha256=_APK_SHA256,
        package_name=QUALIFICATION_PACKAGE,
        version_code=123,
        signature_verified=True,
        signer_count=1,
        certificate_sha256="b" * 64,
        source_revision="c" * 40,
        declared_permissions=frozenset({MANAGE_EXTERNAL_STORAGE}),
        source_dirty=False,
    )


def _oracle_for_pins(
    *,
    fixture_manifest_sha256,
    artifact_sha256,
    plan_sha256,
    rules_sha256,
):
    fixture_expectations = (
        test_admission.ui.LibraryExpectation(
            "fixture-synthetic", "Metroid", "NES"
        ),
    )
    fixture_ids = tuple(item.fixture_id for item in fixture_expectations)
    inputs = {
        "search_exact": "Metroid",
        "search_partial": "Metro",
        "search_empty": "qzxvnomatchissue27",
        "search_clear": "",
        "filter_platform": "NES",
        "filter_region": "NA",
        "filter_hydration": "known",
        "filter_availability": "available",
        "selection": "fixture-synthetic",
        "search_after_selection": "Metroid",
    }
    ordered_cases = {
        "sort_title", "sort_title_ascending", "sort_title_descending",
        "sort_platform", "sort_platform_ascending", "sort_platform_descending",
    }
    unsupported_by_case = {
        "membership": (
            "complete_membership", "traversal_completion", "pagination_completion",
        ),
        "selection": (
            "complete_membership", "interaction_result",
            "selection_identity", "selection_state",
        ),
        "search_exact": (
            "complete_membership", "interaction_result", "retained_query_state",
        ),
        "search_partial": (
            "complete_membership", "interaction_result", "retained_query_state",
        ),
        "search_empty": (
            "complete_membership", "interaction_result", "retained_query_state",
            "searchable_projection_completeness",
        ),
        "search_clear": (
            "complete_membership", "interaction_result", "retained_query_state",
        ),
        "search_after_selection": (
            "complete_membership", "interaction_result", "retained_query_state",
            "selection_identity", "selection_state",
        ),
        "detail_open": (
            "complete_membership", "interaction_result", "stable_detail_facts",
        ),
        "detail_observation": ("complete_membership", "stable_detail_facts"),
    }
    unsupported_by_case.update({
        case_id: ("complete_membership", "interaction_result")
        for case_id in (
            "filter_platform", "filter_region", "filter_hydration",
            "filter_availability", "filter_reset", "view_list", "view_grid",
            "return_to_library", "return_observation",
        )
    })
    unsupported_by_case.update({
        case_id: ("complete_membership", "interaction_result", "result_order")
        for case_id in ordered_cases
    })
    case_expectations = tuple(
        oracle_contract.LibraryCaseExpectation(
            case_id=case_id,
            input_value=inputs.get(case_id),
            expected_fixture_ids=(
                () if case_id == "search_empty" else fixture_ids
            ),
            expected_order_groups=(
                ((fixture_ids[0],),) if case_id in ordered_cases else ()
            ),
            expected_selection_identity=(
                fixture_ids[0]
                if case_id in {"selection", "search_after_selection"}
                else None
            ),
            expected_selection_state=(
                True if case_id in {"selection", "search_after_selection"} else None
            ),
            expected_retained_query=(
                inputs[case_id]
                if case_id in {
                    "search_exact", "search_partial", "search_empty",
                    "search_clear", "search_after_selection",
                }
                else None
            ),
            expected_detail_facts=(
                (fixture_ids[0], "Metroid", "NES")
                if case_id in {"detail_open", "detail_observation"}
                else None
            ),
            searchable_identities=(
                tuple(
                    oracle_contract.LibrarySearchableIdentity(
                        item.fixture_id,
                        (item.display_title,),
                        None,
                        None,
                    )
                    for item in fixture_expectations
                )
                if case_id == "search_empty" else ()
            ),
            unsupported_assertions=unsupported_by_case.get(case_id, ()),
        )
        for case_id in oracle_contract.LIBRARY_INTERACTION_CASE_IDS
    )
    return oracle_contract.LibraryInteractionOracle(
        schema_version=oracle_contract.LIBRARY_INTERACTION_CONTRACT_VERSION,
        fixture_manifest_version=2,
        fixture_manifest_sha256=fixture_manifest_sha256,
        artifact_sha256=artifact_sha256,
        plan_version=1,
        plan_sha256=plan_sha256,
        acceptance_rules_version="1.0.0",
        acceptance_rules_sha256=rules_sha256,
        fixture_expectations=fixture_expectations,
        case_expectations=case_expectations,
    )


def _oracle_for_authorization(authorization):
    return _oracle_for_pins(
        fixture_manifest_sha256=authorization.fixture_manifest_sha256,
        artifact_sha256=authorization.apk_sha256,
        plan_sha256=authorization.plan_sha256,
        rules_sha256=authorization.rules_sha256,
    )


class LibraryInteractionOracleTests(unittest.TestCase):
    def test_private_oracle_contract_is_versioned_and_pin_validated(self):
        self.assertTrue(callable(getattr(oracle_contract, "validate_oracle", None)))
        self.assertTrue(hasattr(oracle_contract, "LibraryInteractionOracle"))
        document = _issue27_authorization_document(timeout_seconds=1)
        authorization = manifest._validate_authorization(
            document,
            profile=manifest._AuthorizationProfile.LIBRARY_INTERACTIONS,
        )
        spec = test_admission.session_spec(authorization)
        oracle = _oracle_for_authorization(authorization)

        self.assertEqual(oracle.schema_version, oracle_contract.LIBRARY_INTERACTION_CONTRACT_VERSION)
        self.assertTrue(oracle_contract.validate_oracle(
            oracle,
            authorization,
            spec,
            oracle.oracle_sha256,
        ))

    def test_no_match_query_is_nonempty_and_clear_is_an_independent_case(self):
        document = _issue27_authorization_document(timeout_seconds=1)
        authorization = manifest._validate_authorization(
            document,
            profile=manifest._AuthorizationProfile.LIBRARY_INTERACTIONS,
        )
        spec = test_admission.session_spec(authorization)
        oracle = _oracle_for_authorization(authorization)
        cases = {item.case_id: item for item in oracle.case_expectations}

        self.assertTrue(cases["search_empty"].input_value)
        self.assertEqual(cases["search_empty"].expected_fixture_ids, ())
        self.assertEqual(cases["search_clear"].input_value, "")
        self.assertEqual(
            cases["search_clear"].expected_fixture_ids,
            tuple(item.fixture_id for item in oracle.fixture_expectations),
        )
        invalid_cases = tuple(
            replace(item, input_value="", expected_fixture_ids=())
            if item.case_id == "search_empty" else item
            for item in oracle.case_expectations
        )
        invalid = replace(oracle, case_expectations=invalid_cases)
        self.assertFalse(oracle_contract.validate_oracle(
            invalid, authorization, spec, invalid.oracle_sha256
        ))

    def test_no_match_projection_requires_all_searchable_identity_fields(self):
        document = _issue27_authorization_document(timeout_seconds=1)
        authorization = manifest._validate_authorization(
            document,
            profile=manifest._AuthorizationProfile.LIBRARY_INTERACTIONS,
        )
        spec = test_admission.session_spec(authorization)
        oracle = _oracle_for_authorization(authorization)
        search_empty = next(
            item for item in oracle.case_expectations
            if item.case_id == "search_empty"
        )

        self.assertIn(
            "searchable_projection_completeness",
            search_empty.unsupported_assertions,
        )
        incomplete_claim = replace(
            oracle,
            case_expectations=tuple(
                replace(
                    item,
                    unsupported_assertions=tuple(
                        assertion for assertion in item.unsupported_assertions
                        if assertion != "searchable_projection_completeness"
                    ),
                )
                if item.case_id == "search_empty" else item
                for item in oracle.case_expectations
            ),
        )
        self.assertFalse(oracle_contract.validate_oracle(
            incomplete_claim,
            authorization,
            spec,
            incomplete_claim.oracle_sha256,
        ))
        missing_projection_with_display_match = replace(
            oracle,
            case_expectations=tuple(
                replace(
                    item,
                    input_value="Metroid-no-match",
                    expected_retained_query="Metroid-no-match",
                    searchable_identities=(),
                )
                if item.case_id == "search_empty" else item
                for item in oracle.case_expectations
            ),
        )
        self.assertFalse(oracle_contract.validate_oracle(
            missing_projection_with_display_match,
            authorization,
            spec,
            missing_projection_with_display_match.oracle_sha256,
        ))

        complete_identity = oracle_contract.LibrarySearchableIdentity(
            "fixture-synthetic",
            ("Metroid",),
            ("Space Hunter",),
            ("Metroid Fallback",),
        )
        complete_case = replace(
            search_empty,
            searchable_identities=(complete_identity,),
            unsupported_assertions=tuple(
                assertion for assertion in search_empty.unsupported_assertions
                if assertion != "searchable_projection_completeness"
            ),
        )
        complete_oracle = replace(
            oracle,
            case_expectations=tuple(
                complete_case if item.case_id == "search_empty" else item
                for item in oracle.case_expectations
            ),
        )
        self.assertTrue(oracle_contract.validate_oracle(
            complete_oracle,
            authorization,
            spec,
            complete_oracle.oracle_sha256,
        ))
        inconsistent_display = replace(
            complete_oracle,
            case_expectations=tuple(
                replace(
                    item,
                    searchable_identities=(
                        replace(complete_identity, display_titles=("Unpinned",)),
                    ),
                )
                if item.case_id == "search_empty" else item
                for item in complete_oracle.case_expectations
            ),
        )
        self.assertFalse(oracle_contract.validate_oracle(
            inconsistent_display,
            authorization,
            spec,
            inconsistent_display.oracle_sha256,
        ))

        for title in ("Metroid", "Space Hunter", "Metroid Fallback"):
            with self.subTest(title=title):
                matching_case = replace(
                    complete_case,
                    input_value=title,
                    expected_retained_query=title,
                )
                matching_oracle = replace(
                    complete_oracle,
                    case_expectations=tuple(
                        matching_case if item.case_id == "search_empty" else item
                        for item in complete_oracle.case_expectations
                    ),
                )
                self.assertFalse(oracle_contract.validate_oracle(
                    matching_oracle,
                    authorization,
                    spec,
                    matching_oracle.oracle_sha256,
                ))

    def test_selection_identity_must_belong_to_initial_selection_membership(self):
        document = _issue27_authorization_document(timeout_seconds=1)
        authorization = manifest._validate_authorization(
            document,
            profile=manifest._AuthorizationProfile.LIBRARY_INTERACTIONS,
        )
        spec = test_admission.session_spec(authorization)
        oracle = _oracle_for_authorization(authorization)
        invalid = replace(
            oracle,
            case_expectations=tuple(
                replace(item, expected_fixture_ids=())
                if item.case_id == "selection" else item
                for item in oracle.case_expectations
            ),
        )

        self.assertFalse(oracle_contract.validate_oracle(
            invalid,
            authorization,
            spec,
            invalid.oracle_sha256,
        ))

    def test_oracle_records_order_groups_and_independent_but_unsupported_assertions(self):
        document = _issue27_authorization_document(timeout_seconds=1)
        authorization = manifest._validate_authorization(
            document,
            profile=manifest._AuthorizationProfile.LIBRARY_INTERACTIONS,
        )
        spec = test_admission.session_spec(authorization)
        oracle = _oracle_for_authorization(authorization)
        cases = {item.case_id: item for item in oracle.case_expectations}

        self.assertEqual(
            getattr(cases["sort_title_ascending"], "expected_order_groups", None),
            (("fixture-synthetic",),),
        )
        selection = cases["selection"]
        self.assertEqual(
            getattr(selection, "expected_selection_identity", None),
            "fixture-synthetic",
        )
        self.assertIs(getattr(selection, "expected_selection_state", None), True)
        self.assertIn(
            "selection_identity",
            getattr(selection, "unsupported_assertions", ()),
        )
        self.assertIn(
            "selection_state",
            getattr(selection, "unsupported_assertions", ()),
        )
        retained = cases["search_after_selection"]
        self.assertEqual(
            getattr(retained, "expected_retained_query", None),
            "Metroid",
        )
        self.assertIn(
            "retained_query_state",
            getattr(retained, "unsupported_assertions", ()),
        )
        detail = cases["detail_observation"]
        self.assertEqual(
            getattr(detail, "expected_detail_facts", None),
            ("fixture-synthetic", "Metroid", "NES"),
        )
        self.assertIn(
            "stable_detail_facts",
            getattr(detail, "unsupported_assertions", ()),
        )

        tied_fixtures = oracle.fixture_expectations + (
            test_admission.ui.LibraryExpectation("fixture-synthetic-2", "Metroid", "SNES"),
        )
        tied_ids = tuple(item.fixture_id for item in tied_fixtures)
        tied_cases = tuple(
            replace(
                item,
                expected_fixture_ids=() if item.case_id == "search_empty" else tied_ids,
                searchable_identities=(
                    tuple(
                        oracle_contract.LibrarySearchableIdentity(
                            fixture.fixture_id,
                            (fixture.display_title,),
                            None,
                            None,
                        )
                        for fixture in tied_fixtures
                    )
                    if item.case_id == "search_empty"
                    else item.searchable_identities
                ),
                expected_order_groups=(
                    (tied_ids,)
                    if item.case_id in {
                        "sort_title", "sort_title_ascending", "sort_title_descending"
                    }
                    else (
                        ((tied_ids[0],), (tied_ids[1],))
                        if item.case_id in {
                            "sort_platform", "sort_platform_ascending"
                        }
                        else (
                            ((tied_ids[1],), (tied_ids[0],))
                            if item.case_id == "sort_platform_descending"
                            else ()
                        )
                    )
                ),
            )
            for item in oracle.case_expectations
        )
        tied_oracle = replace(
            oracle,
            fixture_expectations=tied_fixtures,
            case_expectations=tied_cases,
        )
        self.assertTrue(oracle_contract.validate_oracle(
            tied_oracle,
            authorization,
            spec,
            tied_oracle.oracle_sha256,
        ))

    def test_oracle_rejects_a_matching_no_match_term_and_unbound_detail_facts(self):
        document = _issue27_authorization_document(timeout_seconds=1)
        authorization = manifest._validate_authorization(
            document,
            profile=manifest._AuthorizationProfile.LIBRARY_INTERACTIONS,
        )
        spec = test_admission.session_spec(authorization)
        oracle = _oracle_for_authorization(authorization)
        matching_query = replace(
            oracle,
            case_expectations=tuple(
                replace(
                    item,
                    input_value="Metroid-no-match",
                    expected_retained_query="Metroid-no-match",
                )
                if item.case_id == "search_empty" else item
                for item in oracle.case_expectations
            ),
        )
        self.assertFalse(oracle_contract.validate_oracle(
            matching_query, authorization, spec, matching_query.oracle_sha256
        ))
        unbound_detail = replace(
            oracle,
            case_expectations=tuple(
                replace(
                    item,
                    expected_detail_facts=("fixture-synthetic", "Other Game", "NES"),
                )
                if item.case_id == "detail_observation" else item
                for item in oracle.case_expectations
            ),
        )
        self.assertFalse(oracle_contract.validate_oracle(
            unbound_detail, authorization, spec, unbound_detail.oracle_sha256
        ))
        unsupported_claim = replace(
            oracle,
            case_expectations=tuple(
                replace(item, unsupported_assertions=())
                if item.case_id == "search_exact" else item
                for item in oracle.case_expectations
            ),
        )
        self.assertFalse(oracle_contract.validate_oracle(
            unsupported_claim,
            authorization,
            spec,
            unsupported_claim.oracle_sha256,
        ))
        self.assertFalse(oracle_contract.validate_oracle(
            replace(oracle, artifact_sha256="f" * 64),
            authorization,
            spec,
            oracle.oracle_sha256,
        ))

    def test_search_cases_require_independent_query_membership_and_retained_state(self):
        document = _issue27_authorization_document(timeout_seconds=1)
        authorization = manifest._validate_authorization(
            document,
            profile=manifest._AuthorizationProfile.LIBRARY_INTERACTIONS,
        )
        spec = test_admission.session_spec(authorization)
        oracle = _oracle_for_authorization(authorization)
        invalid_expectations = (
            {"input_value": None},
            {"input_value": ""},
            {"expected_fixture_ids": ()},
            {"expected_fixture_ids": ("not-pinned-to-fixture-manifest",)},
            {"expected_retained_query": None},
            {"expected_retained_query": "contradictory-query"},
        )

        for case_id in ("search_exact", "search_partial"):
            for changes in invalid_expectations:
                with self.subTest(case_id=case_id, changes=changes):
                    invalid = replace(
                        oracle,
                        case_expectations=tuple(
                            replace(item, **changes)
                            if item.case_id == case_id else item
                            for item in oracle.case_expectations
                        ),
                    )
                    self.assertFalse(oracle_contract.validate_oracle(
                        invalid,
                        authorization,
                        spec,
                        invalid.oracle_sha256,
                    ))

    def test_search_exact_and_partial_queries_must_be_distinct(self):
        document = _issue27_authorization_document(timeout_seconds=1)
        authorization = manifest._validate_authorization(
            document,
            profile=manifest._AuthorizationProfile.LIBRARY_INTERACTIONS,
        )
        spec = test_admission.session_spec(authorization)
        oracle = _oracle_for_authorization(authorization)
        invalid = replace(
            oracle,
            case_expectations=tuple(
                replace(
                    item,
                    input_value="Metroid",
                    expected_retained_query="Metroid",
                )
                if item.case_id == "search_partial" else item
                for item in oracle.case_expectations
            ),
        )

        self.assertFalse(oracle_contract.validate_oracle(
            invalid,
            authorization,
            spec,
            invalid.oracle_sha256,
        ))


class _FreshAdmissionTransport:
    def __init__(self):
        self.calls = 0
        self.observation = test_admission.FirstAddScanAdmissionTests.observation(
            admission.InstallationObservation.absent(),
            foreground="com.android.launcher3",
        )

    def observe_fresh_admission(self):
        self.calls += 1
        return self.observation


class LibraryInteractionPlanTests(unittest.TestCase):
    def test_issue27_executor_is_defined_in_a_private_module(self):
        module_spec = importlib.util.find_spec(
            "scripts.android_qualification._library_interaction_executor"
        )

        self.assertIsNotNone(module_spec)
        self.assertFalse(hasattr(admission, "_LibraryInteractionOperationExecutor"))

    def test_closed_executors_share_a_fixed_lifecycle_without_accepting_plan_lists(self):
        lifecycle = getattr(admission, "_execute_closed_admitted_session", None)

        self.assertTrue(callable(lifecycle))
        self.assertNotIn("operations", inspect.signature(lifecycle).parameters)
        with self.assertRaises(admission._AddScanStop):
            lifecycle(object(), now=NOW)

        class UnapprovedExecutor(admission._AddScanOperationExecutor):
            pass

        unapproved = object.__new__(UnapprovedExecutor)
        with self.assertRaises(admission._AddScanStop):
            lifecycle(unapproved, now=NOW)

    def test_admission_import_does_not_load_oracle_or_physical_ui(self):
        repository_root = Path(__file__).resolve().parents[2]
        environment = os.environ.copy()
        environment["PYTHONPATH"] = os.pathsep.join(("src", "tests"))
        import_check = (
            "import sys\n"
            "import scripts.android_qualification.admission as admission\n"
            "try:\n"
            "    admission._execute_closed_admitted_session(object())\n"
            "except admission._AddScanStop:\n"
            "    pass\n"
            "else:\n"
            "    raise AssertionError('unapproved executor was accepted')\n"
            "assert 'scripts.android_qualification._library_interaction_oracle' not in sys.modules\n"
            "assert 'scripts.android_qualification.physical.ui' not in sys.modules\n"
            "assert 'scripts.android_qualification.physical._library_interaction_ui' not in sys.modules\n"
            "assert 'scripts.android_qualification._library_interaction_executor' not in sys.modules"
        )

        result = subprocess.run(
            [sys.executable, "-c", import_check],
            cwd=repository_root,
            env=environment,
            capture_output=True,
            text=True,
            check=False,
        )

        self.assertEqual(result.returncode, 0, result.stderr)

    def test_closed_plan_places_interactions_after_terminal_scan_and_cleanup_once_last(self):
        plan_validator = getattr(admission, "_library_interaction_plan", None)
        self.assertTrue(callable(plan_validator), "The distinct Issue #27 plan is not implemented.")

        authorization = _authorization_with_issue27_plan()
        plan = plan_validator(authorization)

        self.assertIsNotNone(plan)
        layout = admission._library_interaction_layout(plan)
        self.assertIsNotNone(layout)
        labels = [
            (operation.category.value,
             dict(operation.arguments).get("action")
             or dict(operation.arguments).get("observation"))
            for operation in plan
        ]
        self.assertLess(labels.index(("read_only", "terminal_scan")),
                        labels.index(("read_only", "library_complete_membership")))
        self.assertEqual(labels[-1], ("fixture_staging", "remove_session_owned_fixture_set"))
        self.assertEqual(labels.count(("fixture_staging", "remove_session_owned_fixture_set")), 1)
        self.assertEqual(len(plan), 42)
        self.assertEqual(
            len(admission._LIBRARY_INTERACTION_OPERATIONS),
            len(oracle_contract.LIBRARY_INTERACTION_CASE_IDS) - 1,
        )
        self.assertEqual(len(layout.shared_add_scan_prefix), 17)
        self.assertEqual(
            layout.membership.operation_id,
            plan[admission._LIBRARY_MEMBERSHIP_INDEX].operation_id,
        )
        self.assertEqual(len(layout.dependent_interactions), 23)
        self.assertEqual(layout.cleanup.operation_id, plan[-1].operation_id)

    def test_closed_plan_rejects_a_mismatched_dependent_operation(self):
        authorization = _authorization_with_issue27_plan()
        operations = list(authorization.operations)
        dependent_start = admission._LIBRARY_DEPENDENT_INTERACTION_START
        operations[dependent_start] = _operation(
            dependent_start,
            OperationCategory.NAVIGATION,
            "library_filter_region",
            phase="qualification",
            extra={"oracle_sha256": _ORACLE_SHA256, "oracle_version": str(oracle_contract.LIBRARY_INTERACTION_CONTRACT_VERSION)},
        )
        authorization.operations = tuple(operations)

        self.assertIsNone(admission._library_interaction_plan(authorization))

    def test_valid_plan_uses_the_oracle_schema_revision(self):
        document = _issue27_authorization_document()
        authorization = manifest._validate_authorization(
            document,
            profile=manifest._AuthorizationProfile.LIBRARY_INTERACTIONS,
        )
        plan = admission._library_interaction_plan(authorization)
        oracle = _oracle_for_authorization(authorization)

        self.assertIsNotNone(plan)
        oracle_operation = next(
            operation for operation in plan
            if "oracle_version" in dict(operation.arguments)
        )
        self.assertEqual(
            dict(oracle_operation.arguments)["oracle_version"],
            str(oracle.schema_version),
        )
        self.assertEqual(str(oracle.schema_version), str(oracle_contract.LIBRARY_INTERACTION_CONTRACT_VERSION))

    def test_closed_plan_rejects_legacy_oracle_version_two(self):
        authorization = _authorization_with_issue27_plan()
        operations = list(authorization.operations)
        operation_index = admission._LIBRARY_MEMBERSHIP_INDEX
        operation = operations[operation_index]
        arguments = dict(operation.arguments)
        arguments["oracle_version"] = "2"
        operations[operation_index] = replace(
            operation,
            arguments=tuple(sorted(arguments.items())),
        )
        authorization.operations = tuple(operations)

        self.assertIsNone(admission._library_interaction_plan(authorization))

    def test_legacy_navigation_selector_rejects_library_interactions(self):
        with self.assertRaises(test_admission.ui.UIBlocked):
            test_admission.ui.navigation_control([], "library_search_exact")
        with self.assertRaises(test_admission.ui.UIBlocked):
            test_admission.ui.navigation_control([], "library_filter_platform")


class LibraryInteractionAdmissionTests(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.directory = Path(self.temporary_directory.name)
        self.registry_patch = mock.patch.object(
            admission, "_SESSION_REGISTRY_PATH", self.directory / "sessions.json"
        )
        self.safety_patch = mock.patch.object(
            admission, "_DEVICE_SAFETY_PATH", self.directory / "restoration.json"
        )
        self.registry_patch.start()
        self.safety_patch.start()
        self.addCleanup(self.registry_patch.stop)
        self.addCleanup(self.safety_patch.stop)

    def load_inputs(self, **document_options):
        authorization_loader = getattr(
            manifest, "_load_library_interaction_authorization", None
        )
        self.assertTrue(
            callable(authorization_loader),
            "The private Issue #27 authorization profile is not implemented.",
        )
        authorization_path = write_private_json(
            self.directory,
            "authorization.json",
            _issue27_authorization_document(**document_options),
        )
        authorization = authorization_loader(authorization_path)
        approval_path = write_private_json(
            self.directory,
            "approval.json",
            test_admission._first_add_scan_approval_document(authorization),
        )
        approval = manifest.load_owner_approval(
            approval_path,
            authorization,
            now=NOW,
        )
        return authorization, approval, _artifact_facts(), _FreshAdmissionTransport()

    def test_issue27_admission_rejects_over_budget_sequence_before_observation(self):
        admit = getattr(admission, "admit_library_interaction_session", None)
        self.assertTrue(callable(admit), "The private Issue #27 admission path is missing.")
        authorization, approval, artifact, transport = self.load_inputs(timeout_seconds=10)

        result = admit(authorization, approval, artifact, transport, now=NOW)

        self.assertEqual(result.code, admission.AdmissionCode.ADD_SCAN_PLAN_INVALID)
        self.assertEqual(transport.calls, 0)
        self.assertFalse((self.directory / "sessions.json").exists())

    def test_cleanup_reserve_is_checked_before_observation(self):
        admit = getattr(admission, "admit_library_interaction_session", None)
        self.assertTrue(callable(admit), "The private Issue #27 admission path is missing.")
        authorization, approval, artifact, transport = self.load_inputs(
            timeout_seconds=1,
            cleanup_timeout_seconds=10,
            cleanup_reserve_seconds=5,
        )

        result = admit(authorization, approval, artifact, transport, now=NOW)

        self.assertEqual(result.code, admission.AdmissionCode.ADD_SCAN_PLAN_INVALID)
        self.assertEqual(transport.calls, 0)

    def test_manifest_rejects_legacy_issue27_oracle_version_two(self):
        document = _issue27_authorization_document()
        document["operations"][17]["arguments"]["oracle_version"] = "2"

        with self.assertRaises(manifest.AuthorizationError):
            manifest._validate_authorization(
                document,
                profile=manifest._AuthorizationProfile.LIBRARY_INTERACTIONS,
            )

    def test_private_loader_accepts_issue27_profile_without_widening_legacy_loader(self):
        authorization_loader = getattr(
            manifest, "_load_library_interaction_authorization", None
        )
        self.assertTrue(
            callable(authorization_loader),
            "The private Issue #27 authorization profile is not implemented.",
        )
        path = write_private_json(
            self.directory,
            "authorization.json",
            _issue27_authorization_document(timeout_seconds=2),
        )

        authorization = authorization_loader(path)

        self.assertEqual(len(authorization.operations), 42)
        with self.assertRaises(manifest.AuthorizationError):
            manifest.load_authorization(path)

    def test_authorization_validator_rejects_untyped_profile_values(self):
        legacy_document = test_admission._first_add_scan_plan(installation="absent")

        with self.assertRaises(manifest.AuthorizationError):
            manifest._validate_authorization(
                legacy_document,
                profile="library_interactions",
            )

    def test_admission_consumes_the_owner_approval_once(self):
        admit = getattr(admission, "admit_library_interaction_session", None)
        self.assertTrue(callable(admit), "The private Issue #27 admission path is missing.")
        authorization, approval, artifact, transport = self.load_inputs(timeout_seconds=1)

        first = admit(authorization, approval, artifact, transport, now=NOW)
        second = admit(authorization, approval, artifact, transport, now=NOW)

        self.assertEqual(first.code, admission.AdmissionCode.ADMITTED)
        self.assertIsNotNone(first.session)
        self.assertEqual(second.code, admission.AdmissionCode.SESSION_ALREADY_USED)
        self.assertEqual(transport.calls, 1)


class LibraryInteractionExecutorTests(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.directory = Path(self.temporary_directory.name)
        self.registry_patch = mock.patch.object(
            admission, "_SESSION_REGISTRY_PATH", self.directory / "sessions.json"
        )
        self.safety_patch = mock.patch.object(
            admission, "_DEVICE_SAFETY_PATH", self.directory / "restoration.json"
        )
        self.registry_patch.start()
        self.safety_patch.start()
        self.addCleanup(self.registry_patch.stop)
        self.addCleanup(self.safety_patch.stop)
        self.evidence_store = test_admission.evidence.EvidenceStore(
            self.directory / "evidence"
        )

    def _executor_for_transport(self, transport, *, suffix):
        authorization_path = write_private_json(
            self.directory,
            f"authorization-{suffix}.json",
            _issue27_authorization_document(timeout_seconds=2),
        )
        authorization = manifest._load_library_interaction_authorization(
            authorization_path
        )
        approval_path = write_private_json(
            self.directory,
            f"approval-{suffix}.json",
            test_admission._first_add_scan_approval_document(authorization),
        )
        approval = manifest.load_owner_approval(
            approval_path,
            authorization,
            now=NOW,
        )
        admitted = admission.admit_library_interaction_session(
            authorization,
            approval,
            _artifact_facts(),
            transport,
            now=NOW,
        )
        session = admitted.session
        session_id = hashlib.sha256(
            f"argus-library-interactions:{authorization.authorization_id}:"
            f"{authorization.canonical_sha256}".encode()
        ).hexdigest()[:32]
        spec = replace(
            test_admission.session_spec(authorization),
            session_id=session_id,
        )
        writer = test_admission.RecordingWriter(
            self.evidence_store.execution_writer()
        )
        executor = issue27_executor._LibraryInteractionOperationExecutor(
            session=session,
            transport=transport,
            writer=writer,
            evidence_spec=spec,
            fixture_plan=admission.FixtureTransferPlan(
                fixture_manifest_sha256=authorization.fixture_manifest_sha256,
                file_count=1,
                byte_count=4,
                content_sha256="1" * 64,
            ),
            oracle=_oracle_for_authorization(authorization),
        )
        return admitted, executor, writer, session_id

    def _issue26_executor(self):
        legacy_case = test_admission.AddScanExecutorTests()
        legacy_case.directory = self.directory
        legacy_case.evidence_store = test_admission.evidence.EvidenceStore(
            self.directory / "issue26-evidence"
        )
        _, session, transport = legacy_case.admitted("absent")
        return session, legacy_case.executor(session, transport)

    def test_issue26_execute_delegates_to_the_shared_lifecycle(self):
        _, executor = self._issue26_executor()
        sentinel = object()

        with mock.patch.object(
            admission,
            "_execute_closed_admitted_session",
            return_value=sentinel,
        ) as lifecycle:
            result = executor.execute(now=NOW)

        self.assertIs(result, sentinel)
        lifecycle.assert_called_once_with(executor, now=NOW)

    def test_issue26_execution_capability_is_one_use_and_profile_bound(self):
        session, _ = self._issue26_executor()

        self.assertTrue(admission._claim_first_add_scan_execution(session))
        self.assertFalse(admission._claim_first_add_scan_execution(session))
        self.assertFalse(admission._claim_library_interaction_execution(session))

    def test_issue27_executor_is_separate_from_the_closed_issue26_executor(self):
        self.assertFalse(
            issubclass(
                issue27_executor._LibraryInteractionOperationExecutor,
                admission._AddScanOperationExecutor,
            )
        )
        for profile_hook in (
            "_claim_executor_capability",
            "_executor_session_namespace",
            "_executor_admission_binding",
            "_before_cleanup",
        ):
            with self.subTest(profile_hook=profile_hook):
                self.assertNotIn(
                    profile_hook,
                    admission._AddScanOperationExecutor.__dict__,
                )

    def test_issue27_execute_delegates_to_the_shared_lifecycle(self):
        transport = test_admission.FakeAddScanTransport("absent")
        _, executor, _, _ = self._executor_for_transport(
            transport,
            suffix="shared-lifecycle",
        )
        sentinel = object()
        with mock.patch.object(
            admission,
            "_execute_closed_admitted_session",
            return_value=sentinel,
        ) as lifecycle:
            result = executor.execute(now=NOW)

        self.assertIs(result, sentinel)
        lifecycle.assert_called_once_with(executor, now=NOW)

    def test_issue27_capability_is_one_use_and_profile_bound(self):
        transport = test_admission.FakeAddScanTransport("absent")
        _, executor, _, _ = self._executor_for_transport(
            transport,
            suffix="one-use-claim",
        )
        session = executor._session

        self.assertTrue(admission._claim_library_interaction_execution(session))
        self.assertFalse(admission._claim_library_interaction_execution(session))
        self.assertFalse(admission._claim_first_add_scan_execution(session))

    def test_issue27_ui_failure_is_not_downgraded_to_blocked(self):
        from scripts.android_qualification.physical import _library_interaction_ui

        transport = test_admission.FakeAddScanTransport("absent")
        admitted, executor, writer, session_id = self._executor_for_transport(
            transport,
            suffix="explicit-ui-failure",
        )
        explicit_failure = test_admission.ui.UIFailed("synthetic product failure")

        with mock.patch.object(
            _library_interaction_ui,
            "parse_issue27_library_ui",
            side_effect=explicit_failure,
        ):
            result = executor.execute(now=NOW)

        membership_ref = admission._add_scan_alias(
            "assertion",
            f"{session_id}:library-interaction-case-00:result",
        )
        membership_outcome = next(
            item.actual_outcome
            for item in writer.assertions
            if item.assertion_ref == membership_ref
        )
        self.assertEqual(admitted.code, admission.AdmissionCode.ADMITTED)
        self.assertIs(
            membership_outcome,
            test_admission.evidence.AssertionOutcome.FAILED,
        )
        self.assertEqual(result.cleanup_status, "verified")
        self.assertEqual(transport.cleanup_calls, 1)
        self.assertTrue(executor._assertion_failed)

    def test_interrupt_releases_the_session_and_withholds_unowned_cleanup(self):
        transport = test_admission.FakeAddScanTransport("absent")
        transport.interrupt_action = "add_and_scan"
        _, executor, writer, _ = self._executor_for_transport(
            transport,
            suffix="interrupted-session-release",
        )

        result = executor.execute(now=NOW)

        self.assertEqual(result.status, admission.AddScanExecutionStatus.BLOCKED)
        self.assertEqual(result.cleanup_status, "blocked")
        self.assertEqual(transport.cleanup_calls, 0)
        self.assertEqual(
            writer.terminals[-1].outcome,
            test_admission.evidence.TerminalOutcome.INTERRUPTED,
        )
        self.assertTrue(executor._session.reserve_operation())
        executor._session.release_operation()

    def test_executor_blocks_unproven_membership_and_cleans_up_once_at_the_end(self):
        executor_type = getattr(
            issue27_executor, "_LibraryInteractionOperationExecutor", None
        )
        self.assertTrue(
            callable(executor_type),
            "The private Issue #27 executor is not implemented.",
        )
        authorization_path = write_private_json(
            self.directory,
            "authorization.json",
            _issue27_authorization_document(timeout_seconds=2),
        )
        authorization = manifest._load_library_interaction_authorization(
            authorization_path
        )
        approval_path = write_private_json(
            self.directory,
            "approval.json",
            test_admission._first_add_scan_approval_document(authorization),
        )
        approval = manifest.load_owner_approval(
            approval_path,
            authorization,
            now=NOW,
        )
        transport = test_admission.FakeAddScanTransport("absent")
        admitted = admission.admit_library_interaction_session(
            authorization,
            approval,
            _artifact_facts(),
            transport,
            now=NOW,
        )
        self.assertEqual(admitted.code, admission.AdmissionCode.ADMITTED)
        session = admitted.session
        self.assertFalse(
            admission._claim_first_add_scan_execution(session),
            "The Issue #26 capability must not claim an Issue #27 session.",
        )
        session_id = hashlib.sha256(
            f"argus-library-interactions:{authorization.authorization_id}:"
            f"{authorization.canonical_sha256}".encode()
        ).hexdigest()[:32]
        spec = replace(
            test_admission.session_spec(authorization),
            session_id=session_id,
        )
        writer = test_admission.RecordingWriter(
            self.evidence_store.execution_writer()
        )
        executor = executor_type(
            session=session,
            transport=transport,
            writer=writer,
            evidence_spec=spec,
            fixture_plan=admission.FixtureTransferPlan(
                fixture_manifest_sha256=authorization.fixture_manifest_sha256,
                file_count=1,
                byte_count=4,
                content_sha256="1" * 64,
            ),
            oracle=_oracle_for_authorization(authorization),
        )

        result = executor.execute(now=NOW)

        self.assertEqual(result.status, admission.AddScanExecutionStatus.BLOCKED)
        self.assertEqual(
            result.cleanup_status,
            "verified",
            f"blocker={result.blocker!r}; terminal={result.terminal_scan_status!r}; "
            f"admission={result.scan_admission!r}; job={result.job_status!r}; "
            f"mutations={transport.mutations!r}; nav={transport.nav_actions!r}; "
            f"stage_calls={transport.stage_calls}; cleanup_calls={transport.cleanup_calls}",
        )
        self.assertEqual(transport.cleanup_calls, 1)
        self.assertEqual(transport.nav_actions[-1], "library_navigation")
        self.assertNotIn("library_search_exact", transport.nav_actions)
        self.assertNotIn("library_filter_platform", transport.nav_actions)
        self.assertTrue(any(
            item.actual_outcome is test_admission.evidence.AssertionOutcome.BLOCKED
            for item in writer.assertions
        ))
        self.assertTrue(any(
            item.actual_outcome is test_admission.evidence.AssertionOutcome.NOT_RUN
            for item in writer.assertions
        ))
        case_outcomes = {
            item.assertion_ref: item.actual_outcome
            for item in writer.assertions
            if item.assertion_ref in {
                admission._add_scan_alias(
                    "assertion", f"{session_id}:library-interaction-case-{index:02d}:result"
                )
                for index in range(24)
            }
        }
        self.assertEqual(len(case_outcomes), 24)
        self.assertEqual(
            case_outcomes[admission._add_scan_alias(
                "assertion", f"{session_id}:library-interaction-case-00:result"
            )],
            test_admission.evidence.AssertionOutcome.BLOCKED,
        )
        for index in range(1, 24):
            self.assertEqual(
                case_outcomes[admission._add_scan_alias(
                    "assertion", f"{session_id}:library-interaction-case-{index:02d}:result"
                )],
                test_admission.evidence.AssertionOutcome.NOT_RUN,
            )
        self.assertEqual(writer.terminals[-1].outcome,
                         test_admission.evidence.TerminalOutcome.BLOCKED)
        cleanup_request = admission._add_scan_alias(
            "operation", f"{session_id}:operation-41:result"
        )
        cleanup_event = next(
            event for event in writer.events
            if event[0] == "assertion" and event[2].operation_id == cleanup_request
        )
        case_refs = {
            admission._add_scan_alias(
                "assertion", f"{session_id}:library-interaction-case-{index:02d}:result"
            )
            for index in range(24)
        }
        last_case_event = max(
            (index for index, event in enumerate(writer.events)
             if event[0] == "assertion" and event[1].assertion_ref in case_refs),
            default=-1,
        )
        self.assertGreater(writer.events.index(cleanup_event), last_case_event)

    def test_invalid_evidence_spec_fails_closed_before_fixture_staging(self):
        transport = test_admission.FakeAddScanTransport("absent")
        _, executor, _, _ = self._executor_for_transport(
            transport,
            suffix="invalid-evidence-spec",
        )
        try:
            admission._validate_executor_session_inputs(
                session=executor._session,
                evidence_spec=None,
                fixture_plan=executor._fixture_plan,
                expectations=executor._expectations,
                binding=admission._library_interaction_admission_binding(
                    executor._session
                ),
                session_namespace="argus-library-interactions",
                instant=NOW,
            )
        except admission._AddScanStop:
            pass
        except AttributeError as error:
            self.fail(f"Invalid evidence input was dereferenced before validation: {error}")
        else:
            self.fail("An invalid evidence specification must stop before fixture staging.")
        executor._spec = None
        result = executor.execute(now=NOW)
        self.assertEqual(result.status, admission.AddScanExecutionStatus.BLOCKED)
        self.assertEqual(result.cleanup_status, "not_attempted")
        self.assertEqual(transport.stage_calls, 0)

    def test_uncertain_scan_tap_is_not_retried_and_cleanup_follows_terminalization(self):
        authorization_path = write_private_json(
            self.directory,
            "authorization-uncertain.json",
            _issue27_authorization_document(timeout_seconds=2),
        )
        authorization = manifest._load_library_interaction_authorization(
            authorization_path
        )
        approval_path = write_private_json(
            self.directory,
            "approval-uncertain.json",
            test_admission._first_add_scan_approval_document(authorization),
        )
        approval = manifest.load_owner_approval(
            approval_path,
            authorization,
            now=NOW,
        )
        transport = test_admission.FakeAddScanTransport("absent")
        transport.navigation_uncertain_action = "add_and_scan"
        admitted = admission.admit_library_interaction_session(
            authorization,
            approval,
            _artifact_facts(),
            transport,
            now=NOW,
        )
        self.assertEqual(admitted.code, admission.AdmissionCode.ADMITTED)
        session = admitted.session
        session_id = hashlib.sha256(
            f"argus-library-interactions:{authorization.authorization_id}:"
            f"{authorization.canonical_sha256}".encode()
        ).hexdigest()[:32]
        spec = replace(
            test_admission.session_spec(authorization),
            session_id=session_id,
        )
        writer = test_admission.RecordingWriter(
            self.evidence_store.execution_writer()
        )
        executor = issue27_executor._LibraryInteractionOperationExecutor(
            session=session,
            transport=transport,
            writer=writer,
            evidence_spec=spec,
            fixture_plan=admission.FixtureTransferPlan(
                fixture_manifest_sha256=authorization.fixture_manifest_sha256,
                file_count=1,
                byte_count=4,
                content_sha256="1" * 64,
            ),
            oracle=_oracle_for_authorization(authorization),
        )

        result = executor.execute(now=NOW)

        self.assertEqual(result.status, admission.AddScanExecutionStatus.BLOCKED)
        self.assertEqual(transport.nav_actions.count("add_and_scan"), 1)
        self.assertEqual(result.terminal_scan_status, "complete")
        self.assertEqual(transport.cleanup_calls, 1)
        self.assertFalse(transport.staged)
        self.assertLess(
            transport.nav_actions.index("add_and_scan"),
            transport.nav_actions.index("view_job"),
        )

    def test_unresolved_scan_admission_withholds_library_actions_and_cleanup(self):
        transport = test_admission.FakeAddScanTransport("absent")
        transport.navigation_uncertain_action = "add_and_scan"
        transport.scan_admission_uncertain = True
        admitted, executor, _writer, _session_id = self._executor_for_transport(
            transport,
            suffix="unresolved-scan",
        )

        result = executor.execute(now=NOW)

        self.assertEqual(admitted.code, admission.AdmissionCode.ADMITTED)
        self.assertEqual(result.status, admission.AddScanExecutionStatus.BLOCKED)
        self.assertEqual(transport.nav_actions.count("add_and_scan"), 1)
        self.assertIsNone(result.terminal_scan_status)
        self.assertNotIn("library_navigation", transport.nav_actions)
        self.assertEqual(transport.cleanup_calls, 0)
        self.assertEqual(result.cleanup_status, "blocked")
        self.assertTrue(transport.staged)
        self.assertTrue(any(
            "uncertain scan admission" in extension.area
            for extension in result.scope_extensions
        ))

    def test_failed_terminal_scan_skips_library_and_cleans_owned_fixtures_once(self):
        transport = test_admission.FakeAddScanTransport("absent")
        transport.job_status_label = "Failed"
        transport.scan_status_label = "Failed"
        admitted, executor, writer, session_id = self._executor_for_transport(
            transport,
            suffix="failed-terminal-scan",
        )

        result = executor.execute(now=NOW)

        self.assertEqual(admitted.code, admission.AdmissionCode.ADMITTED)
        self.assertEqual(result.status, admission.AddScanExecutionStatus.BLOCKED)
        self.assertEqual(result.terminal_scan_status, "failed")
        self.assertNotIn("library_navigation", transport.nav_actions)
        self.assertEqual(transport.cleanup_calls, 1)
        self.assertEqual(result.cleanup_status, "verified")
        self.assertFalse(transport.staged)
        expected_refs = {
            admission._add_scan_alias(
                "assertion",
                f"{session_id}:library-interaction-case-{index:02d}:result",
            )
            for index in range(1, 24)
        }
        dependent_outcomes = {
            item.assertion_ref: item.actual_outcome
            for item in writer.assertions
            if item.assertion_ref in expected_refs
        }
        self.assertEqual(set(dependent_outcomes), expected_refs)
        self.assertTrue(all(
            outcome is test_admission.evidence.AssertionOutcome.NOT_RUN
            for outcome in dependent_outcomes.values()
        ))

    def test_case_outcome_append_failure_withholds_cleanup(self):
        transport = test_admission.FakeAddScanTransport("absent")
        admitted, executor, writer, session_id = self._executor_for_transport(
            transport,
            suffix="case-evidence-failure",
        )
        failed_ref = admission._add_scan_alias(
            "assertion",
            f"{session_id}:library-interaction-case-05:result",
        )
        append_assertion = writer.append_assertion

        def append_except_one_case(session, observation, request):
            if observation.assertion_ref == failed_ref:
                raise OSError("synthetic append failure")
            return append_assertion(session, observation, request)

        with mock.patch.object(
            writer,
            "append_assertion",
            side_effect=append_except_one_case,
        ):
            result = executor.execute(now=NOW)

        self.assertEqual(admitted.code, admission.AdmissionCode.ADMITTED)
        self.assertEqual(result.status, admission.AddScanExecutionStatus.BLOCKED)
        self.assertEqual(result.terminal_scan_status, "complete")
        self.assertEqual(transport.cleanup_calls, 0)
        self.assertEqual(result.cleanup_status, "blocked")
        self.assertTrue(transport.staged)
        self.assertIn("case outcomes", result.blocker)

    def test_case_outcome_interrupt_is_terminal_and_never_retries_or_cleans_up(self):
        transport = test_admission.FakeAddScanTransport("absent")
        admitted, executor, writer, session_id = self._executor_for_transport(
            transport,
            suffix="case-evidence-interrupted",
        )
        interrupted_ref = admission._add_scan_alias(
            "assertion",
            f"{session_id}:library-interaction-case-05:result",
        )
        append_assertion = writer.append_assertion
        interrupted_attempts = []

        def interrupt_on_one_case(session, observation, request):
            if observation.assertion_ref == interrupted_ref:
                interrupted_attempts.append(observation.assertion_ref)
                raise KeyboardInterrupt
            return append_assertion(session, observation, request)

        with mock.patch.object(
            writer,
            "append_assertion",
            side_effect=interrupt_on_one_case,
        ):
            try:
                result = executor.execute(now=NOW)
            except KeyboardInterrupt:
                self.fail(
                    "An interrupted case append must still finalize the session safely."
                )

        self.assertEqual(admitted.code, admission.AdmissionCode.ADMITTED)
        self.assertEqual(result.status, admission.AddScanExecutionStatus.BLOCKED)
        self.assertEqual(result.terminal_scan_status, "complete")
        self.assertEqual(result.cleanup_status, "blocked")
        self.assertEqual(transport.cleanup_calls, 0)
        self.assertTrue(transport.staged)
        self.assertEqual(interrupted_attempts, [interrupted_ref])
        self.assertNotIn(interrupted_ref, {item.assertion_ref for item in writer.assertions})
        self.assertEqual(
            writer.terminals[-1].outcome,
            test_admission.evidence.TerminalOutcome.INTERRUPTED,
        )
        self.assertTrue(any(
            "fixture cleanup withheld" in extension.area
            for extension in result.scope_extensions
        ))

    def test_membership_outcome_interrupt_is_not_retried_or_cleaned_up(self):
        transport = test_admission.FakeAddScanTransport("absent")
        admitted, executor, writer, session_id = self._executor_for_transport(
            transport,
            suffix="membership-evidence-interrupted",
        )
        membership_ref = admission._add_scan_alias(
            "assertion",
            f"{session_id}:library-interaction-case-00:result",
        )
        case_refs = {
            admission._add_scan_alias(
                "assertion",
                f"{session_id}:library-interaction-case-{index:02d}:result",
            )
            for index in range(len(oracle_contract.LIBRARY_INTERACTION_CASE_IDS))
        }
        append_assertion = writer.append_assertion
        attempted_case_refs = []

        def interrupt_membership_append(session, observation, request):
            if observation.assertion_ref in case_refs:
                attempted_case_refs.append(observation.assertion_ref)
                if observation.assertion_ref == membership_ref:
                    raise KeyboardInterrupt
            return append_assertion(session, observation, request)

        with mock.patch.object(
            writer,
            "append_assertion",
            side_effect=interrupt_membership_append,
        ):
            result = executor.execute(now=NOW)

        self.assertEqual(admitted.code, admission.AdmissionCode.ADMITTED)
        self.assertEqual(result.status, admission.AddScanExecutionStatus.BLOCKED)
        self.assertEqual(result.terminal_scan_status, "complete")
        self.assertEqual(result.cleanup_status, "blocked")
        self.assertEqual(transport.cleanup_calls, 0)
        self.assertTrue(transport.staged)
        self.assertEqual(attempted_case_refs, [membership_ref])
        self.assertEqual(
            writer.terminals[-1].outcome,
            test_admission.evidence.TerminalOutcome.INTERRUPTED,
        )
        self.assertTrue(any(
            "fixture cleanup withheld" in extension.area
            for extension in result.scope_extensions
        ))


if __name__ == "__main__":
    unittest.main()
