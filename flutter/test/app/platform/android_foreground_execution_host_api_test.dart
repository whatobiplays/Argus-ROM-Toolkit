import 'package:argus/app/platform/application/foreground_execution_host_api.dart';
import 'package:argus/app/platform/native/android_foreground_execution_host_api.dart';
import 'package:argus/core/client/client.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('argus/foreground_execution');
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

  test(
    'acquire, release, and projection use the bounded wire contract',
    () async {
      handler.reply = const <String, Object?>{'leaseId': 'lease-1'};
      final api = MethodChannelAndroidForegroundExecutionHostApi();

      final lease = await api.acquireLibraryScanLease();
      expect(lease.value, 'lease-1');

      await api.updateProjection(
        const ForegroundExecutionProjection(
          activeJobCount: 1,
          completedUnits: 4,
          totalUnits: 10,
          phase: 'indexing',
          statusKey: 'scan.indexing',
          cancellableJobRunId: JobRunId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
        ),
      );
      await api.releaseLease(lease);

      expect(handler.calls.map((call) => call.method), [
        'acquireLibraryScanLease',
        'updateProjection',
        'releaseLease',
      ]);
      expect(handler.calls[1].arguments, {
        'activeJobCount': 1,
        'completedUnits': 4,
        'totalUnits': 10,
        'phase': 'indexing',
        'statusKey': 'scan.indexing',
        'operationLabel': null,
        'cancellableJobRunId': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      });
      expect(handler.calls[2].arguments, {'leaseId': 'lease-1'});
    },
  );

  test(
    'malformed acquisition replies fail as a transport contract mismatch',
    () async {
      handler.reply = const <String, Object?>{'leaseId': ''};

      await expectLater(
        MethodChannelAndroidForegroundExecutionHostApi()
            .acquireLibraryScanLease(),
        throwsA(
          isA<TransportFailure>().having(
            (failure) => failure.kind,
            'kind',
            TransportFailureKind.contractMismatch,
          ),
        ),
      );
    },
  );

  test('event wire values map to closed host events', () async {
    final api = MethodChannelAndroidForegroundExecutionHostApi(
      eventStreamFactory: () => Stream<Object?>.fromIterable([
        const <String, Object?>{
          'event': 'cancelRequested',
          'jobRunId': 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        },
        const <String, Object?>{'event': 'timedOut'},
        const <String, Object?>{'event': 'hostLost'},
      ]),
    );

    final events = await api.events.toList();

    expect(events, hasLength(3));
    expect(events[0], isA<ForegroundExecutionCancelRequested>());
    expect(
      (events[0] as ForegroundExecutionCancelRequested).jobRunId,
      const JobRunId('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'),
    );
    expect(events[1], isA<ForegroundExecutionTimedOut>());
    expect(events[2], isA<ForegroundExecutionHostLost>());
  });

  test('malformed event identity becomes a contract mismatch', () async {
    final api = MethodChannelAndroidForegroundExecutionHostApi(
      eventStreamFactory: () => Stream<Object?>.value(const <String, Object?>{
        'event': 'cancelRequested',
        'jobRunId': 'malformed',
      }),
    );

    await expectLater(
      api.events.toList(),
      throwsA(
        isA<TransportFailure>().having(
          (failure) => failure.kind,
          'kind',
          TransportFailureKind.contractMismatch,
        ),
      ),
    );
  });
}

final class MockMethodCallHandler {
  Object? reply;
  final calls = <MethodCall>[];

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    return reply;
  }
}
