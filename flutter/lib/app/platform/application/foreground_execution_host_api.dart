import 'package:argus/core/client/client.dart';

/// Maximum number of active jobs represented by one notification projection.
const int maxForegroundExecutionActiveJobs = 16;

/// One opaque process-local Android foreground execution lease.
final class ForegroundExecutionLease {
  const ForegroundExecutionLease(this.value);

  final String value;
}

/// Bounded, non-authoritative notification facts supplied to the native host.
final class ForegroundExecutionProjection {
  const ForegroundExecutionProjection({
    required this.activeJobCount,
    this.completedUnits,
    this.totalUnits,
    this.phase,
    this.statusKey,
    this.operationLabel,
    this.cancellableJobRunId,
  });

  final int activeJobCount;
  final int? completedUnits;
  final int? totalUnits;
  final String? phase;
  final String? statusKey;
  final String? operationLabel;
  final JobRunId? cancellableJobRunId;
}

/// Closed native event vocabulary delivered to app composition.
sealed class ForegroundExecutionHostEvent {
  const ForegroundExecutionHostEvent();
}

/// Requests that the existing durable Jobs cancellation path be called.
final class ForegroundExecutionCancelRequested
    extends ForegroundExecutionHostEvent {
  const ForegroundExecutionCancelRequested(this.jobRunId);

  final JobRunId jobRunId;
}

/// Reports an Android platform timeout of the live foreground host.
final class ForegroundExecutionTimedOut extends ForegroundExecutionHostEvent {
  const ForegroundExecutionTimedOut();
}

/// Reports unexpected destruction of the live foreground host.
final class ForegroundExecutionHostLost extends ForegroundExecutionHostEvent {
  const ForegroundExecutionHostLost();
}

/// Pure-Dart port for application-scoped foreground execution hosting.
abstract interface class ForegroundExecutionHostApi {
  Stream<ForegroundExecutionHostEvent> get events;

  Future<ForegroundExecutionLease> acquireLibraryScanLease();

  Future<void> releaseLease(ForegroundExecutionLease lease);

  Future<void> updateProjection(ForegroundExecutionProjection projection);
}
