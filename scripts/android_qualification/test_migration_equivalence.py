"""Prove host-test preservation against manifest-pinned archived sources."""

from __future__ import annotations

import ast
import copy
import hashlib
import json
import shutil
import tempfile
import unittest
from collections import Counter
from pathlib import Path

from scripts.android_qualification import repository_checks
from scripts.android_qualification.physical import core


ROOT = Path(__file__).resolve().parents[2]
ARCHIVE_MANIFEST = ROOT / repository_checks.MANIFEST_RELATIVE_PATH
PHYSICAL_TEST_DIRECTORY = "scripts/android_qualification/physical"
BASELINE_SOURCE_PREFIX = "scripts/phase_" + "003_android_physical_qualification/"
NEUTRAL_ACTIVE_TEST_FILES = (
    "scripts/android_qualification/test_admission.py",
    "scripts/android_qualification/test_cli.py",
    "scripts/android_qualification/test_entrypoints.py",
    "scripts/android_qualification/test_manifest.py",
)

# These reviewed replacements preserve the archived identities and assertions
# while redirecting retired live-capable behavior to explicit safety proofs.
SAFETY_BOUNDARY_REPLACEMENTS = {
    (
        "test_core.py",
        "CoreTests",
        "test_process_execution_is_bounded_and_failure_output_is_private",
    ): (
        "scripts.android_qualification.physical.test_execution_isolation."
        "ExecutionIsolationTests.test_process_launch_detection_resolves_import_aliases_and_ignores_device_run",
        "scripts.android_qualification.physical.test_execution_isolation."
        "ExecutionIsolationTests.test_active_package_contains_no_process_or_device_transport_composition",
        "scripts.android_qualification.physical.test_execution_isolation."
        "ExecutionIsolationTests.test_default_runner_fails_before_device_construction_or_adb",
        "scripts.android_qualification.physical.test_execution_isolation."
        "ExecutionIsolationTests.test_default_entrypoints_make_zero_fake_adb_calls",
    ),
    (
        "test_runner.py",
        "CLITests",
        "test_script_entrypoint_prints_preflight_report_and_exits_two",
    ): (
        "scripts.android_qualification.physical.test_runner.CLITests."
        "test_script_entrypoint_fails_closed_before_device_construction",
    ),
}
SAFETY_BOUNDARY_REQUIRED_ASSERTIONS = {
    "scripts.android_qualification.physical.test_execution_isolation."
    "ExecutionIsolationTests.test_process_launch_detection_resolves_import_aliases_and_ignores_device_run": (
        "assertEqual",
    ),
    "scripts.android_qualification.physical.test_execution_isolation."
    "ExecutionIsolationTests.test_active_package_contains_no_process_or_device_transport_composition": (
        "assertEqual",
        "assertFalse",
    ),
    "scripts.android_qualification.physical.test_execution_isolation."
    "ExecutionIsolationTests.test_default_runner_fails_before_device_construction_or_adb": (
        "assertRaisesRegex",
    ),
    "scripts.android_qualification.physical.test_execution_isolation."
    "ExecutionIsolationTests.test_default_entrypoints_make_zero_fake_adb_calls": (
        "assertFalse",
        "assertEqual",
    ),
    "scripts.android_qualification.physical.test_runner.CLITests."
    "test_script_entrypoint_fails_closed_before_device_construction": (
        "assertEqual",
        "assertIn",
        "assert_not_called",
    ),
    "scripts.android_qualification.test_entrypoints.EntrypointTests."
    "test_archived_physical_entrypoint_is_not_active": (
        "assertFalse",
        "_assert_no_adb",
    ),
}
ADDITIONAL_ASSERTIONS = {
    "scripts.android_qualification.physical.test_runner.RunnerTests."
    "test_explicit_trusted_source_resolves_shell_assignments_without_exposing_other_fields": (
        "assert_called_once",
    ),
}


def _test_methods(source: str) -> dict[tuple[str, str], ast.FunctionDef]:
    module = ast.parse(source)
    return {
        (class_node.name, child.name): child
        for class_node in module.body
        if isinstance(class_node, ast.ClassDef)
        for child in class_node.body
        if isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef))
        and child.name.startswith("test_")
    }


def _fold_string_additions(node: ast.AST) -> ast.AST:
    class StringFolder(ast.NodeTransformer):
        def visit_BinOp(self, candidate: ast.BinOp) -> ast.AST:
            candidate = self.generic_visit(candidate)
            if (
                isinstance(candidate, ast.BinOp)
                and isinstance(candidate.op, ast.Add)
                and isinstance(candidate.left, ast.Constant)
                and isinstance(candidate.left.value, str)
                and isinstance(candidate.right, ast.Constant)
                and isinstance(candidate.right.value, str)
            ):
                return ast.copy_location(
                    ast.Constant(candidate.left.value + candidate.right.value),
                    candidate,
                )
            return candidate

    return StringFolder().visit(copy.deepcopy(node))


def _normalized_assertions(method: ast.FunctionDef) -> tuple[str, ...]:
    old_directory = repository_checks.HISTORICAL_DEVICE_DIRECTORY
    old_name = Path(old_directory).name
    new_directory = core.DEVICE_ROOT
    new_name = Path(new_directory).name

    class PathNormalizer(ast.NodeTransformer):
        def visit_Constant(self, node: ast.Constant) -> ast.AST:
            if not isinstance(node.value, str):
                return node
            value = node.value.replace(old_directory, new_directory).replace(old_name, new_name)
            if value == new_directory:
                return ast.copy_location(ast.Name(id="__DEVICE_ROOT__", ctx=ast.Load()), node)
            if value.startswith(new_directory + "/"):
                return ast.copy_location(
                    ast.BinOp(
                        left=ast.Name(id="__DEVICE_ROOT__", ctx=ast.Load()),
                        op=ast.Add(),
                        right=ast.Constant(value[len(new_directory) :]),
                    ),
                    node,
                )
            return ast.copy_location(ast.Constant(value), node)

        def visit_Attribute(self, node: ast.Attribute) -> ast.AST:
            node = self.generic_visit(node)
            if ast.dump(node, include_attributes=False) == "Attribute(value=Name(id='core', ctx=Load()), attr='DEVICE_ROOT', ctx=Load())":
                return ast.copy_location(ast.Name(id="__DEVICE_ROOT__", ctx=ast.Load()), node)
            return node

    normalized = PathNormalizer().visit(_fold_string_additions(method))
    assertions: list[str] = []

    class AssertionCollector(ast.NodeVisitor):
        def visit_Assert(self, node: ast.Assert) -> None:
            assertions.append(ast.dump(node, include_attributes=False))
            self.generic_visit(node)

        def visit_Call(self, node: ast.Call) -> None:
            function = node.func
            if isinstance(function, ast.Attribute) and function.attr.startswith("assert"):
                assertions.append(ast.dump(node, include_attributes=False))
            self.generic_visit(node)

    AssertionCollector().visit(normalized)
    return tuple(assertions)


def _assert_assertions_equivalent(
    case: unittest.TestCase,
    baseline: tuple[str, ...],
    migrated: tuple[str, ...],
    identity: str,
    *,
    additional: tuple[str, ...] = (),
) -> None:
    case.assertEqual(len(baseline) + len(additional), len(migrated), identity)
    for index, (expected, actual) in enumerate(zip(baseline, migrated), start=1):
        with case.subTest(test=identity, assertion=index):
            case.assertEqual(expected, actual)
    for index, required_fragment in enumerate(additional, start=len(baseline) + 1):
        with case.subTest(test=identity, assertion=index):
            case.assertIn(required_fragment, migrated[index - 1])


def _manifest_baseline_inventory(root: Path = ROOT) -> dict[str, bytes]:
    """Load archived originals only when their manifest SHA-256 values match."""
    manifest_path = root / repository_checks.MANIFEST_RELATIVE_PATH
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise AssertionError("Could not read the archived baseline manifest") from error
    entries = manifest.get("entries") if isinstance(manifest, dict) else None
    if not isinstance(entries, list):
        raise AssertionError("Archived baseline manifest entries must be a list")

    inventory: dict[str, bytes] = {}
    seen_archived_paths: set[str] = set()
    for entry in entries:
        if not isinstance(entry, dict):
            raise AssertionError("Archived baseline manifest entries must be objects")
        original_path = entry.get("original_path")
        archived_path = entry.get("archived_path")
        expected_digest = entry.get("sha256")
        if not all(
            isinstance(value, str) and value
            for value in (original_path, archived_path, expected_digest)
        ):
            raise AssertionError("Archived baseline manifest entry is incomplete")

        original_relative_path = Path(original_path)
        archived_relative_path = Path(archived_path)
        if (
            original_relative_path.is_absolute()
            or archived_relative_path.is_absolute()
            or ".." in original_relative_path.parts
            or ".." in archived_relative_path.parts
        ):
            raise AssertionError(f"Unsafe archived baseline path: {archived_path}")
        if original_path in inventory or archived_path in seen_archived_paths:
            raise AssertionError(f"Duplicate archived baseline path: {original_path}")

        archived_bytes = (root / archived_relative_path).read_bytes()
        actual_digest = hashlib.sha256(archived_bytes).hexdigest()
        if actual_digest != expected_digest:
            raise AssertionError(f"Archived baseline hash mismatch: {original_path}")
        inventory[original_path] = archived_bytes
        seen_archived_paths.add(archived_path)
    return inventory


def _test_id(module: str, identity: tuple[str, str]) -> str:
    return f"{module}.{identity[0]}.{identity[1]}"


def _method_for_test_id(test_id: str) -> ast.FunctionDef:
    module, class_name, method_name = test_id.rsplit(".", 2)
    source_path = ROOT.joinpath(*module.split(".")).with_suffix(".py")
    methods = _test_methods(source_path.read_text(encoding="utf-8"))
    return methods[(class_name, method_name)]


def _assertion_call_names(method: ast.FunctionDef) -> set[str]:
    return {
        node.func.attr
        for node in ast.walk(method)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
    }


def _suite_ids(suite: unittest.TestSuite) -> list[str]:
    result: list[str] = []
    for item in suite:
        if isinstance(item, unittest.TestSuite):
            result.extend(_suite_ids(item))
        else:
            result.append(item.id())
    return result


class MigrationEquivalenceTests(unittest.TestCase):
    def test_archived_baseline_inventory_works_without_git_objects(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            isolated_root = Path(temporary)
            shutil.copytree(
                ROOT / repository_checks.ARCHIVE_DIRECTORY,
                isolated_root / repository_checks.ARCHIVE_DIRECTORY,
            )
            inventory = _manifest_baseline_inventory(isolated_root)

        self.assertEqual(len(inventory), 12)

    def _assert_safety_boundary_replacement(
        self,
        old_method: ast.FunctionDef,
        old_id: str,
        replacements: tuple[str, ...],
    ) -> None:
        self.assertTrue(_normalized_assertions(old_method), old_id)
        for replacement in replacements:
            with self.subTest(test=old_id, replacement=replacement):
                target_method = _method_for_test_id(replacement)
                required = SAFETY_BOUNDARY_REQUIRED_ASSERTIONS[replacement]
                self.assertTrue(required, replacement)
                self.assertTrue(
                    set(required).issubset(_assertion_call_names(target_method)),
                    replacement,
                )

    def test_archived_files_match_manifest_hashes_byte_for_byte(self) -> None:
        violations = repository_checks.archive_violations(ROOT)
        self.assertEqual(violations, ())
        manifest = json.loads(ARCHIVE_MANIFEST.read_text(encoding="utf-8"))
        entries = {entry["original_path"]: entry for entry in manifest["entries"]}
        baseline = _manifest_baseline_inventory()
        self.assertEqual(set(entries), set(baseline))
        for original_path, expected_bytes in baseline.items():
            with self.subTest(original_path=original_path):
                archived_path = ROOT / entries[original_path]["archived_path"]
                archived_bytes = archived_path.read_bytes()
                self.assertEqual(archived_bytes, expected_bytes, original_path)
                self.assertEqual(
                    hashlib.sha256(archived_bytes).hexdigest(),
                    entries[original_path]["sha256"],
                    original_path,
                )

    def _physical_sources(self) -> tuple[dict[str, str], dict[str, str]]:
        baseline_inventory = _manifest_baseline_inventory()
        baseline: dict[str, str] = {}
        migrated: dict[str, str] = {}
        for original_path, content in baseline_inventory.items():
            if not original_path.startswith(BASELINE_SOURCE_PREFIX):
                continue
            if not Path(original_path).name.startswith("test_"):
                continue
            filename = Path(original_path).name
            baseline[filename] = content.decode("utf-8")
            migrated[filename] = (
                ROOT / PHYSICAL_TEST_DIRECTORY / filename
            ).read_text(encoding="utf-8")
        return baseline, migrated

    def _baseline_case_mapping(self) -> dict[str, tuple[str, ...]]:
        baseline_ids: dict[str, tuple[str, ...]] = {}

        physical_baseline, physical_migrated = self._physical_sources()
        for filename, source in physical_baseline.items():
            baseline_methods = _test_methods(source)
            current_methods = _test_methods(physical_migrated[filename])
            module = f"scripts.android_qualification.physical.{filename[:-3]}"
            for identity, old_method in baseline_methods.items():
                source_key = (filename, identity[0], identity[1])
                old_id = _test_id(module, identity)
                replacements = SAFETY_BOUNDARY_REPLACEMENTS.get(source_key)
                if replacements:
                    baseline_ids[old_id] = replacements
                    self._assert_safety_boundary_replacement(old_method, old_id, replacements)
                    continue
                new_id = _test_id(module, identity)
                baseline_ids[old_id] = (new_id,)
                self.assertIn(identity, current_methods, old_id)

        for relative_path in NEUTRAL_ACTIVE_TEST_FILES:
            current_source = (ROOT / relative_path).read_text(encoding="utf-8")
            current_methods = _test_methods(current_source)
            module = relative_path[:-3].replace("/", ".")
            for identity, method in current_methods.items():
                test_id = _test_id(module, identity)
                baseline_ids[test_id] = (test_id,)
                required = SAFETY_BOUNDARY_REQUIRED_ASSERTIONS.get(test_id)
                if required:
                    self.assertTrue(
                        set(required).issubset(_assertion_call_names(method)),
                        test_id,
                    )
        return baseline_ids

    def test_archived_physical_test_assertions_match_migrated_cases(self) -> None:
        violations = repository_checks.archive_violations(ROOT)
        self.assertEqual(violations, ())
        physical_baseline, physical_migrated = self._physical_sources()
        total_cases = 0
        for filename, old_source in physical_baseline.items():
            old_methods = _test_methods(old_source)
            current_methods = _test_methods(physical_migrated[filename])
            total_cases += len(old_methods)
            for identity, old_method in old_methods.items():
                source_key = (filename, identity[0], identity[1])
                replacements = SAFETY_BOUNDARY_REPLACEMENTS.get(source_key)
                with self.subTest(test=_test_id(filename, identity)):
                    if replacements:
                        module = f"scripts.android_qualification.physical.{filename[:-3]}"
                        self._assert_safety_boundary_replacement(
                            old_method, _test_id(module, identity), replacements)
                    else:
                        current_identity = identity
                        self.assertIn(current_identity, current_methods)
                        _assert_assertions_equivalent(
                            self,
                            _normalized_assertions(old_method),
                            _normalized_assertions(current_methods[current_identity]),
                            _test_id(filename, identity),
                            additional=ADDITIONAL_ASSERTIONS.get(
                                _test_id(
                                    f"scripts.android_qualification.physical.{filename[:-3]}",
                                    identity,
                                ),
                                (),
                            ),
                        )
        self.assertEqual(total_cases, 234)

        # The retired live-capable route and the now-closed module invocation
        # have explicit replacement tests whose safety claims are checked here.
        runner_methods = _test_methods(physical_migrated["test_runner.py"])
        closed_entrypoint = runner_methods[
            ("CLITests", "test_script_entrypoint_fails_closed_before_device_construction")
        ]
        calls = [
            node.func.attr
            for node in ast.walk(closed_entrypoint)
            if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
        ]
        self.assertIn("assert_not_called", calls)
        self.assertIn("LIVE_EXECUTION_NOT_IMPLEMENTED", ast.unparse(closed_entrypoint))

    def test_baseline_case_ids_are_mapped_and_discovered_once(self) -> None:
        baseline_ids = self._baseline_case_mapping()
        physical_ids = [
            test_id
            for test_id in baseline_ids
            if ".physical." in test_id
        ]
        neutral_ids = [test_id for test_id in baseline_ids if ".physical." not in test_id]
        self.assertEqual(len(physical_ids), 234)
        self.assertEqual(len(neutral_ids), 117)

        loader = unittest.TestLoader()
        suite = loader.discover(
            str(ROOT / "scripts/android_qualification"),
            pattern="test_*.py",
            top_level_dir=str(ROOT),
        )
        combined_ids = _suite_ids(suite)
        counts = Counter(combined_ids)
        self.assertTrue(all(count == 1 for count in counts.values()))
        for baseline_id, migrated_ids in baseline_ids.items():
            with self.subTest(test=baseline_id):
                for migrated_id in migrated_ids:
                    self.assertEqual(counts[migrated_id], 1)
        self.assertGreater(len(combined_ids), len(baseline_ids))


if __name__ == "__main__":
    unittest.main()
