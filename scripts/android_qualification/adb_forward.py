"""Bounded host ADB operations for an explicitly owned readiness forward.

Only the fixed ADB command forms in this module are accepted. The adapter binds
to one serial/build pair, records a forward as owned only after an exact
post-create readback, and connects only to that verified mapping on loopback.
It is an injected host adapter; importing this module never invokes ADB.
"""

from __future__ import annotations

import math
import hashlib
import os
import re
import selectors
import signal
import socket
import stat
import subprocess
import tempfile
import time
from dataclasses import dataclass
from enum import Enum
from typing import Optional

from .readiness_probe import ProbeError, REQUEST_CAP, RESPONSE_CAP, require
from .readiness_probe_session import (
    DIAGNOSTIC_COMMAND,
    ForwardSession,
    WINDOW_DISPLAY_COMMAND,
    _TRANSPORT_POLICIES,
)
from .packaging import QUALIFICATION_APPLICATION_ID


_MAX_COMMAND_OUTPUT_BYTES = 64 * 1024
_MAX_COMMAND_READ_BYTES = 4096
_MAX_FORWARD_LINE_LENGTH = 1024
_MAX_Q7_OUTPUT_BYTES = 1024 * 1024
_MAX_Q7_LINE_LENGTH = 16 * 1024
_Q7_HOST_DEADLINE_SECONDS = 5.0
_MAX_PACKAGE_PROCESS_ROWS = 1024
_PACKAGE_PROCESS_DIAGNOSTIC_SUBTYPES = frozenset(
    {
        "duplicate_pid",
        "empty_output",
        "empty_row",
        "line_too_long",
        "non_ascii_output",
        "numeric_value_out_of_range",
        "pid_not_decimal",
        "row_limit_exceeded",
        "target_name_not_exact",
        "uid_mismatch",
        "uid_not_decimal",
        "unexpected_header",
        "wrong_column_count",
    }
)
_PACKAGE_QUERY_DIAGNOSTIC_SUBTYPES = frozenset({"stderr_nonempty"})
_PROCESS_POLL_INTERVAL_SECONDS = 0.05
_PROCESS_CLEANUP_TIMEOUT_SECONDS = 1.0
_PROCESS_GROUP_QUERY_TIMEOUT_SECONDS = 0.25
_MAX_PROCESS_GROUP_OUTPUT_BYTES = 64 * 1024
_TARGET_PATTERN = re.compile(r"[A-Za-z0-9._:-]{1,128}\Z")
_BUILD_PATTERN = re.compile(r"[A-Za-z0-9][A-Za-z0-9._:/+\-]{0,255}\Z")
_READINESS_PROBE_APK_SHA256 = (
    "1cdac21e45275ccc0c4e55aa4cdde320549a07807e7b664cfb573ff7310be37a"
)
_MAX_READINESS_PROBE_APK_BYTES = 32 * 1024 * 1024
_LOCAL_PATTERN = re.compile(r"tcp:([1-9][0-9]{0,4})\Z")
_REMOTE_PATTERN = re.compile(r"localabstract:[A-Za-z0-9_-]{1,100}\Z")
_FORWARD_SPEC_PATTERN = re.compile(r"[a-z][a-z0-9]*:[A-Za-z0-9._:/+\-]{1,256}\Z")
_READINESS_PROBE_PACKAGE = "com.argusromtoolkit.argus.readinessprobe"
_READINESS_PROBE_VERSION_CODE = 1
_READINESS_PROBE_LAUNCH_COMPONENT = f"{_READINESS_PROBE_PACKAGE}/.LauncherActivity"
_PACKAGE_QUERY_PACKAGES = frozenset(
    {QUALIFICATION_APPLICATION_ID, _READINESS_PROBE_PACKAGE}
)


class _PackageProcessObservationError(ProbeError):
    """Carry one closed parser label without retaining a process row."""

    def __init__(
        self,
        diagnostic_subtype,
        code="IncompleteEvidence",
        *,
        line_number=None,
        token_count=None,
        parser_state="unknown",
    ):
        if diagnostic_subtype not in _PACKAGE_PROCESS_DIAGNOSTIC_SUBTYPES:
            diagnostic_subtype = "unexpected_header"
        self.diagnostic_subtype = diagnostic_subtype
        self.line_number = (
            line_number if type(line_number) is int and line_number > 0 else None
        )
        self.token_count = (
            token_count if type(token_count) is int and token_count >= 0 else None
        )
        self.parser_state = (
            parser_state
            if parser_state in {"unknown", "row_shape", "target_name"}
            else "unknown"
        )
        super().__init__(code, "Transport")


class _PackageQueryObservationError(ProbeError):
    """Carry a closed package-query failure label without diagnostic text."""

    def __init__(self, diagnostic_subtype):
        if diagnostic_subtype not in _PACKAGE_QUERY_DIAGNOSTIC_SUBTYPES:
            diagnostic_subtype = "stderr_nonempty"
        self.diagnostic_subtype = diagnostic_subtype
        super().__init__("IncompleteEvidence", "Transport")


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


@dataclass(frozen=True)
class Q7CommandResult:
    """Sanitized process facts for the one fixed Q7 exploratory command."""

    command_count: int
    started_monotonic: float
    finished_monotonic: float
    stdout_bytes: int
    total_output_bytes: int
    exit_code: Optional[int]
    classification: str
    cleanup_complete: bool

    @property
    def succeeded(self):
        return self.classification == "exit_zero" and self.cleanup_complete


@dataclass
class _CommandRunState:
    """Keep process bookkeeping without retaining diagnostic output."""

    started_monotonic: float
    spawned: bool = False
    stdout_bytes: int = 0
    total_output_bytes: int = 0
    stderr_empty: bool = True
    exit_code: Optional[int] = None
    error_code: Optional[str] = None
    cleanup_complete: bool = True
    finished_monotonic: Optional[float] = None


class _DiscardLineLengthGuard:
    """Enforce a line bound without retaining the bytes being checked."""

    def __init__(self, maximum):
        self._maximum = maximum
        self._current = 0

    def feed(self, chunk):
        for value in chunk:
            if value == 10:
                self._current = 0
            else:
                self._current += 1
                if self._current > self._maximum:
                    raise ProbeError("ResourceLimitExceeded", "Transport")

    def finish(self):
        if self._current > self._maximum:
            raise ProbeError("ResourceLimitExceeded", "Transport")


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


def _valid_android_user_id_text(value):
    if type(value) is not str or re.fullmatch(r"(?:0|[1-9][0-9]{0,9})", value) is None:
        return False
    return int(value) <= (1 << 31) - 1


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
    def _pinned_readiness_fd(path):
        """Return the descriptor for the pinned APK in a private temp directory."""
        if (
            type(path) is not str
            or not os.path.isabs(path)
            or not path.lower().endswith(".apk")
            or len(path) > 4096
            or any(character in path for character in "\x00\r\n")
        ):
            return None
        try:
            link_target = os.readlink(path)
            match = re.fullmatch(r"/dev/fd/([0-9]+)", link_target)
            if match is None:
                return None
            descriptor = int(match.group(1))
            parent = os.lstat(os.path.dirname(path))
            if (
                stat.S_ISLNK(parent.st_mode)
                or not stat.S_ISDIR(parent.st_mode)
                or parent.st_uid != os.getuid()
                or stat.S_IMODE(parent.st_mode) != 0o700
            ):
                return None
            before = os.fstat(descriptor)
            if (
                not stat.S_ISREG(before.st_mode)
                or before.st_uid != os.getuid()
                or stat.S_IMODE(before.st_mode) != 0o400
                or before.st_size <= 0
            ):
                return None
            if before.st_size > _MAX_READINESS_PROBE_APK_BYTES:
                return None
            path_stat = os.stat(path, follow_symlinks=True)
            file_identity = lambda value: (
                value.st_ino,
                value.st_size,
                value.st_mtime_ns,
                value.st_ctime_ns,
            )
            if file_identity(before) != file_identity(path_stat):
                return None
            digest = hashlib.sha256()
            total_bytes = 0
            while True:
                chunk = os.pread(descriptor, 64 * 1024, total_bytes)
                if not chunk:
                    break
                total_bytes += len(chunk)
                if total_bytes > _MAX_READINESS_PROBE_APK_BYTES:
                    return None
                digest.update(chunk)
            after = os.fstat(descriptor)
            current_path = os.stat(path, follow_symlinks=True)
            if (
                file_identity(before) != file_identity(after)
                or file_identity(after) != file_identity(current_path)
                or digest.hexdigest() != _READINESS_PROBE_APK_SHA256
            ):
                return None
            return descriptor
        except (OSError, OverflowError, ValueError):
            return None

    @staticmethod
    def _allowed_vector(argv):
        if type(argv) is not tuple or len(argv) < 4:
            return False
        if argv[0] != "adb" or argv[1] != "-s" or not _valid_target(argv[2]):
            return False
        command = argv[3:]
        if command in (
            ("get-state",),
            ("shell", "getprop", "ro.build.fingerprint"),
            ("shell", "getprop", "ro.build.version.sdk"),
            ("shell", "getprop", "ro.product.cpu.abi"),
            ("shell", "am", "get-current-user"),
            ("shell", "ps", "-A", "-n", "-w", "-o", "UID,PID,NAME"),
            ("forward", "--list"),
        ):
            return True
        if (
            len(command) == 8
            and command[:4] == ("shell", "am", "start", "--user")
            and _valid_android_user_id_text(command[4])
            and command[5:] == ("-W", "-n", _READINESS_PROBE_LAUNCH_COMPONENT)
        ):
            return True
        if (
            len(command) == 6
            and command[:4] == ("shell", "pm", "uninstall", "--user")
            and _valid_android_user_id_text(command[4])
            and command[5] == _READINESS_PROBE_PACKAGE
        ):
            return True
        if (
            len(command) == 9
            and command[:7]
            == ("shell", "pm", "list", "packages", "--show-versioncode", "-U", "--user")
            and _valid_android_user_id_text(command[7])
            and type(command[8]) is str
            and command[8] in _PACKAGE_QUERY_PACKAGES
        ):
            return True
        if (
            len(command) == 5
            and command[:3] == ("install", "--no-streaming", "--user")
            and _valid_android_user_id_text(command[3])
            and _AdbCommandRunner._pinned_readiness_fd(command[4]) is not None
        ):
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

    def _execute(self, argv, deadline, *, started_monotonic, output_limit,
                 stdout_consumer, enforce_q7_line_limit=False):
        """Drain one child process while retaining only caller-selected output."""
        state = _CommandRunState(started_monotonic=started_monotonic)
        try:
            _deadline_remaining(self._clock, deadline)
            self._waitid_flags()
            inherited_fds = ()
            if len(argv) > 3 and argv[3] == "install":
                descriptor = self._pinned_readiness_fd(argv[-1])
                if descriptor is None:
                    raise ProbeError("MalformedRequest", "Transport")
                inherited_fds = (descriptor,)
            _deadline_remaining(self._clock, deadline)
            process = self._popen(
                argv,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                shell=False,
                close_fds=True,
                start_new_session=True,
                pass_fds=inherited_fds,
            )
            state.spawned = True
        except ProbeError as exc:
            state.error_code = exc.code
            try:
                state.finished_monotonic = self._clock()
            except Exception:
                state.finished_monotonic = started_monotonic
                state.error_code = "IncompleteEvidence"
            return state
        except Exception:
            state.error_code = "Disconnected"
            try:
                state.finished_monotonic = self._clock()
            except Exception:
                state.finished_monotonic = started_monotonic
            return state

        selector = None
        process_reaped = False
        stderr_line_guard = (
            _DiscardLineLengthGuard(_MAX_Q7_LINE_LENGTH)
            if enforce_q7_line_limit
            else None
        )
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
                        output_limit - state.total_output_bytes + 1,
                    )
                    chunk = self._reader(key.fd, allowance)
                    if type(chunk) is not bytes:
                        raise ProbeError("IncompleteEvidence", "Transport")
                    if not chunk:
                        selector.unregister(key.fileobj)
                        continue
                    observed_total = state.total_output_bytes + len(chunk)
                    if observed_total > output_limit:
                        state.total_output_bytes = output_limit
                        raise ProbeError("ResourceLimitExceeded", "Transport")
                    state.total_output_bytes = observed_total
                    if key.fileobj is process.stdout:
                        state.stdout_bytes += len(chunk)
                        stdout_consumer(chunk)
                    else:
                        state.stderr_empty = False
                        if stderr_line_guard is not None:
                            stderr_line_guard.feed(chunk)

            if stderr_line_guard is not None:
                stderr_line_guard.finish()
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
            state.exit_code = return_code
            _deadline_remaining(self._clock, deadline)
            if return_code != 0:
                raise ProbeError("IncompleteEvidence", "Transport")
        except ProbeError as exc:
            state.error_code = exc.code
        except subprocess.TimeoutExpired:
            state.error_code = "TimedOut"
        except Exception:
            state.error_code = "IncompleteEvidence"
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
            state.cleanup_complete = cleanup_complete
            if not cleanup_complete:
                state.error_code = "IncompleteEvidence"
            try:
                state.finished_monotonic = self._clock()
            except Exception:
                state.finished_monotonic = started_monotonic
                state.error_code = "IncompleteEvidence"
        return state

    @staticmethod
    def _result_classification(state):
        if not state.cleanup_complete:
            return "cleanup_unverified"
        if state.error_code is None and state.exit_code == 0:
            return "exit_zero"
        if state.error_code == "TimedOut":
            return "host_timeout"
        if not state.spawned:
            return "launch_failed"
        if state.error_code == "ResourceLimitExceeded":
            return "resource_limit"
        if state.exit_code is not None and state.exit_code != 0:
            return "process_nonzero"
        return "incomplete"

    @staticmethod
    def _is_package_list_query(argv):
        return (
            len(argv) == 12
            and argv[3:7] == ("shell", "pm", "list", "packages")
            and argv[7:10]
            == ("--show-versioncode", "-U", "--user")
            and _valid_android_user_id_text(argv[10])
            and argv[11] in _PACKAGE_QUERY_PACKAGES
        )

    def run(self, argv, deadline):
        """Return stdout bytes only, or a closed error without process text."""
        if not self._allowed_vector(argv):
            raise ProbeError("MalformedRequest", "Transport")
        _deadline_remaining(self._clock, deadline)
        self._waitid_flags()
        started = self._clock()
        output = bytearray()
        state = self._execute(
            argv,
            deadline,
            started_monotonic=started,
            output_limit=_MAX_COMMAND_OUTPUT_BYTES,
            stdout_consumer=output.extend,
        )
        if self._result_classification(state) != "exit_zero":
            raise ProbeError(state.error_code or "IncompleteEvidence", "Transport")
        if self._is_package_list_query(argv) and not state.stderr_empty:
            raise _PackageQueryObservationError("stderr_nonempty")
        return bytes(output)

    def run_q7(self, target, stdout_consumer):
        """Run the fixed activity diagnostic with bounded, streaming output."""
        return self._run_bounded_diagnostic(
            target, DIAGNOSTIC_COMMAND, stdout_consumer
        )

    def run_window_displays(self, target, stdout_consumer):
        """Run the fixed WindowManager display diagnostic."""
        return self._run_bounded_diagnostic(
            target, WINDOW_DISPLAY_COMMAND, stdout_consumer
        )

    def _run_bounded_diagnostic(self, target, command, stdout_consumer):
        started = self._clock()
        try:
            if (
                not _valid_target(target)
                or not callable(stdout_consumer)
                or command not in (DIAGNOSTIC_COMMAND, WINDOW_DISPLAY_COMMAND)
            ):
                raise ProbeError("MalformedRequest", "Transport")
            deadline = started + _Q7_HOST_DEADLINE_SECONDS
            _deadline_remaining(self._clock, deadline)
        except ProbeError as exc:
            try:
                finished = self._clock()
            except Exception:
                finished = started
            return Q7CommandResult(
                command_count=0,
                started_monotonic=started,
                finished_monotonic=finished,
                stdout_bytes=0,
                total_output_bytes=0,
                exit_code=None,
                classification=(
                    "host_timeout" if exc.code == "TimedOut" else "launch_failed"
                ),
                cleanup_complete=True,
            )
        except Exception:
            try:
                finished = self._clock()
            except Exception:
                finished = started
            return Q7CommandResult(
                command_count=0,
                started_monotonic=started,
                finished_monotonic=finished,
                stdout_bytes=0,
                total_output_bytes=0,
                exit_code=None,
                classification="launch_failed",
                cleanup_complete=True,
            )

        argv = ("adb", "-s", target, *command)
        state = self._execute(
            argv,
            deadline,
            started_monotonic=started,
            output_limit=_MAX_Q7_OUTPUT_BYTES,
            stdout_consumer=stdout_consumer,
            enforce_q7_line_limit=True,
        )
        return Q7CommandResult(
            command_count=1 if state.spawned else 0,
            started_monotonic=started,
            finished_monotonic=(
                state.finished_monotonic
                if state.finished_monotonic is not None
                else started
            ),
            stdout_bytes=state.stdout_bytes,
            total_output_bytes=state.total_output_bytes,
            exit_code=state.exit_code,
            classification=self._result_classification(state),
            cleanup_complete=state.cleanup_complete,
        )


class AdbForwardAdapter:
    """Read identity, inspect fixed packages, install one probe, or own a forward.

    Package checks require the same serial/build binding and return no install
    paths. Package operations use the Android user ID observed at baseline.
    Probe installation requires the package to be absent, checks one pinned
    APK, and never requests package replacement. Cleanup is limited to that
    user and an install attempt made by this adapter. The adapter does not
    validate external authorization. Manage forward creation, lookup, removal
    and transport through ``ForwardSession``; its exact readbacks and durable
    obligation govern cleanup.
    """

    def __init__(self, *, runner=None, clock=time.monotonic, socket_factory=None):
        self._clock = clock
        self._runner = runner if runner is not None else _AdbCommandRunner(clock=clock)
        self._socket_factory = socket_factory or socket.socket
        self._identity_binding = None
        self._readiness_android_user_id = None
        self._readiness_baseline_absent = None
        self._readiness_install_attempted = False
        self._readiness_installed_uid = None
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

    def platform_api_level(self, target, *, deadline):
        """Read the Android API level with one fixed, bounded property query."""
        self._require_bound_target(target)
        value = self._single_line(
            self._run(target, ("shell", "getprop", "ro.build.version.sdk"), deadline)
        )
        if re.fullmatch(r"[1-9][0-9]{0,2}", value) is None:
            raise ProbeError("IncompleteEvidence", "Transport")
        api_level = int(value)
        if api_level > 1000:
            raise ProbeError("IncompleteEvidence", "Transport")
        return api_level

    def platform_primary_abi(self, target, *, deadline):
        """Read the primary Android ABI through one fixed property query."""
        self._require_bound_target(target)
        value = self._single_line(
            self._run(target, ("shell", "getprop", "ro.product.cpu.abi"), deadline)
        )
        if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}", value) is None:
            raise ProbeError("IncompleteEvidence", "Transport")
        return value

    def current_android_user_id(self, target, *, deadline):
        """Read the numeric Android user selected for package operations."""
        self._require_bound_target(target)
        value = self._single_line(
            self._run(target, ("shell", "am", "get-current-user"), deadline)
        )
        if re.fullmatch(r"(?:0|[1-9][0-9]{0,9})", value) is None:
            raise ProbeError("IncompleteEvidence", "Transport")
        user_id = int(value)
        if user_id > (1 << 31) - 1:
            raise ProbeError("IncompleteEvidence", "Transport")
        if self._readiness_android_user_id is None:
            self._readiness_android_user_id = user_id
        elif self._readiness_android_user_id != user_id:
            raise ProbeError("IntegrityConflict", "Transport")
        return user_id

    def launch_readiness_probe(self, target, *, deadline):
        """Launch the probe entrypoint and retain only its completion facts.

        The entrypoint opens the passive owner-control screen. Discovery starts
        only after an owner action, so Android may report either activity.
        """
        self._require_bound_target(target)
        user_id = self.current_android_user_id(target, deadline=deadline)
        output = self._run(
            target,
            (
                "shell", "am", "start", "--user", str(user_id), "-W", "-n",
                _READINESS_PROBE_LAUNCH_COMPONENT,
            ),
            deadline,
        )
        try:
            text = output.decode("ascii")
        except UnicodeDecodeError:
            raise ProbeError("IncompleteEvidence", "Transport") from None
        lines = text.splitlines()
        if (
            not lines
            or any(len(line.encode("ascii")) > _MAX_FORWARD_LINE_LENGTH for line in lines)
            or "\r" in text
        ):
            raise ProbeError("IncompleteEvidence", "Transport")
        short_component = _READINESS_PROBE_LAUNCH_COMPONENT
        full_component = (
            f"{_READINESS_PROBE_PACKAGE}/"
            "com.argusromtoolkit.argus.readinessprobe.LauncherActivity"
        )
        control_component = f"{_READINESS_PROBE_PACKAGE}/.ProbeControlActivity"
        full_control_component = (
            f"{_READINESS_PROBE_PACKAGE}/"
            "com.argusromtoolkit.argus.readinessprobe.ProbeControlActivity"
        )
        starts = [line for line in lines if line.startswith("Starting: Intent {")]
        if starts not in (
            [f"Starting: Intent {{ cmp={short_component} }}"],
            [f"Starting: Intent {{ cmp={full_component} }}"],
        ):
            raise ProbeError("IncompleteEvidence", "Transport")
        statuses = [line.removeprefix("Status: ") for line in lines
                    if line.startswith("Status: ")]
        if statuses == ["timeout"]:
            raise ProbeError("TimedOut", "Transport")
        components = [line.removeprefix("Activity: ") for line in lines
                      if line.startswith("Activity: ")]
        launch_states = [line.removeprefix("LaunchState: ") for line in lines
                         if line.startswith("LaunchState: ")]
        timing_fields = {}
        for name in ("ThisTime", "TotalTime", "WaitTime"):
            values = [line.removeprefix(f"{name}: ") for line in lines
                      if line.startswith(f"{name}: ")]
            if len(values) > 1:
                raise ProbeError("IncompleteEvidence", "Transport")
            if values:
                if re.fullmatch(r"(?:0|[1-9][0-9]{0,8})", values[0]) is None:
                    raise ProbeError("IncompleteEvidence", "Transport")
                timing_fields[name] = int(values[0])
        if (
            statuses != ["ok"]
            or components not in (
                [short_component],
                [full_component],
                [control_component],
                [full_control_component],
            )
            or lines[-1] != "Complete"
            or lines.count("Complete") != 1
            or len(launch_states) > 1
            or any(re.fullmatch(r"[A-Z][A-Z_]{0,15}", item) is None
                   for item in launch_states)
            or any(line.startswith("Error:") for line in lines)
        ):
            raise ProbeError("IncompleteEvidence", "Transport")
        known_lines = {
            f"Starting: Intent {{ cmp={short_component} }}",
            f"Starting: Intent {{ cmp={full_component} }}",
            "Status: ok",
            "Status: timeout",
            "Complete",
            *(f"LaunchState: {state}" for state in launch_states),
            *(f"Activity: {component}" for component in components),
            *(
                f"{name}: {value}"
                for name, value in timing_fields.items()
            ),
        }
        if any(line not in known_lines for line in lines):
            raise ProbeError("IncompleteEvidence", "Transport")
        result = {
            "state": "launched",
            "component": (
                short_component
                if components[0] in (short_component, full_component)
                else control_component
            ),
            "launch_state": launch_states[0] if launch_states else None,
            "this_time_ms": timing_fields.get("ThisTime"),
            "total_time_ms": timing_fields.get("TotalTime"),
            "wait_time_ms": timing_fields.get("WaitTime"),
        }
        return result

    def package_process_state(self, target, package, *, expected_uid, deadline):
        """Return only target-package process roles from the system process list.

        Rows for other processes are ignored before their UID or PID values are
        checked. Malformed row structure still fails the observation closed.
        """
        if type(package) is not str or package not in _PACKAGE_QUERY_PACKAGES:
            raise ProbeError("MalformedRequest", "Transport")
        if type(expected_uid) is not int or not 0 <= expected_uid <= (1 << 31) - 1:
            raise ProbeError("MalformedRequest", "Transport")
        self._require_bound_target(target)
        self.current_android_user_id(target, deadline=deadline)
        output = self._run(
            target,
            ("shell", "ps", "-A", "-n", "-w", "-o", "UID,PID,NAME"),
            deadline,
        )
        try:
            text = output.decode("ascii")
        except UnicodeDecodeError:
            raise _PackageProcessObservationError("non_ascii_output") from None
        lines = text.splitlines()
        if not lines:
            raise _PackageProcessObservationError("empty_output")
        if any(len(line.encode("ascii")) > _MAX_FORWARD_LINE_LENGTH for line in lines):
            raise _PackageProcessObservationError("line_too_long")
        if any(not line for line in lines):
            raise _PackageProcessObservationError("empty_row")
        if lines[0].split() != ["UID", "PID", "NAME"]:
            raise _PackageProcessObservationError("unexpected_header")
        if len(lines) - 1 > _MAX_PACKAGE_PROCESS_ROWS:
            raise _PackageProcessObservationError(
                "row_limit_exceeded", "ResourceLimitExceeded"
            )
        roles = []
        seen_pids = set()
        for line_number, line in enumerate(lines[1:], start=2):
            fields = line.split(None, 2)
            if len(fields) != 3:
                raise _PackageProcessObservationError(
                    "wrong_column_count",
                    line_number=line_number,
                    token_count=len(fields),
                    parser_state="row_shape",
                )
            uid_text, pid_text, process_name = fields
            target_name = (
                process_name == package
                or process_name.startswith(package + ":")
                or (
                    len(process_name) > len(package)
                    and process_name.startswith(package)
                    and process_name[len(package)].isspace()
                )
            )
            if not target_name:
                continue
            if any(character.isspace() for character in process_name):
                raise _PackageProcessObservationError(
                    "target_name_not_exact",
                    line_number=line_number,
                    token_count=len(fields),
                    parser_state="target_name",
                )
            if re.fullmatch(r"[0-9]+", uid_text) is None:
                raise _PackageProcessObservationError("uid_not_decimal")
            if re.fullmatch(r"[1-9][0-9]{0,9}", pid_text) is None:
                raise _PackageProcessObservationError("pid_not_decimal")
            uid = int(uid_text)
            pid = int(pid_text)
            if uid > (1 << 31) - 1 or pid > (1 << 31) - 1:
                raise _PackageProcessObservationError("numeric_value_out_of_range")
            if process_name == package or process_name.startswith(package + ":"):
                if pid in seen_pids:
                    raise _PackageProcessObservationError("duplicate_pid")
                seen_pids.add(pid)
                if uid != expected_uid:
                    raise _PackageProcessObservationError(
                        "uid_mismatch", "IntegrityConflict"
                    )
            roles.append("main" if process_name == package else "secondary")
        return {
            "state": "running" if roles else "absent",
            "process_count": len(roles),
            "uid_matches_package": bool(roles),
            "roles": roles,
        }

    def uninstall_readiness_probe(self, target, *, deadline):
        """Remove only the pinned package installed by this adapter instance.

        The first package observation must have shown absence. Before cleanup,
        recheck the package version for the user observed at baseline. Cleanup
        remains pinned to that user even if the device's active user changed.
        An absent package needs no uninstall command.
        """
        self._require_bound_target(target)
        if (
            self._readiness_baseline_absent is not True
            or not self._readiness_install_attempted
        ):
            raise ProbeError("IntegrityConflict", "Transport")
        package_state = self.package_install_state(
            target,
            _READINESS_PROBE_PACKAGE,
            deadline=deadline,
            user_id=self._readiness_android_user_id,
        )
        if package_state["state"] == "absent":
            self._readiness_install_attempted = False
            self._readiness_installed_uid = None
            return {"state": "already_absent"}
        if (
            self._readiness_installed_uid is None
            or package_state["version_code"] != _READINESS_PROBE_VERSION_CODE
            or package_state["uid"] != self._readiness_installed_uid
        ):
            raise ProbeError("IntegrityConflict", "Transport")
        result = self._single_line(
            self._run(
                target,
                ("shell", "pm", "uninstall", "--user",
                 str(self._readiness_android_user_id),
                 _READINESS_PROBE_PACKAGE),
                deadline,
            )
        )
        if result != "Success":
            raise ProbeError("IncompleteEvidence", "Transport")
        self._readiness_install_attempted = False
        self._readiness_installed_uid = None
        return {"state": "uninstalled"}

    def recover_readiness_cleanup(self, target, install_record, *, deadline):
        """Recover cleanup ownership from the verified private install record.

        The current device, Android user, package version, and UID are checked
        before the existing uninstall path is allowed to remove the package.
        """
        self._require_bound_target(target)
        if type(install_record) is not dict:
            raise ProbeError("IntegrityConflict", "Transport")
        identity = install_record.get("identity_private")
        artifact = install_record.get("artifact")
        binding = self._identity_binding
        if (
            install_record.get("schema")
            != "argus-issue-74-b1-preparation-observation-v1"
            or install_record.get("identity_preflight_record_bound") is not True
            or install_record.get("identity_match") is not True
            or install_record.get("qualification_assertions_passed") is not False
            or install_record.get("package_baseline_absent") is not True
            or install_record.get("install_status") != "installed"
            or not isinstance(identity, dict)
            or identity.get("serial") != target
            or binding is None
            or identity.get("build_fingerprint") != binding[1]
            or not isinstance(artifact, dict)
            or artifact.get("package") != _READINESS_PROBE_PACKAGE
            or artifact.get("sha256") != _READINESS_PROBE_APK_SHA256
            or type(artifact.get("version_code")) is not int
            or artifact.get("version_code") != _READINESS_PROBE_VERSION_CODE
        ):
            raise ProbeError("IntegrityConflict", "Transport")
        user_id = install_record.get("android_user_private")
        installed_uid = install_record.get("package_uid_private")
        if (
            type(user_id) is not int
            or not 0 <= user_id <= (1 << 31) - 1
            or type(installed_uid) is not int
            or not 0 < installed_uid <= (1 << 31) - 1
        ):
            raise ProbeError("IntegrityConflict", "Transport")
        if self.current_android_user_id(target, deadline=deadline) != user_id:
            self._readiness_android_user_id = None
            raise ProbeError("IntegrityConflict", "Transport")

        self._readiness_baseline_absent = True
        self._readiness_install_attempted = True
        self._readiness_installed_uid = installed_uid
        cleanup = self.uninstall_readiness_probe(target, deadline=deadline)
        readback = self.package_install_state(
            target,
            _READINESS_PROBE_PACKAGE,
            deadline=deadline,
            user_id=user_id,
        )
        if readback["state"] != "absent":
            raise ProbeError("IncompleteEvidence", "Transport")
        return {"state": cleanup["state"], "readback": "absent"}

    def package_install_state(self, target, package, *, deadline, user_id=None):
        """Return package state after a complete, clean package-list query.

        The runner accepts an empty result as no match only after a bounded
        successful exit and empty stderr. Diagnostic bytes are never retained.
        """
        if type(package) is not str or package not in _PACKAGE_QUERY_PACKAGES:
            raise ProbeError("MalformedRequest", "Transport")
        self._require_bound_target(target)
        if user_id is None:
            user_id = self.current_android_user_id(target, deadline=deadline)
        elif (
            type(user_id) is not int
            or not 0 <= user_id <= (1 << 31) - 1
            or user_id != self._readiness_android_user_id
        ):
            raise ProbeError("IntegrityConflict", "Transport")

        def remember_baseline(state):
            if (
                package == _READINESS_PROBE_PACKAGE
                and self._readiness_baseline_absent is None
            ):
                self._readiness_baseline_absent = state == "absent"

        output = self._run(
            target,
            (
                "shell",
                "pm",
                "list",
                "packages",
                "--show-versioncode",
                "-U",
                "--user",
                str(user_id),
                package,
            ),
            deadline,
        )
        if output == b"":
            result = {"state": "absent", "version_code": None, "uid": None}
            remember_baseline(result["state"])
            return result
        package_prefix = b"package:"
        expected_package = package.encode("ascii")
        exact_rows = []
        lines = output.splitlines()
        if not lines or any(len(line) > _MAX_FORWARD_LINE_LENGTH for line in lines):
            raise ProbeError("IncompleteEvidence", "Transport")
        for line in lines:
            first_token = line.split(b" ", 1)[0]
            if not first_token.startswith(package_prefix):
                raise ProbeError("IncompleteEvidence", "Transport")
            if first_token[len(package_prefix) :] != expected_package:
                continue
            match = re.fullmatch(
                rb"package:"
                + re.escape(expected_package)
                + rb" versionCode:([0-9]+) uid:([0-9]+)",
                line,
            )
            if match is None:
                raise ProbeError("IncompleteEvidence", "Transport")
            version_code = int(match.group(1))
            uid = int(match.group(2))
            if version_code > (1 << 63) - 1 or uid > (1 << 31) - 1:
                raise ProbeError("IncompleteEvidence", "Transport")
            exact_rows.append((version_code, uid))
        if not exact_rows:
            result = {"state": "absent", "version_code": None, "uid": None}
            remember_baseline(result["state"])
            return result
        if len(exact_rows) != 1:
            raise ProbeError("IncompleteEvidence", "Transport")
        version_code, uid = exact_rows[0]
        result = {"state": "present", "version_code": version_code, "uid": uid}
        remember_baseline(result["state"])
        return result

    def install_readiness_probe(self, target, artifact_path, *, deadline):
        """Install the pinned Readiness APK for the baseline Android user.

        The source is copied into a private read-only file and checked before
        the ADB child receives its descriptor. The bounded command omits the
        replacement flag and returns only a success classification.
        """
        self._require_bound_target(target)
        if self._readiness_baseline_absent is not True:
            raise ProbeError("IntegrityConflict", "Transport")
        user_id = self.current_android_user_id(target, deadline=deadline)
        try:
            path = os.fspath(artifact_path)
        except (TypeError, ValueError):
            raise ProbeError("MalformedRequest", "Transport") from None
        if (
            type(path) is not str
            or not os.path.isabs(path)
            or not path.lower().endswith(".apk")
            or len(path) > 4096
            or any(character in path for character in "\x00\r\n")
        ):
            raise ProbeError("MalformedRequest", "Transport")
        _deadline_remaining(self._clock, deadline)
        no_follow = getattr(os, "O_NOFOLLOW", None)
        if no_follow is None:
            raise ProbeError("IncompleteEvidence", "Transport")
        with tempfile.TemporaryDirectory(prefix="argus-readiness-install-") as directory:
            directory_stat = os.lstat(directory)
            if (
                stat.S_ISLNK(directory_stat.st_mode)
                or not stat.S_ISDIR(directory_stat.st_mode)
                or directory_stat.st_uid != os.getuid()
                or stat.S_IMODE(directory_stat.st_mode) != 0o700
            ):
                raise ProbeError("IncompleteEvidence", "Transport")
            staged_path = os.path.join(directory, "payload")
            source_fd = None
            staged_fd = None
            install_fd = None
            try:
                source_fd = os.open(path, os.O_RDONLY | no_follow)
                source_before = os.fstat(source_fd)
                if not stat.S_ISREG(source_before.st_mode) or source_before.st_size <= 0:
                    raise ProbeError("MalformedRequest", "Transport")
                if source_before.st_size > _MAX_READINESS_PROBE_APK_BYTES:
                    raise ProbeError("ResourceLimitExceeded", "Transport")
                staged_fd = os.open(
                    staged_path,
                    os.O_WRONLY | os.O_CREAT | os.O_EXCL | no_follow,
                    0o600,
                )
                digest = hashlib.sha256()
                total_bytes = 0
                while True:
                    _deadline_remaining(self._clock, deadline)
                    chunk = os.read(source_fd, 64 * 1024)
                    if not chunk:
                        break
                    total_bytes += len(chunk)
                    if total_bytes > _MAX_READINESS_PROBE_APK_BYTES:
                        raise ProbeError("ResourceLimitExceeded", "Transport")
                    digest.update(chunk)
                    remaining = memoryview(chunk)
                    while remaining:
                        written = os.write(staged_fd, remaining)
                        if type(written) is not int or written <= 0:
                            raise ProbeError("IncompleteEvidence", "Transport")
                        remaining = remaining[written:]
                source_after = os.fstat(source_fd)
                try:
                    current_source_path = os.stat(path, follow_symlinks=False)
                except OSError:
                    raise ProbeError("IntegrityConflict", "Transport") from None
                source_identity = lambda value: (
                    value.st_dev,
                    value.st_ino,
                    value.st_size,
                    value.st_mtime_ns,
                    value.st_ctime_ns,
                )
                if (
                    total_bytes != source_before.st_size
                    or source_identity(source_before) != source_identity(source_after)
                    or source_identity(source_after) != source_identity(current_source_path)
                    or digest.hexdigest() != _READINESS_PROBE_APK_SHA256
                ):
                    raise ProbeError("IntegrityConflict", "Transport")
                os.fsync(staged_fd)
                os.fchmod(staged_fd, 0o400)
                os.close(staged_fd)
                staged_fd = None
                install_fd = os.open(staged_path, os.O_RDONLY | no_follow)
                staged_stat = os.fstat(install_fd)
                if (
                    not stat.S_ISREG(staged_stat.st_mode)
                    or staged_stat.st_uid != os.getuid()
                    or stat.S_IMODE(staged_stat.st_mode) != 0o400
                    or staged_stat.st_size != total_bytes
                ):
                    raise ProbeError("IntegrityConflict", "Transport")
                staged_digest = hashlib.sha256()
                offset = 0
                while offset < staged_stat.st_size:
                    _deadline_remaining(self._clock, deadline)
                    chunk = os.pread(install_fd, 64 * 1024, offset)
                    if not chunk:
                        raise ProbeError("IncompleteEvidence", "Transport")
                    staged_digest.update(chunk)
                    offset += len(chunk)
                if staged_digest.hexdigest() != _READINESS_PROBE_APK_SHA256:
                    raise ProbeError("IntegrityConflict", "Transport")
                _deadline_remaining(self._clock, deadline)
                package_state = self.package_install_state(
                    target,
                    _READINESS_PROBE_PACKAGE,
                    deadline=deadline,
                    user_id=user_id,
                )
                if package_state["state"] != "absent":
                    raise ProbeError("IntegrityConflict", "Transport")
                _deadline_remaining(self._clock, deadline)
                install_path = os.path.join(directory, "readiness.apk")
                os.symlink(f"/dev/fd/{install_fd}", install_path)
                self._readiness_installed_uid = None
                self._readiness_install_attempted = True
                output = self._run(
                    target,
                    (
                        "install",
                        "--no-streaming",
                        "--user",
                        str(user_id),
                        install_path,
                    ),
                    deadline,
                )
                try:
                    lines = output.decode("ascii").splitlines()
                except UnicodeDecodeError:
                    raise ProbeError("IncompleteEvidence", "Transport") from None
                if lines not in (
                    ["Success"],
                    ["Performing Push Install", "Success"],
                ):
                    raise ProbeError("IncompleteEvidence", "Transport")
                installed_state = self.package_install_state(
                    target,
                    _READINESS_PROBE_PACKAGE,
                    deadline=deadline,
                    user_id=user_id,
                )
                if (
                    installed_state["state"] != "present"
                    or installed_state["version_code"]
                    != _READINESS_PROBE_VERSION_CODE
                ):
                    raise ProbeError("IntegrityConflict", "Transport")
                self._readiness_installed_uid = installed_state["uid"]
                return {"state": "installed"}
            except ProbeError:
                raise
            except OSError:
                raise ProbeError("IncompleteEvidence", "Transport") from None
            finally:
                for descriptor in (source_fd, staged_fd, install_fd):
                    if descriptor is not None:
                        try:
                            os.close(descriptor)
                        except OSError:
                            pass

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
