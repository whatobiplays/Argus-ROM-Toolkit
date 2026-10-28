"""Versioned manifest parsing and fixture selection rules."""

from __future__ import annotations

import hashlib
import json
import re
import unicodedata
from pathlib import Path, PurePosixPath
from types import MappingProxyType
from typing import Mapping, Sequence

from scripts.android_qualification import fixture_oracle
from scripts.android_qualification.fixture_staging_contract import (
    FixtureCompanion,
    FixtureFile,
    FixturePlan,
    FixtureSpec,
    _StagingFailure,
)
from scripts.android_qualification.fixture_staging_files import _open_readonly


FIXTURE_MANIFEST_SCHEMA_VERSION = 2

MAX_MANIFEST_BYTES = 32 * 1024 * 1024

_SHA256 = re.compile(r"[0-9a-f]{64}\Z")

def _pairs(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise _StagingFailure("MANIFEST_INVALID")
        result[key] = value
    return result

def _reject_number(_value: str) -> None:
    raise _StagingFailure("MANIFEST_INVALID")

def _document(value: object) -> dict[str, object]:
    if isinstance(value, (Path, str)):
        try:
            with _open_readonly(Path(value).expanduser()) as reader:
                encoded = reader.read(MAX_MANIFEST_BYTES + 1)
        except OSError:
            raise _StagingFailure("MANIFEST_UNAVAILABLE") from None
    elif isinstance(value, bytes):
        encoded = value
    elif isinstance(value, Mapping):
        try:
            encoded = json.dumps(
                value, ensure_ascii=False, sort_keys=True,
                separators=(",", ":"), allow_nan=False,
            ).encode("utf-8")
        except (TypeError, ValueError, UnicodeEncodeError, RecursionError):
            raise _StagingFailure("MANIFEST_INVALID") from None
    else:
        raise _StagingFailure("MANIFEST_INVALID")
    if len(encoded) > MAX_MANIFEST_BYTES:
        raise _StagingFailure("MANIFEST_TOO_LARGE")
    try:
        document = json.loads(
            encoded.decode("utf-8"),
            object_pairs_hook=_pairs,
            parse_float=_reject_number,
            parse_constant=_reject_number,
        )
    except _StagingFailure:
        raise
    except (UnicodeError, ValueError, RecursionError):
        raise _StagingFailure("MANIFEST_INVALID") from None
    if type(document) is not dict:
        raise _StagingFailure("MANIFEST_INVALID")
    return document

def _canonical_json(document: object) -> bytes:
    try:
        return json.dumps(
            document, ensure_ascii=False, sort_keys=True,
            separators=(",", ":"), allow_nan=False,
        ).encode("utf-8")
    except (TypeError, ValueError, UnicodeEncodeError, RecursionError):
        raise _StagingFailure("MANIFEST_INVALID") from None

def _text(value: object, *, limit: int = 512) -> str:
    if (
        type(value) is not str or not value or len(value) > limit
        or value != value.strip()
        or any(unicodedata.category(char) == "Cc" for char in value)
        or unicodedata.normalize("NFC", value) != value
    ):
        raise _StagingFailure("MANIFEST_INVALID")
    return value

def _identifier(value: object) -> str:
    text = _text(value, limit=128)
    if text in {".", ".."} or any(char in text for char in "/\\:"):
        raise _StagingFailure("MANIFEST_INVALID")
    return text

def _relative_path(value: object) -> str:
    text = _text(value, limit=4096)
    path = PurePosixPath(text)
    if (
        path.is_absolute() or "\\" in text or ":" in text
        or any(part in {"", ".", ".."} for part in text.split("/"))
    ):
        raise _StagingFailure("MANIFEST_INVALID")
    return text

def _digest(value: object) -> str:
    if type(value) is not str or _SHA256.fullmatch(value) is None:
        raise _StagingFailure("MANIFEST_INVALID")
    return value

def _parse_manifest(value: object) -> FixturePlan:
    document = _document(value)
    if set(document) != {"schema_version", "coverage", "fixtures"}:
        raise _StagingFailure("MANIFEST_INVALID")
    if type(document["schema_version"]) is not int:
        raise _StagingFailure("MANIFEST_INVALID")
    if document["schema_version"] != FIXTURE_MANIFEST_SCHEMA_VERSION:
        raise _StagingFailure("SCHEMA_UNSUPPORTED")
    coverage = document["coverage"]
    if type(coverage) is not dict or set(coverage) != {
        "mode", "required_fixture_ids", "mandatory_fixture_ids"
    }:
        raise _StagingFailure("MANIFEST_INVALID")
    mode = _text(coverage["mode"], limit=64)
    if mode not in {"mandatory_full_plan", "authorized_partial_plan"}:
        raise _StagingFailure("MANIFEST_INVALID")
    required_value = coverage["required_fixture_ids"]
    mandatory_value = coverage["mandatory_fixture_ids"]
    if type(required_value) is not list or not required_value or type(mandatory_value) is not list:
        raise _StagingFailure("MANIFEST_INVALID")
    required = tuple(_identifier(item) for item in required_value)
    mandatory = tuple(_identifier(item) for item in mandatory_value)
    if len(set(required)) != len(required) or len(set(mandatory)) != len(mandatory):
        raise _StagingFailure("MANIFEST_INVALID")
    if any(item not in required for item in mandatory):
        raise _StagingFailure("MANIFEST_INVALID")
    raw_fixtures = document["fixtures"]
    if type(raw_fixtures) is not list or not raw_fixtures:
        raise _StagingFailure("MANIFEST_INVALID")
    fixtures: dict[str, FixtureSpec] = {}
    ordered_fixture_ids: list[str] = []
    for raw in raw_fixtures:
        if type(raw) is not dict or set(raw) != {
            "fixture_id", "group_id", "order", "platform", "representation",
            "entrypoint", "expected_identity", "structural_expectations",
            "files", "companions", "identity_evidence",
        }:
            raise _StagingFailure("MANIFEST_INVALID")
        fixture_id = _identifier(raw["fixture_id"])
        if fixture_id in fixtures:
            raise _StagingFailure("MANIFEST_INVALID")
        group_id = _identifier(raw["group_id"])
        fixture_order = raw["order"]
        if type(fixture_order) is not int or fixture_order < 0:
            raise _StagingFailure("MANIFEST_INVALID")
        platform = _text(raw["platform"], limit=256)
        representation = _text(raw["representation"], limit=256)
        entrypoint = _relative_path(raw["entrypoint"])
        identity = raw["expected_identity"]
        if type(identity) is not dict or not identity:
            raise _StagingFailure("MANIFEST_INVALID")
        for key, fact in identity.items():
            _text(key, limit=128)
            if type(fact) not in {str, int, bool} or (type(fact) is str and not fact):
                raise _StagingFailure("MANIFEST_INVALID")
        structural = raw["structural_expectations"]
        if type(structural) is not dict or not structural:
            raise _StagingFailure("MANIFEST_INVALID")
        for key, fact in structural.items():
            _text(key, limit=128)
            if type(fact) not in {str, int, bool} or (type(fact) is str and not fact):
                raise _StagingFailure("MANIFEST_INVALID")
        raw_files = raw["files"]
        if type(raw_files) is not list or not raw_files:
            raise _StagingFailure("MANIFEST_INVALID")
        files: list[FixtureFile] = []
        seen_paths: set[str] = set()
        folded_paths: set[str] = set()
        folded_components: dict[str, str] = {}
        for item in raw_files:
            if type(item) is not dict or set(item) != {"path", "role", "size", "sha256"}:
                raise _StagingFailure("MANIFEST_INVALID")
            path = _relative_path(item["path"])
            role = _text(item["role"], limit=64)
            size = item["size"]
            if type(size) is not int or size < 0:
                raise _StagingFailure("MANIFEST_INVALID")
            if path in seen_paths or path.casefold() in folded_paths:
                raise _StagingFailure("MANIFEST_INVALID")
            seen_paths.add(path)
            folded_paths.add(path.casefold())
            for index in range(1, len(path.split("/")) + 1):
                prefix = "/".join(path.split("/")[:index])
                prior = folded_components.setdefault(prefix.casefold(), prefix)
                if prior != prefix:
                    raise _StagingFailure("MANIFEST_INVALID")
            files.append(FixtureFile(
                path=path,
                role=role,
                size=size,
                sha256=_digest(item["sha256"]),
            ))
        if any(
            "/".join(path.split("/")[:index]) in seen_paths
            for path in seen_paths
            for index in range(1, len(path.split("/")))
        ):
            raise _StagingFailure("MANIFEST_INVALID")
        if entrypoint not in seen_paths:
            raise _StagingFailure("MANIFEST_INVALID")
        raw_edges = raw["companions"]
        if type(raw_edges) is not list:
            raise _StagingFailure("MANIFEST_INVALID")
        edges: list[FixtureCompanion] = []
        edge_set: set[tuple[str, str]] = set()
        adjacency = {path: [] for path in seen_paths}
        for edge in raw_edges:
            if type(edge) is not dict or set(edge) != {"source", "target"}:
                raise _StagingFailure("MANIFEST_INVALID")
            source = _relative_path(edge["source"])
            target = _relative_path(edge["target"])
            if source not in seen_paths or target not in seen_paths or (source, target) in edge_set:
                raise _StagingFailure("MANIFEST_INVALID")
            edge_set.add((source, target))
            edges.append(FixtureCompanion(source=source, target=target))
            adjacency[source].append(target)
        if not _graph_reaches_all(entrypoint, seen_paths, adjacency):
            raise _StagingFailure("MANIFEST_INVALID")
        evidence = raw["identity_evidence"]
        try:
            identity_assessment = fixture_oracle.assess_identity_evidence(identity, evidence)
        except fixture_oracle.OracleError:
            raise _StagingFailure("MANIFEST_INVALID")
        fixtures[fixture_id] = FixtureSpec(
            fixture_id=fixture_id,
            group_id=group_id,
            order=fixture_order,
            platform=platform,
            representation=representation,
            entrypoint=entrypoint,
            expected_identity=MappingProxyType(identity),
            structural_expectations=MappingProxyType(structural),
            files=tuple(files),
            companions=tuple(edges),
            identity_evidence=(
                MappingProxyType(evidence) if evidence is not None else None
            ),
            identity_support=identity_assessment.identity_support,
            qualification_status=identity_assessment.qualification_status,
        )
        ordered_fixture_ids.append(fixture_id)
    if tuple(ordered_fixture_ids) != required:
        raise _StagingFailure("MANIFEST_INVALID")
    grouped_orders: dict[str, list[int]] = {}
    for fixture in fixtures.values():
        grouped_orders.setdefault(fixture.group_id, []).append(fixture.order)
    if any(sorted(values) != list(range(len(values))) for values in grouped_orders.values()):
        raise _StagingFailure("MANIFEST_INVALID")
    return FixturePlan(
        manifest_sha256=hashlib.sha256(_canonical_json(document)).hexdigest(),
        coverage_mode=mode,
        required_fixture_ids=required,
        mandatory_fixture_ids=mandatory,
        fixtures=MappingProxyType(fixtures),
    )

def _selected_fixtures(
    fixture_ids: Sequence[str], selected_fixture_ids: Sequence[str], mode: str,
    mandatory_fixture_ids: Sequence[str],
) -> tuple[str, ...]:
    if isinstance(selected_fixture_ids, (str, bytes)):
        raise _StagingFailure("SELECTION_INVALID")
    try:
        selected = tuple(_identifier(item) for item in selected_fixture_ids)
    except (TypeError, _StagingFailure):
        raise _StagingFailure("SELECTION_INVALID") from None
    if not selected or len(set(selected)) != len(selected) or any(item not in fixture_ids for item in selected):
        raise _StagingFailure("SELECTION_INVALID")
    if selected != tuple(item for item in fixture_ids if item in set(selected)):
        raise _StagingFailure("SELECTION_INVALID")
    if mode == "mandatory_full_plan" and selected != tuple(fixture_ids):
        raise _StagingFailure("COVERAGE_INCOMPLETE")
    if mode == "authorized_partial_plan" and selected == tuple(fixture_ids):
        raise _StagingFailure("SELECTION_INVALID")
    if any(item not in selected for item in mandatory_fixture_ids):
        raise _StagingFailure("COVERAGE_INCOMPLETE")
    return selected

def _graph_reaches_all(
    entrypoint: str, paths: set[str], adjacency: Mapping[str, Sequence[str]],
) -> bool:
    reached: set[str] = set()
    active: set[str] = set()
    stack: list[tuple[str, bool]] = [(entrypoint, False)]
    while stack:
        path, leaving = stack.pop()
        if leaving:
            active.remove(path)
            reached.add(path)
            continue
        if path in active:
            return False
        if path in reached:
            continue
        active.add(path)
        stack.append((path, True))
        stack.extend((target, False) for target in reversed(adjacency[path]))
    return reached == paths
