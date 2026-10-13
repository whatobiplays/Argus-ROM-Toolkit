"""Signing-input and partial-execution regression tests."""
import os
import io
import json
import shlex
import signal
import subprocess
import sys
import zipfile
from contextlib import ExitStack
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from argparse import Namespace
from test_core import Transport

import core
import runner
import ui


def remote_command(arguments):
    """Decode the real Device's quoted command vector at the fake ADB boundary."""
    command = arguments[3:]
    if command and command[0] == 'shell':
        return ['shell', *shlex.split(' '.join(command[1:]))]
    return command


class PreparationTransport(Transport):
    """A deterministic dedicated device with package, storage and cleanup state."""
    def __init__(self, *, installed=True, free_kib=1048576, failure=None):
        super().__init__()
        self.installed = installed
        self.free_kib = free_kib
        self.failure = failure
        self.directory_exists = False
        self.fixture_uploaded = False
        self.storage_mode = 'default'
        self.installed_apk_path = None
        self.installed_apk_bytes = None

    def __call__(self, arguments, timeout=30, env=None):
        result = super().__call__(arguments, timeout, env)
        command = remote_command(arguments)
        if command and command[0] == 'install':
            self.installed_apk_path = command[-1]
            self.installed_apk_bytes = Path(command[-1]).read_bytes()
        if command[:3] == ['shell', 'appops', 'get']:
            return 'MANAGE_EXTERNAL_STORAGE: ' + self.storage_mode + '\n'
        if command[:3] == ['shell', 'appops', 'set']:
            if self.failure == 'storage_restore' and command[-1] == 'default':
                raise core.Blocked('Storage access restoration refused')
            if self.failure != 'storage_configure':
                self.storage_mode = command[-1]
        if command[:3] == ['shell', 'sm', 'list-volumes']:
            return 'public:1,2 mounted PRIVATE-ID\nprivate mounted PRIVATE-ID\n'
        if command[:3] == ['shell', 'df', '-k']:
            if self.free_kib is None:
                return 'unparseable capacity\n'
            return f'Filesystem 1K-blocks Used Available Use% Mounted\n/synthetic 2097152 0 {self.free_kib} 0% /sdcard\n'
        if command[:2] == ['shell', 'mkdir']:
            if self.directory_exists or self.failure == 'mkdir':
                raise core.Blocked('Owned test-directory creation refused')
            self.directory_exists = True
        if command[:4] == ['shell', 'pm', 'list', 'packages']:
            return 'package:com.argusromtoolkit.argus\npackage:unrelated.application\n' if self.installed else ''
        if command[:3] == ['shell', 'pm', 'uninstall']:
            if self.failure == 'uninstall':
                return 'Failure\n'
            self.installed = False
        if command[:3] == ['shell', 'pm', 'clear'] and self.failure == 'clear':
            return 'Failure\n'
        if command and command[0] == 'push':
            if self.failure == 'push':
                raise core.Blocked('Fixture upload failed')
            self.fixture_uploaded = True
        if command and command[0] == 'install':
            if self.failure == 'install':
                raise core.Blocked('Release install failed')
            self.installed = True
        if command[:2] == ['shell', 'rm']:
            if self.failure == 'cleanup':
                raise core.Blocked('Guarded cleanup failed')
            self.directory_exists = False
            self.fixture_uploaded = False
        return result

    def mutations(self):
        """Return actual state-changing transport commands, excluding preflight reads."""
        commands = [remote_command(arguments) for arguments in self.commands]
        return [command for command in commands if command and (
            command[0] in ('install', 'push') or command[:2] in (
                ['shell', 'mkdir'], ['shell', 'rm']) or command[:3] in (
                ['shell', 'pm', 'uninstall'], ['shell', 'pm', 'clear'],
                ['shell', 'appops', 'set'],
                ['shell', 'settings', 'put'], ['shell', 'settings', 'delete']))]


class OrchestrationTests(unittest.TestCase):
    """Exercise runner decisions through real Device and fixture implementations."""
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.collection = self.root / 'generated-collection'
        self.collection.mkdir()
        # Synthetic structure only; no private or commercial game payload.
        (self.collection / 'probe.nes').write_bytes(b'NES\x1a' + bytes((1, 0)) + bytes(10 + 16384))
        self.apk = self.root / 'temporary.apk'
        self.apk.write_bytes(b'Synthetic artifact boundary fixture')
        self.args = Namespace(adb='fake-adb', device='selected', fixtures=self.collection,
                              fixture_limit_mib=1, signing_env=None, source_signing_env=False,
                              certificate_sha256=None, preflight_only=False, build=False,
                              apk=self.apk, retain_fixtures_for_owner=False)
        self.transport = PreparationTransport()
        self.device = core.Device('fake-adb', 'selected', self.transport)

    def execute(self, *, ui_action=None, verification=None, environment=None,
                inventory=None, build_action=None, snapshot=None,
                library_action=None, lifecycle_action=None, scaling_action=None):
        """Replace only external observations; all device guards remain active."""
        with ExitStack() as stack:
            stack.enter_context(patch.dict(os.environ, environment or {}, clear=True))
            stack.enter_context(patch.object(core, 'Device', return_value=self.device))
            stack.enter_context(patch.object(runner, 'verify_artifact',
                                            side_effect=verification if (isinstance(verification, BaseException)
                                                                         or callable(verification)) else None,
                                            return_value=(verification if verification and not callable(verification)
                                                          and not isinstance(verification, BaseException)
                                                          else {'signature_valid': True})))
            stack.enter_context(patch('ui.run_ui_scenarios', side_effect=ui_action))
            stack.enter_context(patch('ui.library_controls_probe', side_effect=library_action))
            stack.enter_context(patch('ui.surface_lifecycle_probe', side_effect=lifecycle_action))
            stack.enter_context(patch('ui.scaling_probe', side_effect=scaling_action))
            if inventory is not None:
                stack.enter_context(patch('fixtures.inspect_fixtures', return_value=inventory))
            if build_action is not None:
                stack.enter_context(patch.object(core, 'execute', side_effect=build_action))
                stack.enter_context(patch.object(runner, 'build_environment', side_effect=lambda env: env))
            if snapshot is not None:
                # Instrument construction only; restoration uses the real object.
                constructor = stack.enter_context(patch.object(core, 'SettingsSnapshot', return_value=snapshot))
                constructor.ALLOWED = snapshot.ALLOWED
            return runner.run(self.args)

    def assert_owner_untouched(self, report):
        expected = core.scenario_rows()
        self.assertEqual(set(report['scenarios']), set(expected))
        for key, row in report['scenarios'].items():
            self.assertEqual(row['owner_qualification_status'], 'NOT RUN')
            self.assertEqual(row['owner_checkpoint'], expected[key]['owner_checkpoint'])

    def test_successful_preparation_removes_only_argus_and_cleans_owned_fixtures(self):
        report = self.execute()
        self.assertEqual(report['app_preparation'], {'previous_install_removed': True,
                         'installed': True, 'fresh_state_confirmed': True,
                         'storage_access_configured': True})
        mutations = self.transport.mutations()
        self.assertEqual(mutations, [
            ['shell', 'mkdir', '/sdcard/ArgusPhase003Qualification'],
            next(command for command in mutations if command[0] == 'push'),
            ['shell', 'pm', 'uninstall', 'com.argusromtoolkit.argus'],
            ['install', '-r', self.transport.installed_apk_path],
            ['shell', 'pm', 'clear', 'com.argusromtoolkit.argus'],
            ['shell', 'appops', 'set', 'com.argusromtoolkit.argus', 'MANAGE_EXTERNAL_STORAGE', 'allow'],
            ['shell', 'settings', 'put', 'system', 'font_scale', '1.3'],
            ['shell', 'settings', 'put', 'system', 'font_scale', '2.0'],
            ['shell', 'appops', 'set', 'com.argusromtoolkit.argus', 'MANAGE_EXTERNAL_STORAGE', 'default'],
            ['shell', 'settings', 'put', 'system', 'font_scale', '1.0'],
            ['shell', 'rm', '-rf', '/sdcard/ArgusPhase003Qualification']])
        pushed = mutations[1]
        self.assertEqual(pushed[-1], '/sdcard/ArgusPhase003Qualification/fixtures')
        self.assertFalse(Path(pushed[1]).exists())
        self.assertEqual(report['device_fixture_cleanup'], 'REMOVED')
        self.assertEqual(report['storage_access_cleanup'], 'RESTORED')
        self.assertEqual(report['removable_media']['public_volume_count'], 1)
        self.assertFalse(self.transport.directory_exists)
        self.assertNotIn('PRIVATE-ID', json.dumps(report))
        self.assert_owner_untouched(report)

    def test_install_uses_the_exact_private_apk_bytes_that_verification_received(self):
        original_bytes = self.apk.read_bytes()
        verified_paths = []
        verified_bytes = []

        def verify_and_replace_source(private_apk, *_):
            private_apk = Path(private_apk)
            verified_paths.append(private_apk)
            self.assertEqual(len(list(private_apk.parent.iterdir())), 1)
            self.assertEqual(private_apk.stat().st_mode & 0o222, 0)
            verified_bytes.append(private_apk.read_bytes())
            self.apk.write_bytes(b'Replaced source after verification')
            return {'signature_valid': True}

        report = self.execute(verification=verify_and_replace_source)

        self.assertEqual(self.apk.read_bytes(), b'Replaced source after verification')
        self.assertEqual(verified_bytes, [original_bytes])
        self.assertEqual(self.transport.installed_apk_bytes, original_bytes)
        self.assertNotEqual(self.transport.installed_apk_path, str(self.apk))
        self.assertEqual(len(verified_paths), 1)
        self.assertFalse(verified_paths[0].exists())
        self.assert_owner_untouched(report)

    def test_fixture_staging_oserror_is_sanitized_without_leaking_host_path(self):
        class UnreadableInventory:
            def summary(self):
                return {'classes': {}}

            def stage(self, destination, max_bytes):
                raise OSError('/synthetic/private-host/fixture-data is unreadable')

        report = self.execute(inventory=UnreadableInventory())

        self.assertEqual(report['blockers'], [
            'Host or device I/O failed; raw paths and output withheld'])
        self.assertNotIn('/synthetic/private-host', json.dumps(report))
        self.assertFalse(report['device_mutations'])
        self.assert_owner_untouched(report)

    def test_absent_previous_install_is_not_uninstalled(self):
        self.transport.installed = False
        report = self.execute()
        self.assertFalse(report['app_preparation']['previous_install_removed'])
        self.assertTrue(report['app_preparation']['fresh_state_confirmed'])
        self.assertFalse(any(command[:3] == ['shell', 'pm', 'uninstall']
                             for command in self.transport.mutations()))

    def test_explicit_retention_keeps_exclusively_created_owner_fixture_directory(self):
        self.args.retain_fixtures_for_owner = True
        report = self.execute()
        self.assertTrue(self.transport.directory_exists)
        self.assertTrue(self.transport.fixture_uploaded)
        self.assertEqual(report['device_fixture_cleanup'], 'RETAINED FOR OWNER CHECKPOINTS')
        self.assertFalse(any(command[:2] == ['shell', 'rm'] for command in self.transport.mutations()))
        self.assert_owner_untouched(report)

    def test_unconfirmed_fixture_upload_is_retained_as_blocked_for_owner_inspection(self):
        self.args.retain_fixtures_for_owner = True
        self.transport.failure = 'push'

        report = self.execute()

        self.assertTrue(self.transport.directory_exists)
        self.assertFalse(self.transport.fixture_uploaded)
        self.assertEqual(report['device_fixture_cleanup'], 'BLOCKED')
        self.assertIn(
            'Fixture upload did not confirm; owned directory retained for owner inspection',
            report['blockers'])
        self.assertFalse(any(command[:2] == ['shell', 'rm']
                             for command in self.transport.mutations()))
        self.assert_owner_untouched(report)

    def test_existing_directory_is_never_uploaded_cleared_installed_or_deleted(self):
        self.transport.directory_exists = True
        report = self.execute()
        self.assertFalse(report['device_mutations'])
        self.assertEqual(self.transport.mutations(), [['shell', 'mkdir', '/sdcard/ArgusPhase003Qualification']])
        self.assertTrue(self.transport.directory_exists)
        self.assertNotIn('app_preparation', report)
        self.assertNotEqual(report['device_fixture_cleanup'], 'REMOVED')
        self.assert_owner_untouched(report)

    def test_uncertain_mkdir_timeout_requires_owner_followup_without_deleting_unproven_directory(self):
        class UncertainCreation(PreparationTransport):
            def __call__(self, arguments, timeout=30, env=None):
                result = super().__call__(arguments, timeout, env)
                if remote_command(arguments)[:2] == ['shell', 'mkdir']:
                    raise subprocess.TimeoutExpired('synthetic-adb', timeout)
                return result
        self.transport = UncertainCreation()
        self.device = core.Device('fake-adb', 'selected', self.transport)
        report = self.execute()
        self.assertTrue(self.transport.directory_exists)
        self.assertEqual(report['device_fixture_cleanup'], 'BLOCKED')
        self.assertTrue(report['blockers'])
        self.assertFalse(any(command[:2] == ['shell', 'rm'] or command[0] in ('push', 'install')
                             or command[:3] == ['shell', 'pm', 'clear']
                             for command in self.transport.mutations()))
        self.assert_owner_untouched(report)

    def test_capacity_failures_prevent_all_mutation(self):
        for capacity in (1, None):
            with self.subTest(capacity=capacity):
                self.transport = PreparationTransport(free_kib=capacity)
                self.device = core.Device('fake-adb', 'selected', self.transport)
                report = self.execute()
                self.assertTrue(report['blockers'])
                self.assertFalse(report['device_mutations'])
                self.assertEqual(self.transport.mutations(), [])
                self.assertEqual(report['device_fixture_cleanup'], 'NOT REQUIRED')

    def test_empty_staged_selection_cannot_reset_or_install(self):
        class EmptyInventory:
            def summary(self):
                return {'classes': {}}
            def stage(self, destination, max_bytes):
                return {'status': 'blocked', 'staged_bundles': 0, 'staged_bytes': 0}
        report = self.execute(inventory=EmptyInventory())
        self.assertEqual(self.transport.mutations(), [])
        self.assertTrue(report['blockers'])
        self.assert_owner_untouched(report)

    def test_artifact_rejection_precedes_every_device_mutation(self):
        report = self.execute(verification=core.Blocked('Artifact verification failed'))
        self.assertEqual(self.transport.mutations(), [])
        self.assertFalse(report['device_mutations'])
        self.assertEqual(report['blockers'], ['Artifact verification failed'])

    def test_preflight_only_requires_no_artifact_and_makes_no_mutations(self):
        self.args.preflight_only = True
        self.args.apk = None
        report = self.execute(verification=AssertionError('Artifact verification must not run'))
        self.assertEqual(report['blockers'], [])
        self.assertEqual(self.transport.mutations(), [])
        self.assertNotIn('artifact', report)
        self.assertTrue(all(row['automation_status'] == 'BLOCKED' for row in report['scenarios'].values()))
        self.assert_owner_untouched(report)

    def test_missing_artifact_choice_cannot_mutate(self):
        self.args.apk = None
        report = self.execute()
        self.assertTrue(report['blockers'])
        self.assertNotIn('artifact', report)
        self.assertEqual(self.transport.mutations(), [])

    def test_missing_signing_fields_and_unavailable_keystore_cannot_build_or_mutate(self):
        self.args.build = True
        cases = [{}, {key: 'synthetic-value' for key in runner.SIGNING_FIELDS}]
        for environment in cases:
            with self.subTest(configured=bool(environment)):
                report = self.execute(environment=environment, build_action=AssertionError('Build must not execute'))
                self.assertTrue(report['blockers'])
                self.assertNotIn('build', report)
                self.assertEqual(self.transport.mutations(), [])
                self.assertNotIn('synthetic-value', json.dumps(report))

    def signing_environment(self):
        keystore = self.root / 'synthetic.jks'
        keystore.write_bytes(b'not a real signing key')
        return {'ARGUS_RELEASE_KEYSTORE': str(keystore),
                'ARGUS_RELEASE_STORE_PASSWORD': 'synthetic-store-password',
                'ARGUS_RELEASE_KEY_ALIAS': 'synthetic-alias',
                'ARGUS_RELEASE_KEY_PASSWORD': 'synthetic-key-password'}

    def test_failed_or_timed_out_release_build_cannot_install_clear_or_upload(self):
        self.args.build = True
        for failure in (core.Blocked('Synthetic build refusal'),
                        subprocess.TimeoutExpired('synthetic-build', 1)):
            with self.subTest(failure=type(failure).__name__):
                report = self.execute(environment=self.signing_environment(), build_action=failure)
                self.assertEqual(report['build'], {'attempted': True, 'status': 'FAIL'})
                self.assertEqual(self.transport.mutations(), [])
                self.assertNotIn('synthetic-key-password', json.dumps(report))
                self.assert_owner_untouched(report)

    def test_successful_local_build_uses_its_artifact_before_preparing_app(self):
        artifact = self.root / 'flutter/build/app/outputs/flutter-apk/app-release.apk'
        artifact.parent.mkdir(parents=True)
        artifact.write_bytes(b'Synthetic build output')
        self.args.build = True
        with patch.object(runner, 'ROOT', self.root):
            report = self.execute(environment=self.signing_environment(), build_action=lambda *args, **kwargs: '')
        self.assertEqual(report['build']['status'], 'PASS')
        self.assertEqual(self.transport.installed_apk_bytes, artifact.read_bytes())
        self.assertNotEqual(self.transport.installed_apk_path, str(artifact))
        self.assertTrue(report['app_preparation']['fresh_state_confirmed'])

    def test_device_failures_stop_later_preparation_and_still_cleanup_owned_directory(self):
        for failure in ('push', 'uninstall', 'install', 'clear'):
            with self.subTest(failure=failure):
                self.transport = PreparationTransport(failure=failure)
                self.device = core.Device('fake-adb', 'selected', self.transport)
                report = self.execute(ui_action=AssertionError('UI must not run'))
                self.assertTrue(report['blockers'])
                self.assertEqual(report['device_fixture_cleanup'], 'REMOVED')
                self.assertFalse(self.transport.directory_exists)
                self.assertFalse(report.get('app_preparation', {}).get('fresh_state_confirmed', False))
                if failure in ('push', 'uninstall'):
                    self.assertFalse(any(command[0] == 'install' for command in self.transport.mutations()))
                self.assert_owner_untouched(report)

    def test_cleanup_failure_is_reported_without_claiming_removal(self):
        self.transport.failure = 'cleanup'
        report = self.execute()
        self.assertEqual(report['device_fixture_cleanup'], 'BLOCKED')
        self.assertTrue(self.transport.directory_exists)
        self.assertIn('Device cleanup requires owner follow-up', report['blockers'])

    def test_interruption_restores_changed_and_absent_settings_preserving_owner_results(self):
        for interruption in (KeyboardInterrupt, InterruptedError):
            with self.subTest(interruption=interruption.__name__):
                snapshot = core.SettingsSnapshot(self.device)
                def interrupted(device, rows, summary):
                    snapshot.put('system', 'font_scale', '2.0')
                    snapshot.put('secure', 'accessibility_enabled', '1')
                    core.assertion(rows['AND-02'], 'record_consistency', False, 'Observed expectation failed')
                    raise interruption()
                report = self.execute(ui_action=interrupted, snapshot=snapshot)
                self.assertEqual(self.transport.settings[('system', 'font_scale')], '1.0')
                self.assertEqual(self.transport.settings[('secure', 'accessibility_enabled')], 'null')
                self.assertEqual(report['settings_cleanup'], 'RESTORED')
                self.assertEqual(report['device_fixture_cleanup'], 'REMOVED')
                self.assertEqual(report['scenarios']['AND-02']['automation_status'], 'FAIL')
                self.assert_owner_untouched(report)

    def test_bounded_ui_timeout_is_reported_and_cleans_owned_fixtures(self):
        report = self.execute(ui_action=subprocess.TimeoutExpired('private-command', 1))
        self.assertEqual(report['blockers'], ['Bounded command timed out'])
        self.assertEqual(report['device_fixture_cleanup'], 'REMOVED')
        self.assertNotIn('private-command', json.dumps(report))

    def test_external_signing_loader_is_used_before_preflight_only_returns(self):
        source = self.root / 'synthetic-signing.env'
        source.write_text('ARGUS_RELEASE_KEYSTORE=/synthetic/external.jks\n'
                          'ARGUS_RELEASE_STORE_PASSWORD=synthetic-store-password\n'
                          'ARGUS_RELEASE_KEY_ALIAS=synthetic-alias\n'
                          'ARGUS_RELEASE_KEY_PASSWORD=synthetic-key-password\n')
        source.chmod(0o600)
        self.args.signing_env = source
        self.args.preflight_only = True
        report = self.execute()
        self.assertEqual(report['signing']['configured_fields'], 4)
        self.assertEqual(self.transport.mutations(), [])
        self.assertNotIn('synthetic-key-password', json.dumps(report))

    def test_storage_access_is_allowed_after_fresh_reset_before_ui_and_restored_afterward(self):
        def observed(device, rows, summary):
            self.assertEqual(self.transport.storage_mode, 'allow')
            commands = self.transport.mutations()
            self.assertLess(commands.index(['shell', 'pm', 'clear', 'com.argusromtoolkit.argus']),
                            commands.index(['shell', 'appops', 'set', 'com.argusromtoolkit.argus',
                                            'MANAGE_EXTERNAL_STORAGE', 'allow']))
        report = self.execute(ui_action=observed)
        self.assertEqual(self.transport.storage_mode, 'default')
        self.assertEqual(report['storage_access_cleanup'], 'RESTORED')
        self.assert_owner_untouched(report)

    def test_explicit_ui_failure_stops_all_fallback_and_scaling_probes(self):
        later = []

        def observed_failure(device, rows, summary):
            core.assertion(rows['AND-01'], 'startup_contract', False,
                           'Synthetic product failure observed')

        report = self.execute(
            ui_action=observed_failure,
            library_action=lambda *_: later.append('library'),
            lifecycle_action=lambda *args: later.append(args[-1]),
            scaling_action=lambda *_: later.append('scaling'))

        self.assertEqual(later, [])
        self.assertEqual(report['scenarios']['AND-01']['automation_status'], 'FAIL')
        self.assertEqual(report['scenarios']['AND-02']['automation_status'], 'BLOCKED')
        self.assertFalse(any(command[:3] == ['shell', 'settings', 'put']
                             and command[3:6] == ['system', 'font_scale', '1.3']
                             for command in self.transport.mutations()))
        self.assert_owner_untouched(report)

    def test_ui_cleanup_failure_stops_later_probes_and_preserves_product_failure(self):
        for product_failure, expected in ((False, 'BLOCKED'), (True, 'FAIL')):
            with self.subTest(product_failure=product_failure):
                error = ui.UICleanupBlocked(product_failure_observed=product_failure)
                error.scenario = 'AND-01'
                later = []

                def failed_cleanup(*_):
                    raise error

                report = self.execute(
                    ui_action=failed_cleanup,
                    library_action=lambda *_: later.append('library'),
                    lifecycle_action=lambda *args: later.append(args[-1]),
                    scaling_action=lambda *_: later.append('scaling'))

                self.assertEqual(later, [])
                self.assertEqual(report['scenarios']['AND-01']['automation_status'], expected)
                self.assertIn('Accessibility capture cleanup failed; owner follow-up is required.',
                              report['blockers'])
                self.assertEqual(report['scenarios']['AND-01']['assertions'][-1]['status'], expected)
                self.assertEqual(report['device_fixture_cleanup'], 'REMOVED')
                self.assertEqual(report['storage_access_cleanup'], 'RESTORED')
                self.assert_owner_untouched(report)

    def test_interrupted_ui_cleanup_keeps_explicit_product_failure_as_fail(self):
        error = InterruptedError()
        error.ui_cleanup_blocker = 'Guarded UI capture cleanup was interrupted.'
        error.ui_product_failure_observed = True
        error.ui_cleanup_scenario = 'AND-01'

        def interrupted(*_):
            raise error

        report = self.execute(ui_action=interrupted)

        self.assertIn('Guarded UI capture cleanup was interrupted.', report['blockers'])
        self.assertEqual(report['scenarios']['AND-01']['automation_status'], 'FAIL')
        self.assertEqual(report['scenarios']['AND-01']['assertions'][-1]['status'], 'FAIL')
        self.assertEqual(report['scenarios']['AND-02']['automation_status'], 'BLOCKED')
        self.assert_owner_untouched(report)

    def test_storage_restore_sigterm_preserves_pending_ui_cleanup_evidence(self):
        cases = (
            ('observed_product_failure', 'cleanup', True, 'FAIL',
             'Accessibility capture cleanup failed; owner follow-up is required.'),
            ('unobserved_product_failure', 'cleanup', False, 'BLOCKED',
             'Accessibility capture cleanup failed; owner follow-up is required.'),
            ('interrupted_product_failure', 'interrupted', True, 'FAIL',
             'Guarded UI capture cleanup was interrupted.'),
        )
        for name, error_kind, product_failure, expected_status, expected_cleanup_blocker in cases:
            with self.subTest(case=name):
                class TerminateDuringStorageRestore(PreparationTransport):
                    sent = False

                    def __call__(inner, arguments, timeout=30, env=None):
                        command = remote_command(arguments)
                        result = super(TerminateDuringStorageRestore, inner).__call__(
                            arguments, timeout, env)
                        restoring_storage = command == [
                            'shell', 'appops', 'set', core.PACKAGE,
                            'MANAGE_EXTERNAL_STORAGE', 'default']
                        if not inner.sent and restoring_storage:
                            inner.sent = True
                            os.kill(os.getpid(), signal.SIGTERM)
                        return result

                self.transport = TerminateDuringStorageRestore()
                self.device = core.Device('fake-adb', 'selected', self.transport)
                original_settings = dict(self.transport.settings)
                error = (ui.UICleanupBlocked(product_failure_observed=product_failure)
                         if error_kind == 'cleanup' else InterruptedError())
                error.scenario = 'AND-01'
                if error_kind == 'interrupted':
                    error.ui_cleanup_blocker = expected_cleanup_blocker
                    error.ui_product_failure_observed = product_failure
                    error.ui_cleanup_scenario = 'AND-01'
                later_ui_probes = []

                def fail_ui(*_):
                    raise error

                report = self.execute(
                    ui_action=fail_ui,
                    library_action=lambda *_: later_ui_probes.append('library'),
                    lifecycle_action=lambda *args: later_ui_probes.append(args[-1]),
                    scaling_action=lambda *_: later_ui_probes.append('scaling'))

                self.assertTrue(self.transport.sent)
                self.assertEqual(self.transport.storage_mode, 'default')
                self.assertEqual(report['storage_access_cleanup'], 'RESTORED')
                self.assertEqual(self.transport.settings, original_settings)
                mutations = self.transport.mutations()
                self.assertEqual(
                    [command[-1] for command in mutations if command[:3] ==
                     ['shell', 'appops', 'set']], ['allow', 'default'])
                self.assertFalse(any(command[:3] == ['shell', 'settings', 'put']
                                     or command[:3] == ['shell', 'settings', 'delete']
                                     for command in mutations))
                self.assertEqual(later_ui_probes, [])
                self.assertEqual(report['scenarios']['AND-01']['automation_status'],
                                 expected_status)
                self.assertEqual(report['scenarios']['AND-01']['assertions'][-1]['status'],
                                 expected_status)
                self.assertIn('Qualification interrupted; guarded cleanup attempted',
                              report['blockers'])
                self.assertIn(expected_cleanup_blocker, report['blockers'])
                self.assertEqual(report['scenarios']['AND-02']['automation_status'], 'BLOCKED')
                self.assert_owner_untouched(report)

    def test_settings_restore_sigterm_preserves_pending_scaling_cleanup_evidence(self):
        for product_failure, expected_status in ((True, 'FAIL'), (False, 'BLOCKED')):
            with self.subTest(product_failure=product_failure):
                class TerminateDuringSettingsRestore(PreparationTransport):
                    sent = False

                    def __call__(inner, arguments, timeout=30, env=None):
                        command = remote_command(arguments)
                        result = super(TerminateDuringSettingsRestore, inner).__call__(
                            arguments, timeout, env)
                        restoring_font_scale = command == [
                            'shell', 'settings', 'put', 'system', 'font_scale', '1.0']
                        if not inner.sent and restoring_font_scale:
                            inner.sent = True
                            os.kill(os.getpid(), signal.SIGTERM)
                        return result

                self.transport = TerminateDuringSettingsRestore()
                self.device = core.Device('fake-adb', 'selected', self.transport)
                original_settings = dict(self.transport.settings)
                error = ui.UICleanupBlocked(product_failure_observed=product_failure)
                error.scenario = 'UX-A03'
                scaling_attempts = []

                def failed_scaling(*_):
                    scaling_attempts.append('first')
                    raise error

                report = self.execute(scaling_action=failed_scaling)

                self.assertTrue(self.transport.sent)
                self.assertEqual(self.transport.settings, original_settings)
                self.assertEqual(report['settings_cleanup'], 'RESTORED')
                self.assertEqual(report['storage_access_cleanup'], 'RESTORED')
                mutations = self.transport.mutations()
                self.assertEqual(
                    [command[-1] for command in mutations if command[:3] ==
                     ['shell', 'settings', 'put']], ['1.3', '1.0'])
                self.assertEqual(
                    [command[-1] for command in mutations if command[:3] ==
                     ['shell', 'appops', 'set']], ['allow', 'default'])
                self.assertEqual(scaling_attempts, ['first'])
                self.assertEqual(report['scenarios']['UX-A03']['automation_status'],
                                 expected_status)
                self.assertEqual(report['scenarios']['UX-A03']['assertions'][-1]['status'],
                                 expected_status)
                self.assertIn('Qualification interrupted; guarded cleanup attempted',
                              report['blockers'])
                self.assertIn('Accessibility capture cleanup failed; owner follow-up is required.',
                              report['blockers'])
                self.assert_owner_untouched(report)

    def test_sigterm_during_settings_or_storage_cleanup_is_reported_after_restoration(self):
        for phase in ('settings', 'storage'):
            with self.subTest(phase=phase):
                class TerminateAfterRestore(PreparationTransport):
                    sent = False

                    def __call__(inner, arguments, timeout=30, env=None):
                        command = remote_command(arguments)
                        result = super(TerminateAfterRestore, inner).__call__(arguments, timeout, env)
                        restoring_setting = command == [
                            'shell', 'settings', 'put', 'system', 'font_scale', '1.0']
                        restoring_storage = command == [
                            'shell', 'appops', 'set', core.PACKAGE,
                            'MANAGE_EXTERNAL_STORAGE', 'default']
                        if (not inner.sent and ((phase == 'settings' and restoring_setting)
                                                or (phase == 'storage' and restoring_storage))):
                            inner.sent = True
                            os.kill(os.getpid(), signal.SIGTERM)
                        return result

                self.transport = TerminateAfterRestore()
                self.device = core.Device('fake-adb', 'selected', self.transport)
                report = self.execute()

                self.assertTrue(self.transport.sent)
                self.assertIn('Qualification interrupted; guarded cleanup attempted',
                              report['blockers'])
                self.assertEqual(report['settings_cleanup'], 'RESTORED')
                self.assertEqual(report['storage_access_cleanup'], 'RESTORED')
                self.assertEqual(self.transport.settings[('system', 'font_scale')], '1.0')
                self.assertEqual(self.transport.storage_mode, 'default')
                self.assertEqual(report['device_fixture_cleanup'], 'REMOVED')
                self.assert_owner_untouched(report)

    def test_sigterm_after_fixture_removal_reports_interruption_without_false_cleanup_failure(self):
        class TerminateAfterRemoval(PreparationTransport):
            sent = False

            def __call__(inner, arguments, timeout=30, env=None):
                command = remote_command(arguments)
                result = super(TerminateAfterRemoval, inner).__call__(arguments, timeout, env)
                if (not inner.sent and command[:3] ==
                        ['shell', 'rm', '-rf']):
                    inner.sent = True
                    os.kill(os.getpid(), signal.SIGTERM)
                return result

        self.transport = TerminateAfterRemoval()
        self.device = core.Device('fake-adb', 'selected', self.transport)
        report = self.execute()

        self.assertTrue(self.transport.sent)
        self.assertIn('Qualification interrupted during bounded device cleanup', report['blockers'])
        self.assertEqual(report['device_fixture_cleanup'], 'REMOVED')
        self.assertFalse(self.transport.directory_exists)
        self.assert_owner_untouched(report)

    def test_primary_successful_scenario_observations_are_not_repeated_by_fallbacks(self):
        later = []

        def observed_primary(device, scenarios, summary):
            for scenario, check in (('AND-02', 'library_controls'),
                                    ('AND-04', 'background_return'),
                                    ('AND-05', 'process_relaunch')):
                scenarios[scenario]['assertions'].append({
                    'check': check, 'status': 'PASS', 'detail': 'Synthetic observed probe.'})
                scenarios[scenario]['automation_status'] = 'BLOCKED'

        report = self.execute(
            ui_action=observed_primary,
            library_action=lambda *_: later.append('library'),
            lifecycle_action=lambda _device, _rows, scenario: later.append(scenario))

        self.assertEqual(later, [])
        for scenario in ('AND-02', 'AND-04', 'AND-05'):
            self.assertEqual(report['scenarios'][scenario]['automation_status'], 'BLOCKED')
        self.assert_owner_untouched(report)

    def test_failure_in_each_fallback_stops_later_lifecycle_and_scale_mutations(self):
        for failure_at, expected in (
                ('library', ['library']),
                ('AND-04', ['library', 'AND-04']),
                ('AND-05', ['library', 'AND-04', 'AND-05'])):
            with self.subTest(failure_at=failure_at):
                later = []

                def fail_library(_device, scenarios):
                    later.append('library')
                    if failure_at == 'library':
                        core.assertion(scenarios['AND-02'], 'synthetic_failure', False,
                                       'Observed fallback product failure.')

                def fail_lifecycle(_device, scenarios, scenario):
                    later.append(scenario)
                    if failure_at == scenario:
                        core.assertion(scenarios[scenario], 'synthetic_failure', False,
                                       'Observed fallback product failure.')

                report = self.execute(
                    library_action=fail_library,
                    lifecycle_action=fail_lifecycle,
                    scaling_action=lambda *_: later.append('scaling'))

                self.assertEqual(later, expected)
                self.assertEqual(report['scenarios'][failure_at if failure_at != 'library'
                                                       else 'AND-02']['automation_status'], 'FAIL')
                self.assertFalse(any(command[:3] == ['shell', 'settings', 'put']
                                     and command[3:6] == ['system', 'font_scale', '1.3']
                                     for command in self.transport.mutations()))
                self.assert_owner_untouched(report)

    def test_scaling_failure_stops_later_scale_mutations(self):
        observed = []

        def fail_first_scale(_device, scenarios):
            observed.append(self.transport.settings[('system', 'font_scale')])
            if len(observed) == 1:
                core.assertion(scenarios['UX-A03'], 'synthetic_scaling_failure', False,
                               'Observed scale-specific product failure.')

        report = self.execute(scaling_action=fail_first_scale)

        self.assertEqual(observed, ['1.3'])
        self.assertNotIn(['shell', 'settings', 'put', 'system', 'font_scale', '2.0'],
                         self.transport.mutations())
        self.assertEqual(self.transport.settings[('system', 'font_scale')], '1.0')
        self.assertEqual(report['scenarios']['UX-A03']['automation_status'], 'FAIL')

    def test_interruption_reports_owned_cleanup_blockers(self):
        for attribute, blocker in (
                ('density_cleanup_blocker',
                 'Original display-density state requires owner restoration'),
                ('ui_cleanup_blocker', 'Guarded UI capture cleanup failed.')):
            with self.subTest(attribute=attribute):
                interruption = InterruptedError()
                setattr(interruption, attribute, blocker)

                def interrupted(*_):
                    raise interruption

                report = self.execute(ui_action=interrupted)
                self.assertIn(blocker, report['blockers'])

    def test_font_scale_readback_mismatch_blocks_geometry_probe(self):
        class RejectedFontScale(PreparationTransport):
            def __call__(self, arguments, timeout=30, env=None):
                result = super().__call__(arguments, timeout, env)
                if remote_command(arguments) == [
                        'shell', 'settings', 'put', 'system', 'font_scale', '1.3']:
                    self.settings[('system', 'font_scale')] = '1.0'
                return result

        self.transport = RejectedFontScale()
        self.device = core.Device('fake-adb', 'selected', self.transport)
        scaling_calls = []

        report = self.execute(scaling_action=lambda *_: scaling_calls.append('called'))

        self.assertEqual(scaling_calls, [])
        self.assertEqual(report['scenarios']['UX-A03']['automation_status'], 'BLOCKED')
        readback = [entry for entry in report['scenarios']['UX-A03']['assertions']
                    if entry['check'] == 'font_scale_readback_1_3']
        self.assertEqual(readback[0]['status'], 'BLOCKED')
        self.assertEqual(self.transport.settings[('system', 'font_scale')], '1.0')
        self.assert_owner_untouched(report)

    def test_unconfirmed_storage_access_never_runs_ui_and_restores_original_mode(self):
        self.transport.failure = 'storage_configure'
        report = self.execute(ui_action=AssertionError('Unconfirmed storage access must block UI'))
        self.assertTrue(report['blockers'])
        self.assertEqual(self.transport.storage_mode, 'default')
        self.assertEqual(report['storage_access_cleanup'], 'RESTORED')
        self.assertEqual(report['device_fixture_cleanup'], 'REMOVED')
        self.assertFalse(report['app_preparation'].get('storage_access_configured', False))

    def test_storage_access_cleanup_failure_reports_owner_followup(self):
        self.transport.failure = 'storage_restore'
        report = self.execute()
        self.assertEqual(report['storage_access_cleanup'], 'BLOCKED')
        self.assertEqual(self.transport.storage_mode, 'allow')
        self.assertIn('Argus storage access restoration requires owner follow-up', report['blockers'])
        self.assertEqual(report['device_fixture_cleanup'], 'REMOVED')
        self.assert_owner_untouched(report)

    def test_settings_cleanup_failure_adds_blocker_and_preserves_owner_results(self):
        class RefusedSettingsRestore(PreparationTransport):
            def __call__(self, arguments, timeout=30, env=None):
                command = remote_command(arguments)
                if command == ['shell', 'settings', 'put', 'system', 'font_scale', '1.0']:
                    self.commands.append(arguments)
                    raise core.Blocked('Synthetic settings restore refusal')
                return super().__call__(arguments, timeout, env)
        self.transport = RefusedSettingsRestore()
        self.device = core.Device('fake-adb', 'selected', self.transport)
        snapshot = core.SettingsSnapshot(self.device)
        def change_settings(device, rows, summary):
            snapshot.put('system', 'font_scale', '2.0')
        report = self.execute(ui_action=change_settings, snapshot=snapshot)
        self.assertEqual(report['settings_cleanup'], 'BLOCKED')
        self.assertEqual(self.transport.settings[('system', 'font_scale')], '2.0')
        self.assertIn('Android setting restoration requires owner follow-up', report['blockers'])
        self.assertEqual(report['device_fixture_cleanup'], 'REMOVED')
        self.assert_owner_untouched(report)

    def test_partial_probes_execute_in_order_inside_access_context_at_each_scale_then_restore(self):
        observations = []
        shared_rows = []
        def observe(name, device, rows):
            self.assertIs(device, self.device)
            self.assertEqual(self.transport.storage_mode, 'allow')
            self.assertTrue(all(row['owner_qualification_status'] == 'NOT RUN' for row in rows.values()))
            shared_rows.append(rows)
            observations.append((name, self.transport.settings[('system', 'font_scale')]))
        def startup(device, rows, summary):
            self.assertGreater(summary['staged_bundles'], 0)
            observe('startup', device, rows)
        report = self.execute(
            ui_action=startup,
            library_action=lambda device, rows: observe('library', device, rows),
            lifecycle_action=lambda device, rows, scenario: observe(scenario, device, rows),
            scaling_action=lambda device, rows: observe('scaling', device, rows))
        self.assertEqual(observations, [('startup', '1.0'), ('library', '1.0'),
                                       ('AND-04', '1.0'), ('AND-05', '1.0'),
                                       ('scaling', '1.3'), ('scaling', '2.0')])
        self.assertTrue(all(observed is report['scenarios'] for observed in shared_rows))
        self.assertEqual(self.transport.storage_mode, 'default')
        self.assertEqual(self.transport.settings[('system', 'font_scale')], '1.0')
        self.assertEqual(report['storage_access_cleanup'], 'RESTORED')
        self.assertEqual(report['settings_cleanup'], 'RESTORED')
        self.assertEqual(report['device_fixture_cleanup'], 'REMOVED')
        self.assertEqual(report['blockers'], [])
        self.assertEqual(
            [entry['check'] for entry in report['scenarios']['UX-A03']['assertions']
             if entry['check'].startswith('font_scale_readback_')],
            ['font_scale_readback_1_3', 'font_scale_readback_2_0'])
        self.assert_owner_untouched(report)

    def test_interrupted_first_scaling_probe_restores_settings_access_and_stops_later_scale(self):
        observations = []
        def interrupt_scaling(device, rows):
            observations.append(self.transport.settings[('system', 'font_scale')])
            self.assertEqual(self.transport.storage_mode, 'allow')
            raise InterruptedError()
        report = self.execute(scaling_action=interrupt_scaling)
        self.assertEqual(observations, ['1.3'])
        self.assertEqual(self.transport.settings[('system', 'font_scale')], '1.0')
        self.assertEqual(self.transport.storage_mode, 'default')
        self.assertEqual(report['settings_cleanup'], 'RESTORED')
        self.assertEqual(report['storage_access_cleanup'], 'RESTORED')
        self.assertEqual(report['device_fixture_cleanup'], 'REMOVED')
        self.assertTrue(report['blockers'])
        self.assertNotIn(['shell', 'settings', 'put', 'system', 'font_scale', '2.0'], self.transport.mutations())
        self.assert_owner_untouched(report)


class ArtifactTests(unittest.TestCase):
    """Verify real APK container and provenance rules with synthetic tool output."""
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        (self.root / 'flutter').mkdir()
        (self.root / 'flutter/pubspec.yaml').write_text('name: synthetic\nversion: 0.1.0+1\n')
        self.apk = self.root / 'temporary.apk'
        self.entries = ['lib/arm64-v8a/libargus_bridge.so',
                        'lib/arm64-v8a/libandroid_native_keyring_store.so']
        self.badging = "package: name='com.argusromtoolkit.argus' versionCode='1' versionName='0.1.0'\nminSdkVersion:'30'\nnative-code: 'arm64-v8a'\n"
        self.signer = 'Signer #1 certificate SHA-256 digest: ' + 'a' * 64
        self.commands = []
        self.git_status = ''
        self.write_apk()

    def write_apk(self):
        with zipfile.ZipFile(self.apk, 'w') as archive:
            for entry in self.entries:
                archive.writestr(entry, b'synthetic native packaging placeholder')

    def external_tool(self, arguments, **kwargs):
        self.commands.append(arguments)
        if arguments == ['aapt2', 'dump', 'badging', str(self.apk)]:
            return self.badging
        if arguments == ['apksigner', 'verify', '--verbose', '--print-certs',
                         '--min-sdk-version', '30', str(self.apk)]:
            return self.signer
        if arguments == ['git', '-C', str(self.root), 'rev-parse', 'HEAD']:
            return 'f' * 40 + '\n'
        if arguments == ['git', '-C', str(self.root), 'status', '--porcelain',
                         '--untracked-files=all']:
            return self.git_status
        raise AssertionError('Unexpected external verification command')

    def verify(self, *, reference=None, built_here=False):
        with patch.object(runner, 'ROOT', self.root), \
                patch.object(runner, 'build_tool', side_effect=lambda name, env: name), \
                patch.object(core, 'execute', side_effect=self.external_tool):
            return runner.verify_artifact(self.apk, {}, reference, built_here)

    def test_external_artifact_without_independent_certificate_cannot_proceed(self):
        with self.assertRaises(core.Blocked):
            self.verify()
        self.assertFalse(any(command[0] == 'git' for command in self.commands))

    def test_external_artifact_with_wrong_certificate_is_rejected(self):
        with self.assertRaises(core.Blocked):
            self.verify(reference='b' * 64)

    def test_matching_external_artifact_records_identity_without_claiming_local_build(self):
        facts = self.verify(reference='a' * 64)
        self.assertEqual(facts['release_certificate_reference'], 'MATCHED')
        self.assertEqual(facts['provenance'], 'external_artifact_reference_matched')
        self.assertIsNone(facts['source_commit'])
        self.assertFalse(any(command[0] == 'git' for command in self.commands))
        self.assertTrue(facts['signature_valid'])
        self.assertNotIn('native_profile', facts)

    def test_local_build_requires_manifest_version_and_records_unavailable_independent_reference(self):
        facts = self.verify(built_here=True)
        self.assertEqual(facts['version'], '0.1.0')
        self.assertEqual(facts['version_code'], 1)
        self.assertEqual(facts['release_certificate_reference'], 'UNAVAILABLE')
        self.assertEqual(facts['provenance'], 'built_from_recorded_commit')
        self.assertEqual(facts['source_commit'], 'f' * 40)
        self.assertTrue(facts['source_tree_clean'])
        self.assertIn('native_profile', facts)
        self.assertFalse(facts['debuggable'])

    def test_local_build_does_not_attribute_dirty_sources_to_head_commit(self):
        self.git_status = ' M flutter/lib/main.dart\n?? synthetic-untracked-source.dart\n'

        facts = self.verify(built_here=True)

        self.assertEqual(facts['provenance'], 'built_from_dirty_worktree_commit_unavailable')
        self.assertIsNone(facts['source_commit'])
        self.assertFalse(facts['source_tree_clean'])
        self.assertNotIn('synthetic-untracked-source.dart', json.dumps(facts))

    def test_local_build_manifest_mismatch_or_missing_version_is_rejected(self):
        for text in ('version: 0.1.0+2\n', 'name: synthetic\n'):
            with self.subTest(text=text):
                (self.root / 'flutter/pubspec.yaml').write_text(text)
                with self.assertRaises(core.Blocked):
                    self.verify(built_here=True)

    def test_missing_or_invalid_apk_is_rejected_before_external_tool_execution(self):
        self.apk.unlink()
        with self.assertRaises(core.Blocked):
            self.verify()
        self.apk.write_bytes(b'not a ZIP container')
        with self.assertRaises(core.Blocked):
            self.verify()
        self.assertEqual(self.commands, [])

    def test_wrong_metadata_or_missing_native_library_never_reaches_signer(self):
        for mutation in ('package', 'library'):
            with self.subTest(mutation=mutation):
                self.commands = []
                if mutation == 'package':
                    self.badging = self.badging.replace('com.argusromtoolkit.argus', 'foreign.app')
                else:
                    self.badging = self.badging.replace('foreign.app', 'com.argusromtoolkit.argus')
                    self.entries.pop()
                    self.write_apk()
                with self.assertRaises(core.Blocked):
                    self.verify(reference='a' * 64)
                self.assertFalse(any(command[0] == 'apksigner' for command in self.commands))


class ToolAndSigningTests(unittest.TestCase):
    """Resolve only generated local tool/config fixtures; never inspect owner secrets."""
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.repository = self.root / 'repository'
        self.repository.mkdir()
        self.source = self.root / 'synthetic-signing.env'

    def write_signing(self, text):
        self.source.write_text(text)
        self.source.chmod(0o600)

    def test_loader_ignores_comments_exports_unknown_and_preserves_literal_expressions(self):
        self.write_signing('# synthetic input\n\nexport ARGUS_RELEASE_KEY_ALIAS=synthetic\n'
                           'ARGUS_RELEASE_KEY_PASSWORD="$HOME/literal" # comment\n'
                           'ignored malformed line\nOTHER_SECRET=discarded\n')
        environment = runner.load_signing(self.source, {'BASE': 'preserved'}, repository=self.repository)
        self.assertEqual(environment, {'BASE': 'preserved', 'ARGUS_RELEASE_KEY_ALIAS': 'synthetic',
                                       'ARGUS_RELEASE_KEY_PASSWORD': '$HOME/literal'})

    def test_unquoted_spaces_empty_and_unterminated_values_fail_without_secret_text(self):
        for value in ('synthetic private value', '', "'synthetic-private"):
            with self.subTest(value=value):
                self.write_signing('ARGUS_RELEASE_KEY_PASSWORD=' + value + '\n')
                with self.assertRaises(core.Blocked) as error:
                    runner.load_signing(self.source, {}, repository=self.repository)
                self.assertNotIn('synthetic-private', str(error.exception))

    def test_loader_rejects_symlink_oversize_nonregular_and_foreign_owner(self):
        self.write_signing('ARGUS_RELEASE_KEY_ALIAS=synthetic\n')
        link = self.root / 'link.env'
        link.symlink_to(self.source)
        with self.assertRaises(core.Blocked):
            runner.load_signing(link, {}, repository=self.repository)
        self.write_signing('#' * 16385)
        with self.assertRaises(core.Blocked):
            runner.load_signing(self.source, {}, repository=self.repository)
        directory = self.root / 'directory.env'
        directory.mkdir(mode=0o600)
        with self.assertRaises(core.Blocked):
            runner.load_signing(directory, {}, repository=self.repository)
        self.write_signing('ARGUS_RELEASE_KEY_ALIAS=synthetic\n')
        with patch.object(runner.os, 'getuid', return_value=self.source.stat().st_uid + 1):
            with self.assertRaises(core.Blocked):
                runner.load_signing(self.source, {}, repository=self.repository)

    def test_loader_rejects_non_utf8_input_without_private_location(self):
        self.source.write_bytes(b'\xff')
        self.source.chmod(0o600)
        with self.assertRaises(core.Blocked) as error:
            runner.load_signing(self.source, {}, repository=self.repository)
        self.assertNotIn(str(self.root), str(error.exception))

    def test_default_environment_is_preserved_without_importing_unknown_config_fields(self):
        self.write_signing('ARGUS_RELEASE_KEY_ALIAS=synthetic\nOTHER=discarded\n')
        with patch.dict(os.environ, {'BASE': 'preserved'}, clear=True):
            environment = runner.load_signing(self.source, repository=self.repository)
        self.assertEqual(environment, {'BASE': 'preserved', 'ARGUS_RELEASE_KEY_ALIAS': 'synthetic'})

    def test_trusted_source_accepts_only_four_null_delimited_variables(self):
        self.write_signing('# synthetic trusted input\n')
        with patch.object(core, 'execute', return_value='path\0store\0alias\0key\0'):
            environment = runner.load_signing(self.source, {'BASE': 'preserved'},
                                              repository=self.repository, source_trusted=True)
        self.assertEqual(environment['BASE'], 'preserved')
        self.assertEqual(environment['ARGUS_RELEASE_KEY_PASSWORD'], 'key')
        self.assertEqual(len(environment), 5)
        for output in ('too-few\0', 'path\0store\0alias\0key', 'path\0store\0alias\0key\0extra\0'):
            with self.subTest(output=output), patch.object(core, 'execute', return_value=output):
                with self.assertRaises(core.Blocked):
                    runner.load_signing(self.source, {}, repository=self.repository, source_trusted=True)

    def test_missing_pinned_ndk_or_unreadable_sdk_pin_is_blocked(self):
        flutter = self.repository / 'flutter'
        flutter.mkdir()
        extension = flutter / '.fvm/flutter_sdk/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt'
        extension.parent.mkdir(parents=True)
        for pin, text in (('malformed', ''), ('{}', ''), ('{"flutter":"synthetic"}', 'no NDK declaration'),
                          ('{"flutter":"synthetic"}', 'val ndkVersion: String = "28.2"')):
            with self.subTest(pin=pin, text=text):
                (flutter / '.fvmrc').write_text(pin)
                extension.write_text(text)
                with patch.object(runner, 'ROOT', self.repository):
                    with self.assertRaises(core.Blocked):
                        runner.build_environment({'ANDROID_HOME': str(self.root / 'sdk'),
                                                  'FVM_CACHE_PATH': str(self.root / 'cache')})

    def test_explicit_ndk_skips_sdk_discovery_and_respects_sdk_root(self):
        environment = {'ANDROID_NDK_HOME': '/synthetic/ndk',
                       'ANDROID_SDK_ROOT': '/synthetic/sdk'}
        with patch.object(runner, 'ROOT', self.repository):
            resolved = runner.build_environment(environment)
        self.assertEqual(resolved['ANDROID_NDK_HOME'], '/synthetic/ndk')
        self.assertEqual(resolved['ANDROID_HOME'], '/synthetic/sdk')
        self.assertNotIn('ANDROID_HOME', environment)

    def test_explicit_ndk_uses_default_sdk_home_without_reading_owner_config(self):
        with patch.object(runner.Path, 'home', return_value=self.root):
            environment = runner.build_environment({'ANDROID_NDK_HOME': '/synthetic/ndk'})
        self.assertEqual(environment['ANDROID_HOME'], str(self.root / 'Library/Android/sdk'))

    def test_artifact_tool_resolution_prefers_path_then_sdk_and_blocks_missing_tools(self):
        with patch.object(runner.shutil, 'which', return_value='/synthetic/bin/aapt2'):
            self.assertEqual(runner.build_tool('aapt2', {}), '/synthetic/bin/aapt2')
        tool = self.root / 'sdk/build-tools/35.0/aapt2'
        tool.parent.mkdir(parents=True)
        tool.write_bytes(b'synthetic tool; never executed')
        with patch.object(runner.shutil, 'which', return_value=None), \
                patch.object(runner.Path, 'home', return_value=self.root):
            self.assertEqual(runner.build_tool('aapt2', {'ANDROID_SDK_ROOT': str(self.root / 'sdk')}), str(tool))
            with self.assertRaises(core.Blocked):
                runner.build_tool('missing-tool', {'ANDROID_HOME': str(self.root / 'sdk')})


class CLITests(unittest.TestCase):
    """Exercise real argument parsing and orchestration without external commands."""
    def setUp(self):
        self.harness = OrchestrationTests('test_missing_artifact_choice_cannot_mutate')
        self.harness.setUp()
        self.addCleanup(self.harness.doCleanups)

    def invoke(self, options=(), ui_action=None):
        harness = self.harness
        argv = ['qualification-runner', '--device', 'selected', '--adb', 'fake-adb',
                '--fixtures', str(harness.collection), *options]
        output = io.StringIO()
        with patch.dict(os.environ, {}, clear=True), patch.object(sys, 'argv', argv), \
                patch.object(sys, 'stdout', output), \
                patch.object(core, 'Device', return_value=harness.device), \
                patch.object(runner, 'verify_artifact', return_value={'signature_valid': True}), \
                patch('ui.run_ui_scenarios', side_effect=ui_action), \
                patch('ui.library_controls_probe'), patch('ui.surface_lifecycle_probe'), \
                patch('ui.scaling_probe'):
            code = runner.main()
        return code, json.loads(output.getvalue())

    def test_missing_artifact_choice_prints_blocked_report_and_returns_exit_two(self):
        code, report = self.invoke()
        self.assertEqual(code, 2)
        self.assertTrue(report['blockers'])
        self.assertFalse(report['device_mutations'])
        self.assertEqual(self.harness.transport.mutations(), [])
        self.harness.assert_owner_untouched(report)

    def test_preflight_without_blocker_still_exits_two_for_unexecuted_scenarios(self):
        code, report = self.invoke(['--preflight-only'])
        self.assertEqual(report['blockers'], [])
        self.assertEqual(code, 2)
        self.assertTrue(all(row['automation_status'] == 'BLOCKED' for row in report['scenarios'].values()))
        self.assertFalse(report['device_mutations'])

    def test_successful_preparation_with_unexecuted_ui_never_returns_false_green(self):
        code, report = self.invoke(['--apk', str(self.harness.apk), '--retain-fixtures-for-owner'])
        self.assertEqual(code, 2)
        self.assertEqual(report['blockers'], [])
        self.assertTrue(report['app_preparation']['fresh_state_confirmed'])
        self.assertEqual(report['device_fixture_cleanup'], 'RETAINED FOR OWNER CHECKPOINTS')
        self.harness.assert_owner_untouched(report)

    def test_failed_ui_expectation_returns_exit_two_without_discarding_observation(self):
        def failed(device, rows, summary):
            core.assertion(rows['AND-02'], 'record_consistency', False, 'Observed incorrect record')
        code, report = self.invoke(['--apk', str(self.harness.apk)], ui_action=failed)
        self.assertEqual(code, 2)
        self.assertEqual(report['scenarios']['AND-02']['automation_status'], 'FAIL')
        self.assertEqual(report['scenarios']['AND-02']['assertions'][-1]['detail'], 'Observed incorrect record')
        self.harness.assert_owner_untouched(report)

    def test_sigterm_handler_reports_interruption_cleans_and_restores_previous_handler(self):
        previous = signal.getsignal(signal.SIGTERM)
        def interrupted(device, rows, summary):
            signal.getsignal(signal.SIGTERM)(signal.SIGTERM, None)
        code, report = self.invoke(['--apk', str(self.harness.apk)], ui_action=interrupted)
        self.assertEqual(code, 2)
        self.assertIn('Qualification interrupted; guarded cleanup attempted', report['blockers'])
        self.assertEqual(report['device_fixture_cleanup'], 'REMOVED')
        self.assertEqual(signal.getsignal(signal.SIGTERM), previous)
        self.harness.assert_owner_untouched(report)

    def test_invalid_cli_inputs_exit_two_before_orchestration(self):
        required = ['--device', 'selected', '--fixtures', '/synthetic/fixtures']
        cases = [[], ['--device', 'selected'], required + ['--fixture-limit-mib', '0'],
                 required + ['--fixture-limit-mib', '8193'],
                 required + ['--source-signing-env'],
                 required + ['--apk', '/synthetic.apk', '--build']]
        for options in cases:
            with self.subTest(options=options):
                output, errors = io.StringIO(), io.StringIO()
                with patch.dict(os.environ, {}, clear=True), \
                        patch.object(sys, 'argv', ['qualification-runner', *options]), \
                        patch.object(sys, 'stdout', output), patch.object(sys, 'stderr', errors), \
                        patch.object(runner, 'run', side_effect=AssertionError('Invalid CLI must not execute')):
                    with self.assertRaises(SystemExit) as error:
                        runner.main()
                self.assertEqual(error.exception.code, 2)
                self.assertEqual(output.getvalue(), '')
                self.assertIn('error:', errors.getvalue())

    def test_script_entrypoint_prints_preflight_report_and_exits_two(self):
        import runpy
        output = io.StringIO()
        harness = self.harness
        with patch.dict(os.environ, {}, clear=True), \
                patch.object(sys, 'argv', ['qualification-runner', '--device', 'selected',
                                         '--fixtures', str(harness.collection), '--preflight-only']), \
                patch.object(sys, 'stdout', output), \
                patch.object(core, 'Device', return_value=harness.device):
            with self.assertRaises(SystemExit) as error:
                runpy.run_path(runner.__file__, run_name='__main__')
        self.assertEqual(error.exception.code, 2)
        report = json.loads(output.getvalue())
        self.assertFalse(report['device_mutations'])
        self.harness.assert_owner_untouched(report)


class RunnerTests(unittest.TestCase):
    def test_existing_device_directory_blocks_upload_install_reset_and_cleanup(self):
        class Collision(Transport):
            def __call__(self, args, timeout=30, env=None):
                if remote_command(args)[:3] == ['shell', 'df', '-k']:
                    self.commands.append(args)
                    return 'Filesystem 1K-blocks Used Available Use% Mounted\n/synthetic 2097152 0 1048576 0% /sdcard\n'
                if 'mkdir' in args:
                    self.commands.append(args)
                    raise core.Blocked('Test directory already exists')
                return super().__call__(args, timeout, env)
        class Inventory:
            def summary(self):
                return {'classes':{}, 'selected_ready':True}
            def stage(self, destination, max_bytes):
                destination.mkdir()
                return {'status':'ok','staged_bundles':1,'staged_bytes':10}
        transport = Collision()
        device = core.Device('adb','selected',transport)
        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / 'temporary.apk'
            apk.write_bytes(b'Synthetic artifact')
            args = Namespace(adb='adb',device='selected',fixtures=Path('/owned'),
                             fixture_limit_mib=1,signing_env=None,source_signing_env=False,
                             certificate_sha256=None,preflight_only=False,build=False,apk=apk)
            with patch.dict(os.environ, {}, clear=True), \
                    patch.object(core,'Device',return_value=device), \
                    patch('fixtures.inspect_fixtures',return_value=Inventory()), \
                    patch.object(runner,'verify_artifact',return_value={'signature_valid':True}):
                report=runner.run(args)
        self.assertFalse(report['device_mutations'])
        self.assertTrue(report['blockers'])
        self.assertTrue(any('mkdir' in command for command in transport.commands))
        for word in ('install','push','clear','rm'):
            self.assertFalse(any(word in command for command in transport.commands))

    def test_safe_generated_fixtures_have_independent_positive_and_negative_structure(self):
        with tempfile.TemporaryDirectory() as directory:
            runner.add_safe_fixtures(Path(directory))
            from fixtures import inspect_fixtures
            summary=inspect_fixtures(Path(directory).resolve()).summary()
            self.assertEqual(summary['classes']['nes']['structurally_validated'],1)
            self.assertEqual(summary['classes']['nes']['invalid'],1)

    def test_explicit_trusted_source_resolves_shell_assignments_without_exposing_other_fields(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'signing.env'
            source.write_text('ARGUS_RELEASE_KEYSTORE="$HOME/existing-release.jks"\n'
                              'ARGUS_RELEASE_STORE_PASSWORD=secret\n'
                              'ARGUS_RELEASE_KEY_ALIAS=release\n'
                              'ARGUS_RELEASE_KEY_PASSWORD=secret\n'
                              'export OTHER_SECRET=never_import\n')
            source.chmod(0o600)
            env = runner.load_signing(source, {'HOME': directory}, source_trusted=True)
            self.assertEqual(env['ARGUS_RELEASE_KEYSTORE'], directory + '/existing-release.jks')
            self.assertNotIn('OTHER_SECRET', env)

    def test_fixture_prerequisites_do_not_become_release_or_manual_pass(self):
        rows = core.scenario_rows()
        runner.annotate_fixtures(rows, {'classes': {'nes': {'candidates': 2,
            'structurally_validated': 1, 'header_validated': 0}}})
        row = rows['CNT-01']
        self.assertEqual(row['assertions'][0]['status'], 'PASS')
        self.assertEqual(row['automation_status'], 'NOT RUN')
        self.assertEqual(row['owner_qualification_status'], 'NOT RUN')

    def test_ndk_resolution_uses_pinned_sdk_cache_when_project_symlink_is_absent(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'flutter').mkdir()
            (root / 'flutter/.fvmrc').write_text('{"flutter":"3.44.7"}')
            extension = root / 'cache/versions/3.44.7/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt'
            extension.parent.mkdir(parents=True)
            extension.write_text('val ndkVersion: String = "28.2"')
            (root / 'sdk/ndk/28.2').mkdir(parents=True)
            (root / 'sdk/ndk/99.0').mkdir()
            with patch.object(runner, 'ROOT', root):
                env = runner.build_environment({'FVM_CACHE_PATH':str(root / 'cache'),
                                                'ANDROID_HOME':str(root / 'sdk')})
            self.assertEqual(env['ANDROID_NDK_HOME'], str(root / 'sdk/ndk/28.2'))

    def test_signing_loader_never_executes_shell_and_only_imports_four_fields(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'signing.env'
            marker = Path(directory) / 'executed'
            source.write_text('ARGUS_RELEASE_KEYSTORE=/external/key\n'
                              'ARGUS_RELEASE_STORE_PASSWORD="$(touch ' + str(marker) + ')"\n'
                              'ARGUS_RELEASE_KEY_ALIAS=release\n'
                              "ARGUS_RELEASE_KEY_PASSWORD='literal value'\n"
                              'OTHER_SECRET=ignored\n')
            source.chmod(0o600)
            env = runner.load_signing(source, {})
            self.assertFalse(marker.exists())
            self.assertNotIn('OTHER_SECRET', env)
            self.assertEqual(env['ARGUS_RELEASE_KEY_PASSWORD'], 'literal value')

    def test_signing_loader_rejects_shared_permissions_and_in_repo_location(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'signing.env'
            source.write_text('ARGUS_RELEASE_KEY_ALIAS=release\n')
            source.chmod(0o644)
            with self.assertRaises(core.Blocked):
                runner.load_signing(source, {})
            source.chmod(0o600)
            with self.assertRaises(core.Blocked):
                runner.load_signing(source, {}, repository=Path(directory))

    def test_signing_loader_reports_missing_file_without_private_location(self):
        with self.assertRaises(core.Blocked) as error:
            runner.load_signing(Path('/missing/private/signing.env'), {})
        self.assertNotIn('/missing', str(error.exception))

    def test_blocking_prerequisite_preserves_owner_results_and_prior_failures(self):
        rows = core.scenario_rows()
        core.assertion(rows['AND-02'], 'correct-record', False, 'Wrong record')
        runner.block_remaining(rows, 'Release prerequisite unavailable')
        self.assertEqual(rows['AND-02']['automation_status'], 'FAIL')
        self.assertEqual(rows['AND-01']['automation_status'], 'BLOCKED')
        self.assertTrue(all(row['owner_qualification_status'] == 'NOT RUN' for row in rows.values()))


class DensityProbeDevice:
    """Small in-memory transport for the opt-in density probe contract."""

    def __init__(self):
        self.mode = 'default'
        self.physical_density = 320
        self.density_override = None
        self.writes = []
        self.now = 0.0
        self.clock = lambda: self.now
        self.fail_restore = False

    def shell(self, *args, mutating=False, timeout=30):
        if args[:3] == ('appops', 'get', core.PACKAGE):
            return f'MANAGE_EXTERNAL_STORAGE: {self.mode}\n'
        if args[:2] == ('appops', 'set'):
            self.mode = args[-1]
        if args[:2] == ('wm', 'size'):
            return 'Physical size: 1280x960\n'
        if args[:2] == ('wm', 'density'):
            if mutating:
                self.writes.append(args[-1])
                if self.fail_restore and args[-1] == 'reset':
                    return 'Success\n'
                self.density_override = None if args[-1] == 'reset' else int(args[-1])
                return 'Success\n'
            output = f'Physical density: {self.physical_density}\n'
            if self.density_override is not None:
                output += f'Override density: {self.density_override}\n'
            return output
        return 'Success\n'


class DensityProbeTests(unittest.TestCase):
    def test_expanded_density_probe_runs_once_inside_the_verified_allow_window(self):
        device = DensityProbeDevice()
        access = core.StorageAccessSnapshot(device)
        calls = []

        with access:
            access.configure()
            result = runner.expanded_density_probe(
                device, access,
                lambda deadline, display: calls.append((deadline, display)) or 'observed')

        self.assertEqual(len(calls), 1)
        self.assertGreater(calls[0][0], 0)
        self.assertEqual(calls[0][1]['density_dpi'], 240)
        self.assertEqual(calls[0][1]['logical_width_dp'], 853)
        self.assertEqual(result['probe_result'], 'observed')
        self.assertEqual(result['density_cleanup'], 'RESTORED')
        self.assertEqual(device.writes, ['240', 'reset'])
        self.assertEqual(device.mode, 'default')
        self.assertFalse(access.active_window)
        self.assertFalse(access.configured)

    def test_probe_slot_cannot_be_reused_within_one_allow_window(self):
        device = DensityProbeDevice()
        access = core.StorageAccessSnapshot(device)
        calls = []

        with access:
            access.configure()
            runner.expanded_density_probe(
                device, access, lambda *_: calls.append('first') or 'observed')
            with self.assertRaises(core.Blocked):
                runner.expanded_density_probe(
                    device, access, lambda *_: calls.append('duplicate'))

        self.assertEqual(calls, ['first'])
        self.assertEqual(device.writes, ['240', 'reset'])

    def test_probe_refuses_when_storage_access_changes_after_configuration(self):
        device = DensityProbeDevice()
        access = core.StorageAccessSnapshot(device)
        calls = []

        with access:
            access.configure()
            device.mode = 'deny'
            with self.assertRaises(core.Blocked):
                runner.expanded_density_probe(
                    device, access, lambda *_: calls.append('called'))

        self.assertEqual(calls, [])
        self.assertEqual(device.writes, [])
        self.assertEqual(device.mode, 'default')

    def test_callback_failure_restores_density_then_propagates(self):
        device = DensityProbeDevice()
        access = core.StorageAccessSnapshot(device)

        with self.assertRaisesRegex(core.Blocked, 'synthetic callback failure'):
            with access:
                access.configure()

                def fail(*_):
                    raise core.Blocked('synthetic callback failure')

                runner.expanded_density_probe(device, access, fail)

        self.assertEqual(device.writes, ['240', 'reset'])
        self.assertEqual(device.mode, 'default')

    def test_callback_failure_reports_density_restoration_blocker(self):
        device = DensityProbeDevice()
        device.fail_restore = True
        access = core.StorageAccessSnapshot(device)

        with self.assertRaisesRegex(core.Blocked, 'owner restoration'):
            with access:
                access.configure()
                runner.expanded_density_probe(
                    device, access,
                    lambda *_: (_ for _ in ()).throw(core.Blocked('synthetic callback failure')))

        self.assertEqual(device.writes, ['240', 'reset'])
        self.assertEqual(device.density_override, 240)
        self.assertEqual(device.mode, 'default')

    def test_callback_interruption_restores_density_and_propagates(self):
        device = DensityProbeDevice()
        access = core.StorageAccessSnapshot(device)

        with self.assertRaises(InterruptedError):
            with access:
                access.configure()
                runner.expanded_density_probe(
                    device, access, lambda *_: (_ for _ in ()).throw(InterruptedError()))

        self.assertEqual(device.writes, ['240', 'reset'])
        self.assertEqual(device.mode, 'default')

    def test_direct_helper_sigterm_restores_exact_density_and_previous_handler(self):
        previous_handler = signal.getsignal(signal.SIGTERM)
        for original in (None, 280):
            with self.subTest(original=original):
                device = DensityProbeDevice()
                device.density_override = original
                access = core.StorageAccessSnapshot(device)

                def terminate(_deadline, _display):
                    os.kill(os.getpid(), signal.SIGTERM)

                with self.assertRaises(InterruptedError):
                    with access:
                        access.configure()
                        runner.expanded_density_probe(device, access, terminate)

                expected_restore = 'reset' if original is None else str(original)
                self.assertEqual(device.writes, ['240', expected_restore])
                self.assertEqual(device.density_override, original)
                self.assertEqual(device.mode, 'default')
                self.assertEqual(signal.getsignal(signal.SIGTERM), previous_handler)

    def test_sigterm_during_density_restoration_is_reported_after_exact_restore(self):
        previous_handler = signal.getsignal(signal.SIGTERM)

        class TerminateDuringRestore(DensityProbeDevice):
            sent = False

            def shell(inner, *args, mutating=False, timeout=30):
                result = super(TerminateDuringRestore, inner).shell(
                    *args, mutating=mutating, timeout=timeout)
                if (not inner.sent and mutating and args[:2] == ('wm', 'density')
                        and args[-1] == '280'):
                    inner.sent = True
                    os.kill(os.getpid(), signal.SIGTERM)
                return result

        device = TerminateDuringRestore()
        device.density_override = 280
        access = core.StorageAccessSnapshot(device)
        snapshots = []
        original_snapshot = core.DisplayDensitySnapshot

        class TrackedSnapshot(original_snapshot):
            def __init__(inner, *args, **kwargs):
                super().__init__(*args, **kwargs)
                snapshots.append(inner)

        with patch.object(core, 'DisplayDensitySnapshot', TrackedSnapshot):
            with self.assertRaises(InterruptedError):
                with access:
                    access.configure()
                    runner.expanded_density_probe(device, access, lambda *_: 'observed')

        self.assertTrue(device.sent)
        self.assertEqual(device.writes, ['240', '280'])
        self.assertEqual(device.density_override, 280)
        self.assertEqual(snapshots[0].cleanup_status, 'RESTORED')
        self.assertEqual(device.mode, 'default')
        self.assertEqual(signal.getsignal(signal.SIGTERM), previous_handler)

    def test_direct_helper_sigterm_reports_failed_density_restoration(self):
        previous_handler = signal.getsignal(signal.SIGTERM)
        device = DensityProbeDevice()
        device.fail_restore = True
        access = core.StorageAccessSnapshot(device)

        def terminate(_deadline, _display):
            os.kill(os.getpid(), signal.SIGTERM)

        with self.assertRaises(InterruptedError) as caught:
            with access:
                access.configure()
                runner.expanded_density_probe(device, access, terminate)

        self.assertEqual(
            getattr(caught.exception, 'density_cleanup_blocker', None),
            'Original display-density state requires owner restoration')
        self.assertEqual(device.writes, ['240', 'reset'])
        self.assertEqual(device.density_override, 240)
        self.assertEqual(device.mode, 'default')
        self.assertEqual(signal.getsignal(signal.SIGTERM), previous_handler)

    def test_probe_deadline_is_cooperative_and_late_results_are_rejected(self):
        device = DensityProbeDevice()
        access = core.StorageAccessSnapshot(device)

        with self.assertRaisesRegex(core.Blocked, 'exceeded its bounded deadline'):
            with access:
                access.configure()

                def return_late(deadline, _display):
                    device.now = deadline + 1
                    return 'too late'

                runner.expanded_density_probe(
                    device, access, return_late, budget=5)

        self.assertEqual(device.writes, ['240', 'reset'])
        self.assertEqual(device.mode, 'default')

    def test_expanded_density_probe_refuses_to_run_outside_configured_allow_window(self):
        device = DensityProbeDevice()
        access = core.StorageAccessSnapshot(device)
        calls = []

        with self.assertRaises(core.Blocked):
            runner.expanded_density_probe(
                device, access, lambda *_: calls.append('called'))

        self.assertEqual(calls, [])
        self.assertEqual(device.writes, [])


if __name__ == '__main__':
    unittest.main()
