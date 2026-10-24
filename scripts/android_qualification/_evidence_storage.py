"""Private canonical execution-record persistence and publication."""

from __future__ import annotations

import contextlib
import ctypes
import datetime as dt
import errno
import fcntl
import hashlib
import json
import os
import re
import secrets
import stat
import sys
from pathlib import Path
from typing import Any, Iterator, NoReturn

from scripts.android_qualification import evidence


SCHEMA_VERSION = 1
MAX_RECORD_BYTES = 64 * 1024
_SESSION_ID = re.compile(r"[0-9a-f]{32}\Z")
_SHA256 = re.compile(r"[0-9a-f]{64}\Z")
_OPAQUE_ALIAS_SUFFIX = re.compile(r"[0-9a-f]{32}\Z")
_VERSION = re.compile(
    r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)"
    r"(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?"
    r"(?:\+[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?\Z"
)
_TIMESTAMP = re.compile(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\Z")
_TEMPORARY_RECORD = re.compile(r"\.record-\d{8}\.tmp-[0-9a-f]{32}\Z")
_TEMPORARY_MANIFEST = re.compile(r"\.manifest\.tmp-[0-9a-f]{32}\Z")
_INTERNAL_OPERATION_PREFIX = "internal-"
_INTERNAL_OPERATION_ID = re.compile(r"internal-[0-9a-f]{32}\Z")
_TYPED_ALIAS_PREFIXES = {
    "artifact": "artifact-",
    "assertion": "assertion-",
    "corpus": "corpus-",
    "environment": "environment-",
    "evidence": "evidence-",
    "measurement": "measurement-",
    "operation": "operation-",
    "owner": "owner-",
    "plan": "plan-",
    "platform-version": "platform-version-",
    "rules": "rules-",
    "scenario": "scenario-",
    "target": "target-",
}
_RECOVERY_OPERATION_ID = "internal-" + hashlib.sha256(b"recovery-interruption").hexdigest()[:32]


def _transition(_stage: str) -> None:
    """Provide a no-op checkpoint for deterministic crash-injection tests."""


class _DuplicateKey(ValueError):
    pass


class _FloatingPoint(ValueError):
    pass


class _NonFinite(ValueError):
    pass


class _MissingPrivateFile(Exception):
    """Identify an absent entry without masking unreadable files."""


def _invalid() -> NoReturn:
    raise evidence.EvidenceError(evidence.EvidenceErrorCode.INVALID_INPUT)


def _object_without_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    document: dict[str, Any] = {}
    for key, value in pairs:
        if key in document:
            raise _DuplicateKey
        document[key] = value
    return document


def _reject_float(_value: str) -> NoReturn:
    raise _FloatingPoint


def _reject_non_finite(_value: str) -> NoReturn:
    raise _NonFinite


def _canonical_bytes(document: object) -> bytes:
    try:
        return json.dumps(
            document,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
            allow_nan=False,
        ).encode("utf-8")
    except (RecursionError, TypeError, UnicodeEncodeError, ValueError):
        _invalid()


def _canonical_sha256(document: object) -> str:
    return hashlib.sha256(_canonical_bytes(document)).hexdigest()


def _require_text(value: object, *, maximum: int = 128) -> str:
    if type(value) is not str or not 1 <= len(value) <= maximum:
        _invalid()
    if value != value.strip():
        _invalid()
    if any(ord(character) < 0x20 or ord(character) == 0x7F for character in value):
        _invalid()
    lowered = value.casefold()
    if (
        any(character in value for character in ("/", "\\"))
        or "://" in value
        or any(
            marker in lowered
            for marker in (
                "apikey",
                "api-key",
                "bearer",
                "credential",
                "password",
                "passwd",
                "private-key",
                "secret",
                "serial",
                "token",
            )
        )
    ):
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.PRIVATE_DATA_REJECTED)
    return value


def _require_opaque_ref(value: object, *, kind: str) -> str:
    """Require a typed opaque alias with a fixed-width random identifier."""

    text = _require_text(value)
    prefix = _TYPED_ALIAS_PREFIXES.get(kind)
    if (
        prefix is None
        or not text.startswith(prefix)
        or _OPAQUE_ALIAS_SUFFIX.fullmatch(text[len(prefix) :]) is None
    ):
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.PRIVATE_DATA_REJECTED)
    return text


def _require_internal_operation_id(value: object) -> str:
    """Require the reserved internal operation identifier format."""

    text = _require_text(value)
    if _INTERNAL_OPERATION_ID.fullmatch(text) is None:
        _invalid()
    return text


def _require_caller_operation_id(value: object) -> str:
    """Validate an operation ID accepted from a public writer request."""

    if type(value) is str and value.startswith(_INTERNAL_OPERATION_PREFIX):
        _invalid()
    return _require_opaque_ref(value, kind="operation")


def _require_sha256(value: object) -> str:
    if type(value) is not str or _SHA256.fullmatch(value) is None:
        _invalid()
    return value


def _require_version(value: object) -> str:
    """Validate an exact semantic version string without normalizing it."""

    text = _require_text(value, maximum=64)
    if _VERSION.fullmatch(text) is None:
        _invalid()
    return text


def _require_positive_integer(value: object, *, maximum: int = 1_000_000) -> int:
    if type(value) is not int or not 1 <= value <= maximum:
        _invalid()
    return value


def _require_timestamp(value: object) -> str:
    if type(value) is not str or _TIMESTAMP.fullmatch(value) is None:
        _invalid()
    try:
        parsed = dt.datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError:
        _invalid()
    if parsed.tzinfo is not None:
        _invalid()
    return value


def _now_timestamp() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _require_session_id(value: object) -> str:
    if type(value) is not str or _SESSION_ID.fullmatch(value) is None:
        _invalid()
    return value


def _absolute_path(path: Path) -> Path:
    """Return a lexical absolute path without following the final component."""

    return Path(os.path.abspath(os.fspath(path)))


def _directory_flags() -> int:
    return os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)


def _open_canonical_directory(path: Path) -> int:
    """Open an existing directory component by component without symlinks."""

    canonical = Path(os.path.realpath(path))
    descriptor = -1
    try:
        descriptor = os.open(canonical.anchor or os.sep, _directory_flags())
        for component in canonical.parts[1:]:
            child_descriptor = -1
            try:
                child_descriptor = os.open(
                    component,
                    _directory_flags(),
                    dir_fd=descriptor,
                )
                opened = os.fstat(child_descriptor)
                named = os.stat(component, dir_fd=descriptor, follow_symlinks=False)
            except OSError:
                if child_descriptor >= 0:
                    os.close(child_descriptor)
                raise evidence.EvidenceError(
                    evidence.EvidenceErrorCode.UNSAFE_PATH
                ) from None
            if (
                not stat.S_ISDIR(opened.st_mode)
                or (opened.st_dev, opened.st_ino) != (named.st_dev, named.st_ino)
            ):
                os.close(child_descriptor)
                raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNSAFE_PATH)
            os.close(descriptor)
            descriptor = child_descriptor
        return descriptor
    except BaseException:
        if descriptor >= 0:
            os.close(descriptor)
        raise


def _open_private_child(parent_descriptor: int, name: str) -> int:
    """Open one existing private child directory through its parent descriptor."""

    descriptor = -1
    try:
        named = os.stat(name, dir_fd=parent_descriptor, follow_symlinks=False)
        if stat.S_ISLNK(named.st_mode):
            raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNSAFE_PATH)
        if not stat.S_ISDIR(named.st_mode):
            raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNAVAILABLE)
        descriptor = os.open(name, _directory_flags(), dir_fd=parent_descriptor)
        opened = os.fstat(descriptor)
    except evidence.EvidenceError:
        if descriptor >= 0:
            os.close(descriptor)
        raise
    except OSError:
        if descriptor >= 0:
            os.close(descriptor)
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNSAFE_PATH) from None
    if (
        not stat.S_ISDIR(opened.st_mode)
        or opened.st_uid != os.geteuid()
        or stat.S_IMODE(opened.st_mode) != 0o700
        or (opened.st_dev, opened.st_ino) != (named.st_dev, named.st_ino)
    ):
        os.close(descriptor)
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNSAFE_PATH)
    return descriptor


def _create_private_child(parent_descriptor: int, name: str) -> int:
    """Create and verify one private child, then synchronize its parent."""

    try:
        os.mkdir(name, 0o700, dir_fd=parent_descriptor)
    except FileExistsError:
        pass
    except OSError:
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNAVAILABLE) from None
    child_descriptor = _open_private_child(parent_descriptor, name)
    try:
        _fsync_directory(parent_descriptor)
    except evidence.EvidenceError:
        os.close(child_descriptor)
        raise
    return child_descriptor


def _ensure_private_root(
    root: Path,
    *,
    create: bool,
    missing_ok: bool = False,
) -> int:
    """Open the evidence root without following its final path component.

    With create=False, missing_ok=True returns -1 only when the root is
    absent. Symlink, type, permission, and other filesystem failures continue
    to raise a bounded evidence error.

    With create=True, an existing root is reopened through the creation path so
    that its parent synchronization is repeated before descendants are used.
    """

    absolute_root = _absolute_path(root)
    try:
        existing = absolute_root.lstat()
    except FileNotFoundError:
        existing = None
    except OSError:
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNAVAILABLE) from None

    if existing is not None:
        if stat.S_ISLNK(existing.st_mode):
            raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNSAFE_PATH)
        if not stat.S_ISDIR(existing.st_mode):
            raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNAVAILABLE)
        if absolute_root == absolute_root.parent:
            raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNSAFE_PATH)
        parent_descriptor = _open_canonical_directory(absolute_root.parent)
        try:
            if create:
                return _create_private_child(parent_descriptor, absolute_root.name)
            return _open_private_child(parent_descriptor, absolute_root.name)
        finally:
            os.close(parent_descriptor)

    if not create:
        if missing_ok:
            return -1
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNAVAILABLE)

    missing = [absolute_root.name]
    ancestor = absolute_root.parent
    while True:
        try:
            info = ancestor.lstat()
            if stat.S_ISLNK(info.st_mode):
                break
            if not stat.S_ISDIR(info.st_mode):
                raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNAVAILABLE)
            break
        except FileNotFoundError:
            if ancestor == ancestor.parent:
                raise evidence.EvidenceError(
                    evidence.EvidenceErrorCode.UNAVAILABLE
                ) from None
            missing.append(ancestor.name)
            ancestor = ancestor.parent
        except evidence.EvidenceError:
            raise
        except OSError:
            raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNAVAILABLE) from None

    parent_descriptor = _open_canonical_directory(ancestor)
    try:
        for component in reversed(missing):
            child_descriptor = _create_private_child(parent_descriptor, component)
            os.close(parent_descriptor)
            parent_descriptor = child_descriptor
        return parent_descriptor
    except BaseException:
        os.close(parent_descriptor)
        raise


def _open_private_path(
    root: Path,
    path: Path,
    *,
    create: bool,
    missing_ok: bool = False,
) -> int:
    """Open a path beneath an evidence root using only verified descriptors.

    With create=False, missing_ok=True returns -1 only when a path component
    is absent. Other validation failures continue to propagate.

    When create=True, existing child components are reopened through the
    creation path. This repeats their parent synchronization before the next
    component is used, completing any directory creation that failed after
    it became visible in the parent.
    """

    absolute_root = _absolute_path(root)
    absolute_path = _absolute_path(path)
    if absolute_path == absolute_root:
        return _ensure_private_root(
            absolute_root,
            create=create,
            missing_ok=missing_ok,
        )
    try:
        relative = absolute_path.relative_to(absolute_root)
    except ValueError:
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNSAFE_PATH) from None

    parent_descriptor = _ensure_private_root(
        absolute_root,
        create=create,
        missing_ok=missing_ok,
    )
    if parent_descriptor < 0:
        return -1
    try:
        for component in relative.parts:
            try:
                named = os.stat(
                    component,
                    dir_fd=parent_descriptor,
                    follow_symlinks=False,
                )
            except FileNotFoundError:
                if not create:
                    if missing_ok:
                        os.close(parent_descriptor)
                        return -1
                    raise evidence.EvidenceError(
                        evidence.EvidenceErrorCode.UNAVAILABLE
                    ) from None
                child_descriptor = _create_private_child(parent_descriptor, component)
            except OSError:
                raise evidence.EvidenceError(
                    evidence.EvidenceErrorCode.UNAVAILABLE
                ) from None
            else:
                if stat.S_ISLNK(named.st_mode):
                    raise evidence.EvidenceError(
                        evidence.EvidenceErrorCode.UNSAFE_PATH
                    )
                if not stat.S_ISDIR(named.st_mode):
                    raise evidence.EvidenceError(
                        evidence.EvidenceErrorCode.UNAVAILABLE
                    )
                child_descriptor = (
                    _create_private_child(parent_descriptor, component)
                    if create
                    else _open_private_child(parent_descriptor, component)
                )
            os.close(parent_descriptor)
            parent_descriptor = child_descriptor
        return parent_descriptor
    except BaseException:
        os.close(parent_descriptor)
        raise


def _ensure_private_directory(
    path: Path,
    *,
    create: bool,
    root: Path | None = None,
    missing_ok: bool = False,
) -> os.stat_result | None:
    """Return a private directory after descriptor-relative validation.

    When ``root`` is supplied, every component from that evidence root to
    ``path`` is opened relative to its verified parent. A missing path is
    created one component at a time and each new parent entry is synchronized
    before its child is used. Components above the evidence root retain their
    existing ownership policy. With create=False, missing_ok=True returns None
    only when the path is absent; an inaccessible or incorrectly typed path
    raises an evidence error.
    """

    descriptor = _open_private_path(
        path if root is None else root,
        path,
        create=create,
        missing_ok=missing_ok,
    )
    if descriptor < 0:
        return None
    try:
        return os.fstat(descriptor)
    finally:
        os.close(descriptor)


def _directory_descriptor(path: Path, *, root: Path | None = None) -> int:
    """Return a verified private directory descriptor."""

    return _open_private_path(path if root is None else root, path, create=False)


def _fsync_directory(descriptor: int) -> None:
    try:
        os.fsync(descriptor)
    except OSError:
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNAVAILABLE) from None


def _fsync_private_directory(path: Path, *, root: Path | None = None) -> None:
    """Synchronize one validated directory's entries."""

    descriptor = _directory_descriptor(path, root=root)
    try:
        _fsync_directory(descriptor)
    finally:
        os.close(descriptor)


def _read_private_file(
    directory: Path,
    name: str,
    *,
    root: Path | None = None,
) -> bytes:
    """Read one private entry, distinguishing a missing name from I/O failure.

    `_MissingPrivateFile` means the named entry did not exist at the observed
    operation. Permission, path-identity, and other operating-system failures
    raise stable evidence errors so callers cannot mistake uncertain state for
    absence.
    """

    if "/" in name or name in ("", ".", ".."):
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNSAFE_PATH)
    directory_descriptor = _directory_descriptor(directory, root=root)
    descriptor = -1
    try:
        try:
            named = os.stat(name, dir_fd=directory_descriptor, follow_symlinks=False)
            descriptor = os.open(
                name,
                os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0),
                dir_fd=directory_descriptor,
            )
            opened = os.fstat(descriptor)
        except FileNotFoundError:
            raise _MissingPrivateFile from None
        except OSError:
            raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNAVAILABLE) from None
        if (
            not stat.S_ISREG(opened.st_mode)
            or opened.st_uid != os.geteuid()
            or stat.S_IMODE(opened.st_mode) != 0o600
            or opened.st_nlink != 1
            or (opened.st_dev, opened.st_ino) != (named.st_dev, named.st_ino)
        ):
            raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNSAFE_PATH)
        if opened.st_size > MAX_RECORD_BYTES:
            raise evidence.EvidenceError(evidence.EvidenceErrorCode.INVALID_INPUT)
        chunks: list[bytes] = []
        total = 0
        try:
            while True:
                chunk = os.read(descriptor, min(64 * 1024, MAX_RECORD_BYTES + 1 - total))
                if not chunk:
                    break
                chunks.append(chunk)
                total += len(chunk)
                if total > MAX_RECORD_BYTES:
                    raise evidence.EvidenceError(evidence.EvidenceErrorCode.INVALID_INPUT)
            after = os.fstat(descriptor)
        except OSError:
            raise evidence.EvidenceError(
                evidence.EvidenceErrorCode.UNAVAILABLE
            ) from None
        if (
            (opened.st_dev, opened.st_ino, opened.st_size, opened.st_mtime_ns, opened.st_ctime_ns)
            != (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns, after.st_ctime_ns)
        ):
            raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNSAFE_PATH)
        return b"".join(chunks)
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        os.close(directory_descriptor)


@contextlib.contextmanager
def _stream_lock(
    directory: Path,
    *,
    root: Path | None = None,
    lock_name: str = ".execution.lock",
) -> Iterator[None]:
    descriptor = -1
    directory_descriptor = _directory_descriptor(directory, root=root)
    try:
        try:
            descriptor = os.open(
                lock_name,
                os.O_RDWR | os.O_CREAT | getattr(os, "O_NOFOLLOW", 0),
                0o600,
                dir_fd=directory_descriptor,
            )
            info = os.fstat(descriptor)
            named = os.stat(lock_name, dir_fd=directory_descriptor, follow_symlinks=False)
        except OSError:
            raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNSAFE_PATH) from None
        if (
            not stat.S_ISREG(info.st_mode)
            or info.st_uid != os.geteuid()
            or stat.S_IMODE(info.st_mode) != 0o600
            or info.st_nlink != 1
            or (info.st_dev, info.st_ino) != (named.st_dev, named.st_ino)
        ):
            raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNSAFE_PATH)
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as error:
            if error.errno in (errno.EACCES, errno.EAGAIN):
                raise evidence.EvidenceError(evidence.EvidenceErrorCode.BUSY) from None
            raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNAVAILABLE) from None
        yield
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        os.close(directory_descriptor)


def _publish_no_replace(
    directory: Path,
    temporary_name: str,
    final_name: str,
    encoded: bytes,
    *,
    root: Path | None = None,
    stage_prefix: str = "",
) -> None:
    directory_descriptor = _directory_descriptor(directory, root=root)
    descriptor = -1
    try:
        try:
            descriptor = os.open(
                temporary_name,
                os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0),
                0o600,
                dir_fd=directory_descriptor,
            )
        except OSError:
            raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNAVAILABLE) from None
        _transition(f"{stage_prefix}before_temp_sync")
        view = memoryview(encoded)
        while view:
            try:
                written = os.write(descriptor, view)
            except OSError:
                raise evidence.EvidenceError(
                    evidence.EvidenceErrorCode.UNAVAILABLE
                ) from None
            if written <= 0:
                raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNAVAILABLE)
            view = view[written:]
        _fsync_directory(descriptor)
        _transition(f"{stage_prefix}after_temp_sync")
        try:
            opened = os.fstat(descriptor)
            named = os.stat(
                temporary_name,
                dir_fd=directory_descriptor,
                follow_symlinks=False,
            )
        except OSError:
            raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNAVAILABLE) from None
        if (
            not stat.S_ISREG(opened.st_mode)
            or opened.st_uid != os.geteuid()
            or stat.S_IMODE(opened.st_mode) != 0o600
            or opened.st_nlink != 1
            or (opened.st_dev, opened.st_ino) != (named.st_dev, named.st_ino)
        ):
            raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNSAFE_PATH)
        _transition(f"{stage_prefix}before_publish")
        try:
            _rename_entry_no_replace(
                directory_descriptor,
                temporary_name,
                final_name,
            )
        except FileExistsError:
            raise
        except OSError:
            raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNAVAILABLE) from None
        _transition(f"{stage_prefix}after_publish_before_parent_sync")
        try:
            published = os.stat(
                final_name,
                dir_fd=directory_descriptor,
                follow_symlinks=False,
            )
        except OSError:
            raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNAVAILABLE) from None
        if (published.st_dev, published.st_ino) != (opened.st_dev, opened.st_ino):
            raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNSAFE_PATH)
        _fsync_directory(directory_descriptor)
        _transition(f"{stage_prefix}after_parent_sync")
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        os.close(directory_descriptor)


def _rename_entry_no_replace(
    directory_descriptor: int,
    temporary_name: str,
    final_name: str,
) -> None:
    """Atomically publish one directory entry without replacing a pathname."""

    source = os.fsencode(temporary_name)
    destination = os.fsencode(final_name)
    libc = ctypes.CDLL(None, use_errno=True)
    if sys.platform == "darwin":
        operation = getattr(libc, "renameatx_np", None)
        flags = 0x00000004
    elif sys.platform.startswith("linux"):
        operation = getattr(libc, "renameat2", None)
        flags = 1
    else:
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNAVAILABLE)
    if operation is None:
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNAVAILABLE)
    operation.argtypes = (
        ctypes.c_int,
        ctypes.c_char_p,
        ctypes.c_int,
        ctypes.c_char_p,
        ctypes.c_uint,
    )
    operation.restype = ctypes.c_int
    if (
        operation(
            directory_descriptor,
            source,
            directory_descriptor,
            destination,
            flags,
        )
        != 0
    ):
        error_number = ctypes.get_errno()
        if error_number == errno.EEXIST:
            raise FileExistsError(
                error_number,
                os.strerror(error_number),
            )
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNAVAILABLE)


def _record_name(sequence: int) -> str:
    return f"record-{sequence:08d}.json"


def _record_pattern(name: str) -> int | None:
    match = re.fullmatch(r"record-(\d{8})\.json", name)
    if match is None:
        return None
    sequence = int(match.group(1))
    if sequence < 1 or _record_name(sequence) != name:
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.CORRUPT)
    return sequence


def _parse_record(raw: bytes, *, session_id: str, sequence: int) -> tuple[dict[str, Any], str]:
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.INVALID_INPUT) from None
    try:
        document = json.loads(
            text,
            object_pairs_hook=_object_without_duplicate_keys,
            parse_float=_reject_float,
            parse_constant=_reject_non_finite,
        )
    except _DuplicateKey:
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.DUPLICATE_KEY) from None
    except _FloatingPoint:
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.FLOAT_REJECTED) from None
    except _NonFinite:
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.NON_FINITE_NUMBER) from None
    except (json.JSONDecodeError, RecursionError, ValueError):
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.INVALID_INPUT) from None
    if type(document) is not dict:
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.CORRUPT)
    if raw != _canonical_bytes(document):
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.CORRUPT)
    supplied = set(document)
    expected = {
        "schema_version",
        "session_id",
        "sequence",
        "previous_record_sha256",
        "event",
        "event_sha256",
        "record_sha256",
    }
    if supplied != expected:
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.CORRUPT)
    if type(document["schema_version"]) is not int:
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.CORRUPT)
    if document["schema_version"] != SCHEMA_VERSION:
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNSUPPORTED_SCHEMA)
    if (
        document["session_id"] != session_id
        or type(document["sequence"]) is not int
        or document["sequence"] != sequence
    ):
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.CORRUPT)
    digest_document = dict(document)
    record_sha256 = _require_sha256(digest_document.pop("record_sha256"))
    if _canonical_sha256(digest_document) != record_sha256:
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.CORRUPT)
    if _canonical_sha256(document["event"]) != document["event_sha256"]:
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.CORRUPT)
    return document, record_sha256


def _stored_invalid() -> NoReturn:
    raise evidence.EvidenceError(evidence.EvidenceErrorCode.CORRUPT)


def _stored_ref(value: object, *, kind: str) -> str:
    try:
        return _require_opaque_ref(value, kind=kind)
    except evidence.EvidenceError:
        _stored_invalid()


def _stored_operation_id(value: object) -> str:
    if type(value) is str and value.startswith(_INTERNAL_OPERATION_PREFIX):
        try:
            return _require_internal_operation_id(value)
        except evidence.EvidenceError:
            _stored_invalid()
    return _stored_ref(value, kind="operation")


def _stored_sha256(value: object) -> str:
    if type(value) is not str or _SHA256.fullmatch(value) is None:
        _stored_invalid()
    return value


def _stored_version(value: object) -> str:
    try:
        return _require_version(value)
    except evidence.EvidenceError:
        _stored_invalid()


def _stored_timestamp(value: object) -> str:
    """Validate a persisted UTC timestamp and map failures to corruption."""

    try:
        return _require_timestamp(value)
    except evidence.EvidenceError:
        _stored_invalid()


def _stored_enum(value: object, enum_type: type[Any]) -> str:
    """Validate a persisted enum string without accepting coercible values."""

    if type(value) is not str or value not in {item.value for item in enum_type}:
        _stored_invalid()
    return value


def _stored_integer(value: object, *, positive: bool = False) -> int:
    if type(value) is not int or (positive and value < 1):
        _stored_invalid()
    return value


def _stored_provenance(value: object) -> None:
    if type(value) is not dict or set(value) != {
        "artifact",
        "authorization",
        "environment",
        "fixtures",
        "plan",
        "review_requirements",
        "rules",
    }:
        _stored_invalid()
    artifact = value["artifact"]
    authorization = value["authorization"]
    environment = value["environment"]
    fixtures = value["fixtures"]
    plan = value["plan"]
    requirements = value["review_requirements"]
    rules = value["rules"]
    if type(artifact) is not dict or set(artifact) != {
        "artifact_class",
        "artifact_ref",
        "artifact_sha256",
    }:
        _stored_invalid()
    _stored_enum(artifact["artifact_class"], evidence.ArtifactClass)
    _stored_ref(artifact["artifact_ref"], kind="artifact")
    _stored_sha256(artifact["artifact_sha256"])
    if type(authorization) is not dict or set(authorization) != {
        "manifest_sha256",
        "manifest_version",
    }:
        _stored_invalid()
    _stored_sha256(authorization["manifest_sha256"])
    _stored_integer(authorization["manifest_version"], positive=True)
    if type(fixtures) is not dict or set(fixtures) != {
        "corpus_ref",
        "manifest_sha256",
        "manifest_version",
    }:
        _stored_invalid()
    _stored_ref(fixtures["corpus_ref"], kind="corpus")
    _stored_sha256(fixtures["manifest_sha256"])
    _stored_integer(fixtures["manifest_version"], positive=True)
    if type(plan) is not dict or set(plan) != {
        "plan_ref",
        "plan_sha256",
        "plan_version",
    }:
        _stored_invalid()
    _stored_ref(plan["plan_ref"], kind="plan")
    _stored_sha256(plan["plan_sha256"])
    _stored_integer(plan["plan_version"], positive=True)
    if type(rules) is not dict or set(rules) != {
        "rules_ref",
        "rules_sha256",
        "rules_version",
    }:
        _stored_invalid()
    _stored_ref(rules["rules_ref"], kind="rules")
    _stored_sha256(rules["rules_sha256"])
    _stored_version(rules["rules_version"])
    if type(environment) is not dict or set(environment) != {
        "environment_ref",
        "platform",
        "platform_version",
        "target_ref",
    }:
        _stored_invalid()
    _stored_enum(environment["platform"], evidence.Platform)
    _stored_ref(environment["environment_ref"], kind="environment")
    _stored_ref(environment["platform_version"], kind="platform-version")
    _stored_ref(environment["target_ref"], kind="target")
    if type(requirements) is not dict or set(requirements) != {
        "direct_owner_observation_allowed",
        "objective_review_allowed",
        "required_evidence_refs",
        "retrospective_allowed",
    }:
        _stored_invalid()
    for key in (
        "direct_owner_observation_allowed",
        "objective_review_allowed",
        "retrospective_allowed",
    ):
        if type(requirements[key]) is not bool:
            _stored_invalid()
    refs = requirements["required_evidence_refs"]
    if type(refs) is not list or len(refs) > 32:
        _stored_invalid()
    normalized = [_stored_ref(item, kind="evidence") for item in refs]
    if len(set(normalized)) != len(normalized):
        _stored_invalid()


def _validate_stored_event(event: dict[str, Any], *, sequence: int) -> None:
    event_type = event.get("event_type")
    common = {"event_type", "occurred_at", "operation_id"}
    if event_type == "session_opened":
        expected = common | {"provenance", "scenario_id"}
    elif event_type == "assertion":
        expected = common | {
            "actual_outcome",
            "assertion_ref",
            "evidence_refs",
            "expected_outcome",
            "measurements",
            "observed_at",
            "rules_ref",
            "rules_sha256",
            "rules_version",
        }
    elif event_type == "lifecycle":
        expected = common | {"evidence_refs", "lifecycle"}
    elif event_type == "terminal":
        expected = common | {"ended_at", "evidence_refs", "outcome", "reason"}
    else:
        _stored_invalid()
    if set(event) != expected:
        _stored_invalid()
    occurred_at = _stored_timestamp(event["occurred_at"])
    operation_id = event["operation_id"]
    if operation_id == _RECOVERY_OPERATION_ID:
        _stored_operation_id(operation_id)
        if (
            event_type != "terminal"
            or event["outcome"] != evidence.TerminalOutcome.INTERRUPTED.value
            or event["reason"] != evidence.TerminalReason.RECOVERY_ABANDONED.value
        ):
            _stored_invalid()
    else:
        _stored_ref(operation_id, kind="operation")
    if event_type == "session_opened":
        if sequence != 1:
            _stored_invalid()
        _stored_ref(event["scenario_id"], kind="scenario")
        _stored_provenance(event["provenance"])
        return
    if sequence == 1:
        _stored_invalid()
    evidence_refs = event["evidence_refs"]
    if type(evidence_refs) is not list or len(evidence_refs) > 32:
        _stored_invalid()
    normalized_refs = [_stored_ref(value, kind="evidence") for value in evidence_refs]
    if len(set(normalized_refs)) != len(normalized_refs):
        _stored_invalid()
    if event_type == "lifecycle":
        _stored_enum(event["lifecycle"], evidence.Lifecycle)
        return
    if event_type == "terminal":
        _stored_enum(event["outcome"], evidence.TerminalOutcome)
        _stored_enum(event["reason"], evidence.TerminalReason)
        ended_at = _stored_timestamp(event["ended_at"])
        if ended_at > occurred_at:
            _stored_invalid()
        return
    _stored_enum(event["expected_outcome"], evidence.AssertionOutcome)
    _stored_enum(event["actual_outcome"], evidence.AssertionOutcome)
    _stored_ref(event["assertion_ref"], kind="assertion")
    _stored_ref(event["rules_ref"], kind="rules")
    _stored_sha256(event["rules_sha256"])
    _stored_version(event["rules_version"])
    observed_at = _stored_timestamp(event["observed_at"])
    if observed_at > occurred_at:
        _stored_invalid()
    measurements = event["measurements"]
    if type(measurements) is not list or len(measurements) > 32:
        _stored_invalid()
    measurement_names: set[str] = set()
    for measurement in measurements:
        if type(measurement) is not dict:
            _stored_invalid()
        if set(measurement) != {"name", "unit", "value"}:
            _stored_invalid()
        name = _stored_ref(measurement["name"], kind="measurement")
        if name in measurement_names:
            _stored_invalid()
        measurement_names.add(name)
        _stored_enum(measurement["unit"], evidence.MeasurementUnit)
        value = measurement["value"]
        if type(value) is not int or not -(10**15) <= value <= 10**15:
            _stored_invalid()


def _validate_appendable_event(event: dict[str, object], *, sequence: int) -> None:
    """Validate a fully assembled event before it enters the record chain."""
    try:
        _validate_stored_event(event, sequence=sequence)
    except evidence.EvidenceError:
        _invalid()


def _load_chain(
    directory: Path,
    session_id: str,
    *,
    root: Path,
) -> list[tuple[dict[str, Any], str]]:
    directory_descriptor = _directory_descriptor(directory, root=root)
    try:
        names = os.listdir(directory_descriptor)
    except OSError:
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNAVAILABLE) from None
    finally:
        os.close(directory_descriptor)
    record_names: list[tuple[int, str]] = []
    for name in names:
        sequence = _record_pattern(name)
        if sequence is not None:
            record_names.append((sequence, name))
        elif (
            name not in {".execution.lock", "manifest.json"}
            and _TEMPORARY_RECORD.fullmatch(name) is None
            and _TEMPORARY_MANIFEST.fullmatch(name) is None
        ):
            raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNSAFE_PATH)
    record_names.sort()
    if not record_names:
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.CORRUPT)
    chain: list[tuple[dict[str, Any], str]] = []
    previous: str | None = None
    prior_occurred_at: str | None = None
    operation_ids: set[str] = set()
    terminal_seen = False
    opened_event: dict[str, Any] | None = None
    for expected_sequence, (observed_sequence, name) in enumerate(record_names, start=1):
        if observed_sequence != expected_sequence:
            raise evidence.EvidenceError(evidence.EvidenceErrorCode.CORRUPT)
        try:
            raw = _read_private_file(directory, name, root=root)
        except _MissingPrivateFile:
            raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNAVAILABLE) from None
        record, digest = _parse_record(raw, session_id=session_id, sequence=expected_sequence)
        if record["previous_record_sha256"] != previous:
            raise evidence.EvidenceError(evidence.EvidenceErrorCode.CORRUPT)
        event = record["event"]
        if type(event) is not dict:
            raise evidence.EvidenceError(evidence.EvidenceErrorCode.CORRUPT)
        if terminal_seen:
            raise evidence.EvidenceError(evidence.EvidenceErrorCode.CORRUPT)
        _validate_stored_event(event, sequence=expected_sequence)
        if expected_sequence == 1:
            opened_event = event
        elif event["event_type"] == "assertion":
            if opened_event is None:
                raise evidence.EvidenceError(evidence.EvidenceErrorCode.CORRUPT)
            pinned_rules = opened_event["provenance"]["rules"]
            if (
                event["rules_ref"] != pinned_rules["rules_ref"]
                or event["rules_version"] != pinned_rules["rules_version"]
                or event["rules_sha256"] != pinned_rules["rules_sha256"]
            ):
                raise evidence.EvidenceError(evidence.EvidenceErrorCode.CORRUPT)
        terminal_seen = event["event_type"] == "terminal"
        occurred_at = event.get("occurred_at")
        occurred_at = _stored_timestamp(occurred_at)
        if prior_occurred_at is not None and occurred_at < prior_occurred_at:
            raise evidence.EvidenceError(evidence.EvidenceErrorCode.CORRUPT)
        operation_id = event.get("operation_id")
        if type(operation_id) is not str or operation_id in operation_ids:
            raise evidence.EvidenceError(evidence.EvidenceErrorCode.CORRUPT)
        operation_ids.add(operation_id)
        previous = digest
        prior_occurred_at = occurred_at
        chain.append((record, digest))
    return chain


def _append_event(
    session_directory: Path,
    session_id: str,
    event: dict[str, object],
    request: evidence.WriteRequest,
    *,
    root: Path,
    acquire_lock: bool = True,
    internal_operation: bool = False,
) -> evidence.AppendReceipt:
    if type(request) is not evidence.WriteRequest:
        _invalid()
    operation_id = (
        _require_internal_operation_id(request.operation_id)
        if internal_operation
        else _require_caller_operation_id(request.operation_id)
    )
    occurred_at = (
        _now_timestamp() if request.occurred_at is None else _require_timestamp(request.occurred_at)
    )
    event["occurred_at"] = occurred_at
    event["operation_id"] = operation_id
    expected_head = request.expected_head_sha256
    if expected_head is not None:
        _require_sha256(expected_head)
    lock = (
        _stream_lock(session_directory, root=root)
        if acquire_lock
        else contextlib.nullcontext()
    )
    with lock:
        chain = _load_chain(session_directory, session_id, root=root)
        if event.get("event_type") == "assertion":
            provenance = chain[0][0]["event"]["provenance"]
            pinned_rules = provenance["rules"]
            if (
                event.get("rules_ref") != pinned_rules.get("rules_ref")
                or event.get("rules_version") != pinned_rules.get("rules_version")
                or event.get("rules_sha256") != pinned_rules.get("rules_sha256")
            ):
                _invalid()
        for record, digest in chain:
            existing_event = record["event"]
            if existing_event.get("operation_id") == operation_id:
                comparable = dict(existing_event)
                comparable.pop("occurred_at", None)
                requested = dict(event)
                requested.pop("occurred_at", None)
                if comparable != requested:
                    raise evidence.EvidenceError(evidence.EvidenceErrorCode.OPERATION_CONFLICT)
                _fsync_private_directory(session_directory, root=root)
                return evidence.AppendReceipt(
                    operation_id=operation_id,
                    session_id=session_id,
                    sequence=int(record["sequence"]),
                    record_sha256=digest,
                    head_sha256=digest,
                    idempotent=True,
                )
        if any(record["event"].get("event_type") == "terminal" for record, _digest in chain):
            raise evidence.EvidenceError(evidence.EvidenceErrorCode.FINALIZED)
        head = chain[-1][1]
        if expected_head is not None and expected_head != head:
            raise evidence.EvidenceError(evidence.EvidenceErrorCode.EXPECTED_HEAD_CONFLICT)
        sequence = len(chain) + 1
        prior_occurred_at = chain[-1][0]["event"]["occurred_at"]
        if occurred_at < prior_occurred_at:
            _invalid()
        _validate_appendable_event(event, sequence=sequence)
        record: dict[str, object] = {
            "schema_version": SCHEMA_VERSION,
            "session_id": session_id,
            "sequence": sequence,
            "previous_record_sha256": head,
            "event": event,
            "event_sha256": _canonical_sha256(event),
        }
        record["record_sha256"] = _canonical_sha256(record)
        encoded = _canonical_bytes(record)
        final_name = _record_name(sequence)
        temporary_name = f".record-{sequence:08d}.tmp-{secrets.token_hex(16)}"
        try:
            _publish_no_replace(
                session_directory,
                temporary_name,
                final_name,
                encoded,
                root=root,
            )
        except FileExistsError:
            raise evidence.EvidenceError(
                evidence.EvidenceErrorCode.EXPECTED_HEAD_CONFLICT
            ) from None
        digest = str(record["record_sha256"])
        return evidence.AppendReceipt(
            operation_id=operation_id,
            session_id=session_id,
            sequence=sequence,
            record_sha256=digest,
            head_sha256=digest,
            idempotent=False,
        )


def _measurements_document(
    measurements: tuple[evidence.Measurement, ...],
) -> list[dict[str, object]]:
    if type(measurements) is not tuple or len(measurements) > 32:
        _invalid()
    result: list[dict[str, object]] = []
    names: set[str] = set()
    for measurement in measurements:
        if type(measurement) is not evidence.Measurement:
            _invalid()
        name = _require_opaque_ref(measurement.name, kind="measurement")
        if (
            name in names
            or type(measurement.value) is not int
            or not -(10**15) <= measurement.value <= 10**15
        ):
            _invalid()
        if type(measurement.unit) is not evidence.MeasurementUnit:
            _invalid()
        names.add(name)
        result.append(
            {
                "name": name,
                "unit": measurement.unit.value,
                "value": measurement.value,
            }
        )
    return result


def _evidence_refs_document(value: object) -> list[str]:
    if type(value) is not tuple or len(value) > 32:
        _invalid()
    refs = [_require_opaque_ref(item, kind="evidence") for item in value]
    if len(set(refs)) != len(refs):
        _invalid()
    return refs


def _manifest_document(
    session_id: str,
    chain: list[tuple[dict[str, Any], str]],
) -> dict[str, object]:
    opened = chain[0][0]["event"]
    terminal_record, terminal_digest = chain[-1]
    terminal = terminal_record["event"]
    if opened.get("event_type") != "session_opened" or terminal.get("event_type") != "terminal":
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.CORRUPT)
    document: dict[str, object] = {
        "schema_version": SCHEMA_VERSION,
        "session_id": session_id,
        "scenario_id": opened["scenario_id"],
        "provenance": opened["provenance"],
        "record_count": len(chain),
        "head_sha256": terminal_digest,
        "terminal_sequence": len(chain),
        "terminal_record_sha256": terminal_digest,
    }
    document["manifest_sha256"] = _canonical_sha256(document)
    return document


def _parse_manifest(
    raw: bytes,
    *,
    session_id: str,
    chain: list[tuple[dict[str, Any], str]],
) -> tuple[dict[str, Any], str]:
    try:
        document = json.loads(
            raw.decode("utf-8"),
            object_pairs_hook=_object_without_duplicate_keys,
            parse_float=_reject_float,
            parse_constant=_reject_non_finite,
        )
    except _DuplicateKey:
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.DUPLICATE_KEY) from None
    except _FloatingPoint:
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.FLOAT_REJECTED) from None
    except _NonFinite:
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.NON_FINITE_NUMBER) from None
    except (UnicodeDecodeError, json.JSONDecodeError, RecursionError, ValueError):
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.MANIFEST_MISMATCH) from None
    if type(document) is not dict or raw != _canonical_bytes(document):
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.MANIFEST_MISMATCH)
    expected = {
        "schema_version",
        "session_id",
        "scenario_id",
        "provenance",
        "record_count",
        "head_sha256",
        "terminal_sequence",
        "terminal_record_sha256",
        "manifest_sha256",
    }
    if set(document) != expected:
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.MANIFEST_MISMATCH)
    if type(document["schema_version"]) is not int:
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.MANIFEST_MISMATCH)
    if document["schema_version"] != SCHEMA_VERSION:
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNSUPPORTED_SCHEMA)
    if (
        type(document["record_count"]) is not int
        or type(document["terminal_sequence"]) is not int
    ):
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.MANIFEST_MISMATCH)
    digest_document = dict(document)
    digest = digest_document.pop("manifest_sha256")
    if type(digest) is not str or _SHA256.fullmatch(digest) is None:
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.MANIFEST_MISMATCH)
    if _canonical_sha256(digest_document) != digest:
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.MANIFEST_MISMATCH)
    if document != _manifest_document(session_id, chain):
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.MANIFEST_MISMATCH)
    return document, digest


def _verify_execution_locked(
    session_directory: Path,
    session_id: str,
    chain: list[tuple[dict[str, Any], str]],
    *,
    root: Path,
) -> evidence.ExecutionManifest:
    """Verify an already loaded chain and manifest with its lock held."""

    if chain[-1][0]["event"].get("event_type") != "terminal":
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.MANIFEST_MISSING)
    try:
        raw = _read_private_file(
            session_directory,
            "manifest.json",
            root=root,
        )
    except _MissingPrivateFile:
        raise evidence.EvidenceError(
            evidence.EvidenceErrorCode.MANIFEST_MISSING
        ) from None
    document, digest = _parse_manifest(raw, session_id=session_id, chain=chain)
    return evidence.ExecutionManifest(
        session_id=session_id,
        scenario_id=str(document["scenario_id"]),
        record_count=int(document["record_count"]),
        head_sha256=str(document["head_sha256"]),
        terminal_record_sha256=str(document["terminal_record_sha256"]),
        manifest_sha256=digest,
    )


def _finalize_manifest(
    session_directory: Path,
    session_id: str,
    chain: list[tuple[dict[str, Any], str]],
    *,
    root: Path,
) -> str:
    name = "manifest.json"
    try:
        raw = _read_private_file(session_directory, name, root=root)
    except _MissingPrivateFile:
        pass
    else:
        _document, digest = _parse_manifest(raw, session_id=session_id, chain=chain)
        _fsync_private_directory(session_directory, root=root)
        return digest
    _transition("manifest_before_publication")
    document = _manifest_document(session_id, chain)
    try:
        _publish_no_replace(
            session_directory,
            f".manifest.tmp-{secrets.token_hex(16)}",
            name,
            _canonical_bytes(document),
            root=root,
            stage_prefix="manifest_",
        )
    except FileExistsError:
        raw = _read_private_file(session_directory, name, root=root)
        _document, digest = _parse_manifest(raw, session_id=session_id, chain=chain)
        _fsync_private_directory(session_directory, root=root)
        return digest
    _transition("manifest_before_ack")
    return str(document["manifest_sha256"])


def _provenance_document(spec: evidence.SessionSpec) -> dict[str, object]:
    if type(spec) is not evidence.SessionSpec:
        _invalid()
    if type(spec.artifact) is not evidence.ArtifactPin:
        _invalid()
    if type(spec.artifact.artifact_class) is not evidence.ArtifactClass:
        _invalid()
    if type(spec.authorization) is not evidence.AuthorizationPin:
        _invalid()
    if type(spec.fixtures) is not evidence.FixturePin:
        _invalid()
    if type(spec.plan) is not evidence.PlanPin:
        _invalid()
    if type(spec.rules) is not evidence.AcceptanceRulesPin:
        _invalid()
    if type(spec.environment) is not evidence.EnvironmentPin:
        _invalid()
    if type(spec.environment.platform) is not evidence.Platform:
        _invalid()
    if type(spec.review_requirements) is not evidence.ReviewRequirements:
        _invalid()
    required_refs = spec.review_requirements.required_evidence_refs
    if type(required_refs) is not tuple or len(required_refs) > 32:
        _invalid()
    normalized_refs = tuple(
        _require_opaque_ref(value, kind="evidence") for value in required_refs
    )
    if len(set(normalized_refs)) != len(normalized_refs):
        _invalid()
    for value in (
        spec.review_requirements.objective_review_allowed,
        spec.review_requirements.direct_owner_observation_allowed,
        spec.review_requirements.retrospective_allowed,
    ):
        if type(value) is not bool:
            _invalid()
    return {
        "artifact": {
            "artifact_class": spec.artifact.artifact_class.value,
            "artifact_ref": _require_opaque_ref(
                spec.artifact.artifact_ref, kind="artifact"
            ),
            "artifact_sha256": _require_sha256(spec.artifact.artifact_sha256),
        },
        "authorization": {
            "manifest_sha256": _require_sha256(spec.authorization.manifest_sha256),
            "manifest_version": _require_positive_integer(spec.authorization.manifest_version),
        },
        "environment": {
            "environment_ref": _require_opaque_ref(
                spec.environment.environment_ref, kind="environment"
            ),
            "platform": spec.environment.platform.value,
            "platform_version": _require_opaque_ref(
                spec.environment.platform_version, kind="platform-version"
            ),
            "target_ref": _require_opaque_ref(
                spec.environment.target_ref, kind="target"
            ),
        },
        "fixtures": {
            "corpus_ref": _require_opaque_ref(
                spec.fixtures.corpus_ref, kind="corpus"
            ),
            "manifest_sha256": _require_sha256(spec.fixtures.manifest_sha256),
            "manifest_version": _require_positive_integer(spec.fixtures.manifest_version),
        },
        "plan": {
            "plan_ref": _require_opaque_ref(spec.plan.plan_ref, kind="plan"),
            "plan_sha256": _require_sha256(spec.plan.plan_sha256),
            "plan_version": _require_positive_integer(spec.plan.plan_version),
        },
        "review_requirements": {
            "direct_owner_observation_allowed": spec.review_requirements.direct_owner_observation_allowed,
            "objective_review_allowed": spec.review_requirements.objective_review_allowed,
            "required_evidence_refs": list(normalized_refs),
            "retrospective_allowed": spec.review_requirements.retrospective_allowed,
        },
        "rules": {
            "rules_ref": _require_opaque_ref(spec.rules.rules_ref, kind="rules"),
            "rules_sha256": _require_sha256(spec.rules.rules_sha256),
            "rules_version": _require_version(spec.rules.rules_version),
        },
    }


class ExecutionWriter:
    """Append typed observations to immutable execution record streams."""

    def __init__(self, root: Path) -> None:
        self._root = root

    def _session_directory(self, session_id: str) -> Path:
        return self._root / "executions" / _require_session_id(session_id)

    def open_session(
        self,
        spec: evidence.SessionSpec,
        request: evidence.WriteRequest,
    ) -> evidence.AppendReceipt:
        """Create an execution session or return its receipt on exact replay."""
        if type(spec) is not evidence.SessionSpec or type(request) is not evidence.WriteRequest:
            _invalid()
        if request.expected_head_sha256 is not None:
            _invalid()
        session_id = _require_session_id(spec.session_id)
        operation_id = _require_caller_operation_id(request.operation_id)
        _ensure_private_directory(self._root, create=True, root=self._root)
        executions = self._root / "executions"
        _ensure_private_directory(executions, create=True, root=self._root)
        session_directory = self._session_directory(session_id)
        _ensure_private_directory(session_directory, create=True, root=self._root)
        occurred_at = (
            _now_timestamp() if request.occurred_at is None else _require_timestamp(request.occurred_at)
        )
        event = {
            "event_type": "session_opened",
            "occurred_at": occurred_at,
            "operation_id": operation_id,
            "provenance": _provenance_document(spec),
            "scenario_id": _require_opaque_ref(spec.scenario_id, kind="scenario"),
        }
        with _stream_lock(session_directory, root=self._root):
            final_name = _record_name(1)
            try:
                existing_raw = _read_private_file(
                    session_directory,
                    final_name,
                    root=self._root,
                )
            except _MissingPrivateFile:
                pass
            else:
                existing, existing_digest = _parse_record(
                    existing_raw, session_id=session_id, sequence=1
                )
                if (
                    existing["event"].get("event_type") == "session_opened"
                    and existing["event"].get("operation_id") == operation_id
                    and existing["event"].get("provenance") == event["provenance"]
                    and existing["event"].get("scenario_id") == event["scenario_id"]
                ):
                    chain = _load_chain(
                        session_directory, session_id, root=self._root
                    )
                    original, original_digest = chain[0]
                    if original != existing or original_digest != existing_digest:
                        raise evidence.EvidenceError(
                            evidence.EvidenceErrorCode.CORRUPT
                        )
                    _fsync_private_directory(session_directory, root=self._root)
                    return evidence.AppendReceipt(
                        operation_id=operation_id,
                        session_id=session_id,
                        sequence=1,
                        record_sha256=original_digest,
                        head_sha256=original_digest,
                        idempotent=True,
                    )
                raise evidence.EvidenceError(evidence.EvidenceErrorCode.OPERATION_CONFLICT)
            record: dict[str, object] = {
                "schema_version": SCHEMA_VERSION,
                "session_id": session_id,
                "sequence": 1,
                "previous_record_sha256": None,
                "event": event,
                "event_sha256": _canonical_sha256(event),
            }
            record["record_sha256"] = _canonical_sha256(record)
            encoded = _canonical_bytes(record)
            temporary_name = f".record-00000001.tmp-{secrets.token_hex(16)}"
            try:
                _publish_no_replace(
                    session_directory,
                    temporary_name,
                    final_name,
                    encoded,
                    root=self._root,
                )
            except FileExistsError:
                raise evidence.EvidenceError(
                    evidence.EvidenceErrorCode.EXPECTED_HEAD_CONFLICT
                ) from None
            record_digest = str(record["record_sha256"])
            return evidence.AppendReceipt(
                operation_id=operation_id,
                session_id=session_id,
                sequence=1,
                record_sha256=record_digest,
                head_sha256=record_digest,
                idempotent=False,
            )

    def append_assertion(
        self,
        session_id: str,
        observation: evidence.AssertionObservation,
        request: evidence.WriteRequest,
    ) -> evidence.AppendReceipt:
        """Append one typed assertion observation to an open session."""

        session_id = _require_session_id(session_id)
        if type(observation) is not evidence.AssertionObservation:
            _invalid()
        if type(observation.expected_outcome) is not evidence.AssertionOutcome:
            _invalid()
        if type(observation.actual_outcome) is not evidence.AssertionOutcome:
            _invalid()
        if type(observation.evidence_refs) is not tuple or len(observation.evidence_refs) > 32:
            _invalid()
        evidence_refs = [
            _require_opaque_ref(value, kind="evidence")
            for value in observation.evidence_refs
        ]
        if len(set(evidence_refs)) != len(evidence_refs):
            _invalid()
        event: dict[str, object] = {
            "actual_outcome": observation.actual_outcome.value,
            "assertion_ref": _require_opaque_ref(
                observation.assertion_ref, kind="assertion"
            ),
            "event_type": "assertion",
            "evidence_refs": evidence_refs,
            "expected_outcome": observation.expected_outcome.value,
            "measurements": _measurements_document(observation.measurements),
            "observed_at": _require_timestamp(observation.observed_at),
            "rules_ref": _require_opaque_ref(
                observation.rules_ref, kind="rules"
            ),
            "rules_sha256": _require_sha256(observation.rules_sha256),
            "rules_version": _require_version(observation.rules_version),
        }
        return _append_event(
            self._session_directory(session_id),
            session_id,
            event,
            request,
            root=self._root,
        )

    def append_lifecycle(
        self,
        session_id: str,
        observation: evidence.LifecycleObservation,
        request: evidence.WriteRequest,
    ) -> evidence.AppendReceipt:
        """Append one bounded preparation, execution, or cleanup transition."""

        session_id = _require_session_id(session_id)
        if type(observation) is not evidence.LifecycleObservation:
            _invalid()
        if type(observation.lifecycle) is not evidence.Lifecycle:
            _invalid()
        event: dict[str, object] = {
            "event_type": "lifecycle",
            "evidence_refs": _evidence_refs_document(observation.evidence_refs),
            "lifecycle": observation.lifecycle.value,
        }
        return _append_event(
            self._session_directory(session_id),
            session_id,
            event,
            request,
            root=self._root,
        )

    def append_terminal(
        self,
        session_id: str,
        observation: evidence.TerminalObservation,
        request: evidence.WriteRequest,
    ) -> evidence.AppendReceipt:
        """Append the terminal event and durably publish its execution manifest."""

        session_id = _require_session_id(session_id)
        if type(request) is not evidence.WriteRequest:
            _invalid()
        if type(observation) is not evidence.TerminalObservation:
            _invalid()
        if type(observation.outcome) is not evidence.TerminalOutcome:
            _invalid()
        if type(observation.reason) is not evidence.TerminalReason:
            _invalid()
        ended_at = _require_timestamp(observation.ended_at)
        event: dict[str, object] = {
            "ended_at": ended_at,
            "event_type": "terminal",
            "evidence_refs": _evidence_refs_document(observation.evidence_refs),
            "outcome": observation.outcome.value,
            "reason": observation.reason.value,
        }
        session_directory = self._session_directory(session_id)
        receipt = _append_event(
            session_directory,
            session_id,
            event,
            request,
            root=self._root,
        )
        with _stream_lock(session_directory, root=self._root):
            chain = _load_chain(session_directory, session_id, root=self._root)
        _finalize_manifest(session_directory, session_id, chain, root=self._root)
        return receipt

    def verify_execution(self, session_id: str) -> evidence.ExecutionManifest:
        """Verify a terminal record chain and its immutable manifest."""

        session_id = _require_session_id(session_id)
        session_directory = self._session_directory(session_id)
        _ensure_private_directory(session_directory, create=False, root=self._root)
        with _stream_lock(session_directory, root=self._root):
            chain = _load_chain(session_directory, session_id, root=self._root)
            return _verify_execution_locked(
                session_directory,
                session_id,
                chain,
                root=self._root,
            )

    def snapshot(self, session_id: str) -> evidence.SessionSnapshot:
        """Read and verify the currently published execution-record chain."""

        session_id = _require_session_id(session_id)
        session_directory = self._session_directory(session_id)
        _ensure_private_directory(session_directory, create=False, root=self._root)
        with _stream_lock(session_directory, root=self._root):
            chain = _load_chain(session_directory, session_id, root=self._root)
            if chain[-1][0]["event"].get("event_type") == "terminal":
                _verify_execution_locked(
                    session_directory,
                    session_id,
                    chain,
                    root=self._root,
                )
        records = tuple(
            evidence.RecordSummary(
                sequence=int(record["sequence"]),
                record_sha256=digest,
                previous_record_sha256=record["previous_record_sha256"],
                event_type=str(record["event"]["event_type"]),
            )
            for record, digest in chain
        )
        state = "finalized" if records and records[-1].event_type == "terminal" else "open"
        return evidence.SessionSnapshot(
            session_id=session_id,
            state=state,
            record_count=len(records),
            head_sha256=records[-1].record_sha256,
            records=records,
        )

    def recover(
        self,
        session_id: str,
        *,
        abandoned_before: str | None = None,
    ) -> evidence.RecoveryResult:
        """Verify and finalize an execution without resuming its session.

        A caller must explicitly provide a cutoff only after it has established
        that no writer remains. A free lock by itself is not abandonment proof.
        """

        session_id = _require_session_id(session_id)
        if abandoned_before is not None:
            abandoned_before = _require_timestamp(abandoned_before)
        session_directory = self._session_directory(session_id)
        _ensure_private_directory(session_directory, create=False, root=self._root)
        try:
            with _stream_lock(session_directory, root=self._root):
                chain = _load_chain(session_directory, session_id, root=self._root)
                if chain[-1][0]["event"].get("event_type") == "terminal":
                    digest = _finalize_manifest(
                        session_directory,
                        session_id,
                        chain,
                        root=self._root,
                    )
                    return evidence.RecoveryResult(
                        session_id=session_id,
                        state=evidence.RecoveryState.FINALIZED,
                        appended_interruption=False,
                        manifest_sha256=digest,
                    )
                if abandoned_before is None:
                    return evidence.RecoveryResult(
                        session_id=session_id,
                        state=evidence.RecoveryState.INCOMPLETE,
                        appended_interruption=False,
                        manifest_sha256=None,
                    )
                last_occurred_at = str(chain[-1][0]["event"]["occurred_at"])
                if last_occurred_at > abandoned_before:
                    return evidence.RecoveryResult(
                        session_id=session_id,
                        state=evidence.RecoveryState.INCOMPLETE,
                        appended_interruption=False,
                        manifest_sha256=None,
                    )
                try:
                    manifest_raw = _read_private_file(
                        session_directory,
                        "manifest.json",
                        root=self._root,
                    )
                except _MissingPrivateFile:
                    pass
                else:
                    try:
                        _parse_manifest(manifest_raw, session_id=session_id, chain=chain)
                    except evidence.EvidenceError:
                        raise evidence.EvidenceError(
                            evidence.EvidenceErrorCode.MANIFEST_MISMATCH
                        ) from None
                    raise evidence.EvidenceError(evidence.EvidenceErrorCode.MANIFEST_MISMATCH)
                event: dict[str, object] = {
                    "ended_at": last_occurred_at,
                    "event_type": "terminal",
                    "evidence_refs": [],
                    "outcome": evidence.TerminalOutcome.INTERRUPTED.value,
                    "reason": evidence.TerminalReason.RECOVERY_ABANDONED.value,
                }
                occurred_at = max(_now_timestamp(), last_occurred_at)
                _append_event(
                    session_directory,
                    session_id,
                    event,
                    evidence.WriteRequest(
                        operation_id=_RECOVERY_OPERATION_ID,
                        occurred_at=occurred_at,
                    ),
                    root=self._root,
                    acquire_lock=False,
                    internal_operation=True,
                )
                chain = _load_chain(session_directory, session_id, root=self._root)
                digest = _finalize_manifest(
                    session_directory,
                    session_id,
                    chain,
                    root=self._root,
                )
                return evidence.RecoveryResult(
                    session_id=session_id,
                    state=evidence.RecoveryState.INTERRUPTED,
                    appended_interruption=True,
                    manifest_sha256=digest,
                )
        except evidence.EvidenceError as error:
            if error.code is evidence.EvidenceErrorCode.BUSY:
                return evidence.RecoveryResult(
                    session_id=session_id,
                    state=evidence.RecoveryState.BUSY,
                    appended_interruption=False,
                    manifest_sha256=None,
                )
            raise
