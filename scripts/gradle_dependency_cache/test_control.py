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

    def test_archive_limit_counts_transient_files_excluded_from_digest(self) -> None:
        self.modules.mkdir(parents=True)
        (self.modules / "module.lock").write_bytes(b"x" * 12)

        with self.assertRaises(control.SafetyError):
            control.canonical_manifest(self.modules, 11)

    def test_archive_validation_rejects_excluded_transient_symlink(self) -> None:
        self.modules.mkdir(parents=True)
        outside = self.root / "outside.lock"
        outside.write_bytes(b"keep")
        (self.modules / "ignored.lock").symlink_to(outside)

        with self.assertRaises(control.SafetyError):
            control.canonical_manifest(self.modules, 1024)

    def test_manifest_validates_archive_and_hashes_selected_files_in_one_walk(self) -> None:
        self.modules.mkdir(parents=True)
        (self.modules / "artifact.jar").write_bytes(b"artifact")
        (self.modules / "artifact.jar.lock").write_text("lock", encoding="utf-8")

        with patch("scripts.gradle_dependency_cache.control.os.walk", wraps=os.walk) as walk:
            manifest = control.canonical_manifest(self.modules, 1024)

        self.assertEqual(walk.call_count, 1)
        self.assertEqual(manifest["expanded_bytes"], 12)
        self.assertEqual(manifest["bytes"], 8)

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

    def test_trusted_seed_record_binds_cache_key_run_and_source(self) -> None:
        source_sha = "a" * 40
        cache_key = "argus-gradle-issue93-pilot-v1-test-key"
        manifest_path = control._task_root() / "modules-manifest.json"
        manifest_path.write_text(json.dumps({
            "format": 1,
            "sha256": "b" * 64,
            "files": 3,
            "bytes": 20,
            "expanded_bytes": 25,
        }), encoding="utf-8")
        record_path = control._task_root() / "trusted-seed-manifest.json"
        with patch.dict(os.environ, {
            "GITHUB_SHA": source_sha,
            "GITHUB_REF": "refs/heads/codex/issue-93-gradle-cache-pilot",
            "GITHUB_RUN_ID": "42",
            "GITHUB_RUN_ATTEMPT": "1",
            "EXPERIMENT_CAMPAIGN_ID": "gradle-dependency-cache-pilot-v1",
        }), contextlib.redirect_stdout(io.StringIO()):
            control.command_write_seed_record(Namespace(
                manifest=str(manifest_path), cache_key=cache_key, output=str(record_path),
            ))
            control.command_verify_seed_record(Namespace(
                path=str(record_path), expected_source_sha=source_sha,
                expected_cache_key=cache_key, expected_run_id="42",
            ))

        record = json.loads(record_path.read_text(encoding="utf-8"))
        self.assertEqual(record["seed_source_sha"], source_sha)
        self.assertEqual(record["cache_key"], cache_key)
        evidence = json.loads((control._task_root() / "evidence.json").read_text(encoding="utf-8"))
        self.assertEqual(evidence["trusted_seed_manifest_sha256"], "b" * 64)

    def test_seed_campaign_selection_requires_one_successful_first_attempt(self) -> None:
        head_sha = "a" * 40
        seed = {
            "id": 42,
            "event": "push",
            "head_branch": "codex/issue-93-gradle-cache-pilot",
            "head_sha": head_sha,
            "run_attempt": 1,
            "status": "completed",
            "conclusion": "success",
        }
        pr_runs = [
            {"workflow_runs": [{
                "id": 100,
                "event": "pull_request",
                "pull_requests": [{"number": 7, "head": {"sha": head_sha}}],
            }]},
            {"workflow_runs": []},
        ]

        run_id = control.resolve_seed_campaign(
            [{"workflow_runs": [seed]}], pr_runs,
            head_sha=head_sha, pr_number="7", current_run_id="100",
        )

        self.assertEqual(run_id, "42")

    def test_seed_campaign_selection_rejects_duplicate_campaigns_and_retries(self) -> None:
        head_sha = "a" * 40
        seed = {
            "id": 42,
            "event": "push",
            "head_branch": "codex/issue-93-gradle-cache-pilot",
            "head_sha": head_sha,
            "run_attempt": 1,
            "status": "completed",
            "conclusion": "success",
        }
        duplicate = {**seed, "id": 43, "conclusion": "failure"}
        with self.assertRaises(control.SafetyError):
            control.resolve_seed_campaign(
                [{"workflow_runs": [seed]}, {"workflow_runs": [duplicate]}], [],
                head_sha=head_sha, pr_number="7", current_run_id="100",
            )

        retried = {**seed, "run_attempt": 2}
        with self.assertRaises(control.SafetyError):
            control.resolve_seed_campaign(
                [{"workflow_runs": [retried]}], [],
                head_sha=head_sha, pr_number="7", current_run_id="100",
            )

    def test_seed_campaign_selection_rejects_prior_consumer_on_later_history_page(self) -> None:
        head_sha = "a" * 40
        seed = {
            "id": 42,
            "event": "push",
            "head_branch": "codex/issue-93-gradle-cache-pilot",
            "head_sha": head_sha,
            "run_attempt": 1,
            "status": "completed",
            "conclusion": "success",
        }
        prior_pr = {
            "id": 99,
            "event": "pull_request",
            "pull_requests": [{"number": 7, "head": {"sha": "b" * 40}}],
        }
        with self.assertRaises(control.SafetyError):
            control.resolve_seed_campaign(
                [{"workflow_runs": [seed]}], [{"workflow_runs": []}, {"workflow_runs": [prior_pr]}],
                head_sha=head_sha, pr_number="7", current_run_id="100",
            )

    def test_trusted_seed_record_rejects_another_push_run_id(self) -> None:
        record_path = control._task_root() / "trusted-seed-manifest.json"
        record_path.write_text(json.dumps({
            "schema": 1,
            "campaign_id": "gradle-dependency-cache-pilot-v1",
            "seed_run_id": "42",
            "seed_run_attempt": 1,
            "seed_source_sha": "a" * 40,
            "seed_branch": "refs/heads/codex/issue-93-gradle-cache-pilot",
            "cache_key": "expected-key",
            "manifest_sha256": "b" * 64,
            "manifest_files": 1,
            "manifest_bytes": 10,
            "archive_expanded_bytes": 10,
        }), encoding="utf-8")

        with contextlib.redirect_stdout(io.StringIO()), self.assertRaises(control.SafetyError):
            control.command_verify_seed_record(Namespace(
                path=str(record_path), expected_source_sha="a" * 40,
                expected_cache_key="expected-key", expected_run_id="43",
            ))

    def test_trusted_seed_record_rejects_malformed_expanded_byte_count(self) -> None:
        manifest_path = control._task_root() / "modules-manifest.json"
        record_path = control._task_root() / "trusted-seed-manifest.json"
        source_sha = "a" * 40
        base_manifest = {
            "format": 1,
            "sha256": "b" * 64,
            "files": 1,
            "bytes": 10,
            "expanded_bytes": 10,
        }
        with patch.dict(os.environ, {
            "GITHUB_SHA": source_sha,
            "GITHUB_REF": "refs/heads/codex/issue-93-gradle-cache-pilot",
            "GITHUB_RUN_ID": "42",
            "GITHUB_RUN_ATTEMPT": "1",
            "EXPERIMENT_CAMPAIGN_ID": "gradle-dependency-cache-pilot-v1",
        }), contextlib.redirect_stdout(io.StringIO()):
            for expanded_bytes in (None, "10", True, control.MODULE_CACHE_LIMIT + 1):
                with self.subTest(expanded_bytes=expanded_bytes):
                    manifest = {**base_manifest, "expanded_bytes": expanded_bytes}
                    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
                    with self.assertRaises(control.SafetyError):
                        control.command_write_seed_record(Namespace(
                            manifest=str(manifest_path), cache_key="expected-key",
                            output=str(record_path),
                        ))

    def test_pr_source_evidence_keeps_head_base_merge_and_checkout_identities(self) -> None:
        head = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=Path(__file__).resolve().parents[2],
            text=True,
            stdout=subprocess.PIPE,
            check=True,
        ).stdout.strip()
        with contextlib.redirect_stdout(io.StringIO()):
            control.command_record_pr_identities(Namespace(
                head_sha=head,
                base_sha="b" * 40,
                merge_sha="c" * 40,
                github_sha="d" * 40,
                seed_source_sha=head,
                seed_run_id="42",
            ))

        evidence = json.loads((control._task_root() / "evidence.json").read_text(encoding="utf-8"))
        self.assertEqual(evidence["pr_head_sha"], head)
        self.assertEqual(evidence["checked_out_source_sha"], head)
        self.assertEqual(evidence["pr_base_sha"], "b" * 40)
        self.assertEqual(evidence["pr_merge_sha"], "c" * 40)
        self.assertEqual(evidence["pr_github_sha"], "d" * 40)

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

    def test_read_only_canary_step_skip_is_reported_without_inference(self) -> None:
        args = Namespace(
            cache_mode="read",
            save_outcome="skipped",
            readback_outcome="success",
            cache_hit="",
            matched_key="",
            primary_key="canary-key",
        )
        with contextlib.redirect_stdout(io.StringIO()):
            control.command_classify_read_only_canary(args)
        evidence = json.loads((control._task_root() / "evidence.json").read_text(encoding="utf-8"))
        self.assertEqual(evidence["read_only_canary_classification"], "save_step_skipped_readback_miss")
        self.assertFalse(evidence["cache_service_denial_claimed"])

    def test_read_only_canary_success_without_readback_is_unresolved(self) -> None:
        args = Namespace(
            cache_mode="read",
            save_outcome="success",
            readback_outcome="success",
            cache_hit="",
            matched_key="",
            primary_key="canary-key",
        )
        with contextlib.redirect_stdout(io.StringIO()), self.assertRaises(control.SafetyError):
            control.command_classify_read_only_canary(args)
        evidence = json.loads((control._task_root() / "evidence.json").read_text(encoding="utf-8"))
        self.assertEqual(
            evidence["read_only_canary_classification"],
            "save_succeeded_readback_miss_unresolved",
        )
        self.assertFalse(evidence["cache_service_denial_claimed"])

    def test_partial_cleanup_failure_blocks_gradle_sentinel(self) -> None:
        with contextlib.redirect_stdout(io.StringIO()):
            control.command_simulate_partial(Namespace())
        with patch("scripts.gradle_dependency_cache.control.shutil.rmtree", side_effect=PermissionError("fixture")):
            with contextlib.redirect_stdout(io.StringIO()), self.assertRaises(control.SafetyError):
                control.command_partial_cleanup_failure(Namespace())

        marker = control._task_root() / "gradle-sentinel-ran"
        args = Namespace(
            cleanup_outcome="failure",
            sentinel_outcome="skipped",
            marker=str(marker),
        )
        with contextlib.redirect_stdout(io.StringIO()):
            control.command_verify_partial_sentinel(args)

        self.assertFalse(marker.exists())
        self.assertTrue(self.modules.exists())
        evidence = json.loads((control._task_root() / "evidence.json").read_text(encoding="utf-8"))
        self.assertEqual(evidence["partial_cleanup_outcome"], "expected_failure")
        self.assertTrue(evidence["gradle_sentinel_blocked"])

    def test_cold_observer_requires_target_transfer_and_cached_digest(self) -> None:
        target = "nativeruntime-dist-compat-1.0.18.jar"
        target_bytes = b"trusted target artifact bytes"
        filename_hash = hashlib.sha256(target.encode("utf-8")).hexdigest()
        module_file = (
            self.modules / "files-2.1" / "org.robolectric" / "nativeruntime-dist-compat"
            / "1.0.18" / hashlib.sha256(target_bytes).hexdigest() / target
        )
        module_file.parent.mkdir(parents=True)
        module_file.write_bytes(target_bytes)

        records, invocations = self._valid_observer_records()
        records.append({
            "event": "external_resource_read",
            "invocation_id": "probe_build-1",
            "invocation_label": "probe_build",
            "artifact_body": True,
            "artifact_coordinate": "org.robolectric:nativeruntime-dist-compat:1.0.18",
            "artifact_filename_sha256": filename_hash,
            "resource_sha256": hashlib.sha256(b"redacted-url").hexdigest(),
            "result_state": "completed",
            "bytes_read_known": True,
            "bytes_read": len(target_bytes),
        })
        self._write_observer_fixture(records, invocations)

        with patch.dict(os.environ, {"GRADLE_OBSERVER_OUTPUT": str(self.root / "observer.jsonl")}), contextlib.redirect_stdout(io.StringIO()):
            control.command_verify_observer(Namespace(mode="cold"))

        evidence = json.loads((control._task_root() / "evidence.json").read_text(encoding="utf-8"))
        correlation = evidence["target_artifact_correlation"]
        self.assertEqual(correlation["transfer_bytes"], len(target_bytes))
        self.assertEqual(correlation["cached_files"][0]["sha256"], hashlib.sha256(target_bytes).hexdigest())
        self.assertEqual(correlation["coordinate"], "org.robolectric:nativeruntime-dist-compat:1.0.18")

    def test_cold_observer_rejects_unrelated_artifact_body_as_target_evidence(self) -> None:
        records, invocations = self._valid_observer_records()
        records.append({
            "event": "external_resource_read",
            "invocation_id": "probe_build-1",
            "invocation_label": "probe_build",
            "artifact_body": True,
            "artifact_coordinate": "com.example:other:1.0",
            "resource_sha256": hashlib.sha256(b"unrelated").hexdigest(),
            "result_state": "completed",
            "bytes_read_known": True,
            "bytes_read": 15,
        })
        self._write_observer_fixture(records, invocations)

        with patch.dict(os.environ, {"GRADLE_OBSERVER_OUTPUT": str(self.root / "observer.jsonl")}), contextlib.redirect_stdout(io.StringIO()), self.assertRaises(control.SafetyError):
            control.command_verify_observer(Namespace(mode="cold"))

    def test_cold_observer_rejects_conflicting_cached_target_digests(self) -> None:
        target = "nativeruntime-dist-compat-1.0.18.jar"
        target_bytes = b"trusted target artifact bytes"
        target_directory = (
            self.modules / "files-2.1" / "org.robolectric" / "nativeruntime-dist-compat" / "1.0.18"
        )
        for digest, content in (
            (hashlib.sha256(target_bytes).hexdigest(), target_bytes),
            ("f" * 64, b"x" * len(target_bytes)),
        ):
            artifact = target_directory / digest / target
            artifact.parent.mkdir(parents=True)
            artifact.write_bytes(content)

        records, invocations = self._valid_observer_records()
        records.append({
            "event": "external_resource_read",
            "invocation_id": "probe_build-1",
            "invocation_label": "probe_build",
            "artifact_body": True,
            "artifact_coordinate": "org.robolectric:nativeruntime-dist-compat:1.0.18",
            "artifact_filename_sha256": hashlib.sha256(target.encode("utf-8")).hexdigest(),
            "resource_sha256": hashlib.sha256(b"redacted-url").hexdigest(),
            "result_state": "completed",
            "bytes_read_known": True,
            "bytes_read": len(target_bytes),
        })
        self._write_observer_fixture(records, invocations)

        with patch.dict(os.environ, {"GRADLE_OBSERVER_OUTPUT": str(self.root / "observer.jsonl")}), contextlib.redirect_stdout(io.StringIO()), self.assertRaises(control.SafetyError):
            control.command_verify_observer(Namespace(mode="cold"))

    def test_observer_requires_readiness_and_records_for_every_invocation(self) -> None:
        records, invocations = self._valid_observer_records()
        records = [
            {**record, "invocation_id": "wrong-invocation"}
            if record.get("event") == "observer_ready" and record.get("invocation_id") == "dry_run-1"
            else record
            for record in records
        ]
        self._write_observer_fixture(records, invocations)

        with patch.dict(os.environ, {"GRADLE_OBSERVER_OUTPUT": str(self.root / "observer.jsonl")}), contextlib.redirect_stdout(io.StringIO()), self.assertRaises(control.SafetyError):
            control.command_verify_observer(Namespace(mode="warm"))

    def test_warm_observer_rejects_any_artifact_body_transfer(self) -> None:
        records, invocations = self._valid_observer_records()
        records.append({
            "event": "external_resource_read",
            "invocation_id": "probe_build-1",
            "invocation_label": "probe_build",
            "artifact_body": True,
            "artifact_coordinate": "org.robolectric:nativeruntime-dist-compat:1.0.18",
            "resource_sha256": hashlib.sha256(b"target").hexdigest(),
            "result_state": "completed",
            "bytes_read_known": True,
            "bytes_read": 0,
        })
        self._write_observer_fixture(records, invocations)

        with patch.dict(os.environ, {"GRADLE_OBSERVER_OUTPUT": str(self.root / "observer.jsonl")}), contextlib.redirect_stdout(io.StringIO()), self.assertRaises(control.SafetyError):
            control.command_verify_observer(Namespace(mode="warm"))

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

    def _valid_observer_records(self) -> tuple[list[dict[str, object]], list[dict[str, object]]]:
        labels = ("task_inventory", "dry_run", "probe_build")
        records: list[dict[str, object]] = []
        invocations: list[dict[str, object]] = []
        for label in labels:
            invocation_id = f"{label}-1"
            records.extend([
                {"event": "runner_invocation_start", "invocation_id": invocation_id, "label": label},
                {"event": "observer_ready", "invocation_id": invocation_id, "invocation_label": label, "gradle": "9.1.0"},
                {"event": "runner_invocation_finish", "invocation_id": invocation_id, "label": label, "exit_code": 0},
            ])
            task_outcomes = []
            if label == "probe_build":
                task_outcomes = [
                    {"task": name, "outcome": "SUCCESS"}
                    for name in ("testProbeUnitTest", "lintProbe", "assembleProbe")
                ]
            invocations.append({
                "invocation_id": invocation_id,
                "label": label,
                "exit_code": 0,
                "elapsed_seconds": 1.0,
                "task_outcomes": task_outcomes,
            })
        return records, invocations

    def _write_observer_fixture(self, records: list[dict[str, object]], invocations: list[dict[str, object]]) -> None:
        output = self.root / "observer.jsonl"
        output.write_text("".join(json.dumps(record) + "\n" for record in records), encoding="utf-8")
        control._write_evidence({"gradle_invocations": invocations})


if __name__ == "__main__":
    unittest.main()
