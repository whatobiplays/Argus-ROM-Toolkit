"""Filesystem validation, streaming, and published-byte verification."""

from __future__ import annotations

import hashlib
import os
import re
import shutil
import stat
from pathlib import Path, PurePosixPath
from typing import Mapping, Sequence

from scripts.android_qualification.fixture_staging_contract import (
    FixtureFile,
    FixtureSpec,
    _StagingFailure,
)


COPY_CHUNK_BYTES = 1024 * 1024

MAX_DESCRIPTOR_BYTES = 8 * 1024 * 1024

def _source_tree(root_value: object, fixture: FixtureSpec) -> Path:
    try:
        root = Path(root_value).expanduser()
        root_status = root.lstat()
    except (OSError, TypeError, ValueError):
        raise _StagingFailure("SOURCE_UNAVAILABLE") from None
    if stat.S_ISLNK(root_status.st_mode) or not stat.S_ISDIR(root_status.st_mode):
        raise _StagingFailure("SOURCE_UNSAFE")
    expected = {item.path for item in fixture.files}
    found: set[str] = set()
    def fail_on_walk_error(_error: OSError) -> None:
        raise _StagingFailure("SOURCE_UNAVAILABLE")

    try:
        for directory, names, files in os.walk(
            root, followlinks=False, onerror=fail_on_walk_error,
        ):
            current = Path(directory)
            for name in names:
                child = current / name
                if child.is_symlink() or not child.is_dir():
                    raise _StagingFailure("SOURCE_UNSAFE")
            for name in files:
                child = current / name
                info = child.lstat()
                if not stat.S_ISREG(info.st_mode):
                    raise _StagingFailure("SOURCE_UNSAFE")
                found.add(child.relative_to(root).as_posix())
    except _StagingFailure:
        raise
    except OSError:
        raise _StagingFailure("SOURCE_UNAVAILABLE") from None
    if found != expected:
        raise _StagingFailure("SOURCE_LAYOUT_MISMATCH")
    try:
        resolved = root.resolve(strict=True)
    except (OSError, RuntimeError):
        raise _StagingFailure("SOURCE_UNAVAILABLE") from None
    for item in fixture.files:
        source = root / item.path
        current = root
        for component in item.path.split("/"):
            current = current / component
            try:
                status = current.lstat()
            except OSError:
                raise _StagingFailure("SOURCE_UNAVAILABLE") from None
            if stat.S_ISLNK(status.st_mode):
                raise _StagingFailure("SOURCE_UNSAFE")
        if not stat.S_ISREG(source.lstat().st_mode):
            raise _StagingFailure("SOURCE_UNSAFE")
    return resolved

def _nearest_existing(path: Path) -> Path:
    _validate_destination_ancestors(path)
    current = path
    while not current.exists():
        if current == current.parent:
            raise _StagingFailure("DESTINATION_UNAVAILABLE")
        current = current.parent
    if current.is_symlink() or not current.is_dir():
        raise _StagingFailure("DESTINATION_UNSAFE")
    return current


def _validate_destination_ancestors(path: Path) -> None:
    try:
        absolute = Path(os.path.abspath(path.expanduser()))
        current = Path(absolute.anchor)
        for component in absolute.parts[1:]:
            current = current / component
            try:
                info = current.lstat()
            except FileNotFoundError:
                break
            mode = stat.S_IMODE(info.st_mode)
            if stat.S_ISLNK(info.st_mode):
                if info.st_uid != 0:
                    raise _StagingFailure("DESTINATION_UNSAFE")
                current = current.resolve(strict=True)
                info = current.stat()
                mode = stat.S_IMODE(info.st_mode)
            if not stat.S_ISDIR(info.st_mode):
                raise _StagingFailure("DESTINATION_UNSAFE")
            if mode & 0o022:
                sticky_public = mode & stat.S_ISVTX and info.st_uid in {0, os.getuid()}
                if not sticky_public:
                    raise _StagingFailure("DESTINATION_UNSAFE")
    except _StagingFailure:
        raise
    except (OSError, RuntimeError, TypeError, ValueError):
        raise _StagingFailure("DESTINATION_UNSAFE") from None

def _available_bytes(path: Path) -> int:
    try:
        return shutil.disk_usage(_nearest_existing(path)).free
    except _StagingFailure:
        raise
    except OSError:
        raise _StagingFailure("CAPACITY_UNAVAILABLE") from None

def _open_readonly(path: Path):
    descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
    return os.fdopen(descriptor, "rb")

def _path_overlaps(first: Path, second: Path) -> bool:
    return first == second or first in second.parents or second in first.parents

def _copy_file(
    source: Path,
    destination: Path,
    expected: FixtureFile,
    root: Path,
    remaining: int,
    reserve: int,
) -> tuple[int, int]:
    try:
        before = source.stat(follow_symlinks=False)
        if not stat.S_ISREG(before.st_mode) or before.st_size != expected.size:
            raise _StagingFailure("SOURCE_SIZE_MISMATCH")
        digest = hashlib.sha256()
        count = 0
        destination.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        source_fd = os.open(source, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
        try:
            output_fd = os.open(
                destination,
                os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                0o600,
            )
        except OSError:
            os.close(source_fd)
            raise
        with os.fdopen(source_fd, "rb", buffering=0) as reader, os.fdopen(output_fd, "wb") as writer:
            while True:
                _check_capacity(root, reserve + remaining)
                chunk = reader.read(COPY_CHUNK_BYTES)
                if not chunk:
                    break
                count += len(chunk)
                remaining -= len(chunk)
                if count > expected.size:
                    raise _StagingFailure("SOURCE_SIZE_MISMATCH")
                writer.write(chunk)
                digest.update(chunk)
            writer.flush()
            os.fsync(writer.fileno())
        if count != expected.size:
            raise _StagingFailure("SOURCE_SIZE_MISMATCH")
        if digest.hexdigest() != expected.sha256:
            raise _StagingFailure("SOURCE_DIGEST_MISMATCH")
        return count, remaining
    except _StagingFailure:
        raise
    except OSError:
        raise _StagingFailure("TRANSFER_FAILED") from None

def _check_capacity(path: Path, required: int) -> None:
    if _available_bytes(path) < required:
        raise _StagingFailure("INSUFFICIENT_SPACE")

def _safe_descriptor_reference(value: str, descriptor_path: str) -> str:
    reference = PurePosixPath(value)
    if (
        not value or reference.is_absolute() or "\\" in value or ":" in value
        or any(part in {"", ".", ".."} for part in value.split("/"))
    ):
        raise _StagingFailure("STRUCTURE_MISMATCH")
    resolved = PurePosixPath(descriptor_path).parent / reference
    if any(part in {"", ".", ".."} for part in resolved.parts):
        raise _StagingFailure("STRUCTURE_MISMATCH")
    return resolved.as_posix()

def _descriptor_text(path: Path) -> list[str]:
    try:
        with _open_readonly(path) as reader:
            data = reader.read(MAX_DESCRIPTOR_BYTES + 1)
    except OSError:
        raise _StagingFailure("STRUCTURE_READ_FAILED") from None
    if len(data) > MAX_DESCRIPTOR_BYTES:
        raise _StagingFailure("STRUCTURE_MISMATCH")
    try:
        return data.decode("utf-8-sig").splitlines()
    except UnicodeDecodeError:
        raise _StagingFailure("STRUCTURE_MISMATCH") from None

def _m3u_references(path: Path, relative_path: str) -> list[str]:
    references = []
    for line in _descriptor_text(path):
        value = line.strip()
        if not value or value.startswith("#"):
            continue
        references.append(_safe_descriptor_reference(value, relative_path))
    return references

def _cue_references(path: Path, relative_path: str) -> list[str]:
    references = []
    for line in _descriptor_text(path):
        value = line.strip()
        if not value or not value[:4].casefold() == "file":
            continue
        match = re.fullmatch(r'FILE\s+(?:"([^"]+)"|(\S+))\s+\S+', value, re.IGNORECASE)
        if match is None:
            raise _StagingFailure("STRUCTURE_MISMATCH")
        references.append(_safe_descriptor_reference(match.group(1) or match.group(2), relative_path))
    if not references:
        raise _StagingFailure("STRUCTURE_MISMATCH")
    return references

def _validate_structure(root: Path, fixture: Mapping[str, object]) -> None:
    files = fixture["files"]
    paths = {item["path"] for item in files}
    edges = fixture["companions"]
    outgoing: dict[str, list[str]] = {}
    for edge in edges:
        outgoing.setdefault(edge["source"], []).append(edge["target"])
    expectations = fixture["structural_expectations"]
    kind = expectations.get("entrypoint_kind")
    entrypoint = fixture["entrypoint"]
    if kind == "raw-file":
        if (
            PurePosixPath(entrypoint).suffix.casefold() in {".m3u", ".cue"}
            or edges
        ):
            raise _StagingFailure("STRUCTURE_MISMATCH")
        return
    if kind not in {"m3u", "cue"}:
        raise _StagingFailure("STRUCTURE_MISMATCH")
    suffix = ".m3u" if kind == "m3u" else ".cue"
    if PurePosixPath(entrypoint).suffix.casefold() != suffix:
        raise _StagingFailure("STRUCTURE_MISMATCH")
    if kind == "m3u":
        references = _m3u_references(root / entrypoint, entrypoint)
        if not references:
            raise _StagingFailure("STRUCTURE_MISMATCH")
        declared = [_safe_descriptor_reference(target, entrypoint) for target in outgoing.get(entrypoint, [])]
        if references != declared or any(reference not in paths for reference in references):
            raise _StagingFailure("STRUCTURE_MISMATCH")
        disc_count = expectations.get("disc_count")
        if disc_count is not None and (type(disc_count) is not int or disc_count != len(references)):
            raise _StagingFailure("STRUCTURE_MISMATCH")
    cue_paths = [path for path in paths if PurePosixPath(path).suffix.casefold() == ".cue"]
    if kind == "cue" and entrypoint not in cue_paths:
        cue_paths.append(entrypoint)
    for cue_path in cue_paths:
        references = _cue_references(root / cue_path, cue_path)
        declared = [_safe_descriptor_reference(target, cue_path) for target in outgoing.get(cue_path, [])]
        if references != declared or any(reference not in paths for reference in references):
            raise _StagingFailure("STRUCTURE_MISMATCH")

def _verify_published(published: Path, fixture_records: Sequence[Mapping[str, object]]) -> tuple[int, int]:
    file_count = 0
    byte_count = 0
    expected_fixture_ids = {fixture["fixture_id"] for fixture in fixture_records}
    try:
        published_info = published.lstat()
        root_entries = list(published.iterdir())
    except OSError:
        raise _StagingFailure("PUBLISHED_SET_INCOMPLETE") from None
    if stat.S_ISLNK(published_info.st_mode) or not stat.S_ISDIR(published_info.st_mode):
        raise _StagingFailure("PUBLISHED_SET_UNSAFE")
    if (
        {entry.name for entry in root_entries} != expected_fixture_ids
        or any(entry.is_symlink() or not entry.is_dir() for entry in root_entries)
    ):
        raise _StagingFailure("PUBLISHED_SET_INCOMPLETE")
    for fixture in fixture_records:
        fixture_root = published / fixture["fixture_id"]
        try:
            fixture_root_info = fixture_root.lstat()
        except OSError:
            raise _StagingFailure("PUBLISHED_SET_INCOMPLETE") from None
        if stat.S_ISLNK(fixture_root_info.st_mode) or not stat.S_ISDIR(fixture_root_info.st_mode):
            raise _StagingFailure("PUBLISHED_SET_INCOMPLETE")
        expected = {item["path"] for item in fixture["files"]}
        expected_directories = {
            "/".join(path.split("/")[:index])
            for path in expected for index in range(1, len(path.split("/")))
        }
        found = set()
        found_directories = set()
        for directory, names, files in os.walk(fixture_root, followlinks=False):
            current = Path(directory)
            for name in names:
                child = current / name
                try:
                    child_info = child.lstat()
                except OSError:
                    raise _StagingFailure("PUBLISHED_SET_UNSAFE") from None
                if stat.S_ISLNK(child_info.st_mode) or not stat.S_ISDIR(child_info.st_mode):
                    raise _StagingFailure("PUBLISHED_SET_UNSAFE")
                found_directories.add(child.relative_to(fixture_root).as_posix())
            for name in files:
                path = current / name
                try:
                    info = path.lstat()
                except OSError:
                    raise _StagingFailure("PUBLISHED_SET_UNSAFE") from None
                if not stat.S_ISREG(info.st_mode):
                    raise _StagingFailure("PUBLISHED_SET_UNSAFE")
                found.add(path.relative_to(fixture_root).as_posix())
        if found != expected or found_directories != expected_directories:
            raise _StagingFailure("PUBLISHED_SET_INCOMPLETE")
        for item in fixture["files"]:
            path = fixture_root / item["path"]
            digest = hashlib.sha256()
            count = 0
            try:
                with _open_readonly(path) as reader:
                    while True:
                        chunk = reader.read(COPY_CHUNK_BYTES)
                        if not chunk:
                            break
                        digest.update(chunk)
                        count += len(chunk)
            except OSError:
                raise _StagingFailure("PUBLISHED_READ_FAILED") from None
            if count != item["size"] or digest.hexdigest() != item["sha256"]:
                raise _StagingFailure("PUBLISHED_DIGEST_MISMATCH")
            file_count += 1
            byte_count += count
    return file_count, byte_count
