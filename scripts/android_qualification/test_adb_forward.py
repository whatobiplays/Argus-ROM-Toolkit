"""Host-only tests for the bounded ADB forward and loopback adapters."""

import socket
import subprocess
import unittest

from . import readiness_probe as probe
from . import readiness_probe_session as session_module
from .adb_forward import (
    AdbForwardAdapter,
    ForwardedSocketTransport,
    _AdbCommandRunner,
    _MAX_COMMAND_OUTPUT_BYTES,
    _MAX_PROCESS_GROUP_OUTPUT_BYTES,
    _host_process_group_is_quiescent,
    _process_group_listing_is_quiescent,
    _deadline_remaining,
)


TARGET = "SERIAL-1"
BUILD = "brand/device:version/id/incremental:user/release-keys"
LOCAL = "tcp:12345"
REMOTE = "localabstract:probe_session"


class FakeClock:
    def __init__(self, value=10.0):
        self.value = value

    def __call__(self):
        return self.value


class FakeRunner:
    def __init__(self, replies=()):
        self.replies = list(replies)
        self.calls = []

    def run(self, argv, deadline):
        self.calls.append((tuple(argv), deadline))
        if not self.replies:
            raise AssertionError("unexpected ADB command")
        reply = self.replies.pop(0)
        if isinstance(reply, BaseException):
            raise reply
        return reply


class FakeSocket:
    def __init__(self, replies=()):
        self.replies = list(replies)
        self.connected_to = None
        self.timeouts = []
        self.writes = []
        self.closed = False
        self.connect_error = None
        self.write_error = None
        self.read_error = None
        self.raw_read_result = None
        self.close_error = None

    def settimeout(self, timeout):
        self.timeouts.append(timeout)

    def connect(self, address):
        if self.connect_error is not None:
            raise self.connect_error
        self.connected_to = address

    def sendall(self, value):
        if self.write_error is not None:
            raise self.write_error
        self.writes.append(value)

    def recv(self, count):
        if self.read_error is not None:
            raise self.read_error
        if self.raw_read_result is not None:
            return self.raw_read_result
        if not self.replies:
            return b""
        value = self.replies.pop(0)
        return value[:count]

    def close(self):
        if self.close_error is not None:
            raise self.close_error
        self.closed = True


class AdbForwardAdapterTests(unittest.TestCase):
    def adapter(self, replies=(), *, clock=None, sock=None):
        clock = clock or FakeClock()
        runner = FakeRunner(replies)
        socket_factory = (lambda *_args: sock) if sock is not None else None
        options = {"runner": runner, "clock": clock}
        if socket_factory is not None:
            options["socket_factory"] = socket_factory
        return AdbForwardAdapter(**options), runner, clock

    def identity_replies(self, *tail):
        return [b"device\n", (BUILD + "\n").encode("ascii"), *tail]

    def make_owned_session(self, sock, *, clock=None, arm=True):
        row = f"{TARGET} {LOCAL} {REMOTE}\n".encode("ascii")
        adapter, runner, clock = self.adapter(
            self.identity_replies(
                b"", b"", row, b"device\n", (BUILD + "\n").encode("ascii"), row
            ),
            clock=clock,
            sock=sock,
        )
        session = session_module.ForwardSession(
            adapter,
            TARGET,
            BUILD,
            "a" * 32,
            LOCAL,
            REMOTE,
            clock(),
            clock() + 600,
            clock=clock,
            obligation=lambda _record: None,
        )
        session.create()
        if arm:
            session.arm("b" * 32, now=clock())
        return session, runner, clock

    def test_deadline_helper_rejects_invalid_and_expired_values(self):
        clock = FakeClock(10)
        self.assertEqual(_deadline_remaining(clock, 12), 2)
        for deadline in (None, True, float("inf"), 10):
            with self.subTest(deadline=deadline):
                with self.assertRaises(probe.ProbeError):
                    _deadline_remaining(clock, deadline)
        for clock_value in (float("nan"), float("inf"), True):
            with self.subTest(clock_value=clock_value):
                with self.assertRaises(probe.ProbeError):
                    _deadline_remaining(FakeClock(clock_value), 12)

    def test_identity_uses_explicit_target_and_fixed_command_order(self):
        adapter, runner, _ = self.adapter(self.identity_replies())

        self.assertEqual(adapter.identity(TARGET, deadline=20), (TARGET, BUILD))
        self.assertEqual(
            [call[0] for call in runner.calls],
            [
                ("adb", "-s", TARGET, "get-state"),
                ("adb", "-s", TARGET, "shell", "getprop", "ro.build.fingerprint"),
            ],
        )
        self.assertTrue(all(call[1] == 20 for call in runner.calls))

    def test_identity_accepts_crlf_and_rejects_a_second_serial_binding(self):
        adapter, runner, _ = self.adapter(
            [b"device\r\n", (BUILD + "\r\n").encode("ascii"),
             b"device\n", (BUILD + "\n").encode("ascii")]
        )
        self.assertEqual(adapter.identity(TARGET, deadline=20), (TARGET, BUILD))
        with self.assertRaises(probe.ProbeError):
            adapter.identity("SECOND", deadline=20)
        self.assertEqual(len(runner.calls), 2)

    def test_identity_rejects_bad_serial_before_running_commands(self):
        adapter, runner, _ = self.adapter()

        for target in ("", " SERIAL", "serial;touch-file", "serial\n"):
            with self.subTest(target=target):
                with self.assertRaises(probe.ProbeError):
                    adapter.identity(target, deadline=20)
        self.assertEqual(runner.calls, [])

    def test_identity_requires_online_state_and_does_not_read_build_if_offline(self):
        adapter, runner, _ = self.adapter([b"offline\n"])

        with self.assertRaises(probe.ProbeError) as raised:
            adapter.identity(TARGET, deadline=20)
        self.assertEqual(raised.exception.code, "Disconnected")
        self.assertEqual(len(runner.calls), 1)

    def test_identity_rejects_empty_multiline_and_invalid_build_fingerprints(self):
        for fingerprint in (b"\n", b"one\ntwo\n", b"bad value\n", b"\xff\n"):
            with self.subTest(fingerprint=fingerprint):
                adapter, _, _ = self.adapter([b"device\n", fingerprint])
                with self.assertRaises(probe.ProbeError):
                    adapter.identity(TARGET, deadline=20)

    def test_identity_cannot_rebind_target_or_build(self):
        adapter, _, _ = self.adapter(self.identity_replies() + [b"device\n", b"other/build\n"])
        adapter.identity(TARGET, deadline=20)

        with self.assertRaises(probe.ProbeError) as raised:
            adapter.identity(TARGET, deadline=20)
        self.assertEqual(raised.exception.code, "IntegrityConflict")

    def test_lookup_filters_other_targets_and_requires_exact_forward_rows(self):
        rows = (
            "OTHER tcp:12345 localabstract:other\n"
            f"{TARGET} {LOCAL} {REMOTE}\n"
        ).encode("ascii")
        adapter, runner, _ = self.adapter(self.identity_replies(rows))
        adapter.identity(TARGET, deadline=20)

        self.assertEqual(adapter.lookup(TARGET, LOCAL, deadline=20), REMOTE)
        self.assertEqual(runner.calls[-1][0], ("adb", "-s", TARGET, "forward", "--list"))

    def test_lookup_reports_absence_without_adopting_an_unowned_forward(self):
        adapter, _, _ = self.adapter(self.identity_replies(b""))
        adapter.identity(TARGET, deadline=20)

        self.assertIsNone(adapter.lookup(TARGET, LOCAL, deadline=20))
        with self.assertRaises(probe.ProbeError):
            adapter.open_transport(object(), deadline=20)

    def test_changed_owned_forward_cannot_be_readopted_for_cleanup(self):
        row = f"{TARGET} {LOCAL} {REMOTE}\n".encode("ascii")
        changed = f"{TARGET} {LOCAL} tcp:12346\n".encode("ascii")
        for changed_readback in (b"", changed):
            with self.subTest(changed_readback=changed_readback):
                adapter, runner, _ = self.adapter(
                    self.identity_replies(b"", b"", row, changed_readback, row)
                )
                adapter.identity(TARGET, deadline=20)
                self.assertIsNone(adapter.lookup(TARGET, LOCAL, deadline=20))
                adapter.create_no_rebind(TARGET, LOCAL, REMOTE, deadline=20)
                self.assertEqual(adapter.lookup(TARGET, LOCAL, deadline=20), REMOTE)

                self.assertEqual(
                    adapter.lookup(TARGET, LOCAL, deadline=20),
                    changed_readback.decode("ascii").split()[2]
                    if changed_readback
                    else None,
                )
                self.assertEqual(adapter.lookup(TARGET, LOCAL, deadline=20), REMOTE)
                with self.assertRaises(probe.ProbeError):
                    adapter.remove(TARGET, LOCAL, deadline=20)
                self.assertFalse(any("--remove" in call[0] for call in runner.calls))

    def test_lookup_rejects_ambiguous_or_malformed_output(self):
        cases = (
            f"{TARGET} {LOCAL} {REMOTE}\n{TARGET} {LOCAL} {REMOTE}\n".encode(),
            f"{TARGET}  {LOCAL} {REMOTE}\n".encode(),
            b"not a forward row\n",
            b"\xff\n",
            b"SERIAL-2 tcp:12 localabstract:ok\nextra\trow\n",
            b"SERIAL? tcp:12 localabstract:ok\n",
            b"SERIAL-2 invalid localabstract:ok\n",
            b"SERIAL-2 tcp:12 invalid\n",
            b"OTHER tcp:1 localabstract:other\v" + f"{TARGET} {LOCAL} {REMOTE}\n".encode("ascii"),
            b"OTHER tcp:1 localabstract:other\f" + f"{TARGET} {LOCAL} {REMOTE}\n".encode("ascii"),
        )
        for output in cases:
            with self.subTest(output=output):
                adapter, _, _ = self.adapter(self.identity_replies(output))
                adapter.identity(TARGET, deadline=20)
                with self.assertRaises(probe.ProbeError):
                    adapter.lookup(TARGET, LOCAL, deadline=20)

        with self.assertRaises(probe.ProbeError) as raised:
            AdbForwardAdapter._parse_forward_list(
                b"x" * (_MAX_COMMAND_OUTPUT_BYTES + 1), TARGET, LOCAL
            )
        self.assertEqual(raised.exception.code, "ResourceLimitExceeded")

    def test_lookup_skips_blank_lines_but_rejects_an_oversized_row(self):
        row = f"{TARGET} {LOCAL} {REMOTE}\r\n".encode("ascii")
        adapter, _, _ = self.adapter(self.identity_replies(b"\r\n" + row))
        adapter.identity(TARGET, deadline=20)
        self.assertEqual(adapter.lookup(TARGET, LOCAL, deadline=20), REMOTE)

        too_long = b"SERIAL-2 " + b"x" * 1024 + b" localabstract:other\n"
        adapter, _, _ = self.adapter(self.identity_replies(too_long))
        adapter.identity(TARGET, deadline=20)
        with self.assertRaises(probe.ProbeError) as raised:
            adapter.lookup(TARGET, LOCAL, deadline=20)
        self.assertEqual(raised.exception.code, "ResourceLimitExceeded")

    def test_lookup_rejects_truncated_host_output(self):
        adapter, _, _ = self.adapter(
            self.identity_replies(b"x" * (_MAX_COMMAND_OUTPUT_BYTES + 1))
        )
        adapter.identity(TARGET, deadline=20)

        with self.assertRaises(probe.ProbeError) as raised:
            adapter.lookup(TARGET, LOCAL, deadline=20)
        self.assertEqual(raised.exception.code, "ResourceLimitExceeded")

    def test_lookup_requires_the_bound_target_and_valid_local_port(self):
        adapter, runner, _ = self.adapter(self.identity_replies())
        adapter.identity(TARGET, deadline=20)

        for target, local in (
            ("OTHER", LOCAL), (TARGET, 123), (TARGET, "tcp:0"),
            (TARGET, "tcp:70000"),
        ):
            with self.subTest(target=target, local=local):
                with self.assertRaises(probe.ProbeError):
                    adapter.lookup(target, local, deadline=20)
        self.assertEqual(len(runner.calls), 2)

    def test_create_records_pending_before_one_fixed_no_rebind_command(self):
        adapter, runner, _ = self.adapter(self.identity_replies(b"", b""))
        adapter.identity(TARGET, deadline=20)
        adapter.lookup(TARGET, LOCAL, deadline=20)

        adapter.create_no_rebind(TARGET, LOCAL, REMOTE, deadline=20)

        self.assertEqual(
            runner.calls[-1][0],
            ("adb", "-s", TARGET, "forward", "--no-rebind", LOCAL, REMOTE),
        )
        with self.assertRaises(probe.ProbeError):
            adapter.create_no_rebind(TARGET, LOCAL, REMOTE, deadline=20)
        self.assertEqual(len(runner.calls), 4)

    def test_create_refuses_a_preexisting_mapping_without_running_no_rebind(self):
        existing = f"{TARGET} {LOCAL} {REMOTE}\n".encode("ascii")
        adapter, runner, _ = self.adapter(self.identity_replies(existing))
        adapter.identity(TARGET, deadline=20)
        self.assertEqual(adapter.lookup(TARGET, LOCAL, deadline=20), REMOTE)

        with self.assertRaises(probe.ProbeError):
            adapter.create_no_rebind(TARGET, LOCAL, REMOTE, deadline=20)
        self.assertFalse(any("--no-rebind" in call[0] for call in runner.calls))

    def test_create_rejects_invalid_remote_and_local_before_command(self):
        adapter, runner, _ = self.adapter(self.identity_replies(b""))
        adapter.identity(TARGET, deadline=20)
        adapter.lookup(TARGET, LOCAL, deadline=20)

        for local, remote in ((LOCAL, "tcp:1234"), (123, REMOTE)):
            with self.subTest(local=local, remote=remote):
                with self.assertRaises(probe.ProbeError):
                    adapter.create_no_rebind(TARGET, local, remote, deadline=20)
        self.assertEqual(len(runner.calls), 3)

    def test_create_rejects_invalid_remote_before_command(self):
        adapter, runner, _ = self.adapter(self.identity_replies(b""))
        adapter.identity(TARGET, deadline=20)
        adapter.lookup(TARGET, LOCAL, deadline=20)

        with self.assertRaises(probe.ProbeError):
            adapter.create_no_rebind(TARGET, LOCAL, "tcp:1234", deadline=20)
        self.assertEqual(len(runner.calls), 3)

    def test_uncertain_create_is_not_retried_after_command_timeout(self):
        adapter, runner, _ = self.adapter(self.identity_replies(b"", TimeoutError()))
        adapter.identity(TARGET, deadline=20)
        adapter.lookup(TARGET, LOCAL, deadline=20)

        with self.assertRaises(probe.ProbeError) as raised:
            adapter.create_no_rebind(TARGET, LOCAL, REMOTE, deadline=20)
        self.assertEqual(raised.exception.code, "TimedOut")
        with self.assertRaises(probe.ProbeError):
            adapter.create_no_rebind(TARGET, LOCAL, REMOTE, deadline=20)
        self.assertEqual(len(runner.calls), 4)
        self.assertEqual(runner.calls[-1][0][-3:], ("--no-rebind", LOCAL, REMOTE))

    def test_create_success_needs_exact_readback_before_transport_or_removal(self):
        adapter, runner, _ = self.adapter(self.identity_replies(b"", b"", b""))
        adapter.identity(TARGET, deadline=20)
        adapter.lookup(TARGET, LOCAL, deadline=20)
        adapter.create_no_rebind(TARGET, LOCAL, REMOTE, deadline=20)

        self.assertIsNone(adapter.lookup(TARGET, LOCAL, deadline=20))
        for action in (
            lambda: adapter.open_transport(object(), deadline=20),
            lambda: adapter.remove(TARGET, LOCAL, deadline=20),
        ):
            with self.assertRaises(probe.ProbeError):
                action()
        self.assertEqual(len(runner.calls), 5)

    def test_create_rejects_unexpected_command_output_and_never_later_adopts(self):
        row = f"{TARGET} {LOCAL} {REMOTE}\n".encode("ascii")
        adapter, runner, _ = self.adapter(self.identity_replies(b"", b"unexpected", row))
        adapter.identity(TARGET, deadline=20)
        adapter.lookup(TARGET, LOCAL, deadline=20)

        with self.assertRaises(probe.ProbeError) as raised:
            adapter.create_no_rebind(TARGET, LOCAL, REMOTE, deadline=20)
        self.assertEqual(raised.exception.code, "IncompleteEvidence")
        self.assertEqual(adapter.lookup(TARGET, LOCAL, deadline=20), REMOTE)
        with self.assertRaises(probe.ProbeError):
            adapter.open_transport(object(), deadline=20)
        with self.assertRaises(probe.ProbeError):
            adapter.remove(TARGET, LOCAL, deadline=20)
        self.assertEqual(len(runner.calls), 5)

    def test_mismatched_post_create_mapping_is_not_adopted_or_removed(self):
        other = b"SERIAL-1 tcp:12345 localabstract:replacement\n"
        row = f"{TARGET} {LOCAL} {REMOTE}\n".encode("ascii")
        adapter, runner, _ = self.adapter(self.identity_replies(b"", b"", other, row))
        adapter.identity(TARGET, deadline=20)
        adapter.lookup(TARGET, LOCAL, deadline=20)
        adapter.create_no_rebind(TARGET, LOCAL, REMOTE, deadline=20)

        self.assertEqual(adapter.lookup(TARGET, LOCAL, deadline=20), "localabstract:replacement")
        self.assertEqual(adapter.lookup(TARGET, LOCAL, deadline=20), REMOTE)
        with self.assertRaises(probe.ProbeError):
            adapter.open_transport(object(), deadline=20)
        with self.assertRaises(probe.ProbeError):
            adapter.remove(TARGET, LOCAL, deadline=20)
        self.assertFalse(any("--remove" in call[0] for call in runner.calls))

    def test_exact_post_create_readback_allows_only_loopback_transport(self):
        row = f"{TARGET} {LOCAL} {REMOTE}\n".encode("ascii")
        sock = FakeSocket()
        session, runner, _ = self.make_owned_session(sock)
        runner.replies.extend(self.identity_replies(row) + self.identity_replies(row))

        transport = session.open_discovery_transport()
        with self.assertRaises(probe.ProbeError):
            transport.write(b"frame", 15)
        transport.close(16)

        self.assertEqual(sock.connected_to, ("127.0.0.1", 12345))
        self.assertEqual(sock.writes, [])
        self.assertTrue(sock.closed)
        self.assertEqual(runner.calls[-1][0], ("adb", "-s", TARGET, "forward", "--list"))

    def test_open_transport_fails_closed_for_connect_timeout_and_socket_errors(self):
        timed_sock = FakeSocket()
        timed_sock.connect_error = socket.timeout("private timeout")
        session, runner, _ = self.make_owned_session(timed_sock)
        runner.replies.extend(self.identity_replies(
            f"{TARGET} {LOCAL} {REMOTE}\n".encode("ascii")
        ) * 2)
        with self.assertRaises(probe.ProbeError) as raised:
            session.open_discovery_transport()
        self.assertEqual(raised.exception.code, "TimedOut")
        self.assertTrue(timed_sock.closed)

        failed_sock = FakeSocket()
        failed_sock.connect_error = OSError("private connect address")
        session, runner, _ = self.make_owned_session(failed_sock)
        runner.replies.extend(self.identity_replies(
            f"{TARGET} {LOCAL} {REMOTE}\n".encode("ascii")
        ) * 2)
        with self.assertRaises(probe.ProbeError) as raised:
            session.open_discovery_transport()
        self.assertEqual(raised.exception.code, "Disconnected")
        self.assertNotIn("private", str(raised.exception))
        self.assertTrue(failed_sock.closed)

    def test_open_transport_reports_unresolved_close_after_late_connect(self):
        clock = FakeClock()
        sock = FakeSocket()
        session, runner, _ = self.make_owned_session(sock, clock=clock)
        runner.replies.extend(self.identity_replies(
            f"{TARGET} {LOCAL} {REMOTE}\n".encode("ascii")
        ) * 2)
        sock.connect = lambda _address: setattr(clock, "value", 15)
        sock.close_error = OSError("private close detail")

        with self.assertRaises(probe.ProbeError) as raised:
            session.open_discovery_transport()
        self.assertEqual(raised.exception.code, "IncompleteEvidence")
        self.assertEqual(raised.exception.request_failure_code, "TimedOut")
        self.assertEqual(raised.exception.cleanup_failure_code, "IncompleteEvidence")
        self.assertFalse(sock.closed)
        self.assertTrue(session._discovery_transport.opened)
        self.assertFalse(session._discovery_transport.closed)
        with self.assertRaises(probe.ProbeError):
            session.cleanup()
        self.assertFalse(any("--remove" in call[0] for call in runner.calls))

    def test_open_transport_classifies_late_socket_error_as_timeout(self):
        clock = FakeClock()
        sock = FakeSocket()
        session, runner, _ = self.make_owned_session(sock, clock=clock)
        runner.replies.extend(self.identity_replies(
            f"{TARGET} {LOCAL} {REMOTE}\n".encode("ascii")
        ) * 2)

        def fail_late(_address):
            clock.value = 15
            raise OSError("private late connect failure")

        sock.connect = fail_late
        with self.assertRaises(probe.ProbeError) as raised:
            session.open_discovery_transport()

        self.assertEqual(raised.exception.code, "TimedOut")
        self.assertTrue(sock.closed)
        self.assertNotIn("private", str(raised.exception))

    def test_open_transport_sanitizes_socket_factory_failure(self):
        session, runner, _ = self.make_owned_session(FakeSocket())
        runner.replies.extend(self.identity_replies(
            f"{TARGET} {LOCAL} {REMOTE}\n".encode("ascii")
        ) * 2)
        adapter = session.adb
        adapter._socket_factory = lambda *_args: (_ for _ in ()).throw(
            OSError("private socket path")
        )

        with self.assertRaises(probe.ProbeError) as raised:
            session.open_discovery_transport()
        self.assertEqual(raised.exception.code, "Disconnected")
        self.assertNotIn("private", str(raised.exception))

    def test_session_rejects_transport_before_arm_without_more_io(self):
        sock = FakeSocket()
        session, runner, _ = self.make_owned_session(sock, arm=False)
        calls_before = len(runner.calls)

        with self.assertRaises(probe.ProbeError):
            session.open_discovery_transport()
        with self.assertRaises(probe.ProbeError):
            session.adb.open_transport(session, deadline=15)

        self.assertEqual(len(runner.calls), calls_before)
        self.assertIsNone(sock.connected_to)

    def test_adapter_rejects_direct_transport_open_for_armed_session(self):
        sock = FakeSocket()
        session, runner, _ = self.make_owned_session(sock)
        calls_before = len(runner.calls)

        with self.assertRaises(probe.ProbeError):
            session.adb.open_transport(session, deadline=15)

        self.assertEqual(len(runner.calls), calls_before)
        self.assertIsNone(sock.connected_to)

    def test_session_rejects_transport_after_expiry_without_more_io(self):
        sock = FakeSocket()
        session, runner, clock = self.make_owned_session(sock)
        calls_before = len(runner.calls)
        clock.value = session.deadline

        with self.assertRaises(probe.ProbeError) as raised:
            session.open_discovery_transport()

        self.assertEqual(raised.exception.code, "TimedOut")
        self.assertEqual(len(runner.calls), calls_before)
        self.assertIsNone(sock.connected_to)

    def test_discovery_transport_rejects_at_and_after_admission_deadline(self):
        for expired_at in (15, 15.1):
            with self.subTest(expired_at=expired_at):
                sock = FakeSocket()
                session, runner, clock = self.make_owned_session(sock)
                calls_before = len(runner.calls)
                clock.value = expired_at

                with self.assertRaises(probe.ProbeError) as raised:
                    session.open_discovery_transport()

                self.assertEqual(raised.exception.code, "TimedOut")
                self.assertEqual(len(runner.calls), calls_before)
                self.assertFalse(session.discovery_transport_attempted)
                self.assertIsNone(sock.connected_to)

    def test_open_transport_rechecks_identity_and_exact_mapping(self):
        sock = FakeSocket()
        session, runner, _ = self.make_owned_session(sock)
        expected = f"{TARGET} {LOCAL} {REMOTE}\n".encode("ascii")
        replacement = f"{TARGET} {LOCAL} localabstract:replacement\n".encode("ascii")
        runner.replies.extend(
            self.identity_replies(expected) + self.identity_replies(replacement)
        )

        with self.assertRaises(probe.ProbeError):
            session.open_discovery_transport()

        self.assertIsNone(sock.connected_to)
        self.assertTrue(session.discovery_transport_attempted)
        self.assertFalse(session.discovery_transport_opened)
        self.assertFalse(any("--remove" in call[0] for call in runner.calls))

    def test_session_closes_transport_returned_after_phase_deadline(self):
        sock = FakeSocket()
        session, runner, clock = self.make_owned_session(sock)
        row = f"{TARGET} {LOCAL} {REMOTE}\n".encode("ascii")
        runner.replies.extend(self.identity_replies(row) + self.identity_replies(row))
        adapter = session.adb
        open_transport = adapter.open_transport

        def finish_late(open_session, authorization=None, *, deadline):
            transport = open_transport(
                open_session, authorization, deadline=deadline
            )
            clock.value = deadline
            return transport

        adapter.open_transport = finish_late
        calls_before = len(runner.calls)
        with self.assertRaises(probe.ProbeError) as raised:
            session.open_discovery_transport()

        self.assertEqual(raised.exception.code, "TimedOut")
        self.assertTrue(sock.closed)
        self.assertTrue(session.discovery_transport_attempted)
        self.assertFalse(session.discovery_transport_opened)
        self.assertTrue(session.discovery_transport_closed)
        self.assertEqual(len(runner.calls), calls_before + 6)
        with self.assertRaises(probe.ProbeError):
            session.open_discovery_transport()
        self.assertEqual(len(runner.calls), calls_before + 6)

    def test_session_preserves_failed_release_after_late_transport_return(self):
        sock = FakeSocket()
        sock.close_error = OSError("private late release failure")
        session, runner, clock = self.make_owned_session(sock)
        row = f"{TARGET} {LOCAL} {REMOTE}\n".encode("ascii")
        runner.replies.extend(self.identity_replies(row) + self.identity_replies(row))
        adapter = session.adb
        open_transport = adapter.open_transport

        def finish_late(open_session, authorization=None, *, deadline):
            transport = open_transport(
                open_session, authorization, deadline=deadline
            )
            clock.value = deadline
            return transport

        adapter.open_transport = finish_late
        with self.assertRaises(probe.ProbeError) as raised:
            session.open_discovery_transport()

        self.assertEqual(raised.exception.code, "IncompleteEvidence")
        self.assertEqual(raised.exception.request_failure_code, "TimedOut")
        self.assertEqual(raised.exception.cleanup_failure_code, "IncompleteEvidence")
        self.assertFalse(sock.closed)
        self.assertFalse(session.discovery_transport_opened)
        self.assertFalse(session.discovery_transport_closed)
        self.assertTrue(session._discovery_transport.opened)
        self.assertFalse(session._discovery_transport.closed)
        with self.assertRaises(probe.ProbeError):
            session.cleanup()
        self.assertFalse(any("--remove" in call[0] for call in runner.calls))

    def test_late_discovery_release_cannot_be_reauthorized(self):
        sock = FakeSocket()
        session, runner, clock = self.make_owned_session(sock)
        row = f"{TARGET} {LOCAL} {REMOTE}\n".encode("ascii")
        runner.replies.extend(self.identity_replies(row) + self.identity_replies(row))
        transport = session.open_discovery_transport()

        clock.value = session.armed + 6
        with self.assertRaises(probe.ProbeError) as raised:
            transport.close(session.armed + 60)

        self.assertEqual(raised.exception.code, "TimedOut")
        self.assertTrue(sock.closed)
        self.assertFalse(session.discovery_transport_closed)
        with self.assertRaises(probe.ProbeError):
            session.correlate(
                session_module.Discovery(
                    "a" * 32, "b" * 32, REMOTE, 1, 2000, 100, 5100
                ),
                10.1,
                10.2,
                0,
                True,
            )
        with self.assertRaises(probe.ProbeError):
            session.enforce(2000, True)

    def test_enforcing_phase_opens_one_distinct_readiness_transport(self):
        row = f"{TARGET} {LOCAL} {REMOTE}\n".encode("ascii")
        discovery_sock = FakeSocket()
        readiness_sock = FakeSocket([b"reply"])
        session, runner, clock = self.make_owned_session(discovery_sock)
        sockets = iter((discovery_sock, readiness_sock))
        session.adb._socket_factory = lambda *_args: next(sockets)

        runner.replies.extend(self.identity_replies(row) + self.identity_replies(row))
        discovery_transport = session.open_discovery_transport()
        discovery_transport.close(16)

        clock.value = 15
        runner.replies.extend(self.identity_replies(row))
        session.correlate(
            session_module.Discovery("a" * 32, "b" * 32, REMOTE, 1, 2000, 100, 5100),
            10.1,
            10.2,
            0,
            True,
        )
        runner.replies.extend(self.identity_replies(row))
        session.enforce(2000, True)

        calls_before_readiness = len(runner.calls)
        with self.assertRaises(probe.ProbeError):
            session.adb.open_transport(session, deadline=20)
        self.assertEqual(len(runner.calls), calls_before_readiness)

        runner.replies.extend(self.identity_replies(row) + self.identity_replies(row))
        readiness_transport = session.open_readiness_transport()
        readiness_transport.write(b"frame", 20)
        self.assertEqual(readiness_transport.read(16, 20), b"reply")
        readiness_transport.close(21)

        self.assertTrue(session.discovery_transport_opened)
        self.assertTrue(session.readiness_transport_opened)
        self.assertTrue(discovery_sock.closed)
        self.assertTrue(readiness_sock.closed)
        self.assertEqual(discovery_sock.writes, [])
        self.assertEqual(readiness_sock.writes, [b"frame"])
        calls_after_readiness = len(runner.calls)
        with self.assertRaises(probe.ProbeError):
            session.open_discovery_transport()
        with self.assertRaises(probe.ProbeError):
            session.open_readiness_transport()
        self.assertEqual(len(runner.calls), calls_after_readiness)

    def test_remove_requires_verified_tuple_and_same_phase_readback(self):
        row = f"{TARGET} {LOCAL} {REMOTE}\n".encode("ascii")
        adapter, runner, _ = self.adapter(self.identity_replies(b"", b"", row, row, b""))
        adapter.identity(TARGET, deadline=20)
        adapter.lookup(TARGET, LOCAL, deadline=19)
        adapter.create_no_rebind(TARGET, LOCAL, REMOTE, deadline=19)
        adapter.lookup(TARGET, LOCAL, deadline=19)

        with self.assertRaises(probe.ProbeError):
            adapter.remove(TARGET, LOCAL, deadline=20)
        adapter.lookup(TARGET, LOCAL, deadline=20)
        adapter.remove(TARGET, LOCAL, deadline=20)

        self.assertEqual(
            runner.calls[-1][0],
            ("adb", "-s", TARGET, "forward", "--remove", LOCAL),
        )
        self.assertFalse(any("--remove" in call[0] for call in runner.calls[:-1]))

    def test_remove_rejects_invalid_local_value(self):
        adapter, _, _ = self.adapter(self.identity_replies())
        adapter.identity(TARGET, deadline=20)
        with self.assertRaises(probe.ProbeError):
            adapter.remove(TARGET, 123, deadline=20)

    def test_remove_pending_readback_never_restores_ownership(self):
        row = f"{TARGET} {LOCAL} {REMOTE}\n".encode("ascii")
        adapter, runner, _ = self.adapter(
            self.identity_replies(b"", b"", row, b"", row, b"")
        )
        adapter.identity(TARGET, deadline=20)
        adapter.lookup(TARGET, LOCAL, deadline=20)
        adapter.create_no_rebind(TARGET, LOCAL, REMOTE, deadline=20)
        adapter.lookup(TARGET, LOCAL, deadline=20)
        adapter.remove(TARGET, LOCAL, deadline=20)

        self.assertEqual(adapter.lookup(TARGET, LOCAL, deadline=20), REMOTE)
        with self.assertRaises(probe.ProbeError):
            adapter.remove(TARGET, LOCAL, deadline=20)
        self.assertEqual(
            [call[0] for call in runner.calls if "--remove" in call[0]],
            [("adb", "-s", TARGET, "forward", "--remove", LOCAL)],
        )

    def test_uncertain_remove_is_not_retried_after_later_matching_listing(self):
        row = f"{TARGET} {LOCAL} {REMOTE}\n".encode("ascii")
        adapter, runner, _ = self.adapter(
            self.identity_replies(b"", b"", row, TimeoutError(), row)
        )
        adapter.identity(TARGET, deadline=20)
        adapter.lookup(TARGET, LOCAL, deadline=20)
        adapter.create_no_rebind(TARGET, LOCAL, REMOTE, deadline=20)
        adapter.lookup(TARGET, LOCAL, deadline=20)

        with self.assertRaises(probe.ProbeError) as raised:
            adapter.remove(TARGET, LOCAL, deadline=20)
        self.assertEqual(raised.exception.code, "TimedOut")
        self.assertEqual(adapter.lookup(TARGET, LOCAL, deadline=20), REMOTE)
        with self.assertRaises(probe.ProbeError):
            adapter.remove(TARGET, LOCAL, deadline=20)
        self.assertEqual(
            [call[0] for call in runner.calls if "--remove" in call[0]],
            [("adb", "-s", TARGET, "forward", "--remove", LOCAL)],
        )

    def test_runner_exception_is_sanitized_and_timeout_is_not_retried(self):
        adapter, runner, _ = self.adapter([OSError("secret stderr and path")])

        with self.assertRaises(probe.ProbeError) as raised:
            adapter.identity(TARGET, deadline=20)
        self.assertEqual(raised.exception.code, "Disconnected")
        self.assertNotIn("secret", str(raised.exception))
        self.assertEqual(len(runner.calls), 1)

    def test_adapter_rejects_late_runner_completion(self):
        class LateRunner(FakeRunner):
            def run(self, argv, deadline):
                self.calls.append((tuple(argv), deadline))
                clock.value = deadline
                return b"device\n"

        clock = FakeClock()
        runner = LateRunner()
        adapter = AdbForwardAdapter(runner=runner, clock=clock)

        with self.assertRaises(probe.ProbeError) as raised:
            adapter.identity(TARGET, deadline=20)
        self.assertEqual(raised.exception.code, "TimedOut")
        self.assertEqual(len(runner.calls), 1)

    def test_adapter_rejects_late_forward_readback(self):
        clock = FakeClock()

        class LateListing(FakeRunner):
            def run(self, argv, deadline):
                self.calls.append((tuple(argv), deadline))
                if argv[-2:] == ("forward", "--list"):
                    clock.value = deadline
                return self.replies.pop(0)

        runner = LateListing([b"device\n", (BUILD + "\n").encode(), b""])
        adapter = AdbForwardAdapter(runner=runner, clock=clock)
        adapter.identity(TARGET, deadline=20)

        with self.assertRaises(probe.ProbeError) as raised:
            adapter.lookup(TARGET, LOCAL, deadline=11)
        self.assertEqual(raised.exception.code, "TimedOut")
        self.assertEqual(len(runner.calls), 3)


class ForwardSessionAdapterTests(unittest.TestCase):
    def build_session(self, replies):
        clock = FakeClock(1.0)
        runner = FakeRunner(replies)
        adapter = AdbForwardAdapter(runner=runner, clock=clock)
        journal = []
        session = session_module.ForwardSession(
            adapter,
            TARGET,
            BUILD,
            "a" * 32,
            LOCAL,
            REMOTE,
            0,
            600,
            clock=clock,
            obligation=journal.append,
        )
        return session, runner, journal

    def test_session_records_creation_pending_before_adb_and_owned_after_readback(self):
        row = f"{TARGET} {LOCAL} {REMOTE}\n".encode("ascii")
        session, runner, journal = self.build_session(
            [b"device\n", (BUILD + "\n").encode(), b"", b"", row]
        )
        first_command_seen = []
        original_run = runner.run

        def verify_before_command(argv, deadline):
            first_command_seen.append(tuple(item["state"] for item in journal))
            return original_run(argv, deadline)

        runner.run = verify_before_command
        session.create()

        self.assertEqual(first_command_seen[0], ("creation-pending",))
        self.assertEqual([entry["state"] for entry in journal], ["creation-pending", "owned"])
        self.assertTrue(session.owned)

    def test_session_keeps_creation_obligation_when_success_readback_is_missing(self):
        session, runner, journal = self.build_session(
            [b"device\n", (BUILD + "\n").encode(), b"", b"", b""]
        )

        with self.assertRaises(probe.ProbeError):
            session.create()
        with self.assertRaises(probe.ProbeError):
            session.cleanup()

        self.assertEqual([entry["state"] for entry in journal], ["creation-pending"])
        self.assertFalse(session.owned)
        self.assertFalse(any("--remove" in call[0] for call in runner.calls))

    def test_session_does_not_remove_a_replaced_mapping_during_cleanup(self):
        row = f"{TARGET} {LOCAL} {REMOTE}\n".encode("ascii")
        replacement = f"{TARGET} {LOCAL} localabstract:replacement\n".encode("ascii")
        session, runner, journal = self.build_session(
            [
                b"device\n", (BUILD + "\n").encode(), b"", b"", row,
                b"device\n", (BUILD + "\n").encode(), replacement,
            ]
        )
        session.create()

        with self.assertRaises(probe.ProbeError):
            session.cleanup()

        self.assertEqual([entry["state"] for entry in journal], ["creation-pending", "owned"])
        self.assertFalse(any("--remove" in call[0] for call in runner.calls))
        self.assertTrue(session.owned)

    def test_session_cleanup_records_closed_only_after_verified_absence(self):
        row = f"{TARGET} {LOCAL} {REMOTE}\n".encode("ascii")
        session, runner, journal = self.build_session(
            [
                b"device\n", (BUILD + "\n").encode(), b"", b"", row,
                b"device\n", (BUILD + "\n").encode(), row, b"",
                b"device\n", (BUILD + "\n").encode(), b"",
            ]
        )
        session.create()
        session.cleanup()

        self.assertEqual(
            [entry["state"] for entry in journal],
            ["creation-pending", "owned", "cleanup-pending", "closed"],
        )
        self.assertFalse(session.owned)
        self.assertEqual(
            [call[0] for call in runner.calls if "--remove" in call[0]],
            [("adb", "-s", TARGET, "forward", "--remove", LOCAL)],
        )


class FakePipe:
    def __init__(self, fd):
        self.fd = fd
        self.closed = False
        self.close_error = None

    def fileno(self):
        return self.fd

    def close(self):
        if self.close_error is not None:
            raise self.close_error
        self.closed = True


class FakeSelector:
    def __init__(self, clock, *, expire=False):
        self.clock = clock
        self.expire = expire
        self.keys = {}
        self.closed = False
        self.close_error = None
        self.register_error = None
        self.empty_once = False
        self.select_error = None

    def register(self, fileobj, _events):
        if self.register_error is not None:
            raise self.register_error
        self.keys[fileobj.fileno()] = type("Key", (), {"fileobj": fileobj, "fd": fileobj.fileno()})()

    def unregister(self, fileobj):
        del self.keys[fileobj.fileno()]

    def get_map(self):
        return self.keys

    def select(self, timeout):
        if self.select_error is not None:
            raise self.select_error
        if self.empty_once:
            self.empty_once = False
            return []
        if self.expire:
            self.clock.value += timeout
            return []
        return [(key, 1) for key in self.keys.values()]

    def close(self):
        if self.close_error is not None:
            raise self.close_error
        self.closed = True


class FakeProcess:
    def __init__(self, *, returncode=0):
        self.pid = 1234
        self.stdout = FakePipe(10)
        self.stderr = FakePipe(11)
        self.returncode = returncode
        self.killed = False
        self.wait_timeouts = []
        self.wait_error = None
        self.poll_error = None
        self.kill_error = None
        self.kill_wait_counts = []

    def poll(self):
        if self.poll_error is not None:
            raise self.poll_error
        if not self.killed:
            return self.returncode
        return -9 if self.returncode is None else self.returncode

    def wait(self, timeout=None):
        self.wait_timeouts.append(timeout)
        if self.wait_error is not None and not self.killed:
            raise self.wait_error
        if self.killed:
            return -9
        return self.returncode

    def kill(self):
        self.kill_wait_counts.append(len(self.wait_timeouts))
        if self.kill_error is not None:
            raise self.kill_error
        self.killed = True


class AdbCommandRunnerTests(unittest.TestCase):
    def test_process_group_listing_accepts_only_zombie_members(self):
        self.assertTrue(
            _process_group_listing_is_quiescent(
                b"1234 1234 Zs\n1235 1234 Z\n", 1234
            )
        )

    def test_process_group_listing_fails_closed_on_live_or_incomplete_output(self):
        for output in (
            b"1234 1234 Zs\n1235 1234 S\n",
            b"not a process row\n",
            b"x" * (_MAX_PROCESS_GROUP_OUTPUT_BYTES + 1),
        ):
            with self.subTest(output_length=len(output)):
                self.assertFalse(
                    _process_group_listing_is_quiescent(output, 1234)
                )

    def test_process_group_probe_bounds_output_and_uses_fixed_command(self):
        clock = FakeClock()
        process = FakeProcess(returncode=0)
        selector = FakeSelector(clock)
        chunks = [b"1234 1234 Zs\n", b""]
        reads = []
        calls = []

        def start_query(argv, **options):
            calls.append((tuple(argv), options))
            return process

        def read_output(fd, count):
            reads.append((fd, count))
            return chunks.pop(0)

        self.assertTrue(
            _host_process_group_is_quiescent(
                1234,
                timeout=0.25,
                popen=start_query,
                selector_factory=lambda: selector,
                reader=read_output,
                clock=clock,
            )
        )
        self.assertEqual(
            calls[0][0], ("/bin/ps", "-o", "pid=,pgid=,stat=", "-g", "1234")
        )
        self.assertEqual(calls[0][1]["stdin"], subprocess.DEVNULL)
        self.assertEqual(calls[0][1]["stdout"], subprocess.PIPE)
        self.assertEqual(calls[0][1]["stderr"], subprocess.DEVNULL)
        self.assertFalse(calls[0][1]["shell"])
        self.assertTrue(calls[0][1]["close_fds"])

        overflow_process = FakeProcess(returncode=None)
        overflow_selector = FakeSelector(clock)
        overflow_reads = []

        def read_overflow(_fd, count):
            overflow_reads.append(count)
            return b"x" * count

        self.assertFalse(
            _host_process_group_is_quiescent(
                1234,
                timeout=0.25,
                popen=lambda *_args, **_options: overflow_process,
                selector_factory=lambda: overflow_selector,
                reader=read_overflow,
                clock=clock,
            )
        )
        self.assertLessEqual(sum(overflow_reads), _MAX_PROCESS_GROUP_OUTPUT_BYTES + 1)
        self.assertTrue(overflow_process.killed)

    def test_process_group_probe_does_not_wait_after_its_deadline(self):
        clock = FakeClock()
        clock.value = 0
        process = FakeProcess(returncode=None)
        selector = FakeSelector(clock, expire=True)

        self.assertFalse(
            _host_process_group_is_quiescent(
                1234,
                timeout=0.25,
                popen=lambda *_args, **_options: process,
                selector_factory=lambda: selector,
                clock=clock,
            )
        )

        self.assertEqual(clock.value, 0.25)
        self.assertTrue(process.killed)
        self.assertEqual(process.wait_timeouts, [0.0])

    def build_runner(
        self, *, chunks, clock=None, expire=False, returncode=0,
        selector=None, process=None, reader=None, popen=None, kill_group=None,
        process_group_is_quiescent=None,
    ):
        clock = clock or FakeClock()
        process = process or FakeProcess(returncode=returncode)
        selector = selector or FakeSelector(clock, expire=expire)
        replies = {10: bytearray(chunks[0]), 11: bytearray(chunks[1])}

        def read_output(fd, count):
            pending = replies[fd]
            if not pending:
                return b""
            value = bytes(pending[:count])
            del pending[:count]
            return value

        popen_calls = []

        def start_process(argv, **options):
            popen_calls.append((tuple(argv), options))
            return process

        killed_groups = []
        group_signal_wait_counts = []

        def stop_group(pid, signum):
            killed_groups.append((pid, signum))
            group_signal_wait_counts.append(len(process.wait_timeouts))
            if kill_group is not None:
                kill_group(pid, signum)

        class WaitInfo:
            def __init__(self, pid):
                self.si_pid = pid

        def waitid(_idtype, pid, _options):
            if process.returncode is None and not process.killed:
                return None
            return WaitInfo(pid)

        def sleep_for(timeout):
            clock.value += timeout

        runner = _AdbCommandRunner(
            clock=clock,
            popen=popen or start_process,
            selector_factory=lambda: selector,
            reader=reader or read_output,
            kill_group=stop_group,
            process_group_is_quiescent=(
                process_group_is_quiescent
                if process_group_is_quiescent is not None
                else lambda _pid, **_kwargs: False
            ),
            waitid=waitid,
            sleep=sleep_for,
        )
        runner.test_killed_groups = killed_groups
        runner.test_group_signal_wait_counts = group_signal_wait_counts
        return runner, clock, process, selector, popen_calls

    def test_runner_bounds_and_drains_stdout_and_stderr_without_retaining_stderr(self):
        runner, _, _, selector, calls = self.build_runner(chunks=(b"device\n", b"private error"))

        result = runner.run(("adb", "-s", TARGET, "get-state"), deadline=20)

        self.assertEqual(result, b"device\n")
        self.assertFalse(calls[0][1]["shell"])
        self.assertEqual(calls[0][1]["stdin"], subprocess.DEVNULL)
        self.assertTrue(calls[0][1]["start_new_session"])
        self.assertEqual(runner.test_group_signal_wait_counts, [0])
        self.assertTrue(selector.closed)

    def test_runner_accepts_eperm_for_zombie_only_group_after_exit(self):
        def zombie_only_group(_pid, _signum):
            raise PermissionError("unreaped leader is not signalable")

        checked_groups = []

        def group_is_quiescent(pid, *, timeout):
            checked_groups.append((pid, timeout))
            return True

        runner, _, _, _, _ = self.build_runner(
            chunks=(b"device\n", b""),
            kill_group=zombie_only_group,
            process_group_is_quiescent=group_is_quiescent,
        )

        self.assertEqual(
            runner.run(("adb", "-s", TARGET, "get-state"), deadline=20),
            b"device\n",
        )
        self.assertEqual(runner.test_group_signal_wait_counts, [0])
        self.assertEqual(checked_groups, [(1234, 0.25)])

    def test_runner_rejects_eperm_when_group_still_has_live_members(self):
        def inaccessible_group(_pid, _signum):
            raise PermissionError("unconfirmed group")

        runner, _, _, _, _ = self.build_runner(
            chunks=(b"device\n", b""),
            kill_group=inaccessible_group,
            process_group_is_quiescent=lambda _pid, **_kwargs: False,
        )

        with self.assertRaises(probe.ProbeError) as raised:
            runner.run(("adb", "-s", TARGET, "get-state"), deadline=20)

        self.assertEqual(raised.exception.code, "IncompleteEvidence")

    def test_runner_kills_direct_child_before_wait_when_group_stop_is_unconfirmed(self):
        def inaccessible_group(_pid, _signum):
            raise PermissionError("private process group detail")

        clock = FakeClock()
        runner, _, process, _, _ = self.build_runner(
            chunks=(b"", b""),
            clock=clock,
            selector=FakeSelector(clock, expire=True),
            process=FakeProcess(returncode=None),
            kill_group=inaccessible_group,
            process_group_is_quiescent=lambda _pid, **_kwargs: False,
        )

        with self.assertRaises(probe.ProbeError) as raised:
            runner.run(("adb", "-s", TARGET, "get-state"), deadline=11)

        self.assertEqual(raised.exception.code, "IncompleteEvidence")
        self.assertEqual(process.kill_wait_counts, [0])
        self.assertEqual(len(process.wait_timeouts), 1)

    def test_runner_kills_direct_child_before_retrying_a_timed_out_wait(self):
        clock = FakeClock()
        selector = FakeSelector(clock)
        selector.select_error = OSError("private selector detail")
        process = FakeProcess(returncode=None)
        process.wait_error = subprocess.TimeoutExpired("adb", 1)
        runner, _, _, _, _ = self.build_runner(
            chunks=(b"", b""),
            clock=clock,
            selector=selector,
            process=process,
        )

        with self.assertRaises(probe.ProbeError):
            runner.run(("adb", "-s", TARGET, "get-state"), deadline=20)

        self.assertEqual(process.kill_wait_counts, [1])
        self.assertEqual(len(process.wait_timeouts), 2)

    def test_runner_kills_process_at_absolute_deadline(self):
        runner, clock, process, selector, _ = self.build_runner(
            chunks=(b"", b""), expire=True, returncode=None
        )

        with self.assertRaises(probe.ProbeError) as raised:
            runner.run(("adb", "-s", TARGET, "get-state"), deadline=11)

        self.assertEqual(raised.exception.code, "TimedOut")
        self.assertEqual(clock.value, 11)
        self.assertTrue(process.killed)
        self.assertEqual(len(runner.test_killed_groups), 1)
        self.assertTrue(selector.closed)

    def test_runner_bounds_cleanup_waits_to_remaining_deadline(self):
        clock = FakeClock()
        clock.value = 10.99
        runner, _, process, _, _ = self.build_runner(
            chunks=(b"", b""), clock=clock, expire=True, returncode=None
        )

        with self.assertRaises(probe.ProbeError) as raised:
            runner.run(("adb", "-s", TARGET, "get-state"), deadline=11)

        self.assertEqual(raised.exception.code, "TimedOut")
        self.assertEqual(clock.value, 11)
        self.assertTrue(process.killed)
        self.assertEqual(process.wait_timeouts, [0.0, 0.0])

    def test_runner_does_not_signal_group_again_after_reaping_at_deadline(self):
        clock = FakeClock()
        process = FakeProcess(returncode=0)

        def reap_at_deadline(*, timeout=None):
            process.wait_timeouts.append(timeout)
            clock.value = 20
            return 0

        process.wait = reap_at_deadline
        runner, _, _, _, _ = self.build_runner(
            chunks=(b"device\n", b""),
            clock=clock,
            selector=FakeSelector(clock),
            process=process,
        )

        with self.assertRaises(probe.ProbeError) as raised:
            runner.run(("adb", "-s", TARGET, "get-state"), deadline=20)

        self.assertEqual(raised.exception.code, "TimedOut")
        self.assertEqual(runner.test_group_signal_wait_counts, [0])
        self.assertEqual(len(process.wait_timeouts), 1)
        self.assertEqual(process.kill_wait_counts, [])

    def test_runner_kills_process_when_total_output_exceeds_bound(self):
        runner, _, process, _, _ = self.build_runner(
            chunks=(b"x" * (_MAX_COMMAND_OUTPUT_BYTES + 1), b""), returncode=None
        )

        with self.assertRaises(probe.ProbeError) as raised:
            runner.run(("adb", "-s", TARGET, "get-state"), deadline=20)

        self.assertEqual(raised.exception.code, "ResourceLimitExceeded")
        self.assertTrue(process.killed)
        self.assertEqual(len(runner.test_killed_groups), 1)

    def test_runner_stops_a_descendant_that_keeps_pipes_open_after_client_exit(self):
        clock = FakeClock()
        selector = FakeSelector(clock)
        selector.empty_once = True
        process = FakeProcess(returncode=0)
        runner, _, _, _, _ = self.build_runner(
            chunks=(b"", b""), clock=clock, selector=selector, process=process
        )

        with self.assertRaises(probe.ProbeError) as raised:
            runner.run(("adb", "-s", TARGET, "get-state"), deadline=20)

        self.assertEqual(raised.exception.code, "IncompleteEvidence")
        self.assertEqual(len(runner.test_killed_groups), 1)
        self.assertEqual(runner.test_killed_groups[0][0], process.pid)

    def test_runner_reports_unconfirmed_process_group_cleanup(self):
        clock = FakeClock()
        selector = FakeSelector(clock)
        selector.empty_once = True
        process = FakeProcess(returncode=0)

        def fail_group_kill(_pid, _signum):
            raise PermissionError("private process group detail")

        runner, _, _, _, _ = self.build_runner(
            chunks=(b"", b""),
            clock=clock,
            selector=selector,
            process=process,
            kill_group=fail_group_kill,
        )

        with self.assertRaises(probe.ProbeError) as raised:
            runner.run(("adb", "-s", TARGET, "get-state"), deadline=20)

        self.assertEqual(raised.exception.code, "IncompleteEvidence")
        self.assertTrue(process.killed)
        self.assertEqual(process.kill_wait_counts, [0])
        self.assertTrue(selector.closed)
        self.assertTrue(process.stdout.closed)
        self.assertTrue(process.stderr.closed)

    def test_runner_does_not_treat_missing_process_group_as_stopped(self):
        clock = FakeClock()
        selector = FakeSelector(clock)
        selector.select_error = OSError("private selector detail")
        process = FakeProcess(returncode=None)
        process.kill_error = PermissionError("private child cleanup detail")

        def missing_group(_pid, _signum):
            raise ProcessLookupError("private group detail")

        runner, _, _, _, _ = self.build_runner(
            chunks=(b"", b""),
            clock=clock,
            selector=selector,
            process=process,
            kill_group=missing_group,
        )

        with self.assertRaises(probe.ProbeError) as raised:
            runner.run(("adb", "-s", TARGET, "get-state"), deadline=20)

        self.assertEqual(raised.exception.code, "IncompleteEvidence")
        self.assertFalse(process.killed)
        self.assertTrue(selector.closed)
        self.assertTrue(process.stdout.closed)
        self.assertTrue(process.stderr.closed)

    def test_runner_does_not_spawn_after_deadline(self):
        runner, clock, process, _, calls = self.build_runner(chunks=(b"", b""))
        clock.value = 20

        with self.assertRaises(probe.ProbeError) as raised:
            runner.run(("adb", "-s", TARGET, "get-state"), deadline=20)

        self.assertEqual(raised.exception.code, "TimedOut")
        self.assertEqual(calls, [])
        self.assertFalse(process.killed)

    def test_runner_requires_nonreaping_exit_observation_before_spawn(self):
        runner, _, _, _, calls = self.build_runner(chunks=(b"", b""))
        runner._waitid = None

        with self.assertRaises(probe.ProbeError) as raised:
            runner.run(("adb", "-s", TARGET, "get-state"), deadline=20)

        self.assertEqual(raised.exception.code, "IncompleteEvidence")
        self.assertEqual(calls, [])

    def test_runner_rejects_nonzero_exit_without_returning_process_text(self):
        runner, _, _, _, _ = self.build_runner(
            chunks=(b"private output", b"private stderr"), returncode=1
        )

        with self.assertRaises(probe.ProbeError) as raised:
            runner.run(("adb", "-s", TARGET, "get-state"), deadline=20)

        self.assertEqual(raised.exception.code, "IncompleteEvidence")
        self.assertNotIn("private", str(raised.exception))

    def test_runner_reports_spawn_failure_without_exposing_host_error(self):
        def fail_to_start(*_args, **_options):
            raise OSError("private executable path")

        runner, _, _, _, _ = self.build_runner(
            chunks=(b"", b""), popen=fail_to_start
        )
        with self.assertRaises(probe.ProbeError) as raised:
            runner.run(("adb", "-s", TARGET, "get-state"), deadline=20)
        self.assertEqual(raised.exception.code, "Disconnected")
        self.assertNotIn("private", str(raised.exception))

    def test_runner_normalizes_bad_reader_and_selector_failures(self):
        runner, _, process, _, _ = self.build_runner(
            chunks=(b"", b""), reader=lambda _fd, _count: "not bytes"
        )
        with self.assertRaises(probe.ProbeError) as raised:
            runner.run(("adb", "-s", TARGET, "get-state"), deadline=20)
        self.assertEqual(raised.exception.code, "IncompleteEvidence")

        selector = FakeSelector(FakeClock())
        selector.register_error = RuntimeError("private selector detail")
        process = FakeProcess(returncode=None)
        runner, _, _, _, _ = self.build_runner(
            chunks=(b"", b""), selector=selector, process=process
        )
        with self.assertRaises(probe.ProbeError) as raised:
            runner.run(("adb", "-s", TARGET, "get-state"), deadline=20)
        self.assertEqual(raised.exception.code, "IncompleteEvidence")
        self.assertNotIn("private", str(raised.exception))
        self.assertTrue(process.killed)

    def test_runner_times_out_while_waiting_for_process_exit_and_closes_resources(self):
        process = FakeProcess(returncode=None)
        process.wait_error = subprocess.TimeoutExpired("adb", 1)
        selector = FakeSelector(FakeClock())
        selector.close_error = RuntimeError("private selector close")
        runner, _, _, _, _ = self.build_runner(
            chunks=(b"", b""), process=process, selector=selector
        )
        process.stdout.close_error = OSError("private stdout close")

        with self.assertRaises(probe.ProbeError) as raised:
            runner.run(("adb", "-s", TARGET, "get-state"), deadline=20)
        self.assertEqual(raised.exception.code, "TimedOut")
        self.assertTrue(process.killed)
        self.assertTrue(process.stderr.closed)

    def test_runner_validates_every_supported_fixed_vector(self):
        vectors = (
            ("adb", "-s", TARGET, "get-state"),
            ("adb", "-s", TARGET, "shell", "getprop", "ro.build.fingerprint"),
            ("adb", "-s", TARGET, "forward", "--list"),
            ("adb", "-s", TARGET, "forward", "--no-rebind", LOCAL, REMOTE),
            ("adb", "-s", TARGET, "forward", "--remove", LOCAL),
        )
        self.assertTrue(all(_AdbCommandRunner._allowed_vector(vector) for vector in vectors))
        for vector in (
            ["adb", "-s", TARGET, "get-state"],
            ("adb", "-s", "bad target", "get-state"),
            ("adb", "-s", TARGET),
            ("adb", "-s", TARGET, "forward", "--remove", "tcp:0"),
        ):
            with self.subTest(vector=vector):
                self.assertFalse(_AdbCommandRunner._allowed_vector(vector))

    def test_runner_accepts_only_fixed_adb_command_shapes(self):
        runner, _, _, _, calls = self.build_runner(chunks=(b"", b""))

        with self.assertRaises(probe.ProbeError):
            runner.run(("adb", "-s", TARGET, "shell", "id"), deadline=20)
        self.assertEqual(calls, [])


class ForwardedSocketTransportTests(unittest.TestCase):
    def test_write_and_read_set_remaining_timeout_and_close(self):
        clock = FakeClock(10)
        sock = FakeSocket([b"partial"])
        transport = ForwardedSocketTransport(sock, clock=clock)

        transport.write(b"frame", 15)
        self.assertEqual(transport.read(20, 14), b"partial")
        transport.close(13)

        self.assertEqual(sock.timeouts, [5, 4])
        self.assertEqual(sock.writes, [b"frame"])
        self.assertTrue(sock.closed)
        transport.close(13)
        with self.assertRaises(probe.ProbeError) as raised:
            transport.read(1, 13)
        self.assertEqual(raised.exception.code, "Disconnected")

    def test_transport_rejects_expired_and_oversized_io(self):
        clock = FakeClock(10)
        sock = FakeSocket()
        transport = ForwardedSocketTransport(sock, clock=clock)

        with self.assertRaises(probe.ProbeError):
            transport.write(b"", 20)
        with self.assertRaises(probe.ProbeError):
            transport.read(0, 20)
        with self.assertRaises(probe.ProbeError):
            transport.write(b"x" * 279, 20)
        with self.assertRaises(probe.ProbeError):
            transport.read(398, 20)
        with self.assertRaises(probe.ProbeError) as raised:
            transport.write(b"frame", 10)
        self.assertEqual(raised.exception.code, "TimedOut")
        self.assertEqual(sock.writes, [])

    def test_socket_timeouts_become_timeout_errors_without_raw_os_text(self):
        sock = FakeSocket()
        transport = ForwardedSocketTransport(sock, clock=FakeClock())
        sock.write_error = socket.timeout("private socket detail")
        with self.assertRaises(TimeoutError) as raised:
            transport.write(b"frame", 20)
        self.assertNotIn("private", str(raised.exception))

        sock.write_error = None
        sock.read_error = socket.timeout("private socket detail")
        with self.assertRaises(TimeoutError) as raised:
            transport.read(1, 20)
        self.assertNotIn("private", str(raised.exception))

    def test_socket_failure_is_sanitized_and_close_deadline_is_enforced(self):
        sock = FakeSocket()
        transport = ForwardedSocketTransport(sock, clock=FakeClock())
        sock.write_error = OSError("private address")
        with self.assertRaises(ConnectionError) as raised:
            transport.write(b"frame", 20)
        self.assertNotIn("private", str(raised.exception))
        sock.write_error = None
        sock.read_error = OSError("private read address")
        with self.assertRaises(ConnectionError) as raised:
            transport.read(1, 20)
        self.assertNotIn("private", str(raised.exception))

        malformed_sock = FakeSocket()
        malformed_sock.raw_read_result = "not bytes"
        malformed_transport = ForwardedSocketTransport(malformed_sock, clock=FakeClock())
        with self.assertRaises(probe.ProbeError) as raised:
            malformed_transport.read(10, 20)
        self.assertEqual(raised.exception.code, "IntegrityConflict")

        broken_close = FakeSocket()
        broken_close.close_error = OSError("private close detail")
        with self.assertRaises(probe.ProbeError) as raised:
            ForwardedSocketTransport(broken_close, clock=FakeClock()).close(20)
        self.assertEqual(raised.exception.code, "IncompleteEvidence")

        late_clock = FakeClock(10)
        late_sock = FakeSocket()
        late_transport = ForwardedSocketTransport(late_sock, clock=late_clock)
        late_sock.close = lambda: setattr(late_clock, "value", 11)
        with self.assertRaises(probe.ProbeError) as raised:
            late_transport.close(11)
        self.assertEqual(raised.exception.code, "TimedOut")


if __name__ == "__main__":
    unittest.main()
