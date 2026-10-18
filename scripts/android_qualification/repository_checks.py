"""Validate qualification archive provenance and active naming boundaries."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
ARCHIVE_DIRECTORY = "docs/archive/qualification/issue-21-v1"
MANIFEST_RELATIVE_PATH = f"{ARCHIVE_DIRECTORY}/archive-manifest-v1.json"
BASE_COMMIT = "5d3cc1e166a0760bc1076c648a47052ac268bddc"
HISTORICAL_DEVICE_DIRECTORY = "/sdcard/ArgusPha" + "se003Qualification"
PHYSICAL_SOURCE_PREFIX = "scripts/pha" + "se_003_android_physical_qualification"
RETIRED_ENTRYPOINT = "scripts/run_pha" + "se_003_android_physical_qualification.sh"
HISTORICAL_TECHNICAL_DOCUMENT = "docs/implementation/pha" + "se-003-android-physical-automation.md"
HISTORICAL_MANUAL_DOCUMENT = "docs/implementation/pha" + "se-003-manual-qualification.md"
PHYSICAL_SCENARIO_HELPER = "scripts/run_pha" + "se_002_android_scenario_common.sh"
PHYSICAL_SCENARIO_SOURCE_LINE = 'source "${ROOT_DIR}/scripts/run_pha' + 'se_002_android_scenario_common.sh"'
CI_HISTORICAL_TEST_JOB = "pha" + "se-001-native"
CLASSIFICATION_RELATIVE_PATH = f"{ARCHIVE_DIRECTORY}/surface-classifications-v1.json"

# These two non-source paths are pinned separately from Git tree discovery.
EXPLICIT_BASELINE_ENTRIES = (
    ("retired_entrypoint", RETIRED_ENTRYPOINT),
    ("historical_technical_document", HISTORICAL_TECHNICAL_DOCUMENT),
)

# These path and digest pairs keep archive verification usable when a checkout
# does not contain the fixed provenance commit object.
PINNED_BASELINE_ENTRIES = (
    ("retired_entrypoint", RETIRED_ENTRYPOINT, "4014179356c5567c29ceb0ed59d3fee92b2a403d4cb9cabdbcc374b815f413b7"),
    ("physical_source", f"{PHYSICAL_SOURCE_PREFIX}/core.py", "b30cf6708973593c9b7134b9b6d718688056bd0e365a9ce50b58a6a0d1d6a0fd"),
    ("physical_source", f"{PHYSICAL_SOURCE_PREFIX}/fixtures.py", "7caf20c2124ba7bbc45419476fbc0fbbc4d0bd4fd8c6fe612f7339e0562cfab4"),
    ("physical_source", f"{PHYSICAL_SOURCE_PREFIX}/runner.py", "c95c07cd88a8bb6ee23303804b11a806187580278c7e3a67bf94af9b36ad04d6"),
    ("physical_test", f"{PHYSICAL_SOURCE_PREFIX}/test_core.py", "83f33e85a541de4087a2ead02a14318bfd454548550ec6feba6e979935737ffd"),
    ("physical_test", f"{PHYSICAL_SOURCE_PREFIX}/test_fixtures.py", "262457bcae71bf09aa4a9aeb16cabbfa263419881dc3c48be9cb1c469c32023f"),
    ("physical_test", f"{PHYSICAL_SOURCE_PREFIX}/test_recipe.py", "937fe97f156d836f88847cca5a19fecc781d0c7b2c92fb2b4bde5e1727f69209"),
    ("physical_test", f"{PHYSICAL_SOURCE_PREFIX}/test_runner.py", "85886ec96fa54e7643225cae9a800c8d43faab4c080b695190917526c0d7a7c8"),
    ("physical_test", f"{PHYSICAL_SOURCE_PREFIX}/test_storage_access.py", "f6202362adc6856a2da9dcd71f324c45b2d244a52575ec1cf7b4408b6ee0709a"),
    ("physical_test", f"{PHYSICAL_SOURCE_PREFIX}/test_ui.py", "dbd6b1dc6076c8c34d568a6103e11b963e5083ae17c8da4a313c6432114902a7"),
    ("physical_source", f"{PHYSICAL_SOURCE_PREFIX}/ui.py", "82b81e83a2fb04fdf547fd022d10308fa850c459d62d3969fe6fd0d1d22a1e95"),
    ("historical_technical_document", HISTORICAL_TECHNICAL_DOCUMENT, "f6305688122f409219e57ee9a83916a5f078628d0ca3cc409e7e7caaa61d320b"),
)

LEGACY_NAME_MAPPINGS = (
    (PHYSICAL_SOURCE_PREFIX, "scripts/android_qualification/physical"),
    (RETIRED_ENTRYPOINT, "retired; no active compatibility entrypoint"),
    (HISTORICAL_TECHNICAL_DOCUMENT, "docs/qualification/README.md"),
    ("ArgusPha" + "se003Qualification", "ArgusQualification"),
)

CLASSIFICATION_CATEGORIES = (
    "active",
    "compatibility_only",
    "archival_planning",
    "unrelated_development_test",
)

QUALIFICATION_PACKAGE = "scripts/android_qualification"
EXPLICIT_QUALIFICATION_CANDIDATES = (
    "scripts/check_macos_frb_exports.sh",
    "scripts/macos_rust_build_environment.sh",
    "scripts/test_macos_frb_exports.sh",
    "scripts/test_macos_rust_build_environment.sh",
    "rust/crates/argus-runtime/tests/background_operations.rs",
)


def _surface(path: str, category: str, kind: str = "file", value: str | None = None) -> dict[str, Any]:
    region: dict[str, str] = {"kind": kind}
    if value is not None:
        if kind == "markdown_section":
            selector = "heading"
        elif kind in {"just_recipe", "yaml_job"}:
            selector = "name"
        else:
            selector = "text"
        region[selector] = value
    return {"path": path, "classification": category, "region": region}


def _legacy_mapping_rows() -> tuple[str, ...]:
    tick = chr(96)
    return tuple(
        f"| {tick}{old}{tick} | Retired and archived | {tick}{new}{tick} |"
        for old, new in LEGACY_NAME_MAPPINGS
    )


def _qualification_candidate_files(repository: Path) -> tuple[str, ...]:
    """Discover qualification code, named technical documents, and explicit exceptions."""
    candidates: set[str] = set()
    package = repository / QUALIFICATION_PACKAGE
    if package.is_dir():
        candidates.update(
            path.relative_to(repository).as_posix()
            for path in package.rglob("*.py")
            if path.is_file()
        )

    scripts = repository / "scripts"
    if scripts.is_dir():
        candidates.update(
            path.relative_to(repository).as_posix()
            for path in scripts.rglob("*.sh")
            if path.is_file() and any(token in path.name.casefold() for token in ("qualif", "qualify"))
        )

    documentation = repository / "docs"
    if documentation.is_dir():
        for path in documentation.rglob("*.md"):
            relative = path.relative_to(repository).as_posix()
            if (
                path.is_file()
                and "qualif" in path.name.casefold()
                and relative != ARCHIVE_DIRECTORY
                and not relative.startswith(f"{ARCHIVE_DIRECTORY}/")
            ):
                candidates.add(relative)

    for relative in EXPLICIT_QUALIFICATION_CANDIDATES:
        path = repository / relative
        if path.is_file() or path.is_symlink():
            candidates.add(relative)

    return tuple(sorted(candidates))


def _is_automatically_discovered_qualification_surface(relative: str) -> bool:
    """Identify named qualification shell and documentation surfaces."""
    path = PurePosixPath(relative)
    if path.parts[0] == "scripts":
        return path.suffix == ".sh" and any(token in path.name.casefold() for token in ("qualif", "qualify"))
    if path.parts[0] == "docs":
        return (
            path.suffix == ".md"
            and "qualif" in path.name.casefold()
            and relative != ARCHIVE_DIRECTORY
            and not relative.startswith(f"{ARCHIVE_DIRECTORY}/")
        )
    return False


def _closed_world_classification_violations(repository: Path, surfaces: list[Any]) -> tuple[str, ...]:
    """Require whole-file active rows except for enumerated archival documents."""
    classified_paths = {
        surface["path"]
        for surface in surfaces
        if isinstance(surface, dict) and isinstance(surface.get("path"), str)
    }
    active_file_paths = {
        surface["path"]
        for surface in surfaces
        if isinstance(surface, dict)
        and surface.get("classification") == "active"
        and surface.get("region") == {"kind": "file"}
        and isinstance(surface.get("path"), str)
    }
    required_archival_files = {
        surface["path"]
        for surface in REQUIRED_SURFACES
        if surface["classification"] == "archival_planning"
        and surface["region"] == {"kind": "file"}
    }
    enumerated_archival_files = {
        surface["path"]
        for surface in surfaces
        if isinstance(surface, dict)
        and surface.get("classification") == "archival_planning"
        and surface.get("region") == {"kind": "file"}
        and surface.get("path") in required_archival_files
    }
    violations: list[str] = []
    for relative in _qualification_candidate_files(repository):
        if relative not in classified_paths:
            violations.append(f"unclassified qualification candidate surface: {relative}")
            continue
        if relative in active_file_paths or relative in enumerated_archival_files:
            continue
        if not relative.startswith(f"{QUALIFICATION_PACKAGE}/") and not _is_automatically_discovered_qualification_surface(relative):
            continue
        if relative.startswith(f"{QUALIFICATION_PACKAGE}/") and relative.endswith(".py"):
            if relative not in active_file_paths:
                if PurePosixPath(relative).name.startswith("test_"):
                    violations.append(f"qualification test surface must be active: {relative}")
                else:
                    violations.append(f"qualification implementation surface must be active: {relative}")
        else:
            violations.append(f"qualification candidate surface must be active as a whole file: {relative}")
    return tuple(sorted(set(violations)))


REQUIRED_SURFACES = (
    _surface("scripts/android_qualification/repository_checks.py", "active"),
    _surface("scripts/android_qualification/physical/core.py", "active"),
    _surface("scripts/android_qualification/physical/fixtures.py", "active"),
    _surface("scripts/android_qualification/physical/runner.py", "active"),
    _surface("scripts/android_qualification/physical/ui.py", "active"),
    _surface("scripts/run_library_android_qualification.sh", "active"),
    _surface(PHYSICAL_SCENARIO_HELPER, "compatibility_only"),
    _surface(HISTORICAL_MANUAL_DOCUMENT, "archival_planning"),
    _surface(
        "docs/superpowers/specs/2026-08-30-pha" + "se-003-manual-qualification-closeout-design.md",
        "archival_planning",
    ),
    _surface(
        "docs/superpowers/plans/2026-10-15-argus-qualification-implementation-plan.md",
        "archival_planning",
    ),
    _surface("scripts/run_library_desktop_qualification.sh", "active"),
    _surface("scripts/run_deterministic_qualification.sh", "active"),
    _surface("scripts/run_live_provider_qualification.sh", "active"),
    _surface("scripts/check_qualification_record.sh", "active"),
    _surface("docs/implementation/library-capability-qualification.md", "active"),
    _surface(".github/workflows/ci.yml", "active", "yaml_job", "quality"),
    _surface(".github/workflows/ci.yml", "unrelated_development_test", "yaml_job", CI_HISTORICAL_TEST_JOB),
    _surface("scripts/run_library_android_qualification.sh", "compatibility_only", "markdown_line", PHYSICAL_SCENARIO_SOURCE_LINE),
    _surface(
        "scripts/android_qualification/test_repository_checks.py",
        "compatibility_only",
        "text_line",
        '            active = "scripts/run_pha' + "se_002_android_scenario_common_sibling.sh\"",
    ),
    _surface(
        "scripts/android_qualification/test_repository_checks.py",
        "compatibility_only",
        "text_line",
        '                active: "p ' + '8\\n",',
    ),
    _surface(
        "scripts/android_qualification/test_repository_checks.py",
        "compatibility_only",
        "text_line",
        '                "scripts/run_pha' + 'se_002_android_scenario_common.sh": "P' + '03\\n",',
    ),
    _surface(
        "scripts/android_qualification/test_repository_checks.py",
        "compatibility_only",
        "text_line",
        '                "docs/implementation/pha' + 'se-003-manual-qualification.md": "sli' + 'ce 3\\n",',
    ),
    _surface(
        "scripts/android_qualification/test_repository_checks.py",
        "compatibility_only",
        "text_line",
        '                "tests/test_old_names.py": "mile' + 'stone 4\\n",',
    ),
    _surface(
        "scripts/android_qualification/test_repository_checks.py",
        "compatibility_only",
        "text_line",
        '            "P' + '03",',
    ),
    _surface(
        "scripts/android_qualification/test_repository_checks.py",
        "compatibility_only",
        "text_line",
        '            "P-' + '0002",',
    ),
    _surface(
        "scripts/android_qualification/test_repository_checks.py",
        "compatibility_only",
        "text_line",
        '            "p ' + '7",',
    ),
    _surface("README.md", "active", "markdown_section", "Android qualification entrypoints"),
    _surface("docs/README.md", "active", "markdown_section", "Qualification authority"),
    _surface("docs/archive/README.md", "active", "markdown_section", "Archive index"),
    _surface(
        "docs/reference/qualification-design-decisions.md",
        "compatibility_only",
        "markdown_line",
        "- Migrate the current `scripts/pha" + "se_003_android_physical_qualification` automation into pha" + "se-neutral active source, tests, and test plans. Keep retired source references as historical provenance only in planning/archival evidence.",
    ),
    _surface(
        "docs/reference/qualification-design-decisions.md",
        "compatibility_only",
        "markdown_line",
        "- Q112A: pha" + "se-neutral qualification outcomes and owner-approved assessments are consumed through a separate planning-layer mapping. The qualification system does not declare project pha" + "ses or sli" + "ces complete.",
    ),
    _surface(
        "docs/reference/qualification-design-decisions.md",
        "compatibility_only",
        "markdown_line",
        "4. For whole-release closeout, pending macOS UX scenarios remain mandatory even though initial automation delivery focuses on Android; separate the initial Android qualification mile" + "stone from a completed release assessment.",
    ),
    _surface(
        "docs/reference/qualification-design-decisions.md",
        "compatibility_only",
        "markdown_line",
        "- Q122A: first acceptance mile" + "stone is a real, authorized, isolated Android Release qualification session that validates artifact/fixture admission, one real product behavior, fail-fast behavior, durable evidence, safety cleanup and owner-review packet; deterministic host safety tests precede physical execution.",
    ),
    _surface(
        "docs/specifications/cross-cutting/spec-x-003-qualification-contract.md",
        "compatibility_only",
        "markdown_line",
        "SPEC-X-003 adopts the approved qualification specification source (SHA-256 `b25d713ca62a941cdc746709def86a73a5b3a5eac055fe6955c3ce89f51a9b35`). The original draft and pending-approval labels are preserved below as historical metadata. Package approval and source hashes are recorded in [REF-QUAL-002](../../reference/qualification-design-decisions.md). This contract is planning-cycle neutral: platform, capability, artifact, and evidence applicability govern qualification; pha" + "se, mile" + "stone, and sli" + "ce identifiers do not.",
    ),
    _surface("docs/qualification/README.md", "active"),
    *(
        _surface("docs/qualification/README.md", "compatibility_only", "markdown_line", row)
        for row in _legacy_mapping_rows()
    ),
    *(
        _surface("justfile", "active", "just_recipe", recipe)
        for recipe in (
            "check-qualification-record",
            "test-android-qualification",
            "check-qualification-archive",
            "check-qualification-naming",
            "test-library-desktop-qualification",
            "test-live-provider-qualification",
            "test-deterministic-qualification",
            "test-library-android-qualification",
        )
    ),
)

BANNED_PHASE_WORD = "pha" + "se"
BANNED_SLICE_WORD = "sli" + "ce"
BANNED_MILESTONE_WORD = "mile" + "stone"


def _duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON object key")
        result[key] = value
    return result


def _safe_relative_path(value: Any) -> PurePosixPath | None:
    if not isinstance(value, str) or not value or "\\" in value or "\x00" in value:
        return None
    path = PurePosixPath(value)
    if (
        path.is_absolute()
        or path.as_posix() != value
        or any(part in ("", ".", "..") for part in value.split("/"))
        or re.match(r"^[A-Za-z]:", value)
    ):
        return None
    return path


def _contains_symlink(root: Path, candidate: Path) -> bool:
    try:
        relative = candidate.relative_to(root)
    except ValueError:
        return True
    current = root
    if current.is_symlink():
        return True
    for part in relative.parts:
        current = current / part
        if current.is_symlink():
            return True
    try:
        candidate.resolve(strict=False).relative_to(root.resolve(strict=False))
    except (OSError, ValueError):
        return True
    return False


def _archive_entry_path(original_path: str) -> str:
    return (PurePosixPath(ARCHIVE_DIRECTORY) / "original" / PurePosixPath(original_path)).as_posix()


def _archive_file_inventory(original_root: Path, violations: list[str]) -> set[str]:
    actual: set[str] = set()
    if original_root.is_symlink():
        violations.append("unsafe archived path: original archive root is a symlink")
        return actual
    if not original_root.exists():
        return actual
    if not original_root.is_dir():
        violations.append("unsafe archived path: original archive root is not a directory")
        return actual

    def on_walk_error(error: OSError) -> None:
        violations.append("unreadable archive directory")

    for current_name, directories, filenames in os.walk(original_root, topdown=True, followlinks=False, onerror=on_walk_error):
        current = Path(current_name)
        for directory in tuple(directories):
            candidate = current / directory
            if candidate.is_symlink():
                violations.append(f"unsafe archived path: symlink directory {candidate.relative_to(original_root).as_posix()}")
                directories.remove(directory)
        for filename in filenames:
            candidate = current / filename
            relative = candidate.relative_to(original_root).as_posix()
            if candidate.is_symlink():
                violations.append(f"unsafe archived path: symlink file {relative}")
            elif candidate.is_file():
                actual.add(relative)
            else:
                violations.append(f"unsafe archived path: non-regular file {relative}")
    return actual


def _baseline_source_paths(repository: Path) -> tuple[str, ...]:
    """List tracked files under the retired source directory at the fixed commit."""
    result = subprocess.run(
        ["git", "ls-tree", "-r", "--name-only", BASE_COMMIT, "--", PHYSICAL_SOURCE_PREFIX],
        cwd=repository,
        check=True,
        capture_output=True,
        text=True,
    )
    prefix = f"{PHYSICAL_SOURCE_PREFIX}/"
    return tuple(sorted(path for path in result.stdout.splitlines() if path.startswith(prefix)))


def _baseline_blob(repository: Path, path: str) -> bytes:
    """Read one baseline blob without consulting the current working tree."""
    result = subprocess.run(
        ["git", "show", f"{BASE_COMMIT}:{path}"],
        cwd=repository,
        check=True,
        capture_output=True,
    )
    return result.stdout


def _role_for_baseline_path(path: str) -> str:
    """Assign the archive role from the baseline path's file name."""
    return "physical_test" if PurePosixPath(path).name.startswith("test_") else "physical_source"


def _baseline_inventory(repository: Path) -> dict[str, tuple[str, bytes | None, str]]:
    inventory: dict[str, tuple[str, bytes | None, str]] = {}
    paths = _baseline_source_paths(repository)
    if len(paths) != len(set(paths)):
        raise ValueError("baseline source paths are not unique")
    for path in paths:
        safe = _safe_relative_path(path)
        if safe is None or not path.startswith(f"{PHYSICAL_SOURCE_PREFIX}/"):
            raise ValueError("baseline source path is outside the fixed directory")
        content = _baseline_blob(repository, path)
        inventory[path] = (_role_for_baseline_path(path), content, hashlib.sha256(content).hexdigest())

    for role, path in EXPLICIT_BASELINE_ENTRIES:
        safe = _safe_relative_path(path)
        if safe is None or path in inventory:
            raise ValueError("explicit baseline path is unsafe or repeated")
        content = _baseline_blob(repository, path)
        inventory[path] = (role, content, hashlib.sha256(content).hexdigest())
    return inventory


def _pinned_baseline_inventory() -> dict[str, tuple[str, bytes | None, str]]:
    """Return the independently pinned archive paths, roles, and digests."""
    return {
        path: (role, None, digest)
        for role, path, digest in PINNED_BASELINE_ENTRIES
    }


def archive_violations(root: Path | str = ROOT) -> tuple[str, ...]:
    """Validate the archive against fixed Git blobs or the pinned path and digest inventory."""
    repository = Path(root).resolve(strict=False)
    violations: list[str] = []
    manifest_path = repository / MANIFEST_RELATIVE_PATH
    if _contains_symlink(repository, manifest_path):
        return (f"unsafe manifest path: {MANIFEST_RELATIVE_PATH}",)
    if not manifest_path.is_file():
        return (f"missing manifest: {MANIFEST_RELATIVE_PATH}",)
    try:
        manifest = json.loads(
            manifest_path.read_text(encoding="utf-8"),
            object_pairs_hook=_duplicate_keys,
        )
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError):
        return (f"invalid manifest: {MANIFEST_RELATIVE_PATH}",)

    if not isinstance(manifest, dict):
        return ("invalid manifest: top-level JSON value must be an object",)
    expected_manifest_keys = {
        "manifest_version",
        "fetched_base_commit",
        "historical_device_owned_directory",
        "entries",
    }
    for key in sorted(expected_manifest_keys - set(manifest)):
        violations.append(f"manifest is missing required field: {key}")
    for key in sorted(set(manifest) - expected_manifest_keys):
        violations.append(f"manifest has unexpected field: {key}")
    if type(manifest.get("manifest_version")) is not int or manifest.get("manifest_version") != 1:
        violations.append("manifest_version must be integer 1")
    if manifest.get("fetched_base_commit") != BASE_COMMIT:
        violations.append("fetched_base_commit does not match the fixed archive baseline")
    if manifest.get("historical_device_owned_directory") != HISTORICAL_DEVICE_DIRECTORY:
        violations.append("historical_device_owned_directory does not match the archived fact")

    try:
        expected_by_original = _baseline_inventory(repository)
    except (OSError, subprocess.SubprocessError):
        expected_by_original = _pinned_baseline_inventory()
    except ValueError:
        return ("unable to read the fixed Git archive baseline",)

    entries = manifest.get("entries")
    if not isinstance(entries, list):
        violations.append("manifest entries must be an array")
        entries = []

    seen_originals: set[str] = set()
    seen_archived: set[str] = set()
    listed_originals: set[str] = set()
    expected_fields = {"role", "original_path", "archived_path", "sha256"}
    for index, entry in enumerate(entries):
        label = f"manifest entry {index + 1}"
        if not isinstance(entry, dict):
            violations.append(f"{label} must be an object")
            continue
        for key in sorted(expected_fields - set(entry)):
            violations.append(f"{label} is missing field: {key}")
        for key in sorted(set(entry) - expected_fields):
            violations.append(f"{label} has unexpected field: {key}")

        original = entry.get("original_path")
        archived = entry.get("archived_path")
        safe_original = _safe_relative_path(original)
        safe_archived = _safe_relative_path(archived)
        if safe_original is None:
            violations.append(f"unsafe original path in {label}")
        else:
            original_text = safe_original.as_posix()
            listed_originals.add(original_text)
            if original_text in seen_originals:
                violations.append(f"duplicate original path: {original_text}")
            seen_originals.add(original_text)
            original_file = repository.joinpath(*safe_original.parts)
            if _contains_symlink(repository, original_file):
                violations.append(f"unsafe original path: symlink or escape at {original_text}")
            if original_file.exists() or original_file.is_symlink():
                violations.append(f"retired original path is present: {original_text}")

        if safe_archived is None:
            violations.append(f"unsafe archived path in {label}")
        else:
            archived_text = safe_archived.as_posix()
            if archived_text in seen_archived:
                violations.append(f"duplicate archived path: {archived_text}")
            seen_archived.add(archived_text)
            expected_archive = _archive_entry_path(original) if safe_original is not None else None
            if expected_archive is None or archived_text != expected_archive:
                violations.append(f"unsafe archived path: {archived_text}")

        if safe_original is None:
            continue
        original_text = safe_original.as_posix()
        expected = expected_by_original.get(original_text)
        if expected is None:
            violations.append(f"unexpected manifest entry: {original_text}")
            continue
        expected_role, baseline_bytes, expected_digest = expected
        if entry.get("role") != expected_role:
            violations.append(f"unexpected role for manifest entry: {original_text}")
        digest = entry.get("sha256")
        if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest):
            violations.append(f"invalid SHA-256 in {label}")
        elif digest != expected_digest:
            violations.append(f"manifest SHA-256 does not match fixed provenance: {original_text}")

        archive_relative = _safe_relative_path(_archive_entry_path(original_text))
        if archive_relative is None:
            violations.append(f"unsafe archived path for baseline entry: {original_text}")
            continue
        archive_file = repository.joinpath(*archive_relative.parts)
        if _contains_symlink(repository, archive_file):
            violations.append(f"unsafe archived path: {archive_relative.as_posix()}")
        elif archive_file.is_file():
            try:
                archived_bytes = archive_file.read_bytes()
            except OSError:
                violations.append(f"unreadable archived file: {archive_relative.as_posix()}")
            else:
                if (
                    hashlib.sha256(archived_bytes).hexdigest() != expected_digest
                    or (baseline_bytes is not None and archived_bytes != baseline_bytes)
                ):
                    violations.append(f"SHA-256 mismatch: {archive_relative.as_posix()}")

    for original_path in sorted(set(expected_by_original) - listed_originals):
        violations.append(f"missing manifest entry: {original_path}")

    expected_archived = set(expected_by_original)
    original_root = repository / ARCHIVE_DIRECTORY / "original"
    if _contains_symlink(repository, original_root):
        violations.append("unsafe archived path: original archive root contains a symlink")
        actual_archived: set[str] = set()
    else:
        actual_archived = _archive_file_inventory(original_root, violations)
    for relative in sorted(expected_archived - actual_archived):
        violations.append(f"missing archived file: {relative}")
    for relative in sorted(actual_archived - expected_archived):
        violations.append(f"unexpected archived file: {relative}")

    return tuple(sorted(set(violations)))


def _region_identity(region: dict[str, Any]) -> str:
    return json.dumps(region, sort_keys=True, separators=(",", ":"))


def _surface_identity(path: str, region: dict[str, Any]) -> tuple[str, str]:
    return path, _region_identity(region)


def classification_schema_violations(data: Any) -> tuple[str, ...]:
    """Validate path-and-region classifications and the approved compatibility exceptions."""
    violations: list[str] = []
    if not isinstance(data, dict):
        return ("classification file must contain a JSON object",)
    expected_top_level = {"schema_version", "surfaces"}
    for key in sorted(expected_top_level - set(data)):
        violations.append(f"classification file is missing field: {key}")
    for key in sorted(set(data) - expected_top_level):
        violations.append(f"classification file has unexpected field: {key}")
    if type(data.get("schema_version")) is not int or data.get("schema_version") != 1:
        violations.append("classification schema_version must be integer 1")

    surfaces = data.get("surfaces")
    if not isinstance(surfaces, list):
        violations.append("classification surfaces must be an array")
        surfaces = []

    seen: dict[tuple[str, str], str] = {}
    used_categories: set[str] = set()
    expected_fields = {"path", "classification", "region"}
    for index, surface in enumerate(surfaces):
        label = f"classified surface {index + 1}"
        if not isinstance(surface, dict):
            violations.append(f"{label} must be an object")
            continue
        for key in sorted(expected_fields - set(surface)):
            violations.append(f"{label} is missing field: {key}")
        for key in sorted(set(surface) - expected_fields):
            violations.append(f"{label} has unexpected field: {key}")

        path_value = surface.get("path")
        safe_path = _safe_relative_path(path_value)
        if safe_path is None or any(mark in path_value for mark in "*?[]"):
            violations.append(f"unsafe classified path in {label}")
            continue
        path = safe_path.as_posix()
        if path == ARCHIVE_DIRECTORY or path.startswith(f"{ARCHIVE_DIRECTORY}/"):
            violations.append(f"classified path is inside the archive exclusion: {path}")

        category = surface.get("classification")
        if category not in CLASSIFICATION_CATEGORIES:
            violations.append(f"unknown classification for {path}")
            continue
        used_categories.add(category)

        region = surface.get("region")
        if not isinstance(region, dict) or not isinstance(region.get("kind"), str):
            violations.append(f"invalid classified region for {path}")
            continue
        kind = region["kind"]
        region_fields = {
            "file": {"kind"},
            "markdown_section": {"kind", "heading"},
            "just_recipe": {"kind", "name"},
            "yaml_job": {"kind", "name"},
            "markdown_line": {"kind", "text"},
            "text_line": {"kind", "text"},
        }.get(kind)
        if region_fields is None or set(region) != region_fields:
            violations.append(f"invalid classified region for {path}")
            continue
        selector = region.get("heading", region.get("name", region.get("text")))
        if kind != "file" and (not isinstance(selector, str) or not selector):
            violations.append(f"empty classified region selector for {path}")
            continue

        identity = _surface_identity(path, region)
        if identity in seen:
            violations.append(f"duplicate classified surface: {path}")
        else:
            seen[identity] = category

    approved_compatibility_surfaces = {
        _surface_identity(surface["path"], surface["region"])
        for surface in REQUIRED_SURFACES
        if surface["classification"] == "compatibility_only"
    }
    for identity, category in seen.items():
        if category == "compatibility_only" and identity not in approved_compatibility_surfaces:
            violations.append(f"unapproved compatibility-only surface: {identity[0]}")

    expected_readme_exceptions = set(_legacy_mapping_rows())
    actual_readme_exceptions = {
        surface["region"]["text"]
        for surface in surfaces
        if isinstance(surface, dict)
        and surface.get("path") == "docs/qualification/README.md"
        and surface.get("classification") == "compatibility_only"
        and isinstance(surface.get("region"), dict)
        and surface["region"].get("kind") == "markdown_line"
        and isinstance(surface["region"].get("text"), str)
    }
    if (
        any(
            isinstance(surface, dict) and surface.get("path") == "docs/qualification/README.md"
            for surface in surfaces
        )
        and actual_readme_exceptions != expected_readme_exceptions
    ):
        violations.append("qualification README compatibility exceptions must match the legacy crosswalk")

    for category in CLASSIFICATION_CATEGORIES:
        if category not in used_categories:
            violations.append(f"classification category is unused: {category}")

    for required in REQUIRED_SURFACES:
        required_path = required["path"]
        identity = _surface_identity(required_path, required["region"])
        actual_category = seen.get(identity)
        if actual_category is None:
            violations.append(f"missing required surface: {required_path}")
        elif actual_category != required["classification"]:
            violations.append(f"required surface has the wrong classification: {required_path}")

    return tuple(sorted(set(violations)))


def _extract_region(content: str, region: dict[str, Any]) -> str:
    kind = region["kind"]
    if kind == "file":
        return content
    if kind == "markdown_section":
        return extract_markdown_section(content, region["heading"])
    if kind == "just_recipe":
        return extract_just_recipes(content, (region["name"],))
    if kind == "yaml_job":
        return extract_yaml_job(content, region["name"])
    if kind in {"markdown_line", "text_line"}:
        line = region["text"]
        return line if content.splitlines().count(line) == 1 else ""
    return ""


def classification_violations(root: Path | str = ROOT) -> tuple[str, ...]:
    """Validate the classification document and every exact file or region it names."""
    repository = Path(root).resolve(strict=False)
    classification_path = repository / CLASSIFICATION_RELATIVE_PATH
    if _contains_symlink(repository, classification_path):
        return (f"unsafe classification path: {CLASSIFICATION_RELATIVE_PATH}",)
    if not classification_path.is_file():
        return (f"missing classification file: {CLASSIFICATION_RELATIVE_PATH}",)
    try:
        data = json.loads(
            classification_path.read_text(encoding="utf-8"),
            object_pairs_hook=_duplicate_keys,
        )
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError):
        return (f"invalid classification file: {CLASSIFICATION_RELATIVE_PATH}",)

    violations = list(classification_schema_violations(data))
    if violations or not isinstance(data, dict) or not isinstance(data.get("surfaces"), list):
        return tuple(sorted(set(violations)))

    violations.extend(_closed_world_classification_violations(repository, data["surfaces"]))
    if violations:
        return tuple(sorted(set(violations)))

    for surface in data["surfaces"]:
        safe_path = _safe_relative_path(surface["path"])
        candidate = repository.joinpath(*safe_path.parts)
        relative = safe_path.as_posix()
        if _contains_symlink(repository, candidate):
            violations.append(f"unsafe classified path: {relative}")
            continue
        if not candidate.is_file():
            violations.append(f"missing classified file: {relative}")
            continue
        try:
            content = candidate.read_text(encoding="utf-8")
        except (OSError, UnicodeError):
            violations.append(f"unreadable classified file: {relative}")
            continue
        if not _extract_region(content, surface["region"]):
            violations.append(f"missing classified region: {relative}")
    return tuple(sorted(set(violations)))


def contains_prohibited_name(content: str) -> bool:
    """Return whether text includes a numbered stage label or retired planning term."""
    if re.search(rf"{re.escape(BANNED_PHASE_WORD)}[\s_-]*[0-9]+", content, re.IGNORECASE):
        return True
    if re.search(r"(?<![A-Za-z0-9])p[\s_-]*[0-9]+(?![0-9])", content, re.IGNORECASE):
        return True
    terms = (BANNED_SLICE_WORD, BANNED_MILESTONE_WORD)
    return any(re.search(rf"\b{re.escape(term)}s?\b", content, re.IGNORECASE) for term in terms)


def extract_markdown_section(content: str, heading: str) -> str:
    """Return one Markdown heading and its body, stopping before the next peer heading."""
    lines = content.splitlines(keepends=True)
    heading_pattern = re.compile(r"^(#{1,6})\s+(.+?)\s*#*\s*$")
    start_index: int | None = None
    start_level = 0
    for index, line in enumerate(lines):
        match = heading_pattern.match(line.rstrip("\r\n"))
        if match and match.group(2).strip() == heading:
            start_index = index
            start_level = len(match.group(1))
            break
    if start_index is None:
        return ""

    for index in range(start_index + 1, len(lines)):
        match = heading_pattern.match(lines[index].rstrip("\r\n"))
        if match and len(match.group(1)) <= start_level:
            return "".join(lines[start_index:index])
    return "".join(lines[start_index:])


def extract_just_recipes(content: str, recipe_names: tuple[str, ...]) -> str:
    """Return only the named top-level recipes and their indented bodies."""
    selected = set(recipe_names)
    recipe_header = re.compile(r"^([A-Za-z0-9_-]+)(?:\s+[^:]+)?\s*:")
    active = False
    extracted: list[str] = []
    for line in content.splitlines(keepends=True):
        if line.strip() and not line[0].isspace():
            match = recipe_header.match(line)
            active = bool(match and match.group(1) in selected)
            if active:
                extracted.append(line)
        elif active:
            extracted.append(line)
    return "".join(extracted)


def extract_yaml_job(content: str, job_name: str) -> str:
    """Return the exact top-level GitHub Actions job and its nested configuration."""
    lines = content.splitlines(keepends=True)
    job_header = re.compile(r"^  ([A-Za-z0-9_-]+):\s*(?:#.*)?(?:\r?\n)?$")
    start_index: int | None = None
    for index, line in enumerate(lines):
        match = job_header.match(line)
        if match and match.group(1) == job_name:
            start_index = index
            break
    if start_index is None:
        return ""
    for index in range(start_index + 1, len(lines)):
        if job_header.match(lines[index]):
            return "".join(lines[start_index:index])
    return "".join(lines[start_index:])


def _read_classification(root: Path) -> dict[str, Any]:
    path = root / CLASSIFICATION_RELATIVE_PATH
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=_duplicate_keys)


def active_naming_violations(root: Path | str = ROOT) -> tuple[str, ...]:
    """Scan only active classified file regions for prohibited names."""
    repository = Path(root).resolve(strict=False)
    violations = list(classification_violations(repository))
    if violations:
        return tuple(sorted(set(violations)))

    data = _read_classification(repository)
    surfaces = data["surfaces"]
    compatibility_lines: dict[str, set[str]] = {}
    for surface in surfaces:
        region = surface["region"]
        if surface["classification"] == "compatibility_only" and region["kind"] in {"markdown_line", "text_line"}:
            compatibility_lines.setdefault(surface["path"], set()).add(region["text"])

    for surface in surfaces:
        if surface["classification"] != "active":
            continue
        relative = surface["path"]
        path = repository.joinpath(*PurePosixPath(relative).parts)
        try:
            content = path.read_text(encoding="utf-8")
        except (OSError, UnicodeError):
            violations.append(f"unreadable active qualification file: {relative}")
            continue
        region = _extract_region(content, surface["region"])
        exclusions = compatibility_lines.get(relative, set())
        if exclusions:
            region = "\n".join(line for line in region.splitlines() if line not in exclusions)
        if contains_prohibited_name(f"{relative}\n{region}"):
            violations.append(f"prohibited active qualification name in {relative}")
    return tuple(sorted(set(violations)))


def _sanitized_diagnostic(message: str, repository: Path) -> str:
    result = " ".join(message.splitlines())
    for private_path in (str(repository), str(Path.home()), str(ROOT)):
        if private_path:
            result = result.replace(private_path, "<repo>")
    return result


def main(argv: list[str] | None = None) -> int:
    """Run one focused repository qualification check with stable output."""
    arguments = list(sys.argv[1:] if argv is None else argv)
    if len(arguments) != 1 or arguments[0] not in {"archive", "naming"}:
        print("usage: python3 -m scripts.android_qualification.repository_checks {archive|naming}", file=sys.stderr)
        return 2
    mode = arguments[0]
    check = archive_violations if mode == "archive" else active_naming_violations
    try:
        violations = check(ROOT)
    except Exception:
        print(f"Qualification {mode} check failed: checker error", file=sys.stderr)
        return 1
    if violations:
        print(f"Qualification {mode} check failed", file=sys.stderr)
        for violation in violations:
            print(_sanitized_diagnostic(violation, ROOT), file=sys.stderr)
        return 1
    print(f"Qualification {mode} check passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
