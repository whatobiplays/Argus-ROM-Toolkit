"""Focused tests for the native fixture-staging Python boundary."""

from __future__ import annotations

import copy
import hashlib
import json
import os
import signal
import stat
import subprocess
import sys
import time
import inspect
from dataclasses import dataclass, replace
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
import unittest
from unittest import mock

from scripts.android_qualification import _fixture_staging_native as native
from scripts.android_qualification import _fixture_staging_orchestration as orchestration
from scripts.android_qualification import _fixture_staging_session as session
from scripts.android_qualification import fixture_oracle
from scripts.android_qualification import fixture_staging
from scripts.android_qualification._fixture_staging_model import (
    FixtureStagingError,
    FixtureStagingErrorCode,
    IdentityEvidenceKind,
)
from scripts.android_qualification._fixture_staging_test_support import (
    FixtureStagingTestCase,
    _stage_fixtures_for_synthetic_mechanics,
)
from scripts.android_qualification._fixture_staging_session import (
    JournalError,
    OwnerExportDispatch,
    OwnerPrivateLifecycleJournal,
    OwnerSessionExportClient,
)
from scripts.android_qualification._fixture_staging_lifecycle import _members_sha256
from scripts.android_qualification.test_manifest import NOW, write_private_json
from scripts.android_qualification.test_fixture_oracle import bundle, encoded, validate


@dataclass(frozen=True)
class _GrantBinding:
    fixture_manifest_sha256: str
    plan_sha256: str
    rules_sha256: str
    fixture_ids: tuple[str, ...]
    required_fixture_ids: tuple[str, ...]
    mandatory_fixture_ids: tuple[str, ...]
    coverage_mode: str


_EXPORT_MANIFEST_BYTES = b"reviewed fixture manifest bytes"
_EXPORT_AUTHORIZATION_DOCUMENT = {
    "schema_version": 1,
    "authorization_id": "fixture-staging-test",
}
_EXPORT_MANIFEST_SHA256 = hashlib.sha256(_EXPORT_MANIFEST_BYTES).hexdigest()
_EXPORT_AUTHORIZATION_SHA256 = native._authority._canonical_sha256(
    _EXPORT_AUTHORIZATION_DOCUMENT
)


def _private_export_authorization(
    test_case: unittest.TestCase,
    document: Mapping[str, object] = _EXPORT_AUTHORIZATION_DOCUMENT,
) -> Path:
    temporary = TemporaryDirectory()
    test_case.addCleanup(temporary.cleanup)
    path = Path(temporary.name) / "authorization.json"
    write_private_json(path.parent, path.name, document)
    return path


def _durable_completion(attempt: dict[str, object]) -> dict[str, object]:
    members = attempt["members"]
    receipt: dict[str, object] = {
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
        "members_sha256": _members_sha256(members),
        "member_count": len(members),
        "frame_sha256": hashlib.sha256(b"frame").hexdigest(),
        "receipt_sha256": "0" * 64,
        "receipt_path": "/private/var/db/argus-qualification/receipts/receipt.json",
        "durable": True,
    }
    digest_payload = {
        key: value
        for key, value in receipt.items()
        if key not in {"service_boot_id", "sequence", "receipt_sha256", "receipt_path"}
    }
    receipt["receipt_sha256"] = hashlib.sha256(
        fixture_oracle.canonical_json(
            digest_payload,
            maximum_bytes=fixture_oracle.MAX_RECEIPT_DOCUMENT_BYTES,
        )
    ).hexdigest()
    return receipt


class SnapshotSupportTests(unittest.TestCase):
    def test_receipt_json_uses_a_separate_bounded_256_kib_limit(self) -> None:
        members = [
            {"path": f"fixture/{index:04d}/" + "x" * 96, "size": 1,
             "sha256": "d" * 64}
            for index in range(400)
        ]
        receipt = {"members": members}
        encoded = fixture_oracle.canonical_json(
            receipt, maximum_bytes=fixture_oracle.MAX_RECEIPT_DOCUMENT_BYTES
        )

        self.assertGreater(len(encoded), fixture_oracle.MAX_DOCUMENT_BYTES)
        self.assertLessEqual(len(encoded), fixture_oracle.MAX_RECEIPT_DOCUMENT_BYTES)
        self.assertEqual(
            fixture_oracle.decode_document(
                encoded, maximum_bytes=fixture_oracle.MAX_RECEIPT_DOCUMENT_BYTES
            ),
            receipt,
        )
        with self.assertRaises(fixture_oracle.OracleError):
            fixture_oracle.decode_document(encoded)

    def test_production_factory_and_recovery_do_not_accept_caller_clocks(self) -> None:
        self.assertNotIn(
            "clock_ns",
            inspect.signature(
                native.create_production_owner_export_preparation
            ).parameters,
        )
        self.assertNotIn(
            "now_ns",
            inspect.signature(OwnerSessionExportClient.recover_export).parameters,
        )
        self.assertNotIn("clock_ns", OwnerExportDispatch.__dataclass_fields__)

    def test_session_transport_bounds_receipt_streams_including_newline(self) -> None:
        maximum = fixture_oracle.MAX_RECEIPT_DOCUMENT_BYTES

        def run_session(document_bytes: int, *, overflow_stream: str | None = None):
            writes = []
            for stream in ("stdout", "stderr"):
                if overflow_stream is None or overflow_stream == stream:
                    writes.append(
                        f"sys.{stream}.buffer.write(b'x' * {document_bytes} + b'\\n')"
                    )
            program = "import sys; sys.stdin.buffer.read(); " + "; ".join(writes)
            with mock.patch.object(native, "_require_root_executable"), mock.patch.object(
                native, "BROKER_PATH", Path(sys.executable)
            ):
                return native.InstalledBrokerXPCSessionTransport._run_session(
                    ("-c", program), b"", (), time.monotonic_ns() + 5_000_000_000,
                    maximum_stream_bytes=maximum,
                )

        # Both streams can carry a maximum sized line including its LF frame.
        stdout, stderr = run_session(maximum - 1)
        self.assertEqual(len(stdout), maximum)
        self.assertEqual(len(stderr), maximum)

        for stream in ("stdout", "stderr"):
            with self.subTest(stream=stream), self.assertRaises(FixtureStagingError) as raised:
                run_session(maximum + 1, overflow_stream=stream)
            self.assertEqual(raised.exception.code, FixtureStagingErrorCode.INPUT_TOO_LARGE)

    def test_unsealed_support_tier_is_downgraded_without_approval(self) -> None:
        manifest, record, evidence = bundle(False)
        synthetic = validate(manifest, record, evidence)
        self.assertEqual(
            native.classify_snapshot_contract(synthetic), native.SnapshotSupport.SYNTHETIC_ONLY
        )
        self.assertEqual({item.owner_approval for item in synthetic.fixtures}, {"not_checked"})

        manifest, record, evidence = bundle(True)
        pinned = validate(manifest, record, evidence)
        self.assertEqual(
            native.classify_snapshot_contract(pinned), native.SnapshotSupport.PINNED_UNVERIFIED
        )
        mixed = replace(
            synthetic,
            fixtures=(synthetic.fixtures[0], pinned.fixtures[0]),
        )
        self.assertEqual(
            native.classify_snapshot_contract(mixed), native.SnapshotSupport.PINNED_UNVERIFIED
        )
        verified = replace(
            pinned,
            fixtures=(
                replace(
                    pinned.fixtures[0],
                    independent_support="verified_independent_reference",
                ),
            ),
        )
        self.assertEqual(
            native.classify_snapshot_contract(verified),
            native.SnapshotSupport.PINNED_UNVERIFIED,
        )
        self.assertEqual({item.byte_integrity for item in verified.fixtures}, {"not_checked"})
        self.assertEqual({item.owner_approval for item in verified.fixtures}, {"not_checked"})


class InstallationSelectionTests(unittest.TestCase):
    def test_fixed_policy_read_rejects_growth_after_initial_stat(self) -> None:
        metadata = SimpleNamespace(
            st_mode=stat.S_IFREG | 0o600,
            st_uid=0,
            st_size=4,
        )
        with mock.patch.object(native.os, "open", return_value=47), mock.patch.object(
            native.os, "fstat", return_value=metadata
        ), mock.patch.object(
            native.os, "read", side_effect=(b"1234", b"x")
        ) as read, mock.patch.object(native.os, "close"):
            with self.assertRaises(FixtureStagingError) as raised:
                native._fixed_file(Path("/root/policy.json"), maximum=4)

        self.assertEqual(raised.exception.code, FixtureStagingErrorCode.INPUT_TOO_LARGE)
        self.assertEqual(read.call_args_list, [mock.call(47, 5), mock.call(47, 1)])

    def test_bounded_helper_deadline_covers_blocked_stdin_write(self) -> None:
        with mock.patch.object(
            native, "_RUN_BOUNDED_TIMEOUT_SECONDS", 0.15
        ), mock.patch.object(
            native.subprocess, "Popen", wraps=subprocess.Popen
        ) as popen, mock.patch.object(native.os, "killpg", wraps=os.killpg) as killpg:
            started = time.monotonic()
            with self.assertRaises(subprocess.TimeoutExpired):
                native._run_bounded(
                    Path(sys.executable),
                    ("-c", "import time; time.sleep(10)"),
                    input_bytes=b"x" * (2 * 1024 * 1024),
                )
            elapsed = time.monotonic() - started

        self.assertLess(elapsed, 2)
        self.assertTrue(popen.call_args.kwargs["start_new_session"])
        killpg.assert_called_once()
        self.assertEqual(killpg.call_args.args[1], signal.SIGKILL)

    def test_bounded_helper_streams_input_and_captures_bounded_output(self) -> None:
        returncode, output = native._run_bounded(
            Path(sys.executable),
            (
                "-c",
                "import sys; sys.stdin.buffer.read(); sys.stdout.buffer.write(b'ok')",
            ),
            input_bytes=b"readiness request",
        )

        self.assertEqual(returncode, 0)
        self.assertEqual(output, b"ok")

    def test_bounded_helper_rejects_output_above_capture_limit(self) -> None:
        with self.assertRaises(FixtureStagingError) as raised:
            native._run_bounded(
                Path(sys.executable),
                (
                    "-c",
                    "import sys; sys.stdout.buffer.write(b'x' * "
                    "(int(sys.argv[1]) + 1))",
                    str(native.MAX_NATIVE_PROBE_BYTES),
                ),
            )

        self.assertEqual(raised.exception.code, FixtureStagingErrorCode.INPUT_TOO_LARGE)

    def _assert_rejected_ancestry(
        self,
        insecure_parent: Path,
        mode: int,
        executable_mode: int = stat.S_IFREG | 0o755,
    ) -> None:
        def inspect_path(path: Path) -> mock.Mock:
            if path == native.SERVICE_PATH:
                return mock.Mock(st_mode=executable_mode, st_uid=0)
            if path == insecure_parent:
                return mock.Mock(st_mode=mode, st_uid=0)
            return mock.Mock(st_mode=stat.S_IFDIR | 0o755, st_uid=0)

        with mock.patch.object(
            native.os, "lstat", side_effect=inspect_path
        ), mock.patch.object(native.os, "access", return_value=True):
            with self.assertRaises(FixtureStagingError) as raised:
                native._require_root_executable(native.SERVICE_PATH)
        self.assertEqual(
            raised.exception.code,
            FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY,
        )

    def test_selector_enforces_fixed_root_owned_ancestry(self) -> None:
        policy = encoded(
            {
                "schema": 1,
                "team_id": "ABCDEFGHIJ",
                "broker_cdhash": "a" * 40,
                "service_cdhash": "b" * 40,
                "owner_uid": 501,
                "service_uid": 502,
                "key_access_group": "ABCDEFGHIJ.com.argusromtoolkit.fixture-staging.broker",
                "key_tag": "com.argusromtoolkit.fixture-staging.owner-consent.v1",
                "owner_public_key": None,
            }
        )
        service = {
            "ready": True,
            "protocol_version": 1,
            "installation_id": "installation-a",
            "service_boot_id": "boot-a",
            "broker_revision": "a" * 40,
            "owner_key_id": "com.argusromtoolkit.fixture-staging.owner-consent.v1",
            "staging_root": native.PRODUCTION_STAGING_ROOT,
            "namespace_authority": "protected_service_identity",
            "python_destination": "AVAILABLE",
            "exclusive_cleanup_authority": "kernel_isolation_proof_verified",
        }
        broker = {"status": "NOT_READY", "code": "AWAITING_XPC_DEPENDENCY_PROOF"}
        with mock.patch.object(
            native, "_fixed_file", return_value=policy
        ), mock.patch.object(
            native, "_require_root_executable"
        ), mock.patch.object(native, "_self_check", return_value=broker), mock.patch.object(
            native, "_service_readiness_via_broker", return_value=service
        ):
            selected = native.select_verified_native_installation()
        self.assertIsNotNone(selected)
        self.assertTrue(selected.service_ready)
        self.assertFalse(selected.broker_ready)
        self.assertEqual(selected.broker_revision, "a" * 40)
        self.assertEqual(
            selected.owner_key_id,
            "com.argusromtoolkit.fixture-staging.owner-consent.v1",
        )
        self.assertFalse(selected.operation_enabled)
        for ancestry, mode in (
            ("group-writable parent", stat.S_IFDIR | 0o775),
            ("symlink parent", stat.S_IFLNK | 0o777),
        ):
            with self.subTest(ancestry=ancestry):
                self._assert_rejected_ancestry(native.SERVICE_PATH.parent, mode)
        with self.subTest(ancestry="group-writable executable"):
            self._assert_rejected_ancestry(
                native.SERVICE_PATH.parent,
                stat.S_IFDIR | 0o755,
                executable_mode=stat.S_IFREG | 0o775,
            )

    def test_selector_rejects_service_identity_different_from_installation_policy(self) -> None:
        policy = {
            "schema": 1,
            "team_id": "ABCDEFGHIJ",
            "broker_cdhash": "a" * 40,
            "service_cdhash": "b" * 40,
            "owner_uid": 501,
            "service_uid": 502,
            "key_access_group": "ABCDEFGHIJ.com.argusromtoolkit.fixture-staging.broker",
            "key_tag": "com.argusromtoolkit.fixture-staging.owner-consent.v1",
            "owner_public_key": None,
        }
        service = {
            "ready": True,
            "protocol_version": 1,
            "installation_id": "installation-a",
            "service_boot_id": "boot-a",
            "broker_revision": "a" * 40,
            "owner_key_id": policy["key_tag"],
            "staging_root": native.PRODUCTION_STAGING_ROOT,
            "namespace_authority": "protected_service_identity",
            "python_destination": "AVAILABLE",
            "exclusive_cleanup_authority": "kernel_isolation_proof_verified",
        }
        for field in ("broker_revision", "owner_key_id"):
            with self.subTest(field=field):
                mismatched_service = dict(service)
                mismatched_service[field] = "different-installation-value"
                with mock.patch.object(
                    native, "_fixed_file", return_value=encoded(policy)
                ), mock.patch.object(native, "_require_root_executable"), mock.patch.object(
                    native,
                    "_self_check",
                    return_value={
                        "status": "NOT_READY",
                        "code": "AWAITING_XPC_DEPENDENCY_PROOF",
                    },
                ), mock.patch.object(
                    native,
                    "_service_readiness_via_broker",
                    return_value=mismatched_service,
                ):
                    self.assertIsNone(native.select_verified_native_installation())

    def test_service_readiness_uses_authenticated_broker_relay(self) -> None:
        service = {
            "ready": True,
            "protocol_version": 1,
            "installation_id": "installation-a",
            "service_boot_id": "boot-a",
            "staging_root": native.PRODUCTION_STAGING_ROOT,
            "namespace_authority": "protected_service_identity",
            "python_destination": "BLOCKED_UNSUPPORTED_EXCLUSIVITY",
            "exclusive_cleanup_authority": "requires_kernel_isolation_proof",
        }
        request = encoded(
            {
                "schema_version": 1,
                "operation": "readiness",
                "request_id": "native-readiness",
            }
        )
        response = encoded(
            {"status": "OK", "request_id": "native-readiness", "result": service}
        )
        with mock.patch.object(
            native, "_require_root_executable"
        ), mock.patch.object(
            native, "_run_bounded", return_value=(0, response)
        ) as run_bounded:
            actual = native._service_readiness_via_broker(native.BROKER_PATH)

        self.assertEqual(actual, service)
        run_bounded.assert_called_once_with(
            native.BROKER_PATH, ("relay",), input_bytes=request
        )

    def test_non_object_service_readiness_response_fails_closed(self) -> None:
        for envelope in ([], None, "not-an-object"):
            with self.subTest(envelope=envelope):
                with mock.patch.object(
                    native, "_require_root_executable"
                ), mock.patch.object(
                    native, "_run_bounded", return_value=(0, b"synthetic")
                ), mock.patch.object(
                    native.fixture_oracle, "decode_document", return_value=envelope
                ):
                    with self.assertRaises(FixtureStagingError) as raised:
                        native._service_readiness_via_broker(native.BROKER_PATH)

                self.assertEqual(
                    raised.exception.code,
                    FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY,
                )

    def test_session_deadline_covers_a_broker_that_never_reads_stdin(self) -> None:
        process = subprocess.Popen(
            ("python3", "-c", "import time; time.sleep(10)"),
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        with mock.patch.object(native, "_require_root_executable"), mock.patch.object(
            native.subprocess, "Popen", return_value=process
        ):
            started = time.monotonic()
            with self.assertRaises(subprocess.TimeoutExpired):
                native.InstalledBrokerXPCSessionTransport._run_session(
                    ("session",),
                    b"x" * (2 * 1024 * 1024),
                    (),
                    time.monotonic_ns() + 150_000_000,
                )
            elapsed = time.monotonic() - started
        self.assertLess(elapsed, 2)
        self.assertIsNotNone(process.poll())

    def test_missing_installation_has_no_synthetic_fallback(self) -> None:
        with mock.patch.object(
            native,
            "_fixed_file",
            side_effect=FixtureStagingError(FixtureStagingErrorCode.INPUT_UNAVAILABLE),
        ):
            self.assertIsNone(native.select_verified_native_installation())

    def test_production_preparation_factory_defers_native_work(self) -> None:
        grant = SimpleNamespace(
            fixture_manifest_sha256=_EXPORT_MANIFEST_SHA256,
            authorization_sha256=_EXPORT_AUTHORIZATION_SHA256,
        )
        with mock.patch.object(
            native, "_validate_grant_for_use", return_value=grant
        ) as validate_grant, mock.patch.object(
            native, "select_verified_native_installation"
        ) as select_installation, mock.patch.object(
            native, "create_owner_session_export_client"
        ) as create_client:
            preparation = native.create_production_owner_export_preparation(
                grant,
                object(),
                attempt_manifest_sha256=_EXPORT_MANIFEST_SHA256,
                attempt_authorization_sha256=_EXPORT_AUTHORIZATION_SHA256,
                authorization_path=_private_export_authorization(self),
                receipt_directory=Path("/owner/receipts"),
                export_intent={},
                source_fds={"fixture/game.rom": 10},
                documents={"manifest": _EXPORT_MANIFEST_BYTES},
                delivery_fd=11,
            )

        self.assertIsInstance(preparation, native.ProductionOwnerExportPreparation)
        validate_grant.assert_not_called()
        select_installation.assert_not_called()
        create_client.assert_not_called()

    def test_public_none_destination_stops_before_grant_or_local_adapter(self) -> None:
        with mock.patch.object(
            native, "select_verified_native_installation", return_value=None
        ) as select:
            result = orchestration.stage_fixtures(
                object(), source_roots={}, destination=None
            )
        # Public admission is fail-closed before it inspects installation state.
        select.assert_not_called()
        self.assertEqual(result.status, "BLOCKED")
        self.assertEqual(
            result.blocker_code,
            FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY.value,
        )

    def test_selected_native_does_not_fall_back_to_synthetic_staging(self) -> None:
        selected = mock.create_autospec(native.VerifiedNativeInstallation, instance=True)
        selected.operation_enabled = True
        with mock.patch.object(
            native, "select_verified_native_installation", return_value=selected
        ) as select:
            result = orchestration.stage_fixtures(
                object(), source_roots={}, destination=None
            )

        # Public admission is fail-closed before it inspects installation state.
        select.assert_not_called()
        self.assertEqual(result.status, "BLOCKED")
        self.assertEqual(
            result.blocker_code,
            FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY.value,
        )


class InstalledBrokerPreparedDispatchTests(unittest.TestCase):
    def _pipe_backed_broker_session(self, stdout_bytes: bytes, stderr_bytes: bytes):
        stdin_read_fd, stdin_write_fd = os.pipe()
        stdout_read_fd, stdout_write_fd = os.pipe()
        stderr_read_fd, stderr_write_fd = os.pipe()

        def close_descriptor(descriptor: int) -> None:
            try:
                os.close(descriptor)
            except OSError:
                pass

        for descriptor in (
            stdin_read_fd, stdin_write_fd,
            stdout_read_fd, stdout_write_fd,
            stderr_read_fd, stderr_write_fd,
        ):
            self.addCleanup(close_descriptor, descriptor)

        os.write(stdout_write_fd, stdout_bytes)
        os.close(stdout_write_fd)
        os.write(stderr_write_fd, stderr_bytes)
        os.close(stderr_write_fd)

        broker_session = object.__new__(native._BrokerLineSession)
        broker_session.deadline_ns = time.monotonic_ns() + 5_000_000_000
        broker_session.process = SimpleNamespace(
            args=("fixture-broker", "session"),
            stdin=os.fdopen(stdin_write_fd, "wb", buffering=0),
            stdout=os.fdopen(stdout_read_fd, "rb", buffering=0, closefd=False),
            stderr=os.fdopen(stderr_read_fd, "rb", buffering=0, closefd=False),
            poll=lambda: 0,
            wait=lambda timeout=None: 0,
            kill=lambda: None,
        )
        broker_session.stdin_fd = stdin_write_fd
        broker_session.stdout_fd = stdout_read_fd
        broker_session.stderr_fd = stderr_read_fd
        broker_session.stdout_buffer = bytearray()
        broker_session.stdout_lines = []
        broker_session.stdout_frames = []
        broker_session.stdout_bytes_read = 0
        broker_session.stderr_bytes = bytearray()
        broker_session.stdout_eof = False
        broker_session.stderr_eof = False
        return broker_session, stdin_read_fd

    def test_ordered_response_validation_rejects_missing_extra_or_reordered_records(self) -> None:
        requests = (
            {"request_id": "admit"},
            {"request_id": "stage"},
            {"request_id": "export"},
        )
        responses = [
            {"status": "OK", "request_id": request["request_id"]}
            for request in requests
        ]

        self.assertTrue(native._ordered_session_responses_match(responses, requests))
        self.assertFalse(
            native._ordered_session_responses_match(responses[:-1], requests)
        )
        self.assertFalse(
            native._ordered_session_responses_match(
                [*responses, {"status": "OK", "request_id": "unrelated"}], requests
            )
        )
        self.assertFalse(
            native._ordered_session_responses_match(
                [responses[1], responses[0], responses[2]], requests
            )
        )

    def test_durable_completion_must_bind_every_attempt_identity(self) -> None:
        attempt: dict[str, object] = {
            "request_id": "export-1",
            "session_id": "session-1",
            "service_boot_id": "boot-1",
            "sequence": 3,
            "deadline_ns": 1000,
            "manifest_sha256": "a" * 64,
            "generation": 7,
            "authorization_sha256": "b" * 64,
            "members": [],
        }
        receipt = _durable_completion(attempt)

        self.assertTrue(session._receipt_matches_attempt(attempt, receipt))
        for field, replacement in (
            ("request_id", "other-request"),
            ("session_id", "other-session"),
            ("service_boot_id", "other-boot"),
            ("sequence", 4),
            ("deadline_ns", 1001),
            ("manifest_sha256", "c" * 64),
            ("generation", 8),
            ("authorization_sha256", "d" * 64),
            ("members", [{"path": "different.bin", "size": 1, "sha256": "e" * 64}]),
        ):
            with self.subTest(field=field):
                altered = copy.deepcopy(receipt)
                altered[field] = replacement
                digest_payload = {
                    key: value
                    for key, value in altered.items()
                    if key not in {
                        "service_boot_id", "sequence", "receipt_sha256", "receipt_path"
                    }
                }
                altered["receipt_sha256"] = hashlib.sha256(
                    fixture_oracle.canonical_json(
                        digest_payload,
                        maximum_bytes=fixture_oracle.MAX_RECEIPT_DOCUMENT_BYTES,
                    )
                ).hexdigest()
                self.assertFalse(session._receipt_matches_attempt(attempt, altered))

    def test_dispatch_rejects_distinct_source_fds_for_the_same_file(self) -> None:
        with TemporaryDirectory() as temporary:
            source = Path(temporary) / "source.bin"
            source.write_bytes(b"fixture")
            delivery = Path(temporary) / "delivery.bin"
            source_fd_a = os.open(source, os.O_RDONLY)
            source_fd_b = os.open(source, os.O_RDONLY)
            delivery_fd = os.open(
                delivery, os.O_CREAT | os.O_EXCL | os.O_RDWR, 0o600
            )
            self.addCleanup(os.close, source_fd_a)
            self.addCleanup(os.close, source_fd_b)
            self.addCleanup(os.close, delivery_fd)
            transport = object.__new__(native.InstalledBrokerXPCSessionTransport)
            workflow = (
                {"operation": "hello"},
                {"operation": "admit"},
                {
                    "operation": "stage",
                    "source_paths": ["fixture/a.bin", "fixture/b.bin"],
                },
                {"operation": "export"},
            )

            with mock.patch.object(
                native.InstalledBrokerXPCSessionTransport, "_run_session"
            ) as run_session:
                with self.assertRaises(FixtureStagingError) as raised:
                    transport.dispatch_export(
                        {"deadline_ns": time.monotonic_ns() + 5_000_000_000},
                        workflow[-1],
                        {
                            "fixture/a.bin": source_fd_a,
                            "fixture/b.bin": source_fd_b,
                        },
                        workflow,
                        {},
                        delivery_fd,
                    )

        self.assertEqual(
            raised.exception.code, FixtureStagingErrorCode.INPUT_UNAVAILABLE
        )
        run_session.assert_not_called()

    def test_prepared_dispatch_ignores_accumulated_control_replies(self) -> None:
        installation = native.VerifiedNativeInstallation(
            "installation-1", "boot-1", "broker-revision-1", "owner-key-1",
            "f" * 64, True, True, True, native._INSTALLATION_SEAL,
        )
        attempt = {
            "request_id": "export-1",
            "session_id": "session-1",
            "service_boot_id": "boot-1",
            "sequence": 3,
            "deadline_ns": 1000,
            "manifest_sha256": "a" * 64,
            "generation": 7,
            "authorization_sha256": "b" * 64,
            "members": [],
        }
        attempt_sha256 = hashlib.sha256(
            fixture_oracle.canonical_json(attempt)
        ).hexdigest()
        workflow = (
            {"operation": "hello", "request_id": "hello-1"},
            {"operation": "admit", "request_id": "admit-1"},
            {"operation": "stage", "request_id": "stage-1"},
            {"operation": "export", "request_id": "export-1"},
        )
        hello_response = {"status": "OK", "request_id": "hello-1"}
        prepared_response = {
            "status": "PREPARED",
            "attempt": attempt,
            "signed_request": workflow[-1],
            "workflow": list(workflow),
        }
        acknowledgement = {
            "status": "JOURNAL_ACKNOWLEDGED",
            "attempt_sha256": attempt_sha256,
        }
        response_frames = [
            hello_response,
            prepared_response,
            acknowledgement,
            *(
                {"status": "OK", "request_id": request["request_id"]}
                for request in workflow[1:]
            ),
        ]
        stdout_bytes = b"".join(
            fixture_oracle.canonical_json(response) + b"\n"
            for response in response_frames
        )
        stderr_bytes = fixture_oracle.canonical_json(
            _durable_completion(attempt)
        ) + b"\n"

        with TemporaryDirectory() as temporary:
            delivery_fd = os.open(
                Path(temporary) / "delivery.aqsnap",
                os.O_CREAT | os.O_EXCL | os.O_RDWR,
                0o600,
            )
            self.addCleanup(os.close, delivery_fd)
            broker_session, stdin_read_fd = self._pipe_backed_broker_session(
                stdout_bytes, stderr_bytes
            )
            broker_session.delivery_fd = delivery_fd
            broker_session.source_descriptors = ()
            self.assertEqual(
                broker_session.exchange(
                    {"operation": "hello", "request_id": "hello-1"}
                ),
                hello_response,
            )
            self.assertEqual(
                broker_session.exchange({"broker_operation": "prepare_export"}),
                prepared_response,
            )
            prepared = session.PreparedOwnerExport(
                attempt=attempt,
                signed_request=workflow[-1],
                workflow=workflow,
                continuation=broker_session,
                _authenticated_xpc=session._PREPARED_XPC_SEAL,
            )
            with mock.patch.object(native, "_require_root_executable"):
                transport = native.InstalledBrokerXPCSessionTransport(
                    installation,
                    authorization_path=Path(temporary) / "authorization.json",
                    receipt_directory=Path(temporary) / "receipts",
                )
                reply = transport.dispatch_prepared_export(
                    prepared, {}, {}, delivery_fd
                )

        consumed_responses = [
            fixture_oracle.decode_document(line)
            for line in broker_session.stdout_lines
        ]
        self.assertEqual(
            consumed_responses,
            [hello_response, prepared_response, acknowledgement],
        )
        request_frames = os.read(stdin_read_fd, 16_384).splitlines()
        self.assertEqual(
            [fixture_oracle.decode_document(line) for line in request_frames],
            [
                {"operation": "hello", "request_id": "hello-1"},
                {"broker_operation": "prepare_export"},
                {
                    "schema_version": 1,
                    "broker_operation": "journal_ack",
                    "attempt_sha256": attempt_sha256,
                },
                {"schema_version": 1, "broker_operation": "dispatch_prepared"},
            ],
        )
        self.assertEqual(broker_session.stdout_bytes_read, len(stdout_bytes))
        self.assertTrue(reply.receipt["durable"])
        self.assertEqual(reply.service_identity, installation.installation_id)
        self.assertEqual(reply.broker_identity, installation.broker_revision)


class BrokerLineSessionBufferTests(unittest.TestCase):
    def _session_after_reading(self, data: bytes):
        read_fd, write_fd = os.pipe()
        self.addCleanup(os.close, read_fd)
        try:
            os.write(write_fd, data)
        finally:
            os.close(write_fd)

        broker_session = object.__new__(native._BrokerLineSession)
        broker_session.stdout_fd = read_fd
        broker_session.stdout_buffer = bytearray()
        broker_session.stdout_lines = []
        broker_session.stdout_frames = []
        broker_session.stdout_bytes_read = 0
        broker_session.stderr_bytes = bytearray()
        broker_session.stdout_eof = False
        broker_session.stderr_eof = True
        broker_session._read_ready([read_fd])
        return broker_session

    def test_byte_reader_drains_multiple_complete_frames(self) -> None:
        broker_session = self._session_after_reading(
            b'{"status":"OK"}\n{"status":"PREPARED"}\n'
        )

        self.assertEqual(
            broker_session._take_buffered_lines(),
            [b'{"status":"OK"}', b'{"status":"PREPARED"}'],
        )

    def test_byte_reader_reassembles_a_newline_frame_split_across_reads(self) -> None:
        read_fd, write_fd = os.pipe()
        self.addCleanup(os.close, read_fd)
        self.addCleanup(os.close, write_fd)

        broker_session = object.__new__(native._BrokerLineSession)
        broker_session.stdout_fd = read_fd
        broker_session.stdout_buffer = bytearray()
        broker_session.stdout_lines = []
        broker_session.stdout_frames = []
        broker_session.stdout_bytes_read = 0
        broker_session.stderr_bytes = bytearray()
        broker_session.stdout_eof = False
        broker_session.stderr_eof = True

        os.write(write_fd, b'{"status":')
        broker_session._read_ready([read_fd])
        self.assertEqual(broker_session.stdout_frames, [])
        self.assertEqual(broker_session.stdout_buffer, b'{"status":')

        os.write(write_fd, b'"OK"}\n')
        broker_session._read_ready([read_fd])

        self.assertEqual(
            broker_session._take_buffered_lines(), [b'{"status":"OK"}']
        )

    def test_byte_reader_rejects_an_incomplete_final_frame(self) -> None:
        broker_session = self._session_after_reading(b'{"status":"OK"}\n{"status":')

        with self.assertRaises(FixtureStagingError) as raised:
            broker_session._take_buffered_lines()

        self.assertEqual(
            raised.exception.code,
            FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY,
        )


class InstalledBrokerPreparedEnvelopeSizeTests(unittest.TestCase):
    def test_prepare_round_trips_large_document_and_prepared_response_lines(self) -> None:
        installation = native.VerifiedNativeInstallation(
            "installation-1", "boot-1", "broker-revision-1", "owner-key-1",
            "f" * 64, True, True, True, native._INSTALLATION_SEAL,
        )
        members = [
            {
                "path": f"fixture/game-{index:04d}/" + "x" * 87 + ".rom",
                "size": 4,
                "sha256": "c" * 64,
            }
            for index in range(400)
        ]
        attempt = {"request_id": "request-1", "members": members}
        prepared_response = {
            "status": "PREPARED",
            "attempt": attempt,
            "signed_request": {"operation": "export"},
            "workflow": [{}, {}, {}, {}],
        }
        response_lines = [
            fixture_oracle.canonical_json({"status": "OK", "request_id": "hello-1"})
            + b"\n",
            fixture_oracle.canonical_json(
                prepared_response,
                maximum_bytes=fixture_oracle.MAX_RECEIPT_DOCUMENT_BYTES - 1,
            ) + b"\n",
        ]
        self.assertGreater(len(response_lines[1]), fixture_oracle.MAX_DOCUMENT_BYTES)
        self.assertLessEqual(
            len(response_lines[1]), fixture_oracle.MAX_BROKER_SESSION_LINE_BYTES
        )

        with TemporaryDirectory() as temporary:
            source_path = Path(temporary) / "game.rom"
            source_path.write_bytes(b"rom!")
            source_fd = os.open(source_path, os.O_RDONLY)
            self.addCleanup(os.close, source_fd)
            delivery_path = Path(temporary) / "delivery.aqsnap"
            delivery_fd = os.open(
                delivery_path,
                os.O_CREAT | os.O_EXCL | os.O_RDWR,
                0o600,
            )
            self.addCleanup(os.close, delivery_fd)
            wire_path = Path(temporary) / "requests.jsonl"
            wire_fd = os.open(
                wire_path,
                os.O_CREAT | os.O_EXCL | os.O_RDWR,
                0o600,
            )
            self.addCleanup(os.close, wire_fd)

            exchange = native._BrokerLineSession.exchange
            write_request = native._BrokerLineSession._write_request
            created_sessions = []

            class MemoryBrokerSession:
                def __init__(self, _arguments, _pass_fds, deadline_ns):
                    self.deadline_ns = deadline_ns
                    self.process = SimpleNamespace(args=("memory-broker",))
                    self.stdin_fd = wire_fd
                    self.lines = list(response_lines)
                    self.delivery_fd = None
                    self.source_descriptors = ()
                    created_sessions.append(self)

                def exchange(self, request):
                    return exchange(self, request)

                def _write_request(self, request):
                    return write_request(self, request)

                def _remaining(self):
                    return None

                def _timeout(self):
                    return 0

                def _read_stdout_line(self):
                    frame = self.lines.pop(0)
                    if not frame.endswith(b"\n"):
                        raise AssertionError("native response omitted line framing")
                    return frame[:-1]

                def abort(self):
                    pass

            intent = {
                "hello": {"operation": "hello", "request_id": "hello-1"},
                "workflow_templates": [
                    {"operation": "admit", "request_id": "admit-1"},
                    {
                        "operation": "stage",
                        "source_paths": ["fixture/game.rom"],
                    },
                    {"operation": "export", "deadline_ns": 1_000},
                ],
                "consent_envelope": {"schema_version": 1},
            }
            documents = {
                "consent": b"c" * fixture_oracle.MAX_DOCUMENT_BYTES,
                "signature": b"s",
                "manifest": b"{}",
                "plan": b"{}",
                "oracles": [],
                "evidence": [],
            }
            submitted_document_bytes = sum(
                len(value) for value in documents.values() if isinstance(value, bytes)
            )
            self.assertGreater(submitted_document_bytes, fixture_oracle.MAX_DOCUMENT_BYTES)
            with mock.patch.object(native, "_require_root_executable"), \
                 mock.patch.object(native, "_BrokerLineSession", MemoryBrokerSession), \
                 mock.patch.object(native.time, "monotonic_ns", return_value=100):
                transport = native.InstalledBrokerXPCSessionTransport(
                    installation,
                    authorization_path=Path(temporary) / "authorization.json",
                    receipt_directory=Path(temporary) / "receipts",
                )
                prepared = transport.prepare_export(
                    intent,
                    {"fixture/game.rom": source_fd},
                    documents,
                    delivery_fd,
                )

            self.assertEqual(prepared.attempt, attempt)
            self.assertEqual(len(created_sessions), 1)
            wire = os.pread(wire_fd, os.fstat(wire_fd).st_size, 0)
            frames = wire.splitlines(keepends=True)
            self.assertEqual(len(frames), 2)
            self.assertTrue(all(frame.endswith(b"\n") for frame in frames))
            self.assertGreater(len(frames[1]), fixture_oracle.MAX_DOCUMENT_BYTES)
            self.assertLessEqual(
                len(frames[1]), fixture_oracle.MAX_BROKER_SESSION_LINE_BYTES
            )
            decoded_request = fixture_oracle.decode_document(
                frames[1][:-1],
                maximum_bytes=fixture_oracle.MAX_BROKER_SESSION_DOCUMENT_BYTES,
            )
            encoded_consent = decoded_request["workflow_templates"][0]["documents_b64"]["consent"]
            self.assertEqual(len(encoded_consent), 4 * ((fixture_oracle.MAX_DOCUMENT_BYTES + 2) // 3))


class ProductionOwnerDispatchFailureTests(unittest.TestCase):
    def test_journal_dispatch_error_returns_blocked_result(self) -> None:
        installation = native.VerifiedNativeInstallation(
            "installation-1", "boot-1", "broker-revision-1", "owner-key-1",
            "f" * 64, True, True, True, native._INSTALLATION_SEAL,
        )
        attempt = {
            "manifest_sha256": _EXPORT_MANIFEST_SHA256,
            "authorization_sha256": _EXPORT_AUTHORIZATION_SHA256,
        }
        validated_grant = SimpleNamespace(
            fixture_manifest_sha256=_EXPORT_MANIFEST_SHA256,
            authorization_sha256=_EXPORT_AUTHORIZATION_SHA256,
        )
        with TemporaryDirectory() as temporary:
            journal = OwnerPrivateLifecycleJournal(Path(temporary))
            preparation = native.create_production_owner_export_preparation(
                validated_grant,
                journal,
                attempt_manifest_sha256=_EXPORT_MANIFEST_SHA256,
                attempt_authorization_sha256=_EXPORT_AUTHORIZATION_SHA256,
                authorization_path=_private_export_authorization(self),
                receipt_directory=Path("/owner/receipts"),
                export_intent={},
                source_fds={"fixture/game.rom": 10},
                documents={"manifest": _EXPORT_MANIFEST_BYTES},
                delivery_fd=11,
            )
            client = OwnerSessionExportClient._for_testing(
                journal,
                object(),
                service_identity="installation-1",
                broker_identity="broker-revision-1",
            )
            client._test_transport = False
            client._installation = installation
            owner_export = OwnerExportDispatch(
                client=client,
                attempt=attempt,
                signed_request={},
                source_fds={},
            )
            preparation = replace(
                preparation, _prepare=lambda _installation: owner_export
            )
            with mock.patch.object(
                orchestration, "_admit_production_staging_namespace"
            ), mock.patch.object(
                native, "select_verified_native_installation", return_value=installation
            ), mock.patch.object(
                orchestration, "_validate_grant_for_use", return_value=validated_grant
            ), mock.patch.object(
                OwnerExportDispatch,
                "dispatch",
                side_effect=JournalError("mutation outcome is uncertain"),
            ):
                result = orchestration._stage_production_export(
                    object(), preparation
                )

        self.assertEqual(result.status, "BLOCKED")
        self.assertEqual(
            result.blocker_code,
            FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY.value,
        )


class ProductionOwnerExportPreparationTests(unittest.TestCase):
    @staticmethod
    def _grant():
        return SimpleNamespace(
            fixture_manifest_sha256=_EXPORT_MANIFEST_SHA256,
            authorization_sha256=_EXPORT_AUTHORIZATION_SHA256,
        )

    def _make_preparation(
        self,
        grant,
        *,
        manifest_sha256=None,
        authorization_sha256=None,
        manifest_bytes=_EXPORT_MANIFEST_BYTES,
        authorization_document=_EXPORT_AUTHORIZATION_DOCUMENT,
    ):
        return native.create_production_owner_export_preparation(
            grant,
            object(),
            attempt_manifest_sha256=manifest_sha256 or _EXPORT_MANIFEST_SHA256,
            attempt_authorization_sha256=(
                authorization_sha256 or _EXPORT_AUTHORIZATION_SHA256
            ),
            authorization_path=_private_export_authorization(
                self, authorization_document
            ),
            receipt_directory=Path("/owner/receipts"),
            export_intent={},
            source_fds={"fixture/game.rom": 10},
            documents={"manifest": manifest_bytes},
            delivery_fd=11,
        )

    def test_mismatched_attempt_binding_is_rejected_before_preparation(self) -> None:
        grant = self._grant()
        for manifest, authorization in (
            ("c" * 64, grant.authorization_sha256),
            (grant.fixture_manifest_sha256, "d" * 64),
        ):
            with self.subTest(
                manifest=manifest[:1], authorization=authorization[:1]
            ):
                preparation = self._make_preparation(
                    grant,
                    manifest_sha256=manifest,
                    authorization_sha256=authorization,
                )
                prepare = mock.Mock()
                preparation = replace(preparation, _prepare=prepare)
                with mock.patch.object(
                    orchestration, "_admit_production_staging_namespace"
                ), mock.patch.object(
                    orchestration, "_validate_grant_for_use", return_value=grant
                ), mock.patch.object(
                    native, "select_verified_native_installation"
                ) as select_installation:
                    result = orchestration._stage_production_export(
                        grant, preparation
                    )

                self.assertEqual(
                    result.blocker_code,
                    FixtureStagingErrorCode.INVALID_AUTHORITY.value,
                )
                prepare.assert_not_called()
                select_installation.assert_not_called()

    def test_missing_grant_is_rejected_before_preparation(self) -> None:
        preparation = self._make_preparation(None)
        prepare = mock.Mock()
        preparation = replace(preparation, _prepare=prepare)
        with mock.patch.object(
            orchestration, "_admit_production_staging_namespace"
        ), mock.patch.object(
            orchestration,
            "_validate_grant_for_use",
            side_effect=FixtureStagingError(FixtureStagingErrorCode.INVALID_AUTHORITY),
        ), mock.patch.object(
            native, "select_verified_native_installation"
        ) as select_installation:
            result = orchestration._stage_production_export(None, preparation)

        self.assertEqual(
            result.blocker_code, FixtureStagingErrorCode.INVALID_AUTHORITY.value
        )
        prepare.assert_not_called()
        select_installation.assert_not_called()

    def test_manifest_and_authorization_inputs_are_checked_before_preparation(self) -> None:
        grant = self._grant()
        changed_authorization = {
            "schema_version": 1,
            "authorization_id": "different-authorization",
        }
        for manifest_bytes, authorization_document in (
            (b"changed manifest bytes", _EXPORT_AUTHORIZATION_DOCUMENT),
            (_EXPORT_MANIFEST_BYTES, changed_authorization),
        ):
            with self.subTest(
                manifest_changed=manifest_bytes != _EXPORT_MANIFEST_BYTES,
                authorization_changed=(
                    authorization_document != _EXPORT_AUTHORIZATION_DOCUMENT
                ),
            ):
                preparation = self._make_preparation(
                    grant,
                    manifest_bytes=manifest_bytes,
                    authorization_document=authorization_document,
                )
                prepare = mock.Mock()
                preparation = replace(preparation, _prepare=prepare)
                with mock.patch.object(
                    orchestration, "_admit_production_staging_namespace"
                ), mock.patch.object(
                    orchestration, "_validate_grant_for_use", return_value=grant
                ), mock.patch.object(
                    native, "select_verified_native_installation"
                ) as select_installation:
                    result = orchestration._stage_production_export(
                        grant, preparation
                    )

                self.assertEqual(
                    result.blocker_code,
                    FixtureStagingErrorCode.INVALID_AUTHORITY.value,
                )
                prepare.assert_not_called()
                select_installation.assert_not_called()

    def test_native_attempt_is_rechecked_before_dispatch(self) -> None:
        grant = self._grant()
        preparation = self._make_preparation(grant)
        abort = mock.Mock()
        prepared = SimpleNamespace(
            attempt={
                "manifest_sha256": "c" * 64,
                "authorization_sha256": grant.authorization_sha256,
            },
            signed_request={},
            workflow=(),
            continuation=SimpleNamespace(abort=abort),
        )
        client = SimpleNamespace(prepare_export=mock.Mock(return_value=prepared))
        installation = native.VerifiedNativeInstallation(
            "installation-1", "boot-1", "broker-revision-1", "owner-key-1",
            "f" * 64, True, True, True, native._INSTALLATION_SEAL,
        )

        with mock.patch.object(
            native, "_validate_grant_for_use", return_value=grant
        ), mock.patch.object(
            native, "create_owner_session_export_client", return_value=client
        ):
            with self.assertRaises(FixtureStagingError) as raised:
                preparation._prepare(installation)

        self.assertEqual(
            raised.exception.code, FixtureStagingErrorCode.INVALID_AUTHORITY
        )
        client.prepare_export.assert_called_once()
        abort.assert_called_once()

    def test_stage_rejects_attempt_binding_before_native_preparation(self) -> None:
        grant = self._grant()
        preparation = self._make_preparation(
            grant, manifest_sha256="c" * 64
        )
        prepare = mock.Mock()
        preparation = replace(preparation, _prepare=prepare)
        installation = native.VerifiedNativeInstallation(
            "installation-1", "boot-1", "broker-revision-1", "owner-key-1",
            "f" * 64, True, True, True, native._INSTALLATION_SEAL,
        )

        with mock.patch.object(
            orchestration, "_admit_production_staging_namespace"
        ), mock.patch.object(
            orchestration, "_validate_grant_for_use", return_value=grant
        ), mock.patch.object(
            native, "select_verified_native_installation", return_value=installation
        ):
            result = orchestration._stage_production_export(grant, preparation)

        self.assertEqual(result.status, "BLOCKED")
        self.assertEqual(
            result.blocker_code, FixtureStagingErrorCode.INVALID_AUTHORITY.value
        )
        prepare.assert_not_called()

    def test_stage_rejects_a_different_grant_object_before_preparation(self) -> None:
        preparation_grant = self._grant()
        stage_grant = self._grant()
        preparation = self._make_preparation(preparation_grant)
        prepare = mock.Mock()
        preparation = replace(preparation, _prepare=prepare)

        with mock.patch.object(
            orchestration, "_admit_production_staging_namespace"
        ), mock.patch.object(
            orchestration, "_validate_grant_for_use", return_value=stage_grant
        ):
            result = orchestration._stage_production_export(
                stage_grant, preparation
            )

        self.assertEqual(result.status, "BLOCKED")
        self.assertEqual(
            result.blocker_code, FixtureStagingErrorCode.INVALID_AUTHORITY.value
        )
        prepare.assert_not_called()

    def test_valid_matching_grant_remains_behind_public_fail_closed_gate(self) -> None:
        grant = self._grant()
        preparation = self._make_preparation(grant)
        prepare = mock.Mock()
        preparation = replace(preparation, _prepare=prepare)

        result = orchestration.stage_fixtures(
            grant,
            source_roots={},
            destination=None,
            owner_export_preparation=preparation,
        )

        self.assertEqual(result.status, "BLOCKED")
        self.assertEqual(
            result.blocker_code,
            FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY.value,
        )
        prepare.assert_not_called()


class NativeContractResultTests(unittest.TestCase):
    def _fixture(self):
        manifest, record, evidence = bundle(True)
        contract = validate(manifest, record, evidence)
        grant = _GrantBinding(
            fixture_manifest_sha256=contract.manifest_sha256,
            plan_sha256=manifest["plan_sha256"],
            rules_sha256=manifest["rules_sha256"],
            fixture_ids=tuple(item.fixture_id for item in contract.fixtures),
            required_fixture_ids=tuple(item.fixture_id for item in contract.fixtures),
        mandatory_fixture_ids=tuple(item.fixture_id for item in contract.fixtures),
            coverage_mode="mandatory_full_plan",
        )
        result = {
            "store": {"session_id": "session-a"},
            "manifest_sha256": contract.manifest_sha256,
            "source_authority": contract.source_authority,
            "selected_fixture_ids": list(grant.fixture_ids),
            "oracle_support": [item.independent_support for item in contract.fixtures],
            "coverage": {
                "mode": "mandatory_full_plan",
                "required_fixture_ids": list(grant.required_fixture_ids),
                "selected_fixture_ids": list(grant.fixture_ids),
                "mandatory_fixture_ids": list(grant.mandatory_fixture_ids),
            },
            "owner_consent": "verified_by_installed_owner_key",
            "owner_approval": "not_checked",
            "byte_integrity": "not_checked",
        }
        response = encoded(
            {"status": "OK", "request_id": "request-a", "result": result}
        )
        return manifest, record, grant, evidence, response

    def test_result_binds_oracle_grant_and_native_claims(self) -> None:
        manifest, oracle, grant, evidence, response = self._fixture()
        with mock.patch.object(native, "_validate_grant_for_use", return_value=grant):
            validated = native.validate_native_contract_result(
                grant,
                response,
                encoded(manifest),
                (encoded(oracle),),
                tuple(encoded(item) for item in evidence),
            )
        self.assertEqual(validated.owner_consent, "unverified")
        self.assertEqual(validated.owner_approval, "not_checked")
        self.assertEqual(validated.byte_integrity, "not_checked")
        self.assertEqual(
            validated.oracle_support,
            (native.SnapshotSupport.PINNED_UNVERIFIED,),
        )

    def test_native_result_requires_canonical_serialization(self) -> None:
        manifest, oracle, grant, evidence, response = self._fixture()
        envelope = fixture_oracle.decode_document(response)
        reordered = {
            "status": envelope["status"],
            "result": envelope["result"],
            "request_id": envelope["request_id"],
        }
        noncanonical_responses = (
            response.replace(b'"request_id":', b'"request_id": ', 1),
            json.dumps(
                reordered,
                ensure_ascii=False,
                sort_keys=False,
                separators=(",", ":"),
            ).encode("utf-8"),
        )
        with mock.patch.object(native, "_validate_grant_for_use", return_value=grant):
            for candidate in noncanonical_responses:
                with self.subTest(candidate=candidate[:24]):
                    self.assertNotEqual(
                        fixture_oracle.canonical_json(
                            fixture_oracle.decode_document(candidate)
                        ),
                        candidate,
                    )
                    with self.assertRaises(FixtureStagingError) as raised:
                        native.validate_native_contract_result(
                            grant,
                            candidate,
                            encoded(manifest),
                            (encoded(oracle),),
                            tuple(encoded(item) for item in evidence),
                        )
                    self.assertIs(
                        raised.exception.code,
                        FixtureStagingErrorCode.EXPECTATION_UNVERIFIED,
                    )

    def test_native_result_cannot_promote_pinned_reference(self) -> None:
        manifest, oracle, grant, evidence, response = self._fixture()
        envelope = native.fixture_oracle.decode_document(response)
        changed = encoded(
            {
                **envelope,
                "result": {
                    **envelope["result"],
                    "oracle_support": ["verified_independent_reference"],
                },
            }
        )
        with mock.patch.object(native, "_validate_grant_for_use", return_value=grant):
            with self.assertRaises(FixtureStagingError) as raised:
                native.validate_native_contract_result(
                    grant,
                    changed,
                    encoded(manifest),
                    (encoded(oracle),),
                    tuple(encoded(item) for item in evidence),
                )

        self.assertIs(
            raised.exception.code, FixtureStagingErrorCode.EXPECTATION_UNVERIFIED
        )

    def test_native_result_cannot_promote_owner_approval(self) -> None:
        manifest, oracle, grant, evidence, response = self._fixture()
        changed = encoded(
            {
                **native.fixture_oracle.decode_document(response),
                "result": {
                    **native.fixture_oracle.decode_document(response)["result"],
                    "owner_approval": "approved",
                },
            }
        )
        with mock.patch.object(native, "_validate_grant_for_use", return_value=grant):
            with self.assertRaises(FixtureStagingError) as raised:
                native.validate_native_contract_result(
                    grant,
                    changed,
                    encoded(manifest),
                    (encoded(oracle),),
                    tuple(encoded(item) for item in evidence),
                )
        self.assertIs(raised.exception.code, FixtureStagingErrorCode.EXPECTATION_UNVERIFIED)

    def test_raw_owner_consent_field_cannot_claim_installed_key_verification(self) -> None:
        manifest, oracle, grant, evidence, response = self._fixture()
        envelope = native.fixture_oracle.decode_document(response)
        self.assertEqual(
            envelope["result"]["owner_consent"], "verified_by_installed_owner_key"
        )
        with mock.patch.object(native, "_validate_grant_for_use", return_value=grant):
            validated = native.validate_native_contract_result(
                grant,
                response,
                encoded(manifest),
                (encoded(oracle),),
                tuple(encoded(item) for item in evidence),
            )
        self.assertEqual(validated.owner_consent, "unverified")


    def test_native_result_must_preserve_mandatory_fixture_coverage(self) -> None:
        manifest, oracle, grant, evidence, response = self._fixture()
        envelope = native.fixture_oracle.decode_document(response)
        result = envelope["result"]
        changed = encoded(
            {
                **envelope,
                "result": {
                    **result,
                    "coverage": {
                        **result["coverage"],
                        "mandatory_fixture_ids": [],
                    },
                },
            }
        )
        with mock.patch.object(native, "_validate_grant_for_use", return_value=grant):
            with self.assertRaises(FixtureStagingError) as raised:
                native.validate_native_contract_result(
                    grant,
                    changed,
                    encoded(manifest),
                    (encoded(oracle),),
                    tuple(encoded(item) for item in evidence),
                )
        self.assertIs(raised.exception.code, FixtureStagingErrorCode.EXPECTATION_UNVERIFIED)


class SnapshotManifestAdmissionTests(FixtureStagingTestCase):
    def _snapshot_inputs(
        self, support: IdentityEvidenceKind
    ) -> tuple[tuple[Path, ...], tuple[Path, ...]]:
        fixture = copy.deepcopy(self.fixture_document["fixtures"][0])
        fixture.pop("identity_evidence")
        fixture.pop("oracle_pin", None)
        rules_sha256 = fixture_oracle.manifest_sha256(self.plan_document["rules"])
        evidence_documents: list[dict[str, object]] = []
        evidence_pins: list[dict[str, object]] = []
        if support is IdentityEvidenceKind.SYNTHETIC_ONLY:
            corpus_origin = "synthetic"
            method = "synthetic_expectation"
            identity_evidence = "synthetic_expectation_v2"
        else:
            corpus_origin = "owner_private_genuine"
            method = "independent_reference"
            identity_evidence = "independent_reference_pinned_v1"
            evidence = {
                "schema_version": 1,
                "evidence_ref": "evidence-synthetic",
                "revision": "revision-1",
                "fixture": fixture,
                "corpus_origin": corpus_origin,
                "acceptance_rule_sha256": rules_sha256,
                "method": method,
                "provenance": "Synthetic deterministic test record",
                "limitations": ["No external source is authenticated"],
                "conflicts": [],
                "evidence_refs": [],
                "reference": {
                    "ref": "test-reference",
                    "revision": "revision-1",
                    "sha256": "d" * 64,
                },
            }
            evidence_documents.append(evidence)
            evidence_pins.append(
                {
                    "schema_version": 1,
                    "evidence_ref": evidence["evidence_ref"],
                    "revision": evidence["revision"],
                    "sha256": fixture_oracle.evidence_sha256(evidence),
                }
            )

        oracle_document = {
            "schema_version": 1,
            "oracle_ref": "oracle-synthetic",
            "revision": "revision-1",
            "fixture": fixture,
            "corpus_origin": corpus_origin,
            "acceptance_rule_sha256": rules_sha256,
            "method": method,
            "provenance": "Synthetic deterministic test record",
            "limitations": ["No external source is authenticated"],
            "conflicts": [],
            "evidence_refs": evidence_pins,
        }
        manifest_fixture = copy.deepcopy(fixture)
        manifest_fixture.update(
            {
                "identity_evidence": identity_evidence,
                "oracle_pin": {
                    "schema_version": 1,
                    "oracle_ref": oracle_document["oracle_ref"],
                    "revision": oracle_document["revision"],
                    "sha256": fixture_oracle.oracle_sha256(oracle_document),
                },
            }
        )
        manifest_document = {
            "schema_version": 2,
            "source_authority": fixture_oracle.SOURCE_AUTHORITY,
            "plan_sha256": self.fixture_document["plan_sha256"],
            "rules_sha256": rules_sha256,
            "coverage_mode": self.fixture_document["coverage_mode"],
            "selected_fixture_ids": self.fixture_document["selected_fixture_ids"],
            "fixtures": [manifest_fixture],
        }
        self._rebind_inputs(fixture_manifest=manifest_document)

        oracle_path = write_private_json(
            self.directory, "oracle.json", oracle_document
        )
        evidence_paths = tuple(
            write_private_json(self.directory, f"evidence-{index}.json", document)
            for index, document in enumerate(evidence_documents)
        )
        return (oracle_path,), evidence_paths

    def _authorize_snapshot(
        self,
        oracle_paths: tuple[Path, ...],
        evidence_paths: tuple[Path, ...],
    ):
        return fixture_staging.authorize_fixture_staging(
            self.authorization,
            self.approval,
            plan_path=self.plan_path,
            fixture_manifest_path=self.fixture_path,
            operation_id="fixture-stage-synthetic",
            oracle_paths=oracle_paths,
            evidence_paths=evidence_paths,
        )

    def test_schema_two_admission_downgrades_unavailable_verification(self) -> None:
        cases = (
            (IdentityEvidenceKind.SYNTHETIC_ONLY, IdentityEvidenceKind.SYNTHETIC_ONLY),
            (IdentityEvidenceKind.PINNED_UNVERIFIED, IdentityEvidenceKind.PINNED_UNVERIFIED),
            (
                IdentityEvidenceKind.VERIFIED_INDEPENDENT_REFERENCE,
                IdentityEvidenceKind.PINNED_UNVERIFIED,
            ),
        )
        for support, expected in cases:
            with self.subTest(support=support):
                oracle_paths, evidence_paths = self._snapshot_inputs(support)
                grant = self._authorize_snapshot(oracle_paths, evidence_paths)

                self.assertEqual(
                    grant._fixture_expectations[0].identity_evidence, expected
                )
                self.assertEqual(
                    grant.approval_authorization_sha256,
                    self.authorization.canonical_sha256,
                )
                self.assertFalse(grant.device_admitted)
                self.assertFalse(grant.session_authorization_consumed)

    def test_authorizer_rejects_caller_reference_verifier(self) -> None:
        oracle_paths, evidence_paths = self._snapshot_inputs(
            IdentityEvidenceKind.PINNED_UNVERIFIED
        )
        with self.assertRaises(TypeError):
            fixture_staging.authorize_fixture_staging(
                self.authorization,
                self.approval,
                plan_path=self.plan_path,
                fixture_manifest_path=self.fixture_path,
                operation_id="fixture-stage-synthetic",
                oracle_paths=oracle_paths,
                evidence_paths=evidence_paths,
                reference_verifier=lambda _: True,
            )

    def test_schema_two_missing_oracle_is_not_reinterpreted_as_schema_one(self) -> None:
        self._snapshot_inputs(IdentityEvidenceKind.SYNTHETIC_ONLY)
        with self.assertRaises(FixtureStagingError) as raised:
            self._authorize_snapshot((), ())

        self.assertEqual(
            raised.exception.code, FixtureStagingErrorCode.EXPECTATION_UNVERIFIED
        )

    def test_schema_two_support_tier_survives_verified_staging(self) -> None:
        oracle_paths, evidence_paths = self._snapshot_inputs(
            IdentityEvidenceKind.SYNTHETIC_ONLY
        )
        grant = self._authorize_snapshot(oracle_paths, evidence_paths)
        _, source_root, destination, grant = self._make_staging_inputs(
            capability=self.synthetic_capability,
            grant=grant,
        )

        result = _stage_fixtures_for_synthetic_mechanics(
            self.synthetic_capability,
            grant,
            source_roots={"fixture-synthetic": source_root},
            destination=destination,
            now=NOW,
        )

        self.assertEqual(result.status, "VERIFIED_FIXTURE", result.blocker_code)
        self.assertEqual(result.identity_evidence, "synthetic_only")
        self.assertEqual(result.evidence_class, "SYNTHETIC_SIMULATION")


class ReceiptReconnectBindingTests(unittest.TestCase):
    def test_reconnect_queries_only_the_original_read_only_receipt_binding(self) -> None:
        installation = native.VerifiedNativeInstallation(
            "installation-1", "boot-1", "broker-revision-1", "owner-key-1",
            "f" * 64, True, True, True, native._INSTALLATION_SEAL,
        )
        attempt = {
            "request_id": "request-original",
            "session_id": "session-original",
            "service_boot_id": "boot-original",
            "connection_id": "connection-original",
            "installation_id": "installation-1",
            "broker_revision": "broker-revision-1",
            "owner_key_id": "owner-key-1",
            "authorization_sha256": "a" * 64,
            "sequence": 7,
            "deadline_ns": 99,
            "manifest_sha256": "b" * 64,
            "generation": 4,
            "members": [
                {
                    "path": (
                        f"fixture/game-{index:04d}/"
                        + "x" * (87 if index < 399 else 68)
                        + ".rom"
                    ),
                    "size": 4,
                    "sha256": "c" * 64,
                }
                for index in range(400)
            ],
        }
        expected_binding = {
            key: attempt[key]
            for key in (
                "request_id", "session_id", "service_boot_id", "sequence",
                "deadline_ns", "manifest_sha256", "generation", "members",
            )
        }
        completion = {
            "request_id": attempt["request_id"],
            "session_id": attempt["session_id"],
            "service_boot_id": attempt["service_boot_id"],
            "sequence": attempt["sequence"],
            "deadline_ns": attempt["deadline_ns"],
            "manifest_sha256": attempt["manifest_sha256"],
            "generation": attempt["generation"],
            "members": attempt["members"],
        }
        requests: list[dict[str, object]] = []
        request_lines: list[bytes] = []
        def run_session(arguments, input_bytes, pass_fds, deadline_ns, **kwargs):
            self.assertEqual(kwargs, {
                "maximum_stream_bytes": fixture_oracle.MAX_RECEIPT_DOCUMENT_BYTES,
            })
            request_lines.append(input_bytes)
            self.assertTrue(input_bytes.endswith(b"\n"))
            self.assertLessEqual(len(input_bytes), fixture_oracle.MAX_RECEIPT_DOCUMENT_BYTES)
            requests.append(fixture_oracle.decode_document(
                input_bytes[:-1],
                maximum_bytes=fixture_oracle.MAX_RECEIPT_DOCUMENT_BYTES - 1,
            ))
            self.assertEqual(arguments, ("session",))
            self.assertEqual(pass_fds, ())
            self.assertEqual(deadline_ns, 100 + native.RECEIPT_QUERY_TIMEOUT_NS)
            response = fixture_oracle.canonical_json(
                {"completion": completion},
                maximum_bytes=fixture_oracle.MAX_RECEIPT_DOCUMENT_BYTES - 1,
            ) + b"\n"
            self.assertGreater(len(response), fixture_oracle.MAX_DOCUMENT_BYTES)
            self.assertLessEqual(len(response), fixture_oracle.MAX_RECEIPT_DOCUMENT_BYTES)
            return response, b""

        with mock.patch.object(native, "_require_root_executable"):
            transport = native.InstalledBrokerXPCSessionTransport(
                installation,
                authorization_path=Path("/owner/authorization.json"),
                receipt_directory=Path("/owner/receipts"),
            )
        with mock.patch.object(native.time, "monotonic_ns", return_value=100), \
             mock.patch.object(transport, "_run_session", side_effect=run_session):
            reply = transport.query_export_receipt(attempt)

        self.assertEqual(
            requests,
            [{
                "operation": "receipt_query",
                "request_id": attempt["request_id"],
                "binding": expected_binding,
                "query_deadline_ns": 100 + native.RECEIPT_QUERY_TIMEOUT_NS,
            }],
        )
        self.assertEqual(reply.receipt, completion)
        self.assertEqual(len(request_lines), 1)
        self.assertEqual(len(request_lines[0]), 82_726)


if __name__ == "__main__":
    unittest.main()
