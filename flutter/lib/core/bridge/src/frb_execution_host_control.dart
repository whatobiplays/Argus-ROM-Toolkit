import 'package:argus/core/bridge/generated/lib.dart' as dto;
import 'package:argus/core/bridge/src/frb_argus_client_gateway.dart'
    show mapFrbFailure;
import 'package:argus/core/client/client.dart';

/// The only live execution-host conditions the native bridge may report.
enum ExecutionHostStopReason {
  /// The foreground host exceeded the live execution deadline.
  timeout,

  /// The foreground host stopped without an accepted durable cancellation.
  hostLost,
}

/// Callback used by the control adapter's tests and platform composition.
///
/// The callback intentionally accepts only pure-Dart values. Generated FRB
/// DTOs are constructed inside the default reporter and never escape this
/// bridge adapter's public API.
typedef ExecutionHostStopReporter =
    Future<void> Function({
      required List<JobRunId> jobRunIds,
      required ExecutionHostStopReason reason,
    });

/// Reports live foreground-host stops for already-admitted background runs.
///
/// This adapter is deliberately separate from [ArgusClientGateway]: a host
/// stop is execution control, not a Jobs command, and therefore must not be
/// exposed as cancellation or any other durable client operation.
final class FrbExecutionHostControl {
  /// The maximum number of job identities accepted in one host-stop report.
  static const int maxJobRunIds = 16;

  /// Creates a control adapter, optionally replacing the generated reporter.
  FrbExecutionHostControl({ExecutionHostStopReporter? report})
    : _report = report ?? _reportWithFrb;

  final ExecutionHostStopReporter _report;

  /// Reports a timeout or host-loss condition for active job runs.
  ///
  /// Invalid identities and empty/oversized batches fail locally as a bridge
  /// contract mismatch, before any native transport call is attempted.
  Future<void> reportExecutionHostStop({
    required Iterable<JobRunId> jobRunIds,
    required ExecutionHostStopReason reason,
  }) async {
    final ids = List<JobRunId>.unmodifiable(jobRunIds);
    _validate(ids);
    try {
      await _report(jobRunIds: ids, reason: reason);
    } catch (error, stackTrace) {
      throw mapFrbFailure(error, stackTrace);
    }
  }

  static void _validate(List<JobRunId> jobRunIds) {
    if (jobRunIds.isEmpty || jobRunIds.length > maxJobRunIds) {
      throw const TransportFailure(
        'Invalid execution-host stop batch',
        kind: TransportFailureKind.contractMismatch,
      );
    }
    if (jobRunIds.any((id) => !id.isValid)) {
      throw const TransportFailure(
        'Invalid execution-host job identity',
        kind: TransportFailureKind.contractMismatch,
      );
    }
  }

  static Future<void> _reportWithFrb({
    required List<JobRunId> jobRunIds,
    required ExecutionHostStopReason reason,
  }) => dto.reportExecutionHostStop(
    request: dto.ReportExecutionHostStopRequestDto(
      jobRunIds: [for (final id in jobRunIds) id.value],
      reason: switch (reason) {
        ExecutionHostStopReason.timeout =>
          dto.ExecutionHostStopReasonDto.timeout,
        ExecutionHostStopReason.hostLost =>
          dto.ExecutionHostStopReasonDto.hostLost,
      },
    ),
  );
}
