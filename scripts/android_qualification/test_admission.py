"""Tests for the shared structural host-validation seam."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from scripts.android_qualification import admission, manifest


class AdmissionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.directory = Path(self.temporary_directory.name)
        self.manifest_path = self.directory / "manifest.json"
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

    def test_host_validation_returns_only_structural_result(self) -> None:
        result = admission.admit_host_only(self.manifest_path, manifest.StateMode.FRESH)
        self.assertIsInstance(result, admission.HostValidationResult)
        self.assertEqual(result.manifest.state_mode, manifest.StateMode.FRESH)
        self.assertFalse(hasattr(result, "admitted"))
        self.assertIn(
            "does not establish session authorization or admission",
            admission.admit_host_only.__doc__ or "",
        )

    def test_live_handoff_fails_closed_with_required_message(self) -> None:
        validation = admission.admit_host_only(
            self.manifest_path, manifest.StateMode.FRESH
        )
        with self.assertRaises(admission.LiveExecutionBlocked) as caught:
            admission.request_live_execution(validation)
        self.assertEqual(
            str(caught.exception),
            "live authorization/device admission not implemented",
        )

    def test_host_and_live_paths_have_no_subprocess_boundary(self) -> None:
        validation = admission.admit_host_only(
            self.manifest_path, manifest.StateMode.FRESH
        )
        with mock.patch("subprocess.run", side_effect=AssertionError("subprocess")), \
             mock.patch("subprocess.Popen", side_effect=AssertionError("subprocess")), \
             mock.patch("os.system", side_effect=AssertionError("subprocess")):
            admission.admit_host_only(self.manifest_path, manifest.StateMode.FRESH)
            with self.assertRaises(admission.LiveExecutionBlocked):
                admission.request_live_execution(validation)

    def test_implementation_has_no_device_or_legacy_runner_reference(self) -> None:
        module_directory = Path(__file__).resolve().parent
        names = (
            "manifest.py",
            "admission.py",
            "cli.py",
            "fresh.py",
            "no_reset.py",
        )
        for name in names:
            with self.subTest(name=name):
                source = (module_directory / name).read_text(encoding="utf-8")
                self.assertNotIn("adb", source.casefold())
                self.assertNotIn("subprocess", source)
                self.assertNotIn("Popen(", source)
                self.assertNotIn("os.system", source)
                self.assertNotIn("phase_" + "003", source)
                self.assertNotIn("run_phase_", source)
                self.assertNotIn("keyring", source)
                self.assertNotIn("ADMITTED", source)


if __name__ == "__main__":
    unittest.main()
