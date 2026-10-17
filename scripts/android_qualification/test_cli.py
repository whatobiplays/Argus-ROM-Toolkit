"""Tests for sanitized host-validation CLI behavior."""

from __future__ import annotations

import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from scripts.android_qualification import cli, manifest


class CliTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.directory = Path(self.temporary_directory.name)
        self.manifest_path = self.directory / "private manifest.json"
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

    def _run(
        self,
        arguments: list[str],
        mode: manifest.StateMode = manifest.StateMode.FRESH,
    ) -> tuple[int, str, str]:
        stdout = io.StringIO()
        stderr = io.StringIO()
        code = cli.main(mode, arguments, stdout=stdout, stderr=stderr)
        return code, stdout.getvalue(), stderr.getvalue()

    def test_dry_run_and_preflight_are_identical_host_validation(self) -> None:
        dry_run = self._run(["--manifest", str(self.manifest_path), "--dry-run"])
        preflight = self._run(
            ["--manifest", str(self.manifest_path), "--preflight"]
        )
        self.assertEqual(dry_run, preflight)
        code, stdout, stderr = dry_run
        self.assertEqual(code, 0)
        self.assertEqual(
            json.loads(stdout),
            {"status": "HOST_VALIDATED", "state_mode": "fresh"},
        )
        self.assertEqual(stderr, "")
        self.assertNotIn("ADMITTED", stdout)

    def test_live_request_fails_closed_after_structural_validation(self) -> None:
        code, stdout, stderr = self._run(["--manifest", str(self.manifest_path)])
        payload = json.loads(stdout)
        self.assertEqual(code, 3)
        self.assertEqual(payload["status"], "BLOCKED")
        self.assertEqual(payload["error"]["code"], "LIVE_ADMISSION_NOT_IMPLEMENTED")
        self.assertEqual(
            payload["error"]["message"],
            "live authorization/device admission not implemented",
        )
        self.assertEqual(stderr, "")

    def test_blocked_manifest_does_not_disclose_path_or_content(self) -> None:
        secret = "PRIVATE_ROM_AND_SERIAL"
        blocked_path = self.directory / f"{secret}.json"
        blocked_path.write_text(
            json.dumps({"schema_version": 1, "artifact_ref": secret}),
            encoding="utf-8",
        )
        code, stdout, stderr = self._run(
            ["--manifest", str(blocked_path), "--dry-run"]
        )
        payload = json.loads(stdout)
        self.assertEqual(code, 2)
        self.assertEqual(payload["status"], "BLOCKED")
        self.assertEqual(payload["error"]["code"], "MANIFEST_MISSING_FIELD")
        rendered = stdout + stderr
        self.assertNotIn(secret, rendered)
        self.assertNotIn(str(blocked_path), rendered)

    def test_missing_manifest_argument_is_sanitized(self) -> None:
        code, stdout, stderr = self._run(["--dry-run"])
        payload = json.loads(stdout)
        self.assertEqual(code, 2)
        self.assertEqual(payload["error"]["code"], "CLI_ARGUMENTS_INVALID")
        self.assertEqual(stderr, "")

    def test_authorization_override_attempt_is_sanitized(self) -> None:
        secret = "SERIAL_AND_ROM_NAME"
        arguments = [
            "--manifest",
            str(self.manifest_path),
            "--device",
            secret,
            "--dry-run",
        ]
        code, stdout, stderr = self._run(arguments)
        payload = json.loads(stdout)
        self.assertEqual(code, 2)
        self.assertEqual(payload["error"]["code"], "CLI_ARGUMENTS_INVALID")
        self.assertNotIn(secret, stdout + stderr)

    def test_mutually_exclusive_host_flags_are_rejected(self) -> None:
        code, stdout, _ = self._run(
            [
                "--manifest",
                str(self.manifest_path),
                "--dry-run",
                "--preflight",
            ]
        )
        self.assertEqual(code, 2)
        self.assertEqual(json.loads(stdout)["error"]["code"], "CLI_ARGUMENTS_INVALID")

    def test_entrypoint_state_mode_mismatch_is_rejected(self) -> None:
        code, stdout, _ = self._run(
            ["--manifest", str(self.manifest_path), "--dry-run"],
            manifest.StateMode.NO_RESET,
        )
        self.assertEqual(code, 2)
        self.assertEqual(
            json.loads(stdout)["error"]["code"],
            "MANIFEST_STATE_MODE_MISMATCH",
        )

    def test_internal_validation_failure_is_sanitized(self) -> None:
        secret = "PRIVATE_ROM_NAME_AND_SERIAL"
        with mock.patch.object(cli, "admit_host_only", side_effect=RuntimeError(secret)):
            code, stdout, stderr = self._run(
                ["--manifest", str(self.manifest_path), "--dry-run"]
            )
        payload = json.loads(stdout)
        self.assertEqual(code, 2)
        self.assertEqual(payload["error"]["code"], "HOST_VALIDATION_INTERNAL_ERROR")
        self.assertEqual(stderr, "")
        self.assertNotIn(secret, stdout + stderr)

    def test_live_handoff_cannot_fall_through(self) -> None:
        with mock.patch.object(cli, "request_live_execution", return_value=None):
            with self.assertRaises(AssertionError):
                self._run(["--manifest", str(self.manifest_path)])


if __name__ == "__main__":
    unittest.main()
