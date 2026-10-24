"""Append-only owner verdicts and deterministic review-packet projection."""

from __future__ import annotations

import json
import os
import re
import secrets
from pathlib import Path
from typing import Any, NoReturn

from scripts.android_qualification import evidence
from scripts.android_qualification import _evidence_storage as storage


_SESSION_NAME = re.compile(r"[0-9a-f]{32}\Z")
_VERDICT_NAME = re.compile(r"verdict-(\d{8})\.json\Z")
_TEMPORARY_VERDICT = re.compile(r"\.verdict-\d{8}\.tmp-[0-9a-f]{32}\Z")


def _invalid() -> NoReturn:
    raise evidence.EvidenceError(evidence.EvidenceErrorCode.INVALID_INPUT)


def _binding_invalid() -> NoReturn:
    raise evidence.EvidenceError(evidence.EvidenceErrorCode.VERDICT_BINDING_INVALID)


def _sufficiency_invalid() -> NoReturn:
    raise evidence.EvidenceError(evidence.EvidenceErrorCode.VERDICT_SUFFICIENCY_INVALID)


def _verdict_name(sequence: int) -> str:
    return f"verdict-{sequence:08d}.json"


def _selected_document(
    selected: tuple[evidence.SelectedRecord, ...],
) -> list[dict[str, object]]:
    if type(selected) is not tuple or len(selected) > 64:
        _invalid()
    result: list[dict[str, object]] = []
    previous_sequence = 0
    for item in selected:
        if type(item) is not evidence.SelectedRecord:
            _invalid()
        if type(item.sequence) is not int or item.sequence <= previous_sequence:
            _invalid()
        digest = storage._require_sha256(item.record_sha256)
        previous_sequence = item.sequence
        result.append({"sequence": item.sequence, "record_sha256": digest})
    return result


def _find_verified_manifest(
    root: Path,
    manifest_sha256: str,
) -> tuple[str, dict[str, Any], list[tuple[dict[str, Any], str]]]:
    manifest_sha256 = storage._require_sha256(manifest_sha256)
    storage._ensure_private_directory(root, create=False, root=root)
    executions = root / "executions"
    storage._ensure_private_directory(executions, create=False, root=root)
    directory_descriptor = storage._directory_descriptor(executions, root=root)
    try:
        names = os.listdir(directory_descriptor)
    except OSError:
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNAVAILABLE) from None
    finally:
        os.close(directory_descriptor)
    for name in sorted(names):
        if _SESSION_NAME.fullmatch(name) is None:
            raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNSAFE_PATH)
        session_directory = executions / name
        storage._ensure_private_directory(session_directory, create=False, root=root)
        try:
            with storage._stream_lock(session_directory, root=root):
                try:
                    chain = storage._load_chain(session_directory, name, root=root)
                except evidence.EvidenceError as error:
                    if error.code is not evidence.EvidenceErrorCode.CORRUPT:
                        raise
                    descriptor = storage._directory_descriptor(
                        session_directory,
                        root=root,
                    )
                    try:
                        names_in_session = os.listdir(descriptor)
                    except OSError:
                        raise evidence.EvidenceError(
                            evidence.EvidenceErrorCode.UNAVAILABLE
                        ) from None
                    finally:
                        os.close(descriptor)
                    has_record = any(
                        storage._record_pattern(entry) is not None
                        for entry in names_in_session
                    )
                    if "manifest.json" not in names_in_session and not has_record:
                        continue
                    raise
                raw = storage._read_private_file(
                    session_directory,
                    "manifest.json",
                    root=root,
                )
        except storage._MissingPrivateFile:
            continue
        document, digest = storage._parse_manifest(
            raw,
            session_id=name,
            chain=chain,
        )
        if digest == manifest_sha256:
            return name, document, chain
    raise evidence.EvidenceError(evidence.EvidenceErrorCode.MANIFEST_MISSING)


def _validate_binding(
    request: evidence.VerdictRequest,
    manifest: dict[str, Any],
    chain: list[tuple[dict[str, Any], str]],
    occurred_at: str,
) -> None:
    """Validate provenance, selected evidence, sufficiency, and chronology."""
    provenance = manifest["provenance"]
    if type(provenance) is not dict:
        _binding_invalid()
    artifact = provenance.get("artifact")
    rules = provenance.get("rules")
    requirements = provenance.get("review_requirements")
    if type(artifact) is not dict or type(rules) is not dict or type(requirements) is not dict:
        _binding_invalid()
    if (
        artifact.get("artifact_ref") != request.artifact_ref
        or artifact.get("artifact_sha256") != request.artifact_sha256
        or rules.get("rules_ref") != request.rules_ref
        or rules.get("rules_version") != request.rules_version
        or rules.get("rules_sha256") != request.rules_sha256
    ):
        _binding_invalid()
    selected_document = _selected_document(request.selected_records)
    if (
        request.verdict is evidence.OwnerVerdictOutcome.PASS
        and request.basis is evidence.ReviewBasis.OBJECTIVE_REVIEW
        and not selected_document
    ):
        _invalid()
    reviewed_at = storage._require_timestamp(request.reviewed_at)
    if reviewed_at > storage._require_timestamp(occurred_at):
        _invalid()
    selected_events: list[dict[str, Any]] = []
    for selected in selected_document:
        sequence = selected["sequence"]
        assert type(sequence) is int
        if sequence < 1 or sequence > len(chain):
            _binding_invalid()
        record, digest = chain[sequence - 1]
        if digest != selected["record_sha256"]:
            _binding_invalid()
        selected_events.append(record["event"])
    chronology_floor = storage._require_timestamp(
        chain[-1][0]["event"]["occurred_at"]
    )
    for event in selected_events:
        chronology_field = (
            "observed_at"
            if event.get("event_type") == "assertion"
            else "occurred_at"
        )
        chronology_floor = max(
            chronology_floor,
            storage._require_timestamp(event.get(chronology_field)),
        )
    if reviewed_at < chronology_floor:
        _invalid()
    if type(request.retrospective) is not bool:
        _invalid()
    if type(request.direct_observation_declared) is not bool:
        _invalid()
    if request.retrospective and requirements.get("retrospective_allowed") is not True:
        _sufficiency_invalid()
    if request.basis is evidence.ReviewBasis.OBJECTIVE_REVIEW:
        if requirements.get("objective_review_allowed") is not True:
            _sufficiency_invalid()
        if request.direct_observation_declared:
            _invalid()
        if request.sufficiency is not evidence.Sufficiency.SUFFICIENT:
            _sufficiency_invalid()
    elif request.basis is evidence.ReviewBasis.DIRECT_OWNER_OBSERVATION:
        if requirements.get("direct_owner_observation_allowed") is not True:
            _sufficiency_invalid()
        if request.direct_observation_declared is not True:
            _sufficiency_invalid()
    else:
        _invalid()
    if request.verdict is evidence.OwnerVerdictOutcome.PASS:
        if request.sufficiency is not evidence.Sufficiency.SUFFICIENT:
            _sufficiency_invalid()
    required = requirements.get("required_evidence_refs")
    if type(required) is not list:
        _binding_invalid()
    observed_refs: set[str] = set()
    for event in selected_events:
        refs = event.get("evidence_refs", [])
        if type(refs) is list:
            observed_refs.update(value for value in refs if type(value) is str)
    if request.basis is evidence.ReviewBasis.OBJECTIVE_REVIEW and not set(required).issubset(
        observed_refs
    ):
        _sufficiency_invalid()


def _event_document(
    owner_alias: str,
    request: evidence.VerdictRequest,
    scenario_id: str,
    operation_id: str,
    occurred_at: str,
) -> dict[str, object]:
    if type(request) is not evidence.VerdictRequest:
        _invalid()
    if type(request.retrospective) is not bool:
        _invalid()
    if type(request.direct_observation_declared) is not bool:
        _invalid()
    if type(request.verdict) is not evidence.OwnerVerdictOutcome:
        _invalid()
    if type(request.basis) is not evidence.ReviewBasis:
        _invalid()
    if type(request.sufficiency) is not evidence.Sufficiency:
        _invalid()
    reviewed_at = storage._require_timestamp(request.reviewed_at)
    supersedes = request.supersedes_verdict_sha256
    if supersedes is not None:
        supersedes = storage._require_sha256(supersedes)
    return {
        "artifact_ref": storage._require_opaque_ref(request.artifact_ref, kind="artifact"),
        "artifact_sha256": storage._require_sha256(request.artifact_sha256),
        "attendance_authentication": "not_provided",
        "basis": request.basis.value,
        "direct_observation_declared": request.direct_observation_declared,
        "event_type": "owner_verdict",
        "evidence_manifest_sha256": storage._require_sha256(
            request.evidence_manifest_sha256
        ),
        "occurred_at": occurred_at,
        "operation_id": operation_id,
        "owner_alias": storage._require_opaque_ref(owner_alias, kind="owner"),
        "owner_identity_authentication": "self_asserted",
        "retrospective": request.retrospective,
        "reviewed_at": reviewed_at,
        "rules_ref": storage._require_opaque_ref(request.rules_ref, kind="rules"),
        "rules_sha256": storage._require_sha256(request.rules_sha256),
        "rules_version": storage._require_version(request.rules_version),
        "scenario_id": storage._require_opaque_ref(scenario_id, kind="scenario"),
        "selected_records": _selected_document(request.selected_records),
        "sufficiency": request.sufficiency.value,
        "supersedes_verdict_sha256": supersedes,
        "verdict": request.verdict.value,
    }


def _parse_verdict(raw: bytes, *, sequence: int) -> tuple[dict[str, Any], str]:
    try:
        document = json.loads(
            raw.decode("utf-8"),
            object_pairs_hook=storage._object_without_duplicate_keys,
            parse_float=storage._reject_float,
            parse_constant=storage._reject_non_finite,
        )
    except storage._DuplicateKey:
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.DUPLICATE_KEY) from None
    except storage._FloatingPoint:
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.FLOAT_REJECTED) from None
    except storage._NonFinite:
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.NON_FINITE_NUMBER) from None
    except (UnicodeDecodeError, json.JSONDecodeError, RecursionError, ValueError):
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.CORRUPT) from None
    if type(document) is not dict or raw != storage._canonical_bytes(document):
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.CORRUPT)
    if set(document) != {
        "schema_version",
        "sequence",
        "previous_verdict_sha256",
        "event",
        "event_sha256",
        "verdict_sha256",
    }:
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.CORRUPT)
    if type(document["schema_version"]) is not int:
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.CORRUPT)
    if document["schema_version"] != storage.SCHEMA_VERSION:
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNSUPPORTED_SCHEMA)
    if type(document["sequence"]) is not int or document["sequence"] != sequence:
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.CORRUPT)
    digest_document = dict(document)
    digest = digest_document.pop("verdict_sha256")
    if storage._canonical_sha256(digest_document) != digest:
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.CORRUPT)
    event = document["event"]
    if type(event) is not dict or storage._canonical_sha256(event) != document["event_sha256"]:
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.CORRUPT)
    if set(event) != {
        "artifact_ref",
        "artifact_sha256",
        "attendance_authentication",
        "basis",
        "direct_observation_declared",
        "event_type",
        "evidence_manifest_sha256",
        "occurred_at",
        "operation_id",
        "owner_alias",
        "owner_identity_authentication",
        "retrospective",
        "reviewed_at",
        "rules_ref",
        "rules_sha256",
        "rules_version",
        "scenario_id",
        "selected_records",
        "sufficiency",
        "supersedes_verdict_sha256",
        "verdict",
    }:
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.CORRUPT)
    if event["event_type"] != "owner_verdict":
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.CORRUPT)
    storage._stored_ref(event["artifact_ref"], kind="artifact")
    storage._stored_sha256(event["artifact_sha256"])
    if event["attendance_authentication"] != "not_provided":
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.CORRUPT)
    storage._stored_enum(event["basis"], evidence.ReviewBasis)
    if type(event["direct_observation_declared"]) is not bool:
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.CORRUPT)
    storage._stored_sha256(event["evidence_manifest_sha256"])
    storage._stored_timestamp(event["occurred_at"])
    storage._stored_ref(event["operation_id"], kind="operation")
    storage._stored_ref(event["owner_alias"], kind="owner")
    if event["owner_identity_authentication"] != "self_asserted":
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.CORRUPT)
    if type(event["retrospective"]) is not bool:
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.CORRUPT)
    storage._stored_timestamp(event["reviewed_at"])
    storage._stored_ref(event["rules_ref"], kind="rules")
    storage._stored_sha256(event["rules_sha256"])
    storage._stored_version(event["rules_version"])
    storage._stored_ref(event["scenario_id"], kind="scenario")
    selected_records = event["selected_records"]
    if type(selected_records) is not list or len(selected_records) > 64:
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.CORRUPT)
    previous_sequence = 0
    for selected in selected_records:
        if type(selected) is not dict or set(selected) != {"sequence", "record_sha256"}:
            raise evidence.EvidenceError(evidence.EvidenceErrorCode.CORRUPT)
        sequence_value = storage._stored_integer(selected["sequence"], positive=True)
        if sequence_value <= previous_sequence:
            raise evidence.EvidenceError(evidence.EvidenceErrorCode.CORRUPT)
        previous_sequence = sequence_value
        storage._stored_sha256(selected["record_sha256"])
    storage._stored_enum(event["sufficiency"], evidence.Sufficiency)
    supersedes = event["supersedes_verdict_sha256"]
    if supersedes is not None:
        storage._stored_sha256(supersedes)
    storage._stored_enum(event["verdict"], evidence.OwnerVerdictOutcome)
    return document, digest


def _validate_stored_verdict(
    document: dict[str, Any],
    *,
    root: Path,
) -> None:
    """Revalidate persisted verdict semantics against its exact manifest."""

    event = document["event"]
    selected_records = tuple(
        evidence.SelectedRecord(
            sequence=storage._stored_integer(selected["sequence"], positive=True),
            record_sha256=storage._stored_sha256(selected["record_sha256"]),
        )
        for selected in event["selected_records"]
    )
    request = evidence.VerdictRequest(
        evidence_manifest_sha256=storage._stored_sha256(event["evidence_manifest_sha256"]),
        selected_records=selected_records,
        artifact_ref=storage._stored_ref(event["artifact_ref"], kind="artifact"),
        artifact_sha256=storage._stored_sha256(event["artifact_sha256"]),
        rules_ref=storage._stored_ref(event["rules_ref"], kind="rules"),
        rules_version=storage._stored_version(event["rules_version"]),
        rules_sha256=storage._stored_sha256(event["rules_sha256"]),
        verdict=evidence.OwnerVerdictOutcome(storage._stored_enum(
            event["verdict"], evidence.OwnerVerdictOutcome
        )),
        basis=evidence.ReviewBasis(storage._stored_enum(event["basis"], evidence.ReviewBasis)),
        sufficiency=evidence.Sufficiency(storage._stored_enum(
            event["sufficiency"], evidence.Sufficiency
        )),
        retrospective=event["retrospective"],
        direct_observation_declared=event["direct_observation_declared"],
        reviewed_at=storage._stored_timestamp(event["reviewed_at"]),
        supersedes_verdict_sha256=event["supersedes_verdict_sha256"],
    )
    try:
        _session_id, manifest, execution_chain = _find_verified_manifest(
            root,
            request.evidence_manifest_sha256,
        )
        if event["scenario_id"] != manifest["scenario_id"]:
            raise evidence.EvidenceError(evidence.EvidenceErrorCode.CORRUPT)
        _validate_binding(request, manifest, execution_chain, event["occurred_at"])
    except evidence.EvidenceError:
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.CORRUPT) from None


def _logical_verdict_previous(
    chain: list[tuple[dict[str, Any], str]],
    event: dict[str, Any],
) -> str | None:
    """Find the prior digest a verdict in this logical stream must supersede."""

    for record, digest in reversed(chain):
        prior = record["event"]
        if (
            prior.get("scenario_id") == event.get("scenario_id")
            and prior.get("artifact_ref") == event.get("artifact_ref")
            and prior.get("artifact_sha256") == event.get("artifact_sha256")
            and prior.get("rules_ref") == event.get("rules_ref")
            and prior.get("rules_version") == event.get("rules_version")
            and prior.get("rules_sha256") == event.get("rules_sha256")
        ):
            return digest
    return None


def _load_verdict_chain(
    directory: Path,
    *,
    root: Path,
) -> list[tuple[dict[str, Any], str]]:
    directory_descriptor = storage._directory_descriptor(directory, root=root)
    try:
        names = os.listdir(directory_descriptor)
    except OSError:
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNAVAILABLE) from None
    finally:
        os.close(directory_descriptor)
    sequence_names: list[tuple[int, str]] = []
    for name in names:
        if name == ".owner-review.lock":
            continue
        if _TEMPORARY_VERDICT.fullmatch(name) is not None:
            continue
        match = _VERDICT_NAME.fullmatch(name)
        if match is None:
            raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNSAFE_PATH)
        sequence_names.append((int(match.group(1)), name))
    sequence_names.sort()
    chain: list[tuple[dict[str, Any], str]] = []
    previous: str | None = None
    operation_ids: set[str] = set()
    prior_occurred_at: str | None = None
    for expected, (observed, name) in enumerate(sequence_names, start=1):
        if observed != expected:
            raise evidence.EvidenceError(evidence.EvidenceErrorCode.CORRUPT)
        raw = storage._read_private_file(directory, name, root=root)
        document, digest = _parse_verdict(raw, sequence=expected)
        _validate_stored_verdict(document, root=root)
        if document["event"]["supersedes_verdict_sha256"] != _logical_verdict_previous(
            chain,
            document["event"],
        ):
            raise evidence.EvidenceError(evidence.EvidenceErrorCode.CORRUPT)
        if document["previous_verdict_sha256"] != previous:
            raise evidence.EvidenceError(evidence.EvidenceErrorCode.CORRUPT)
        operation_id = document["event"].get("operation_id")
        if type(operation_id) is not str or operation_id in operation_ids:
            raise evidence.EvidenceError(evidence.EvidenceErrorCode.CORRUPT)
        occurred_at = storage._stored_timestamp(document["event"].get("occurred_at"))
        if prior_occurred_at is not None and occurred_at < prior_occurred_at:
            raise evidence.EvidenceError(evidence.EvidenceErrorCode.CORRUPT)
        prior_occurred_at = occurred_at
        operation_ids.add(operation_id)
        previous = digest
        chain.append((document, digest))
    return chain


def _public_verdict(document: dict[str, Any], digest: str) -> evidence.OwnerVerdict:
    event = document["event"]
    return evidence.OwnerVerdict(
        sequence=int(document["sequence"]),
        owner_alias=str(event["owner_alias"]),
        verdict=evidence.OwnerVerdictOutcome(event["verdict"]),
        basis=evidence.ReviewBasis(event["basis"]),
        sufficiency=evidence.Sufficiency(event["sufficiency"]),
        evidence_manifest_sha256=str(event["evidence_manifest_sha256"]),
        verdict_sha256=digest,
        previous_verdict_sha256=document["previous_verdict_sha256"],
        supersedes_verdict_sha256=event["supersedes_verdict_sha256"],
    )


class OwnerReviewer:
    """Append explicit owner decisions without an execution-writing capability."""

    def __init__(self, root: Path, owner_alias: str) -> None:
        self._root = root
        self._owner_alias = storage._require_opaque_ref(owner_alias, kind="owner")
        self._directory_name = "owner-verdicts"

    def _directory(self) -> Path:
        storage._ensure_private_directory(self._root, create=True, root=self._root)
        directory = self._root / self._directory_name
        storage._ensure_private_directory(directory, create=True, root=self._root)
        return directory

    def record_verdict(
        self,
        request: evidence.VerdictRequest,
        write_request: evidence.WriteRequest,
    ) -> evidence.VerdictReceipt:
        """Append an owner verdict or return its receipt for an exact replay."""
        if type(request) is not evidence.VerdictRequest:
            _invalid()
        if type(write_request) is not evidence.WriteRequest:
            _invalid()
        expected_head = write_request.expected_head_sha256
        if expected_head is not None:
            storage._require_sha256(expected_head)
        operation_id = storage._require_caller_operation_id(write_request.operation_id)
        occurred_at = (
            storage._now_timestamp()
            if write_request.occurred_at is None
            else storage._require_timestamp(write_request.occurred_at)
        )
        _session_id, manifest, execution_chain = _find_verified_manifest(
            self._root,
            request.evidence_manifest_sha256,
        )
        scenario_id = str(manifest["scenario_id"])
        event = _event_document(
            self._owner_alias,
            request,
            scenario_id,
            operation_id,
            occurred_at,
        )
        directory = self._directory()
        with storage._stream_lock(
            directory,
            root=self._root,
            lock_name=".owner-review.lock",
        ):
            chain = _load_verdict_chain(directory, root=self._root)
            for record, digest in chain:
                existing = record["event"]
                if existing.get("operation_id") == operation_id:
                    comparable = dict(existing)
                    comparable.pop("occurred_at", None)
                    requested = dict(event)
                    requested.pop("occurred_at", None)
                    if comparable != requested:
                        raise evidence.EvidenceError(
                            evidence.EvidenceErrorCode.OPERATION_CONFLICT
                        )
                    storage._fsync_private_directory(directory, root=self._root)
                    return evidence.VerdictReceipt(
                        operation_id=operation_id,
                        sequence=int(record["sequence"]),
                        verdict_sha256=digest,
                        idempotent=True,
                    )
            _validate_binding(request, manifest, execution_chain, occurred_at)
            current_head = chain[-1][1] if chain else None
            if expected_head is not None and expected_head != current_head:
                raise evidence.EvidenceError(
                    evidence.EvidenceErrorCode.EXPECTED_HEAD_CONFLICT
                )
            if chain:
                last_occurred_at = storage._stored_timestamp(
                    chain[-1][0]["event"].get("occurred_at")
                )
                if occurred_at < last_occurred_at:
                    _invalid()

            previous = chain[-1][1] if chain else None
            logical_previous = _logical_verdict_previous(chain, event)
            if request.supersedes_verdict_sha256 != logical_previous:
                raise evidence.EvidenceError(
                    evidence.EvidenceErrorCode.VERDICT_BINDING_INVALID
                )
            sequence = len(chain) + 1
            record: dict[str, object] = {
                "schema_version": storage.SCHEMA_VERSION,
                "sequence": sequence,
                "previous_verdict_sha256": previous,
                "event": event,
                "event_sha256": storage._canonical_sha256(event),
            }
            record["verdict_sha256"] = storage._canonical_sha256(record)
            encoded = storage._canonical_bytes(record)
            final_name = _verdict_name(sequence)
            try:
                storage._publish_no_replace(
                    directory,
                    f".verdict-{sequence:08d}.tmp-{secrets.token_hex(16)}",
                    final_name,
                    encoded,
                    root=self._root,
                )
            except FileExistsError:
                raise evidence.EvidenceError(
                    evidence.EvidenceErrorCode.EXPECTED_HEAD_CONFLICT
                ) from None
            digest = str(record["verdict_sha256"])
            return evidence.VerdictReceipt(
                operation_id=operation_id,
                sequence=sequence,
                verdict_sha256=digest,
                idempotent=False,
            )

    def latest_verdict(self, scenario_id: str) -> evidence.OwnerVerdict | None:
        """Return the latest verdict for a scenario when its chain exists."""

        scenario_id = storage._require_opaque_ref(scenario_id, kind="scenario")
        directory = self._root / self._directory_name
        if (
            storage._ensure_private_directory(
                directory,
                create=False,
                root=self._root,
                missing_ok=True,
            )
            is None
        ):
            return None
        with storage._stream_lock(
            directory,
            root=self._root,
            lock_name=".owner-review.lock",
        ):
            chain = _load_verdict_chain(directory, root=self._root)
        for document, digest in reversed(chain):
            if document["event"].get("scenario_id") == scenario_id:
                return _public_verdict(document, digest)
        return None

    def review_packet(self, evidence_manifest_sha256: str) -> bytes:
        """Return canonical JSON for the verified manifest and record chain."""
        _session_id, manifest, chain = _find_verified_manifest(
            self._root,
            evidence_manifest_sha256,
        )
        packet = {
            "schema_version": storage.SCHEMA_VERSION,
            "execution_manifest_sha256": manifest["manifest_sha256"],
            "manifest": manifest,
            "records": [
                {
                    "sequence": record["sequence"],
                    "record_sha256": digest,
                    "previous_record_sha256": record["previous_record_sha256"],
                    "event": record["event"],
                }
                for record, digest in chain
            ],
        }
        return storage._canonical_bytes(packet)
