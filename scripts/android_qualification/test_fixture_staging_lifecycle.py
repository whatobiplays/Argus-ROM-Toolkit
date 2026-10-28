"""Regression tests for the durable owner-side native session journal."""

from __future__ import annotations

from pathlib import Path
from tempfile import TemporaryDirectory
import hashlib
import base64
import json
import os
import stat
import threading
import unittest
from dataclasses import replace
from types import SimpleNamespace
from unittest import mock

from scripts.android_qualification._fixture_staging_lifecycle import (
    JournalCorrupt,
    JournalError,
    OwnerPrivateLifecycleJournal,
)
from scripts.android_qualification.fixture_oracle import canonical_json
from scripts.android_qualification._fixture_staging_session import (
    AuthenticatedXPCReply,
    OwnerExportDispatch,
    OwnerSessionExportClient,
)
from scripts.android_qualification._fixture_staging_model import FixtureStagingErrorCode
from scripts.android_qualification import _fixture_staging_native as native
from scripts.android_qualification import _fixture_staging_orchestration as orchestration
from scripts.android_qualification import fixture_staging
from scripts.android_qualification.test_manifest import write_private_json


def _signed_request(
    *, sequence: int = 1, deadline_ns: int = 500, operation: str = "export",
    overrides: dict[str, object] | None = None,
) -> dict[str, object]:
    freshness = {
        "schema_version": 1,
        "installation_id": "installation-1",
        "service_boot_id": "boot-1",
        "broker_revision": "broker-revision-1",
        "owner_key_id": "owner-key-1",
        "connection_id": "connection-1",
        "session_id": "session-1",
        "request_id": f"request-{sequence}",
        "sequence": sequence,
        "operation": operation,
        "request_sha256": "f" * 64,
        "authorization_sha256": "a" * 64,
        "consent_sha256": "b" * 64,
        "deadline_ns": deadline_ns,
    }
    request = {
        "operation": operation,
        "request_id": f"request-{sequence}",
        "session_id": "session-1",
        "service_boot_id": "boot-1",
        "sequence": sequence,
        "nonce": f"nonce-{sequence}",
        "deadline_ns": deadline_ns,
        "manifest_sha256": "c" * 64,
        "generation": 7,
        "members": [
            {
                "path": "fixture/game.rom",
                "size": 4,
                "sha256": hashlib.sha256(b"rom!").hexdigest(),
            }
        ],
        "source_paths": ["fixture/game.rom"],
        "freshness_envelope": base64.b64encode(canonical_json(freshness)).decode(),
        "freshness_signature": "test-only-owner-signature",
        "consent_signature": "test-only-consent-signature",
        "authorization_sha256": "a" * 64,
    }
    request.update(overrides or {})
    return request


def _attempt(
    *, sequence: int = 1, deadline_ns: int = 500, operation: str = "export",
    signed_request: dict[str, object] | None = None,
) -> dict[str, object]:
    signed_request = signed_request or _signed_request(
        sequence=sequence, deadline_ns=deadline_ns, operation=operation
    )
    return {
        "owner_id": "owner-1",
        "installation_id": "installation-1",
        "broker_revision": "broker-revision-1",
        "owner_key_id": "owner-key-1",
        "authorization_sha256": "a" * 64,
        "consent_sha256": "b" * 64,
        "service_boot_id": "boot-1",
        "session_id": "session-1",
        "connection_id": "connection-1",
        "request_id": f"request-{sequence}",
        "request_sha256": hashlib.sha256(canonical_json(signed_request)).hexdigest(),
        "operation": operation,
        "nonce": f"nonce-{sequence}",
        "sequence": sequence,
        "deadline_ns": deadline_ns,
        "manifest_sha256": "c" * 64,
        "generation": 7,
        "members": [
            {
                "path": "fixture/game.rom",
                "size": 4,
                "sha256": hashlib.sha256(b"rom!").hexdigest(),
            }
        ],
    }


def _preparation_for_dispatch(test_case, grant, owner_export):
    temporary = TemporaryDirectory()
    test_case.addCleanup(temporary.cleanup)
    manifest_bytes = b"lifecycle reviewed manifest"
    authorization_document = {
        "schema_version": 1,
        "authorization_id": "lifecycle-test",
    }
    authorization_path = Path(temporary.name) / "authorization.json"
    write_private_json(
        authorization_path.parent, authorization_path.name, authorization_document
    )
    grant.fixture_manifest_sha256 = hashlib.sha256(manifest_bytes).hexdigest()
    grant.authorization_sha256 = native._authority._canonical_sha256(
        authorization_document
    )
    owner_export.attempt["manifest_sha256"] = grant.fixture_manifest_sha256
    owner_export.attempt["authorization_sha256"] = grant.authorization_sha256
    preparation = native.create_production_owner_export_preparation(
        grant,
        object(),
        attempt_manifest_sha256=owner_export.attempt["manifest_sha256"],
        attempt_authorization_sha256=owner_export.attempt[
            "authorization_sha256"
        ],
        authorization_path=authorization_path,
        receipt_directory=Path(temporary.name) / "receipts",
        export_intent={},
        source_fds={"fixture/game.rom": 10},
        documents={"manifest": manifest_bytes},
        delivery_fd=11,
    )
    return replace(preparation, _prepare=lambda _installation: owner_export)


def _members_sha256(members: object) -> str:
    return hashlib.sha256(
        b"argus.fixture-staging.export-members.v1\0" + canonical_json(members)
    ).hexdigest()


def _record_receipt(
    journal: OwnerPrivateLifecycleJournal, sequence: int, *, now_ns: int | None = None
) -> None:
    journal.record_native_receipt(
        request_id=f"request-{sequence}",
        sequence=sequence,
        deadline_ns=500,
        manifest_sha256="c" * 64,
        generation=7,
        members_sha256=_members_sha256(_attempt(sequence=sequence)["members"]),
        receipt_sha256="e" * 64,
        durable=True,
        now_ns=200 if now_ns is None else now_ns,
    )


def _native_completion(
    attempt: dict[str, object],
    *,
    overrides: dict[str, object] | None = None,
) -> dict[str, object]:
    members = attempt["members"]
    members_sha256 = _members_sha256(members)
    completion: dict[str, object] = {
        "schema_version": 1,
        "status": "VERIFIED_RECEIVER_COMPLETION",
        "code": "BROKER_RECEIVER_RECEIPT_DURABLE",
        "request_id": attempt["request_id"],
        "session_id": attempt["session_id"],
        "service_boot_id": attempt["service_boot_id"],
        "sequence": attempt["sequence"],
        "deadline_ns": attempt["deadline_ns"],
        "manifest_sha256": attempt["manifest_sha256"],
        "generation": attempt["generation"],
        "authorization_sha256": attempt["authorization_sha256"],
        "members": members,
        "members_sha256": members_sha256,
        "member_count": len(members),
        "frame_sha256": _native_frame_sha256(attempt, b"rom!"),
        "receipt_path": "/private/var/db/argus-qualification/receipts/export.receipt.json",
        "durable": True,
    }
    completion.update(overrides or {})
    requested_receipt_sha256 = (overrides or {}).get("receipt_sha256")
    digest_payload = {
        key: value
        for key, value in completion.items()
        if key not in {
            "service_boot_id", "sequence", "receipt_sha256", "receipt_path"
        }
    }
    completion["receipt_sha256"] = hashlib.sha256(
        canonical_json(digest_payload)
    ).hexdigest()
    if requested_receipt_sha256 is not None:
        completion["receipt_sha256"] = requested_receipt_sha256
    return completion


def _native_frame_sha256(attempt: dict[str, object], payload: bytes) -> str:
    header = canonical_json(
        {
            "schema_version": 1,
            "session_id": attempt["session_id"],
            "manifest_sha256": attempt["manifest_sha256"],
            "generation": attempt["generation"],
            "members": attempt["members"],
        }
    )
    transcript = b"AQSNAP1\n" + len(header).to_bytes(8, "big") + header + payload
    return hashlib.sha256(transcript).hexdigest()


class OwnerPrivateLifecycleJournalTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "journal"
        self.root.mkdir(mode=0o700)

    def test_export_client_rejects_public_caller_asserted_peer_identities(self) -> None:
        with self.assertRaises(TypeError):
            OwnerSessionExportClient(
                OwnerPrivateLifecycleJournal(self.root),
                object(),
                service_identity="caller-selected-service",
                broker_identity="caller-selected-broker",
            )

    def test_production_export_rejects_incomplete_native_completion(self) -> None:
        grant = SimpleNamespace(
            authorization_sha256="a" * 64,
            fixture_manifest_sha256="c" * 64,
            _fixture_expectations=(object(),),
            required_fixture_ids=("fixture",),
            coverage_mode="full",
        )
        attempt = _attempt()
        installation = native.VerifiedNativeInstallation(
            "installation-1", "boot-1", "broker-revision-1", "owner-key-1",
            "f" * 64, True, True, True, native._INSTALLATION_SEAL,
        )
        client = OwnerSessionExportClient._for_testing(
            OwnerPrivateLifecycleJournal(self.root), object(), installation
        )
        client._test_transport = False
        owner_export = OwnerExportDispatch(
            client,
            attempt,
            _signed_request(),
            {},
        )
        preparation = _preparation_for_dispatch(self, grant, owner_export)
        incomplete_reply = AuthenticatedXPCReply(
            "installation-1",
            "broker-revision-1",
            {"status": "VERIFIED_RECEIVER_COMPLETION", "durable": False},
            True,
        )

        with (
            mock.patch.object(
                orchestration,
                "_admit_production_staging_namespace",
                return_value=None,
            ),
            mock.patch.object(
                orchestration, "_validate_grant_for_use", return_value=grant
            ),
            mock.patch.object(
                native, "select_verified_native_installation", return_value=installation
            ),
            mock.patch.object(
                OwnerExportDispatch, "dispatch", return_value=incomplete_reply
            ),
        ):
            result = fixture_staging.stage_fixtures(
                grant,
                source_roots={},
                destination=None,
                owner_export_preparation=preparation,
            )

        self.assertEqual(result.status, "BLOCKED")

    def test_synthetic_client_cannot_enable_public_production_staging(self) -> None:
        attempt = _attempt(sequence=3)
        signed_request = _signed_request(sequence=3)
        hello = {
            "operation": "hello", "request_id": "hello-1",
            "installation_id": "installation-1", "service_boot_id": "boot-1",
            "broker_revision": "broker-revision-1", "owner_key_id": "owner-key-1",
            "authorization_sha256": "a" * 64,
        }
        admit = _signed_request(sequence=1, operation="admit")
        stage = _signed_request(sequence=2, operation="stage")
        stage["source_paths"] = ["fixture/game.rom"]
        workflow = (hello, admit, stage, signed_request)
        receipt = _native_completion(attempt)
        installation = native.VerifiedNativeInstallation(
            "installation-1", "boot-1", "broker-revision-1", "owner-key-1",
            "f" * 64, True, True, True, native._INSTALLATION_SEAL,
        )

        journal = OwnerPrivateLifecycleJournal(self.root)

        class Transport:
            def dispatch_export(
                _self, _attempt, _signed_request, _source_fds, requests=(),
                _documents=None, delivery_fd=None
            ):
                records = [
                    json.loads(line)
                    for line in (self.root / "lifecycle.jsonl").read_text().splitlines()
                ]
                self.assertEqual(records[-1]["event"], "attempt")
                self.assertTrue(journal.fsync_completed)
                self.assertEqual(
                    tuple(request["operation"] for request in requests),
                    ("hello", "admit", "stage", "export"),
                )
                self.assertIsNotNone(delivery_fd)
                os.write(delivery_fd, b"rom!")
                os.fsync(delivery_fd)
                return AuthenticatedXPCReply(
                    "installation-1", "broker-revision-1", receipt, True
                )

            def query_export_receipt(_self, _attempt):
                return None

        with self.assertRaises(JournalError):
            OwnerSessionExportClient.from_verified_installation(
                journal, Transport(), installation
            )
        client = OwnerSessionExportClient._for_testing(journal, Transport(), installation)
        grant = SimpleNamespace(
            authorization_sha256="a" * 64,
            fixture_manifest_sha256="c" * 64,
            _fixture_expectations=(object(),),
            required_fixture_ids=("fixture",),
            coverage_mode="full",
        )
        with TemporaryDirectory() as source_directory:
            source_path = Path(source_directory) / "game.rom"
            source_path.write_bytes(b"rom!")
            descriptor = os.open(source_path, os.O_RDONLY)
            self.addCleanup(os.close, descriptor)
            delivery_path = Path(source_directory) / "delivery.aqsnap"
            delivery_fd = os.open(
                delivery_path, os.O_CREAT | os.O_EXCL | os.O_RDWR, 0o600
            )
            self.addCleanup(os.close, delivery_fd)
            owner_export = OwnerExportDispatch(
                client, attempt, signed_request, {"fixture/game.rom": descriptor},
                delivery_fd, workflow,
            )
            preparation = _preparation_for_dispatch(self, grant, owner_export)
            with (
                mock.patch.object(orchestration, "_validate_grant_for_use", return_value=grant),
                mock.patch.object(
                    orchestration,
                    "_admit_production_staging_namespace",
                    return_value=None,
                ),
                mock.patch.object(
                    native, "select_verified_native_installation", return_value=installation
                ),
            ):
                result = fixture_staging.stage_fixtures(
                    grant,
                    source_roots={},
                    destination=None,
                    owner_export_preparation=preparation,
                )
            delivered_bytes = delivery_path.read_bytes()

        self.assertEqual(result.status, "BLOCKED")
        self.assertEqual(
            result.blocker_code,
            FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY.value,
        )
        self.assertEqual(result.verified_bytes, 0)
        self.assertEqual(delivered_bytes, b"")
        self.assertEqual(journal.recovery_obligations(), ())
        self.assertEqual(OwnerPrivateLifecycleJournal(self.root).recovery_obligations(), ())

    def test_attempt_is_durable_before_dispatch_and_reopens_as_unknown(self) -> None:
        journal = OwnerPrivateLifecycleJournal(self.root)

        journal.begin_attempt(_attempt(), now_ns=100)

        record_path = self.root / "lifecycle.jsonl"
        self.assertEqual(stat.S_IMODE(record_path.stat().st_mode), 0o600)
        self.assertTrue(journal.fsync_completed)
        recovered = OwnerPrivateLifecycleJournal(self.root)
        obligation = recovered.recovery_obligations()[0]
        self.assertEqual(obligation.status, "UNKNOWN")
        self.assertEqual(obligation.request_id, "request-1")

    def test_dispatch_waits_for_durable_attempt_and_requires_verified_receipt(self) -> None:
        journal = OwnerPrivateLifecycleJournal(self.root)
        attempt = _attempt()
        dispatches: list[str] = []

        def send() -> dict[str, object]:
            records = [
                json.loads(line)
                for line in (self.root / "lifecycle.jsonl").read_text().splitlines()
            ]
            self.assertEqual(records[-1]["event"], "attempt")
            dispatches.append("sent")
            members = _members_sha256(attempt["members"])
            return {
                "receipt": {
                    "request_id": "request-1",
                    "sequence": 1,
                    "deadline_ns": 500,
                    "manifest_sha256": "c" * 64,
                    "generation": 7,
                    "members_sha256": members,
                    "receipt_sha256": "e" * 64,
                    "durable": True,
                }
            }

        with self.assertRaises(JournalError):
            journal.dispatch(
                attempt,
                now_ns=100,
                send=send,
                verify_receipt=lambda _attempt, _response: False,
                clock_ns=lambda: 200,
            )

        self.assertEqual(dispatches, ["sent"])
        obligation = journal.recovery_obligations()[0]
        self.assertEqual(obligation.status, "UNKNOWN")

    def test_export_dispatch_rejects_non_export_operation_before_journal_or_transport(self) -> None:
        journal = OwnerPrivateLifecycleJournal(self.root)
        transport = mock.Mock()
        installation = native.VerifiedNativeInstallation(
            "installation-1", "boot-1", "broker-revision-1", "owner-key-1",
            "f" * 64, True, True, True, native._INSTALLATION_SEAL,
        )
        client = OwnerSessionExportClient._for_testing(journal, transport, installation)
        signed_request = _signed_request(operation="cleanup")
        attempt = _attempt(operation="cleanup", signed_request=signed_request)

        with self.assertRaises(JournalError):
            client.dispatch_export(
                attempt, signed_request, {},
            )

        transport.dispatch_export.assert_not_called()
        self.assertFalse((self.root / "lifecycle.jsonl").exists())

    def test_export_dispatch_cross_binds_signed_peer_and_authorization_fields(self) -> None:
        installation = native.VerifiedNativeInstallation(
            "installation-1", "boot-1", "broker-revision-1", "owner-key-1",
            "f" * 64, True, True, True, native._INSTALLATION_SEAL,
        )
        mismatches = (
            {"installation_id": "other-installation"},
            {"broker_revision": "other-broker"},
            {"owner_key_id": "other-owner-key"},
            {"connection_id": "other-connection"},
            {"consent_sha256": "9" * 64},
        )
        for override in mismatches:
            with self.subTest(field=next(iter(override))):
                root = Path(self.temporary.name) / f"journal-{next(iter(override))}"
                root.mkdir(mode=0o700)
                journal = OwnerPrivateLifecycleJournal(root)
                transport = mock.Mock()
                client = OwnerSessionExportClient._for_testing(
                    journal, transport, installation
                )
                request = _signed_request()
                envelope = json.loads(
                    base64.b64decode(request["freshness_envelope"], validate=True)
                )
                envelope.update(override)
                request["freshness_envelope"] = base64.b64encode(
                    canonical_json(envelope)
                ).decode()
                attempt = _attempt(signed_request=request)
                with self.assertRaises(JournalError):
                    client.dispatch_export(
                        attempt, request, {},
                    )
                transport.dispatch_export.assert_not_called()
                self.assertFalse((root / "lifecycle.jsonl").exists())

        root = Path(self.temporary.name) / "journal-authorization"
        root.mkdir(mode=0o700)
        journal = OwnerPrivateLifecycleJournal(root)
        transport = mock.Mock()
        client = OwnerSessionExportClient._for_testing(journal, transport, installation)
        request = _signed_request(overrides={"authorization_sha256": "9" * 64})
        attempt = _attempt(signed_request=request)
        with self.assertRaises(JournalError):
            client.dispatch_export(attempt, request, {}, )
        transport.dispatch_export.assert_not_called()
        self.assertFalse((root / "lifecycle.jsonl").exists())

    def test_dispatch_ack_requires_authenticated_native_durable_receipt(self) -> None:
        journal = OwnerPrivateLifecycleJournal(self.root)
        attempt = _attempt()
        members = _members_sha256(attempt["members"])
        response = {
            "receipt": {
                "request_id": "request-1",
                "sequence": 1,
                "deadline_ns": 500,
                "manifest_sha256": "c" * 64,
                "generation": 7,
                "members_sha256": members,
                "receipt_sha256": "e" * 64,
                "durable": True,
            }
        }

        journal.dispatch(
            attempt,
            now_ns=100,
            send=lambda: response,
            verify_receipt=lambda _attempt, _response: True,
            clock_ns=lambda: 200,
        )

        self.assertEqual(journal.recovery_obligations(), ())

    def test_export_client_persists_attempt_before_authenticated_xpc_dispatch(self) -> None:
        journal = OwnerPrivateLifecycleJournal(self.root)
        attempt = _attempt()
        calls: list[tuple[str, ...]] = []
        receipt = _native_completion(attempt)

        class Transport:
            def dispatch_export(_self, _attempt, _signed_request, _fds):
                events = [
                    json.loads(line)["event"]
                    for line in (self.root / "lifecycle.jsonl").read_text().splitlines()
                ]
                self.assertEqual(events, ["attempt"])
                calls.append(("dispatch",))
                return AuthenticatedXPCReply(
                    "installation-1", "broker-revision-1", receipt, True
                )

            def query_export_receipt(_self, _attempt):
                calls.append(("query",))
                return None

        client = OwnerSessionExportClient._for_testing(
            journal,
            Transport(),
            service_identity="installation-1",
            broker_identity="broker-revision-1",
        )
        client.dispatch_export(
            attempt,
            _signed_request(),
            {"fixture/game.rom": 21},


        )

        self.assertEqual(calls, [("dispatch",)])
        self.assertEqual(journal.recovery_obligations(), ())

    def test_preparation_hello_precedes_journal_and_dispatch_continuation(self) -> None:
        journal = OwnerPrivateLifecycleJournal(self.root)
        attempt = _attempt()
        signed_request = _signed_request()
        prepared = {
            "attempt": attempt,
            "signed_request": signed_request,
            "continuation": object(),
        }
        events: list[str] = []
        receipt = _native_completion(attempt)

        class Transport:
            def prepare_export(_self, _intent, _source_fds, _documents, _delivery_fd):
                events.append("hello")
                return prepared

            def dispatch_prepared_export(
                _self, received, _source_fds, _documents, delivery_fd
            ):
                self.assertIs(received, prepared)
                records = [
                    json.loads(line)
                    for line in (self.root / "lifecycle.jsonl").read_text().splitlines()
                ]
                self.assertEqual([record["event"] for record in records], ["attempt"])
                self.assertTrue(journal.fsync_completed)
                os.write(delivery_fd, b"rom!")
                os.fsync(delivery_fd)
                events.append("dispatch")
                return AuthenticatedXPCReply(
                    "installation-1", "broker-revision-1", receipt, True
                )

            def query_export_receipt(_self, _attempt):
                raise AssertionError("known completion must not require recovery")

        client = OwnerSessionExportClient._for_testing(
            journal,
            Transport(),
            service_identity="installation-1",
            broker_identity="broker-revision-1",
        )
        with TemporaryDirectory() as delivery_directory:
            delivery_fd = os.open(
                Path(delivery_directory) / "receiver.aqsnap",
                os.O_CREAT | os.O_EXCL | os.O_RDWR,
                0o600,
            )
            self.addCleanup(os.close, delivery_fd)
            client.prepare_and_dispatch_export(
                {},
                {"fixture/game.rom": 21},
                {},
                delivery_fd,


            )

        self.assertEqual(events, ["hello", "dispatch"])
        self.assertEqual(journal.recovery_obligations(), ())

    def test_missing_or_rejected_native_authority_never_reaches_journal(self) -> None:
        for outcome in (None, RuntimeError("owner consent rejected")):
            with self.subTest(outcome=outcome):
                root = Path(self.temporary.name) / f"rejected-{outcome is None}"
                root.mkdir(mode=0o700)
                journal = OwnerPrivateLifecycleJournal(root)
                dispatches: list[str] = []

                class Transport:
                    def prepare_export(_self, _intent, _source_fds, _documents, _fd):
                        if isinstance(outcome, Exception):
                            raise outcome
                        return outcome

                    def dispatch_prepared_export(
                        _self, _prepared, _source_fds, _documents, _fd
                    ):
                        dispatches.append("dispatch")
                        raise AssertionError("rejected authority cannot dispatch")

                    def query_export_receipt(_self, _attempt):
                        return None

                client = OwnerSessionExportClient._for_testing(
                    journal,
                    Transport(),
                    service_identity="installation-1",
                    broker_identity="broker-revision-1",
                )
                with self.assertRaises(JournalError):
                    client.prepare_and_dispatch_export(
                        {}, {"fixture/game.rom": 21}, {}, 22,

                    )

                self.assertEqual(dispatches, [])
                self.assertFalse((root / "lifecycle.jsonl").exists())

    def test_malformed_prepared_connection_binding_is_rejected_before_journal(self) -> None:
        journal = OwnerPrivateLifecycleJournal(self.root)
        attempt = _attempt()
        attempt["connection_id"] = "connection-from-another-session"
        prepared = {
            "attempt": attempt,
            "signed_request": _signed_request(),
            "continuation": object(),
        }

        class Transport:
            def prepare_export(_self, _intent, _source_fds, _documents, _fd):
                return prepared

            def dispatch_prepared_export(_self, *_args):
                raise AssertionError("invalid session binding cannot dispatch")

            def query_export_receipt(_self, _attempt):
                return None

        client = OwnerSessionExportClient._for_testing(
            journal,
            Transport(),
            service_identity="installation-1",
            broker_identity="broker-revision-1",
        )
        with self.assertRaises(JournalError):
            client.prepare_and_dispatch_export(
                {}, {"fixture/game.rom": 21}, {}, 22,

            )

        self.assertFalse((self.root / "lifecycle.jsonl").exists())

    def test_missing_descriptors_and_expired_preparation_do_not_dispatch(self) -> None:
        journal = OwnerPrivateLifecycleJournal(self.root)
        attempt = _attempt(deadline_ns=100)
        prepared = {
            "attempt": attempt,
            "signed_request": _signed_request(deadline_ns=100),
            "continuation": object(),
        }
        calls: list[str] = []

        class Transport:
            def prepare_export(_self, _intent, _source_fds, _documents, _fd):
                calls.append("hello")
                return prepared

            def dispatch_prepared_export(_self, *_args):
                calls.append("dispatch")
                raise AssertionError("expired preparation cannot dispatch")

            def query_export_receipt(_self, _attempt):
                return None

        client = OwnerSessionExportClient._for_testing(
            journal,
            Transport(),
            service_identity="installation-1",
            broker_identity="broker-revision-1",
        )
        with self.assertRaises(JournalError):
            client.prepare_and_dispatch_export(
                {}, {}, {}, 22,
            )
        self.assertEqual(calls, [])
        with self.assertRaises(JournalError):
            client.prepare_and_dispatch_export(
                {}, {"fixture/game.rom": 21}, {}, 22,

            )
        self.assertEqual(calls, ["hello"])
        self.assertFalse((self.root / "lifecycle.jsonl").exists())

    def test_uncertain_prepared_mutation_is_recovered_without_replay(self) -> None:
        journal = OwnerPrivateLifecycleJournal(self.root)
        attempt = _attempt()
        prepared = {
            "attempt": attempt,
            "signed_request": _signed_request(),
            "continuation": object(),
        }
        calls = {"dispatch": 0, "query": 0}

        class Transport:
            def prepare_export(_self, _intent, _source_fds, _documents, _fd):
                return prepared

            def dispatch_prepared_export(_self, *_args):
                calls["dispatch"] += 1
                raise TimeoutError("reply was interrupted")

            def query_export_receipt(_self, _attempt):
                calls["query"] += 1
                return None

        client = OwnerSessionExportClient._for_testing(
            journal,
            Transport(),
            service_identity="installation-1",
            broker_identity="broker-revision-1",
        )
        with self.assertRaises(JournalError):
            client.prepare_and_dispatch_export(
                {}, {"fixture/game.rom": 21}, {}, 22,

            )
        self.assertEqual(journal.recovery_obligations()[0].status, "UNKNOWN")

        self.assertIsNone(client.recover_export(attempt))
        self.assertEqual(calls, {"dispatch": 1, "query": 1})

    def test_prepared_dispatch_rejects_mismatched_receipt(self) -> None:
        journal = OwnerPrivateLifecycleJournal(self.root)
        attempt = _attempt()
        prepared = {
            "attempt": attempt,
            "signed_request": _signed_request(),
            "continuation": object(),
        }
        bad_receipt = _native_completion(attempt) | {"request_id": "another-request"}

        class Transport:
            def prepare_export(_self, _intent, _source_fds, _documents, _fd):
                return prepared

            def dispatch_prepared_export(_self, *_args):
                return AuthenticatedXPCReply(
                    "installation-1", "broker-revision-1", bad_receipt, True
                )

            def query_export_receipt(_self, _attempt):
                return None

        client = OwnerSessionExportClient._for_testing(
            journal,
            Transport(),
            service_identity="installation-1",
            broker_identity="broker-revision-1",
        )
        with self.assertRaises(JournalError):
            client.prepare_and_dispatch_export(
                {}, {"fixture/game.rom": 21}, {}, 22,

            )
        self.assertEqual(journal.recovery_obligations()[0].status, "UNKNOWN")

    def test_native_shaped_completion_reaches_owner_ack(self) -> None:
        journal = OwnerPrivateLifecycleJournal(self.root)
        attempt = _attempt()
        completion = _native_completion(attempt)
        delivery_path = self.root / "native-delivery.bin"
        delivery_fd = os.open(
            delivery_path, os.O_CREAT | os.O_EXCL | os.O_RDWR, 0o600
        )
        self.addCleanup(os.close, delivery_fd)
        os.write(delivery_fd, b"rom!")
        os.fsync(delivery_fd)

        class Transport:
            def dispatch_export(
                _self, _attempt, _signed_request, _fds,
                _workflow=(), _documents=None, _delivery_fd=None,
            ):
                return AuthenticatedXPCReply(
                    "installation-1", "broker-revision-1", completion, True
                )

            def query_export_receipt(_self, _attempt):
                return None

        client = OwnerSessionExportClient._for_testing(
            journal,
            Transport(),
            service_identity="installation-1",
            broker_identity="broker-revision-1",
        )
        client.dispatch_export(
            attempt,
            _signed_request(),
            {"fixture/game.rom": 21},


            delivery_fd=delivery_fd,
        )

        records = [
            json.loads(line)
            for line in (self.root / "lifecycle.jsonl").read_text().splitlines()
        ]
        self.assertEqual([record["event"] for record in records], ["attempt", "receipt"])
        self.assertEqual(journal.recovery_obligations(), ())

    def test_native_completion_requires_the_complete_receipt_dto(self) -> None:
        attempt = _attempt()
        completion = _native_completion(attempt)
        client = OwnerSessionExportClient._for_testing(
            OwnerPrivateLifecycleJournal(self.root),
            object(),
            service_identity="installation-1",
            broker_identity="broker-revision-1",
        )

        def response(receipt):
            reply = AuthenticatedXPCReply(
                "installation-1", "broker-revision-1", receipt, True
            )
            return {"_xpc_reply": reply, "receipt": receipt}

        self.assertTrue(client._verify_reply(attempt, response(completion)))
        for field, value in (
            ("receipt_path", None),
            ("receipt_path", "relative/export.receipt.json"),
            ("service_boot_id", None),
            ("sequence", None),
        ):
            with self.subTest(field=field, value=value):
                malformed = dict(completion)
                if value is None:
                    malformed.pop(field)
                else:
                    malformed[field] = value
                self.assertFalse(client._verify_reply(attempt, response(malformed)))

    def test_native_completion_binding_mismatches_are_rejected(self) -> None:
        attempt = _attempt()
        client = OwnerSessionExportClient._for_testing(
            OwnerPrivateLifecycleJournal(self.root),
            object(),
            service_identity="installation-1",
            broker_identity="broker-revision-1",
        )
        bad_receipts = {
            "status": _native_completion(attempt, overrides={"status": "UNKNOWN"}),
            "code": _native_completion(attempt, overrides={"code": "NOT_DURABLE"}),
            "request_id": _native_completion(attempt, overrides={"request_id": "wrong"}),
            "session_id": _native_completion(attempt, overrides={"session_id": "wrong"}),
            "service_boot_id": _native_completion(
                attempt, overrides={"service_boot_id": "wrong"}
            ),
            "sequence": _native_completion(attempt, overrides={"sequence": 2}),
            "deadline_ns": _native_completion(attempt, overrides={"deadline_ns": 501}),
            "manifest_sha256": _native_completion(
                attempt, overrides={"manifest_sha256": "2" * 64}
            ),
            "generation": _native_completion(attempt, overrides={"generation": 8}),
            "authorization_sha256": _native_completion(
                attempt, overrides={"authorization_sha256": "2" * 64}
            ),
            "members": _native_completion(attempt, overrides={"members": []}),
            "members_sha256": _native_completion(
                attempt, overrides={"members_sha256": "2" * 64}
            ),
            "member_count": _native_completion(attempt, overrides={"member_count": 0}),
            "frame_sha256": _native_completion(
                attempt, overrides={"frame_sha256": "2" * 64}
            ),
            "receipt_sha256": _native_completion(
                attempt, overrides={"receipt_sha256": "2" * 64}
            ),
            "durable": _native_completion(attempt, overrides={"durable": False}),
        }
        valid = _native_completion(attempt)
        delivery_path = self.root / "delivery.bin"
        delivery_fd = os.open(
            delivery_path, os.O_CREAT | os.O_EXCL | os.O_RDWR, 0o600
        )
        self.addCleanup(os.close, delivery_fd)
        os.write(delivery_fd, b"rom!")
        os.fsync(delivery_fd)
        valid_reply = AuthenticatedXPCReply(
            "installation-1", "broker-revision-1", valid, True
        )
        self.assertTrue(
            client._verify_reply(
                attempt, {"_xpc_reply": valid_reply, "receipt": valid},
                delivery_fd=delivery_fd,
            )
        )

        for field, receipt in bad_receipts.items():
            with self.subTest(field=field):
                reply = AuthenticatedXPCReply(
                    "installation-1", "broker-revision-1", receipt, True
                )
                self.assertFalse(
                    client._verify_reply(
                        attempt, {"_xpc_reply": reply, "receipt": receipt},
                        delivery_fd=delivery_fd,
                    )
                )

        ordered_attempt = _attempt()
        ordered_members = [
            {
                "path": "fixture/a.rom",
                "size": 1,
                "sha256": hashlib.sha256(b"a").hexdigest(),
            },
            {
                "path": "fixture/b.rom",
                "size": 1,
                "sha256": hashlib.sha256(b"b").hexdigest(),
            },
        ]
        ordered_attempt["members"] = ordered_members
        ordered_completion = _native_completion(ordered_attempt)
        ordered_reply = AuthenticatedXPCReply(
            "installation-1", "broker-revision-1", ordered_completion, True
        )
        self.assertTrue(
            client._verify_reply(
                ordered_attempt,
                {"_xpc_reply": ordered_reply, "receipt": ordered_completion},
            )
        )
        reversed_members = list(reversed(ordered_members))
        reordered_completion = _native_completion(
            ordered_attempt,
            overrides={
                "members": reversed_members,
                "members_sha256": _members_sha256(reversed_members),
            },
        )
        reordered_reply = AuthenticatedXPCReply(
            "installation-1", "broker-revision-1", reordered_completion, True
        )
        self.assertFalse(
            client._verify_reply(
                ordered_attempt,
                {"_xpc_reply": reordered_reply, "receipt": reordered_completion},
            )
        )

        for service, broker, authenticated in (
            ("wrong-service", "broker-revision-1", True),
            ("installation-1", "wrong-broker", True),
            ("installation-1", "broker-revision-1", False),
        ):
            with self.subTest(service=service, broker=broker, authenticated=authenticated):
                reply = AuthenticatedXPCReply(service, broker, valid, authenticated)
                self.assertFalse(
                    client._verify_reply(
                        attempt, {"_xpc_reply": reply, "receipt": valid},
                        delivery_fd=delivery_fd,
                    )
                )

    def test_export_recovery_rejects_caller_attempt_changes_with_same_request_id(self) -> None:
        journal = OwnerPrivateLifecycleJournal(self.root)
        attempt = _attempt()
        journal.begin_attempt(attempt, now_ns=100)
        journal.mark_unknown(request_id=attempt["request_id"], reason="connection_lost")
        queries: list[object] = []

        class Transport:
            def query_export_receipt(_self, supplied_attempt):
                queries.append(supplied_attempt)
                return None

        client = OwnerSessionExportClient._for_testing(
            journal,
            Transport(),
            service_identity="installation-1",
            broker_identity="broker-revision-1",
        )
        for key, value in attempt.items():
            if key == "request_id":
                continue
            altered = dict(attempt)
            if isinstance(value, bool):
                altered[key] = not value
            elif isinstance(value, int):
                altered[key] = value + 1
            elif isinstance(value, str):
                altered[key] = value + "-altered"
            elif isinstance(value, list):
                altered[key] = [*value, {"altered": True}]
            elif isinstance(value, dict):
                altered[key] = {**value, "altered": True}
            else:
                self.fail(f"add an adversarial mutation for {key!r}")
            with self.subTest(field=key):
                self.assertEqual(altered["request_id"], attempt["request_id"])
                with self.assertRaises(JournalError):
                    client.recover_export(altered)

        self.assertEqual(queries, [])
        self.assertEqual(journal.recovery_obligations()[0].status, "UNKNOWN")

    def test_export_recovery_queries_xpc_receipt_without_resending(self) -> None:
        journal = OwnerPrivateLifecycleJournal(self.root)
        attempt = _attempt()
        journal.begin_attempt(attempt, now_ns=100)
        journal.mark_unknown(request_id="request-1", reason="connection_lost")
        calls: list[str] = []
        receipt = _native_completion(attempt)

        class Transport:
            def dispatch_export(_self, _attempt, _signed_request, _fds):
                calls.append("dispatch")
                raise AssertionError("recovery must never replay an export")

            def query_export_receipt(_self, _attempt):
                calls.append("query")
                return AuthenticatedXPCReply(
                    "installation-1", "broker-revision-1", receipt, True
                )

        client = OwnerSessionExportClient._for_testing(
            journal,
            Transport(),
            service_identity="installation-1",
            broker_identity="broker-revision-1",
        )
        client.recover_export(attempt)

        self.assertEqual(calls, ["query"])
        self.assertEqual(journal.recovery_obligations(), ())

    def test_expired_attempt_can_reconcile_only_its_existing_durable_receipt(self) -> None:
        journal = OwnerPrivateLifecycleJournal(self.root)
        attempt = _attempt(deadline_ns=150)
        journal.begin_attempt(attempt, now_ns=100)
        journal.mark_unknown(request_id=attempt["request_id"], reason="connection_lost")
        receipt = _native_completion(attempt)
        calls: list[tuple[str, object]] = []

        class Transport:
            def query_export_receipt(_self, query_attempt):
                calls.append(("query", query_attempt))
                return AuthenticatedXPCReply(
                    "installation-1", "broker-revision-1", receipt, True
                )

            def dispatch_export(_self, *_args):
                calls.append(("dispatch", None))
                raise AssertionError("expired reconciliation must never dispatch")

        client = OwnerSessionExportClient._for_testing(
            journal,
            Transport(),
            service_identity="installation-1",
            broker_identity="broker-revision-1",
            clock_ns=lambda: 200,
        )
        client.recover_export(attempt)

        self.assertEqual(calls, [("query", attempt)])
        self.assertEqual(journal.recovery_obligations(), ())

    def test_direct_dispatch_cannot_overlap_reserved_preparation(self) -> None:
        journal = OwnerPrivateLifecycleJournal(self.root)
        attempt = _attempt()
        signed_request = _signed_request()
        prepared = {
            "attempt": attempt,
            "signed_request": signed_request,
            "continuation": object(),
        }
        prepare_started = threading.Event()
        release_prepare = threading.Event()
        dispatches: list[str] = []

        class Transport:
            def prepare_export(_self, _intent, _source_fds, _documents, _fd):
                prepare_started.set()
                if not release_prepare.wait(2):
                    raise TimeoutError("test preparation was not released")
                return prepared

            def dispatch_export(_self, *_args):
                dispatches.append("dispatch")
                raise AssertionError("dispatch must not overlap preparation")

            def query_export_receipt(_self, _attempt):
                return None

        client = OwnerSessionExportClient._for_testing(
            journal,
            Transport(),
            service_identity="installation-1",
            broker_identity="broker-revision-1",
        )
        preparation_errors: list[BaseException] = []

        def prepare() -> None:
            try:
                client.prepare_export({}, {"fixture/game.rom": 21}, {}, 22)
            except BaseException as error:
                preparation_errors.append(error)

        thread = threading.Thread(target=prepare)
        thread.start()
        self.assertTrue(prepare_started.wait(2))
        try:
            with self.assertRaises(JournalError):
                client.dispatch_export(attempt, signed_request, {"fixture/game.rom": 21})
        finally:
            release_prepare.set()
            thread.join(2)

        self.assertFalse(thread.is_alive())
        self.assertEqual(preparation_errors, [])
        self.assertEqual(dispatches, [])
        self.assertEqual(journal.recovery_obligations(), ())

    def test_concurrent_prepare_has_one_session_reservation(self) -> None:
        journal = OwnerPrivateLifecycleJournal(self.root)
        attempt = _attempt()
        signed_request = _signed_request()
        prepare_started = threading.Event()
        release_prepare = threading.Event()
        call_count = 0
        results: dict[str, object] = {}

        class Transport:
            def prepare_export(_self, _intent, _source_fds, _documents, _delivery_fd):
                nonlocal call_count
                call_count += 1
                prepare_started.set()
                release_prepare.wait(timeout=2)
                return {
                    "attempt": attempt,
                    "signed_request": signed_request,
                    "continuation": object(),
                }

        client = OwnerSessionExportClient._for_testing(
            journal,
            Transport(),
            service_identity="installation-1",
            broker_identity="broker-revision-1",
        )

        def prepare(name: str) -> None:
            try:
                results[name] = client.prepare_export({}, {"fixture/game.rom": 21}, {}, 22)
            except Exception as error:
                results[name] = error

        first = threading.Thread(target=prepare, args=("first",))
        second = threading.Thread(target=prepare, args=("second",))
        first.start()
        self.assertTrue(prepare_started.wait(timeout=1))
        second.start()
        second.join(timeout=0.1)
        release_prepare.set()
        first.join(timeout=2)
        second.join(timeout=2)

        self.assertFalse(first.is_alive())
        self.assertFalse(second.is_alive())
        self.assertEqual(call_count, 1)
        self.assertFalse(isinstance(results["first"], Exception))
        self.assertIsInstance(results["second"], JournalError)

    def test_export_client_rejects_wrong_xpc_peer_identity(self) -> None:
        journal = OwnerPrivateLifecycleJournal(self.root)
        attempt = _attempt()
        receipt = _native_completion(attempt)

        class Transport:
            def dispatch_export(_self, _attempt, _signed_request, _fds):
                return AuthenticatedXPCReply(
                    "wrong-service", "broker-revision-1", receipt, True
                )

            def query_export_receipt(_self, _attempt):
                return None

        client = OwnerSessionExportClient._for_testing(
            journal,
            Transport(),
            service_identity="installation-1",
            broker_identity="broker-revision-1",
        )
        with self.assertRaises(JournalError):
            client.dispatch_export(
                attempt,
                _signed_request(),
                {"fixture/game.rom": 21},


            )

        self.assertEqual(journal.recovery_obligations()[0].status, "UNKNOWN")

    def test_export_client_rejects_unsigned_subprocess_style_mapping(self) -> None:
        journal = OwnerPrivateLifecycleJournal(self.root)
        attempt = _attempt()

        class Transport:
            def dispatch_export(_self, _attempt, _signed_request, _fds):
                return {
                    "status": "OK",
                    "receipt": {
                        "request_id": "request-1",
                        "sequence": 1,
                        "deadline_ns": 500,
                        "manifest_sha256": "c" * 64,
                        "generation": 7,
                        "members_sha256": "f" * 64,
                        "receipt_sha256": "e" * 64,
                        "durable": True,
                    },
                }

            def query_export_receipt(_self, _attempt):
                return None

        client = OwnerSessionExportClient._for_testing(
            journal,
            Transport(),
            service_identity="installation-1",
            broker_identity="broker-revision-1",
        )
        with self.assertRaises(JournalError):
            client.dispatch_export(
                attempt,
                _signed_request(),
                {"fixture/game.rom": 21},


            )

        self.assertEqual(journal.recovery_obligations()[0].status, "UNKNOWN")

    def test_signed_request_binding_is_checked_before_journal_dispatch(self) -> None:
        journal = OwnerPrivateLifecycleJournal(self.root)
        attempt = _attempt()
        calls: list[str] = []

        class Transport:
            def dispatch_export(_self, _attempt, _signed_request, _fds):
                calls.append("dispatch")
                raise AssertionError("mismatched signed request must not be sent")

            def query_export_receipt(_self, _attempt):
                calls.append("query")
                return None

        request = _signed_request()
        request["deadline_ns"] = 501
        client = OwnerSessionExportClient._for_testing(
            journal, Transport(), service_identity="service", broker_identity="broker"
        )
        with self.assertRaises(JournalError):
            client.dispatch_export(
                attempt,
                request,
                {"fixture/game.rom": 21},


            )

        self.assertEqual(calls, [])
        self.assertFalse((self.root / "lifecycle.jsonl").exists())

    def test_unknown_attempt_cannot_be_replayed_without_native_receipt(self) -> None:
        journal = OwnerPrivateLifecycleJournal(self.root)
        journal.begin_attempt(_attempt(), now_ns=100)
        recovered = OwnerPrivateLifecycleJournal(self.root)

        with self.assertRaises(JournalError):
            recovered.begin_attempt(_attempt(), now_ns=101)

    def test_matching_durable_receipt_resolves_unknown_attempt(self) -> None:
        journal = OwnerPrivateLifecycleJournal(self.root)
        journal.begin_attempt(_attempt(), now_ns=100)
        journal.mark_unknown(request_id="request-1", reason="connection_lost")

        _record_receipt(journal, 1)

        reopened = OwnerPrivateLifecycleJournal(self.root)
        self.assertEqual(reopened.recovery_obligations(), ())

    def test_reconnect_preserves_binding_sequence_and_original_deadline(self) -> None:
        journal = OwnerPrivateLifecycleJournal(self.root)
        first = _attempt()
        journal.begin_attempt(first, now_ns=100)
        _record_receipt(journal, 1)
        second = _attempt(sequence=2)
        second["connection_id"] = "connection-2"
        journal.begin_attempt(second, now_ns=200)

        with self.assertRaises(JournalError):
            journal.begin_attempt(_attempt(sequence=3, deadline_ns=600), now_ns=201)
        with self.assertRaises(JournalError):
            changed = _attempt(sequence=3)
            changed["owner_key_id"] = "other-key"
            journal.begin_attempt(changed, now_ns=201)

    def test_successor_cannot_change_immutable_export_bindings(self) -> None:
        changed_values = {
            "manifest_sha256": "f" * 64,
            "generation": 8,
            "members": [
                {
                    "path": "fixture/other.rom",
                    "size": 4,
                    "sha256": hashlib.sha256(b"else").hexdigest(),
                }
            ],
        }
        for field, value in changed_values.items():
            with self.subTest(field=field):
                journal_root = self.root / field
                journal_root.mkdir(mode=0o700)
                journal = OwnerPrivateLifecycleJournal(journal_root)
                journal.begin_attempt(_attempt(), now_ns=100)
                _record_receipt(journal, 1)
                before = (journal_root / "lifecycle.jsonl").read_bytes()

                successor = _attempt(sequence=2)
                successor[field] = value
                with self.assertRaises(JournalError):
                    journal.begin_attempt(successor, now_ns=201)

                self.assertEqual(
                    (journal_root / "lifecycle.jsonl").read_bytes(), before
                )

    def test_reused_nonce_from_an_older_sequence_is_rejected(self) -> None:
        journal = OwnerPrivateLifecycleJournal(self.root)
        journal.begin_attempt(_attempt(), now_ns=100)
        _record_receipt(journal, 1)
        journal.begin_attempt(_attempt(sequence=2), now_ns=200)
        _record_receipt(journal, 2)
        replay = _attempt(sequence=3)
        replay["nonce"] = "nonce-1"

        with self.assertRaises(JournalError):
            journal.begin_attempt(replay, now_ns=300)

    def test_incomplete_or_nondurable_receipt_does_not_resolve_export(self) -> None:
        journal = OwnerPrivateLifecycleJournal(self.root)
        journal.begin_attempt(_attempt(), now_ns=100)

        with self.assertRaises(JournalError):
            journal.record_native_receipt(
                request_id="request-1",
                sequence=1,
                deadline_ns=500,
                manifest_sha256="c" * 64,
                generation=7,
                members_sha256="f" * 64,
                receipt_sha256="e" * 64,
                durable=False,
                now_ns=200,
            )

        self.assertEqual(journal.recovery_obligations()[0].status, "UNKNOWN")

    def test_receipt_after_immutable_deadline_does_not_accept_delivery(self) -> None:
        journal = OwnerPrivateLifecycleJournal(self.root)
        journal.begin_attempt(_attempt(), now_ns=100)

        with self.assertRaises(JournalError):
            _record_receipt(journal, 1, now_ns=500)

        self.assertEqual(journal.recovery_obligations()[0].status, "UNKNOWN")

    def test_expired_deadline_is_rejected_before_attempt_is_written(self) -> None:
        journal = OwnerPrivateLifecycleJournal(self.root)

        with self.assertRaises(JournalError):
            journal.begin_attempt(_attempt(deadline_ns=100), now_ns=100)

        self.assertEqual(journal.recovery_obligations(), ())

    def test_journal_capacity_preflight_blocks_send_before_attempt_append(self) -> None:
        journal = OwnerPrivateLifecycleJournal(self.root)
        journal.begin_attempt(_attempt(), now_ns=100)
        _record_receipt(journal, 1)
        journal_path = self.root / "lifecycle.jsonl"
        before = journal_path.read_bytes()

        next_attempt = _attempt(sequence=2)
        next_attempt["connection_id"] = "connection-2"
        prior_records = [json.loads(line) for line in before.splitlines()]
        normalized = journal._validate_attempt(next_attempt, now_ns=200)
        body = {
            "event": "attempt",
            "payload": normalized,
            "previous_sha256": prior_records[-1]["record_sha256"],
        }
        record = {
            **body,
            "record_sha256": hashlib.sha256(canonical_json(body)).hexdigest(),
        }
        framed_record = canonical_json(record) + b"\n"
        capacity = len(before) + len(framed_record) - 1
        sends: list[str] = []

        with mock.patch(
            "scripts.android_qualification._fixture_staging_lifecycle._MAX_JOURNAL_BYTES",
            capacity,
            create=True,
        ):
            with self.assertRaises(JournalError):
                journal.dispatch(
                    next_attempt,
                    now_ns=200,
                    send=lambda: sends.append("sent") or {},
                    verify_receipt=lambda _attempt, _response: True,
                    clock_ns=lambda: 200,
                )

        self.assertEqual(sends, [])
        self.assertEqual(journal_path.read_bytes(), before)
        self.assertFalse((self.root / "recovery-required.json").exists())

    def test_journal_corruption_fails_closed_and_records_recovery_obligation(self) -> None:
        journal = OwnerPrivateLifecycleJournal(self.root)
        journal.begin_attempt(_attempt(), now_ns=100)
        record_path = self.root / "lifecycle.jsonl"
        data = bytearray(record_path.read_bytes())
        data[len(data) // 2] ^= 1
        record_path.write_bytes(data)

        recovered = OwnerPrivateLifecycleJournal(self.root)
        with self.assertRaises(JournalCorrupt):
            recovered.recovery_obligations()
        marker = self.root / "recovery-required.json"
        self.assertTrue(marker.is_file())
        self.assertEqual(stat.S_IMODE(marker.stat().st_mode), 0o600)
        payload = json.loads(marker.read_text())
        self.assertEqual(payload["status"], "UNKNOWN")
        self.assertEqual(payload["reason"], "journal_corrupt")

    def test_existing_recovery_marker_syncs_parent_directory(self) -> None:
        journal = OwnerPrivateLifecycleJournal(self.root)
        marker = self.root / "recovery-required.json"
        marker.write_bytes(b"existing recovery obligation\n")
        directory_fsyncs: list[int] = []
        real_fsync = os.fsync

        def record_fsync(descriptor: int) -> None:
            if stat.S_ISDIR(os.fstat(descriptor).st_mode):
                directory_fsyncs.append(descriptor)
            real_fsync(descriptor)

        with mock.patch(
            "scripts.android_qualification._fixture_staging_lifecycle.os.fsync",
            side_effect=record_fsync,
        ):
            journal._write_recovery_marker("journal_corrupt")

        self.assertEqual(len(directory_fsyncs), 1)
        self.assertEqual(marker.read_bytes(), b"existing recovery obligation\n")

    def test_recovery_reads_recheck_marker_after_lock_acquisition(self) -> None:
        for operation in ("obligations", "attempt"):
            with self.subTest(operation=operation):
                directory = self.root / operation
                directory.mkdir(mode=0o700)
                journal = OwnerPrivateLifecycleJournal(directory)
                attempt = _attempt()
                journal.begin_attempt(attempt, now_ns=100)
                if operation == "attempt":
                    journal.recovery_obligations()

                acquire_locked_file = journal._locked_file

                def publish_marker_before_lock(*, create: bool):
                    journal._write_recovery_marker("journal_corrupt")
                    return acquire_locked_file(create=create)

                with mock.patch.object(
                    journal, "_locked_file", new=publish_marker_before_lock
                ):
                    with self.assertRaises(JournalCorrupt):
                        if operation == "obligations":
                            journal.recovery_obligations()
                        else:
                            journal.recovery_attempt(attempt["request_id"])

    def test_partial_journal_append_marks_recovery_required(self) -> None:
        journal = OwnerPrivateLifecycleJournal(self.root)
        original_write = os.write
        writes = 0

        def partial_then_fail(descriptor: int, value: bytes) -> int:
            nonlocal writes
            writes += 1
            if writes == 1:
                return original_write(descriptor, value[:7])
            if writes == 2:
                raise OSError("simulated journal write failure")
            return original_write(descriptor, value)

        with mock.patch(
            "scripts.android_qualification._fixture_staging_lifecycle.os.write",
            side_effect=partial_then_fail,
        ):
            with self.assertRaises(JournalError):
                journal.begin_attempt(_attempt(), now_ns=100)

        marker = self.root / "recovery-required.json"
        self.assertTrue(marker.is_file())
        self.assertEqual(json.loads(marker.read_text())["reason"], "journal_append_uncertain")
        with self.assertRaises(JournalCorrupt):
            OwnerPrivateLifecycleJournal(self.root).recovery_obligations()

    def test_hash_consistent_receipt_with_wrong_attempt_binding_is_corrupt(self) -> None:
        journal = OwnerPrivateLifecycleJournal(self.root)
        journal.begin_attempt(_attempt(), now_ns=100)
        path = self.root / "lifecycle.jsonl"
        attempt_record = json.loads(path.read_bytes().splitlines()[0])
        receipt = {
            "request_id": "different-request",
            "sequence": 1,
            "deadline_ns": 500,
            "manifest_sha256": "c" * 64,
            "generation": 7,
            "members_sha256": _members_sha256(
                attempt_record["payload"]["members"]
            ),
            "receipt_sha256": "e" * 64,
            "durable": True,
        }
        body = {
            "event": "receipt",
            "payload": receipt,
            "previous_sha256": attempt_record["record_sha256"],
        }
        record = {
            **body,
            "record_sha256": hashlib.sha256(canonical_json(body)).hexdigest(),
        }
        path.write_bytes(path.read_bytes() + canonical_json(record) + b"\n")

        with self.assertRaises(JournalCorrupt):
            OwnerPrivateLifecycleJournal(self.root).recovery_obligations()

    def test_hash_consistent_unknown_with_wrong_sequence_is_corrupt(self) -> None:
        journal = OwnerPrivateLifecycleJournal(self.root)
        journal.begin_attempt(_attempt(), now_ns=100)
        path = self.root / "lifecycle.jsonl"
        attempt_record = json.loads(path.read_bytes().splitlines()[0])
        body = {
            "event": "unknown",
            "payload": {
                "request_id": "request-1",
                "sequence": 2,
                "reason": "interrupted_attempt",
            },
            "previous_sha256": attempt_record["record_sha256"],
        }
        record = {
            **body,
            "record_sha256": hashlib.sha256(canonical_json(body)).hexdigest(),
        }
        path.write_bytes(path.read_bytes() + canonical_json(record) + b"\n")

        with self.assertRaises(JournalCorrupt):
            OwnerPrivateLifecycleJournal(self.root).recovery_obligations()

    def test_native_receipt_rejects_boolean_integer_fields_without_appending(self):
        for field in ("sequence", "generation"):
            with self.subTest(field=field):
                path = self.root / field
                path.mkdir(mode=0o700)
                journal = OwnerPrivateLifecycleJournal(path)
                attempt = _attempt()
                attempt["generation"] = 1
                journal.begin_attempt(attempt=attempt, now_ns=100)
                original = {
                    item.name: item.read_bytes()
                    for item in path.iterdir()
                    if item.is_file()
                }
                receipt = {
                    "request_id": attempt["request_id"],
                    "sequence": attempt["sequence"],
                    "deadline_ns": attempt["deadline_ns"],
                    "manifest_sha256": attempt["manifest_sha256"],
                    "generation": attempt["generation"],
                    "members_sha256": _members_sha256(attempt["members"]),
                    "receipt_sha256": "e" * 64,
                    "durable": True,
                    "now_ns": 200,
                }
                receipt[field] = True

                with self.assertRaises(JournalError):
                    journal.record_native_receipt(**receipt)

                self.assertEqual(
                    {
                        item.name: item.read_bytes()
                        for item in path.iterdir()
                        if item.is_file()
                    },
                    original,
                )
                self.assertIsInstance(journal.recovery_obligations(), tuple)


if __name__ == "__main__":
    unittest.main()
