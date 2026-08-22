import 'package:argus/app/platform/application/platform_host_api.dart';
import 'package:argus/app/platform/native/android_platform_host_api.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('argus/platform_readiness');
  late MockMethodCallHandler handler;

  setUp(() {
    handler = MockMethodCallHandler();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler.handle);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('readSnapshot maps validated wire fields', () async {
    handler.reply = <String, Object?>{
      'allFilesAccessRequired': true,
      'allFilesAccessGranted': true,
      'notificationAuthorization': 'promptRequired',
      'standardApplicationDataDirectory':
          '/data/user/0/com.argusromtoolkit.argus/files/argus',
    };

    final snapshot = await const MethodChannelAndroidPlatformHostApi()
        .readSnapshot();

    expect(snapshot.allFilesAccessRequired, isTrue);
    expect(snapshot.allFilesAccessGranted, isTrue);
    expect(
      snapshot.notificationAuthorization,
      NotificationAuthorization.promptRequired,
    );
    expect(
      snapshot.standardApplicationDataDirectory,
      '/data/user/0/com.argusromtoolkit.argus/files/argus',
    );
  });

  test(
    'malformed snapshot fields become a bounded unavailable failure',
    () async {
      handler.reply = <String, Object?>{
        'allFilesAccessRequired': true,
        'allFilesAccessGranted': 'not-a-bool',
        'notificationAuthorization': 'promptRequired',
      };

      await expectLater(
        const MethodChannelAndroidPlatformHostApi().readSnapshot(),
        throwsA(
          isA<PlatformHostException>().having(
            (error) => error.kind,
            'kind',
            PlatformReadinessFailureKind.snapshotUnavailable,
          ),
        ),
      );
    },
  );

  test('unknown notification wire value becomes a bounded failure', () async {
    handler.reply = <String, Object?>{
      'allFilesAccessRequired': true,
      'allFilesAccessGranted': true,
      'notificationAuthorization': 'sometimes',
    };

    await expectLater(
      const MethodChannelAndroidPlatformHostApi().readSnapshot(),
      throwsA(
        isA<PlatformHostException>().having(
          (error) => error.kind,
          'kind',
          PlatformReadinessFailureKind.snapshotUnavailable,
        ),
      ),
    );
  });

  test(
    'settings-launch PlatformException maps to the bounded failure',
    () async {
      handler.error = PlatformException(
        code: 'SETTINGS_UNAVAILABLE',
        message: 'secret native detail',
      );

      await expectLater(
        const MethodChannelAndroidPlatformHostApi()
            .openAllFilesAccessSettings(),
        throwsA(
          isA<PlatformHostException>().having(
            (error) => error.kind,
            'kind',
            PlatformReadinessFailureKind.settingsLaunchFailed,
          ),
        ),
      );
    },
  );

  test('malformed notification reply maps to the bounded failure', () async {
    handler.reply = 'sometimes';

    await expectLater(
      const MethodChannelAndroidPlatformHostApi()
          .requestNotificationPermission(),
      throwsA(
        isA<PlatformHostException>().having(
          (error) => error.kind,
          'kind',
          PlatformReadinessFailureKind.notificationRequestFailed,
        ),
      ),
    );
  });
}

final class MockMethodCallHandler {
  Object? reply;
  Object? error;

  Future<Object?> handle(MethodCall call) async {
    final error = this.error;
    if (error != null) throw error;
    return reply;
  }
}
