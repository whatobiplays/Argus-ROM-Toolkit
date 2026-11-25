"""Exercise the attended Readiness transport with injected device operations."""

import json
import tempfile
import unittest
from io import BytesIO
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

from . import _evidence_storage
from .readiness_b1_transport import (
    B1_OUTCOME_ENTRY_BUDGET, _require_closed_forward_obligations,
    require_b1_capacity, run_readiness_exchange,
)
from .readiness_probe import AttemptRunner, EvidenceStore, Identity, ProbeError, RESPONSE_CAP, frame, success
from .readiness_probe_session import Discovery
from .test_readiness_probe_session import FakeADB


class ReadinessExchangeTests(unittest.TestCase):
    def run_case(
        self, *, approved=True, failing_read=False, response=b"", interrupted=False,
        release_failed=False, persistence_failed=False, readback_failed=False, late_open=False,
        near_capacity=False,
    ):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            if near_capacity:
                # Other phases leave one entry for the outcome and six for
                # the forward events, plus the forward lock and receipt directory.
                for index in range(_evidence_storage.MAX_OUTCOMES_ENTRIES - 9):
                    (path / f"history-{index}").touch()
            adapter = FakeADB()
            now = [1]
            discovery = Discovery("a" * 32, "b" * 32, "localabstract:probe", 1, 2000, 100, 5100)
            opened = Mock(wraps=adapter.open_transport)
            transport_read = Mock(return_value=response)
            transport_write = Mock()
            readiness_write = Mock()
            ids = Identity("c" * 32, "d" * 32, "e" * 32)
            reply = BytesIO(frame(success(ids, 100, 101), RESPONSE_CAP))

            def open_transport(*args, **kwargs):
                transport = opened(*args, **kwargs)
                if opened.call_count == 1:
                    transport.read = transport_read
                    transport.write = transport_write
                    if release_failed:
                        transport.close = Mock(side_effect=ProbeError("TimedOut"))
                else:
                    if late_open:
                        self.assertEqual(kwargs["deadline"], 60)
                        now[0] = 60.5
                    transport.write = readiness_write
                    transport.read = Mock(
                        side_effect=TimeoutError if failing_read else lambda size, _: reply.read(size),
                    )
                return transport

            adapter.open_transport = open_transport
            create = adapter.create_no_rebind

            def verify_pending(*args, **kwargs):
                records = list(path.glob("*.json"))
                self.assertEqual(len(records), 1)
                self.assertEqual(json.loads(records[0].read_bytes())["state"], "creation-pending")
                self.assertEqual(records[0].stat().st_mode & 0o777, 0o600)
                create(*args, **kwargs)

            adapter.create_no_rebind = verify_pending
            lookup = adapter.lookup
            if readback_failed:
                adapter.lookup = lambda *args, **kwargs: (
                    "localabstract:probe" if adapter.removed else lookup(*args, **kwargs)
                )

            def confirm(*, deadline):
                if interrupted:
                    raise KeyboardInterrupt
                now[0] = 7
                return discovery

            receipts = EvidenceStore(path / "receipts")
            references = dict.fromkeys(
                ("target_ref", "artifact_ref", "authorization_ref",
                 "rules_ref", "assertion_alias", "evidence_ref"), "private-ref",
            )
            with patch("scripts.android_qualification.readiness_b1_transport.AttemptRunner",
                       wraps=AttemptRunner) as runner:
                def approve(uid, *, deadline):
                    if late_open:
                        now[0] = 59
                    return uid if approved else None

                call = lambda: run_readiness_exchange(
                    adapter, target="target", build="build", session_id="a" * 32,
                    local="tcp:12345", remote="localabstract:probe", started=0,
                    deadline=120, clock=lambda: now[0], outcomes_directory=path,
                    receipts=receipts, ids=ids, discovery_attempt="b" * 32,
                    references=references, arm_on_device=lambda *, deadline: None,
                    confirm_discovery=confirm, approve_uid=approve,
                )
                if persistence_failed:
                    with patch("scripts.android_qualification._evidence_storage._publish_no_replace",
                               side_effect=OSError), self.assertRaises(ProbeError):
                        call()
                    self.assertFalse(adapter.forwards)
                    opened.assert_not_called()
                    self.assertEqual(list(path.glob("*.json")), [])
                    return
                if interrupted:
                    with self.assertRaises(KeyboardInterrupt):
                        call()
                elif failing_read or not approved or response or release_failed or readback_failed or late_open:
                    with self.assertRaises(ProbeError) as blocked:
                        call()
                    if late_open:
                        self.assertEqual(blocked.exception.code, "TimedOut")
                else:
                    self.assertEqual(call()["outcome"]["result"], {"state": "Ready"})
                reaches_readiness = approved and not response and not interrupted and not release_failed
                self.assertEqual(runner.call_count, int(reaches_readiness and not late_open))
                self.assertEqual(readiness_write.call_count, int(reaches_readiness and not late_open))
                self.assertEqual(len(receipts.verify()), int(failing_read))
            self.assertEqual(opened.call_count, 2 if reaches_readiness else 1)
            self.assertEqual(transport_read.call_count, 1)
            transport_write.assert_not_called()
            if release_failed or readback_failed:
                with self.assertRaises(ProbeError):
                    _require_closed_forward_obligations(path)
                self.assertEqual(len(adapter.removed), int(readback_failed))
                return
            if near_capacity:
                (path / "formal-outcome").touch()
                self.assertEqual(len(list(path.iterdir())), _evidence_storage.MAX_OUTCOMES_ENTRIES)
            _require_closed_forward_obligations(path)
            self.assertEqual(len(adapter.removed), 1)
            self.assertFalse(adapter.forwards)
            self.assertTrue(any(json.loads(f.read_bytes())["state"] == "closed" for f in path.glob("*.json")))

    def test_ready_releases_both_connections_and_removes_owned_forward(self):
        self.run_case()

    def test_capacity_counts_inode_for_nested_failure_receipt(self):
        with tempfile.TemporaryDirectory() as directory:
            for receipts_created in (False, True):
                remaining = B1_OUTCOME_ENTRY_BUDGET - int(receipts_created)
                space = SimpleNamespace(f_bavail=256, f_frsize=4096, f_files=8192, f_favail=remaining)
                with patch("scripts.android_qualification.readiness_b1_transport.os.fstatvfs",
                           return_value=space):
                    with self.assertRaises(ProbeError) as failure:
                        require_b1_capacity(Path(directory), receipts_created=receipts_created)
                    self.assertEqual(failure.exception.code, "ResourceLimitExceeded")
                    space.f_favail += 1
                    require_b1_capacity(Path(directory), receipts_created=receipts_created)
                    space.f_bavail -= 1
                    with self.assertRaises(ProbeError) as failure:
                        require_b1_capacity(Path(directory), receipts_created=receipts_created)
                    self.assertEqual(failure.exception.code, "ResourceLimitExceeded")

    def test_forward_restores_at_the_outcomes_limit(self):
        self.run_case(near_capacity=True)

    def test_forward_obligation_remains_open_near_the_outcomes_limit(self):
        self.run_case(near_capacity=True, readback_failed=True)

    def test_refused_uid_prevents_readiness_and_removes_owned_forward(self):
        self.run_case(approved=False)

    def test_discovery_application_bytes_prevent_readiness(self):
        self.run_case(response=b"x")

    def test_readiness_failure_restores_forward(self):
        self.run_case(failing_read=True)

    def test_interruption_during_owner_control_restores_forward(self):
        self.run_case(interrupted=True)

    def test_failed_release_keeps_owned_forward_and_blocks_another_attempt(self):
        self.run_case(release_failed=True)

    def test_failed_removal_readback_leaves_obligation_open(self):
        self.run_case(readback_failed=True)

    def test_persistence_failure_precedes_create_and_transport(self):
        self.run_case(persistence_failed=True)

    def test_readiness_connection_is_bounded_by_restoration_cutoff(self):
        self.run_case(late_open=True)
