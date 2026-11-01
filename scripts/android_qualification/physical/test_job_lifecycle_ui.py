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

    def test_jobs_surface_counts_one_refresh_row_and_active_state(self) -> None:
        observed = lifecycle_ui.parse_job_lifecycle_surface(
            merged_xml(("Jobs", "Active", "Recent"), ("Library Refresh", "Running"))
        )
        self.assertIs(observed.surface, JobLifecycleSurface.JOBS)
        self.assertEqual(observed.visible_refresh_row_count, 1)
        self.assertEqual(observed.active_refresh_row_count, 1)
        self.assertEqual(observed.lifecycle_status, "Running")
        self.assertIsNone(observed.jobs_arrival_marker)

    def test_empty_jobs_surface_reports_no_refresh_rows(self) -> None:
        observed = lifecycle_ui.parse_job_lifecycle_surface(
            xml("Jobs", "Active", "Recent")
        )
        self.assertIs(observed.surface, JobLifecycleSurface.JOBS)
        self.assertEqual(observed.visible_refresh_row_count, 0)
        self.assertEqual(observed.active_refresh_row_count, 0)
        self.assertIsNone(observed.lifecycle_status)

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
        separate = lifecycle_ui.parse_job_lifecycle_surface(
            xml("Jobs", "Active", "Library Refresh", "Running")
        )
        self.assertIs(separate.surface, JobLifecycleSurface.JOBS)
        self.assertEqual(separate.visible_refresh_row_count, 1)
        self.assertIsNone(separate.active_refresh_row_count)
        self.assertIsNone(separate.lifecycle_status)

    def test_jobs_row_status_ignores_a_neighbouring_job_status(self) -> None:
        observed = lifecycle_ui.parse_job_lifecycle_surface(
            merged_xml(
                ("Jobs", "Active"),
                ("Library Scan", "Running"),
                ("Library Refresh",),
            )
        )
        self.assertIs(observed.surface, JobLifecycleSurface.JOBS)
        self.assertEqual(observed.visible_refresh_row_count, 1)
        self.assertIsNone(observed.active_refresh_row_count)
        self.assertIsNone(observed.lifecycle_status)

    def test_jobs_row_status_withholds_conflicting_node_states(self) -> None:
        conflicting = lifecycle_ui.parse_job_lifecycle_surface(
            merged_xml(
                ("Jobs", "Active"),
                ("Library Refresh", "Running", "Completed"),
            )
        )
        self.assertIsNone(conflicting.active_refresh_row_count)
        self.assertIsNone(conflicting.lifecycle_status)
        mixed_titles = lifecycle_ui.parse_job_lifecycle_surface(
            merged_xml(
                ("Jobs", "Active"),
                ("Library Refresh", "Library Scan", "Running"),
            )
        )
        self.assertIsNone(mixed_titles.active_refresh_row_count)
        self.assertIsNone(mixed_titles.lifecycle_status)

    def test_jobs_row_status_withholds_duplicate_identical_node_states(self) -> None:
        observed = lifecycle_ui.parse_job_lifecycle_surface(
            merged_xml(
                ("Jobs", "Active"),
                ("Library Refresh", "Running", "Running"),
            )
        )
        self.assertIs(observed.surface, JobLifecycleSurface.JOBS)
        self.assertEqual(observed.visible_refresh_row_count, 1)
        self.assertIsNone(observed.active_refresh_row_count)
        self.assertIsNone(observed.lifecycle_status)

    def test_jobs_ambiguity_withholds_row_and_status_counts(self) -> None:
        duplicate_rows = lifecycle_ui.parse_job_lifecycle_surface(
            xml("Jobs", "Active", "Library Refresh", "Library Refresh", "Running")
        )
        self.assertIsNone(duplicate_rows.active_refresh_row_count)
        conflicting_states = lifecycle_ui.parse_job_lifecycle_surface(
            xml("Jobs", "Active", "Library Refresh", "Running", "Completed")
        )
        self.assertIsNone(conflicting_states.lifecycle_status)

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
