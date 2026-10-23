"""Create, verify, and atomically publish host fixture destinations."""

from __future__ import annotations
from datetime import datetime
from functools import wraps
from pathlib import Path
from typing import Callable, Literal
import hashlib
import inspect
import json
import os
import shutil
import stat
from ._fixture_staging_model import (
    CapacityObservation,
    FixtureStagingError,
    FixtureStagingErrorCode,
    FixtureStagingGrant,
)
from . import _fixture_staging_manifest as _authority
from ._fixture_staging_manifest import _identifier, _safe_relative_path, _validate_grant_for_use
from ._fixture_staging_content import _destination_companion_edges, _file_identity, _graph_reaches_all
from ._fixture_staging_ownership import FixtureStagingOwnership, _exists_nofollow, _fsync_directory, _owned_entry_map, _rename_entry_exclusive, _validate_private_directory, _validate_session_id, _validate_tree_for_removal
from . import _fixture_staging_ownership as staging_ownership


def _admit_production_staging_namespace():
    """Refuse staging until the host provides kernel-enforced isolation.

    Identity checks can prove which directory was inspected, but they cannot
    stop another process running as the same user from moving a destination
    namespace into the source tree after that inspection. No supported host
    boundary is installed yet, so successful staging must stop before the
    first destination mutation.
    """

    raise FixtureStagingError(
        FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY
    )


def _require_exclusive_staging_namespace(capability):
    """Require explicit production authority for one destination mutation."""

    staging_ownership._require_namespace_capability(
        capability,
        origin="production",
    )
    return capability


def _coordinated_destination_change(method):
    """Serialize one destination mutation with cleanup and state updates."""

    method_signature = inspect.signature(method)

    @wraps(method)
    def coordinated(self, *args, **kwargs):
        bound = method_signature.bind(self, *args, **kwargs)
        capability = bound.arguments.get("capability")
        grant = bound.arguments.get("grant")
        self._require_destination_operation_authority(
            grant=grant,
            capability=capability,
        )
        with self._ownership.coordination_lock(capability=capability):
            return method(self, *args, **kwargs)

    return coordinated


class FilesystemFixtureDestination:
    """Private host destination that simulates a future qualification target.

    The adapter has no device transport. Capacity comes from the local
    destination filesystem after namespace admission; no caller-supplied
    capacity callback is part of the public interface. All file creation and
    readback remains on the host.
    """

    is_simulated = True
    _admission_origin = "production"
    _STATE_DIRECTORY = FixtureStagingOwnership._STATE_DIRECTORY

    def _new_ownership(self) -> FixtureStagingOwnership:
        return FixtureStagingOwnership(self.root)

    def __init__(self, root: Path) -> None:
        self.root = Path(root).absolute()
        self._ownership = self._new_ownership()

    def _require_admitted_capability(self, capability):
        """Require the exact admission class represented by this adapter."""

        self._ownership._require_mutation_capability(capability)
        return capability

    def _require_destination_operation_authority(self, *, grant, capability):
        """Validate private capability and trusted grant timing before work."""

        self._require_admitted_capability(capability)
        _validate_grant_for_use(grant, _authority._utc_now())

    def _require_record_grant_binding(self, record, grant) -> None:
        """Require durable ownership state to describe the supplied grant."""

        if (
            record.get("authorization_sha256") != grant.authorization_sha256
            or record.get("approval_sha256") != grant.approval_sha256
            or record.get("operation_id") != grant.operation_id
            or record.get("plan_sha256") != grant.plan_sha256
            or record.get("fixture_manifest_sha256")
            != grant.fixture_manifest_sha256
        ):
            raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)

    def _require_grant_state(
        self,
        session_id: str,
        *,
        grant: FixtureStagingGrant,
        capability,
        required_state: str | tuple[str, ...],
    ) -> dict[str, object]:
        """Require exact authority and an expected durable session state."""
        self._require_destination_operation_authority(
            grant=grant,
            capability=capability,
        )
        _validate_session_id(session_id)
        record = self._ownership._load_state(session_id)
        allowed_states = (
            required_state if isinstance(required_state, tuple) else (required_state,)
        )
        if record.get("state") not in allowed_states:
            raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
        self._require_record_grant_binding(record, grant)
        if not self._ownership._ownership_is_proven(record, session_id):
            raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
        self._ownership._assert_record_timing(
            record,
            mode="staging",
            clock=capability.monotonic_clock or staging_ownership._monotonic_now,
        )
        _validate_grant_for_use(grant, _authority._utc_now())
        return record

    def _require_published_grant_state(
        self,
        session_id: str,
        *,
        grant: FixtureStagingGrant,
        capability,
    ) -> dict[str, object]:
        """Require exact private authority and a live published session record.

        The capability and grant are checked before durable state is read. A
        session that is not published, was blocked, or belongs to another grant
        is rejected before this adapter resolves a payload path or opens any
        destination filesystem object.
        """
        return self._require_grant_state(
            session_id,
            grant=grant,
            capability=capability,
            required_state="published",
        )

    def _require_staging_grant_state(
        self,
        session_id: str,
        *,
        grant: FixtureStagingGrant,
        capability,
    ) -> dict[str, object]:
        """Require exact authority for an in-progress synthetic transfer.

        Preparation may verify the destination once before publication and once
        after the atomic rename records publication intent. Both phases must
        prove the same capability, grant, owner, and thread before filesystem
        contact, while remaining inaccessible through published helpers.
        """

        return self._require_grant_state(
            session_id,
            grant=grant,
            capability=capability,
            required_state=("preparing", "publication_pending"),
        )
    def _require_granted_file(
        self,
        grant: FixtureStagingGrant,
        fixture_id: str,
        relative_path: str,
    ) -> None:
        """Require a requested member to be declared by the supplied grant."""
        for fixture in grant._fixture_expectations:
            if fixture.fixture_id != fixture_id:
                continue
            if any(item.path == relative_path for item in fixture.files):
                return
        raise FixtureStagingError(FixtureStagingErrorCode.INVALID_AUTHORITY)

    def _require_owned_root_file_authority(
        self,
        session_id: str,
        fixture_id: str,
        relative_path: str,
        *,
        grant: FixtureStagingGrant,
        capability,
        access: Literal["published", "staging"],
    ) -> None:
        """Require exact authority for one owned-root file operation.

        Published access accepts only a live published session. Staging access
        is limited to the two transient synthetic preparation states. Unknown
        access modes fail closed before durable state is inspected.
        """

        if access == "published":
            self._require_published_grant_state(
                session_id,
                grant=grant,
                capability=capability,
            )
        elif access == "staging":
            self._require_staging_grant_state(
                session_id,
                grant=grant,
                capability=capability,
            )
        else:
            raise FixtureStagingError(FixtureStagingErrorCode.INVALID_AUTHORITY)
        self._require_granted_file(grant, fixture_id, relative_path)

    def _validate_root_identity(self) -> None:
        """Prove the configured destination root still has its pinned identity."""

        validated_info = _validate_private_directory(self.root)
        current_info = self.root.stat(follow_symlinks=False)
        if (current_info.st_dev, current_info.st_ino) != (
            validated_info.st_dev,
            validated_info.st_ino,
        ):
            raise FixtureStagingError(FixtureStagingErrorCode.DESTINATION_UNSAFE)

    def capacity_observation(self) -> CapacityObservation:
        """Refuse public capacity access until production admission exists."""
        _admit_production_staging_namespace()
        raise AssertionError("production capacity admission must fail closed")

    def _capacity_observation_for_staging(
        self,
        *,
        grant: FixtureStagingGrant,
        capability,
    ) -> CapacityObservation:
        """Read capacity only through the admitted private staging path."""
        self._require_destination_operation_authority(
            grant=grant,
            capability=capability,
        )
        return self._validated_capacity_observation(
            self._read_capacity_observation()
        )

    def _validated_capacity_observation(self, observation) -> CapacityObservation:
        """Validate one bounded capacity observation from the host adapter."""
        if (
            type(observation) is not CapacityObservation
            or type(observation.host_free_bytes) is not int
            or observation.host_free_bytes < 0
            or type(observation.destination_free_bytes) is not int
            or observation.destination_free_bytes < 0
        ):
            raise FixtureStagingError(FixtureStagingErrorCode.CAPACITY_UNPROVEN)
        return observation
    def _read_capacity_observation(self) -> CapacityObservation:
        """Read current host capacity without caller-controlled callbacks."""

        try:
            free_bytes = shutil.disk_usage(self.root).free
        except Exception:
            raise FixtureStagingError(FixtureStagingErrorCode.CAPACITY_UNPROVEN) from None
        return CapacityObservation(free_bytes, free_bytes)

    def _final_path(
        self,
        session_id: str,
        *,
        grant: FixtureStagingGrant,
        capability,
    ) -> Path:
        """Return a final pathname only for a live published grant.

        Consumers that need eligibility should use :meth:`eligible_root`. This
        private accessor first proves the exact capability, live grant, durable
        session ownership, and published state so a pending or blocked
        directory name cannot be obtained through it.
        """
        self._require_published_grant_state(
            session_id,
            grant=grant,
            capability=capability,
        )
        return self.root / f"fixture-{session_id}"
    def eligible_root(
        self,
        session_id: str,
        *,
        grant: FixtureStagingGrant,
    ) -> Path | None:
        """Return no production fixture until OS isolation admits eligibility."""

        try:
            _admit_production_staging_namespace()
        except FixtureStagingError:
            return None

    def _eligible_root_impl(
        self,
        session_id: str,
        *,
        grant: FixtureStagingGrant,
        capability,
    ) -> Path | None:
        """Return a current, owner-pinned fixture root only after publication.

        The durable publication state, ownership tree, grant bindings, and
        current private authorization inputs must all still be valid. Every
        published file is also hashed against the validated fixture manifest.
        """

        self._require_admitted_capability(capability)
        try:
            _validate_session_id(session_id)
            grant = _validate_grant_for_use(grant, _authority._utc_now())
            record = self._ownership._load_state(session_id)
            if (
                record.get("state") != "published"
                or record.get("authorization_sha256") != grant.authorization_sha256
                or record.get("approval_sha256") != grant.approval_sha256
                or record.get("operation_id") != grant.operation_id
                or record.get("plan_sha256") != grant.plan_sha256
                or record.get("fixture_manifest_sha256") != grant.fixture_manifest_sha256
                or not self._ownership._ownership_is_proven(record, session_id)
            ):
                return None
            self._ownership._assert_record_timing(
                record,
                mode="staging",
                clock=capability.monotonic_clock or staging_ownership._monotonic_now,
            )
            for fixture in grant._fixture_expectations:
                for expected in fixture.files:
                    digest = hashlib.sha256()
                    size = 0
                    for chunk in self._read_file_chunks(
                        session_id,
                        fixture.fixture_id,
                        expected.path,
                        grant=grant,
                        capability=capability,
                    ):
                        digest.update(chunk)
                        size += len(chunk)
                    if size != expected.size or digest.hexdigest() != expected.sha256:
                        return None
            _validate_grant_for_use(grant, _authority._utc_now())
            return self._final_path(
                session_id,
                grant=grant,
                capability=capability,
            )
        except FixtureStagingError:
            return None

    def _temporary_path(
        self,
        session_id: str,
        *,
        grant: FixtureStagingGrant,
        capability,
    ) -> Path:
        """Return a quarantine pathname only for a live published grant."""
        self._require_published_grant_state(
            session_id,
            grant=grant,
            capability=capability,
        )
        return self._ownership.temporary_root(session_id)
    def recovery_state_path(self, session_id: str) -> Path:
        """Return the private durable state record for a valid session."""

        _validate_session_id(session_id)
        return self._ownership.recovery_state_path(session_id)

    def create_quarantine(
        self,
        session_id: str,
        token: str,
        grant: FixtureStagingGrant,
    ) -> None:
        """Refuse an ungated quarantine mutation before coordination state."""

        _admit_production_staging_namespace()
        raise AssertionError("production quarantine admission must fail closed")

    @_coordinated_destination_change
    def _create_quarantine(
        self,
        session_id: str,
        token: str,
        grant: FixtureStagingGrant,
        *,
        capability=None,
    ) -> None:
        """Create a unique private temporary root and bind its inode to state."""

        self._require_admitted_capability(capability)
        record = self._ownership._load_state(session_id)
        if record.get("state") != "reserved" or record.get("ownership_token") != token:
            raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
        self._require_record_grant_binding(record, grant)
        capability.check_deadline(record, mode="staging")
        _validate_grant_for_use(grant, _authority._utc_now())
        temporary_root = self._ownership.temporary_root(session_id)
        final_path = self._ownership.final_root(session_id)
        if _exists_nofollow(temporary_root) or _exists_nofollow(final_path):
            raise FixtureStagingError(FixtureStagingErrorCode.DESTINATION_UNSAFE)
        try:
            temporary_root.mkdir(mode=0o700)
            root_info = temporary_root.lstat()
            if not stat.S_ISDIR(root_info.st_mode) or root_info.st_uid != os.geteuid() or stat.S_IMODE(root_info.st_mode) != 0o700:
                raise FixtureStagingError(FixtureStagingErrorCode.DESTINATION_UNSAFE)
            _fsync_directory(self.root)
            record.update(
                {
                    "state": "preparing",
                    "root_device": root_info.st_dev,
                    "root_inode": root_info.st_ino,
                    "owned_entries": [],
                }
            )
            self._ownership._replace_state(record, capability=capability)
            marker = {
                "schema_version": 1,
                "session_id": session_id,
                "ownership_token": token,
                "authorization_sha256": grant.authorization_sha256,
                "plan_sha256": grant.plan_sha256,
                "fixture_manifest_sha256": grant.fixture_manifest_sha256,
            }
            self._ownership._write_private_json_exclusive(
            temporary_root / ".owner.json",
            marker,
            capability=capability,
            )
            marker_info = (temporary_root / ".owner.json").lstat()
            _fsync_directory(temporary_root)
            self._ownership._record_owned_entry(
                session_id,
                token,
                "file",
                ".owner.json",
                marker_info,
                created=True,
            capability=capability,
            )
            _fsync_directory(self.root)
        except FixtureStagingError:
            raise
        except OSError:
            raise FixtureStagingError(
                FixtureStagingErrorCode.DESTINATION_UNSAFE
            ) from None

    def write_file(
        self,
        session_id: str,
        fixture_id: str,
        relative_path: str,
        chunks,
        *,
        ownership_token: str,
        source_mtime_ns: int,
    ) -> tuple[int, str]:
        """Refuse an ungated destination write before coordination state."""

        _admit_production_staging_namespace()
        raise AssertionError("production write admission must fail closed")

    @_coordinated_destination_change
    def _write_file(
        self,
        session_id: str,
        fixture_id: str,
        relative_path: str,
        chunks,
        *,
        ownership_token: str,
        source_mtime_ns: int,
        grant: FixtureStagingGrant,
        capability=None,
    ) -> tuple[int, str]:
        """Create one new file in the owned quarantine, never replacing data."""

        self._require_admitted_capability(capability)
        record = self._ownership._load_state(session_id)
        self._ownership._assert_record_owner(record, session_id, ownership_token)
        self._require_record_grant_binding(record, grant)
        capability.check_deadline(record, mode="staging")
        _validate_grant_for_use(grant, _authority._utc_now())
        root_fd = self._ownership._open_owned_root(session_id)
        parent_fd = -1
        descriptor = -1
        try:
            parent_fd = _open_destination_parent(
                root_fd,
                fixture_id,
                relative_path,
                create=True,
            capability=capability,
                on_directory=lambda path, info, created: self._ownership._record_owned_entry(
                    session_id,
                    ownership_token,
                    "directory",
                    path,
                    info,
                    created=created,
                        capability=capability,
                ),
            )
            basename = relative_path.split("/")[-1]
            owned_path = f"{fixture_id}/{relative_path}"
            stamp = _creation_stamp(session_id, ownership_token, owned_path)
            flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
            descriptor = os.open(basename, flags, 0o600, dir_fd=parent_fd)
            view = memoryview(stamp)
            while view:
                written = os.write(descriptor, view)
                if written <= 0:
                    raise FixtureStagingError(FixtureStagingErrorCode.COPY_INVALID)
                view = view[written:]
            os.fsync(descriptor)
            entry_info = os.fstat(descriptor)
            self._ownership._record_owned_entry(
                session_id,
                ownership_token,
                "file",
                owned_path,
                entry_info,
                created=True,
                capability=capability,
            )
            os.ftruncate(descriptor, 0)
            os.lseek(descriptor, 0, os.SEEK_SET)
            digest = hashlib.sha256()
            total = 0
            for chunk in chunks:
                view = memoryview(chunk)
                while view:
                    written = os.write(descriptor, view)
                    if written <= 0:
                        raise FixtureStagingError(FixtureStagingErrorCode.COPY_INVALID)
                    digest.update(view[:written])
                    total += written
                    view = view[written:]
            os.fsync(descriptor)
            os.utime(descriptor, ns=(source_mtime_ns, source_mtime_ns))
            os.fsync(descriptor)
            os.fsync(parent_fd)
            return total, digest.hexdigest()
        except FixtureStagingError:
            raise
        except OSError:
            raise FixtureStagingError(FixtureStagingErrorCode.COPY_INVALID) from None
        finally:
            if descriptor >= 0:
                os.close(descriptor)
            if parent_fd >= 0:
                os.close(parent_fd)
            os.close(root_fd)

    def _read_file_chunks(
        self,
        session_id: str,
        fixture_id: str,
        relative_path: str,
        *,
        grant: FixtureStagingGrant,
        capability,
    ):
        """Read a granted published member only after private authority checks."""
        yield from self._read_file_chunks_from_owned_root(
            session_id,
            fixture_id,
            relative_path,
            grant=grant,
            capability=capability,
            access="published",
        )

    def _read_file_chunks_for_staging(
        self,
        session_id: str,
        fixture_id: str,
        relative_path: str,
        *,
        grant: FixtureStagingGrant,
        capability,
    ):
        """Read a granted member during admitted synthetic preparation."""
        yield from self._read_file_chunks_from_owned_root(
            session_id,
            fixture_id,
            relative_path,
            grant=grant,
            capability=capability,
            access="staging",
        )

    def _read_file_chunks_from_owned_root(
        self,
        session_id: str,
        fixture_id: str,
        relative_path: str,
        *,
        grant: FixtureStagingGrant,
        capability,
        access: Literal["published", "staging"],
    ):
        """Stream one owned-root member after intrinsic authority validation.

        The supplied capability and grant are checked against the requested
        published or staging state before any owned-root descriptor, stat,
        open, read, or yielded byte is produced.
        """

        self._require_owned_root_file_authority(
            session_id,
            fixture_id,
            relative_path,
            grant=grant,
            capability=capability,
            access=access,
        )
        root_fd = self._ownership._open_owned_root(session_id)
        parent_fd = -1
        descriptor = -1
        try:
            parent_fd = _open_destination_parent(root_fd, fixture_id, relative_path, create=False)
            basename = relative_path.split("/")[-1]
            before = os.stat(basename, dir_fd=parent_fd, follow_symlinks=False)
            if (
                not stat.S_ISREG(before.st_mode)
                or before.st_uid != os.geteuid()
                or before.st_nlink != 1
                or stat.S_IMODE(before.st_mode) != 0o600
            ):
                raise FixtureStagingError(FixtureStagingErrorCode.COPY_INVALID)
            descriptor = os.open(basename, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0), dir_fd=parent_fd)
            opened = os.fstat(descriptor)
            if _file_identity(before) != _file_identity(opened):
                raise FixtureStagingError(FixtureStagingErrorCode.COPY_INVALID)
            while True:
                chunk = os.read(descriptor, 1024 * 1024)
                if not chunk:
                    break
                yield chunk
            after = os.fstat(descriptor)
            current = os.stat(basename, dir_fd=parent_fd, follow_symlinks=False)
            if _file_identity(opened) != _file_identity(after) or _file_identity(after) != _file_identity(current):
                raise FixtureStagingError(FixtureStagingErrorCode.COPY_INVALID)
        except FixtureStagingError:
            raise
        except OSError:
            raise FixtureStagingError(FixtureStagingErrorCode.COPY_INVALID) from None
        finally:
            if descriptor >= 0:
                os.close(descriptor)
            if parent_fd >= 0:
                os.close(parent_fd)
            os.close(root_fd)

    def _file_mtime_ns(
        self,
        session_id: str,
        fixture_id: str,
        relative_path: str,
        *,
        grant: FixtureStagingGrant,
        capability,
    ) -> int:
        """Read a granted published member's metadata after authority checks."""
        return self._file_mtime_ns_from_owned_root(
            session_id,
            fixture_id,
            relative_path,
            grant=grant,
            capability=capability,
            access="published",
        )

    def _file_mtime_ns_for_staging(
        self,
        session_id: str,
        fixture_id: str,
        relative_path: str,
        *,
        grant: FixtureStagingGrant,
        capability,
    ) -> int:
        """Read granted metadata during admitted synthetic preparation."""
        return self._file_mtime_ns_from_owned_root(
            session_id,
            fixture_id,
            relative_path,
            grant=grant,
            capability=capability,
            access="staging",
        )

    def _file_mtime_ns_from_owned_root(
        self,
        session_id: str,
        fixture_id: str,
        relative_path: str,
        *,
        grant: FixtureStagingGrant,
        capability,
        access: Literal["published", "staging"],
    ) -> int:
        """Read owned-root metadata after intrinsic authority validation.

        Published access requires the current published session. Staging access
        is limited to admitted synthetic preparation. Both checks complete
        before any owned-root descriptor, parent traversal, or stat operation.
        """

        self._require_owned_root_file_authority(
            session_id,
            fixture_id,
            relative_path,
            grant=grant,
            capability=capability,
            access=access,
        )
        root_fd = self._ownership._open_owned_root(session_id)
        parent_fd = -1
        try:
            parent_fd = _open_destination_parent(root_fd, fixture_id, relative_path, create=False)
            info = os.stat(relative_path.split("/")[-1], dir_fd=parent_fd, follow_symlinks=False)
            if (
                not stat.S_ISREG(info.st_mode)
                or info.st_uid != os.geteuid()
                or info.st_nlink != 1
                or stat.S_IMODE(info.st_mode) != 0o600
            ):
                raise FixtureStagingError(FixtureStagingErrorCode.COPY_INVALID)
            return info.st_mtime_ns
        except FixtureStagingError:
            raise
        except OSError:
            raise FixtureStagingError(FixtureStagingErrorCode.COPY_INVALID) from None
        finally:
            if parent_fd >= 0:
                os.close(parent_fd)
            os.close(root_fd)

    def _verify_verified_files(
        self,
        session_id: str,
        verified_files: list[dict[str, object]],
        *,
        check_deadline: Callable[[], None] | None,
        grant: FixtureStagingGrant,
        capability,
    ) -> None:
        """Rehash every verified member and its preserved metadata."""

        for item in verified_files:
            if check_deadline is not None:
                check_deadline()
            digest = hashlib.sha256()
            size = 0
            for chunk in self._read_file_chunks_for_staging(
                session_id,
                item["fixture_id"],
                item["path"],
                grant=grant,
                capability=capability,
            ):
                if check_deadline is not None:
                    check_deadline()
                digest.update(chunk)
                size += len(chunk)
            if (
                size != item["size"]
                or digest.hexdigest() != item["sha256"]
                or self._file_mtime_ns_for_staging(
                    session_id,
                    item["fixture_id"],
                    item["path"],
                    grant=grant,
                    capability=capability,
                )
                != item["mtime_ns"]
            ):
                raise FixtureStagingError(FixtureStagingErrorCode.COPY_INVALID)

    def publish(
        self,
        session_id: str,
        token: str,
        *,
        grant: FixtureStagingGrant,
    ) -> None:
        """Refuse an ungated publication before coordination state."""

        _admit_production_staging_namespace()
        raise AssertionError("production publication admission must fail closed")

    @_coordinated_destination_change
    def _publish(
        self,
        session_id: str,
        token: str,
        *,
        grant: FixtureStagingGrant,
        capability=None,
    ) -> None:
        """Persist intent, then atomically rename the verified quarantine.

        The durable intent names the temporary and final entries and pins the
        moved directory identity. It is written before the no-replace rename,
        so crashes on either side of that atomic operation leave one
        unambiguous, ineligible recovery state.
        """

        self._require_destination_operation_authority(
            grant=grant,
            capability=capability,
        )
        publication_intent_persisted = False
        record = self._ownership._load_state(session_id)
        self._ownership._assert_record_owner(record, session_id, token)
        def check_deadline() -> None:
            capability.check_deadline(record, mode="staging")

        record = self._ownership._load_state(session_id)
        self._ownership._assert_record_owner(record, session_id, token)
        self._require_record_grant_binding(record, grant)
        check_deadline()
        root_descriptor = self._ownership._open_owned_root(session_id)
        parent_descriptor = -1
        try:
            if record.get("state") != "preparing":
                raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
            expected_files = record.get("expected_files")
            verified_files = record.get("verified_files")
            if type(expected_files) is not list or type(verified_files) is not list:
                raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
            verified_expectations = [
                {
                    "fixture_id": item.get("fixture_id"),
                    "path": item.get("path"),
                    "size": item.get("size"),
                    "sha256": item.get("sha256"),
                }
                for item in verified_files
                if type(item) is dict
            ]
            if len(verified_expectations) != len(verified_files) or verified_expectations != expected_files:
                raise FixtureStagingError(FixtureStagingErrorCode.COPY_INVALID)
            grant_files = [
                {
                    "fixture_id": fixture.fixture_id,
                    "path": item.path,
                    "size": item.size,
                    "sha256": item.sha256,
                }
                for fixture in grant._fixture_expectations
                for item in fixture.files
            ]
            if expected_files != grant_files:
                raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
            ownership = _owned_entry_map(record)
            expected_paths = {".owner.json"}
            for item in expected_files:
                if type(item) is not dict:
                    raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
                fixture_id = _identifier(item.get("fixture_id"))
                relative_path = _safe_relative_path(item.get("path"))
                member_path = f"{fixture_id}/{relative_path}"
                expected_paths.add(member_path)
                parts = member_path.split("/")
                expected_paths.update(
                    "/".join(parts[:index]) for index in range(1, len(parts))
                )
            if set(ownership) != expected_paths:
                raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
            for path, (kind, _device, _inode) in ownership.items():
                expected_kind = "file" if path == ".owner.json" or path in {
                    f"{_identifier(item['fixture_id'])}/{_safe_relative_path(item['path'])}"
                    for item in expected_files
                } else "directory"
                if kind != expected_kind:
                    raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
            _validate_tree_for_removal(root_descriptor, ownership)
            for fixture in grant._fixture_expectations:
                edges = _destination_companion_edges(
                    self,
                    session_id,
                    fixture,
                    grant=grant,
                    capability=capability,
                )
                if edges != fixture.companions or not _graph_reaches_all(fixture, edges):
                    raise FixtureStagingError(FixtureStagingErrorCode.COPY_INVALID)
            self._verify_verified_files(
                session_id,
                verified_files,
                check_deadline=check_deadline,
                grant=grant,
                capability=capability,
            )
            check_deadline()
            _validate_grant_for_use(grant, _authority._utc_now())
            check_deadline()

            parent_descriptor = os.open(
                self.root,
                os.O_RDONLY
                | getattr(os, "O_DIRECTORY", 0)
                | getattr(os, "O_NOFOLLOW", 0),
            )
            opened_parent = os.fstat(parent_descriptor)
            path_parent = self.root.lstat()
            if (
                (opened_parent.st_dev, opened_parent.st_ino)
                != (record.get("parent_device"), record.get("parent_inode"))
                or (path_parent.st_dev, path_parent.st_ino)
                != (opened_parent.st_dev, opened_parent.st_ino)
            ):
                raise FixtureStagingError(FixtureStagingErrorCode.DESTINATION_UNSAFE)

            source_name = self._ownership.temporary_root(session_id).name
            final_name = self._ownership.final_root(session_id).name
            opened_root = os.fstat(root_descriptor)
            source_info = os.stat(
                source_name,
                dir_fd=parent_descriptor,
                follow_symlinks=False,
            )
            if (
                not stat.S_ISDIR(source_info.st_mode)
                or (source_info.st_dev, source_info.st_ino)
                != (opened_root.st_dev, opened_root.st_ino)
                or (source_info.st_dev, source_info.st_ino)
                != (record.get("root_device"), record.get("root_inode"))
            ):
                raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)

            record["publication_intent"] = {
                "temporary_name": source_name,
                "final_name": final_name,
                "root_device": opened_root.st_dev,
                "root_inode": opened_root.st_ino,
            }
            record["state"] = "publication_pending"
            self._ownership._replace_state(record, capability=capability)
            publication_intent_persisted = True
            check_deadline()
            _validate_grant_for_use(grant, _authority._utc_now())
            check_deadline()

            # The open directory descriptor is the verified source object. The
            # rename still operates on a namespace entry, so immediately prove
            # that the published entry is that same object.
            _rename_entry_exclusive(
                parent_descriptor,
                source_name,
                parent_descriptor,
                final_name,
                capability=capability,
            )
            published_info = os.stat(
                final_name,
                dir_fd=parent_descriptor,
                follow_symlinks=False,
            )
            if (
                not stat.S_ISDIR(published_info.st_mode)
                or (published_info.st_dev, published_info.st_ino)
                != (opened_root.st_dev, opened_root.st_ino)
            ):
                raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
            os.fsync(parent_descriptor)

            # A same-user process can mutate the original directory in place
            # after the pre-rename proof. Recheck the exact tree and bytes
            # through the object that was moved before making it eligible.
            _validate_tree_for_removal(root_descriptor, ownership)
            self._verify_verified_files(
                session_id,
                verified_files,
                check_deadline=check_deadline,
                grant=grant,
                capability=capability,
            )
            check_deadline()
            _validate_grant_for_use(grant, _authority._utc_now())
            check_deadline()
        except FixtureStagingError as error:
            if publication_intent_persisted and not self._ownership.mark_blocked(
                session_id,
                token,
                error.code,
                capability=capability,
            ):
                raise FixtureStagingError(
                    FixtureStagingErrorCode.DESTINATION_UNSAFE
                ) from None
            raise
        except OSError:
            if publication_intent_persisted and not self._ownership.mark_blocked(
                session_id,
                token,
                FixtureStagingErrorCode.DESTINATION_UNSAFE,
                capability=capability,
            ):
                raise FixtureStagingError(
                    FixtureStagingErrorCode.DESTINATION_UNSAFE
                ) from None
            raise FixtureStagingError(FixtureStagingErrorCode.DESTINATION_UNSAFE) from None
        finally:
            if parent_descriptor >= 0:
                os.close(parent_descriptor)
            os.close(root_descriptor)

    def confirm_publication(
        self,
        session_id: str,
        token: str,
        *,
        grant: FixtureStagingGrant,
    ) -> None:
        """Refuse an ungated publication confirmation before state access."""

        _admit_production_staging_namespace()
        raise AssertionError(
            "production publication confirmation admission must fail closed"
        )

    @_coordinated_destination_change
    def _confirm_publication(
        self,
        session_id: str,
        token: str,
        *,
        grant: FixtureStagingGrant,
        capability=None,
    ) -> None:
        """Make a published tree eligible after post-rename authority checks."""

        self._require_destination_operation_authority(
            grant=grant,
            capability=capability,
        )
        record = self._ownership._load_state(session_id)
        self._ownership._assert_record_owner(record, session_id, token)

        def check_deadline() -> None:
            capability.check_deadline(record, mode="staging")

        check_deadline()
        self._require_record_grant_binding(record, grant)
        if (
            record.get("state") != "publication_pending"
            or not self._ownership._ownership_is_proven(record, session_id)
        ):
            raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
        if not _exists_nofollow(
            self._ownership.final_root(session_id)
        ) or _exists_nofollow(
            self._ownership.temporary_root(session_id)
        ):
            raise FixtureStagingError(FixtureStagingErrorCode.OWNERSHIP_UNPROVEN)
        check_deadline()
        _validate_grant_for_use(grant, _authority._utc_now())
        record["state"] = "published"
        self._ownership._replace_state(record, capability=capability)
        try:
            check_deadline()
            _validate_grant_for_use(grant, _authority._utc_now())
        except FixtureStagingError as error:
            if not self._ownership.mark_blocked(
                session_id,
                token,
                error.code,
                capability=capability,
            ):
                raise FixtureStagingError(
                    FixtureStagingErrorCode.DESTINATION_UNSAFE
                ) from None
            raise

    def _publish_and_confirm(
        self,
        session_id: str,
        token: str,
        *,
        grant: FixtureStagingGrant,
        capability=None,
    ) -> None:
        """Recheck authorization around publication and eligibility confirmation."""

        self._require_destination_operation_authority(
            grant=grant,
            capability=capability,
        )
        self._publish(
            session_id,
            token,
            grant=grant,
            capability=capability,
        )
        _validate_grant_for_use(grant, _authority._utc_now())
        self._confirm_publication(
            session_id,
            token,
            grant=grant,
            capability=capability,
        )
        _validate_grant_for_use(grant, _authority._utc_now())


def _open_destination_parent(
    root_descriptor: int,
    fixture_id: str,
    relative_path: str,
    *,
    create: bool,
    capability=None,
    before_directory=None,
    on_directory_failure=None,
    on_directory=None,
) -> int:
    if create:
        staging_ownership._require_namespace_capability(capability)
    _identifier(fixture_id)
    _safe_relative_path(relative_path)
    components = [fixture_id, *relative_path.split("/")[:-1]]
    current = os.dup(root_descriptor)
    try:
        for index, component in enumerate(components):
            created = False
            try:
                info = os.stat(component, dir_fd=current, follow_symlinks=False)
            except FileNotFoundError:
                if not create:
                    raise FixtureStagingError(FixtureStagingErrorCode.COPY_INVALID)
                relative_directory = "/".join(components[: index + 1])
                if before_directory is not None:
                    before_directory(relative_directory)
                created_directory = False
                try:
                    os.mkdir(component, mode=0o700, dir_fd=current)
                    created_directory = True
                    os.fsync(current)
                    info = os.stat(component, dir_fd=current, follow_symlinks=False)
                    created = True
                except FileExistsError:
                    if on_directory_failure is not None and not created_directory:
                        on_directory_failure(relative_directory)
                    raise FixtureStagingError(FixtureStagingErrorCode.COPY_INVALID) from None
                except OSError:
                    if on_directory_failure is not None and not created_directory:
                        on_directory_failure(relative_directory)
                    raise FixtureStagingError(FixtureStagingErrorCode.COPY_INVALID) from None
            if (
                not stat.S_ISDIR(info.st_mode)
                or info.st_uid != os.geteuid()
                or stat.S_IMODE(info.st_mode) != 0o700
            ):
                raise FixtureStagingError(FixtureStagingErrorCode.COPY_INVALID)
            try:
                next_descriptor = os.open(
                    component,
                    os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0),
                    dir_fd=current,
                )
            except OSError:
                raise FixtureStagingError(FixtureStagingErrorCode.COPY_INVALID) from None
            opened = os.fstat(next_descriptor)
            if (opened.st_dev, opened.st_ino) != (info.st_dev, info.st_ino):
                os.close(next_descriptor)
                raise FixtureStagingError(FixtureStagingErrorCode.COPY_INVALID)
            if on_directory is not None:
                try:
                    on_directory("/".join(components[: index + 1]), opened, created)
                except BaseException:
                    os.close(next_descriptor)
                    raise
            os.close(current)
            current = next_descriptor
        return current
    except BaseException:
        os.close(current)
        raise

def _creation_stamp(session_id: str, token: str, relative_path: str) -> bytes:
    """Return a small ownership proof written before a new file is ledgered."""

    return json.dumps(
        {
            "fixture_staging_creation": 1,
            "session_id": session_id,
            "ownership_token": token,
            "path": relative_path,
        },
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
