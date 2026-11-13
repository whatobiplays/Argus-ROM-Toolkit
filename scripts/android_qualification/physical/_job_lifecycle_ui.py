"""Private accessibility parser for Issue #28 job lifecycle surfaces.

The parser recognizes only the fixed production labels rendered by the pinned
qualification application. It discards arbitrary accessibility text, refuses
ambiguous or foreign surfaces, and maps run identity only from validated
semantics resource IDs and hierarchy. UI identity remains a projection that
must be checked against the independently authorized identity observer.
"""

from __future__ import annotations

from dataclasses import dataclass
import re
import xml.etree.ElementTree as ET
from urllib.parse import quote, unquote
from uuid import uuid4

from . import ui
from .._job_lifecycle_contract import (
    JobIdentityObservation,
    JobLifecycleSurface,
    JobsSurfaceObservation,
    LibrarySurfaceObservation,
    RecoveryState,
    RefreshDetailObservation,
    RefreshProgressFacts,
    ROOT_HISTORICAL_SCAN_STATES,
    RootExclusionObservation,
    RootExclusionReason,
    ScanRootObservation,
    ScanRootPresentation,
    ScanRunObservation,
    ScanRunRelation,
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
_JOB_RUN_PREFIX = "job-run:"
_SCAN_RUN_PREFIX = "scan-run:"
_LIBRARY_ROOT_PREFIX = "library-root:"
_LIBRARY_PAGE_PREFIX = "argus.library.page.v1;"
_LIBRARY_ROW_PREFIX = "argus.library.row.v1;"
_LIBRARY_PAGE_FIELDS = (
    "observation", "profile", "page", "first", "continuation", "status",
    "hasNext", "final", "pageSize", "expectedRows",
)
_LIBRARY_ROW_FIELDS = ("observation", "page", "row", "gameId")
_LIBRARY_PROFILES = frozenset({
    "OrdinaryUserQuery", "AllActiveMembershipBaseline",
})
_ROOT_COVERAGE_COMPLETE = "Folder coverage: complete."
_ROOT_COVERAGE_UNAVAILABLE = "Some historical folder outcomes unavailable."
_JOB_OPERATIONS = frozenset({
    "Library Refresh", "Library Scan", "Game Refresh", "Metadata Resolution",
})
_EXCLUSION_REASONS = {
    "Already being scanned": RootExclusionReason.ALREADY_SCANNING,
    "No longer configured": RootExclusionReason.NO_LONGER_CONFIGURED,
    "Invalid configuration": RootExclusionReason.INVALID_CONFIGURATION,
}
_RECOVERY_STATES = {
    "Queued": RecoveryState.ACTIVE,
    "Preparing": RecoveryState.ACTIVE,
    "Running": RecoveryState.ACTIVE,
    "Completed": RecoveryState.COMPLETED,
    "Completed with issues": RecoveryState.COMPLETED_WITH_ISSUES,
    "Failed": RecoveryState.FAILED,
    "Cancelled": RecoveryState.CANCELLED,
    "Interrupted": RecoveryState.INTERRUPTED,
    "Abandoned": RecoveryState.ABANDONED,
}


@dataclass(frozen=True)
class LibraryPageObservation:
    """One parsed page marker from a single Android hierarchy capture."""

    observation_id: str
    query_profile: str
    page_ordinal: int
    is_first_page: bool
    is_continuation_page: bool
    status: str
    has_next_page: bool | None
    is_final_page: bool | None
    page_size: int
    expected_row_count: int | None
    capture_ref: str


@dataclass(frozen=True)
class LibraryRowObservation:
    """One parsed row marker carrying the exact GameId from the UI."""

    observation_id: str
    page_ordinal: int
    row_ordinal: int
    game_id: str
    boundary_page_ordinal: int | None
    capture_ref: str


@dataclass(frozen=True)
class JobRunRowObservation:
    """One lifecycle JobRunId bound to its own operation and status subtree."""

    job_run_ref: str
    operation_label: str | None
    lifecycle_status: str | None


@dataclass(frozen=True)
class ScanRunScreenObservation:
    """One UI-projected ScanRun relationship and its visible child state."""

    relation: ScanRunRelation
    lifecycle_status: str | None


@dataclass(frozen=True)
class _SemanticFacts:
    job_run_rows: tuple[JobRunRowObservation, ...]
    parent_run_ref: str | None
    view_job_run_ref: str | None
    scan_run_relations: tuple[ScanRunRelation, ...]
    scan_run_screen_observations: tuple[ScanRunScreenObservation, ...]
    root_refs: tuple[str, ...]
    excluded_root_refs: tuple[str, ...]
    root_exclusions: tuple[RootExclusionObservation, ...]
    retry_source_run_ref: str | None
    retry_successor_run_ref: str | None
    root_outcome_coverage_complete: bool | None


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
    root_scan_active: bool | None
    cancellation_requested: bool | None
    scan_job_status: str | None
    scan_child_status: str | None
    library_pages: tuple[LibraryPageObservation, ...] = ()
    library_rows: tuple[LibraryRowObservation, ...] = ()
    job_run_rows: tuple[JobRunRowObservation, ...] = ()
    parent_run_ref: str | None = None
    scan_run_relations: tuple[ScanRunRelation, ...] = ()
    scan_run_screen_observations: tuple[ScanRunScreenObservation, ...] = ()
    root_refs: tuple[str, ...] = ()
    excluded_root_refs: tuple[str, ...] = ()
    root_exclusions: tuple[RootExclusionObservation, ...] = ()
    view_job_run_ref: str | None = None
    retry_source_run_ref: str | None = None
    retry_successor_run_ref: str | None = None
    root_outcome_coverage_complete: bool | None = None
    # Unique to one parser invocation; never interpreted as process identity.
    capture_ref: str = ""


@dataclass(frozen=True)
class _AccessibilityNode:
    """Transient, package-checked facts from one XML hierarchy node."""

    labels: tuple[str, ...]
    resource_id: str | None
    ancestor_resource_ids: tuple[str, ...]
    descendant_resource_ids: tuple[str, ...]
    subtree_labels: tuple[str, ...]
    subtree_labels_without_nested_job_runs: tuple[str, ...]
    subtree_labels_without_nested_lifecycle_runs: tuple[str, ...]
    enabled: bool
    clickable: bool
    selected: bool


def _accessibility_nodes(
    xml: str, expected_package: str
) -> tuple[_AccessibilityNode, ...]:
    """Read bounded hierarchy nodes while keeping raw device text transient."""
    if (
        not isinstance(xml, str)
        or len(xml) > 2 * 1024 * 1024
        or "<!DOCTYPE" in xml.upper()
        or "<!ENTITY" in xml.upper()
    ):
        raise ui.UIBlocked("Accessibility capture is invalid or exceeds its bound.")
    try:
        root = ET.fromstring(xml)
    except (ET.ParseError, ValueError):
        raise ui.UIBlocked("Lifecycle accessibility XML could not be parsed.") from None
    if root.tag != "hierarchy":
        raise ui.UIBlocked("Lifecycle accessibility hierarchy is missing.")

    node_count = 0

    def visit(
        element: ET.Element,
        ancestor_resource_ids: tuple[str, ...],
        depth: int,
        ancestor_visible: bool = True,
    ) -> tuple[
        list[_AccessibilityNode],
        tuple[str, ...],
        tuple[str, ...],
        tuple[str, ...],
        tuple[str, ...],
        str | None,
    ]:
        nonlocal node_count
        if depth > 256:
            raise ui.UIBlocked("Accessibility hierarchy depth exceeded.")
        package = element.get("package", "")
        if package == "com.android.systemui":
            return [], (), (), (), (), None
        elif package != expected_package:
            raise ui.UIBlocked("A foreign or unidentified UI surface prevents selection.")

        node_count += 1
        if node_count > 10000:
            raise ui.UIBlocked("Accessibility node limit exceeded.")
        visible = ancestor_visible and element.get("visible-to-user", "true") != "false"
        text_labels = tuple(
            line for line in element.get("text", "").splitlines() if line
        ) if visible else ()
        description_labels = tuple(
            line for line in element.get("content-desc", "").splitlines() if line
        ) if visible else ()
        if text_labels and text_labels == description_labels:
            labels = text_labels
        else:
            labels = text_labels + description_labels

        raw_resource_id = element.get("resource-id") if visible else None
        resource_id = raw_resource_id if raw_resource_id else None
        child_ancestors = ancestor_resource_ids + (
            (resource_id,) if resource_id is not None else ()
        )
        child_nodes: list[_AccessibilityNode] = []
        child_labels: list[str] = []
        child_labels_without_nested_runs: list[str] = []
        child_labels_without_nested_lifecycle_runs: list[str] = []
        child_resource_ids: list[str] = []
        for child in element:
            if child.tag != "node":
                continue
            (
                nested_nodes,
                nested_labels,
                nested_ids,
                nested_labels_without_runs,
                nested_labels_without_lifecycle_runs,
                child_resource_id,
            ) = visit(
                child, child_ancestors, depth + 1, visible
            )
            child_nodes.extend(nested_nodes)
            child_labels.extend(nested_labels)
            child_resource_ids.extend(nested_ids)
            if child_resource_id is None or not child_resource_id.startswith(
                _JOB_RUN_PREFIX
            ):
                child_labels_without_nested_runs.extend(
                    nested_labels_without_runs
                )
            if child_resource_id is None or not child_resource_id.startswith(
                (_JOB_RUN_PREFIX, _SCAN_RUN_PREFIX)
            ):
                child_labels_without_nested_lifecycle_runs.extend(
                    nested_labels_without_lifecycle_runs
                )

        node = _AccessibilityNode(
            labels=labels,
            resource_id=resource_id,
            ancestor_resource_ids=ancestor_resource_ids,
            descendant_resource_ids=tuple(child_resource_ids),
            subtree_labels=labels + tuple(child_labels),
            subtree_labels_without_nested_job_runs=(
                labels + tuple(child_labels_without_nested_runs)
            ),
            subtree_labels_without_nested_lifecycle_runs=(
                labels + tuple(child_labels_without_nested_lifecycle_runs)
            ),
            enabled=element.get("enabled") == "true",
            clickable=element.get("clickable") == "true",
            selected=element.get("selected") == "true",
        )
        records = ([node] if visible else []) + child_nodes
        own_resource_ids = (
            ((resource_id,) if resource_id is not None else ())
            + tuple(child_resource_ids)
        )
        return (
            records,
            node.subtree_labels,
            own_resource_ids,
            node.subtree_labels_without_nested_job_runs,
            node.subtree_labels_without_nested_lifecycle_runs,
            resource_id,
        )

    result: list[_AccessibilityNode] = []
    for child in root:
        if child.tag != "node":
            continue
        nodes, _, _, _, _, _ = visit(child, (), 1)
        result.extend(nodes)
    return tuple(result)


def _valid_reference(value: object) -> bool:
    return (
        type(value) is str
        and 1 <= len(value) <= 256
        and bool(value.strip())
        and not any(ord(character) < 0x20 or ord(character) == 0x7F for character in value)
    )


def _typed_resource_reference(resource_id: str, prefix: str, code: str) -> str:
    value = resource_id[len(prefix):]
    if (
        not resource_id.startswith(prefix)
        or not re.fullmatch(r"[0-9a-f]{32}", value)
        or set(value) == {"0"}
    ):
        raise ui.UIBlocked(code)
    return value


def _decode_component(value: str, code: str) -> str:
    if not value or len(value) > 768 or re.search(r"%(?![0-9A-Fa-f]{2})", value):
        raise ui.UIBlocked(code)
    try:
        decoded = unquote(value, errors="strict")
    except (UnicodeDecodeError, ValueError):
        raise ui.UIBlocked(code) from None
    if (
        not _valid_reference(decoded)
        or quote(decoded, safe="-_.!~*'()") != value
    ):
        raise ui.UIBlocked(code)
    return decoded


def _identifier_fields(
    resource_id: str,
    prefix: str,
    expected_fields: tuple[str, ...],
    code: str,
) -> dict[str, str]:
    if not resource_id.startswith(prefix):
        raise ui.UIBlocked(code)
    encoded_fields = resource_id[len(prefix):].split(";")
    if len(encoded_fields) != len(expected_fields):
        raise ui.UIBlocked(code)
    values: dict[str, str] = {}
    for expected, item in zip(expected_fields, encoded_fields, strict=True):
        key, separator, value = item.partition("=")
        if not separator or key != expected or not value or key in values:
            raise ui.UIBlocked(code)
        values[key] = value
    return values


def _parse_library_page_identifier(
    resource_id: str, *, capture_ref: str
) -> LibraryPageObservation:
    code = "Library page identity is malformed or unsupported."
    values = _identifier_fields(
        resource_id, _LIBRARY_PAGE_PREFIX, _LIBRARY_PAGE_FIELDS, code
    )
    observation_id = _decode_component(values["observation"], code)
    if not re.fullmatch(r"obs-[1-9]\d{0,8}", observation_id):
        raise ui.UIBlocked(code)
    profile = values["profile"]
    if profile not in _LIBRARY_PROFILES:
        raise ui.UIBlocked(code)
    numeric_values: dict[str, int | None] = {}
    for field in ("page", "pageSize", "expectedRows"):
        value = values[field]
        if field == "expectedRows" and value == "unknown":
            numeric_values[field] = None
            continue
        if not re.fullmatch(r"\d{1,6}", value):
            raise ui.UIBlocked(code)
        numeric_values[field] = int(value)
    page = numeric_values["page"]
    page_size = numeric_values["pageSize"]
    expected_rows = numeric_values["expectedRows"]
    if (
        type(page) is not int
        or page < 1
        or type(page_size) is not int
        or page_size < 1
        or (type(expected_rows) is int and expected_rows > page_size)
    ):
        raise ui.UIBlocked(code)

    def boolean(name: str, *, allow_unknown: bool = False) -> bool | None:
        value = values[name]
        if allow_unknown and value == "unknown":
            return None
        if value not in {"true", "false"}:
            raise ui.UIBlocked(code)
        return value == "true"

    first = boolean("first")
    continuation = boolean("continuation")
    has_next = boolean("hasNext", allow_unknown=True)
    is_final = boolean("final", allow_unknown=True)
    status = values["status"]
    if status not in {"loading", "complete", "failed"}:
        raise ui.UIBlocked(code)
    return LibraryPageObservation(
        observation_id=observation_id,
        query_profile=profile,
        page_ordinal=page,
        is_first_page=bool(first),
        is_continuation_page=bool(continuation),
        status=status,
        has_next_page=has_next,
        is_final_page=is_final,
        page_size=page_size,
        expected_row_count=expected_rows,
        capture_ref=capture_ref,
    )


def _parse_library_row_identifier(
    resource_id: str,
    *,
    capture_ref: str,
    boundary_page_ordinal: int | None,
) -> LibraryRowObservation:
    code = "Library row identity is malformed or unsupported."
    values = _identifier_fields(
        resource_id, _LIBRARY_ROW_PREFIX, _LIBRARY_ROW_FIELDS, code
    )
    observation_id = _decode_component(values["observation"], code)
    game_id = _decode_component(values["gameId"], code)
    if not re.fullmatch(r"obs-[1-9]\d{0,8}", observation_id):
        raise ui.UIBlocked(code)
    if not re.fullmatch(r"[0-9a-f]{32}", game_id) or set(game_id) == {"0"}:
        raise ui.UIBlocked(code)
    for field in ("page", "row"):
        if not re.fullmatch(r"\d{1,6}", values[field]):
            raise ui.UIBlocked(code)
    page = int(values["page"])
    row = int(values["row"])
    if page < 1 or not 1 <= row <= 999999:
        raise ui.UIBlocked(code)
    return LibraryRowObservation(
        observation_id=observation_id,
        page_ordinal=page,
        row_ordinal=row,
        game_id=game_id,
        boundary_page_ordinal=boundary_page_ordinal,
        capture_ref=capture_ref,
    )


def _semantic_resource_kind(resource_id: str) -> tuple[str, str] | None:
    prefixes = (
        ("job", _JOB_RUN_PREFIX),
        ("scan", _SCAN_RUN_PREFIX),
        ("root", _LIBRARY_ROOT_PREFIX),
    )
    for kind, prefix in prefixes:
        if resource_id.startswith(prefix):
            code = f"The {kind} resource identity is malformed."
            return kind, _typed_resource_reference(resource_id, prefix, code)
    return None


def _lifecycle_status(labels: tuple[str, ...]) -> str | None:
    candidates = [
        status
        for label in labels
        for status in _STATUS_LABELS
        if label == status or label == f"{status} (cancelling)"
    ]
    return candidates[0] if len(candidates) == 1 else None


def _semantic_facts(
    nodes: tuple[_AccessibilityNode, ...], surface: JobLifecycleSurface
) -> _SemanticFacts:
    identified: list[tuple[_AccessibilityNode, str, str]] = []
    for node in nodes:
        if node.resource_id is None:
            continue
        identity = _semantic_resource_kind(node.resource_id)
        if identity is not None:
            identified.append((node, *identity))

    job_nodes = tuple(item for item in identified if item[1] == "job")
    scan_nodes = tuple(item for item in identified if item[1] == "scan")
    root_nodes = tuple(item for item in identified if item[1] == "root")
    job_run_rows: list[JobRunRowObservation] = []
    for node, _, job_ref in job_nodes:
        local_labels = node.subtree_labels_without_nested_lifecycle_runs
        operations = set(local_labels).intersection(_JOB_OPERATIONS)
        status = _lifecycle_status(local_labels)
        if operations or status is not None:
            job_run_rows.append(JobRunRowObservation(
                job_run_ref=job_ref,
                operation_label=(
                    next(iter(operations)) if len(operations) == 1 else None
                ),
                lifecycle_status=status,
            ))

    relations: list[ScanRunRelation] = []
    scan_screen_observations: list[ScanRunScreenObservation] = []
    for node, _, scan_ref in scan_nodes:
        parent_refs = tuple(
            _typed_resource_reference(
                value,
                _JOB_RUN_PREFIX,
                "ScanRun parent identity is malformed.",
            )
            for value in node.ancestor_resource_ids
            if value.startswith(_JOB_RUN_PREFIX)
        )
        root_refs = tuple(
            _typed_resource_reference(
                value,
                _LIBRARY_ROOT_PREFIX,
                "ScanRun root identity is malformed.",
            )
            for value in node.ancestor_resource_ids + node.descendant_resource_ids
            if value.startswith(_LIBRARY_ROOT_PREFIX)
        )
        if len(set(parent_refs)) != 1 or len(set(root_refs)) != 1:
            raise ui.UIBlocked(
                "A ScanRun is not bound to one parent JobRun and LibraryRoot."
            )
        relation = ScanRunRelation(
            scan_run_ref=scan_ref,
            parent_run_ref=parent_refs[0],
            root_ref=root_refs[0],
        )
        if not relation.established():
            raise ui.UIBlocked("A ScanRun relationship is incomplete.")
        statuses = tuple(
            label
            for label in node.subtree_labels_without_nested_lifecycle_runs
            if label in _SCAN_STATUS_LABELS
        )
        scan_status = statuses[0] if len(statuses) == 1 else None
        relations.append(relation)
        scan_screen_observations.append(
            ScanRunScreenObservation(relation, scan_status)
        )
    if len({item.scan_run_ref for item in relations}) != len(relations):
        raise ui.UIBlocked("The hierarchy contains duplicate ScanRun identities.")

    all_root_refs = tuple(root_ref for _, _, root_ref in root_nodes)
    if len(set(all_root_refs)) != len(all_root_refs):
        raise ui.UIBlocked("The hierarchy contains duplicate LibraryRoot identities.")

    root_exclusions: list[RootExclusionObservation] = []
    for node, _, root_ref in root_nodes:
        nested_scans = tuple(
            resource_id
            for resource_id in node.descendant_resource_ids
            if resource_id.startswith(_SCAN_RUN_PREFIX)
        )
        if surface is not JobLifecycleSurface.REFRESH_DETAIL or nested_scans:
            continue
        if "Library folder" not in node.subtree_labels:
            continue
        reasons = set(node.subtree_labels).intersection(_EXCLUSION_REASONS)
        reason = (
            _EXCLUSION_REASONS[next(iter(reasons))]
            if len(reasons) == 1
            else None
        )
        root_exclusions.append(RootExclusionObservation(root_ref, reason))

    parent_refs: set[str] = set()
    refresh_parent_nodes: list[_AccessibilityNode] = []
    if surface is JobLifecycleSurface.REFRESH_DETAIL:
        for node, _, job_ref in job_nodes:
            local_labels = node.subtree_labels_without_nested_job_runs
            if "Library Refresh" in local_labels:
                parent_refs.add(job_ref)
                refresh_parent_nodes.append(node)
    elif surface is JobLifecycleSurface.SCAN_ROOT_DETAIL:
        parent_refs.update(item.parent_run_ref for item in relations)
    if len(parent_refs) > 1:
        raise ui.UIBlocked(
            "The detail hierarchy contains conflicting parent JobRun identities."
        )

    view_job_refs = tuple(
        job_ref
        for node, _, job_ref in job_nodes
        if "View Job" in node.subtree_labels_without_nested_job_runs
    )
    if len(view_job_refs) > 1:
        raise ui.UIBlocked("The View Job target identity is ambiguous.")
    view_job_run_ref = view_job_refs[0] if view_job_refs else None

    retry_links: dict[str, list[str]] = {"Retried from": [], "Retried as": []}
    for node, _, job_ref in job_nodes:
        direct_labels = node.labels
        if set(direct_labels).intersection(_JOB_OPERATIONS):
            continue
        for label, refs in retry_links.items():
            if label in direct_labels:
                refs.append(job_ref)
    if any(len(refs) > 1 for refs in retry_links.values()):
        raise ui.UIBlocked("Retry source or successor identity is ambiguous.")

    coverage_labels = {
        label
        for node in refresh_parent_nodes
        for label in node.subtree_labels_without_nested_job_runs
    }
    has_complete_coverage = _ROOT_COVERAGE_COMPLETE in coverage_labels
    has_unavailable_coverage = _ROOT_COVERAGE_UNAVAILABLE in coverage_labels
    if has_complete_coverage and has_unavailable_coverage:
        raise ui.UIBlocked("Root outcome coverage is contradictory.")
    coverage_complete = (
        True if has_complete_coverage
        else False if has_unavailable_coverage
        else None
    )

    return _SemanticFacts(
        job_run_rows=tuple(job_run_rows),
        parent_run_ref=next(iter(parent_refs)) if parent_refs else None,
        view_job_run_ref=view_job_run_ref,
        scan_run_relations=tuple(relations),
        scan_run_screen_observations=tuple(scan_screen_observations),
        root_refs=all_root_refs,
        excluded_root_refs=tuple(item.root_ref for item in root_exclusions),
        root_exclusions=tuple(root_exclusions),
        retry_source_run_ref=(
            retry_links["Retried from"][0] if retry_links["Retried from"] else None
        ),
        retry_successor_run_ref=(
            retry_links["Retried as"][0] if retry_links["Retried as"] else None
        ),
        root_outcome_coverage_complete=coverage_complete,
    )


def _node_label_groups(
    xml: str, expected_package: str
) -> tuple[tuple[str, ...], ...]:
    """Return bounded visible labels for each node of the expected application."""
    return tuple(node.labels for node in _accessibility_nodes(xml, expected_package))


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


def _control_count(
    groups: tuple[tuple[str, ...], ...],
    *,
    label: str,
    accessibility_nodes: tuple[_AccessibilityNode, ...],
) -> int:
    """Count one uniquely represented, actionable control or fail closed."""
    occurrences = sum(group.count(label) for group in groups)
    matches = [node for node in accessibility_nodes if node.labels.count(label) == 1]
    if occurrences > 1 or len(matches) > 1:
        return max(2, occurrences, len(matches))
    if occurrences != 1:
        return 0
    if len(matches) != 1:
        return 0
    node = matches[0]
    return int(node.enabled and node.clickable)


def _jobs_page_structure_is_verified(
    accessibility_nodes: tuple[_AccessibilityNode, ...],
    groups: tuple[tuple[str, ...], ...],
) -> bool:
    """Require a selected Jobs destination and a separate page title."""
    jobs_groups = [group for group in groups if "Jobs" in group]
    jobs_nodes = [node for node in accessibility_nodes if "Jobs" in node.labels]
    if (
        len(jobs_groups) != 2
        or any(group.count("Jobs") != 1 for group in jobs_groups)
        or len(jobs_nodes) != 2
    ):
        return False
    selected = [node for node in jobs_nodes if node.selected]
    heading = [node for node in jobs_nodes if not node.selected]
    if (
        len(selected) != 1
        or not selected[0].enabled
        or not selected[0].clickable
        or len(heading) != 1
        or not heading[0].enabled
        or heading[0].clickable
    ):
        return False
    return True


def _jobs_content_is_verified(
    groups: tuple[tuple[str, ...], ...],
    accessibility_nodes: tuple[_AccessibilityNode, ...],
) -> bool:
    """Require coherent Jobs content after page structure is verified."""
    content_markers = ("Active", "Recent", "No jobs yet")
    marker_groups = [
        group
        for group in groups
        if any(marker in group for marker in content_markers)
    ]
    if not marker_groups or any(
        sum(group.count(marker) for group in groups) > 1
        for marker in content_markers
    ):
        return False
    if any(
        group not in {("Active",), ("Recent",), ("No jobs yet",)}
        for group in marker_groups
    ):
        return False

    lifecycle_titles = ("Library Refresh", "Library Scan")
    lifecycle_row_groups = [
        group for group in groups if any(title in group for title in lifecycle_titles)
    ]
    semantic_rows = tuple(
        node
        for node in accessibility_nodes
        if node.resource_id is not None
        and node.resource_id.startswith(_JOB_RUN_PREFIX)
        and not any(
            child_id.startswith(_JOB_RUN_PREFIX)
            for child_id in node.descendant_resource_ids
        )
    )
    if semantic_rows:
        semantic_row_refs = tuple(
            _typed_resource_reference(
                node.resource_id,
                _JOB_RUN_PREFIX,
                "Jobs row identity is malformed.",
            )
            for node in semantic_rows
            if node.resource_id is not None
        )
        row_title_count = sum(
            sum(node.subtree_labels.count(title) for title in lifecycle_titles)
            for node in semantic_rows
        )
        visible_title_count = sum(
            group.count(title) for group in groups for title in lifecycle_titles
        )
        row_status_count = sum(
            sum(label in _STATUS_LABELS for label in node.subtree_labels)
            for node in semantic_rows
        )
        visible_status_count = sum(
            label in _STATUS_LABELS for group in groups for label in group
        )
        if (
            len(set(semantic_row_refs)) == len(semantic_rows)
            and all(
                sum(node.subtree_labels.count(title) for title in lifecycle_titles) == 1
                and sum(label in _STATUS_LABELS for label in node.subtree_labels) == 1
                for node in semantic_rows
            )
            and row_title_count == visible_title_count
            and row_status_count == visible_status_count
        ):
            return all(
                group in {("Active",), ("Recent",)} for group in marker_groups
            )
        return False
    if lifecycle_row_groups:
        return False

    return len(marker_groups) == 1 and marker_groups[0] == ("No jobs yet",)


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
    capture_ref = uuid4().hex
    accessibility_nodes = _accessibility_nodes(xml, expected_package)
    label_groups = tuple(node.labels for node in accessibility_nodes)
    if any(
        ui._LABELS.get(label) == "product_failure"
        for node in accessibility_nodes
        for label in node.labels
    ):
        raise ui.UIFailed("The Release UI reports a product operation failure.")
    library_pages: list[LibraryPageObservation] = []
    library_rows: list[LibraryRowObservation] = []
    for node in accessibility_nodes:
        resource_id = node.resource_id
        if resource_id is None:
            continue
        if resource_id.startswith("argus.library.page.v1"):
            library_pages.append(
                _parse_library_page_identifier(resource_id, capture_ref=capture_ref)
            )
        elif resource_id.startswith("argus.library.row.v1"):
            page_ancestors = tuple(
                ancestor
                for ancestor in node.ancestor_resource_ids
                if ancestor.startswith(_LIBRARY_PAGE_PREFIX)
            )
            if len(page_ancestors) > 1:
                raise ui.UIBlocked("A Library row has ambiguous page boundaries.")
            boundary_page_ordinal = (
                _parse_library_page_identifier(
                    page_ancestors[0], capture_ref=capture_ref
                ).page_ordinal
                if page_ancestors
                else None
            )
            library_rows.append(
                _parse_library_row_identifier(
                    resource_id,
                    capture_ref=capture_ref,
                    boundary_page_ordinal=boundary_page_ordinal,
                )
            )
    labels = tuple(label for group in label_groups for label in group)
    label_set = frozenset(labels)
    jobs_markers = tuple(
        marker for marker in ("Active", "Recent", "No jobs yet") if marker in label_set
    )
    progress = _parse_progress(labels)
    has_last_scan = any(_LAST_SCAN_RE.fullmatch(label) for label in labels)
    has_refresh_title = "Library Refresh" in label_set
    has_scan_title = "Library Scan" in label_set
    has_source_scan_identity = all(
        any(
            node.resource_id is not None
            and node.resource_id.startswith(prefix)
            for node in accessibility_nodes
        )
        for prefix in (_LIBRARY_ROOT_PREFIX, _JOB_RUN_PREFIX, _SCAN_RUN_PREFIX)
    )
    has_retry_relation = (
        "Retried from" in label_set or "Retried as" in label_set
    )
    jobs_page_structure = _jobs_page_structure_is_verified(
        accessibility_nodes, label_groups
    )
    if jobs_page_structure and not jobs_markers:
        raise ui.UIBlocked("The Jobs page content marker is unavailable.")
    if jobs_markers and (
        not jobs_page_structure
        or not _jobs_content_is_verified(label_groups, accessibility_nodes)
    ):
        raise ui.UIBlocked("The Jobs destination and page structure are ambiguous.")
    if jobs_markers:
        surface = JobLifecycleSurface.JOBS
    elif "View Job" in label_set and (
        has_last_scan
        or ("Scanning in progress" in label_set and has_source_scan_identity)
    ):
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

    semantic_facts = _semantic_facts(accessibility_nodes, surface)

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
        lifecycle_status = statuses[0] if len(statuses) == 1 else None

    scan_statuses = [label for label in labels if label in _SCAN_STATUS_LABELS]
    scan_child_status = scan_statuses[0] if len(set(scan_statuses)) == 1 else None
    last_scan_states = [
        match.group(1) for label in labels if (match := _LAST_SCAN_RE.fullmatch(label))
    ]
    root_state = last_scan_states[0] if len(set(last_scan_states)) == 1 else None
    root_scan_active = "Scanning in progress" in label_set
    if root_scan_active and last_scan_states:
        raise ui.UIBlocked("Sources root scan state is contradictory.")
    library_navigation_count = _control_count(
        label_groups,
        label="Library",
        accessibility_nodes=accessibility_nodes,
    )
    jobs_navigation_count = _control_count(
        label_groups,
        label="Jobs",
        accessibility_nodes=accessibility_nodes,
    )
    sources_navigation_count = _control_count(
        label_groups,
        label="Sources",
        accessibility_nodes=accessibility_nodes,
    )
    refresh_control_count = _control_count(
        label_groups,
        label="Refresh Library",
        accessibility_nodes=accessibility_nodes,
    )
    retry_control_count = _control_count(
        label_groups,
        label="Retry",
        accessibility_nodes=accessibility_nodes,
    )
    view_job_count = _control_count(
        label_groups,
        label="View Job",
        accessibility_nodes=accessibility_nodes,
    )
    return JobLifecycleScreenObservation(
        surface=surface,
        lifecycle_status=lifecycle_status,
        progress=progress,
        jobs_arrival_marker=jobs_markers[0] if len(jobs_markers) == 1 else None,
        visible_refresh_row_count=refresh_rows,
        active_refresh_row_count=active_refresh_rows,
        library_navigation_present=library_navigation_count == 1,
        jobs_navigation_present=(
            surface is JobLifecycleSurface.JOBS
            or jobs_navigation_count == 1
        ),
        sources_navigation_present=sources_navigation_count == 1,
        refresh_control_present=refresh_control_count == 1,
        retry_control_count=retry_control_count,
        view_job_control_count=view_job_count,
        root_last_scan=root_state,
        root_scan_active=root_scan_active if surface is JobLifecycleSurface.SCAN_ROOT_DETAIL else None,
        cancellation_requested="Cancelling…" in label_set,
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
        library_pages=tuple(library_pages),
        library_rows=tuple(library_rows),
        job_run_rows=semantic_facts.job_run_rows,
        parent_run_ref=semantic_facts.parent_run_ref,
        scan_run_relations=semantic_facts.scan_run_relations,
        scan_run_screen_observations=semantic_facts.scan_run_screen_observations,
        root_refs=semantic_facts.root_refs,
        excluded_root_refs=semantic_facts.excluded_root_refs,
        root_exclusions=semantic_facts.root_exclusions,
        retry_source_run_ref=semantic_facts.retry_source_run_ref,
        retry_successor_run_ref=semantic_facts.retry_successor_run_ref,
        root_outcome_coverage_complete=semantic_facts.root_outcome_coverage_complete,
        view_job_run_ref=(
            semantic_facts.view_job_run_ref
            if surface is JobLifecycleSurface.SCAN_ROOT_DETAIL
            and view_job_count == 1
            else None
        ),
        capture_ref=capture_ref,
    )


def _verify_refresh_root_scope(
    observation: JobLifecycleScreenObservation,
    identity: JobIdentityObservation,
) -> None:
    """Cross-check every rendered root outcome against independent identity."""
    if (
        type(observation) is not JobLifecycleScreenObservation
        or observation.surface is not JobLifecycleSurface.REFRESH_DETAIL
        or type(identity) is not JobIdentityObservation
        or not identity.parent_identity_complete()
        or not identity.scan_relationships_complete()
        or observation.root_outcome_coverage_complete is not True
    ):
        raise ui.UIBlocked("Complete refresh root coverage is unavailable.")
    if (
        type(observation.root_refs) is not tuple
        or any(not _valid_reference(ref) for ref in observation.root_refs)
        or type(observation.excluded_root_refs) is not tuple
        or any(
            not _valid_reference(ref) for ref in observation.excluded_root_refs
        )
        or type(observation.scan_run_relations) is not tuple
        or any(
            type(relation) is not ScanRunRelation
            or not _valid_reference(relation.scan_run_ref)
            or not _valid_reference(relation.parent_run_ref)
            or not _valid_reference(relation.root_ref)
            or not relation.established()
            for relation in observation.scan_run_relations
        )
        or type(observation.root_exclusions) is not tuple
        or any(
            type(exclusion) is not RootExclusionObservation
            or not _valid_reference(exclusion.root_ref)
            or not exclusion.established()
            for exclusion in observation.root_exclusions
        )
    ):
        raise ui.UIBlocked("Refresh detail root scope evidence is malformed.")
    exclusion_refs = tuple(
        exclusion.root_ref for exclusion in observation.root_exclusions
    )
    if (
        len(set(exclusion_refs)) != len(exclusion_refs)
        or set(exclusion_refs) != set(observation.excluded_root_refs)
    ):
        raise ui.UIBlocked(
            "Root exclusion identities do not match the frozen excluded-root set."
        )
    if (
        observation.parent_run_ref != identity.parent_run_ref
        or set(observation.root_refs) != set(identity.requested_root_refs or ())
        or set(observation.excluded_root_refs)
        != set(identity.excluded_root_refs or ())
        or set(observation.scan_run_relations)
        != set(identity.scan_run_relations or ())
        or any(not exclusion.established() for exclusion in observation.root_exclusions)
    ):
        raise ui.UIBlocked("Rendered root outcomes do not match the frozen job scope.")
    admitted_roots = {
        relation.root_ref for relation in observation.scan_run_relations
    }
    excluded_roots = set(observation.excluded_root_refs)
    if (
        admitted_roots != set(identity.admitted_root_refs or ())
        or admitted_roots.intersection(excluded_roots)
        or admitted_roots.union(excluded_roots)
        != set(identity.requested_root_refs or ())
    ):
        raise ui.UIBlocked("Rendered root partition is incomplete or conflicting.")


def _verify_scan_root_identity(
    observation: JobLifecycleScreenObservation,
    identity: JobIdentityObservation,
) -> ScanRunRelation:
    if (
        type(observation) is not JobLifecycleScreenObservation
        or observation.surface is not JobLifecycleSurface.SCAN_ROOT_DETAIL
        or type(identity) is not JobIdentityObservation
        or not identity.parent_identity_complete()
        or not identity.scan_relationships_complete()
        or len(observation.root_refs) != 1
        or len(observation.scan_run_relations) != 1
        or observation.view_job_control_count != 1
    ):
        raise ui.UIBlocked("Sources root ownership or View Job identity is unavailable.")
    relation = observation.scan_run_relations[0]
    if (
        relation not in (identity.scan_run_relations or ())
        or relation.root_ref != observation.root_refs[0]
        or relation.root_ref not in (identity.requested_root_refs or ())
        or observation.view_job_run_ref != relation.parent_run_ref
    ):
        raise ui.UIBlocked("Sources root does not identify its owning ScanRun and JobRun.")
    return relation


def adapt_jobs_surface_observation(
    observation: object, *, observer_ref: object
) -> JobsSurfaceObservation:
    """Project visible Jobs rows without treating a visible subset as history."""
    if (
        type(observation) is not JobLifecycleScreenObservation
        or observation.surface is not JobLifecycleSurface.JOBS
        or type(observer_ref) is not str
        or not _valid_reference(observer_ref)
    ):
        raise ui.UIBlocked("A verified Jobs surface and observer are required.")
    if type(observation.cancellation_requested) is not bool:
        raise ui.UIBlocked("Jobs cancellation status evidence is malformed.")
    if observation.cancellation_requested:
        raise ui.UIBlocked(
            "Jobs state cannot represent a refresh cancellation request."
        )
    if (
        type(observation.job_run_rows) is not tuple
        or any(
            type(row) is not JobRunRowObservation
            or not _valid_reference(row.job_run_ref)
            or (
                row.operation_label is not None
                and (
                    type(row.operation_label) is not str
                    or row.operation_label not in _JOB_OPERATIONS
                )
            )
            or (
                row.lifecycle_status is not None
                and (
                    type(row.lifecycle_status) is not str
                    or row.lifecycle_status not in _STATUS_LABELS
                )
            )
            for row in observation.job_run_rows
        )
    ):
        raise ui.UIBlocked("Jobs row identity or status evidence is malformed.")
    if len({row.job_run_ref for row in observation.job_run_rows}) != len(
        observation.job_run_rows
    ):
        raise ui.UIBlocked("Jobs rows contain duplicate JobRun identities.")
    refresh_rows = tuple(
        row for row in observation.job_run_rows
        if row.operation_label == "Library Refresh"
    )
    statuses = tuple(
        _RECOVERY_STATES.get(row.lifecycle_status) for row in refresh_rows
    )
    active_count = (
        sum(state is RecoveryState.ACTIVE for state in statuses)
        if all(state is not None for state in statuses)
        else None
    )
    active_rows = tuple(
        row
        for row, state in zip(refresh_rows, statuses, strict=True)
        if state is RecoveryState.ACTIVE
    )
    terminal_rows = tuple(
        row
        for row, state in zip(refresh_rows, statuses, strict=True)
        if state in {
            RecoveryState.COMPLETED,
            RecoveryState.COMPLETED_WITH_ISSUES,
            RecoveryState.FAILED,
            RecoveryState.CANCELLED,
            RecoveryState.INTERRUPTED,
            RecoveryState.ABANDONED,
        }
    )
    state_values = {state for state in statuses if state is not None}
    return JobsSurfaceObservation(
        surface=JobLifecycleSurface.JOBS,
        parent_run_ref=(
            active_rows[0].job_run_ref if len(active_rows) == 1 else None
        ),
        state=next(iter(state_values)) if len(state_values) == 1 else None,
        refresh_row_count=len(refresh_rows),
        active_refresh_row_count=active_count,
        jobs_navigation_present=observation.jobs_navigation_present,
        observer_ref=observer_ref,
        history_complete=False,
        terminal_refresh_run_refs=tuple(row.job_run_ref for row in terminal_rows),
    )


def adapt_refresh_detail_observation(
    observation: object,
    *,
    identity: object,
    observer_ref: object,
) -> RefreshDetailObservation:
    """Project a refresh detail only after its root scope matches independent identity."""
    if (
        type(observation) is not JobLifecycleScreenObservation
        or type(identity) is not JobIdentityObservation
        or type(observer_ref) is not str
        or not _valid_reference(observer_ref)
    ):
        raise ui.UIBlocked("A verified refresh detail and observer are required.")
    if (
        type(observation.job_run_rows) is not tuple
        or any(
            type(row) is not JobRunRowObservation
            for row in observation.job_run_rows
        )
    ):
        raise ui.UIBlocked("Refresh detail JobRun status evidence is malformed.")
    _verify_refresh_root_scope(observation, identity)
    parent_rows = tuple(
        row
        for row in observation.job_run_rows
        if row.job_run_ref == observation.parent_run_ref
    )
    if (
        len(parent_rows) != 1
        or parent_rows[0].operation_label != "Library Refresh"
        or type(observation.lifecycle_status) is not str
        or type(parent_rows[0].lifecycle_status) is not str
        or parent_rows[0].lifecycle_status != observation.lifecycle_status
    ):
        raise ui.UIBlocked(
            "Refresh status is not uniquely bound to its parent JobRun."
        )
    state = _RECOVERY_STATES.get(observation.lifecycle_status)
    if (
        not _valid_reference(observation.parent_run_ref)
        or type(state) is not RecoveryState
        or type(observation.progress) is not RefreshProgressFacts
        or type(observation.retry_control_count) is not int
        or type(observation.cancellation_requested) is not bool
    ):
        raise ui.UIBlocked("Refresh detail identity, state, or progress is incomplete.")
    return RefreshDetailObservation(
        parent_run_ref=observation.parent_run_ref,
        state=state,
        progress=observation.progress,
        retry_control_count=observation.retry_control_count,
        retry_source_run_ref=observation.retry_source_run_ref,
        retry_successor_run_ref=observation.retry_successor_run_ref,
        cancellation_requested=observation.cancellation_requested,
        observer_ref=observer_ref,
    )


def adapt_scan_run_observation(
    observation: object,
    relation: object,
    *,
    identity: object,
    observer_ref: object,
) -> ScanRunObservation:
    """Map one nested ScanRun status after its parent/root scope is verified."""
    if (
        type(observation) is not JobLifecycleScreenObservation
        or type(identity) is not JobIdentityObservation
        or type(relation) is not ScanRunRelation
        or not _valid_reference(relation.scan_run_ref)
        or not _valid_reference(relation.parent_run_ref)
        or not _valid_reference(relation.root_ref)
        or not relation.established()
        or type(observer_ref) is not str
        or not _valid_reference(observer_ref)
    ):
        raise ui.UIBlocked("A typed ScanRun relationship and observer are required.")
    _verify_refresh_root_scope(observation, identity)
    if (
        type(observation.scan_run_screen_observations) is not tuple
        or any(
            type(item) is not ScanRunScreenObservation
            or type(item.relation) is not ScanRunRelation
            or not _valid_reference(item.relation.scan_run_ref)
            or not _valid_reference(item.relation.parent_run_ref)
            or not _valid_reference(item.relation.root_ref)
            or not item.relation.established()
            or (
                item.lifecycle_status is not None
                and type(item.lifecycle_status) is not str
            )
            for item in observation.scan_run_screen_observations
        )
    ):
        raise ui.UIBlocked("ScanRun status evidence is malformed.")
    screen_scans = tuple(
        item
        for item in observation.scan_run_screen_observations
        if item.relation == relation
    )
    if len(screen_scans) != 1:
        raise ui.UIBlocked("ScanRun status is missing or duplicated.")
    screen_scan = screen_scans[0]
    state = identity.parent_state
    status = (
        None
        if screen_scan is None or screen_scan.lifecycle_status is None
        else screen_scan.lifecycle_status.lower()
    )
    if (
        screen_scan is None
        or type(state) is not RecoveryState
        or status not in ROOT_HISTORICAL_SCAN_STATES | {"scanning"}
    ):
        raise ui.UIBlocked("ScanRun status or independent parent state is incomplete.")
    return ScanRunObservation(
        surface=JobLifecycleSurface.REFRESH_DETAIL,
        parent_run_ref=relation.parent_run_ref,
        scan_run_ref=relation.scan_run_ref,
        root_ref=relation.root_ref,
        parent_state=state,
        scan_state=status,
        observer_ref=observer_ref,
    )


def adapt_scan_root_observation(
    observation: object,
    *,
    identity: object,
    observer_ref: object,
) -> ScanRootObservation:
    """Map Sources root ownership while keeping View Job and ScanRun IDs distinct."""
    if (
        type(observation) is not JobLifecycleScreenObservation
        or type(identity) is not JobIdentityObservation
        or type(observer_ref) is not str
        or not _valid_reference(observer_ref)
    ):
        raise ui.UIBlocked("A verified Sources root and observer are required.")
    if type(observation.root_scan_active) is not bool:
        raise ui.UIBlocked("Sources root activity state is malformed.")
    relation = _verify_scan_root_identity(observation, identity)
    if observation.root_scan_active is True:
        if observation.root_last_scan is not None:
            raise ui.UIBlocked("Active scan evidence conflicts with root history.")
        presentation = ScanRootPresentation.ACTIVE_SCAN
        last_scan_state = None
    elif (
        type(observation.root_last_scan) is str
        and observation.root_last_scan in ROOT_HISTORICAL_SCAN_STATES
    ):
        presentation = ScanRootPresentation.HISTORICAL_LAST_SCAN
        last_scan_state = observation.root_last_scan
    else:
        raise ui.UIBlocked("Sources root history does not identify an active or known scan.")
    return ScanRootObservation(
        surface=JobLifecycleSurface.SCAN_ROOT_DETAIL,
        root_ref=relation.root_ref,
        last_scan_state=last_scan_state,
        view_job_control_count=observation.view_job_control_count,
        view_job_run_ref=observation.view_job_run_ref,
        observer_ref=observer_ref,
        presentation=presentation,
        scan_run_ref=relation.scan_run_ref,
        scan_parent_run_ref=relation.parent_run_ref,
    )


def adapt_library_surface_observation(
    observation: object,
    *,
    refresh_active: object,
    observer_ref: object,
) -> LibrarySurfaceObservation:
    """Build contract v5 membership facts from one complete hierarchy capture.

    Page identifiers are application observations, not process-lifetime proof.
    This adapter accepts one parser result only and rejects facts whose
    in-memory capture references differ, even when their ``obs-N`` values
    match. It never performs navigation, scrolling, or device capture.
    """
    if (
        type(observation) is not JobLifecycleScreenObservation
        or observation.surface is not JobLifecycleSurface.LIBRARY
        or not _valid_reference(observation.capture_ref)
    ):
        raise ui.UIBlocked("One verified Library hierarchy capture is required.")
    if (
        type(refresh_active) is not bool
        or type(observer_ref) is not str
        or not _valid_reference(observer_ref)
        or observation.refresh_control_present is not True
    ):
        raise ui.UIBlocked("Library observation provenance or controls are incomplete.")

    pages = observation.library_pages
    rows = observation.library_rows
    if (
        type(pages) is not tuple
        or not pages
        or len(pages) > 10000
        or type(rows) is not tuple
    ):
        raise ui.UIBlocked("Library page coverage is unavailable.")
    if any(type(page) is not LibraryPageObservation for page in pages):
        raise ui.UIBlocked("Library page coverage is malformed.")
    if any(type(row) is not LibraryRowObservation for row in rows):
        raise ui.UIBlocked("Library row coverage is malformed.")

    observation_ids = {page.observation_id for page in pages}
    profiles = {page.query_profile for page in pages}
    if (
        len(observation_ids) != 1
        or profiles != {"AllActiveMembershipBaseline"}
        or any(row.observation_id not in observation_ids for row in rows)
        or any(page.capture_ref != observation.capture_ref for page in pages)
        or any(row.capture_ref != observation.capture_ref for row in rows)
    ):
        raise ui.UIBlocked("Library pages do not share one baseline capture.")

    page_ordinals = [page.page_ordinal for page in pages]
    if page_ordinals != list(range(1, len(pages) + 1)):
        raise ui.UIBlocked("Library page ordinals are incomplete or out of order.")

    rows_by_page: dict[int, list[LibraryRowObservation]] = {
        page.page_ordinal: [] for page in pages
    }
    for row in rows:
        if (
            row.page_ordinal not in rows_by_page
            or row.boundary_page_ordinal != row.page_ordinal
        ):
            raise ui.UIBlocked("A Library row has no page boundary.")
        rows_by_page[row.page_ordinal].append(row)

    ordered_game_ids: list[str] = []
    for index, page in enumerate(pages):
        last_page = index == len(pages) - 1
        if (
            page.status != "complete"
            or page.page_size != 50
            or type(page.expected_row_count) is not int
            or not 0 <= page.expected_row_count <= page.page_size
            or page.is_first_page is not (index == 0)
            or page.is_continuation_page is not (index > 0)
            or page.has_next_page is not (not last_page)
            or page.is_final_page is not last_page
        ):
            raise ui.UIBlocked("A Library page is incomplete or has conflicting boundaries.")
        page_rows = rows_by_page[page.page_ordinal]
        row_ordinals = [row.row_ordinal for row in page_rows]
        if (
            len(page_rows) != page.expected_row_count
            or row_ordinals != list(range(1, page.expected_row_count + 1))
        ):
            raise ui.UIBlocked("Visible Library rows do not cover the complete page.")
        ordered_game_ids.extend(row.game_id for row in page_rows)

    if (
        len(set(ordered_game_ids)) != len(ordered_game_ids)
        or any(not _valid_reference(game_id) for game_id in ordered_game_ids)
    ):
        raise ui.UIBlocked("Library GameId coverage is duplicate or malformed.")

    return LibrarySurfaceObservation(
        surface=JobLifecycleSurface.LIBRARY,
        membership_count=len(ordered_game_ids),
        refresh_control_present=True,
        refresh_active=refresh_active,
        observer_ref=observer_ref,
        membership_ids=tuple(ordered_game_ids),
        next_page_available=False,
        identity_continuity=None,
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
