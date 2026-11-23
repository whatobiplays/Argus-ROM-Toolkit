"""Fixed Activity Manager evidence reader for the Issue #74 Readiness probe."""

import re
from dataclasses import dataclass, field

from .readiness_probe import ProbeError
from .readiness_probe_artifact import PACKAGE


_HEADER = b"ACTIVITY MANAGER ACTIVITIES (dumpsys activity activities)"
_BOUNDARY = b"ActivityTaskSupervisor state:"
_FOOTER = re.compile(rb"  NumNonAppVisibleWindowByUid:\[(?: [0-9]{1,10}:[0-9]{1,10})*\]")
_DISPLAY = re.compile(rb"Display #([0-9]{1,10}) \(activities from top to bottom\):")
_ROOT = re.compile(rb"  RootTask #([0-9]{1,10}): type=[\w-]+ mode=([\w-]+)")
_TASK = re.compile(
    rb"    \* Task\{([a-f0-9]{1,8}) #([0-9]{1,10}) type=[\w-]+ "
    rb"(?:A=\S+|I=\S+|aI=\S+|\?\?) U=([0-9]{1,10})"
    rb"(?: rootTaskId=([0-9]{1,10}))? visible=(?:true|false)"
    rb" mode=([\w-]+) translucent=(?:true|false) sz=[0-9]{1,10}\}"
)
_RECORD = rb"ActivityRecord\{([a-f0-9]{1,8}) u([0-9]{1,10}) (\S+) t([0-9]{1,10})\}"
_MEMBER = re.compile(rb"      \* Hist\s*#[0-9]{1,10}: " + _RECORD)
_ROOT_RESUMED = re.compile(rb"    mResumedActivity: " + _RECORD)
_TOP = re.compile(rb"  ResumedActivity: " + _RECORD)
_STATE = re.compile(rb" +state=([A-Z_]+)(?: .*)?")
_ERROR = re.compile(
    rb"(?i)^(?:\*\*\* SERVICE .* DUMP TIMEOUT|error\b|exception\b|"
    rb"java\.[a-z.]+Exception\b|permission denial|can't find service|"
    rb"failed to (?:read|write|dump|create pipe)|dump timeout)"
)
_COMPONENTS = {
    f"{PACKAGE}/{suffix}".encode(): name
    for name in ("LauncherActivity", "ProbeControlActivity")
    for suffix in ("." + name, PACKAGE + "." + name)
}
_RESUMED = b"RESUMED"
_OTHER_STATES = {b"PAUSED", b"STOPPED", b"STARTED", b"INITIALIZING", b"DESTROYED",
                 b"STOPPING", b"PAUSING", b"DESTROYING", b"RESTARTING_PROCESS"}
_MODES = {b"fullscreen", b"pinned", b"freeform", b"split-screen-primary",
          b"split-screen-secondary", b"multi-window"}
_MAX_LINE = 16 * 1024
_MAX_OUTPUT = 1024 * 1024


def _check(condition):
    if not condition:
        raise ProbeError("IncompleteEvidence", "Transport")


@dataclass(frozen=True)
class ReadinessActivityFacts:
    """One snapshot. The private IDs are meaningful only within a bound session."""

    component: str
    user_id: int = field(repr=False)
    activity_id: bytes = field(repr=False)
    task_id: int = field(repr=False)
    task_instance: bytes = field(repr=False)
    root_task_id: int = field(repr=False)
    display_id: int = field(repr=False)
    windowing_mode: str
    resumed: bool
    top_resumed: bool


class ReadinessActivityReader:
    """Collect one selected activity and its leaf task, root task, and display."""

    def __init__(self, component, user_id):
        _check(component in _COMPONENTS.values() and type(user_id) is int and user_id >= 0)
        self._component = component
        self._user = user_id
        self._pending = bytearray()
        self._bytes = 0
        self._started = False
        self._ended = False
        self._footer = False
        self._display = self._root = self._task = None
        self._display_ids, self._root_ids, self._task_ids = set(), set(), set()
        self._target = self._resumed = self._top = self._state = None
        self._in_target = False
        self._root_has_resumed = False

    def feed(self, chunk):
        self._bytes += len(chunk)
        if self._bytes > _MAX_OUTPUT:
            raise ProbeError("ResourceLimitExceeded", "Transport")
        self._pending.extend(chunk)
        while True:
            index = self._pending.find(b"\n")
            length = index if index >= 0 else len(self._pending)
            if length > _MAX_LINE:
                raise ProbeError("ResourceLimitExceeded", "Transport")
            if index < 0:
                return
            line = bytes(self._pending[:index])
            del self._pending[: index + 1]
            self._line(line)

    def _record(self, match):
        token, user, component, task = match.groups()
        name = _COMPONENTS.get(component)
        if component.startswith(PACKAGE.encode() + b"/"):
            _check(name is not None and int(user) == self._user)
        return (token, int(task)) if name == self._component else False

    def _line(self, line):
        stripped = line.lstrip(b" ")
        _check(not _ERROR.match(stripped) and b"\r" not in line and b"\x00" not in line)
        try:
            line.decode("utf-8")
        except UnicodeDecodeError:
            raise ProbeError("IncompleteEvidence", "Transport") from None
        if not self._started:
            _check(line == _HEADER)
            self._started = True
            return
        if self._footer:
            _check(not stripped)
            return
        if stripped.startswith(b"NumNonAppVisibleWindowByUid:"):
            _check(self._ended and _FOOTER.fullmatch(line) is not None)
            self._footer = True
            return
        if line == _BOUNDARY:
            _check(not self._ended and self._display is not None and self._top is not None)
            self._ended = True
            self._task = None
            self._display_ids.clear()
            self._root_ids.clear()
            self._task_ids.clear()
            return
        if self._ended:
            _check(line != _HEADER and not stripped.startswith(b"ResumedActivity:"))
            return
        if stripped.startswith(b"Display #"):
            match = _DISPLAY.fullmatch(line)
            _check(match is not None and self._top is None)
            self._display = int(match[1])
            _check(self._display not in self._display_ids)
            self._display_ids.add(self._display)
            self._root = self._task = None
            self._in_target = False
            self._root_has_resumed = False
        elif stripped.startswith(b"RootTask #"):
            match = _ROOT.fullmatch(line)
            _check(match is not None and self._display is not None and self._top is None)
            self._root = int(match[1])
            _check(self._root not in self._root_ids)
            self._root_ids.add(self._root)
            self._task = None
            self._in_target = False
            self._root_has_resumed = False
        elif stripped.startswith(b"* Task{"):
            match = _TASK.fullmatch(line)
            _check(match is not None and self._root is not None and self._top is None)
            instance, task, user, root, mode = match.groups()
            _check(int(root or task) == self._root and int(task) not in self._task_ids)
            self._task_ids.add(int(task))
            self._task = int(task), instance, int(user), mode
            self._in_target = False
        elif stripped.startswith(b"* Hist"):
            match = _MEMBER.fullmatch(line)
            _check(match is not None and self._task is not None and self._top is None)
            selected = self._record(match)
            self._in_target = bool(selected)
            if selected:
                task, instance, user, mode = self._task
                _check(self._target is None and selected[1] == task and user == self._user
                       and mode in _MODES and self._root_has_resumed)
                self._target = selected, instance, self._root, self._display, mode
        elif stripped.startswith(b"mResumedActivity:"):
            match = _ROOT_RESUMED.fullmatch(line)
            _check(match is not None and self._root is not None and self._top is None
                   and not self._root_has_resumed and self._task is None)
            self._root_has_resumed = True
            self._in_target = False
            selected = self._record(match)
            if selected:
                _check(self._resumed is None)
                self._resumed = selected, self._root, self._display
        elif stripped.startswith(b"ResumedActivity:"):
            match = _TOP.fullmatch(line)
            _check(match is not None and self._top is None)
            self._top = self._record(match)
            self._in_target = False
        elif self._in_target and stripped.startswith(b"state="):
            match = _STATE.fullmatch(line)
            _check(len(line) - len(stripped) > 6 and match is not None
                   and self._state is None and match[1] in _OTHER_STATES | {_RESUMED})
            self._state = match[1]
        elif stripped and len(line) - len(stripped) <= 6:
            self._in_target = False

    def finish(self, acquisition):
        """Accept only a clean, bounded acquisition through the activity boundary."""
        _check(acquisition.command_count == 1 and acquisition.exit_code == 0
               and acquisition.classification == "exit_zero" and acquisition.stderr_empty
               and acquisition.cleanup_complete and acquisition.stdout_bytes == self._bytes
               and acquisition.total_output_bytes == self._bytes)
        _check(not self._pending and self._footer and self._target is not None and self._state is not None)
        selected, instance, root, display, mode = self._target
        resumed = self._state == _RESUMED
        top = bool(self._top)
        _check((self._resumed == (selected, root, display) if resumed else self._resumed is None)
               and (not top or (resumed and self._top == selected)))
        return ReadinessActivityFacts(
            self._component, self._user, selected[0], selected[1], instance, root, display,
            mode.decode("ascii"), resumed, top,
        )
