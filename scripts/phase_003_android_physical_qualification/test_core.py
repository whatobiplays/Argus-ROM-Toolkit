"""Safety and evidence contracts for the physical Release qualification runner."""
import subprocess
import unittest
import shlex
import sys
import os
import signal

import core


class Transport:
    """Model ADB responses without connecting to a developer's device."""

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
                output += f'Override size: {self.display_size_override[0]}x{self.display_size_override[1]}\n'
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


class CoreTests(unittest.TestCase):
    def setUp(self):
        self.transport = Transport()
        self.device = core.Device('adb', 'selected', self.transport)

    def test_valid_preflight_omits_serial_and_machine_identity(self):
        proof = self.device.preflight()
        self.assertEqual(proof['api'], 30)
        self.assertTrue(proof['physical_usb'])
        self.assertNotIn('selected', str(proof))
        self.assertNotIn('dedicated-product', str(proof))

    def test_destructive_command_rejects_each_invalid_target(self):
        cases = ['List of devices attached\n',
                 'selected offline usb:1-1\n',
                 'selected device\n',
                 'selected device usb:1-1\nother device usb:1-2\n',
                 'replacement device usb:1-1\n']
        for targets in cases:
            with self.subTest(targets=targets):
                self.transport.targets = targets
                with self.assertRaises(core.Blocked):
                    self.device.shell('pm', 'clear', core.PACKAGE, mutating=True)
                self.assertFalse(any('clear' in command for command in self.transport.commands))

    def test_destructive_command_rejects_wrong_properties(self):
        for prop, value in [('ro.product.model', 'different'),
                            ('ro.build.version.sdk', '36'),
                            ('ro.product.cpu.abi', 'x86_64'),
                            ('ro.kernel.qemu', '1'), ('sys.boot_completed', '0')]:
            transport = Transport()
            transport.props[prop] = value
            with self.assertRaises(core.Blocked):
                core.Device('adb', 'selected', transport).shell('pm', 'clear', core.PACKAGE, mutating=True)
            self.assertFalse(any('clear' in command for command in transport.commands))

    def test_identity_replacement_after_preflight_is_rejected(self):
        self.device.preflight()
        self.transport.props['ro.product.device'] = 'replacement-product'
        with self.assertRaises(core.Blocked):
            self.device.shell('pm', 'clear', core.PACKAGE, mutating=True)

    def test_settings_restore_on_exception_and_restore_absent_value(self):
        with self.assertRaises(ValueError):
            with core.SettingsSnapshot(self.device) as settings:
                settings.put('system', 'font_scale', '2.0')
                settings.put('secure', 'accessibility_enabled', '1')
                raise ValueError('interrupted')
        self.assertEqual(self.transport.settings[('system', 'font_scale')], '1.0')
        self.assertEqual(self.transport.settings[('secure', 'accessibility_enabled')], 'null')

    def test_cleanup_will_not_touch_replacement(self):
        with core.SettingsSnapshot(self.device) as settings:
            settings.put('system', 'font_scale', '2.0')
            self.transport.targets = 'replacement device usb:1-1\n'
        self.assertEqual(settings.cleanup_status, 'BLOCKED')
        self.assertEqual(self.transport.settings[('system', 'font_scale')], '2.0')

    def test_owner_and_automation_status_are_independent(self):
        rows = core.scenario_rows()
        self.assertEqual(len(rows), 21)
        core.assertion(rows['AND-01'], 'startup', True, 'Release startup visible')
        self.assertEqual(rows['AND-01']['owner_qualification_status'], 'NOT RUN')
        self.assertNotEqual(rows['AND-01']['automation_status'], 'PASS')
        core.assertion(rows['AND-01'], 'scan', False, 'Expected state absent')
        self.assertEqual(rows['AND-01']['automation_status'], 'FAIL')
        self.assertEqual(rows['AND-01']['owner_qualification_status'], 'NOT RUN')

    def test_artifact_metadata_rejects_wrong_package_debug_and_abi(self):
        good = "package: name='com.argusromtoolkit.argus' versionCode='1' versionName='0.1.0'\nsdkVersion:'30'\nnative-code: 'arm64-v8a'\n"
        entries = ['lib/arm64-v8a/libargus_bridge.so',
                   'lib/arm64-v8a/libandroid_native_keyring_store.so']
        self.assertEqual(core.check_metadata(good, entries)['version'], '0.1.0')
        self.assertEqual(core.check_metadata(good.replace('sdkVersion:', 'minSdkVersion:'), entries)['min_sdk'], 30)
        for badging in [good.replace(core.PACKAGE, 'other'), good + 'application-debuggable\n',
                        good.replace("sdkVersion:'30'", "sdkVersion:'36'"),
                        good.replace("'arm64-v8a'", "'x86_64'")]:
            with self.assertRaises(core.Blocked):
                core.check_metadata(badging, entries)
        with self.assertRaises(core.Blocked):
            core.check_metadata(good, entries + ['lib/x86/libargus_bridge.so'])

    def test_valid_signature_is_distinct_from_reference_identity(self):
        output = 'Signer #1 certificate SHA-256 digest: ' + 'a' * 64
        self.assertEqual(core.check_certificate(output, None), 'UNAVAILABLE')
        self.assertEqual(core.check_certificate(output, 'AA:' * 31 + 'AA'), 'MATCHED')
        with self.assertRaises(core.Blocked):
            core.check_certificate(output, 'b' * 64)
        with self.assertRaises(core.Blocked):
            core.check_certificate(output, 'invalid')

    def test_process_error_does_not_expose_command_secrets(self):
        def failure(args, timeout=30, env=None):
            raise subprocess.CalledProcessError(1, args, output='private game and secret')
        device = core.Device('adb', 'private-serial', failure)
        with self.assertRaises(core.Blocked) as error:
            device.preflight()
        self.assertNotIn('private', str(error.exception))

    def test_unowned_destructive_commands_are_rejected(self):
        for args in [('pm', 'clear', 'other.app'), ('rm', '-rf', '/sdcard'),
                     ('rm', '-f', core.DEVICE_ROOT + '/../private'),
                     ('sm', 'unmount', 'public:1,2'),
                     ('settings', 'put', 'system', 'unowned', '1')]:
            with self.subTest(args=args), self.assertRaises(core.Blocked):
                self.device.shell(*args, mutating=True)

    def test_preflight_consumes_the_same_deadline_as_the_destructive_command(self):
        current = [0.0]
        def slow(args, timeout=30, env=None):
            result = self.transport(args, timeout, env)
            current[0] += .5
            return result
        device = core.Device('adb', 'selected', slow, clock=lambda: current[0])
        with self.assertRaises(core.Blocked):
            device.shell('pm', 'clear', core.PACKAGE, mutating=True, timeout=1)
        self.assertFalse(any('clear' in command for command in self.transport.commands))

    def test_restoration_continues_after_interrupt_and_never_reports_false_success(self):
        calls = [0]
        def interrupted(args, timeout=30, env=None):
            if 'put' in args and '1.0' in args:
                calls[0] += 1
                if calls[0] == 1:
                    raise KeyboardInterrupt()
            return self.transport(args, timeout, env)
        device = core.Device('adb', 'selected', interrupted)
        with core.SettingsSnapshot(device) as settings:
            settings.put('system', 'font_scale', '2.0')
        self.assertEqual(self.transport.settings[('system', 'font_scale')], '1.0')
        self.assertEqual(settings.cleanup_status, 'RESTORED')

    def test_settings_restore_reads_back_before_retrying_an_applied_interrupted_write(self):
        class AppliedThenInterrupted(Transport):
            restore_writes = 0

            def __call__(inner, args, timeout=30, env=None):
                command = args[3:]
                if command and command[0] == 'shell':
                    command = ['shell', *shlex.split(' '.join(command[1:]))]
                result = super(AppliedThenInterrupted, inner).__call__(args, timeout, env)
                if command == ['shell', 'settings', 'put', 'system', 'font_scale', '1.0']:
                    inner.restore_writes += 1
                    if inner.restore_writes == 1:
                        raise InterruptedError()
                return result

        transport = AppliedThenInterrupted()
        device = core.Device('adb', 'selected', transport)
        with core.SettingsSnapshot(device) as settings:
            settings.put('system', 'font_scale', '2.0')

        self.assertEqual(transport.settings[('system', 'font_scale')], '1.0')
        self.assertEqual(transport.restore_writes, 1)
        self.assertEqual(settings.cleanup_status, 'RESTORED')

    def test_settings_sigterm_is_deferred_until_exact_state_is_restored(self):
        class TerminateAfterRestore(Transport):
            sent = False

            def __call__(inner, args, timeout=30, env=None):
                command = args[3:]
                if command and command[0] == 'shell':
                    command = ['shell', *shlex.split(' '.join(command[1:]))]
                result = super(TerminateAfterRestore, inner).__call__(args, timeout, env)
                if (not inner.sent and command ==
                        ['shell', 'settings', 'put', 'system', 'font_scale', '1.0']):
                    inner.sent = True
                    os.kill(os.getpid(), signal.SIGTERM)
                return result

        transport = TerminateAfterRestore()
        settings = core.SettingsSnapshot(core.Device('adb', 'selected', transport))
        with self.assertRaises(InterruptedError):
            with settings:
                settings.put('system', 'font_scale', '2.0')

        self.assertTrue(transport.sent)
        self.assertEqual(transport.settings[('system', 'font_scale')], '1.0')
        self.assertEqual(settings.cleanup_status, 'RESTORED')

    def test_storage_restore_reads_back_before_retrying_an_applied_interrupted_write(self):
        class AppliedThenInterrupted(Transport):
            storage_mode = 'default'
            restore_writes = 0

            def __call__(inner, args, timeout=30, env=None):
                command = args[3:]
                if command and command[0] == 'shell':
                    command = ['shell', *shlex.split(' '.join(command[1:]))]
                if command[:3] == ['shell', 'appops', 'get']:
                    return 'MANAGE_EXTERNAL_STORAGE: ' + inner.storage_mode + '\n'
                result = super(AppliedThenInterrupted, inner).__call__(args, timeout, env)
                if command[:3] == ['shell', 'appops', 'set']:
                    inner.storage_mode = command[-1]
                    if command[-1] == 'default':
                        inner.restore_writes += 1
                        if inner.restore_writes == 1:
                            raise InterruptedError()
                return result

        transport = AppliedThenInterrupted()
        device = core.Device('adb', 'selected', transport)
        device.preflight()
        access = core.StorageAccessSnapshot(device)
        with access:
            access.configure()

        self.assertEqual(transport.storage_mode, 'default')
        self.assertEqual(transport.restore_writes, 1)
        self.assertEqual(access.cleanup_status, 'RESTORED')

    def test_storage_sigterm_is_deferred_until_exact_state_is_restored(self):
        class TerminateAfterRestore(Transport):
            storage_mode = 'default'
            sent = False

            def __call__(inner, args, timeout=30, env=None):
                command = args[3:]
                if command and command[0] == 'shell':
                    command = ['shell', *shlex.split(' '.join(command[1:]))]
                if command[:3] == ['shell', 'appops', 'get']:
                    return 'MANAGE_EXTERNAL_STORAGE: ' + inner.storage_mode + '\n'
                result = super(TerminateAfterRestore, inner).__call__(args, timeout, env)
                if command[:3] == ['shell', 'appops', 'set']:
                    inner.storage_mode = command[-1]
                    if not inner.sent and command[-1] == 'default':
                        inner.sent = True
                        os.kill(os.getpid(), signal.SIGTERM)
                return result

        transport = TerminateAfterRestore()
        device = core.Device('adb', 'selected', transport)
        device.preflight()
        access = core.StorageAccessSnapshot(device)
        with self.assertRaises(InterruptedError):
            with access:
                access.configure()

        self.assertTrue(transport.sent)
        self.assertEqual(transport.storage_mode, 'default')
        self.assertEqual(access.cleanup_status, 'RESTORED')
        self.assertFalse(access.active_window)

    def test_process_execution_is_bounded_and_failure_output_is_private(self):
        self.assertEqual(core.execute([sys.executable,'-c','print("safe")']), 'safe\n')
        with self.assertRaises(core.Blocked) as error:
            core.execute([sys.executable,'-c','import sys; print("secret"); sys.exit(1)'])
        self.assertNotIn('secret',str(error.exception))
        with self.assertRaises(subprocess.TimeoutExpired):
            core.execute([sys.executable,'-c','import time; time.sleep(60)'],timeout=.1)
        with self.assertRaises(core.Blocked):
            core.execute(['/missing/executable'])

    def test_setting_write_timeout_still_restores_the_original_value(self):
        def timeout_after_write(args, timeout=30, env=None):
            result=self.transport(args,timeout,env)
            if 'put' in args and '2.0' in args:
                raise subprocess.TimeoutExpired('adb',timeout)
            return result
        device=core.Device('adb','selected',timeout_after_write)
        with self.assertRaises(core.Blocked):
            with core.SettingsSnapshot(device) as settings:
                settings.put('system','font_scale','2.0')
        self.assertEqual(self.transport.settings[('system','font_scale')],'1.0')
        self.assertEqual(settings.cleanup_status,'RESTORED')

    def test_display_density_snapshot_restores_exact_existing_override(self):
        self.transport.density_override = 280

        with core.DisplayDensitySnapshot(self.device) as display:
            info = display.configure_expanded()
            self.assertEqual(info['density_dpi'], 240)
            self.assertEqual(info['logical_width_dp'], 853)
            self.assertEqual(self.transport.density_override, 240)

        self.assertEqual(self.transport.density_override, 280)
        self.assertIsNone(self.transport.display_size_override)
        self.assertEqual(display.cleanup_status, 'RESTORED')
        mutations = [command for command in self.transport.commands
                     if command[-3:-1] == ['wm', 'density']]
        self.assertEqual([command[-1] for command in mutations], ['240', '280'])

    def test_display_density_snapshot_resets_when_no_override_existed(self):
        with core.DisplayDensitySnapshot(self.device) as display:
            display.configure_expanded()
            self.assertEqual(self.transport.density_override, 240)

        self.assertIsNone(self.transport.density_override)
        self.assertEqual(display.cleanup_status, 'RESTORED')
        mutations = [command for command in self.transport.commands
                     if command[-3:-1] == ['wm', 'density']]
        self.assertEqual([command[-1] for command in mutations], ['240', 'reset'])

    def test_display_density_snapshot_restores_if_target_command_times_out_after_applying(self):
        class AppliedThenTimeout(Transport):
            def __call__(inner, args, timeout=30, env=None):
                result = super(AppliedThenTimeout, inner).__call__(args, timeout, env)
                command = args[3:]
                if command[:3] == ['shell', 'wm', 'density'] and command[-1] == '240':
                    raise subprocess.TimeoutExpired('synthetic-adb', timeout)
                return result

        transport = AppliedThenTimeout()
        device = core.Device('adb', 'selected', transport)
        display = core.DisplayDensitySnapshot(device)

        with self.assertRaises(core.Blocked):
            with display:
                display.configure_expanded()

        self.assertIsNone(transport.density_override)
        self.assertEqual(display.cleanup_status, 'RESTORED')

    def test_display_density_snapshot_restores_if_target_dispatch_is_interrupted_after_applying(self):
        class AppliedThenInterrupted(Transport):
            interrupted = False

            def __call__(inner, args, timeout=30, env=None):
                result = super(AppliedThenInterrupted, inner).__call__(args, timeout, env)
                command = args[3:]
                if (not inner.interrupted and command[:3] == ['shell', 'wm', 'density']
                        and command[-1] == '240'):
                    inner.interrupted = True
                    raise InterruptedError()
                return result

        transport = AppliedThenInterrupted()
        transport.density_override = 280
        device = core.Device('adb', 'selected', transport)
        display = core.DisplayDensitySnapshot(device)

        with self.assertRaises(InterruptedError):
            with display:
                display.configure_expanded()

        self.assertEqual(transport.density_override, 280)
        self.assertEqual(display.cleanup_status, 'RESTORED')

    def test_display_density_snapshot_retries_interrupted_restore_and_propagates_it(self):
        class InterruptOnceOnRestore(Transport):
            interrupted = False

            def __call__(inner, args, timeout=30, env=None):
                command = args[3:]
                if (not inner.interrupted and command[:3] == ['shell', 'wm', 'density']
                        and command[-1] == '280'):
                    inner.interrupted = True
                    raise InterruptedError()
                return super(InterruptOnceOnRestore, inner).__call__(args, timeout, env)

        transport = InterruptOnceOnRestore()
        transport.density_override = 280
        device = core.Device('adb', 'selected', transport)
        display = core.DisplayDensitySnapshot(device)

        with self.assertRaises(InterruptedError):
            with display:
                display.configure_expanded()

        self.assertEqual(transport.density_override, 280)
        self.assertEqual(display.cleanup_status, 'RESTORED')

    def test_display_density_snapshot_refuses_stale_state_without_mutation(self):
        display = core.DisplayDensitySnapshot(self.device)
        with self.assertRaises(core.Blocked):
            with display:
                self.transport.density_override = 300
                display.configure_expanded()

        self.assertEqual(self.transport.density_override, 300)
        self.assertFalse(any(command[-3:-1] == ['wm', 'density']
                             and len(command) > 6
                             for command in self.transport.commands))
        self.assertEqual(display.cleanup_status, 'NOT REQUIRED')

    def test_display_density_mutation_allows_only_target_or_snapshotted_restore_value(self):
        self.transport.density_override = 280
        display = core.DisplayDensitySnapshot(self.device)

        with display:
            with self.assertRaises(core.Blocked):
                self.device.shell('wm', 'density', '240', mutating=True)
            with self.assertRaises(core.Blocked):
                self.device.shell('wm', 'density', '480', mutating=True)
            display.configure_expanded()

        mutations = [command[-1] for command in self.transport.commands
                     if command[-3:-1] == ['wm', 'density'] and len(command) > 6]
        self.assertEqual(mutations, ['240', '280'])
        self.assertEqual(self.transport.density_override, 280)

    def test_display_density_snapshot_blocks_before_mutation_when_expanded_width_is_unreachable(self):
        self.transport.display_size = (1200, 960)
        display = core.DisplayDensitySnapshot(self.device)

        with self.assertRaises(core.Blocked):
            with display:
                display.configure_expanded()

        self.assertFalse(any(command[-3:-1] == ['wm', 'density']
                             for command in self.transport.commands))
        self.assertEqual(display.cleanup_status, 'NOT REQUIRED')


if __name__ == '__main__':
    unittest.main()
