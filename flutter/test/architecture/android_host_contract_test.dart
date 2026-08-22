import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<ProcessResult> runReleaseWrapper(
    Map<String, String> environment,
  ) async {
    final process = await Process.start(
      'bash',
      [File('../scripts/build_android_release.sh').absolute.path],
      workingDirectory: File('..').absolute.path,
      environment: environment,
    );
    final stdout = process.stdout.transform(utf8.decoder).join();
    final stderr = process.stderr.transform(utf8.decoder).join();
    final exitCode = await process.exitCode.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        process.kill();
        fail('release wrapper did not exit within the test timeout');
      },
    );
    return ProcessResult(process.pid, exitCode, await stdout, await stderr);
  }

  test('Android scaffold is API 30+ and repository-owned', () {
    final settings = File('android/settings.gradle.kts').readAsStringSync();
    final appBuild = File('android/app/build.gradle.kts').readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final service = File(
      'android/app/src/main/kotlin/com/argusromtoolkit/argus/'
      'ArgusForegroundExecutionService.kt',
    ).readAsStringSync();

    expect(settings, contains('dev.flutter.flutter-plugin-loader'));
    expect(appBuild, contains('minSdk = 30'));
    expect(
      manifest,
      contains('android:name="io.flutter.embedding.android.NormalTheme"'),
    );
    expect(
      manifest,
      contains('android:name=".ArgusForegroundExecutionService"'),
    );
    expect(manifest, contains('android:exported="false"'));
    expect(manifest, contains('android:foregroundServiceType="dataSync"'));
    expect(service, contains('return START_NOT_STICKY'));
  });

  test('Android identity is permanent and ARM64-only', () {
    final appBuild = File('android/app/build.gradle.kts').readAsStringSync();
    final buildScript = File(
      '../scripts/build_android_bridge.sh',
    ).readAsStringSync();
    final justfile = File('../justfile').readAsStringSync();

    expect(appBuild, contains('namespace = "com.argusromtoolkit.argus"'));
    expect(appBuild, contains('applicationId = "com.argusromtoolkit.argus"'));
    expect(appBuild, isNot(contains('dev.argusromtoolkit.argus')));
    expect(appBuild, isNot(contains('x86_64')));
    expect(appBuild, isNot(contains('android-x64')));

    expect(buildScript, contains('aarch64-linux-android'));
    expect(buildScript, contains('-t arm64-v8a'));
    expect(buildScript, isNot(contains('x86_64-linux-android')));
    expect(buildScript, isNot(contains('-t x86_64')));

    expect(justfile, contains('--target-platform android-arm64'));
    expect(justfile, isNot(contains('android-arm64,android-x64')));
    expect(justfile, isNot(contains('x86_64')));
  });

  test('Android harnesses are ARM64-only and use the permanent identity', () {
    final common = File(
      '../scripts/run_phase_002_android_scenario_common.sh',
    ).readAsStringSync();
    final bootstrap = File(
      '../scripts/run_phase_002_android_bootstrap_tests.sh',
    ).readAsStringSync();
    final scan = File(
      '../scripts/run_phase_002_android_scan_tests.sh',
    ).readAsStringSync();
    final foreground = File(
      '../scripts/run_phase_002_android_foreground_execution_tests.sh',
    ).readAsStringSync();
    final adaptive = File(
      '../scripts/run_phase_002_android_adaptive_ux_tests.sh',
    ).readAsStringSync();

    expect(common, contains('com.argusromtoolkit.argus'));
    expect(common, isNot(contains('ARGUS_ANDROID_DEVICE_REQUIRE_ARM64')));
    expect(common, isNot(contains('android-x64')));
    expect(common, isNot(contains('x86_64')));
    expect(common, contains('--target-platform android-arm64'));
    expect(common, contains('arm64-v8a'));

    for (final script in [bootstrap, scan, foreground, adaptive]) {
      expect(script, contains('com.argusromtoolkit.argus'));
      expect(script, isNot(contains('android-arm64,android-x64')));
      expect(script, isNot(contains('dual-ABI')));
      expect(script, isNot(contains('ARGUS_ANDROID_DEVICE_REQUIRE_ARM64')));
    }
    expect(bootstrap, isNot(contains('x86_64')));
    expect(scan, isNot(contains('lib/x86_64/')));
    expect(scan, isNot(contains('android-x64')));
    expect(foreground, isNot(contains('lib/x86_64/')));
    expect(
      foreground,
      contains(
        'com.argusromtoolkit.androidharness.ArgusNotificationCancelTest',
      ),
    );
    expect(
      adaptive,
      isNot(contains('apk_target_platforms=android-arm64,android-x64')),
    );
  });

  test('Android test fixtures use the permanent identity', () {
    final paths = <String>[
      'integration_test/phase_002_android_permission_gate_test.dart',
      'test/app/platform/platform_readiness_gate_test.dart',
      'test/app/platform/platform_readiness_controller_test.dart',
      'test/app/platform/android_platform_host_api_test.dart',
      'test/app/bootstrap/client_bootstrap_test.dart',
      'test/app/bootstrap/app_bootstrap_test.dart',
      'test/core/bridge/frb_mapper_test.dart',
    ];
    for (final path in paths) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('dev.argusromtoolkit.argus')));
    }
    final rustRuntime = File(
      '../rust/crates/argus-runtime/src/lib.rs',
    ).readAsStringSync();
    expect(rustRuntime, isNot(contains('dev.argusromtoolkit.argus')));
  });

  test('Android release signing is external and ARM64-only', () {
    final appBuild = File('android/app/build.gradle.kts').readAsStringSync();
    final releaseScript = File(
      '../scripts/build_android_release.sh',
    ).readAsStringSync();

    expect(appBuild, isNot(contains('signingConfigs.getByName("debug")')));
    expect(appBuild, contains('ARGUS_RELEASE_KEYSTORE'));
    expect(appBuild, contains('ARGUS_RELEASE_STORE_PASSWORD'));
    expect(appBuild, contains('ARGUS_RELEASE_KEY_ALIAS'));
    expect(appBuild, contains('ARGUS_RELEASE_KEY_PASSWORD'));

    expect(releaseScript, contains('--target-platform android-arm64'));
    expect(releaseScript, isNot(contains('android-x64')));
    expect(releaseScript, isNot(contains('x86_64')));
    expect(releaseScript, contains('ARGUS_RELEASE_KEYSTORE'));
    expect(releaseScript, contains('apksigner'));
  });

  test(
    'Hosted CI verifies the Android ARM64 package without emulator claims',
    () {
      final ci = File('../.github/workflows/ci.yml').readAsStringSync();

      expect(ci, contains('Android ARM64 build and package verification'));
      expect(ci, contains('just check-android-contract'));
      expect(ci, contains('just build-android-debug'));
      expect(ci, contains('just check-android-package'));
      expect(ci, isNot(contains('avdmanager')));
      expect(ci, isNot(contains('emulator')));
      expect(ci, isNot(contains('test-phase-002-android-final')));
    },
  );

  test(
    'release wrapper hides signing values on missing configuration',
    () async {
      final result = await runReleaseWrapper({
        'ARGUS_RELEASE_KEYSTORE': '',
        'ARGUS_RELEASE_STORE_PASSWORD': '',
        'ARGUS_RELEASE_KEY_ALIAS': '',
        'ARGUS_RELEASE_KEY_PASSWORD': '',
      });

      expect(result.exitCode, isNot(0));
      final stderr = result.stderr as String;
      expect(stderr, contains('ARGUS_RELEASE_KEYSTORE'));
      expect(stderr, contains('ARGUS_RELEASE_STORE_PASSWORD'));
      expect(stderr, contains('ARGUS_RELEASE_KEY_ALIAS'));
      expect(stderr, contains('ARGUS_RELEASE_KEY_PASSWORD'));
      expect(stderr, isNot(contains('secret-store-password')));
      expect(stderr, isNot(contains('secret-alias')));
      expect(stderr, isNot(contains('secret-key-password')));
    },
  );

  test('release wrapper hides an unreadable keystore value', () async {
    const keystoreValue = '/nonexistent/argus-release.keystore';
    final result = await runReleaseWrapper({
      'ARGUS_RELEASE_KEYSTORE': keystoreValue,
      'ARGUS_RELEASE_STORE_PASSWORD': 'secret-store-password',
      'ARGUS_RELEASE_KEY_ALIAS': 'secret-alias',
      'ARGUS_RELEASE_KEY_PASSWORD': 'secret-key-password',
    });

    expect(result.exitCode, isNot(0));
    final stderr = result.stderr as String;
    expect(stderr, contains('ARGUS_RELEASE_KEYSTORE'));
    expect(stderr, isNot(contains(keystoreValue)));
    expect(stderr, isNot(contains('secret-store-password')));
    expect(stderr, isNot(contains('secret-alias')));
    expect(stderr, isNot(contains('secret-key-password')));
  });

  test('Android owns one cached engine and a narrow platform bridge', () {
    final kotlinRoot = 'android/app/src/main/kotlin/com/argusromtoolkit/argus';
    final application = File(
      '$kotlinRoot/ArgusApplication.kt',
    ).readAsStringSync();
    final bridge = File(
      '$kotlinRoot/ArgusPlatformBridge.kt',
    ).readAsStringSync();
    final activity = File('$kotlinRoot/MainActivity.kt').readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(application, contains('class ArgusApplication : Application()'));
    expect(application, contains('FlutterEngineCache'));
    expect(application, contains('ENGINE_ID'));
    expect(application, contains('FlutterEngineCache.getInstance().put'));
    expect(activity, contains('provideFlutterEngine'));
    expect(activity, contains('argusApplication.flutterEngine'));
    expect(
      activity,
      contains('shouldDestroyEngineWithHost(): Boolean = false'),
    );
    expect(bridge, contains('"argus/platform_readiness"'));
    expect(bridge, contains('readSnapshot'));
    expect(bridge, contains('openAllFilesAccessSettings'));
    expect(bridge, contains('requestNotificationPermission'));
    expect(manifest, contains('android.permission.MANAGE_EXTERNAL_STORAGE'));
    expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
    expect(manifest, contains('android.permission.FOREGROUND_SERVICE'));
    expect(
      manifest,
      contains('android.permission.FOREGROUND_SERVICE_DATA_SYNC'),
    );
    expect(manifest, contains('android:name=".ArgusApplication"'));
    expect(manifest, contains('android:enableOnBackInvokedCallback="true"'));
    expect(manifest, isNot(contains('windowOptOutEdgeToEdgeEnforcement')));
    expect(application, contains('foregroundExecutionHost'));
    expect(application, contains('foregroundExecutionBridge'));
    expect(
      RegExp(r'FlutterEngine\(this\)').allMatches(application),
      hasLength(1),
    );
  });

  test('Android Activity identity is qualification-only host evidence', () {
    final kotlinRoot = 'android/app/src/main/kotlin/com/argusromtoolkit/argus';
    final qualification = File(
      '$kotlinRoot/ArgusQualificationBridge.kt',
    ).readAsStringSync();
    final application = File(
      '$kotlinRoot/ArgusApplication.kt',
    ).readAsStringSync();
    final activity = File('$kotlinRoot/MainActivity.kt').readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final hostApi = File(
      'lib/app/platform/application/platform_host_api.dart',
    ).readAsStringSync();
    final androidHostApi = File(
      'lib/app/platform/native/android_platform_host_api.dart',
    ).readAsStringSync();

    expect(qualification, contains('argus/android_qualification'));
    expect(qualification, contains('readActivityInstanceId'));
    expect(application, contains('qualificationBridge'));
    expect(activity, contains('qualificationInstanceId'));
    expect(activity, contains('qualificationBridge.attachActivity'));
    // The stock Flutter configChanges opt-out makes rotation an in-place
    // configuration change; the identity marker proves the expected behavior
    // and the cached engine/runtime invariant on the API 36 emulator.
    expect(
      manifest,
      contains(
        'android:configChanges='
        '"orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|'
        'locale|layoutDirection|fontScale|screenLayout|density|uiMode"',
      ),
    );
    // The qualification channel must never become product state or a second
    // platform authority.
    expect(hostApi, isNot(contains('android_qualification')));
    expect(androidHostApi, isNot(contains('android_qualification')));
    expect(hostApi, isNot(contains('readActivityInstanceId')));
  });
}
