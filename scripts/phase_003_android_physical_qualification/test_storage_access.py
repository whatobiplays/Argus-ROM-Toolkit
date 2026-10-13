"""All-files-access snapshot tests use synthetic ADB responses only."""

import shlex
import subprocess
import unittest

import core
from test_core import Transport


class StorageTransport(Transport):
    """Model one app operation while retaining the real Device identity guard."""
    def __init__(self, mode='default', empty_output=None, failure=None):
        super().__init__()
        self.storage_mode = mode
        self.empty_output = empty_output
        self.failure = failure
        self.restore_attempts = 0

    def __call__(self, arguments, timeout=30, env=None):
        result = super().__call__(arguments, timeout, env)
        command = arguments[3:]
        if command and command[0] == 'shell':
            command = ['shell', *shlex.split(' '.join(command[1:]))]
        if command[:3] == ['shell', 'appops', 'get']:
            if self.empty_output is not None and self.storage_mode == 'default':
                return self.empty_output
            return 'MANAGE_EXTERNAL_STORAGE: ' + self.storage_mode + '\n'
        if command[:3] == ['shell', 'appops', 'set']:
            mode = command[-1]
            if mode != 'allow':
                self.restore_attempts += 1
                if self.failure == 'restore':
                    raise core.Blocked('Synthetic restoration failure')
                if self.failure == 'restore_interrupt' and self.restore_attempts == 1:
                    raise KeyboardInterrupt()
                if self.failure == 'restore_unconfirmed':
                    return result
            if self.failure != 'configure_unconfirmed':
                self.storage_mode = mode
            if self.failure == 'configure_timeout' and mode == 'allow':
                raise subprocess.TimeoutExpired('synthetic-adb', timeout)
        return result

    def access_writes(self):
        writes = []
        for arguments in self.commands:
            command = arguments[3:]
            if command and command[0] == 'shell':
                command = ['shell', *shlex.split(' '.join(command[1:]))]
            if command[:3] == ['shell', 'appops', 'set']:
                writes.append(command[3:])
        return writes


class StorageAccessTests(unittest.TestCase):
    def snapshot(self, **options):
        self.transport = StorageTransport(**options)
        self.device = core.Device('fake-adb', 'selected', self.transport)
        return core.StorageAccessSnapshot(self.device)

    def test_configure_allows_owned_storage_operation_then_restores_and_verifies_default(self):
        snapshot = self.snapshot()
        with snapshot:
            self.assertEqual(snapshot.original, 'default')
            snapshot.configure()
            self.assertEqual(self.transport.storage_mode, 'allow')
        self.assertEqual(self.transport.storage_mode, 'default')
        self.assertEqual(snapshot.cleanup_status, 'RESTORED')
        self.assertEqual(self.transport.access_writes(), [
            ['com.argusromtoolkit.argus', 'MANAGE_EXTERNAL_STORAGE', 'allow'],
            ['com.argusromtoolkit.argus', 'MANAGE_EXTERNAL_STORAGE', 'default']])

    def test_api30_empty_operations_with_default_mode_line_is_restorable(self):
        for output in ('No operations.\n', 'No operations.\nDefault mode: default\n'):
            with self.subTest(output=output):
                snapshot = self.snapshot(empty_output=output)
                with snapshot:
                    snapshot.configure()
                self.assertEqual(snapshot.original, 'default')
                self.assertEqual(snapshot.cleanup_status, 'RESTORED')
                self.assertEqual(self.transport.storage_mode, 'default')

    def test_original_deny_and_ignore_are_restored_after_configuration(self):
        for mode in ('deny', 'ignore'):
            with self.subTest(mode=mode):
                snapshot = self.snapshot(mode=mode)
                with snapshot:
                    snapshot.configure()
                self.assertEqual(self.transport.storage_mode, mode)
                self.assertEqual(snapshot.cleanup_status, 'RESTORED')

    def test_preexisting_allow_requires_no_access_mutation_or_restoration(self):
        snapshot = self.snapshot(mode='allow')
        with snapshot:
            snapshot.configure()
        self.assertEqual(self.transport.access_writes(), [])
        self.assertEqual(snapshot.cleanup_status, 'NOT REQUIRED')

    def test_unrecognized_mode_blocks_before_any_mutation_without_raw_output(self):
        snapshot = self.snapshot(mode='unknown-private-value')
        with self.assertRaises(core.Blocked) as error:
            with snapshot:
                snapshot.configure()
        self.assertNotIn('private-value', str(error.exception))
        self.assertEqual(self.transport.access_writes(), [])

    def test_uid_deny_override_with_package_ignore_blocks_without_access_writes(self):
        for prefix in ('Uid mode:', 'uid mode:', 'UID MODE:'):
            with self.subTest(prefix=prefix):
                snapshot = self.snapshot(empty_output=prefix + ' deny\nMANAGE_EXTERNAL_STORAGE: ignore\n')
                with self.assertRaises(core.Blocked):
                    with snapshot:
                        snapshot.configure()
                self.assertEqual(self.transport.access_writes(), [])
                self.assertEqual(self.transport.storage_mode, 'default')
                self.assertEqual(snapshot.cleanup_status, 'NOT REQUIRED')

    def test_configure_requires_prior_snapshot(self):
        snapshot = self.snapshot()
        with self.assertRaises(core.Blocked):
            snapshot.configure()
        self.assertEqual(self.transport.access_writes(), [])

    def test_no_configuration_leaves_original_mode_untouched(self):
        snapshot = self.snapshot()
        with snapshot:
            pass
        self.assertEqual(self.transport.access_writes(), [])
        self.assertEqual(snapshot.cleanup_status, 'NOT REQUIRED')

    def test_restoration_occurs_on_exception_and_interruption(self):
        for failure in (ValueError, KeyboardInterrupt, InterruptedError):
            with self.subTest(failure=failure.__name__):
                snapshot = self.snapshot()
                with self.assertRaises(failure):
                    with snapshot:
                        snapshot.configure()
                        raise failure()
                self.assertEqual(self.transport.storage_mode, 'default')
                self.assertEqual(snapshot.cleanup_status, 'RESTORED')

    def test_configuration_timeout_after_remote_write_still_restores_original(self):
        snapshot = self.snapshot(failure='configure_timeout')
        with self.assertRaises(core.Blocked):
            with snapshot:
                snapshot.configure()
        self.assertEqual(self.transport.storage_mode, 'default')
        self.assertEqual(snapshot.cleanup_status, 'RESTORED')

    def test_unconfirmed_configuration_blocks_and_restores_original(self):
        snapshot = self.snapshot(failure='configure_unconfirmed')
        with self.assertRaises(core.Blocked):
            with snapshot:
                snapshot.configure()
        self.assertEqual(self.transport.storage_mode, 'default')
        self.assertEqual(snapshot.cleanup_status, 'RESTORED')

    def test_failed_or_unconfirmed_restore_never_reports_restored(self):
        for failure in ('restore', 'restore_unconfirmed'):
            with self.subTest(failure=failure):
                snapshot = self.snapshot(failure=failure)
                with snapshot:
                    snapshot.configure()
                self.assertEqual(snapshot.cleanup_status, 'BLOCKED')
                self.assertEqual(self.transport.storage_mode, 'allow')

    def test_interrupted_restore_is_retried_with_same_owned_operation(self):
        snapshot = self.snapshot(failure='restore_interrupt')
        with snapshot:
            snapshot.configure()
        self.assertEqual(self.transport.restore_attempts, 2)
        self.assertEqual(self.transport.storage_mode, 'default')
        self.assertEqual(snapshot.cleanup_status, 'RESTORED')

    def test_replacement_device_prevents_restore_and_requires_owner_followup(self):
        snapshot = self.snapshot()
        with snapshot:
            snapshot.configure()
            self.transport.targets = 'replacement device usb:1-1\n'
        self.assertEqual(snapshot.cleanup_status, 'BLOCKED')
        self.assertEqual(self.transport.storage_mode, 'allow')
        self.assertEqual(len(self.transport.access_writes()), 1)

    def test_unowned_package_operation_and_invalid_mode_are_refused(self):
        self.snapshot()
        for args in (('appops', 'set', 'unrelated.app', 'MANAGE_EXTERNAL_STORAGE', 'allow'),
                     ('appops', 'set', core.PACKAGE, 'UNOWNED_OPERATION', 'allow'),
                     ('appops', 'set', core.PACKAGE, 'MANAGE_EXTERNAL_STORAGE', 'unknown')):
            with self.subTest(args=args), self.assertRaises(core.Blocked):
                self.device.shell(*args, mutating=True)
        self.assertEqual(self.transport.access_writes(), [])


if __name__ == '__main__':
    unittest.main()
