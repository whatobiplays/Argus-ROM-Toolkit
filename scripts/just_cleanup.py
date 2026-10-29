#!/usr/bin/env python3
"""Preview and reclaim repository-owned generated build output.

Cleanup is an offline maintenance command for an idle checkout. Preview and
apply use the same safety admission and approved-directory inventory. Once a
root is admitted, the helper removes that entire tree independently of file
names. It never follows a candidate symlink, deletes tracked content, enters
nested repositories, crosses a filesystem-device boundary, or removes global
caches.

Bytecode writes are disabled before the local policy import so preview remains
read-only when invoked directly.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import stat
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence

# Preserve the read-only preview contract before importing the local policy.
sys.dont_write_bytecode = True

try:
    from just_cleanup_policy import (
        GIT_CONTEXT_ENVIRONMENT,
        PROTECTED_PATHS,
    )
except ModuleNotFoundError:
    from scripts.just_cleanup_policy import (
        GIT_CONTEXT_ENVIRONMENT,
        PROTECTED_PATHS,
    )


class CleanupError(RuntimeError):
    """Base class for a refusal that must be shown to the operator."""


class UnsafeWorktreeError(CleanupError):
    """The invoked helper cannot be bound to one Git worktree."""


class UnsafeCandidateError(CleanupError):
    """A candidate does not satisfy the directory safety policy."""


@dataclass(frozen=True)
class CandidateSpec:
    """One repository-owned directory approved for complete removal."""

    category: str
    relative_path: str
    default_clean: bool
    regeneration_note: str


@dataclass(frozen=True)
class CountedEntry:
    """One logical file or symbolic-link size observed in a candidate tree."""

    relative_path: str
    size: int
    identity: tuple[int, int]


@dataclass(frozen=True)
class CandidateSnapshot:
    """Read-only size and path inventory for one approved candidate."""

    estimated_bytes: int
    entries: int
    counted_entries: tuple[CountedEntry, ...]


@dataclass
class CandidateObservation:
    """Read-only information captured for one candidate before action."""

    spec: CandidateSpec
    snapshot: CandidateSnapshot | None = None
    action: str = "skipped"
    reason: str = "missing"
    error: str | None = None

    @property
    def estimated_bytes(self) -> int:
        return self.snapshot.estimated_bytes if self.snapshot is not None else 0

    @property
    def entries(self) -> int:
        return self.snapshot.entries if self.snapshot is not None else 0


@dataclass(frozen=True)
class Worktree:
    """A resolved physical Git worktree."""

    root: Path


@dataclass
class RemovalOutcome:
    """Truthful result for one candidate's attempted removal."""

    status: str
    verified_reclaimed_bytes: int = 0
    errors: list[str] | None = None

    def __post_init__(self) -> None:
        if self.errors is None:
            self.errors = []


DEFAULT_CANDIDATES: tuple[CandidateSpec, ...] = (
    CandidateSpec(
        category="rust",
        relative_path="rust/target",
        default_clean=True,
        regeneration_note="Cargo rebuilds Rust dependencies and application targets.",
    ),
    CandidateSpec(
        category="android",
        relative_path="flutter/build/app/intermediates",
        default_clean=True,
        regeneration_note="Gradle recreates Android compiler intermediates.",
    ),
    CandidateSpec(
        category="android",
        relative_path="flutter/build/app/generated",
        default_clean=True,
        regeneration_note=(
            "Gradle regenerates Android source and resource intermediates."
        ),
    ),
    CandidateSpec(
        category="android",
        relative_path="flutter/build/app/tmp",
        default_clean=True,
        regeneration_note="Gradle recreates temporary build files.",
    ),
    CandidateSpec(
        category="android",
        relative_path="flutter/build/app/.cxx",
        default_clean=True,
        regeneration_note="The Android native build recreates C++ intermediates.",
    ),
    CandidateSpec(
        category="native",
        relative_path="flutter/build/macos/Build/Intermediates.noindex",
        default_clean=True,
        regeneration_note="Xcode recreates macOS compiler intermediates.",
    ),
    CandidateSpec(
        category="flutter",
        relative_path="flutter/.dart_tool/flutter_build",
        default_clean=False,
        regeneration_note="Deep cleanup removes Flutter compiler intermediates only.",
    ),
    CandidateSpec(
        category="gradle",
        relative_path="flutter/android/.gradle",
        default_clean=False,
        regeneration_note="Deep cleanup removes the project-local Gradle cache.",
    ),
    CandidateSpec(
        category="kotlin",
        relative_path="flutter/android/.kotlin",
        default_clean=False,
        regeneration_note=(
            "Deep cleanup removes Kotlin compiler state for this checkout."
        ),
    ),
)


def _repository_root() -> Path:
    """Return the physical worktree containing this helper."""

    return Path(__file__).resolve().parents[1]


def _sanitized_git_environment() -> dict[str, str]:
    """Build a Git environment that cannot be redirected by the caller."""

    unexpected = [name for name in GIT_CONTEXT_ENVIRONMENT if os.environ.get(name)]
    if unexpected:
        joined = ", ".join(unexpected)
        raise UnsafeWorktreeError(
            f"Unexpected Git context environment is set: {joined}. "
            "Run cleanup without an explicit Git repository, work-tree, index, "
            "object store, or discovery override."
        )
    environment = os.environ.copy()
    for name in GIT_CONTEXT_ENVIRONMENT:
        environment.pop(name, None)
    return environment


def _run_git(
    root: Path,
    arguments: Sequence[str],
    *,
    check: bool = True,
) -> subprocess.CompletedProcess[bytes]:
    """Run a local Git query without allowing ambient repository context."""

    return subprocess.run(
        ["git", "-C", os.fspath(root), *arguments],
        env=_sanitized_git_environment(),
        capture_output=True,
        check=check,
    )


def discover_worktree(root: Path | None = None) -> Worktree:
    """Resolve the helper root and verify that Git names the same worktree."""

    observed_root = (root or _repository_root()).expanduser()
    try:
        physical_root = observed_root.resolve(strict=True)
    except OSError as error:
        raise UnsafeWorktreeError(f"Cannot inspect cleanup root: {error}") from error
    if not physical_root.is_dir():
        raise UnsafeWorktreeError("The cleanup root must be a directory.")
    try:
        result = _run_git(physical_root, ("rev-parse", "--show-toplevel"))
        inside = _run_git(
            physical_root,
            ("rev-parse", "--is-inside-work-tree"),
        )
    except (OSError, subprocess.CalledProcessError) as error:
        raise UnsafeWorktreeError(
            f"Cannot bind cleanup to a Git worktree: {error}"
        ) from error
    reported_text = os.fsdecode(result.stdout).strip()
    if not reported_text:
        raise UnsafeWorktreeError("Git did not report a worktree top level.")
    try:
        reported_root = Path(reported_text).expanduser().resolve(strict=True)
    except OSError as error:
        raise UnsafeWorktreeError(
            f"Cannot resolve the Git worktree top level: {error}"
        ) from error
    if physical_root != reported_root:
        raise UnsafeWorktreeError(
            "The cleanup helper is not bound to the active Git top level. "
            f"Helper root: {physical_root}; Git top level: {reported_root}."
        )
    if os.fsdecode(inside.stdout).strip() != "true":
        raise UnsafeWorktreeError("Cleanup requires a non-bare Git worktree.")
    return Worktree(root=physical_root)


def _safe_relative_path(value: str) -> tuple[str, ...]:
    """Split an approved repository-relative path without traversal syntax."""

    path = Path(value)
    if path.is_absolute() or not path.parts:
        raise UnsafeCandidateError(f"Candidate path is not relative: {value}")
    if any(part in ("", ".", "..") for part in path.parts):
        raise UnsafeCandidateError(f"Candidate path contains traversal: {value}")
    return path.parts


def _first_symlink_parent(
    worktree: Worktree,
    parts: Sequence[str],
) -> str | None:
    """Return the first symlinked parent component of an approved candidate."""

    current = worktree.root
    for part in parts[:-1]:
        current /= part
        try:
            metadata = current.lstat()
        except FileNotFoundError:
            return None
        except OSError as error:
            raise UnsafeCandidateError(
                "Cannot inspect candidate parent "
                f"{current.relative_to(worktree.root)}: "
                f"{error}"
            ) from error
        if stat.S_ISLNK(metadata.st_mode):
            return current.relative_to(worktree.root).as_posix()
    return None


def _lexists(path: Path) -> bool:
    """Return whether a path or symbolic link exists without following it."""

    return path.exists() or path.is_symlink()


def _has_git_marker(path: Path) -> bool:
    """Return whether a directory contains ordinary Git metadata."""

    return _lexists(path / ".git")


def _is_bare_git_repository(directory: Path) -> bool:
    """Return whether Git positively identifies a directory as bare.

    A bare repository must have a HEAD entry, so ordinary output directories
    can be skipped without starting a Git process. Git remains the authority
    for directories that contain that marker.

    Git performs repository discovery from the supplied directory, so the
    result also covers bare repositories whose configuration, object store, or
    refs use nonstandard locations. Filenames alone never make a directory a
    repository.
    """

    try:
        (directory / "HEAD").lstat()
    except FileNotFoundError:
        return False
    except OSError:
        # Preserve Git's existing check when the marker cannot be inspected.
        pass

    result = _run_git(directory, ("rev-parse", "--is-bare-repository"))
    return result.stdout.strip() == b"true"


def _first_intermediate_git_boundary(
    worktree: Worktree,
    parts: Sequence[str],
) -> str | None:
    """Return an intermediate candidate parent that belongs to another worktree."""

    current = worktree.root
    for part in parts[:-1]:
        current /= part
        if _has_git_marker(current):
            return current.relative_to(worktree.root).as_posix()
    return None


def _first_intermediate_bare_git_boundary(
    worktree: Worktree,
    parts: Sequence[str],
) -> str | None:
    """Return the nearest bare Git repository above an approved candidate."""

    current = worktree.root
    for part in parts[:-1]:
        current /= part
        try:
            metadata = current.lstat()
        except FileNotFoundError:
            return None
        except OSError as error:
            raise UnsafeCandidateError(
                f"Cannot inspect candidate parent "
                f"{current.relative_to(worktree.root)}: {error}"
            ) from error
        if stat.S_ISDIR(metadata.st_mode) and _is_bare_git_repository(current):
            return current.relative_to(worktree.root).as_posix()
    return None


def _directory_has_only_untracked_content(
    worktree: Worktree,
    relative_path: str,
) -> bool:
    """Return whether Git reports no index entries beneath a candidate."""

    listed = _run_git(
        worktree.root,
        ("ls-files", "-z", "--", relative_path),
    )
    return not listed.stdout


def _is_ignored_generated_path(worktree: Worktree, relative_path: str) -> bool:
    """Require the repository ignore policy to mark a candidate generated."""

    result = _run_git(
        worktree.root,
        ("check-ignore", "-q", "--", relative_path),
        check=False,
    )
    return result.returncode == 0


def _inspect_directory(
    directory: Path,
    *,
    relative_path: str,
    expected_device: int,
    counted_identities: set[tuple[int, int]],
    counted_entries: list[CountedEntry],
) -> tuple[int, int, str | None]:
    """Validate and measure an owned tree without following symbolic links.

    Eligibility comes from the candidate root. Once a tree reaches this
    function, every regular file, directory, and symbolic link is disposable;
    names and extensions do not participate in that decision.
    """

    if _is_bare_git_repository(directory):
        return (
            0,
            0,
            f"A bare Git repository is present at {relative_path}; "
            "the candidate content is retained.",
        )

    total_bytes = 0
    total_entries = 0
    try:
        children = sorted(directory.iterdir(), key=lambda item: item.name)
    except OSError as error:
        return 0, 0, f"Cannot inspect {relative_path}: {error}"

    for child in children:
        entry_path = f"{relative_path}/{child.name}"
        if child.name.casefold() == ".git":
            return (
                0,
                0,
                f"Nested Git metadata (.git) is present beneath {relative_path}; "
                "the candidate content is retained.",
            )
        try:
            metadata = child.lstat()
        except OSError as error:
            return 0, 0, f"Cannot inspect {entry_path}: {error}"
        if int(metadata.st_dev) != expected_device:
            return (
                0,
                0,
                f"Filesystem boundary crossed beneath {relative_path} at {entry_path}.",
            )
        total_entries += 1
        identity = (int(metadata.st_dev), int(metadata.st_ino))
        if stat.S_ISDIR(metadata.st_mode):
            child_bytes, child_entries, violation = _inspect_directory(
                child,
                relative_path=entry_path,
                expected_device=expected_device,
                counted_identities=counted_identities,
                counted_entries=counted_entries,
            )
            if violation:
                return 0, 0, violation
            total_bytes += child_bytes
            total_entries += child_entries
            continue
        if not (
            stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode)
        ):
            return 0, 0, f"Unexpected filesystem object at {entry_path}."

        if identity not in counted_identities:
            counted_identities.add(identity)
            total_bytes += int(metadata.st_size)
            counted_entries.append(
                CountedEntry(
                    relative_path=entry_path,
                    size=int(metadata.st_size),
                    identity=identity,
                )
            )
    return total_bytes, total_entries, None


def _observe_candidate(
    worktree: Worktree,
    spec: CandidateSpec,
    *,
    seen_file_identities: set[tuple[int, int]] | None = None,
) -> CandidateObservation:
    """Admit and measure one approved directory without modifying it."""

    observation = CandidateObservation(spec=spec)
    parts = _safe_relative_path(spec.relative_path)
    try:
        symlink_parent = _first_symlink_parent(worktree, parts)
        if symlink_parent:
            observation.action = "failed"
            observation.reason = (
                f"Candidate parent {symlink_parent} is a symbolic link and is "
                "refused without following links."
            )
            observation.error = observation.reason
            return observation

        bare_git_parent = _first_intermediate_bare_git_boundary(worktree, parts)
        if bare_git_parent:
            observation.action = "failed"
            observation.reason = (
                f"Candidate parent {bare_git_parent} is a bare Git repository; "
                "cleanup is confined to the active worktree root."
            )
            observation.error = observation.reason
            return observation

        git_boundary = _first_intermediate_git_boundary(worktree, parts)
        if git_boundary:
            observation.action = "failed"
            observation.reason = (
                f"Candidate parent {git_boundary} contains Git metadata (.git); "
                "cleanup is confined to the active worktree root."
            )
            observation.error = observation.reason
            return observation

        candidate = worktree.root / spec.relative_path
        try:
            candidate_metadata = candidate.lstat()
        except FileNotFoundError:
            return observation
        except OSError as error:
            observation.action = "failed"
            observation.reason = f"Cannot inspect {spec.relative_path}: {error}"
            observation.error = observation.reason
            return observation

        if stat.S_ISLNK(candidate_metadata.st_mode):
            observation.reason = (
                "Candidate root is a symbolic link and is skipped without "
                "following it."
            )
            return observation
        if not stat.S_ISDIR(candidate_metadata.st_mode):
            observation.action = "failed"
            observation.reason = "Candidate path is not a directory."
            observation.error = observation.reason
            return observation

        worktree_device = int(worktree.root.stat().st_dev)
        if int(candidate_metadata.st_dev) != worktree_device:
            observation.reason = "Candidate is on a different filesystem."
            return observation
        if not _directory_has_only_untracked_content(
            worktree,
            spec.relative_path,
        ):
            observation.reason = (
                "Git tracks content beneath the candidate; the candidate is retained."
            )
            return observation
        if not _is_ignored_generated_path(worktree, spec.relative_path):
            observation.action = "failed"
            observation.reason = (
                "The repository ignore policy does not mark the candidate generated."
            )
            observation.error = observation.reason
            return observation

        counted_identities = set(seen_file_identities or ())
        counted_entries: list[CountedEntry] = []
        estimated_bytes, entries, violation = _inspect_directory(
            candidate,
            relative_path=spec.relative_path,
            expected_device=int(candidate_metadata.st_dev),
            counted_identities=counted_identities,
            counted_entries=counted_entries,
        )
        if violation:
            observation.action = "failed"
            observation.reason = violation
            observation.error = violation
            return observation
        if seen_file_identities is not None:
            seen_file_identities.update(counted_identities)
    except (OSError, UnsafeCandidateError, subprocess.CalledProcessError) as error:
        observation.action = "failed"
        observation.reason = str(error)
        observation.error = str(error)
        return observation

    observation.snapshot = CandidateSnapshot(
        estimated_bytes=estimated_bytes,
        entries=entries,
        counted_entries=tuple(counted_entries),
    )
    observation.action = "selected"
    observation.reason = spec.regeneration_note
    return observation


def _find_python_cache_candidates(
    worktree: Worktree,
) -> tuple[list[CandidateSpec], list[tuple[str, str]]]:
    """Find bytecode caches and report ordinary directory-walk failures."""

    scripts = worktree.root / "scripts"
    if not scripts.is_dir() or scripts.is_symlink():
        return [], []
    if _has_git_marker(scripts):
        return [], []

    candidates: list[CandidateSpec] = []
    discovery_errors: list[tuple[str, str]] = []

    def record_walk_error(error: OSError) -> None:
        failed_path = Path(error.filename) if error.filename else scripts
        try:
            relative_path = failed_path.relative_to(worktree.root).as_posix()
        except ValueError:
            relative_path = "scripts"
        discovery_errors.append(
            (
                relative_path,
                f"Cannot inspect Python bytecode cache tree {relative_path}: {error}",
            )
        )

    for current_text, directory_names, _file_names in os.walk(
        scripts,
        followlinks=False,
        onerror=record_walk_error,
    ):
        current = Path(current_text)
        directory_names.sort()
        retained_directories: list[str] = []
        for directory_name in directory_names:
            child = current / directory_name
            if directory_name == "__pycache__":
                if child.is_dir() and not child.is_symlink():
                    candidates.append(
                        CandidateSpec(
                            category="python",
                            relative_path=child.relative_to(worktree.root).as_posix(),
                            default_clean=True,
                            regeneration_note=(
                                "Python recreates script bytecode caches when needed."
                            ),
                        )
                    )
                continue
            if child.is_symlink():
                continue
            try:
                if _has_git_marker(child):
                    continue
            except OSError as error:
                record_walk_error(error)
                continue
            retained_directories.append(directory_name)
        directory_names[:] = retained_directories
    return (
        sorted(candidates, key=lambda item: item.relative_path),
        sorted(discovery_errors),
    )


def _rust_candidate_is_redirected(worktree: Worktree) -> str | None:
    """Describe a Cargo target redirect that makes rust/target ambiguous."""

    configured = os.environ.get("CARGO_TARGET_DIR")
    if not configured:
        return None
    configured_path = Path(configured).expanduser()
    if not configured_path.is_absolute():
        configured_path = worktree.root / configured_path
    if configured_path.resolve(strict=False) != worktree.root / "rust/target":
        return "CARGO_TARGET_DIR redirects Cargo away from rust/target."
    return None


def _collect_observations(
    worktree: Worktree,
    *,
    deep: bool,
) -> list[CandidateObservation]:
    """Select and measure candidates with the shared preview/apply policy."""

    python_candidates, python_discovery_errors = _find_python_cache_candidates(
        worktree
    )
    specifications = list(DEFAULT_CANDIDATES) + python_candidates
    observations: list[CandidateObservation] = []
    seen_file_identities: set[tuple[int, int]] = set()
    rust_redirect_reason = _rust_candidate_is_redirected(worktree)
    for relative_path, message in python_discovery_errors:
        observations.append(
            CandidateObservation(
                spec=CandidateSpec(
                    category="python",
                    relative_path=relative_path,
                    default_clean=True,
                    regeneration_note=message,
                ),
                action="failed",
                reason=message,
                error=message,
            )
        )
    for specification in specifications:
        if not specification.default_clean and not deep:
            continue
        if specification.relative_path == "rust/target" and rust_redirect_reason:
            observations.append(
                CandidateObservation(
                    spec=specification,
                    action="skipped",
                    reason=rust_redirect_reason,
                )
            )
            continue
        observations.append(
            _observe_candidate(
                worktree,
                specification,
                seen_file_identities=seen_file_identities,
            )
        )
    return observations


def _removed_entries(
    worktree: Worktree,
    snapshot: CandidateSnapshot,
    seen_file_identities: set[tuple[int, int]],
) -> tuple[int, int]:
    """Count logical bytes and entries that are no longer present."""

    reclaimed_bytes = 0
    removed_entries = 0
    for entry in snapshot.counted_entries:
        if entry.identity in seen_file_identities:
            continue
        if _lexists(worktree.root / entry.relative_path):
            continue
        seen_file_identities.add(entry.identity)
        reclaimed_bytes += entry.size
        removed_entries += 1
    return reclaimed_bytes, removed_entries


def remove_candidate(
    worktree: Worktree,
    observation: CandidateObservation,
    *,
    seen_file_identities: set[tuple[int, int]] | None = None,
) -> RemovalOutcome:
    """Remove one previously validated candidate with ordinary filesystem errors."""

    relative_path = observation.spec.relative_path
    candidate = worktree.root / relative_path

    if not _lexists(candidate):
        return RemovalOutcome(status="removed")
    if candidate.is_symlink():
        return RemovalOutcome(
            status="failed",
            errors=[
                f"Cannot remove candidate {relative_path}: it became a symbolic link."
            ],
        )

    errors: list[str] = []

    def record_error(
        function: object,
        path: str,
        exc_info: tuple[object, object, object],
    ) -> None:
        operation = getattr(function, "__name__", "delete")
        exception = exc_info[1]
        errors.append(f"Cannot {operation} {path}: {exception}")

    try:
        shutil.rmtree(candidate, onerror=record_error)
    except OSError as error:
        errors.append(f"Cannot remove {relative_path}: {error}")

    snapshot = observation.snapshot or CandidateSnapshot(0, 0, ())
    seen = seen_file_identities if seen_file_identities is not None else set()
    reclaimed_bytes, removed_entries = _removed_entries(worktree, snapshot, seen)

    if not errors and not _lexists(candidate):
        return RemovalOutcome(
            status="removed",
            verified_reclaimed_bytes=reclaimed_bytes,
        )

    if not errors:
        errors.append(f"Candidate directory remains after removal: {relative_path}")
    status = "partial" if removed_entries or reclaimed_bytes else "failed"
    return RemovalOutcome(
        status=status,
        verified_reclaimed_bytes=reclaimed_bytes,
        errors=errors,
    )


def _diagnostic_item(path: str, *, action: str, reason: str) -> dict[str, object]:
    return {
        "path": path,
        "action": action,
        "reason": reason,
        "estimated_bytes": 0,
    }


def build_report(
    worktree: Worktree,
    *,
    deep: bool,
    mode: str,
    observations: Sequence[CandidateObservation] | None = None,
) -> dict[str, object]:
    """Build a report using the same candidate policy for preview and apply."""

    selected_observations = (
        list(observations)
        if observations is not None
        else _collect_observations(worktree, deep=deep)
    )

    categories: dict[str, list[dict[str, object]]] = {}
    for observation in selected_observations:
        item: dict[str, object] = {
            "path": observation.spec.relative_path,
            "action": observation.action,
            "reason": observation.reason,
            "estimated_bytes": observation.estimated_bytes,
        }
        if observation.error:
            item["error"] = observation.error
            item["errors"] = [observation.error]
        categories.setdefault(observation.spec.category, []).append(item)

    protected_category: list[dict[str, object]] = []
    for relative_path, reason in PROTECTED_PATHS:
        path = worktree.root / relative_path
        if _lexists(path):
            protected_category.append(
                _diagnostic_item(relative_path, action="skipped", reason=reason)
            )
    if protected_category:
        categories["protected"] = protected_category

    estimated_bytes = sum(item.estimated_bytes for item in selected_observations)
    failed = any(item.action == "failed" for item in selected_observations)
    warnings = [
        "Estimated bytes are logical file sizes from a read-only snapshot; "
        "they are not filesystem allocation measurements.",
        "Cleanup assumes an idle checkout. It does not detect or coordinate "
        "with builds, tests, generators, IDEs, or other cleanup commands.",
    ]
    if deep:
        warnings.append(
            "Deep cleanup removes project-local tool caches and will require "
            "additional regeneration time; configured SDKs and global caches remain."
        )
    return {
        "schema_version": 1,
        "mode": mode,
        "deep": deep,
        "worktree": os.fspath(worktree.root),
        "snapshot_reliable": not failed,
        "estimated_bytes": estimated_bytes,
        "categories": [
            {"name": name, "paths": categories[name]} for name in sorted(categories)
        ],
        "warnings": warnings,
    }


def _bytes_semantics() -> dict[str, str]:
    """Describe what the byte counts in cleanup reports represent."""

    return {
        "estimated_bytes": (
            "Logical file and symbolic-link sizes measured during the read-only "
            "snapshot; directory metadata and allocation are excluded. Regular "
            "files are counted once per device and inode."
        ),
        "verified_reclaimed_bytes": (
            "Logical file and symbolic-link sizes for entries no longer present "
            "after deletion. Regular files are counted once per device and inode. "
            "This is not a filesystem allocation measurement."
        ),
    }


def _emit_report(report: dict[str, object]) -> None:
    print(json.dumps(report, indent=2, sort_keys=True))


def _preview(deep: bool) -> int:
    """Measure eligible generated outputs without changing the checkout."""

    worktree = discover_worktree()
    mode = "preview-deep" if deep else "preview"
    report = build_report(worktree, deep=deep, mode=mode)
    _emit_report(report)
    return 0 if report["snapshot_reliable"] else 2


def _apply(deep: bool) -> int:
    """Remove eligible generated outputs and report the actual result."""

    worktree = discover_worktree()
    mode = "apply-deep" if deep else "apply"
    observations = _collect_observations(worktree, deep=deep)
    report = build_report(
        worktree,
        deep=deep,
        mode=mode,
        observations=observations,
    )
    category_by_path = {
        item["path"]: item
        for category in report["categories"]
        for item in category["paths"]
    }
    all_errors: list[str] = []
    verified_reclaimed_bytes = 0
    removed_any = False
    seen_removed_file_identities: set[tuple[int, int]] = set()
    for observation in observations:
        item = category_by_path[observation.spec.relative_path]
        if observation.action != "selected":
            item["outcome"] = observation.action
            if observation.action == "failed":
                all_errors.append(
                    f"{observation.spec.relative_path}: "
                    f"{observation.error or observation.reason}"
                )
            continue

        revalidated = _observe_candidate(worktree, observation.spec)
        if revalidated.action != "selected":
            item["outcome"] = revalidated.action
            if revalidated.action == "failed":
                message = (
                    f"{observation.spec.relative_path}: "
                    f"{revalidated.error or revalidated.reason}"
                )
                item["error"] = message
                item["errors"] = [message]
                all_errors.append(message)
                report["snapshot_reliable"] = False
            else:
                item["reason"] = revalidated.reason
            continue

        removal = remove_candidate(
            worktree,
            revalidated,
            seen_file_identities=seen_removed_file_identities,
        )
        item["outcome"] = removal.status
        item["verified_reclaimed_bytes"] = removal.verified_reclaimed_bytes
        verified_reclaimed_bytes += removal.verified_reclaimed_bytes
        if removal.status == "removed" or removal.verified_reclaimed_bytes:
            removed_any = True
        if removal.errors:
            item["errors"] = list(removal.errors)
            all_errors.extend(removal.errors)
    report["errors"] = list(dict.fromkeys(all_errors))
    report["verified_reclaimed_bytes"] = verified_reclaimed_bytes
    report["bytes_semantics"] = _bytes_semantics()
    if all_errors:
        report["status"] = "partial" if removed_any else "failed"
    else:
        report["status"] = "complete"

    _emit_report(report)
    return 0 if report["status"] == "complete" else 1


def _parser() -> argparse.ArgumentParser:
    """Return the offline cleanup command-line parser."""

    parser = argparse.ArgumentParser(
        description="Preview or reclaim repository-owned generated outputs."
    )
    subcommands = parser.add_subparsers(dest="mode", required=True)
    for mode in ("preview", "apply", "preview-deep", "apply-deep"):
        subcommands.add_parser(mode)
    return parser


def main(arguments: Iterable[str] | None = None) -> int:
    """Run one cleanup command and emit its JSON report."""

    parsed = _parser().parse_args(
        list(arguments) if arguments is not None else None
    )
    try:
        if parsed.mode in {"preview", "preview-deep"}:
            return _preview(parsed.mode == "preview-deep")
        if parsed.mode in {"apply", "apply-deep"}:
            return _apply(parsed.mode == "apply-deep")
    except CleanupError as error:
        print(f"cleanup: {error}", file=sys.stderr)
        return 2
    raise AssertionError(f"Unsupported cleanup mode: {parsed.mode}")


if __name__ == "__main__":
    raise SystemExit(main())
