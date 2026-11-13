"""Synthetic tests for the private Issue #28 accessibility surface parser."""

from __future__ import annotations

from dataclasses import replace
import unittest
from unittest.mock import patch
from xml.sax.saxutils import escape

from scripts.android_qualification import _job_lifecycle_oracle as lifecycle_oracle
from scripts.android_qualification._job_lifecycle_contract import (
    JobIdentityObservation,
    JobLifecycleSurface,
    JobsSurfaceObservation,
    LibrarySurfaceObservation,
    RecoveryState,
    RootExclusionReason,
    ScanRootObservation,
    ScanRunObservation,
    ScanRunRelation,
)
from scripts.android_qualification.physical import _job_lifecycle_ui as lifecycle_ui
from scripts.android_qualification.physical import ui


QUALIFICATION_PACKAGE = ui.QUALIFICATION_PACKAGE


def xml(*labels: str, package: str = QUALIFICATION_PACKAGE) -> str:
    """Build one bounded accessibility hierarchy from exact visible labels."""
    nodes = "".join(
        f'<node package="{package}" text="{escape(label, {chr(34): "&quot;"})}" '
        f'content-desc="" enabled="true" clickable="true" selected="false" '
        f'visible-to-user="true" bounds="[10,{index * 40 + 10}][210,{index * 40 + 40}]" />'
        for index, label in enumerate(labels)
    )
    return '<hierarchy rotation="0">' + nodes + "</hierarchy>"


def node_xml(
    *,
    text: str,
    content_desc: str = "",
    enabled: bool = True,
    clickable: bool = True,
    selected: bool = False,
    index: int = 0,
    resource_id: str | None = None,
) -> str:
    """Build one accessibility node with explicit control-state evidence."""
    text_value = escape(text, {chr(34): "&quot;"}).replace("\n", "&#10;")
    description_value = escape(content_desc, {chr(34): "&quot;"}).replace(
        "\n", "&#10;"
    )
    resource_value = ""
    if resource_id is not None:
        resource_value = (
            'resource-id="' + escape(resource_id, {chr(34): "&quot;"}) + '" '
        )
    return (
        f'<node package="{QUALIFICATION_PACKAGE}" {resource_value}'
        f'text="{text_value}" content-desc="{description_value}" '
        f'enabled="{str(enabled).lower()}" '
        f'clickable="{str(clickable).lower()}" '
        f'selected="{str(selected).lower()}" visible-to-user="true" '
        f'bounds="[10,{index * 40 + 10}][210,{index * 40 + 40}]" />'
    )


def wrap_nodes(*nodes: str) -> str:
    return '<hierarchy rotation="0">' + "".join(nodes) + "</hierarchy>"


def semantic_node_xml(
    *,
    resource_id: str,
    text: str = "",
    package: str = QUALIFICATION_PACKAGE,
    children: str = "",
    enabled: bool = False,
    clickable: bool = False,
) -> str:
    resource_value = escape(resource_id, {chr(34): "&quot;"})
    text_value = escape(text, {chr(34): "&quot;"}).replace("\n", "&#10;")
    return (
        f'<node package="{package}" resource-id="{resource_value}" '
        f'text="{text_value}" content-desc="" '
        f'enabled="{str(enabled).lower()}" clickable="{str(clickable).lower()}" '
        f'selected="false" visible-to-user="true" bounds="[0,0][20,20]">'
        f"{children}</node>"
    )


def library_page_identifier(
    *,
    page: int,
    expected_rows: int,
    has_next: bool,
    observation: str = "obs-1",
    profile: str = "AllActiveMembershipBaseline",
    status: str = "complete",
    page_size: int = 50,
) -> str:
    return (
        "argus.library.page.v1;"
        f"observation={observation};profile={profile};page={page};"
        f"first={str(page == 1).lower()};"
        f"continuation={str(page > 1).lower()};status={status};"
        f"hasNext={str(has_next).lower()};final={str(not has_next).lower()};"
        f"pageSize={page_size};expectedRows={expected_rows}"
    )


def library_row_identifier(
    *, page: int, row: int, game_id: str, observation: str = "obs-1"
) -> str:
    return (
        "argus.library.row.v1;"
        f"observation={observation};page={page};row={row};gameId={game_id}"
    )


def library_hierarchy(
    pages: tuple[tuple[int, bool, tuple[str, ...]], ...],
    *,
    observation: str = "obs-1",
    include_page_boundaries: bool = True,
    wrap_first_row_with_page_boundary: bool = True,
    package: str = QUALIFICATION_PACKAGE,
    expected_row_counts: dict[int, int] | None = None,
) -> str:
    navigation = "".join(
        node_xml(text=label, index=index)
        for index, label in enumerate(
            ("Search Library", "Refresh Library", "Library", "Jobs", "Sources")
        )
    )
    page_nodes = []
    for page, has_next, game_ids in pages:
        rows = tuple(
            semantic_node_xml(
                resource_id=library_row_identifier(
                    page=page, row=row, game_id=game_id, observation=observation
                ),
                package=package,
            )
            for row, game_id in enumerate(game_ids, start=1)
        )
        first_row = rows[:1] if wrap_first_row_with_page_boundary else ()
        sibling_rows = rows[len(first_row) :]
        boundary = semantic_node_xml(
            resource_id=library_page_identifier(
                page=page,
                expected_rows=(
                    len(game_ids)
                    if expected_row_counts is None
                    else expected_row_counts[page]
                ),
                has_next=has_next,
                observation=observation,
            ),
            children="".join(first_row),
            package=package,
        )
        if include_page_boundaries:
            page_nodes.append(boundary)
        page_nodes.extend(sibling_rows if include_page_boundaries else rows)
    return wrap_nodes(navigation, *page_nodes)


def library_hierarchy_with_nodes(*page_nodes: str) -> str:
    """Build a Library capture with caller-controlled semantic node order."""
    navigation = "".join(
        node_xml(text=label, index=index)
        for index, label in enumerate(
            ("Search Library", "Refresh Library", "Library", "Jobs", "Sources")
        )
    )
    return wrap_nodes(navigation, *page_nodes)


def refresh_detail_hierarchy(
    *,
    parent: str = "a" * 32,
    scan: str = "b" * 32,
    admitted_root: str = "c" * 32,
    excluded_root: str = "d" * 32,
    source: str = "e" * 32,
    successor: str = "f" * 32,
    coverage: str = "Folder coverage: complete.",
    scan_status: str | None = None,
    parent_status: str | None = "Running",
) -> str:
    scan_node = semantic_node_xml(
        resource_id=f"scan-run:{scan}",
        children=(
            (node_xml(text=scan_status) if scan_status is not None else "")
            + semantic_node_xml(
                resource_id=f"library-root:{admitted_root}", text="Complete"
            )
        ),
    )
    exclusion_node = semantic_node_xml(
        resource_id=f"library-root:{excluded_root}",
        text="Library folder",
        children=node_xml(text="Already being scanned"),
    )
    retry_source = semantic_node_xml(
        resource_id=f"job-run:{source}", text="Retried from"
    )
    retry_successor = semantic_node_xml(
        resource_id=f"job-run:{successor}", text="Retried as"
    )
    detail = semantic_node_xml(
        resource_id=f"job-run:{parent}",
        text=(
            "Library Refresh\n"
            + (f"{parent_status}\n" if parent_status is not None else "")
            + "Phase: scanning\nCompleted units: 1\n"
            f"Total units: 2\n{coverage}"
        ),
        children=(
            scan_node
            + exclusion_node
            + retry_source
            + retry_successor
            + node_xml(text="Retry")
        ),
    )
    return wrap_nodes(detail)


def identity_for_refresh(
    *,
    parent: str = "a" * 32,
    scan: str = "b" * 32,
    admitted_root: str = "c" * 32,
    excluded_root: str = "d" * 32,
    scope: tuple[str, ...] | None = None,
) -> JobIdentityObservation:
    requested = scope or (admitted_root, excluded_root)
    admitted = (admitted_root,) if admitted_root in requested else ()
    excluded = (excluded_root,) if excluded_root in requested else ()
    return JobIdentityObservation(
        parent_run_ref=parent,
        scan_run_relations=(
            ScanRunRelation(
                scan_run_ref=scan,
                parent_run_ref=parent,
                root_ref=admitted_root,
            ),
        ),
        requested_root_refs=requested,
        admitted_root_refs=admitted,
        excluded_root_refs=excluded,
        frozen_scope_ref="frozen-scope",
        observer_ref="independent-identity-observer",
        parent_state=RecoveryState.ACTIVE,
    )


def merged_xml(*groups: tuple[str, ...], package: str = QUALIFICATION_PACKAGE) -> str:
    """Build one hierarchy where each group is a merged accessibility node."""
    nodes = []
    for index, group in enumerate(groups):
        text = escape("\n".join(group), {chr(34): "&quot;"})
        text = text.replace("\n", "&#10;")
        nodes.append(
            f'<node package="{package}" text="{text}" content-desc="" enabled="true" '
            f'clickable="true" selected="false" visible-to-user="true" '
            f'bounds="[10,{index * 40 + 10}][210,{index * 40 + 40}]" />'
        )
    return '<hierarchy rotation="0">' + "".join(nodes) + "</hierarchy>"


def jobs_surface_xml(
    *groups: tuple[str, ...], package: str = QUALIFICATION_PACKAGE
) -> str:
    """Build distinct selected navigation, page-title, and Jobs content nodes."""
    selected = (
        f'<node package="{package}" text="Jobs" enabled="true" '
        'clickable="true" selected="true" visible-to-user="true" '
        'bounds="[10,10][210,40]" />'
    )
    heading = (
        f'<node package="{package}" text="Jobs" enabled="true" '
        'clickable="false" selected="false" visible-to-user="true" '
        'bounds="[10,50][210,80]" />'
    )
    content = merged_xml(*groups, package=package)
    return content.replace(
        '<hierarchy rotation="0">',
        '<hierarchy rotation="0">' + selected + heading,
        1,
    )


class SurfaceParsingTests(unittest.TestCase):
    def test_library_surface_requires_fixed_controls(self) -> None:
        observed = lifecycle_ui.parse_job_lifecycle_surface(
            xml("Search Library", "Refresh Library", "Library", "Jobs", "Sources")
        )
        self.assertIs(observed.surface, JobLifecycleSurface.LIBRARY)
        self.assertTrue(observed.library_navigation_present)
        self.assertTrue(observed.jobs_navigation_present)
        self.assertTrue(observed.sources_navigation_present)
        self.assertTrue(observed.refresh_control_present)
        self.assertIsNone(observed.progress)

    def test_sources_and_retry_survive_shared_allowlist_removal(self):
        with patch.dict(ui._LABELS):
            ui._LABELS.pop("Sources", None)
            ui._LABELS.pop("Retry", None)
            library = lifecycle_ui.parse_job_lifecycle_surface(
                xml(
                    "Search Library", "Refresh Library", "Library", "Jobs", "Sources"
                )
            )
            refresh = lifecycle_ui.parse_job_lifecycle_surface(
                wrap_nodes(
                    node_xml(text="Library Refresh", index=0),
                    node_xml(text="Abandoned", index=1),
                    node_xml(text="Phase: finalizing", index=2),
                    node_xml(text="Retry", index=3),
                )
            )
        self.assertTrue(library.sources_navigation_present)
        self.assertEqual(refresh.retry_control_count, 1)

    def test_library_resource_ids_expose_complete_page_and_row_facts(self):
        observed = lifecycle_ui.parse_job_lifecycle_surface(
            library_hierarchy(((1, False, ("a" * 32, "b" * 32)),))
        )
        pages = observed.library_pages
        rows = observed.library_rows
        self.assertEqual(len(pages), 1)
        self.assertEqual(len(rows), 2)
        self.assertEqual(pages[0].observation_id, "obs-1")
        self.assertEqual(pages[0].query_profile, "AllActiveMembershipBaseline")
        self.assertEqual(pages[0].page_ordinal, 1)
        self.assertEqual(pages[0].expected_row_count, 2)
        self.assertEqual(tuple(row.game_id for row in rows), ("a" * 32, "b" * 32))
        self.assertEqual(
            tuple(row.boundary_page_ordinal for row in rows), (1, None)
        )

    def test_complete_single_capture_builds_existing_library_observation(self):
        screen = lifecycle_ui.parse_job_lifecycle_surface(
            library_hierarchy(((1, False, ("a" * 32, "b" * 32)),))
        )
        observed = lifecycle_ui.adapt_library_surface_observation(
            screen, refresh_active=False, observer_ref="authorized-observer"
        )
        self.assertIs(type(observed), LibrarySurfaceObservation)
        self.assertEqual(observed.membership_count, 2)
        self.assertEqual(observed.membership_ids, ("a" * 32, "b" * 32))
        self.assertFalse(observed.next_page_available)
        self.assertIsNone(observed.identity_continuity)
        self.assertEqual(
            tuple(row.boundary_page_ordinal for row in screen.library_rows),
            (1, None),
        )

    def test_complete_multi_page_sibling_rows_match_lifecycle_oracle(self):
        screen = lifecycle_ui.parse_job_lifecycle_surface(
            library_hierarchy(
                (
                    (1, True, ("a" * 32, "b" * 32)),
                    (2, False, ("c" * 32, "d" * 32)),
                )
            )
        )
        self.assertEqual(
            tuple(row.boundary_page_ordinal for row in screen.library_rows),
            (1, None, 2, None),
        )
        observed = lifecycle_ui.adapt_library_surface_observation(
            screen, refresh_active=False, observer_ref="authorized-observer"
        )
        result = lifecycle_oracle.library_recovery_persistence(
            observed.membership_ids, observed
        )
        self.assertEqual(
            observed.membership_ids,
            ("a" * 32, "b" * 32, "c" * 32, "d" * 32),
        )
        self.assertEqual(result.outcome.name, "PASSED")

    def test_empty_terminal_first_page_remains_complete_membership(self):
        screen = lifecycle_ui.parse_job_lifecycle_surface(
            library_hierarchy(((1, False, ()),))
        )
        observed = lifecycle_ui.adapt_library_surface_observation(
            screen, refresh_active=False, observer_ref="authorized-observer"
        )
        self.assertEqual(observed.membership_count, 0)
        self.assertEqual(observed.membership_ids, ())

    def test_nonterminal_library_page_cannot_be_empty(self):
        screen = lifecycle_ui.parse_job_lifecycle_surface(
            library_hierarchy(
                ((1, True, ()), (2, False, ("b" * 32,)))
            )
        )
        with self.assertRaisesRegex(
            ui.UIBlocked, "A nonterminal Library page cannot be empty"
        ):
            lifecycle_ui.adapt_library_surface_observation(
                screen, refresh_active=False, observer_ref="authorized-observer"
            )

    def test_empty_terminal_continuation_page_can_complete_membership(self):
        screen = lifecycle_ui.parse_job_lifecycle_surface(
            library_hierarchy(
                ((1, True, ("a" * 32,)), (2, False, ()))
            )
        )
        observed = lifecycle_ui.adapt_library_surface_observation(
            screen, refresh_active=False, observer_ref="authorized-observer"
        )
        self.assertEqual(observed.membership_count, 1)
        self.assertEqual(observed.membership_ids, ("a" * 32,))

    def test_multirow_page_before_empty_terminal_continuation_is_complete(self):
        screen = lifecycle_ui.parse_job_lifecycle_surface(
            library_hierarchy(
                ((1, True, ("a" * 32, "b" * 32)), (2, False, ()))
            )
        )
        observed = lifecycle_ui.adapt_library_surface_observation(
            screen, refresh_active=False, observer_ref="authorized-observer"
        )
        self.assertEqual(observed.membership_count, 2)
        self.assertEqual(observed.membership_ids, ("a" * 32, "b" * 32))

    def test_empty_terminal_boundary_cannot_interrupt_prior_page_siblings(self):
        first_row = semantic_node_xml(
            resource_id=library_row_identifier(page=1, row=1, game_id="a" * 32)
        )
        first_page = semantic_node_xml(
            resource_id=library_page_identifier(
                page=1, expected_rows=2, has_next=True
            ),
            children=first_row,
        )
        empty_terminal_page = semantic_node_xml(
            resource_id=library_page_identifier(
                page=2, expected_rows=0, has_next=False
            )
        )
        prior_page_sibling = semantic_node_xml(
            resource_id=library_row_identifier(page=1, row=2, game_id="b" * 32)
        )
        screen = lifecycle_ui.parse_job_lifecycle_surface(
            library_hierarchy_with_nodes(
                first_page, empty_terminal_page, prior_page_sibling
            )
        )
        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.adapt_library_surface_observation(
                screen, refresh_active=False, observer_ref="authorized-observer"
            )

    def test_empty_terminal_boundary_cannot_be_followed_by_a_sibling_row(self):
        first_row = semantic_node_xml(
            resource_id=library_row_identifier(page=1, row=1, game_id="a" * 32)
        )
        first_page = semantic_node_xml(
            resource_id=library_page_identifier(
                page=1, expected_rows=1, has_next=True
            ),
            children=first_row,
        )
        empty_terminal_page = semantic_node_xml(
            resource_id=library_page_identifier(
                page=2, expected_rows=0, has_next=False
            )
        )
        unexpected_sibling = semantic_node_xml(
            resource_id=library_row_identifier(page=2, row=2, game_id="b" * 32)
        )
        screen = lifecycle_ui.parse_job_lifecycle_surface(
            library_hierarchy_with_nodes(
                first_page, empty_terminal_page, unexpected_sibling
            )
        )
        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.adapt_library_surface_observation(
                screen, refresh_active=False, observer_ref="authorized-observer"
            )

    def test_empty_nonterminal_page_requires_an_exact_integer_count(self):
        screen = lifecycle_ui.parse_job_lifecycle_surface(
            library_hierarchy(
                ((1, True, ()), (2, False, ("b" * 32,)))
            )
        )
        malformed = replace(
            screen,
            library_pages=(
                replace(screen.library_pages[0], expected_row_count="0"),
                screen.library_pages[1],
            ),
        )
        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.adapt_library_surface_observation(
                malformed,
                refresh_active=False,
                observer_ref="authorized-observer",
            )

    def test_virtualized_missing_rows_block_even_on_terminal_page(self):
        screen = lifecycle_ui.parse_job_lifecycle_surface(
            library_hierarchy(
                ((1, False, ("a" * 32,)),), expected_row_counts={1: 2}
            )
        )
        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.adapt_library_surface_observation(
                screen, refresh_active=False, observer_ref="authorized-observer"
            )

    def test_missing_offscreen_page_boundary_blocks_membership(self):
        screen = lifecycle_ui.parse_job_lifecycle_surface(
            library_hierarchy(
                ((1, True, ("a" * 32,)), (2, False, ("b" * 32,))),
                include_page_boundaries=False,
            )
        )
        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.adapt_library_surface_observation(
                screen, refresh_active=False, observer_ref="authorized-observer"
            )

    def test_process_restart_reusing_obs_one_cannot_join_capture_pages(self):
        before_restart = lifecycle_ui.parse_job_lifecycle_surface(
            library_hierarchy(((1, True, ("a" * 32,)),))
        )
        after_restart = lifecycle_ui.parse_job_lifecycle_surface(
            library_hierarchy(((2, False, ("b" * 32,)),))
        )
        combined = replace(
            before_restart,
            library_pages=before_restart.library_pages + after_restart.library_pages,
            library_rows=before_restart.library_rows + after_restart.library_rows,
        )
        self.assertEqual(
            tuple(page.observation_id for page in combined.library_pages),
            ("obs-1", "obs-1"),
        )
        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.adapt_library_surface_observation(
                combined,
                refresh_active=False,
                observer_ref="same-task-and-observer",
            )

    def test_duplicate_library_page_boundary_cannot_establish_membership(self):
        capture = library_hierarchy(((1, False, ("a" * 32,)),))
        duplicate_boundary = semantic_node_xml(
            resource_id=library_page_identifier(
                page=1,
                expected_rows=1,
                has_next=False,
                observation="obs-1",
            ),
            package=QUALIFICATION_PACKAGE,
        )
        screen = lifecycle_ui.parse_job_lifecycle_surface(
            capture.replace("</hierarchy>", duplicate_boundary + "</hierarchy>")
        )
        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.adapt_library_surface_observation(
                screen, refresh_active=False, observer_ref="authorized-observer"
            )

    def test_first_row_must_be_nested_under_its_page_boundary(self):
        screen = lifecycle_ui.parse_job_lifecycle_surface(
            library_hierarchy(
                ((1, False, ("a" * 32, "b" * 32)),),
                wrap_first_row_with_page_boundary=False,
            )
        )
        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.adapt_library_surface_observation(
                screen, refresh_active=False, observer_ref="authorized-observer"
            )

    def test_library_sibling_rows_must_keep_their_page_and_traversal_order(self):
        screen = lifecycle_ui.parse_job_lifecycle_surface(
            library_hierarchy(((1, False, ("a" * 32, "b" * 32)),))
        )
        first, sibling = screen.library_rows
        other_capture = lifecycle_ui.parse_job_lifecycle_surface(
            library_hierarchy(((1, False, ("a" * 32, "b" * 32)),))
        )
        cases = {
            "missing sibling": replace(screen, library_rows=(first,)),
            "reordered sibling": replace(
                screen, library_rows=(sibling, first)
            ),
            "duplicated sibling": replace(
                screen, library_rows=(first, sibling, sibling)
            ),
            "sibling attributed to another page": replace(
                screen,
                library_rows=(first, replace(sibling, page_ordinal=2)),
            ),
            "row from another observation": replace(
                screen,
                library_rows=(first, replace(sibling, observation_id="obs-2")),
            ),
            "row from another parser capture": replace(
                screen, library_rows=(first, other_capture.library_rows[1])
            ),
        }
        for name, malformed in cases.items():
            with self.subTest(case=name), self.assertRaises(ui.UIBlocked):
                lifecycle_ui.adapt_library_surface_observation(
                    malformed,
                    refresh_active=False,
                    observer_ref="authorized-observer",
                )

    def test_duplicate_game_ids_cannot_complete_membership(self):
        screen = lifecycle_ui.parse_job_lifecycle_surface(
            library_hierarchy(((1, False, ("a" * 32, "a" * 32)),))
        )
        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.adapt_library_surface_observation(
                screen, refresh_active=False, observer_ref="authorized-observer"
            )

    def test_library_ordinals_must_be_exact_integers(self):
        screen = lifecycle_ui.parse_job_lifecycle_surface(
            library_hierarchy(((1, False, ("a" * 32,)),))
        )
        page = screen.library_pages[0]
        row = screen.library_rows[0]
        malformed_observations = (
            replace(screen, library_pages=(replace(page, page_ordinal=True),)),
            replace(screen, library_rows=(replace(row, page_ordinal=True),)),
            replace(screen, library_rows=(replace(row, row_ordinal=True),)),
            replace(
                screen,
                library_rows=(replace(row, boundary_page_ordinal=True),),
            ),
        )
        for malformed in malformed_observations:
            with self.subTest(observation=malformed.library_pages):
                with self.assertRaises(ui.UIBlocked):
                    lifecycle_ui.adapt_library_surface_observation(
                        malformed,
                        refresh_active=False,
                        observer_ref="authorized-observer",
                    )

    def test_library_adapter_rejects_nonbaseline_and_inconsistent_page_chains(self):
        ordinary_profile = library_hierarchy(((1, False, ("a" * 32,)),)).replace(
            "AllActiveMembershipBaseline", "OrdinaryUserQuery"
        )
        gapped_pages = library_hierarchy(
            ((1, True, ("a" * 32,)), (3, False, ("c" * 32,)))
        )
        for capture in (ordinary_profile, gapped_pages):
            with self.subTest(capture=capture[:120]):
                screen = lifecycle_ui.parse_job_lifecycle_surface(capture)
                with self.assertRaises(ui.UIBlocked):
                    lifecycle_ui.adapt_library_surface_observation(
                        screen,
                        refresh_active=False,
                        observer_ref="authorized-observer",
                    )

    def test_library_rows_require_their_page_boundary_and_one_based_identity(self):
        no_boundary = library_hierarchy(
            ((1, False, ("a" * 32,)),), include_page_boundaries=False
        )
        zero_based_row = library_hierarchy(((1, False, ("a" * 32,)),)).replace(
            ";row=1;", ";row=0;"
        )
        for capture in (no_boundary, zero_based_row):
            with self.subTest(capture=capture[:100]):
                with self.assertRaises(ui.UIBlocked):
                    screen = lifecycle_ui.parse_job_lifecycle_surface(capture)
                    lifecycle_ui.adapt_library_surface_observation(
                        screen,
                        refresh_active=False,
                        observer_ref="authorized-observer",
                    )

    def test_jobs_rows_keep_jobrun_identity_but_not_complete_history(self):
        base = jobs_surface_xml(("Active",), ("Recent",))
        row = semantic_node_xml(
            resource_id=f"job-run:{'a' * 32}",
            text="Library Refresh\nRunning",
        )
        screen = lifecycle_ui.parse_job_lifecycle_surface(
            base.replace("</hierarchy>", row + "</hierarchy>")
        )
        self.assertEqual(screen.surface, JobLifecycleSurface.JOBS)
        self.assertEqual(len(screen.job_run_rows), 1)
        self.assertEqual(screen.job_run_rows[0].job_run_ref, "a" * 32)
        self.assertEqual(screen.job_run_rows[0].operation_label, "Library Refresh")
        self.assertEqual(screen.job_run_rows[0].lifecycle_status, "Running")
        observed = lifecycle_ui.adapt_jobs_surface_observation(
            screen, observer_ref="authorized-observer"
        )
        self.assertIs(type(observed), JobsSurfaceObservation)
        self.assertEqual(observed.parent_run_ref, "a" * 32)
        self.assertFalse(observed.history_complete)
        self.assertFalse(observed.established())

    def test_invalid_semantic_jobs_rows_cannot_fall_back_to_visible_labels(self):
        visible_rows = jobs_surface_xml(
            ("Active",), ("Library Refresh", "Running")
        )
        missing_row_evidence = visible_rows.replace(
            "</hierarchy>",
            semantic_node_xml(resource_id=f"job-run:{'a' * 32}")
            + "</hierarchy>",
        )
        duplicate_identity = jobs_surface_xml(("Active",)).replace(
            "</hierarchy>",
            semantic_node_xml(
                resource_id=f"job-run:{'a' * 32}",
                text="Library Refresh\nRunning",
            )
            + semantic_node_xml(
                resource_id=f"job-run:{'a' * 32}",
                text="Library Refresh\nCompleted",
            )
            + "</hierarchy>",
        )
        label_only_row = jobs_surface_xml(
            ("Active",), ("Library Refresh", "Running")
        )

        for capture in (missing_row_evidence, duplicate_identity, label_only_row):
            with self.subTest(capture=capture[-220:]), self.assertRaises(
                ui.UIBlocked
            ):
                lifecycle_ui.parse_job_lifecycle_surface(capture)

    def test_jobs_adapter_blocks_duplicate_jobrun_row_identities(self):
        base = jobs_surface_xml(("Active",), ("Recent",))
        row = semantic_node_xml(
            resource_id=f"job-run:{'a' * 32}",
            text="Library Refresh\nCompleted",
        )
        screen = lifecycle_ui.parse_job_lifecycle_surface(
            base.replace("</hierarchy>", row + "</hierarchy>")
        )
        duplicated = replace(
            screen,
            job_run_rows=screen.job_run_rows + screen.job_run_rows,
        )

        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.adapt_jobs_surface_observation(
                duplicated,
                observer_ref="authorized-observer",
            )

    def test_jobs_adapter_blocks_unrepresented_cancellation_intent(self):
        base = jobs_surface_xml(("Active",), ("Recent",))
        row = semantic_node_xml(
            resource_id=f"job-run:{'a' * 32}",
            text="Library Refresh\nRunning\nCancelling…",
        )
        screen = lifecycle_ui.parse_job_lifecycle_surface(
            base.replace("</hierarchy>", row + "</hierarchy>")
        )
        self.assertTrue(screen.cancellation_requested)
        self.assertEqual(screen.job_run_rows[0].lifecycle_status, "Running")

        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.adapt_jobs_surface_observation(
                screen,
                observer_ref="authorized-observer",
            )

    def test_refresh_detail_maps_parent_child_root_and_retry_ids(self):
        screen = lifecycle_ui.parse_job_lifecycle_surface(refresh_detail_hierarchy())
        identity = identity_for_refresh()
        self.assertEqual(screen.parent_run_ref, identity.parent_run_ref)
        self.assertEqual(screen.scan_run_relations, identity.scan_run_relations)
        self.assertEqual(screen.root_refs, ("c" * 32, "d" * 32))
        self.assertEqual(screen.excluded_root_refs, ("d" * 32,))
        self.assertEqual(
            screen.root_exclusions[0].reason,
            RootExclusionReason.ALREADY_SCANNING,
        )
        self.assertTrue(screen.root_outcome_coverage_complete)
        self.assertEqual(screen.retry_source_run_ref, "e" * 32)
        self.assertEqual(screen.retry_successor_run_ref, "f" * 32)

        detail = lifecycle_ui.adapt_refresh_detail_observation(
            screen,
            identity=identity,
            observer_ref="authorized-observer",
        )
        self.assertEqual(detail.parent_run_ref, "a" * 32)
        self.assertEqual(detail.retry_source_run_ref, "e" * 32)
        self.assertEqual(detail.retry_successor_run_ref, "f" * 32)
        self.assertTrue(detail.established())

        scan = lifecycle_ui.adapt_scan_run_observation(
            screen,
            identity.scan_run_relations[0],
            identity=identity,
            observer_ref="authorized-observer",
        )
        self.assertIs(type(scan), ScanRunObservation)
        self.assertEqual(scan.parent_run_ref, "a" * 32)
        self.assertEqual(scan.scan_run_ref, "b" * 32)
        self.assertEqual(scan.root_ref, "c" * 32)
        self.assertEqual(scan.scan_state, "complete")
        self.assertTrue(scan.established())

    def test_refresh_detail_blocks_duplicate_parent_and_child_status_evidence(self):
        screen = lifecycle_ui.parse_job_lifecycle_surface(
            refresh_detail_hierarchy(scan_status="Running")
        )

        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.adapt_refresh_detail_observation(
                screen,
                identity=identity_for_refresh(),
                observer_ref="authorized-observer",
            )
        self.assertIsNone(screen.lifecycle_status)
        parent_rows = tuple(
            row for row in screen.job_run_rows
            if row.job_run_ref == screen.parent_run_ref
        )
        self.assertEqual(len(parent_rows), 1)
        self.assertEqual(parent_rows[0].lifecycle_status, "Running")

    def test_refresh_detail_does_not_attribute_child_only_status_to_parent(self):
        screen = lifecycle_ui.parse_job_lifecycle_surface(
            refresh_detail_hierarchy(parent_status=None, scan_status="Completed")
        )
        parent_rows = tuple(
            row for row in screen.job_run_rows
            if row.job_run_ref == screen.parent_run_ref
        )

        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.adapt_refresh_detail_observation(
                screen,
                identity=identity_for_refresh(),
                observer_ref="authorized-observer",
            )
        self.assertEqual(screen.lifecycle_status, "Completed")
        self.assertEqual(len(parent_rows), 1)
        self.assertIsNone(parent_rows[0].lifecycle_status)

    def test_refresh_detail_blocks_malformed_status_values(self):
        screen = lifecycle_ui.parse_job_lifecycle_surface(refresh_detail_hierarchy())
        parent_rows = tuple(
            replace(row, lifecycle_status=[])
            if row.job_run_ref == screen.parent_run_ref
            else row
            for row in screen.job_run_rows
        )
        malformed = replace(
            screen,
            lifecycle_status=[],
            job_run_rows=parent_rows,
        )

        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.adapt_refresh_detail_observation(
                malformed,
                identity=identity_for_refresh(),
                observer_ref="authorized-observer",
            )

    def test_refresh_detail_blocks_unhashable_root_references(self):
        screen = lifecycle_ui.parse_job_lifecycle_surface(refresh_detail_hierarchy())
        malformed = replace(screen, root_refs=([],))

        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.adapt_refresh_detail_observation(
                malformed,
                identity=identity_for_refresh(),
                observer_ref="authorized-observer",
            )

    def test_scan_run_adapter_blocks_malformed_status_values(self):
        screen = lifecycle_ui.parse_job_lifecycle_surface(refresh_detail_hierarchy())
        scan_screen = replace(
            screen.scan_run_screen_observations[0], lifecycle_status=[]
        )
        malformed = replace(screen, scan_run_screen_observations=(scan_screen,))
        identity = identity_for_refresh()

        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.adapt_scan_run_observation(
                malformed,
                identity.scan_run_relations[0],
                identity=identity,
                observer_ref="authorized-observer",
            )

    def test_retry_labels_without_resource_ids_do_not_infer_run_identity(self):
        capture = refresh_detail_hierarchy()
        capture = capture.replace(f'resource-id="job-run:{"e" * 32}" ', "")
        capture = capture.replace(f'resource-id="job-run:{"f" * 32}" ', "")
        screen = lifecycle_ui.parse_job_lifecycle_surface(capture)
        self.assertIsNone(screen.retry_source_run_ref)
        self.assertIsNone(screen.retry_successor_run_ref)

    def test_retry_labels_on_intermediate_nodes_do_not_bind_nested_run_ids(self):
        source = "e" * 32
        successor = "f" * 32

        def nested_retry_link(label: str, outer_ref: str, target_ref: str) -> str:
            target = semantic_node_xml(resource_id=f"job-run:{target_ref}")
            label_container = semantic_node_xml(
                resource_id="", text=label, children=target
            )
            return semantic_node_xml(
                resource_id=f"job-run:{outer_ref}", children=label_container
            )

        capture = refresh_detail_hierarchy()
        capture = capture.replace(
            semantic_node_xml(resource_id=f"job-run:{source}", text="Retried from"),
            nested_retry_link("Retried from", "1" * 32, source),
        )
        capture = capture.replace(
            semantic_node_xml(resource_id=f"job-run:{successor}", text="Retried as"),
            nested_retry_link("Retried as", "2" * 32, successor),
        )

        screen = lifecycle_ui.parse_job_lifecycle_surface(capture)

        self.assertIsNone(screen.retry_source_run_ref)
        self.assertIsNone(screen.retry_successor_run_ref)

    def test_refresh_scope_and_production_historical_coverage_must_be_complete(self):
        identity = identity_for_refresh()
        historical = lifecycle_ui.parse_job_lifecycle_surface(
            refresh_detail_hierarchy(
                coverage="Some historical folder outcomes are unavailable."
            )
        )
        self.assertFalse(historical.root_outcome_coverage_complete)
        complete_but_wrong_scope = lifecycle_ui.parse_job_lifecycle_surface(
            refresh_detail_hierarchy()
        )
        for screen, candidate_identity in (
            (historical, identity),
            (
                complete_but_wrong_scope,
                identity_for_refresh(scope=("a" * 32, "b" * 32)),
            ),
        ):
            with self.subTest(coverage=screen.root_outcome_coverage_complete):
                with self.assertRaises(ui.UIBlocked):
                    lifecycle_ui.adapt_refresh_detail_observation(
                        screen,
                        identity=candidate_identity,
                        observer_ref="authorized-observer",
                    )

    def test_refresh_blocks_root_exclusion_for_unknown_identity(self):
        screen = lifecycle_ui.parse_job_lifecycle_surface(refresh_detail_hierarchy())
        wrong_exclusion = replace(screen.root_exclusions[0], root_ref="e" * 32)
        malformed = replace(screen, root_exclusions=(wrong_exclusion,))

        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.adapt_refresh_detail_observation(
                malformed,
                identity=identity_for_refresh(),
                observer_ref="authorized-observer",
            )

    def test_refresh_coverage_marker_outside_parent_jobrun_does_not_prove_scope(self):
        capture = refresh_detail_hierarchy(coverage="Coverage summary omitted.")
        capture = capture.replace(
            "</hierarchy>",
            node_xml(text="Folder coverage: complete.") + "</hierarchy>",
        )
        screen = lifecycle_ui.parse_job_lifecycle_surface(capture)

        self.assertIsNone(screen.root_outcome_coverage_complete)
        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.adapt_refresh_detail_observation(
                screen,
                identity=identity_for_refresh(),
                observer_ref="authorized-observer",
            )

    def test_sources_root_maps_owner_jobrun_separately_from_scanrun(self):
        root_ref = "a" * 32
        parent_ref = "b" * 32
        scan_ref = "c" * 32
        root = semantic_node_xml(
            resource_id=f"library-root:{root_ref}",
            children=semantic_node_xml(
                resource_id=f"job-run:{parent_ref}",
                children=(
                    semantic_node_xml(
                        resource_id=f"scan-run:{scan_ref}",
                        text="Last scan: complete",
                    )
                    + semantic_node_xml(
                        resource_id=f"job-run:{parent_ref}",
                        children=node_xml(text="View Job"),
                    )
                ),
            )
        )
        screen = lifecycle_ui.parse_job_lifecycle_surface(wrap_nodes(root))
        identity = JobIdentityObservation(
            parent_run_ref=parent_ref,
            scan_run_relations=(
                ScanRunRelation(
                    scan_run_ref=scan_ref,
                    parent_run_ref=parent_ref,
                    root_ref=root_ref,
                ),
            ),
            requested_root_refs=(root_ref,),
            admitted_root_refs=(root_ref,),
            excluded_root_refs=(),
            frozen_scope_ref="frozen-scope",
            observer_ref="independent-identity-observer",
            parent_state=RecoveryState.COMPLETED,
        )
        observed = lifecycle_ui.adapt_scan_root_observation(
            screen,
            identity=identity,
            observer_ref="authorized-observer",
        )
        self.assertIs(type(observed), ScanRootObservation)
        self.assertEqual(observed.root_ref, root_ref)
        self.assertEqual(observed.view_job_run_ref, parent_ref)
        self.assertEqual(observed.scan_run_ref, scan_ref)
        self.assertNotEqual(observed.view_job_run_ref, observed.scan_run_ref)
        self.assertTrue(observed.established())

        with self.subTest(malformed_root_last_scan=True):
            with self.assertRaises(ui.UIBlocked):
                lifecycle_ui.adapt_scan_root_observation(
                    replace(screen, root_last_scan=[]),
                    identity=identity,
                    observer_ref="authorized-observer",
                )

    def test_sources_root_requires_view_job_target_resource_identity(self):
        root_ref = "a" * 32
        parent_ref = "b" * 32
        scan_ref = "c" * 32
        mismatched_view_job_ref = "d" * 32
        identity = JobIdentityObservation(
            parent_run_ref=parent_ref,
            scan_run_relations=(
                ScanRunRelation(
                    scan_run_ref=scan_ref,
                    parent_run_ref=parent_ref,
                    root_ref=root_ref,
                ),
            ),
            requested_root_refs=(root_ref,),
            admitted_root_refs=(root_ref,),
            excluded_root_refs=(),
            frozen_scope_ref="frozen-scope",
            observer_ref="independent-identity-observer",
            parent_state=RecoveryState.COMPLETED,
        )
        view_job_controls = (
            node_xml(text="View Job"),
            semantic_node_xml(
                resource_id=f"job-run:{mismatched_view_job_ref}",
                children=node_xml(text="View Job"),
            ),
        )
        for control in view_job_controls:
            with self.subTest(control=control[:40]):
                root = semantic_node_xml(
                    resource_id=f"library-root:{root_ref}",
                    children=(
                        semantic_node_xml(
                            resource_id=f"job-run:{parent_ref}",
                            children=semantic_node_xml(
                                resource_id=f"scan-run:{scan_ref}",
                                text="Last scan: complete",
                            ),
                        )
                        + control
                    ),
                )
                screen = lifecycle_ui.parse_job_lifecycle_surface(
                    wrap_nodes(root)
                )
                with self.assertRaises(ui.UIBlocked):
                    lifecycle_ui.adapt_scan_root_observation(
                        screen,
                        identity=identity,
                        observer_ref="authorized-observer",
                    )

    def test_library_navigation_and_refresh_controls_require_actionable_unique_nodes(self):
        base = (
            node_xml(text="Search Library", index=0)
            + node_xml(text="Refresh Library", index=1)
            + node_xml(text="Library", index=2)
            + node_xml(text="Jobs", index=3)
            + node_xml(text="Sources", index=4)
        )
        duplicate_disabled_sources = lifecycle_ui.parse_job_lifecycle_surface(
            wrap_nodes(
                base,
                node_xml(
                    text="Sources", enabled=False, clickable=False, index=5
                ),
            )
        )
        self.assertFalse(duplicate_disabled_sources.sources_navigation_present)
        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.require_navigation(
                duplicate_disabled_sources, "navigate_sources"
            )

        duplicate_same_node_sources = lifecycle_ui.parse_job_lifecycle_surface(
            wrap_nodes(
                node_xml(text="Search Library", index=0),
                node_xml(text="Refresh Library", index=1),
                node_xml(text="Library", index=2),
                node_xml(text="Jobs", index=3),
                node_xml(text="Sources\nSources", index=4),
            )
        )
        self.assertFalse(duplicate_same_node_sources.sources_navigation_present)

        disabled_refresh = lifecycle_ui.parse_job_lifecycle_surface(
            wrap_nodes(
                node_xml(text="Search Library", index=0),
                node_xml(
                    text="Refresh Library", enabled=False, clickable=False, index=1
                ),
                node_xml(text="Library", index=2),
                node_xml(text="Jobs", index=3),
                node_xml(text="Sources", index=4),
            )
        )
        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.require_refresh_control(disabled_refresh)

    def test_retry_control_requires_actionable_unique_occurrence(self):
        mirrored = lifecycle_ui.parse_job_lifecycle_surface(
            wrap_nodes(
                node_xml(text="Library Refresh", index=0),
                node_xml(text="Abandoned", index=1),
                node_xml(text="Phase: finalizing", index=2),
                node_xml(text="Retry", content_desc="Retry", index=3),
            )
        )
        self.assertEqual(mirrored.retry_control_count, 1)
        lifecycle_ui.require_retry_control(mirrored)

        duplicate_disabled = lifecycle_ui.parse_job_lifecycle_surface(
            wrap_nodes(
                node_xml(text="Library Refresh", index=0),
                node_xml(text="Abandoned", index=1),
                node_xml(text="Phase: finalizing", index=2),
                node_xml(text="Retry", index=3),
                node_xml(
                    text="Retry", enabled=False, clickable=False, index=4
                ),
            )
        )
        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.require_retry_control(duplicate_disabled)

        disabled = lifecycle_ui.parse_job_lifecycle_surface(
            wrap_nodes(
                node_xml(text="Library Refresh", index=0),
                node_xml(text="Abandoned", index=1),
                node_xml(text="Phase: finalizing", index=2),
                node_xml(
                    text="Retry", enabled=False, clickable=False, index=3
                ),
            )
        )
        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.require_retry_control(disabled)

    def test_jobs_surface_requires_selected_tab_distinct_heading_and_content(self):
        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.parse_job_lifecycle_surface(
                merged_xml(("Jobs", "Active", "Recent"))
            )
        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.parse_job_lifecycle_surface(
                wrap_nodes(
                    node_xml(text="Jobs", selected=False, index=0),
                    node_xml(text="Active", index=1),
                )
            )
        valid = jobs_surface_xml(
            ("Active",), ("Library Refresh", "Running")
        )
        duplicate_disabled = valid.replace(
            "</hierarchy>",
            node_xml(
                text="Jobs", enabled=False, clickable=False, index=5
            )
            + "</hierarchy>",
        )
        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.parse_job_lifecycle_surface(duplicate_disabled)

    def test_jobs_section_word_alone_is_not_a_valid_content_marker(self):
        for marker in ("Active", "Recent"):
            with self.subTest(marker=marker), self.assertRaises(ui.UIBlocked):
                lifecycle_ui.parse_job_lifecycle_surface(
                    jobs_surface_xml((marker,))
                )
        recent = lifecycle_ui.parse_job_lifecycle_surface(
            jobs_surface_xml(("Recent",)).replace(
                "</hierarchy>",
                semantic_node_xml(
                    resource_id=f"job-run:{'a' * 32}",
                    text="Library Refresh\nCompleted",
                )
                + "</hierarchy>",
            )
        )
        self.assertIs(recent.surface, JobLifecycleSurface.JOBS)

    def test_jobs_surface_requires_actionable_tab_and_non_actionable_heading(self):
        cases = (
            (
                node_xml(text="Jobs", selected=True, clickable=True, index=0),
                node_xml(text="Jobs", selected=False, clickable=True, index=1),
            ),
            (
                node_xml(text="Jobs", selected=True, clickable=False, index=0),
                node_xml(text="Jobs", selected=False, clickable=False, index=1),
            ),
        )
        for jobs_nodes in cases:
            with self.subTest(jobs_nodes=jobs_nodes), self.assertRaises(ui.UIBlocked):
                lifecycle_ui.parse_job_lifecycle_surface(
                    wrap_nodes(
                        *jobs_nodes,
                        node_xml(text="Active", index=2),
                        node_xml(text="Library Refresh\nRunning", index=3),
                    )
                )

    def test_jobs_surface_rejects_repeated_content_markers(self):
        cases = (
            (("Active", "Active"), ("Library Refresh", "Running")),
            (("Recent", "Recent"), ("Library Refresh", "Completed")),
            (("No jobs yet", "No jobs yet"),),
        )
        for groups in cases:
            with self.subTest(groups=groups), self.assertRaises(ui.UIBlocked):
                lifecycle_ui.parse_job_lifecycle_surface(jobs_surface_xml(*groups))

    def test_jobs_page_without_section_marker_cannot_fall_through_to_refresh_detail(self):
        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.parse_job_lifecycle_surface(
                jobs_surface_xml(
                    (
                        "Library Refresh",
                        "Phase: scanning",
                        "Completed units: 1",
                        "Total units: 2",
                    )
                )
            )

    def test_jobs_row_status_normalizes_only_proven_mirrored_attributes(self):
        row = "Library Refresh\nRunning"
        prefix = (
            node_xml(text="Jobs", selected=True, index=0)
            + node_xml(text="Jobs", clickable=False, index=1)
            + node_xml(text="Active", index=2)
        )
        mirrored = lifecycle_ui.parse_job_lifecycle_surface(
            wrap_nodes(
                prefix,
                node_xml(
                    text=row,
                    content_desc=row,
                    index=3,
                    resource_id=f"job-run:{'a' * 32}",
                ),
            )
        )
        self.assertEqual(mirrored.lifecycle_status, "Running")
        self.assertEqual(mirrored.active_refresh_row_count, 1)

        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.parse_job_lifecycle_surface(
                wrap_nodes(
                    prefix,
                    node_xml(
                        text=row,
                        content_desc=row + "\nRunning",
                        index=3,
                        resource_id=f"job-run:{'a' * 32}",
                    ),
                )
            )

    def test_jobs_surface_counts_one_refresh_row_and_active_state(self) -> None:
        observed = lifecycle_ui.parse_job_lifecycle_surface(
            jobs_surface_xml(("Active",), ("Recent",)).replace(
                "</hierarchy>",
                semantic_node_xml(
                    resource_id=f"job-run:{'a' * 32}",
                    text="Library Refresh\nRunning",
                )
                + "</hierarchy>",
            )
        )
        self.assertIs(observed.surface, JobLifecycleSurface.JOBS)
        self.assertEqual(observed.visible_refresh_row_count, 1)
        self.assertEqual(observed.active_refresh_row_count, 1)
        self.assertEqual(observed.lifecycle_status, "Running")
        self.assertIsNone(observed.jobs_arrival_marker)

    def test_empty_jobs_surface_reports_no_refresh_rows(self) -> None:
        observed = lifecycle_ui.parse_job_lifecycle_surface(
            jobs_surface_xml(("No jobs yet",))
        )
        self.assertIs(observed.surface, JobLifecycleSurface.JOBS)
        self.assertEqual(observed.visible_refresh_row_count, 0)
        self.assertEqual(observed.active_refresh_row_count, 0)
        self.assertIsNone(observed.lifecycle_status)
        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.parse_job_lifecycle_surface(
                jobs_surface_xml(("No jobs yet",), ("Library Scan",))
            )

    def test_refresh_detail_reads_parent_progress_and_issue_count(self) -> None:
        observed = lifecycle_ui.parse_job_lifecycle_surface(
            xml(
                "Library Refresh",
                "Running",
                "Phase: scan",
                "Progress: 2/3",
                "library_refresh.scanning",
                "Issues: 1",
                "Retry",
                "Library",
                "Jobs",
            )
        )
        self.assertIs(observed.surface, JobLifecycleSurface.REFRESH_DETAIL)
        self.assertEqual(observed.lifecycle_status, "Running")
        self.assertIsNotNone(observed.progress)
        self.assertEqual(observed.progress.phase, "scan")
        self.assertEqual(observed.progress.completed_units, 2)
        self.assertEqual(observed.progress.total_units, 3)
        self.assertEqual(observed.progress.status_key, "library_refresh.scanning")
        self.assertEqual(observed.progress.issue_count, 1)
        self.assertEqual(observed.retry_control_count, 1)
        self.assertFalse(observed.refresh_control_present)

    def test_terminal_refresh_detail_preserves_completed_units(self) -> None:
        observed = lifecycle_ui.parse_job_lifecycle_surface(
            xml(
                "Library Refresh",
                "Completed",
                "Phase: finalizing",
                "Completed units: 7",
                "Issues: 0",
            )
        )
        self.assertIs(observed.surface, JobLifecycleSurface.REFRESH_DETAIL)
        self.assertEqual(observed.lifecycle_status, "Completed")
        self.assertEqual(observed.progress.completed_units, 7)
        self.assertIsNone(observed.progress.total_units)
        self.assertIsNone(observed.progress.status_key)
        self.assertEqual(observed.progress.issue_count, 0)

    def test_scan_root_and_scan_job_surfaces_remain_distinct(self) -> None:
        root = lifecycle_ui.parse_job_lifecycle_surface(
            xml("Last scan: complete", "View Job", "Library", "Jobs", "Sources")
        )
        self.assertIs(root.surface, JobLifecycleSurface.SCAN_ROOT_DETAIL)
        self.assertEqual(root.root_last_scan, "complete")
        self.assertEqual(root.view_job_control_count, 1)

        scan = lifecycle_ui.parse_job_lifecycle_surface(
            xml("Library Scan", "Running", "Partial", "Library", "Jobs")
        )
        self.assertIs(scan.surface, JobLifecycleSurface.SCAN_JOB_DETAIL)
        self.assertEqual(scan.lifecycle_status, "Running")
        self.assertEqual(scan.scan_job_status, "Running")
        self.assertEqual(scan.scan_child_status, "Partial")

    def test_active_sources_root_detail_remains_unidentified(self) -> None:
        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.parse_job_lifecycle_surface(
                xml(
                    "Scanning in progress",
                    "View Job",
                    "Library",
                    "Jobs",
                    "Sources",
                )
            )

    def test_ambiguous_surface_blocks(self) -> None:
        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.parse_job_lifecycle_surface(
                xml("Library Refresh", "Library Scan", "Running")
            )

    def test_foreign_package_blocks(self) -> None:
        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.parse_job_lifecycle_surface(
                xml("Library Refresh", package="com.example.foreign")
            )

    def test_product_failure_is_not_reinterpreted_as_a_surface(self) -> None:
        with self.assertRaises(ui.UIFailed):
            lifecycle_ui.parse_job_lifecycle_surface(xml("Retry Library setup"))

    def test_conflicting_progress_forms_block(self) -> None:
        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.parse_job_lifecycle_surface(
                xml(
                    "Library Refresh",
                    "Running",
                    "Progress: 2/3",
                    "Completed units: 2",
                )
            )

    def test_progress_above_total_fails_closed(self) -> None:
        with self.assertRaises(ui.UIFailed):
            lifecycle_ui.parse_job_lifecycle_surface(
                xml("Library Refresh", "Running", "Progress: 4/3")
            )

    def test_ambiguous_phase_and_progress_block(self) -> None:
        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.parse_job_lifecycle_surface(
                xml("Library Refresh", "Running", "Phase: scan", "Phase: finalizing")
            )
        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.parse_job_lifecycle_surface(
                xml("Library Refresh", "Running", "Progress: 1/3", "Progress: 2/3")
            )

    def test_malformed_or_missing_hierarchy_blocks(self) -> None:
        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.parse_job_lifecycle_surface("<hierarchy>")
        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.parse_job_lifecycle_surface("<not-a-hierarchy />")

    def test_label_scan_enforces_the_node_bound(self) -> None:
        nodes = "".join(
            f'<node package="{QUALIFICATION_PACKAGE}" text="x" visible-to-user="true" />'
            for _ in range(10001)
        )
        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui._node_labels("<hierarchy>" + nodes + "</hierarchy>", QUALIFICATION_PACKAGE)

    def test_non_qualification_target_is_rejected(self) -> None:
        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.parse_job_lifecycle_surface(
                xml("Library Refresh", "Running"),
                expected_package="com.argusromtoolkit.argus",
            )

    def test_surface_and_navigation_guards_fail_closed(self) -> None:
        library = lifecycle_ui.parse_job_lifecycle_surface(
            xml("Search Library", "Refresh Library", "Library")
        )
        lifecycle_ui.require_surface(library, JobLifecycleSurface.LIBRARY)
        lifecycle_ui.require_refresh_control(library)
        lifecycle_ui.require_navigation(library, "navigate_library")
        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.require_surface(library, JobLifecycleSurface.JOBS)
        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.require_navigation(library, "navigate_jobs")
        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.require_navigation(library, "open_refresh_detail")
        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.require_retry_control(library)
        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.require_surface(object(), JobLifecycleSurface.LIBRARY)

    def test_retry_control_requires_exactly_one_detail_control(self) -> None:
        detail = lifecycle_ui.parse_job_lifecycle_surface(
            xml("Library Refresh", "Abandoned", "Phase: finalizing", "Completed units: 2", "Retry")
        )
        lifecycle_ui.require_retry_control(detail)
        duplicate = lifecycle_ui.parse_job_lifecycle_surface(
            xml(
                "Library Refresh",
                "Abandoned",
                "Phase: finalizing",
                "Completed units: 2",
                "Retry",
                "Retry",
            )
        )
        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.require_retry_control(duplicate)

    def test_jobs_row_status_requires_one_merged_accessibility_node(self) -> None:
        for groups in (
            (("Active",), ("Library Refresh",), ("Running",)),
            (("Recent",), ("Library Refresh",)),
        ):
            with self.subTest(groups=groups), self.assertRaises(ui.UIBlocked):
                lifecycle_ui.parse_job_lifecycle_surface(jobs_surface_xml(*groups))

    def test_jobs_row_status_ignores_a_neighbouring_job_status(self) -> None:
        observed = lifecycle_ui.parse_job_lifecycle_surface(
            jobs_surface_xml(("Active",)).replace(
                "</hierarchy>",
                semantic_node_xml(
                    resource_id=f"job-run:{'a' * 32}",
                    text="Library Scan\nRunning",
                )
                + semantic_node_xml(
                    resource_id=f"job-run:{'b' * 32}",
                    text="Library Refresh\nCompleted",
                )
                + "</hierarchy>",
            )
        )
        self.assertIs(observed.surface, JobLifecycleSurface.JOBS)
        self.assertEqual(observed.visible_refresh_row_count, 1)
        self.assertEqual(observed.active_refresh_row_count, 0)
        self.assertEqual(observed.lifecycle_status, "Completed")

    def test_jobs_surface_rejects_an_unclassified_refresh_row(self) -> None:
        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.parse_job_lifecycle_surface(
                jobs_surface_xml(
                    ("Active",),
                    ("Library Refresh", "Running"),
                    ("Library Refresh",),
                )
            )

    def test_jobs_surface_rejects_an_unbound_lifecycle_status(self) -> None:
        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.parse_job_lifecycle_surface(
                jobs_surface_xml(
                    ("Active",),
                    ("Library Refresh", "Running"),
                    ("Running",),
                )
            )

    def test_jobs_row_status_withholds_conflicting_node_states(self) -> None:
        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.parse_job_lifecycle_surface(
                jobs_surface_xml(
                    ("Active",),
                    ("Library Refresh", "Running", "Completed"),
                )
            )
        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.parse_job_lifecycle_surface(
                jobs_surface_xml(
                    ("Active",),
                    ("Library Refresh", "Library Scan", "Running"),
                )
            )

    def test_jobs_row_status_withholds_duplicate_identical_node_states(self) -> None:
        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.parse_job_lifecycle_surface(
                jobs_surface_xml(
                    ("Active",),
                    ("Library Refresh", "Running", "Running"),
                )
            )

    def test_jobs_ambiguity_withholds_row_and_status_counts(self) -> None:
        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.parse_job_lifecycle_surface(
                jobs_surface_xml(
                    ("Active",),
                    ("Library Refresh",),
                    ("Library Refresh",),
                    ("Running",),
                )
            )
        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.parse_job_lifecycle_surface(
                jobs_surface_xml(
                    ("Active",),
                    ("Library Refresh",),
                    ("Running",),
                    ("Completed",),
                )
            )

    def test_direct_label_scan_rejects_malformed_or_foreign_input(self) -> None:
        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui._node_labels("<hierarchy>", QUALIFICATION_PACKAGE)
        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui._node_labels("<not-a-hierarchy />", QUALIFICATION_PACKAGE)
        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui._node_labels(
                '<hierarchy><node package="com.example.foreign" text="Jobs" /></hierarchy>',
                QUALIFICATION_PACKAGE,
            )

    def test_direct_label_scan_ignores_system_ui_and_invisible_nodes(self) -> None:
        frame = (
            "<hierarchy>"
            f'<node package="com.android.systemui" text="Library Refresh" />'
            f'<node package="{QUALIFICATION_PACKAGE}" text="Hidden" visible-to-user="false" />'
            f'<node package="{QUALIFICATION_PACKAGE}" text="Jobs" />'
            "</hierarchy>"
        )
        self.assertEqual(
            lifecycle_ui._node_labels(frame, QUALIFICATION_PACKAGE),
            ("Jobs",),
        )

    def test_refresh_control_guard_rejects_a_library_without_the_control(self) -> None:
        library = lifecycle_ui.parse_job_lifecycle_surface(
            xml("Search Library", "Refresh Library", "Library")
        )
        without_control = replace(library, refresh_control_present=False)
        with self.assertRaises(ui.UIBlocked):
            lifecycle_ui.require_refresh_control(without_control)


if __name__ == "__main__":
    unittest.main()
