"""Exercise the archive and active-surface contracts without touching devices."""

from __future__ import annotations

import hashlib
import io
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from unittest import mock

from scripts.android_qualification import repository_checks


ROOT = Path(__file__).resolve().parents[2]
PHYSICAL_IMPLEMENTATIONS = (
    "scripts/android_qualification/physical/core.py",
    "scripts/android_qualification/physical/fixtures.py",
    "scripts/android_qualification/physical/runner.py",
    "scripts/android_qualification/physical/ui.py",
)
CURRENT_CLASSIFICATION_RELATIVE_PATH = (
    "docs/qualification/surface-classifications-v1.json"
)
ARCHIVED_ISSUE21_CLASSIFICATION_SHA256 = (
    "4ed807af23fecaf66db498cd64625bda79d5f89ebb92db88d23f368a6943e58a"
)
ISSUE25_CLASSIFICATIONS = (
    "scripts/android_qualification/evidence.py",
    "scripts/android_qualification/_evidence_storage.py",
    "scripts/android_qualification/_evidence_review.py",
    "scripts/android_qualification/test_evidence_storage.py",
    "scripts/android_qualification/test_evidence_review.py",
    "scripts/android_qualification/test_evidence_issue24_boundary.py",
)
ISSUE27_CLASSIFICATIONS = (
    "scripts/android_qualification/_library_interaction_contract.py",
    "scripts/android_qualification/_library_interaction_executor.py",
    "scripts/android_qualification/_library_interaction_oracle.py",
    "scripts/android_qualification/physical/_library_interaction_ui.py",
    "scripts/android_qualification/test_library_interactions.py",
)
RETIRED_ISSUE24_STAGING_SURFACES = frozenset(
    {
        "scripts/android_qualification/_fixture_staging_content.py",
        "scripts/android_qualification/_fixture_staging_destination.py",
        "scripts/android_qualification/_fixture_staging_manifest.py",
        "scripts/android_qualification/_fixture_staging_model.py",
        "scripts/android_qualification/_fixture_staging_orchestration.py",
        "scripts/android_qualification/_fixture_staging_ownership.py",
        "scripts/android_qualification/_fixture_staging_transfer.py",
        "scripts/android_qualification/_fixture_staging_test_support.py",
        "scripts/android_qualification/test_fixture_staging_authorization.py",
        "scripts/android_qualification/test_fixture_staging_content.py",
        "scripts/android_qualification/test_fixture_staging_destination.py",
        "scripts/android_qualification/test_fixture_staging_recovery.py",
    }
)
ISSUE24_STAGING_CLASSIFICATIONS = (
    "scripts/android_qualification/fixture_staging_contract.py",
    "scripts/android_qualification/fixture_staging_files.py",
    "scripts/android_qualification/fixture_staging_manifest.py",
    "scripts/android_qualification/fixture_staging_orchestration.py",
    "scripts/android_qualification/fixture_staging_runs.py",
    "scripts/android_qualification/fixture_oracle.py",
    "scripts/android_qualification/test_fixture_oracle.py",
    "scripts/android_qualification/test_fixture_staging_simple.py",
)


def _copy_naming_fixture(root: Path) -> list[dict[str, object]]:
    data = repository_checks._read_classification(ROOT)
    selected_paths = {*PHYSICAL_IMPLEMENTATIONS, "docs/qualification/README.md"}
    surfaces = [surface for surface in data["surfaces"] if surface["path"] in selected_paths]
    copied: set[str] = set()
    for surface in surfaces:
        relative = surface["path"]
        if relative in copied:
            continue
        destination = root / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / relative, destination)
        copied.add(relative)

    history = "docs/implementation/project-history.md"
    history_path = root / history
    history_path.parent.mkdir(parents=True, exist_ok=True)
    history_path.write_text("historical note\n", encoding="utf-8")
    surfaces.append({"path": history, "classification": "archival_planning", "region": {"kind": "file"}})

    development_test = "tests/test_unrelated_names.py"
    development_test_path = root / development_test
    development_test_path.parent.mkdir(parents=True, exist_ok=True)
    development_test_path.write_text("unrelated development test\n", encoding="utf-8")
    surfaces.append(
        {
            "path": development_test,
            "classification": "unrelated_development_test",
            "region": {"kind": "file"},
        }
    )

    classification_path = root / repository_checks.CLASSIFICATION_RELATIVE_PATH
    classification_path.parent.mkdir(parents=True, exist_ok=True)
    classification_path.write_text(
        json.dumps({"schema_version": 1, "surfaces": surfaces}),
        encoding="utf-8",
    )

    archive_history = root / repository_checks.ARCHIVE_DIRECTORY / "original/historical.py"
    archive_history.parent.mkdir(parents=True, exist_ok=True)
    archive_history.write_text("archived record\n", encoding="utf-8")
    return surfaces


class ArchiveContractTests(unittest.TestCase):
    def test_checked_in_archive_matches_independent_git_authority(self) -> None:
        self.assertEqual(repository_checks.archive_violations(ROOT), ())

    def test_archive_verification_does_not_require_a_git_object_database(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            shutil.copytree(
                ROOT / repository_checks.ARCHIVE_DIRECTORY,
                root / repository_checks.ARCHIVE_DIRECTORY,
            )
            self.assertEqual(repository_checks.archive_violations(root), ())

    def test_archive_verification_is_independent_of_current_naming_inventory(self) -> None:
        with mock.patch.object(
            repository_checks,
            "CLASSIFICATION_RELATIVE_PATH",
            "missing-current-inventory.json",
        ):
            self.assertEqual(repository_checks.archive_violations(ROOT), ())

    def _synthetic_archive(self) -> tuple[tempfile.TemporaryDirectory[str], Path, dict[str, bytes]]:
        temporary = tempfile.TemporaryDirectory()
        root = Path(temporary.name)
        sources = (
            f"{repository_checks.PHYSICAL_SOURCE_PREFIX}/core.py",
            f"{repository_checks.PHYSICAL_SOURCE_PREFIX}/test_core.py",
        )
        extras = repository_checks.EXPLICIT_BASELINE_ENTRIES
        baseline = {
            sources[0]: b"source bytes\n",
            sources[1]: b"test bytes\n",
            extras[0][1]: b"entrypoint bytes\n",
            extras[1][1]: b"historical document bytes\n",
        }
        entries = []
        for original, content in baseline.items():
            archived = repository_checks._archive_entry_path(original)
            archived_file = root / archived
            archived_file.parent.mkdir(parents=True, exist_ok=True)
            archived_file.write_bytes(content)
            entries.append(
                {
                    "role": repository_checks._role_for_baseline_path(original),
                    "original_path": original,
                    "archived_path": archived,
                    "sha256": hashlib.sha256(content).hexdigest(),
                }
            )
        manifest = {
            "manifest_version": 1,
            "fetched_base_commit": repository_checks.BASE_COMMIT,
            "historical_device_owned_directory": repository_checks.HISTORICAL_DEVICE_DIRECTORY,
            "entries": entries,
        }
        manifest_path = root / repository_checks.MANIFEST_RELATIVE_PATH
        manifest_path.parent.mkdir(parents=True, exist_ok=True)
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        self.addCleanup(temporary.cleanup)
        return temporary, manifest_path, baseline

    def _run_synthetic(self, manifest_path: Path, baseline: dict[str, bytes]) -> tuple[str, ...]:
        root = manifest_path.parents[4]
        with (
            mock.patch.object(
                repository_checks,
                "_baseline_source_paths",
                return_value=(
                    f"{repository_checks.PHYSICAL_SOURCE_PREFIX}/core.py",
                    f"{repository_checks.PHYSICAL_SOURCE_PREFIX}/test_core.py",
                ),
            ),
            mock.patch.object(
                repository_checks,
                "_baseline_blob",
                side_effect=lambda _root, path: baseline.get(path, b""),
            ),
        ):
            return repository_checks.archive_violations(root)

    def test_candidate_manifest_cannot_omit_a_baseline_path(self) -> None:
        _temporary, manifest_path, baseline = self._synthetic_archive()
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["entries"].pop()
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        self.assertTrue(any("missing manifest entry" in item for item in self._run_synthetic(manifest_path, baseline)))

    def test_candidate_manifest_cannot_duplicate_or_add_paths(self) -> None:
        _temporary, manifest_path, baseline = self._synthetic_archive()
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["entries"].append(dict(manifest["entries"][0]))
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        errors = self._run_synthetic(manifest_path, baseline)
        self.assertTrue(any("duplicate original path" in item for item in errors))

        manifest["entries"].pop()
        extra = dict(manifest["entries"][0])
        extra["original_path"] = "scripts/retired_harness/extra.py"
        extra["archived_path"] = repository_checks._archive_entry_path(extra["original_path"])
        manifest["entries"].append(extra)
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        self.assertTrue(any("unexpected manifest entry" in item for item in self._run_synthetic(manifest_path, baseline)))

    def test_baseline_mismatch_digest_mismatch_and_unsafe_path_are_rejected(self) -> None:
        _temporary, manifest_path, baseline = self._synthetic_archive()
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["fetched_base_commit"] = "0" * 40
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        self.assertTrue(any("fixed archive baseline" in item for item in self._run_synthetic(manifest_path, baseline)))

        manifest["fetched_base_commit"] = repository_checks.BASE_COMMIT
        manifest["entries"][0]["sha256"] = "0" * 64
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        self.assertTrue(any("fixed provenance" in item for item in self._run_synthetic(manifest_path, baseline)))

        manifest["entries"][0]["original_path"] = "../outside.py"
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        self.assertTrue(any("unsafe original path" in item for item in self._run_synthetic(manifest_path, baseline)))

    def test_archived_bytes_must_equal_git_blob_bytes(self) -> None:
        _temporary, manifest_path, baseline = self._synthetic_archive()
        archived = manifest_path.parent / "original" / repository_checks.PHYSICAL_SOURCE_PREFIX / "core.py"
        archived.write_bytes(b"modified archive bytes\n")
        errors = self._run_synthetic(manifest_path, baseline)
        self.assertTrue(any("SHA-256 mismatch" in item for item in errors))

    def test_candidate_archive_cannot_contain_extra_files(self) -> None:
        _temporary, manifest_path, baseline = self._synthetic_archive()
        extra = manifest_path.parent / "original/unlisted.txt"
        extra.write_text("unexpected", encoding="utf-8")
        errors = self._run_synthetic(manifest_path, baseline)
        self.assertTrue(any("unexpected archived file: unlisted.txt" in item for item in errors))

    def test_archived_path_must_use_the_exact_archive_prefix(self) -> None:
        _temporary, manifest_path, baseline = self._synthetic_archive()
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["entries"][0]["archived_path"] = "docs/elsewhere/core.py"
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        errors = self._run_synthetic(manifest_path, baseline)
        self.assertTrue(any("unsafe archived path" in item for item in errors))

    def test_source_paths_are_derived_from_the_exact_baseline_tree_prefix(self) -> None:
        prefix = repository_checks.PHYSICAL_SOURCE_PREFIX
        baseline_output = f"{prefix}/core.py\n{prefix}-neighbor/ignored.py\n"
        with mock.patch.object(
            repository_checks.subprocess,
            "run",
            return_value=mock.Mock(stdout=baseline_output),
        ) as git_run:
            paths = repository_checks._baseline_source_paths(ROOT)
        self.assertEqual(paths, (f"{prefix}/core.py",))
        command = git_run.call_args.args[0]
        self.assertEqual(command[:4], ["git", "ls-tree", "-r", "--name-only"])
        self.assertEqual(command[4:], [repository_checks.BASE_COMMIT, "--", prefix])


class ClassificationSchemaTests(unittest.TestCase):
    def test_new_package_files_must_be_classified_and_qualification_tests_active(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            package = root / "scripts/android_qualification"
            physical = package / "physical"
            planning = root / "docs/implementation"
            package.mkdir(parents=True)
            physical.mkdir()
            planning.mkdir(parents=True)
            files = {
                package / "__init__.py": "\n",
                package / "test_sample.py": "\n",
                package / "new_surface.py": "\n",
                physical / "helper.py": "\n",
                planning / "old-notes.md": "\n",
            }
            for path, content in files.items():
                path.write_text(content, encoding="utf-8")
            surfaces = [
                {
                    "path": "scripts/android_qualification/__init__.py",
                    "classification": "active",
                    "region": {"kind": "file"},
                },
                {
                    "path": "scripts/android_qualification/test_sample.py",
                    "classification": "unrelated_development_test",
                    "region": {"kind": "file"},
                },
                {
                    "path": "scripts/android_qualification/physical/helper.py",
                    "classification": "compatibility_only",
                    "region": {"kind": "file"},
                },
                {
                    "path": "docs/implementation/old-notes.md",
                    "classification": "archival_planning",
                    "region": {"kind": "file"},
                },
            ]
            classification_path = root / repository_checks.CLASSIFICATION_RELATIVE_PATH
            classification_path.parent.mkdir(parents=True)
            classification_path.write_text(
                json.dumps({"schema_version": 1, "surfaces": surfaces}),
                encoding="utf-8",
            )
            with mock.patch.object(repository_checks, "REQUIRED_SURFACES", (surfaces[2],)):
                errors = repository_checks.classification_violations(root)

        self.assertTrue(
            any("unclassified qualification candidate surface" in item and "new_surface.py" in item for item in errors)
        )
        self.assertTrue(
            any("qualification test surface must be active" in item and "test_sample.py" in item for item in errors)
        )

    def test_new_qualification_implementation_python_must_be_active(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            path = "scripts/android_qualification/new_implementation.py"
            implementation = root / path
            implementation.parent.mkdir(parents=True)
            implementation.write_text("value = 1\n", encoding="utf-8")
            errors = repository_checks._closed_world_classification_violations(
                root,
                [{"path": path, "classification": "compatibility_only", "region": {"kind": "file"}}],
            )

        self.assertIn(f"qualification implementation surface must be active: {path}", errors)

    def test_required_surface_cannot_be_omitted_or_duplicated(self) -> None:
        required = {
            "path": "scripts/qualification.py",
            "classification": "active",
            "region": {"kind": "file"},
        }
        with mock.patch.object(repository_checks, "REQUIRED_SURFACES", (required,)):
            missing = repository_checks.classification_schema_violations(
                {"schema_version": 1, "surfaces": []}
            )
            duplicated = repository_checks.classification_schema_violations(
                {"schema_version": 1, "surfaces": [required, required]}
            )
        self.assertTrue(any("missing required surface" in item for item in missing))
        self.assertTrue(any("duplicate classified surface" in item for item in duplicated))

    def test_qualification_readme_allows_only_the_four_legacy_crosswalk_exceptions(self) -> None:
        data = repository_checks._read_classification(ROOT)
        data["surfaces"].append(
            {
                "path": "docs/qualification/README.md",
                "classification": "compatibility_only",
                "region": {"kind": "markdown_line", "text": "| unreviewed | Retired and archived | unreviewed |"},
            }
        )

        errors = repository_checks.classification_schema_violations(data)

        self.assertIn("qualification README compatibility exceptions must match the legacy crosswalk", errors)

    def test_classification_paths_are_exact_and_excluded_categories_are_not_scanned(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            active = "scripts/run_phase_002_android_scenario_common_sibling.sh"
            paths_and_contents = {
                active: "p 8\n",
                "scripts/run_phase_002_android_scenario_common.sh": "P03\n",
                "docs/implementation/phase-003-manual-qualification.md": "slice 3\n",
                "tests/test_old_names.py": "milestone 4\n",
            }
            categories = (
                ("active", {"kind": "file"}),
                ("compatibility_only", {"kind": "file"}),
                ("archival_planning", {"kind": "file"}),
                ("unrelated_development_test", {"kind": "file"}),
            )
            surfaces = []
            for (path, content), (category, region) in zip(paths_and_contents.items(), categories):
                file_path = root / path
                file_path.parent.mkdir(parents=True, exist_ok=True)
                file_path.write_text(content, encoding="utf-8")
                surfaces.append({"path": path, "classification": category, "region": region})
            classification_path = root / repository_checks.CLASSIFICATION_RELATIVE_PATH
            classification_path.parent.mkdir(parents=True, exist_ok=True)
            classification_path.write_text(
                json.dumps({"schema_version": 1, "surfaces": surfaces}),
                encoding="utf-8",
            )
            with mock.patch.object(repository_checks, "REQUIRED_SURFACES", tuple(surfaces[1:3])):
                errors = repository_checks.active_naming_violations(root)
        self.assertEqual(len(errors), 1)
        self.assertIn(active, errors[0])

    def test_unsafe_and_unclassified_paths_are_rejected(self) -> None:
        with mock.patch.object(repository_checks, "REQUIRED_SURFACES", ()):
            errors = repository_checks.classification_schema_violations(
                {
                    "schema_version": 1,
                    "surfaces": [
                        {
                            "path": "../outside.py",
                            "classification": "active",
                            "region": {"kind": "file"},
                        }
                    ],
                }
            )
        self.assertTrue(any("unsafe classified path" in item for item in errors))



class CurrentNamingInventoryTests(unittest.TestCase):
    def test_current_inventory_is_the_naming_authority(self) -> None:
        self.assertEqual(
            repository_checks.CLASSIFICATION_RELATIVE_PATH,
            CURRENT_CLASSIFICATION_RELATIVE_PATH,
        )
        self.assertEqual(repository_checks.classification_violations(ROOT), ())

    def test_current_inventory_retires_old_issue24_surfaces_then_lists_current_work(self) -> None:
        archive_path = (
            ROOT
            / repository_checks.ARCHIVE_DIRECTORY
            / "surface-classifications-v1.json"
        )
        current_path = ROOT / CURRENT_CLASSIFICATION_RELATIVE_PATH
        self.assertTrue(current_path.is_file())
        archived = json.loads(archive_path.read_text(encoding="utf-8"))
        current = json.loads(current_path.read_text(encoding="utf-8"))

        archived_surfaces = archived["surfaces"]
        retained_archived = [
            surface for surface in archived_surfaces
            if surface["path"] not in RETIRED_ISSUE24_STAGING_SURFACES
        ]
        expected_issue24 = [
            {
                "path": relative,
                "classification": "active",
                "region": {"kind": "file"},
            }
            for relative in ISSUE24_STAGING_CLASSIFICATIONS
        ]
        expected_issue25 = [
            {
                "path": relative,
                "classification": "active",
                "region": {"kind": "file"},
            }
            for relative in ISSUE25_CLASSIFICATIONS
        ]
        self.assertEqual(len(archived_surfaces), 121)
        self.assertEqual(current["schema_version"], archived["schema_version"])
        self.assertEqual(current["surfaces"][:len(retained_archived)], retained_archived)
        issue24_start = len(retained_archived)
        issue24_end = issue24_start + len(expected_issue24)
        self.assertEqual(current["surfaces"][issue24_start:issue24_end], expected_issue24)
        issue25_end = issue24_end + len(expected_issue25)
        self.assertEqual(current["surfaces"][issue24_end:issue25_end], expected_issue25)
        expected_issue27 = [
            {
                "path": relative,
                "classification": "active",
                "region": {"kind": "file"},
            }
            for relative in ISSUE27_CLASSIFICATIONS
        ]
        self.assertEqual(current["surfaces"][issue25_end:], expected_issue27)
        self.assertEqual(
            len(current["surfaces"]),
            len(retained_archived)
            + len(expected_issue24)
            + len(expected_issue25)
            + len(expected_issue27),
        )

    def test_issue25_files_are_active_whole_file_classifications(self) -> None:
        data = repository_checks._read_classification(ROOT)
        rows = {surface["path"]: surface for surface in data["surfaces"]}
        for relative in ISSUE25_CLASSIFICATIONS:
            with self.subTest(relative=relative):
                self.assertIn(relative, rows)
                self.assertEqual(rows[relative]["classification"], "active")
                self.assertEqual(rows[relative]["region"], {"kind": "file"})

    def test_issue27_files_are_active_whole_file_classifications(self) -> None:
        data = repository_checks._read_classification(ROOT)
        rows = {surface["path"]: surface for surface in data["surfaces"]}
        for relative in ISSUE27_CLASSIFICATIONS:
            with self.subTest(relative=relative):
                self.assertIn(relative, rows)
                self.assertEqual(rows[relative]["classification"], "active")
                self.assertEqual(rows[relative]["region"], {"kind": "file"})

    def test_current_inventory_requires_each_surface_once(self) -> None:
        data = repository_checks._read_classification(ROOT)
        required = next(
            surface
            for surface in data["surfaces"]
            if surface["path"] == ISSUE25_CLASSIFICATIONS[0]
        )
        remaining = [
            surface for surface in data["surfaces"] if surface != required
        ]
        with mock.patch.object(repository_checks, "REQUIRED_SURFACES", (required,)):
            missing = repository_checks.classification_schema_violations(
                {"schema_version": 1, "surfaces": remaining}
            )
            duplicated = repository_checks.classification_schema_violations(
                {"schema_version": 1, "surfaces": [required, required]}
            )

        self.assertTrue(any("missing required surface" in item for item in missing))
        self.assertTrue(any("duplicate classified surface" in item for item in duplicated))

    def test_unexpected_python_surface_and_archival_exception_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            package = root / "scripts/android_qualification"
            package.mkdir(parents=True)
            relative = "scripts/android_qualification/unexpected.py"
            (root / relative).write_text("pass\n", encoding="utf-8")

            unclassified = repository_checks._closed_world_classification_violations(
                root, []
            )
            with mock.patch.object(repository_checks, "REQUIRED_SURFACES", ()):
                archival_exception = (
                    repository_checks._closed_world_classification_violations(
                        root,
                        [
                            {
                                "path": relative,
                                "classification": "archival_planning",
                                "region": {"kind": "file"},
                            }
                        ],
                    )
                )

        self.assertIn(
            f"unclassified qualification candidate surface: {relative}",
            unclassified,
        )
        self.assertIn(
            f"qualification implementation surface must be active: {relative}",
            archival_exception,
        )

    def test_archived_issue21_classification_hash_remains_pinned(self) -> None:
        archive_path = (
            ROOT
            / repository_checks.ARCHIVE_DIRECTORY
            / "surface-classifications-v1.json"
        )
        self.assertEqual(
            hashlib.sha256(archive_path.read_bytes()).hexdigest(),
            ARCHIVED_ISSUE21_CLASSIFICATION_SHA256,
        )

    def test_current_naming_diagnostics_are_deterministic(self) -> None:
        outputs: list[tuple[str, str]] = []
        for _ in range(2):
            stdout = io.StringIO()
            stderr = io.StringIO()
            with redirect_stdout(stdout), redirect_stderr(stderr):
                result = repository_checks.main(["naming"])
            self.assertEqual(result, 0)
            outputs.append((stdout.getvalue(), stderr.getvalue()))
        self.assertEqual(outputs[0], outputs[1])


class ActiveNamingContractTests(unittest.TestCase):
    def test_current_classified_surfaces_pass(self) -> None:
        self.assertEqual(repository_checks.active_naming_violations(ROOT), ())

    def test_protected_governing_wording_has_narrow_compatibility_rows(self) -> None:
        expected = {
            "docs/reference/qualification-design-decisions.md": 4,
            "docs/specifications/cross-cutting/spec-x-003-qualification-contract.md": 1,
        }
        compatibility_rows = [
            surface
            for surface in repository_checks.REQUIRED_SURFACES
            if surface["path"] in expected
            and surface["classification"] == "compatibility_only"
            and surface["region"]["kind"] == "markdown_line"
        ]
        actual = {
            path: sum(surface["path"] == path for surface in compatibility_rows)
            for path in expected
        }
        self.assertEqual(actual, expected)

    def test_general_numbered_names_and_terms_are_rejected_case_insensitively(self) -> None:
        phase_word = "pha" + "se"
        slice_word = "sli" + "ce"
        milestone_word = "mile" + "stone"
        examples = (
            phase_word + "003",
            phase_word + " 3",
            phase_word + "_0002",
            "P03",
            "P-0002",
            "p 7",
            slice_word,
            milestone_word,
        )
        for example in examples:
            with self.subTest(example=example):
                self.assertTrue(repository_checks.contains_prohibited_name(example.upper()))
        self.assertFalse(repository_checks.contains_prohibited_name("phase-neutral qualification"))
        self.assertFalse(repository_checks.contains_prohibited_name("provider identity matrix"))

    def test_each_physical_implementation_is_scanned_for_numbered_terms(self) -> None:
        numbered_term = "pha" + "se" + " 7"
        for relative in PHYSICAL_IMPLEMENTATIONS:
            with self.subTest(path=relative), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                surfaces = _copy_naming_fixture(root)
                target = root / relative
                target.write_text(target.read_text(encoding="utf-8") + numbered_term + "\n", encoding="utf-8")
                with (
                    mock.patch.object(repository_checks, "REQUIRED_SURFACES", tuple(surfaces)),
                    mock.patch.object(repository_checks, "EXPLICIT_QUALIFICATION_CANDIDATES", ()),
                ):
                    errors = repository_checks.active_naming_violations(root)
                self.assertIn(f"prohibited active qualification name in {relative}", errors)

    def test_public_host_validation_instructions_are_scanned(self) -> None:
        numbered_term = "pha" + "se" + " 7"
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            surfaces = _copy_naming_fixture(root)
            readme = root / "docs/qualification/README.md"
            content = readme.read_text(encoding="utf-8")
            heading = "## Public host validation\n"
            readme.write_text(content.replace(heading, heading + numbered_term + "\n", 1), encoding="utf-8")
            with (
                mock.patch.object(repository_checks, "REQUIRED_SURFACES", tuple(surfaces)),
                mock.patch.object(repository_checks, "EXPLICIT_QUALIFICATION_CANDIDATES", ()),
            ):
                errors = repository_checks.active_naming_violations(root)

        self.assertIn("prohibited active qualification name in docs/qualification/README.md", errors)

    def test_internal_host_test_harness_section_is_scanned(self) -> None:
        numbered_term = "pha" + "se" + " 7"
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            surfaces = _copy_naming_fixture(root)
            readme = root / "docs/qualification/README.md"
            content = readme.read_text(encoding="utf-8")
            heading = "## Internal host test harness\n"
            readme.write_text(content.replace(heading, heading + numbered_term + "\n", 1), encoding="utf-8")
            with (
                mock.patch.object(repository_checks, "REQUIRED_SURFACES", tuple(surfaces)),
                mock.patch.object(repository_checks, "EXPLICIT_QUALIFICATION_CANDIDATES", ()),
            ):
                errors = repository_checks.active_naming_violations(root)

        self.assertIn("prohibited active qualification name in docs/qualification/README.md", errors)

    def test_unapproved_compatibility_exception_cannot_hide_numbered_name(self) -> None:
        numbered_term = "pha" + "se" + " 7"
        relative = PHYSICAL_IMPLEMENTATIONS[0]
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            surfaces = _copy_naming_fixture(root)
            required_surfaces = tuple(surfaces)
            target = root / relative
            target.write_text(target.read_text(encoding="utf-8") + numbered_term + "\n", encoding="utf-8")
            surfaces.append(
                {
                    "path": relative,
                    "classification": "compatibility_only",
                    "region": {"kind": "text_line", "text": numbered_term},
                }
            )
            classification_path = root / repository_checks.CLASSIFICATION_RELATIVE_PATH
            classification_path.write_text(
                json.dumps({"schema_version": 1, "surfaces": surfaces}),
                encoding="utf-8",
            )
            with (
                mock.patch.object(repository_checks, "REQUIRED_SURFACES", required_surfaces),
                mock.patch.object(repository_checks, "EXPLICIT_QUALIFICATION_CANDIDATES", ()),
            ):
                errors = repository_checks.active_naming_violations(root)

        self.assertIn(f"unapproved compatibility-only surface: {relative}", errors)

    def test_automatically_discovered_qualification_shell_requires_whole_file_classification(self) -> None:
        relative = "scripts/qualify_new.sh"
        safe_line = "echo safe"
        numbered_term = "pha" + "se 7"
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            surfaces = _copy_naming_fixture(root)
            script = root / relative
            script.parent.mkdir(parents=True, exist_ok=True)
            script.write_text(f"{safe_line}\n{numbered_term}\n", encoding="utf-8")
            surfaces.append(
                {
                    "path": relative,
                    "classification": "active",
                    "region": {"kind": "text_line", "text": safe_line},
                }
            )
            classification_path = root / repository_checks.CLASSIFICATION_RELATIVE_PATH
            classification_path.write_text(
                json.dumps({"schema_version": 1, "surfaces": surfaces}),
                encoding="utf-8",
            )
            with (
                mock.patch.object(repository_checks, "REQUIRED_SURFACES", tuple(surfaces)),
                mock.patch.object(repository_checks, "EXPLICIT_QUALIFICATION_CANDIDATES", ()),
            ):
                errors = repository_checks.active_naming_violations(root)

            self.assertIn(
                f"qualification candidate surface must be active as a whole file: {relative}",
                errors,
            )

            surfaces[-1]["region"] = {"kind": "file"}
            classification_path.write_text(
                json.dumps({"schema_version": 1, "surfaces": surfaces}),
                encoding="utf-8",
            )
            with (
                mock.patch.object(repository_checks, "REQUIRED_SURFACES", tuple(surfaces)),
                mock.patch.object(repository_checks, "EXPLICIT_QUALIFICATION_CANDIDATES", ()),
            ):
                full_file_errors = repository_checks.active_naming_violations(root)

        self.assertIn(
            f"prohibited active qualification name in {relative}",
            full_file_errors,
        )

    def test_historical_archive_and_unrelated_development_tests_remain_excluded(self) -> None:
        numbered_term = "pha" + "se" + " 7"
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            surfaces = _copy_naming_fixture(root)
            history = root / "docs/implementation/project-history.md"
            history.write_text(numbered_term + "\n", encoding="utf-8")
            development_test = root / "tests/test_unrelated_names.py"
            development_test.write_text(numbered_term + "\n", encoding="utf-8")
            archive = root / repository_checks.ARCHIVE_DIRECTORY / "original/historical.py"
            archive.write_text(numbered_term + "\n", encoding="utf-8")
            with (
                mock.patch.object(repository_checks, "REQUIRED_SURFACES", tuple(surfaces)),
                mock.patch.object(repository_checks, "EXPLICIT_QUALIFICATION_CANDIDATES", ()),
            ):
                errors = repository_checks.active_naming_violations(root)

        self.assertEqual(errors, ())

    def test_legacy_crosswalk_rows_keep_exact_output(self) -> None:
        phase = "pha" + "se"
        expected = (
            "| `scripts/" + phase + "_003_android_physical_qualification` | Retired and archived | `scripts/android_qualification/physical` |",
            "| `scripts/run_" + phase + "_003_android_physical_qualification.sh` | Retired and archived | `retired; no active compatibility entrypoint` |",
            "| `docs/implementation/" + phase + "-003-android-physical-automation.md` | Retired and archived | `docs/qualification/README.md` |",
            "| `Argus" + phase.title() + "003Qualification` | Retired and archived | `ArgusQualification` |",
        )
        self.assertEqual(repository_checks._legacy_mapping_rows(), expected)

    def test_markdown_section_extraction_stops_at_next_heading(self) -> None:
        phase_word = "pha" + "se"
        text = (
            "# Project planning\n"
            + phase_word
            + " 4 is unrelated\n\n## Qualification authority\nCurrent host checks.\n"
            "## Historical planning\n"
            + phase_word
            + " 5 remains historical.\n"
        )
        section = repository_checks.extract_markdown_section(text, "Qualification authority")
        self.assertIn("Current host checks", section)
        self.assertNotIn(phase_word + " 4", section)
        self.assertNotIn(phase_word + " 5", section)

    def test_just_recipe_extraction_does_not_scan_unrelated_development_targets(self) -> None:
        phase_word = "pha" + "se"
        active = "test-android-qualification"
        unrelated = "test-" + phase_word + "-002-android-final"
        text = (
            active
            + ":\n    python3 -m unittest\n\n"
            + unrelated
            + ":\n    run development tests\n"
        )
        selected = repository_checks.extract_just_recipes(text, (active,))
        self.assertIn("python3", selected)
        self.assertNotIn(unrelated, selected)

    def test_checked_in_classification_covers_the_required_surfaces_once(self) -> None:
        self.assertEqual(repository_checks.classification_violations(ROOT), ())


class CliContractTests(unittest.TestCase):
    def test_just_modes_return_deterministic_success(self) -> None:
        for mode in ("archive", "naming"):
            with self.subTest(mode=mode):
                output = []
                for _ in range(2):
                    stream = io.StringIO()
                    with redirect_stdout(stream):
                        self.assertEqual(repository_checks.main([mode]), 0)
                    output.append(stream.getvalue())
                self.assertEqual(output[0], output[1])

    def test_failure_output_is_deterministic_and_does_not_leak_absolute_paths(self) -> None:
        with mock.patch.object(
            repository_checks,
            "archive_violations",
            return_value=("invalid archive at relative/file",),
        ):
            outputs = []
            for _ in range(2):
                stderr = io.StringIO()
                with redirect_stderr(stderr):
                    self.assertEqual(repository_checks.main(["archive"]), 1)
                outputs.append(stderr.getvalue())
        self.assertEqual(outputs[0], outputs[1])
        self.assertNotIn(str(ROOT), outputs[0])
        self.assertIn("relative/file", outputs[0])


if __name__ == "__main__":
    unittest.main()
