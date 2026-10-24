"""Test explicit owner verdicts and deterministic review packets."""

from __future__ import annotations

import copy
import errno
import hashlib
import json
import os
import tempfile
import unittest
from dataclasses import replace
from pathlib import Path
from unittest.mock import patch

from scripts.android_qualification import evidence
from scripts.android_qualification import _evidence_storage


def _alias(kind: str, label: str) -> str:
    digest = hashlib.sha256(f"{kind}:{label}".encode("utf-8")).hexdigest()
    return f"{kind}-{digest[:32]}"


def _operation(label: str) -> str:
    return _alias("operation", label)


class EvidenceReviewTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.root = Path(self.temporary_directory.name) / "qualification-evidence"
        self.store = evidence.EvidenceStore(self.root)
        self.writer = self.store.execution_writer()

    @staticmethod
    def _session_spec(
        *,
        required_evidence_refs: tuple[str, ...] = (_alias("evidence", "synthetic"),),
        review_requirements: evidence.ReviewRequirements | None = None,
    ) -> evidence.SessionSpec:
        return evidence.SessionSpec(
            session_id="1" * 32,
            scenario_id=_alias("scenario", "synthetic"),
            artifact=evidence.ArtifactPin(
                artifact_ref=_alias("artifact", "synthetic"),
                artifact_sha256="2" * 64,
                artifact_class=evidence.ArtifactClass.QUALIFICATION_VARIANT,
            ),
            authorization=evidence.AuthorizationPin(
                manifest_version=1,
                manifest_sha256="3" * 64,
            ),
            fixtures=evidence.FixturePin(
                manifest_version=1,
                manifest_sha256="4" * 64,
                corpus_ref=_alias("corpus", "fixture-synthetic"),
            ),
            plan=evidence.PlanPin(
                plan_ref=_alias("plan", "synthetic"),
                plan_version=1,
                plan_sha256="5" * 64,
            ),
            rules=evidence.AcceptanceRulesPin(
                rules_ref=_alias("rules", "synthetic"),
                rules_version="1.0.0",
                rules_sha256="6" * 64,
            ),
            environment=evidence.EnvironmentPin(
                platform=evidence.Platform.ANDROID,
                platform_version=_alias("platform-version", "api-35"),
                environment_ref=_alias("environment", "synthetic"),
                target_ref=_alias("target", "synthetic"),
            ),
            review_requirements=review_requirements
            or evidence.ReviewRequirements(
                required_evidence_refs=required_evidence_refs,
                objective_review_allowed=True,
                direct_owner_observation_allowed=True,
                retrospective_allowed=False,
            ),
        )

    def _finalized_execution(
        self,
        *,
        required_evidence_refs: tuple[str, ...] = (_alias("evidence", "synthetic"),),
        review_requirements: evidence.ReviewRequirements | None = None,
    ) -> evidence.ExecutionManifest:
        opened = self.writer.open_session(
            self._session_spec(
                required_evidence_refs=required_evidence_refs,
                review_requirements=review_requirements,
            ),
            evidence.WriteRequest(
                operation_id=_operation("open-session-synthetic"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )
        assertion = self.writer.append_assertion(
            "1" * 32,
            evidence.AssertionObservation(
                assertion_ref=_alias("assertion", "synthetic"),
                rules_ref=_alias("rules", "synthetic"),
                rules_version="1.0.0",
                rules_sha256="6" * 64,
                observed_at="2026-10-23T01:00:01Z",
                expected_outcome=evidence.AssertionOutcome.PASSED,
                actual_outcome=evidence.AssertionOutcome.PASSED,
                evidence_refs=(_alias("evidence", "synthetic"),),
                measurements=(),
            ),
            evidence.WriteRequest(
                operation_id=_operation("assertion-synthetic"),
                occurred_at="2026-10-23T01:00:02Z",
                expected_head_sha256=opened.head_sha256,
            ),
        )
        self.writer.append_terminal(
            "1" * 32,
            evidence.TerminalObservation(
                outcome=evidence.TerminalOutcome.COMPLETED,
                reason=evidence.TerminalReason.PLAN_COMPLETE,
                ended_at="2026-10-23T01:00:03Z",
                evidence_refs=(_alias("evidence", "synthetic"),),
            ),
            evidence.WriteRequest(
                operation_id=_operation("terminal-synthetic"),
                occurred_at="2026-10-23T01:00:04Z",
                expected_head_sha256=assertion.head_sha256,
            ),
        )
        return self.writer.verify_execution("1" * 32)

    def _assertion_selection(
        self,
        *,
        required_evidence_refs: tuple[str, ...] = (_alias("evidence", "synthetic"),),
        review_requirements: evidence.ReviewRequirements | None = None,
    ) -> tuple[evidence.ExecutionManifest, evidence.SelectedRecord]:
        manifest = self._finalized_execution(
            required_evidence_refs=required_evidence_refs,
            review_requirements=review_requirements,
        )
        assertion = self.writer.snapshot("1" * 32).records[1]
        return manifest, evidence.SelectedRecord(
            sequence=assertion.sequence,
            record_sha256=assertion.record_sha256,
        )

    @staticmethod
    def _request(
        manifest: evidence.ExecutionManifest,
        selected: tuple[evidence.SelectedRecord, ...],
        *,
        verdict: evidence.OwnerVerdictOutcome = evidence.OwnerVerdictOutcome.PASS,
        basis: evidence.ReviewBasis = evidence.ReviewBasis.OBJECTIVE_REVIEW,
        sufficiency: evidence.Sufficiency = evidence.Sufficiency.SUFFICIENT,
        retrospective: bool = False,
        direct_observation_declared: bool = False,
        supersedes: str | None = None,
        reviewed_at: str = "2026-10-23T01:00:05Z",
    ) -> evidence.VerdictRequest:
        return evidence.VerdictRequest(
            evidence_manifest_sha256=manifest.manifest_sha256,
            selected_records=selected,
            artifact_ref=_alias("artifact", "synthetic"),
            artifact_sha256="2" * 64,
            rules_ref=_alias("rules", "synthetic"),
            rules_version="1.0.0",
            rules_sha256="6" * 64,
            verdict=verdict,
            basis=basis,
            sufficiency=sufficiency,
            retrospective=retrospective,
            direct_observation_declared=direct_observation_declared,
            reviewed_at=reviewed_at,
            supersedes_verdict_sha256=supersedes,
        )

    def _rewrite_verdict(
        self,
        path: Path,
        document: dict[str, object],
    ) -> None:
        event = document["event"]
        self.assertIsInstance(event, dict)
        document["event_sha256"] = hashlib.sha256(
            json.dumps(
                event,
                sort_keys=True,
                separators=(",", ":"),
            ).encode("utf-8")
        ).hexdigest()
        digest_document = dict(document)
        digest_document.pop("verdict_sha256", None)
        document["verdict_sha256"] = hashlib.sha256(
            json.dumps(
                digest_document,
                sort_keys=True,
                separators=(",", ":"),
            ).encode("utf-8")
        ).hexdigest()
        path.write_bytes(
            json.dumps(
                document,
                sort_keys=True,
                separators=(",", ":"),
            ).encode("utf-8")
        )

    def _rewrite_execution_record(
        self,
        session_directory: Path,
        sequence: int,
        record: dict[str, object],
    ) -> str:
        event = record["event"]
        self.assertIsInstance(event, dict)
        record["event_sha256"] = _evidence_storage._canonical_sha256(event)
        digest_document = dict(record)
        digest_document.pop("record_sha256", None)
        record["record_sha256"] = _evidence_storage._canonical_sha256(digest_document)
        path = session_directory / f"record-{sequence:08d}.json"
        path.write_bytes(_evidence_storage._canonical_bytes(record))
        return str(record["record_sha256"])

    @staticmethod
    def _failing_directory_sync(path: Path):
        target = (path.stat().st_dev, path.stat().st_ino)
        real_sync = _evidence_storage._fsync_directory

        def fail_target(descriptor: int) -> None:
            opened = os.fstat(descriptor)
            if (opened.st_dev, opened.st_ino) == target:
                raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNAVAILABLE)
            real_sync(descriptor)

        return patch.object(_evidence_storage, "_fsync_directory", side_effect=fail_target)

    def test_record_verdict_rejects_malformed_request_before_attribute_access(self) -> None:
        reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))

        with self.assertRaises(evidence.EvidenceError) as caught:
            reviewer.record_verdict(
                None,  # type: ignore[arg-type]
                evidence.WriteRequest(operation_id=_operation("verdict-synthetic")),
            )

        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.INVALID_INPUT)

    def test_record_verdict_rejects_invalid_write_and_event_values(self) -> None:
        manifest, selected = self._assertion_selection()
        reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))
        valid = self._request(manifest, (selected,))
        requests = (
            replace(valid, verdict="PASS"),
            replace(valid, basis="objective_review"),
            replace(valid, sufficiency="sufficient"),
            replace(valid, reviewed_at="not-a-timestamp"),
            replace(valid, retrospective=1),
            replace(valid, direct_observation_declared=1),
            replace(valid, supersedes_verdict_sha256="not-a-hash"),
        )

        for index, request in enumerate(requests):
            with self.subTest(index=index):
                with self.assertRaises(evidence.EvidenceError) as caught:
                    reviewer.record_verdict(
                        request,
                        evidence.WriteRequest(
                            operation_id=_operation(f"invalid-verdict-value-{index}")
                        ),
                    )
                self.assertEqual(
                    caught.exception.code,
                    evidence.EvidenceErrorCode.INVALID_INPUT,
                )

        with self.assertRaises(evidence.EvidenceError) as caught:
            reviewer.record_verdict(valid, None)  # type: ignore[arg-type]
        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.INVALID_INPUT)
        self.assertEqual(list((self.root / "owner-verdicts").glob("verdict-*.json")), [])

    def test_objective_owner_pass_and_packet_are_deterministic(self) -> None:
        manifest = self._finalized_execution()
        snapshot = self.writer.snapshot("1" * 32)
        assertion_record = snapshot.records[1]
        reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))
        self.assertFalse(hasattr(self.writer, "record_verdict"))
        self.assertFalse(hasattr(reviewer, "append_assertion"))

        request = evidence.VerdictRequest(
            evidence_manifest_sha256=manifest.manifest_sha256,
            selected_records=(
                evidence.SelectedRecord(
                    sequence=assertion_record.sequence,
                    record_sha256=assertion_record.record_sha256,
                ),
            ),
            artifact_ref=_alias("artifact", "synthetic"),
            artifact_sha256="2" * 64,
            rules_ref=_alias("rules", "synthetic"),
            rules_version="1.0.0",
            rules_sha256="6" * 64,
            verdict=evidence.OwnerVerdictOutcome.PASS,
            basis=evidence.ReviewBasis.OBJECTIVE_REVIEW,
            sufficiency=evidence.Sufficiency.SUFFICIENT,
            retrospective=False,
            direct_observation_declared=False,
            reviewed_at="2026-10-23T01:00:05Z",
        )
        receipt = reviewer.record_verdict(
            request,
            evidence.WriteRequest(
                operation_id=_operation("owner-verdict-synthetic"),
                occurred_at="2026-10-23T01:00:05Z",
            ),
        )
        packet_one = reviewer.review_packet(manifest.manifest_sha256)
        packet_two = reviewer.review_packet(manifest.manifest_sha256)

        self.assertEqual(receipt.sequence, 1)
        self.assertEqual(packet_one, packet_two)
        packet = json.loads(packet_one)
        self.assertEqual(packet["execution_manifest_sha256"], manifest.manifest_sha256)
        self.assertNotIn("generated_at", packet_one.decode("utf-8"))
        verdict = reviewer.latest_verdict(_alias("scenario", "synthetic"))
        self.assertIsNotNone(verdict)
        assert verdict is not None
        self.assertEqual(verdict.verdict, evidence.OwnerVerdictOutcome.PASS)
        verdict_document = json.loads(
            (self.root / "owner-verdicts" / "verdict-00000001.json").read_text()
        )
        self.assertEqual(verdict_document["event"]["rules_version"], "1.0.0")

    def test_manifest_lookup_skips_an_empty_lexically_preceding_session(self) -> None:
        manifest = self._finalized_execution()
        empty_session = self.root / "executions" / ("0" * 32)
        empty_session.mkdir(mode=0o700)
        reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))

        packet = json.loads(reviewer.review_packet(manifest.manifest_sha256))

        self.assertEqual(packet["execution_manifest_sha256"], manifest.manifest_sha256)

    def test_manifest_lookup_rejects_a_nonempty_corrupt_session(self) -> None:
        manifest = self._finalized_execution()
        corrupt_session = self.root / "executions" / ("0" * 32)
        corrupt_session.mkdir(mode=0o700)
        corrupt_record = corrupt_session / "record-00000001.json"
        corrupt_record.write_bytes(b"{}")
        corrupt_record.chmod(0o600)
        reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))

        with self.assertRaises(evidence.EvidenceError) as caught:
            reviewer.review_packet(manifest.manifest_sha256)

        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.CORRUPT)

    def test_persisted_verdict_rejects_boolean_schema_and_sequence(self) -> None:
        manifest, selected = self._assertion_selection()
        reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))
        reviewer.record_verdict(
            self._request(manifest, (selected,)),
            evidence.WriteRequest(
                operation_id=_operation("owner-verdict-synthetic"),
                occurred_at="2026-10-23T01:00:05Z",
            ),
        )
        verdict_path = self.root / "owner-verdicts" / "verdict-00000001.json"
        original = verdict_path.read_bytes()

        for field in ("schema_version", "sequence"):
            with self.subTest(field=field):
                document = json.loads(original)
                document[field] = True
                self._rewrite_verdict(verdict_path, document)
                with self.assertRaises(evidence.EvidenceError) as caught:
                    reviewer.latest_verdict(_alias("scenario", "synthetic"))
                self.assertEqual(
                    caught.exception.code,
                    evidence.EvidenceErrorCode.CORRUPT,
                )

    def test_persisted_verdict_rejects_malformed_data_and_event_shapes(self) -> None:
        manifest, selected = self._assertion_selection()
        reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))
        reviewer.record_verdict(
            self._request(manifest, (selected,)),
            evidence.WriteRequest(
                operation_id=_operation("owner-verdict-corrupt-shapes"),
                occurred_at="2026-10-23T01:00:05Z",
            ),
        )
        path = self.root / "owner-verdicts" / "verdict-00000001.json"
        original_bytes = path.read_bytes()
        original_document = json.loads(original_bytes)

        bad_record_digest = copy.deepcopy(original_document)
        bad_record_digest["verdict_sha256"] = "0" * 64
        bad_event_digest = copy.deepcopy(original_document)
        bad_event_digest["event_sha256"] = "0" * 64
        serialization_cases = (
            (b"\xff", evidence.EvidenceErrorCode.CORRUPT),
            (b"{", evidence.EvidenceErrorCode.CORRUPT),
            (
                original_bytes.replace(b'"sequence":1', b'"sequence":1.0', 1),
                evidence.EvidenceErrorCode.FLOAT_REJECTED,
            ),
            (
                original_bytes.replace(b'"sequence":1', b'"sequence":NaN', 1),
                evidence.EvidenceErrorCode.NON_FINITE_NUMBER,
            ),
            (b"[]", evidence.EvidenceErrorCode.CORRUPT),
            (
                json.dumps(original_document, indent=2).encode("utf-8"),
                evidence.EvidenceErrorCode.CORRUPT,
            ),
            (
                _evidence_storage._canonical_bytes(bad_record_digest),
                evidence.EvidenceErrorCode.CORRUPT,
            ),
            (
                _evidence_storage._canonical_bytes(bad_event_digest),
                evidence.EvidenceErrorCode.CORRUPT,
            ),
        )

        for index, (raw, expected) in enumerate(serialization_cases):
            with self.subTest(serialization=index):
                path.write_bytes(raw)
                with self.assertRaises(evidence.EvidenceError) as caught:
                    reviewer.latest_verdict(_alias("scenario", "synthetic"))
                self.assertEqual(caught.exception.code, expected)

        def duplicate_selected_records(document: dict[str, object]) -> None:
            event = document["event"]
            self.assertIsInstance(event, dict)
            selected_records = event["selected_records"]
            self.assertIsInstance(selected_records, list)
            first = copy.deepcopy(selected_records[0])
            event["selected_records"] = [
                first,
                {**first, "sequence": first["sequence"] - 1},
            ]

        document_cases = (
            lambda document: document.__setitem__("extra", True),
            lambda document: document.__setitem__("schema_version", "1"),
            lambda document: document["event"].__setitem__("extra", True),
            lambda document: document["event"].__setitem__("event_type", "other"),
            lambda document: document["event"].__setitem__("artifact_ref", "../outside"),
            lambda document: document["event"].__setitem__(
                "direct_observation_declared", 1
            ),
            lambda document: document["event"].__setitem__(
                "occurred_at", "not-a-timestamp"
            ),
            lambda document: document["event"].__setitem__("retrospective", 1),
            lambda document: document["event"].__setitem__(
                "reviewed_at", "not-a-timestamp"
            ),
            lambda document: document["event"].__setitem__(
                "selected_records", [{"sequence": 1}]
            ),
            duplicate_selected_records,
            lambda document: document["event"].__setitem__(
                "selected_records", [{"sequence": 1, "record_sha256": "invalid"}]
            ),
        )

        for index, mutate in enumerate(document_cases):
            with self.subTest(document=index):
                document = copy.deepcopy(original_document)
                mutate(document)
                self._rewrite_verdict(path, document)
                with self.assertRaises(evidence.EvidenceError) as caught:
                    reviewer.latest_verdict(_alias("scenario", "synthetic"))
                self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.CORRUPT)

    def test_absent_and_all_explicit_owner_outcomes_remain_distinct(self) -> None:
        manifest, selected = self._assertion_selection()
        reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))
        self.assertIsNone(reviewer.latest_verdict(_alias("scenario", "synthetic")))
        previous: str | None = None
        outcomes = (
            evidence.OwnerVerdictOutcome.PASS,
            evidence.OwnerVerdictOutcome.FAIL,
            evidence.OwnerVerdictOutcome.BLOCKED,
            evidence.OwnerVerdictOutcome.NOT_RUN,
        )
        for index, outcome in enumerate(outcomes, start=1):
            receipt = reviewer.record_verdict(
                self._request(
                    manifest,
                    (selected,),
                    verdict=outcome,
                    supersedes=previous,
                    reviewed_at=f"2026-10-23T01:00:0{index + 4}Z",
                ),
                evidence.WriteRequest(
                    operation_id=_operation(f"owner-verdict-{index}"),
                    occurred_at=f"2026-10-23T01:00:0{index + 4}Z",
                ),
            )
            previous = receipt.verdict_sha256
            latest = reviewer.latest_verdict(_alias("scenario", "synthetic"))
            self.assertIsNotNone(latest)
            assert latest is not None
            self.assertEqual(latest.verdict, outcome)

        verdict_directory = self.root / "owner-verdicts"
        self.assertEqual(len(list(verdict_directory.glob("verdict-*.json"))), 4)

    def test_latest_verdict_returns_none_for_absent_owner_directory(self) -> None:
        reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))

        self.assertIsNone(reviewer.latest_verdict(_alias("scenario", "synthetic")))
        self.assertFalse((self.root / "owner-verdicts").exists())

    def test_latest_verdict_propagates_owner_directory_regular_file(self) -> None:
        self.root.mkdir(mode=0o700)
        (self.root / "owner-verdicts").write_text("not a directory", encoding="utf-8")
        reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))

        with self.assertRaises(evidence.EvidenceError) as caught:
            reviewer.latest_verdict(_alias("scenario", "synthetic"))

        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.UNAVAILABLE)

    def test_latest_verdict_propagates_owner_directory_access_failure(self) -> None:
        reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))
        unavailable = evidence.EvidenceError(evidence.EvidenceErrorCode.UNAVAILABLE)

        with patch.object(
            _evidence_storage,
            "_ensure_private_directory",
            side_effect=unavailable,
        ):
            with self.assertRaises(evidence.EvidenceError) as caught:
                reviewer.latest_verdict(_alias("scenario", "synthetic"))

        self.assertIs(caught.exception, unavailable)
        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.UNAVAILABLE)

    def test_owner_verdict_cannot_predate_execution_finalization(self) -> None:
        manifest, selected = self._assertion_selection()
        reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))
        request = replace(
            self._request(manifest, (selected,)),
            reviewed_at="2026-10-23T01:00:02Z",
        )

        with self.assertRaises(evidence.EvidenceError) as caught:
            reviewer.record_verdict(
                request,
                evidence.WriteRequest(
                    operation_id=_operation("owner-verdict-before-finalization"),
                    occurred_at="2026-10-23T01:00:05Z",
                ),
            )

        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.INVALID_INPUT)
        self.assertFalse(
            (self.root / "owner-verdicts" / "verdict-00000001.json").exists()
        )

    def test_objective_pass_requires_selected_execution_evidence(self) -> None:
        manifest, _selected = self._assertion_selection(required_evidence_refs=())
        reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))

        with self.assertRaises(evidence.EvidenceError) as caught:
            reviewer.record_verdict(
                self._request(manifest, ()),
                evidence.WriteRequest(
                    operation_id=_operation("objective-pass-without-evidence"),
                    occurred_at="2026-10-23T01:00:05Z",
                ),
            )

        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.INVALID_INPUT)
        verdict_directory = self.root / "owner-verdicts"
        self.assertEqual(list(verdict_directory.glob("verdict-*.json")), [])

    def test_objective_owner_review_rejects_every_binding_mismatch(self) -> None:
        manifest, selected = self._assertion_selection()
        reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))
        valid = self._request(manifest, (selected,))
        invalid_requests = (
            replace(valid, evidence_manifest_sha256="a" * 64),
            replace(valid, artifact_ref=_alias("artifact", "other")),
            replace(valid, artifact_sha256="b" * 64),
            replace(valid, rules_ref=_alias("rules", "other")),
            replace(valid, rules_version="2.0.0"),
            replace(valid, rules_sha256="c" * 64),
            replace(valid, selected_records=(replace(selected, record_sha256="d" * 64),)),
        )
        for index, request in enumerate(invalid_requests):
            with self.subTest(index=index):
                with self.assertRaises(evidence.EvidenceError) as caught:
                    reviewer.record_verdict(
                        request,
                        evidence.WriteRequest(operation_id=_operation(f"invalid-binding-{index}")),
                    )
                self.assertIn(
                    caught.exception.code,
                    {
                        evidence.EvidenceErrorCode.MANIFEST_MISSING,
                        evidence.EvidenceErrorCode.VERDICT_BINDING_INVALID,
                    },
                )

        opened_only = evidence.SelectedRecord(
            sequence=1,
            record_sha256=self.writer.snapshot("1" * 32).records[0].record_sha256,
        )
        with self.assertRaises(evidence.EvidenceError) as caught:
            reviewer.record_verdict(
                self._request(manifest, (opened_only,)),
                evidence.WriteRequest(operation_id=_operation("insufficient-evidence")),
            )
        self.assertEqual(
            caught.exception.code,
            evidence.EvidenceErrorCode.VERDICT_SUFFICIENCY_INVALID,
        )

    def test_direct_owner_basis_requires_declaration_and_records_limits(self) -> None:
        manifest, selected = self._assertion_selection()
        reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))
        with self.assertRaises(evidence.EvidenceError) as caught:
            reviewer.record_verdict(
                self._request(
                    manifest,
                    (selected,),
                    basis=evidence.ReviewBasis.DIRECT_OWNER_OBSERVATION,
                ),
                evidence.WriteRequest(operation_id=_operation("direct-without-declaration")),
            )
        self.assertEqual(
            caught.exception.code,
            evidence.EvidenceErrorCode.VERDICT_SUFFICIENCY_INVALID,
        )
        with self.assertRaises(evidence.EvidenceError) as caught:
            reviewer.record_verdict(
                self._request(
                    manifest,
                    (selected,),
                    verdict=evidence.OwnerVerdictOutcome.NOT_RUN,
                    retrospective=True,
                ),
                evidence.WriteRequest(operation_id=_operation("retrospective-not-allowed")),
            )
        self.assertEqual(
            caught.exception.code,
            evidence.EvidenceErrorCode.VERDICT_SUFFICIENCY_INVALID,
        )

        reviewer.record_verdict(
            self._request(
                manifest,
                (selected,),
                basis=evidence.ReviewBasis.DIRECT_OWNER_OBSERVATION,
                direct_observation_declared=True,
            ),
            evidence.WriteRequest(
                operation_id=_operation("direct-owner-observation"),
                occurred_at="2026-10-23T01:00:05Z",
            ),
        )
        raw = (self.root / "owner-verdicts" / "verdict-00000001.json").read_bytes()
        document = json.loads(raw)
        self.assertEqual(
            document["event"]["owner_identity_authentication"],
            "self_asserted",
        )
        self.assertEqual(
            document["event"]["attendance_authentication"],
            "not_provided",
        )

    def test_direct_observation_declaration_rejects_non_booleans(self) -> None:
        manifest, selected = self._assertion_selection()
        reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))
        invalid_values = (0, "", None, 1, "true", [], [False], object())

        for index, value in enumerate(invalid_values):
            with self.subTest(value=value):
                with self.assertRaises(evidence.EvidenceError) as caught:
                    reviewer.record_verdict(
                        self._request(
                            manifest,
                            (selected,),
                            direct_observation_declared=value,
                        ),
                        evidence.WriteRequest(
                            operation_id=_operation(f"non-boolean-declaration-{index}")
                        ),
                    )
                self.assertEqual(
                    caught.exception.code,
                    evidence.EvidenceErrorCode.INVALID_INPUT,
                )

        verdict_path = self.root / "owner-verdicts" / "verdict-00000001.json"
        self.assertFalse(verdict_path.exists())

    def test_direct_observation_declaration_matches_selected_basis(self) -> None:
        manifest, selected = self._assertion_selection()
        reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))

        objective = reviewer.record_verdict(
            self._request(
                manifest,
                (selected,),
                basis=evidence.ReviewBasis.OBJECTIVE_REVIEW,
                direct_observation_declared=False,
            ),
            evidence.WriteRequest(
                operation_id=_operation("objective-without-direct-observation")
            ),
        )
        direct = reviewer.record_verdict(
            self._request(
                manifest,
                (selected,),
                basis=evidence.ReviewBasis.DIRECT_OWNER_OBSERVATION,
                direct_observation_declared=True,
                supersedes=objective.verdict_sha256,
            ),
            evidence.WriteRequest(
                operation_id=_operation("direct-with-observation")
            ),
        )

        self.assertEqual(objective.sequence, 1)
        self.assertEqual(direct.sequence, 2)

    def test_owner_verdict_rejects_disabled_review_bases(self) -> None:
        requirements = evidence.ReviewRequirements(
            required_evidence_refs=(_alias("evidence", "synthetic"),),
            objective_review_allowed=False,
            direct_owner_observation_allowed=False,
            retrospective_allowed=False,
        )
        manifest, selected = self._assertion_selection(review_requirements=requirements)
        reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))
        requests = (
            self._request(manifest, (selected,)),
            self._request(
                manifest,
                (selected,),
                basis=evidence.ReviewBasis.DIRECT_OWNER_OBSERVATION,
                direct_observation_declared=True,
            ),
        )

        for index, request in enumerate(requests):
            with self.subTest(index=index):
                with self.assertRaises(evidence.EvidenceError) as caught:
                    reviewer.record_verdict(
                        request,
                        evidence.WriteRequest(
                            operation_id=_operation(f"disabled-review-basis-{index}")
                        ),
                    )
                self.assertEqual(
                    caught.exception.code,
                    evidence.EvidenceErrorCode.VERDICT_SUFFICIENCY_INVALID,
                )

    def test_owner_verdict_rejects_objective_direct_claim_and_insufficient_pass(
        self,
    ) -> None:
        manifest, selected = self._assertion_selection()
        reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))
        requests = (
            (
                self._request(
                    manifest,
                    (selected,),
                    direct_observation_declared=True,
                ),
                evidence.EvidenceErrorCode.INVALID_INPUT,
            ),
            (
                self._request(
                    manifest,
                    (selected,),
                    sufficiency=evidence.Sufficiency.INSUFFICIENT,
                ),
                evidence.EvidenceErrorCode.VERDICT_SUFFICIENCY_INVALID,
            ),
        )

        for index, (request, expected) in enumerate(requests):
            with self.subTest(index=index):
                with self.assertRaises(evidence.EvidenceError) as caught:
                    reviewer.record_verdict(
                        request,
                        evidence.WriteRequest(
                            operation_id=_operation(f"invalid-review-outcome-{index}")
                        ),
                    )
                self.assertEqual(caught.exception.code, expected)

    def test_lost_verdict_ack_retry_completes_parent_sync(self) -> None:
        manifest, selected = self._assertion_selection()
        request = self._request(manifest, (selected,))
        reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))
        write_request = evidence.WriteRequest(
            operation_id=_operation("owner-verdict-synthetic"),
            occurred_at="2026-10-23T01:00:05Z",
        )

        def crash(stage: str) -> None:
            if stage == "after_publish_before_parent_sync":
                raise RuntimeError

        with patch.object(_evidence_storage, "_transition", side_effect=crash):
            with self.assertRaises(RuntimeError):
                reviewer.record_verdict(request, write_request)

        verdict_directory = self.root / "owner-verdicts"
        with self._failing_directory_sync(verdict_directory):
            with self.assertRaises(evidence.EvidenceError) as caught:
                reviewer.record_verdict(request, write_request)
        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.UNAVAILABLE)

    def test_verdict_publish_collision_maps_to_expected_head_conflict(self) -> None:
        manifest, selected = self._assertion_selection()
        reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))

        with patch.object(
            _evidence_storage,
            "_publish_no_replace",
            side_effect=FileExistsError,
        ):
            with self.assertRaises(evidence.EvidenceError) as caught:
                reviewer.record_verdict(
                    self._request(manifest, (selected,)),
                    evidence.WriteRequest(
                        operation_id=_operation("owner-verdict-publish-collision"),
                        occurred_at="2026-10-23T01:00:05Z",
                    ),
                )

        self.assertEqual(
            caught.exception.code,
            evidence.EvidenceErrorCode.EXPECTED_HEAD_CONFLICT,
        )
        self.assertFalse(
            (self.root / "owner-verdicts" / "verdict-00000001.json").exists()
        )

    def test_persisted_owner_verdict_rejects_internal_operation_id(self) -> None:
        manifest, selected = self._assertion_selection()
        reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))
        reviewer.record_verdict(
            self._request(manifest, (selected,)),
            evidence.WriteRequest(
                operation_id=_operation("owner-verdict-synthetic"),
                occurred_at="2026-10-23T01:00:05Z",
            ),
        )
        path = self.root / "owner-verdicts" / "verdict-00000001.json"
        document = json.loads(path.read_text())
        document["event"]["operation_id"] = f"internal-{'a' * 32}"
        self._rewrite_verdict(path, document)

        with self.assertRaises(evidence.EvidenceError) as caught:
            reviewer.latest_verdict(_alias("scenario", "synthetic"))

        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.CORRUPT)

    def test_persisted_verdicts_revalidate_binding_sufficiency_and_privacy(self) -> None:
        manifest, selected = self._assertion_selection()
        request = self._request(manifest, (selected,))
        reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))
        reviewer.record_verdict(
            request,
            evidence.WriteRequest(
                operation_id=_operation("owner-verdict-synthetic"),
                occurred_at="2026-10-23T01:00:05Z",
            ),
        )
        path = self.root / "owner-verdicts" / "verdict-00000001.json"
        original = json.loads(path.read_text())
        cases = {
            "manifest": ("evidence_manifest_sha256", "9" * 64),
            "artifact": ("artifact_sha256", "8" * 64),
            "rules": ("rules_version", "2.0.0"),
            "sufficiency": ("sufficiency", evidence.Sufficiency.INSUFFICIENT.value),
            "privacy": ("owner_alias", "token"),
            "enum-type": ("verdict", []),
        }

        for case, (field, value) in cases.items():
            with self.subTest(case=case):
                document = copy.deepcopy(original)
                document["event"][field] = value
                self._rewrite_verdict(path, document)

                with self.assertRaises(evidence.EvidenceError) as caught:
                    reviewer.latest_verdict(_alias("scenario", "synthetic"))

                self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.CORRUPT)

    def test_owner_aliases_reject_untyped_private_and_payload_values_on_write(self) -> None:
        for value in ("pokemon-red", "screenshot", "log-entry", "a" * 64, "../private"):
            with self.subTest(value=value):
                with self.assertRaises(evidence.EvidenceError) as caught:
                    self.store.owner_reviewer(value)
                self.assertEqual(
                    caught.exception.code,
                    evidence.EvidenceErrorCode.PRIVATE_DATA_REJECTED,
                )

    def test_review_packet_rejects_hash_recomputed_private_aliases(self) -> None:
        manifest, _selected = self._assertion_selection()
        session_directory = self.root / "executions" / ("1" * 32)
        record_paths = {
            sequence: session_directory / f"record-{sequence:08d}.json"
            for sequence in range(1, 4)
        }
        originals = {sequence: path.read_bytes() for sequence, path in record_paths.items()}
        reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))
        cases = {
            "private-artifact-identity": (
                1,
                lambda event: event["provenance"]["artifact"].__setitem__(
                    "artifact_ref", "pokemon-red"
                ),
            ),
            "private-scenario-hash": (
                1,
                lambda event: event.__setitem__("scenario_id", "a" * 64),
            ),
            "screenshot-payload": (
                2,
                lambda event: event.__setitem__("evidence_refs", ["screenshot"]),
            ),
            "log-payload": (
                2,
                lambda event: event.__setitem__("evidence_refs", ["log-entry"]),
            ),
            "private-path": (
                1,
                lambda event: event["provenance"]["artifact"].__setitem__(
                    "artifact_ref", "../private/rom.gba"
                ),
            ),
            "credential": (
                2,
                lambda event: event.__setitem__("rules_ref", "password-secret"),
            ),
            "operation-payload": (
                2,
                lambda event: event.__setitem__("operation_id", "screenshot"),
            ),
        }

        try:
            for case, (sequence, mutate) in cases.items():
                with self.subTest(case=case):
                    for record_sequence, path in record_paths.items():
                        path.write_bytes(originals[record_sequence])
                        path.chmod(0o600)
                    record = json.loads(originals[sequence])
                    mutate(record["event"])
                    self._rewrite_execution_record(session_directory, sequence, record)
                    for later_sequence in range(sequence + 1, 4):
                        record_paths[later_sequence].unlink()
                    with self.assertRaises(evidence.EvidenceError) as caught:
                        reviewer.review_packet(manifest.manifest_sha256)
                    self.assertEqual(
                        caught.exception.code,
                        evidence.EvidenceErrorCode.CORRUPT,
                    )
        finally:
            for sequence, path in record_paths.items():
                path.write_bytes(originals[sequence])
                path.chmod(0o600)

    def test_persisted_verdict_rejects_another_scenario_with_recomputed_hashes(
        self,
    ) -> None:
        manifest, selected = self._assertion_selection()
        reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))
        reviewer.record_verdict(
            self._request(manifest, (selected,)),
            evidence.WriteRequest(
                operation_id=_operation("owner-verdict-scenario-tampering"),
                occurred_at="2026-10-23T01:00:05Z",
            ),
        )
        verdict_path = self.root / "owner-verdicts" / "verdict-00000001.json"
        document = json.loads(verdict_path.read_text())
        self.assertIsInstance(document, dict)
        event = document["event"]
        self.assertIsInstance(event, dict)
        event["scenario_id"] = _alias("scenario", "other")
        self._rewrite_verdict(verdict_path, document)

        with self.assertRaises(evidence.EvidenceError) as caught:
            reviewer.latest_verdict(_alias("scenario", "other"))

        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.CORRUPT)

    def test_persisted_verdict_rejects_review_before_terminal_with_recomputed_hashes(
        self,
    ) -> None:
        manifest, selected = self._assertion_selection()
        reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))
        reviewer.record_verdict(
            self._request(manifest, (selected,)),
            evidence.WriteRequest(
                operation_id=_operation("owner-verdict-before-terminal-tampering"),
                occurred_at="2026-10-23T01:00:05Z",
            ),
        )
        verdict_path = self.root / "owner-verdicts" / "verdict-00000001.json"
        document = json.loads(verdict_path.read_text())
        self.assertIsInstance(document, dict)
        event = document["event"]
        self.assertIsInstance(event, dict)
        event["reviewed_at"] = "2026-10-23T01:00:02Z"
        self._rewrite_verdict(verdict_path, document)

        with self.assertRaises(evidence.EvidenceError) as caught:
            reviewer.latest_verdict(_alias("scenario", "synthetic"))

        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.CORRUPT)

    def test_persisted_verdict_rejects_review_after_occurrence(self) -> None:
        manifest, selected = self._assertion_selection()
        reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))
        reviewer.record_verdict(
            self._request(manifest, (selected,)),
            evidence.WriteRequest(
                operation_id=_operation("owner-verdict-reviewed-after-occurrence"),
                occurred_at="2026-10-23T01:00:05Z",
            ),
        )
        verdict_path = self.root / "owner-verdicts" / "verdict-00000001.json"
        document = json.loads(verdict_path.read_text())
        event = document["event"]
        self.assertIsInstance(event, dict)
        event["reviewed_at"] = "2026-10-23T01:00:07Z"
        self._rewrite_verdict(verdict_path, document)

        with self.assertRaises(evidence.EvidenceError) as caught:
            reviewer.latest_verdict(_alias("scenario", "synthetic"))

        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.CORRUPT)

    def test_persisted_supersession_must_match_the_prior_logical_verdict(self) -> None:
        manifest, selected = self._assertion_selection()
        reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))
        first = reviewer.record_verdict(
            self._request(manifest, (selected,)),
            evidence.WriteRequest(
                operation_id=_operation("owner-verdict-first"),
                occurred_at="2026-10-23T01:00:05Z",
            ),
        )
        reviewer.record_verdict(
            self._request(
                manifest,
                (selected,),
                supersedes=first.verdict_sha256,
                reviewed_at="2026-10-23T01:00:06Z",
            ),
            evidence.WriteRequest(
                operation_id=_operation("owner-verdict-second"),
                occurred_at="2026-10-23T01:00:06Z",
            ),
        )
        path = self.root / "owner-verdicts" / "verdict-00000002.json"
        document = json.loads(path.read_text())
        document["event"]["supersedes_verdict_sha256"] = None
        self._rewrite_verdict(path, document)

        with self.assertRaises(evidence.EvidenceError) as caught:
            reviewer.latest_verdict(_alias("scenario", "synthetic"))

        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.CORRUPT)

    def test_verdict_append_rejects_explicit_timestamp_before_latest(self) -> None:
        manifest, selected = self._assertion_selection()
        reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))
        first = reviewer.record_verdict(
            self._request(manifest, (selected,)),
            evidence.WriteRequest(
                operation_id=_operation("owner-verdict-before-clock-order"),
                occurred_at="2026-10-23T01:00:05Z",
            ),
        )
        prior = reviewer.latest_verdict(_alias("scenario", "synthetic"))
        assert prior is not None

        with self.assertRaises(evidence.EvidenceError) as caught:
            reviewer.record_verdict(
                self._request(
                    manifest,
                    (selected,),
                    supersedes=first.verdict_sha256,
                    reviewed_at="2026-10-23T01:00:04Z",
                ),
                evidence.WriteRequest(
                    operation_id=_operation("owner-verdict-explicit-earlier"),
                    occurred_at="2026-10-23T01:00:04Z",
                ),
            )

        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.INVALID_INPUT)
        self.assertFalse(
            (self.root / "owner-verdicts" / "verdict-00000002.json").exists()
        )
        self.assertEqual(
            reviewer.latest_verdict(_alias("scenario", "synthetic")),
            prior,
        )

    def test_verdict_append_rejects_backwards_wall_clock(self) -> None:
        manifest, selected = self._assertion_selection()
        reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))
        first = reviewer.record_verdict(
            self._request(manifest, (selected,)),
            evidence.WriteRequest(
                operation_id=_operation("owner-verdict-before-backwards-clock"),
                occurred_at="2026-10-23T01:00:05Z",
            ),
        )
        prior = reviewer.latest_verdict(_alias("scenario", "synthetic"))
        assert prior is not None

        with patch.object(
            _evidence_storage,
            "_now_timestamp",
            return_value="2026-10-23T01:00:04Z",
        ):
            with self.assertRaises(evidence.EvidenceError) as caught:
                reviewer.record_verdict(
                    self._request(
                        manifest,
                        (selected,),
                        supersedes=first.verdict_sha256,
                        reviewed_at="2026-10-23T01:00:04Z",
                    ),
                    evidence.WriteRequest(
                        operation_id=_operation("owner-verdict-backwards-clock"),
                    ),
                )

        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.INVALID_INPUT)
        self.assertFalse(
            (self.root / "owner-verdicts" / "verdict-00000002.json").exists()
        )
        self.assertEqual(
            reviewer.latest_verdict(_alias("scenario", "synthetic")),
            prior,
        )

    def test_verdict_retry_accepts_occurrence_before_reviewed_at(self) -> None:
        manifest, selected = self._assertion_selection()
        reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))
        request = self._request(manifest, (selected,))
        write_request = evidence.WriteRequest(
            operation_id=_operation("owner-verdict-rollback-retry"),
            occurred_at="2026-10-23T01:00:05Z",
        )
        first = reviewer.record_verdict(request, write_request)

        retry = reviewer.record_verdict(
            request,
            replace(write_request, occurred_at="2026-10-23T01:00:04Z"),
        )

        self.assertTrue(retry.idempotent)
        self.assertEqual(retry.sequence, first.sequence)
        self.assertEqual(retry.verdict_sha256, first.verdict_sha256)
        latest = reviewer.latest_verdict(_alias("scenario", "synthetic"))
        assert latest is not None
        self.assertEqual(latest.verdict_sha256, first.verdict_sha256)

    def test_verdict_rejects_mismatched_expected_head_before_first_append(self) -> None:
        manifest, selected = self._assertion_selection()
        reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))

        with self.assertRaises(evidence.EvidenceError) as caught:
            reviewer.record_verdict(
                self._request(manifest, (selected,)),
                evidence.WriteRequest(
                    operation_id=_operation("owner-verdict-mismatched-head"),
                    occurred_at="2026-10-23T01:00:05Z",
                    expected_head_sha256="f" * 64,
                ),
            )

        self.assertEqual(
            caught.exception.code,
            evidence.EvidenceErrorCode.EXPECTED_HEAD_CONFLICT,
        )
        self.assertFalse(
            (self.root / "owner-verdicts" / "verdict-00000001.json").exists()
        )

    def test_verdict_accepts_expected_head_matching_current_chain(self) -> None:
        manifest, selected = self._assertion_selection()
        reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))
        first = reviewer.record_verdict(
            self._request(manifest, (selected,)),
            evidence.WriteRequest(
                operation_id=_operation("owner-verdict-current-head-first"),
                occurred_at="2026-10-23T01:00:05Z",
            ),
        )

        second = reviewer.record_verdict(
            self._request(
                manifest,
                (selected,),
                supersedes=first.verdict_sha256,
            ),
            evidence.WriteRequest(
                operation_id=_operation("owner-verdict-current-head-second"),
                occurred_at="2026-10-23T01:00:06Z",
                expected_head_sha256=first.verdict_sha256,
            ),
        )

        self.assertFalse(second.idempotent)
        self.assertEqual(second.sequence, 2)
        latest = reviewer.latest_verdict(_alias("scenario", "synthetic"))
        assert latest is not None
        self.assertEqual(latest.verdict_sha256, second.verdict_sha256)

    def test_verdict_rejects_mismatched_expected_head_after_append(self) -> None:
        manifest, selected = self._assertion_selection()
        reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))
        first = reviewer.record_verdict(
            self._request(manifest, (selected,)),
            evidence.WriteRequest(
                operation_id=_operation("owner-verdict-head-before-conflict"),
                occurred_at="2026-10-23T01:00:05Z",
            ),
        )

        with self.assertRaises(evidence.EvidenceError) as caught:
            reviewer.record_verdict(
                self._request(
                    manifest,
                    (selected,),
                    supersedes=first.verdict_sha256,
                    reviewed_at="2026-10-23T01:00:06Z",
                ),
                evidence.WriteRequest(
                    operation_id=_operation("owner-verdict-head-conflict"),
                    occurred_at="2026-10-23T01:00:06Z",
                    expected_head_sha256="f" * 64,
                ),
            )

        self.assertEqual(
            caught.exception.code,
            evidence.EvidenceErrorCode.EXPECTED_HEAD_CONFLICT,
        )
        self.assertFalse(
            (self.root / "owner-verdicts" / "verdict-00000002.json").exists()
        )
        latest = reviewer.latest_verdict(_alias("scenario", "synthetic"))
        assert latest is not None
        self.assertEqual(latest.verdict_sha256, first.verdict_sha256)

    def test_verdict_retry_accepts_stale_expected_head_for_exact_operation(self) -> None:
        manifest, selected = self._assertion_selection()
        reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))
        first_request = self._request(manifest, (selected,))
        first_write_request = evidence.WriteRequest(
            operation_id=_operation("owner-verdict-stale-head-retry"),
            occurred_at="2026-10-23T01:00:05Z",
        )
        first = reviewer.record_verdict(first_request, first_write_request)
        second = reviewer.record_verdict(
            self._request(
                manifest,
                (selected,),
                supersedes=first.verdict_sha256,
            ),
            evidence.WriteRequest(
                operation_id=_operation("owner-verdict-stale-head-later"),
                occurred_at="2026-10-23T01:00:06Z",
                expected_head_sha256=first.verdict_sha256,
            ),
        )

        retry = reviewer.record_verdict(
            first_request,
            replace(
                first_write_request,
                occurred_at="2026-10-23T01:00:07Z",
                expected_head_sha256=first.verdict_sha256,
            ),
        )

        self.assertTrue(retry.idempotent)
        self.assertEqual(retry.sequence, first.sequence)
        self.assertEqual(retry.verdict_sha256, first.verdict_sha256)
        latest = reviewer.latest_verdict(_alias("scenario", "synthetic"))
        assert latest is not None
        self.assertEqual(latest.verdict_sha256, second.verdict_sha256)

    def test_verdict_retry_rejects_malformed_expected_head_before_idempotent_response(
        self,
    ) -> None:
        manifest, selected = self._assertion_selection()
        reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))
        request = self._request(manifest, (selected,))
        write_request = evidence.WriteRequest(
            operation_id=_operation("owner-verdict-malformed-head-retry"),
            occurred_at="2026-10-23T01:00:05Z",
        )
        first = reviewer.record_verdict(request, write_request)

        with self.assertRaises(evidence.EvidenceError) as caught:
            reviewer.record_verdict(
                request,
                replace(write_request, expected_head_sha256="not-a-sha256"),
            )

        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.INVALID_INPUT)
        latest = reviewer.latest_verdict(_alias("scenario", "synthetic"))
        assert latest is not None
        self.assertEqual(latest.verdict_sha256, first.verdict_sha256)

    def test_verdict_retry_rejects_non_boolean_declarations_before_idempotent_response(
        self,
    ) -> None:
        manifest, selected = self._assertion_selection()
        reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))
        request = self._request(manifest, (selected,))
        write_request = evidence.WriteRequest(
            operation_id=_operation("owner-verdict-non-boolean-declaration-retry"),
            occurred_at="2026-10-23T01:00:05Z",
        )
        first = reviewer.record_verdict(request, write_request)

        for field in ("retrospective", "direct_observation_declared"):
            for malformed in (0, 1):
                with self.subTest(field=field, malformed=malformed):
                    with self.assertRaises(evidence.EvidenceError) as caught:
                        reviewer.record_verdict(
                            replace(request, **{field: malformed}),
                            replace(write_request, occurred_at="2026-10-23T01:00:06Z"),
                        )
                    self.assertEqual(
                        caught.exception.code,
                        evidence.EvidenceErrorCode.INVALID_INPUT,
                    )

        retry = reviewer.record_verdict(
            request,
            replace(write_request, occurred_at="2026-10-23T01:00:07Z"),
        )
        self.assertTrue(retry.idempotent)
        self.assertEqual(retry.verdict_sha256, first.verdict_sha256)

    def test_verdict_retry_is_idempotent_and_changed_content_conflicts(self) -> None:
        manifest, selected = self._assertion_selection()
        reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))
        request = self._request(manifest, (selected,))
        write_request = evidence.WriteRequest(
            operation_id=_operation("owner-verdict-idempotent"),
            occurred_at="2026-10-23T01:00:05Z",
        )
        first = reviewer.record_verdict(request, write_request)
        retry = reviewer.record_verdict(
            request,
            replace(write_request, occurred_at="2026-10-23T01:00:06Z"),
        )
        self.assertTrue(retry.idempotent)
        self.assertEqual(retry.verdict_sha256, first.verdict_sha256)

        with self.assertRaises(evidence.EvidenceError) as caught:
            reviewer.record_verdict(
                replace(request, verdict=evidence.OwnerVerdictOutcome.FAIL),
                write_request,
            )
        self.assertEqual(
            caught.exception.code,
            evidence.EvidenceErrorCode.OPERATION_CONFLICT,
        )

    def test_corrupt_verdict_chain_is_rejected_with_stable_error(self) -> None:
        manifest, selected = self._assertion_selection()
        reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))
        reviewer.record_verdict(
            self._request(manifest, (selected,)),
            evidence.WriteRequest(
                operation_id=_operation("owner-verdict-corrupt"),
                occurred_at="2026-10-23T01:00:05Z",
            ),
        )
        path = self.root / "owner-verdicts" / "verdict-00000001.json"
        document = json.loads(path.read_bytes())
        document["event"]["verdict"] = "MAYBE"
        document["event_sha256"] = hashlib.sha256(
            json.dumps(
                document["event"],
                sort_keys=True,
                separators=(",", ":"),
            ).encode("utf-8")
        ).hexdigest()
        digest_document = dict(document)
        digest_document.pop("verdict_sha256")
        document["verdict_sha256"] = hashlib.sha256(
            json.dumps(
                digest_document,
                sort_keys=True,
                separators=(",", ":"),
            ).encode("utf-8")
        ).hexdigest()
        path.write_bytes(
            json.dumps(
                document,
                sort_keys=True,
                separators=(",", ":"),
            ).encode("utf-8")
        )

        with self.assertRaises(evidence.EvidenceError) as caught:
            reviewer.latest_verdict(_alias("scenario", "synthetic"))

        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.CORRUPT)

    def test_gapped_and_duplicate_operation_verdict_chains_are_rejected(self) -> None:
        for mode in ("gap", "duplicate-operation"):
            with self.subTest(mode=mode):
                with tempfile.TemporaryDirectory() as temporary_name:
                    root = Path(temporary_name) / "evidence"
                    store = evidence.EvidenceStore(root)
                    self.root = root
                    self.store = store
                    self.writer = store.execution_writer()
                    manifest, selected = self._assertion_selection()
                    reviewer = store.owner_reviewer(_alias("owner", "synthetic"))
                    first = reviewer.record_verdict(
                        self._request(manifest, (selected,)),
                        evidence.WriteRequest(
                            operation_id=_operation("owner-verdict-one"),
                            occurred_at="2026-10-23T01:00:05Z",
                        ),
                    )
                    reviewer.record_verdict(
                        self._request(
                            manifest,
                            (selected,),
                            verdict=evidence.OwnerVerdictOutcome.FAIL,
                            supersedes=first.verdict_sha256,
                            reviewed_at="2026-10-23T01:00:06Z",
                        ),
                        evidence.WriteRequest(
                            operation_id=_operation("owner-verdict-two"),
                            occurred_at="2026-10-23T01:00:06Z",
                        ),
                    )
                    directory = root / "owner-verdicts"
                    first_path = directory / "verdict-00000001.json"
                    second_path = directory / "verdict-00000002.json"
                    if mode == "gap":
                        second_path.rename(directory / "verdict-00000003.json")
                    else:
                        duplicate = json.loads(first_path.read_bytes())
                        duplicate["sequence"] = 2
                        duplicate["previous_verdict_sha256"] = first.verdict_sha256
                        self._rewrite_verdict(second_path, duplicate)

                    with self.assertRaises(evidence.EvidenceError) as caught:
                        reviewer.latest_verdict(_alias("scenario", "synthetic"))
                    self.assertEqual(
                        caught.exception.code,
                        evidence.EvidenceErrorCode.CORRUPT,
                    )

    def test_packet_requires_finalized_evidence_and_private_verdict_files(self) -> None:
        self.writer.open_session(
            self._session_spec(),
            evidence.WriteRequest(
                operation_id=_operation("open-session-synthetic"),
                occurred_at="2026-10-23T01:00:00Z",
            ),
        )
        reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))
        with self.assertRaises(evidence.EvidenceError) as caught:
            reviewer.review_packet("a" * 64)
        self.assertEqual(caught.exception.code, evidence.EvidenceErrorCode.MANIFEST_MISSING)

        with tempfile.TemporaryDirectory() as temporary_name:
            self.root = Path(temporary_name) / "evidence"
            self.store = evidence.EvidenceStore(self.root)
            self.writer = self.store.execution_writer()
            manifest, selected = self._assertion_selection()
            reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))
            reviewer.record_verdict(
                self._request(manifest, (selected,)),
                evidence.WriteRequest(
                    operation_id=_operation("owner-verdict-private"),
                    occurred_at="2026-10-23T01:00:05Z",
                ),
            )
            directory = self.root / "owner-verdicts"
            path = directory / "verdict-00000001.json"
            self.assertEqual(directory.stat().st_mode & 0o777, 0o700)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            packet = reviewer.review_packet(manifest.manifest_sha256)
            self.assertNotIn(b"/private/", packet)
            self.assertNotIn(b"device-serial", packet)

    def test_selected_record_contract_rejects_malformed_shapes_order_and_ranges(
        self,
    ) -> None:
        manifest, selected = self._assertion_selection()
        snapshot = self.writer.snapshot("1" * 32)
        terminal = replace(
            selected,
            sequence=3,
            record_sha256=snapshot.records[2].record_sha256,
        )
        valid = self._request(manifest, (selected,))
        reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))
        cases = (
            (
                "container",
                replace(valid, selected_records=[selected]),
                evidence.EvidenceErrorCode.INVALID_INPUT,
            ),
            (
                "item",
                replace(valid, selected_records=(object(),)),
                evidence.EvidenceErrorCode.INVALID_INPUT,
            ),
            (
                "boolean-sequence",
                replace(
                    valid,
                    selected_records=(replace(selected, sequence=True),),
                ),
                evidence.EvidenceErrorCode.INVALID_INPUT,
            ),
            (
                "descending",
                replace(valid, selected_records=(terminal, selected)),
                evidence.EvidenceErrorCode.INVALID_INPUT,
            ),
            (
                "duplicate",
                replace(valid, selected_records=(selected, selected)),
                evidence.EvidenceErrorCode.INVALID_INPUT,
            ),
            (
                "out-of-range",
                replace(
                    valid,
                    selected_records=(replace(selected, sequence=99),),
                ),
                evidence.EvidenceErrorCode.VERDICT_BINDING_INVALID,
            ),
        )
        for case, request, expected in cases:
            with self.subTest(case=case):
                with self.assertRaises(evidence.EvidenceError) as caught:
                    reviewer.record_verdict(
                        request,
                        evidence.WriteRequest(
                            operation_id=_operation(f"invalid-selection-{case}")
                        ),
                    )
                self.assertEqual(caught.exception.code, expected)
        self.assertEqual(
            list((self.root / "owner-verdicts").glob("verdict-*.json")),
            [],
        )

    def test_direct_pass_requires_sufficient_observation(self) -> None:
        manifest, selected = self._assertion_selection()
        reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))
        request = self._request(
            manifest,
            (selected,),
            basis=evidence.ReviewBasis.DIRECT_OWNER_OBSERVATION,
            sufficiency=evidence.Sufficiency.INSUFFICIENT,
            direct_observation_declared=True,
        )
        with self.assertRaises(evidence.EvidenceError) as caught:
            reviewer.record_verdict(
                request,
                evidence.WriteRequest(
                    operation_id=_operation("direct-insufficient-pass")
                ),
            )
        self.assertEqual(
            caught.exception.code,
            evidence.EvidenceErrorCode.VERDICT_SUFFICIENCY_INVALID,
        )

    def test_persisted_verdict_parser_maps_duplicate_schema_and_event_digest_faults(
        self,
    ) -> None:
        manifest, selected = self._assertion_selection()
        reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))
        reviewer.record_verdict(
            self._request(manifest, (selected,)),
            evidence.WriteRequest(
                operation_id=_operation("owner-verdict-parser"),
                occurred_at="2026-10-23T01:00:05Z",
            ),
        )
        path = self.root / "owner-verdicts" / "verdict-00000001.json"
        original = path.read_bytes()
        original_document = json.loads(original)

        unsupported = copy.deepcopy(original_document)
        unsupported["schema_version"] = _evidence_storage.SCHEMA_VERSION + 1
        self._rewrite_verdict(path, unsupported)
        unsupported_bytes = path.read_bytes()

        bad_event_digest = copy.deepcopy(original_document)
        bad_event_digest["event_sha256"] = "0" * 64
        digest_document = dict(bad_event_digest)
        digest_document.pop("verdict_sha256", None)
        bad_event_digest["verdict_sha256"] = _evidence_storage._canonical_sha256(
            digest_document
        )
        cases = (
            (
                "duplicate-key",
                original.replace(
                    b'{"event":', b'{"schema_version":1,"event":', 1
                ),
                evidence.EvidenceErrorCode.DUPLICATE_KEY,
            ),
            (
                "unsupported-schema",
                unsupported_bytes,
                evidence.EvidenceErrorCode.UNSUPPORTED_SCHEMA,
            ),
            (
                "event-digest",
                _evidence_storage._canonical_bytes(bad_event_digest),
                evidence.EvidenceErrorCode.CORRUPT,
            ),
        )
        for case, raw, expected in cases:
            with self.subTest(case=case):
                path.write_bytes(raw)
                path.chmod(0o600)
                with self.assertRaises(evidence.EvidenceError) as caught:
                    reviewer.latest_verdict(_alias("scenario", "synthetic"))
                self.assertEqual(caught.exception.code, expected)
                path.write_bytes(original)
                path.chmod(0o600)

    def test_persisted_verdict_rejects_authentication_and_selection_corruption(
        self,
    ) -> None:
        manifest, selected = self._assertion_selection()
        reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))
        reviewer.record_verdict(
            self._request(manifest, (selected,)),
            evidence.WriteRequest(
                operation_id=_operation("owner-verdict-auth-selection"),
                occurred_at="2026-10-23T01:00:05Z",
            ),
        )
        path = self.root / "owner-verdicts" / "verdict-00000001.json"
        original = json.loads(path.read_bytes())
        cases = {
            "attendance": lambda event: event.__setitem__(
                "attendance_authentication", "self_asserted"
            ),
            "owner-authentication": lambda event: event.__setitem__(
                "owner_identity_authentication", "not_provided"
            ),
            "selection-container": lambda event: event.__setitem__(
                "selected_records", {"not": "a list"}
            ),
            "selection-overflow": lambda event: event.__setitem__(
                "selected_records",
                [
                    {"sequence": index + 1, "record_sha256": "a" * 64}
                    for index in range(65)
                ],
            ),
        }
        for case, mutate in cases.items():
            with self.subTest(case=case):
                document = copy.deepcopy(original)
                mutate(document["event"])
                self._rewrite_verdict(path, document)
                with self.assertRaises(evidence.EvidenceError) as caught:
                    reviewer.latest_verdict(_alias("scenario", "synthetic"))
                self.assertEqual(
                    caught.exception.code, evidence.EvidenceErrorCode.CORRUPT
                )
                path.write_bytes(_evidence_storage._canonical_bytes(original))
                path.chmod(0o600)

    def test_verdict_chain_rejects_linkage_operation_and_time_regressions(
        self,
    ) -> None:
        manifest, selected = self._assertion_selection()
        reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))
        first = reviewer.record_verdict(
            self._request(manifest, (selected,)),
            evidence.WriteRequest(
                operation_id=_operation("owner-verdict-first"),
                occurred_at="2026-10-23T01:00:05Z",
            ),
        )
        reviewer.record_verdict(
            self._request(
                manifest,
                (selected,),
                reviewed_at="2026-10-23T01:00:06Z",
                supersedes=first.verdict_sha256,
            ),
            evidence.WriteRequest(
                operation_id=_operation("owner-verdict-second"),
                occurred_at="2026-10-23T01:00:06Z",
            ),
        )
        path = self.root / "owner-verdicts" / "verdict-00000002.json"
        original = json.loads(path.read_bytes())
        cases = {
            "previous-digest": lambda document: document.__setitem__(
                "previous_verdict_sha256", "0" * 64
            ),
            "duplicate-operation": lambda document: document["event"].__setitem__(
                "operation_id", first.operation_id
            ),
            "time-regression": lambda document: (
                document["event"].__setitem__(
                    "occurred_at", "2026-10-23T01:00:04Z"
                ),
                document["event"].__setitem__(
                    "reviewed_at", "2026-10-23T01:00:03Z"
                ),
            ),
        }
        for case, mutate in cases.items():
            with self.subTest(case=case):
                document = copy.deepcopy(original)
                mutate(document)
                self._rewrite_verdict(path, document)
                with self.assertRaises(evidence.EvidenceError) as caught:
                    reviewer.latest_verdict(_alias("scenario", "synthetic"))
                self.assertEqual(
                    caught.exception.code, evidence.EvidenceErrorCode.CORRUPT
                )
                path.write_bytes(_evidence_storage._canonical_bytes(original))
                path.chmod(0o600)

    def test_verdict_supersession_is_exact_and_scenario_lookup_can_miss(self) -> None:
        manifest, selected = self._assertion_selection()
        reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))
        reviewer.record_verdict(
            self._request(manifest, (selected,)),
            evidence.WriteRequest(
                operation_id=_operation("owner-verdict-supersession-first"),
                occurred_at="2026-10-23T01:00:05Z",
            ),
        )
        with self.assertRaises(evidence.EvidenceError) as caught:
            reviewer.record_verdict(
                self._request(
                    manifest,
                    (selected,),
                    reviewed_at="2026-10-23T01:00:06Z",
                ),
                evidence.WriteRequest(
                    operation_id=_operation(
                        "owner-verdict-supersession-missing"
                    ),
                    occurred_at="2026-10-23T01:00:06Z",
                ),
            )
        self.assertEqual(
            caught.exception.code,
            evidence.EvidenceErrorCode.VERDICT_BINDING_INVALID,
        )
        self.assertEqual(
            reviewer.latest_verdict(_alias("scenario", "other")),
            None,
        )

    def test_verdict_directory_scan_faults_and_unknown_entries(self) -> None:
        manifest, selected = self._assertion_selection()
        reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))
        reviewer.record_verdict(
            self._request(manifest, (selected,)),
            evidence.WriteRequest(
                operation_id=_operation("owner-verdict-directory-audit"),
                occurred_at="2026-10-23T01:00:05Z",
            ),
        )
        directory = self.root / "owner-verdicts"
        temporary = directory / f".verdict-00000099.tmp-{'a' * 32}"
        temporary.write_bytes(b"ignored")
        temporary.chmod(0o600)
        self.assertIsNotNone(
            reviewer.latest_verdict(_alias("scenario", "synthetic"))
        )
        temporary.unlink()
        unknown = directory / "unknown-entry"
        unknown.write_text("unsafe", encoding="utf-8")
        with self.assertRaises(evidence.EvidenceError) as caught:
            reviewer.latest_verdict(_alias("scenario", "synthetic"))
        self.assertEqual(
            caught.exception.code, evidence.EvidenceErrorCode.UNSAFE_PATH
        )
        unknown.unlink()

        with patch.object(
            _evidence_storage.os,
            "listdir",
            side_effect=OSError(errno.EIO, "owner-verdicts"),
        ):
            with self.assertRaises(evidence.EvidenceError) as caught:
                reviewer.latest_verdict(_alias("scenario", "synthetic"))
        self.assertEqual(
            caught.exception.code, evidence.EvidenceErrorCode.UNAVAILABLE
        )

    def test_review_manifest_scan_maps_failures_and_rejects_unknown_entries(
        self,
    ) -> None:
        for failure_at in (1, 3):
            with self.subTest(scan_failure_at=failure_at):
                with tempfile.TemporaryDirectory() as temporary_name:
                    self.root = Path(temporary_name) / "evidence"
                    self.store = evidence.EvidenceStore(self.root)
                    self.writer = self.store.execution_writer()
                    manifest, _selected = self._assertion_selection()
                    reviewer = self.store.owner_reviewer(
                        _alias("owner", "synthetic")
                    )
                    if failure_at == 3:
                        session_directory = (
                            self.root / "executions" / ("1" * 32)
                        )
                        record_path = (
                            session_directory / "record-00000001.json"
                        )
                        record = json.loads(record_path.read_text())
                        record["record_sha256"] = "0" * 64
                        record_path.write_bytes(
                            _evidence_storage._canonical_bytes(record)
                        )
                        record_path.chmod(0o600)
                    real_listdir = os.listdir
                    calls = 0

                    def fail_selected_scan(descriptor: int):
                        nonlocal calls
                        calls += 1
                        if calls == failure_at:
                            raise OSError(errno.EIO, "execution scan")
                        return real_listdir(descriptor)

                    with patch.object(
                        _evidence_storage.os,
                        "listdir",
                        side_effect=fail_selected_scan,
                    ):
                        with self.assertRaises(evidence.EvidenceError) as caught:
                            reviewer.review_packet(manifest.manifest_sha256)
                    self.assertEqual(
                        caught.exception.code,
                        evidence.EvidenceErrorCode.UNAVAILABLE,
                    )

        with tempfile.TemporaryDirectory() as temporary_name:
            self.root = Path(temporary_name) / "evidence"
            self.store = evidence.EvidenceStore(self.root)
            self.writer = self.store.execution_writer()
            manifest, _selected = self._assertion_selection()
            reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))
            (self.root / "executions" / "0bad").mkdir()
            with self.assertRaises(evidence.EvidenceError) as caught:
                reviewer.review_packet(manifest.manifest_sha256)
            self.assertEqual(
                caught.exception.code,
                evidence.EvidenceErrorCode.UNSAFE_PATH,
            )

        with tempfile.TemporaryDirectory() as temporary_name:
            self.root = Path(temporary_name) / "evidence"
            self.store = evidence.EvidenceStore(self.root)
            self.writer = self.store.execution_writer()
            manifest, _selected = self._assertion_selection()
            reviewer = self.store.owner_reviewer(_alias("owner", "synthetic"))
            session_directory = self.root / "executions" / ("1" * 32)
            (session_directory / "unknown-entry").write_text(
                "unsafe", encoding="utf-8"
            )
            with self.assertRaises(evidence.EvidenceError) as caught:
                reviewer.review_packet(manifest.manifest_sha256)
            self.assertEqual(
                caught.exception.code,
                evidence.EvidenceErrorCode.UNSAFE_PATH,
            )
