"""Host-only tests for the bounded ADB forward and loopback adapters."""

import hashlib
import json
import os
import pathlib
import socket
import subprocess
import tempfile
import time
import unittest
from unittest import mock

from .test_readiness_probe_install_journal import complete_session_dump

from . import readiness_probe as probe
from . import readiness_probe_artifact
from . import readiness_probe_install_journal
from . import adb_forward
from . import packaging
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
        self.stdin_summaries = []
        self.last_install_payload = b""
        self.session_id = None
        self.session_user_id = None
        self.session_committed = False
        self.session_dump_replies = []
        self.outcomes_directory = None
        self.persisted_state_at_install = None
        self.pre_create_binding = {
            ("get-state",): b"device\n",
            ("shell", "getprop", "ro.build.fingerprint"): (BUILD + "\n").encode("ascii"),
            ("shell", "am", "get-current-user"): b"10\n",
        }
        self.last_package_state = b""

    def run_install_sessions(self, target, stdout_consumer, *, deadline):
        output = self.run(("adb", "-s", target, *adb_forward._INSTALL_SESSIONS_COMMAND), deadline)
        output = complete_session_dump(output)
        stdout_consumer(output)
        return adb_forward.Q7CommandResult(
            command_count=1, started_monotonic=0.0, finished_monotonic=0.0,
            stdout_bytes=len(output), total_output_bytes=len(output), exit_code=0,
            classification="exit_zero", cleanup_complete=True, stderr_empty=True,
        )

    def run(self, argv, deadline, *, input_fd=None, input_size=None):
        self.calls.append((tuple(argv), deadline))
        if input_fd is not None:
            digest = hashlib.sha256()
            offset = 0
            payload = bytearray()
            while offset < input_size:
                chunk = os.pread(input_fd, min(65536, input_size - offset), offset)
                if not chunk:
                    raise AssertionError("short install input")
                digest.update(chunk)
                payload.extend(chunk)
                offset += len(chunk)
            self.stdin_summaries.append((input_size, digest.hexdigest()))
            self.last_install_payload = bytes(payload)
        command = tuple(argv[3:])
        if (
            command in self.pre_create_binding
            and self.outcomes_directory is not None
            and self.persisted_state_at_install is None
            and any(self.outcomes_directory.glob("readiness-install-attempt-*.json"))
        ):
            return self.pre_create_binding[command]
        if command == adb_forward._INSTALL_SESSIONS_COMMAND:
            if self.session_dump_replies:
                return self.session_dump_replies.pop(0)
            if self.session_id is None:
                return b"Active install sessions:\n"
            section = "Historical" if self.session_committed else "Active"
            final_status = 1 if self.session_committed else 0
            return (
                f"{section} install sessions:\n"
                f"  Session {self.session_id}:\n"
                f"    userId={self.session_user_id}\n"
                "    installerPackageName=com.android.shell\n"
                "    mInstallerUid=2000\n"
                f"    appPackageName={readiness_probe_artifact.PACKAGE}\n"
                f"    mCommitted={'true' if self.session_committed else 'false'}\n"
                f"    mFinalStatus={final_status}\n"
            ).encode("ascii")
        if command == ("shell", "pm", "list", "users"):
            return b"Users:\n  UserInfo{10:Owner:13} running\n"
        if command[:4] == ("shell", "pm", "list", "packages"):
            user_id = int(command[-2])
            if user_id != 10:
                return b""
            if self.replies:
                candidate = self.replies[0]
                if isinstance(candidate, BaseException):
                    self.replies.pop(0)
                    raise candidate
                if (
                    self.session_id is not None
                    and not self.session_committed
                    and candidate.startswith(b"package:")
                ):
                    return self.last_package_state
                if not (
                    candidate.startswith((
                        b"Success",
                        b"Failure",
                        b"Active install sessions:",
                        b"Historical install sessions:",
                        b"package:/data/app/",
                    ))
                    or (candidate and candidate == b"x" * 28)
                ):
                    self.last_package_state = self.replies.pop(0)
            return self.last_package_state
        if command[:3] == ("shell", "pm", "install-create"):
            if self.outcomes_directory is not None:
                records = [
                    json.loads(path.read_text())
                    for path in self.outcomes_directory.glob(
                        "readiness-install-attempt-*.json"
                    )
                ]
                records.sort(key=lambda record: record["event_sequence"])
                self.persisted_state_at_install = (
                    records[-1]["state"], records[-1]["phase"]
                ) if records else None
            if self.replies:
                queued = self.replies.pop(0)
                if queued not in (
                    b"Success\n",
                    b"Performing Push Install\nSuccess\n",
                ):
                    return queued
            self.session_id = 17
            self.session_user_id = int(command[6])
            self.session_committed = False
            return b"Success: created install session [17]\n"
        if command[:3] == ("shell", "pm", "install-write"):
            return f"Success: streamed {command[4]} bytes\n".encode("ascii")
        if command[:3] == ("shell", "pm", "install-commit"):
            self.session_committed = True
            return b"Success\n"
        if command[:3] == ("shell", "pm", "install-abandon"):
            self.session_committed = False
            return b"Success\n"
        if command == ("shell", "pm", "path", readiness_probe_artifact.PACKAGE):
            return b"package:/data/app/argus-readiness/base.apk\n"
        if command[:2] == ("exec-out", "cat"):
            return self.last_install_payload
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

    def install_probe(
        self,
        adapter,
        target,
        artifact_path,
        *,
        deadline,
        install_attempt_id="d" * 32,
    ):
        private_outcomes = tempfile.TemporaryDirectory()
        self.addCleanup(private_outcomes.cleanup)
        outcomes_directory = pathlib.Path(private_outcomes.name)
        self.install_outcomes_directories = getattr(
            self, "install_outcomes_directories", []
        )
        self.install_outcomes_directories.append(outcomes_directory)
        if isinstance(adapter._runner, FakeRunner):
            adapter._runner.outcomes_directory = outcomes_directory
        return adapter.install_readiness_probe(
            target,
            artifact_path,
            deadline=deadline,
            outcomes_directory=outcomes_directory,
            target_reference="i74-tgt-7f6cd8181514b822",
            install_attempt_id=install_attempt_id,
        )

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
            adapter.identity(TARGET, deadline=time.monotonic() + 20)
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

    def test_package_state_is_bound_and_retains_only_version_and_uid(self):
        package = readiness_probe_artifact.PACKAGE
        package_output = (
            f"package:{package} versionCode:1 uid:10123\n".encode("ascii")
        )
        adapter, runner, _ = self.adapter(
            self.identity_replies(b"10\n", package_output)
        )
        adapter.identity(TARGET, deadline=20)

        result = adapter.package_install_state(TARGET, package, deadline=20)
        self.assertEqual(result, {"state": "present", "version_code": 1, "uid": 10123})
        self.assertEqual(
            runner.calls[-1][0],
            (
                "adb", "-s", TARGET, "shell", "pm", "list", "packages",
                "--show-versioncode", "-U", "--user", "10", package,
            ),
        )

    def test_package_state_accepts_empty_and_discards_unrelated_filter_matches(self):
        adapter, runner, _ = self.adapter(self.identity_replies(b"10\n", b""))
        adapter.identity(TARGET, deadline=20)
        self.assertEqual(
            adapter.package_install_state(
                TARGET, packaging.QUALIFICATION_APPLICATION_ID, deadline=20
            ),
            {"state": "absent", "version_code": None, "uid": None},
        )

        matching_unrelated = (
            "package:example.com.prefix."
            + packaging.QUALIFICATION_APPLICATION_ID
            + ".suffix versionCode:9 uid:90009\n"
        ).encode("ascii")
        adapter, _, _ = self.adapter(
            self.identity_replies(b"10\n", matching_unrelated)
        )
        adapter.identity(TARGET, deadline=20)
        self.assertEqual(
            adapter.package_install_state(
                TARGET, packaging.QUALIFICATION_APPLICATION_ID, deadline=20
            ),
            {"state": "absent", "version_code": None, "uid": None},
        )

        with self.assertRaises(probe.ProbeError) as raised:
            adapter.package_install_state(
                TARGET, "com.unrelated.privateapp", deadline=20
            )
            self.assertEqual(raised.exception.code, "MalformedRequest")
        self.assertEqual(len(runner.calls), 4)

    def test_package_state_rejects_unbound_target_and_malformed_output(self):
        adapter, runner, _ = self.adapter()
        with self.assertRaises(probe.ProbeError) as raised:
            adapter.package_install_state(
                TARGET, readiness_probe_artifact.PACKAGE, deadline=20
            )
        self.assertEqual(raised.exception.code, "IntegrityConflict")
        self.assertEqual(runner.calls, [])

        adapter, runner, _ = self.adapter(
            self.identity_replies(
                b"10\n",
                f"package:{readiness_probe_artifact.PACKAGE} "
                "versionCode:bad uid:secret\n".encode("ascii")
            )
        )
        adapter.identity(TARGET, deadline=20)
        with self.assertRaises(probe.ProbeError) as raised:
            adapter.package_install_state(
                TARGET, readiness_probe_artifact.PACKAGE, deadline=20
            )
        self.assertEqual(raised.exception.code, "IncompleteEvidence")
        self.assertNotIn("private.package", str(raised.exception))
        self.assertNotIn("secret", str(raised.exception))
        self.assertEqual(len(runner.calls), 4)

    def test_package_state_does_not_turn_a_failed_query_into_absence(self):
        adapter, runner, _ = self.adapter(
            self.identity_replies(
                b"10\n", probe.ProbeError("Disconnected", "Transport")
            )
        )
        adapter.identity(TARGET, deadline=20)

        with self.assertRaises(probe.ProbeError) as raised:
            adapter.package_install_state(
                TARGET, readiness_probe_artifact.PACKAGE, deadline=20
            )

        self.assertEqual(raised.exception.code, "Disconnected")
        self.assertEqual(len(runner.calls), 4)
        self.assertIsNone(adapter._readiness_baseline_absent)

    def test_package_state_rejects_stderr_notice_without_recording_absence(self):
        adapter, runner, _ = self.adapter(
            self.identity_replies(
                b"10\n",
                adb_forward._PackageQueryObservationError("stderr_nonempty"),
            )
        )
        adapter.identity(TARGET, deadline=20)

        with self.assertRaises(probe.ProbeError) as raised:
            adapter.package_install_state(
                TARGET, readiness_probe_artifact.PACKAGE, deadline=20
            )

        self.assertEqual(raised.exception.code, "IncompleteEvidence")
        self.assertEqual(raised.exception.diagnostic_subtype, "stderr_nonempty")
        self.assertIsNone(adapter._readiness_baseline_absent)
        self.assertEqual(len(runner.calls), 4)

    def test_build_api_and_current_user_are_parsed_from_fixed_queries(self):
        adapter, runner, _ = self.adapter(self.identity_replies(b"36\n", b"10\n"))
        adapter.identity(TARGET, deadline=20)

        self.assertEqual(adapter.platform_api_level(TARGET, deadline=20), 36)
        self.assertEqual(adapter.current_android_user_id(TARGET, deadline=20), 10)
        self.assertEqual(
            [call[0][3:] for call in runner.calls[2:]],
            [
                ("shell", "getprop", "ro.build.version.sdk"),
                ("shell", "am", "get-current-user"),
            ],
        )

    def test_primary_abi_is_parsed_from_one_bound_fixed_query(self):
        adapter, runner, _ = self.adapter(self.identity_replies(b"arm64-v8a\n"))
        adapter.identity(TARGET, deadline=20)

        self.assertEqual(adapter.platform_primary_abi(TARGET, deadline=20), "arm64-v8a")
        self.assertEqual(
            runner.calls[-1][0],
            ("adb", "-s", TARGET, "shell", "getprop", "ro.product.cpu.abi"),
        )

    def test_primary_abi_rejects_empty_multiline_and_non_ascii_values(self):
        for value in (b"\n", b"arm64-v8a\narm\n", b"\xff\n"):
            with self.subTest(output_size=len(value)):
                adapter, runner, _ = self.adapter(self.identity_replies(value))
                adapter.identity(TARGET, deadline=20)
                with self.assertRaises(probe.ProbeError) as raised:
                    adapter.platform_primary_abi(TARGET, deadline=20)
                self.assertEqual(raised.exception.code, "IncompleteEvidence")
                self.assertNotIn("arm64-v8a", str(raised.exception))
                self.assertEqual(len(runner.calls), 3)

    def test_build_api_and_current_user_reject_malformed_values(self):
        for value, operation in (
            (b"34\nextra\n", "platform_api_level"),
            (b"user 0\n", "current_android_user_id"),
        ):
            with self.subTest(operation=operation):
                adapter, runner, _ = self.adapter(self.identity_replies(value))
                adapter.identity(TARGET, deadline=20)
                with self.assertRaises(probe.ProbeError) as raised:
                    getattr(adapter, operation)(TARGET, deadline=20)
                self.assertEqual(raised.exception.code, "IncompleteEvidence")
                self.assertNotIn(value.decode("ascii").strip(), str(raised.exception))
                self.assertEqual(len(runner.calls), 3)

    def test_current_android_user_cannot_change_after_baseline_binding(self):
        adapter, runner, _ = self.adapter(
            self.identity_replies(b"10\n", b"11\n")
        )
        adapter.identity(TARGET, deadline=20)
        self.assertEqual(adapter.current_android_user_id(TARGET, deadline=20), 10)

        with self.assertRaises(probe.ProbeError) as raised:
            adapter.current_android_user_id(TARGET, deadline=20)

        self.assertEqual(raised.exception.code, "IntegrityConflict")
        self.assertNotIn("11", str(raised.exception))
        self.assertEqual(len(runner.calls), 4)

    def test_launch_readiness_probe_requires_complete_exact_component_result(self):
        package = readiness_probe_artifact.PACKAGE
        output = (
            f"Starting: Intent {{ cmp={package}/.LauncherActivity }}\n"
            "Status: ok\n"
            "LaunchState: COLD\n"
            f"Activity: {package}/.LauncherActivity\n"
            "ThisTime: 139\n"
            "TotalTime: 142\n"
            "WaitTime: 149\n"
            "Complete\n"
        ).encode("ascii")
        adapter, runner, _ = self.adapter(self.identity_replies(b"10\n", output))
        adapter.identity(TARGET, deadline=20)

        self.assertEqual(
            adapter.launch_readiness_probe(TARGET, deadline=20),
            {
                "state": "launched",
                "component": f"{package}/.LauncherActivity",
                "launch_state": "COLD",
                "this_time_ms": 139,
                "total_time_ms": 142,
                "wait_time_ms": 149,
            },
        )
        self.assertEqual(
            runner.calls[-1][0],
            (
                "adb", "-s", TARGET, "shell", "am", "start", "--user",
                "10", "-W", "-n", f"{package}/.LauncherActivity",
            ),
        )

    def test_launch_readiness_probe_accepts_owner_control_redirect(self):
        package = readiness_probe_artifact.PACKAGE
        output = (
            f"Starting: Intent {{ cmp={package}/.LauncherActivity }}\n"
            "Status: ok\n"
            "LaunchState: COLD\n"
            f"Activity: {package}/.ProbeControlActivity\n"
            "ThisTime: 139\n"
            "TotalTime: 142\n"
            "WaitTime: 149\n"
            "Complete\n"
        ).encode("ascii")
        adapter, runner, _ = self.adapter(self.identity_replies(b"10\n", output))
        adapter.identity(TARGET, deadline=20)

        self.assertEqual(
            adapter.launch_readiness_probe(TARGET, deadline=20),
            {
                "state": "launched",
                "component": f"{package}/.ProbeControlActivity",
                "launch_state": "COLD",
                "this_time_ms": 139,
                "total_time_ms": 142,
                "wait_time_ms": 149,
            },
        )
        self.assertEqual(
            runner.calls[-1][0],
            (
                "adb", "-s", TARGET, "shell", "am", "start", "--user",
                "10", "-W", "-n", f"{package}/.LauncherActivity",
            ),
        )

    def test_launch_readiness_probe_rejects_incomplete_or_unexpected_output(self):
        package = readiness_probe_artifact.PACKAGE
        for output in (
            b"Starting: Intent { cmp=com.argusromtoolkit.argus.readinessprobe/.LauncherActivity }\nStatus: ok\nComplete\n",
            (
                f"Starting: Intent {{ cmp={package}/.LauncherActivity }}\n"
                "Status: ok\n"
                f"Activity: unrelated.app/.Home\n"
                "Complete\n"
            ).encode("ascii"),
            (
                f"Starting: Intent {{ cmp={package}/.LauncherActivity }}\n"
                "Status: timeout\nComplete\n"
            ).encode("ascii"),
            (
                f"Starting: Intent {{ cmp={package}/.LauncherActivity }}\n"
                "Status: ok\nActivity: x\nComplete\nprivate diagnostic\n"
            ).encode("ascii"),
        ):
            with self.subTest(output_size=len(output)):
                adapter, runner, _ = self.adapter(
                    self.identity_replies(b"10\n", output)
                )
                adapter.identity(TARGET, deadline=20)
                with self.assertRaises(probe.ProbeError) as raised:
                    adapter.launch_readiness_probe(TARGET, deadline=20)
                self.assertIn(raised.exception.code, {"TimedOut", "IncompleteEvidence"})
                self.assertNotIn("private diagnostic", str(raised.exception))
                self.assertEqual(len(runner.calls), 4)

    def test_package_process_state_retains_only_target_process_projection(self):
        package = readiness_probe_artifact.PACKAGE
        process_output = (
            "UID PID NAME\n"
            "1000 1 init\n"
            f"10123 321 {package}\n"
            f"10123 322 {package}:worker\n"
            f"2000 555 {package}.unrelated\n"
        ).encode("ascii")
        adapter, runner, _ = self.adapter(
            self.identity_replies(b"10\n", process_output)
        )
        adapter.identity(TARGET, deadline=20)

        result = adapter.package_process_state(
            TARGET, package, expected_uid=10123, deadline=20
        )

        self.assertEqual(
            result,
            {
                "state": "running",
                "process_count": 2,
                "uid_matches_package": True,
                "roles": ["main", "secondary"],
            },
        )
        self.assertEqual(
            runner.calls[-1][0],
            (
                "adb", "-s", TARGET, "shell", "ps", "-A", "-n", "-w",
                "-o", "UID,PID,NAME",
            ),
        )
        self.assertNotIn("init", repr(result))
        self.assertNotIn("10123", repr(result))
        self.assertNotIn("321", repr(result))

    def test_package_process_state_preserves_spaces_in_unrelated_name(self):
        package = readiness_probe_artifact.PACKAGE
        process_output = (
            "UID PID NAME\n"
            "1000 1 system service\n"
            f"10123 321 {package}\n"
        ).encode("ascii")
        adapter, _, _ = self.adapter(self.identity_replies(b"10\n", process_output))

        adapter.identity(TARGET, deadline=20)
        result = adapter.package_process_state(
            TARGET, package, expected_uid=10123, deadline=20
        )

        self.assertEqual(
            result,
            {
                "state": "running",
                "process_count": 1,
                "uid_matches_package": True,
                "roles": ["main"],
            },
        )

    def test_package_process_state_rejects_extra_tokens_on_target_name(self):
        package = readiness_probe_artifact.PACKAGE
        process_output = (
            "UID PID NAME\n"
            f"10123 321 {package} extra\n"
        ).encode("ascii")
        adapter, _, _ = self.adapter(self.identity_replies(b"10\n", process_output))

        adapter.identity(TARGET, deadline=20)
        with self.assertRaises(probe.ProbeError) as raised:
            adapter.package_process_state(
                TARGET, package, expected_uid=10123, deadline=20
            )

        self.assertEqual(raised.exception.code, "IncompleteEvidence")
        self.assertEqual(raised.exception.diagnostic_subtype, "target_name_not_exact")
        self.assertEqual(raised.exception.line_number, 2)
        self.assertEqual(raised.exception.token_count, 3)
        self.assertEqual(raised.exception.parser_state, "target_name")
        self.assertNotIn(package, str(raised.exception))

    def test_package_process_state_rejects_tab_suffix_on_target_name(self):
        package = readiness_probe_artifact.PACKAGE
        process_output = (
            "UID PID NAME\n"
            f"10123 321 {package}\textra\n"
        ).encode("ascii")
        adapter, _, _ = self.adapter(self.identity_replies(b"10\n", process_output))

        adapter.identity(TARGET, deadline=20)
        with self.assertRaises(probe.ProbeError) as raised:
            adapter.package_process_state(
                TARGET, package, expected_uid=10123, deadline=20
            )

        self.assertEqual(raised.exception.diagnostic_subtype, "target_name_not_exact")
        self.assertEqual(raised.exception.line_number, 2)
        self.assertEqual(raised.exception.token_count, 3)
        self.assertEqual(raised.exception.parser_state, "target_name")
        self.assertNotIn(package, str(raised.exception))

    def test_package_process_state_blocks_uid_mismatch_and_malformed_rows(self):
        package = readiness_probe_artifact.PACKAGE
        for output, expected_subtype, expected_code in (
            (b"", "empty_output", "IncompleteEvidence"),
            (
                b"UID PID NAME\n\xff\n",
                "non_ascii_output",
                "IncompleteEvidence",
            ),
            (
                ("UID PID NAME\n" + "x" * 1025 + "\n").encode("ascii"),
                "line_too_long",
                "IncompleteEvidence",
            ),
            (b"UID PID NAME\n\n", "empty_row", "IncompleteEvidence"),
            (
                f"UID PID NAME\n10124 321 {package}\n".encode("ascii"),
                "uid_mismatch",
                "IntegrityConflict",
            ),
            (
                f"UID PID NAME\nu0_a123 321 {package}\n".encode("ascii"),
                "uid_not_decimal",
                "IncompleteEvidence",
            ),
            (
                f"UID PID NAME\n10123 not-a-pid {package}\n".encode("ascii"),
                "pid_not_decimal",
                "IncompleteEvidence",
            ),
            (
                f"UID PID NAME\n99999999999 321 {package}\n".encode("ascii"),
                "numeric_value_out_of_range",
                "IncompleteEvidence",
            ),
            (
                f"UID PID NAME\n10123 321 {package}\n10123 321 {package}:worker\n".encode("ascii"),
                "duplicate_pid",
                "IncompleteEvidence",
            ),
            (
                f"UID PID NAME\n10123 321\n".encode("ascii"),
                "wrong_column_count",
                "IncompleteEvidence",
            ),
            (
                f"wrong header\n10123 321 {package}\n".encode("ascii"),
                "unexpected_header",
                "IncompleteEvidence",
            ),
        ):
            with self.subTest(output_size=len(output)):
                adapter, runner, _ = self.adapter(
                    self.identity_replies(b"10\n", output)
                )
                adapter.identity(TARGET, deadline=20)
                with self.assertRaises(probe.ProbeError) as raised:
                    adapter.package_process_state(
                        TARGET, package, expected_uid=10123, deadline=20
                    )
                self.assertIn(
                    raised.exception.code, {"IntegrityConflict", "IncompleteEvidence"}
                )
                self.assertEqual(raised.exception.diagnostic_subtype, expected_subtype)
                self.assertEqual(raised.exception.code, expected_code)
                self.assertNotIn(package, str(raised.exception))
                if expected_subtype == "wrong_column_count":
                    self.assertEqual(raised.exception.line_number, 2)
                    self.assertEqual(raised.exception.token_count, 2)
                    self.assertEqual(raised.exception.parser_state, "row_shape")
            self.assertEqual(len(runner.calls), 4)

    def test_package_process_state_discards_unrelated_uid_values_before_parsing(self):
        package = readiness_probe_artifact.PACKAGE
        process_output = (
            "UID PID NAME\n"
            "u0_a123 123 unrelated.application\n"
            "shell 1 init\n"
        ).encode("ascii")
        adapter, _, _ = self.adapter(
            self.identity_replies(b"10\n", process_output)
        )
        adapter.identity(TARGET, deadline=20)

        result = adapter.package_process_state(
            TARGET, package, expected_uid=10123, deadline=20
        )

        self.assertEqual(
            result,
            {
                "state": "absent",
                "process_count": 0,
                "uid_matches_package": False,
                "roles": [],
            },
        )
        self.assertNotIn("unrelated.application", repr(result))
        self.assertNotIn("u0_a123", repr(result))

    def test_package_process_state_bounds_rows_before_projection(self):
        package = readiness_probe_artifact.PACKAGE
        rows = [f"10123 {pid} {package}:worker\n" for pid in range(1, 1026)]
        output = ("UID PID NAME\n" + "".join(rows)).encode("ascii")
        adapter, runner, _ = self.adapter(
            self.identity_replies(b"10\n", output)
        )
        adapter.identity(TARGET, deadline=20)

        with self.assertRaises(probe.ProbeError) as raised:
            adapter.package_process_state(
                TARGET, package, expected_uid=10123, deadline=20
            )

        self.assertEqual(raised.exception.code, "ResourceLimitExceeded")
        self.assertEqual(raised.exception.diagnostic_subtype, "row_limit_exceeded")
        self.assertNotIn(package, str(raised.exception))
        self.assertEqual(len(runner.calls), 4)

    def test_new_package_commands_are_closed_allowlist_entries(self):
        package = readiness_probe_artifact.PACKAGE
        approved = (
            ("shell", "getprop", "ro.build.version.sdk"),
            ("shell", "am", "get-current-user"),
            (
                "shell", "am", "start", "--user", "10", "-W", "-n",
                f"{package}/.LauncherActivity",
            ),
            ("shell", "ps", "-A", "-n", "-w", "-o", "UID,PID,NAME"),
        )
        for command in approved:
            self.assertTrue(
                _AdbCommandRunner._allowed_vector(("adb", "-s", TARGET, *command))
            )
        self.assertFalse(
            _AdbCommandRunner._allowed_vector(
                (
                    "adb", "-s", TARGET, "shell", "am", "start", "--user",
                    "current", "-W", "-n", f"{package}/.LauncherActivity",
                )
            )
        )
        self.assertFalse(
            _AdbCommandRunner._allowed_vector(
                ("adb", "-s", TARGET, "shell", "am", "start", "-n", "other.app/.Home")
            )
        )
        self.assertFalse(
            _AdbCommandRunner._allowed_vector(
                ("adb", "-s", TARGET, "shell", "ps", "-A", "-o", "CMDLINE")
            )
        )
        self.assertTrue(
            _AdbCommandRunner._allowed_vector(
                (
                    "adb", "-s", TARGET, "shell", "pm", "uninstall", "--user",
                    "10", "--versionCode",
                    str(adb_forward._READINESS_PROBE_VERSION_CODE), package,
                )
            )
        )

    def test_uninstall_allowlist_rejects_unbound_forms(self):
        command = (
            "adb", "-s", TARGET, "shell", "pm", "uninstall", "--user", "10",
            "--versionCode", "1", readiness_probe_artifact.PACKAGE,
        )
        self.assertTrue(_AdbCommandRunner._allowed_vector(command))
        for rejected in (
            command[:7] + ("all",) + command[8:],
            command[:9] + ("2", command[-1]),
            command[:-1] + ("other.app",),
            command[:6] + ("-k",) + command[6:],
            command[:8] + command[-1:],
        ):
            self.assertFalse(_AdbCommandRunner._allowed_vector(rejected))

    def test_install_snapshot_rejects_expired_and_late_parser_result(self):
        adapter, runner, _ = self.adapter(self.identity_replies())
        adapter.identity(TARGET, deadline=20)
        adapter._clock = lambda: 1.0
        with mock.patch.object(runner, "run_install_sessions", wraps=runner.run_install_sessions) as call:
            with self.assertRaises(probe.ProbeError):
                adapter._install_session_snapshot(TARGET, 1.0)
            call.assert_not_called()

            parser = readiness_probe_install_journal.InstallSessionParser
            finish = parser.finish
            def finish_late(instance):
                result = finish(instance)
                adapter._clock = lambda: 2.0
                return result

            with mock.patch.object(parser, "finish", finish_late):
                with self.assertRaises(probe.ProbeError) as error:
                    adapter._install_session_snapshot(TARGET, 2.0)
            self.assertEqual(error.exception.code, "TimedOut")
            self.assertEqual(call.call_args.kwargs["deadline"], 2.0)

    def test_readiness_cleanup_refuses_failed_final_identity_read(self):
        package = readiness_probe_artifact.PACKAGE
        present = f"package:{package} versionCode:1 uid:10123\n".encode("ascii")
        adapter, runner, _ = self.adapter(
            self.identity_replies(
                b"10\n", b"", b"10\n", b"",
                b"Success\n", present, b"10\n", present,
                b"Success\n",
                b"",
            )
        )
        apk_bytes = b"reviewed readiness apk bytes"
        with tempfile.TemporaryDirectory() as directory:
            apk = pathlib.Path(directory) / "readiness.apk"
            apk.write_bytes(apk_bytes)
            adapter.identity(TARGET, deadline=20)
            adapter.package_install_state(TARGET, package, deadline=20)
            with mock.patch.object(
                adb_forward,
                "_READINESS_PROBE_APK_SHA256",
                hashlib.sha256(apk_bytes).hexdigest(),
                create=True,
            ):
                install_result = self.install_probe(adapter,
                    TARGET, apk, deadline=20
                )
                self.assertEqual(install_result["state"], "installed")
                self.assertRegex(
                    install_result["install_attempt_id"], r"^[0-9a-f]{32}$"
                )

        with mock.patch.object(
            adb_forward, "_READINESS_PROBE_APK_SHA256", hashlib.sha256(apk_bytes).hexdigest()
        ), mock.patch.object(adapter, "identity", side_effect=probe.ProbeError("IntegrityConflict")):
            with self.assertRaises(probe.ProbeError) as cleanup_error:
                adapter.uninstall_readiness_probe(TARGET, deadline=20)
        self.assertEqual(cleanup_error.exception.code, "IntegrityConflict")
        self.assertFalse(any(
            call[0][3:6] == ("shell", "pm", "uninstall")
            for call in runner.calls
        ))

    def test_recovery_blocks_present_pinned_readiness_install(self):
        package = readiness_probe_artifact.PACKAGE
        present = f"package:{package} versionCode:1 uid:10123\n".encode("ascii")
        adapter, runner, _ = self.adapter(
            self.identity_replies(
                b"10\n", present, b"Success\n", b"",
            )
        )
        install_record = {
            "schema": "argus-issue-74-b1-preparation-observation-v1",
            "identity_preflight_record_bound": True,
            "identity_match": True,
            "qualification_assertions_passed": False,
            "identity_private": {
                "serial": TARGET,
                "build_fingerprint": BUILD,
            },
            "artifact": {
                "package": package,
                "sha256": adb_forward._READINESS_PROBE_APK_SHA256,
                "version_code": 1,
            },
            "install_status": "installed",
            "package_baseline_absent": True,
            "android_user_private": 10,
            "package_uid_private": 10123,
        }

        adapter.identity(TARGET, deadline=20)
        self.assertTrue(callable(getattr(adapter, "recover_readiness_cleanup", None)))
        with self.assertRaises(probe.ProbeError) as caught:
            adapter.recover_readiness_cleanup(
                TARGET, install_record, deadline=20
            )

        self.assertEqual(caught.exception.code, "IntegrityConflict")
        self.assertEqual(len(runner.calls), 4)
        self.assertFalse(any(
            call[0][3:6] == ("shell", "pm", "uninstall")
            for call in runner.calls
        ))

    def test_recovery_blocks_present_v2_install_with_its_attempt_identity(self):
        package = readiness_probe_artifact.PACKAGE
        present = f"package:{package} versionCode:1 uid:10123\n".encode("ascii")
        adapter, runner, _ = self.adapter(
            self.identity_replies(b"10\n", present, b"Success\n", b"")
        )
        install_record = {
            "schema": "argus-issue-74-b1-preparation-observation-v2",
            "install_attempt_id": "a" * 32,
            "identity_preflight_record_bound": True,
            "identity_match": True,
            "qualification_assertions_passed": False,
            "identity_private": {"serial": TARGET, "build_fingerprint": BUILD},
            "artifact": {
                "package": package,
                "sha256": adb_forward._READINESS_PROBE_APK_SHA256,
                "version_code": 1,
            },
            "install_status": "installed",
            "package_baseline_absent": True,
            "android_user_private": 10,
            "package_uid_private": 10123,
        }

        adapter.identity(TARGET, deadline=20)
        with self.assertRaises(probe.ProbeError) as caught:
            adapter.recover_readiness_cleanup(
                TARGET, install_record, deadline=20
            )

        self.assertEqual(caught.exception.code, "IntegrityConflict")
        self.assertEqual(len(runner.calls), 4)
        self.assertFalse(any(
            call[0][3:6] == ("shell", "pm", "uninstall")
            for call in runner.calls
        ))

    def test_recovery_rejects_a_malformed_v2_install_attempt_identity(self):
        adapter, runner, _ = self.adapter(self.identity_replies(b"10\n"))
        install_record = {
            "schema": "argus-issue-74-b1-preparation-observation-v2",
            "install_attempt_id": "not-an-attempt-id",
            "identity_preflight_record_bound": True,
            "identity_match": True,
            "qualification_assertions_passed": False,
            "identity_private": {"serial": TARGET, "build_fingerprint": BUILD},
            "artifact": {
                "package": readiness_probe_artifact.PACKAGE,
                "sha256": adb_forward._READINESS_PROBE_APK_SHA256,
                "version_code": 1,
            },
            "install_status": "installed",
            "package_baseline_absent": True,
            "android_user_private": 10,
            "package_uid_private": 10123,
        }

        adapter.identity(TARGET, deadline=20)
        with self.assertRaises(probe.ProbeError):
            adapter.recover_readiness_cleanup(TARGET, install_record, deadline=20)

        self.assertEqual(len(runner.calls), 2)

    def test_recovery_rejects_mismatched_identity_before_package_operations(self):
        adapter, runner, _ = self.adapter(self.identity_replies(b"10\n"))
        install_record = {
            "schema": "argus-issue-74-b1-preparation-observation-v1",
            "identity_preflight_record_bound": True,
            "identity_match": True,
            "qualification_assertions_passed": False,
            "identity_private": {
                "serial": "SERIAL-OTHER",
                "build_fingerprint": BUILD,
            },
            "artifact": {
                "package": readiness_probe_artifact.PACKAGE,
                "sha256": adb_forward._READINESS_PROBE_APK_SHA256,
                "version_code": 1,
            },
            "install_status": "installed",
            "package_baseline_absent": True,
            "android_user_private": 10,
            "package_uid_private": 10123,
        }

        adapter.identity(TARGET, deadline=20)
        self.assertTrue(callable(getattr(adapter, "recover_readiness_cleanup", None)))
        with self.assertRaises(probe.ProbeError) as caught:
            adapter.recover_readiness_cleanup(
                TARGET, install_record, deadline=20
            )

        self.assertEqual(caught.exception.code, "IntegrityConflict")
        self.assertEqual(len(runner.calls), 2)

    def test_readiness_cleanup_stays_bound_if_the_active_user_changes(self):
        package = readiness_probe_artifact.PACKAGE
        present = f"package:{package} versionCode:1 uid:10123\n".encode("ascii")
        adapter, runner, _ = self.adapter(
            self.identity_replies(
                b"10\n", b"", b"10\n", b"",
                b"Success\n", present, b"11\n",
                b"11\n",
            )
        )
        apk_bytes = b"reviewed readiness apk bytes"
        with tempfile.TemporaryDirectory() as directory:
            apk = pathlib.Path(directory) / "readiness.apk"
            apk.write_bytes(apk_bytes)
            adapter.identity(TARGET, deadline=20)
            adapter.package_install_state(TARGET, package, deadline=20)
            with mock.patch.object(
                adb_forward,
                "_READINESS_PROBE_APK_SHA256",
                hashlib.sha256(apk_bytes).hexdigest(),
                create=True,
            ):
                self.install_probe(adapter, TARGET, apk, deadline=20)

        with self.assertRaises(probe.ProbeError) as raised:
            adapter.current_android_user_id(TARGET, deadline=20)
        self.assertEqual(raised.exception.code, "IntegrityConflict")
        with mock.patch.object(
            adb_forward,
            "_READINESS_PROBE_APK_SHA256",
            hashlib.sha256(apk_bytes).hexdigest(),
            create=True,
        ):
            with self.assertRaises(probe.ProbeError) as cleanup_error:
                adapter.uninstall_readiness_probe(TARGET, deadline=20)
        self.assertEqual(cleanup_error.exception.code, "IntegrityConflict")
        self.assertFalse(any(
            call[0][3:6] == ("shell", "pm", "uninstall")
            for call in runner.calls
        ))

    def test_readiness_cleanup_rejects_unexpected_package_version(self):
        package = readiness_probe_artifact.PACKAGE
        present = f"package:{package} versionCode:1 uid:10123\n".encode("ascii")
        other_version = f"package:{package} versionCode:2 uid:10123\n".encode(
            "ascii"
        )
        adapter, runner, _ = self.adapter(
            self.identity_replies(
                b"10\n", b"", b"10\n", b"", b"Success\n", present,
                b"10\n", other_version,
            )
        )
        apk_bytes = b"reviewed readiness apk bytes"
        with tempfile.TemporaryDirectory() as directory:
            apk = pathlib.Path(directory) / "readiness.apk"
            apk.write_bytes(apk_bytes)
            adapter.identity(TARGET, deadline=20)
            adapter.package_install_state(TARGET, package, deadline=20)
            with mock.patch.object(
                adb_forward,
                "_READINESS_PROBE_APK_SHA256",
                hashlib.sha256(apk_bytes).hexdigest(),
                create=True,
            ):
                self.install_probe(adapter, TARGET, apk, deadline=20)

        with mock.patch.object(
            adb_forward,
            "_READINESS_PROBE_APK_SHA256",
            hashlib.sha256(apk_bytes).hexdigest(),
            create=True,
        ):
            with self.assertRaises(probe.ProbeError) as raised:
                adapter.uninstall_readiness_probe(TARGET, deadline=20)

        self.assertEqual(raised.exception.code, "IntegrityConflict")
        self.assertGreater(len(runner.calls), 0)
        self.assertFalse(any(
            call[0][3:6] == ("shell", "pm", "uninstall")
            for call in runner.calls
        ))

    def test_readiness_cleanup_requires_the_uid_verified_after_install(self):
        package = readiness_probe_artifact.PACKAGE
        installed = f"package:{package} versionCode:1 uid:10123\n".encode("ascii")
        replacement = f"package:{package} versionCode:1 uid:10124\n".encode("ascii")
        adapter, runner, _ = self.adapter(
            self.identity_replies(
                b"10\n", b"", b"10\n", b"", b"Success\n",
                installed, b"10\n", replacement,
            )
        )
        apk_bytes = b"reviewed readiness apk bytes"
        with tempfile.TemporaryDirectory() as directory:
            apk = pathlib.Path(directory) / "readiness.apk"
            apk.write_bytes(apk_bytes)
            adapter.identity(TARGET, deadline=20)
            adapter.package_install_state(TARGET, package, deadline=20)
            with mock.patch.object(
                adb_forward,
                "_READINESS_PROBE_APK_SHA256",
                hashlib.sha256(apk_bytes).hexdigest(),
                create=True,
            ):
                self.install_probe(adapter, TARGET, apk, deadline=20)

        with mock.patch.object(
            adb_forward, "_READINESS_PROBE_APK_SHA256", hashlib.sha256(apk_bytes).hexdigest()
        ):
            with self.assertRaises(probe.ProbeError) as raised:
                adapter.uninstall_readiness_probe(TARGET, deadline=20)

        self.assertEqual(raised.exception.code, "IntegrityConflict")
        self.assertNotIn("uninstall", [call[0][3] for call in runner.calls])

    def test_readiness_cleanup_refuses_unverified_package_after_install_failure(self):
        package = readiness_probe_artifact.PACKAGE
        present = f"package:{package} versionCode:1 uid:10123\n".encode("ascii")
        adapter, runner, _ = self.adapter(
            self.identity_replies(
                b"10\n", b"", b"10\n", b"",
                b"Failure [INSTALL_FAILED_SECRET_VALUE]\n", b"10\n", present,
            )
        )
        apk_bytes = b"reviewed readiness apk bytes"
        with tempfile.TemporaryDirectory() as directory:
            apk = pathlib.Path(directory) / "readiness.apk"
            apk.write_bytes(apk_bytes)
            adapter.identity(TARGET, deadline=20)
            adapter.package_install_state(TARGET, package, deadline=20)
            with mock.patch.object(
                adb_forward,
                "_READINESS_PROBE_APK_SHA256",
                hashlib.sha256(apk_bytes).hexdigest(),
                create=True,
            ):
                with self.assertRaises(probe.ProbeError) as install_error:
                    self.install_probe(adapter, TARGET, apk, deadline=20)

        self.assertEqual(install_error.exception.code, "IncompleteEvidence")
        self.assertNotIn("INSTALL_FAILED_SECRET_VALUE", str(install_error.exception))
        with mock.patch.object(
            adb_forward, "_READINESS_PROBE_APK_SHA256", hashlib.sha256(apk_bytes).hexdigest()
        ):
            with self.assertRaises(probe.ProbeError) as cleanup_error:
                adapter.uninstall_readiness_probe(TARGET, deadline=20)

        self.assertEqual(cleanup_error.exception.code, "IntegrityConflict")
        self.assertNotIn("uninstall", [call[0][3] for call in runner.calls])

    def test_readiness_cleanup_requires_recorded_absence_and_install_attempt(self):
        adapter, runner, _ = self.adapter(self.identity_replies())
        adapter.identity(TARGET, deadline=20)

        with self.assertRaises(probe.ProbeError) as raised:
            adapter.uninstall_readiness_probe(TARGET, deadline=20)

        self.assertEqual(raised.exception.code, "IntegrityConflict")
        self.assertEqual(len(runner.calls), 2)

        adapter, runner, _ = self.adapter(self.identity_replies(b"10\n", b""))
        adapter.identity(TARGET, deadline=20)
        adapter.package_install_state(
            TARGET, readiness_probe_artifact.PACKAGE, deadline=20
        )
        with self.assertRaises(probe.ProbeError) as raised:
            adapter.uninstall_readiness_probe(TARGET, deadline=20)
        self.assertEqual(raised.exception.code, "IntegrityConflict")
        self.assertEqual(len(runner.calls), 4)

        package = readiness_probe_artifact.PACKAGE
        present = f"package:{package} versionCode:1 uid:10123\n".encode("ascii")
        adapter, runner, _ = self.adapter(self.identity_replies(b"10\n", present))
        adapter.identity(TARGET, deadline=20)
        adapter.package_install_state(TARGET, package, deadline=20)

        with self.assertRaises(probe.ProbeError) as raised:
            adapter.uninstall_readiness_probe(TARGET, deadline=20)

        self.assertEqual(raised.exception.code, "IntegrityConflict")
        self.assertEqual(len(runner.calls), 4)

    def test_readiness_cleanup_reports_already_absent_without_uninstall(self):
        package = readiness_probe_artifact.PACKAGE
        adapter, runner, _ = self.adapter(
            self.identity_replies(
                b"10\n", b"", b"10\n", b"", b"Failure\n", b"10\n", b""
            )
        )
        apk_bytes = b"reviewed readiness apk bytes"
        with tempfile.TemporaryDirectory() as directory:
            apk = pathlib.Path(directory) / "readiness.apk"
            apk.write_bytes(apk_bytes)
            adapter.identity(TARGET, deadline=20)
            adapter.package_install_state(TARGET, package, deadline=20)
            with mock.patch.object(
                adb_forward,
                "_READINESS_PROBE_APK_SHA256",
                hashlib.sha256(apk_bytes).hexdigest(),
                create=True,
            ):
                with self.assertRaises(probe.ProbeError):
                    self.install_probe(adapter, TARGET, apk, deadline=20)
                self.assertEqual(
                    adapter.uninstall_readiness_probe(TARGET, deadline=20),
                    {"state": "already_absent", "readback": "absent"},
                )
        self.assertEqual(len(runner.calls), 19)
        self.assertEqual(
            sum(
                call[0][3:] == ("shell", "pm", "list", "users")
                for call in runner.calls
            ),
            3,
        )

    def test_readiness_install_verifies_pinned_apk_and_never_replaces(self):
        apk_bytes = b"reviewed readiness apk bytes"
        digest = hashlib.sha256(apk_bytes).hexdigest()
        with tempfile.TemporaryDirectory() as directory:
            apk = pathlib.Path(directory) / "readiness.apk"
            apk.write_bytes(apk_bytes)
            adapter, runner, _ = self.adapter(
                self.identity_replies(
                    b"10\n", b"", b"10\n", b"",
                b"Success\n",
                    f"package:{readiness_probe_artifact.PACKAGE} versionCode:1 uid:10123\n".encode("ascii"),
                )
            )
            adapter.identity(TARGET, deadline=20)
            adapter.package_install_state(
                TARGET, readiness_probe_artifact.PACKAGE, deadline=20
            )

            with mock.patch.object(
                adb_forward,
                "_READINESS_PROBE_APK_SHA256",
                digest,
                create=True,
            ):
                install_attempt_id = "c" * 32
                result = self.install_probe(adapter,
                    TARGET,
                    apk,
                    deadline=time.monotonic() + 20,
                    install_attempt_id=install_attempt_id,
                )

        self.assertEqual(result["state"], "installed")
        self.assertEqual(result["install_attempt_id"], install_attempt_id)
        install_vectors = [
            call[0] for call in runner.calls
            if call[0][3:6] == ("shell", "pm", "install-create")
        ]
        self.assertEqual(len(install_vectors), 1)
        self.assertEqual(runner.persisted_state_at_install, ("attempted", "create_started"))
        install_events = readiness_probe_install_journal.read_install_journal_events(
            self.install_outcomes_directories[-1],
            target_reference="i74-tgt-7f6cd8181514b822",
        )[install_attempt_id]
        self.assertEqual(
            [(event["state"], event["phase"]) for event in install_events],
            [
                ("pending", "before_install"),
                ("attempted", "create_started"),
                ("attempted", "session_created"),
                ("attempted", "write_started"),
                ("attempted", "payload_written"),
                ("attempted", "commit_started"),
                ("completed", "installed"),
            ],
        )
        self.assertEqual(
            [call[0][5] for call in runner.calls if call[0][0:5] == (
                "adb", "-s", TARGET, "shell", "pm"
            ) and call[0][5:6] in (("install-create",), ("install-write",), ("install-commit",))],
            ["install-create", "install-write", "install-commit"],
        )
        self.assertFalse(any(call[0][3] == "install" for call in runner.calls))

    def test_readiness_install_requires_a_valid_attempt_id_before_install(self):
        adapter, runner, _ = self.adapter(
            self.identity_replies(b"10\n", b"")
        )
        adapter.identity(TARGET, deadline=20)
        adapter.package_install_state(
            TARGET, readiness_probe_artifact.PACKAGE, deadline=20
        )
        calls_before_install = tuple(runner.calls)

        with tempfile.TemporaryDirectory() as directory:
            for install_attempt_id in ("not-an-attempt-id",):
                with self.subTest(install_attempt_id=install_attempt_id):
                    with self.assertRaises(probe.ProbeError) as raised:
                        adapter.install_readiness_probe(
                            TARGET,
                            "/unused/readiness.apk",
                            deadline=20,
                            outcomes_directory=directory,
                            target_reference="i74-tgt-7f6cd8181514b822",
                            install_attempt_id=install_attempt_id,
                        )

                self.assertEqual(raised.exception.code, "MalformedRequest")
                self.assertEqual(tuple(runner.calls), calls_before_install)

    def test_readiness_install_uses_verified_copy_if_source_inode_is_modified(self):
        apk_bytes = b"reviewed readiness apk bytes"
        digest = hashlib.sha256(apk_bytes).hexdigest()
        with tempfile.TemporaryDirectory() as directory:
            apk = pathlib.Path(directory) / "readiness.apk"
            apk.write_bytes(apk_bytes)
            source_inode = apk.stat().st_ino

            class ReplacingRunner(FakeRunner):
                def __init__(self, replies):
                    super().__init__(replies)
                    self.installed_digest = None
                    self.installed_inode = None

                def run(self, argv, deadline, *, input_fd=None, input_size=None):
                    command = tuple(argv[3:])
                    if command[:3] == ("shell", "pm", "install-create"):
                        apk.write_bytes(b"modified after verification")
                    result = super().run(
                        argv, deadline, input_fd=input_fd, input_size=input_size
                    )
                    if command[:3] == ("shell", "pm", "install-write"):
                        self.installed_digest = hashlib.sha256(
                            self.last_install_payload
                        ).hexdigest()
                        self.installed_inode = os.fstat(input_fd).st_ino
                    return result

            runner = ReplacingRunner(
                self.identity_replies(
                    b"10\n",
                    b"",
                    b"10\n",
                    b"",
                    b"Success\n",
                    f"package:{readiness_probe_artifact.PACKAGE} versionCode:1 uid:10123\n".encode("ascii"),
                )
            )
            adapter = AdbForwardAdapter(runner=runner)
            adapter.identity(TARGET, deadline=time.monotonic() + 20)
            adapter.package_install_state(
                TARGET, readiness_probe_artifact.PACKAGE,
                deadline=time.monotonic() + 20,
            )
            with mock.patch.object(
                adb_forward,
                "_READINESS_PROBE_APK_SHA256",
                digest,
                create=True,
            ):
                result = self.install_probe(adapter,
                    TARGET, apk, deadline=time.monotonic() + 20
                )

        self.assertEqual(result["state"], "installed")
        self.assertRegex(result["install_attempt_id"], r"^[0-9a-f]{32}$")
        self.assertEqual(runner.installed_digest, digest)
        self.assertNotEqual(runner.installed_inode, source_inode)

    def test_readiness_install_rejects_wrong_artifact_hash_before_install(self):
        with tempfile.TemporaryDirectory() as directory:
            apk = pathlib.Path(directory) / "readiness.apk"
            apk.write_bytes(b"not the approved apk")
            adapter, runner, _ = self.adapter(
                self.identity_replies(b"10\n", b"", b"10\n")
            )
            adapter.identity(TARGET, deadline=20)
            adapter.package_install_state(
                TARGET, readiness_probe_artifact.PACKAGE, deadline=20
            )

            with mock.patch.object(
                adb_forward,
                "_READINESS_PROBE_APK_SHA256",
                "0" * 64,
                create=True,
            ):
                with self.assertRaises(probe.ProbeError) as raised:
                    self.install_probe(adapter,
                        TARGET, apk, deadline=20
                    )

        self.assertEqual(raised.exception.code, "IntegrityConflict")
        self.assertEqual(len(runner.calls), 5)

    def test_readiness_install_requires_bound_target_before_file_access(self):
        adapter, runner, _ = self.adapter()
        with self.assertRaises(probe.ProbeError) as raised:
            self.install_probe(adapter,
                TARGET, "/not-a-real-private-path.apk", deadline=20
            )

        self.assertEqual(raised.exception.code, "IntegrityConflict")
        self.assertEqual(runner.calls, [])

    def test_readiness_install_requires_absent_baseline_before_file_access(self):
        adapter, runner, _ = self.adapter(self.identity_replies())
        adapter.identity(TARGET, deadline=20)

        with self.assertRaises(probe.ProbeError) as raised:
            self.install_probe(adapter,
                TARGET, "/not-a-real-private-path.apk", deadline=20
            )

        self.assertEqual(raised.exception.code, "IntegrityConflict")
        self.assertEqual(len(runner.calls), 2)

    def test_readiness_install_rechecks_absence_before_installing(self):
        package = readiness_probe_artifact.PACKAGE
        present = f"package:{package} versionCode:1 uid:10123\n".encode("ascii")
        adapter, runner, _ = self.adapter(
            self.identity_replies(b"10\n", b"", b"10\n", present)
        )
        adapter.identity(TARGET, deadline=20)
        adapter.package_install_state(TARGET, package, deadline=20)

        with tempfile.TemporaryDirectory() as directory:
            apk = pathlib.Path(directory) / "readiness.apk"
            apk_bytes = b"reviewed readiness apk bytes"
            apk.write_bytes(apk_bytes)
            with mock.patch.object(
                adb_forward,
                "_READINESS_PROBE_APK_SHA256",
                hashlib.sha256(apk_bytes).hexdigest(),
                create=True,
            ):
                with self.assertRaises(probe.ProbeError) as raised:
                    self.install_probe(adapter, TARGET, apk, deadline=20)

        self.assertEqual(raised.exception.code, "IntegrityConflict")
        self.assertEqual(len(runner.calls), 6)

    def test_readiness_install_rejects_non_success_output_without_echoing_it(self):
        adapter, runner, _ = self.adapter(
            self.identity_replies(
                b"10\n", b"", b"10\n", b"",
                b"Failure [INSTALL_FAILED_SECRET_VALUE]\n",
            )
        )
        adapter.identity(TARGET, deadline=20)
        adapter.package_install_state(
            TARGET, readiness_probe_artifact.PACKAGE, deadline=20
        )
        with tempfile.TemporaryDirectory() as directory:
            apk = pathlib.Path(directory) / "readiness.apk"
            apk_bytes = b"reviewed readiness apk bytes"
            apk.write_bytes(apk_bytes)
            with mock.patch.object(
                adb_forward,
                "_READINESS_PROBE_APK_SHA256",
                hashlib.sha256(apk_bytes).hexdigest(),
                create=True,
            ):
                with self.assertRaises(probe.ProbeError) as raised:
                    self.install_probe(adapter,
                        TARGET, apk, deadline=20
                    )

        self.assertEqual(raised.exception.code, "IncompleteEvidence")
        self.assertNotIn("INSTALL_FAILED_SECRET_VALUE", str(raised.exception))
        self.assertEqual(len(runner.calls), 15)
        self.assertEqual(
            sum(
                call[0][3:] == ("shell", "pm", "list", "users")
                for call in runner.calls
            ),
            2,
        )

    def test_readiness_install_refuses_binding_changes_before_create(self):
        for command, output in (
            (("shell", "getprop", "ro.build.fingerprint"),
             b"other/device:version/id/incremental:user/release-keys\n"),
            (("shell", "am", "get-current-user"), b"11\n"),
        ):
            with self.subTest(command=command), tempfile.TemporaryDirectory() as directory:
                adapter, runner, _ = self.adapter(self.identity_replies(b"10\n", b"", b"10\n", b""))
                runner.pre_create_binding[command] = output
                adapter.identity(TARGET, deadline=20)
                adapter.package_install_state(TARGET, readiness_probe_artifact.PACKAGE, deadline=20)
                apk = pathlib.Path(directory) / "readiness.apk"
                payload = b"reviewed readiness apk bytes"
                apk.write_bytes(payload)
                with mock.patch.object(adb_forward, "_READINESS_PROBE_APK_SHA256",
                                       hashlib.sha256(payload).hexdigest()):
                    with self.assertRaises(probe.ProbeError) as raised:
                        self.install_probe(adapter, TARGET, apk, deadline=20)
                self.assertEqual(raised.exception.code, "IntegrityConflict")
                self.assertFalse(any(
                    call[0][3:6] == ("shell", "pm", "install-create") for call in runner.calls
                ))

    def test_adb_install_allowlist_excludes_replacement_and_other_users(self):
        apk_bytes = b"reviewed readiness apk bytes"
        digest = hashlib.sha256(apk_bytes).hexdigest()
        with tempfile.TemporaryDirectory() as directory:
            apk = pathlib.Path(directory) / "source.apk"
            apk.write_bytes(apk_bytes)
            apk.chmod(0o400)
            descriptor = os.open(apk, os.O_RDONLY)
            try:
                link = pathlib.Path(directory) / "readiness.apk"
                link.symlink_to(f"/dev/fd/{descriptor}")
                approved = (
                    "adb", "-s", TARGET, "install", "--no-streaming",
                    "--user", "10", str(link),
                )
                with mock.patch.object(
                    adb_forward,
                    "_READINESS_PROBE_APK_SHA256",
                    digest,
                    create=True,
                ):
                    self.assertFalse(_AdbCommandRunner._allowed_vector(approved))
                    self.assertFalse(
                        _AdbCommandRunner._allowed_vector(
                            approved[:4] + ("-r",) + approved[4:]
                        )
                    )
                    self.assertFalse(
                        _AdbCommandRunner._allowed_vector(
                            approved[:6] + ("all",) + approved[7:]
                        )
                    )
            finally:
                os.close(descriptor)

    def test_adb_runner_rejects_unpinned_install_path_before_spawn(self):
        with tempfile.TemporaryDirectory() as directory:
            apk = pathlib.Path(directory) / "wrong.apk"
            apk.write_bytes(b"not the approved signed artifact")
            argv = (
                "adb", "-s", TARGET, "install", "--no-streaming",
                "--user", "10", str(apk),
            )
            popen = mock.Mock()
            runner = _AdbCommandRunner(popen=popen)
            with mock.patch.object(
                adb_forward,
                "_READINESS_PROBE_APK_SHA256",
                "0" * 64,
                create=True,
            ):
                with self.assertRaises(probe.ProbeError) as raised:
                    runner.run(argv, deadline=time.monotonic() + 20)

        self.assertEqual(raised.exception.code, "MalformedRequest")
        popen.assert_not_called()

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

    def test_runner_rejects_nonempty_stderr_for_package_state_query(self):
        package = readiness_probe_artifact.PACKAGE
        runner, _, process, selector, _ = self.build_runner(
            chunks=(b"", b"private package manager diagnostic")
        )
        command = (
            "adb", "-s", TARGET, "shell", "pm", "list", "packages",
            "--show-versioncode", "-U", "--user", "10", package,
        )

        with self.assertRaises(probe.ProbeError) as raised:
            runner.run(command, deadline=20)

        self.assertEqual(raised.exception.code, "IncompleteEvidence")
        self.assertEqual(raised.exception.diagnostic_subtype, "stderr_nonempty")
        self.assertNotIn("private package manager diagnostic", str(raised.exception))
        self.assertTrue(selector.closed)
        self.assertTrue(process.stdout.closed)
        self.assertTrue(process.stderr.closed)

    def test_runner_rejects_unjournaled_direct_install(self):
        runner, _, _, _, popen_calls = self.build_runner(chunks=(b"", b""))
        argv = (
            "adb", "-s", TARGET, "install", "--no-streaming",
            "--user", "10", "/unused/readiness.apk",
        )

        with self.assertRaises(probe.ProbeError) as raised:
            runner.run(argv, deadline=20)

        self.assertEqual(raised.exception.code, "MalformedRequest")
        self.assertEqual(popen_calls, [])
        self.assertTrue(_AdbCommandRunner._allowed_vector((
            "adb", "-s", TARGET, "shell", "pm", "install-create", "-S",
            "28", "--user", "10", "--pkg", readiness_probe_artifact.PACKAGE,
        )))
        self.assertTrue(_AdbCommandRunner._allowed_vector((
            "adb", "-s", TARGET, "shell", "pm", "install-write", "-S",
            "28", "17", "base", "-",
        )))
        self.assertTrue(_AdbCommandRunner._allowed_vector((
            "adb", "-s", TARGET, "shell", "pm", "install-commit", "17",
        )))

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
            ("adb", "-s", TARGET, "shell", "getprop", "ro.product.cpu.abi"),
            (
                "adb", "-s", TARGET, "shell", "pm", "list", "packages",
                "--show-versioncode", "-U", "--user", "10",
                packaging.QUALIFICATION_APPLICATION_ID,
            ),
            (
                "adb", "-s", TARGET, "shell", "pm", "list", "packages",
                "--show-versioncode", "-U", "--user", "10",
                readiness_probe_artifact.PACKAGE,
            ),
            ("adb", "-s", TARGET, "forward", "--list"),
            ("adb", "-s", TARGET, "forward", "--no-rebind", LOCAL, REMOTE),
            ("adb", "-s", TARGET, "forward", "--remove", LOCAL),
        )
        self.assertTrue(all(_AdbCommandRunner._allowed_vector(vector) for vector in vectors))
        self.assertFalse(
            _AdbCommandRunner._allowed_vector(
                (
                    "adb", "-s", TARGET, "shell", "pm", "list", "packages",
                "--show-versioncode", "-U", "--user", "10", [],
                )
            )
        )
        for vector in (
            ["adb", "-s", TARGET, "get-state"],
            ("adb", "-s", "bad target", "get-state"),
            ("adb", "-s", TARGET),
            ("adb", "-s", TARGET, "shell", "getprop", "ro.product.model"),
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
