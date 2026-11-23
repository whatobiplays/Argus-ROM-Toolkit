"""Host-only tests for recovering a pinned Readiness package cleanup."""

import hashlib
import json
import os
import pathlib
import tempfile
import time
import unittest
from datetime import datetime, timezone
from types import SimpleNamespace
from unittest import mock

from .test_readiness_probe_install_journal import (
    complete_session_dump, session_dump, wrapped_historical_session,
)

from . import adb_forward
from . import readiness_probe as probe
from . import readiness_probe_artifact
from . import readiness_probe_recovery as recovery
from . import readiness_probe_install_journal
from . import q7_exploratory_acquisition as q7


TARGET = "SERIAL-1"
BUILD = "brand/device:version/id/incremental:user/release-keys"
UID = 10123


class FakeRunner:
    def __init__(self, replies):
        self.replies = list(replies)
        self.calls = []

    def run_install_sessions(self, target, stdout_consumer, *, deadline):
        output = self.run(("adb", "-s", target, *adb_forward._INSTALL_SESSIONS_COMMAND), deadline)
        output = complete_session_dump(output)
        stdout_consumer(output)
        return adb_forward.Q7CommandResult(
            command_count=1, started_monotonic=0.0, finished_monotonic=0.0,
            stdout_bytes=len(output), total_output_bytes=len(output), exit_code=0,
            classification="exit_zero", cleanup_complete=True, stderr_empty=True,
        )

    def run(self, argv, deadline):
        self.calls.append(tuple(argv))
        if tuple(argv[3:]) == ("shell", "pm", "list", "users"):
            return b"Users:\n  UserInfo{10:Owner:13} running\n"
        if not self.replies:
            raise AssertionError("unexpected ADB command")
        return self.replies.pop(0)


class LifecycleRunner:
    """Model package installation with one-shot command-boundary faults."""

    def __init__(self, *, fail_command=None, failure_point=None):
        self.calls = []
        self.fail_command = fail_command
        self.failure_point = failure_point
        self.package_present = False
        self.android_user_ids = (10,)
        self.other_user_packages = set()
        self.users_output = None
        self.session = None
        self.session_active = False
        self.preexisting_active_session = False
        self.competing_session_after_create = False
        self.competing_session_active = False
        self.install_session_snapshot_count = 0
        self.competing_session_after_snapshot_number = None
        self.installed_apk = b""
        self.abandon_behavior = "abandon"

    def _fail_if_requested(self, command_name, point):
        if self.fail_command == command_name and self.failure_point == point:
            self.fail_command = None
            self.failure_point = None
            raise TimeoutError("synthetic bounded command failure")

    def _session_dump(self):
        if self.session is None:
            if self.preexisting_active_session:
                package = readiness_probe_artifact.PACKAGE
                return (
                    "Active install sessions:\n"
                    "  Session 99:\n"
                    "    userId=10\n"
                    "    installerPackageName=com.android.shell\n"
                    "    mInstallerUid=2000\n"
                    f"    appPackageName={package}\n"
                    "    mCommitted=true\n"
                    "    mFinalStatus=1\n"
                ).encode("ascii")
            return b"Active install sessions:\n"
        package = readiness_probe_artifact.PACKAGE
        committed = self.session["committed"]
        final_status = 1 if committed else 0
        section = "Active" if self.session_active else "Historical"
        output = (
            f"{section} install sessions:\n"
            "  Session 17:\n"
            "    userId=10\n"
            "    installerPackageName=com.android.shell\n"
            "    mInstallerUid=2000\n"
            f"    appPackageName={package}\n"
            f"    mCommitted={'true' if committed else 'false'}\n"
            f"    mFinalStatus={final_status}\n"
        )
        if self.competing_session_active:
            output += (
                "  Session 18:\n"
                "    userId=10\n"
                "    installerPackageName=com.android.shell\n"
                "    mInstallerUid=2000\n"
                f"    appPackageName={package}\n"
                "    mCommitted=false\n"
                "    mFinalStatus=0\n"
            )
        return output.encode("ascii")

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
        self.calls.append(tuple(argv))
        command = tuple(argv[3:])
        if command == ("get-state",):
            return b"device\n"
        if command == ("shell", "getprop", "ro.build.fingerprint"):
            return (BUILD + "\n").encode("ascii")
        if command == ("shell", "am", "get-current-user"):
            return b"10\n"
        if command == ("shell", "pm", "list", "users"):
            if self.users_output is not None:
                return self.users_output
            rows = "".join(
                f"  UserInfo{{{user_id}:Owner:13}} running\n"
                for user_id in self.android_user_ids
            )
            return ("Users:\n" + rows).encode("ascii")
        if command[:4] == ("shell", "pm", "list", "packages"):
            user_id = int(command[-2])
            is_present = (
                self.package_present if user_id == 10
                else user_id in self.other_user_packages
            )
            if not is_present:
                return b""
            package = readiness_probe_artifact.PACKAGE
            return f"package:{package} versionCode:1 uid:{UID}\n".encode("ascii")
        if command == adb_forward._INSTALL_SESSIONS_COMMAND:
            self.install_session_snapshot_count += 1
            output = self._session_dump()
            if (
                self.install_session_snapshot_count
                == self.competing_session_after_snapshot_number
            ):
                self.competing_session_active = True
            return output
        if command[:3] == ("shell", "pm", "install-create"):
            self._fail_if_requested("install-create", "before")
            self.session = {"committed": False, "payload": b""}
            self.session_active = True
            self.competing_session_active = self.competing_session_after_create
            self._fail_if_requested("install-create", "after")
            return b"Success: created install session [17]\n"
        if command[:3] == ("shell", "pm", "install-write"):
            self._fail_if_requested("install-write", "before")
            if input_fd is None or type(input_size) is not int:
                raise AssertionError("install session payload was not streamed")
            payload = bytearray()
            offset = 0
            while offset < input_size:
                chunk = os.pread(input_fd, min(65536, input_size - offset), offset)
                if not chunk:
                    raise AssertionError("install session payload was truncated")
                payload.extend(chunk)
                offset += len(chunk)
            self.session["payload"] = bytes(payload)
            self._fail_if_requested("install-write", "after")
            return f"Success: streamed {input_size} bytes\n".encode("ascii")
        if command[:3] == ("shell", "pm", "install-commit"):
            self._fail_if_requested("install-commit", "before")
            if self.session is None:
                raise AssertionError("no install session to commit")
            self.session["committed"] = True
            self.package_present = True
            self.installed_apk = self.session["payload"]
            self.session_active = False
            self._fail_if_requested("install-commit", "after")
            return b"Success\n"
        if command[:3] == ("shell", "pm", "install-abandon"):
            self._fail_if_requested("install-abandon", "before")
            if self.abandon_behavior == "late_commit":
                if self.session is None:
                    raise AssertionError("no install session to finish")
                self.session["committed"] = True
                self.package_present = True
                self.installed_apk = self.session["payload"]
                self.session_active = False
            elif self.abandon_behavior == "remain_active":
                pass
            else:
                self.session = None
                self.session_active = False
            self._fail_if_requested("install-abandon", "after")
            return b"Success\n"
        if command == ("shell", "pm", "path", readiness_probe_artifact.PACKAGE):
            return b"package:/data/app/readiness/base.apk\n"
        if command[:2] == ("exec-out", "cat"):
            return self.installed_apk
        if command[:3] == ("shell", "pm", "uninstall"):
            self._fail_if_requested("uninstall", "before")
            self.package_present = False
            self._fail_if_requested("uninstall", "after")
            return b"Success\n"
        raise AssertionError("unexpected bounded ADB command")


def install_record(install_attempt_id="a" * 32):
    return {
        "schema": "argus-issue-74-b1-preparation-observation-v2",
        "install_attempt_id": install_attempt_id,
        "acquired_at_utc": "2026-11-22T12:47:30Z",
        "target_reference": q7.TARGET_REFERENCE,
        "identity_preflight_record_bound": True,
        "identity_match": True,
        "identity_private": {
            "serial": TARGET,
            "build_fingerprint": BUILD,
        },
        "artifact": {
            "package": readiness_probe_artifact.PACKAGE,
            "sha256": adb_forward._READINESS_PROBE_APK_SHA256,
            "version_code": adb_forward._READINESS_PROBE_VERSION_CODE,
        },
        "install_status": "installed",
        "package_baseline_absent": True,
        "qualification_assertions_passed": False,
        "android_user_private": 10,
        "package_uid_private": UID,
    }


def legacy_install_record():
    record = install_record()
    record["schema"] = "argus-issue-74-b1-preparation-observation-v1"
    record.pop("install_attempt_id")
    return record


def write_record(directory, record, *, mode=0o600, name="install.json"):
    path = pathlib.Path(directory) / name
    payload = (json.dumps(record, sort_keys=True) + "\n").encode("utf-8")
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, mode)
    try:
        os.write(descriptor, payload)
        os.fchmod(descriptor, mode)
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    return path


def record_digest(path):
    return hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()


def cleanup_outcome(
    install_record_sha256,
    *,
    cleanup_attempt_id,
    install_attempt_id=None,
):
    return {
        "schema": "argus-issue-74-b1-cleanup-recovery-v2",
        "target_reference": q7.TARGET_REFERENCE,
        "classification": "cleanup_complete",
        "failure_code": None,
        "cleanup_state": "uninstalled",
        "readback_state": "absent",
        "finished_at_utc": "2026-11-22T12:47:33Z",
        "cleanup_attempt_id": cleanup_attempt_id,
        "install_attempt_id": install_attempt_id,
        "install_record_sha256": install_record_sha256,
        "source_identity": {
            "adb_forward_sha256": "a" * 64,
            "recovery_sha256": "b" * 64,
        },
        "raw_output_retained": False,
        "stdout_retained": False,
        "stderr_retained": False,
        "qualification_assertions_passed": False,
    }


class ReadinessProbeRecoveryTests(unittest.TestCase):
    def private_directory(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        directory = pathlib.Path(temporary.name) / "outcomes"
        directory.mkdir(mode=0o700)
        return directory

    def runner_for_cleanup(self, *, user=b"10\n", package_state=None):
        package = readiness_probe_artifact.PACKAGE
        present = (
            f"package:{package} versionCode:1 uid:{UID}\n".encode("ascii")
            if package_state is None
            else package_state
        )
        return FakeRunner(
            [
                b"device\n",
                (BUILD + "\n").encode("ascii"),
                user,
                present,
                b"Success\n",
                b"",
            ]
        )

    def journal_for_attempt(
        self, directory, *, attempt_id="c" * 32, digest=None, fresh_baseline_admission=False,
    ):
        digest = digest or adb_forward._READINESS_PROBE_APK_SHA256
        payload_size = 28
        journal = readiness_probe_install_journal.ReadinessInstallJournal(
            directory,
            target_reference=q7.TARGET_REFERENCE,
            serial=TARGET,
            build_fingerprint=BUILD,
            android_user_id=10,
            package=readiness_probe_artifact.PACKAGE,
            artifact_sha256=digest,
            version_code=adb_forward._READINESS_PROBE_VERSION_CODE,
            artifact_size=payload_size,
            baseline_session_ids=(),
            attempt_id=attempt_id,
            fresh_baseline_admission=fresh_baseline_admission,
        )
        return journal

    def complete_journal(self, journal, *, digest):
        journal.checkpoint("attempted", "create_started")
        journal.checkpoint(
            "attempted", "session_created", remote_session_id=17
        )
        journal.checkpoint(
            "attempted", "write_started", remote_session_id=17
        )
        journal.checkpoint(
            "attempted", "payload_written", remote_session_id=17
        )
        journal.checkpoint(
            "attempted", "commit_started", remote_session_id=17
        )
        journal.checkpoint(
            "completed",
            "installed",
            remote_session_id=17,
            package_uid_private=UID,
            installed_apk_sha256=digest,
        )

    def runner_for_journal_cleanup(self, *, digest, package_state=None):
        package = readiness_probe_artifact.PACKAGE
        present = (
            f"package:{package} versionCode:1 uid:{UID}\n".encode("ascii")
            if package_state is None
            else package_state
        )
        session_dump = (
            "Historical install sessions:\n"
            "  Session 17:\n"
            "    userId=10\n"
            "    installerPackageName=com.android.shell\n"
            "    mInstallerUid=2000\n"
            f"    appPackageName={package}\n"
            "    mCommitted=true\n"
            "    mFinalStatus=1\n"
        ).encode("ascii")
        return FakeRunner([
            b"device\n",
            (BUILD + "\n").encode("ascii"),
            b"10\n",
            present,
            session_dump,
            b"package:/data/app/readiness/base.apk\n",
            b"x" * 28,
            b"Success\n",
            b"",
        ])

    def install_with_lifecycle_runner(
        self, runner, outcomes_directory, *, payload=b"reviewed readiness apk bytes",
        attempt_id="d" * 32,
    ):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        apk = pathlib.Path(temporary.name) / "readiness.apk"
        apk.write_bytes(payload)
        adapter = adb_forward.AdbForwardAdapter(runner=runner)
        deadline = time.monotonic() + 60
        adapter.identity(TARGET, deadline=deadline)
        adapter.package_install_state(
            TARGET, readiness_probe_artifact.PACKAGE, deadline=deadline
        )
        digest = hashlib.sha256(payload).hexdigest()
        result = adapter.install_readiness_probe(
            TARGET,
            apk,
            deadline=deadline,
            outcomes_directory=outcomes_directory,
            target_reference=q7.TARGET_REFERENCE,
            install_attempt_id=attempt_id,
        )
        return adapter, result, digest

    def test_recovery_uninstalls_owned_package_after_host_interruption(self):
        directory = self.private_directory()
        payload = b"x" * 28
        digest = hashlib.sha256(payload).hexdigest()
        journal = self.journal_for_attempt(directory, digest=digest)
        self.complete_journal(journal, digest=digest)
        runner = LifecycleRunner()
        runner.package_present = True
        runner.session = {"committed": True, "payload": payload}
        runner.installed_apk = payload

        with mock.patch.object(
            adb_forward, "_READINESS_PROBE_APK_SHA256", digest
        ):
            result = recovery.recover_installed_readiness_probe(
                directory,
                target_reference=q7.TARGET_REFERENCE,
                runner=runner,
                utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
            )

        self.assertEqual(result["classification"], "cleanup_complete")
        self.assertEqual(result["failure_code"], None)
        self.assertEqual(result["adb_command_counts"]["package_uninstall"], 1)
        self.assertFalse(runner.package_present)
        self.assertTrue(any(
            call[3:6] == ("shell", "pm", "uninstall")
            for call in runner.calls
        ))
        self.assertEqual(result["source_identity"]["install_journal_sha256"],
                         recovery._source_hash(readiness_probe_install_journal.__file__))
        events = readiness_probe_install_journal.read_install_journal_events(
            directory, target_reference=q7.TARGET_REFERENCE
        )[journal.attempt_id]
        self.assertEqual((events[-1]["state"], events[-1]["phase"]),
                         ("cleaned_up", "package_uninstalled"))

    def test_recovery_rechecks_ownership_after_durable_cleanup_intent(self):
        directory = self.private_directory()
        payload = b"x" * 28
        digest = hashlib.sha256(payload).hexdigest()
        journal = self.journal_for_attempt(directory, digest=digest)
        self.complete_journal(journal, digest=digest)
        journal.checkpoint(
            "attempted", "cleanup_started", remote_session_id=17
        )
        runner = LifecycleRunner()
        runner.package_present = True
        runner.session = {"committed": True, "payload": payload}
        runner.installed_apk = payload

        with mock.patch.object(adb_forward, "_READINESS_PROBE_APK_SHA256", digest):
            result = recovery.recover_installed_readiness_probe(
                directory,
                target_reference=q7.TARGET_REFERENCE,
                runner=runner,
                utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
            )

        self.assertEqual(result["classification"], "cleanup_complete")
        self.assertEqual(result["failure_code"], None)
        self.assertEqual(result["adb_command_counts"]["package_uninstall"], 1)
        self.assertFalse(runner.package_present)
        events = readiness_probe_install_journal.read_install_journal_events(
            directory, target_reference=q7.TARGET_REFERENCE
        )[journal.attempt_id]
        self.assertEqual((events[-1]["state"], events[-1]["phase"]),
                         ("cleaned_up", "package_uninstalled"))

    def test_recovery_rejects_record_paired_with_another_install_journal(self):
        directory = self.private_directory()
        digest = hashlib.sha256(b"x" * 28).hexdigest()
        first = self.journal_for_attempt(
            directory, attempt_id="c" * 32, digest=digest
        )
        self.complete_journal(first, digest=digest)
        second = self.journal_for_attempt(
            directory, attempt_id="d" * 32, digest=digest
        )
        self.complete_journal(second, digest=digest)
        runner = self.runner_for_journal_cleanup(digest=digest)
        adapter = adb_forward.AdbForwardAdapter(runner=runner)
        deadline = time.monotonic() + 60

        with mock.patch.object(adb_forward, "_READINESS_PROBE_APK_SHA256", digest):
            adapter.identity(TARGET, deadline=deadline)
            with self.assertRaises(adb_forward.ProbeError):
                adapter.recover_readiness_cleanup(
                    TARGET,
                    first.latest,
                    deadline=deadline,
                    install_journal=second,
                )

        self.assertFalse(any("uninstall" in call for call in runner.calls))

    def test_recovery_rejects_stale_record_from_the_same_install_journal(self):
        directory = self.private_directory()
        digest = hashlib.sha256(b"x" * 28).hexdigest()
        journal = self.journal_for_attempt(
            directory, attempt_id="c" * 32, digest=digest
        )
        self.complete_journal(journal, digest=digest)
        stale_record = journal.latest
        journal.checkpoint(
            "attempted", "cleanup_started", remote_session_id=17
        )
        runner = self.runner_for_journal_cleanup(digest=digest)
        adapter = adb_forward.AdbForwardAdapter(runner=runner)
        deadline = time.monotonic() + 60

        with mock.patch.object(adb_forward, "_READINESS_PROBE_APK_SHA256", digest):
            adapter.identity(TARGET, deadline=deadline)
            with self.assertRaises(adb_forward.ProbeError):
                adapter.recover_readiness_cleanup(
                    TARGET,
                    stale_record,
                    deadline=deadline,
                    install_journal=journal,
                )

        self.assertFalse(any("uninstall" in call for call in runner.calls))

    def test_install_blocks_if_qualification_package_exists_for_another_user(self):
        directory = self.private_directory()
        runner = LifecycleRunner()
        runner.android_user_ids = (10, 11)
        runner.other_user_packages = {11}
        payload = b"reviewed readiness apk bytes"
        digest = hashlib.sha256(payload).hexdigest()

        with mock.patch.object(adb_forward, "_READINESS_PROBE_APK_SHA256", digest):
            with self.assertRaises(probe.ProbeError) as raised:
                self.install_with_lifecycle_runner(
                    runner, directory, payload=payload, attempt_id="e" * 32
                )

        self.assertEqual(raised.exception.code, "IntegrityConflict")
        commands = [call[3:] for call in runner.calls]
        self.assertNotIn(("shell", "pm", "install-create", "-S"), commands)
        self.assertEqual(
            readiness_probe_install_journal.read_install_journal_events(
                directory, target_reference=q7.TARGET_REFERENCE
            ),
            {},
        )

    def test_recovery_blocks_cleanup_if_package_exists_for_another_user(self):
        directory = self.private_directory()
        runner = LifecycleRunner()
        payload = b"reviewed readiness apk bytes"
        digest = hashlib.sha256(payload).hexdigest()

        with mock.patch.object(adb_forward, "_READINESS_PROBE_APK_SHA256", digest):
            _adapter, installed, _digest = self.install_with_lifecycle_runner(
                runner, directory, payload=payload, attempt_id="f" * 32
            )
            self.assertEqual(installed["state"], "installed")
            runner.android_user_ids = (10, 11)
            runner.other_user_packages = {11}

            result = recovery.recover_installed_readiness_probe(
                directory,
                target_reference=q7.TARGET_REFERENCE,
                runner=runner,
                utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
            )

        self.assertEqual(result["classification"], "blocked")
        self.assertEqual(result["adb_command_counts"]["package_uninstall"], 0)
        self.assertNotIn(
            ("shell", "pm", "uninstall", "--user", "10",
             readiness_probe_artifact.PACKAGE),
            [call[3:] for call in runner.calls],
        )

    def test_unrecognized_user_list_fails_closed_without_install(self):
        directory = self.private_directory()
        runner = LifecycleRunner()
        runner.users_output = b"warning: private profile diagnostic\n"
        payload = b"reviewed readiness apk bytes"
        digest = hashlib.sha256(payload).hexdigest()

        with mock.patch.object(adb_forward, "_READINESS_PROBE_APK_SHA256", digest):
            with self.assertRaises(probe.ProbeError) as raised:
                self.install_with_lifecycle_runner(
                    runner, directory, payload=payload, attempt_id="9" * 32
                )

        self.assertEqual(raised.exception.code, "IncompleteEvidence")
        self.assertNotIn("private profile diagnostic", str(raised.exception))
        self.assertFalse(
            any(call[3:6] == ("shell", "pm", "install-create")
                for call in runner.calls)
        )
        self.assertEqual(
            readiness_probe_install_journal.read_install_journal_events(
                directory, target_reference=q7.TARGET_REFERENCE
            ),
            {},
        )

    def test_recovery_resolves_pending_journal_absence_without_uninstall(self):
        directory = self.private_directory()
        journal = self.journal_for_attempt(directory)
        runner = FakeRunner([
            b"device\n",
            (BUILD + "\n").encode("ascii"),
            b"10\n",
            b"",
            b"Active install sessions:\n",
        ])

        result = recovery.recover_installed_readiness_probe(
            directory,
            target_reference=q7.TARGET_REFERENCE,
            runner=runner,
            utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
        )

        self.assertEqual(result["classification"], "cleanup_complete")
        self.assertEqual(result["cleanup_state"], "already_absent")
        self.assertEqual(result["adb_command_counts"]["package_uninstall"], 0)
        events = readiness_probe_install_journal.read_install_journal_events(
            directory, target_reference=q7.TARGET_REFERENCE
        )[journal.attempt_id]
        self.assertEqual((events[-1]["state"], events[-1]["phase"]),
                         ("cleaned_up", "verified_absent"))

    def test_recovery_resolves_absence_when_recorded_session_is_missing(self):
        directory = self.private_directory()
        journal = self.journal_for_attempt(directory)
        journal.checkpoint("attempted", "create_started")
        journal.checkpoint(
            "attempted", "session_created", remote_session_id=17
        )
        runner = FakeRunner([
            b"device\n",
            (BUILD + "\n").encode("ascii"),
            b"10\n",
            b"",
            b"Active install sessions:\n",
        ])

        result = recovery.recover_installed_readiness_probe(
            directory,
            target_reference=q7.TARGET_REFERENCE,
            runner=runner,
            utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
        )

        self.assertEqual(result["classification"], "cleanup_complete")
        self.assertEqual(result["cleanup_state"], "already_absent")
        self.assertEqual(result["adb_command_counts"]["install_abandon"], 0)
        self.assertEqual(result["adb_command_counts"]["package_uninstall"], 0)
        events = readiness_probe_install_journal.read_install_journal_events(
            directory, target_reference=q7.TARGET_REFERENCE
        )[journal.attempt_id]
        self.assertEqual((events[-1]["state"], events[-1]["phase"]),
                         ("cleaned_up", "verified_absent"))

    def test_recovery_outcome_write_failure_is_reported_after_absence_readback(self):
        directory = self.private_directory()
        journal = self.journal_for_attempt(directory)
        runner = FakeRunner([
            b"device\n",
            (BUILD + "\n").encode("ascii"),
            b"10\n",
            b"",
            b"Active install sessions:\n",
        ])

        with mock.patch.object(
            recovery,
            "_write_private_outcome",
            side_effect=probe.ProbeError("IncompleteEvidence", "Transport"),
        ):
            result = recovery.recover_installed_readiness_probe(
                directory,
                target_reference=q7.TARGET_REFERENCE,
                runner=runner,
                utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
            )

        self.assertEqual(result["classification"], "cleanup_verified_unrecorded")
        self.assertEqual(result["failure_code"], "IncompleteEvidence")
        self.assertFalse(result["outcome_written"])
        self.assertEqual(result["cleanup_state"], "already_absent")
        self.assertEqual(result["adb_command_counts"]["package_uninstall"], 0)
        self.assertEqual(
            readiness_probe_install_journal.read_install_journal_events(
                directory, target_reference=q7.TARGET_REFERENCE
            )[journal.attempt_id][-1]["phase"],
            "verified_absent",
        )

    def test_active_committed_session_is_abandoned_before_absence_is_accepted(self):
        directory = self.private_directory()
        runner = LifecycleRunner()
        payload = b"reviewed readiness apk bytes"
        digest = hashlib.sha256(payload).hexdigest()

        with mock.patch.object(adb_forward, "_READINESS_PROBE_APK_SHA256", digest):
            _adapter, installed, _digest = self.install_with_lifecycle_runner(
                runner, directory, payload=payload, attempt_id="3" * 32
            )
            self.assertEqual(installed["state"], "installed")
            runner.package_present = False
            runner.session_active = True

            result = recovery.recover_installed_readiness_probe(
                directory,
                target_reference=q7.TARGET_REFERENCE,
                runner=runner,
                utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
            )

        self.assertEqual(result["classification"], "cleanup_complete")
        self.assertEqual(result["cleanup_state"], "already_absent")
        self.assertEqual(result["failure_code"], None)
        self.assertEqual(result["adb_command_counts"]["install_abandon"], 1)
        self.assertEqual(result["adb_command_counts"]["package_uninstall"], 0)
        self.assertFalse(any(
            call[3:6] == ("shell", "pm", "uninstall")
            for call in runner.calls
        ))
        events = readiness_probe_install_journal.read_install_journal_events(
            directory, target_reference=q7.TARGET_REFERENCE
        )["3" * 32]
        self.assertEqual((events[-1]["state"], events[-1]["phase"]),
                         ("cleaned_up", "verified_absent"))

    def test_recovery_blocks_if_committed_session_survives_abandon(self):
        directory = self.private_directory()
        runner = LifecycleRunner()
        payload = b"reviewed readiness apk bytes"
        digest = hashlib.sha256(payload).hexdigest()

        with mock.patch.object(adb_forward, "_READINESS_PROBE_APK_SHA256", digest):
            self.install_with_lifecycle_runner(
                runner, directory, payload=payload, attempt_id="5" * 32
            )
            runner.package_present = False
            runner.session_active = True
            runner.abandon_behavior = "remain_active"

            result = recovery.recover_installed_readiness_probe(
                directory,
                target_reference=q7.TARGET_REFERENCE,
                runner=runner,
                utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
            )

        self.assertEqual(result["classification"], "blocked")
        self.assertEqual(result["failure_code"], "IncompleteEvidence")
        self.assertEqual(result["adb_command_counts"]["install_abandon"], 1)
        self.assertEqual(result["adb_command_counts"]["package_uninstall"], 0)
        events = readiness_probe_install_journal.read_install_journal_events(
            directory, target_reference=q7.TARGET_REFERENCE
        )["5" * 32]
        self.assertEqual((events[-1]["state"], events[-1]["phase"]),
                         ("attempted", "abandon_started"))

    def test_late_commit_is_verified_before_owned_package_cleanup(self):
        directory = self.private_directory()
        runner = LifecycleRunner()
        payload = b"reviewed readiness apk bytes"
        digest = hashlib.sha256(payload).hexdigest()

        with mock.patch.object(adb_forward, "_READINESS_PROBE_APK_SHA256", digest):
            self.install_with_lifecycle_runner(
                runner, directory, payload=payload, attempt_id="6" * 32
            )
            runner.package_present = False
            runner.session_active = True
            runner.abandon_behavior = "late_commit"

            result = recovery.recover_installed_readiness_probe(
                directory,
                target_reference=q7.TARGET_REFERENCE,
                runner=runner,
                utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
            )

        self.assertEqual(result["classification"], "cleanup_complete")
        self.assertEqual(result["failure_code"], None)
        self.assertEqual(result["cleanup_state"], "uninstalled")
        self.assertEqual(result["adb_command_counts"]["install_abandon"], 1)
        self.assertEqual(result["adb_command_counts"]["package_uninstall"], 1)
        self.assertFalse(runner.package_present)
        events = readiness_probe_install_journal.read_install_journal_events(
            directory, target_reference=q7.TARGET_REFERENCE
        )["6" * 32]
        self.assertEqual((events[-1]["state"], events[-1]["phase"]),
                         ("cleaned_up", "package_uninstalled"))

    def test_abandon_intent_persistence_faults_prevent_the_command(self):
        for index, failure_point in enumerate(("before", "after"), start=1):
            with self.subTest(failure_point=failure_point):
                directory = self.private_directory()
                runner = LifecycleRunner()
                payload = b"reviewed readiness apk bytes"
                digest = hashlib.sha256(payload).hexdigest()
                attempt_id = f"{index + 6:032x}"

                with mock.patch.object(adb_forward, "_READINESS_PROBE_APK_SHA256", digest):
                    self.install_with_lifecycle_runner(
                        runner, directory, payload=payload, attempt_id=attempt_id
                    )
                    runner.package_present = False
                    runner.session_active = True
                    original_checkpoint = (
                        readiness_probe_install_journal.ReadinessInstallJournal.checkpoint
                    )

                    def fail_abandon_intent(journal, state, phase, **kwargs):
                        if (state, phase) == ("attempted", "abandon_started"):
                            if failure_point == "after":
                                original_checkpoint(journal, state, phase, **kwargs)
                            raise probe.ProbeError("IncompleteEvidence", "Transport")
                        return original_checkpoint(journal, state, phase, **kwargs)

                    with mock.patch.object(
                        readiness_probe_install_journal.ReadinessInstallJournal,
                        "checkpoint",
                        fail_abandon_intent,
                    ):
                        result = recovery.recover_installed_readiness_probe(
                            directory,
                            target_reference=q7.TARGET_REFERENCE,
                            runner=runner,
                            utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
                        )

                self.assertEqual(result["classification"], "blocked")
                self.assertEqual(result["adb_command_counts"]["install_abandon"], 0)
                events = readiness_probe_install_journal.read_install_journal_events(
                    directory, target_reference=q7.TARGET_REFERENCE
                )[attempt_id]
                expected = (
                    ("completed", "installed")
                    if failure_point == "before"
                    else ("attempted", "abandon_started")
                )
                self.assertEqual((events[-1]["state"], events[-1]["phase"]), expected)

    def test_abandon_command_faults_resume_from_durable_intent(self):
        for index, failure_point in enumerate(("before", "after"), start=1):
            with self.subTest(failure_point=failure_point):
                directory = self.private_directory()
                runner = LifecycleRunner(
                    fail_command="install-abandon", failure_point=failure_point
                )
                payload = b"reviewed readiness apk bytes"
                digest = hashlib.sha256(payload).hexdigest()
                attempt_id = f"{index + 8:032x}"

                with mock.patch.object(adb_forward, "_READINESS_PROBE_APK_SHA256", digest):
                    self.install_with_lifecycle_runner(
                        runner, directory, payload=payload, attempt_id=attempt_id
                    )
                    runner.package_present = False
                    runner.session_active = True
                    first = recovery.recover_installed_readiness_probe(
                        directory,
                        target_reference=q7.TARGET_REFERENCE,
                        runner=runner,
                        utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
                    )
                    second = recovery.recover_installed_readiness_probe(
                        directory,
                        target_reference=q7.TARGET_REFERENCE,
                        runner=runner,
                        utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
                    )

                self.assertEqual(first["classification"], "blocked")
                self.assertEqual(second["classification"], "cleanup_complete")
                self.assertEqual(second["cleanup_state"], "already_absent")
                abandon_calls = sum(
                    call[3:6] == ("shell", "pm", "install-abandon")
                    for call in runner.calls
                )
                self.assertEqual(abandon_calls, 2 if failure_point == "before" else 1)
                self.assertEqual(second["adb_command_counts"]["package_uninstall"], 0)

    def test_recovery_does_not_abandon_when_a_competing_package_session_exists(self):
        directory = self.private_directory()
        runner = LifecycleRunner()
        payload = b"reviewed readiness apk bytes"
        digest = hashlib.sha256(payload).hexdigest()

        with mock.patch.object(adb_forward, "_READINESS_PROBE_APK_SHA256", digest):
            self.install_with_lifecycle_runner(
                runner, directory, payload=payload, attempt_id="b" * 32
            )
            runner.package_present = False
            runner.session_active = True
            runner.competing_session_active = True

            result = recovery.recover_installed_readiness_probe(
                directory,
                target_reference=q7.TARGET_REFERENCE,
                runner=runner,
                utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
            )

        self.assertEqual(result["classification"], "blocked")
        self.assertEqual(result["failure_code"], "IntegrityConflict")
        self.assertEqual(result["adb_command_counts"]["install_abandon"], 0)
        self.assertEqual(result["adb_command_counts"]["package_uninstall"], 0)

    def test_recovery_blocks_competing_session_appearing_after_initial_snapshot(self):
        directory = self.private_directory()
        runner = LifecycleRunner()
        payload = b"reviewed readiness apk bytes"
        digest = hashlib.sha256(payload).hexdigest()

        with mock.patch.object(adb_forward, "_READINESS_PROBE_APK_SHA256", digest):
            self.install_with_lifecycle_runner(
                runner, directory, payload=payload, attempt_id="8" * 32
            )
            runner.competing_session_after_snapshot_number = (
                runner.install_session_snapshot_count + 1
            )

            result = recovery.recover_installed_readiness_probe(
                directory,
                target_reference=q7.TARGET_REFERENCE,
                runner=runner,
                utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
            )

        self.assertEqual(result["classification"], "blocked")
        self.assertEqual(result["failure_code"], "IntegrityConflict")
        self.assertTrue(runner.package_present)
        self.assertEqual(result["adb_command_counts"]["package_uninstall"], 0)

    def test_recovery_rechecks_sessions_after_final_package_readback(self):
        directory = self.private_directory()
        runner = LifecycleRunner()
        payload = b"reviewed readiness apk bytes"
        digest = hashlib.sha256(payload).hexdigest()

        with mock.patch.object(adb_forward, "_READINESS_PROBE_APK_SHA256", digest):
            self.install_with_lifecycle_runner(
                runner, directory, payload=payload, attempt_id="9" * 32
            )
            runner.competing_session_after_snapshot_number = (
                runner.install_session_snapshot_count + 2
            )

            result = recovery.recover_installed_readiness_probe(
                directory,
                target_reference=q7.TARGET_REFERENCE,
                runner=runner,
                utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
            )

        self.assertEqual(result["classification"], "blocked")
        self.assertEqual(result["failure_code"], "IntegrityConflict")
        self.assertTrue(runner.package_present)
        self.assertEqual(result["adb_command_counts"]["package_uninstall"], 0)

    def test_preexisting_active_session_blocks_before_install_journal_or_mutation(self):
        directory = self.private_directory()
        runner = LifecycleRunner()
        runner.preexisting_active_session = True
        payload = b"reviewed readiness apk bytes"
        digest = hashlib.sha256(payload).hexdigest()

        with mock.patch.object(adb_forward, "_READINESS_PROBE_APK_SHA256", digest):
            with self.assertRaises(probe.ProbeError) as raised:
                self.install_with_lifecycle_runner(
                    runner, directory, payload=payload, attempt_id="4" * 32
                )

        self.assertEqual(raised.exception.code, "IntegrityConflict")
        self.assertFalse(any(
            call[3:6] in {
                ("shell", "pm", "install-create"),
                ("shell", "pm", "install-write"),
                ("shell", "pm", "install-commit"),
            }
            for call in runner.calls
        ))
        self.assertEqual(
            readiness_probe_install_journal.read_install_journal_events(
                directory, target_reference=q7.TARGET_REFERENCE
            ),
            {},
        )

    def test_fresh_attempt_with_opaque_history_and_conflicting_legacy_can_restore(self):
        class HistoricalRunner(LifecycleRunner):
            def _session_dump(self):
                return super()._session_dump() + wrapped_historical_session(
                    session_id=31, package="null",
                )

        digest = hashlib.sha256(b"reviewed readiness apk bytes").hexdigest()
        for interrupted in (False, True):
            with self.subTest(interrupted=interrupted), mock.patch.object(
                adb_forward, "_READINESS_PROBE_APK_SHA256", digest,
            ):
                directory = self.private_directory()
                first = legacy_install_record()
                second = dict(first, package_uid_private=first["package_uid_private"] + 1)
                records = [
                    write_record(directory, first, name="legacy-1.json"),
                    write_record(directory, second, name="legacy-2.json"),
                ]
                original_digests = [record_digest(path) for path in records]
                runner = HistoricalRunner(
                    fail_command="install-write" if interrupted else None,
                    failure_point="after",
                )
                runner.android_user_ids = (0, 10, 11)
                if interrupted:
                    with self.assertRaises(probe.ProbeError):
                        self.install_with_lifecycle_runner(runner, directory)
                else:
                    _, installed, _ = self.install_with_lifecycle_runner(runner, directory)
                    self.assertEqual(installed["install_attempt_id"], "d" * 32)
                result = recovery.recover_installed_readiness_probe(
                    directory, target_reference=q7.TARGET_REFERENCE, runner=runner,
                )
                self.assertEqual(result["classification"], "cleanup_complete")
                self.assertEqual(result["adb_command_counts"]["install_abandon"], int(interrupted))
                self.assertEqual(result["adb_command_counts"]["package_uninstall"], int(not interrupted))
                self.assertFalse(runner.package_present)
                outcome = next(directory.glob("readiness-cleanup-recovery-*.json"))
                self.assertEqual(json.loads(outcome.read_text())["install_attempt_id"], "d" * 32)
                events = readiness_probe_install_journal.read_install_journal_events(
                    directory, target_reference=q7.TARGET_REFERENCE,
                )["d" * 32]
                self.assertEqual(events[0]["baseline_package_session_ids"], [31])
                self.assertTrue(all(event["fresh_baseline_admission"] for event in events))
                self.assertEqual(events[-1]["state"], "cleaned_up")
                self.assertEqual([record_digest(path) for path in records], original_digests)
                with self.assertRaises(probe.ProbeError) as raised:
                    recovery._read_install_record(directory, q7.TARGET_REFERENCE)
                self.assertEqual(raised.exception.code, "IntegrityConflict")

    def test_fresh_attempt_blocks_changed_live_baseline_before_install_create(self):
        class ChangingRunner(LifecycleRunner):
            def _session_dump(self):
                if self.install_session_snapshot_count == 2:
                    return session_dump(session_id=31, package="com.example.unrelated")
                return wrapped_historical_session(session_id=31, package="null")

        directory = self.private_directory()
        runner = ChangingRunner()
        digest = hashlib.sha256(b"reviewed readiness apk bytes").hexdigest()
        with mock.patch.object(adb_forward, "_READINESS_PROBE_APK_SHA256", digest):
            with self.assertRaises(probe.ProbeError) as raised:
                self.install_with_lifecycle_runner(runner, directory)
        self.assertEqual(raised.exception.code, "IntegrityConflict")
        self.assertFalse(any(call[3:6] == ("shell", "pm", "install-create") for call in runner.calls))
        events = readiness_probe_install_journal.read_install_journal_events(
            directory, target_reference=q7.TARGET_REFERENCE,
        )["d" * 32]
        self.assertEqual([event["phase"] for event in events], ["before_install"])

    def test_fresh_attempt_keeps_current_conflicts_and_cannot_be_closed_by_outcome(self):
        directory = self.private_directory()
        first = legacy_install_record()
        write_record(directory, first, name="legacy-1.json")
        write_record(directory, dict(first, package_uid_private=UID + 1), name="legacy-2.json")
        binding = (TARGET, BUILD, 10)
        self.assertIsNone(recovery._read_install_record(
            directory, q7.TARGET_REFERENCE, allow_no_active=True, fresh_binding=binding,
        ))
        with self.assertRaises(probe.ProbeError):
            recovery._read_install_record(
                directory, q7.TARGET_REFERENCE, allow_no_active=True,
                fresh_binding=(TARGET, BUILD, 11),
            )
        current = self.journal_for_attempt(directory)
        with self.assertRaises(probe.ProbeError):
            # A journal from before the decision cannot inherit the exception.
            recovery._read_install_record(directory, q7.TARGET_REFERENCE)
        self.assertEqual(recovery._read_install_record(
            directory, q7.TARGET_REFERENCE, allow_no_active=True, fresh_binding=binding,
        )[0], current.latest)
        self.journal_for_attempt(directory, attempt_id="e" * 32)
        with self.assertRaises(probe.ProbeError):
            recovery._read_install_record(
                directory, q7.TARGET_REFERENCE, allow_no_active=True, fresh_binding=binding,
            )
    def test_cleanup_outcome_cannot_replace_durable_current_cleanup(self):
        directory = self.private_directory()
        first = legacy_install_record()
        write_record(directory, first, name="legacy-1.json")
        write_record(directory, dict(first, package_uid_private=UID + 1), name="legacy-2.json")
        current = self.journal_for_attempt(directory, fresh_baseline_admission=True)
        self.assertEqual(recovery._read_install_record(directory, q7.TARGET_REFERENCE)[0], current.latest)
        write_record(
            directory, cleanup_outcome(
                record_digest(directory / current.latest_filename),
                install_attempt_id=current.attempt_id, cleanup_attempt_id="f" * 32,
            ), name="untrusted-current-cleanup.json",
        )
        runner = LifecycleRunner()
        result = recovery.recover_installed_readiness_probe(
            directory, target_reference=q7.TARGET_REFERENCE, runner=runner,
        )
        self.assertEqual(result["failure_code"], "IntegrityConflict")
        self.assertEqual(runner.calls, [])

    def test_install_stops_before_payload_write_when_a_competing_session_appears(self):
        directory = self.private_directory()
        runner = LifecycleRunner()
        runner.competing_session_after_create = True
        payload = b"reviewed readiness apk bytes"
        digest = hashlib.sha256(payload).hexdigest()

        with mock.patch.object(adb_forward, "_READINESS_PROBE_APK_SHA256", digest):
            with self.assertRaises(probe.ProbeError) as raised:
                self.install_with_lifecycle_runner(
                    runner, directory, payload=payload, attempt_id="5" * 32
                )

        self.assertEqual(raised.exception.code, "IntegrityConflict")
        commands = [call[3:6] for call in runner.calls]
        self.assertEqual(commands.count(("shell", "pm", "install-create")), 1)
        self.assertEqual(commands.count(("shell", "pm", "install-write")), 0)
        self.assertEqual(commands.count(("shell", "pm", "install-commit")), 0)
        events = readiness_probe_install_journal.read_install_journal_events(
            directory, target_reference=q7.TARGET_REFERENCE
        )["5" * 32]
        self.assertEqual((events[-1]["state"], events[-1]["phase"]),
                         ("attempted", "session_created"))

    def test_recovery_blocks_unjournaled_present_package_and_writes_sanitized_outcome(self):
        directory = self.private_directory()
        write_record(directory, install_record())
        runner = self.runner_for_cleanup()

        result = recovery.recover_installed_readiness_probe(
            directory,
            target_reference=q7.TARGET_REFERENCE,
            runner=runner,
            utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
        )

        self.assertEqual(result["classification"], "blocked")
        self.assertEqual(result["failure_code"], "IntegrityConflict")
        self.assertEqual(result["target_reference"], q7.TARGET_REFERENCE)
        self.assertNotIn("cleanup_attempt_id", result)
        self.assertNotIn("install_attempt_id", result)
        self.assertNotIn("install_record_sha256", result)
        self.assertEqual(result["adb_command_total"], 4)
        self.assertEqual(result["adb_command_counts"]["package_uninstall"], 0)
        self.assertEqual(len(runner.calls), 4)
        self.assertEqual(
            sum(call[3:] == ("shell", "pm", "list", "users") for call in runner.calls),
            0,
        )
        self.assertFalse(any(call[4:6] == ("pm", "uninstall") for call in runner.calls))

        outcomes = []
        for path in directory.glob("*.json"):
            metadata = path.stat(follow_symlinks=False)
            if path.name == "install.json":
                continue
            self.assertEqual(metadata.st_mode & 0o777, 0o600)
            self.assertEqual(metadata.st_uid, os.getuid())
            outcomes.append(json.loads(path.read_text()))
        self.assertEqual(len(outcomes), 1)
        serialized = json.dumps(outcomes[0], sort_keys=True)
        self.assertNotIn('"serial"', serialized)
        self.assertNotIn('"build_fingerprint"', serialized)
        self.assertNotIn('"package_uid_private"', serialized)
        self.assertFalse(outcomes[0]["qualification_assertions_passed"])
        self.assertEqual(
            outcomes[0]["install_record_sha256"],
            record_digest(directory / "install.json"),
        )
        self.assertRegex(outcomes[0]["cleanup_attempt_id"], r"^[0-9a-f]{32}$")

    def test_each_install_persistence_boundary_stops_the_next_mutation(self):
        checkpoints = (
            ("pending", "before_install", []),
            ("attempted", "create_started", []),
            ("attempted", "session_created", ["install-create"]),
            ("attempted", "write_started", ["install-create"]),
            ("attempted", "payload_written", ["install-create", "install-write"]),
            ("attempted", "commit_started", ["install-create", "install-write"]),
            (
                "completed",
                "installed",
                ["install-create", "install-write", "install-commit"],
            ),
        )
        payload = b"reviewed readiness apk bytes"
        digest = hashlib.sha256(payload).hexdigest()

        for index, (target_state, target_phase, expected) in enumerate(checkpoints):
            for mode in ("before", "after"):
                with self.subTest(
                    checkpoint=(target_state, target_phase), mode=mode
                ):
                    directory = self.private_directory()
                    runner = LifecycleRunner()
                    attempt_id = f"{index + 1:032x}"

                    class FaultingJournal(
                        readiness_probe_install_journal.ReadinessInstallJournal
                    ):
                        def _append(self, record):
                            if (
                                (target_state, target_phase)
                                == ("pending", "before_install")
                                and record.get("state") == "pending"
                            ):
                                if mode == "after":
                                    super()._append(record)
                                raise probe.ProbeError("IncompleteEvidence", "Transport")
                            return super()._append(record)

                        def checkpoint(self, state, phase, **kwargs):
                            if (state, phase) == (target_state, target_phase):
                                if mode == "after":
                                    super().checkpoint(state, phase, **kwargs)
                                raise probe.ProbeError("IncompleteEvidence", "Transport")
                            return super().checkpoint(state, phase, **kwargs)

                    with mock.patch.object(
                        adb_forward, "_READINESS_PROBE_APK_SHA256", digest
                    ), mock.patch.object(
                        readiness_probe_install_journal,
                        "ReadinessInstallJournal",
                        FaultingJournal,
                    ):
                        with self.assertRaises(probe.ProbeError):
                            self.install_with_lifecycle_runner(
                                runner,
                                directory,
                                payload=payload,
                                attempt_id=attempt_id,
                            )

                    actual = [
                        call[5]
                        for call in runner.calls
                        if call[3:5] == ("shell", "pm")
                        and call[5] in {
                            "install-create", "install-write", "install-commit"
                        }
                    ]
                    self.assertEqual(actual, expected)

    def test_install_command_faults_reconcile_only_known_sessions(self):
        cases = (
            ("install-create", "before", "cleanup_complete", "already_absent", 0, 0),
            ("install-create", "after", "blocked", None, 0, 0),
            ("install-write", "before", "cleanup_complete", "already_absent", 1, 0),
            ("install-write", "after", "cleanup_complete", "already_absent", 1, 0),
            ("install-commit", "before", "cleanup_complete", "already_absent", 1, 0),
            ("install-commit", "after", "cleanup_complete", "uninstalled", 0, 1),
        )
        payload = b"reviewed readiness apk bytes"
        digest = hashlib.sha256(payload).hexdigest()

        with mock.patch.object(adb_forward, "_READINESS_PROBE_APK_SHA256", digest):
            for index, (command, point, classification, cleanup_state,
                        abandon_count, uninstall_count) in enumerate(cases, start=1):
                with self.subTest(command=command, point=point):
                    directory = self.private_directory()
                    runner = LifecycleRunner(
                        fail_command=command, failure_point=point
                    )
                    attempt_id = f"{index + 10:032x}"
                    with self.assertRaises(probe.ProbeError):
                        self.install_with_lifecycle_runner(
                            runner,
                            directory,
                            payload=payload,
                            attempt_id=attempt_id,
                        )

                    result = recovery.recover_installed_readiness_probe(
                        directory,
                        target_reference=q7.TARGET_REFERENCE,
                        runner=runner,
                        utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
                    )

                    self.assertEqual(result["classification"], classification)
                    self.assertEqual(result["cleanup_state"], cleanup_state)
                    self.assertEqual(
                        result["adb_command_counts"]["install_abandon"], abandon_count
                    )
                    self.assertEqual(
                        result["adb_command_counts"]["package_uninstall"],
                        uninstall_count,
                    )

    def test_lost_install_create_response_leaves_unknown_session_unowned(self):
        directory = self.private_directory()
        runner = LifecycleRunner(
            fail_command="install-create", failure_point="after"
        )
        payload = b"reviewed readiness apk bytes"
        digest = hashlib.sha256(payload).hexdigest()

        with mock.patch.object(adb_forward, "_READINESS_PROBE_APK_SHA256", digest):
            with self.assertRaises(probe.ProbeError):
                self.install_with_lifecycle_runner(
                    runner, directory, payload=payload, attempt_id="e" * 32
                )
            result = recovery.recover_installed_readiness_probe(
                directory,
                target_reference=q7.TARGET_REFERENCE,
                runner=runner,
                utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
            )

        self.assertEqual(result["classification"], "blocked")
        self.assertEqual(result["failure_code"], "IntegrityConflict")
        self.assertFalse(any(
            call[3:6] == ("shell", "pm", "install-abandon")
            for call in runner.calls
        ))
        self.assertFalse(any(
            call[3:6] == ("shell", "pm", "uninstall")
            for call in runner.calls
        ))

    def test_known_session_after_write_timeout_is_abandoned_without_package_uninstall(self):
        directory = self.private_directory()
        runner = LifecycleRunner(
            fail_command="install-write", failure_point="after"
        )
        payload = b"reviewed readiness apk bytes"
        digest = hashlib.sha256(payload).hexdigest()

        with mock.patch.object(adb_forward, "_READINESS_PROBE_APK_SHA256", digest):
            with self.assertRaises(probe.ProbeError):
                self.install_with_lifecycle_runner(
                    runner, directory, payload=payload, attempt_id="f" * 32
                )
            result = recovery.recover_installed_readiness_probe(
                directory,
                target_reference=q7.TARGET_REFERENCE,
                runner=runner,
                utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
            )

        self.assertEqual(result["classification"], "cleanup_complete")
        self.assertEqual(result["cleanup_state"], "already_absent")
        self.assertEqual(result["adb_command_counts"]["install_abandon"], 1)
        self.assertEqual(result["adb_command_counts"]["package_uninstall"], 0)

    def test_commit_timeout_recovers_only_the_matching_installed_artifact(self):
        directory = self.private_directory()
        runner = LifecycleRunner(
            fail_command="install-commit", failure_point="after"
        )
        payload = b"reviewed readiness apk bytes"
        digest = hashlib.sha256(payload).hexdigest()

        with mock.patch.object(adb_forward, "_READINESS_PROBE_APK_SHA256", digest):
            with self.assertRaises(probe.ProbeError):
                self.install_with_lifecycle_runner(
                    runner, directory, payload=payload, attempt_id="1" * 32
                )
            result = recovery.recover_installed_readiness_probe(
                directory,
                target_reference=q7.TARGET_REFERENCE,
                runner=runner,
                utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
            )

        self.assertEqual(result["classification"], "cleanup_complete")
        self.assertEqual(result["failure_code"], None)
        self.assertEqual(result["cleanup_state"], "uninstalled")
        self.assertEqual(result["adb_command_counts"]["package_uninstall"], 1)
        self.assertFalse(runner.package_present)

    def test_failed_cleanup_intent_prevents_uninstall(self):
        directory = self.private_directory()
        runner = LifecycleRunner()
        payload = b"reviewed readiness apk bytes"
        digest = hashlib.sha256(payload).hexdigest()

        with mock.patch.object(adb_forward, "_READINESS_PROBE_APK_SHA256", digest):
            adapter, _, _ = self.install_with_lifecycle_runner(
                runner, directory, payload=payload
            )
            with mock.patch.object(
                readiness_probe_install_journal._evidence_storage,
                "_publish_no_replace",
                side_effect=OSError,
            ):
                with self.assertRaises(probe.ProbeError):
                    adapter.uninstall_readiness_probe(TARGET, deadline=time.monotonic() + 60)
        self.assertTrue(runner.package_present)
        self.assertFalse(any(call[3:6] == ("shell", "pm", "uninstall") for call in runner.calls))

    def test_present_package_uninstall_interruptions_leave_durable_intent(self):
        payload = b"reviewed readiness apk bytes"
        digest = hashlib.sha256(payload).hexdigest()
        for point in ("before", "after"):
            with self.subTest(point=point):
                directory = self.private_directory()
                runner = LifecycleRunner(fail_command="uninstall", failure_point=point)
                with mock.patch.object(adb_forward, "_READINESS_PROBE_APK_SHA256", digest):
                    adapter, _, _ = self.install_with_lifecycle_runner(
                        runner, directory, payload=payload, attempt_id="2" * 32
                    )
                    with self.assertRaises(probe.ProbeError):
                        adapter.uninstall_readiness_probe(TARGET, deadline=time.monotonic() + 60)
                    events = readiness_probe_install_journal.read_install_journal_events(
                        directory, target_reference=q7.TARGET_REFERENCE
                    )["2" * 32]
                    self.assertEqual(events[-1]["phase"], "cleanup_started")
                    self.assertEqual(runner.package_present, point == "before")
                    recovered = recovery.recover_installed_readiness_probe(
                        directory, target_reference=q7.TARGET_REFERENCE, runner=runner
                    )
                    self.assertEqual(recovered["classification"], "cleanup_complete")
                    self.assertEqual(recovered["adb_command_counts"]["package_uninstall"],
                                     int(point == "before"))
                    self.assertFalse(runner.package_present)

    def test_recovery_stops_when_recorded_android_user_is_not_active(self):
        directory = self.private_directory()
        write_record(directory, install_record())
        runner = self.runner_for_cleanup(user=b"11\n")

        result = recovery.recover_installed_readiness_probe(
            directory,
            target_reference=q7.TARGET_REFERENCE,
            runner=runner,
            utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
        )

        self.assertEqual(result["classification"], "blocked")
        self.assertEqual(result["failure_code"], "IntegrityConflict")
        self.assertEqual(len(runner.calls), 3)
        self.assertFalse(
            any(call[4:6] == ("pm", "uninstall") for call in runner.calls)
        )

    def test_recovery_stops_when_current_build_differs_from_private_record(self):
        directory = self.private_directory()
        write_record(directory, install_record())
        runner = FakeRunner(
            [
                b"device\n",
                b"brand/device:version/id/other:user/release-keys\n",
            ]
        )

        result = recovery.recover_installed_readiness_probe(
            directory,
            target_reference=q7.TARGET_REFERENCE,
            runner=runner,
            utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
        )

        self.assertEqual(result["classification"], "blocked")
        self.assertEqual(result["failure_code"], "IntegrityConflict")
        self.assertEqual(len(runner.calls), 2)

    def test_recovery_stops_when_installed_version_differs_from_the_pin(self):
        directory = self.private_directory()
        write_record(directory, install_record())
        package = readiness_probe_artifact.PACKAGE
        runner = self.runner_for_cleanup(
            package_state=f"package:{package} versionCode:2 uid:{UID}\n".encode(
                "ascii"
            )
        )

        result = recovery.recover_installed_readiness_probe(
            directory,
            target_reference=q7.TARGET_REFERENCE,
            runner=runner,
            utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
        )

        self.assertEqual(result["classification"], "blocked")
        self.assertEqual(result["failure_code"], "IntegrityConflict")
        self.assertEqual(len(runner.calls), 4)
        self.assertFalse(
            any(call[3:] == ("shell", "pm", "list", "users") for call in runner.calls)
        )
        self.assertFalse(
            any(call[4:6] == ("pm", "uninstall") for call in runner.calls)
        )

    def test_recovery_stops_before_adb_when_record_digest_differs_from_pin(self):
        directory = self.private_directory()
        record = install_record()
        record["artifact"]["sha256"] = "0" * 64
        write_record(directory, record)
        runner = self.runner_for_cleanup(package_state=b"")

        result = recovery.recover_installed_readiness_probe(
            directory,
            target_reference=q7.TARGET_REFERENCE,
            runner=runner,
            utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
        )

        self.assertEqual(result["classification"], "blocked")
        self.assertEqual(result["failure_code"], "IntegrityConflict")
        self.assertEqual(runner.calls, [])

    def test_recovery_stops_when_the_installed_uid_differs_from_the_record(self):
        directory = self.private_directory()
        write_record(directory, install_record())
        package = readiness_probe_artifact.PACKAGE
        runner = self.runner_for_cleanup(
            package_state=f"package:{package} versionCode:1 uid:10124\n".encode(
                "ascii"
            )
        )

        result = recovery.recover_installed_readiness_probe(
            directory,
            target_reference=q7.TARGET_REFERENCE,
            runner=runner,
            utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
        )

        self.assertEqual(result["classification"], "blocked")
        self.assertEqual(result["failure_code"], "IntegrityConflict")
        self.assertEqual(len(runner.calls), 4)
        self.assertFalse(
            any(call[3:] == ("shell", "pm", "list", "users") for call in runner.calls)
        )
        self.assertFalse(
            any(call[4:6] == ("pm", "uninstall") for call in runner.calls)
        )

    def test_recovery_rejects_ambiguous_install_records_before_adb(self):
        directory = self.private_directory()
        write_record(directory, install_record(), name="install-one.json")
        write_record(directory, install_record(), name="install-two.json")
        runner = self.runner_for_cleanup()

        result = recovery.recover_installed_readiness_probe(
            directory,
            target_reference=q7.TARGET_REFERENCE,
            runner=runner,
            utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
        )

        self.assertEqual(result["classification"], "blocked")
        self.assertEqual(result["failure_code"], "IntegrityConflict")
        self.assertEqual(runner.calls, [])

    def test_recovery_does_not_resolve_legacy_records_without_lineage(self):
        directory = self.private_directory()
        write_record(directory, legacy_install_record(), name="old-install.json")
        current = legacy_install_record()
        current["acquired_at_utc"] = "2026-11-22T12:47:34Z"
        write_record(directory, current, name="current-install.json")
        write_record(
            directory,
            {
                "schema": "argus-issue-74-b1-cleanup-recovery-v1",
                "target_reference": q7.TARGET_REFERENCE,
                "classification": "cleanup_complete",
                "failure_code": None,
                "cleanup_state": "uninstalled",
                "readback_state": "absent",
                "finished_at_utc": "2026-11-22T12:47:33Z",
                "source_identity": {
                    "adb_forward_sha256": "a" * 64,
                    "recovery_sha256": "b" * 64,
                },
                "raw_output_retained": False,
                "stdout_retained": False,
                "stderr_retained": False,
                "qualification_assertions_passed": False,
            },
            name="completed-cleanup.json",
        )
        runner = self.runner_for_cleanup()

        result = recovery.recover_installed_readiness_probe(
            directory,
            target_reference=q7.TARGET_REFERENCE,
            runner=runner,
            utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
        )

        self.assertEqual(result["classification"], "blocked")
        self.assertEqual(result["failure_code"], "IntegrityConflict")
        self.assertEqual(runner.calls, [])

    def test_recovery_selects_a_new_install_record_after_old_cleanup(self):
        directory = self.private_directory()
        old = install_record("a" * 32)
        old["acquired_at_utc"] = "2026-11-22T12:47:30.12345Z"
        old_path = write_record(directory, old, name="old-install.json")
        write_record(
            directory,
            cleanup_outcome(
                record_digest(old_path),
                cleanup_attempt_id="1" * 32,
                install_attempt_id=old["install_attempt_id"],
            ),
            name="completed-cleanup.json",
        )
        new = install_record("b" * 32)
        new["acquired_at_utc"] = "2026-11-22T12:47:34Z"
        write_record(directory, new, name="new-install.json")
        runner = self.runner_for_cleanup(package_state=b"")

        result = recovery.recover_installed_readiness_probe(
            directory,
            target_reference=q7.TARGET_REFERENCE,
            runner=runner,
            utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
        )

        self.assertEqual(result["classification"], "cleanup_complete")
        self.assertEqual(result["cleanup_state"], "already_absent")
        self.assertEqual(len(runner.calls), 5)
        self.assertEqual(
            sum(call[3:] == ("shell", "pm", "list", "users") for call in runner.calls),
            1,
        )
        self.assertFalse(any(call[4:6] == ("pm", "uninstall") for call in runner.calls))
        current_outcome = next(
            json.loads(path.read_text())
            for path in directory.glob("*.json")
            if path.name != "old-install.json"
            and path.name != "new-install.json"
            and json.loads(path.read_text()).get("install_attempt_id")
            == new["install_attempt_id"]
        )
        self.assertEqual(
            current_outcome["install_record_sha256"], record_digest(directory / "new-install.json")
        )

    def test_recovery_selects_new_install_after_unique_legacy_cleanup(self):
        directory = self.private_directory()
        old = legacy_install_record()
        old.pop("acquired_at_utc")
        old_path = write_record(directory, old, name="legacy-install.json")
        write_record(
            directory,
            cleanup_outcome(
                record_digest(old_path), cleanup_attempt_id="b" * 32
            ),
            name="legacy-cleanup.json",
        )
        new = install_record("b" * 32)
        new["acquired_at_utc"] = "2026-11-22T12:47:34Z"
        write_record(directory, new, name="new-install.json")
        runner = self.runner_for_cleanup(package_state=b"")

        result = recovery.recover_installed_readiness_probe(
            directory,
            target_reference=q7.TARGET_REFERENCE,
            runner=runner,
            utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
        )

        self.assertEqual(result["classification"], "cleanup_complete")
        self.assertEqual(result["cleanup_state"], "already_absent")
        self.assertEqual(len(runner.calls), 5)
        self.assertEqual(
            sum(call[3:] == ("shell", "pm", "list", "users") for call in runner.calls),
            1,
        )
        self.assertFalse(any(call[4:6] == ("pm", "uninstall") for call in runner.calls))
        current_outcome = next(
            json.loads(path.read_text())
            for path in directory.glob("*.json")
            if path.name not in {"legacy-install.json", "new-install.json"}
            and json.loads(path.read_text()).get("install_attempt_id")
            == new["install_attempt_id"]
        )
        self.assertEqual(
            current_outcome["install_record_sha256"], record_digest(directory / "new-install.json")
        )

    def test_recovery_blocks_near_duplicate_legacy_install_after_cleanup(self):
        directory = self.private_directory()
        old = legacy_install_record()
        old_path = write_record(directory, old, name="old-install.json")
        duplicate = legacy_install_record()
        duplicate["acquired_at_utc"] = "2026-11-22T12:48:30Z"
        write_record(directory, duplicate, name="near-duplicate-install.json")
        write_record(
            directory,
            cleanup_outcome(
                record_digest(old_path), cleanup_attempt_id="c" * 32
            ),
            name="completed-cleanup.json",
        )
        runner = self.runner_for_cleanup(package_state=b"")

        result = recovery.recover_installed_readiness_probe(
            directory,
            target_reference=q7.TARGET_REFERENCE,
            runner=runner,
            utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
        )

        self.assertEqual(result["classification"], "blocked")
        self.assertEqual(result["failure_code"], "IntegrityConflict")
        self.assertEqual(runner.calls, [])

    def test_recovery_blocks_duplicate_install_attempt_ids_after_cleanup(self):
        directory = self.private_directory()
        old = install_record("c" * 32)
        old_path = write_record(directory, old, name="old-install.json")
        duplicate = install_record("c" * 32)
        duplicate["acquired_at_utc"] = "2026-11-22T12:48:30Z"
        write_record(directory, duplicate, name="near-duplicate-install.json")
        write_record(
            directory,
            cleanup_outcome(
                record_digest(old_path),
                cleanup_attempt_id="d" * 32,
                install_attempt_id=old["install_attempt_id"],
            ),
            name="completed-cleanup.json",
        )
        runner = self.runner_for_cleanup()

        result = recovery.recover_installed_readiness_probe(
            directory,
            target_reference=q7.TARGET_REFERENCE,
            runner=runner,
            utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
        )

        self.assertEqual(result["classification"], "blocked")
        self.assertEqual(result["failure_code"], "IntegrityConflict")
        self.assertEqual(runner.calls, [])

    def test_recovery_uses_exact_record_digest_when_file_timestamps_tie(self):
        directory = self.private_directory()
        old = install_record("a" * 32)
        old["acquired_at_utc"] = "2026-11-22T12:47:30.12345Z"
        old_path = write_record(directory, old, name="old-install.json")
        cleanup = cleanup_outcome(
            record_digest(old_path),
            cleanup_attempt_id="2" * 32,
            install_attempt_id=old["install_attempt_id"],
        )
        write_record(directory, cleanup, name="completed-cleanup.json")
        current = install_record("b" * 32)
        current["acquired_at_utc"] = "2026-11-22T12:47:34Z"
        current_path = write_record(directory, current, name="current-install.json")
        runner = self.runner_for_cleanup(package_state=b"")

        original_stat = recovery._stat_private_entry

        def tied_stat(directory_fd, name):
            observed = original_stat(directory_fd, name)
            return SimpleNamespace(
                st_mode=observed.st_mode,
                st_uid=observed.st_uid,
                st_nlink=observed.st_nlink,
                st_size=observed.st_size,
                st_ctime_ns=1,
                st_mtime_ns=1,
            )

        with mock.patch.object(recovery, "_stat_private_entry", side_effect=tied_stat):
            result = recovery.recover_installed_readiness_probe(
                directory,
                target_reference=q7.TARGET_REFERENCE,
                runner=runner,
                utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
            )

        self.assertEqual(result["classification"], "cleanup_complete")
        self.assertEqual(result["cleanup_state"], "already_absent")
        self.assertEqual(len(runner.calls), 5)
        self.assertEqual(
            sum(call[3:] == ("shell", "pm", "list", "users") for call in runner.calls),
            1,
        )
        cleanup_records = [
            json.loads(path.read_text(encoding="utf-8"))
            for path in pathlib.Path(directory).glob("*.json")
            if path.name != "old-install.json"
            and path.name != "current-install.json"
        ]
        current_cleanup = next(
            item
            for item in cleanup_records
            if item.get("install_record_sha256") == record_digest(current_path)
        )
        self.assertEqual(
            current_cleanup["install_attempt_id"], current["install_attempt_id"]
        )

    def test_recovery_does_not_resolve_an_install_from_an_unrelated_cleanup(self):
        directory = self.private_directory()
        write_record(directory, install_record())
        write_record(
            directory,
            cleanup_outcome("c" * 64, cleanup_attempt_id="f" * 32),
            name="unrelated-cleanup.json",
        )
        runner = self.runner_for_cleanup(package_state=b"")

        result = recovery.recover_installed_readiness_probe(
            directory,
            target_reference=q7.TARGET_REFERENCE,
            runner=runner,
            utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
        )

        self.assertEqual(result["classification"], "cleanup_complete")
        self.assertEqual(result["cleanup_state"], "already_absent")
        self.assertEqual(len(runner.calls), 5)
        self.assertEqual(
            sum(call[3:] == ("shell", "pm", "list", "users") for call in runner.calls),
            1,
        )

    def test_recovery_blocks_conflicting_cleanup_attempt_identities(self):
        directory = self.private_directory()
        install_path = write_record(directory, install_record())
        install_digest = record_digest(install_path)
        write_record(
            directory,
            cleanup_outcome(install_digest, cleanup_attempt_id="9" * 32),
            name="cleanup-one.json",
        )
        write_record(
            directory,
            cleanup_outcome("d" * 64, cleanup_attempt_id="9" * 32),
            name="cleanup-two.json",
        )
        runner = self.runner_for_cleanup()

        result = recovery.recover_installed_readiness_probe(
            directory,
            target_reference=q7.TARGET_REFERENCE,
            runner=runner,
            utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
        )

        self.assertEqual(result["classification"], "blocked")
        self.assertEqual(result["failure_code"], "IntegrityConflict")
        self.assertEqual(runner.calls, [])

    def test_recovery_blocks_multiple_successful_cleanups_for_one_install(self):
        directory = self.private_directory()
        install_path = write_record(directory, install_record())
        install_digest = record_digest(install_path)
        write_record(
            directory,
            cleanup_outcome(
                install_digest,
                cleanup_attempt_id="1" * 32,
                install_attempt_id="a" * 32,
            ),
            name="cleanup-one.json",
        )
        write_record(
            directory,
            cleanup_outcome(
                install_digest,
                cleanup_attempt_id="2" * 32,
                install_attempt_id="a" * 32,
            ),
            name="cleanup-two.json",
        )
        runner = self.runner_for_cleanup()

        result = recovery.recover_installed_readiness_probe(
            directory,
            target_reference=q7.TARGET_REFERENCE,
            runner=runner,
            utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
        )

        self.assertEqual(result["classification"], "blocked")
        self.assertEqual(result["failure_code"], "IntegrityConflict")
        self.assertEqual(runner.calls, [])

    def test_recovery_rejects_successful_new_cleanup_without_install_lineage(self):
        directory = self.private_directory()
        write_record(directory, install_record())
        cleanup = cleanup_outcome("e" * 64, cleanup_attempt_id="8" * 32)
        cleanup.pop("install_record_sha256")
        write_record(directory, cleanup, name="missing-lineage-cleanup.json")
        runner = self.runner_for_cleanup()

        result = recovery.recover_installed_readiness_probe(
            directory,
            target_reference=q7.TARGET_REFERENCE,
            runner=runner,
            utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
        )

        self.assertEqual(result["classification"], "blocked")
        self.assertEqual(result["failure_code"], "IncompleteEvidence")
        self.assertEqual(runner.calls, [])

    def test_recovery_rejects_successful_v2_cleanup_without_install_attempt_id(self):
        directory = self.private_directory()
        install_path = write_record(directory, install_record())
        cleanup = cleanup_outcome(
            record_digest(install_path),
            cleanup_attempt_id="8" * 32,
            install_attempt_id="a" * 32,
        )
        cleanup.pop("install_attempt_id")
        write_record(directory, cleanup, name="missing-install-id-cleanup.json")
        runner = self.runner_for_cleanup()

        result = recovery.recover_installed_readiness_probe(
            directory,
            target_reference=q7.TARGET_REFERENCE,
            runner=runner,
            utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
        )

        self.assertEqual(result["classification"], "blocked")
        self.assertEqual(result["failure_code"], "IncompleteEvidence")
        self.assertEqual(runner.calls, [])

    def test_recovery_blocks_valid_install_digest_with_wrong_attempt_id(self):
        directory = self.private_directory()
        install_path = write_record(directory, install_record("a" * 32))
        write_record(
            directory,
            cleanup_outcome(
                record_digest(install_path),
                cleanup_attempt_id="8" * 32,
                install_attempt_id="b" * 32,
            ),
            name="wrong-install-attempt-id.json",
        )
        runner = self.runner_for_cleanup()

        result = recovery.recover_installed_readiness_probe(
            directory,
            target_reference=q7.TARGET_REFERENCE,
            runner=runner,
            utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
        )

        self.assertEqual(result["classification"], "blocked")
        self.assertEqual(result["failure_code"], "IntegrityConflict")
        self.assertEqual(runner.calls, [])

    def test_recovery_blocks_valid_attempt_id_with_wrong_install_digest(self):
        directory = self.private_directory()
        write_record(directory, install_record("a" * 32))
        write_record(
            directory,
            cleanup_outcome(
                "d" * 64,
                cleanup_attempt_id="8" * 32,
                install_attempt_id="a" * 32,
            ),
            name="wrong-install-record-digest.json",
        )
        runner = self.runner_for_cleanup()

        result = recovery.recover_installed_readiness_probe(
            directory,
            target_reference=q7.TARGET_REFERENCE,
            runner=runner,
            utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
        )

        self.assertEqual(result["classification"], "blocked")
        self.assertEqual(result["failure_code"], "IntegrityConflict")
        self.assertEqual(runner.calls, [])

    def test_recovery_blocks_duplicate_cleanup_ids_across_targets(self):
        directory = self.private_directory()
        install_path = write_record(directory, install_record())
        cleanup_id = "9" * 32
        current_target_cleanup = cleanup_outcome(
            record_digest(install_path),
            cleanup_attempt_id=cleanup_id,
            install_attempt_id="a" * 32,
        )
        current_target_cleanup["classification"] = "blocked"
        current_target_cleanup["failure_code"] = "IntegrityConflict"
        current_target_cleanup["cleanup_state"] = None
        current_target_cleanup["readback_state"] = None
        write_record(
            directory, current_target_cleanup, name="current-target-outcome.json"
        )
        other_target_cleanup = cleanup_outcome(
            "d" * 64,
            cleanup_attempt_id=cleanup_id,
            install_attempt_id="b" * 32,
        )
        other_target_cleanup["target_reference"] = "i74-tgt-0000000000000000"
        write_record(directory, other_target_cleanup, name="other-target-outcome.json")
        runner = self.runner_for_cleanup()

        result = recovery.recover_installed_readiness_probe(
            directory,
            target_reference=q7.TARGET_REFERENCE,
            runner=runner,
            utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
        )

        self.assertEqual(result["classification"], "blocked")
        self.assertEqual(result["failure_code"], "IntegrityConflict")
        self.assertEqual(runner.calls, [])

    def test_recovery_rejects_multiple_legacy_records_before_cleanup(self):
        directory = self.private_directory()
        first = legacy_install_record()
        first.pop("acquired_at_utc")
        second = legacy_install_record()
        second.pop("acquired_at_utc")
        write_record(directory, first, name="legacy-install-one.json")
        write_record(directory, second, name="legacy-install-two.json")
        write_record(
            directory,
            {
                "schema": "argus-issue-74-b1-cleanup-recovery-v1",
                "target_reference": q7.TARGET_REFERENCE,
                "classification": "cleanup_complete",
                "failure_code": None,
                "cleanup_state": "uninstalled",
                "readback_state": "absent",
                "finished_at_utc": "2026-11-22T12:47:33Z",
                "source_identity": {
                    "adb_forward_sha256": "a" * 64,
                    "recovery_sha256": "b" * 64,
                },
                "raw_output_retained": False,
                "stdout_retained": False,
                "stderr_retained": False,
                "qualification_assertions_passed": False,
            },
            name="legacy-cleanup.json",
        )
        runner = self.runner_for_cleanup()

        result = recovery.recover_installed_readiness_probe(
            directory,
            target_reference=q7.TARGET_REFERENCE,
            runner=runner,
            utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
        )

        self.assertEqual(result["classification"], "blocked")
        self.assertEqual(result["failure_code"], "IntegrityConflict")
        self.assertEqual(runner.calls, [])

    def test_recovery_rejects_noncanonical_install_timestamp_before_adb(self):
        directory = self.private_directory()
        record = install_record()
        record["acquired_at_utc"] = "2026-11-22T12:47:30+00:00"
        write_record(directory, record)
        write_record(
            directory,
            {
                "schema": "argus-issue-74-b1-cleanup-recovery-v1",
                "target_reference": q7.TARGET_REFERENCE,
                "classification": "cleanup_complete",
                "failure_code": None,
                "cleanup_state": "uninstalled",
                "readback_state": "absent",
                "finished_at_utc": "2026-11-22T12:47:33Z",
                "source_identity": {
                    "adb_forward_sha256": "a" * 64,
                    "recovery_sha256": "b" * 64,
                },
                "raw_output_retained": False,
                "stdout_retained": False,
                "stderr_retained": False,
                "qualification_assertions_passed": False,
            },
            name="later-cleanup.json",
        )
        runner = self.runner_for_cleanup()

        result = recovery.recover_installed_readiness_probe(
            directory,
            target_reference=q7.TARGET_REFERENCE,
            runner=runner,
            utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
        )

        self.assertEqual(result["classification"], "blocked")
        self.assertEqual(result["failure_code"], "IncompleteEvidence")
        self.assertEqual(runner.calls, [])

    def test_recovery_blocks_noncanonical_legacy_record_without_lineage(self):
        directory = self.private_directory()
        write_record(
            directory,
            {
                "schema": "argus-issue-74-b1-cleanup-recovery-v1",
                "target_reference": q7.TARGET_REFERENCE,
                "classification": "cleanup_complete",
                "failure_code": None,
                "cleanup_state": "uninstalled",
                "readback_state": "absent",
                "finished_at_utc": "2026-11-22T12:47:33Z",
                "source_identity": {
                    "adb_forward_sha256": "a" * 64,
                    "recovery_sha256": "b" * 64,
                },
                "raw_output_retained": False,
                "stdout_retained": False,
                "stderr_retained": False,
                "qualification_assertions_passed": False,
            },
            name="completed-cleanup.json",
        )
        old = legacy_install_record()
        old["acquired_at_utc"] = "2026-11-22T12:47:30.12345Z"
        write_record(directory, old, name="old-install.json")
        current = legacy_install_record()
        current["acquired_at_utc"] = "2026-11-22T12:47:34Z"
        write_record(directory, current, name="current-install.json")
        runner = self.runner_for_cleanup()

        result = recovery.recover_installed_readiness_probe(
            directory,
            target_reference=q7.TARGET_REFERENCE,
            runner=runner,
            utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
        )

        self.assertEqual(result["classification"], "blocked")
        self.assertEqual(result["failure_code"], "IncompleteEvidence")
        self.assertEqual(runner.calls, [])

    def test_v1_millisecond_timestamp_preserves_record_bytes_and_ownership(self):
        directory = self.private_directory()
        old = legacy_install_record()
        old["acquired_at_utc"] = "2026-11-22T12:47:30.123Z"
        original = write_record(directory, old, name="legacy-install.json")
        expected_digest = record_digest(original)
        record, digest, attempt = recovery._read_install_record(directory, q7.TARGET_REFERENCE)
        self.assertEqual((record, digest, attempt), (old, expected_digest, None))

        current = legacy_install_record()
        current["acquired_at_utc"] = "2026-11-22T12:47:34Z"
        write_record(directory, current, name="second-install.json")
        with self.assertRaises(recovery.ProbeError) as error:
            recovery._read_install_record(directory, q7.TARGET_REFERENCE, allow_no_active=True)
        self.assertEqual(error.exception.code, "IntegrityConflict")
        self.assertEqual(record_digest(original), expected_digest)

    def test_v1_timestamp_compatibility_is_limited_to_three_utc_fraction_digits(self):
        for value in (
            "2026-02-30T12:47:30.123Z",
            "2026-11-22T12:47:30.12Z",
            "2026-11-22T12:47:30.1234Z",
            "2026-11-22T12:47:30.123+00:00",
        ):
            with self.subTest(value=value):
                record = legacy_install_record()
                record["acquired_at_utc"] = value
                self.assertFalse(recovery._valid_install_record(record, q7.TARGET_REFERENCE))
        record = install_record()
        record["acquired_at_utc"] = "2026-11-22T12:47:30.123Z"
        self.assertFalse(recovery._valid_install_record(record, q7.TARGET_REFERENCE))

    def test_recovery_rejects_incomplete_success_outcome_before_adb(self):
        directory = self.private_directory()
        write_record(directory, install_record())
        write_record(
            directory,
            {
                "schema": "argus-issue-74-b1-cleanup-recovery-v1",
                "target_reference": q7.TARGET_REFERENCE,
                "classification": "cleanup_complete",
                "failure_code": None,
                "cleanup_state": "uninstalled",
                "readback_state": "absent",
                "finished_at_utc": "2026-11-22T12:47:33Z",
                "raw_output_retained": False,
                "stdout_retained": False,
                "stderr_retained": False,
                "qualification_assertions_passed": True,
            },
            name="incomplete-cleanup.json",
        )
        runner = self.runner_for_cleanup()

        result = recovery.recover_installed_readiness_probe(
            directory,
            target_reference=q7.TARGET_REFERENCE,
            runner=runner,
            utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
        )

        self.assertEqual(result["classification"], "blocked")
        self.assertEqual(result["failure_code"], "IncompleteEvidence")
        self.assertEqual(runner.calls, [])

    def test_recovery_rejects_truncated_cleanup_outcome_before_adb(self):
        directory = self.private_directory()
        write_record(directory, install_record())
        truncated_outcome = pathlib.Path(directory) / "truncated-cleanup.json"
        descriptor = os.open(
            truncated_outcome,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL,
            0o600,
        )
        try:
            os.write(
                descriptor,
                b'{"classification":"cleanup_complete",'
                b'"schema":"argus-issue-74-b1-cleanup-recovery-v1",',
            )
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
        runner = self.runner_for_cleanup()

        result = recovery.recover_installed_readiness_probe(
            directory,
            target_reference=q7.TARGET_REFERENCE,
            runner=runner,
            utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
        )

        self.assertEqual(result["classification"], "blocked")
        self.assertEqual(result["failure_code"], "IncompleteEvidence")
        self.assertEqual(runner.calls, [])

    def test_recovery_rejects_symlinked_outcome_entries_before_adb(self):
        directory = self.private_directory()
        source = write_record(directory, install_record())
        (directory / "other.json").symlink_to(source.name)
        runner = self.runner_for_cleanup()

        result = recovery.recover_installed_readiness_probe(
            directory,
            target_reference=q7.TARGET_REFERENCE,
            runner=runner,
            utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
        )

        self.assertEqual(result["classification"], "blocked")
        self.assertEqual(result["failure_code"], "UnauthorizedPeer")
        self.assertEqual(runner.calls, [])

    def test_recovery_rejects_non_private_install_record_before_adb(self):
        directory = self.private_directory()
        write_record(directory, install_record(), mode=0o640)
        runner = self.runner_for_cleanup()

        result = recovery.recover_installed_readiness_probe(
            directory,
            target_reference=q7.TARGET_REFERENCE,
            runner=runner,
            utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
        )

        self.assertEqual(result["classification"], "blocked")
        self.assertEqual(result["failure_code"], "UnauthorizedPeer")
        self.assertEqual(runner.calls, [])


if __name__ == "__main__":
    unittest.main()
