"""Test the versioned, fail-closed owner export-evidence boundary."""

from __future__ import annotations

import hashlib
import unittest

from scripts.android_qualification._fixture_staging_export_evidence import (
    ExportEvidenceV1,
    ProductionAdmissionIssuer,
)
from scripts.android_qualification._fixture_staging_model import (
    FixtureStagingError,
    FixtureStagingErrorCode,
)
from scripts.android_qualification.fixture_oracle import canonical_json


def _attempt() -> dict[str, object]:
    return {
        "request_id": "request-1",
        "session_id": "session-1",
        "service_boot_id": "boot-1",
        "sequence": 7,
        "nonce": "nonce-1",
        "deadline_ns": 500,
        "manifest_sha256": "a" * 64,
        "authorization_sha256": "f" * 64,
        "generation": 3,
        "members": [
            {"path": "a.bin", "size": 2, "sha256": "b" * 64},
            {"path": "b.bin", "size": 4, "sha256": "c" * 64},
        ],
    }


def _receipt(**changes: object) -> dict[str, object]:
    result: dict[str, object] = {
        "schema_version": 1,
        "status": "VERIFIED_RECEIVER_COMPLETION",
        "code": "BROKER_RECEIVER_RECEIPT_DURABLE",
        "request_id": "request-1",
        "session_id": "session-1",
        "service_boot_id": "boot-1",
        "sequence": 7,
        "deadline_ns": 500,
        "manifest_sha256": "a" * 64,
        "authorization_sha256": "f" * 64,
        "generation": 3,
        "members": _attempt()["members"],
        "members_sha256": hashlib.sha256(canonical_json(_attempt()["members"])).hexdigest(),
        "member_count": len(_attempt()["members"]),
        "frame_sha256": "e" * 64,
        "receipt_path": "/tmp/native-receipt.json",
        "receipt_sha256": "0" * 64,
        "durable": True,
    }
    result.update(changes)
    if "receipt_sha256" not in changes:
        digest_payload = {
            key: value
            for key, value in result.items()
            if key not in {"service_boot_id", "sequence", "receipt_sha256", "receipt_path"}
        }
        result["receipt_sha256"] = hashlib.sha256(canonical_json(digest_payload)).hexdigest()
    return result


class _SyntheticAuthorityProvider:
    """Synthetic host fixture; this provider never represents production authority."""

    def __init__(self) -> None:
        self.calls = 0
        self.query_calls = 0

    def verify_and_admit(self, evidence: ExportEvidenceV1) -> object:
        self.calls += 1
        return evidence

    def query_export_receipt(self) -> dict[str, object]:
        self.query_calls += 1
        return _receipt()


class ExportEvidenceTests(unittest.TestCase):
    def test_v1_canonicalization_is_stable_and_binds_ordered_members(self) -> None:
        evidence = ExportEvidenceV1.from_native(_attempt(), _receipt())

        self.assertEqual(evidence.schema_version, 1)
        self.assertEqual(evidence.ordered_member_digests, ("b" * 64, "c" * 64))
        self.assertEqual(evidence.canonical_bytes, canonical_json(evidence.payload))
        self.assertEqual(evidence, ExportEvidenceV1.from_native(_attempt(), _receipt()))

    def test_admission_requires_authority_provider_and_fails_closed(self) -> None:
        with self.assertRaises(FixtureStagingError) as raised:
            ProductionAdmissionIssuer(None).issue(_attempt(), _receipt())

        self.assertEqual(
            raised.exception.code,
            FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY,
        )

    def test_synthetic_provider_is_called_only_after_evidence_validation(self) -> None:
        provider = _SyntheticAuthorityProvider()
        evidence = ProductionAdmissionIssuer(provider).issue(_attempt(), _receipt())

        self.assertIsInstance(evidence, ExportEvidenceV1)
        self.assertEqual(provider.calls, 1)

    def test_rejects_identity_session_epoch_sequence_and_deadline_mismatches(self) -> None:
        changes = (
            {"request_id": "other"},
            {"session_id": "other"},
            {"service_boot_id": "other"},
            {"sequence": 8},
            {"deadline_ns": 501},
        )
        for change in changes:
            with self.subTest(change=change), self.assertRaises(FixtureStagingError):
                ExportEvidenceV1.from_native(_attempt(), _receipt(**change))

    def test_rejects_incomplete_or_non_durable_native_receipts(self) -> None:
        for receipt in (
            _receipt(durable=False),
            _receipt(receipt_sha256=None),
            {key: value for key, value in _receipt().items() if key != "session_id"},
        ):
            with self.subTest(receipt=receipt), self.assertRaises(FixtureStagingError):
                ExportEvidenceV1.from_native(_attempt(), receipt)

    def test_rejects_receipt_digest_that_does_not_bind_its_payload(self) -> None:
        receipt = _receipt()
        receipt["frame_sha256"] = "9" * 64

        with self.assertRaises(FixtureStagingError):
            ExportEvidenceV1.from_native(_attempt(), receipt)

    def test_requires_receipt_authorization_digest_for_attempt(self) -> None:
        with self.assertRaises(FixtureStagingError):
            ExportEvidenceV1.from_native(
                _attempt(), _receipt(authorization_sha256="8" * 64)
            )

    def test_recovery_queries_receipt_without_dispatching_again(self) -> None:
        provider = _SyntheticAuthorityProvider()
        issuer = ProductionAdmissionIssuer(provider)
        issuer.recover()

        self.assertEqual(provider.calls, 0)
        self.assertEqual(provider.query_calls, 1)


if __name__ == "__main__":
    unittest.main()
