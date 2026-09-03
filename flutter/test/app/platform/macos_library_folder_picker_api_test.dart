import 'package:argus/app/platform/application/macos_library_folder_picker_api.dart';
import 'package:argus/app/platform/native/macos_library_folder_picker_api.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('argus/macos_library_folder_picker');
  late _MockMethodCallHandler handler;

  setUp(() {
    handler = _MockMethodCallHandler();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler.handle);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'maps a confirmed folder and retains authorization as opaque bytes',
    () async {
      handler.reply = <String, Object?>{
        'path': '/Users/example/Library',
        'authorization': Uint8List.fromList(<int>[0xde, 0xad, 0xbe, 0xef]),
      };

      final selection = await const MethodChannelMacosLibraryFolderPickerApi()
          .pickLibraryFolder();

      expect(selection, isNotNull);
      expect(selection!.path, '/Users/example/Library');
      expect(selection.authorization, <int>[0xde, 0xad, 0xbe, 0xef]);
      expect(selection.toString(), isNot(contains('222')));
      expect(selection.toString(), contains('opaque'));
    },
  );

  test('maps native cancellation to null', () async {
    handler.reply = null;

    expect(
      await const MethodChannelMacosLibraryFolderPickerApi()
          .pickLibraryFolder(),
      isNull,
    );
  });

  test(
    'rejects malformed native selections without exposing details',
    () async {
      handler.reply = <String, Object?>{
        'path': '/Users/example/Library',
        'authorization': <int>[1, 2, 3],
      };

      await expectLater(
        const MethodChannelMacosLibraryFolderPickerApi().pickLibraryFolder(),
        throwsA(
          isA<MacosLibraryFolderPickerException>().having(
            (error) => error.kind,
            'kind',
            MacosLibraryFolderPickerFailureKind.malformedResponse,
          ),
        ),
      );
    },
  );

  test('maps native failures to a bounded opaque error', () async {
    handler.error = PlatformException(
      code: 'PRIVATE_NATIVE_FAILURE',
      message: 'private bookmark detail',
      details: 'private native object',
    );

    await expectLater(
      const MethodChannelMacosLibraryFolderPickerApi().pickLibraryFolder(),
      throwsA(
        isA<MacosLibraryFolderPickerException>()
            .having(
              (error) => error.kind,
              'kind',
              MacosLibraryFolderPickerFailureKind.nativeUnavailable,
            )
            .having(
              (error) => error.toString(),
              'safe string',
              isNot(contains('private')),
            ),
      ),
    );
  });
}

final class _MockMethodCallHandler {
  Object? reply;
  Object? error;

  Future<Object?> handle(MethodCall call) async {
    final error = this.error;
    if (error != null) throw error;
    return reply;
  }
}
