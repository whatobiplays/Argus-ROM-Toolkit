"""Validate the Python side of the installed native fixture-staging boundary.

This module accepts only fixed installation locations and canonical native
results. It validates declarations and bindings; it does not create owner
approval, prove that source bytes were read, or make a manifest authoritative.
"""

from __future__ import annotations

import os
import hashlib
import select
import signal
import stat
import subprocess
import time
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from types import MappingProxyType
from typing import Callable, Mapping

from . import _fixture_staging_manifest as _authority
from . import fixture_oracle
from ._fixture_staging_manifest import _validate_grant_for_use
from ._fixture_staging_model import (
    FixtureStagingError,
    FixtureStagingErrorCode,
    FixtureStagingGrant,
)


POLICY_PATH = Path("/Library/PrivilegedHelperTools/ArgusFixtureStaging/installation.json")
SERVICE_PATH = Path("/Library/PrivilegedHelperTools/ArgusFixtureStaging/argus-staging-service")
BROKER_PATH = Path(
    "/Library/PrivilegedHelperTools/ArgusFixtureStaging/"
    "ArgusStagingBroker.app/Contents/MacOS/ArgusStagingBroker"
)
PRODUCTION_STAGING_ROOT = "/private/var/db/argus-qualification/staging"
MAX_POLICY_BYTES = 16 * 1024
MAX_NATIVE_PROBE_BYTES = 16 * 1024
_RUN_BOUNDED_TIMEOUT_SECONDS = 5
RECEIPT_QUERY_TIMEOUT_NS = 5_000_000_000
_READINESS_REQUEST_ID = "native-readiness"
_INSTALLATION_SEAL = object()
_OWNER_EXPORT_PREPARATION_SEAL = object()


class SnapshotSupport(str, Enum):
    """Evidence strength; none is equivalent to an owner verdict."""

    SYNTHETIC_ONLY = "synthetic_only"
    PINNED_UNVERIFIED = "pinned_unverified"
    VERIFIED_INDEPENDENT_REFERENCE = "verified_independent_reference"


@dataclass(frozen=True)
class VerifiedNativeInstallation:
    """Fixed-path installation identities returned by authenticated probes."""

    installation_id: str
    service_boot_id: str
    broker_revision: str
    owner_key_id: str
    policy_sha256: str
    service_ready: bool
    broker_ready: bool
    operation_enabled: bool
    _seal: object = field(repr=False, compare=False)

    def __post_init__(self) -> None:
        if self._seal is not _INSTALLATION_SEAL:
            raise TypeError("native installation must come from its trusted probe")


@dataclass(frozen=True)
class ProductionOwnerExportPreparation:
    """Grant-bound export inputs whose native preparation is deferred to staging."""

    grant: FixtureStagingGrant = field(repr=False, compare=False)
    attempt_manifest_sha256: str
    attempt_authorization_sha256: str
    _authorization_path: Path = field(repr=False, compare=False)
    _documents: Mapping[str, object] = field(repr=False, compare=False)
    _prepare: Callable[[VerifiedNativeInstallation], object] = field(
        repr=False, compare=False
    )
    _seal: object = field(repr=False, compare=False)

    def __post_init__(self) -> None:
        if self._seal is not _OWNER_EXPORT_PREPARATION_SEAL or not callable(
            self._prepare
        ):
            raise TypeError("owner export preparation must come from its factory")


def _freeze_export_input(value):
    """Copy JSON-like export inputs into immutable mappings and sequences."""

    if isinstance(value, Mapping):
        return MappingProxyType(
            {key: _freeze_export_input(item) for key, item in value.items()}
        )
    if isinstance(value, (list, tuple)):
        return tuple(_freeze_export_input(item) for item in value)
    return value


def _validate_production_owner_export_preparation_inputs(
    grant: FixtureStagingGrant,
    preparation: ProductionOwnerExportPreparation,
) -> None:
    """Verify the exact staged inputs against the grant before native work."""

    if (
        preparation.grant is not grant
        or preparation.attempt_manifest_sha256 != grant.fixture_manifest_sha256
        or preparation.attempt_authorization_sha256 != grant.authorization_sha256
    ):
        raise FixtureStagingError(FixtureStagingErrorCode.INVALID_AUTHORITY)
    manifest_bytes = preparation._documents.get("manifest")
    if (
        type(manifest_bytes) is not bytes
        or hashlib.sha256(manifest_bytes).hexdigest()
        != grant.fixture_manifest_sha256
    ):
        raise FixtureStagingError(FixtureStagingErrorCode.INVALID_AUTHORITY)
    authorization_document, _encoded, _pin = _authority._private_document(
        preparation._authorization_path
    )
    if (
        _authority._canonical_sha256(authorization_document)
        != grant.authorization_sha256
    ):
        raise FixtureStagingError(FixtureStagingErrorCode.INVALID_AUTHORITY)


@dataclass(frozen=True)
class ValidatedSnapshotContract:
    """Python oracle validation bound to a grant, without staging authority."""

    contract: fixture_oracle.SnapshotContract
    support: SnapshotSupport


@dataclass(frozen=True)
class ValidatedNativeContractResult:
    """Cross-checked native admission result with authority fields separated."""

    manifest_sha256: str
    source_authority: str
    selected_fixture_ids: tuple[str, ...]
    oracle_support: tuple[SnapshotSupport, ...]
    owner_consent: str
    owner_approval: str
    byte_integrity: str
    store_result: bytes


def _fixed_file(path: Path, *, maximum: int | None = None) -> bytes:
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise FixtureStagingError(FixtureStagingErrorCode.INPUT_UNAVAILABLE) from error
    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != 0:
            raise FixtureStagingError(FixtureStagingErrorCode.DESTINATION_UNSAFE)
        if metadata.st_mode & (stat.S_IWGRP | stat.S_IWOTH):
            raise FixtureStagingError(FixtureStagingErrorCode.DESTINATION_UNSAFE)
        if maximum is not None and not 0 < metadata.st_size <= maximum:
            raise FixtureStagingError(FixtureStagingErrorCode.INPUT_TOO_LARGE)
        chunks: list[bytes] = []
        remaining = maximum
        while True:
            request = 8192 if remaining is None else min(8192, remaining + 1)
            chunk = os.read(descriptor, request)
            if not chunk:
                break
            chunks.append(chunk)
            if remaining is not None:
                remaining -= len(chunk)
                if remaining < 0:
                    raise FixtureStagingError(FixtureStagingErrorCode.INPUT_TOO_LARGE)
        return b"".join(chunks)
    finally:
        os.close(descriptor)


def _ordered_session_responses_match(responses, requests) -> bool:
    """Require one successful response for each workflow request, in order."""

    return len(responses) == len(requests) and all(
        isinstance(response, Mapping)
        and isinstance(request, Mapping)
        and response.get("status") == "OK"
        and response.get("request_id") == request.get("request_id")
        for response, request in zip(responses, requests, strict=True)
    )


def _require_root_executable(path: Path) -> None:
    """Require a root-owned executable beneath secure root-owned directories."""

    try:
        metadata = os.lstat(path)
        if (
            not stat.S_ISREG(metadata.st_mode)
            or metadata.st_uid != 0
            or metadata.st_mode & (stat.S_IWGRP | stat.S_IWOTH)
            or not os.access(path, os.X_OK)
        ):
            raise FixtureStagingError(
                FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY
            )
        for parent in path.parents:
            metadata = os.lstat(parent)
            if (
                not stat.S_ISDIR(metadata.st_mode)
                or metadata.st_uid != 0
                or metadata.st_mode & (stat.S_IWGRP | stat.S_IWOTH)
            ):
                raise FixtureStagingError(
                    FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY
                )
    except OSError as error:
        raise FixtureStagingError(
            FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY
        ) from error


def _run_bounded(
    path: Path, arguments: tuple[str, ...], *, input_bytes: bytes | None = None
) -> tuple[int, bytes]:
    """Run one fixed helper while keeping stdout and wall time strictly bounded."""

    process = subprocess.Popen(
        (str(path), *arguments),
        stdin=subprocess.PIPE if input_bytes is not None else subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        cwd="/",
        env={"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C"},
        start_new_session=True,
    )
    deadline = time.monotonic() + _RUN_BOUNDED_TIMEOUT_SECONDS
    output = bytearray()
    assert process.stdout is not None
    stdout_fd = process.stdout.fileno()
    stdin_fd = process.stdin.fileno() if process.stdin is not None else None
    input_offset = 0
    stdin_open = stdin_fd is not None
    stdout_eof = False
    try:
        os.set_blocking(stdout_fd, False)
        if stdin_fd is not None:
            os.set_blocking(stdin_fd, False)
            if not input_bytes:
                process.stdin.close()
                stdin_open = False
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise subprocess.TimeoutExpired(
                    (str(path), *arguments), _RUN_BOUNDED_TIMEOUT_SECONDS
                )
            read_fds = () if stdout_eof else (stdout_fd,)
            write_fds = (
                (stdin_fd,)
                if stdin_open and input_offset < len(input_bytes or b"")
                else ()
            )
            if read_fds or write_fds:
                readable, writable, _ = select.select(
                    read_fds, write_fds, (), remaining
                )
                if not readable and not writable:
                    raise subprocess.TimeoutExpired(
                        (str(path), *arguments), _RUN_BOUNDED_TIMEOUT_SECONDS
                    )
            else:
                if process.poll() is not None:
                    break
                time.sleep(min(remaining, 0.05))
                continue

            if stdout_fd in readable:
                chunk = os.read(
                    stdout_fd,
                    min(8192, MAX_NATIVE_PROBE_BYTES + 1 - len(output)),
                )
                if not chunk:
                    stdout_eof = True
                else:
                    output.extend(chunk)
                    if len(output) > MAX_NATIVE_PROBE_BYTES:
                        raise FixtureStagingError(
                            FixtureStagingErrorCode.INPUT_TOO_LARGE
                        )

            if stdin_fd is not None and stdin_fd in writable:
                try:
                    written = os.write(
                        stdin_fd,
                        memoryview(input_bytes)[input_offset : input_offset + 8192],
                    )
                except BrokenPipeError:
                    input_offset = len(input_bytes)
                else:
                    input_offset += written
                if input_offset >= len(input_bytes):
                    process.stdin.close()
                    stdin_open = False

            if stdout_eof and process.poll() is not None:
                break
        remaining = max(0.0, deadline - time.monotonic())
        return process.wait(timeout=remaining), bytes(output)
    except Exception:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        except OSError:
            if process.poll() is None:
                process.kill()
        process.wait()
        raise
    finally:
        if process.stdin is not None and not process.stdin.closed:
            process.stdin.close()
        process.stdout.close()


class _BrokerLineSession:
    """Keep one installed broker process alive across prepare and dispatch frames."""

    _MAX_STREAM_BYTES = fixture_oracle.MAX_BROKER_SESSION_LINE_BYTES

    def __init__(self, arguments: tuple[str, ...], pass_fds: tuple[int, ...], deadline_ns: int):
        self.deadline_ns = deadline_ns
        self.process = subprocess.Popen(
            (str(BROKER_PATH), *arguments),
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd="/",
            env={"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C"},
            pass_fds=pass_fds,
            close_fds=True,
            bufsize=0,
        )
        assert self.process.stdin is not None
        assert self.process.stdout is not None
        assert self.process.stderr is not None
        self.stdin_fd = self.process.stdin.fileno()
        self.stdout_fd = self.process.stdout.fileno()
        self.stderr_fd = self.process.stderr.fileno()
        self.stdout_buffer = bytearray()
        self.stdout_lines: list[bytes] = []
        self.stdout_frames: list[bytes] = []
        self.stdout_bytes_read = 0
        self.stderr_bytes = bytearray()
        self.stdout_eof = False
        self.stderr_eof = False

    def exchange(self, request: Mapping[str, object]) -> Mapping[str, object]:
        try:
            self._write_request(request)
            line = self._read_stdout_line()
            response = fixture_oracle.decode_document(
                line, maximum_bytes=fixture_oracle.MAX_BROKER_SESSION_DOCUMENT_BYTES
            )
            if not isinstance(response, dict):
                raise ValueError("broker session response is not an object")
            return response
        except Exception:
            self.abort()
            raise

    def send(self, request: Mapping[str, object]) -> None:
        """Write one request line without consuming the broker's later replies.

        Some broker commands emit several workflow responses and no separate
        command acknowledgment. Callers use this method for those commands and
        collect their response frames while draining the session.
        """

        try:
            self._write_request(request)
        except Exception:
            self.abort()
            raise

    def _write_request(self, request: Mapping[str, object]) -> None:
        wire = fixture_oracle.canonical_json(
            request, maximum_bytes=fixture_oracle.MAX_BROKER_SESSION_DOCUMENT_BYTES
        ) + b"\n"
        offset = 0
        while offset < len(wire):
            self._remaining()
            _, writable, _ = select.select((), (self.stdin_fd,), (), self._timeout())
            if not writable:
                raise subprocess.TimeoutExpired(self.process.args, 0)
            try:
                offset += os.write(self.stdin_fd, wire[offset:])
            except BrokenPipeError as error:
                raise FixtureStagingError(
                    FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY
                ) from error

    def finish(
        self, *, after_response_count: int = 0
    ) -> tuple[list[Mapping[str, object]], bytes]:
        """Drain the broker and return responses after the supplied stream cursor."""

        if self.process.stdin is not None and not self.process.stdin.closed:
            self.process.stdin.close()
        try:
            while not (self.stdout_eof and self.stderr_eof):
                self._remaining()
                streams = []
                if not self.stdout_eof:
                    streams.append(self.stdout_fd)
                if not self.stderr_eof:
                    streams.append(self.stderr_fd)
                readable, _, _ = select.select(streams, (), (), self._timeout())
                if not readable:
                    raise subprocess.TimeoutExpired(self.process.args, 0)
                self._read_ready(readable)
            remaining = max(0.0, (self.deadline_ns - time.monotonic_ns()) / 1_000_000_000)
            returncode = self.process.wait(timeout=remaining)
            lines = self._take_buffered_lines()
            decoded = [
                fixture_oracle.decode_document(
                    line, maximum_bytes=fixture_oracle.MAX_BROKER_SESSION_DOCUMENT_BYTES
                )
                for line in lines if line.strip()
            ]
            if returncode != 0:
                raise FixtureStagingError(
                    FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY
                )
            return decoded[after_response_count:], bytes(self.stderr_bytes)
        except Exception:
            self.abort()
            raise
        finally:
            for stream in (self.process.stdin, self.process.stdout, self.process.stderr):
                if stream is not None and not stream.closed:
                    stream.close()

    def abort(self) -> None:
        if self.process.poll() is None:
            self.process.kill()
            self.process.wait()
        for stream in (self.process.stdin, self.process.stdout, self.process.stderr):
            if stream is not None and not stream.closed:
                stream.close()

    def _read_stdout_line(self) -> bytes:
        while not self.stdout_frames:
            self._remaining()
            streams = [self.stdout_fd]
            if not self.stderr_eof:
                streams.append(self.stderr_fd)
            readable, _, _ = select.select(streams, (), (), self._timeout())
            if not readable:
                raise subprocess.TimeoutExpired(self.process.args, 0)
            self._read_ready(readable)
            if self.stdout_eof and not self.stdout_frames:
                raise FixtureStagingError(
                    FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY
                )
        line = self.stdout_frames.pop(0)
        self.stdout_lines.append(line)
        return line

    def _read_ready(self, readable: list[int]) -> None:
        for descriptor in readable:
            chunk = os.read(descriptor, 8192)
            if descriptor == self.stdout_fd:
                if not chunk:
                    self.stdout_eof = True
                    continue
                self.stdout_bytes_read += len(chunk)
                if self.stdout_bytes_read > self._MAX_STREAM_BYTES:
                    raise FixtureStagingError(FixtureStagingErrorCode.INPUT_TOO_LARGE)
                self.stdout_buffer.extend(chunk)
                while b"\n" in self.stdout_buffer:
                    line, _, rest = self.stdout_buffer.partition(b"\n")
                    self.stdout_frames.append(bytes(line))
                    self.stdout_buffer = bytearray(rest)
            else:
                if not chunk:
                    self.stderr_eof = True
                    continue
                self.stderr_bytes.extend(chunk)
                if len(self.stderr_bytes) > self._MAX_STREAM_BYTES:
                    raise FixtureStagingError(FixtureStagingErrorCode.INPUT_TOO_LARGE)

    def _take_buffered_lines(self) -> list[bytes]:
        if self.stdout_buffer:
            raise FixtureStagingError(FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY)
        lines = list(self.stdout_lines)
        lines.extend(self.stdout_frames)
        self.stdout_frames.clear()
        return lines

    def _remaining(self) -> None:
        if self.deadline_ns - time.monotonic_ns() <= 0:
            raise subprocess.TimeoutExpired(self.process.args, 0)

    def _timeout(self) -> float:
        self._remaining()
        return max(0.0, (self.deadline_ns - time.monotonic_ns()) / 1_000_000_000)



class InstalledBrokerXPCSessionTransport:
    """Use the sealed broker to attach descriptors and perform authenticated XPC."""

    def __init__(
        self,
        installation: VerifiedNativeInstallation,
        *,
        authorization_path: Path,
        receipt_directory: Path,
    ) -> None:
        if (
            not isinstance(installation, VerifiedNativeInstallation)
            or installation._seal is not _INSTALLATION_SEAL
            or not installation.operation_enabled
        ):
            raise FixtureStagingError(
                FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY
            )
        self.installation = installation
        self.authorization_path = Path(authorization_path).absolute()
        self.receipt_directory = Path(receipt_directory).absolute()
        _require_root_executable(BROKER_PATH)

    def dispatch_export(
        self,
        attempt: Mapping[str, object],
        signed_request: Mapping[str, object],
        source_fds: Mapping[str, int],
        workflow: tuple[Mapping[str, object], ...],
        documents: Mapping[str, object] | None,
        delivery_fd: int | None = None,
    ):
        from ._fixture_staging_session import (
            AuthenticatedXPCReply,
            _AUTHENTICATED_XPC_SEAL,
            _receipt_matches_attempt,
        )

        if len(workflow) != 4:
            raise FixtureStagingError(FixtureStagingErrorCode.INVALID_AUTHORITY)
        stage_request = workflow[2]
        source_paths = stage_request.get("source_paths")
        if (
            not isinstance(source_paths, list)
            or len(source_paths) != len(source_fds)
            or set(source_paths) != set(source_fds)
        ):
            raise FixtureStagingError(FixtureStagingErrorCode.INPUT_UNAVAILABLE)
        descriptors = tuple(source_fds[path] for path in source_paths)
        if len(set(descriptors)) != len(descriptors):
            raise FixtureStagingError(FixtureStagingErrorCode.INPUT_UNAVAILABLE)
        source_file_ids: set[tuple[int, int]] = set()
        for descriptor in descriptors:
            try:
                metadata = os.fstat(descriptor)
            except (OSError, TypeError, ValueError) as error:
                raise FixtureStagingError(
                    FixtureStagingErrorCode.INPUT_UNAVAILABLE
                ) from error
            if (
                isinstance(descriptor, bool)
                or not isinstance(descriptor, int)
                or descriptor < 0
                or not stat.S_ISREG(metadata.st_mode)
            ):
                raise FixtureStagingError(FixtureStagingErrorCode.INPUT_UNAVAILABLE)
            file_id = (metadata.st_dev, metadata.st_ino)
            if file_id in source_file_ids:
                raise FixtureStagingError(FixtureStagingErrorCode.INPUT_UNAVAILABLE)
            source_file_ids.add(file_id)

        if delivery_fd is None:
            raise FixtureStagingError(FixtureStagingErrorCode.INPUT_UNAVAILABLE)
        try:
            delivery_info = os.fstat(delivery_fd)
            delivery_offset = os.lseek(delivery_fd, 0, os.SEEK_CUR)
        except OSError as error:
            raise FixtureStagingError(FixtureStagingErrorCode.INPUT_UNAVAILABLE) from error
        if (
            isinstance(delivery_fd, bool)
            or not isinstance(delivery_fd, int)
            or not stat.S_ISREG(delivery_info.st_mode)
            or delivery_info.st_uid != os.getuid()
            or delivery_info.st_nlink != 1
            or stat.S_IMODE(delivery_info.st_mode) != 0o600
            or delivery_info.st_size != 0
            or delivery_offset != 0
            or (delivery_info.st_dev, delivery_info.st_ino) in source_file_ids
        ):
            raise FixtureStagingError(FixtureStagingErrorCode.INPUT_UNAVAILABLE)

        deadline_ns = attempt.get("deadline_ns")
        if isinstance(deadline_ns, bool) or not isinstance(deadline_ns, int):
            raise FixtureStagingError(FixtureStagingErrorCode.OPERATION_TIMEOUT)
        arguments = (
            "session",
            f"--authorization-file={self.authorization_path}",
            f"--receiver-receipt-dir={self.receipt_directory}",
            f"--delivery-fd={delivery_fd}",
            *(f"--source-fd={descriptor}" for descriptor in descriptors),
        )
        wire_requests = [dict(request) for request in workflow]
        if documents is not None:
            wire_requests[1]["documents_b64"] = self._encode_documents(documents)
        wire_input = b"\n".join(
            fixture_oracle.canonical_json(
                request, maximum_bytes=fixture_oracle.MAX_BROKER_SESSION_DOCUMENT_BYTES
            ) for request in wire_requests
        ) + b"\n"
        stdout, stderr = self._run_session(
            arguments,
            wire_input,
            (*descriptors, delivery_fd),
            deadline_ns,
        )
        decoded = [
            fixture_oracle.decode_document(
                line, maximum_bytes=fixture_oracle.MAX_RECEIPT_DOCUMENT_BYTES
            )
            for line in stderr.splitlines()
            if line.strip()
        ]
        session_responses = [
            fixture_oracle.decode_document(line)
            for line in stdout.splitlines()
            if line.strip()
        ]
        if not _ordered_session_responses_match(session_responses, workflow[:3]):
            raise FixtureStagingError(
                FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY
            )
        completion = next(
            (item for item in reversed(decoded)
             if isinstance(item, dict) and item.get("durable") is True),
            None,
        )
        service_responses = [
            item
            for item in decoded
            if isinstance(item, dict)
            and item.get("status") == "OK"
            and item.get("request_id") == attempt.get("request_id")
        ]
        service_response = service_responses[0] if len(service_responses) == 1 else None
        if (
            completion is None
            or not _receipt_matches_attempt(attempt, completion)
            or service_response is None
        ):
            raise FixtureStagingError(
                FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY
            )
        expected_size = sum(int(member["size"]) for member in attempt["members"])
        if os.fstat(delivery_fd).st_size != expected_size:
            raise FixtureStagingError(FixtureStagingErrorCode.INPUT_UNAVAILABLE)
        return AuthenticatedXPCReply(
            self.installation.installation_id,
            self.installation.broker_revision,
            completion,
            _AUTHENTICATED_XPC_SEAL,
        )

    @classmethod
    def _encode_documents(cls, value):
        import base64

        total_bytes = 0

        def encode(item):
            nonlocal total_bytes
            if isinstance(item, bytes):
                if (len(item) > fixture_oracle.MAX_DOCUMENT_BYTES
                        or total_bytes > fixture_oracle.MAX_BROKER_DOCUMENTS_BYTES - len(item)):
                    raise FixtureStagingError(FixtureStagingErrorCode.INPUT_TOO_LARGE)
                total_bytes += len(item)
                return base64.b64encode(item).decode("ascii")
            if isinstance(item, (list, tuple)):
                return [encode(child) for child in item]
            if isinstance(item, Mapping):
                return {key: encode(child) for key, child in item.items()}
            raise FixtureStagingError(FixtureStagingErrorCode.INPUT_UNAVAILABLE)

        return encode(value)

    def query_export_receipt(self, attempt: Mapping[str, object]):
        from ._fixture_staging_session import (
            AuthenticatedXPCReply,
            _AUTHENTICATED_XPC_SEAL,
        )

        binding = {
            key: attempt[key]
            for key in (
                "request_id", "session_id", "service_boot_id", "sequence",
                "deadline_ns", "manifest_sha256", "generation", "members",
            )
        }
        query_deadline_ns = time.monotonic_ns() + RECEIPT_QUERY_TIMEOUT_NS
        request = {
            "operation": "receipt_query",
            "request_id": attempt["request_id"],
            "binding": binding,
            "query_deadline_ns": query_deadline_ns,
        }
        request_line = fixture_oracle.canonical_json(
            request, maximum_bytes=fixture_oracle.MAX_RECEIPT_DOCUMENT_BYTES - 1
        ) + b"\n"
        response, _stderr = self._run_session(
            ("session",),
            request_line,
            (),
            query_deadline_ns,
            maximum_stream_bytes=fixture_oracle.MAX_RECEIPT_DOCUMENT_BYTES,
        )
        if (len(response) > fixture_oracle.MAX_RECEIPT_DOCUMENT_BYTES
                or not response.endswith(b"\n") or response.count(b"\n") != 1):
            raise FixtureStagingError(FixtureStagingErrorCode.INPUT_TOO_LARGE)
        response_line = response[:-1]
        decoded = fixture_oracle.decode_document(
            response_line, maximum_bytes=fixture_oracle.MAX_RECEIPT_DOCUMENT_BYTES - 1
        )
        completion = decoded.get("completion") if isinstance(decoded, dict) else None
        if not isinstance(completion, dict):
            return None
        return AuthenticatedXPCReply(
            self.installation.installation_id,
            self.installation.broker_revision,
            completion,
            _AUTHENTICATED_XPC_SEAL,
        )

    def prepare_export(
        self,
        intent: Mapping[str, object],
        source_fds: Mapping[str, int],
        documents: Mapping[str, object],
        delivery_fd: int,
    ):
        """Send hello first and retain the broker after its native prepare reply."""

        from ._fixture_staging_session import (
            PreparedOwnerExport,
            _PREPARED_XPC_SEAL,
        )

        if not isinstance(intent, Mapping) or not isinstance(documents, Mapping):
            raise FixtureStagingError(FixtureStagingErrorCode.INVALID_AUTHORITY)
        hello_template = intent.get("hello")
        templates = intent.get("workflow_templates")
        consent_envelope = intent.get("consent_envelope")
        if (
            not isinstance(hello_template, Mapping)
            or hello_template.get("operation") != "hello"
            or not isinstance(templates, (tuple, list))
            or len(templates) != 3
            or tuple(item.get("operation") for item in templates if isinstance(item, Mapping))
            != ("admit", "stage", "export")
            or not isinstance(consent_envelope, Mapping)
        ):
            raise FixtureStagingError(FixtureStagingErrorCode.INVALID_AUTHORITY)
        if len(templates) != sum(isinstance(item, Mapping) for item in templates):
            raise FixtureStagingError(FixtureStagingErrorCode.INVALID_AUTHORITY)
        for template in templates:
            if any(
                key in template
                for key in (
                    "freshness_envelope",
                    "freshness_signature",
                    "consent_signature",
                    "connection_id",
                    "session_id",
                    "installation_id",
                    "service_boot_id",
                    "broker_revision",
                    "owner_key_id",
                )
            ):
                raise FixtureStagingError(FixtureStagingErrorCode.INVALID_AUTHORITY)

        stage_template = templates[1]
        source_paths = stage_template.get("source_paths")
        if (
            not isinstance(source_paths, list)
            or len(source_paths) != len(source_fds)
            or set(source_paths) != set(source_fds)
        ):
            raise FixtureStagingError(FixtureStagingErrorCode.INPUT_UNAVAILABLE)
        descriptors = tuple(source_fds[path] for path in source_paths)
        if len(set(descriptors)) != len(descriptors):
            raise FixtureStagingError(FixtureStagingErrorCode.INPUT_UNAVAILABLE)
        source_file_ids: set[tuple[int, int]] = set()
        for descriptor in descriptors:
            try:
                metadata = os.fstat(descriptor)
            except (OSError, TypeError, ValueError) as error:
                raise FixtureStagingError(
                    FixtureStagingErrorCode.INPUT_UNAVAILABLE
                ) from error
            if (
                isinstance(descriptor, bool)
                or not isinstance(descriptor, int)
                or descriptor < 0
                or not stat.S_ISREG(metadata.st_mode)
            ):
                raise FixtureStagingError(FixtureStagingErrorCode.INPUT_UNAVAILABLE)
            file_id = (metadata.st_dev, metadata.st_ino)
            if file_id in source_file_ids:
                raise FixtureStagingError(FixtureStagingErrorCode.INPUT_UNAVAILABLE)
            source_file_ids.add(file_id)

        try:
            delivery_info = os.fstat(delivery_fd)
            delivery_offset = os.lseek(delivery_fd, 0, os.SEEK_CUR)
        except (OSError, TypeError, ValueError) as error:
            raise FixtureStagingError(FixtureStagingErrorCode.INPUT_UNAVAILABLE) from error
        if (
            isinstance(delivery_fd, bool)
            or not isinstance(delivery_fd, int)
            or not stat.S_ISREG(delivery_info.st_mode)
            or delivery_info.st_uid != os.getuid()
            or delivery_info.st_nlink != 1
            or stat.S_IMODE(delivery_info.st_mode) != 0o600
            or delivery_info.st_size != 0
            or delivery_offset != 0
            or (delivery_info.st_dev, delivery_info.st_ino) in source_file_ids
        ):
            raise FixtureStagingError(FixtureStagingErrorCode.INPUT_UNAVAILABLE)

        deadline_ns = templates[2].get("deadline_ns")
        if (
            isinstance(deadline_ns, bool)
            or not isinstance(deadline_ns, int)
            or deadline_ns <= time.monotonic_ns()
        ):
            raise FixtureStagingError(FixtureStagingErrorCode.OPERATION_TIMEOUT)
        arguments = (
            "session",
            f"--authorization-file={self.authorization_path}",
            f"--receiver-receipt-dir={self.receipt_directory}",
            f"--delivery-fd={delivery_fd}",
            *(f"--source-fd={descriptor}" for descriptor in descriptors),
        )
        broker_session = _BrokerLineSession(
            arguments, (*descriptors, delivery_fd), deadline_ns
        )
        broker_session.source_descriptors = descriptors
        broker_session.delivery_fd = delivery_fd
        try:
            hello = dict(hello_template)
            hello.update(
                {
                    "installation_id": self.installation.installation_id,
                    "service_boot_id": self.installation.service_boot_id,
                    "broker_revision": self.installation.broker_revision,
                    "owner_key_id": self.installation.owner_key_id,
                }
            )
            hello_response = broker_session.exchange(hello)
            if (
                hello_response.get("status") != "OK"
                or hello_response.get("request_id") != hello.get("request_id")
            ):
                raise FixtureStagingError(FixtureStagingErrorCode.INVALID_AUTHORITY)

            wire_templates = [dict(template) for template in templates]
            wire_templates[0]["documents_b64"] = self._encode_documents(documents)
            prepared_response = broker_session.exchange(
                {
                    "schema_version": 1,
                    "broker_operation": "prepare_export",
                    "consent_envelope": dict(consent_envelope),
                    "workflow_templates": wire_templates,
                }
            )
            attempt = prepared_response.get("attempt")
            signed_request = prepared_response.get("signed_request")
            workflow = prepared_response.get("workflow")
            if (
                prepared_response.get("status") != "PREPARED"
                or not isinstance(attempt, Mapping)
                or not isinstance(signed_request, Mapping)
                or not isinstance(workflow, list)
                or len(workflow) != 4
                or time.monotonic_ns() >= deadline_ns
            ):
                raise FixtureStagingError(FixtureStagingErrorCode.INVALID_AUTHORITY)
            prepared = PreparedOwnerExport(
                attempt=attempt,
                signed_request=signed_request,
                workflow=tuple(workflow),
                continuation=broker_session,
                _authenticated_xpc=_PREPARED_XPC_SEAL,
            )
            return prepared
        except Exception:
            broker_session.abort()
            raise

    def dispatch_prepared_export(
        self,
        prepared,
        source_fds: Mapping[str, int],
        documents: Mapping[str, object],
        delivery_fd: int,
    ):
        """Acknowledge durable journaling, then continue the held native session."""

        from ._fixture_staging_session import (
            AuthenticatedXPCReply,
            PreparedOwnerExport,
            _AUTHENTICATED_XPC_SEAL,
            _PREPARED_XPC_SEAL,
            _receipt_matches_attempt,
        )

        if (
            not isinstance(prepared, PreparedOwnerExport)
            or prepared._authenticated_xpc is not _PREPARED_XPC_SEAL
            or not isinstance(prepared.continuation, _BrokerLineSession)
            or prepared.continuation.delivery_fd != delivery_fd
            or tuple(sorted(prepared.continuation.source_descriptors))
            != tuple(sorted(source_fds.values()))
        ):
            raise FixtureStagingError(FixtureStagingErrorCode.INVALID_AUTHORITY)
        broker_session = prepared.continuation
        try:
            ack = broker_session.exchange(
                {
                    "schema_version": 1,
                    "broker_operation": "journal_ack",
                    "attempt_sha256": hashlib.sha256(
                        fixture_oracle.canonical_json(dict(prepared.attempt))
                    ).hexdigest(),
                }
            )
            if (
                ack.get("status") != "JOURNAL_ACKNOWLEDGED"
                or ack.get("attempt_sha256")
                != hashlib.sha256(
                    fixture_oracle.canonical_json(dict(prepared.attempt))
                ).hexdigest()
            ):
                raise FixtureStagingError(FixtureStagingErrorCode.INVALID_AUTHORITY)
            operation_response_start = len(broker_session.stdout_lines)
            broker_session.send(
                {"schema_version": 1, "broker_operation": "dispatch_prepared"}
            )
            responses, stderr = broker_session.finish(
                after_response_count=operation_response_start
            )
        except Exception:
            broker_session.abort()
            raise

        operation_requests = prepared.workflow[1:]
        if not _ordered_session_responses_match(responses, operation_requests):
            raise FixtureStagingError(FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY)
        stderr_items = [
            fixture_oracle.decode_document(line)
            for line in stderr.splitlines()
            if line.strip()
        ]
        completion = next(
            (
                item
                for item in reversed(stderr_items)
                if isinstance(item, dict) and item.get("durable") is True
            ),
            None,
        )
        if completion is None or not _receipt_matches_attempt(
            prepared.attempt, completion
        ):
            raise FixtureStagingError(FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY)
        expected_size = sum(int(member["size"]) for member in prepared.attempt["members"])
        if os.fstat(delivery_fd).st_size != expected_size:
            raise FixtureStagingError(FixtureStagingErrorCode.INPUT_UNAVAILABLE)
        return AuthenticatedXPCReply(
            self.installation.installation_id,
            self.installation.broker_revision,
            completion,
            _AUTHENTICATED_XPC_SEAL,
        )

    @staticmethod
    def _run_session(
        arguments: tuple[str, ...],
        input_bytes: bytes,
        pass_fds: tuple[int, ...],
        deadline_ns: int,
        *,
        maximum_stream_bytes: int = fixture_oracle.MAX_BROKER_SESSION_LINE_BYTES,
    ) -> tuple[bytes, bytes]:
        _require_root_executable(BROKER_PATH)
        process = subprocess.Popen(
            (str(BROKER_PATH), *arguments),
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd="/",
            env={"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C"},
            close_fds=True,
            pass_fds=pass_fds,
        )
        outputs = {process.stdout: bytearray(), process.stderr: bytearray()}
        try:
            assert process.stdin is not None
            input_fd = process.stdin.fileno()
            os.set_blocking(input_fd, False)
            for stream in outputs:
                os.set_blocking(stream.fileno(), False)
            input_offset = 0
            input_open = True
            if not input_bytes:
                process.stdin.close()
                input_open = False
            open_streams = set(outputs)
            if isinstance(deadline_ns, bool) or not isinstance(deadline_ns, int):
                raise FixtureStagingError(
                    FixtureStagingErrorCode.OPERATION_TIMEOUT
                )
            while open_streams or input_open:
                remaining_ns = deadline_ns - time.monotonic_ns()
                if remaining_ns <= 0:
                    raise subprocess.TimeoutExpired(process.args, 0)
                remaining = remaining_ns / 1_000_000_000
                writable_fds = (input_fd,) if input_open else ()
                readable, writable, _ = select.select(
                    tuple(stream.fileno() for stream in open_streams),
                    writable_fds,
                    (),
                    remaining,
                )
                if not readable and not writable:
                    raise subprocess.TimeoutExpired(process.args, 0)
                if input_open and input_fd in writable:
                    try:
                        written = os.write(input_fd, input_bytes[input_offset:])
                    except BlockingIOError:
                        written = 0
                    input_offset += written
                    if input_offset == len(input_bytes):
                        process.stdin.close()
                        input_open = False
                for stream_fd in readable:
                    stream = next(
                        candidate for candidate in open_streams
                        if candidate.fileno() == stream_fd
                    )
                    chunk = os.read(stream_fd, 8192)
                    if not chunk:
                        open_streams.remove(stream)
                        continue
                    outputs[stream].extend(chunk)
                    if len(outputs[stream]) > maximum_stream_bytes:
                        raise FixtureStagingError(FixtureStagingErrorCode.INPUT_TOO_LARGE)
            remaining_ns = deadline_ns - time.monotonic_ns()
            if remaining_ns <= 0 or process.wait(
                timeout=remaining_ns / 1_000_000_000
            ) != 0:
                raise FixtureStagingError(
                    FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY
                )
            return bytes(outputs[process.stdout]), bytes(outputs[process.stderr])
        except Exception:
            process.kill()
            process.wait()
            raise
        finally:
            for stream in (process.stdin, process.stdout, process.stderr):
                if stream is not None and not stream.closed:
                    stream.close()


def create_owner_session_export_client(
    journal,
    installation: VerifiedNativeInstallation,
    *,
    authorization_path: Path,
    receipt_directory: Path,
):
    """Create a journaled client bound to a probed native installation."""

    from ._fixture_staging_session import OwnerSessionExportClient

    transport = InstalledBrokerXPCSessionTransport(
        installation,
        authorization_path=authorization_path,
        receipt_directory=receipt_directory,
    )
    return OwnerSessionExportClient.from_verified_installation(
        journal, transport, installation
    )


def create_production_owner_export_preparation(
    grant: FixtureStagingGrant,
    journal,
    *,
    attempt_manifest_sha256: str,
    attempt_authorization_sha256: str,
    authorization_path: Path,
    receipt_directory: Path,
    export_intent: Mapping[str, object],
    source_fds: Mapping[str, int],
    documents: Mapping[str, object],
    delivery_fd: int,
) -> ProductionOwnerExportPreparation:
    """Create a grant-bound export preparation without starting native work.

    The preparation snapshots caller inputs but performs no grant, filesystem,
    installation, or native-session checks. Staging validates the expected
    digests and the reviewed input bytes after namespace admission and before
    invoking native preparation.
    """

    if (
        not isinstance(export_intent, Mapping)
        or not isinstance(source_fds, Mapping)
        or not source_fds
        or not isinstance(documents, Mapping)
        or isinstance(delivery_fd, bool)
        or not isinstance(delivery_fd, int)
        or delivery_fd < 0
    ):
        raise FixtureStagingError(
            FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY
        )
    try:
        frozen_export_intent = _freeze_export_input(export_intent)
        frozen_source_fds = MappingProxyType(dict(source_fds))
        frozen_documents = _freeze_export_input(documents)
        authorization_path = Path(authorization_path)
        receipt_directory = Path(receipt_directory)
    except (TypeError, ValueError) as error:
        raise FixtureStagingError(
            FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY
        ) from error

    def prepare(installation: VerifiedNativeInstallation):
        from ._fixture_staging_session import OwnerExportDispatch, OwnerSessionExportClient

        validated_grant = _validate_grant_for_use(grant, _authority._utc_now())
        if validated_grant is not grant:
            raise FixtureStagingError(FixtureStagingErrorCode.INVALID_AUTHORITY)
        _validate_production_owner_export_preparation_inputs(
            validated_grant, preparation
        )
        if (
            not isinstance(installation, VerifiedNativeInstallation)
            or installation._seal is not _INSTALLATION_SEAL
            or not installation.operation_enabled
        ):
            raise FixtureStagingError(
                FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY
            )
        client = create_owner_session_export_client(
            journal,
            installation,
            authorization_path=authorization_path,
            receipt_directory=receipt_directory,
        )
        prepared = None
        try:
            prepared = client.prepare_export(
                frozen_export_intent,
                frozen_source_fds,
                frozen_documents,
                delivery_fd,
            )
            attempt = OwnerSessionExportClient._prepared_value(prepared, "attempt")
            signed_request = OwnerSessionExportClient._prepared_value(
                prepared, "signed_request"
            )
            workflow = OwnerSessionExportClient._prepared_value(prepared, "workflow")
            if (
                not isinstance(attempt, Mapping)
                or not isinstance(signed_request, Mapping)
                or not isinstance(workflow, tuple)
            ):
                raise ValueError("native broker returned an incomplete preparation")
            if (
                attempt.get("manifest_sha256")
                != validated_grant.fixture_manifest_sha256
                or attempt.get("authorization_sha256")
                != validated_grant.authorization_sha256
            ):
                raise FixtureStagingError(FixtureStagingErrorCode.INVALID_AUTHORITY)
        except Exception as error:
            continuation = OwnerSessionExportClient._prepared_value(
                prepared, "continuation"
            )
            abort = getattr(continuation, "abort", None)
            if callable(abort):
                try:
                    abort()
                except Exception:
                    pass
            if isinstance(error, FixtureStagingError):
                raise
            raise FixtureStagingError(
                FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY
            ) from error
        return OwnerExportDispatch(
            client=client,
            attempt=attempt,
            signed_request=signed_request,
            source_fds=frozen_source_fds,
            delivery_fd=delivery_fd,
            workflow=workflow,
            documents=frozen_documents,
        )

    preparation = ProductionOwnerExportPreparation(
        grant,
        attempt_manifest_sha256,
        attempt_authorization_sha256,
        authorization_path,
        frozen_documents,
        prepare,
        _OWNER_EXPORT_PREPARATION_SEAL,
    )
    return preparation


def _self_check(path: Path) -> Mapping[str, object]:
    _require_root_executable(path)
    try:
        returncode, stdout = _run_bounded(path, ("--self-check",))
        result = fixture_oracle.decode_document(stdout)
    except (OSError, subprocess.SubprocessError, ValueError) as error:
        raise FixtureStagingError(
            FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY
        ) from error
    if returncode != 0:
        raise FixtureStagingError(FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY)
    return result


def _service_readiness_via_broker(path: Path) -> Mapping[str, object]:
    """Ask the installed broker to query service readiness over authenticated XPC.

    The broker validates the service code requirement before resuming the
    connection, and the service authenticates the broker peer before handling
    the request. This host test exercises response validation only; it is not
    evidence that a signed installation was exercised.
    """

    _require_root_executable(path)
    request = fixture_oracle.canonical_json(
        {
            "schema_version": 1,
            "operation": "readiness",
            "request_id": _READINESS_REQUEST_ID,
        }
    )
    try:
        returncode, stdout = _run_bounded(path, ("relay",), input_bytes=request)
        envelope = fixture_oracle.decode_document(stdout)
        if (
            returncode != 0
            or not isinstance(envelope, dict)
            or set(envelope) != {"status", "request_id", "result"}
            or envelope["status"] != "OK"
            or envelope["request_id"] != _READINESS_REQUEST_ID
            or not isinstance(envelope["result"], dict)
        ):
            raise ValueError("readiness response")
        return envelope["result"]
    except (OSError, subprocess.SubprocessError, ValueError, fixture_oracle.OracleError) as error:
        raise FixtureStagingError(
            FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY
        ) from error


def select_verified_native_installation() -> VerifiedNativeInstallation | None:
    """Probe only the installed, root-owned native implementation.

    A missing policy, executable, owner enrollment, signature check, or proof
    prerequisite is represented by ``None``. No development or synthetic
    destination is considered.
    """

    try:
        policy_bytes = _fixed_file(POLICY_PATH, maximum=MAX_POLICY_BYTES)
        policy = fixture_oracle.decode_document(policy_bytes)
        if set(policy) != {
            "schema",
            "team_id",
            "broker_cdhash",
            "service_cdhash",
            "owner_uid",
            "service_uid",
            "key_access_group",
            "key_tag",
            "owner_public_key",
        }:
            return None
        if policy["schema"] != 1 or policy["owner_uid"] == policy["service_uid"]:
            return None
        _require_root_executable(SERVICE_PATH)
        broker = _self_check(BROKER_PATH)
        service = _service_readiness_via_broker(BROKER_PATH)
        if set(broker) != {"status", "code"} or broker != {
            "status": "NOT_READY",
            "code": "AWAITING_XPC_DEPENDENCY_PROOF",
        }:
            return None
        if set(service) != {
            "ready",
            "protocol_version",
            "installation_id",
            "service_boot_id",
            "broker_revision",
            "owner_key_id",
            "staging_root",
            "namespace_authority",
            "python_destination",
            "exclusive_cleanup_authority",
        }:
            return None
        if (
            service["ready"] is not True
            or service["protocol_version"] != 1
            or service["staging_root"] != PRODUCTION_STAGING_ROOT
            or service["namespace_authority"] != "protected_service_identity"
            or service["broker_revision"] != policy["broker_cdhash"]
            or service["owner_key_id"] != policy["key_tag"]
        ):
            return None
        return VerifiedNativeInstallation(
            installation_id=_text(service["installation_id"]),
            service_boot_id=_text(service["service_boot_id"]),
            broker_revision=_text(service["broker_revision"]),
            owner_key_id=_text(service["owner_key_id"]),
            policy_sha256=fixture_oracle.manifest_sha256(policy),
            service_ready=True,
            # The diagnostic self-check deliberately remains NOT_READY until
            # live broker identity and IPC proof are available.
            broker_ready=False,
            operation_enabled=False,
            _seal=_INSTALLATION_SEAL,
        )
    except (FixtureStagingError, KeyError, TypeError, ValueError, OSError):
        return None


def _text(value: object) -> str:
    if not isinstance(value, str) or not value or len(value) > 4096:
        raise ValueError("invalid native text")
    return value


def _translate_oracle_error(error: fixture_oracle.OracleError) -> FixtureStagingError:
    code = {
        "PIN_MISMATCH": FixtureStagingErrorCode.DIGEST_MISMATCH,
        "REFERENCE_UNVERIFIED": FixtureStagingErrorCode.EXPECTATION_UNVERIFIED,
        "EVIDENCE_CONFLICT": FixtureStagingErrorCode.EXPECTATION_UNVERIFIED,
        "LIMIT_EXCEEDED": FixtureStagingErrorCode.INPUT_TOO_LARGE,
        "MISSING_REFERENCE": FixtureStagingErrorCode.EXPECTATION_UNVERIFIED,
        "REFERENCE_CYCLE": FixtureStagingErrorCode.MANIFEST_INVALID,
        "UNUSED_RECORD": FixtureStagingErrorCode.MANIFEST_INVALID,
    }.get(error.code, FixtureStagingErrorCode.MANIFEST_INVALID)
    return FixtureStagingError(code)


def classify_snapshot_contract(
    contract: fixture_oracle.SnapshotContract,
) -> SnapshotSupport:
    """Aggregate validated support without promoting unsealed declarations.

    A :class:`fixture_oracle.SnapshotContract` records declaration-validation
    results and does not carry an authenticated native verifier result. Until
    one exists, even a caller-built contract containing
    ``verified_independent_reference`` remains pinned and unverified.
    """

    values = {item.independent_support for item in contract.fixtures}
    if values == {SnapshotSupport.SYNTHETIC_ONLY.value}:
        return SnapshotSupport.SYNTHETIC_ONLY
    recognized = {
        SnapshotSupport.SYNTHETIC_ONLY.value,
        SnapshotSupport.PINNED_UNVERIFIED.value,
        SnapshotSupport.VERIFIED_INDEPENDENT_REFERENCE.value,
    }
    if values and values <= recognized:
        return SnapshotSupport.PINNED_UNVERIFIED
    raise FixtureStagingError(FixtureStagingErrorCode.EXPECTATION_UNVERIFIED)


def validate_snapshot_contract_for_grant(
    grant: FixtureStagingGrant,
    manifest: bytes,
    oracles: tuple[bytes, ...] | list[bytes],
    evidence: tuple[bytes, ...] | list[bytes],
) -> ValidatedSnapshotContract:
    """Validate oracle documents against an issued grant's exact pins."""

    try:
        grant = _validate_grant_for_use(grant, _authority._utc_now())
        contract = fixture_oracle.validate_snapshot_contract(
            manifest,
            oracles,
            evidence,
            authorized_manifest_sha256=grant.fixture_manifest_sha256,
            authorized_plan_sha256=grant.plan_sha256,
            authorized_rules_sha256=grant.rules_sha256,
        )
    except fixture_oracle.OracleError as error:
        raise _translate_oracle_error(error) from error
    if tuple(item.fixture_id for item in contract.fixtures) != grant.fixture_ids:
        raise FixtureStagingError(FixtureStagingErrorCode.EXPECTATION_UNVERIFIED)
    if any(
        item.owner_approval != "not_checked" or item.byte_integrity != "not_checked"
        for item in contract.fixtures
    ):
        raise FixtureStagingError(FixtureStagingErrorCode.EXPECTATION_UNVERIFIED)
    return ValidatedSnapshotContract(contract, classify_snapshot_contract(contract))


def validate_native_contract_result(
    grant: FixtureStagingGrant,
    response: bytes,
    manifest: bytes,
    oracles: tuple[bytes, ...] | list[bytes],
    evidence: tuple[bytes, ...] | list[bytes],
) -> ValidatedNativeContractResult:
    """Cross-check canonical broker output with Python oracle validation.

    ``response`` is caller-supplied bytes at this boundary. The Python process
    therefore cannot authenticate a native field that claims an installed-key
    signature, even when the field is syntactically present. The returned
    consent remains unverified until a separately sealed transport result is
    available and validated here.
    """

    validated = validate_snapshot_contract_for_grant(
        grant,
        manifest,
        oracles,
        evidence,
    )
    try:
        envelope = fixture_oracle.decode_document(response)
        if fixture_oracle.canonical_json(envelope) != response:
            raise ValueError("canonical native result")
        if set(envelope) != {"status", "request_id", "result"}:
            raise ValueError("envelope fields")
        result = envelope["result"]
        if not isinstance(result, dict) or set(result) != {
            "store",
            "manifest_sha256",
            "source_authority",
            "selected_fixture_ids",
            "oracle_support",
            "coverage",
            "owner_consent",
            "owner_approval",
            "byte_integrity",
        }:
            raise ValueError("result fields")
        if envelope["status"] != "OK":
            raise ValueError("status")
        _text(envelope["request_id"])
        store_result = result["store"]
        if not isinstance(store_result, dict):
            raise ValueError("store")
        selected = result["selected_fixture_ids"]
        support = result["oracle_support"]
        coverage = result["coverage"]
        if (
            not isinstance(selected, list)
            or any(not isinstance(item, str) for item in selected)
            or tuple(selected) != grant.fixture_ids
            or not isinstance(support, list)
            or tuple(support) != tuple(item.independent_support for item in validated.contract.fixtures)
            or result["manifest_sha256"] != validated.contract.manifest_sha256
            or result["source_authority"] != validated.contract.source_authority
            or result["owner_consent"] != "verified_by_installed_owner_key"
            or result["owner_approval"] != "not_checked"
            or result["byte_integrity"] != "not_checked"
        ):
            raise ValueError("binding")
        if (
            not isinstance(coverage, dict)
            or set(coverage)
            != {
                "mode",
                "required_fixture_ids",
                "selected_fixture_ids",
                "mandatory_fixture_ids",
            }
            or coverage.get("mode") != grant.coverage_mode
            or coverage.get("selected_fixture_ids") != list(grant.fixture_ids)
            or coverage.get("required_fixture_ids") != list(grant.required_fixture_ids)
            or coverage.get("mandatory_fixture_ids")
            != list(grant.mandatory_fixture_ids)
        ):
            raise ValueError("coverage")
        tiers = tuple(SnapshotSupport(value) for value in support)
    except (fixture_oracle.OracleError, ValueError, TypeError) as error:
        raise FixtureStagingError(FixtureStagingErrorCode.EXPECTATION_UNVERIFIED) from error
    return ValidatedNativeContractResult(
        manifest_sha256=validated.contract.manifest_sha256,
        source_authority=validated.contract.source_authority,
        selected_fixture_ids=tuple(selected),
        oracle_support=tiers,
        owner_consent="unverified",
        owner_approval="not_checked",
        byte_integrity="not_checked",
        store_result=fixture_oracle.canonical_json(store_result),
    )
