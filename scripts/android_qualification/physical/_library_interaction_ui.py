"""Private Issue #27 observations layered over the shared Android UI parser.

The legacy UI module stays limited to shared allowlisted controls and fixture
identity tokens. This module owns Library-specific candidate classification,
row-order observations, and the fail-closed pagination guard. Raw accessibility
labels remain transient and are never copied into returned objects.
"""

from dataclasses import dataclass
import re
from typing import NoReturn
import xml.etree.ElementTree as ET

from . import ui


@dataclass(frozen=True)
class Issue27LibraryObservation:
    """One in-memory row order expressed only as fixture ordinals."""

    fixture_ordinals: tuple[int, ...]


def parse_issue27_library_ui(
    xml: str,
    *,
    expected_package: str = ui.QUALIFICATION_PACKAGE,
    library_expectations: tuple[ui.LibraryExpectation, ...],
) -> list[ui.Node]:
    """Add Issue #27-only Game-card candidates to the shared parsed surface.

    Every unfamiliar comma-labeled node is treated as a candidate because a
    partial accessibility signature cannot prove that it is an unrelated
    control. Only the complete title/platform, selected-state, tap, and
    long-press signature can establish an extra Game; incomplete candidates
    block membership. Raw labels remain transient and never enter returned
    Nodes.
    """
    expectations = tuple(library_expectations)
    if expected_package != ui.QUALIFICATION_PACKAGE:
        raise ui.UIBlocked("Issue #27 requires the isolated qualification application.")
    nodes = ui.parse_ui(
        xml,
        expected_package=expected_package,
        library_expectations=expectations,
    )
    try:
        root = ET.fromstring(xml)
    except (ET.ParseError, ValueError):
        raise ui.UIBlocked("Accessibility XML could not be parsed.") from None
    known_labels = dict(ui._LABELS)
    known_labels.update(ui._fixture_tokens(expectations))
    for index, element in enumerate(root.iter("node")):
        if index >= 10000:
            raise ui.UIBlocked("Accessibility node limit exceeded.")
        package = element.get("package", "")
        if package == "com.android.systemui":
            continue
        if package != expected_package:
            raise ui.UIBlocked(
                "A foreign or unidentified UI surface prevents selection."
            )
        if element.get("visible-to-user", "true") == "false":
            continue
        labels = tuple(dict.fromkeys(
            line for attribute in ("text", "content-desc")
            for line in element.get(attribute, "").splitlines()
            if line
        ))
        unfamiliar = tuple(
            label for label in labels
            if ", " in label and label not in known_labels
        )
        if not unfamiliar:
            continue
        game_labels = tuple(label for label in labels if ", " in label)
        bounds_match = re.fullmatch(
            r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]",
            element.get("bounds", ""),
        )
        if not bounds_match:
            raise ui.UIBlocked("Recognized control has invalid geometry.")
        bounds = tuple(map(int, bounds_match.groups()))
        left, top, right, bottom = bounds
        if right <= left or bottom <= top or max(bounds) > 32768:
            raise ui.UIBlocked("Recognized control has invalid geometry.")
        is_card_signature = (
            len(game_labels) == 1
            and len(unfamiliar) == 1
            and unfamiliar[0].count(", ") == 1
            and all(part.strip() for part in unfamiliar[0].split(", "))
            and element.get("selected") in {"true", "false"}
            and element.get("clickable") == "true"
            and element.get("long-clickable") == "true"
        )
        key = "unmatched_game" if is_card_signature else "ambiguous_game_candidate"
        nodes.append(ui.Node(
            key,
            bounds,
            element.get("enabled") == "true",
            element.get("clickable") == "true",
            element.get("selected") == "true",
        ))
    return nodes


def observe_issue27_fixture_library_results(
    nodes: list[ui.Node],
    expectations: tuple[ui.LibraryExpectation, ...],
) -> Issue27LibraryObservation:
    """Return Issue #27 fixture ordinals in the observed hierarchy order.

    Ordinals preserve row ordering without exposing fixture IDs, titles, or
    platform labels. A confirmed unexpected Game fails; an ambiguous candidate
    blocks the observation.
    """
    if not expectations:
        raise ui.UIBlocked("Independent fixture expectations are unavailable.")
    ui._fixture_tokens(expectations)
    if any(node.key == "unmatched_game" for node in nodes):
        raise ui.UIFailed("The Library exposes a Game row outside the pinned fixture identities.")
    if any(node.key == "ambiguous_game_candidate" for node in nodes):
        raise ui.UIBlocked("The Library exposes an ambiguous comma-labeled actionable control.")
    if any(node.key == "product_failure" for node in nodes):
        raise ui.UIFailed("The Release UI reports a product operation failure.")
    observed = []
    for node in nodes:
        match = re.fullmatch(r"fixture_result_(\d{3})", node.key)
        if match is None:
            continue
        ordinal = int(match.group(1))
        if ordinal >= len(expectations) or ordinal in observed:
            raise ui.UIBlocked("Fixture-specific Library results are ambiguous.")
        observed.append(ordinal)
    return Issue27LibraryObservation(tuple(observed))


def require_verified_fixture_library_exhaustion(
    nodes: list[ui.Node],
    expectations: tuple[ui.LibraryExpectation, ...],
    *,
    snapshots: tuple[tuple[int, ...], ...],
) -> NoReturn:
    """Fail closed until a pinned Release exposes a verified exhaustion signal.

    Repeated viewport snapshots do not establish exhaustion. The pinned
    Release accessibility contract has no verified traversal or backend
    pagination completion signal, so this guard never claims completeness.
    """
    visible = observe_issue27_fixture_library_results(nodes, expectations)
    if (
        type(snapshots) is not tuple
        or not snapshots
        or any(type(snapshot) is not tuple for snapshot in snapshots)
        or any(type(index) is not int for snapshot in snapshots for index in snapshot)
        or any(
            len(set(snapshot)) != len(snapshot)
            or any(index < 0 or index >= len(expectations) for index in snapshot)
            for snapshot in snapshots
        )
        or snapshots[-1] != visible.fixture_ordinals
    ):
        raise ui.UIBlocked("Library traversal evidence is incomplete or ambiguous.")
    if len(snapshots) > 1 and snapshots[-1] == snapshots[-2]:
        raise ui.UIBlocked("A repeated last-row observation does not prove Library exhaustion.")
    raise ui.UIBlocked(
        "The pinned Release accessibility contract does not prove complete Library traversal and pagination."
    )
