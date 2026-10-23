"""Validate source membership, directory identities, companion references, and content identity.

Directory identities detect replacement between discovery and access. They do not establish
exclusive control over a writable same-user namespace.
"""

from __future__ import annotations
from dataclasses import dataclass, field
from pathlib import Path, PurePosixPath
import os
import re
import stat
from ._fixture_staging_model import (
    CompanionEdge,
    FixtureExpectation,
    FixtureFileExpectation,
    FixtureStagingError,
    FixtureStagingErrorCode,
    FixtureStagingGrant,
)
from ._fixture_staging_manifest import _safe_relative_path, _walk_companion_graph
from typing import TYPE_CHECKING
if TYPE_CHECKING:
    from ._fixture_staging_destination import FilesystemFixtureDestination


def _require_descriptor_relative_operations() -> None:
    """Reject platforms without the primitives required for verified traversal."""

    try:
        supported = (
            os.open in os.supports_dir_fd
            and os.stat in os.supports_dir_fd
            and os.stat in os.supports_follow_symlinks
            and os.scandir in os.supports_fd
            and hasattr(os, "O_DIRECTORY")
            and hasattr(os, "O_NOFOLLOW")
            and hasattr(os, "O_NONBLOCK")
            and hasattr(os, "set_blocking")
        )
    except (AttributeError, TypeError):
        supported = False
    if not supported:
        raise FixtureStagingError(FixtureStagingErrorCode.SOURCE_INVALID) from None


def _directory_identity(value: object) -> tuple[int, int] | None:
    """Return a valid device/inode pair or ``None`` for ambiguous provenance."""

    if (
        type(value) is not tuple
        or len(value) != 2
        or type(value[0]) is not int
        or type(value[1]) is not int
        or value[0] < 0
        or value[1] < 0
    ):
        return None
    return value


def _anchor_hierarchy(
    value: object,
) -> tuple[tuple[int, int], ...] | None:
    """Return a non-empty, structurally valid root-anchor hierarchy."""

    if type(value) is not tuple or not value:
        return None
    if any(_directory_identity(item) is None for item in value):
        return None
    return value


class _DirectoryIdentityTable(tuple[tuple[str, tuple[int, int]], ...]):
    """Directory identities paired with the root-anchor hierarchy they came from."""

    _root_hierarchy: tuple[tuple[int, int], ...]

    @property
    def root_hierarchy(self) -> tuple[tuple[int, int], ...]:
        return self._root_hierarchy

    def __new__(cls, entries, root_hierarchy):
        hierarchy = _anchor_hierarchy(root_hierarchy)
        if hierarchy is None:
            raise FixtureStagingError(FixtureStagingErrorCode.SOURCE_INVALID)
        table = super().__new__(cls, tuple(entries))
        table._root_hierarchy = hierarchy
        return table


def _open_verified_directory(
    name: str | Path,
    expected_identity: tuple[int, int],
    *,
    dir_fd: int | None = None,
    open_error_code: FixtureStagingErrorCode = FixtureStagingErrorCode.SOURCE_INVALID,
) -> int:
    """Open one directory, then require its descriptor identity to match discovery."""

    _require_descriptor_relative_operations()
    expected = _directory_identity(expected_identity)
    if expected is None:
        raise FixtureStagingError(FixtureStagingErrorCode.SOURCE_INVALID)
    descriptor = -1
    try:
        flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
        if dir_fd is None:
            descriptor = os.open(name, flags)
        else:
            descriptor = os.open(name, flags, dir_fd=dir_fd)
        opened = os.fstat(descriptor)
    except (OSError, TypeError, ValueError):
        if descriptor >= 0:
            os.close(descriptor)
        raise FixtureStagingError(open_error_code) from None
    if (
        not stat.S_ISDIR(opened.st_mode)
        or opened.st_uid != os.geteuid()
    ):
        os.close(descriptor)
        raise FixtureStagingError(FixtureStagingErrorCode.SOURCE_INVALID)
    if (opened.st_dev, opened.st_ino) != expected:
        os.close(descriptor)
        raise FixtureStagingError(FixtureStagingErrorCode.SOURCE_CHANGED)
    return descriptor


def _file_identity(info: os.stat_result) -> tuple[int, ...]:
    return (
        info.st_dev,
        info.st_ino,
        info.st_size,
        info.st_mtime_ns,
        info.st_ctime_ns,
        info.st_mode,
        info.st_nlink,
        info.st_uid,
    )


def _open_anchored_root(
    root: Path,
    *,
    expected_identity: tuple[int, int] | None = None,
    expected_hierarchy: tuple[tuple[int, int], ...] | None = None,
    open_error_code: FixtureStagingErrorCode = FixtureStagingErrorCode.SOURCE_CHANGED,
) -> tuple[int, tuple[tuple[int, int], ...]]:
    """Open an absolute root through a no-follow chain from a trusted anchor."""
    _require_descriptor_relative_operations()
    absolute = Path(root)
    if not absolute.is_absolute():
        raise FixtureStagingError(FixtureStagingErrorCode.SOURCE_INVALID)

    current = -1
    try:
        anchor = Path(absolute.anchor)
        flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
        current = os.open(anchor, flags)
        anchor_info = os.fstat(current)
        if not stat.S_ISDIR(anchor_info.st_mode):
            raise FixtureStagingError(FixtureStagingErrorCode.SOURCE_INVALID)
        hierarchy = [(anchor_info.st_dev, anchor_info.st_ino)]
        if (
            expected_hierarchy is not None
            and (
                not expected_hierarchy
                or hierarchy[0] != expected_hierarchy[0]
            )
        ):
            raise FixtureStagingError(FixtureStagingErrorCode.SOURCE_CHANGED)

        for component_index, component in enumerate(absolute.parts[1:], start=1):
            before = os.stat(component, dir_fd=current, follow_symlinks=False)
            if not stat.S_ISDIR(before.st_mode):
                raise FixtureStagingError(open_error_code)
            child = -1
            try:
                child = os.open(component, flags, dir_fd=current)
                opened = os.fstat(child)
                if (
                    not stat.S_ISDIR(opened.st_mode)
                    or (before.st_dev, before.st_ino)
                    != (opened.st_dev, opened.st_ino)
                ):
                    raise FixtureStagingError(open_error_code)
                if (
                    expected_hierarchy is not None
                    and (
                        component_index >= len(expected_hierarchy)
                        or (opened.st_dev, opened.st_ino)
                        != expected_hierarchy[component_index]
                    )
                ):
                    raise FixtureStagingError(FixtureStagingErrorCode.SOURCE_CHANGED)
            except BaseException:
                if child >= 0:
                    os.close(child)
                raise
            os.close(current)
            current = child
            hierarchy.append((opened.st_dev, opened.st_ino))
    except FixtureStagingError:
        if current >= 0:
            os.close(current)
        raise
    except (OSError, TypeError, ValueError):
        if current >= 0:
            os.close(current)
        raise FixtureStagingError(open_error_code) from None

    try:
        if expected_hierarchy is not None and tuple(hierarchy) != expected_hierarchy:
            raise FixtureStagingError(FixtureStagingErrorCode.SOURCE_CHANGED)
        if expected_identity is not None and hierarchy[-1] != expected_identity:
            raise FixtureStagingError(FixtureStagingErrorCode.SOURCE_CHANGED)
        if os.fstat(current).st_uid != os.geteuid():
            raise FixtureStagingError(FixtureStagingErrorCode.SOURCE_INVALID)
        return current, tuple(hierarchy)
    except BaseException:
        os.close(current)
        raise


def _discover_source_root(
    root: Path,
) -> tuple[Path, tuple[int, int], tuple[tuple[int, int], ...]]:
    """Resolve stable aliases, then verify the physical root by descriptor."""
    _require_descriptor_relative_operations()
    descriptor = -1
    try:
        absolute = Path(root).absolute()
        before = absolute.lstat()
        if not stat.S_ISDIR(before.st_mode) or before.st_uid != os.geteuid():
            raise FixtureStagingError(FixtureStagingErrorCode.SOURCE_INVALID)
        canonical = absolute.resolve(strict=True)
        descriptor, hierarchy = _open_anchored_root(
            canonical,
            expected_identity=(before.st_dev, before.st_ino),
            open_error_code=FixtureStagingErrorCode.SOURCE_INVALID,
        )
        opened = os.fstat(descriptor)
        if opened.st_uid != os.geteuid():
            raise FixtureStagingError(FixtureStagingErrorCode.SOURCE_INVALID)
        return canonical, (opened.st_dev, opened.st_ino), hierarchy
    except FixtureStagingError:
        raise
    except (OSError, TypeError, ValueError):
        raise FixtureStagingError(FixtureStagingErrorCode.SOURCE_INVALID) from None
    finally:
        if descriptor >= 0:
            os.close(descriptor)


@dataclass(frozen=True)
class _SourceSnapshot:
    fixture_id: str
    expectation: FixtureFileExpectation
    root: Path
    root_device: int
    root_inode: int
    file_identity: tuple[int, ...]
    directory_identities: tuple[tuple[str, tuple[int, int]], ...]
    root_hierarchy: tuple[tuple[int, int], ...] | None = None


def _source_root_identity(root: Path) -> tuple[int, int]:
    """Discover the current root identity through the trusted anchor chain."""

    _canonical, identity, _hierarchy = _discover_source_root(root)
    return identity


def _open_source_member(
    root: Path,
    relative_path: str,
    directory_identities: tuple[tuple[str, tuple[int, int]], ...],
    *,
    root_hierarchy: tuple[tuple[int, int], ...] | None = None,
) -> tuple[int, int, str, os.stat_result, tuple[int, int]]:
    """Open one contained member through directories verified against discovery."""

    _require_descriptor_relative_operations()
    _safe_relative_path(relative_path)
    try:
        identity_items = tuple(directory_identities)
        expected_by_path = dict(identity_items)
    except (TypeError, ValueError):
        raise FixtureStagingError(FixtureStagingErrorCode.SOURCE_INVALID) from None
    if len(expected_by_path) != len(identity_items):
        raise FixtureStagingError(FixtureStagingErrorCode.SOURCE_INVALID)
    for expected_path, expected_value in identity_items:
        if type(expected_path) is not str or _directory_identity(expected_value) is None:
            raise FixtureStagingError(FixtureStagingErrorCode.SOURCE_INVALID)
    root_identity = _directory_identity(expected_by_path.get(""))
    if root_identity is None:
        raise FixtureStagingError(FixtureStagingErrorCode.SOURCE_INVALID)
    table_hierarchy = (
        directory_identities.root_hierarchy
        if type(directory_identities) is _DirectoryIdentityTable
        else None
    )
    if root_hierarchy is None:
        root_hierarchy = table_hierarchy
    elif table_hierarchy is not None and root_hierarchy != table_hierarchy:
        raise FixtureStagingError(FixtureStagingErrorCode.SOURCE_INVALID)
    root_hierarchy = _anchor_hierarchy(root_hierarchy)
    if root_hierarchy is None:
        raise FixtureStagingError(FixtureStagingErrorCode.SOURCE_INVALID)
    try:
        current, _opened_hierarchy = _open_anchored_root(
            root,
            expected_identity=root_identity,
            expected_hierarchy=root_hierarchy,
        )
    except FixtureStagingError:
        raise
    except (OSError, TypeError, ValueError):
        raise FixtureStagingError(FixtureStagingErrorCode.SOURCE_INVALID) from None
    try:
        components = relative_path.split("/")
        prefix = ""
        for component in components[:-1]:
            prefix = f"{prefix}/{component}" if prefix else component
            expected_identity = _directory_identity(expected_by_path.get(prefix))
            if expected_identity is None:
                raise FixtureStagingError(FixtureStagingErrorCode.SOURCE_INVALID)
            try:
                next_descriptor = _open_verified_directory(
                    component,
                    expected_identity,
                    dir_fd=current,
                )
            except FixtureStagingError:
                raise
            except (OSError, TypeError, ValueError):
                raise FixtureStagingError(FixtureStagingErrorCode.SOURCE_INVALID) from None
            os.close(current)
            current = next_descriptor
        basename = components[-1]
        descriptor = -1
        try:
            before = os.stat(basename, dir_fd=current, follow_symlinks=False)
            if (
                not stat.S_ISREG(before.st_mode)
                or before.st_uid != os.geteuid()
                or before.st_nlink != 1
                or before.st_dev != root_identity[0]
            ):
                raise FixtureStagingError(FixtureStagingErrorCode.SOURCE_INVALID)
            descriptor = os.open(
                basename,
                os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW,
                dir_fd=current,
            )
            opened = os.fstat(descriptor)
            if _file_identity(before) != _file_identity(opened):
                raise FixtureStagingError(FixtureStagingErrorCode.SOURCE_CHANGED)
            os.set_blocking(descriptor, True)
        except FixtureStagingError:
            if descriptor >= 0:
                os.close(descriptor)
            raise
        except OSError:
            if descriptor >= 0:
                os.close(descriptor)
            raise FixtureStagingError(FixtureStagingErrorCode.SOURCE_INVALID) from None
        return descriptor, current, basename, opened, root_identity
    except BaseException:
        os.close(current)
        raise


def _close_source_member(descriptor: int, parent_descriptor: int) -> None:
    os.close(descriptor)
    os.close(parent_descriptor)


def _verify_source_path(snapshot: _SourceSnapshot) -> None:
    descriptor, parent_descriptor, _basename, opened, root_identity = _open_source_member(
        snapshot.root,
        snapshot.expectation.path,
        snapshot.directory_identities,
        root_hierarchy=snapshot.root_hierarchy,
    )
    try:
        if root_identity != (snapshot.root_device, snapshot.root_inode) or _file_identity(opened) != snapshot.file_identity:
            raise FixtureStagingError(FixtureStagingErrorCode.SOURCE_CHANGED)
    finally:
        _close_source_member(descriptor, parent_descriptor)


def _validate_source_membership(
    root: Path,
    expected_paths: tuple[str, ...],
    root_identity: tuple[int, int],
    *,
    root_hierarchy: tuple[tuple[int, int], ...] | None = None,
) -> tuple[tuple[str, tuple[int, int]], ...]:
    """Reject unlisted entries and retain every verified directory identity."""

    expected_files = set(expected_paths)
    expected_directories: set[str] = set()
    for path in expected_paths:
        parts = path.split("/")
        expected_directories.update(
            "/".join(parts[:index]) for index in range(1, len(parts))
        )
    if root_hierarchy is None:
        root, discovered_identity, root_hierarchy = _discover_source_root(root)
        if discovered_identity != root_identity:
            raise FixtureStagingError(FixtureStagingErrorCode.SOURCE_CHANGED)
    root_hierarchy = _anchor_hierarchy(root_hierarchy)
    if root_hierarchy is None:
        raise FixtureStagingError(FixtureStagingErrorCode.SOURCE_INVALID)
    root_descriptor, _opened_hierarchy = _open_anchored_root(
        root,
        expected_identity=root_identity,
        expected_hierarchy=root_hierarchy,
    )
    directory_identities: list[tuple[str, tuple[int, int]]] = [("", root_identity)]
    identity_paths = {root_identity: ""}
    pending: list[tuple[int, str]] = [(root_descriptor, "")]
    discovered_files: set[str] = set()
    try:
        while pending:
            descriptor, prefix = pending.pop()
            try:
                with os.scandir(descriptor) as entries:
                    for entry in entries:
                        relative = f"{prefix}/{entry.name}" if prefix else entry.name
                        try:
                            info = entry.stat(follow_symlinks=False)
                        except OSError:
                            raise FixtureStagingError(
                                FixtureStagingErrorCode.SOURCE_CHANGED
                            ) from None
                        if stat.S_ISDIR(info.st_mode):
                            if (
                                relative not in expected_directories
                                or info.st_uid != os.geteuid()
                                or info.st_dev != root_identity[0]
                            ):
                                raise FixtureStagingError(
                                    FixtureStagingErrorCode.SOURCE_INVALID
                                )
                            child_identity = (info.st_dev, info.st_ino)
                            child = _open_verified_directory(
                                entry.name,
                                child_identity,
                                dir_fd=descriptor,
                                open_error_code=FixtureStagingErrorCode.SOURCE_CHANGED,
                            )
                            existing_path = identity_paths.get(child_identity)
                            if existing_path is not None and existing_path != relative:
                                os.close(child)
                                raise FixtureStagingError(
                                    FixtureStagingErrorCode.SOURCE_INVALID
                                )
                            identity_paths[child_identity] = relative
                            directory_identities.append((relative, child_identity))
                            pending.append((child, relative))
                        elif stat.S_ISREG(info.st_mode):
                            if (
                                relative not in expected_files
                                or info.st_uid != os.geteuid()
                                or info.st_nlink != 1
                                or info.st_dev != root_identity[0]
                            ):
                                raise FixtureStagingError(
                                    FixtureStagingErrorCode.SOURCE_INVALID
                                )
                            discovered_files.add(relative)
                        else:
                            raise FixtureStagingError(
                                FixtureStagingErrorCode.SOURCE_INVALID
                            )
            finally:
                os.close(descriptor)
    except OSError:
        for descriptor, _prefix in pending:
            try:
                os.close(descriptor)
            except OSError:
                pass
        raise FixtureStagingError(FixtureStagingErrorCode.SOURCE_CHANGED) from None
    except BaseException:
        for descriptor, _prefix in pending:
            try:
                os.close(descriptor)
            except OSError:
                pass
        raise
    if discovered_files != expected_files:
        raise FixtureStagingError(FixtureStagingErrorCode.SOURCE_INVALID)
    return _DirectoryIdentityTable(directory_identities, root_hierarchy)


def _preflight_sources(
    expectations: tuple[FixtureExpectation, ...],
    source_roots: dict[str, Path],
    destination_root: Path,
) -> tuple[tuple[_SourceSnapshot, ...], int]:
    expected_ids = tuple(item.fixture_id for item in expectations)
    if type(source_roots) is not dict or set(source_roots) != set(expected_ids):
        raise FixtureStagingError(FixtureStagingErrorCode.SOURCE_INVALID)
    destination_real = destination_root.resolve(strict=True)
    snapshots: list[_SourceSnapshot] = []
    total_bytes = 0
    for fixture in expectations:
        root = Path(source_roots[fixture.fixture_id]).absolute()
        try:
            root, root_identity, root_hierarchy = _discover_source_root(root)
            overlap = _paths_overlap_by_directory_identity(root, destination_real)
        except FixtureStagingError:
            raise
        except (OSError, ValueError, TypeError):
            raise FixtureStagingError(FixtureStagingErrorCode.SOURCE_INVALID) from None
        if overlap:
            raise FixtureStagingError(FixtureStagingErrorCode.SOURCE_INVALID)
        root_device, root_inode = root_identity
        directory_identities = _validate_source_membership(
            root,
            tuple(item.path for item in fixture.files),
            root_identity,
            root_hierarchy=root_hierarchy,
        )
        for expected in fixture.files:
            descriptor, parent_descriptor, _basename, opened, identity = _open_source_member(
                root,
                expected.path,
                directory_identities,
                root_hierarchy=root_hierarchy,
            )
            try:
                snapshot_identity = _file_identity(opened)
                if opened.st_size != expected.size or identity != root_identity:
                    raise FixtureStagingError(FixtureStagingErrorCode.SOURCE_CHANGED)
                snapshots.append(
                    _SourceSnapshot(
                        fixture.fixture_id,
                        expected,
                        root,
                        root_device,
                        root_inode,
                        snapshot_identity,
                        directory_identities,
                        root_hierarchy=root_hierarchy,
                    )
                )
                total_bytes += opened.st_size
            finally:
                _close_source_member(descriptor, parent_descriptor)
        _validate_companion_graph(fixture, root, snapshots[-len(fixture.files):])
    return tuple(snapshots), total_bytes


def _paths_overlap_by_directory_identity(first: Path, second: Path) -> bool:
    """Detect equal or nested roots by inode identity rather than spelling."""

    def is_ancestor(ancestor: Path, descendant: Path) -> bool:
        ancestor_info = ancestor.stat()
        if not stat.S_ISDIR(ancestor_info.st_mode):
            raise OSError("a root is not a directory")
        ancestor_identity = (ancestor_info.st_dev, ancestor_info.st_ino)
        for candidate in (descendant, *descendant.parents):
            info = candidate.stat()
            if not stat.S_ISDIR(info.st_mode):
                raise OSError("a root ancestor is not a directory")
            if (info.st_dev, info.st_ino) == ancestor_identity:
                return True
        return False

    return is_ancestor(first, second) or is_ancestor(second, first)


_CUE_FILE = re.compile(r'^\s*FILE\s+(?:"([^"]+)"|(\S+))\s+(BINARY|MOTOROLA|WAVE|AIFF|MP3)\s*$', re.IGNORECASE)


_MAX_DESCRIPTOR_LINE_BYTES = 4096


def _descriptor_edges(fixture: FixtureExpectation, root: Path, snapshots: tuple[_SourceSnapshot, ...]) -> tuple[CompanionEdge, ...]:
    by_path = {item.expectation.path: item for item in snapshots}
    edges: list[CompanionEdge] = []
    for expected in fixture.files:
        suffix = PurePosixPath(expected.path).suffix.casefold()
        if suffix not in {".cue", ".m3u", ".m3u8"}:
            continue
        snapshot = by_path[expected.path]
        descriptor, parent_descriptor, basename, opened, _identity = _open_source_member(
            snapshot.root,
            expected.path,
            snapshot.directory_identities,
            root_hierarchy=snapshot.root_hierarchy,
        )
        try:
            if _file_identity(opened) != snapshot.file_identity:
                raise FixtureStagingError(FixtureStagingErrorCode.SOURCE_CHANGED)
            with os.fdopen(descriptor, "rb", closefd=True) as stream:
                descriptor = -1
                chunks = iter(lambda: stream.read(64 * 1024), b"")
                edges.extend(
                    _parse_companion_lines(
                        expected.path,
                        _iter_lines(
                            chunks,
                            error_code=FixtureStagingErrorCode.SOURCE_INVALID,
                        ),
                        error_code=FixtureStagingErrorCode.SOURCE_INVALID,
                    )
                )
                after = os.fstat(stream.fileno())
            current = os.stat(basename, dir_fd=parent_descriptor, follow_symlinks=False)
            if _file_identity(after) != snapshot.file_identity or _file_identity(current) != snapshot.file_identity:
                raise FixtureStagingError(FixtureStagingErrorCode.SOURCE_CHANGED)
        except FixtureStagingError:
            raise
        except OSError:
            raise FixtureStagingError(FixtureStagingErrorCode.SOURCE_CHANGED) from None
        finally:
            if descriptor >= 0:
                os.close(descriptor)
            os.close(parent_descriptor)
    return tuple(edges)


def _validate_companion_graph(
    fixture: FixtureExpectation,
    root: Path,
    snapshots: tuple[_SourceSnapshot, ...],
) -> None:
    paths = {item.expectation.path for item in snapshots}
    actual = _descriptor_edges(fixture, root, snapshots)
    if actual != fixture.companions or any(edge.target not in paths for edge in actual):
        raise FixtureStagingError(FixtureStagingErrorCode.SOURCE_INVALID)
    adjacency: dict[str, list[str]] = {}
    for edge in actual:
        adjacency.setdefault(edge.source, []).append(edge.target)
    visited = _walk_companion_graph(fixture.entrypoint, adjacency)
    if visited is None or visited != paths:
        raise FixtureStagingError(FixtureStagingErrorCode.SOURCE_INVALID)


def _iter_lines(
    chunks,
    *,
    error_code: FixtureStagingErrorCode,
):
    buffered = bytearray()
    first = True
    for chunk in chunks:
        buffered.extend(chunk)
        while True:
            newline = buffered.find(b"\n")
            if newline < 0:
                if len(buffered) > _MAX_DESCRIPTOR_LINE_BYTES:
                    raise FixtureStagingError(error_code)
                break
            if newline + 1 > _MAX_DESCRIPTOR_LINE_BYTES:
                raise FixtureStagingError(error_code)
            raw_line = bytes(buffered[: newline + 1])
            del buffered[: newline + 1]
            try:
                yield raw_line.decode("utf-8-sig" if first else "utf-8").strip()
            except UnicodeDecodeError:
                raise FixtureStagingError(error_code) from None
            first = False
    if buffered:
        try:
            yield bytes(buffered).decode("utf-8-sig" if first else "utf-8").strip()
        except UnicodeDecodeError:
            raise FixtureStagingError(error_code) from None


def _parse_companion_lines(
    path: str,
    lines,
    *,
    error_code: FixtureStagingErrorCode = FixtureStagingErrorCode.SOURCE_INVALID,
) -> tuple[CompanionEdge, ...]:
    suffix = PurePosixPath(path).suffix.casefold()
    if suffix not in {".cue", ".m3u", ".m3u8"}:
        return ()
    edges: list[CompanionEdge] = []
    try:
        for line in lines:
            if suffix == ".cue":
                if not line or line.upper().startswith("REM "):
                    continue
                if re.match(r"^FILE(?:\s|$)", line, re.IGNORECASE) is None:
                    continue
                match = _CUE_FILE.fullmatch(line)
                if match is None:
                    raise FixtureStagingError(error_code)
                reference = match.group(1) or match.group(2)
            else:
                if not line or line.startswith("#"):
                    continue
                reference = line
            reference = _safe_relative_path(reference)
            parent_parts = PurePosixPath(path).parent.parts
            target = _safe_relative_path("/".join((*parent_parts, *PurePosixPath(reference).parts)))
            edges.append(CompanionEdge(path, target))
    except FixtureStagingError:
        raise FixtureStagingError(error_code) from None
    return tuple(edges)


def _destination_companion_edges(
    destination: FilesystemFixtureDestination,
    session_id: str,
    fixture: FixtureExpectation,
    *,
    check_deadline=None,
    grant: FixtureStagingGrant,
    capability,
) -> tuple[CompanionEdge, ...]:
    edges: list[CompanionEdge] = []
    for expected in fixture.files:
        if PurePosixPath(expected.path).suffix.casefold() not in {".cue", ".m3u", ".m3u8"}:
            continue

        def checked_chunks():
            for chunk in destination._read_file_chunks_for_staging(
                session_id,
                fixture.fixture_id,
                expected.path,
                grant=grant,
                capability=capability,
            ):
                if check_deadline is not None:
                    check_deadline()
                yield chunk

        edges.extend(
            _parse_companion_lines(
                expected.path,
                _iter_lines(
                    checked_chunks(), error_code=FixtureStagingErrorCode.COPY_INVALID
                ),
                error_code=FixtureStagingErrorCode.COPY_INVALID,
            )
        )
    return tuple(edges)


def _graph_reaches_all(fixture: FixtureExpectation, edges: tuple[CompanionEdge, ...]) -> bool:
    paths = {item.path for item in fixture.files}
    if any(edge.source not in paths or edge.target not in paths for edge in edges):
        return False
    adjacency: dict[str, list[str]] = {}
    for edge in edges:
        adjacency.setdefault(edge.source, []).append(edge.target)
    visited = _walk_companion_graph(fixture.entrypoint, adjacency)
    return visited is not None and visited == paths
