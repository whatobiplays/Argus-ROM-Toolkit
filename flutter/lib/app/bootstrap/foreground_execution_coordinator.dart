import 'dart:async';

import 'package:argus/app/platform/platform_host.dart';
import 'package:argus/core/bridge/bridge.dart';
import 'package:argus/core/client/client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'client_bootstrap.dart';

part 'foreground_execution_coordinator.g.dart';

/// Creates the one app-lifetime coordinator over the root client's focused
/// capabilities. Desktop composition supplies no host and remains pass-through.
@Riverpod(keepAlive: true)
ForegroundExecutionCoordinator foregroundExecutionCoordinator(Ref ref) {
  final client = ref.watch(argusClientProvider);
  final coordinator = ForegroundExecutionCoordinator(
    sources: client.sources,
    jobs: client.jobs,
    refresh: client.refresh,
    events: client.events,
    host: ref.watch(foregroundExecutionHostApiProvider),
  );
  ref.onDispose(() => unawaited(coordinator.dispose()));
  return coordinator;
}

/// App-composition decorator that hosts qualifying Library and composed-refresh
/// admissions.
///
/// The coordinator owns only transient native leases. Jobs and Sources remain
/// the authoritative product APIs, and every reconciliation reads current
/// durable Jobs state before changing the lease set or notification
/// projection.
final class ForegroundExecutionCoordinator {
  factory ForegroundExecutionCoordinator({
    required SourcesApi sources,
    required JobsApi jobs,
    required LibraryRefreshApi refresh,
    required EventsApi events,
    ForegroundExecutionHostApi? host,
    FrbExecutionHostControl? executionHostControl,
  }) => ForegroundExecutionCoordinator._(
    sources,
    jobs,
    refresh,
    events,
    host,
    executionHostControl,
  );

  ForegroundExecutionCoordinator._(
    this._sources,
    this._jobs,
    this._refresh,
    this._events,
    this._host,
    FrbExecutionHostControl? executionHostControl,
  ) : _executionHostControl =
          executionHostControl ?? FrbExecutionHostControl() {
    final executionHost = _host;
    if (executionHost == null) return;
    _hostEventsSubscription = executionHost.events.listen((event) {
      unawaited(_handleHostEvent(event));
    });
    _runtimeEventsSubscription = _events.events.listen((_) {
      unawaited(_reconcileSerialized().catchError((_) {}));
    });
  }

  final SourcesApi _sources;
  final JobsApi _jobs;
  final LibraryRefreshApi _refresh;
  final EventsApi _events;
  final ForegroundExecutionHostApi? _host;
  final FrbExecutionHostControl _executionHostControl;
  final List<ForegroundExecutionLease> _leases = [];
  final Map<JobRunId, Future<void>> _cancellationInFlight = {};
  Future<void> _admissionTail = Future<void>.value();
  Future<void>? _reconciliation;
  StreamSubscription<ForegroundExecutionHostEvent>? _hostEventsSubscription;
  StreamSubscription<RuntimeEvent>? _runtimeEventsSubscription;
  bool _disposed = false;

  /// Sources API decorated with pre-admission foreground hosting.
  late final SourcesApi sourcesApi = ForegroundHostedSourcesApi(this, _sources);

  /// Jobs API decorated with authoritative retry qualification and hosting.
  late final JobsApi jobsApi = ForegroundHostedJobsApi(this, _jobs);

  /// Library refresh admissions decorated with the existing native lease.
  late final LibraryRefreshApi refreshApi = ForegroundHostedLibraryRefreshApi(
    this,
    _refresh,
  );

  /// Releases transient native state and detaches event listeners.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _hostEventsSubscription?.cancel();
    await _runtimeEventsSubscription?.cancel();
    await _releaseAllLeases();
  }

  Future<T> admit<T>(Future<T> Function() operation) async {
    // Serialize direct admissions so one response cannot release the
    // provisional lease belonging to another durable call still in flight.
    final previous = _admissionTail;
    final turn = Completer<void>();
    _admissionTail = turn.future;
    await previous;
    try {
      final host = _host;
      if (host == null) return operation();

      // The native acknowledgement is awaited before the durable call begins.
      final lease = await host.acquireLibraryScanLease();
      _leases.add(lease);
      try {
        final result = await operation();
        // A successful result is returned unchanged even if a secondary
        // notification projection update fails.
        try {
          await _reconcileSerialized();
        } catch (_) {
          // The next runtime event or direct admission retries authority reads.
        }
        return result;
      } catch (error, stackTrace) {
        try {
          await _reconcileSerialized();
        } catch (_) {
          // Preserve the original typed product failure exactly.
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
    } finally {
      turn.complete();
    }
  }

  Future<RetryJobResult> retry(JobRunId jobRunId) async {
    if (_host == null) return _jobs.retryJob(jobRunId);

    // Retry qualification is authoritative and must precede lease acquisition.
    final detail = await _jobs.getJob(jobRunId);
    final qualifies =
        _foregroundOperationTypes.contains(detail.job.operationType) &&
        detail.job.controls.canRetry;
    if (!qualifies) return _jobs.retryJob(jobRunId);
    return admit(() => _jobs.retryJob(jobRunId));
  }

  Future<void> _handleHostEvent(ForegroundExecutionHostEvent event) async {
    if (_disposed) return;
    switch (event) {
      case ForegroundExecutionCancelRequested(:final jobRunId):
        await _cancelFromNative(jobRunId);
      case ForegroundExecutionTimedOut():
        await _reportHostStop(ExecutionHostStopReason.timeout);
      case ForegroundExecutionHostLost():
        await _reportHostStop(ExecutionHostStopReason.hostLost);
    }
  }

  Future<void> _cancelFromNative(JobRunId jobRunId) async {
    final existing = _cancellationInFlight[jobRunId];
    if (existing != null) return existing;
    final operation = () async {
      await _jobs.cancelJob(jobRunId);
      await _reconcileSerialized();
    }();
    _cancellationInFlight[jobRunId] = operation;
    try {
      await operation;
    } finally {
      _cancellationInFlight.remove(jobRunId);
    }
  }

  Future<void> _reportHostStop(ExecutionHostStopReason reason) async {
    try {
      final active = await _readActiveWithOneQueryRetry();
      final ids = [for (final item in active) item.jobRunId];
      if (ids.isNotEmpty) {
        await _reportExecutionHostStopForIds(ids, reason);
      }
    } finally {
      await _invalidateLeasesAfterHostStop();
    }
  }

  Future<void> _reconcileSerialized() async {
    if (_host == null || _disposed) return;
    final existing = _reconciliation;
    if (existing != null) return existing;
    final operation = _reconcileWithOneQueryRetry();
    _reconciliation = operation;
    try {
      await operation;
    } finally {
      if (identical(_reconciliation, operation)) _reconciliation = null;
    }
  }

  Future<void> _reconcileWithOneQueryRetry() async {
    final active = await _readActiveWithOneQueryRetry();
    await _applyAuthoritativeActiveJobs(active);
  }

  Future<List<JobListItem>> _readActiveWithOneQueryRetry() async {
    try {
      return await _readActiveQualifyingJobs();
    } catch (_) {
      // A transient Jobs read failure retains provisional leases. Only the
      // authoritative query is retried once; no business command is replayed.
      await Future<void>.delayed(Duration.zero);
      return _readActiveQualifyingJobs();
    }
  }

  Future<List<JobListItem>> _readActiveQualifyingJobs() async {
    final page = await _jobs.listActiveJobs();
    return [
      for (final item in page.items)
        if (_foregroundOperationTypes.contains(item.operationType) &&
            !item.lifecycleState.isTerminal)
          item,
    ];
  }

  Future<void> _applyAuthoritativeActiveJobs(List<JobListItem> active) async {
    final host = _host;
    if (host == null) return;
    if (active.length > _leases.length) {
      try {
        await _reportExecutionHostStopForIds([
          for (final item in active) item.jobRunId,
        ], ExecutionHostStopReason.hostLost);
      } finally {
        await _invalidateLeasesAfterHostStop();
      }
      return;
    }
    while (_leases.length > active.length) {
      final lease = _leases.last;
      await host.releaseLease(lease);
      _leases.removeLast();
    }
    await _updateProjection(await _projectionFor(active));
  }

  Future<void> _reportExecutionHostStopForIds(
    List<JobRunId> jobRunIds,
    ExecutionHostStopReason reason,
  ) async {
    for (
      var offset = 0;
      offset < jobRunIds.length;
      offset += FrbExecutionHostControl.maxJobRunIds
    ) {
      final end =
          offset + FrbExecutionHostControl.maxJobRunIds < jobRunIds.length
          ? offset + FrbExecutionHostControl.maxJobRunIds
          : jobRunIds.length;
      await _executionHostControl.reportExecutionHostStop(
        jobRunIds: jobRunIds.sublist(offset, end),
        reason: reason,
      );
    }
  }

  Future<ForegroundExecutionProjection> _projectionFor(
    List<JobListItem> active,
  ) async {
    if (active.isEmpty) {
      return const ForegroundExecutionProjection(activeJobCount: 0);
    }
    var phase = active.length == 1 ? active.single.phase : null;
    final operationLabel = active.length == 1
        ? _foregroundOperationLabel(active.single.operationType)
        : 'Library work';
    int? completedUnits;
    int? totalUnits;
    String? statusKey;
    JobRunId? cancellableJobRunId;
    if (active.length == 1) {
      try {
        final detail = await _jobs.getJob(active.single.jobRunId);
        if (detail.job.controls.canCancel) {
          cancellableJobRunId = active.single.jobRunId;
        }
        if (detail.operationDetail case OperationDetailLibraryScan(
          :final detail,
        )) {
          phase ??= detail.progress.phase;
          completedUnits = detail.progress.completedUnits;
          totalUnits = detail.progress.totalUnits;
          statusKey = detail.progress.statusKey;
        } else {
          final progress = switch (detail.operationDetail) {
            OperationDetailLibraryRefresh(:final detail) => detail.progress,
            OperationDetailGameRefresh(:final detail) => detail.progress,
            OperationDetailLibraryResolutionRefresh(:final detail) =>
              detail.progress,
            OperationDetailLibraryScan() => null,
          };
          if (progress != null) {
            phase ??= progress.phase;
            completedUnits = progress.completedUnits;
            totalUnits = progress.totalUnits;
            statusKey = progress.statusKey;
          }
        }
      } catch (_) {
        // A bounded list read remains useful for count/projection even when a
        // detail read is temporarily unavailable; no cancel action is shown.
      }
    }
    return ForegroundExecutionProjection(
      activeJobCount: active.length,
      completedUnits: completedUnits,
      totalUnits: totalUnits,
      phase: phase,
      statusKey: statusKey,
      operationLabel: operationLabel,
      cancellableJobRunId: cancellableJobRunId,
    );
  }

  Future<void> _updateProjection(ForegroundExecutionProjection projection) {
    final host = _host;
    return host == null
        ? Future<void>.value()
        : host.updateProjection(projection);
  }

  Future<void> _releaseAllLeases() async {
    final host = _host;
    if (host == null) return;
    while (_leases.isNotEmpty) {
      final lease = _leases.last;
      await host.releaseLease(lease);
      _leases.removeLast();
    }
  }

  Future<void> _invalidateLeasesAfterHostStop() async {
    final host = _host;
    if (host == null) return;
    final leases = List<ForegroundExecutionLease>.of(_leases);
    _leases.clear();
    for (final lease in leases) {
      try {
        await host.releaseLease(lease);
      } catch (_) {
        // Host timeout/loss already invalidates local authority; stale native
        // releases are best-effort and never become durable Jobs state.
      }
    }
    try {
      await host.updateProjection(
        const ForegroundExecutionProjection(activeJobCount: 0),
      );
    } catch (_) {
      // Projection cleanup is secondary to the host-stop control report.
    }
  }
}

const Set<String> _foregroundOperationTypes = <String>{
  'library_scan',
  'library_refresh',
  'game_refresh',
  'library_resolution_refresh',
};

String _foregroundOperationLabel(String operationType) =>
    switch (operationType) {
      'library_scan' => 'Library scan',
      'library_refresh' => 'Library refresh',
      'game_refresh' => 'Game refresh',
      'library_resolution_refresh' => 'Metadata resolution',
      _ => 'Library work',
    };

/// Sources forwarding wrapper owned exclusively by app composition.
final class ForegroundHostedSourcesApi implements SourcesApi {
  const ForegroundHostedSourcesApi(this._coordinator, this._delegate);

  final ForegroundExecutionCoordinator _coordinator;
  final SourcesApi _delegate;

  @override
  Future<LibraryRootPage> listLibraryRoots({
    required int offset,
    required int pageSize,
  }) => _delegate.listLibraryRoots(offset: offset, pageSize: pageSize);

  @override
  Future<LibraryRoot> getLibraryRoot(LibraryRootId libraryRootId) =>
      _delegate.getLibraryRoot(libraryRootId);

  @override
  Future<AddLocalLibraryRootResult> addLocalLibraryRoot(
    LocalFilesystemRootSelection selection,
  ) => _delegate.addLocalLibraryRoot(selection);

  @override
  Future<AddLocalLibraryRootAndScanResult> addLocalLibraryRootAndScan(
    LocalFilesystemRootSelection selection,
  ) =>
      _coordinator.admit(() => _delegate.addLocalLibraryRootAndScan(selection));

  @override
  Future<RemoveLibraryRootResult> removeLibraryRoot(
    LibraryRootId libraryRootId,
  ) => _delegate.removeLibraryRoot(libraryRootId);

  @override
  Future<StartLibraryScanResult> startLibraryScan(
    LibraryRootId libraryRootId,
  ) => _coordinator.admit(() => _delegate.startLibraryScan(libraryRootId));

  @override
  Future<StartLibraryScanAllResult> startLibraryScanAll(
    ScanAllRequestIdentity requestIdentity,
  ) => _delegate.startLibraryScanAll(requestIdentity);

  @override
  Future<SourceEntryChildrenPage> listSourceEntryChildren({
    required LibraryRootId libraryRootId,
    SourceEntryId? parentSourceEntryId,
    String? cursor,
    required int pageSize,
  }) => _delegate.listSourceEntryChildren(
    libraryRootId: libraryRootId,
    parentSourceEntryId: parentSourceEntryId,
    cursor: cursor,
    pageSize: pageSize,
  );

  @override
  Future<SourceEntryDetail> getSourceEntry(SourceEntryId sourceEntryId) =>
      _delegate.getSourceEntry(sourceEntryId);

  @override
  Future<List<LocalFilesystemBrowseRoot>> listLocalFilesystemBrowseRoots() =>
      _delegate.listLocalFilesystemBrowseRoots();

  @override
  Future<LocalFilesystemBrowsePage> listLocalFilesystemBrowseDirectories({
    required LocalFilesystemBrowseLocation location,
    String? cursor,
    required int pageSize,
  }) => _delegate.listLocalFilesystemBrowseDirectories(
    location: location,
    cursor: cursor,
    pageSize: pageSize,
  );
}

/// Library refresh forwarding wrapper owned exclusively by app composition.
final class ForegroundHostedLibraryRefreshApi implements LibraryRefreshApi {
  const ForegroundHostedLibraryRefreshApi(this._coordinator, this._delegate);

  final ForegroundExecutionCoordinator _coordinator;
  final LibraryRefreshApi _delegate;

  @override
  Future<OperationHandle> startGameRefresh({
    required List<GameId> gameIds,
    required RefreshMode mode,
  }) => _coordinator.admit(
    () => _delegate.startGameRefresh(gameIds: gameIds, mode: mode),
  );

  @override
  Future<OperationHandle> refreshLibrary() =>
      _coordinator.admit(_delegate.refreshLibrary);
}

/// Jobs forwarding wrapper owned exclusively by app composition.
final class ForegroundHostedJobsApi implements JobsApi {
  const ForegroundHostedJobsApi(this._coordinator, this._delegate);

  final ForegroundExecutionCoordinator _coordinator;
  final JobsApi _delegate;

  @override
  Future<JobSummaryPage> listActiveJobs() => _delegate.listActiveJobs();

  @override
  Future<JobSummaryPage> listRecentTerminalJobs({
    required int offset,
    required int pageSize,
  }) => _delegate.listRecentTerminalJobs(offset: offset, pageSize: pageSize);

  @override
  Future<JobDetail> getJob(JobRunId jobRunId) => _delegate.getJob(jobRunId);

  @override
  Future<CancelJobResult> cancelJob(JobRunId jobRunId) =>
      _delegate.cancelJob(jobRunId);

  @override
  Future<RetryJobResult> retryJob(JobRunId jobRunId) =>
      _coordinator.retry(jobRunId);

  @override
  Future<LibraryRootScanAdmission?> getRootScanAdmission(
    LibraryRootId libraryRootId,
  ) => _delegate.getRootScanAdmission(libraryRootId);

  @override
  Future<LibraryScanAllRequestResolution> resolveScanAllRequest(
    ScanAllRequestIdentity requestIdentity,
  ) => _delegate.resolveScanAllRequest(requestIdentity);

  @override
  Future<ActiveJobSummary> getActiveJobSummary() =>
      _delegate.getActiveJobSummary();
}
