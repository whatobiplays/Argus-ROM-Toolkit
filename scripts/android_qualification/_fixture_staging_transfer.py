"""Apply staging deadlines and stream validated source bytes to a destination."""

from __future__ import annotations
from datetime import datetime
import hashlib
import os
from pathlib import Path
from ._fixture_staging_model import (
    FixtureStagingError,
    FixtureStagingErrorCode,
    FixtureStagingGrant,
    _check_operation_timing,
    _new_operation_timing,
)

from ._fixture_staging_content import _SourceSnapshot, _close_source_member, _destination_companion_edges, _file_identity, _graph_reaches_all, _open_source_member, _preflight_sources, _verify_source_path
from typing import TYPE_CHECKING, Callable
if TYPE_CHECKING:
    from ._fixture_staging_destination import FilesystemFixtureDestination


def _staging_deadline_checker(
    grant: FixtureStagingGrant,
    instant: datetime,
    clock,
    *,
    operation_timing: dict[str, object] | None = None,
) -> Callable[[], None]:
    """Build the operation and authorization checks for one staging run."""

    timing = operation_timing or _new_operation_timing(grant, instant, clock)

    def check_deadline() -> None:
        _check_operation_timing(
            timing,
            clock=clock,
            mode="staging",
        )

    check_deadline()
    return check_deadline


def _ensure_capacity(
    destination: FilesystemFixtureDestination,
    grant: FixtureStagingGrant,
    remaining_bytes: int,
    *,
    check_deadline=None,
    capability,
) -> None:
    destination._require_destination_operation_authority(
        grant=grant,
        capability=capability,
    )
    if check_deadline is not None:
        check_deadline()
    observation = destination._capacity_observation_for_staging(
        grant=grant,
        capability=capability,
    )
    if check_deadline is not None:
        check_deadline()
    if (
        observation.host_free_bytes < remaining_bytes + grant.host_reserve_bytes
        or observation.destination_free_bytes < remaining_bytes + grant.destination_reserve_bytes
    ):
        raise FixtureStagingError(FixtureStagingErrorCode.CAPACITY_INSUFFICIENT)


def _preflight_staging_sources(
    destination: FilesystemFixtureDestination,
    grant: FixtureStagingGrant,
    source_roots: dict[str, Path],
    *,
    capability,
    capacity_access_admission: Callable[[], object],
) -> tuple[tuple[_SourceSnapshot, ...], int, object]:
    """Pin sources only after exact private capability and grant validation.

    The optional admission callback remains after source inspection so a
    caller can recheck a namespace after the preflight race window. That
    callback and every source or destination probe run only after the
    capability, owner, thread, and trusted grant state have been validated.
    """
    destination._require_destination_operation_authority(
        grant=grant,
        capability=capability,
    )
    destination._validate_root_identity()
    snapshots, total_bytes = _preflight_sources(
        grant._fixture_expectations,
        source_roots,
        destination.root,
    )
    admitted_capability = capacity_access_admission()
    if admitted_capability is not capability:
        raise FixtureStagingError(FixtureStagingErrorCode.INVALID_AUTHORITY)
    return snapshots, total_bytes, capability

def _stream_source(
    snapshot: _SourceSnapshot,
    *,
    destination: FilesystemFixtureDestination,
    grant: FixtureStagingGrant,
    total_bytes: int,
    copied_bytes: list[int],
    check_deadline=None,
    cancellation=None,
    capability,
):
    destination._require_destination_operation_authority(
        grant=grant,
        capability=capability,
    )
    descriptor, parent_descriptor, basename, opened, identity = _open_source_member(
        snapshot.root,
        snapshot.expectation.path,
        snapshot.directory_identities,
        root_hierarchy=snapshot.root_hierarchy,
    )
    try:
        if (
            identity != (snapshot.root_device, snapshot.root_inode)
            or _file_identity(opened) != snapshot.file_identity
        ):
            raise FixtureStagingError(FixtureStagingErrorCode.SOURCE_CHANGED)
        digest = hashlib.sha256()
        size = 0
        while True:
            if check_deadline is not None:
                check_deadline()
            if cancellation is not None and cancellation():
                raise FixtureStagingError(FixtureStagingErrorCode.COPY_INVALID)
            _ensure_capacity(
                destination,
                grant,
                total_bytes - copied_bytes[0],
                check_deadline=check_deadline,
            capability=capability,
            )
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            if size + len(chunk) > snapshot.expectation.size:
                raise FixtureStagingError(FixtureStagingErrorCode.SOURCE_CHANGED)
            digest.update(chunk)
            size += len(chunk)
            copied_bytes[0] += len(chunk)
            yield chunk
        after = os.fstat(descriptor)
        current = os.stat(basename, dir_fd=parent_descriptor, follow_symlinks=False)
        if (
            _file_identity(after) != snapshot.file_identity
            or _file_identity(current) != snapshot.file_identity
            or size != snapshot.expectation.size
            or digest.hexdigest() != snapshot.expectation.sha256
        ):
            raise FixtureStagingError(FixtureStagingErrorCode.SOURCE_CHANGED)
        _verify_source_path(snapshot)
    except FixtureStagingError:
        raise
    except OSError:
        raise FixtureStagingError(FixtureStagingErrorCode.SOURCE_CHANGED) from None
    finally:
        _close_source_member(descriptor, parent_descriptor)


def _transfer_and_verify_fixture_set(
    snapshots: list[_SourceSnapshot],
    *,
    destination: FilesystemFixtureDestination,
    grant: FixtureStagingGrant,
    session_id: str,
    ownership_token: str,
    total_bytes: int,
    copied_bytes: list[int],
    verified_bytes: list[int],
    check_deadline: Callable[[], None],
    cancellation=None,
    capability,
) -> int:
    """Transfer pinned inputs, verify destination bytes, and recheck sources."""

    destination._require_destination_operation_authority(
        grant=grant,
        capability=capability,
    )
    for snapshot in snapshots:
        check_deadline()
        _ensure_capacity(
            destination,
            grant,
            total_bytes - copied_bytes[0],
            check_deadline=check_deadline,
            capability=capability,
        )
        streamed_size, streamed_digest = destination._write_file(
            session_id,
            snapshot.fixture_id,
            snapshot.expectation.path,
            _stream_source(
                snapshot,
                destination=destination,
                grant=grant,
                total_bytes=total_bytes,
                copied_bytes=copied_bytes,
                check_deadline=check_deadline,
                cancellation=cancellation,
                capability=capability,
            ),
            ownership_token=ownership_token,
            source_mtime_ns=snapshot.file_identity[3],
            grant=grant,
            capability=capability,
        )
        check_deadline()
        if (
            streamed_size != snapshot.expectation.size
            or streamed_digest != snapshot.expectation.sha256
        ):
            raise FixtureStagingError(FixtureStagingErrorCode.SOURCE_CHANGED)

    for fixture in grant._fixture_expectations:
        for expected in fixture.files:
            check_deadline()
            digest = hashlib.sha256()
            size = 0
            for chunk in destination._read_file_chunks_for_staging(
                session_id,
                fixture.fixture_id,
                expected.path,
                grant=grant,
                capability=capability,
            ):
                check_deadline()
                digest.update(chunk)
                size += len(chunk)
            if size != expected.size or digest.hexdigest() != expected.sha256:
                raise FixtureStagingError(FixtureStagingErrorCode.COPY_INVALID)
            snapshot = next(
                item
                for item in snapshots
                if item.fixture_id == fixture.fixture_id
                and item.expectation.path == expected.path
            )
            check_deadline()
            if (
                destination._file_mtime_ns_for_staging(
                    session_id,
                    fixture.fixture_id,
                    expected.path,
                    grant=grant,
                    capability=capability,
                )
                != snapshot.file_identity[3]
            ):
                raise FixtureStagingError(FixtureStagingErrorCode.COPY_INVALID)
            destination._ownership.record_verified_file(
                session_id,
                ownership_token,
                fixture.fixture_id,
                expected,
                snapshot.file_identity[3],
                grant=grant,
                capability=capability,
            )
            verified_bytes[0] += size
        check_deadline()
        destination_edges = _destination_companion_edges(
            destination,
            session_id,
            fixture,
            check_deadline=check_deadline,
            grant=grant,
            capability=capability,
        )
        if (
            destination_edges != fixture.companions
            or not _graph_reaches_all(fixture, destination_edges)
        ):
            raise FixtureStagingError(FixtureStagingErrorCode.COPY_INVALID)

    for snapshot in snapshots:
        check_deadline()
        descriptor, parent_descriptor, _basename, opened, identity = (
            _open_source_member(
                snapshot.root,
                snapshot.expectation.path,
                snapshot.directory_identities,
                root_hierarchy=snapshot.root_hierarchy,
            )
        )
        try:
            if (
                identity != (snapshot.root_device, snapshot.root_inode)
                or _file_identity(opened) != snapshot.file_identity
            ):
                raise FixtureStagingError(FixtureStagingErrorCode.SOURCE_CHANGED)
        finally:
            _close_source_member(descriptor, parent_descriptor)
    check_deadline()
    return verified_bytes[0]
