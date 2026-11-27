"""Test redacted evidence for Robolectric runtime transfers."""

from __future__ import annotations

import hashlib
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts.gradle_dependency_cache import runner


class RunnerEvidenceTests(unittest.TestCase):
    def test_required_task_outcomes_reject_skip_and_reuse(self) -> None:
        output = """\
> Task :testProbeUnitTest
> Task :lintProbe UP-TO-DATE
> Task :assembleProbe
BUILD SUCCESSFUL
"""
        outcomes = runner.parse_gradle_task_outcomes(output)

        self.assertEqual(outcomes, [
            {"task": "testProbeUnitTest", "task_path": ":testProbeUnitTest", "outcome": "SUCCESS"},
            {"task": "lintProbe", "task_path": ":lintProbe", "outcome": "UP-TO-DATE"},
            {"task": "assembleProbe", "task_path": ":assembleProbe", "outcome": "SUCCESS"},
        ])
        with self.assertRaises(runner.RunnerError):
            runner.validate_required_task_outcomes(outcomes)

    def test_incremental_invocation_evidence_survives_a_later_failure(self) -> None:
        with tempfile.TemporaryDirectory(prefix="gradle-runner-incremental-test-") as name:
            root = Path(name)
            evidence: dict[str, object] = {"wrapper_version_seconds": 2.5}
            with patch.dict(os.environ, {"RUNNER_TEMP": str(root)}):
                runner.persist_invocation_result(evidence, {
                    "invocation_id": "task-inventory-1",
                    "label": "task_inventory",
                    "exit_code": 0,
                    "elapsed_seconds": 4.25,
                    "task_outcomes": [],
                    "observer_coverage": "complete",
                })
                runner.persist_invocation_result(evidence, {
                    "invocation_id": "dry-run-1",
                    "label": "dry_run",
                    "exit_code": 1,
                    "elapsed_seconds": 7.75,
                    "task_outcomes": [],
                    "observer_coverage": "complete",
                })

            persisted = json.loads(
                (root / "gradle-dependency-cache-experiment" / "state" / "evidence.json")
                .read_text(encoding="utf-8")
            )
            self.assertEqual(
                [item["label"] for item in persisted["gradle_invocations"]],
                ["task_inventory", "dry_run"],
            )
            self.assertEqual(persisted["timings_seconds"]["task_inventory"], 4.25)
            self.assertEqual(persisted["timings_seconds"]["dry_run"], 7.75)
            self.assertEqual(persisted["wrapper_version_seconds"], 2.5)

    def test_robolectric_attempts_exclude_unrelated_gradle_transfers(self) -> None:
        with tempfile.TemporaryDirectory(prefix="gradle-runner-evidence-test-") as name:
            root = Path(name)
            log = root / "gradle.log"
            robolectric_url = (
                "https://repo.example.invalid/maven2/org/robolectric/"
                "nativeruntime-dist-compat/1.0.18/"
                "nativeruntime-dist-compat-1.0.18.jar"
            )
            unrelated_url = "https://repo.example.invalid/maven2/com/example/other/1.0/other-1.0.jar"
            log.write_text(
                f"Transferring {robolectric_url}\nTransferring {unrelated_url}\n",
                encoding="utf-8",
            )

            with patch.dict(os.environ, {"RUNNER_TEMP": str(root)}):
                runner.capture_robolectric_attempts(log)

            evidence = json.loads(
                (
                    root
                    / "gradle-dependency-cache-experiment"
                    / "state"
                    / "robolectric-attempts-redacted.json"
                ).read_text(encoding="utf-8")
            )
            self.assertEqual(evidence["attempt_lines_observed"], 1)
            self.assertEqual(
                evidence["attempts"][0]["resource_sha256"],
                hashlib.sha256(robolectric_url.encode("utf-8")).hexdigest(),
            )
            self.assertNotIn(robolectric_url, json.dumps(evidence))


if __name__ == "__main__":
    unittest.main()
