"""Pure artifact, configuration, and evidence checks for qualification.

ADB output is transient. Public evidence contains only fixed labels and bounded
technical facts; exceptions deliberately omit command arguments and raw output.
"""
from __future__ import annotations

import re
import signal
import subprocess
import time
import threading
from contextlib import contextmanager

PACKAGE = 'com.argusromtoolkit.argus'
DEVICE_ROOT = '/sdcard/ArgusQualification'


class Blocked(Exception):
    """A prerequisite or safety check prevented a reliable observation."""


@contextmanager
def cleanup_signals():
    """Defer further cancellation signals during bounded restoration.

    Cancellation is delivered after owned state has been restored and the
    process's previous signal handlers have been reinstated.
    """
    previous = {}
    pending = []

    def defer(number, _frame):
        if not pending:
            pending.append(number)

    if threading.current_thread() is threading.main_thread():
        for number in (signal.SIGINT, signal.SIGTERM):
            previous[number] = signal.signal(number, defer)
    body_error = None
    try:
        try:
            yield
        except BaseException as error:
            body_error = error
    finally:
        for number, handler in previous.items():
            signal.signal(number, handler)
    if pending:
        if pending[0] == signal.SIGINT:
            raise KeyboardInterrupt()
        raise InterruptedError('Qualification interrupted')
    if body_error is not None:
        raise body_error.with_traceback(body_error.__traceback__)


@contextmanager
def interrupt_on_sigterm():
    """Convert SIGTERM to a catchable interruption while state is temporary.

    Python signal handlers run only on the main thread. Refusing other threads
    keeps a direct helper call from silently retaining the process's default
    terminate behavior while a display override is active.
    """
    if threading.current_thread() is not threading.main_thread():
        raise Blocked('Temporary display changes require the main thread for SIGTERM cleanup')
    previous = signal.getsignal(signal.SIGTERM)

    def interrupt(_number, _frame):
        raise InterruptedError('Qualification interrupted')

    signal.signal(signal.SIGTERM, interrupt)
    try:
        yield
    finally:
        signal.signal(signal.SIGTERM, previous)


def _preserve_ui_cleanup_evidence(interruption, original_error):
    """Carry sanitized UI cleanup facts onto an interruption raised by restore."""
    if original_error is None:
        return
    cleanup_blocker = getattr(original_error, 'ui_cleanup_blocker', None)
    has_cleanup_marker = hasattr(original_error, 'product_failure_observed')
    if not cleanup_blocker and has_cleanup_marker:
        cleanup_blocker = 'Accessibility capture cleanup failed; owner follow-up is required.'
    if cleanup_blocker:
        interruption.ui_cleanup_blocker = cleanup_blocker
    if hasattr(original_error, 'ui_product_failure_observed'):
        interruption.ui_product_failure_observed = bool(
            original_error.ui_product_failure_observed)
    elif has_cleanup_marker:
        interruption.ui_product_failure_observed = bool(
            original_error.product_failure_observed)
    scenario = (getattr(original_error, 'ui_cleanup_scenario', None)
                or getattr(original_error, 'scenario', None))
    if scenario:
        interruption.ui_cleanup_scenario = scenario


class StorageAccessSnapshot:
    """Restore Argus's all-files-access app operation after qualification.

    API 30 requires this admission before backend startup. Only the package's
    single storage operation is changed; its original mode is verified again
    during bounded cleanup, including failures and interruptions.
    """

    def __init__(self, device):
        self.device = device
        self.original = None
        self.changed = False
        self.cleanup_status = 'NOT REQUIRED'
        self.active_window = False
        self.configured = False
        self.density_probe_used = False

    def mode(self):
        output = self.device.shell('appops', 'get', PACKAGE, 'MANAGE_EXTERNAL_STORAGE', timeout=10).strip()
        if re.search(r'^\s*Uid mode:', output, re.M | re.I):
            raise Blocked('UID-scoped storage access overrides require owner configuration')
        if output in ('No operations.', 'No operations.\nDefault mode: default'):
            return 'default'
        match = re.search(r'^\s*MANAGE_EXTERNAL_STORAGE:\s*(allow|deny|ignore|default)\b', output, re.M)
        if not match:
            raise Blocked('Argus storage access mode could not be established')
        return match[1]

    def __enter__(self):
        if self.active_window or self.original is not None:
            raise Blocked('Argus storage access snapshot cannot be reused')
        self.original = self.mode()
        self.active_window = True
        return self

    def configure(self):
        if not self.active_window or self.original is None:
            raise Blocked('Argus storage access was not snapshotted')
        if self.configured:
            raise Blocked('Argus storage access was already configured for this window')
        if self.original != 'allow':
            self.changed = True
            self.device.shell('appops', 'set', PACKAGE, 'MANAGE_EXTERNAL_STORAGE', 'allow', mutating=True, timeout=10)
        if self.mode() != 'allow':
            raise Blocked('Argus storage access configuration did not confirm success')
        self.configured = True

    def __exit__(self, exception_type=None, original_error=None, traceback=None):
        try:
            if not self.changed:
                return False
            self.cleanup_status = 'BLOCKED'
            try:
                with cleanup_signals():
                    for attempt in range(2):
                        try:
                            if self.mode() == self.original:
                                self.cleanup_status = 'RESTORED'
                                break
                            self.device.shell('appops', 'set', PACKAGE, 'MANAGE_EXTERNAL_STORAGE', self.original, mutating=True, timeout=10)
                            if self.mode() == self.original:
                                self.cleanup_status = 'RESTORED'
                            break
                        except (KeyboardInterrupt, InterruptedError):
                            if attempt == 0:
                                continue
                        except (Blocked, subprocess.SubprocessError, OSError):
                            break
            except (KeyboardInterrupt, InterruptedError) as interruption:
                # A deferred cancellation raised here replaces the exception
                # being unwound from the guarded UI scope. Carry only its
                # sanitized cleanup evidence onto the interruption report.
                _preserve_ui_cleanup_evidence(interruption, original_error)
                raise
        finally:
            self.active_window = False
            self.configured = False
        return False


class SettingsSnapshot:
    """Restore each changed setting even when scenario execution raises.

    Restoration is attempted independently for every setting. A disconnected
    or replaced device never receives cleanup commands; the cleanup status then
    requires owner follow-up. Unset values are restored with `settings delete`.
    """

    ALLOWED = {('system', 'font_scale'), ('secure', 'accessibility_enabled'),
               ('secure', 'enabled_accessibility_services')}

    def __init__(self, device):
        self.device = device
        self.original = {}
        self.changed = []
        self.cleanup_status = 'NOT REQUIRED'

    def __enter__(self):
        for namespace, key in sorted(self.ALLOWED):
            self.original[(namespace, key)] = self.device.shell(
                'settings', 'get', namespace, key).strip()
        return self

    def put(self, namespace, key, value):
        if (namespace, key) not in self.ALLOWED or (namespace, key) not in self.original:
            raise Blocked('Unowned or unsnapshotted Android setting')
        if (namespace, key) not in self.changed:
            self.changed.append((namespace, key))
        self.device.shell('settings', 'put', namespace, key, value, mutating=True)

    def read(self, namespace, key):
        """Read back a setting only after its original value was snapshotted."""
        if (namespace, key) not in self.ALLOWED or (namespace, key) not in self.original:
            raise Blocked('Unowned or unsnapshotted Android setting')
        return self.device.shell('settings', 'get', namespace, key, timeout=5).strip()

    def __exit__(self, exception_type=None, original_error=None, traceback=None):
        if not self.changed:
            return
        self.cleanup_status = 'PENDING'
        restored = 0
        try:
            try:
                with cleanup_signals():
                    for namespace, key in reversed(self.changed):
                        for attempt in range(2):
                            try:
                                value = self.original[(namespace, key)]
                                actual = self.device.shell('settings', 'get', namespace, key,
                                                           timeout=5).strip()
                                if actual == value:
                                    restored += 1
                                    break
                                if value == 'null':
                                    self.device.shell('settings', 'delete', namespace, key,
                                                      mutating=True, timeout=10)
                                else:
                                    self.device.shell('settings', 'put', namespace, key, value,
                                                      mutating=True, timeout=10)
                                actual = self.device.shell('settings', 'get', namespace, key,
                                                           timeout=5).strip()
                                if actual == value:
                                    restored += 1
                                break
                            except (KeyboardInterrupt, InterruptedError):
                                if attempt == 0:
                                    continue
                            except (Blocked, subprocess.SubprocessError, OSError):
                                break
            except (KeyboardInterrupt, InterruptedError) as interruption:
                _preserve_ui_cleanup_evidence(interruption, original_error)
                raise
        finally:
            self.cleanup_status = 'RESTORED' if restored == len(self.changed) else 'BLOCKED'


class DisplayDensitySnapshot:
    """Apply one snapshot-owned expanded-width density and restore its prior override.

    Device-level density writes are accepted only while this snapshot is issuing
    its target or restoration command. The original override is read back before
    the scope is released, including when command dispatch is interrupted.
    """

    TARGET_DPI = 240
    EXPANDED_WIDTH_DP = 840
    COMMAND_TIMEOUT = 10
    CLEANUP_BUDGET = 30

    def __init__(self, device, *, budget=30):
        self.device = device
        self.clock = getattr(device, 'clock', time.monotonic)
        self.budget = budget
        self.deadline = None
        self.original = None
        self.changed = False
        self.cleanup_status = 'NOT REQUIRED'
        self._entered = False
        self._signal_guard = None
        self._scope_acquired = False
        self._authorized_write = None

    def _remaining(self, deadline=None):
        limit = self.deadline if deadline is None else deadline
        remaining = limit - self.clock()
        if remaining <= 0:
            raise Blocked('Display-density observation deadline expired')
        return min(self.COMMAND_TIMEOUT, remaining)

    def _read(self, command, kind, deadline=None):
        output = self.device.shell('wm', command, timeout=self._remaining(deadline))
        if not isinstance(output, str) or len(output) > 4096:
            raise Blocked('Display configuration could not be safely established')
        physical = None
        override = None
        expression = (r'^\s*(Physical|Override) ' + re.escape(kind)
                      + r':\s*([0-9]+)(?:x([0-9]+))?\s*$')
        for line in output.splitlines():
            if not line.strip():
                continue
            match = re.fullmatch(expression, line)
            if not match:
                raise Blocked('Display configuration could not be safely established')
            value = tuple(int(part) for part in match.groups()[1:] if part is not None)
            if not value or any(part <= 0 or part > 32768 for part in value):
                raise Blocked('Display configuration could not be safely established')
            if kind == 'size' and len(value) != 2 or kind == 'density' and len(value) != 1:
                raise Blocked('Display configuration could not be safely established')
            if match[1] == 'Physical':
                if physical is not None:
                    raise Blocked('Display configuration could not be safely established')
                physical = value
            else:
                if override is not None:
                    raise Blocked('Display configuration could not be safely established')
                override = value
        if physical is None:
            raise Blocked('Display configuration could not be safely established')
        return physical, override

    def _read_state(self, deadline=None):
        size = self._read('size', 'size', deadline)
        density = self._read('density', 'density', deadline)
        return size, density

    def __enter__(self):
        if self._entered or not isinstance(self.budget, (int, float)) or self.budget <= 0:
            raise Blocked('Display-density snapshot requires one positive bounded observation window')
        self._entered = True
        self._signal_guard = interrupt_on_sigterm()
        self._signal_guard.__enter__()
        try:
            self.deadline = self.clock() + min(float(self.budget), 120.0)
            self.original = self._read_state()
            if getattr(self.device, '_density_scope_owner', None) is not None:
                raise Blocked('A display-density snapshot is already active for this device')
            original_override = self.original[1][1]
            restore_value = 'reset' if original_override is None else str(original_override[0])
            self.device._density_scope_owner = self
            self.device._density_mutation_values = frozenset(
                (str(self.TARGET_DPI), restore_value))
            self._scope_acquired = True
            return self
        except BaseException as error:
            self._release_scope()
            guard, self._signal_guard = self._signal_guard, None
            guard.__exit__(type(error), error, error.__traceback__)
            raise

    def _release_scope(self):
        if self._scope_acquired and getattr(self.device, '_density_scope_owner', None) is self:
            self.device._density_scope_owner = None
            self.device._density_mutation_values = frozenset()
        self._scope_acquired = False

    def _write_density(self, value, deadline=None):
        """Issue one value-scoped density write owned by this snapshot."""
        value = str(value)
        if (not self._scope_acquired
                or value not in self.device._density_mutation_values):
            raise Blocked('Display-density mutation is outside the snapshotted qualification values')
        self._authorized_write = value
        try:
            return self.device.shell('wm', 'density', value, mutating=True,
                                     timeout=self._remaining(deadline))
        finally:
            self._authorized_write = None

    def configure_expanded(self):
        """Apply density 240 only when it yields an 840dp expanded-width layout."""
        if not self._entered or self.original is None:
            raise Blocked('Display-density state was not snapshotted')
        size, density = self.original
        active_size = size[1] or size[0]
        logical_width = active_size[0] * 160 // self.TARGET_DPI
        if logical_width < self.EXPANDED_WIDTH_DP:
            raise Blocked('The bounded density target would not expose expanded-width controls')
        if self._read_state() != self.original:
            raise Blocked('Display configuration changed after its snapshot')
        current_dpi = density[1][0] if density[1] else density[0][0]
        if current_dpi != self.TARGET_DPI:
            # Record ownership before dispatch because an interrupted transport
            # may have applied the override before reporting that it stopped.
            self.changed = True
            self._write_density(self.TARGET_DPI)
        state = self._read_state()
        actual_size, actual_density = state
        actual_dpi = actual_density[1][0] if actual_density[1] else actual_density[0][0]
        if actual_size != size or actual_density[0] != density[0] or actual_dpi != self.TARGET_DPI:
            raise Blocked('The requested expanded-width density did not verify')
        return {'density_dpi': actual_dpi, 'logical_width_dp': logical_width,
                'layout_class': 'expanded'}

    def __exit__(self, exc_type, exc, traceback):
        try:
            if not self.changed:
                return False
            self.cleanup_status = 'PENDING'
            interrupted = None
            cleanup_deadline = self.clock() + self.CLEANUP_BUDGET
            expected_size, expected_density = self.original
            original_override = expected_density[1]
            with cleanup_signals():
                for attempt in range(2):
                    try:
                        current_size, current_density = self._read_state(cleanup_deadline)
                        if (current_size == expected_size and current_density == expected_density):
                            self.cleanup_status = 'RESTORED'
                            break
                        if (current_size != expected_size or current_density[0] != expected_density[0]
                                or current_density[1] != (self.TARGET_DPI,)):
                            raise Blocked('Display state changed outside the bounded density probe')
                        restore = 'reset' if original_override is None else str(original_override[0])
                        self._write_density(restore, cleanup_deadline)
                        if self._read_state(cleanup_deadline) == self.original:
                            self.cleanup_status = 'RESTORED'
                            break
                        raise Blocked('Original display-density override did not restore')
                    except (KeyboardInterrupt, InterruptedError) as error:
                        interrupted = error
                        if attempt == 1:
                            self.cleanup_status = 'BLOCKED'
                    except (Blocked, OSError, subprocess.SubprocessError):
                        self.cleanup_status = 'BLOCKED'
                        break
            if interrupted is not None and exc_type not in (KeyboardInterrupt, InterruptedError):
                raise interrupted
            return False
        finally:
            self._release_scope()
            guard, self._signal_guard = self._signal_guard, None
            if guard is not None:
                guard.__exit__(exc_type, exc, traceback)


def check_metadata(badging, entries):
    """Check Release identity and native packaging without trusting a filename."""
    match = re.search(r"^package: name='([^']+)' versionCode='([0-9]+)' versionName='([^']+)'", badging, re.M)
    native = re.search(r'^native-code: (.+)$', badging, re.M)
    if (not match or match[1] != PACKAGE
            or 'application-debuggable' in badging
            or not re.search(r"^(?:minSdkVersion|sdkVersion):'30'\s*$", badging, re.M)
            or not native or re.findall(r"'([^']+)'", native[1]) != ['arm64-v8a']):
        raise Blocked('APK package, SDK, Release flag, or ABI contract failed')
    required = {'lib/arm64-v8a/libargus_bridge.so',
                'lib/arm64-v8a/libandroid_native_keyring_store.so'}
    if not required.issubset(entries) or any(
            item.startswith('lib/') and item.split('/')[1] != 'arm64-v8a'
            for item in entries):
        raise Blocked('APK native library packaging contract failed')
    return {'package': PACKAGE, 'version': match[3], 'version_code': int(match[2]),
            'min_sdk': 30, 'abi': 'arm64-v8a', 'debuggable': False}


def check_certificate(signer_output, reference):
    """Compare to an independently supplied certificate reference, when present.

    A valid APK signature does not establish the production signing identity.
    Reference absence is reported separately rather than treated as a match.
    """
    digests = re.findall(r'Signer #[0-9]+ certificate SHA-256 digest: ([0-9a-fA-F]{64})', signer_output)
    if len(digests) != 1:
        raise Blocked('Exactly one verifiable APK signing certificate is required')
    if not reference:
        return 'UNAVAILABLE'
    normalized = reference.replace(':', '').strip().lower()
    if not re.fullmatch(r'[0-9a-f]{64}', normalized) or normalized != digests[0].lower():
        raise Blocked('APK signing certificate does not match the Release identity reference')
    return 'MATCHED'


CHECKPOINTS = {
    'AND-01': 'Observe fresh Release onboarding, native folder selection, Add & Scan and a usable populated Library.',
    'AND-02': 'Observe correct browse, search, filter, sort and corresponding game detail.',
    'AND-03': 'Observe provider configuration, secret-safe production credential storage, real hydration and actionable recovery.',
    'AND-04': 'Observe truthful progress and coherent Library/Jobs state across background and foreground transitions.',
    'AND-05': 'Observe persisted state, truthful interrupted refresh, no silent resume and successful explicit retry.',
    'AND-06': 'Disconnect and restore genuine configured removable media; observe non-destructive recovery.',
    'CNT-01': 'Observe native cartridge identification and coherent Library/detail presentation.',
    'CNT-02': 'Observe native optical-image identification and coherent presentation.',
    'CNT-03': 'Observe descriptor plus dependent tracks admitted as coherent logical content.',
    'CNT-04': 'Observe playlist/multi-disc grouping without unwanted duplicate games.',
    'CNT-05': 'Observe a valid ZIP/7z admitted, extracted, identified and presented as one coherent logical game.',
    'CNT-06': 'Observe valid CHD identification and coherent presentation.',
    'CNT-07': 'Observe a valid RVZ, CSO or WBFS representation identified and presented.',
    'CNT-08': 'Observe two supported equivalent representations converge without duplicate logical games.',
    'CNT-09': 'Observe identified unmatched content remains visible with bounded fallback presentation.',
    'CNT-10': 'Observe successful real provider metadata and artwork hydration in Library/detail.',
    'CNT-11': 'Observe temporary content/source unavailability and restoration without false orphan/destructive behavior.',
    'CNT-12': 'Observe a malformed/unsupported safe fixture fails understandably without corrupting unrelated Library state.',
    'UX-A01': 'With TalkBack enabled, listen to labels, roles, focus, progress, errors and recovery in Library/detail.',
    'UX-A02': 'Directly exercise critical touch actions and judge sizing, spacing and practical usability.',
    'UX-A03': 'Inspect Library/detail at supported font and display scales for readable, reachable, unclipped controls.',
}


def scenario_rows():
    """Create independent evidence rows without granting manual qualification."""
    return {identifier: {'automation_status': 'NOT RUN',
                         'owner_qualification_status': 'NOT RUN',
                         'assertions': [], 'reason': 'Release execution not attempted',
                         'owner_checkpoint': checkpoint}
            for identifier, checkpoint in CHECKPOINTS.items()}


def assertion(row, check, passed, detail):
    """Record one assertion; a partial success never promotes a whole scenario."""
    row['assertions'].append({'check': check, 'status': 'PASS' if passed else 'FAIL',
                              'detail': detail})
    if not passed:
        row['automation_status'] = 'FAIL'
