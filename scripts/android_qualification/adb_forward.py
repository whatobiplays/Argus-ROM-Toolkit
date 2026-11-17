"""Bounded host ADB operations for an explicitly owned readiness forward.

Only the fixed ADB command forms in this module are accepted. The adapter binds
to one serial/build pair, records a forward as owned only after an exact
post-create readback, and connects only to that verified mapping on loopback.
It is an injected host adapter; importing this module never invokes ADB.
"""

from __future__ import annotations

import math
import os
import re
import selectors
import signal
import socket
import subprocess
import time
from dataclasses import dataclass
from enum import Enum
from typing import Optional

from .readiness_probe import ProbeError, REQUEST_CAP, RESPONSE_CAP, require
from .readiness_probe_session import ForwardSession, _TRANSPORT_POLICIES


_MAX_COMMAND_OUTPUT_BYTES = 64 * 1024
_MAX_COMMAND_READ_BYTES = 4096
_MAX_FORWARD_LINE_LENGTH = 1024
_PROCESS_POLL_INTERVAL_SECONDS = 0.05
_PROCESS_CLEANUP_TIMEOUT_SECONDS = 1.0
_PROCESS_GROUP_QUERY_TIMEOUT_SECONDS = 0.25
_MAX_PROCESS_GROUP_OUTPUT_BYTES = 64 * 1024
_TARGET_PATTERN = re.compile(r"[A-Za-z0-9._:-]{1,128}\Z")
_BUILD_PATTERN = re.compile(r"[A-Za-z0-9][A-Za-z0-9._:/+\-]{0,255}\Z")
_LOCAL_PATTERN = re.compile(r"tcp:([1-9][0-9]{0,4})\Z")
_REMOTE_PATTERN = re.compile(r"localabstract:[A-Za-z0-9_-]{1,100}\Z")
_FORWARD_SPEC_PATTERN = re.compile(r"[a-z][a-z0-9]*:[A-Za-z0-9._:/+\-]{1,256}\Z")


class _ForwardPhase(Enum):
    """States for one target/local forward owned by the host adapter."""

    OBSERVED = "observed"
    CREATE_PENDING = "create_pending"
    CREATE_SUCCEEDED = "create_succeeded"
    CREATE_READBACK_PENDING = "create_readback_pending"
    CREATE_UNCERTAIN = "create_uncertain"
    OWNED = "owned"
    OWNERSHIP_UNCERTAIN = "ownership_uncertain"
    REMOVE_PENDING = "remove_pending"
    REMOVE_SUCCEEDED = "remove_succeeded"
    REMOVE_READBACK_PENDING = "remove_readback_pending"
    REMOVE_UNCERTAIN = "remove_uncertain"
    REMOVED = "removed"


@dataclass
class _ForwardRecord:
    """Keep one forward's expected tuple, phase and latest readback together."""

    phase: _ForwardPhase
    expected_remote: Optional[str] = None
    observed_remote: Optional[str] = None
    observed_deadline: Optional[float] = None


def _deadline_remaining(clock, deadline):
    """Return positive time left on an absolute host-monotonic deadline."""
    try:
        valid_deadline = type(deadline) in (int, float) and math.isfinite(deadline)
    except (OverflowError, TypeError, ValueError):
        valid_deadline = False
    if not valid_deadline:
        raise ProbeError("MalformedRequest", "Transport")
    try:
        now = clock()
        if type(now) not in (int, float) or not math.isfinite(now):
            raise ValueError
        remaining = deadline - now
        if not math.isfinite(remaining):
            raise ValueError
    except (OverflowError, TypeError, ValueError):
        raise ProbeError("TimedOut", "Transport") from None
    if remaining <= 0:
        raise ProbeError("TimedOut", "Transport")
    return remaining


def _cleanup_wait_timeout(clock, deadline):
    """Return a child-reaping timeout that fits before the caller's deadline."""
    try:
        now = clock()
        if type(now) not in (int, float) or not math.isfinite(now):
            return 0.0
        remaining = deadline - now
        if not math.isfinite(remaining) or remaining <= 0:
            return 0.0
    except (OverflowError, TypeError, ValueError):
        return 0.0
    return min(_PROCESS_CLEANUP_TIMEOUT_SECONDS, remaining)


def _valid_target(target):
    return type(target) is str and _TARGET_PATTERN.fullmatch(target) is not None


def _valid_local(local):
    if type(local) is not str:
        return False
    match = _LOCAL_PATTERN.fullmatch(local)
    return match is not None and int(match.group(1)) <= 65535


def _valid_remote(remote):
    return type(remote) is str and _REMOTE_PATTERN.fullmatch(remote) is not None


def _process_group_listing_is_quiescent(output, process_group):
    """Accept only complete process listings with no live group member."""
    if type(output) is not bytes or len(output) > _MAX_PROCESS_GROUP_OUTPUT_BYTES:
        return False
    seen_pids = set()
    for line in output.splitlines():
        try:
            fields = line.decode("ascii").split()
        except UnicodeDecodeError:
            return False
        if len(fields) != 3 or not fields[0].isdigit() or not fields[1].isdigit():
            return False
        member_pid, member_group = int(fields[0]), int(fields[1])
        state = fields[2]
        if member_pid <= 0 or member_group <= 0 or not state:
            return False
        if member_pid in seen_pids:
            return False
        seen_pids.add(member_pid)
        if member_pid == process_group and member_group != process_group:
            return False
        if member_group == process_group and state[0] != "Z":
            return False
    return True


def _host_process_group_is_quiescent(
    process_group,
    *,
    timeout,
    popen=None,
    selector_factory=None,
    reader=None,
    clock=None,
):
    """Read a bounded process listing before accepting EPERM after client exit."""
    if type(process_group) is not int or process_group <= 0:
        return False
    try:
        valid_timeout = type(timeout) in (int, float) and math.isfinite(timeout)
    except (OverflowError, TypeError, ValueError):
        valid_timeout = False
    if not valid_timeout or timeout <= 0:
        return False
    popen = subprocess.Popen if popen is None else popen
    selector_factory = (
        selectors.DefaultSelector if selector_factory is None else selector_factory
    )
    reader = os.read if reader is None else reader
    clock = time.monotonic if clock is None else clock
    try:
        deadline = clock() + timeout
        if not math.isfinite(deadline):
            return False
    except (OverflowError, TypeError, ValueError):
        return False

    process = None
    selector = None
    reaped = False
    output = bytearray()
    try:
        process = popen(
            ("/bin/ps", "-o", "pid=,pgid=,stat=", "-g", str(process_group)),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            shell=False,
            close_fds=True,
        )
        selector = selector_factory()
        selector.register(process.stdout, selectors.EVENT_READ)
        while selector.get_map():
            remaining = deadline - clock()
            if not math.isfinite(remaining) or remaining <= 0:
                return False
            events = selector.select(remaining)
            if not events:
                return False
            for key, _mask in events:
                allowance = min(
                    _MAX_COMMAND_READ_BYTES,
                    _MAX_PROCESS_GROUP_OUTPUT_BYTES - len(output) + 1,
                )
                chunk = reader(key.fd, allowance)
                if type(chunk) is not bytes:
                    return False
                if not chunk:
                    selector.unregister(key.fileobj)
                    continue
                output.extend(chunk)
                if len(output) > _MAX_PROCESS_GROUP_OUTPUT_BYTES:
                    return False
        remaining = deadline - clock()
        if not math.isfinite(remaining) or remaining <= 0:
            return False
        return_code = process.wait(timeout=remaining)
        if type(return_code) is not int:
            return False
        reaped = True
        if return_code != 0:
            return False
        return _process_group_listing_is_quiescent(bytes(output), process_group)
    except Exception:
        return False
    finally:
        if process is not None and not reaped:
            try:
                process.kill()
            except Exception:
                pass
            try:
                process.wait(timeout=_cleanup_wait_timeout(clock, deadline))
            except Exception:
                pass
        if selector is not None:
            try:
                selector.close()
            except Exception:
                pass
        if process is not None and process.stdout is not None:
            try:
                process.stdout.close()
            except Exception:
                pass


class _AdbCommandRunner:
    """Run one allowlisted ADB command with bounded I/O and group cleanup."""

    def __init__(
        self,
        *,
        clock=time.monotonic,
        popen=subprocess.Popen,
        selector_factory=selectors.DefaultSelector,
        reader=os.read,
        kill_group=os.killpg,
        process_group_is_quiescent=None,
        waitid=None,
        sleep=time.sleep,
    ):
        self._clock = clock
        self._popen = popen
        self._selector_factory = selector_factory
        self._reader = reader
        self._kill_group = kill_group
        self._process_group_is_quiescent = (
            process_group_is_quiescent or _host_process_group_is_quiescent
        )
        self._waitid = waitid if waitid is not None else getattr(os, "waitid", None)
        self._sleep = sleep

    def _waitid_flags(self):
        """Return POSIX flags for observing exit without reaping the child."""
        waitid = self._waitid
        idtype = getattr(os, "P_PID", None)
        options = tuple(
            getattr(os, name, None) for name in ("WEXITED", "WNOHANG", "WNOWAIT")
        )
        if not callable(waitid) or idtype is None or any(value is None for value in options):
            raise ProbeError("IncompleteEvidence", "Transport")
        return idtype, options[0] | options[1] | options[2]

    def _process_exited(self, process):
        """Check leader exit while keeping its process-group ID reserved."""
        idtype, options = self._waitid_flags()
        try:
            result = self._waitid(idtype, process.pid, options)
        except Exception:
            raise ProbeError("IncompleteEvidence", "Transport") from None
        if result is None:
            return False
        result_pid = getattr(result, "si_pid", None)
        if result_pid == 0:
            return False
        if result_pid != process.pid:
            raise ProbeError("IncompleteEvidence", "Transport")
        return True

    def _wait_for_process_exit(self, process, deadline):
        """Wait for client exit within the host deadline without reaping it."""
        while not self._process_exited(process):
            remaining = _deadline_remaining(self._clock, deadline)
            self._sleep(min(remaining, _PROCESS_POLL_INTERVAL_SECONDS))

    def _signal_process_group(
        self, process, *, missing_is_success=False, deadline=None
    ):
        """Signal the isolated group, verifying quiescence if exit leaves EPERM."""
        try:
            self._kill_group(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            return missing_is_success
        except PermissionError:
            if not missing_is_success:
                return False
            timeout = _PROCESS_GROUP_QUERY_TIMEOUT_SECONDS
            if deadline is not None:
                try:
                    timeout = min(timeout, _deadline_remaining(self._clock, deadline))
                except ProbeError:
                    return False
            try:
                return self._process_group_is_quiescent(
                    process.pid, timeout=timeout
                ) is True
            except Exception:
                return False
        except Exception:
            return False
        return True

    @staticmethod
    def _kill_direct_child(process):
        """Kill the direct child, treating an already-gone PID as settled."""
        try:
            process.kill()
        except ProcessLookupError:
            return True
        except Exception:
            return False
        return True

    @staticmethod
    def _allowed_vector(argv):
        if type(argv) is not tuple or len(argv) < 4:
            return False
        if argv[0] != "adb" or argv[1] != "-s" or not _valid_target(argv[2]):
            return False
        command = argv[3:]
        if command in (("get-state",), ("shell", "getprop", "ro.build.fingerprint"),
                       ("forward", "--list")):
            return True
        if len(command) == 4 and command[:2] == ("forward", "--no-rebind"):
            return _valid_local(command[2]) and _valid_remote(command[3])
        if len(command) == 3 and command[:2] == ("forward", "--remove"):
            return _valid_local(command[2])
        return False

    def _stop(self, process, deadline):
        group_stopped = self._signal_process_group(process, deadline=deadline)
        if not group_stopped:
            self._kill_direct_child(process)
        try:
            return_code = process.wait(
                timeout=_cleanup_wait_timeout(self._clock, deadline)
            )
        except Exception:
            return_code = None
        if return_code is None and group_stopped:
            self._kill_direct_child(process)
            try:
                return_code = process.wait(
                    timeout=_cleanup_wait_timeout(self._clock, deadline)
                )
            except Exception:
                return_code = None
        return group_stopped and return_code is not None

    def run(self, argv, deadline):
        """Return stdout bytes only, or a closed error without process text."""
        if not self._allowed_vector(argv):
            raise ProbeError("MalformedRequest", "Transport")
        _deadline_remaining(self._clock, deadline)
        self._waitid_flags()
        try:
            process = self._popen(
                argv,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                shell=False,
                close_fds=True,
                start_new_session=True,
            )
        except Exception:
            raise ProbeError("Disconnected", "Transport") from None

        selector = None
        stdout = bytearray()
        total_bytes = 0
        completed = False
        process_reaped = False
        try:
            _deadline_remaining(self._clock, deadline)
            selector = self._selector_factory()
            selector.register(process.stdout, selectors.EVENT_READ)
            selector.register(process.stderr, selectors.EVENT_READ)
            while selector.get_map():
                timeout = min(
                    _deadline_remaining(self._clock, deadline),
                    _PROCESS_POLL_INTERVAL_SECONDS,
                )
                events = selector.select(timeout)
                if not events:
                    if self._process_exited(process):
                        raise ProbeError("IncompleteEvidence", "Transport")
                    _deadline_remaining(self._clock, deadline)
                    continue
                for key, _mask in events:
                    allowance = min(
                        _MAX_COMMAND_READ_BYTES,
                        _MAX_COMMAND_OUTPUT_BYTES - total_bytes + 1,
                    )
                    chunk = self._reader(key.fd, allowance)
                    if type(chunk) is not bytes:
                        raise ProbeError("IncompleteEvidence", "Transport")
                    if not chunk:
                        selector.unregister(key.fileobj)
                        continue
                    total_bytes += len(chunk)
                    if total_bytes > _MAX_COMMAND_OUTPUT_BYTES:
                        raise ProbeError("ResourceLimitExceeded", "Transport")
                    if key.fileobj is process.stdout:
                        stdout.extend(chunk)

            self._wait_for_process_exit(process, deadline)
            if not self._signal_process_group(
                process, missing_is_success=True, deadline=deadline
            ):
                raise ProbeError("IncompleteEvidence", "Transport")
            timeout = _deadline_remaining(self._clock, deadline)
            try:
                return_code = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                raise ProbeError("TimedOut", "Transport") from None
            if type(return_code) is not int:
                raise ProbeError("IncompleteEvidence", "Transport")
            process_reaped = True
            _deadline_remaining(self._clock, deadline)
            if return_code != 0:
                raise ProbeError("IncompleteEvidence", "Transport")
            completed = True
            return bytes(stdout)
        except ProbeError:
            raise
        except subprocess.TimeoutExpired:
            raise ProbeError("TimedOut", "Transport") from None
        except Exception:
            raise ProbeError("IncompleteEvidence", "Transport") from None
        finally:
            cleanup_complete = True
            if not process_reaped:
                cleanup_complete = self._stop(process, deadline)
            if selector is not None:
                try:
                    selector.close()
                except Exception:
                    pass
            for stream in (process.stdout, process.stderr):
                try:
                    stream.close()
                except Exception:
                    pass
            if not cleanup_complete:
                raise ProbeError("IncompleteEvidence", "Transport")


class AdbForwardAdapter:
    """Implement ForwardAdapter with one target/build and owned tuple at a time.

    Callers must use this adapter through ``ForwardSession``. Its most recent
    exact lookup under the current phase deadline authorizes removal; a failed
    or late operation leaves the corresponding local ownership state unresolved.
    The trusted-host policy assumes no concurrent external forward mutator.
    """

    def __init__(self, *, runner=None, clock=time.monotonic, socket_factory=None):
        self._clock = clock
        self._runner = runner if runner is not None else _AdbCommandRunner(clock=clock)
        self._socket_factory = socket_factory or socket.socket
        self._identity_binding = None
        self._forwards = {}

    def _run(self, target, command, deadline):
        if not _valid_target(target):
            raise ProbeError("MalformedRequest", "Transport")
        _deadline_remaining(self._clock, deadline)
        argv = ("adb", "-s", target, *command)
        try:
            result = self._runner.run(argv, deadline)
        except ProbeError:
            raise
        except TimeoutError:
            raise ProbeError("TimedOut", "Transport") from None
        except OSError:
            raise ProbeError("Disconnected", "Transport") from None
        except Exception:
            raise ProbeError("IncompleteEvidence", "Transport") from None
        _deadline_remaining(self._clock, deadline)
        if type(result) is not bytes:
            raise ProbeError("IncompleteEvidence", "Transport")
        if len(result) > _MAX_COMMAND_OUTPUT_BYTES:
            raise ProbeError("ResourceLimitExceeded", "Transport")
        return result

    @staticmethod
    def _single_line(output):
        try:
            value = output.decode("ascii")
        except UnicodeDecodeError:
            raise ProbeError("IncompleteEvidence", "Transport") from None
        if value.endswith("\r\n"):
            value = value[:-2]
        elif value.endswith("\n"):
            value = value[:-1]
        if "\r" in value or "\n" in value:
            raise ProbeError("IncompleteEvidence", "Transport")
        return value

    def identity(self, target, *, deadline):
        """Read and bind the exact serial and build fingerprint."""
        if not _valid_target(target):
            raise ProbeError("MalformedRequest", "Transport")
        if (self._identity_binding is not None
                and self._identity_binding[0] != target):
            raise ProbeError("IntegrityConflict", "Transport")
        state = self._single_line(self._run(target, ("get-state",), deadline))
        if state != "device":
            raise ProbeError("Disconnected", "Transport")
        build = self._single_line(
            self._run(target, ("shell", "getprop", "ro.build.fingerprint"), deadline)
        )
        if _BUILD_PATTERN.fullmatch(build) is None:
            raise ProbeError("IncompleteEvidence", "Transport")
        observed = (target, build)
        if self._identity_binding is not None and self._identity_binding != observed:
            raise ProbeError("IntegrityConflict", "Transport")
        self._identity_binding = observed
        return observed

    def _require_bound_target(self, target):
        if self._identity_binding is None or self._identity_binding[0] != target:
            raise ProbeError("IntegrityConflict", "Transport")

    @staticmethod
    def _parse_forward_list(output, target, local):
        """Parse a complete listing, rejecting malformed or duplicate rows."""
        if len(output) > _MAX_COMMAND_OUTPUT_BYTES:
            raise ProbeError("ResourceLimitExceeded", "Transport")
        try:
            listing = output.decode("ascii")
        except UnicodeDecodeError:
            raise ProbeError("IncompleteEvidence", "Transport") from None
        listing = listing.replace("\r\n", "\n")
        if "\r" in listing:
            raise ProbeError("IncompleteEvidence", "Transport")
        found = None
        matches = 0
        for line in listing.split("\n"):
            if any(ord(char) < 32 or ord(char) == 127 for char in line):
                raise ProbeError("IncompleteEvidence", "Transport")
            if not line:
                continue
            if len(line) > _MAX_FORWARD_LINE_LENGTH:
                raise ProbeError("ResourceLimitExceeded", "Transport")
            fields = line.split(" ")
            if len(fields) != 3 or any(not field for field in fields):
                raise ProbeError("IncompleteEvidence", "Transport")
            serial, observed_local, remote = fields
            if not _valid_target(serial) or not _FORWARD_SPEC_PATTERN.fullmatch(observed_local):
                raise ProbeError("IncompleteEvidence", "Transport")
            if not _FORWARD_SPEC_PATTERN.fullmatch(remote):
                raise ProbeError("IncompleteEvidence", "Transport")
            if serial == target and observed_local == local:
                matches += 1
                found = remote
        if matches > 1:
            raise ProbeError("IntegrityConflict", "Transport")
        return found

    def lookup(self, target, local, *, deadline):
        """Return one mapping for the bound target, or None when absent."""
        self._require_bound_target(target)
        if not _valid_local(local):
            raise ProbeError("MalformedRequest", "Transport")
        key = (target, local)
        record = self._forwards.get(key)
        if record is None:
            record = _ForwardRecord(_ForwardPhase.OBSERVED)
            self._forwards[key] = record
        first_create_readback = record.phase == _ForwardPhase.CREATE_SUCCEEDED
        if first_create_readback:
            record.phase = _ForwardPhase.CREATE_READBACK_PENDING
        first_remove_readback = record.phase == _ForwardPhase.REMOVE_SUCCEEDED
        if first_remove_readback:
            record.phase = _ForwardPhase.REMOVE_READBACK_PENDING
        owned_readback = record.phase == _ForwardPhase.OWNED
        try:
            output = self._run(target, ("forward", "--list"), deadline)
            remote = self._parse_forward_list(output, target, local)
        except Exception:
            if first_create_readback:
                record.phase = _ForwardPhase.CREATE_UNCERTAIN
            if first_remove_readback:
                record.phase = _ForwardPhase.REMOVE_UNCERTAIN
            if owned_readback:
                record.phase = _ForwardPhase.OWNERSHIP_UNCERTAIN
            raise
        if first_create_readback:
            record.phase = (
                _ForwardPhase.OWNED
                if remote == record.expected_remote
                else _ForwardPhase.CREATE_UNCERTAIN
            )
        elif first_remove_readback:
            if remote is None:
                record.phase = _ForwardPhase.REMOVED
            else:
                record.phase = _ForwardPhase.REMOVE_UNCERTAIN
        elif owned_readback and remote != record.expected_remote:
            record.phase = _ForwardPhase.OWNERSHIP_UNCERTAIN
        record.observed_remote = remote
        record.observed_deadline = deadline
        return remote

    def create_no_rebind(self, target, local, remote, *, deadline):
        """Create once after a same-phase absent readback; never retry or adopt."""
        self._require_bound_target(target)
        if not _valid_local(local) or not _valid_remote(remote):
            raise ProbeError("MalformedRequest", "Transport")
        key = (target, local)
        record = self._forwards.get(key)
        if (record is None or record.phase != _ForwardPhase.OBSERVED
                or record.observed_remote is not None
                or record.observed_deadline != deadline):
            raise ProbeError("IntegrityConflict", "Transport")
        record.phase = _ForwardPhase.CREATE_PENDING
        record.expected_remote = remote
        try:
            output = self._run(target, ("forward", "--no-rebind", local, remote), deadline)
            if output != b"":
                raise ProbeError("IncompleteEvidence", "Transport")
        except Exception:
            record.phase = _ForwardPhase.CREATE_UNCERTAIN
            raise
        record.phase = _ForwardPhase.CREATE_SUCCEEDED

    def remove(self, target, local, *, deadline):
        """Remove only a verified owned tuple following same-phase readback."""
        self._require_bound_target(target)
        if not _valid_local(local):
            raise ProbeError("MalformedRequest", "Transport")
        key = (target, local)
        record = self._forwards.get(key)
        if (record is None or record.phase != _ForwardPhase.OWNED
                or record.expected_remote is None
                or record.observed_remote != record.expected_remote
                or record.observed_deadline != deadline):
            raise ProbeError("IntegrityConflict", "Transport")
        record.phase = _ForwardPhase.REMOVE_PENDING
        try:
            output = self._run(target, ("forward", "--remove", local), deadline)
            if output != b"":
                raise ProbeError("IncompleteEvidence", "Transport")
        except Exception:
            record.phase = _ForwardPhase.REMOVE_UNCERTAIN
            raise
        record.phase = _ForwardPhase.REMOVE_SUCCEEDED

    @staticmethod
    def _close_failed_socket(
        sock, request_code, *, on_close=None, on_uncertain_close=None
    ):
        try:
            sock.close()
        except ProbeError as cleanup_error:
            if on_uncertain_close is not None:
                on_uncertain_close()
            raise ProbeError(
                "IncompleteEvidence",
                "Transport",
                request_failure_code=request_code,
                cleanup_failure_code=cleanup_error.code,
            ) from None
        except Exception:
            if on_uncertain_close is not None:
                on_uncertain_close()
            raise ProbeError(
                "IncompleteEvidence",
                "Transport",
                request_failure_code=request_code,
                cleanup_failure_code="IncompleteEvidence",
            ) from None
        if on_close is not None:
            on_close()

    def open_transport(self, session, authorization=None, *, deadline):
        """Open a one-shot authorized session forward through IPv4 loopback."""
        if not isinstance(session, ForwardSession):
            raise ProbeError("IntegrityConflict", "Transport")
        if session.adb is not self:
            raise ProbeError("IntegrityConflict", "Transport")
        phase = session._consume_transport_authorization(
            authorization, deadline=deadline
        )
        target, build = session.target, session.build
        local, remote = session.local, session.remote
        self._require_bound_target(target)
        if self.identity(target, deadline=deadline) != (target, build):
            raise ProbeError("IntegrityConflict", "Transport")
        if self.lookup(target, local, deadline=deadline) != remote:
            raise ProbeError("IntegrityConflict", "Transport")
        key = (target, local)
        record = self._forwards.get(key)
        if (not _valid_local(local) or not _valid_remote(remote)
                or record is None or record.phase != _ForwardPhase.OWNED
                or record.expected_remote != remote
                or record.observed_remote != remote
                or record.observed_deadline != deadline):
            raise ProbeError("IntegrityConflict", "Transport")
        sock = None
        mark_closed = lambda: session._mark_transport_closed(phase)
        mark_opened = lambda: session._mark_transport_opened(phase)
        mark_uncertain = lambda: session._mark_transport_uncertain(phase)
        try:
            sock = self._socket_factory(socket.AF_INET, socket.SOCK_STREAM)
            session._mark_transport_socket_created(phase)
            sock.settimeout(_deadline_remaining(self._clock, deadline))
            sock.connect(("127.0.0.1", int(local[4:])))
            session._mark_transport_opened(phase)
            _deadline_remaining(self._clock, deadline)
            return ForwardedSocketTransport(
                sock,
                clock=self._clock,
                writes_allowed=_TRANSPORT_POLICIES[phase].writes_allowed,
                close_deadline=_TRANSPORT_POLICIES[phase].release_deadline(
                    session.armed, deadline
                ),
                on_close=mark_closed,
            )
        except socket.timeout:
            if sock is not None:
                self._close_failed_socket(
                    sock,
                    "TimedOut",
                    on_close=mark_closed,
                    on_uncertain_close=mark_uncertain,
                )
            raise ProbeError("TimedOut", "Transport") from None
        except ProbeError as request_error:
            if sock is not None:
                self._close_failed_socket(
                    sock,
                    request_error.code,
                    on_close=mark_closed,
                    on_uncertain_close=mark_uncertain,
                )
            raise
        except Exception:
            try:
                _deadline_remaining(self._clock, deadline)
            except ProbeError as deadline_error:
                request_code = deadline_error.code
            else:
                request_code = "Disconnected"
            if sock is not None:
                self._close_failed_socket(
                    sock,
                    request_code,
                    on_close=mark_closed,
                    on_uncertain_close=mark_uncertain,
                )
            if request_code == "TimedOut":
                raise ProbeError("TimedOut", "Transport") from None
            raise ProbeError("Disconnected", "Transport") from None


class ForwardedSocketTransport:
    """Bound framed I/O over a verified socket with optional phase limits."""

    def __init__(
        self,
        sock,
        *,
        clock=time.monotonic,
        writes_allowed=True,
        close_deadline=None,
        on_close=None,
    ):
        self._socket = sock
        self._clock = clock
        self._writes_allowed = writes_allowed
        self._close_deadline = close_deadline
        self._on_close = on_close
        self._closed = False

    def _set_timeout(self, deadline):
        if self._closed:
            raise ProbeError("Disconnected", "Transport")
        remaining = _deadline_remaining(self._clock, deadline)
        self._socket.settimeout(remaining)

    def write(self, data, deadline):
        """Send one bounded readiness or cancellation frame before deadline."""
        if not self._writes_allowed:
            raise ProbeError("UnauthorizedPeer", "Transport")
        if type(data) is not bytes or not 0 < len(data) <= REQUEST_CAP + 4:
            raise ProbeError("ResourceLimitExceeded", "Transport")
        self._set_timeout(deadline)
        try:
            self._socket.sendall(data)
        except socket.timeout:
            raise TimeoutError from None
        except OSError:
            raise ConnectionError("transport unavailable") from None
        _deadline_remaining(self._clock, deadline)

    def read(self, count, deadline):
        """Read available response bytes without exceeding the frame bound."""
        if type(count) is not int or not 0 < count <= RESPONSE_CAP + 4:
            raise ProbeError("ResourceLimitExceeded", "Transport")
        self._set_timeout(deadline)
        try:
            result = self._socket.recv(count)
        except socket.timeout:
            raise TimeoutError from None
        except OSError:
            raise ConnectionError("transport unavailable") from None
        _deadline_remaining(self._clock, deadline)
        if type(result) is not bytes or len(result) > count:
            raise ProbeError("IntegrityConflict", "Transport")
        return result

    def close(self, deadline):
        """Close the socket within any fixed phase release limit."""
        if self._closed:
            return

        try:
            _deadline_remaining(self._clock, deadline)
            effective_deadline = deadline
            if self._close_deadline is not None:
                effective_deadline = min(deadline, self._close_deadline)
            _deadline_remaining(self._clock, effective_deadline)
        except ProbeError as deadline_error:
            try:
                self._socket.close()
            except Exception:
                raise ProbeError(
                    "IncompleteEvidence",
                    "Transport",
                    request_failure_code=deadline_error.code,
                    cleanup_failure_code="IncompleteEvidence",
                ) from None
            self._closed = True
            raise
        try:
            self._socket.close()
        except Exception:
            raise ProbeError("IncompleteEvidence", "Transport") from None
        self._closed = True
        if self._clock() >= effective_deadline:
            raise ProbeError("TimedOut", "Transport")
        if self._on_close is not None:
            self._on_close()
