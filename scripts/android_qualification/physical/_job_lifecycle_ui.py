"""Private accessibility parser for Issue #28 job lifecycle surfaces.

The parser recognizes only the fixed production labels rendered by the pinned
qualification application. It discards arbitrary accessibility text, refuses
ambiguous or foreign surfaces, and never infers a JobRunId from row order,
titles, or timing. Job identity comes from an explicitly authorized observer.
"""

from __future__ import annotations

from dataclasses import dataclass
import re
import xml.etree.ElementTree as ET

from . import ui
from .._job_lifecycle_contract import (
    JobLifecycleSurface,
    RefreshProgressFacts,
)

_PHASE_RE = re.compile(r"^Phase: ([^\r\n]{1,96})$")
_PROGRESS_RE = re.compile(r"^Progress: (\d{1,18})/(\d{1,18})$")
_COMPLETED_RE = re.compile(r"^Completed units: (\d{1,18})$")
_TOTAL_RE = re.compile(r"^Total units: (\d{1,18})$")
_ISSUES_RE = re.compile(r"^Issues: (\d{1,18})$")
_STATUS_KEY_RE = re.compile(r"^library_refresh\.[a-z0-9_.-]{1,96}$")
_LAST_SCAN_RE = re.compile(r"^Last scan: ([a-z]{1,32})$")

_ACTIVE_STATUS_LABELS = frozenset({"Queued", "Preparing", "Running"})
_TERMINAL_STATUS_LABELS = frozenset({
    "Completed", "Completed with issues", "Failed", "Cancelled",
    "Interrupted", "Abandoned",
})
_STATUS_LABELS = _ACTIVE_STATUS_LABELS | _TERMINAL_STATUS_LABELS
_SCAN_STATUS_LABELS = frozenset({
    "Scanning", "Complete", "Partial", "Failed", "Cancelled", "Abandoned",
})


@dataclass(frozen=True)
class JobLifecycleScreenObservation:
    """Sanitized facts from exactly one verified application surface."""

    surface: JobLifecycleSurface
    lifecycle_status: str | None
    progress: RefreshProgressFacts | None
    jobs_arrival_marker: str | None
    visible_refresh_row_count: int | None
    active_refresh_row_count: int | None
    library_navigation_present: bool
    jobs_navigation_present: bool
    sources_navigation_present: bool
    refresh_control_present: bool
    retry_control_count: int
    view_job_control_count: int
    root_last_scan: str | None
    scan_job_status: str | None
    scan_child_status: str | None


def _node_label_groups(
    xml: str, expected_package: str
) -> tuple[tuple[str, ...], ...]:
    """Return bounded visible labels for each node of the expected application."""
    try:
        root = ET.fromstring(xml)
    except (ET.ParseError, ValueError):
        raise ui.UIBlocked("Lifecycle accessibility XML could not be parsed.") from None
    if root.tag != "hierarchy":
        raise ui.UIBlocked("Lifecycle accessibility hierarchy is missing.")
    groups: list[tuple[str, ...]] = []
    for index, element in enumerate(root.iter("node")):
        if index >= 10000:
            raise ui.UIBlocked("Accessibility node limit exceeded.")
        package = element.get("package", "")
        if package == "com.android.systemui":
            continue
        if package != expected_package:
            raise ui.UIBlocked("A foreign or unidentified UI surface prevents selection.")
        if element.get("visible-to-user", "true") == "false":
            continue
        groups.append(
            tuple(
                line
                for attribute in ("text", "content-desc")
                for line in element.get(attribute, "").splitlines()
                if line
            )
        )
    return tuple(groups)


def _node_labels(xml: str, expected_package: str) -> tuple[str, ...]:
    """Return bounded visible labels for the expected application only."""
    return tuple(
        label
        for group in _node_label_groups(xml, expected_package)
        for label in group
    )


def _single(values: list[object], code: str) -> object | None:
    if not values:
        return None
    if len(values) != 1:
        raise ui.UIBlocked(code)
    return values[0]


def _parse_progress(labels: tuple[str, ...]) -> RefreshProgressFacts | None:
    phases = [match.group(1) for label in labels if (match := _PHASE_RE.fullmatch(label))]
    progresses = [
        (int(match.group(1)), int(match.group(2)))
        for label in labels
        if (match := _PROGRESS_RE.fullmatch(label))
    ]
    completed = [
        int(match.group(1)) for label in labels if (match := _COMPLETED_RE.fullmatch(label))
    ]
    totals = [
        int(match.group(1)) for label in labels if (match := _TOTAL_RE.fullmatch(label))
    ]
    status_keys = [label for label in labels if _STATUS_KEY_RE.fullmatch(label)]
    issues = [
        int(match.group(1))
        for label in labels
        if (match := _ISSUES_RE.fullmatch(label))
    ]
    if not any((phases, progresses, completed, totals, status_keys)):
        return None
    if len(set(phases)) > 1:
        raise ui.UIBlocked("Refresh phase is ambiguous.")
    phase = phases[0] if phases else None
    progress = _single(progresses, "Refresh progress is ambiguous.")
    completed_value = _single(completed, "Completed refresh units are ambiguous.")
    total_value = _single(totals, "Total refresh units are ambiguous.")
    status_key = _single(status_keys, "Refresh status key is ambiguous.")
    issue_count = _single(issues, "Refresh issue count is ambiguous.")
    if progress is not None and (completed_value is not None or total_value is not None):
        raise ui.UIBlocked("Refresh progress is expressed in conflicting forms.")
    if progress is not None:
        completed_value, total_value = progress
    if (
        type(completed_value) is int
        and type(total_value) is int
        and completed_value > total_value
    ):
        raise ui.UIFailed("Refresh progress contradicts its total unit count.")
    return RefreshProgressFacts(
        phase=phase if type(phase) is str else None,
        completed_units=completed_value if type(completed_value) is int else None,
        total_units=total_value if type(total_value) is int else None,
        status_key=status_key if type(status_key) is str else None,
        issue_count=issue_count if type(issue_count) is int else None,
    )


def parse_job_lifecycle_surface(
    xml: str,
    *,
    expected_package: str = ui.QUALIFICATION_PACKAGE,
) -> JobLifecycleScreenObservation:
    """Parse one coherent lifecycle surface with exact production labels."""
    if expected_package != ui.QUALIFICATION_PACKAGE:
        raise ui.UIBlocked("Job lifecycle qualification requires the isolated application.")
    nodes = ui.parse_ui(xml, expected_package=expected_package)
    if any(node.key == "product_failure" for node in nodes):
        raise ui.UIFailed("The Release UI reports a product operation failure.")
    label_groups = _node_label_groups(xml, expected_package)
    labels = tuple(label for group in label_groups for label in group)
    keys = tuple(node.key for node in nodes)
    label_set = frozenset(labels)
    jobs_markers = tuple(
        marker for marker in ("Active", "Recent", "No jobs yet") if marker in label_set
    )
    progress = _parse_progress(labels)
    has_last_scan = any(_LAST_SCAN_RE.fullmatch(label) for label in labels)
    has_refresh_title = "Library Refresh" in label_set
    has_scan_title = "Library Scan" in label_set
    has_retry_relation = (
        "Retried from" in label_set or "Retried as" in label_set
    )
    if jobs_markers:
        surface = JobLifecycleSurface.JOBS
    elif has_last_scan and "View Job" in label_set:
        surface = JobLifecycleSurface.SCAN_ROOT_DETAIL
    elif has_scan_title and not has_refresh_title:
        surface = JobLifecycleSurface.SCAN_JOB_DETAIL
    elif has_refresh_title and (
        has_retry_relation or progress is not None or "Phase" in label_set
    ):
        surface = JobLifecycleSurface.REFRESH_DETAIL
    elif (
        "Search Library" in label_set
        and "Refresh Library" in label_set
        and not has_refresh_title
        and not has_scan_title
    ):
        surface = JobLifecycleSurface.LIBRARY
    else:
        raise ui.UIBlocked("The current surface is ambiguous for a lifecycle observation.")

    if surface is JobLifecycleSurface.JOBS:
        refresh_rows = labels.count("Library Refresh")
        refresh_row_groups = tuple(
            group for group in label_groups if "Library Refresh" in group
        )
        active_refresh_rows: int | None = None
        lifecycle_status: str | None = None
        if refresh_rows == 0:
            active_refresh_rows = 0
        elif (
            len(refresh_row_groups) == 1
            and refresh_row_groups[0].count("Library Refresh") == 1
            and "Library Scan" not in refresh_row_groups[0]
        ):
            row_statuses = [
                label for label in refresh_row_groups[0] if label in _STATUS_LABELS
            ]
            if len(row_statuses) == 1:
                lifecycle_status = row_statuses[0]
                active_refresh_rows = int(lifecycle_status in _ACTIVE_STATUS_LABELS)
    else:
        refresh_rows = None
        active_refresh_rows = None
        statuses = [label for label in labels if label in _STATUS_LABELS]
        lifecycle_status = statuses[0] if len(set(statuses)) == 1 else None

    scan_statuses = [label for label in labels if label in _SCAN_STATUS_LABELS]
    scan_child_status = scan_statuses[0] if len(set(scan_statuses)) == 1 else None
    last_scan_states = [
        match.group(1) for label in labels if (match := _LAST_SCAN_RE.fullmatch(label))
    ]
    root_state = last_scan_states[0] if len(set(last_scan_states)) == 1 else None
    view_job_count = keys.count("view_job")
    return JobLifecycleScreenObservation(
        surface=surface,
        lifecycle_status=lifecycle_status,
        progress=progress,
        jobs_arrival_marker=jobs_markers[0] if len(jobs_markers) == 1 else None,
        visible_refresh_row_count=refresh_rows,
        active_refresh_row_count=active_refresh_rows,
        library_navigation_present="library_navigation" in keys,
        jobs_navigation_present="jobs_navigation" in keys,
        sources_navigation_present=(
            "sources_navigation" in keys or "Sources" in label_set
        ),
        refresh_control_present="refresh" in keys,
        retry_control_count=labels.count("Retry"),
        view_job_control_count=view_job_count,
        root_last_scan=root_state,
        scan_job_status=(
            lifecycle_status
            if surface is JobLifecycleSurface.SCAN_JOB_DETAIL
            else None
        ),
        scan_child_status=(
            scan_child_status
            if surface is JobLifecycleSurface.SCAN_JOB_DETAIL
            else None
        ),
    )


def require_surface(
    observation: JobLifecycleScreenObservation,
    expected: JobLifecycleSurface,
) -> None:
    """Require the observation to belong to its own current verified surface."""
    if (
        type(observation) is not JobLifecycleScreenObservation
        or observation.surface is not expected
    ):
        raise ui.UIBlocked("The observation does not belong to the expected current surface.")


def require_navigation(observation: JobLifecycleScreenObservation, action: str) -> None:
    """Require one unique shell navigation control for the requested route."""
    available = {
        "navigate_library": observation.library_navigation_present,
        "navigate_jobs": observation.jobs_navigation_present,
        "navigate_sources": observation.sources_navigation_present,
    }
    if action not in available:
        raise ui.UIBlocked("The requested lifecycle navigation action is unsupported.")
    if not available[action]:
        raise ui.UIBlocked("The requested shell navigation control is unavailable.")


def require_refresh_control(observation: JobLifecycleScreenObservation) -> None:
    """Require the unique Library refresh control on the current Library."""
    require_surface(observation, JobLifecycleSurface.LIBRARY)
    if not observation.refresh_control_present:
        raise ui.UIBlocked("The Library refresh control is unavailable.")


def require_retry_control(observation: JobLifecycleScreenObservation) -> None:
    """Require one surface-scoped retry control on refresh detail."""
    require_surface(observation, JobLifecycleSurface.REFRESH_DETAIL)
    if observation.retry_control_count != 1:
        raise ui.UIBlocked("A unique refresh-detail retry control is unavailable.")
