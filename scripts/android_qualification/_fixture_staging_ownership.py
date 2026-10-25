"""Persist destination ownership and recover or remove only proven trees."""

from __future__ import annotations
from contextlib import contextmanager
from datetime import datetime
from functools import wraps
from pathlib import Path
from typing import Any, Iterator
import ctypes
import errno
import fcntl
import hashlib
import json
import math
import os
import re
import secrets
import stat
import sys
import threading
import time
import uuid
import weakref
from ._fixture_staging_model import (
    FixtureFileExpectation,
    FixtureStagingError,
    FixtureStagingErrorCode,
    FixtureStagingGrant,
    RecoveryObligation,
    _boot_identity,
    _check_operation_timing,
    _datetime_ns,
    _monotonic_deadline_checker,
    _new_operation_timing,
    _read_monotonic_ns,
    _validate_operation_timing,
)
from . import _fixture_staging_manifest as _authority
from ._fixture_staging_manifest import _identifier, _safe_relative_path, _validate_grant_for_use
from ._fixture_staging_content import _file_identity

_STATE_DIRECTORY = ".fixture-staging-state"
_STATE_SCHEMA_VERSION = 2
_STATE_RECORD_NAME = re.compile(
    r"^(?P<session>[0-9a-f]{32})\.(?P<generation>[0-9]{8})\.json$"
)
_LEGACY_STATE_RECORD_NAME = re.compile(r"^(?P<session>[0-9a-f]{32})\.json$")
_STATE_TEMP_NAME = re.compile(
    r"^\.[0-9a-f]{32}\.[0-9a-f]{16}\.tmp$"
)
_COORDINATION_LOCK_NAME = ".coordination.lock"
_COORDINATION_LOCK_GUARD = threading.Lock()
_COORDINATION_LOCKS: dict[str, Any] = {}
_COORDINATION_LOCK_STATE = threading.local()


def _build_synthetic_namespace_capability_support():
    """Build the immutable capability type and its closure-owned issuer."""

    construction_key = object()
    capability_bindings: weakref.WeakKeyDictionary[
        object, tuple[object, object, threading.Thread]
    ] = weakref.WeakKeyDictionary()

    class _ExclusiveStagingNamespaceCapability:
        """Opaque, owner-bound proof for private synthetic mechanics only.

        Production has no issuer while the host lacks OS-enforced namespace
        isolation. The constructor secret and every identity binding belong to
        this closure. The current :class:`threading.Thread` object is also held
        strongly by the registry and compared by identity. A later thread that
        receives the same reusable numeric thread identifier therefore cannot
        inherit authority. The instance has no writable data attributes, so
        direct ``object.__setattr__`` calls cannot retarget its authority.
        """

        __slots__ = ("__weakref__",)

        def __init__(
            self,
            *,
            owner,
            monotonic_clock,
            construction_key: object,
        ) -> None:
            if construction_key is not _BUILD_CONSTRUCTION_KEY:
                raise TypeError("destination namespace capability is not constructible")
            if owner is None:
                raise TypeError("destination namespace capability requires an owner")
            if monotonic_clock is not None and not callable(monotonic_clock):
                raise TypeError("destination namespace capability clock is invalid")
            capability_bindings[self] = (
                owner,
                monotonic_clock,
                threading.current_thread(),
            )

        def __setattr__(self, name: str, value: object) -> None:
            raise AttributeError("destination namespace capability is immutable")

        def __delattr__(self, name: str) -> None:
            raise AttributeError("destination namespace capability is immutable")

        def __init_subclass__(cls, **kwargs) -> None:
            raise TypeError("destination namespace capability is not subclassable")

        def _binding(self) -> tuple[object, object, threading.Thread]:
            binding = capability_bindings.get(self)
            if binding is None:
                raise TypeError(
                    "destination namespace capability has no admitted binding"
                )
            return binding

        @property
        def origin(self) -> str:
            """Return the only supported private capability origin."""

            return "synthetic"

        @property
        def monotonic_clock(self):
            """Return the admitted timing source without exposing construction."""

            return self._binding()[1]

        def _owner_identity(self) -> object:
            return self._binding()[0]

        def _thread_identity(self) -> threading.Thread:
            return self._binding()[2]

        def check_deadline(
            self,
            record: dict[str, Any],
            *,
            mode: str,
        ) -> None:
            """Check the persisted operation timeline with admitted timing."""

            _check_operation_timing(
                record.get("operation_timing"),
                clock=self.monotonic_clock or _monotonic_now,
                mode=mode,
            )

    _BUILD_CONSTRUCTION_KEY = construction_key

    def issue(*, owner, monotonic_clock=None):
        """Issue one private synthetic capability bound to an exact owner."""

        return _ExclusiveStagingNamespaceCapability(
            owner=owner,
            monotonic_clock=monotonic_clock,
            construction_key=construction_key,
        )

    return _ExclusiveStagingNamespaceCapability, issue


(
    _ExclusiveStagingNamespaceCapability,
    _issue_synthetic_namespace_capability,
) = _build_synthetic_namespace_capability_support()
del _build_synthetic_namespace_capability_support


def _require_namespace_capability(
    capability,
    *,
    origin: str | None = None,
    owner: object | None = None,
) -> None:
    """Require one exact, immutable, owner-bound synthetic capability."""

    if type(capability) is not _ExclusiveStagingNamespaceCapability:
        raise FixtureStagingError(
            FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY
        )
    try:
        owner_identity, _monotonic_clock, thread_identity = capability._binding()
    except (AttributeError, TypeError):
        raise FixtureStagingError(
            FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY
        ) from None
    if origin is not None and capability.origin != origin:
        raise FixtureStagingError(
            FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY
        )
    if owner is not None and owner_identity is not owner:
        raise FixtureStagingError(
            FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY
        )
    if thread_identity is not threading.current_thread():
        raise FixtureStagingError(
            FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY
        )


def _synthetic_namespace_owner(capability) -> object:
    """Return the exact owner bound by one private synthetic capability."""

    _require_namespace_capability(capability, origin="synthetic")
    return capability._owner_identity()


def _coordinated_state_change(
    *,
    create_state_directory: bool = False,
    authorization: str | None = None,
):
    """Validate authority before serializing one durable state transition."""

    def decorate(method):
        @wraps(method)
        def coordinated(self, *args, **kwargs):
            capability = kwargs.get("capability")
            self._require_mutation_capability(capability)
            if "operation_timing" in kwargs:
                raise FixtureStagingError(
                    FixtureStagingErrorCode.TIMING_UNVERIFIED
                )
            if authorization is not None:
                grant = kwargs.get("grant")
                if grant is None and args:
                    grant = args[0]
                _validate_grant_for_use(
                    grant,
                    _authority._utc_now(),
                    cleanup_window=authorization == "cleanup",
                )
            with self.coordination_lock(
                create_state_directory=create_state_directory,
                capability=capability,
            ):
                return method(self, *args, **kwargs)

        return coordinated

    return decorate


def _monotonic_now() -> int:
    """Return nanoseconds in the existing uptime-based monotonic clock domain.

    On macOS this clock excludes system sleep. Using its integer API avoids
    float precision loss without changing persisted timing evidence semantics.
    A sleep-inclusive clock requires a separately versioned timing contract.
    """

    return time.monotonic_ns()


class FixtureStagingOwnership:
    """Own durable records, inode proofs, and explicit cleanup recovery."""

    _STATE_DIRECTORY = _STATE_DIRECTORY
    _mutation_origin = "production"

    def __init__(
        self,
        root: Path,
        *,
        session_id_factory=None,
        capability=None,
    ) -> None:
        self.root = Path(root).absolute()
        self._session_id_factory = session_id_factory or (lambda: uuid.uuid4().hex)
        self._capability = capability
        if capability is not None:
            self._require_mutation_capability(capability)
        _validate_private_directory(self.root)

    def _require_mutation_capability(self, capability=None):
        """Reject every mutation capability while production isolation is absent."""

        if type(self) is not FixtureStagingOwnership:
            raise FixtureStagingError(
                FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY
            )
        raise FixtureStagingError(
            FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY
        )

    @contextmanager
    def coordination_lock(
        self,
        *,
        create_state_directory: bool = False,
        capability=None,
    ) -> Iterator[None]:
        """Serialize cooperating operations on this destination root.

        The thread lock coordinates callers in one process, and the private
        advisory lock file coordinates cooperating processes. Neither lock
        excludes a same-user process from replacing a pathname in the
        destination namespace.
        """

        self._require_mutation_capability(capability)
        key = os.fspath(self.root)
        with _COORDINATION_LOCK_GUARD:
            process_lock = _COORDINATION_LOCKS.setdefault(
                key, threading.RLock()
            )
        process_lock.acquire()
        held = getattr(_COORDINATION_LOCK_STATE, "held", None)
        if held is None:
            held = set()
            _COORDINATION_LOCK_STATE.held = held
        if key in held:
            try:
                yield
            finally:
                process_lock.release()
            return

        descriptor = -1
        try:
            state_directory = self._state_directory(
                create=create_state_directory,
                capability=capability,
            )
            lock_path = state_directory / _COORDINATION_LOCK_NAME
            descriptor = os.open(
                lock_path,
                os.O_RDWR
                | os.O_CREAT
                | getattr(os, "O_NOFOLLOW", 0),
                0o600,
            )
            info = os.fstat(descriptor)
            path_info = lock_path.lstat()
            if (
                not stat.S_ISREG(info.st_mode)
                or info.st_uid != os.geteuid()
                or stat.S_IMODE(info.st_mode) != 0o600
                or info.st_nlink != 1
                or (info.st_dev, info.st_ino)
                != (path_info.st_dev, path_info.st_ino)
            ):
                raise FixtureStagingError(
                    FixtureStagingErrorCode.DESTINATION_UNSAFE
                )
            fcntl.flock(descriptor, fcntl.LOCK_EX)
            held.add(key)
            yield
        except OSError:
            raise FixtureStagingError(
                FixtureStagingErrorCode.DESTINATION_UNSAFE
            ) from None
        finally:
            held.discard(key)
            if descriptor >= 0:
                try:
                    fcntl.flock(descriptor, fcntl.LOCK_UN)
                except OSError:
                    pass
                os.close(descriptor)
            process_lock.release()

    def final_root(self, session_id: str) -> Path:
        _validate_session_id(session_id)
        return self.root / f"fixture-{session_id}"

    def temporary_root(self, session_id: str) -> Path:
        _validate_session_id(session_id)
        try:
            record = self._load_state(session_id)
            name = record.get("temporary_name")
            if (
                type(name) is str
                and name.startswith(f".fixture-{session_id}-")
                and name.endswith(".partial")
                and Path(name).name == name
            ):
                return self.root / name
        except FixtureStagingError:
            pass
        return self.root / f".fixture-{session_id}.partial"

    def recovery_state_path(self, session_id: str) -> Path:
        """Return the highest persisted generation for owner inspection."""
        _validate_session_id(session_id)
        directory = self.root / self._STATE_DIRECTORY
        generations: list[int] = []
        legacy_present = False
        try:
            entries = tuple(directory.iterdir())
        except OSError:
            entries = ()
        for path in entries:
            match = _STATE_RECORD_NAME.fullmatch(path.name)
            if match is not None and match.group("session") == session_id:
                generations.append(int(match.group("generation")))
                continue
            legacy = _LEGACY_STATE_RECORD_NAME.fullmatch(path.name)
            if legacy is not None and legacy.group("session") == session_id:
                legacy_present = True
        if generations:
            return self._state_record_path(session_id, max(generations))
        if legacy_present:
            return directory / f"{session_id}.json"
        return self._state_record_path(session_id, 0)

    def _state_record_path(self, session_id: str, generation: int) -> Path:
        _validate_session_id(session_id)
        if type(generation) is not int or generation < 0:
            raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
        return (
            self.root
            / self._STATE_DIRECTORY
            / f"{session_id}.{generation:08d}.json"
        )

    def _state_directory(self, *, create: bool, capability=None) -> Path:
        if create:
            self._require_mutation_capability(capability)
        path = self.root / self._STATE_DIRECTORY
        try:
            info = path.lstat()
        except FileNotFoundError:
            if not create:
                raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN) from None
            try:
                path.mkdir(mode=0o700)
            except OSError:
                raise FixtureStagingError(FixtureStagingErrorCode.DESTINATION_UNSAFE) from None
            info = path.lstat()
        except OSError:
            raise FixtureStagingError(FixtureStagingErrorCode.DESTINATION_UNSAFE) from None
        if (
            not stat.S_ISDIR(info.st_mode)
            or stat.S_IMODE(info.st_mode) != 0o700
            or info.st_uid != os.geteuid()
        ):
            raise FixtureStagingError(FixtureStagingErrorCode.DESTINATION_UNSAFE)
        return path

    @_coordinated_state_change(
        create_state_directory=True,
        authorization="staging",
    )
    def reserve_session(
        self,
        grant: FixtureStagingGrant,
        *,
        capability=None,
    ) -> tuple[str, str]:
        """Persist ownership intent before creating an unpublished root."""

        _validate_private_directory(self.root)
        state_directory = self._state_directory(create=True, capability=capability)
        session_id = self._session_id_factory()
        _validate_session_id(session_id)
        token = secrets.token_hex(32)
        timing = _new_operation_timing(
            grant,
            _authority._utc_now(),
            capability.monotonic_clock or _monotonic_now,
        )
        temporary_name = f".fixture-{session_id}-{token}.partial"
        record = {
            "schema_version": _STATE_SCHEMA_VERSION,
            "session_id": session_id,
            "generation": 0,
            "previous_sha256": None,
            "state": "reserved",
            "ownership_token": token,
            "temporary_name": temporary_name,
            "final_name": self.final_root(session_id).name,
            "publication_intent": None,
            "root_device": None,
            "root_inode": None,
            "parent_device": os.stat(self.root, follow_symlinks=False).st_dev,
            "parent_inode": os.stat(self.root, follow_symlinks=False).st_ino,
            "authorization_sha256": grant.authorization_sha256,
            "approval_sha256": grant.approval_sha256,
            "operation_id": grant.operation_id,
            "plan_sha256": grant.plan_sha256,
            "fixture_manifest_sha256": grant.fixture_manifest_sha256,
            "operation_timing": timing,
            "recovery_attempt": None,
            "fixture_count": len(grant.fixture_ids),
            "expected_files": [
                {
                    "fixture_id": fixture.fixture_id,
                    "path": item.path,
                    "size": item.size,
                    "sha256": item.sha256,
                }
                for fixture in grant._fixture_expectations
                for item in fixture.files
            ],
            "verified_files": [],
            "owned_entries": [],
            "blocker_code": None,
        }
        _seal_state_record(record)
        path = self._state_record_path(session_id, 0)
        temporary = state_directory / f".{session_id}.{token}.tmp"
        if _exists_nofollow(path) or _exists_nofollow(
            state_directory / f"{session_id}.json"
        ):
            raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
        try:
            _publish_json_exclusive(
                path,
                temporary,
                _encode_state(record),
            capability=capability,
            )
        except FileExistsError:
            raise FixtureStagingError(
                FixtureStagingErrorCode.OWNERSHIP_UNPROVEN
            ) from None
        except FixtureStagingError:
            raise
        except OSError:
            raise FixtureStagingError(FixtureStagingErrorCode.DESTINATION_UNSAFE) from None
        return session_id, token

    @_coordinated_state_change(authorization="staging")
    def record_verified_file(
        self,
        session_id: str,
        token: str,
        fixture_id: str,
        expectation: FixtureFileExpectation,
        source_mtime_ns: int,
        *,
        grant: FixtureStagingGrant,
        capability=None,
    ) -> None:
        """Persist minimal verified-member state for crash recovery."""

        record = self._load_state(session_id)
        self._assert_record_owner(record, session_id, token)
        if record.get("state") != "preparing":
            raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
        verified = record.get("verified_files")
        expected_files = record.get("expected_files")
        if type(verified) is not list or type(expected_files) is not list:
            raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
        expected = {
            "fixture_id": fixture_id,
            "path": expectation.path,
            "size": expectation.size,
            "sha256": expectation.sha256,
        }
        if expected not in expected_files or any(
            item.get("fixture_id") == fixture_id and item.get("path") == expectation.path
            for item in verified
            if type(item) is dict
        ):
            raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
        verified.append(
            {
                "fixture_id": fixture_id,
                "path": expectation.path,
                "size": expectation.size,
                "sha256": expectation.sha256,
                "mtime_ns": source_mtime_ns,
            }
        )
        self._replace_state(record, capability=capability)

    @_coordinated_state_change()
    def _record_owned_entry(
        self,
        session_id: str,
        token: str,
        kind: str,
        relative_path: str,
        info: os.stat_result,
        *,
        created: bool,
        capability=None,
    ) -> None:
        """Persist each newly created path before writing its contents."""

        record = self._load_state(session_id)
        self._assert_record_owner(record, session_id, token)
        if record.get("state") != "preparing" or kind not in {"file", "directory"}:
            raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
        _safe_relative_path(relative_path)
        entries = record.get("owned_entries")
        if type(entries) is not list:
            raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
        matches = [item for item in entries if type(item) is dict and item.get("path") == relative_path]
        identity = (info.st_dev, info.st_ino)
        if matches:
            if (
                created
                or len(matches) != 1
                or matches[0].get("kind") != kind
                or (matches[0].get("device"), matches[0].get("inode")) != identity
            ):
                raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
            return
        if not created:
            raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
        entries.append(
            {
                "kind": kind,
                "path": relative_path,
                "device": info.st_dev,
                "inode": info.st_ino,
            }
        )
        self._replace_state(record, capability=capability)

    def mark_blocked(
        self,
        session_id: str,
        token: str,
        code: FixtureStagingErrorCode,
        *,
        capability=None,
    ) -> bool:
        """Persist a blocked obligation, returning False if locking or writing fails."""

        try:
            with self.coordination_lock(
                create_state_directory=True,
                capability=capability,
            ):
                record = self._load_state(session_id)
                self._assert_record_owner(record, session_id, token)
                if record.get("state") not in {
                    "cleanup_in_progress",
                    "cleanup_complete",
                }:
                    record["state"] = "blocked"
                record["blocker_code"] = code.value
                record["recovery_attempt"] = {
                    "schema_version": 1,
                    "boot_id": _boot_identity()[0],
                    "monotonic_ns": _read_monotonic_ns(_monotonic_now),
                    "wall_time_ns": _datetime_ns(_authority._utc_now()),
                    "outcome": code.value,
                }
                self._replace_state(record, capability=capability)
        except FixtureStagingError:
            return False
        return True

    def mark_blocked_or_destination_unsafe(
        self,
        session_id: str,
        token: str,
        error_code: FixtureStagingErrorCode,
        *,
        capability=None,
    ) -> FixtureStagingErrorCode:
        """Persist a blocked state or return the safe state-write failure code."""

        if not self.mark_blocked(
            session_id,
            token,
            error_code,
            capability=capability,
        ):
            return FixtureStagingErrorCode.DESTINATION_UNSAFE
        return error_code

    def recovery_obligations(self) -> tuple[RecoveryObligation, ...]:
        """List private staging records without exposing their fixture contents."""

        try:
            directory = self._state_directory(create=False)
            entries = tuple(directory.iterdir())
        except FixtureStagingError:
            return ()
        obligations: list[RecoveryObligation] = []
        session_ids: set[str] = set()
        unknown = False
        for path in entries:
            if path.name == _COORDINATION_LOCK_NAME or _STATE_TEMP_NAME.fullmatch(path.name):
                continue
            generation_match = _STATE_RECORD_NAME.fullmatch(path.name)
            if generation_match is not None:
                session_ids.add(generation_match.group("session"))
                continue
            legacy_match = _LEGACY_STATE_RECORD_NAME.fullmatch(path.name)
            if legacy_match is not None:
                session_ids.add(legacy_match.group("session"))
                continue
            if path.suffix == ".json":
                unknown = True
        for session_id in sorted(session_ids):
            try:
                record = self._load_state(session_id)
                proven = self._ownership_is_proven(record, session_id)
                state = record.get("state")
                if state in {
                    "reserved",
                    "preparing",
                    "publication_pending",
                    "cleanup_in_progress",
                    "blocked",
                }:
                    state = "blocked"
                obligations.append(
                    RecoveryObligation(
                        session_id,
                        str(state or "BLOCKED"),
                        record.get("blocker_code"),
                        proven,
                    )
                )
            except FixtureStagingError as error:
                obligations.append(
                    RecoveryObligation(
                        session_id,
                        "BLOCKED",
                        error.code.value,
                        False,
                    )
                )
        if unknown:
            obligations.append(
                RecoveryObligation(
                    "unknown",
                    "BLOCKED",
                    FixtureStagingErrorCode.OWNERSHIP_UNPROVEN.value,
                    False,
                )
            )
        return tuple(obligations)

    def _write_private_json_exclusive(
        self,
        path: Path,
        document: dict[str, Any],
        *,
        capability=None,
    ) -> None:
        capability = self._require_mutation_capability(capability)
        token = document.get("ownership_token")
        if type(token) is not str or re.fullmatch(r"[0-9a-f]{64}", token) is None:
            raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
        temporary = path.with_name(f"{path.name}.{token}.tmp")
        _publish_json_exclusive(
            path,
            temporary,
            _encode_state(document),
            capability=capability,
        )

    @_coordinated_state_change()
    def _replace_state(
        self,
        record: dict[str, Any],
        *,
        capability=None,
    ) -> None:
        """Publish one state generation while retaining ambiguous sidecars.

        A same-user process can recreate a temporary pathname after rename or
        after a failed publication. The current object behind that pathname
        cannot be proven from its name, so recovery review owns its removal.
        """
        self._require_mutation_capability(capability)
        session_id = record.get("session_id")
        _validate_session_id(session_id)
        current, current_encoded, generation = self._load_state_envelope(session_id)
        immutable_fields = (
            "session_id",
            "ownership_token",
            "temporary_name",
            "final_name",
            "parent_device",
            "parent_inode",
            "authorization_sha256",
            "approval_sha256",
            "operation_id",
            "plan_sha256",
            "fixture_manifest_sha256",
            "fixture_count",
            "expected_files",
            "operation_timing",
        )
        if any(record.get(field) != current.get(field) for field in immutable_fields):
            raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
        current_intent = current.get("publication_intent")
        next_intent = record.get("publication_intent")
        if current_intent is not None and next_intent != current_intent:
            raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
        if next_intent is not None:
            if record.get("state") != "publication_pending" and current_intent is None:
                raise FixtureStagingError(
                    FixtureStagingErrorCode.OWNERSHIP_UNPROVEN
                )
            if not _publication_intent_is_proven(record):
                raise FixtureStagingError(
                    FixtureStagingErrorCode.OWNERSHIP_UNPROVEN
                )
        next_generation = generation + 1
        record["generation"] = next_generation
        record["previous_sha256"] = hashlib.sha256(current_encoded).hexdigest()
        _seal_state_record(record)
        path = self._state_record_path(session_id, next_generation)
        directory = self._state_directory(create=False)
        temporary = directory / f".{session_id}.{secrets.token_hex(8)}.tmp"
        try:
            _publish_json_exclusive(
                path,
                temporary,
                _encode_state(record),
            capability=capability,
            )
        except FileExistsError:
            raise FixtureStagingError(
                FixtureStagingErrorCode.OWNERSHIP_UNPROVEN
            ) from None
        except FixtureStagingError:
            raise
        except OSError:
            raise FixtureStagingError(FixtureStagingErrorCode.DESTINATION_UNSAFE) from None

    def _load_state(self, session_id: str) -> dict[str, Any]:
        return self._load_state_envelope(session_id)[0]

    def _load_state_envelope(
        self, session_id: str
    ) -> tuple[dict[str, Any], bytes, int]:
        """Load and prove one contiguous immutable generation chain."""
        _validate_session_id(session_id)
        directory = self._state_directory(create=False)
        generations: dict[int, Path] = {}
        legacy: Path | None = None
        unknown_related = False
        for path in directory.iterdir():
            generation_match = _STATE_RECORD_NAME.fullmatch(path.name)
            if (
                generation_match is not None
                and generation_match.group("session") == session_id
            ):
                generations[int(generation_match.group("generation"))] = path
                continue
            legacy_match = _LEGACY_STATE_RECORD_NAME.fullmatch(path.name)
            if legacy_match is not None and legacy_match.group("session") == session_id:
                legacy = path
                continue
            if (
                path.name.startswith(session_id)
                and _STATE_TEMP_NAME.fullmatch(path.name) is None
            ):
                unknown_related = True
        if unknown_related or (legacy is not None and generations):
            raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
        if legacy is not None:
            document, _encoded, _pin = _authority._private_document(legacy)
            if (
                document.get("schema_version") != 1
                or document.get("session_id") != session_id
                or not self._ownership_is_proven(document, session_id)
            ):
                raise FixtureStagingError(
                    FixtureStagingErrorCode.OWNERSHIP_UNPROVEN
                )
            raise FixtureStagingError(
                FixtureStagingErrorCode.TIMING_UNVERIFIED
            )
        if not generations:
            raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
        highest = max(generations)
        if set(generations) != set(range(highest + 1)):
            raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
        previous_encoded: bytes | None = None
        first_timing: object = None
        document: dict[str, Any] = {}
        encoded = b""
        for generation in range(highest + 1):
            try:
                document, encoded, _pin = _authority._private_document(
                    generations[generation]
                )
            except FixtureStagingError:
                raise FixtureStagingError(
                    FixtureStagingErrorCode.OWNERSHIP_UNPROVEN
                ) from None
            self._validate_state_document(document, session_id, generation)
            if encoded != _encode_state(document):
                raise FixtureStagingError(
                    FixtureStagingErrorCode.OWNERSHIP_UNPROVEN
                )
            if generation == 0:
                if document.get("previous_sha256") is not None:
                    raise FixtureStagingError(
                        FixtureStagingErrorCode.OWNERSHIP_UNPROVEN
                    )
                first_timing = document.get("operation_timing")
            else:
                if document.get("operation_timing") != first_timing:
                    raise FixtureStagingError(
                        FixtureStagingErrorCode.OWNERSHIP_UNPROVEN
                    )
                previous_hash = (
                    hashlib.sha256(previous_encoded).hexdigest()
                    if previous_encoded is not None
                    else None
                )
                if document.get("previous_sha256") != previous_hash:
                    raise FixtureStagingError(
                        FixtureStagingErrorCode.OWNERSHIP_UNPROVEN
                    )
            previous_encoded = encoded
        return document, encoded, highest

    def _validate_state_document(
        self,
        document: object,
        session_id: str,
        generation: int,
    ) -> dict[str, Any]:
        """Validate one immutable record and its authority bindings."""
        if (
            type(document) is not dict
            or document.get("schema_version") != _STATE_SCHEMA_VERSION
            or document.get("session_id") != session_id
            or document.get("generation") != generation
            or type(document.get("record_sha256")) is not str
            or re.fullmatch(r"[0-9a-f]{64}", document["record_sha256"]) is None
            or document["record_sha256"] != _state_record_digest(document)
            or type(document.get("ownership_token")) is not str
            or re.fullmatch(
                r"[0-9a-f]{64}", document.get("ownership_token", "")
            )
            is None
            or type(document.get("parent_device")) is not int
            or type(document.get("parent_inode")) is not int
        ):
            raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
        previous = document.get("previous_sha256")
        if generation == 0:
            if previous is not None:
                raise FixtureStagingError(
                    FixtureStagingErrorCode.OWNERSHIP_UNPROVEN
                )
        elif type(previous) is not str or re.fullmatch(r"[0-9a-f]{64}", previous) is None:
            raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
        timing = _validate_operation_timing(document.get("operation_timing"))
        if any(
            timing.get(field) != document.get(field)
            for field in (
                "operation_id",
                "authorization_sha256",
                "plan_sha256",
                "fixture_manifest_sha256",
                "approval_sha256",
            )
        ):
            raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
        expected_temporary_prefix = (
            f".fixture-{session_id}-{document.get('ownership_token')}"
        )
        if (
            document.get("final_name") != f"fixture-{session_id}"
            or type(document.get("temporary_name")) is not str
            or not document["temporary_name"].startswith(expected_temporary_prefix)
            or not document["temporary_name"].endswith(".partial")
            or Path(document["temporary_name"]).name != document["temporary_name"]
        ):
            raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
        attempt = document.get("recovery_attempt")
        if attempt is not None and (
            type(attempt) is not dict
            or set(attempt) != {
                "schema_version",
                "boot_id",
                "monotonic_ns",
                "wall_time_ns",
                "outcome",
            }
            or attempt.get("schema_version") != 1
            or type(attempt.get("boot_id")) is not str
            or re.fullmatch(r"[0-9a-f-]{16,128}", attempt["boot_id"]) is None
            or type(attempt.get("monotonic_ns")) is not int
            or attempt["monotonic_ns"] < 0
            or type(attempt.get("wall_time_ns")) is not int
            or attempt["wall_time_ns"] < 0
            or type(attempt.get("outcome")) is not str
            or not attempt["outcome"]
        ):
            raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
        return document

    def _assert_record_owner(self, record: dict[str, Any], session_id: str, token: str) -> None:
        if record.get("session_id") != session_id or record.get("ownership_token") != token:
            raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)

    def _assert_record_timing(
        self,
        record: dict[str, Any],
        *,
        mode: str,
        clock=_monotonic_now,
    ) -> None:
        """Require the immutable original timeline to authorize this action."""
        _check_operation_timing(
            record.get("operation_timing"),
            clock=clock,
            mode=mode,
        )

    def _open_owned_root(self, session_id: str) -> int:
        record = self._load_state(session_id)
        if not self._ownership_is_proven(record, session_id):
            raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
        root_path = self._record_root(record, session_id)
        try:
            descriptor = os.open(
                root_path,
                os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0),
            )
            info = os.fstat(descriptor)
        except OSError:
            raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN) from None
        if (info.st_dev, info.st_ino) != (record.get("root_device"), record.get("root_inode")):
            os.close(descriptor)
            raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
        return descriptor

    def _record_root(self, record: dict[str, Any], session_id: str) -> Path:
        temporary_name = record.get("temporary_name")
        if type(temporary_name) is not str or Path(temporary_name).name != temporary_name:
            raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
        temporary = self.root / temporary_name
        final = self.final_root(session_id)
        existing = [candidate for candidate in (temporary, final) if _exists_nofollow(candidate)]
        if len(existing) != 1:
            raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
        candidate = existing[0]
        expected_name = record.get("temporary_name") if candidate == temporary else record.get("final_name")
        if candidate.name != expected_name:
            raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
        return candidate

    def _ownership_is_proven(self, record: dict[str, Any], session_id: str) -> bool:
        try:
            if (
                record.get("session_id") != session_id
                or record.get("parent_device") != os.stat(self.root, follow_symlinks=False).st_dev
                or record.get("parent_inode") != os.stat(self.root, follow_symlinks=False).st_ino
            ):
                return False
            if record.get("state") == "cleanup_complete":
                return (
                    record.get("root_device") is None
                    and record.get("root_inode") is None
                    and type(record.get("temporary_name")) is str
                    and not _exists_nofollow(
                        self.root / record["temporary_name"]
                    )
                    and not _exists_nofollow(self.final_root(session_id))
                )
            if (
                record.get("state") == "cleanup_in_progress"
                and type(record.get("root_device")) is int
                and type(record.get("root_inode")) is int
                and type(record.get("temporary_name")) is str
                and not _exists_nofollow(
                    self.root / record["temporary_name"]
                )
                and not _exists_nofollow(self.final_root(session_id))
            ):
                return True
            state = record.get("state")
            publication_intent = record.get("publication_intent")
            if publication_intent is not None and not _publication_intent_is_proven(record):
                return False
            if state in {"publication_pending", "published"} and publication_intent is None:
                return False
            if type(record.get("root_device")) is not int or type(record.get("root_inode")) is not int:
                return False
            root_path = self._record_root(record, session_id)
            info = root_path.lstat()
            if (
                not stat.S_ISDIR(info.st_mode)
                or info.st_uid != os.geteuid()
                or stat.S_IMODE(info.st_mode) != 0o700
                or (info.st_dev, info.st_ino) != (record["root_device"], record["root_inode"])
            ):
                return False
            marker_path = root_path / ".owner.json"
            marker_missing = not _exists_nofollow(marker_path)
            if marker_missing:
                if record.get("state") != "cleanup_in_progress":
                    return False
            else:
                marker, _encoded, _pin = _authority._private_document(marker_path)
                if marker != {
                    "schema_version": 1,
                    "session_id": session_id,
                    "ownership_token": record.get("ownership_token"),
                    "authorization_sha256": record.get("authorization_sha256"),
                    "plan_sha256": record.get("plan_sha256"),
                    "fixture_manifest_sha256": record.get("fixture_manifest_sha256"),
                }:
                    return False
            root_descriptor = os.open(
                root_path,
                os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0),
            )
            try:
                opened = os.fstat(root_descriptor)
                if (opened.st_dev, opened.st_ino) != (info.st_dev, info.st_ino):
                    return False
                _validate_tree_for_removal(
                    root_descriptor,
                    _owned_entry_map(record),
                    allow_missing=record.get("state") == "cleanup_in_progress",
                )
            finally:
                os.close(root_descriptor)
            return True
        except (FixtureStagingError, OSError, TypeError, ValueError):
            return False

    def _exclusive_namespace_authority_available(self) -> bool:
        """Report whether cleanup can exclude same-user pathname replacement.

        The supported host filesystem APIs address deletion by directory and
        entry name. A same-user process can replace that entry between an
        identity check and unlink, so this host cannot prove the exclusive
        destructive namespace authority required for safe cleanup.
        """

        return False

    @_coordinated_state_change(authorization="cleanup")
    def remove_owned_session(
        self,
        session_id: str,
        token: str,
        *,
        grant: FixtureStagingGrant,
        capability=None,
        now: datetime | None = None,
    ) -> None:
        """Delete one owned tree only under current, pinned cleanup authority.

        The legacy ``now`` argument remains accepted for call compatibility;
        authorization always uses the trusted UTC clock.
        """

        self._require_mutation_capability(capability)
        clock = capability.monotonic_clock or _monotonic_now
        record = self._load_state(session_id)
        self._assert_record_owner(record, session_id, token)
        timing = record.get("operation_timing")

        def check_cleanup_authority() -> None:
            instant = _authority._utc_now()
            _validate_grant_for_use(grant, instant, cleanup_window=True)
            if not grant.cleanup_authorized:
                raise FixtureStagingError(
                    FixtureStagingErrorCode.CLEANUP_UNAUTHORIZED
                )
            _check_operation_timing(
                timing,
                clock=clock,
                mode="cleanup",
            )

        try:
            check_cleanup_authority()
        except FixtureStagingError:
            raise
        except Exception:
            raise FixtureStagingError(
                FixtureStagingErrorCode.TIMING_UNVERIFIED
            ) from None

        record = self._load_state(session_id)
        self._assert_record_owner(record, session_id, token)
        if (
            record.get("authorization_sha256") != grant.authorization_sha256
            or record.get("approval_sha256") != grant.approval_sha256
            or record.get("operation_id") != grant.operation_id
            or record.get("plan_sha256") != grant.plan_sha256
            or record.get("fixture_manifest_sha256") != grant.fixture_manifest_sha256
            or record.get("state")
            not in {
                "published",
                "publication_pending",
                "blocked",
                "preparing",
                "cleanup_in_progress",
            }
        ):
            raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
        ownership_proven = self._ownership_is_proven(record, session_id)
        if not ownership_proven:
            raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
        check_cleanup_authority()
        if not self._exclusive_namespace_authority_available():
            check_cleanup_authority()
            raise FixtureStagingError(
                FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY
            )
        if (
            record.get("state") == "cleanup_in_progress"
            and not _exists_nofollow(self.temporary_root(session_id))
            and not _exists_nofollow(self.final_root(session_id))
        ):
            check_cleanup_authority()
            record["state"] = "cleanup_complete"
            record["root_device"] = None
            record["root_inode"] = None
            record["owned_entries"] = []
            self._replace_state(record, capability=capability)
            return
        root_path = self._record_root(record, session_id)
        root_descriptor = self._open_owned_root(session_id)
        ownership = _owned_entry_map(record)
        parent_descriptor = -1
        try:
            _validate_tree_for_removal(
                root_descriptor,
                ownership,
                allow_missing=record.get("state") == "cleanup_in_progress",
            )
            check_cleanup_authority()
            if record.get("state") != "cleanup_in_progress":
                record["state"] = "cleanup_in_progress"
                self._replace_state(record, capability=capability)
            _remove_tree_contents(
                root_descriptor,
                ownership,
                capability=capability,
                check_deadline=check_cleanup_authority,
            )
            check_cleanup_authority()
            parent_descriptor = os.open(
                self.root,
                os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0),
            )
            root_info = os.stat(root_path.name, dir_fd=parent_descriptor, follow_symlinks=False)
            if (
                not stat.S_ISDIR(root_info.st_mode)
                or (root_info.st_dev, root_info.st_ino) != (record.get("root_device"), record.get("root_inode"))
            ):
                raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
            check_cleanup_authority()
            os.rmdir(root_path.name, dir_fd=parent_descriptor)
            os.fsync(parent_descriptor)
            check_cleanup_authority()
            record["state"] = "cleanup_complete"
            record["root_device"] = None
            record["root_inode"] = None
            record["owned_entries"] = []
            self._replace_state(record, capability=capability)
        except FixtureStagingError:
            raise
        except OSError:
            raise FixtureStagingError(FixtureStagingErrorCode.CLEANUP_BLOCKED) from None
        finally:
            os.close(root_descriptor)
            if parent_descriptor >= 0:
                os.close(parent_descriptor)

def _state_record_digest(record: dict[str, Any]) -> str:
    """Return the self-digest of every record field except the digest itself."""
    body = {
        field: value for field, value in record.items() if field != "record_sha256"
    }
    return hashlib.sha256(_encode_state(body)).hexdigest()


def _publication_intent_is_proven(record: dict[str, Any]) -> bool:
    """Check the bounded pre-rename publication intent against its record."""

    intent = record.get("publication_intent")
    if type(intent) is not dict or set(intent) != {
        "temporary_name",
        "final_name",
        "root_device",
        "root_inode",
    }:
        return False
    return (
        type(intent["temporary_name"]) is str
        and type(intent["final_name"]) is str
        and type(intent["root_device"]) is int
        and type(intent["root_inode"]) is int
        and intent["temporary_name"] == record.get("temporary_name")
        and intent["final_name"] == record.get("final_name")
        and (
            (
                record.get("root_device") is None
                and record.get("root_inode") is None
            )
            or (
                intent["root_device"] == record.get("root_device")
                and intent["root_inode"] == record.get("root_inode")
            )
        )
    )


def _seal_state_record(record: dict[str, Any]) -> None:
    """Set a record self-digest immediately before exclusive publication."""
    record.pop("record_sha256", None)
    record["record_sha256"] = _state_record_digest(record)


def _encode_state(record: dict[str, Any]) -> bytes:
    try:
        return json.dumps(
            record,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
            allow_nan=False,
        ).encode("utf-8")
    except (TypeError, ValueError, UnicodeEncodeError):
        raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN) from None

def _owned_entry_map(record: dict[str, Any]) -> dict[str, tuple[str, int, int]]:
    """Read the durable path-to-inode ownership ledger without guessing."""

    entries = record.get("owned_entries")
    if type(entries) is not list:
        raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
    result: dict[str, tuple[str, int, int]] = {}
    for item in entries:
        if type(item) is not dict or set(item) != {"kind", "path", "device", "inode"}:
            raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
        kind = item["kind"]
        path = item["path"]
        device = item["device"]
        inode = item["inode"]
        if (
            kind not in {"file", "directory"}
            or type(path) is not str
            or type(device) is not int
            or type(inode) is not int
            or device < 0
            or inode < 0
            or path in result
        ):
            raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
        try:
            _safe_relative_path(path)
        except FixtureStagingError:
            raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN) from None
        result[path] = (kind, device, inode)
    return result

def _validate_tree_for_removal(
    directory_descriptor: int,
    ownership: dict[str, tuple[str, int, int]],
    *,
    allow_missing: bool = False,
) -> None:
    """Prove the tree contains exactly the persisted session-owned inodes."""

    seen: set[str] = set()

    def visit(descriptor: int, prefix: str) -> None:
        try:
            names = os.listdir(descriptor)
        except OSError:
            raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN) from None
        for name in names:
            if name in {".", ".."} or "/" in name or "\\" in name:
                raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
            path = f"{prefix}/{name}" if prefix else name
            expected = ownership.get(path)
            if expected is None:
                raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
            try:
                info = os.stat(name, dir_fd=descriptor, follow_symlinks=False)
            except OSError:
                raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN) from None
            kind = "directory" if stat.S_ISDIR(info.st_mode) else "file" if stat.S_ISREG(info.st_mode) else "other"
            if (
                kind != expected[0]
                or (info.st_dev, info.st_ino) != expected[1:]
                or info.st_uid != os.geteuid()
            ):
                raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
            if kind == "directory":
                if stat.S_IMODE(info.st_mode) != 0o700:
                    raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
                try:
                    child = os.open(
                        name,
                        os.O_RDONLY
                        | getattr(os, "O_DIRECTORY", 0)
                        | getattr(os, "O_NOFOLLOW", 0),
                        dir_fd=descriptor,
                    )
                except OSError:
                    raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN) from None
                try:
                    opened = os.fstat(child)
                    if (opened.st_dev, opened.st_ino) != (info.st_dev, info.st_ino):
                        raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
                    visit(child, path)
                finally:
                    os.close(child)
            elif stat.S_IMODE(info.st_mode) != 0o600 or info.st_nlink != 1:
                raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
            seen.add(path)

    visit(directory_descriptor, "")
    if (not allow_missing and seen != set(ownership)) or (
        allow_missing and not seen <= set(ownership)
    ):
        raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)

def _validate_private_directory(path: Path) -> os.stat_result:
    try:
        info = path.lstat()
    except OSError:
        raise FixtureStagingError(FixtureStagingErrorCode.DESTINATION_UNSAFE) from None
    if (
        not stat.S_ISDIR(info.st_mode)
        or info.st_uid != os.geteuid()
        or stat.S_IMODE(info.st_mode) != 0o700
    ):
        raise FixtureStagingError(FixtureStagingErrorCode.DESTINATION_UNSAFE)
    return info

def _exists_nofollow(path: Path) -> bool:
    try:
        path.lstat()
        return True
    except FileNotFoundError:
        return False
    except OSError:
        return True

def _remove_tree_contents(
    directory_descriptor: int,
    ownership: dict[str, tuple[str, int, int]],
    prefix: str = "",
    *,
    capability=None,
    check_deadline=None,
) -> None:
    """Remove only inodes recorded by the complete ownership proof."""

    _require_namespace_capability(capability)
    if check_deadline is not None:
        check_deadline()
    names = os.listdir(directory_descriptor)
    if not prefix:
        names.sort(key=lambda name: name == ".owner.json")
    for name in names:
        path = f"{prefix}/{name}" if prefix else name
        if check_deadline is not None:
            check_deadline()
        expected = ownership.get(path)
        if expected is None:
            raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
        info = os.stat(name, dir_fd=directory_descriptor, follow_symlinks=False)
        if (info.st_dev, info.st_ino) != expected[1:] or info.st_uid != os.geteuid():
            raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
        if expected[0] == "directory":
            if not stat.S_ISDIR(info.st_mode):
                raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
            child = os.open(
                name,
                os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0),
                dir_fd=directory_descriptor,
            )
            try:
                opened = os.fstat(child)
                if (opened.st_dev, opened.st_ino) != (info.st_dev, info.st_ino):
                    raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
                _remove_tree_contents(
                    child,
                    ownership,
                    path,
                    capability=capability,
                    check_deadline=check_deadline,
                )
            finally:
                os.close(child)
            current = os.stat(name, dir_fd=directory_descriptor, follow_symlinks=False)
            if (current.st_dev, current.st_ino) != (info.st_dev, info.st_ino):
                raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
            if check_deadline is not None:
                check_deadline()
            os.rmdir(name, dir_fd=directory_descriptor)
        else:
            if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
                raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
            current = os.stat(name, dir_fd=directory_descriptor, follow_symlinks=False)
            if _file_identity(current) != _file_identity(info):
                raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
            if check_deadline is not None:
                check_deadline()
            os.unlink(name, dir_fd=directory_descriptor)
    os.fsync(directory_descriptor)

def _fsync_directory(path: Path) -> None:
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(path, flags)
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
    except OSError:
        raise FixtureStagingError(FixtureStagingErrorCode.DESTINATION_UNSAFE) from None

def _rename_entry_exclusive(
    source_directory: int,
    source_name: str,
    destination_directory: int,
    destination_name: str,
    *,
    capability=None,
) -> None:
    """Atomically move one entry without replacing an existing destination."""

    _require_namespace_capability(capability)
    source_bytes = os.fsencode(source_name)
    destination_bytes = os.fsencode(destination_name)
    libc = ctypes.CDLL(None, use_errno=True)
    if sys.platform == "darwin":
        rename_exclusive = getattr(libc, "renameatx_np", None)
        if rename_exclusive is None:
            raise FixtureStagingError(FixtureStagingErrorCode.DESTINATION_UNSAFE)
        rename_exclusive.argtypes = [
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_uint,
        ]
        rename_exclusive.restype = ctypes.c_int
        result = rename_exclusive(
            source_directory,
            source_bytes,
            destination_directory,
            destination_bytes,
            0x00000004,
        )
    elif sys.platform.startswith("linux"):
        rename_noreplace = getattr(libc, "renameat2", None)
        if rename_noreplace is None:
            raise FixtureStagingError(FixtureStagingErrorCode.DESTINATION_UNSAFE)
        rename_noreplace.argtypes = [
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_uint,
        ]
        rename_noreplace.restype = ctypes.c_int
        result = rename_noreplace(
            source_directory,
            source_bytes,
            destination_directory,
            destination_bytes,
            1,
        )
    else:
        raise FixtureStagingError(FixtureStagingErrorCode.DESTINATION_UNSAFE)
    if result != 0:
        error_number = ctypes.get_errno()
        if error_number == errno.EEXIST:
            raise FileExistsError(error_number, os.strerror(error_number), destination_name)
        raise OSError(error_number, os.strerror(error_number))

def _publish_json_exclusive(
    path: Path,
    temporary: Path,
    encoded: bytes,
    *,
    capability=None,
) -> None:
    """Publish complete JSON and bind the authoritative name to its object.

    A no-replace rename still resolves pathname entries. The open descriptor is
    retained across the rename and compared with the authoritative entry so a
    same-user replacement is detected after publication. The replacement is
    retained for recovery and never treated as an accepted state generation.
    """

    _require_namespace_capability(capability)
    if temporary.parent != path.parent:
        raise FixtureStagingError(FixtureStagingErrorCode.DESTINATION_UNSAFE)
    validated_parent = _validate_private_directory(path.parent)
    directory_descriptor = -1
    descriptor = -1
    stream_descriptor = -1
    try:
        directory_descriptor = os.open(
            path.parent,
            os.O_RDONLY
            | getattr(os, "O_DIRECTORY", 0)
            | getattr(os, "O_NOFOLLOW", 0),
        )
        opened_parent = os.fstat(directory_descriptor)
        path_parent = path.parent.lstat()
        if (
            (opened_parent.st_dev, opened_parent.st_ino)
            != (validated_parent.st_dev, validated_parent.st_ino)
            or (path_parent.st_dev, path_parent.st_ino)
            != (opened_parent.st_dev, opened_parent.st_ino)
        ):
            raise FixtureStagingError(FixtureStagingErrorCode.DESTINATION_UNSAFE)

        flags = (
            os.O_RDWR
            | os.O_CREAT
            | os.O_EXCL
            | getattr(os, "O_NOFOLLOW", 0)
        )
        descriptor = os.open(
            temporary.name,
            flags,
            0o600,
            dir_fd=directory_descriptor,
        )
        stream_descriptor = os.dup(descriptor)
        with os.fdopen(stream_descriptor, "wb") as stream:
            stream_descriptor = -1
            stream.write(encoded)
            stream.flush()
            os.fsync(stream.fileno())

        opened = os.fstat(descriptor)
        current = os.stat(
            temporary.name,
            dir_fd=directory_descriptor,
            follow_symlinks=False,
        )
        if (
            not stat.S_ISREG(opened.st_mode)
            or opened.st_uid != os.geteuid()
            or opened.st_nlink != 1
            or stat.S_IMODE(opened.st_mode) != 0o600
            or (opened.st_dev, opened.st_ino)
            != (current.st_dev, current.st_ino)
        ):
            raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)

        def read_exact_descriptor() -> bytes:
            os.lseek(descriptor, 0, os.SEEK_SET)
            observed = bytearray()
            while len(observed) <= len(encoded):
                chunk = os.read(
                    descriptor,
                    min(64 * 1024, len(encoded) + 1 - len(observed)),
                )
                if not chunk:
                    break
                observed.extend(chunk)
            return bytes(observed)

        if read_exact_descriptor() != encoded:
            raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)

        _rename_entry_exclusive(
            directory_descriptor,
            temporary.name,
            directory_descriptor,
            path.name,
        capability=capability,
        )
        published = os.stat(
            path.name,
            dir_fd=directory_descriptor,
            follow_symlinks=False,
        )
        if (
            not stat.S_ISREG(published.st_mode)
            or (published.st_dev, published.st_ino)
            != (opened.st_dev, opened.st_ino)
            or read_exact_descriptor() != encoded
        ):
            raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
        _fsync_directory(path.parent)
        os.fsync(directory_descriptor)
    finally:
        if stream_descriptor >= 0:
            os.close(stream_descriptor)
        if descriptor >= 0:
            os.close(descriptor)
        if directory_descriptor >= 0:
            os.close(directory_descriptor)

def _validate_session_id(value: object) -> str:
    if type(value) is not str or re.fullmatch(r"[0-9a-f]{32}", value) is None:
        raise FixtureStagingError(FixtureStagingErrorCode.DESTINATION_UNSAFE)
    return value
