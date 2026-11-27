"""Tests for cache-path guards and canonical dependency manifests."""

from __future__ import annotations

import contextlib
import hashlib
import io
import json
import os
import subprocess
import tempfile
import unittest
from argparse import Namespace
from pathlib import Path
from unittest.mock import patch

from scripts.gradle_dependency_cache import control


class ControlTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="gradle-cache-control-test-")
        self.root = Path(self.temp.name)
        self.github_env = self.root / "github-env"
        self.github_output = self.root / "github-output"
        self.environment = patch.dict(os.environ, {
            "RUNNER_TEMP": str(self.root),
            "GITHUB_RUN_ID": "42",
            "GITHUB_JOB": "cache_seed",
            "GITHUB_RUN_ATTEMPT": "1",
            "GITHUB_ENV": str(self.github_env),
            "GITHUB_OUTPUT": str(self.github_output),
        })
        self.environment.start()
        control.command_init_environment(Namespace())
        self.home = control._home()
        self.modules = self.home / "caches" / "modules-2"

    def tearDown(self) -> None:
        self.environment.stop()
        self.temp.cleanup()

    def test_canonical_manifest_excludes_only_transient_files(self) -> None:
        cache = self.modules / "files" / "fixture"
        cache.mkdir(parents=True)
        (cache / "sample.jar").write_bytes(b"artifact")
        (cache / "sample.jar.lock").write_text("lock", encoding="utf-8")
        (cache / "gc.properties").write_text("metadata", encoding="utf-8")

        manifest = control.canonical_manifest(self.modules, 1024)

        self.assertEqual(manifest["files"], 1)
        self.assertEqual(manifest["bytes"], 8)
        self.assertEqual(manifest["entries"][0]["path"], "files/fixture/sample.jar")
        self.assertEqual(manifest["entries"][0]["sha256"], hashlib.sha256(b"artifact").hexdigest())

    def test_manifest_rejects_symlinks_and_expanded_size_over_limit(self) -> None:
        self.modules.mkdir(parents=True)
        outside = self.root / "outside.bin"
        outside.write_bytes(b"outside")
        (self.modules / "escape").symlink_to(outside)

        with self.assertRaises(control.SafetyError):
            control.canonical_manifest(self.modules, 1024)

        (self.modules / "escape").unlink()
        (self.modules / "large.bin").write_bytes(b"x" * 12)
        with self.assertRaises(control.SafetyError):
            control.canonical_manifest(self.modules, 11)

    def test_cleanup_removes_only_modules_two(self) -> None:
        self.modules.mkdir(parents=True)
        (self.modules / "partial.bin").write_bytes(b"partial")
        wrapper_file = self.home / "wrapper" / "dists" / "gradle.zip"
        wrapper_file.parent.mkdir(parents=True)
        wrapper_file.write_bytes(b"wrapper")

        control._clean_modules()

        self.assertFalse(self.modules.exists())
        self.assertTrue(wrapper_file.is_file())

    def test_cleanup_rejects_module_cache_symlink(self) -> None:
        self.modules.parent.mkdir(parents=True)
        outside = self.root / "outside-cache"
        outside.mkdir()
        marker = outside / "keep.bin"
        marker.write_bytes(b"keep")
        self.modules.symlink_to(outside, target_is_directory=True)

        with self.assertRaises(control.SafetyError):
            control._clean_modules()

        self.assertTrue(marker.is_file())

    def test_non_exact_restore_cleans_before_miss_is_accepted(self) -> None:
        self.modules.mkdir(parents=True)
        (self.modules / "partial.bin").write_bytes(b"partial")
        args = Namespace(
            action_outcome="success",
            cache_hit="",
            matched_key="",
            primary_key="expected-key",
            expected="miss",
            manifest_sha256="",
        )

        with contextlib.redirect_stdout(io.StringIO()):
            control.command_restore_check(args)

        self.assertFalse(self.modules.exists())
        evidence = json.loads((control._task_root() / "evidence.json").read_text(encoding="utf-8"))
        self.assertEqual(evidence["restore_state"], "non_exact_cleaned")

    def test_restore_action_error_is_not_accepted_as_a_miss(self) -> None:
        self.modules.mkdir(parents=True)
        (self.modules / "partial.bin").write_bytes(b"partial")
        args = Namespace(
            action_outcome="failure",
            cache_hit="",
            matched_key="",
            primary_key="expected-key",
            expected="miss",
            manifest_sha256="",
        )

        with contextlib.redirect_stdout(io.StringIO()), self.assertRaises(control.SafetyError):
            control.command_restore_check(args)

        self.assertFalse(self.modules.exists())

    def test_warm_miss_cleans_then_fails(self) -> None:
        self.modules.mkdir(parents=True)
        (self.modules / "partial.bin").write_bytes(b"partial")
        args = Namespace(
            action_outcome="success",
            cache_hit="",
            matched_key="",
            primary_key="expected-key",
            expected="exact",
            manifest_sha256="trusted-digest",
        )

        with contextlib.redirect_stdout(io.StringIO()), self.assertRaises(control.SafetyError):
            control.command_restore_check(args)

        self.assertFalse(self.modules.exists())

    def test_exact_restore_requires_matching_seed_manifest(self) -> None:
        self.modules.mkdir(parents=True)
        (self.modules / "artifact.jar").write_bytes(b"trusted")
        digest = control.canonical_manifest(self.modules, 1024)["sha256"]
        args = Namespace(
            action_outcome="success",
            cache_hit="true",
            matched_key="key",
            primary_key="key",
            expected="exact",
            manifest_sha256=digest,
        )

        with contextlib.redirect_stdout(io.StringIO()):
            control.command_restore_check(args)

        evidence = json.loads((control._task_root() / "evidence.json").read_text(encoding="utf-8"))
        self.assertEqual(evidence["restore_state"], "exact")
        self.assertTrue(evidence["restored_manifest_sha256"] == digest)

    def test_fixture_is_bounded_and_namespaced(self) -> None:
        control.command_create_fixture(Namespace(name="semantic", value="A", bytes=1024))
        fixture_path = Path(os.environ["GRADLE_FIXTURE_ROOT"]) / "semantic"
        with contextlib.redirect_stdout(io.StringIO()):
            control.command_verify_fixture(Namespace(path=str(fixture_path), value="A", bytes=1024))
        self.assertEqual((fixture_path / "fixture.bin").stat().st_size, 1024)
        with self.assertRaises(control.SafetyError):
            control.command_create_fixture(Namespace(name="oversized", value="A", bytes=control.FIXTURE_LIMIT + 1))

    def test_dependency_input_change_changes_cache_key_material(self) -> None:
        root = Path(__file__).resolve().parents[2]
        baseline = control.dependency_input_digest(root)
        changed = control.dependency_input_digest(root, mutation=True)
        self.assertNotEqual(baseline, changed)

    def test_cache_key_uses_the_resolved_temurin_17_runtime(self) -> None:
        result = subprocess.CompletedProcess(
            args=["java"],
            returncode=0,
            stdout="    java.runtime.version = 17.0.21.1+2\n    java.vendor = Eclipse Adoptium\n",
        )
        with patch("scripts.gradle_dependency_cache.control.subprocess.run", return_value=result):
            identity = control.java_runtime_identity({})
        self.assertEqual(identity, {
            "java_runtime_version": "17.0.21.1+2",
            "java_vendor": "Eclipse Adoptium",
        })

        other_runtime = subprocess.CompletedProcess(
            args=["java"],
            returncode=0,
            stdout="    java.runtime.version = 25.0.1+8\n    java.vendor = Eclipse Adoptium\n",
        )
        with patch("scripts.gradle_dependency_cache.control.subprocess.run", return_value=other_runtime):
            with self.assertRaises(control.SafetyError):
                control.java_runtime_identity({})

    def test_cache_key_records_runtime_vendor_and_android_revisions(self) -> None:
        sdk = self.root / "android-sdk"
        platform = sdk / "platforms" / "android-36"
        build_tools = sdk / "build-tools" / "36.0.0"
        platform.mkdir(parents=True)
        build_tools.mkdir(parents=True)
        (platform / "source.properties").write_text("Pkg.Revision=3\n", encoding="utf-8")
        (build_tools / "source.properties").write_text("Pkg.Revision=36.0.0\n", encoding="utf-8")
        with patch.dict(os.environ, {
            "ANDROID_HOME": str(sdk),
            "RUNNER_ARCH": "X64",
            "GITHUB_OUTPUT": str(self.github_output),
        }), patch("scripts.gradle_dependency_cache.control.dependency_input_digest", return_value="a" * 64), patch(
            "scripts.gradle_dependency_cache.control.java_runtime_identity",
            return_value={"java_runtime_version": "17.0.21.1+2", "java_vendor": "Eclipse Adoptium"},
        ), contextlib.redirect_stdout(io.StringIO()):
            control.command_cache_key(Namespace(root=str(self.root), mutate_dependency_input=False))
        output = self.github_output.read_text(encoding="utf-8")
        self.assertIn("temurin-eclipse-adoptium-17.0.21.1+2", output)
        self.assertIn("sdk36r3-bt36.0.0r36.0.0", output)

    def test_fixture_restore_error_cleans_only_fixture_namespace(self) -> None:
        fixture_root = Path(os.environ["GRADLE_FIXTURE_ROOT"])
        target = fixture_root / "readback"
        target.mkdir()
        (target / "partial.bin").write_bytes(b"partial")
        unrelated = fixture_root / "other" / "keep.bin"
        unrelated.parent.mkdir()
        unrelated.write_bytes(b"keep")
        args = Namespace(
            path=str(target),
            expected="miss",
            action_outcome="failure",
            cache_hit="",
            matched_key="",
            primary_key="unused-key",
        )

        with contextlib.redirect_stdout(io.StringIO()), self.assertRaises(control.SafetyError):
            control.command_fixture_restore_check(args)

        self.assertFalse(target.exists())
        self.assertEqual(unrelated.read_bytes(), b"keep")

    def test_read_only_canary_is_classified_as_action_skip_not_service_denial(self) -> None:
        args = Namespace(
            cache_mode="read",
            save_outcome="success",
            readback_outcome="success",
            cache_hit="",
            matched_key="",
            primary_key="canary-key",
        )
        with contextlib.redirect_stdout(io.StringIO()):
            control.command_classify_read_only_canary(args)
        evidence = json.loads((control._task_root() / "evidence.json").read_text(encoding="utf-8"))
        self.assertEqual(evidence["read_only_canary_classification"], "action_level_skip_read_mode")
        self.assertFalse(evidence["cache_service_denial_claimed"])

    def test_warm_observer_rejects_completed_zero_byte_artifact_read(self) -> None:
        observer_output = self.root / "observer.jsonl"
        records = [
            {"event": "observer_ready"},
            {
                "event": "external_resource_read",
                "artifact_body": True,
                "bytes_read_known": True,
                "bytes_read": 0,
                "result_state": "completed",
            },
        ]
        observer_output.write_text(
            "".join(json.dumps(record) + "\n" for record in records),
            encoding="utf-8",
        )

        with patch.dict(os.environ, {"GRADLE_OBSERVER_OUTPUT": str(observer_output)}):
            with contextlib.redirect_stdout(io.StringIO()), self.assertRaises(control.SafetyError):
                control.command_verify_observer(Namespace(mode="warm"))


if __name__ == "__main__":
    unittest.main()
