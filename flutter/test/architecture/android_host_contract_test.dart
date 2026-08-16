import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android scaffold is API 30+ and repository-owned', () {
    final settings = File('android/settings.gradle.kts').readAsStringSync();
    final appBuild = File('android/app/build.gradle.kts').readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(settings, contains('dev.flutter.flutter-plugin-loader'));
    expect(appBuild, contains('minSdk = 30'));
    expect(
      manifest,
      contains('android:name="io.flutter.embedding.android.NormalTheme"'),
    );
    expect(manifest, isNot(contains('<service')));
  });

  test('Android owns one cached engine and a narrow platform bridge', () {
    final kotlinRoot = 'android/app/src/main/kotlin/dev/argusromtoolkit/argus';
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
    expect(manifest, contains('android:name=".ArgusApplication"'));
    expect(manifest, isNot(contains('FOREGROUND_SERVICE')));
    expect(manifest, isNot(contains('<service')));
  });
}
