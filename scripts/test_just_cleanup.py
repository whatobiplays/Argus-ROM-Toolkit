"""Contract tests for the repository Just cleanup entrypoints.

The tests build disposable Git repositories and invoke the real helper copied
into each fixture.  No test targets the developer checkout for preview or
deletion.
"""

from __future__ import annotations

import hashlib
import importlib.util
import io
import json
import os
import shlex
import shutil
import socket
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
CLEANUP_HELPER = REPOSITORY_ROOT / "scripts" / "just_cleanup.py"
CLEANUP_POLICY = REPOSITORY_ROOT / "scripts" / "just_cleanup_policy.py"
def _hash_tree(root: Path) -> dict[str, str]:
    """Snapshot cleanup-managed fixture content, excluding Git metadata."""

    snapshot: dict[str, str] = {}
    if not root.exists():
        return snapshot
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root).as_posix()
        if relative == ".git" or relative.startswith(".git/"):
            continue
        if path.is_symlink():
            snapshot[relative] = f"symlink:{os.readlink(path)}"
        elif path.is_file():
            snapshot[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
        elif path.is_dir():
            snapshot[relative] = "directory"
    return snapshot


def _category(report: dict[str, object], name: str) -> list[dict[str, object]]:
    for category in report["categories"]:
        if category["name"] == name:
            return category["paths"]
    raise AssertionError(f"Missing report category {name!r}")


def _load_cleanup_module():
    specification = importlib.util.spec_from_file_location(
        "argus_just_cleanup",
        CLEANUP_HELPER,
    )
    if specification is None or specification.loader is None:
        raise AssertionError("Could not load cleanup helper")
    module = importlib.util.module_from_spec(specification)
    sys.modules[specification.name] = module
    specification.loader.exec_module(module)
    return module


class DisposableGitRepository:
    """Create an isolated checkout that owns the production cleanup helper."""

    def __init__(self, *, prefix: str = "argus cleanup fixture ") -> None:
        self._temporary_directory = tempfile.TemporaryDirectory(
            prefix=prefix,
            ignore_cleanup_errors=True,
        )
        self.root = Path(self._temporary_directory.name).resolve()
        self._run_git("init", "-q")
        self._run_git("config", "user.email", "cleanup-tests@example.invalid")
        self._run_git("config", "user.name", "Cleanup Tests")

        scripts = self.root / "scripts"
        scripts.mkdir()
        shutil.copyfile(CLEANUP_HELPER, scripts / CLEANUP_HELPER.name)
        shutil.copyfile(CLEANUP_POLICY, scripts / CLEANUP_POLICY.name)
        (self.root / ".gitignore").write_text(
            "rust/target/\n"
            "flutter/build/app/intermediates/\n"
            "flutter/build/macos/Build/Intermediates.noindex/\n"
            "flutter/build/app/outputs/\n"
            "flutter/build/native-jni/\n"
            "flutter/build/qualification/\n"
            "flutter/.dart_tool/\n"
            "flutter/android/.gradle/\n"
            "flutter/android/.kotlin/\n"
            "flutter/.fvm/\n"
            "scripts/**/__pycache__/\n",
            encoding="utf-8",
        )
        self.write_justfile(self.default_justfile())
        self._run_git("add", ".")
        self._run_git("commit", "-q", "-m", "fixture")

    def close(self) -> None:
        self._temporary_directory.cleanup()

    def _run_git(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["git", "-C", str(self.root), *arguments],
            check=True,
            capture_output=True,
            text=True,
        )

    @staticmethod
    def default_justfile() -> str:
        return """\
set shell := ["bash", "-uc"]

clean-preview:
    @python3 "{{justfile_directory()}}/scripts/just_cleanup.py" preview

clean-deep-preview:
    @python3 "{{justfile_directory()}}/scripts/just_cleanup.py" preview-deep

clean-preview-deep: clean-deep-preview

clean:
    @python3 "{{justfile_directory()}}/scripts/just_cleanup.py" apply

clean-deep:
    @python3 "{{justfile_directory()}}/scripts/just_cleanup.py" apply-deep
"""

    @staticmethod
    def isolated_environment(extra: dict[str, str] | None = None) -> dict[str, str]:
        """Build an isolated child environment for one disposable fixture."""

        environment = os.environ.copy()
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        if extra:
            environment.update(extra)
        return environment

    def write_justfile(self, content: str) -> None:
        (self.root / "justfile").write_text(content, encoding="utf-8")

    def run_just(
        self,
        recipe: str,
        *,
        cwd: Path | None = None,
        environment: dict[str, str] | None = None,
        timeout: float = 20.0,
    ) -> subprocess.CompletedProcess[str]:
        command = [
            "just",
            "--justfile",
            str(self.root / "justfile"),
            "--working-directory",
            str(self.root),
            recipe,
        ]
        process_environment = self.isolated_environment(environment)
        return subprocess.run(
            command,
            cwd=cwd or self.root,
            env=process_environment,
            capture_output=True,
            text=True,
            timeout=timeout,
        )


    def run_helper(
        self,
        *arguments: str,
        environment: dict[str, str] | None = None,
        timeout: float = 20.0,
    ) -> subprocess.CompletedProcess[str]:
        process_environment = self.isolated_environment(environment)
        return subprocess.run(
            [
                sys.executable,
                str(self.root / "scripts" / CLEANUP_HELPER.name),
                *arguments,
            ],
            cwd=self.root,
            env=process_environment,
            capture_output=True,
            text=True,
            timeout=timeout,
        )


@unittest.skipIf(
    os.name == "nt",
    "Safe inspection and deletion filesystem primitives are POSIX-only.",
)
class CleanupEntrypointTests(unittest.TestCase):
    def setUp(self) -> None:
        self.repository = DisposableGitRepository()
        self.addCleanup(self.repository.close)

    def _write(self, relative: str, content: bytes) -> Path:
        path = self.repository.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        return path

    def test_preview_creates_no_bytecode_through_just_or_direct_cli(self) -> None:
        entrypoints = ("just", "direct")
        for name in entrypoints:
            with self.subTest(entrypoint=name):
                repository = DisposableGitRepository()
                try:
                    (repository.root / "rust/target/debug/preview.rlib").parent.mkdir(
                        parents=True
                    )
                    (repository.root / "rust/target/debug/preview.rlib").write_bytes(
                        b"preview artifact"
                    )
                    environment = repository.isolated_environment()
                    environment.pop("PYTHONDONTWRITEBYTECODE", None)
                    environment.pop("PYTHONPYCACHEPREFIX", None)
                    before = _hash_tree(repository.root)
                    command = (
                        [
                            "just",
                            "--justfile",
                            str(repository.root / "justfile"),
                            "--working-directory",
                            str(repository.root),
                            "clean-preview",
                        ]
                        if name == "just"
                        else [
                            sys.executable,
                            str(
                                repository.root
                                / "scripts"
                                / CLEANUP_HELPER.name
                            ),
                            "preview",
                        ]
                    )
                    result = subprocess.run(
                        command,
                        cwd=repository.root,
                        env=environment,
                        capture_output=True,
                        text=True,
                        timeout=20,
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)
                    after = _hash_tree(repository.root)
                    self.assertEqual(after, before)
                    self.assertFalse(
                        any("__pycache__" in path for path in after),
                        after,
                    )
                finally:
                    repository.close()

    def test_preview_uses_the_deletion_policy_without_changing_the_checkout(self) -> None:
        self._write("rust/target/debug/libargus_bridge.rlib", b"rust output")
        self._write("flutter/build/app/intermediates/dex/classes.dex", b"compiler output")
        self._write("scripts/example/__pycache__/module.pyc", b"python bytecode")
        self._write("flutter/build/app/outputs/flutter-apk/app-debug.apk", b"debug apk")
        self._write("flutter/build/qualification/evidence.bin", b"qualification")
        before = _hash_tree(self.repository.root)

        result = self.repository.run_just("clean-preview", cwd=Path(tempfile.gettempdir()))

        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report["mode"], "preview")
        self.assertTrue(report["snapshot_reliable"])
        selected = {
            item["path"]
            for category in report["categories"]
            for item in category["paths"]
            if item["action"] == "selected"
        }
        self.assertIn("rust/target", selected)
        self.assertIn("flutter/build/app/intermediates", selected)
        self.assertIn("scripts/example/__pycache__", selected)
        self.assertNotIn("flutter/build/app/outputs", selected)
        self.assertNotIn("flutter/build/qualification", selected)
        self.assertNotIn("flutter/build/native-jni", selected)
        self.assertGreater(report["estimated_bytes"], 0)
        self.assertNotIn("verified_reclaimed_bytes", report)
        self.assertEqual(_hash_tree(self.repository.root), before)

    def test_nested_scripts_python_cache_is_ignored_and_cleanup_eligible(self) -> None:
        shutil.copyfile(REPOSITORY_ROOT / ".gitignore", self.repository.root / ".gitignore")
        self.repository._run_git("add", ".gitignore")
        self.repository._run_git("commit", "-q", "-m", "production ignore policy")
        nested_cache = Path("scripts/android_qualification/__pycache__")
        nested_cache_path = nested_cache.as_posix()
        self._write(
            f"{nested_cache_path}/qualification.cpython-314.pyc",
            b"python bytecode",
        )

        ignore_result = subprocess.run(
            [
                "git",
                "-C",
                str(self.repository.root),
                "check-ignore",
                "-q",
                "--",
                nested_cache_path,
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(ignore_result.returncode, 0, ignore_result.stderr)

        result = self.repository.run_just("clean")

        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        selected = {
            item["path"]
            for category in report["categories"]
            for item in category["paths"]
            if item["action"] == "selected"
        }
        self.assertIn(nested_cache_path, selected)
        self.assertNotIn(nested_cache_path, _hash_tree(self.repository.root))

    def test_clean_removes_selected_outputs_and_retains_siblings_byte_identically(
        self,
    ) -> None:
        self._write("rust/target/debug/rust-output.rlib", b"rust output")
        self._write(
            "flutter/build/app/intermediates/dex/classes.dex",
            b"compiler output",
        )
        self._write("scripts/example/__pycache__/module.pyc", b"python bytecode")
        protected = {
            "flutter/build/app/outputs/flutter-apk/app-debug.apk": b"debug apk",
            "flutter/build/app/outputs/flutter-apk/app-release.apk": b"release apk",
            "flutter/build/qualification/argus-qualification.apk": b"qualification apk",
            "flutter/build/qualification/native-build.json": b"qualification metadata",
            "flutter/build/native-jni/release/native-build.json": b"jni metadata",
            "flutter/.dart_tool/package_config.json": b"default retained tool state",
            "flutter/build/unknown/sentinel.bin": b"unknown sentinel",
        }
        for relative, content in protected.items():
            self._write(relative, content)

        result = self.repository.run_just("clean")

        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report["mode"], "apply")
        self.assertGreater(report["verified_reclaimed_bytes"], 0)
        self.assertNotIn("rust/target", _hash_tree(self.repository.root))
        self.assertNotIn(
            "flutter/build/app/intermediates",
            _hash_tree(self.repository.root),
        )
        self.assertNotIn("scripts/example/__pycache__", _hash_tree(self.repository.root))
        for relative, content in protected.items():
            with self.subTest(path=relative):
                self.assertEqual((self.repository.root / relative).read_bytes(), content)


    def test_deep_cleanup_expands_only_declared_project_caches(self) -> None:
        self._write("flutter/.dart_tool/package_config.json", b"dart state")
        self._write("flutter/.dart_tool/flutter_build/" + "a" * 64 + "/generated.dill", b"build output")
        self._write("flutter/android/.gradle/caches/cache.bin", b"gradle state")
        self._write("flutter/android/.kotlin/sessions/session.bin", b"kotlin state")
        protected = {
            "flutter/.fvm/flutter_sdk/bin/flutter": b"pinned sdk",
            "build/root-output.bin": b"root build retained",
            "flutter/build/app/outputs/flutter-apk/app-debug.apk": b"debug apk",
            "flutter/build/qualification/evidence.json": b"qualification",
            "flutter/build/native-jni/release/native-build.json": b"jni metadata",
        }
        for relative, content in protected.items():
            self._write(relative, content)

        result = self.repository.run_just("clean-deep")

        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report["mode"], "apply-deep")
        self.assertTrue(any("regeneration" in warning.lower() for warning in report["warnings"]))
        for removed in (
            "flutter/.dart_tool/flutter_build",
            "flutter/android/.gradle",
            "flutter/android/.kotlin",
        ):
            with self.subTest(removed=removed):
                self.assertFalse((self.repository.root / removed).exists())
        self.assertEqual(
            (self.repository.root / "flutter/.dart_tool/package_config.json").read_bytes(),
            b"dart state",
        )
        for relative, content in protected.items():
            with self.subTest(retained=relative):
                self.assertEqual((self.repository.root / relative).read_bytes(), content)

    def test_rust_candidate_preserves_nested_credentials_databases_and_roms(self) -> None:
        protected = {
            "rust/target/debug/.env.local": b"secret",
            "rust/target/debug/.git-credentials": b"token",
            "rust/target/debug/library.sqlite": b"database",
            "rust/target/debug/private-signing.jks": b"signing key",
            "rust/target/debug/notes.apk": b"unexpected package",
            "rust/target/roms/game.rom": b"rom data",
            "rust/target/qualification/native-build.json": b"qualification evidence",
        }
        for relative, content in protected.items():
            self._write(relative, content)

        result = self.repository.run_just("clean")

        self.assertNotEqual(result.returncode, 0)
        report = json.loads(result.stdout)
        rust = _category(report, "rust")[0]
        self.assertEqual(rust["outcome"], "failed")
        self.assertTrue(rust["errors"])
        for relative, content in protected.items():
            with self.subTest(path=relative):
                self.assertEqual((self.repository.root / relative).read_bytes(), content)

    def test_rust_incremental_candidate_preserves_roms_archives_and_packages(
        self,
    ) -> None:
        for filename in ("game.gba", "release.zip", "release.apk"):
            with self.subTest(filename=filename):
                repository = DisposableGitRepository()
                try:
                    relative = f"rust/target/debug/incremental/{filename}"
                    content = f"protected {filename}".encode()
                    path = repository.root / relative
                    path.parent.mkdir(parents=True)
                    path.write_bytes(content)

                    result = repository.run_just("clean")

                    self.assertNotEqual(result.returncode, 0)
                    report = json.loads(result.stdout)
                    rust = _category(report, "rust")[0]
                    self.assertEqual(rust["outcome"], "failed")
                    self.assertEqual(path.read_bytes(), content)
                finally:
                    repository.close()

    def test_python_cache_candidate_removes_bytecode_only(self) -> None:
        bytecode = self._write("scripts/example/__pycache__/module.pyc", b"bytecode")
        secret = self._write("scripts/example/__pycache__/.env.local", b"secret")

        result = self.repository.run_just("clean")

        self.assertNotEqual(result.returncode, 0)
        report = json.loads(result.stdout)
        cache = _category(report, "python")[0]
        self.assertEqual(cache["outcome"], "failed")
        self.assertEqual(bytecode.read_bytes(), b"bytecode")
        self.assertEqual(secret.read_bytes(), b"secret")

        unexpected = self._write("scripts/example/__pycache__/source.py", b"source")
        result = self.repository.run_just("clean")
        self.assertNotEqual(result.returncode, 0)
        report = json.loads(result.stdout)
        cache = _category(report, "python")[0]
        self.assertEqual(cache["outcome"], "failed")
        self.assertEqual(unexpected.read_bytes(), b"source")

    def test_apply_rejects_protected_state_credentials_and_unexpected_content(
        self,
    ) -> None:
        cases = (
            ("rust/target", "clean", "rust/target/debug/settings.local"),
            ("rust/target", "clean", "rust/target/debug/.envrc"),
            ("rust/target", "clean", "rust/target/.chatgpt/state.json"),
            ("rust/target", "clean", "rust/target/.codex/state.json"),
            ("rust/target", "clean", "rust/target/.superpowers/state.json"),
            ("rust/target", "clean", "rust/target/debug/signing.pem"),
            ("rust/target", "clean", "rust/target/debug/unexpected.bin"),
            (
                "flutter/build/app/intermediates",
                "clean",
                "flutter/build/app/intermediates/foreign/sentinel.bin",
            ),
            (
                "flutter/build/app/intermediates",
                "clean",
                "flutter/build/app/intermediates/unexpected.dat",
            ),
            (
                "flutter/build/macos/Build/Intermediates.noindex",
                "clean",
                "flutter/build/macos/Build/Intermediates.noindex/unknown/sentinel.bin",
            ),
            (
                "flutter/.dart_tool/flutter_build",
                "clean-deep",
                "flutter/.dart_tool/flutter_build/foreign/sentinel.bin",
            ),
            (
                "flutter/android/.gradle",
                "clean-deep",
                "flutter/android/.gradle/unexpected.zzz",
            ),
            (
                "flutter/android/.kotlin",
                "clean-deep",
                "flutter/android/.kotlin/unexpected.zzz",
            ),
        )
        for candidate_path, command, relative in cases:
            with self.subTest(path=relative):
                repository = DisposableGitRepository()
                try:
                    retained = repository.root / relative
                    retained.parent.mkdir(parents=True, exist_ok=True)
                    retained.write_bytes(b"retained fixture")

                    result = repository.run_just(command)

                    self.assertNotEqual(result.returncode, 0)
                    report = json.loads(result.stdout)
                    candidate = next(
                        item
                        for category in report["categories"]
                        for item in category["paths"]
                        if item["path"] == candidate_path
                    )
                    self.assertEqual(candidate["action"], "failed", report)
                    self.assertTrue(candidate.get("error"))
                    self.assertEqual(retained.read_bytes(), b"retained fixture")
                finally:
                    repository.close()

    def test_apply_rejects_protected_and_unclassified_nested_content(self) -> None:
        cases = (
            (
                "clean",
                "rust/target",
                "rust/target/debug/output.rlib",
                "rust/target/debug/.env.production",
            ),
            (
                "clean",
                "rust/target",
                "rust/target/debug/output.rlib",
                "rust/target/debug/settings.local",
            ),
            (
                "clean",
                "rust/target",
                "rust/target/debug/output.rlib",
                "rust/target/.chatgpt/state.json",
            ),
            (
                "clean",
                "rust/target",
                "rust/target/debug/output.rlib",
                "rust/target/.codex/state.json",
            ),
            (
                "clean",
                "rust/target",
                "rust/target/debug/output.rlib",
                "rust/target/.superpowers/state.json",
            ),
            (
                "clean",
                "rust/target",
                "rust/target/debug/output.rlib",
                "rust/target/debug/signing.pem",
            ),
            (
                "clean",
                "rust/target",
                "rust/target/debug/output.rlib",
                "rust/target/foreign.json",
            ),
            (
                "clean",
                "flutter/build/app/intermediates",
                "flutter/build/app/intermediates/dex/classes.dex",
                "flutter/build/app/intermediates/vendor/state.json",
            ),
            (
                "clean",
                "flutter/build/macos/Build/Intermediates.noindex",
                "flutter/build/macos/Build/Intermediates.noindex/"
                "Sample.build/Objects-normal/arm64/sample.o",
                "flutter/build/macos/Build/Intermediates.noindex/"
                "Sample.build/identity.key",
            ),
            (
                "clean-deep",
                "flutter/.dart_tool/flutter_build",
                "flutter/.dart_tool/flutter_build/" + "a" * 64 + "/generated.dill",
                "flutter/.dart_tool/flutter_build/vendor/state.json",
            ),
            (
                "clean-deep",
                "flutter/android/.gradle",
                "flutter/android/.gradle/caches/cache.bin",
                "flutter/android/.gradle/vendor/state.json",
            ),
            (
                "clean-deep",
                "flutter/android/.kotlin",
                "flutter/android/.kotlin/sessions/session.bin",
                "flutter/android/.kotlin/vendor/state.json",
            ),
            (
                "clean",
                "scripts/example/__pycache__",
                "scripts/example/__pycache__/module.pyc",
                "scripts/example/__pycache__/vendor/state.pyc",
            ),
        )
        for command, candidate_path, producer_output, retained_path in cases:
            with self.subTest(retained=retained_path):
                repository = DisposableGitRepository()
                try:
                    for relative, content in (
                        (producer_output, b"recognized producer output"),
                        (retained_path, b"content that must be retained"),
                    ):
                        path = repository.root / relative
                        path.parent.mkdir(parents=True, exist_ok=True)
                        path.write_bytes(content)

                    result = repository.run_just(command)

                    self.assertNotEqual(result.returncode, 0)
                    report = json.loads(result.stdout)
                    candidate = next(
                        item
                        for category in report["categories"]
                        for item in category["paths"]
                        if item["path"] == candidate_path
                    )
                    self.assertEqual(candidate["action"], "failed", report)
                    self.assertTrue(candidate.get("error"))
                    self.assertEqual(
                        (repository.root / retained_path).read_bytes(),
                        b"content that must be retained",
                    )
                finally:
                    repository.close()

    def test_deep_cleanup_retains_generator_state_in_dart_tool(self) -> None:
        protected = {
            "flutter/.dart_tool/package_config.json": b"package config",
            "flutter/.dart_tool/flutter_rust_bridge/generated.bin": b"frb state",
            "flutter/.dart_tool/cargo-ndk/toolchain.json": b"cargo ndk state",
        }
        for relative, content in protected.items():
            self._write(relative, content)

        result = self.repository.run_just("clean-deep")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("flutter/.dart_tool", _hash_tree(self.repository.root))
        retained_tree = _hash_tree(self.repository.root)
        self.assertIn(
            "flutter/.dart_tool/flutter_rust_bridge/generated.bin",
            retained_tree,
        )
        self.assertIn("flutter/.dart_tool/cargo-ndk/toolchain.json", retained_tree)
        for relative, content in protected.items():
            with self.subTest(path=relative):
                self.assertEqual((self.repository.root / relative).read_bytes(), content)

    def test_symlink_candidate_is_skipped_without_touching_its_destination(self) -> None:
        destination = self._write("release/keep.bin", b"protected destination")
        candidate = self.repository.root / "rust/target"
        candidate.parent.mkdir(parents=True)
        candidate.symlink_to(Path("../release/keep.bin"), target_is_directory=False)

        result = self.repository.run_just("clean")

        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        rust = _category(report, "rust")
        self.assertEqual(rust[0]["action"], "skipped")
        self.assertIn("symbolic link", rust[0]["reason"].lower())
        self.assertEqual(destination.read_bytes(), b"protected destination")
        self.assertTrue(candidate.is_symlink())

    def test_nested_repository_beneath_candidate_is_refused(self) -> None:
        nested = "rust/target/debug/build/fixture-0123456789abcdef/nested"
        self._write(f"{nested}/.git/HEAD", b"ref: refs/heads/main\n")
        self._write(f"{nested}/sentinel.rlib", b"nested repository")

        result = self.repository.run_just("clean")

        self.assertNotEqual(result.returncode, 0)
        report = json.loads(result.stdout)
        rust = _category(report, "rust")[0]
        self.assertEqual(rust["action"], "failed")
        self.assertIn(".git", rust["error"].lower())
        self.assertIn("retained", rust["error"].lower())
        self.assertEqual(
            (
                self.repository.root / nested / "sentinel.rlib"
            ).read_bytes(),
            b"nested repository",
        )

    def test_tracked_content_beneath_candidate_is_never_deleted(self) -> None:
        tracked = self._write("rust/target/keep.txt", b"tracked sentinel")
        self.repository._run_git("add", "-f", "rust/target/keep.txt")
        self.repository._run_git("commit", "-q", "-m", "tracked output sentinel")

        result = self.repository.run_just("clean")

        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        rust = _category(report, "rust")[0]
        self.assertEqual(rust["action"], "skipped")
        self.assertIn("tracks content", rust["reason"].lower())
        self.assertEqual(tracked.read_bytes(), b"tracked sentinel")

    def test_custom_cargo_target_directory_is_reported_and_never_modified(self) -> None:
        self._write("rust/target/debug/local.rlib", b"local target")
        external = self.repository.root.parent / "external cargo target"
        external.mkdir()
        self.addCleanup(shutil.rmtree, external, True)
        external_file = external / "keep.bin"
        external_file.write_bytes(b"external target")

        result = self.repository.run_just(
            "clean",
            environment={"CARGO_TARGET_DIR": str(external)},
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        rust = _category(report, "rust")[0]
        self.assertEqual(rust["action"], "skipped")
        self.assertIn("redirects cargo", rust["reason"].lower())
        self.assertEqual(
            (self.repository.root / "rust/target/debug/local.rlib").read_bytes(),
            b"local target",
        )
        self.assertEqual(external_file.read_bytes(), b"external target")

    def test_linked_worktree_cleanup_leaves_other_worktree_and_admin_metadata_untouched(
        self,
    ) -> None:
        main_root = self.repository.root
        linked_parent = Path(tempfile.mkdtemp(prefix="linked cleanup fixture "))
        self.addCleanup(shutil.rmtree, linked_parent, True)
        linked_root = linked_parent / "linked worktree"
        subprocess.run(
            [
                "git",
                "-C",
                str(main_root),
                "worktree",
                "add",
                "-q",
                "-b",
                "linked-cleanup-test",
                str(linked_root),
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        main_output = self._write("rust/target/debug/main-only.rlib", b"main output")
        linked_output = linked_root / "rust/target/debug/linked-only.rlib"
        linked_output.parent.mkdir(parents=True)
        linked_output.write_bytes(b"linked output")
        metadata_before = _hash_tree(main_root / ".git" / "worktrees")

        result = subprocess.run(
            [
                "just",
                "--justfile",
                str(linked_root / "justfile"),
                "--working-directory",
                str(linked_root),
                "clean",
            ],
            cwd=linked_parent,
            env=self.repository.isolated_environment(),
            capture_output=True,
            text=True,
            timeout=20,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(linked_output.exists())
        self.assertEqual(main_output.read_bytes(), b"main output")
        self.assertEqual(_hash_tree(main_root / ".git" / "worktrees"), metadata_before)

    def test_candidate_ancestor_git_boundary_retains_foreign_repository(self) -> None:
        for kind, recipe, expected_status in (
            ("linked worktree", "clean-preview", 2),
            ("linked worktree", "clean", 1),
            ("nested repository", "clean-preview", 2),
            ("nested repository", "clean", 1),
        ):
            with self.subTest(kind=kind, recipe=recipe):
                repository = DisposableGitRepository()
                try:
                    rust_root = repository.root / "rust"
                    if kind == "linked worktree":
                        subprocess.run(
                            [
                                "git",
                                "-C",
                                str(repository.root),
                                "worktree",
                                "add",
                                "-q",
                                "--detach",
                                str(rust_root),
                                "HEAD",
                            ],
                            check=True,
                            capture_output=True,
                            text=True,
                        )
                    else:
                        rust_root.mkdir()
                        subprocess.run(
                            ["git", "-C", str(rust_root), "init", "-q"],
                            check=True,
                            capture_output=True,
                            text=True,
                        )
                    foreign_output = rust_root / "target/debug/output.rlib"
                    foreign_output.parent.mkdir(parents=True)
                    foreign_output.write_bytes(b"foreign worktree output")
                    before = _hash_tree(rust_root)

                    result = repository.run_just(recipe)

                    self.assertEqual(result.returncode, expected_status, result.stderr)
                    report = json.loads(result.stdout)
                    self.assertFalse(report["snapshot_reliable"])
                    rust = _category(report, "rust")[0]
                    self.assertEqual(rust["action"], "failed", report)
                    self.assertIn(".git", rust["error"])
                    self.assertEqual(_hash_tree(rust_root), before)
                finally:
                    repository.close()

    def test_symlinked_worktree_root_resolves_to_physical_directory(self) -> None:
        cleanup = _load_cleanup_module()
        alias = self.repository.root.with_name(self.repository.root.name + "-alias")
        alias.symlink_to(self.repository.root, target_is_directory=True)
        self.addCleanup(alias.unlink, missing_ok=True)

        worktree = cleanup.discover_worktree(alias)

        self.assertEqual(worktree.root, self.repository.root)

    def test_git_query_failure_is_reported_and_preserves_candidate(self) -> None:
        cleanup = _load_cleanup_module()
        worktree = cleanup.discover_worktree(self.repository.root)
        candidate = self._write("rust/target/debug/output.rlib", b"candidate")
        real_run_git = cleanup._run_git

        def fail_ls_files(
            root: Path,
            arguments: tuple[str, ...],
            *,
            check: bool = True,
        ) -> subprocess.CompletedProcess[bytes]:
            if "ls-files" in arguments:
                raise subprocess.CalledProcessError(128, ["git", "ls-files"])
            return real_run_git(root, arguments, check=check)

        stdout = io.StringIO()
        stderr = io.StringIO()
        with (
            mock.patch.dict(
                os.environ,
                self.repository.isolated_environment(),
                clear=True,
            ),
            mock.patch.object(cleanup, "discover_worktree", return_value=worktree),
            mock.patch.object(cleanup, "_run_git", side_effect=fail_ls_files),
            mock.patch("sys.stdout", stdout),
            mock.patch("sys.stderr", stderr),
        ):
            status = cleanup._apply(deep=False)

        self.assertEqual(status, 1)
        self.assertEqual(stderr.getvalue(), "")
        report = json.loads(stdout.getvalue())
        self.assertEqual(report["status"], "failed")
        self.assertFalse(report["snapshot_reliable"])
        self.assertTrue(report["errors"])
        rust = _category(report, "rust")[0]
        self.assertEqual(rust["action"], "failed")
        self.assertEqual(candidate.read_bytes(), b"candidate")

    def test_each_producer_category_accepts_outputs_and_retains_sensitive_names(
        self,
    ) -> None:
        cases = (
            (
                "clean",
                "rust/target",
                "rust/target/debug/output.rlib",
            ),
            (
                "clean",
                "flutter/build/app/intermediates",
                "flutter/build/app/intermediates/dex/classes.dex",
            ),
            (
                "clean",
                "flutter/build/macos/Build/Intermediates.noindex",
                "flutter/build/macos/Build/Intermediates.noindex/"
                "Sample.build/Objects-normal/arm64/sample.o",
            ),
            (
                "clean-deep",
                "flutter/.dart_tool/flutter_build",
                "flutter/.dart_tool/flutter_build/" + "a" * 64 + "/generated.dill",
            ),
            (
                "clean-deep",
                "flutter/android/.gradle",
                "flutter/android/.gradle/caches/cache.bin",
            ),
            (
                "clean-deep",
                "flutter/android/.kotlin",
                "flutter/android/.kotlin/sessions/session.bin",
            ),
        )
        for command, candidate_path, producer_path in cases:
            with self.subTest(candidate=candidate_path, kind="positive"):
                repository = DisposableGitRepository()
                try:
                    output = repository.root / producer_path
                    output.parent.mkdir(parents=True, exist_ok=True)
                    output.write_bytes(b"recognized producer output")

                    result = repository.run_just(command)

                    self.assertEqual(
                        result.returncode,
                        0,
                        f"{result.stderr}\n{result.stdout}",
                    )
                    report = json.loads(result.stdout)
                    candidate = next(
                        item
                        for category in report["categories"]
                        for item in category["paths"]
                        if item["path"] == candidate_path
                    )
                    self.assertEqual(candidate["outcome"], "removed", report)
                    self.assertFalse(output.exists())
                finally:
                    repository.close()

            with self.subTest(candidate=candidate_path, kind="protected names"):
                repository = DisposableGitRepository()
                try:
                    output = repository.root / producer_path
                    output.parent.mkdir(parents=True, exist_ok=True)
                    output.write_bytes(b"recognized producer output")
                    protected_files = {
                        ".env": b"environment credentials",
                        ".env.development": b"environment credentials",
                        "developer.local": b"machine-local settings",
                        "credentials.json": b"private credentials",
                        "release-signing.properties": b"signing configuration",
                        "signing.pem": b"private signing key",
                    }
                    for filename, content in protected_files.items():
                        (output.parent / filename).write_bytes(content)

                    result = repository.run_just(command)

                    self.assertNotEqual(result.returncode, 0)
                    report = json.loads(result.stdout)
                    candidate = next(
                        item
                        for category in report["categories"]
                        for item in category["paths"]
                        if item["path"] == candidate_path
                    )
                    self.assertEqual(candidate["action"], "failed", report)
                    for filename, content in protected_files.items():
                        protected_file = output.parent / filename
                        self.assertEqual(protected_file.read_bytes(), content)
                    self.assertEqual(output.read_bytes(), b"recognized producer output")
                finally:
                    repository.close()

    def test_unreviewed_rust_subdirectories_are_retained(self) -> None:
        for relative_path in (
            "rust/target/debug/vendor/important.rlib",
            "rust/target/debug/deps/vendor/important.rlib",
        ):
            with self.subTest(relative_path=relative_path):
                repository = DisposableGitRepository()
                try:
                    output = repository.root / relative_path
                    output.parent.mkdir(parents=True)
                    output.write_bytes(b"unknown producer output")

                    result = repository.run_just("clean")

                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(output.read_bytes(), b"unknown producer output")
                    self.assertTrue((repository.root / "rust/target").is_dir())
                finally:
                    repository.close()

    def test_non_generic_suffixes_require_a_reviewed_producer_path(self) -> None:
        for command, candidate_path, output_path in (
            (
                "clean",
                "flutter/build/app/intermediates",
                "flutter/build/app/intermediates/dex/vendor/important.class",
            ),
            (
                "clean-deep",
                "flutter/android/.gradle",
                "flutter/android/.gradle/caches/vendor/important.jar",
            ),
            (
                "clean-deep",
                "flutter/android/.kotlin",
                "flutter/android/.kotlin/sessions/vendor/important.class",
            ),
            (
                "clean-deep",
                "flutter/.dart_tool/flutter_build",
                "flutter/.dart_tool/flutter_build/"
                + "a" * 64
                + "/vendor/important.dill",
            ),
            (
                "clean",
                "flutter/build/macos/Build/Intermediates.noindex",
                "flutter/build/macos/Build/Intermediates.noindex/"
                "user-abcd/important.o",
            ),
            (
                "clean",
                "flutter/build/app/intermediates",
                "flutter/build/app/intermediates/important.class",
            ),
            (
                "clean-deep",
                "flutter/.dart_tool/flutter_build",
                "flutter/.dart_tool/flutter_build/important.dill",
            ),
            (
                "clean",
                "flutter/build/app/intermediates",
                "flutter/build/app/intermediates/classes.dex",
            ),
            (
                "clean-deep",
                "flutter/.dart_tool/flutter_build",
                "flutter/.dart_tool/flutter_build/generated.dill",
            ),
        ):
            with self.subTest(candidate=candidate_path, output=output_path):
                repository = DisposableGitRepository()
                try:
                    output = repository.root / output_path
                    output.parent.mkdir(parents=True)
                    output.write_bytes(b"unclassified producer suffix")

                    result = repository.run_just(command)

                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(output.read_bytes(), b"unclassified producer suffix")
                    self.assertTrue((repository.root / candidate_path).is_dir())
                finally:
                    repository.close()

    def test_generic_data_files_require_producer_path_and_filename_signatures(
        self,
    ) -> None:
        cases = (
            (
                "clean",
                "rust/target",
                "rust/target/.fingerprint/fixture-0123456789abcdef/lib-fixture.json",
            ),
            (
                "clean",
                "flutter/build/app/intermediates",
                "flutter/build/app/intermediates/merged_manifests/debug/"
                "AndroidManifest.xml",
            ),
            (
                "clean",
                "flutter/build/macos/Build/Intermediates.noindex",
                "flutter/build/macos/Build/Intermediates.noindex/"
                "Sample.build/Objects-normal/arm64/Sample-OutputFileMap.json",
            ),
            (
                "clean-deep",
                "flutter/.dart_tool/flutter_build",
                "flutter/.dart_tool/flutter_build/outputs.json",
            ),
            (
                "clean-deep",
                "flutter/android/.gradle",
                "flutter/android/.gradle/caches/modules-2/files-2.1/"
                "org.example/widget/1.0/pom.xml",
            ),
            (
                "clean-deep",
                "flutter/android/.kotlin",
                "flutter/android/.kotlin/compiler/build-history.json",
            ),
        )
        for command, candidate_path, producer_path in cases:
            with self.subTest(candidate=candidate_path, producer_file=producer_path):
                repository = DisposableGitRepository()
                try:
                    producer_file = repository.root / producer_path
                    producer_file.parent.mkdir(parents=True)
                    producer_file.write_bytes(b"known producer metadata")

                    result = repository.run_just(command)

                    self.assertEqual(
                        result.returncode,
                        0,
                        f"{result.stderr}\n{result.stdout}",
                    )
                    report = json.loads(result.stdout)
                    candidate = next(
                        item
                        for category in report["categories"]
                        for item in category["paths"]
                        if item["path"] == candidate_path
                    )
                    self.assertEqual(candidate["outcome"], "removed", report)
                    self.assertFalse(producer_file.exists())
                finally:
                    repository.close()

    def test_unreviewed_generic_data_names_are_retained(self) -> None:
        cases = (
            (
                "clean",
                "rust/target",
                "rust/target/.fingerprint/fixture-0123456789abcdef/notes.json",
            ),
            (
                "clean",
                "flutter/build/app/intermediates",
                "flutter/build/app/intermediates/merged_manifests/debug/notes.xml",
            ),
            (
                "clean",
                "flutter/build/macos/Build/Intermediates.noindex",
                "flutter/build/macos/Build/Intermediates.noindex/"
                "Sample.build/Objects-normal/arm64/notes.json",
            ),
            (
                "clean-deep",
                "flutter/.dart_tool/flutter_build",
                "flutter/.dart_tool/flutter_build/notes.json",
            ),
            (
                "clean-deep",
                "flutter/android/.gradle",
                "flutter/android/.gradle/caches/modules-2/files-2.1/"
                "org.example/widget/1.0/notes.xml",
            ),
            (
                "clean-deep",
                "flutter/android/.kotlin",
                "flutter/android/.kotlin/compiler/notes.json",
            ),
        )
        for command, candidate_path, foreign_path in cases:
            with self.subTest(candidate=candidate_path, foreign_file=foreign_path):
                repository = DisposableGitRepository()
                try:
                    foreign_file = repository.root / foreign_path
                    foreign_file.parent.mkdir(parents=True)
                    foreign_file.write_bytes(b"unclassified generic data")

                    result = repository.run_just(command)

                    self.assertNotEqual(result.returncode, 0)
                    report = json.loads(result.stdout)
                    candidate = next(
                        item
                        for category in report["categories"]
                        for item in category["paths"]
                        if item["path"] == candidate_path
                    )
                    self.assertEqual(candidate["action"], "failed", report)
                    self.assertEqual(
                        foreign_file.read_bytes(), b"unclassified generic data"
                    )
                finally:
                    repository.close()

    def test_task_family_prefixes_require_component_boundaries(self) -> None:
        foreign = {
            "flutter/build/app/intermediates/processbackup/classes.dex": b"lowercase"
            b" sibling",
            "flutter/build/app/intermediates/process-backup/classes.dex": b"process"
            b" sibling",
            "flutter/build/app/intermediates/process_backup/classes.dex": b"underscore"
            b" sibling",
            "flutter/build/app/intermediates/merge-notes/classes.dex": b"merge sibling",
            "flutter/build/app/intermediates/validate-userdata/classes.dex": b"validate"
            b" sibling",
        }
        for command in ("clean-preview", "clean"):
            with self.subTest(command=command):
                repository = DisposableGitRepository()
                try:
                    for relative, content in foreign.items():
                        path = repository.root / relative
                        path.parent.mkdir(parents=True, exist_ok=True)
                        path.write_bytes(content)

                    result = repository.run_just(command)

                    self.assertNotEqual(result.returncode, 0)
                    report = json.loads(result.stdout)
                    candidate = next(
                        item
                        for category in report["categories"]
                        for item in category["paths"]
                        if item["path"] == "flutter/build/app/intermediates"
                    )
                    self.assertEqual(candidate["action"], "failed", report)
                    for relative, content in foreign.items():
                        self.assertEqual((repository.root / relative).read_bytes(), content)
                finally:
                    repository.close()

    def test_reviewed_task_family_directory_remains_eligible(self) -> None:
        output = self._write(
            "flutter/build/app/intermediates/processDebugResources/classes.dex",
            b"task output",
        )

        result = self.repository.run_just("clean")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(output.exists())
        self.assertFalse((self.repository.root / "flutter/build/app/intermediates").exists())

    def test_unreviewed_native_build_layouts_are_retained(self) -> None:
        foreign = {
            "flutter/build/macos/Build/Intermediates.noindex/"
            "archive.build/notes/user.log": b"archive note",
            "flutter/build/macos/Build/Intermediates.noindex/"
            "user-data.build/notes/user.log": b"user data",
            "flutter/build/macos/Build/Intermediates.noindex/"
            "Sample.build/Objects-normal/arm64/Sample.swiftmodule/user.log": (
                b"swift module child"
            ),
            "flutter/build/macos/Build/Intermediates.noindex/"
            "Sample.build/Objects-normal/arm64/Sample.swiftmodule/private/user.log": (
                b"nested swift module child"
            ),
        }
        for command in ("clean-preview", "clean"):
            with self.subTest(command=command):
                repository = DisposableGitRepository()
                try:
                    for relative, content in foreign.items():
                        path = repository.root / relative
                        path.parent.mkdir(parents=True, exist_ok=True)
                        path.write_bytes(content)

                    result = repository.run_just(command)

                    self.assertNotEqual(result.returncode, 0)
                    report = json.loads(result.stdout)
                    candidate = next(
                        item
                        for category in report["categories"]
                        for item in category["paths"]
                        if item["path"]
                        == "flutter/build/macos/Build/Intermediates.noindex"
                    )
                    self.assertEqual(candidate["action"], "failed", report)
                    for relative, content in foreign.items():
                        self.assertEqual((repository.root / relative).read_bytes(), content)
                finally:
                    repository.close()

    def test_executable_rust_fallback_requires_reviewed_parent_directory(self) -> None:
        foreign = self._write(
            "rust/target/debug/unreviewed/keep.rs",
            b"executable source data",
        )
        foreign.chmod(0o755)

        for command in ("clean-preview", "clean"):
            with self.subTest(command=command):
                result = self.repository.run_just(command)

                self.assertNotEqual(result.returncode, 0)
                report = json.loads(result.stdout)
                candidate = next(
                    item
                    for category in report["categories"]
                    for item in category["paths"]
                    if item["path"] == "rust/target"
                )
                self.assertEqual(candidate["action"], "failed", report)
                self.assertEqual(foreign.read_bytes(), b"executable source data")

    def test_direct_executable_rust_file_under_debug_remains_eligible(self) -> None:
        executable = self._write("rust/target/debug/tool", b"cargo executable")
        executable.chmod(0o755)

        result = self.repository.run_just("clean")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.repository.root / "rust/target").exists())

    def test_generic_data_suffixes_do_not_override_sensitive_names(self) -> None:
        cases = (
            ("clean", "rust/target/debug/output.rlib", "secrets.toml"),
            (
                "clean",
                "flutter/build/app/intermediates/dex/classes.dex",
                "api-token.properties",
            ),
            (
                "clean",
                "flutter/build/macos/Build/Intermediates.noindex/"
                "Sample.build/Objects-normal/arm64/sample.o",
                "private-info.plist",
            ),
            (
                "clean-deep",
                "flutter/.dart_tool/flutter_build/" + "a" * 64 + "/generated.dill",
                "private-state.yaml",
            ),
            (
                "clean-deep",
                "flutter/android/.gradle/caches/cache.bin",
                "credentials.properties",
            ),
            (
                "clean-deep",
                "flutter/android/.kotlin/sessions/session.bin",
                "auth.json",
            ),
        )
        for command, producer_path, private_name in cases:
            with self.subTest(private_name=private_name):
                repository = DisposableGitRepository()
                try:
                    output = repository.root / producer_path
                    output.parent.mkdir(parents=True, exist_ok=True)
                    output.write_bytes(b"recognized producer output")
                    private_file = output.parent / private_name
                    private_file.write_bytes(b"private state")

                    result = repository.run_just(command)

                    self.assertNotEqual(result.returncode, 0)
                    self.assertTrue(private_file.is_file())
                    self.assertEqual(private_file.read_bytes(), b"private state")
                    self.assertEqual(output.read_bytes(), b"recognized producer output")
                finally:
                    repository.close()

    def test_recursive_child_failure_prevents_false_parent_success(self) -> None:
        cleanup = _load_cleanup_module()
        worktree = cleanup.discover_worktree(self.repository.root)
        specification = cleanup.CandidateSpec(
            category="rust",
            relative_path="rust/target",
            default_clean=True,
            regeneration_note="fixture",
        )
        sibling = self._write(
            "rust/target/debug/a.rlib",
            b"sibling output",
        )
        nested = self._write(
            "rust/target/debug/deps/child.rlib",
            b"nested output",
        )
        observation = cleanup._observe_candidate(worktree, specification)
        self.assertEqual(observation.action, "selected")
        real_unlink = cleanup.os.unlink

        def fail_nested_unlink(name: str, *, dir_fd: int | None = None) -> None:
            if name == "child.rlib":
                raise PermissionError("simulated child deletion failure")
            real_unlink(name, dir_fd=dir_fd)

        with mock.patch.object(
            cleanup.os,
            "unlink",
            side_effect=fail_nested_unlink,
        ):
            outcome = cleanup.remove_candidate(worktree, observation)

        self.assertEqual(outcome.status, "partial", outcome.errors)
        self.assertEqual(outcome.verified_reclaimed_bytes, len(b"sibling output"))
        self.assertTrue(outcome.errors)
        self.assertIn(
            "child deletion failure",
            " ".join(outcome.errors).lower(),
        )
        self.assertFalse(sibling.exists())
        self.assertEqual(nested.read_bytes(), b"nested output")
        self.assertTrue((self.repository.root / "rust/target").is_dir())

        retried = cleanup.remove_candidate(worktree, observation)
        self.assertEqual(retried.status, "removed", retried.errors)
        self.assertFalse(retried.errors)
        self.assertFalse((self.repository.root / "rust/target").exists())

    def test_apply_reports_recursive_child_failure_and_retains_parent(self) -> None:
        cleanup = _load_cleanup_module()
        worktree = cleanup.discover_worktree(self.repository.root)
        sibling_payload = b"sibling output"
        nested_payload = b"nested output"
        sibling = self._write("rust/target/debug/a.rlib", sibling_payload)
        nested = self._write("rust/target/debug/deps/child.rlib", nested_payload)
        real_unlink = cleanup.os.unlink

        def fail_nested_unlink(name: str, *, dir_fd: int | None = None) -> None:
            if name == "child.rlib":
                raise PermissionError("simulated child deletion failure")
            real_unlink(name, dir_fd=dir_fd)

        stdout = io.StringIO()
        stderr = io.StringIO()
        with (
            mock.patch.dict(
                os.environ,
                self.repository.isolated_environment(),
                clear=True,
            ),
            mock.patch.object(cleanup, "discover_worktree", return_value=worktree),
            mock.patch.object(
                cleanup.os,
                "unlink",
                new=fail_nested_unlink,
            ),
            mock.patch("sys.stdout", stdout),
            mock.patch("sys.stderr", stderr),
        ):
            status = cleanup._apply(deep=False)

        self.assertEqual(status, 1)
        self.assertEqual(stderr.getvalue(), "")
        report = json.loads(stdout.getvalue())
        self.assertEqual(report["status"], "partial")
        self.assertEqual(report["verified_reclaimed_bytes"], len(sibling_payload))
        self.assertIn(
            "child deletion failure",
            " ".join(report["errors"]).lower(),
        )
        rust = _category(report, "rust")[0]
        self.assertEqual(rust["outcome"], "partial")
        self.assertEqual(rust["verified_reclaimed_bytes"], len(sibling_payload))
        self.assertIn(
            "child deletion failure",
            " ".join(rust["errors"]).lower(),
        )
        self.assertFalse(sibling.exists())
        self.assertEqual(nested.read_bytes(), nested_payload)
        self.assertTrue((self.repository.root / "rust/target").is_dir())

    def test_missing_scripts_directory_yields_no_python_candidates(self) -> None:
        cleanup = _load_cleanup_module()
        worktree = cleanup.discover_worktree(self.repository.root)
        shutil.rmtree(self.repository.root / "scripts")

        self.assertEqual(cleanup._find_python_cache_candidates(worktree), ([], []))

    def test_python_cache_walk_failure_is_reported_without_hiding_removal(self) -> None:
        if os.name == "nt" or os.geteuid() == 0:
            self.skipTest("POSIX non-root permission semantics are required.")

        for recipe, expected_status in (("clean-preview", 2), ("clean", 1)):
            with self.subTest(recipe=recipe):
                repository = DisposableGitRepository()
                try:
                    rust_output = repository.root / "rust/target/debug/output.rlib"
                    rust_output.parent.mkdir(parents=True)
                    rust_output.write_bytes(b"removable output")
                    locked = repository.root / "scripts/locked"
                    cache = locked / "__pycache__/module.pyc"
                    cache.parent.mkdir(parents=True)
                    cache.write_bytes(b"discovered bytecode")
                    locked.chmod(0)
                    try:
                        result = repository.run_just(recipe)
                    finally:
                        locked.chmod(0o700)

                    self.assertEqual(result.returncode, expected_status, result.stderr)
                    report = json.loads(result.stdout)
                    self.assertFalse(report["snapshot_reliable"])
                    python = _category(report, "python")
                    self.assertTrue(python)
                    self.assertEqual(python[0]["action"], "failed")
                    self.assertIn(
                        "python bytecode cache tree",
                        " ".join(
                            [python[0]["error"], *report.get("errors", [])]
                        ).lower(),
                    )
                    self.assertEqual(cache.read_bytes(), b"discovered bytecode")
                    if recipe == "clean-preview":
                        self.assertEqual(rust_output.read_bytes(), b"removable output")
                    else:
                        self.assertEqual(report["status"], "partial")
                        self.assertEqual(
                            report["verified_reclaimed_bytes"],
                            len(b"removable output"),
                        )
                        self.assertFalse(rust_output.exists())
                finally:
                    repository.close()

    def test_permission_denial_is_reported_as_a_retryable_failure(self) -> None:
        if os.name == "nt" or os.geteuid() == 0:
            self.skipTest("POSIX non-root permission semantics are required.")
        denied = self.repository.root / "rust/target/denied"
        denied.mkdir(parents=True)
        (denied / "file.bin").write_bytes(b"denied content")
        removable = self._write(
            "flutter/build/app/intermediates/dex/classes.dex",
            b"removable output",
        )
        denied.chmod(0)
        self.addCleanup(denied.chmod, 0o700)

        result = self.repository.run_just("clean")

        self.assertNotEqual(result.returncode, 0)
        report = json.loads(result.stdout)
        self.assertEqual(report["status"], "partial")
        self.assertTrue(report["errors"])
        denied.chmod(0o700)
        self.assertTrue((denied / "file.bin").is_file())
        self.assertFalse(removable.exists())

    def test_repeated_clean_is_a_zero_byte_idempotent_noop(self) -> None:
        self._write("rust/target/debug/output.rlib", b"output")

        first = self.repository.run_just("clean")
        second = self.repository.run_just("clean")

        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(second.returncode, 0, second.stderr)
        second_report = json.loads(second.stdout)
        self.assertEqual(second_report["verified_reclaimed_bytes"], 0)
        rust = _category(second_report, "rust")[0]
        self.assertEqual(rust["action"], "skipped")
        self.assertEqual(rust["reason"], "missing")

    def test_full_protected_content_matrix_survives_routine_cleanup(self) -> None:
        self._write("rust/target/debug/output.rlib", b"candidate")
        protected = {
            ".chatgpt/run/PROMPT.md": b"run provenance",
            ".codex/state.json": b"local agent state",
            ".env.local": b"private credentials",
            "docs/archive/qualification/evidence.bin": b"archive evidence",
            "docs/qualification/current/report.json": b"qualification record",
            "state.sqlite": b"database",
            "roms/game.rom": b"user rom",
            "flutter/lib/core/bridge/generated/frb_generated.dart": b"generated source",
            "flutter/test/fixture.bin": b"test fixture",
            "flutter/.fvm/flutter_sdk/bin/flutter": b"sdk",
            "flutter/build/app/outputs/flutter-apk/app-debug.apk": b"debug apk",
            "flutter/build/app/outputs/flutter-apk/app-release.apk": b"release apk",
            "flutter/build/qualification/argus-qualification.apk": b"qualification apk",
            "flutter/build/native-jni/release/native-build.json": b"native metadata",
            "build/root-output.bin": b"root build",
        }
        for relative, content in protected.items():
            self._write(relative, content)

        result = self.repository.run_just("clean")

        self.assertEqual(result.returncode, 0, result.stderr)
        for relative, content in protected.items():
            with self.subTest(path=relative):
                self.assertEqual((self.repository.root / relative).read_bytes(), content)

    def test_symlink_inside_candidate_is_unlinked_without_following_destination(self) -> None:
        destination = self._write("release/keep.bin", b"linked destination")
        link = self.repository.root / "rust/target/debug/deps/link.bin"
        link.parent.mkdir(parents=True)
        link.symlink_to(destination)

        result = self.repository.run_just("clean")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.repository.root / "rust/target").exists())
        self.assertEqual(destination.read_bytes(), b"linked destination")

    def test_symlink_in_candidate_parent_causes_fail_closed_refusal(self) -> None:
        external = Path(tempfile.mkdtemp(prefix="external flutter build "))
        self.addCleanup(shutil.rmtree, external, True)
        protected = external / "app" / "intermediates" / "keep.bin"
        protected.parent.mkdir(parents=True)
        protected.write_bytes(b"external output")
        flutter_build = self.repository.root / "flutter/build"
        flutter_build.parent.mkdir(parents=True)
        flutter_build.symlink_to(external, target_is_directory=True)

        result = self.repository.run_just("clean")

        self.assertNotEqual(result.returncode, 0)
        report = json.loads(result.stdout)
        android = _category(report, "android")
        failed = [item for item in android if item["action"] == "failed"]
        self.assertTrue(failed)
        self.assertTrue(all("without following links" in item["error"] for item in failed))
        self.assertEqual(protected.read_bytes(), b"external output")

    def test_special_files_inside_candidate_fail_closed(self) -> None:
        for kind in ("fifo", "socket"):
            with self.subTest(kind=kind):
                repository = DisposableGitRepository()
                try:
                    special = repository.root / f"rust/target/debug/unexpected-{kind}"
                    special.parent.mkdir(parents=True)
                    sibling = special.parent / "0.rlib"
                    sibling.write_bytes(b"must survive partial-validation failure")
                    if kind == "fifo":
                        os.mkfifo(special)
                    else:
                        listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                        try:
                            previous_directory = Path.cwd()
                            try:
                                os.chdir(repository.root)
                                listener.bind(special.relative_to(repository.root).as_posix())
                            finally:
                                os.chdir(previous_directory)
                        finally:
                            listener.close()

                    result = repository.run_just("clean")

                    self.assertNotEqual(result.returncode, 0)
                    self.assertTrue(special.exists())
                    self.assertEqual(
                        sibling.read_bytes(),
                        b"must survive partial-validation failure",
                    )
                    self.assertTrue((repository.root / "rust/target").is_dir())
                finally:
                    repository.close()

    def test_ambient_git_context_is_rejected_before_any_deletion(self) -> None:
        candidate = self._write("rust/target/debug/output.rlib", b"must survive")
        result = self.repository.run_just(
            "clean",
            environment={"GIT_DIR": "/forged/repository"},
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unexpected git context", result.stderr.lower())
        self.assertEqual(candidate.read_bytes(), b"must survive")

    def test_deep_preview_names_are_separate_and_read_only(self) -> None:
        for recipe in ("clean-deep-preview", "clean-preview-deep"):
            with self.subTest(recipe=recipe):
                repository = DisposableGitRepository()
                self.addCleanup(repository.close)
                self.repository = repository
                self._write("flutter/.dart_tool/package_config.json", b"dart state")
                self._write(
                    "flutter/.dart_tool/flutter_build/" + "a" * 64 + "/generated.dill",
                    b"compiler state",
                )
                self._write(
                    "flutter/android/.gradle/caches/cache.bin",
                    b"gradle state",
                )
                self._write(
                    "flutter/build/qualification/argus-qualification.apk",
                    b"retained artifact",
                )
                environment = self.repository.isolated_environment()
                environment.pop("PYTHONDONTWRITEBYTECODE", None)
                environment.pop("PYTHONPYCACHEPREFIX", None)
                before = _hash_tree(self.repository.root)
                result = subprocess.run(
                    [
                        "just",
                        "--justfile",
                        str(self.repository.root / "justfile"),
                        "--working-directory",
                        str(self.repository.root),
                        recipe,
                    ],
                    cwd=self.repository.root,
                    env=environment,
                    capture_output=True,
                    text=True,
                    timeout=20,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                report = json.loads(result.stdout)
                self.assertEqual(report["mode"], "preview-deep")
                self.assertTrue(report["deep"])
                selected = {
                    item["path"]
                    for category in report["categories"]
                    for item in category["paths"]
                    if item["action"] == "selected"
                }
                self.assertIn("flutter/.dart_tool/flutter_build", selected)
                self.assertNotIn("flutter/.dart_tool", selected)
                self.assertIn("flutter/android/.gradle", selected)
                after = _hash_tree(self.repository.root)
                self.assertEqual(after, before)
                self.assertFalse(
                    any("__pycache__" in path for path in after),
                    after,
                )

    def test_cleanup_never_invokes_build_toolchains(self) -> None:
        self._write("rust/target/debug/output.rlib", b"candidate")
        marker = self.repository.root / "toolchain-invoked"
        bin_directory = self.repository.root / "fixture bin"
        bin_directory.mkdir()
        for name in ("cargo", "flutter", "fvm", "gradle", "java"):
            tool = bin_directory / name
            tool.write_text(
                f"#!/bin/sh\nprintf '%s' {name} >> {shlex.quote(str(marker))}\nexit 97\n",
                encoding="utf-8",
            )
            tool.chmod(0o755)

        result = self.repository.run_just(
            "clean-preview",
            environment={"PATH": f"{bin_directory}{os.pathsep}{os.environ['PATH']}"},
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(marker.exists())

    def test_preview_does_not_double_count_hard_links(self) -> None:
        first = self._write("rust/target/debug/first.rlib", b"same inode")
        second = self.repository.root / "rust/target/debug/second.rlib"
        os.link(first, second)

        result = self.repository.run_just("clean-preview")

        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report["estimated_bytes"], len(b"same inode"))

    def test_preview_does_not_double_count_hard_linked_symlinks(self) -> None:
        target = self._write("rust/target/debug/target.rlib", b"target")
        first = self.repository.root / "rust/target/debug/first-link.rlib"
        first.symlink_to(target.name)
        second = self.repository.root / "rust/target/debug/second-link.rlib"
        os.link(first, second, follow_symlinks=False)

        result = self.repository.run_just("clean-preview")

        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        expected = len(b"target") + len(os.readlink(first))
        self.assertEqual(report["estimated_bytes"], expected)

class ProductionRepositoryContractTests(unittest.TestCase):
    def test_production_justfile_exposes_and_composes_cleanup_recipes(self) -> None:
        text = (REPOSITORY_ROOT / "justfile").read_text(encoding="utf-8")

        for recipe in (
            "clean-preview:",
            "clean-deep-preview:",
            "clean-preview-deep:",
            "clean:",
            "clean-deep:",
            "test-cleanup:",
        ):
            with self.subTest(recipe=recipe):
                self.assertIn(recipe, text)
        self.assertIn("just test-cleanup", text)
        self.assertNotIn("_run-shared", text)
        self.assertNotIn("run-shared", text)
        self.assertNotIn("run-exclusive", text)

    def test_existing_ci_jobs_run_the_focused_cleanup_recipe_on_all_platforms(
        self,
    ) -> None:
        text = (REPOSITORY_ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")

        self.assertGreaterEqual(text.count("run: just test-cleanup"), 2)
        native_desktop = text.split("native-desktop:", 1)[1].split("provider-windows:", 1)[0]
        self.assertIn("extractions/setup-just@v4", native_desktop)
        self.assertIn("run: just test-cleanup", native_desktop)

    def test_readme_and_test_convention_document_cleanup_contract(self) -> None:
        readme = (REPOSITORY_ROOT / "README.md").read_text(encoding="utf-8")
        convention = (
            REPOSITORY_ROOT
            / "docs/conventions/conv-test-001-test-pyramid-fixtures-and-verification-commands.md"
        ).read_text(encoding="utf-8")
        helper = (REPOSITORY_ROOT / "scripts" / "just_cleanup.py").read_text(
            encoding="utf-8"
        )

        for text in (readme, convention):
            normalized = text.lower()
            self.assertIn("clean-preview", normalized)
            self.assertIn("clean-deep", normalized)
            self.assertIn("idle checkout", normalized)
            self.assertIn("windows", normalized)

        normalized_convention = convention.lower()
        for retired_contract in (
            "worktree leases",
            "in-process supervisor",
            "inherited socket",
            "lockfileex",
            "exclusive lease",
        ):
            with self.subTest(retired_contract=retired_contract):
                self.assertNotIn(retired_contract, normalized_convention)

        normalized_helper = helper.lower()
        for retired_mechanism in (
            "cleanup lease",
            "worktree lease",
            "supervisor",
            "socket authentication",
            "inherited descriptor",
            "process polling",
            "process monitoring",
        ):
            with self.subTest(retired_mechanism=retired_mechanism):
                self.assertNotIn(retired_mechanism, normalized_helper)
if __name__ == "__main__":
    unittest.main()
