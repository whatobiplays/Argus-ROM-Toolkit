import 'dart:async';

import 'failures.dart';
import 'models.dart';
import 'ports.dart';

/// Root pure-Dart client. It owns native connectivity, generation-aware event
/// binding, and typed failure translation while remaining independent of
/// Flutter, Riverpod, and generated FRB transport types.
final class ArgusClient implements ClientBootstrap {
  ArgusClient({required ArgusClientGateway gateway})
    // The public seam keeps callers independent of the private field name.
    // ignore: prefer_initializing_formals
    : _gateway = gateway {
    runtime = _RuntimeApi(this);
    settings = _SettingsApi(this);
    sources = _SourcesApi(this);
    jobs = _JobsApi(this);
    diagnostics = _DiagnosticsApi(this);
    events = _EventsApi(this);
  }

  final ArgusClientGateway _gateway;
  final StreamController<RuntimeEvent> _eventStream =
      StreamController<RuntimeEvent>.broadcast();

  /// Runtime/startup/recovery operations owned by this root client.
  late final RuntimeApi runtime;

  /// Appearance-settings operations owned by this root client.
  late final SettingsApi settings;

  /// Configured library-root operations owned by this root client.
  late final SourcesApi sources;

  /// Durable job observation and control operations owned by this root client.
  late final JobsApi jobs;

  /// Failed-startup diagnostics operations owned by this root client.
  late final DiagnosticsApi diagnostics;

  /// Mapped runtime notifications owned by this root client.
  late final EventsApi events;

  StreamSubscription<RuntimeEvent>? _eventSubscription;
  Future<void>? _bindingTask;
  Future<void>? _reconnectTask;
  RuntimeInstanceId? _boundGeneration;
  int _subscriptionToken = 0;
  bool _suppressStreamErrors = false;
  bool _shuttingDown = false;
  bool _closed = false;
  ClientFailure? _lateBindCloseFailure;

  /// The currently bound runtime generation, if initialization has completed.
  RuntimeInstanceId? get boundGeneration => _boundGeneration;

  @override
  Future<RuntimeState> initialize() async {
    final state = await _request(_gateway.initialize);
    await _bindEvents(_runtimeId(state));
    return state;
  }

  /// Explicitly reconnects the current generation after a transport error.
  /// Concurrent calls are serialized so only one native connection is active.
  Future<void> reconnectEvents() async {
    if (_shuttingDown || _closed) return;
    final generation = _boundGeneration;
    if (generation == null) return;
    await _bindEvents(generation, force: true);
  }

  Future<RuntimeState> _getRuntimeState() => _request(_gateway.getRuntimeState);

  Future<RuntimeState> _retryStartup(RuntimeInstanceId expected) async {
    _suppressStreamErrors = true;
    try {
      final state = await _request(() => _gateway.retryStartup(expected));
      await _bindEvents(_runtimeId(state));
      return state;
    } finally {
      _suppressStreamErrors = false;
    }
  }

  Future<RuntimeState> _resetAppearanceSettings(
    RuntimeInstanceId expected,
  ) async {
    _suppressStreamErrors = true;
    try {
      final state = await _request(
        () => _gateway.resetAppearanceSettings(expected),
      );
      await _bindEvents(_runtimeId(state));
      return state;
    } finally {
      _suppressStreamErrors = false;
    }
  }

  Future<RuntimeState> _exitFailedRuntime(RuntimeInstanceId expected) async {
    _suppressStreamErrors = true;
    try {
      final state = await _request(() => _gateway.exitFailedRuntime(expected));
      await _unbindEvents();
      return state;
    } finally {
      _suppressStreamErrors = false;
    }
  }

  Future<void> _generalShutdown() async {
    _shuttingDown = true;
    _suppressStreamErrors = true;
    Object? shutdownError;
    try {
      await _requestVoid(_gateway.generalShutdown);
    } catch (error, stackTrace) {
      shutdownError = error is ClientFailure
          ? error
          : TransportFailure(
              'Native general shutdown failed',
              cause: error,
              stackTrace: stackTrace,
            );
    } finally {
      Object? closeError;
      try {
        // Close/invalidate the native event connection before awaiting local
        // cancellation so a failed or racing shutdown cannot leave the FRB
        // subscription parked.
        await _gateway.closeEventConnection();
      } catch (error, stackTrace) {
        closeError = error is ClientFailure
            ? error
            : TransportFailure(
                'Native event connection could not be closed',
                cause: error,
                stackTrace: stackTrace,
              );
      }
      try {
        // Await a bind in flight so its stale-branch cleanup can close any
        // native connection established after shutdown closed the boundary.
        await _bindingTask;
      } catch (_) {
        // Bind errors during shutdown are already represented by the close
        // handling above; the in-flight task must never block shutdown.
      }
      final lateCloseFailure = _lateBindCloseFailure;
      _lateBindCloseFailure = null;
      if (lateCloseFailure != null) {
        // A late cleanup-close failure keeps close-error precedence: primary
        // shutdown error still wins, and this outranks Dart cancellation.
        closeError ??= lateCloseFailure;
      }
      Object? cancelError;
      try {
        await _unbindEvents();
      } catch (error, stackTrace) {
        cancelError = error is ClientFailure
            ? error
            : TransportFailure(
                'Native event subscription could not be cancelled',
                cause: error,
                stackTrace: stackTrace,
              );
      }
      _suppressStreamErrors = false;
      if (shutdownError case final Object error) throw error;
      if (closeError case final Object error) throw error;
      if (cancelError case final Object error) throw error;
    }
  }

  Future<AppearanceSettings> _getAppearanceSettings() =>
      _request(_gateway.getAppearanceSettings);

  Future<void> _updateAppearanceSettings(AppearanceSettings settings) =>
      _requestVoid(() => _gateway.updateAppearanceSettings(settings));

  Future<LibraryRootPage> _listLibraryRoots({
    required int offset,
    required int pageSize,
  }) => _request(
    () => _gateway.listLibraryRoots(offset: offset, pageSize: pageSize),
  );

  Future<LibraryRoot> _getLibraryRoot(LibraryRootId libraryRootId) =>
      _request(() => _gateway.getLibraryRoot(libraryRootId));

  Future<AddLocalLibraryRootResult> _addLocalLibraryRoot(
    LocalFilesystemRootSelection selection,
  ) => _request(() => _gateway.addLocalLibraryRoot(selection));

  Future<AddLocalLibraryRootAndScanResult> _addLocalLibraryRootAndScan(
    LocalFilesystemRootSelection selection,
  ) => _request(() => _gateway.addLocalLibraryRootAndScan(selection));

  Future<RemoveLibraryRootResult> _removeLibraryRoot(
    LibraryRootId libraryRootId,
  ) => _request(() => _gateway.removeLibraryRoot(libraryRootId));

  Future<StartLibraryScanResult> _startLibraryScan(
    LibraryRootId libraryRootId,
  ) => _request(() => _gateway.startLibraryScan(libraryRootId));

  Future<StartLibraryScanAllResult> _startLibraryScanAll(
    ScanAllRequestIdentity requestIdentity,
  ) => _request(() => _gateway.startLibraryScanAll(requestIdentity));

  Future<SourceEntryChildrenPage> _listSourceEntryChildren({
    required LibraryRootId libraryRootId,
    SourceEntryId? parentSourceEntryId,
    String? cursor,
    required int pageSize,
  }) => _request(
    () => _gateway.listSourceEntryChildren(
      libraryRootId: libraryRootId,
      parentSourceEntryId: parentSourceEntryId,
      cursor: cursor,
      pageSize: pageSize,
    ),
  );

  Future<SourceEntryDetail> _getSourceEntry(SourceEntryId sourceEntryId) =>
      _request(() => _gateway.getSourceEntry(sourceEntryId));

  Future<JobSummaryPage> _listActiveJobs() => _request(_gateway.listActiveJobs);

  Future<JobSummaryPage> _listRecentTerminalJobs({
    required int offset,
    required int pageSize,
  }) => _request(
    () => _gateway.listRecentTerminalJobs(offset: offset, pageSize: pageSize),
  );

  Future<JobDetail> _getJob(JobRunId jobRunId) =>
      _request(() => _gateway.getJob(jobRunId));

  Future<CancelJobResult> _cancelJob(JobRunId jobRunId) =>
      _request(() => _gateway.cancelJob(jobRunId));

  Future<RetryJobResult> _retryJob(JobRunId jobRunId) =>
      _request(() => _gateway.retryJob(jobRunId));

  Future<LibraryRootScanAdmission?> _getRootScanAdmission(
    LibraryRootId libraryRootId,
  ) => _request(() => _gateway.getRootScanAdmission(libraryRootId));

  Future<LibraryScanAllRequestResolution> _resolveScanAllRequest(
    ScanAllRequestIdentity requestIdentity,
  ) => _request(() => _gateway.resolveScanAllRequest(requestIdentity));

  Future<DiagnosticsExport> _exportStartupDiagnostics(
    RuntimeInstanceId expected,
    String destination,
  ) => _request(() => _gateway.exportStartupDiagnostics(expected, destination));

  Future<TechnicalDetails> _startupTechnicalDetails(
    RuntimeInstanceId expected,
  ) => _request(() => _gateway.startupTechnicalDetails(expected));

  Future<void> _openStartupDataDirectory(RuntimeInstanceId expected) =>
      _requestVoid(() => _gateway.openStartupDataDirectory(expected));

  Future<T> _request<T>(Future<T> Function() operation) async {
    _ensureOpen();
    try {
      return await operation();
    } on ClientFailure {
      rethrow;
    } catch (error, stackTrace) {
      throw TransportFailure(
        'Native request transport failed',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _requestVoid(Future<void> Function() operation) async {
    await _request<void>(operation);
  }

  /// Serializes native binding changes. A force reconnect waits for any
  /// previous bind to finish, so replacing a stream can never overlap it.
  Future<void> _bindEvents(RuntimeInstanceId generation, {bool force = false}) {
    _ensureOpen();
    if (_shuttingDown) {
      throw const TransportFailure('ArgusClient is shutting down');
    }
    final previous = _bindingTask ?? Future<void>.value();
    late final Future<void> tracked;
    final task = previous.then((_) => _performBind(generation, force: force));
    tracked = task.whenComplete(() {
      if (identical(_bindingTask, tracked)) _bindingTask = null;
    });
    _bindingTask = tracked;
    return tracked;
  }

  Future<void> _performBind(
    RuntimeInstanceId generation, {
    required bool force,
  }) async {
    if (!force &&
        _boundGeneration == generation &&
        _eventSubscription != null) {
      return;
    }

    final oldSubscription = _eventSubscription;
    _eventSubscription = null;
    ++_subscriptionToken;
    await oldSubscription?.cancel();
    _ensureOpen();

    _boundGeneration = generation;
    final token = _subscriptionToken;
    // The gateway future completes only after the one native event connection
    // for this generation has attached; initialize/reconnect therefore never
    // reports binding usable while a committed change could fall into the
    // pre-attachment gap.
    final EventBindResult bind;
    try {
      bind = await _gateway.subscribeEvents(generation);
    } catch (error, stackTrace) {
      throw _asTransportFailure(error, stackTrace);
    }
    if (token != _subscriptionToken || _closed || _shuttingDown) {
      // A newer bind or teardown superseded this attempt. If this attempt
      // established a native connection after teardown began, close it now:
      // Dart-side cancellation alone cannot be assumed to release the parked
      // native receive loop, and teardown awaits this task before completing.
      if (bind.nativeAttached) {
        try {
          await _gateway.closeEventConnection();
        } catch (error, stackTrace) {
          // The cleanup close still physically released the connection, but
          // its typed failure must reach teardown with close-error precedence.
          // Record it here and keep cleaning up the stale stream regardless.
          _lateBindCloseFailure = error is ClientFailure
              ? error
              : TransportFailure(
                  'Native event connection could not be closed',
                  cause: error,
                  stackTrace: stackTrace,
                );
        }
      }
      final stale = bind.stream.listen(
        (_) {},
        onError: (Object _, StackTrace _) {},
      );
      try {
        await stale.cancel();
      } catch (_) {
        // The stale stream's cancellation is teardown cleanup; its failure is
        // secondary to any recorded cleanup-close failure and must not fail
        // the racing caller.
      }
      return;
    }

    var terminalReported = false;
    late final StreamSubscription<RuntimeEvent> subscription;
    try {
      subscription = bind.stream.listen(
        (event) {
          if (token != _subscriptionToken ||
              event.runtimeInstanceId != generation) {
            return;
          }
          _eventStream.add(event);
        },
        onError: (Object error, StackTrace stackTrace) {
          if (_shuttingDown ||
              _suppressStreamErrors ||
              token != _subscriptionToken ||
              terminalReported) {
            return;
          }
          terminalReported = true;
          _eventSubscription = null;
          _eventStream.addError(
            _asTransportFailure(error, stackTrace),
            stackTrace,
          );
          _scheduleReconnect(generation);
        },
        onDone: () {
          if (_shuttingDown ||
              _suppressStreamErrors ||
              token != _subscriptionToken ||
              terminalReported) {
            return;
          }
          terminalReported = true;
          _eventSubscription = null;
          _eventStream.addError(
            const TransportFailure('Native runtime event stream closed'),
          );
          _scheduleReconnect(generation);
        },
        cancelOnError: false,
      );
    } catch (error, stackTrace) {
      throw _asTransportFailure(error, stackTrace);
    }
    if (token == _subscriptionToken && !_closed && !_shuttingDown) {
      _eventSubscription = subscription;
    } else {
      await subscription.cancel();
    }
  }

  void _scheduleReconnect(RuntimeInstanceId generation) {
    if (_shuttingDown ||
        _suppressStreamErrors ||
        _closed ||
        _reconnectTask != null) {
      return;
    }
    final completer = Completer<void>();
    _reconnectTask = completer.future;
    scheduleMicrotask(() async {
      try {
        if (!_shuttingDown && !_closed && _boundGeneration == generation) {
          await _bindEvents(generation, force: true);
        }
      } catch (error, stackTrace) {
        if (!_shuttingDown && !_closed && _boundGeneration == generation) {
          _eventStream.addError(_asTransportFailure(error, stackTrace));
        }
      } finally {
        if (identical(_reconnectTask, completer.future)) {
          _reconnectTask = null;
        }
        completer.complete();
      }
    });
  }

  Future<void> _unbindEvents() async {
    ++_subscriptionToken;
    final subscription = _eventSubscription;
    _eventSubscription = null;
    await subscription?.cancel();
    _boundGeneration = null;
  }

  RuntimeInstanceId _runtimeId(RuntimeState state) {
    final id = state.map(
      uninitialized: (value) => value.runtimeInstanceId,
      starting: (value) => value.runtimeInstanceId,
      ready: (value) => value.runtimeInstanceId,
      startupFailed: (value) => value.runtimeInstanceId,
      shuttingDown: (value) => value.runtimeInstanceId,
      stopped: (value) => value.runtimeInstanceId,
    );
    if (!id.isValid) {
      throw const TransportFailure(
        'Native runtime identity is invalid',
        kind: TransportFailureKind.contractMismatch,
      );
    }
    return id;
  }

  TransportFailure _asTransportFailure(Object error, StackTrace stackTrace) {
    if (error is TransportFailure) return error;
    return TransportFailure(
      'Native runtime event transport failed',
      cause: error,
      stackTrace: stackTrace,
    );
  }

  void _ensureOpen() {
    if (_closed) {
      throw const TransportFailure('ArgusClient is closed');
    }
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    _shuttingDown = true;
    Object? teardownError;
    // A pending bind/reconnect also owns (or is about to own) the native
    // connection, so teardown must close it even before the Dart subscription
    // exists; otherwise the native attach could linger past disposal.
    final hadEventConnection =
        _eventSubscription != null || _bindingTask != null;
    if (hadEventConnection) {
      try {
        // Close the native event connection first so a parked FRB subscription
        // can return before the Dart-side stream is cancelled.
        await _gateway.closeEventConnection();
      } catch (error, stackTrace) {
        teardownError = error is ClientFailure
            ? error
            : TransportFailure(
                'Native event connection could not be closed',
                cause: error,
                stackTrace: stackTrace,
              );
      }
    }
    try {
      // A bind in flight may resume after the close and attach with the
      // post-close admission epoch. Teardown must await that task so its
      // stale-branch cleanup closes any late native connection before a
      // replacement client can bind.
      await _bindingTask;
    } catch (_) {
      // Bind errors during teardown are already represented by the close
      // handling above; the in-flight task must never block disposal.
    }
    final lateCloseFailure = _lateBindCloseFailure;
    _lateBindCloseFailure = null;
    if (lateCloseFailure != null) {
      // The stale bind's cleanup close failed after teardown began: surface it
      // with close-error precedence (after a first-close error, before any
      // Dart cancellation error).
      teardownError ??= lateCloseFailure;
    }
    try {
      await _unbindEvents();
    } catch (error, stackTrace) {
      teardownError ??= error is ClientFailure
          ? error
          : TransportFailure(
              'Native event subscription could not be cancelled',
              cause: error,
              stackTrace: stackTrace,
            );
    }
    await _eventStream.close();
    if (teardownError case final Object error) {
      throw error;
    }
  }
}

final class _RuntimeApi implements RuntimeApi {
  _RuntimeApi(this._client);

  final ArgusClient _client;

  @override
  Future<RuntimeState> getRuntimeState() => _client._getRuntimeState();

  @override
  Future<RuntimeState> retryStartup(RuntimeInstanceId expected) =>
      _client._retryStartup(expected);

  @override
  Future<RuntimeState> resetAppearanceSettings(RuntimeInstanceId expected) =>
      _client._resetAppearanceSettings(expected);

  @override
  Future<RuntimeState> exitFailedRuntime(RuntimeInstanceId expected) =>
      _client._exitFailedRuntime(expected);

  @override
  Future<void> generalShutdown() => _client._generalShutdown();
}

final class _SettingsApi implements SettingsApi {
  _SettingsApi(this._client);

  final ArgusClient _client;

  @override
  Future<AppearanceSettings> getAppearanceSettings() =>
      _client._getAppearanceSettings();

  @override
  Future<void> updateAppearanceSettings(AppearanceSettings settings) =>
      _client._updateAppearanceSettings(settings);
}

final class _SourcesApi implements SourcesApi {
  _SourcesApi(this._client);

  final ArgusClient _client;

  @override
  Future<LibraryRootPage> listLibraryRoots({
    required int offset,
    required int pageSize,
  }) => _client._listLibraryRoots(offset: offset, pageSize: pageSize);

  @override
  Future<LibraryRoot> getLibraryRoot(LibraryRootId libraryRootId) =>
      _client._getLibraryRoot(libraryRootId);

  @override
  Future<AddLocalLibraryRootResult> addLocalLibraryRoot(
    LocalFilesystemRootSelection selection,
  ) => _client._addLocalLibraryRoot(selection);

  @override
  Future<AddLocalLibraryRootAndScanResult> addLocalLibraryRootAndScan(
    LocalFilesystemRootSelection selection,
  ) => _client._addLocalLibraryRootAndScan(selection);

  @override
  Future<RemoveLibraryRootResult> removeLibraryRoot(
    LibraryRootId libraryRootId,
  ) => _client._removeLibraryRoot(libraryRootId);

  @override
  Future<StartLibraryScanResult> startLibraryScan(
    LibraryRootId libraryRootId,
  ) => _client._startLibraryScan(libraryRootId);

  @override
  Future<StartLibraryScanAllResult> startLibraryScanAll(
    ScanAllRequestIdentity requestIdentity,
  ) => _client._startLibraryScanAll(requestIdentity);

  @override
  Future<SourceEntryChildrenPage> listSourceEntryChildren({
    required LibraryRootId libraryRootId,
    SourceEntryId? parentSourceEntryId,
    String? cursor,
    required int pageSize,
  }) => _client._listSourceEntryChildren(
    libraryRootId: libraryRootId,
    parentSourceEntryId: parentSourceEntryId,
    cursor: cursor,
    pageSize: pageSize,
  );

  @override
  Future<SourceEntryDetail> getSourceEntry(SourceEntryId sourceEntryId) =>
      _client._getSourceEntry(sourceEntryId);
}

final class _JobsApi implements JobsApi {
  _JobsApi(this._client);

  final ArgusClient _client;

  @override
  Future<JobSummaryPage> listActiveJobs() => _client._listActiveJobs();

  @override
  Future<JobSummaryPage> listRecentTerminalJobs({
    required int offset,
    required int pageSize,
  }) => _client._listRecentTerminalJobs(offset: offset, pageSize: pageSize);

  @override
  Future<JobDetail> getJob(JobRunId jobRunId) => _client._getJob(jobRunId);

  @override
  Future<CancelJobResult> cancelJob(JobRunId jobRunId) =>
      _client._cancelJob(jobRunId);

  @override
  Future<RetryJobResult> retryJob(JobRunId jobRunId) =>
      _client._retryJob(jobRunId);

  @override
  Future<LibraryRootScanAdmission?> getRootScanAdmission(
    LibraryRootId libraryRootId,
  ) => _client._getRootScanAdmission(libraryRootId);

  @override
  Future<LibraryScanAllRequestResolution> resolveScanAllRequest(
    ScanAllRequestIdentity requestIdentity,
  ) => _client._resolveScanAllRequest(requestIdentity);

  @override
  Future<ActiveJobSummary> getActiveJobSummary() async {
    final active = await _client._listActiveJobs();
    return ActiveJobSummary(
      activeCount: active.items.length,
      soleActiveJobRunId: active.items.length == 1
          ? active.items.single.jobRunId
          : null,
    );
  }
}

final class _DiagnosticsApi implements DiagnosticsApi {
  _DiagnosticsApi(this._client);

  final ArgusClient _client;

  @override
  Future<DiagnosticsExport> exportStartupDiagnostics(
    RuntimeInstanceId expected,
    String destination,
  ) => _client._exportStartupDiagnostics(expected, destination);

  @override
  Future<TechnicalDetails> startupTechnicalDetails(
    RuntimeInstanceId expected,
  ) => _client._startupTechnicalDetails(expected);

  @override
  Future<void> openStartupDataDirectory(RuntimeInstanceId expected) =>
      _client._openStartupDataDirectory(expected);
}

final class _EventsApi implements EventsApi {
  _EventsApi(this._client);

  final ArgusClient _client;

  @override
  Stream<RuntimeEvent> get events => _client._eventStream.stream;
}
