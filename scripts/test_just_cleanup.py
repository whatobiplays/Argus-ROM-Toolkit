#!/usr/bin/env python3
"""Integration tests for generated-output cleanup commands.

Every destructive test invokes the production cleanup helper from a disposable
Git repository. The suite never previews or deletes output in the developer
checkout. The fixture copies both cleanup modules so Git worktree discovery,
ignore policy, tracked-content checks, and subprocess entrypoints behave like
the production command.
"""

from __future__ import annotations

import hashlib
import importlib.util
import io
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
CLEANUP_HELPER = REPOSITORY_ROOT / "scripts" / "just_cleanup.py"
CLEANUP_POLICY = REPOSITORY_ROOT / "scripts" / "just_cleanup_policy.py"

NORMAL_ROOTS = (
    "rust/target",
    "flutter/build/app/intermediates",
    "flutter/build/app/generated",
    "flutter/build/app/tmp",
    "flutter/build/app/.cxx",
    "flutter/build/macos/Build/Intermediates.noindex",
)
DEEP_ROOTS = (
    "flutter/.dart_tool/flutter_build",
    "flutter/android/.gradle",
    "flutter/android/.kotlin",
)
ALL_APPROVED_ROOTS = NORMAL_ROOTS + DEEP_ROOTS


def _hash_tree(root: Path) -> dict[str, str]:
    """Return a deterministic snapshot of a tree without following symlinks."""

    snapshot: dict[str, str] = {}
    if not root.exists() and not root.is_symlink():
        return snapshot
    metadata = root.lstat()
    if stat.S_ISLNK(metadata.st_mode):
        return {".": f"symlink:{os.readlink(root)}"}
    if not stat.S_ISDIR(metadata.st_mode):
        return {".": f"type:{stat.S_IFMT(metadata.st_mode)}"}

    for current_text, directory_names, file_names in os.walk(
        root,
        followlinks=False,
    ):
        current = Path(current_text)
        directory_names.sort()
        file_names.sort()
        retained_directories: list[str] = []
        for name in directory_names:
            path = current / name
            relative = path.relative_to(root).as_posix()
            child_metadata = path.lstat()
            if stat.S_ISLNK(child_metadata.st_mode):
                snapshot[relative] = f"symlink:{os.readlink(path)}"
            elif stat.S_ISDIR(child_metadata.st_mode):
                snapshot[relative] = "directory"
                retained_directories.append(name)
            else:
                snapshot[relative] = f"type:{stat.S_IFMT(child_metadata.st_mode)}"
        directory_names[:] = retained_directories
        for name in file_names:
            path = current / name
            relative = path.relative_to(root).as_posix()
            child_metadata = path.lstat()
            if stat.S_ISLNK(child_metadata.st_mode):
                snapshot[relative] = f"symlink:{os.readlink(path)}"
            elif stat.S_ISREG(child_metadata.st_mode):
                snapshot[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
            else:
                snapshot[relative] = f"type:{stat.S_IFMT(child_metadata.st_mode)}"
    return snapshot


def _outside_snapshot(
    repository_root: Path,
    approved_roots: tuple[str, ...] = ALL_APPROVED_ROOTS,
) -> dict[str, str]:
    """Hash working-tree content outside approved roots and Git metadata."""

    snapshot = _hash_tree(repository_root)
    def is_python_cache(path: str) -> bool:
        components = path.split("/")
        return components[0] == "scripts" and "__pycache__" in components[1:]

    return {
        path: digest
        for path, digest in snapshot.items()
        if path != ".git"
        and not path.startswith(".git/")
        and not is_python_cache(path)
        and not any(
            path == root or path.startswith(root + "/") for root in approved_roots
        )
    }


def _category(report: dict[str, object], name: str) -> list[dict[str, object]]:
    for category in report["categories"]:
        if category["name"] == name:
            return category["paths"]
    raise AssertionError(f"Missing report category {name!r}: {report}")


def _item(report: dict[str, object], candidate_path: str) -> dict[str, object]:
    for category in report["categories"]:
        for item in category["paths"]:
            if item["path"] == candidate_path:
                return item
    raise AssertionError(f"Missing cleanup item {candidate_path!r}: {report}")


def _selected_paths(report: dict[str, object]) -> tuple[str, ...]:
    return tuple(
        sorted(
            item["path"]
            for category in report["categories"]
            for item in category["paths"]
            if item["action"] == "selected"
        )
    )


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
    """A temporary Git repository containing a copy of the cleanup helper."""

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
            "\n".join(f"{root}/" for root in ALL_APPROVED_ROOTS)
            + "\nscripts/**/__pycache__/\n",
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
        environment: dict[str, str] | None = None,
        timeout: float = 20.0,
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                "just",
                "--justfile",
                str(self.root / "justfile"),
                "--working-directory",
                str(self.root),
                recipe,
            ],
            cwd=self.root,
            env=self.isolated_environment(environment),
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
        return subprocess.run(
            [
                sys.executable,
                str(self.root / "scripts" / CLEANUP_HELPER.name),
                *arguments,
            ],
            cwd=self.root,
            env=self.isolated_environment(environment),
            capture_output=True,
            text=True,
            timeout=timeout,
        )


@unittest.skipIf(
    os.name == "nt",
    "Safe inspection and deletion filesystem primitives require POSIX.",
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

    def _symlink(self, relative: str, target: str) -> Path:
        path = self.repository.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.symlink_to(target, target_is_directory=True)
        return path

    def _report(self, result: subprocess.CompletedProcess[str]) -> dict[str, object]:
        self.assertEqual(result.stderr, "", result.stderr)
        return json.loads(result.stdout)

    def test_apply_removes_unknown_files_inside_an_approved_directory(self) -> None:
        self._write("rust/target/release/extensionless-output", b"unknown output")
        self._write(
            "rust/target/release/new-tool-state/binary.zzz",
            b"unrecognized nested output",
        )
        outside = self._write("rust/target-similar/durable.bin", b"keep outside")

        result = self.repository.run_helper("apply")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse((self.repository.root / "rust/target").exists())
        self.assertEqual(outside.read_bytes(), b"keep outside")

    def test_apply_removes_complete_combined_build_output_tree(self) -> None:
        files = {
            "rust/target/debug/deps/libfixture.rlib": b"cargo",
            "rust/target/debug/.fingerprint/crate-hash/lib-crate.json": b"{}",
            "rust/target/Cargo.lock": b"lock",
            "rust/target/release/.DS_Store": b"finder",
            "rust/target/release/unclassified.zzz": b"unknown",
            "rust/target/aarch64-linux-android/debug/deps/tool-output": b"cross",
            (
                "flutter/build/app/intermediates/merged_manifests/debug/"
                "manifest.xml"
            ): b"xml",
            "flutter/build/app/generated/unrecognized/R.java": b"java",
            "flutter/build/app/tmp/new-task/state.bin": b"tmp",
            "flutter/build/app/.cxx/Release/obj/local/arm64-v8a/libapp.so": b"native",
            (
                "flutter/build/macos/Build/Intermediates.noindex/"
                "XCBuildData/output"
            ): b"mac",
            "scripts/nested/__pycache__/module.cpython-313.pyc": b"bytecode",
            "scripts/nested/__pycache__/unexpected.apk": b"cache content",
        }
        for relative, content in files.items():
            self._write(relative, content)
        outside = {
            "docs/qualification/evidence.apk": b"evidence",
            "flutter/build/app/outputs/flutter-apk/app.apk": b"package",
            "flutter/lib/main.dart": b"source",
            "flutter/build/app/keep.txt": b"parent retained",
            "scripts/keep.py": b"script",
        }
        for relative, content in outside.items():
            self._write(relative, content)
        outside_before = _outside_snapshot(self.repository.root)

        result = self.repository.run_helper("apply")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report["schema_version"], 1)
        self.assertEqual(report["mode"], "apply")
        self.assertFalse(report["deep"])
        self.assertEqual(report["status"], "complete")
        self.assertTrue(report["snapshot_reliable"])
        self.assertGreater(report["verified_reclaimed_bytes"], 0)
        for root in NORMAL_ROOTS:
            with self.subTest(root=root):
                self.assertFalse((self.repository.root / root).exists())
        python_item = _item(
            report,
            "scripts/nested/__pycache__",
        )
        self.assertEqual(python_item["outcome"], "removed")
        self.assertEqual(_outside_snapshot(self.repository.root), outside_before)

    def test_normal_cleanup_leaves_deep_only_roots_untouched(self) -> None:
        for root in NORMAL_ROOTS:
            self._write(f"{root}/normal/output.bin", b"normal")
        for root in DEEP_ROOTS:
            self._write(f"{root}/deep/output.bin", b"deep")

        result = self.repository.run_helper("apply")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for root in NORMAL_ROOTS:
            with self.subTest(root=root):
                self.assertFalse((self.repository.root / root).exists())
        for root in DEEP_ROOTS:
            with self.subTest(root=root):
                self.assertEqual(
                    (self.repository.root / root / "deep/output.bin").read_bytes(),
                    b"deep",
                )

    def test_deep_cleanup_removes_normal_and_deep_roots(self) -> None:
        for root in ALL_APPROVED_ROOTS:
            self._write(f"{root}/unknown/extensionless", root.encode())

        result = self.repository.run_helper("apply-deep")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        report = json.loads(result.stdout)
        self.assertTrue(report["deep"])
        self.assertEqual(report["mode"], "apply-deep")
        for root in ALL_APPROVED_ROOTS:
            with self.subTest(root=root):
                self.assertFalse((self.repository.root / root).exists())

    def test_preview_is_read_only_and_matches_apply_selection(self) -> None:
        for root in NORMAL_ROOTS:
            self._write(f"{root}/unreviewed/file.unknown", root.encode())
        before = _outside_snapshot(self.repository.root, ())

        preview_result = self.repository.run_just("clean-preview")

        self.assertEqual(
            preview_result.returncode,
            0,
            preview_result.stdout + preview_result.stderr,
        )
        preview = json.loads(preview_result.stdout)
        self.assertEqual(_outside_snapshot(self.repository.root, ()), before)
        selected = _selected_paths(preview)
        self.assertEqual(selected, tuple(sorted(NORMAL_ROOTS)))

        apply_result = self.repository.run_just("clean")

        self.assertEqual(
            apply_result.returncode,
            0,
            apply_result.stdout + apply_result.stderr,
        )
        applied = json.loads(apply_result.stdout)
        self.assertEqual(_selected_paths(applied), selected)
        for root in NORMAL_ROOTS:
            with self.subTest(root=root):
                self.assertEqual(_item(applied, root)["outcome"], "removed")

    def test_json_reporting_contains_schema_categories_and_byte_semantics(self) -> None:
        payload = b"logical byte accounting"
        self._write("rust/target/debug/payload.bin", payload)

        result = self.repository.run_helper("apply-deep")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report["schema_version"], 1)
        self.assertEqual(report["worktree"], os.fspath(self.repository.root))
        self.assertEqual(report["verified_reclaimed_bytes"], len(payload))
        self.assertIn("estimated_bytes", report["bytes_semantics"])
        self.assertIn("verified_reclaimed_bytes", report["bytes_semantics"])
        self.assertIn("idle checkout", " ".join(report["warnings"]))
        rust = _item(report, "rust/target")
        self.assertEqual(rust["action"], "selected")
        self.assertEqual(rust["outcome"], "removed")
        self.assertEqual(rust["estimated_bytes"], len(payload))
        self.assertEqual(rust["verified_reclaimed_bytes"], len(payload))

    def test_repeated_clean_is_a_zero_byte_idempotent_noop(self) -> None:
        self._write("flutter/android/.gradle/caches/state.bin", b"cache")
        first = self.repository.run_helper("apply-deep")
        self.assertEqual(first.returncode, 0, first.stdout + first.stderr)

        second = self.repository.run_helper("apply-deep")

        self.assertEqual(second.returncode, 0, second.stdout + second.stderr)
        report = json.loads(second.stdout)
        self.assertEqual(report["status"], "complete")
        self.assertEqual(report["verified_reclaimed_bytes"], 0)
        self.assertTrue(
            all(
                item["action"] in {"skipped", "failed"}
                or item.get("outcome") == "removed"
                for category in report["categories"]
                for item in category["paths"]
            )
        )
        self.assertEqual(
            _item(report, "flutter/android/.gradle")["reason"],
            "missing",
        )

    def test_partial_success_across_candidates_is_reported_truthfully(self) -> None:
        cargo = self._write("rust/target/debug/libapp.rlib", b"cargo output")
        self._write("flutter/build/app/tmp/sentinel.bin", b"retained with fifo")
        fifo = self.repository.root / "flutter/build/app/tmp/unsupported.pipe"
        os.mkfifo(fifo)
        outside = self._write("rust/target-neighbor/keep.bin", b"outside")

        result = self.repository.run_helper("apply")

        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report["status"], "partial")
        self.assertFalse(cargo.exists())
        self.assertFalse((self.repository.root / "rust/target").exists())
        self.assertTrue(fifo.exists())
        self.assertEqual(
            (self.repository.root / "flutter/build/app/tmp/sentinel.bin").read_bytes(),
            b"retained with fifo",
        )
        self.assertEqual(_item(report, "rust/target")["outcome"], "removed")
        self.assertEqual(
            _item(report, "flutter/build/app/tmp")["outcome"],
            "failed",
        )
        self.assertEqual(report["verified_reclaimed_bytes"], len(b"cargo output"))
        self.assertEqual(outside.read_bytes(), b"outside")

    def test_tracked_content_blocks_the_entire_candidate(self) -> None:
        tracked = self._write("rust/target/keep.bin", b"tracked")
        self._write("rust/target/unknown.bin", b"untracked")
        self.repository._run_git("add", "-f", "rust/target/keep.bin")
        self.repository._run_git("commit", "-q", "-m", "tracked output")
        before = _hash_tree(self.repository.root / "rust/target")

        result = self.repository.run_helper("apply")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        report = json.loads(result.stdout)
        rust = _item(report, "rust/target")
        self.assertEqual(rust["action"], "skipped")
        self.assertIn("tracks content", rust["reason"].lower())
        self.assertEqual(tracked.read_bytes(), b"tracked")
        self.assertEqual(_hash_tree(self.repository.root / "rust/target"), before)

    def test_nested_git_metadata_blocks_the_entire_candidate(self) -> None:
        self._write("rust/target/debug/nested/.git/HEAD", b"ref: refs/heads/main\n")
        self._write("rust/target/debug/nested/output.bin", b"nested repository")
        before = _hash_tree(self.repository.root / "rust/target")

        result = self.repository.run_helper("apply")

        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        report = json.loads(result.stdout)
        rust = _item(report, "rust/target")
        self.assertEqual(rust["action"], "failed")
        self.assertIn(".git", rust["error"])
        self.assertFalse(report["snapshot_reliable"])
        self.assertEqual(_hash_tree(self.repository.root / "rust/target"), before)

    def test_nested_linked_worktree_blocks_the_entire_candidate(self) -> None:
        self._write("rust/target/debug/output.rlib", b"candidate output")
        linked_root = self.repository.root / "rust/target/nested-linked-worktree"
        linked_root.parent.mkdir(parents=True, exist_ok=True)
        self.repository._run_git(
            "worktree",
            "add",
            "-q",
            "-b",
            "nested-cleanup-test",
            os.fspath(linked_root),
        )
        linked_git_file = linked_root / ".git"
        self.assertTrue(linked_git_file.is_file())
        candidate_before = _hash_tree(self.repository.root / "rust/target")
        worktree_metadata = self.repository.root / ".git" / "worktrees"
        metadata_before = _hash_tree(worktree_metadata)

        result = self.repository.run_helper("apply")

        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        report = json.loads(result.stdout)
        rust = _item(report, "rust/target")
        self.assertEqual(rust["action"], "failed")
        self.assertIn(".git", rust["error"])
        self.assertFalse(report["snapshot_reliable"])
        self.assertEqual(
            _hash_tree(self.repository.root / "rust/target"),
            candidate_before,
        )
        self.assertEqual(_hash_tree(worktree_metadata), metadata_before)

    def test_nested_bare_repository_blocks_the_entire_candidate(self) -> None:
        bare_repository = self.repository.root / "rust/target/debug/nested.git"
        bare_repository.parent.mkdir(parents=True)
        subprocess.run(
            ["git", "init", "--bare", "-q", os.fspath(bare_repository)],
            check=True,
            capture_output=True,
            text=True,
        )
        self._write("rust/target/debug/output.rlib", b"candidate output")
        before = _hash_tree(self.repository.root / "rust/target")

        result = self.repository.run_helper("apply")

        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        report = json.loads(result.stdout)
        rust = _item(report, "rust/target")
        self.assertEqual(rust["action"], "failed")
        self.assertIn("bare Git repository", rust["error"])
        self.assertFalse(report["snapshot_reliable"])
        self.assertEqual(_hash_tree(self.repository.root / "rust/target"), before)

    def test_directory_inspection_probes_only_bare_repository_candidates(self) -> None:
        scan_root = self.repository.root / "probe-tree"
        for index in range(24):
            output = scan_root / f"directory-{index:03d}" / "nested"
            output.mkdir(parents=True)
            (output / "payload").write_bytes(b"generated output")

        bare_repository = scan_root / "zz-bare.git"
        subprocess.run(
            ["git", "init", "--bare", "-q", os.fspath(bare_repository)],
            check=True,
            capture_output=True,
            text=True,
        )

        cleanup = _load_cleanup_module()
        with mock.patch.object(
            cleanup,
            "_run_git",
            wraps=cleanup._run_git,
        ) as run_git:
            _, _, violation = cleanup._inspect_directory(
                scan_root,
                relative_path="probe-tree",
                expected_device=scan_root.stat().st_dev,
                counted_identities=set(),
                counted_entries=[],
            )

        bare_probes = [
            call
            for call in run_git.call_args_list
            if call.args[1] == ("rev-parse", "--is-bare-repository")
        ]
        self.assertEqual(
            len(bare_probes),
            1,
            f"expected one Git repository probe, got {len(bare_probes)}",
        )
        self.assertIsNotNone(violation)
        self.assertIn("bare Git repository", violation)

    def test_incidental_bare_repository_names_remain_eligible(self) -> None:
        incidental = self.repository.root / "rust/target/debug/output-layout"
        (incidental / "objects").mkdir(parents=True)
        (incidental / "refs").mkdir()
        (incidental / "HEAD").write_text("not Git metadata\n", encoding="utf-8")
        (incidental / "config").write_text(
            "[core]\n\tbare = false\n",
            encoding="utf-8",
        )

        result = self.repository.run_helper("apply")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse((self.repository.root / "rust/target").exists())

    def test_bare_repository_ancestor_blocks_the_approved_candidate(self) -> None:
        bare_repository = self.repository.root / "rust"
        subprocess.run(
            ["git", "init", "--bare", "-q", os.fspath(bare_repository)],
            check=True,
            capture_output=True,
            text=True,
        )
        self._write("rust/target/debug/output.rlib", b"candidate output")
        before = _hash_tree(bare_repository)

        result = self.repository.run_helper("apply")

        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        report = json.loads(result.stdout)
        rust = _item(report, "rust/target")
        self.assertEqual(rust["action"], "failed")
        self.assertIn("bare Git repository", rust["error"])
        self.assertFalse(report["snapshot_reliable"])
        self.assertEqual(_hash_tree(bare_repository), before)

    def test_bare_metadata_variants_still_block_the_entire_candidate(self) -> None:
        metadata_name = "config"
        cases = (
            ("missing-config", "missing"),
            ("symlink-config", metadata_name),
            ("symlink-objects", "objects"),
            ("symlink-refs", "refs"),
        )
        for case_name, metadata_variant in cases:
            with self.subTest(case=case_name):
                repository = DisposableGitRepository()
                try:
                    bare_repository = (
                        repository.root / f"rust/target/debug/{case_name}.git"
                    )
                    bare_repository.parent.mkdir(parents=True)
                    subprocess.run(
                        [
                            "git",
                            "init",
                            "--bare",
                            "-q",
                            os.fspath(bare_repository),
                        ],
                        check=True,
                        capture_output=True,
                        text=True,
                    )
                    if metadata_variant == "missing":
                        (bare_repository / "config").unlink()
                    else:
                        metadata = bare_repository / metadata_variant
                        external = (
                            repository.root
                            / "external-bare-metadata"
                            / f"{case_name}-{metadata_variant}"
                        )
                        external.parent.mkdir(parents=True)
                        metadata.rename(external)
                        metadata.symlink_to(
                            external,
                            target_is_directory=external.is_dir(),
                        )
                    output = repository.root / "rust/target/debug/output.rlib"
                    output.parent.mkdir(parents=True, exist_ok=True)
                    output.write_bytes(b"candidate output")
                    candidate = repository.root / "rust/target"
                    before = _hash_tree(candidate)

                    result = repository.run_helper("apply")

                    self.assertEqual(
                        result.returncode,
                        1,
                        result.stdout + result.stderr,
                    )
                    report = json.loads(result.stdout)
                    rust = _item(report, "rust/target")
                    self.assertEqual(rust["action"], "failed")
                    self.assertIn("bare Git repository", rust["error"])
                    self.assertFalse(report["snapshot_reliable"])
                    self.assertEqual(_hash_tree(candidate), before)
                finally:
                    repository.close()

    def test_symlinked_candidate_is_skipped_without_following_target(self) -> None:
        destination = self._write("external/target/keep.bin", b"destination")
        candidate = self.repository.root / "rust/target"
        candidate.parent.mkdir(parents=True)
        candidate.symlink_to(Path("../../external/target"), target_is_directory=True)

        result = self.repository.run_helper("apply")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        report = json.loads(result.stdout)
        rust = _item(report, "rust/target")
        self.assertEqual(rust["action"], "skipped")
        self.assertIn("symbolic link", rust["reason"].lower())
        self.assertTrue(candidate.is_symlink())
        self.assertEqual(destination.read_bytes(), b"destination")

    def test_symlinked_candidate_ancestor_is_refused(self) -> None:
        external = Path(tempfile.mkdtemp(prefix="cleanup external flutter "))
        self.addCleanup(shutil.rmtree, external, True)
        retained = external / "build/app/intermediates/data/output.bin"
        retained.parent.mkdir(parents=True)
        retained.write_bytes(b"external flutter")
        before = _hash_tree(external)
        (self.repository.root / "flutter").symlink_to(
            external,
            target_is_directory=True,
        )

        result = self.repository.run_helper("apply")

        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        report = json.loads(result.stdout)
        self.assertFalse(report["snapshot_reliable"])
        self.assertEqual(_hash_tree(external), before)
        self.assertTrue(any(
            item["action"] == "failed" and "symbolic link" in item["reason"].lower()
            for category in report["categories"]
            for item in category["paths"]
        ))

    def test_internal_symlink_is_unlinked_without_following_target(self) -> None:
        destination = Path(tempfile.mkdtemp(prefix="cleanup symlink destination "))
        self.addCleanup(shutil.rmtree, destination, True)
        retained = destination / "keep.bin"
        retained.write_bytes(b"outside symlink target")
        link = self.repository.root / "rust/target/debug/output-link"
        link.parent.mkdir(parents=True)
        link.symlink_to(destination, target_is_directory=True)
        before = _hash_tree(destination)

        result = self.repository.run_helper("apply")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse((self.repository.root / "rust/target").exists())
        self.assertEqual(_hash_tree(destination), before)
        self.assertEqual(retained.read_bytes(), b"outside symlink target")

    def test_ignored_root_check_prevents_deletion(self) -> None:
        payload = self._write("rust/target/debug/output.bin", b"not ignored")
        (self.repository.root / ".gitignore").write_text("", encoding="utf-8")

        result = self.repository.run_helper("apply")

        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        report = json.loads(result.stdout)
        rust = _item(report, "rust/target")
        self.assertEqual(rust["action"], "failed")
        self.assertIn("ignore policy", rust["error"])
        self.assertEqual(payload.read_bytes(), b"not ignored")

    def test_cargo_target_redirect_protects_local_and_external_outputs(self) -> None:
        local = self._write("rust/target/debug/local.rlib", b"local target")
        external = Path(tempfile.mkdtemp(prefix="external cargo target "))
        self.addCleanup(shutil.rmtree, external, True)
        external_file = external / "keep.bin"
        external_file.write_bytes(b"external target")

        result = self.repository.run_helper(
            "apply",
            environment={"CARGO_TARGET_DIR": os.fspath(external)},
        )

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        report = json.loads(result.stdout)
        rust = _item(report, "rust/target")
        self.assertEqual(rust["action"], "skipped")
        self.assertIn("redirects cargo", rust["reason"].lower())
        self.assertEqual(local.read_bytes(), b"local target")
        self.assertEqual(external_file.read_bytes(), b"external target")

    def test_nested_filesystem_device_boundary_is_rejected(self) -> None:
        cleanup = _load_cleanup_module()
        worktree = cleanup.discover_worktree(self.repository.root)
        output = self._write("rust/target/debug/output.bin", b"candidate")
        spec = cleanup.CandidateSpec(
            category="rust",
            relative_path="rust/target",
            default_clean=True,
            regeneration_note="test",
        )
        real_lstat = Path.lstat

        def fabricated_lstat(path: Path) -> os.stat_result:
            metadata = real_lstat(path)
            if path == output:
                values = list(metadata)
                values[2] = int(metadata.st_dev) + 1
                return os.stat_result(values)
            return metadata

        with mock.patch.object(Path, "lstat", new=fabricated_lstat):
            observation = cleanup._observe_candidate(worktree, spec)

        self.assertEqual(observation.action, "failed")
        self.assertIn("Filesystem boundary", observation.error)
        self.assertEqual(output.read_bytes(), b"candidate")

    def test_root_on_another_device_is_skipped(self) -> None:
        cleanup = _load_cleanup_module()
        worktree = cleanup.discover_worktree(self.repository.root)
        candidate = self.repository.root / "rust/target"
        candidate.mkdir(parents=True)
        spec = cleanup.CandidateSpec(
            category="rust",
            relative_path="rust/target",
            default_clean=True,
            regeneration_note="test",
        )
        real_lstat = Path.lstat

        def fabricated_lstat(path: Path) -> os.stat_result:
            metadata = real_lstat(path)
            if path == candidate:
                values = list(metadata)
                values[2] = int(metadata.st_dev) + 1
                return os.stat_result(values)
            return metadata

        with mock.patch.object(Path, "lstat", new=fabricated_lstat):
            observation = cleanup._observe_candidate(worktree, spec)

        self.assertEqual(observation.action, "skipped")
        self.assertIn("different filesystem", observation.reason)
        self.assertTrue(candidate.is_dir())

    def test_unsupported_entry_type_is_rejected_before_deletion(self) -> None:
        self._write("rust/target/debug/output.rlib", b"candidate")
        fifo = self.repository.root / "rust/target/debug/unsupported.pipe"
        os.mkfifo(fifo)

        result = self.repository.run_helper("apply")

        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        report = json.loads(result.stdout)
        self.assertIn("Unexpected filesystem object", report["errors"][0])
        self.assertTrue(fifo.exists())
        self.assertEqual(
            (self.repository.root / "rust/target/debug/output.rlib").read_bytes(),
            b"candidate",
        )

    def test_admitted_root_does_not_veto_sensitive_or_package_like_names(self) -> None:
        names = (
            "credentials.json",
            "private-key.pem",
            "release.apk",
            "disc.gba",
            "roms/library.db",
            "unknown/evidence.zip",
            ".chatgpt/review.json",
            ".codex/config",
            ".superpowers/memory",
            "qualification/evidence.apk",
            "flutter/lib/main.dart",
            "build/output.bin",
            ".DS_Store",
            "Cargo.lock",
            "extensionless",
        )
        for name in names:
            self._write(f"rust/target/debug/{name}", name.encode())

        result = self.repository.run_helper("apply")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse((self.repository.root / "rust/target").exists())

    def test_similar_paths_and_durable_content_remain_byte_identical(self) -> None:
        for root in ALL_APPROVED_ROOTS:
            self._write(f"{root}/generated/unknown.zzz", b"generated")
        outside_paths = {
            "rust/targeted/keep.bin": b"rust similar",
            "flutter/build/app/intermediates-similar/keep.bin": b"android similar",
            "flutter/.dart_tool/flutter_build-similar/keep.bin": b"flutter similar",
            "docs/qualification/evidence.apk": b"qualification",
            "flutter/build/app/outputs/release.apk": b"package",
            "flutter/build/native-jni/libapp.so": b"native",
            "flutter/lib/main.dart": b"source",
            "build/keep.bin": b"root build",
        }
        for relative, content in outside_paths.items():
            self._write(relative, content)
        before = _outside_snapshot(self.repository.root)

        result = self.repository.run_helper("apply-deep")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(_outside_snapshot(self.repository.root), before)
        for relative, content in outside_paths.items():
            with self.subTest(path=relative):
                self.assertEqual(
                    (self.repository.root / relative).read_bytes(),
                    content,
                )

    def test_protected_diagnostics_are_reported_without_deletion(self) -> None:
        protected = {
            "docs/archive/record.md": b"archive",
            "docs/qualification/evidence.apk": b"evidence",
            "flutter/android/local.properties": b"machine-local",
            "flutter/.fvm/flutter_sdk/bin/flutter": b"sdk",
            "flutter/lib/main.dart": b"source",
        }
        for relative, content in protected.items():
            self._write(relative, content)

        result = self.repository.run_helper("apply-deep")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        report = json.loads(result.stdout)
        protected_paths = {
            item["path"] for item in _category(report, "protected")
        }
        self.assertIn("docs/archive", protected_paths)
        self.assertIn("docs/qualification", protected_paths)
        self.assertIn("flutter/lib", protected_paths)
        for relative, content in protected.items():
            with self.subTest(path=relative):
                self.assertEqual(
                    (self.repository.root / relative).read_bytes(),
                    content,
                )

    def test_python_cache_discovery_does_not_follow_symlinks(self) -> None:
        self._write("scripts/fixture/__pycache__/generated.apk", b"owned cache")
        external = Path(tempfile.mkdtemp(prefix="python cache symlink target "))
        self.addCleanup(shutil.rmtree, external, True)
        retained = external / "__pycache__/external.pyc"
        retained.parent.mkdir()
        retained.write_bytes(b"external cache")
        (self.repository.root / "scripts/vendor").symlink_to(
            external,
            target_is_directory=True,
        )

        result = self.repository.run_helper("apply")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(
            (self.repository.root / "scripts/fixture/__pycache__").exists()
        )
        self.assertEqual(retained.read_bytes(), b"external cache")

    def test_python_cache_walk_error_marks_snapshot_unreliable(self) -> None:
        cleanup = _load_cleanup_module()
        worktree = cleanup.discover_worktree(self.repository.root)
        blocked = self.repository.root / "scripts/blocked"
        blocked.mkdir(parents=True)
        retained = self._write(
            "scripts/blocked/__pycache__/retained.pyc",
            b"not discovered",
        )

        def fail_walk(
            top: object,
            *,
            followlinks: bool,
            onerror: object,
        ) -> object:
            error = PermissionError("simulated walk failure")
            error.filename = os.fspath(blocked)
            onerror(error)
            return iter(())

        with mock.patch.object(cleanup.os, "walk", side_effect=fail_walk):
            observations = cleanup._collect_observations(worktree, deep=False)
            report = cleanup.build_report(
                worktree,
                deep=False,
                mode="preview",
                observations=observations,
            )

        self.assertFalse(report["snapshot_reliable"])
        failed = _item(report, "scripts/blocked")
        self.assertEqual(failed["action"], "failed")
        self.assertIn("Cannot inspect Python bytecode cache tree", failed["error"])
        self.assertEqual(retained.read_bytes(), b"not discovered")

    def test_linked_worktree_cleanup_is_confined_to_that_worktree(self) -> None:
        linked_parent = Path(tempfile.mkdtemp(prefix="linked cleanup fixture "))
        self.addCleanup(shutil.rmtree, linked_parent, True)
        linked_root = linked_parent / "linked worktree"
        self.repository._run_git(
            "worktree",
            "add",
            "-q",
            "-b",
            "linked-cleanup-test",
            os.fspath(linked_root),
        )
        main_output = self._write("rust/target/debug/main.rlib", b"main")
        linked_output = linked_root / "rust/target/debug/linked.rlib"
        linked_output.parent.mkdir(parents=True)
        linked_output.write_bytes(b"linked")
        metadata_before = _hash_tree(self.repository.root / ".git" / "worktrees")

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

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(linked_output.exists())
        self.assertEqual(main_output.read_bytes(), b"main")
        self.assertEqual(
            _hash_tree(self.repository.root / ".git" / "worktrees"),
            metadata_before,
        )

    def test_ambient_git_context_is_rejected_before_deletion(self) -> None:
        output = self._write("rust/target/debug/output.rlib", b"candidate")

        result = self.repository.run_helper(
            "apply",
            environment={"GIT_DIR": os.fspath(self.repository.root / ".git")},
        )

        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn("Unexpected Git context environment", result.stderr)
        self.assertEqual(output.read_bytes(), b"candidate")

    def test_path_escape_candidate_is_rejected_without_deletion(self) -> None:
        cleanup = _load_cleanup_module()
        worktree = cleanup.discover_worktree(self.repository.root)
        outside = Path(tempfile.mkdtemp(prefix="cleanup escape target "))
        self.addCleanup(shutil.rmtree, outside, True)
        retained = outside / "keep.bin"
        retained.write_bytes(b"outside")
        spec = cleanup.CandidateSpec(
            category="rust",
            relative_path="../" + outside.name,
            default_clean=True,
            regeneration_note="test",
        )

        with self.assertRaisesRegex(cleanup.UnsafeCandidateError, "traversal"):
            cleanup._observe_candidate(worktree, spec)
        self.assertEqual(retained.read_bytes(), b"outside")

    def test_deep_preview_alias_is_read_only(self) -> None:
        output = self._write(
            "flutter/.dart_tool/flutter_build/generated/output.bin",
            b"deep preview",
        )

        result = self.repository.run_just("clean-preview-deep")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report["mode"], "preview-deep")
        self.assertTrue(report["deep"])
        self.assertEqual(
            _item(report, "flutter/.dart_tool/flutter_build")["action"],
            "selected",
        )
        self.assertEqual(output.read_bytes(), b"deep preview")

    def test_hard_links_are_counted_once_for_preview_and_reclaimed_bytes(self) -> None:
        payload = b"hard-linked logical bytes"
        first = self._write("rust/target/debug/first.bin", payload)
        second = self.repository.root / "rust/target/debug/second.bin"
        os.link(first, second)

        preview_result = self.repository.run_helper("preview")

        self.assertEqual(
            preview_result.returncode,
            0,
            preview_result.stdout + preview_result.stderr,
        )
        preview = json.loads(preview_result.stdout)
        self.assertEqual(_item(preview, "rust/target")["estimated_bytes"], len(payload))

        apply_result = self.repository.run_helper("apply")

        self.assertEqual(
            apply_result.returncode,
            0,
            apply_result.stdout + apply_result.stderr,
        )
        applied = json.loads(apply_result.stdout)
        self.assertEqual(applied["verified_reclaimed_bytes"], len(payload))

    def test_removal_error_after_one_success_reports_partial_completion(self) -> None:
        cleanup = _load_cleanup_module()
        worktree = cleanup.discover_worktree(self.repository.root)
        cargo = self._write("rust/target/debug/output.rlib", b"cargo bytes")
        android = self._write(
            "flutter/build/app/tmp/debug/output.bin",
            b"android bytes",
        )
        real_rmtree = cleanup.shutil.rmtree

        def fail_android(path: object, *, onerror: object = None) -> None:
            if Path(path) == self.repository.root / "flutter/build/app/tmp":
                raise OSError("simulated removal failure")
            return real_rmtree(path, onerror=onerror)

        stdout = io.StringIO()
        with (
            mock.patch.dict(
                os.environ,
                self.repository.isolated_environment(),
                clear=True,
            ),
            mock.patch.object(cleanup, "discover_worktree", return_value=worktree),
            mock.patch.object(cleanup.shutil, "rmtree", side_effect=fail_android),
            mock.patch("sys.stdout", stdout),
        ):
            status = cleanup._apply(False)

        self.assertEqual(status, 1)
        report = json.loads(stdout.getvalue())
        self.assertEqual(report["status"], "partial")
        self.assertFalse(cargo.exists())
        self.assertEqual(android.read_bytes(), b"android bytes")
        self.assertEqual(report["verified_reclaimed_bytes"], len(b"cargo bytes"))

    def test_apply_revalidates_safety_before_deleting(self) -> None:
        cleanup = _load_cleanup_module()
        worktree = cleanup.discover_worktree(self.repository.root)
        output = self._write("rust/target/debug/output.rlib", b"candidate")
        real_observe = cleanup._observe_candidate
        rust_observations = 0

        def fail_second_observation(
            observed_worktree: object,
            spec: object,
            *,
            seen_file_identities: set[tuple[int, int]] | None = None,
        ) -> object:
            nonlocal rust_observations
            observation = real_observe(
                observed_worktree,
                spec,
                seen_file_identities=seen_file_identities,
            )
            if spec.relative_path == "rust/target":
                rust_observations += 1
                if rust_observations == 2:
                    observation.action = "failed"
                    observation.reason = "candidate changed before apply"
                    observation.error = observation.reason
            return observation

        stdout = io.StringIO()
        with (
            mock.patch.dict(
                os.environ,
                self.repository.isolated_environment(),
                clear=True,
            ),
            mock.patch.object(cleanup, "discover_worktree", return_value=worktree),
            mock.patch.object(
                cleanup,
                "_observe_candidate",
                side_effect=fail_second_observation,
            ),
            mock.patch("sys.stdout", stdout),
        ):
            status = cleanup._apply(False)

        self.assertEqual(status, 1)
        report = json.loads(stdout.getvalue())
        self.assertEqual(report["status"], "failed")
        self.assertFalse(report["snapshot_reliable"])
        self.assertEqual(_item(report, "rust/target")["outcome"], "failed")
        self.assertEqual(output.read_bytes(), b"candidate")

    def test_git_query_failure_is_reported_without_deletion(self) -> None:
        cleanup = _load_cleanup_module()
        worktree = cleanup.discover_worktree(self.repository.root)
        output = self._write("rust/target/debug/output.rlib", b"candidate")
        spec = cleanup.CandidateSpec(
            category="rust",
            relative_path="rust/target",
            default_clean=True,
            regeneration_note="test",
        )
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

        with mock.patch.object(cleanup, "_run_git", side_effect=fail_ls_files):
            observation = cleanup._observe_candidate(worktree, spec)

        self.assertEqual(observation.action, "failed")
        self.assertIn("ls-files", observation.error)
        self.assertEqual(output.read_bytes(), b"candidate")

    def test_candidate_that_is_not_a_directory_fails_closed(self) -> None:
        candidate = self._write("rust/target", b"not a directory")

        result = self.repository.run_helper("apply")

        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        report = json.loads(result.stdout)
        rust = _item(report, "rust/target")
        self.assertEqual(rust["action"], "failed")
        self.assertIn("not a directory", rust["error"])
        self.assertEqual(candidate.read_bytes(), b"not a directory")


@unittest.skipIf(
    os.name == "nt",
    "Repository command contract tests use POSIX shell recipes.",
)
class ProductionRepositoryContractTests(unittest.TestCase):
    def test_justfile_exposes_cleanup_commands_and_deep_preview_alias(self) -> None:
        justfile = (REPOSITORY_ROOT / "justfile").read_text(encoding="utf-8")

        for recipe in (
            "clean-preview",
            "clean",
            "clean-deep-preview",
            "clean-deep",
            "test-cleanup",
            "clean-preview-deep",
        ):
            with self.subTest(recipe=recipe):
                self.assertRegex(justfile, rf"(?m)^{recipe}:")

    def test_readme_documents_directory_ownership_and_boundaries(self) -> None:
        readme = (REPOSITORY_ROOT / "README.md").read_text(encoding="utf-8").casefold()

        for phrase in (
            "entire approved directory",
            "idle checkout",
            "scripts/**/__pycache__",
            "different-device",
            "same-device bind mounts",
        ):
            with self.subTest(phrase=phrase):
                self.assertIn(phrase, readme)


if __name__ == "__main__":
    unittest.main()
