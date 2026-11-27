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
