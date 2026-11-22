"""Host-only tests for recovering a pinned Readiness package cleanup."""

import json
import os
import pathlib
import tempfile
import unittest
from datetime import datetime, timezone

from . import adb_forward
from . import readiness_probe_artifact
from . import readiness_probe_recovery as recovery
from . import q7_exploratory_acquisition as q7


TARGET = "SERIAL-1"
BUILD = "brand/device:version/id/incremental:user/release-keys"
UID = 10123


class FakeRunner:
    def __init__(self, replies):
        self.replies = list(replies)
        self.calls = []

    def run(self, argv, deadline):
        self.calls.append(tuple(argv))
        if not self.replies:
            raise AssertionError("unexpected ADB command")
        return self.replies.pop(0)


def install_record():
    return {
        "schema": "argus-issue-74-b1-preparation-observation-v1",
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

    def test_recovery_cleans_pinned_package_and_writes_sanitized_private_outcome(self):
        directory = self.private_directory()
        write_record(directory, install_record())
        runner = self.runner_for_cleanup()

        result = recovery.recover_installed_readiness_probe(
            directory,
            target_reference=q7.TARGET_REFERENCE,
            runner=runner,
            utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
        )

        self.assertEqual(result["classification"], "cleanup_complete")
        self.assertEqual(result["target_reference"], q7.TARGET_REFERENCE)
        self.assertEqual(result["adb_command_total"], 6)
        self.assertEqual(result["adb_command_counts"]["package_uninstall"], 1)
        self.assertEqual(len(runner.calls), 6)
        self.assertEqual(
            runner.calls[-2],
            (
                "adb", "-s", TARGET, "shell", "pm", "uninstall", "--user",
                "10", readiness_probe_artifact.PACKAGE,
            ),
        )

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
            any(call[4:6] == ("pm", "uninstall") for call in runner.calls)
        )

    def test_recovery_stops_before_adb_when_record_digest_differs_from_pin(self):
        directory = self.private_directory()
        record = install_record()
        record["artifact"]["sha256"] = "0" * 64
        write_record(directory, record)
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

    def test_recovery_does_not_reuse_a_record_resolved_by_later_cleanup(self):
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
        old = install_record()
        old["acquired_at_utc"] = "2026-11-22T12:47:30.12345Z"
        old["package_uid_private"] = 10124
        write_record(directory, old, name="old-install.json")
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
        new = install_record()
        new["acquired_at_utc"] = "2026-11-22T12:47:34Z"
        write_record(directory, new, name="new-install.json")
        runner = self.runner_for_cleanup()

        result = recovery.recover_installed_readiness_probe(
            directory,
            target_reference=q7.TARGET_REFERENCE,
            runner=runner,
            utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
        )

        self.assertEqual(result["classification"], "cleanup_complete")
        self.assertEqual(len(runner.calls), 6)
        self.assertEqual(
            runner.calls[-2][4:6],
            ("pm", "uninstall"),
        )

    def test_recovery_selects_new_install_after_unique_legacy_cleanup(self):
        directory = self.private_directory()
        old = install_record()
        old.pop("acquired_at_utc")
        write_record(directory, old, name="legacy-install.json")
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
        new = install_record()
        new["acquired_at_utc"] = "2026-11-22T12:47:34Z"
        write_record(directory, new, name="new-install.json")
        runner = self.runner_for_cleanup()

        result = recovery.recover_installed_readiness_probe(
            directory,
            target_reference=q7.TARGET_REFERENCE,
            runner=runner,
            utc_clock=lambda: datetime(2026, 11, 22, tzinfo=timezone.utc),
        )

        self.assertEqual(result["classification"], "cleanup_complete")
        self.assertEqual(len(runner.calls), 6)
        self.assertEqual(runner.calls[-2][4:6], ("pm", "uninstall"))

    def test_recovery_rejects_multiple_legacy_records_before_cleanup(self):
        directory = self.private_directory()
        first = install_record()
        first.pop("acquired_at_utc")
        second = install_record()
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

    def test_recovery_requires_file_order_for_noncanonical_stale_record(self):
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
        old = install_record()
        old["acquired_at_utc"] = "2026-11-22T12:47:30.12345Z"
        write_record(directory, old, name="old-install.json")
        current = install_record()
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
