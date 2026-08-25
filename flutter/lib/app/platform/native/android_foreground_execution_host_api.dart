import 'package:argus/core/client/client.dart';
import 'package:flutter/services.dart';

import '../application/foreground_execution_host_api.dart';

/// Android MethodChannel/EventChannel adapter for the foreground execution
/// host. Android channel values are validated before entering app composition.
final class MethodChannelAndroidForegroundExecutionHostApi
    implements ForegroundExecutionHostApi {
  const MethodChannelAndroidForegroundExecutionHostApi({
    MethodChannel? commandChannel,
    EventChannel? eventChannel,
    Stream<Object?> Function()? eventStreamFactory,
  }) : this._(
         commandChannel ?? const MethodChannel('argus/foreground_execution'),
         eventChannel ??
             const EventChannel('argus/foreground_execution/events'),
         eventStreamFactory,
       );

  const MethodChannelAndroidForegroundExecutionHostApi._(
    this._commandChannel,
    this._eventChannel,
    this._eventStreamFactory,
  );

  final MethodChannel _commandChannel;
  final EventChannel _eventChannel;
  final Stream<Object?> Function()? _eventStreamFactory;

  @override
  Stream<ForegroundExecutionHostEvent> get events async* {
    try {
      final source =
          _eventStreamFactory?.call() ?? _eventChannel.receiveBroadcastStream();
      await for (final raw in source) {
        yield _parseEvent(raw);
      }
    } catch (error, stackTrace) {
      throw _mapChannelFailure(error, stackTrace);
    }
  }

  @override
  Future<ForegroundExecutionLease> acquireLibraryScanLease() async {
    try {
      final raw = await _commandChannel.invokeMapMethod<Object?, Object?>(
        'acquireLibraryScanLease',
      );
      if (raw == null) _throwContract('Missing foreground lease response');
      final leaseId = raw['leaseId'];
      if (leaseId is! String || !_isValidLeaseId(leaseId)) {
        _throwContract('Malformed foreground lease response');
      }
      return ForegroundExecutionLease(leaseId);
    } catch (error, stackTrace) {
      throw _mapChannelFailure(error, stackTrace);
    }
  }

  @override
  Future<void> releaseLease(ForegroundExecutionLease lease) async {
    if (!_isValidLeaseId(lease.value)) {
      _throwContract('Malformed foreground lease identity');
    }
    try {
      await _commandChannel.invokeMethod<void>('releaseLease', {
        'leaseId': lease.value,
      });
    } catch (error, stackTrace) {
      throw _mapChannelFailure(error, stackTrace);
    }
  }

  @override
  Future<void> updateProjection(
    ForegroundExecutionProjection projection,
  ) async {
    _validateProjection(projection);
    try {
      await _commandChannel.invokeMethod<void>('updateProjection', {
        'activeJobCount': projection.activeJobCount,
        'completedUnits': projection.completedUnits,
        'totalUnits': projection.totalUnits,
        'phase': projection.phase,
        'statusKey': projection.statusKey,
        'operationLabel': projection.operationLabel,
        'cancellableJobRunId': projection.cancellableJobRunId?.value,
      });
    } catch (error, stackTrace) {
      throw _mapChannelFailure(error, stackTrace);
    }
  }

  ForegroundExecutionHostEvent _parseEvent(Object? raw) {
    if (raw is! Map<Object?, Object?>) {
      _throwContract('Malformed foreground host event');
    }
    final event = raw['event'];
    return switch (event) {
      'cancelRequested' => _parseCancelEvent(raw),
      'timedOut' => const ForegroundExecutionTimedOut(),
      'hostLost' => const ForegroundExecutionHostLost(),
      _ => _throwContract('Unknown foreground host event'),
    };
  }

  ForegroundExecutionHostEvent _parseCancelEvent(Map<Object?, Object?> raw) {
    final value = raw['jobRunId'];
    final jobRunId = value is String ? JobRunId.tryParse(value) : null;
    if (jobRunId == null) _throwContract('Malformed foreground cancel event');
    return ForegroundExecutionCancelRequested(jobRunId);
  }

  void _validateProjection(ForegroundExecutionProjection projection) {
    final completed = projection.completedUnits;
    final total = projection.totalUnits;
    if (projection.activeJobCount < 0 ||
        projection.activeJobCount > maxForegroundExecutionActiveJobs ||
        completed != null &&
            (completed < 0 || total != null && completed > total) ||
        total != null && total < 0) {
      _throwContract('Malformed foreground projection');
    }
    if (!_validText(projection.phase) ||
        !_validText(projection.statusKey) ||
        !_validText(projection.operationLabel)) {
      _throwContract('Malformed foreground projection');
    }
    final cancellable = projection.cancellableJobRunId;
    if (cancellable != null && !cancellable.isValid) {
      _throwContract('Malformed foreground projection');
    }
  }

  bool _validText(String? value) => value == null || value.length <= 128;

  bool _isValidLeaseId(String value) => value.isNotEmpty && value.length <= 128;

  Never _throwContract(String message) {
    throw TransportFailure(
      message,
      kind: TransportFailureKind.contractMismatch,
    );
  }

  ClientFailure _mapChannelFailure(Object error, StackTrace stackTrace) {
    if (error is ClientFailure) return error;
    final kind = error is MissingPluginException
        ? TransportFailureKind.bridgeUnavailable
        : TransportFailureKind.communicationFailed;
    return TransportFailure(
      'Foreground execution host transport failed',
      kind: kind,
      cause: error,
      stackTrace: stackTrace,
    );
  }
}
