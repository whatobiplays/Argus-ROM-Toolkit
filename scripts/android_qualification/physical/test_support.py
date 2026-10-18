"""Synthetic device and dependency support for the physical test suite.

This module is imported only by tests. Its fake transport records argument
vectors in memory and never launches ADB or another external process.
"""

from dataclasses import dataclass
import shlex
import subprocess
import time
from pathlib import Path

from scripts.android_qualification.physical import core


class FakeTransport:
    """Return deterministic device responses and record requested commands."""

    def __init__(self):
        self.targets = 'List of devices attached\nselected device usb:1-1 transport_id:1\n'
        self.props = {'ro.product.model': 'GT78-VN', 'ro.build.version.sdk': '30',
                      'ro.product.cpu.abi': 'arm64-v8a', 'ro.kernel.qemu': '',
                      'ro.boot.qemu': '', 'sys.boot_completed': '1',
                      'ro.product.device': 'dedicated-product'}
        self.commands = []
        self.settings = {('system', 'font_scale'): '1.0',
                         ('secure', 'accessibility_enabled'): 'null'}
        self.display_size = (1280, 960)
        self.display_size_override = None
        self.physical_density = 320
        self.density_override = None

    def __call__(self, args, timeout=30, env=None):
        self.commands.append(args)
        if args[1:] == ['devices', '-l']:
            return self.targets
        command = args[3:]
        if command and command[0] == 'shell':
            command = ['shell', *shlex.split(' '.join(command[1:]))]
        if command[:2] == ['shell', 'getprop']:
            return self.props.get(command[2], '') + '\n'
        if command[:3] == ['shell', 'settings', 'get']:
            return self.settings.get(tuple(command[3:5]), 'null') + '\n'
        if command[:3] == ['shell', 'settings', 'put']:
            self.settings[tuple(command[3:5])] = command[5]
        if command[:3] == ['shell', 'settings', 'delete']:
            self.settings[tuple(command[3:5])] = 'null'
        if command[:3] == ['shell', 'wm', 'size']:
            output = f'Physical size: {self.display_size[0]}x{self.display_size[1]}\n'
            if self.display_size_override is not None:
                output += (f'Override size: {self.display_size_override[0]}x'
                           f'{self.display_size_override[1]}\n')
            return output
        if command[:3] == ['shell', 'wm', 'density']:
            if len(command) == 3:
                output = f'Physical density: {self.physical_density}\n'
                if self.density_override is not None:
                    output += f'Override density: {self.density_override}\n'
                return output
            if command[3] == 'reset':
                self.density_override = None
            else:
                self.density_override = int(command[3])
        return 'Success\n'


class FakeDevice:
    """Apply production safety checks while using only a supplied fake transport."""

    def __init__(self, adb, serial, transport, clock=time.monotonic):
        self.adb, self.serial, self.transport = adb, serial, transport
        self._identity = None
        self.clock = clock
        self._density_scope_owner = None
        self._density_mutation_values = frozenset()

    def _call(self, args, timeout=30):
        try:
            return self.transport(args, timeout=timeout)
        except (KeyboardInterrupt, InterruptedError):
            raise
        except (OSError, subprocess.SubprocessError):
            raise core.Blocked('ADB command failed or timed out; raw output withheld') from None

    def _within(self, args, deadline):
        remaining = deadline - self.clock()
        if remaining <= 0:
            raise core.Blocked('Device command deadline expired before execution')
        result = self._call(args, remaining)
        if self.clock() >= deadline:
            raise core.Blocked('Device command deadline expired during identity validation')
        return result

    def preflight(self, timeout=30, deadline=None):
        """Require exactly one online, booted, physical API-30 ARM64 USB target."""
        deadline = self.clock() + timeout if deadline is None else deadline
        lines = self._within([self.adb, 'devices', '-l'], deadline).splitlines()
        targets = [line.split() for line in lines
                   if line.strip() and not line.startswith(('List of devices', '*'))]
        if (len(targets) != 1 or len(targets[0]) < 3
                or targets[0][:2] != [self.serial, 'device']
                or not any(part.startswith('usb:') for part in targets[0][2:])):
            raise core.Blocked('Exactly one explicitly selected online USB target is required')
        props = {}
        for name in ('ro.product.model', 'ro.build.version.sdk',
                     'ro.product.cpu.abi', 'ro.kernel.qemu', 'ro.boot.qemu',
                     'sys.boot_completed', 'ro.product.device'):
            props[name] = self._within([self.adb, '-s', self.serial, 'shell',
                                        'getprop', name], deadline).strip()
        if (props['ro.product.model'] != 'GT78-VN'
                or props['ro.build.version.sdk'] != '30'
                or props['ro.product.cpu.abi'] != 'arm64-v8a'
                or props['ro.kernel.qemu'] not in ('', '0')
                or props['ro.boot.qemu'] not in ('', '0')
                or props['sys.boot_completed'] != '1'
                or not props['ro.product.device']):
            raise core.Blocked('Target is not the required booted physical GT78-VN/API-30/ARM64 device')
        identity = tuple(props.items()) + tuple(targets[0][2:])
        if self._identity is not None and self._identity != identity:
            raise core.Blocked('Originally selected device identity or USB transport changed')
        self._identity = identity
        return {'model': 'GT78-VN', 'api': 30, 'abi': 'arm64-v8a',
                'physical_usb': True, 'boot_completed': True,
                'target_count': 1}

    def run(self, *args, mutating=False, timeout=30):
        deadline = self.clock() + timeout
        if mutating:
            self.preflight(deadline=deadline)
        return self._within([self.adb, '-s', self.serial, *args], deadline)

    def shell(self, *args, mutating=False, timeout=30):
        if mutating:
            if args[:2] in (('pm', 'clear'), ('pm', 'uninstall')) and args != (*args[:2], core.PACKAGE):
                raise core.Blocked('Package reset is restricted to Argus')
            if args and args[0] in ('rm', 'mkdir'):
                paths = [arg for arg in args[1:] if not arg.startswith('-')]
                if args[0] == 'rm' and paths != [core.DEVICE_ROOT]:
                    raise core.Blocked('Cleanup is restricted to the qualification-owned device directory')
                if args[0] == 'mkdir' and (
                        not paths or any(
                            not (path == core.DEVICE_ROOT
                                 or path.startswith(core.DEVICE_ROOT + '/'))
                            or '..' in Path(path).parts
                            for path in paths)):
                    raise core.Blocked('Filesystem mutation is restricted to the test-owned device directory')
            if args and args[0] == 'sm':
                raise core.Blocked('Removable-media changes require an owner-operated supported condition')
            if args[:2] == ('appops', 'set') and (
                    len(args) != 5 or args[2:4] != (core.PACKAGE, 'MANAGE_EXTERNAL_STORAGE')
                    or args[4] not in ('allow', 'deny', 'ignore', 'default')):
                raise core.Blocked('App access configuration is restricted to Argus storage access')
            if args[:2] in (('settings', 'put'), ('settings', 'delete')) and (
                    tuple(args[2:4]) not in core.SettingsSnapshot.ALLOWED):
                raise core.Blocked('Unowned Android setting')
            if args[:2] == ('wm', 'density'):
                owner = self._density_scope_owner
                if (len(args) != 3 or owner is None
                        or args[2] not in self._density_mutation_values
                        or getattr(owner, '_authorized_write', None) != args[2]):
                    raise core.Blocked('Display-density mutation is outside the snapshotted qualification values')
            if args[:2] == ('wm', 'size'):
                raise core.Blocked('Display-size mutation is not part of physical qualification')
        # The fake boundary uses the same shell quoting as the future device adapter.
        return self.run('shell', *(shlex.quote(str(arg)) for arg in args),
                        mutating=mutating, timeout=timeout)


@dataclass(frozen=True)
class RunnerDependencies:
    """Explicit fake boundaries required to exercise runner orchestration."""

    device: object
    command_executor: object
    fixture_inspector: object
    settings_snapshot_factory: object
    run_ui_scenarios: object
    library_controls_probe: object
    surface_lifecycle_probe: object
    scaling_probe: object
