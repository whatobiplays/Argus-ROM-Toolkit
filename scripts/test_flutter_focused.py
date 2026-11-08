"""Black-box tests for the Argus-owned focused Flutter runner."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "run_flutter_focused.sh"
JOBS_TEST = "test/features/jobs/jobs_feature_test.dart"
SOURCES_TEST = "test/features/sources/sources_feature_test.dart"
JOBS_SOURCE = "lib/features/jobs/presentation/job_detail_page.dart"


class FocusedFlutterContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tempdir.cleanup)
        temp = Path(self.tempdir.name)
        stub = temp / "fvm"
        stub.write_text(
            '#!/usr/bin/env bash\n'
            'printf "%s\\n" "$*" >> "$FOCUSED_FLUTTER_LOG"\n'
            'if [[ "${FOCUSED_FLUTTER_FAIL_ON:-}" == "$1" ]]; then exit 17; fi\n',
            encoding="utf-8",
        )
        stub.chmod(0o755)
        self.log = temp / "commands.log"
        self.env = {
            **os.environ,
            "PATH": f"{temp}{os.pathsep}{os.environ.get('PATH', '')}",
            "FOCUSED_FLUTTER_LOG": str(self.log),
        }

    def invoke(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["bash", str(SCRIPT), *args],
            cwd=ROOT,
            env=self.env,
            capture_output=True,
            text=True,
            check=False,
        )

    def commands(self) -> list[str]:
        if not self.log.exists():
            return []
        return self.log.read_text(encoding="utf-8").splitlines()

    def test_formats_test_files_and_sources_before_running_requested_tests(self) -> None:
        result = self.invoke(f"{JOBS_TEST},{SOURCES_TEST}", JOBS_SOURCE)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.commands(),
            [
                "dart format --output=none --set-exit-if-changed "
                f"{JOBS_TEST} {SOURCES_TEST} {JOBS_SOURCE}",
                f"flutter test --no-pub {JOBS_TEST} {SOURCES_TEST}",
            ],
        )

    def test_source_argument_is_optional_and_tests_are_always_formatted(self) -> None:
        result = self.invoke(JOBS_TEST)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.commands(),
            [
                f"dart format --output=none --set-exit-if-changed {JOBS_TEST}",
                f"flutter test --no-pub {JOBS_TEST}",
            ],
        )

    def test_invalid_paths_fail_before_running_any_tool(self) -> None:
        cases = [
            (),
            ("",),
            (JOBS_SOURCE,),
            ("test/../lib/example.dart",),
            ("test/missing_test.dart",),
            (f"{JOBS_TEST},",),
            (f"{JOBS_TEST},,{SOURCES_TEST}",),
            (f"{JOBS_TEST};touch/tmp/marker",),
            (JOBS_TEST, "../justfile"),
            (JOBS_TEST, "lib/missing.dart"),
            (JOBS_TEST, "test/../../scripts/run_flutter_focused.sh"),
            (JOBS_TEST, "test/foo.dart,"),
            (JOBS_TEST, JOBS_SOURCE, SOURCES_TEST),
        ]
        for args in cases:
            with self.subTest(args=args):
                self.log.unlink(missing_ok=True)
                result = self.invoke(*args)
                self.assertEqual(result.returncode, 64, (args, result.stderr))
                self.assertEqual(self.commands(), [])

    def test_formatter_failure_aborts_before_tests(self) -> None:
        self.env["FOCUSED_FLUTTER_FAIL_ON"] = "dart"
        result = self.invoke(JOBS_TEST)
        self.assertEqual(result.returncode, 17)
        self.assertEqual(
            self.commands(),
            [f"dart format --output=none --set-exit-if-changed {JOBS_TEST}"],
        )

    def test_just_declares_focused_and_smoke_targets(self) -> None:
        justfile = (ROOT / "justfile").read_text(encoding="utf-8")
        self.assertIn('\nflutter-focused tests formats="":\n', justfile)
        self.assertIn("\nsmoke:\n", justfile)
        self.assertIn("scripts/run_flutter_focused.sh", justfile)


if __name__ == "__main__":
    unittest.main()
