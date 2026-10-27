"""Integration tests for shell, Justfile, and legacy entrypoints."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
FRESH_WRAPPER = ROOT / "scripts" / "qualify_android_fresh.sh"
NO_RESET_WRAPPER = ROOT / "scripts" / "qualify_android_no_reset.sh"
ARCHIVE_MANIFEST = ROOT / "docs/archive/qualification/issue-21-v1/archive-manifest-v1.json"
_archive = json.loads(ARCHIVE_MANIFEST.read_text(encoding="utf-8"))
_retired_entry = next(
    entry for entry in _archive["entries"] if entry["role"] == "retired_entrypoint"
)
RETIRED_ENTRYPOINT = ROOT / _retired_entry["original_path"]


class EntrypointTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.directory = Path(self.temporary_directory.name)
        self.working_directory = self.directory / "arbitrary working directory"
        self.working_directory.mkdir()
        self.manifest_path = self.directory / "private qualification manifest.json"
        self.manifest_path.write_text(
            json.dumps(
                {
                    "schema_version": 1,
                    "authorization_ref": "authorization-synthetic",
                    "target_ref": "target-synthetic",
                    "artifact_ref": "artifact-synthetic",
                    "plan_ref": "plan-synthetic",
                    "scope_ref": "scope-synthetic",
                    "state_mode": "fresh",
                    "inherited_state_session_ref": None,
                }
            ),
            encoding="utf-8",
        )
        self.bin_directory = self.directory / "bin"
        self.bin_directory.mkdir()
        self.adb_marker = self.directory / "adb-invoked"
        adb = self.bin_directory / "adb"
        adb.write_text(
            "#!/bin/sh\nprintf invoked > \"$ARGUS_FAKE_ADB_MARKER\"\nexit 99\n",
            encoding="utf-8",
        )
        adb.chmod(0o755)
        self.environment = os.environ.copy()
        self.environment["PATH"] = (
            str(self.bin_directory) + os.pathsep + self.environment["PATH"]
        )
        self.environment["ARGUS_FAKE_ADB_MARKER"] = str(self.adb_marker)

    def _assert_no_adb(self) -> None:
        self.assertFalse(self.adb_marker.exists(), "new qualification path invoked ADB")

    def _run(self, command: list[str], timeout: int = 30) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            command,
            cwd=self.working_directory,
            env=self.environment,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )

    def test_canonical_justfile_entrypoints_work_from_arbitrary_directory(self) -> None:
        for recipe, flag in (
            ("qualify-android-fresh", "--dry-run"),
            ("qualify-android-fresh", "--preflight"),
            ("qualify-android-no-reset", "--dry-run"),
        ):
            with self.subTest(recipe=recipe, flag=flag):
                manifest_path = self.manifest_path
                if recipe == "qualify-android-no-reset":
                    manifest_path = self.directory / "no-reset manifest.json"
                    document = json.loads(self.manifest_path.read_text(encoding="utf-8"))
                    document["state_mode"] = "no-reset"
                    document["inherited_state_session_ref"] = "prior-session-synthetic"
                    manifest_path.write_text(json.dumps(document), encoding="utf-8")
                result = self._run(
                    [
                        "just",
                        "--justfile",
                        str(ROOT / "justfile"),
                        recipe,
                        str(manifest_path),
                        flag,
                    ]
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout)["status"], "HOST_VALIDATED")
                self._assert_no_adb()

    def test_shell_entrypoints_work_from_arbitrary_directory(self) -> None:
        for wrapper, flag in (
            (FRESH_WRAPPER, "--dry-run"),
            (FRESH_WRAPPER, "--preflight"),
            (NO_RESET_WRAPPER, "--dry-run"),
        ):
            with self.subTest(wrapper=wrapper.name, flag=flag):
                manifest_path = self.manifest_path
                if wrapper == NO_RESET_WRAPPER:
                    manifest_path = self.directory / "no-reset manifest.json"
                    document = json.loads(
                        self.manifest_path.read_text(encoding="utf-8")
                    )
                    document["state_mode"] = "no-reset"
                    document["inherited_state_session_ref"] = "prior-session-synthetic"
                    manifest_path.write_text(json.dumps(document), encoding="utf-8")
                result = self._run(
                    [
                        str(wrapper),
                        "--manifest",
                        str(manifest_path),
                        flag,
                    ]
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout)["status"], "HOST_VALIDATED")
                self._assert_no_adb()

    def test_entrypoint_state_modes_are_distinct(self) -> None:
        result = self._run(
            [
                "bash",
                str(NO_RESET_WRAPPER),
                "--manifest",
                str(self.manifest_path),
                "--dry-run",
            ]
        )
        self.assertEqual(result.returncode, 2)
        self.assertEqual(
            json.loads(result.stdout)["error"]["code"],
            "MANIFEST_STATE_MODE_MISMATCH",
        )
        self._assert_no_adb()

    def test_live_request_is_blocked_without_device_access(self) -> None:
        result = self._run(
            ["bash", str(FRESH_WRAPPER), "--manifest", str(self.manifest_path)]
        )
        self.assertEqual(result.returncode, 3)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["status"], "BLOCKED")
        self.assertEqual(
            payload["error"]["message"],
            "live authorization/device admission not implemented",
        )
        self._assert_no_adb()

    def test_justfile_recipes_forward_arguments_and_paths_with_spaces(self) -> None:
        dry_run = self._run(
            [
                "just",
                "--justfile",
                str(ROOT / "justfile"),
                "qualify-android-fresh",
                str(self.manifest_path),
                "--dry-run",
            ]
        )
        self.assertEqual(dry_run.returncode, 0, dry_run.stderr)
        self.assertEqual(json.loads(dry_run.stdout)["status"], "HOST_VALIDATED")
        self._assert_no_adb()

        no_reset_manifest = self.directory / "no reset manifest.json"
        document = json.loads(self.manifest_path.read_text(encoding="utf-8"))
        document["state_mode"] = "no-reset"
        document["inherited_state_session_ref"] = "prior-session-synthetic"
        no_reset_manifest.write_text(json.dumps(document), encoding="utf-8")
        preflight = self._run(
            [
                "just",
                "--justfile",
                str(ROOT / "justfile"),
                "qualify-android-no-reset",
                str(no_reset_manifest),
                "--preflight",
            ]
        )
        self.assertEqual(preflight.returncode, 0, preflight.stderr)
        self.assertEqual(json.loads(preflight.stdout)["status"], "HOST_VALIDATED")
        self._assert_no_adb()

    def test_justfile_live_request_reaches_the_fail_closed_handoff(self) -> None:
        result = self._run(
            [
                "just",
                "--justfile",
                str(ROOT / "justfile"),
                "qualify-android-fresh",
                str(self.manifest_path),
            ]
        )
        self.assertEqual(result.returncode, 3, result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["status"], "BLOCKED")
        self.assertEqual(
            payload["error"]["message"],
            "live authorization/device admission not implemented",
        )
        self._assert_no_adb()

    def test_new_help_is_host_only(self) -> None:
        for wrapper in (FRESH_WRAPPER, NO_RESET_WRAPPER):
            with self.subTest(wrapper=wrapper.name):
                result = self._run(["bash", str(wrapper), "--help"])
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("--manifest", result.stdout)
                self.assertIn("--dry-run", result.stdout)
                self.assertIn("--preflight", result.stdout)
                self._assert_no_adb()

    def test_archived_physical_entrypoint_is_not_active(self) -> None:
        self.assertFalse(RETIRED_ENTRYPOINT.exists())
        self._assert_no_adb()


class PackageImportTests(unittest.TestCase):
    def test_shared_modules_import_through_package_namespace(self) -> None:
        command = (
            "from scripts.android_qualification import "
            "admission, cli, fresh, manifest, no_reset"
        )
        result = subprocess.run(
            [sys.executable, "-c", command],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )

        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
