import 'package:argus/app/platform/native/android_qualification_api.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('argus/android_qualification');
  late _QualificationHandler handler;

  setUp(() {
    handler = _QualificationHandler();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler.handle);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('reads the attached Activity identity', () async {
    handler.replies['readActivityInstanceId'] = 'activity-7';

    final value = await const AndroidQualificationApi()
        .readActivityInstanceId();

    expect(value, 'activity-7');
    expect(handler.methods, ['readActivityInstanceId']);
  });

  test('rejects a malformed attached Activity identity', () async {
    handler.replies['readActivityInstanceId'] = 7;

    await expectLater(
      const AndroidQualificationApi().readActivityInstanceId(),
      throwsA(isA<FormatException>()),
    );
  });

  test('controls deterministic execution-host qualification paths', () async {
    handler.replies['triggerExecutionHostTimeout'] = true;
    handler.replies['triggerExecutionHostLoss'] = false;

    await const AndroidQualificationApi().rejectNextExecutionHostStart();
    final timedOut = await const AndroidQualificationApi()
        .triggerExecutionHostTimeout();
    final hostLost = await const AndroidQualificationApi()
        .triggerExecutionHostLoss();

    expect(timedOut, isTrue);
    expect(hostLost, isFalse);
    expect(handler.methods, [
      'rejectNextExecutionHostStart',
      'triggerExecutionHostTimeout',
      'triggerExecutionHostLoss',
    ]);
  });

  test('normalizes an absent boolean result to false', () async {
    final value = await const AndroidQualificationApi()
        .triggerExecutionHostTimeout();

    expect(value, isFalse);
  });
}

final class _QualificationHandler {
  final replies = <String, Object?>{};
  final methods = <String>[];

  Future<Object?> handle(MethodCall call) async {
    methods.add(call.method);
    return replies[call.method];
  }
}
