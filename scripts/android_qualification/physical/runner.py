"""Orchestrate physical Android Release qualification without manual verdicts.

Only stdout carries the sanitized execution report. The owning delegation's
RESULT.json is the sole durable result; this runner never edits that ledger or
stores raw device/UI output. Private fixture staging is automatically removed.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import zipfile
from datetime import datetime, timezone

from scripts.android_qualification.physical import core

ROOT = Path(__file__).resolve().parents[3]
SIGNING_FIELDS = ('ARGUS_RELEASE_KEYSTORE', 'ARGUS_RELEASE_STORE_PASSWORD',
                  'ARGUS_RELEASE_KEY_ALIAS', 'ARGUS_RELEASE_KEY_PASSWORD')


class LiveExecutionUnavailable(RuntimeError):
    """Signal that physical execution awaits isolated packaging and admission."""


def load_signing(path, environment=None, repository=ROOT, source_trusted=False,
                 command_executor=None):
    """Read four literal dotenv fields from an owner-only external file.

    Shell expressions and variable expansion are never evaluated. This avoids
    giving a signing file executable authority or exposing its contents in logs.
    """
    env = dict(os.environ if environment is None else environment)
    try:
        resolved = path.resolve(strict=True)
        information = resolved.stat()
        if (resolved.is_relative_to(repository.resolve()) or path.is_symlink()
                or information.st_uid != os.getuid()
                or stat.S_IMODE(information.st_mode) != 0o600
                or information.st_size > 16384 or not resolved.is_file()):
            raise core.Blocked('Signing input must be an owner-only regular file outside the repository')
        if source_trusted:
            # This mode requires explicit trust in an owner-provisioned file.
            # The caller must provide its own execution boundary; the active
            # package does not construct a subprocess transport.
            if not callable(command_executor):
                raise core.Blocked('Trusted signing input execution is unavailable')
            script = ('set +x; source "$1" >/dev/null 2>&1 || exit 1; set +x; '
                      "printf '%s\\0' " + ' '.join('"${' + key + '-}"' for key in SIGNING_FIELDS))
            values = command_executor(
                ['bash', '-c', script, 'trusted-signing-input', str(resolved)], env=env
            ).split('\0')
            if len(values) != 5 or values[-1] != '':
                raise core.Blocked('Trusted signing input did not yield exactly four variables')
            env.update(zip(SIGNING_FIELDS, values[:-1]))
            return env
        text = resolved.read_text()
    except (OSError, UnicodeError):
        raise core.Blocked('External signing file is missing or unreadable') from None
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        if line.startswith('export '):
            line = line[7:]
        name, separator, value = line.partition('=')
        if not separator or name.strip() not in SIGNING_FIELDS:
            continue
        try:
            parts = shlex.split(value, comments=True)
        except ValueError:
            raise core.Blocked('Signing input contains an invalid literal value') from None
        if len(parts) != 1:
            raise core.Blocked('Signing values containing spaces must be quoted')
        env[name.strip()] = parts[0]
    return env


def block_remaining(rows, reason):
    """Block unproven scenarios without overwriting failures or owner results."""
    for row in rows.values():
        if row['automation_status'] not in ('PASS', 'FAIL'):
            row['automation_status'] = 'BLOCKED'
            row['reason'] = reason


def block_unrun_after_ui_failure(rows):
    """Stop later UI probes after an explicit product failure observation."""
    for row in rows.values():
        if row['automation_status'] == 'NOT RUN':
            row['automation_status'] = 'BLOCKED'
            row['reason'] = 'Later UI probes stopped after an explicit product failure.'


def has_ui_failure(rows):
    """Return whether any scenario contains an explicit product failure."""
    return any(row['automation_status'] == 'FAIL' for row in rows.values())


def record_ui_cleanup_failure(rows, scenario, product_failure_observed):
    """Retain cleanup failure and any stronger product-failure observation."""
    if scenario not in rows:
        return
    status = 'FAIL' if product_failure_observed else 'BLOCKED'
    detail = ('The Release UI reported an operation failure before cleanup failed.'
              if product_failure_observed else
              'Accessibility capture cleanup failed; owner follow-up is required.')
    row = rows[scenario]
    row.setdefault('assertions', []).append({
        'check': 'ui_capture_cleanup', 'status': status, 'detail': detail})
    if row.get('automation_status') != 'FAIL' or status == 'FAIL':
        row['automation_status'] = status
        row['reason'] = detail


def scenario_unobserved(rows, scenario):
    """Allow a partial probe only when its scenario has no primary evidence."""
    row = rows[scenario]
    return row['automation_status'] == 'NOT RUN' and not row.get('assertions')


def expanded_density_probe(device, access_snapshot, probe, *, budget=120):
    """Run one cooperative, deadline-bounded probe at verified expanded width.

    The caller must hold the same configured storage-access snapshot for the
    entire call. The callback receives the monotonic deadline and verified
    display facts, and must honor that deadline for every UI wait. Density is
    restored before this function returns or propagates a callback failure.
    """
    if (access_snapshot.device is not device or not access_snapshot.active_window
            or not access_snapshot.configured or access_snapshot.density_probe_used
            or not callable(probe)):
        raise core.Blocked('Expanded-width probe requires one unused configured storage-access window')
    if access_snapshot.mode() != 'allow':
        raise core.Blocked('Expanded-width probe requires verified Argus storage access')

    # Claim the one probe slot before changing display state. A failed setup
    # still consumes the slot so retries cannot duplicate UI mutations.
    access_snapshot.density_probe_used = True
    display_snapshot = core.DisplayDensitySnapshot(device, budget=budget)
    try:
        with display_snapshot:
            display = display_snapshot.configure_expanded()
            if display_snapshot.clock() >= display_snapshot.deadline:
                raise core.Blocked('Expanded-width probe deadline expired before UI observation')
            probe_result = probe(display_snapshot.deadline, display)
            if display_snapshot.clock() >= display_snapshot.deadline:
                raise core.Blocked('Expanded-width UI observation exceeded its bounded deadline')
    except BaseException as error:
        if display_snapshot.changed and display_snapshot.cleanup_status != 'RESTORED':
            blocker = 'Original display-density state requires owner restoration'
            if isinstance(error, (KeyboardInterrupt, InterruptedError)):
                error.density_cleanup_blocker = blocker
                raise
            raise core.Blocked(blocker) from None
        raise

    if display_snapshot.changed and display_snapshot.cleanup_status != 'RESTORED':
        raise core.Blocked('Original display-density state requires owner restoration')
    return {'probe_result': probe_result,
            'density_cleanup': display_snapshot.cleanup_status}


def annotate_fixtures(rows, summary):
    """Attach host prerequisites without claiming Android content behavior."""
    mapping = {'CNT-01': ('nes',), 'CNT-02': ('iso',), 'CNT-03': ('cue',),
               'CNT-04': ('m3u',), 'CNT-05': ('zip', 'seven_zip'),
               'CNT-06': ('chd',), 'CNT-07': ('rvz', 'cso', 'wbfs')}
    for identifier, kinds in mapping.items():
        for kind in kinds:
            counts = summary.get('classes', {}).get(kind, {})
            structural = counts.get('structurally_validated', 0)
            header = counts.get('header_validated', 0)
            if structural or header:
                core.assertion(rows[identifier], 'host_fixture_' + kind, True,
                               f'Structurally checked={structural}; header-only={header}; device content behavior unverified')


def add_safe_fixtures(collection):
    """Create owned structural-positive and intentionally malformed probes.

    The positive cartridge is synthetic and establishes no provider identity.
    The negative bytes are never supplied by the owner's collection.
    """
    probes = collection / 'safe-probes'
    probes.mkdir()
    header = b'NES\x1a' + bytes((1, 0)) + bytes(10)
    (probes / 'synthetic.nes').write_bytes(header + bytes((index * 37 + 19) % 256 for index in range(16384)))
    (probes / 'malformed.nes').write_bytes(b'ARGUS intentionally malformed qualification probe')


def build_environment(environment):
    """Resolve the installed NDK matching the pinned Flutter SDK, not latest."""
    env = dict(environment)
    sdk = Path(env.get('ANDROID_SDK_ROOT') or env.get('ANDROID_HOME')
               or Path.home() / 'Library/Android/sdk')
    if not env.get('ANDROID_NDK_HOME'):
        try:
            pin = json.loads((ROOT / 'flutter/.fvmrc').read_text())['flutter']
            sdk_candidates = [ROOT / 'flutter/.fvm/flutter_sdk',
                              ROOT / '.fvm/flutter_sdk',
                              Path(env.get('FVM_CACHE_PATH', str(Path.home() / 'fvm'))) / 'versions' / pin]
            extension = next(root / 'packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt'
                             for root in sdk_candidates
                             if (root / 'packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt').is_file())
            match = re.search(r'ndkVersion: String = "([^"]+)"', extension.read_text())
        except (OSError, ValueError, KeyError, StopIteration):
            match = None
        if not match or not (sdk / 'ndk' / match[1]).is_dir():
            raise core.Blocked('Pinned Flutter NDK is unavailable; configure ANDROID_NDK_HOME')
        env['ANDROID_NDK_HOME'] = str(sdk / 'ndk' / match[1])
    env.setdefault('ANDROID_HOME', str(sdk))
    return env


def build_tool(name, env):
    direct = shutil.which(name, path=env.get('PATH'))
    if direct:
        return direct
    for root in (env.get('ANDROID_SDK_ROOT'), env.get('ANDROID_HOME'),
                 str(Path.home() / 'Library/Android/sdk')):
        if root:
            candidates = sorted(Path(root).glob('build-tools/*/' + name))
            if candidates:
                return str(candidates[-1])
    raise core.Blocked('Required Android artifact verification tool is unavailable')


def verify_artifact(apk, env, reference, built_here, *, command_executor):
    """Prove packaging, signature and available signing-identity provenance."""
    if not apk.is_file():
        raise core.Blocked('Signed Release APK is unavailable')
    try:
        with zipfile.ZipFile(apk) as archive:
            entries = archive.namelist()
    except (OSError, zipfile.BadZipFile):
        raise core.Blocked('Release artifact is not a readable APK') from None
    badging = command_executor([build_tool('aapt2', env), 'dump', 'badging', str(apk)])
    facts = core.check_metadata(badging, entries)
    signer = command_executor([build_tool('apksigner', env), 'verify', '--verbose',
                               '--print-certs', '--min-sdk-version', '30', str(apk)])
    facts['signature_valid'] = True
    facts['release_certificate_reference'] = core.check_certificate(signer, reference)
    if not built_here and facts['release_certificate_reference'] != 'MATCHED':
        raise core.Blocked('An external APK requires an independent Release certificate reference')
    if built_here:
        revision = command_executor(['git', '-C', str(ROOT), 'rev-parse', 'HEAD']).strip()
        working_tree = command_executor(['git', '-C', str(ROOT), 'status', '--porcelain',
                                         '--untracked-files=all'])
        facts['source_tree_clean'] = not working_tree.strip()
        facts['source_commit'] = revision if facts['source_tree_clean'] else None
        facts['provenance'] = ('built_from_recorded_commit' if facts['source_tree_clean']
                               else 'built_from_dirty_worktree_commit_unavailable')
    else:
        facts['source_commit'] = None
        facts['provenance'] = 'external_artifact_reference_matched'
    if built_here:
        version = re.search(r'^version: ([^\n]+)$', (ROOT / 'flutter/pubspec.yaml').read_text(), re.M)
        if not version or version[1] != f"{facts['version']}+{facts['version_code']}":
            raise core.Blocked('Release artifact version does not match the source manifest')
        facts['native_profile'] = 'existing repository bridge builder; no cargo --release flag'
    return facts


def private_apk_copy(source, directory):
    """Copy one stable APK into an owner-private directory for verification/install."""
    source = Path(source)
    directory = Path(directory)
    target = directory / 'release.apk'

    def identity(info):
        return (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns)

    try:
        before = source.stat()
        if not stat.S_ISREG(before.st_mode):
            raise core.Blocked('Signed Release APK must be a regular file')
        with source.open('rb') as original, target.open('xb') as copy:
            opened = os.fstat(original.fileno())
            if identity(opened) != identity(before):
                raise core.Blocked('Signed Release APK changed before private staging')
            remaining = before.st_size
            while remaining:
                chunk = original.read(min(1024 * 1024, remaining))
                if not chunk:
                    raise core.Blocked('Signed Release APK changed during private staging')
                copy.write(chunk)
                remaining -= len(chunk)
            if original.read(1):
                raise core.Blocked('Signed Release APK changed during private staging')
            after_open = os.fstat(original.fileno())
        after_path = source.stat()
        staged = target.stat()
        if (identity(after_open) != identity(before) or identity(after_path) != identity(before)
                or staged.st_size != before.st_size or not stat.S_ISREG(staged.st_mode)):
            raise core.Blocked('Signed Release APK changed during private staging')
        target.chmod(stat.S_IRUSR)
        return target
    except core.Blocked:
        raise
    except OSError:
        raise core.Blocked('Signed Release APK could not be copied to private verification staging') from None


def remove_private_apk(directory):
    """Remove only the staged APK and its empty private directory."""
    if directory is None:
        return True
    directory = Path(directory)
    try:
        (directory / 'release.apk').unlink(missing_ok=True)
        directory.rmdir()
        return True
    except OSError:
        return False


def run(args):
    """Fail closed; public production entry points cannot run the device flow."""
    raise LiveExecutionUnavailable('LIVE_EXECUTION_NOT_IMPLEMENTED')


def _run_with_test_dependencies(args, *, dependencies):
    """Exercise orchestration only with a test-supplied dependency bundle."""

    from scripts.android_qualification.physical.ui import UICleanupBlocked

    device = dependencies.device
    inspect_fixtures = dependencies.fixture_inspector
    run_ui_scenarios = dependencies.run_ui_scenarios
    library_controls_probe = dependencies.library_controls_probe
    surface_lifecycle_probe = dependencies.surface_lifecycle_probe
    scaling_probe = dependencies.scaling_probe
    report = {'timestamp_utc': datetime.now(timezone.utc).isoformat(),
              'scenarios': core.scenario_rows(), 'blockers': [],
              'device_mutations': False, 'settings_cleanup': 'NOT REQUIRED',
              'device_fixture_cleanup': 'NOT REQUIRED'}
    settings = None
    storage_access = None
    private_apk_directory = None
    verified_apk = None
    directory_created = False
    directory_creation_uncertain = False
    fixture_upload_confirmed = False
    try:
        report['device'] = device.preflight()
        volumes = device.shell('sm', 'list-volumes', 'public')
        report['removable_media'] = {'public_volume_count': sum(
            line.startswith('public:') for line in volumes.splitlines()),
            'genuine_unavailability_test': 'OWNER REQUIRED'}
        inventory = inspect_fixtures(args.fixtures, max_bytes=args.fixture_limit_mib * 1048576)
        report['fixtures'] = inventory.summary()
        annotate_fixtures(report['scenarios'], report['fixtures'])
        env = dict(os.environ)
        if args.signing_env:
            env = load_signing(args.signing_env, env, source_trusted=args.source_signing_env,
                               command_executor=dependencies.command_executor)
        report['signing'] = {'configured_fields': sum(bool(env.get(key)) for key in SIGNING_FIELDS),
                             'required_fields': 4,
                             'independent_certificate_reference': 'AVAILABLE' if args.certificate_sha256 else 'UNAVAILABLE'}
        if args.preflight_only:
            block_remaining(report['scenarios'], 'Preflight-only run; no Release observations executed')
            return report
        if args.build:
            if any(not env.get(key) for key in SIGNING_FIELDS):
                raise core.Blocked('Required Release signing configuration is unavailable')
            keystore = Path(env['ARGUS_RELEASE_KEYSTORE'])
            if not keystore.is_absolute() or not keystore.is_file():
                raise core.Blocked('External Release keystore is unavailable')
            env = build_environment(env)
            report['build'] = {'attempted': True, 'status': 'NOT RUN'}
            try:
                dependencies.command_executor(
                    ['bash', str(ROOT / 'scripts/build_android_release.sh')],
                    timeout=1800,
                    env=env,
                )
            except (core.Blocked, subprocess.TimeoutExpired):
                report['build']['status'] = 'FAIL'
                raise core.Blocked('Signed Release build failed or timed out; no device app state changed') from None
            report['build']['status'] = 'PASS'
            apk = ROOT / 'flutter/build/app/outputs/flutter-apk/app-release.apk'
        elif args.apk:
            apk = args.apk
        else:
            raise core.Blocked('Supply --build or a verified signed Release APK')
        private_apk_directory = Path(tempfile.mkdtemp(prefix='argus-qualification-apk-'))
        verified_apk = private_apk_copy(apk, private_apk_directory)
        report['artifact'] = verify_artifact(
            verified_apk, env, args.certificate_sha256, args.build,
            command_executor=dependencies.command_executor)
        # A verified artifact is required before any fixture or app-state change.
        settings = dependencies.settings_snapshot_factory(device)
        with settings, tempfile.TemporaryDirectory(prefix='argus-qualification-fixtures-') as staging:
            collection = Path(staging).resolve() / 'collection'
            report['staged_fixtures'] = inventory.stage(collection, args.fixture_limit_mib * 1048576)
            if (report['staged_fixtures']['status'] != 'ok'
                    or not report['staged_fixtures']['staged_bundles']):
                raise core.Blocked('No safely staged representative fixture set is available')
            add_safe_fixtures(collection)
            report['staged_fixtures']['synthetic_probes'] = 2
            capacity = device.shell('df', '-k', '/sdcard').splitlines()
            try:
                free_bytes = int(capacity[-1].split()[3]) * 1024
            except (ValueError, IndexError):
                raise core.Blocked('Available device fixture capacity could not be established') from None
            if free_bytes < report['staged_fixtures']['staged_bytes'] + 65536 + verified_apk.stat().st_size * 2 + 134217728:
                raise core.Blocked('Device has insufficient free space for bounded fixture and APK staging')
            # Exclusive creation is ownership proof. An existing directory is
            # never reused or recursively cleared, even at this known name.
            directory_creation_uncertain = True
            try:
                device.shell('mkdir', core.DEVICE_ROOT, mutating=True)
            except core.Blocked:
                # A command failure does not establish ownership. Preserve a
                # possible pre-existing directory, and report uncertainty.
                raise
            directory_creation_uncertain = False
            directory_created = True
            report['device_mutations'] = True
            device.run('push', str(collection), core.DEVICE_ROOT + '/fixtures', mutating=True, timeout=600)
            fixture_upload_confirmed = True
            installed = device.shell('pm', 'list', 'packages', core.PACKAGE).splitlines()
            report['app_preparation'] = {'previous_install_removed': False,
                                         'installed': False, 'fresh_state_confirmed': False}
            if 'package:' + core.PACKAGE in installed:
                if device.shell('pm', 'uninstall', core.PACKAGE, mutating=True).strip() != 'Success':
                    raise core.Blocked('Dedicated-device Argus uninstall did not confirm success')
                report['app_preparation']['previous_install_removed'] = True
            device.run('install', '-r', str(verified_apk), mutating=True, timeout=180)
            report['app_preparation']['installed'] = True
            if device.shell('pm', 'clear', core.PACKAGE, mutating=True).strip() != 'Success':
                raise core.Blocked('Argus fresh-state reset did not confirm success')
            report['app_preparation']['fresh_state_confirmed'] = True
            storage_access = core.StorageAccessSnapshot(device)
            with storage_access:
                storage_access.configure()
                report['app_preparation']['storage_access_configured'] = True
                run_ui_scenarios(device, report['scenarios'], report['staged_fixtures'])
                if has_ui_failure(report['scenarios']):
                    block_unrun_after_ui_failure(report['scenarios'])
                else:
                    # Use a partial probe only when the primary UI path did not
                    # already observe that scenario.
                    if scenario_unobserved(report['scenarios'], 'AND-02'):
                        library_controls_probe(device, report['scenarios'])
                    if has_ui_failure(report['scenarios']):
                        block_unrun_after_ui_failure(report['scenarios'])

                    for scenario in ('AND-04', 'AND-05'):
                        if has_ui_failure(report['scenarios']):
                            break
                        if scenario_unobserved(report['scenarios'], scenario):
                            surface_lifecycle_probe(device, report['scenarios'], scenario)
                        if has_ui_failure(report['scenarios']):
                            block_unrun_after_ui_failure(report['scenarios'])

                    if not has_ui_failure(report['scenarios']):
                        for scale in ('1.3', '2.0'):
                            settings.put('system', 'font_scale', scale)
                            actual_scale = settings.read('system', 'font_scale')
                            check = 'font_scale_readback_' + scale.replace('.', '_')
                            row = report['scenarios']['UX-A03']
                            if actual_scale != scale:
                                row.setdefault('assertions', []).append({
                                    'check': check, 'status': 'BLOCKED',
                                    'detail': 'Requested font scale did not verify before geometry observation.'})
                                raise core.Blocked('Requested Android font scale did not verify')
                            core.assertion(row, check, True,
                                           'Requested font scale was read back before geometry observation.')
                            scaling_probe(device, report['scenarios'])
                            if has_ui_failure(report['scenarios']):
                                block_unrun_after_ui_failure(report['scenarios'])
                                break
    except UICleanupBlocked as error:
        reason = 'Accessibility capture cleanup failed; owner follow-up is required.'
        report['blockers'].append(reason)
        record_ui_cleanup_failure(report['scenarios'], error.scenario,
                                  error.product_failure_observed)
        if has_ui_failure(report['scenarios']):
            block_unrun_after_ui_failure(report['scenarios'])
        else:
            block_remaining(report['scenarios'], reason)
    except (core.Blocked, subprocess.TimeoutExpired) as error:
        reason = str(error) if isinstance(error, core.Blocked) else 'Bounded command timed out'
        report['blockers'].append(reason)
        block_remaining(report['scenarios'], reason)
    except (KeyboardInterrupt, InterruptedError) as error:
        report['blockers'].append('Qualification interrupted; guarded cleanup attempted')
        for attribute in ('density_cleanup_blocker', 'ui_cleanup_blocker'):
            blocker = getattr(error, attribute, None)
            if blocker and blocker not in report['blockers']:
                report['blockers'].append(blocker)
        ui_cleanup_blocker = getattr(error, 'ui_cleanup_blocker', None)
        ui_cleanup_scenario = getattr(error, 'ui_cleanup_scenario', None)
        if ui_cleanup_blocker:
            record_ui_cleanup_failure(
                report['scenarios'], ui_cleanup_scenario,
                getattr(error, 'ui_product_failure_observed', False))
        if has_ui_failure(report['scenarios']):
            block_unrun_after_ui_failure(report['scenarios'])
        else:
            block_remaining(report['scenarios'], 'Qualification interrupted')
    except OSError:
        reason = 'Host or device I/O failed; raw paths and output withheld'
        report['blockers'].append(reason)
        block_remaining(report['scenarios'], reason)
    finally:
        if settings:
            report['settings_cleanup'] = settings.cleanup_status
            if settings.cleanup_status == 'BLOCKED':
                report['blockers'].append('Android setting restoration requires owner follow-up')
        if storage_access:
            report['storage_access_cleanup'] = storage_access.cleanup_status
            if storage_access.cleanup_status == 'BLOCKED':
                report['blockers'].append('Argus storage access restoration requires owner follow-up')
        if directory_creation_uncertain:
            report['device_fixture_cleanup'] = 'BLOCKED'
            report['blockers'].append('Fixture directory creation outcome is uncertain; owner inspection required before cleanup')
        if directory_created and getattr(args, 'retain_fixtures_for_owner', False):
            if fixture_upload_confirmed:
                report['device_fixture_cleanup'] = 'RETAINED FOR OWNER CHECKPOINTS'
            else:
                report['device_fixture_cleanup'] = 'BLOCKED'
                report['blockers'].append(
                    'Fixture upload did not confirm; owned directory retained for owner inspection')
        elif directory_created:
            removed = False
            try:
                with core.cleanup_signals():
                    device.shell('rm', '-rf', core.DEVICE_ROOT, mutating=True, timeout=15)
                    removed = True
                report['device_fixture_cleanup'] = 'REMOVED'
            except (core.Blocked, KeyboardInterrupt, InterruptedError) as error:
                if removed:
                    report['device_fixture_cleanup'] = 'REMOVED'
                else:
                    report['device_fixture_cleanup'] = 'BLOCKED'
                    report['blockers'].append('Device cleanup requires owner follow-up')
                if isinstance(error, (KeyboardInterrupt, InterruptedError)):
                    report['blockers'].append('Qualification interrupted during bounded device cleanup')
                    block_remaining(report['scenarios'], 'Qualification interrupted')
        if not remove_private_apk(private_apk_directory):
            report['blockers'].append('Private APK staging cleanup requires owner follow-up')
    return report


def argument_parser():
    """Build the host-only parser for the retired physical runner interface."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True, help='Explicit USB ADB serial; never retained in evidence')
    parser.add_argument('--adb', default='adb')
    parser.add_argument('--fixtures', required=True, type=Path)
    parser.add_argument('--fixture-limit-mib', default=8192, type=int,
                        help='Positive per-bundle and total staging cap; default 8192 MiB')
    parser.add_argument('--signing-env', type=Path)
    parser.add_argument('--source-signing-env', action='store_true',
                        help='Explicitly trust and source the owner-provisioned external signing file')
    parser.add_argument('--certificate-sha256', default=os.environ.get('ARGUS_RELEASE_CERTIFICATE_SHA256'))
    parser.add_argument('--preflight-only', action='store_true')
    parser.add_argument('--retain-fixtures-for-owner', action='store_true',
                        help='Retain only the exclusively created test fixtures for immediate direct owner observations')
    artifacts = parser.add_mutually_exclusive_group()
    artifacts.add_argument('--build', action='store_true')
    artifacts.add_argument('--apk', type=Path)
    return parser


def parse_args(argv=None):
    """Validate runner options without constructing a device or executing work."""
    parser = argument_parser()
    args = parser.parse_args(argv)
    if not 0 < args.fixture_limit_mib <= 8192:
        parser.error('--fixture-limit-mib must be between 1 and 8192')
    if args.source_signing_env and not args.signing_env:
        parser.error('--source-signing-env requires --signing-env')
    return args


def main(argv=None):
    """Validate syntax, then fail closed until isolated admission is implemented."""
    parse_args(argv)
    print('LIVE_EXECUTION_NOT_IMPLEMENTED', file=sys.stderr)
    return 3


if __name__ == '__main__':
    raise SystemExit(main())
