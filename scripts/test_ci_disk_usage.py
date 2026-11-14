"""Tests for the bounded CI disk usage reporter."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
REPORTER = REPOSITORY_ROOT / "scripts" / "report_ci_disk_usage.sh"


class CIDiskUsageReporterTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.fixture = Path(self.temporary_directory.name) / "ci disk fixture"
        self.fixture.mkdir()
        self.bin_directory = self.fixture / "bin"
        self.bin_directory.mkdir()
        self.tool_log = self.fixture / "tool calls.log"
        self.target = self.fixture / "cargo target with spaces"
        self.pub_cache = self.fixture / "pub cache with spaces"
        self.fvm_cache = self.fixture / "fvm cache missing"
        self.action_sdk = self.fixture / "flutter action sdk"
        self.sdk_cache = self.fixture / "fvm sdk cache"
        self.project_cache = self.fixture / "project fvm cache"
        self.project_git_cache = self.fixture / "project fvm git cache"
        self.relative_target = self.fixture / "repository" / "cargo target relative"
        self.git_cache = self.fixture / "fvm git cache"
        self.home = self.fixture / "home"
        self.default_fvm_cache = self.home / "fvm"
        self.default_fvm_git_cache = self.default_fvm_cache / "cache.git"
        self.flutter_project = self.fixture / "repository" / "flutter"
        self.flutter_project.mkdir(parents=True)
        self.rust_toolchain_file = self.fixture / "repository" / "rust-toolchain.toml"
        self.rust_toolchain_file.write_text(
            'channel = "stable-x86_64-unknown-linux-gnu"\n', encoding="utf-8"
        )
        self.flutter_sdk_link = self.flutter_project / ".fvm" / "flutter_sdk"
        self.flutter_sdk_link.parent.mkdir()
        self.sdk_cache.mkdir()
        self.action_sdk.mkdir()
        self.flutter_sdk_link.symlink_to(self.sdk_cache, target_is_directory=True)
        self.pub_cache.mkdir()
        self.git_cache.mkdir()
        self.project_cache.mkdir()
        self.project_git_cache.mkdir()
        self.relative_target.mkdir()
        self.default_fvm_git_cache.mkdir(parents=True)
        (self.flutter_project / ".fvmrc").write_text(
            json.dumps(
                {
                    "flutter": "3.44.7",
                    "cachePath": str(self.project_cache),
                    "gitCachePath": str(self.project_git_cache),
                }
            ),
            encoding="utf-8",
        )

        self._write_executable(
            "cargo",
            """#!/usr/bin/env bash
printf 'cargo:%s\n' "$*" >> "$TOOL_LOG"
printf 'cargo-toolchain:%s\n' "${RUSTUP_TOOLCHAIN:-}" >> "$TOOL_LOG"
if [[ ${FAKE_CARGO_FAIL:-0} == 1 ]]; then
  printf 'simulated metadata failure\n' >&2
  exit 42
fi
if [[ -n ${FAKE_EXPECTED_TOOLCHAIN:-} && "${RUSTUP_TOOLCHAIN:-}" != "$FAKE_EXPECTED_TOOLCHAIN" ]]; then
  printf 'unexpected Rust toolchain selected\n' >&2
  exit 43
fi
target_directory=${FAKE_CARGO_TARGET_DIRECTORY}
if [[ -n ${CARGO_TARGET_DIR:-} ]]; then
  if [[ "$CARGO_TARGET_DIR" == /* ]]; then
    target_directory=$CARGO_TARGET_DIR
  else
    target_directory="$PWD/$CARGO_TARGET_DIR"
  fi
fi
printf '{"target_directory":"%s"}\n' "$target_directory"
""",
        )
        self._write_executable(
            "rustup",
            """#!/usr/bin/env bash
if [[ ${1:-} == toolchain && ${2:-} == list ]]; then
  printf '%s\n' "${FAKE_RUSTUP_TOOLCHAINS:-stable-x86_64-unknown-linux-gnu (default)}"
  exit 0
fi
exit 1
""",
        )
        self._write_executable(
            "df",
            """#!/usr/bin/env bash
printf 'df:%s\n' "$*" >> "$TOOL_LOG"
if [[ -n ${FAIL_DF_PATTERN:-} && "$*" == *"$FAIL_DF_PATTERN"* ]]; then
  printf 'simulated df failure\n' >&2
  exit 1
fi
printf 'Filesystem 1K-blocks Used Available Use%% Mounted on\n'
printf '/dev/fake 1000000 1000 999000 1%% /fake\n'
""",
        )
        self._write_executable(
            "du",
            """#!/usr/bin/env bash
last_argument=
for argument in "$@"; do last_argument=$argument; done
printf 'du:%s\n' "$last_argument" >> "$TOOL_LOG"
if [[ -n ${FAIL_DU_PATTERN:-} && "$last_argument" == *"$FAIL_DU_PATTERN"* ]]; then
  printf 'simulated du failure\n' >&2
  exit 1
fi
printf '1.2G %s\n' "$last_argument"
""",
        )

        self.reporter = self.fixture / "repository" / "scripts" / "report_ci_disk_usage.sh"
        self.reporter.parent.mkdir(parents=True)
        if REPORTER.is_file():
            shutil.copyfile(REPORTER, self.reporter)
        else:
            self.reporter.write_text("exit 127\n", encoding="utf-8")
        self.environment = os.environ.copy()
        self.environment.update(
            {
                "PATH": f"{self.bin_directory}{os.pathsep}{self.environment['PATH']}",
                "HOME": str(self.home),
                "TOOL_LOG": str(self.tool_log),
                "FAKE_CARGO_TARGET_DIRECTORY": str(self.target),
                "FLUTTER_SDK_PATH": str(self.action_sdk),
                "PUB_CACHE_PATH": str(self.pub_cache),
                "FVM_CACHE_PATH": str(self.fvm_cache),
                "FVM_GIT_CACHE_PATH": str(self.git_cache),
            }
        )
        self.target.mkdir()

    def _write_executable(self, name: str, contents: str) -> None:
        executable = self.bin_directory / name
        executable.write_text(contents, encoding="utf-8")
        executable.chmod(0o755)

    def _run_report(self, phase: str, **environment: str) -> subprocess.CompletedProcess[str]:
        current_environment = self.environment.copy()
        current_environment.update(environment)
        return subprocess.run(
            ["bash", str(self.reporter), phase],
            cwd=self.fixture / "repository",
            env=current_environment,
            check=False,
            capture_output=True,
            text=True,
        )

    def test_report_includes_space_containing_paths_and_resolves_fvm_sdk(self) -> None:
        result = self._run_report("before-check")
        output = result.stdout + result.stderr

        self.assertEqual(0, result.returncode, output)
        self.assertIn("phase=before-check", result.stdout)
        self.assertIn(f"Cargo target: {self.target.resolve()}", result.stdout)
        self.assertIn(f"Pub cache: {self.pub_cache.resolve()}", result.stdout)
        self.assertIn(f"FVM project cache: {self.project_cache.resolve()}", result.stdout)
        self.assertIn(
            f"FVM project Git cache: {self.project_git_cache.resolve()}", result.stdout
        )
        self.assertIn(f"FVM project SDK: {self.sdk_cache.resolve()}", result.stdout)
        self.assertIn("999000", result.stdout)
        self.assertIn("1.2G", result.stdout)
        calls = self.tool_log.read_text(encoding="utf-8")
        self.assertIn(f"du:{self.sdk_cache.resolve()}", calls)
        self.assertNotIn(f"du:{self.flutter_sdk_link}\n", calls)

    def test_relative_cargo_target_directory_with_spaces_is_resolved(self) -> None:
        result = self._run_report("before-check", CARGO_TARGET_DIR="cargo target relative")

        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertIn(f"Cargo target: {self.relative_target.resolve()}", result.stdout)

    def test_pinned_toolchain_match_does_not_accept_a_numeric_prefix(self) -> None:
        self.rust_toolchain_file.write_text('channel = "1.8"\n', encoding="utf-8")
        installed_toolchain = "1.80.0-x86_64-unknown-linux-gnu"
        result = self._run_report(
            "before-check",
            FAKE_RUSTUP_TOOLCHAINS=f"{installed_toolchain} (default)",
            FAKE_EXPECTED_TOOLCHAIN=installed_toolchain,
        )

        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertIn(f"Cargo target: {self.target.resolve()}", result.stdout)
        self.assertIn(f"cargo-toolchain:{installed_toolchain}", self.tool_log.read_text())

    def test_major_minor_pin_matches_an_installed_patch_release(self) -> None:
        self.rust_toolchain_file.write_text('channel = "1.8"\n', encoding="utf-8")
        pinned_toolchain = "1.8.0-x86_64-unknown-linux-gnu"
        default_toolchain = "1.80.0-x86_64-unknown-linux-gnu"
        result = self._run_report(
            "before-check",
            FAKE_RUSTUP_TOOLCHAINS=(
                f"{pinned_toolchain}\n{default_toolchain} (default)"
            ),
            FAKE_EXPECTED_TOOLCHAIN=pinned_toolchain,
        )

        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertIn(f"Cargo target: {self.target.resolve()}", result.stdout)
        self.assertIn(f"cargo-toolchain:{pinned_toolchain}", self.tool_log.read_text())

    def test_missing_paths_are_reported_without_zero_sizes(self) -> None:
        result = self._run_report("before-flutter")

        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertIn(f"FVM cache: not present ({self.fvm_cache})", result.stdout)
        self.assertNotIn(f"0 B {self.fvm_cache}", result.stdout)

    def test_default_fvm_cache_paths_are_reported(self) -> None:
        (self.flutter_project / ".fvmrc").write_text(
            json.dumps({"flutter": "3.44.7"}), encoding="utf-8"
        )
        result = self._run_report(
            "after-bootstrap",
            FVM_CACHE_PATH="",
            FVM_HOME="",
            FVM_GIT_CACHE_PATH="",
        )

        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertIn(f"FVM cache: {self.default_fvm_cache.resolve()}", result.stdout)
        self.assertIn(f"FVM Git cache: {self.default_fvm_git_cache.resolve()}", result.stdout)

    def test_invalid_phase_stops_before_calling_measurement_tools(self) -> None:
        result = self._run_report("after-everything")

        self.assertEqual(2, result.returncode)
        self.assertIn("Usage:", result.stderr)
        self.assertFalse(self.tool_log.exists())

    def test_measurement_failure_is_reported_and_other_paths_are_attempted(self) -> None:
        result = self._run_report("after-bootstrap", FAIL_DU_PATTERN="cargo target")
        output = result.stdout + result.stderr

        self.assertNotEqual(0, result.returncode)
        self.assertIn("size: unavailable", output)
        self.assertIn(f"Pub cache: {self.pub_cache.resolve()}", result.stdout)
        self.assertIn(f"du:{self.pub_cache.resolve()}", self.tool_log.read_text(encoding="utf-8"))

    def test_cargo_metadata_failure_is_not_reported_as_zero(self) -> None:
        result = self._run_report("after-bootstrap", FAKE_CARGO_FAIL="1")
        output = result.stdout + result.stderr

        self.assertNotEqual(0, result.returncode)
        self.assertIn("Cargo target: unavailable", output)
        self.assertNotIn("0 B", output)
        self.assertIn(f"Pub cache: {self.pub_cache.resolve()}", result.stdout)


if __name__ == "__main__":
    unittest.main()
