import 'package:argus/core/bridge/src/frb_execution_host_control.dart';
import 'package:argus/core/bridge/generated/lib.dart' as dto;
import 'package:argus/core/client/client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const jobRunId = JobRunId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');

  test('reports pure job identities and the closed stop reason', () async {
    List<JobRunId>? receivedIds;
    ExecutionHostStopReason? receivedReason;
    final control = FrbExecutionHostControl(
      report: ({required jobRunIds, required reason}) async {
        receivedIds = jobRunIds;
        receivedReason = reason;
      },
    );

    await control.reportExecutionHostStop(
      jobRunIds: const [jobRunId],
      reason: ExecutionHostStopReason.timeout,
    );

    expect(receivedIds, const [jobRunId]);
    expect(receivedReason, ExecutionHostStopReason.timeout);
  });

  test('rejects invalid host-stop requests before transport', () async {
    var calls = 0;
    final control = FrbExecutionHostControl(
      report: ({required jobRunIds, required reason}) async => calls++,
    );

    final invalidRequests = <Iterable<JobRunId>>[
      const [],
      const [JobRunId('not-a-job-run-id')],
      List<JobRunId>.filled(FrbExecutionHostControl.maxJobRunIds + 1, jobRunId),
    ];
    for (final request in invalidRequests) {
      await expectLater(
        control.reportExecutionHostStop(
          jobRunIds: request,
          reason: ExecutionHostStopReason.hostLost,
        ),
        throwsA(
          isA<TransportFailure>().having(
            (failure) => failure.kind,
            'kind',
            TransportFailureKind.contractMismatch,
          ),
        ),
      );
    }

    expect(calls, 0);
  });

  test(
    'maps a generated application error through the shared failure path',
    () async {
      final control = FrbExecutionHostControl(
        report: ({required jobRunIds, required reason}) async {
          throw const dto.ApplicationErrorDto(
            code: 'ARGUS.V1.RUNTIME.STALE_INSTANCE',
            category: 'runtime',
            severity: 'Warning',
            recoverability: 'UserAction',
            retryPolicy: 'Never',
            messageKey: 'errors.runtime.stale_instance',
            traceId: '01010101010101010101010101010101',
            safeContext: [],
          );
        },
      );

      await expectLater(
        control.reportExecutionHostStop(
          jobRunIds: const [jobRunId],
          reason: ExecutionHostStopReason.hostLost,
        ),
        throwsA(isA<ApplicationFailure>()),
      );
    },
  );
}
