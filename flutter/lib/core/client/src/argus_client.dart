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
  bool _closed = false;

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
    _suppressStreamErrors = true;
    try {
      await _requestVoid(_gateway.generalShutdown);
    } finally {
      await _unbindEvents();
      _suppressStreamErrors = false;
    }
  }

  Future<AppearanceSettings> _getAppearanceSettings() =>
      _request(_gateway.getAppearanceSettings);

  Future<void> _updateAppearanceSettings(AppearanceSettings settings) =>
      _requestVoid(() => _gateway.updateAppearanceSettings(settings));

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
    final Stream<RuntimeEvent> stream;
    try {
      stream = _gateway.subscribeEvents(generation);
    } catch (error, stackTrace) {
      throw _asTransportFailure(error, stackTrace);
    }

    var terminalReported = false;
    late final StreamSubscription<RuntimeEvent> subscription;
    try {
      subscription = stream.listen(
        (event) {
          if (token != _subscriptionToken ||
              event.runtimeInstanceId != generation) {
            return;
          }
          _eventStream.add(event);
        },
        onError: (Object error, StackTrace stackTrace) {
          if (_suppressStreamErrors ||
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
          if (_suppressStreamErrors ||
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
    if (token == _subscriptionToken && !_closed) {
      _eventSubscription = subscription;
    } else {
      await subscription.cancel();
    }
  }

  void _scheduleReconnect(RuntimeInstanceId generation) {
    if (_suppressStreamErrors || _closed || _reconnectTask != null) return;
    final completer = Completer<void>();
    _reconnectTask = completer.future;
    scheduleMicrotask(() async {
      try {
        if (!_closed && _boundGeneration == generation) {
          await _bindEvents(generation, force: true);
        }
      } catch (error, stackTrace) {
        if (!_closed && _boundGeneration == generation) {
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
    await _unbindEvents();
    await _eventStream.close();
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
