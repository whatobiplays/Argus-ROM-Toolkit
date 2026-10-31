"""Private, versioned expectations for the Issue #27 Library scenario.

The oracle binds fixture display identities and interaction expectations to the
approved fixture manifest, Release artifact, plan, and acceptance-rule pins.
Its private labels are used only in memory; shared execution evidence contains
opaque assertion aliases and categorical outcomes.
"""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
import re

from . import evidence, manifest
from ._library_interaction_contract import (
    LIBRARY_INTERACTION_CASE_IDS,
    LIBRARY_INTERACTION_CONTRACT_VERSION,
)
from .physical import ui

_DIGEST_RE = re.compile(r"[0-9a-f]{64}")
_ORDERED_CASES = frozenset({
    "sort_title", "sort_title_ascending", "sort_title_descending",
    "sort_platform", "sort_platform_ascending", "sort_platform_descending",
})
_ALLOWED_UNSUPPORTED_ASSERTIONS = frozenset({
    "complete_membership", "traversal_completion", "pagination_completion",
    "interaction_result", "result_order", "selection_identity",
    "selection_state", "retained_query_state", "stable_detail_facts",
    "searchable_projection_completeness",
})
_REQUIRED_UNSUPPORTED_ASSERTIONS = {
    "membership": frozenset({
        "complete_membership", "traversal_completion", "pagination_completion",
    }),
    "search_exact": frozenset({
        "complete_membership", "interaction_result", "retained_query_state",
    }),
    "search_partial": frozenset({
        "complete_membership", "interaction_result", "retained_query_state",
    }),
    "search_empty": frozenset({
        "complete_membership", "interaction_result", "retained_query_state",
    }),
    "search_clear": frozenset({
        "complete_membership", "interaction_result", "retained_query_state",
    }),
    "filter_platform": frozenset({"complete_membership", "interaction_result"}),
    "filter_region": frozenset({"complete_membership", "interaction_result"}),
    "filter_hydration": frozenset({"complete_membership", "interaction_result"}),
    "filter_availability": frozenset({"complete_membership", "interaction_result"}),
    "filter_reset": frozenset({"complete_membership", "interaction_result"}),
    "selection": frozenset({
        "complete_membership", "interaction_result", "selection_identity",
        "selection_state",
    }),
    "sort_title": frozenset({
        "complete_membership", "interaction_result", "result_order",
    }),
    "sort_title_ascending": frozenset({
        "complete_membership", "interaction_result", "result_order",
    }),
    "sort_title_descending": frozenset({
        "complete_membership", "interaction_result", "result_order",
    }),
    "sort_platform": frozenset({
        "complete_membership", "interaction_result", "result_order",
    }),
    "sort_platform_ascending": frozenset({
        "complete_membership", "interaction_result", "result_order",
    }),
    "sort_platform_descending": frozenset({
        "complete_membership", "interaction_result", "result_order",
    }),
    "view_list": frozenset({"complete_membership", "interaction_result"}),
    "view_grid": frozenset({"complete_membership", "interaction_result"}),
    "search_after_selection": frozenset({
        "complete_membership", "interaction_result", "retained_query_state",
        "selection_identity", "selection_state",
    }),
    "detail_open": frozenset({
        "complete_membership", "interaction_result", "stable_detail_facts",
    }),
    "detail_observation": frozenset({
        "complete_membership", "stable_detail_facts",
    }),
    "return_to_library": frozenset({"complete_membership", "interaction_result"}),
    "return_observation": frozenset({"complete_membership", "interaction_result"}),
}


@dataclass(frozen=True)
class LibrarySearchableIdentity:
    """Private searchable identities established for one pinned fixture.

    ``None`` represents a field whose independent value is unavailable. An
    empty tuple records an independently established absence. These values are
    included in the private oracle digest and never copied to shared evidence.
    """

    fixture_id: str
    display_titles: tuple[str, ...] | None
    alternate_titles: tuple[str, ...] | None
    active_fallback_titles: tuple[str, ...] | None


@dataclass(frozen=True)
class LibraryCaseExpectation:
    """Independent private expectations and unsupported facts for one case.

    Order groups are traversed in sequence, while fixture IDs within a group
    are tied and may appear in any order. Expected query, selection, and detail
    values are pinned independently; ``searchable_identities`` is the private
    no-match proof across display, alternate, and active fallback titles; and
    ``unsupported_assertions`` records which facts the current Release cannot
    prove through its accessibility contract.
    """

    case_id: str
    input_value: str | None
    expected_fixture_ids: tuple[str, ...]
    expected_order_groups: tuple[tuple[str, ...], ...] = ()
    expected_selection_identity: str | None = None
    expected_selection_state: bool | None = None
    expected_retained_query: str | None = None
    expected_detail_facts: tuple[str, ...] | None = None
    searchable_identities: tuple[LibrarySearchableIdentity, ...] = ()
    unsupported_assertions: tuple[str, ...] = ()


@dataclass(frozen=True)
class LibraryInteractionOracle:
    """Versioned expectations bound to one authorized qualification session."""

    schema_version: int
    fixture_manifest_version: int
    fixture_manifest_sha256: str
    artifact_sha256: str
    plan_version: int
    plan_sha256: str
    acceptance_rules_version: str
    acceptance_rules_sha256: str
    fixture_expectations: tuple[ui.LibraryExpectation, ...]
    case_expectations: tuple[LibraryCaseExpectation, ...]

    @property
    def oracle_sha256(self) -> str:
        """Return a canonical digest of every private expectation and pin."""
        document = {
            "schema_version": self.schema_version,
            "fixture_manifest_version": self.fixture_manifest_version,
            "fixture_manifest_sha256": self.fixture_manifest_sha256,
            "artifact_sha256": self.artifact_sha256,
            "plan_version": self.plan_version,
            "plan_sha256": self.plan_sha256,
            "acceptance_rules_version": self.acceptance_rules_version,
            "acceptance_rules_sha256": self.acceptance_rules_sha256,
            "fixture_expectations": [
                {
                    "fixture_id": item.fixture_id,
                    "display_title": item.display_title,
                    "platform_label": item.platform_label,
                }
                for item in self.fixture_expectations
            ],
            "case_expectations": [
                {
                    "case_id": item.case_id,
                    "input_value": item.input_value,
                    "expected_fixture_ids": list(item.expected_fixture_ids),
                    "expected_order_groups": [
                        list(group) for group in item.expected_order_groups
                    ],
                    "expected_selection_identity": item.expected_selection_identity,
                    "expected_selection_state": item.expected_selection_state,
                    "expected_retained_query": item.expected_retained_query,
                    "expected_detail_facts": (
                        list(item.expected_detail_facts)
                        if item.expected_detail_facts is not None else None
                    ),
                    "searchable_identities": [
                        {
                            "fixture_id": identity.fixture_id,
                            "display_titles": (
                                list(identity.display_titles)
                                if identity.display_titles is not None else None
                            ),
                            "alternate_titles": (
                                list(identity.alternate_titles)
                                if identity.alternate_titles is not None else None
                            ),
                            "active_fallback_titles": (
                                list(identity.active_fallback_titles)
                                if identity.active_fallback_titles is not None
                                else None
                            ),
                        }
                        for identity in item.searchable_identities
                    ],
                    "unsupported_assertions": list(item.unsupported_assertions),
                }
                for item in self.case_expectations
            ],
        }
        encoded = json.dumps(
            document,
            sort_keys=True,
            separators=(",", ":"),
            ensure_ascii=False,
            allow_nan=False,
        ).encode("utf-8")
        return hashlib.sha256(encoded).hexdigest()


def _valid_searchable_identity_field(
    values: tuple[str, ...] | None,
) -> bool:
    """Return whether one optional private searchable field is well formed."""
    if values is None:
        return True
    if type(values) is not tuple:
        return False
    return all(
        type(title) is str
        and 1 <= len(title) <= 256
        and not any(
            ord(character) < 0x20 or ord(character) == 0x7f
            for character in title
        )
        for title in values
    ) and len(set(values)) == len(values)


def _valid_searchable_identities(
    identities: object,
    fixture_expectations: tuple[ui.LibraryExpectation, ...],
) -> bool:
    """Return whether an optional projection is well formed or unavailable."""
    fixture_ids = tuple(item.fixture_id for item in fixture_expectations)
    fixture_titles = {
        item.fixture_id: item.display_title for item in fixture_expectations
    }
    if type(identities) is not tuple:
        return False
    if not identities:
        return True
    if len(identities) != len(fixture_ids):
        return False
    if any(
        type(identity) is not LibrarySearchableIdentity
        or identity.fixture_id not in fixture_ids
        or not _valid_searchable_identity_field(identity.display_titles)
        or (
            identity.display_titles is not None
            and fixture_titles[identity.fixture_id] not in identity.display_titles
        )
        or not _valid_searchable_identity_field(identity.alternate_titles)
        or not _valid_searchable_identity_field(identity.active_fallback_titles)
        for identity in identities
    ):
        return False
    projected_ids = tuple(identity.fixture_id for identity in identities)
    return (
        len(set(projected_ids)) == len(projected_ids)
        and set(projected_ids) == set(fixture_ids)
    )


def validate_oracle(
    oracle: object,
    authorization: manifest.SessionAuthorization,
    evidence_spec: evidence.SessionSpec,
    expected_oracle_sha256: str,
) -> bool:
    """Check one exact oracle against all private session and evidence pins.

    Exact and partial search cases must independently pin a nonempty query,
    expected fixture identities from the bound manifest, and the retained
    query state expected after the search.
    """
    if (
        type(oracle) is not LibraryInteractionOracle
        or type(authorization) is not manifest.SessionAuthorization
        or type(evidence_spec) is not evidence.SessionSpec
        or type(expected_oracle_sha256) is not str
        or _DIGEST_RE.fullmatch(expected_oracle_sha256) is None
        or type(oracle.schema_version) is not int
        or oracle.schema_version != LIBRARY_INTERACTION_CONTRACT_VERSION
        or type(oracle.fixture_manifest_version) is not int
        or type(oracle.plan_version) is not int
        or oracle.fixture_manifest_sha256 != authorization.fixture_manifest_sha256
        or oracle.fixture_manifest_sha256 != evidence_spec.fixtures.manifest_sha256
        or oracle.fixture_manifest_version != evidence_spec.fixtures.manifest_version
        or oracle.artifact_sha256 != authorization.apk_sha256
        or oracle.artifact_sha256 != evidence_spec.artifact.artifact_sha256
        or oracle.plan_sha256 != authorization.plan_sha256
        or oracle.plan_sha256 != evidence_spec.plan.plan_sha256
        or oracle.plan_version != evidence_spec.plan.plan_version
        or oracle.acceptance_rules_sha256 != authorization.rules_sha256
        or oracle.acceptance_rules_sha256 != evidence_spec.rules.rules_sha256
        or oracle.acceptance_rules_version != evidence_spec.rules.rules_version
        or type(oracle.fixture_expectations) is not tuple
        or not oracle.fixture_expectations
        or type(oracle.case_expectations) is not tuple
        or len(oracle.case_expectations) != len(LIBRARY_INTERACTION_CASE_IDS)
    ):
        return False
    try:
        ui._fixture_tokens(oracle.fixture_expectations)
        fixture_ids = tuple(item.fixture_id for item in oracle.fixture_expectations)
        case_ids = tuple(item.case_id for item in oracle.case_expectations)
        if case_ids != LIBRARY_INTERACTION_CASE_IDS:
            return False
        for expectation in oracle.case_expectations:
            if (
                type(expectation) is not LibraryCaseExpectation
                or type(expectation.input_value) not in (str, type(None))
                or (
                    type(expectation.input_value) is str
                    and (
                        len(expectation.input_value) > 512
                        or any(
                            ord(character) < 0x20 or ord(character) == 0x7f
                            for character in expectation.input_value
                        )
                    )
                )
                or type(expectation.expected_fixture_ids) is not tuple
                or len(set(expectation.expected_fixture_ids))
                != len(expectation.expected_fixture_ids)
                or any(
                    fixture_id not in fixture_ids
                    for fixture_id in expectation.expected_fixture_ids
                )
                or type(expectation.expected_order_groups) is not tuple
                or any(
                    type(group) is not tuple
                    or not group
                    or any(type(fixture_id) is not str for fixture_id in group)
                    for group in expectation.expected_order_groups
                )
                or type(expectation.expected_selection_identity)
                not in (str, type(None))
                or (
                    expectation.expected_selection_identity is not None
                    and expectation.expected_selection_identity not in fixture_ids
                )
                or type(expectation.expected_selection_state)
                not in (bool, type(None))
                or type(expectation.expected_retained_query)
                not in (str, type(None))
                or (
                    type(expectation.expected_retained_query) is str
                    and (
                        len(expectation.expected_retained_query) > 512
                        or any(
                            ord(character) < 0x20 or ord(character) == 0x7f
                            for character in expectation.expected_retained_query
                        )
                    )
                )
                or type(expectation.expected_detail_facts)
                not in (tuple, type(None))
                or (
                    expectation.expected_detail_facts is not None
                    and (
                        any(type(fact) is not str or not fact for fact in expectation.expected_detail_facts)
                        or len(set(expectation.expected_detail_facts))
                        != len(expectation.expected_detail_facts)
                    )
                )
                or not _valid_searchable_identities(
                    expectation.searchable_identities,
                    oracle.fixture_expectations,
                )
                or (
                    expectation.case_id != "search_empty"
                    and expectation.searchable_identities
                )
                or type(expectation.unsupported_assertions) is not tuple
                or len(set(expectation.unsupported_assertions))
                != len(expectation.unsupported_assertions)
                or any(
                    assertion not in _ALLOWED_UNSUPPORTED_ASSERTIONS
                    for assertion in expectation.unsupported_assertions
                )
                or (
                    expectation.case_id == "search_empty"
                    and not _REQUIRED_UNSUPPORTED_ASSERTIONS[
                        expectation.case_id
                    ].issubset(expectation.unsupported_assertions)
                )
                or (
                    expectation.case_id == "search_empty"
                    and frozenset(expectation.unsupported_assertions)
                    - (
                        _REQUIRED_UNSUPPORTED_ASSERTIONS[expectation.case_id]
                        | {"searchable_projection_completeness"}
                    )
                )
                or (
                    expectation.case_id != "search_empty"
                    and frozenset(expectation.unsupported_assertions)
                    != _REQUIRED_UNSUPPORTED_ASSERTIONS[expectation.case_id]
                )
            ):
                return False
            groups = expectation.expected_order_groups
            if expectation.case_id in _ORDERED_CASES:
                if not groups:
                    return False
                grouped_ids = tuple(fixture_id for group in groups for fixture_id in group)
                if (
                    len(set(grouped_ids)) != len(grouped_ids)
                    or set(grouped_ids) != set(expectation.expected_fixture_ids)
                    or len(grouped_ids) != len(expectation.expected_fixture_ids)
                ):
                    return False
                sort_field = (
                    "display_title"
                    if "title" in expectation.case_id
                    else "platform_label"
                )
                descending = expectation.case_id.endswith("descending")
                previous = None
                by_id = {item.fixture_id: item for item in oracle.fixture_expectations}
                for group in groups:
                    values = {
                        getattr(by_id[fixture_id], sort_field).casefold()
                        for fixture_id in group
                    }
                    if len(values) != 1:
                        return False
                    value = next(iter(values))
                    if previous is not None and (
                        value > previous if descending else value < previous
                    ):
                        return False
                    previous = value
            elif groups:
                return False
        cases_by_id = {item.case_id: item for item in oracle.case_expectations}
        membership = oracle.case_expectations[0]
        if membership.expected_fixture_ids != fixture_ids:
            return False
        for case_id in ("search_exact", "search_partial"):
            search = cases_by_id[case_id]
            if (
                type(search.input_value) is not str
                or not search.input_value.strip()
                or not search.expected_fixture_ids
                or any(
                    fixture_id not in fixture_ids
                    for fixture_id in search.expected_fixture_ids
                )
                or search.expected_retained_query != search.input_value
            ):
                return False
        if (
            cases_by_id["search_exact"].input_value
            == cases_by_id["search_partial"].input_value
        ):
            return False
        no_match = cases_by_id["search_empty"]
        query_terms = (
            re.findall(r"[a-z0-9]+", no_match.input_value.casefold())
            if type(no_match.input_value) is str else []
        )
        searchable_projection_complete = (
            len(no_match.searchable_identities) == len(fixture_ids)
            and all(
                identity.display_titles is not None
                and identity.alternate_titles is not None
                and identity.active_fallback_titles is not None
                for identity in no_match.searchable_identities
            )
        )
        searchable_labels = tuple(
            title.casefold()
            for identity in no_match.searchable_identities
            for titles in (
                identity.display_titles,
                identity.alternate_titles,
                identity.active_fallback_titles,
            )
            if titles is not None
            for title in titles
        ) + tuple(
            item.display_title.casefold()
            for item in oracle.fixture_expectations
        )
        if (
            type(no_match.input_value) is not str
            or not no_match.input_value
            or not query_terms
            or no_match.expected_fixture_ids
            or no_match.expected_retained_query != no_match.input_value
            or (
                "searchable_projection_completeness"
                in no_match.unsupported_assertions
            ) == searchable_projection_complete
            or any(
                term in label
                for term in query_terms
                for label in searchable_labels
            )
        ):
            return False
        clear = cases_by_id["search_clear"]
        if (
            clear.input_value != ""
            or clear.expected_retained_query != ""
            or clear.expected_fixture_ids != fixture_ids
        ):
            return False
        selection = cases_by_id["selection"]
        if (
            selection.expected_selection_identity
            not in selection.expected_fixture_ids
            or selection.expected_selection_identity
            not in membership.expected_fixture_ids
            or selection.expected_selection_identity != fixture_ids[0]
            or selection.expected_selection_state is not True
            or not {"selection_identity", "selection_state"}.issubset(
                selection.unsupported_assertions
            )
        ):
            return False
        retained_selection = cases_by_id["search_after_selection"]
        if (
            retained_selection.expected_retained_query
            != retained_selection.input_value
            or retained_selection.expected_selection_identity != fixture_ids[0]
            or retained_selection.expected_selection_state is not True
            or not {"retained_query_state", "selection_identity", "selection_state"}
            .issubset(retained_selection.unsupported_assertions)
        ):
            return False
        for case_id in ("detail_open", "detail_observation"):
            detail = cases_by_id[case_id]
            detail_fixture = (
                next(
                    (
                        item for item in oracle.fixture_expectations
                        if detail.expected_detail_facts
                        and item.fixture_id == detail.expected_detail_facts[0]
                    ),
                    None,
                )
            )
            if (
                type(detail.expected_detail_facts) is not tuple
                or not detail.expected_detail_facts
                or detail_fixture is None
                or detail.expected_detail_facts != (
                    detail_fixture.fixture_id,
                    detail_fixture.display_title,
                    detail_fixture.platform_label,
                )
                or "stable_detail_facts" not in detail.unsupported_assertions
            ):
                return False
        return oracle.oracle_sha256 == expected_oracle_sha256
    except (AttributeError, TypeError, ValueError, ui.UIBlocked):
        return False
