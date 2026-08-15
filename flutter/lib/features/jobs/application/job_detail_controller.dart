import 'dart:async';

import 'package:argus/core/client/client.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../jobs_composition.dart';
import 'jobs_state.dart';

part 'job_detail_controller.freezed.dart';
part 'job_detail_controller.g.dart';

/// Loaded job-detail state keyed by the routed execution identity.
@freezed
sealed class JobDetailState with _$JobDetailState {
  /// The routed execution attempt is authoritatively known.
  const factory JobDetailState.ready({
    required JobDetail detail,
    required bool refreshing,
    required bool cancelling,
    required bool cancelAmbiguous,
    ClientFailure? lastFailure,
  }) = JobDetailStateReady;

  /// The syntactically valid job identity is not known.
  const factory JobDetailState.missing() = JobDetailStateMissing;
}

/// One application-lifetime owner of authoritative job-detail state.
@Riverpod(keepAlive: true)
class JobDetailController extends _$JobDetailController {
  static const String _jobNotFoundCode = 'ARGUS.V1.JOBS.JOB_RUN_NOT_FOUND';

  JobsRuntimeContext? _lastRuntimeContext;
  AsyncValue<JobDetailState>? _lastBuildValue;
  JobDetail? _lastLoaded;
  RuntimeInstanceId? _activeRuntimeInstanceId;
  int _readToken = 0;
  bool _readInFlight = false;
  bool _cancelInFlight = false;
  int _demandToken = 0;
  StreamSubscription<JobsReconciliationDemand>? _demandSubscription;

  @override
  AsyncValue<JobDetailState> build(JobRunId jobRunId) {
    ref.onDispose(() {
      _demandToken++;
      _demandSubscription?.cancel();
    });
    final demandSource = ref.watch(jobsReconciliationDemandProvider);
    _subscribeToDemandSource(demandSource, jobRunId);
    final context = ref.watch(jobsRuntimeContextProvider);
    if (context == _lastRuntimeContext && _lastLoaded != null) {
      return _lastBuildValue ?? const AsyncLoading();
    }
    _lastRuntimeContext = context;
    _readToken++;
    _readInFlight = false;
    _activeRuntimeInstanceId = switch (context) {
      JobsRuntimeContextPreReady() => null,
      JobsRuntimeContextReady(:final runtimeInstanceId) => runtimeInstanceId,
    };
    scheduleMicrotask(() => unawaited(_readAuthoritative(jobRunId)));
    return const AsyncLoading();
  }

  Future<void> refresh(JobRunId jobRunId) => _readAuthoritative(jobRunId);

  /// Requests durable cancellation and reconciles authoritative state.
  Future<void> cancel(JobRunId jobRunId) async {
    final current = state.value;
    if (current is! JobDetailStateReady ||
        current.cancelling ||
        current.cancelAmbiguous ||
        _cancelInFlight ||
        _readInFlight ||
        !current.detail.job.controls.canCancel) {
      return;
    }
    _cancelInFlight = true;
    try {
      final result = await ref.read(jobsApiProvider).cancelJob(jobRunId);
      if (result == CancelJobResult.cancellationRequested) {
        final latest = state.value;
        if (latest is! JobDetailStateReady) return;
        _publish(
          JobDetailState.ready(
            detail: latest.detail,
            refreshing: true,
            cancelling: true,
            cancelAmbiguous: false,
            lastFailure: null,
          ),
        );
      }
      await _readAuthoritative(jobRunId);
    } on ClientFailure catch (failure) {
      final latest = state.value;
      if (latest is! JobDetailStateReady) return;
      final ambiguous = failure is TransportFailure;
      _publish(
        JobDetailState.ready(
          detail: latest.detail,
          refreshing: false,
          cancelling: false,
          cancelAmbiguous: ambiguous,
          lastFailure: failure,
        ),
      );
      await _readAuthoritative(jobRunId);
    } finally {
      _cancelInFlight = false;
    }
  }

  Future<void> _readAuthoritative(JobRunId jobRunId) async {
    final runtimeId = _activeRuntimeInstanceId;
    if (runtimeId == null || _readInFlight) return;
    _readInFlight = true;
    final token = ++_readToken;
    try {
      final detail = await ref.read(jobsApiProvider).getJob(jobRunId);
      if (token != _readToken || runtimeId != _activeRuntimeInstanceId) return;
      _lastLoaded = detail;
      final current = state.value;
      _publish(
        JobDetailState.ready(
          detail: detail,
          refreshing: false,
          cancelling: current is JobDetailStateReady && current.cancelling,
          cancelAmbiguous:
              current is JobDetailStateReady && current.cancelAmbiguous,
          lastFailure: null,
        ),
      );
    } on ClientFailure catch (failure) {
      if (token != _readToken || runtimeId != _activeRuntimeInstanceId) return;
      if (_isJobNotFound(failure)) {
        _lastLoaded = null;
        _publish(const JobDetailState.missing());
        return;
      }
      final current = state.value;
      if (current is! JobDetailStateReady) {
        _setState(AsyncError(failure, StackTrace.current));
        return;
      }
      _publish(
        JobDetailState.ready(
          detail: current.detail,
          refreshing: false,
          cancelling: current.cancelling,
          cancelAmbiguous: current.cancelAmbiguous,
          lastFailure: failure,
        ),
      );
    } finally {
      if (token == _readToken) {
        _readInFlight = false;
      }
    }
  }

  void _subscribeToDemandSource(
    JobsReconciliationDemandSource source,
    JobRunId jobRunId,
  ) {
    _demandToken++;
    final token = _demandToken;
    final routedJobRunId = jobRunId;
    final subscription = source.stream.listen((demand) {
      if (token != _demandToken) return;
      switch (demand) {
        case JobsReconciliationDemandListChanged():
          unawaited(_readAuthoritative(routedJobRunId));
        case JobsReconciliationDemandDetailChanged(:final jobRunId):
          if (jobRunId == routedJobRunId) {
            unawaited(_readAuthoritative(routedJobRunId));
          }
      }
    });
    final previous = _demandSubscription;
    _demandSubscription = subscription;
    previous?.cancel();
  }

  bool _isJobNotFound(ClientFailure failure) =>
      failure is ApplicationFailure &&
      failure.error.code.value == _jobNotFoundCode;

  void _publish(JobDetailState next) {
    _setState(AsyncData(next));
  }

  void _setState(AsyncValue<JobDetailState> next) {
    _lastBuildValue = next;
    state = next;
  }
}
