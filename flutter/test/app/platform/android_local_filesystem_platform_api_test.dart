import 'package:argus/app/platform/application/local_filesystem_platform_api.dart';
import 'package:argus/app/platform/native/android_local_filesystem_platform_api.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('argus/local_filesystem_platform');
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

  test('readMountedVolumes maps bounded native facts', () async {
    handler.reply = <Object?>[
      <String, Object?>{
        'providerVolumeId': 'primary',
        'transientMountPath': '/storage/emulated/0',
        'safeDisplayName': 'Internal storage',
        'isPrimary': true,
        'isRemovable': false,
      },
      <String, Object?>{
        'providerVolumeId': 'ABCD-1234',
        'transientMountPath': '/storage/ABCD-1234',
        'safeDisplayName': 'SD card',
        'isPrimary': false,
        'isRemovable': true,
      },
    ];

    final volumes = await const MethodChannelAndroidLocalFilesystemPlatformApi()
        .readMountedVolumes();

    expect(volumes, hasLength(2));
    expect(volumes.first.providerVolumeId, 'primary');
    expect(volumes.first.isPrimary, isTrue);
    expect(volumes.last.isRemovable, isTrue);
  });

  test('malformed fields become a bounded discovery failure', () async {
    handler.reply = <Object?>[
      <String, Object?>{
        'providerVolumeId': 'primary',
        'transientMountPath': '/storage/emulated/0',
        'safeDisplayName': 'Internal storage',
        'isPrimary': 'yes',
        'isRemovable': false,
      },
    ];

    await expectLater(
      const MethodChannelAndroidLocalFilesystemPlatformApi()
          .readMountedVolumes(),
      throwsA(
        isA<LocalFilesystemPlatformException>().having(
          (error) => error.kind,
          'kind',
          LocalFilesystemPlatformFailureKind.malformedSnapshot,
        ),
      ),
    );
  });

  test(
    'duplicate volume identities become a bounded discovery failure',
    () async {
      handler.reply = List<Object?>.generate(
        2,
        (_) => <String, Object?>{
          'providerVolumeId': 'duplicate',
          'transientMountPath': '/storage/emulated/0',
          'safeDisplayName': 'Storage',
          'isPrimary': true,
          'isRemovable': false,
        },
      );

      await expectLater(
        const MethodChannelAndroidLocalFilesystemPlatformApi()
            .readMountedVolumes(),
        throwsA(isA<LocalFilesystemPlatformException>()),
      );
    },
  );

  test('missing primary volume becomes a bounded discovery failure', () async {
    handler.reply = <Object?>[
      <String, Object?>{
        'providerVolumeId': 'ABCD-1234',
        'transientMountPath': '/storage/ABCD-1234',
        'safeDisplayName': 'SD card',
        'isPrimary': false,
        'isRemovable': true,
      },
    ];

    await expectLater(
      const MethodChannelAndroidLocalFilesystemPlatformApi()
          .readMountedVolumes(),
      throwsA(
        isA<LocalFilesystemPlatformException>().having(
          (error) => error.kind,
          'kind',
          LocalFilesystemPlatformFailureKind.malformedSnapshot,
        ),
      ),
    );
  });

  test('oversized snapshots become a bounded discovery failure', () async {
    handler.reply = List<Object?>.generate(
      33,
      (index) => <String, Object?>{
        'providerVolumeId': 'volume-$index',
        'transientMountPath': '/storage/volume-$index',
        'safeDisplayName': 'Storage $index',
        'isPrimary': index == 0,
        'isRemovable': index != 0,
      },
    );

    await expectLater(
      const MethodChannelAndroidLocalFilesystemPlatformApi()
          .readMountedVolumes(),
      throwsA(isA<LocalFilesystemPlatformException>()),
    );
  });

  test('native channel failures do not expose native error text', () async {
    handler.error = PlatformException(
      code: 'DISCOVERY_FAILED',
      message: 'private native detail',
    );

    await expectLater(
      const MethodChannelAndroidLocalFilesystemPlatformApi()
          .readMountedVolumes(),
      throwsA(
        isA<LocalFilesystemPlatformException>().having(
          (error) => error.kind,
          'kind',
          LocalFilesystemPlatformFailureKind.discoveryUnavailable,
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
