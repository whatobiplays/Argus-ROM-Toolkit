import 'package:argus/app/platform/application/diagnostics_publication_api.dart';
import 'package:argus/app/platform/native/android_diagnostics_publication_api.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('argus/diagnostics_share');
  late MockDiagnosticsHandler handler;

  setUp(() {
    handler = MockDiagnosticsHandler();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler.handle);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('publishes through a no-argument native operation', () async {
    await const MethodChannelAndroidDiagnosticsPublicationApi()
        .publishCompletedStartupDiagnostics();

    expect(handler.calls, hasLength(1));
    expect(handler.calls.single.method, 'shareCompletedStartupDiagnostics');
    expect(handler.calls.single.arguments, isNull);
  });

  test(
    'maps bounded native publication failures without native text',
    () async {
      handler.error = PlatformException(
        code: 'ARTIFACT_UNAVAILABLE',
        message: '/private/path/should-not-cross',
      );

      await expectLater(
        const MethodChannelAndroidDiagnosticsPublicationApi()
            .publishCompletedStartupDiagnostics(),
        throwsA(
          isA<DiagnosticsPublicationException>().having(
            (error) => error.kind,
            'kind',
            DiagnosticsPublicationFailureKind.artifactUnavailable,
          ),
        ),
      );
    },
  );

  test('unknown native failure maps to share unavailable', () async {
    handler.error = PlatformException(code: 'UNEXPECTED_NATIVE_DETAIL');

    await expectLater(
      const MethodChannelAndroidDiagnosticsPublicationApi()
          .publishCompletedStartupDiagnostics(),
      throwsA(
        isA<DiagnosticsPublicationException>().having(
          (error) => error.kind,
          'kind',
          DiagnosticsPublicationFailureKind.shareUnavailable,
        ),
      ),
    );
  });
}

final class MockDiagnosticsHandler {
  Object? error;
  final List<MethodCall> calls = [];

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    final error = this.error;
    if (error != null) throw error;
    return null;
  }
}
