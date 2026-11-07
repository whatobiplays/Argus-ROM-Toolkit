"""Synthetic tests for the private Issue #28 accessibility surface parser."""

from __future__ import annotations

from dataclasses import replace
import unittest
from xml.sax.saxutils import escape

from scripts.android_qualification._job_lifecycle_contract import (
    JobLifecycleSurface,
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
) -> str:
    """Build one accessibility node with explicit control-state evidence."""
    text_value = escape(text, {chr(34): "&quot;"}).replace("\n", "&#10;")
    description_value = escape(content_desc, {chr(34): "&quot;"}).replace(
        "\n", "&#10;"
    )
    return (
        f'<node package="{QUALIFICATION_PACKAGE}" '
        f'text="{text_value}" content-desc="{description_value}" '
        f'enabled="{str(enabled).lower()}" '
        f'clickable="{str(clickable).lower()}" '
        f'selected="{str(selected).lower()}" visible-to-user="true" '
        f'bounds="[10,{index * 40 + 10}][210,{index * 40 + 40}]" />'
    )


def wrap_nodes(*nodes: str) -> str:
    return '<hierarchy rotation="0">' + "".join(nodes) + "</hierarchy>"


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
            jobs_surface_xml(("Recent",), ("Library Refresh", "Completed"))
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
                node_xml(text=row, content_desc=row, index=3),
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
                    ),
                )
            )

    def test_jobs_surface_counts_one_refresh_row_and_active_state(self) -> None:
        observed = lifecycle_ui.parse_job_lifecycle_surface(
            jobs_surface_xml(
                ("Active",),
                ("Recent",),
                ("Library Refresh", "Running"),
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
            jobs_surface_xml(
                ("Active",),
                ("Library Scan", "Running"),
                ("Library Refresh", "Completed"),
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
