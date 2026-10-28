"""Bounded, data-only snapshot provenance; this module grants no authority.

Schema definitions and trust boundaries are documented in
``docs/qualification/production-staging/oracle-contract.md``. This standalone
module does not import the legacy parser, inspect content files, or use a network.
"""

from __future__ import annotations

import hashlib
import json
import re
import unicodedata
from dataclasses import dataclass


MAX_DOCUMENT_BYTES = 64 * 1024
MAX_RECEIPT_DOCUMENT_BYTES = 256 * 1024
MAX_BROKER_SESSION_LINE_BYTES = 12 * 1024 * 1024
MAX_BROKER_SESSION_DOCUMENT_BYTES = MAX_BROKER_SESSION_LINE_BYTES - 1
MAX_BROKER_DOCUMENTS_BYTES = 8 * 1024 * 1024
MAX_DOCUMENT_DEPTH = 32
MAX_GRAPH_RECORDS = 128
ORACLE_DOMAIN = b"argus.fixture-oracle.v1\x00"
EVIDENCE_DOMAIN = b"argus.fixture-evidence.v1\x00"
SOURCE_AUTHORITY = "service_protected_snapshot_v1"
_SHA256 = re.compile(r"[0-9a-f]{64}\Z")
_FIXTURE_FIELDS = {"fixture_id", "platform", "representation", "identity", "group_id",
                   "order", "entrypoint", "files", "companions"}
_RECORD_FIELDS = {"schema_version", "revision", "fixture", "corpus_origin",
                  "acceptance_rule_sha256", "method", "provenance", "limitations",
                  "conflicts", "evidence_refs"}


class OracleError(ValueError):
    """A fixed error code without private values, source paths, or raw JSON."""

    def __init__(self, code: str = "INPUT_INVALID") -> None:
        self.code = code
        super().__init__(code)


@dataclass(frozen=True)
class FixtureAssessment:
    """Declaration and reference checks, separate from content and owner checks."""

    fixture_id: str
    oracle_ref: str
    oracle_revision: str
    oracle_sha256: str
    corpus_origin: str
    independent_support: str
    byte_integrity: str = "not_checked"
    structural_expectation: str = "validated"
    owner_approval: str = "not_checked"


@dataclass(frozen=True)
class SnapshotContract:
    """Immutable validation result; not a staging grant or a qualification verdict."""

    manifest_sha256: str
    source_authority: str
    fixtures: tuple[FixtureAssessment, ...]


def _canonical_value(value: object, depth: int = 0) -> None:
    if depth > MAX_DOCUMENT_DEPTH:
        raise OracleError("LIMIT_EXCEEDED")
    if value is None or type(value) is bool:
        return
    if type(value) is int:
        if not -(2**63) <= value < 2**63:
            raise OracleError()
    elif type(value) is str:
        if unicodedata.normalize("NFC", value) != value:
            raise OracleError()
        try:
            value.encode("utf-8")
        except UnicodeEncodeError:
            raise OracleError() from None
    elif type(value) is list:
        for item in value:
            _canonical_value(item, depth + 1)
    elif type(value) is dict:
        for key, item in value.items():
            if type(key) is not str or not key.isascii():
                raise OracleError()
            _canonical_value(item, depth + 1)
    else:
        raise OracleError()


def canonical_json(
    value: object, *, maximum_bytes: int = MAX_DOCUMENT_BYTES
) -> bytes:
    """Return bounded UTF-8 canonical JSON, rejecting non-NFC or lossy values.

    Keys are ASCII and sorted. Arrays retain order. Booleans and signed 64-bit
    integers remain distinct. Floats and surrogate code points are unsupported.
    Strings are rejected, never silently normalized before a digest is checked.
    Ordinary documents default to 64 KiB. Receipt transport may select up to
    256 KiB, and prepared broker frames may select up to 12 MiB minus the
    newline byte reserved for line framing.
    """
    if type(maximum_bytes) is not int or not 1 <= maximum_bytes <= MAX_BROKER_SESSION_DOCUMENT_BYTES:
        raise OracleError("LIMIT_EXCEEDED")
    _canonical_value(value)
    encoded = json.dumps(value, ensure_ascii=False, sort_keys=True,
                         separators=(",", ":"), allow_nan=False).encode("utf-8")
    if len(encoded) > maximum_bytes:
        raise OracleError("LIMIT_EXCEEDED")
    return encoded


def _pairs(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise OracleError()
        result[key] = value
    return result


def _reject_number(_value: str) -> None:
    raise OracleError()


def _integer(value: str) -> int:
    if value == "-0":
        raise OracleError()
    return int(value)


def decode_document(
    encoded: bytes, *, maximum_bytes: int = MAX_DOCUMENT_BYTES
) -> dict[str, object]:
    """Decode one bounded JSON object, rejecting duplicate keys anywhere.

    Only bytes are accepted. The caller owns secure file acquisition; this
    function never treats a path, URI, or reference as something to open.
    Ordinary documents default to 64 KiB. Authenticated receipt records may
    use a caller-selected bound up to 256 KiB, and prepared broker responses
    may use the bounded native session line limit minus its newline byte.
    """
    if type(maximum_bytes) is not int or not 1 <= maximum_bytes <= MAX_BROKER_SESSION_DOCUMENT_BYTES:
        raise OracleError("LIMIT_EXCEEDED")
    if type(encoded) is not bytes:
        raise OracleError()
    if len(encoded) > maximum_bytes:
        raise OracleError("LIMIT_EXCEEDED")
    try:
        document = json.loads(encoded.decode("utf-8"), object_pairs_hook=_pairs,
                              parse_int=_integer, parse_float=_reject_number,
                              parse_constant=_reject_number)
        if type(document) is not dict:
            raise OracleError()
        canonical_json(document, maximum_bytes=maximum_bytes)
    except OracleError:
        raise
    except (ValueError, UnicodeError, RecursionError):
        raise OracleError() from None
    return document


def manifest_sha256(document: object) -> str:
    """Hash canonical JSON without a prefix, preserving authorization pins."""
    return hashlib.sha256(canonical_json(document)).hexdigest()


def oracle_sha256(document: object) -> str:
    """Hash canonical bytes with the oracle-v1 NUL-terminated domain prefix."""
    return hashlib.sha256(ORACLE_DOMAIN + canonical_json(document)).hexdigest()


def evidence_sha256(document: object) -> str:
    """Hash canonical bytes with the evidence-v1 NUL-terminated domain prefix."""
    return hashlib.sha256(EVIDENCE_DOMAIN + canonical_json(document)).hexdigest()


def _fields(value: object, required: set[str], optional: frozenset[str] = frozenset()) -> dict:
    if type(value) is not dict or required - value.keys() or value.keys() - required - optional:
        raise OracleError()
    return value


def _text(value: object, maximum: int = 4096) -> str:
    if (type(value) is not str or not value or len(value) > maximum or value.strip() != value
            or any(unicodedata.category(char) == "Cc" for char in value)):
        raise OracleError()
    return value


def _identifier(value: object) -> str:
    value = _text(value, 256)
    if value in {".", ".."} or any(char in value for char in "/\\:"):
        raise OracleError()
    return value


def _digest(value: object) -> str:
    if type(value) is not str or _SHA256.fullmatch(value) is None:
        raise OracleError()
    return value


def _version(value: object, expected: int) -> None:
    if type(value) is not int or value != expected:
        raise OracleError("SCHEMA_UNSUPPORTED")


def _array(value: object, *, nonempty: bool = False) -> list:
    if type(value) is not list or (nonempty and not value):
        raise OracleError()
    return value


def _nonnegative(value: object) -> None:
    if type(value) is not int or not 0 <= value < 2**63:
        raise OracleError()


def _fold(value: str) -> str:
    return unicodedata.normalize("NFD", unicodedata.normalize("NFD", value).casefold())


def _path(value: object) -> str:
    value = _text(value)
    if "\\" in value or ":" in value or any(part in {"", ".", ".."} for part in value.split("/")):
        raise OracleError()
    return value


def _pin(value: object, kind: str) -> dict:
    pin = _fields(value, {"schema_version", f"{kind}_ref", "revision", "sha256"})
    _version(pin["schema_version"], 1)
    _identifier(pin[f"{kind}_ref"])
    _text(pin["revision"], 256)
    _digest(pin["sha256"])
    return pin


def _walk(roots: list[str], adjacency: dict[str, list[str]], *, provenance: bool) -> set[str]:
    """Traverse first, so even an unhashable circular provenance graph is refused."""
    visited: set[str] = set()
    active: set[str] = set()
    for root in roots:
        if root in visited:
            continue
        stack = [(root, False)]
        while stack:
            node, leaving = stack.pop()
            if leaving:
                active.remove(node)
                visited.add(node)
                continue
            if node in active:
                raise OracleError("REFERENCE_CYCLE" if provenance else "INPUT_INVALID")
            if node in visited:
                continue
            if node not in adjacency:
                raise OracleError("MISSING_REFERENCE" if provenance else "INPUT_INVALID")
            active.add(node)
            stack.append((node, True))
            stack.extend((child, False) for child in reversed(adjacency[node]))
    return visited


def _fixture(value: object, *, manifest: bool = False) -> dict:
    fields = _FIXTURE_FIELDS | ({"identity_evidence", "oracle_pin"} if manifest else set())
    fixture = _fields(value, fields, frozenset({"facts"}))
    _identifier(fixture["fixture_id"])
    for field in ("platform", "representation", "group_id"):
        _text(fixture[field], 256)
    _text(fixture["identity"], 512)
    _nonnegative(fixture["order"])
    entrypoint = _path(fixture["entrypoint"])
    paths: set[str] = set()
    components: dict[tuple[str, ...], tuple[str, ...]] = {}
    for value in _array(fixture["files"], nonempty=True):
        member = _fields(value, {"path", "role", "size", "sha256"})
        path = _path(member["path"])
        _text(member["role"], 64)
        _nonnegative(member["size"])
        _digest(member["sha256"])
        if path in paths:
            raise OracleError()
        paths.add(path)
        parts = tuple(path.split("/"))
        for length in range(1, len(parts) + 1):
            spelling = parts[:length]
            folded = tuple(_fold(part) for part in spelling)
            if components.setdefault(folded, spelling) != spelling:
                raise OracleError()
    if any("/".join(path.split("/")[:length]) in paths
           for path in paths for length in range(1, len(path.split("/")))):
        raise OracleError()
    adjacency: dict[str, list[str]] = {path: [] for path in paths}
    edges: set[tuple[str, str]] = set()
    for value in _array(fixture["companions"]):
        edge = _fields(value, {"source", "target"})
        source, target = _path(edge["source"]), _path(edge["target"])
        if source not in paths or target not in paths or (source, target) in edges:
            raise OracleError()
        edges.add((source, target))
        adjacency[source].append(target)
    if _walk([entrypoint], adjacency, provenance=False) != paths:
        raise OracleError()
    if "facts" in fixture:
        facts = _fields(fixture["facts"], set(), frozenset({"edition", "region", "disc_set"}))
        if not facts:
            raise OracleError()
        for fact in facts.values():
            _text(fact, 256)
    if manifest:
        if _text(fixture["identity_evidence"]) not in {
            "synthetic_expectation_v2", "independent_reference_pinned_v1"
        }:
            raise OracleError()
        _pin(fixture["oracle_pin"], "oracle")
    return {key: item for key, item in fixture.items() if key in _FIXTURE_FIELDS | {"facts"}}


def _record(value: object, kind: str) -> dict:
    record = _fields(value, _RECORD_FIELDS | {f"{kind}_ref"},
                     frozenset({"reference"}) if kind == "evidence" else frozenset())
    _version(record["schema_version"], 1)
    _identifier(record[f"{kind}_ref"])
    _text(record["revision"], 256)
    _fixture(record["fixture"])
    _digest(record["acceptance_rule_sha256"])
    origin = _text(record["corpus_origin"])
    expected_method = {"synthetic": "synthetic_expectation",
                       "owner_private_genuine": "independent_reference"}.get(origin)
    if expected_method is None or record["method"] != expected_method:
        raise OracleError()
    _text(record["provenance"])
    for field in ("limitations", "conflicts"):
        values = [_text(item) for item in _array(record[field])]
        if len(values) != len(set(values)):
            raise OracleError()
    if record["conflicts"]:
        raise OracleError("EVIDENCE_CONFLICT")
    refs = [_pin(item, "evidence")["evidence_ref"] for item in _array(record["evidence_refs"])]
    if len(refs) != len(set(refs)):
        raise OracleError()
    if origin == "owner_private_genuine":
        if kind == "oracle" and not refs:
            raise OracleError()
        if kind == "evidence":
            reference = _fields(record.get("reference"), {"ref", "revision", "sha256"})
            _text(reference["ref"])
            _text(reference["revision"], 256)
            _digest(reference["sha256"])
    elif "reference" in record:
        raise OracleError()
    return record


def _registry(documents: list[bytes] | tuple[bytes, ...], kind: str) -> dict[str, dict]:
    records: dict[str, dict] = {}
    for raw in documents:
        record = _record(decode_document(raw), kind)
        name = record[f"{kind}_ref"]
        if name in records:
            raise OracleError()
        records[name] = record
    return records


def _check_pin(pin: dict, record: dict, kind: str) -> None:
    hasher = oracle_sha256 if kind == "oracle" else evidence_sha256
    if pin["revision"] != record["revision"] or pin["sha256"] != hasher(record):
        raise OracleError("PIN_MISMATCH")


def _manifest(raw: bytes) -> dict:
    document = _fields(decode_document(raw), {
        "schema_version", "source_authority", "plan_sha256", "rules_sha256",
        "coverage_mode", "selected_fixture_ids", "fixtures",
    })
    _version(document["schema_version"], 2)
    if document["source_authority"] != SOURCE_AUTHORITY:
        raise OracleError()
    _digest(document["plan_sha256"])
    _digest(document["rules_sha256"])
    if _text(document["coverage_mode"]) not in {"mandatory_full_plan", "authorized_partial_plan"}:
        raise OracleError()
    selected = [_identifier(item) for item in _array(document["selected_fixture_ids"], nonempty=True)]
    if len({_fold(item) for item in selected}) != len(selected):
        raise OracleError()
    fixtures = [_fixture(item, manifest=True) for item in _array(document["fixtures"], nonempty=True)]
    if [item["fixture_id"] for item in fixtures] != selected:
        raise OracleError()
    groups: dict[str, int] = {}
    for fixture in fixtures:
        group, order = fixture["group_id"], fixture["order"]
        if order <= groups.get(group, -1):
            raise OracleError()
        groups[group] = order
    return document


def validate_snapshot_contract(
    manifest: bytes,
    oracles: list[bytes] | tuple[bytes, ...],
    evidence: list[bytes] | tuple[bytes, ...],
    *,
    authorized_manifest_sha256: str,
    authorized_plan_sha256: str,
    authorized_rules_sha256: str,
) -> SnapshotContract:
    """Validate a complete pinned graph without accepting caller trust.

    Inputs are bounded private document bytes, never filenames. The three pins
    must come from separately authenticated authorization. Genuine declarations
    remain ``pinned_unverified`` because this module has no authenticated native
    verifier result. A caller-supplied callable cannot mint independent
    verification. This function does not issue owner approval or verify snapshot
    payload bytes, and no partial assessment survives any failure.
    """
    if type(oracles) not in {list, tuple} or type(evidence) not in {list, tuple}:
        raise OracleError()
    if len(oracles) + len(evidence) > MAX_GRAPH_RECORDS:
        raise OracleError("LIMIT_EXCEEDED")
    document = _manifest(manifest)
    manifest_digest = manifest_sha256(document)
    if (manifest_digest != _digest(authorized_manifest_sha256)
            or document["plan_sha256"] != _digest(authorized_plan_sha256)
            or document["rules_sha256"] != _digest(authorized_rules_sha256)):
        raise OracleError("PIN_MISMATCH")
    oracle_records = _registry(oracles, "oracle")
    evidence_records = _registry(evidence, "evidence")
    adjacency = {ref: [pin["evidence_ref"] for pin in record["evidence_refs"]]
                 for ref, record in evidence_records.items()}
    used_oracles: set[str] = set()
    used_evidence: set[str] = set()
    selections: list[tuple[dict, dict]] = []
    for fixture in document["fixtures"]:
        pin = fixture["oracle_pin"]
        record = oracle_records.get(pin["oracle_ref"])
        if record is None:
            raise OracleError("MISSING_REFERENCE")
        used_oracles.add(pin["oracle_ref"])
        _check_pin(pin, record, "oracle")
        binding = {key: value for key, value in fixture.items() if key in _FIXTURE_FIELDS | {"facts"}}
        expected_label = ("synthetic_expectation_v2" if record["corpus_origin"] == "synthetic"
                          else "independent_reference_pinned_v1")
        if (binding != record["fixture"] or record["acceptance_rule_sha256"] != document["rules_sha256"]
                or fixture["identity_evidence"] != expected_label):
            raise OracleError("EVIDENCE_CONFLICT")
        reachable = _walk([pin["evidence_ref"] for pin in record["evidence_refs"]],
                          adjacency, provenance=True)
        used_evidence.update(reachable)
        closure = [record] + [evidence_records[ref] for ref in sorted(reachable)]
        for item in closure:
            if any(item[key] != record[key] for key in ("fixture", "corpus_origin", "acceptance_rule_sha256")):
                raise OracleError("EVIDENCE_CONFLICT")
            for dependency in item["evidence_refs"]:
                _check_pin(dependency, evidence_records[dependency["evidence_ref"]], "evidence")
        selections.append((fixture, record))
    if used_oracles != oracle_records.keys() or used_evidence != evidence_records.keys():
        raise OracleError("UNUSED_RECORD")

    source_pins: dict[str, tuple[str, str]] = {}
    for ref in sorted(used_evidence):
        record = evidence_records[ref]
        if "reference" in record:
            reference = record["reference"]
            identity = (reference["revision"], reference["sha256"])
            if source_pins.setdefault(reference["ref"], identity) != identity:
                raise OracleError("EVIDENCE_CONFLICT")

    assessments = []
    for fixture, record in selections:
        support = (
            "synthetic_only"
            if record["corpus_origin"] == "synthetic"
            else "pinned_unverified"
        )
        assessments.append(FixtureAssessment(
            fixture_id=fixture["fixture_id"], oracle_ref=record["oracle_ref"],
            oracle_revision=record["revision"], oracle_sha256=fixture["oracle_pin"]["sha256"],
            corpus_origin=record["corpus_origin"], independent_support=support,
        ))
    return SnapshotContract(manifest_digest, SOURCE_AUTHORITY, tuple(assessments))
