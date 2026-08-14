import 'dart:async';

import 'package:argus/app/bootstrap/client_bootstrap.dart';
import 'package:argus/core/client/client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'startup_state.dart';

part 'startup_controller.g.dart';

/// Machine-readable stale-generation error code.
const String _staleInstanceCode = 'ARGUS.V1.RUNTIME.STALE_INSTANCE';

/// One application-lifetime owner of pre-ready startup and recovery state.
///
/// The controller consumes only the initialization-only [ClientBootstrap]
/// seam, [RuntimeApi], [DiagnosticsApi], and the shared mapped runtime-event
/// projection. It never imports FRB types, bridge DTOs, routing, Flutter, or
/// platform APIs, and it never infers readiness from time or events.
@Riverpod(keepAlive: true)
class StartupController extends _$StartupController {
  int _bootstrapAttempt = 0;
  bool _bootstrapInFlight = false;
  int _mutationToken = 0;
  bool _mutationInFlight = false;
  int _reconcileToken = 0;
  bool _reconcileInFlight = false;
  int _eventToken = 0;
  StreamSubscription<RuntimeEvent>? _eventSubscription;

  @override
  AsyncValue<StartupState> build() {
    ref.onDispose(() {
      _eventToken++;
      _eventSubscription?.cancel();
    });
    ref.listen<EventsApi>(runtimeEventsProvider, (previous, next) {
      _subscribeToEvents(next);
    });
    _subscribeToEvents(ref.read(runtimeEventsProvider));
    unawaited(_initializeBootstrap());
    return const AsyncLoading();
  }

  /// Starts a fresh client/bootstrap attempt.
  ///
  /// The first call initializes the active root client; later calls replace
  /// the root client through the app-composition seam before initializing.
  Future<void> retryInitialization() => _initializeBootstrap();

  Future<void> _initializeBootstrap() async {
    if (_bootstrapInFlight) return;
    _bootstrapInFlight = true;
    final attempt = ++_bootstrapAttempt;
    try {
      final runtimeState = await ref.read(clientBootstrapProvider).initialize();
      if (!ref.mounted || attempt != _bootstrapAttempt) return;
      _adopt(runtimeState);
    } on ClientFailure catch (failure) {
      if (!ref.mounted || attempt != _bootstrapAttempt) return;
      // Lossless outer bootstrap failure: transport and application failures
      // keep their exact types and are never reclassified.
      state = AsyncError(failure, StackTrace.current);
    } finally {
      if (attempt == _bootstrapAttempt) {
        _bootstrapInFlight = false;
      }
    }
  }

  /// Retries the failed runtime through a fresh backend generation.
  Future<void> retryStartup() =>
      _runRuntimeMutation(RecoveryActionKind.retryStartup);

  /// Runs the dedicated targeted appearance recovery, then a fresh generation.
  Future<void> resetAppearanceSettings() =>
      _runRuntimeMutation(RecoveryActionKind.resetAppearanceSettings);

  /// Exits the failed runtime through the generation-bound capability.
  Future<void> requestExit() => _runRuntimeMutation(RecoveryActionKind.exit);

  Future<void> _runRuntimeMutation(RecoveryActionKind kind) async {
    final current = state.value;
    if (current is! StartupStateStartupFailed || _mutationInFlight) return;
    if (!_advertises(current, kind)) return;
    _mutationInFlight = true;
    final token = ++_mutationToken;
    final expectedId = current.runtimeInstanceId;
    state = AsyncData(
      current.copyWith(
        recoveryOperation: const RecoveryOperationState.running(),
      ),
    );
    try {
      final next = await _invokeMutation(
        ref.read(runtimeApiProvider),
        kind,
        expectedId,
      );
      if (!ref.mounted || token != _mutationToken) return;
      _adopt(next);
    } on ApplicationFailure catch (failure) {
      if (!ref.mounted || token != _mutationToken) return;
      if (_isStale(failure)) {
        state = AsyncData(
          current.copyWith(
            recoveryOperation: RecoveryOperationState.failed(failure),
          ),
        );
        unawaited(reconcileRuntime());
        return;
      }
      state = AsyncData(
        current.copyWith(
          recoveryOperation: RecoveryOperationState.failed(failure),
        ),
      );
    } on TransportFailure catch (failure) {
      if (!ref.mounted || token != _mutationToken) return;
      _enterUncertain(failure, _contextFor(current));
    } finally {
      if (token == _mutationToken) {
        _mutationInFlight = false;
      }
    }
  }

  Future<RuntimeState> _invokeMutation(
    RuntimeApi runtime,
    RecoveryActionKind kind,
    RuntimeInstanceId expectedId,
  ) {
    return switch (kind) {
      RecoveryActionKind.retryStartup => runtime.retryStartup(expectedId),
      RecoveryActionKind.resetAppearanceSettings =>
        runtime.resetAppearanceSettings(expectedId),
      RecoveryActionKind.exit => runtime.exitFailedRuntime(expectedId),
      _ => throw StateError('kind is not a runtime mutation: $kind'),
    };
  }

  /// Reads authoritative runtime state without replaying any prior mutation.
  Future<void> reconcileRuntime() async {
    if (_reconcileInFlight) return;
    _reconcileInFlight = true;
    final token = ++_reconcileToken;
    final current = state.value;
    final lastKnown = current is StartupStateRuntimeUnavailable
        ? current.lastKnownRuntime
        : current is StartupStateStartupFailed
        ? _contextFor(current)
        : null;
    if (current is StartupStateRuntimeUnavailable) {
      state = AsyncData(
        current.copyWith(
          reconciliationOperation: const ReconciliationOperationState.running(),
        ),
      );
    }
    try {
      final authoritative = await ref
          .read(runtimeApiProvider)
          .getRuntimeState();
      if (!ref.mounted || token != _reconcileToken) return;
      _adopt(authoritative);
    } on ClientFailure catch (failure) {
      if (!ref.mounted || token != _reconcileToken) return;
      final latest = state.value;
      if (latest is StartupStateRuntimeUnavailable) {
        state = AsyncData(
          latest.copyWith(
            reconciliationOperation: ReconciliationOperationState.failed(
              failure,
            ),
          ),
        );
      } else {
        state = AsyncData(
          StartupState.runtimeUnavailable(
            cause: failure,
            lastKnownRuntime: lastKnown,
            reconciliationOperation: ReconciliationOperationState.failed(
              failure,
            ),
          ),
        );
      }
    } finally {
      if (token == _reconcileToken) {
        _reconcileInFlight = false;
      }
    }
  }

  /// Exports sanitized backend diagnostics to a presentation-approved path.
  Future<void> exportDiagnostics({required String destination}) async {
    final current = state.value;
    if (current is! StartupStateStartupFailed || _mutationInFlight) return;
    if (current.exportOperation is ExportOperationStateRunning ||
        current.exportOperation is ExportOperationStateSucceeded) {
      return;
    }
    if (!_advertises(current, RecoveryActionKind.exportDiagnostics)) return;
    final expectedId = current.runtimeInstanceId;
    state = AsyncData(
      current.copyWith(exportOperation: const ExportOperationState.running()),
    );
    try {
      final result = await ref
          .read(diagnosticsApiProvider)
          .exportStartupDiagnostics(expectedId, destination);
      if (!ref.mounted) return;
      final latest = state.value;
      if (latest is! StartupStateStartupFailed ||
          latest.runtimeInstanceId != expectedId) {
        return;
      }
      state = AsyncData(
        latest.copyWith(
          exportOperation: ExportOperationState.succeeded(result),
        ),
      );
    } on ClientFailure catch (failure) {
      if (!ref.mounted) return;
      final latest = state.value;
      if (latest is! StartupStateStartupFailed ||
          latest.runtimeInstanceId != expectedId) {
        return;
      }
      if (_isStale(failure)) {
        state = AsyncData(
          latest.copyWith(
            exportOperation: ExportOperationState.failed(failure),
          ),
        );
        unawaited(reconcileRuntime());
        return;
      }
      state = AsyncData(
        latest.copyWith(exportOperation: ExportOperationState.failed(failure)),
      );
    }
  }

  /// Lazily loads generation-bound technical details for copy/display.
  Future<void> loadTechnicalDetails() async {
    final current = state.value;
    if (current is! StartupStateStartupFailed || _mutationInFlight) return;
    if (current.technicalDetails is TechnicalDetailsOperationStateLoading ||
        current.technicalDetails is TechnicalDetailsOperationStateLoaded) {
      return;
    }
    if (!_advertises(current, RecoveryActionKind.copyTechnicalDetails)) return;
    final expectedId = current.runtimeInstanceId;
    state = AsyncData(
      current.copyWith(
        technicalDetails: const TechnicalDetailsOperationState.loading(),
      ),
    );
    try {
      final details = await ref
          .read(diagnosticsApiProvider)
          .startupTechnicalDetails(expectedId);
      if (!ref.mounted) return;
      final latest = state.value;
      if (latest is! StartupStateStartupFailed ||
          latest.runtimeInstanceId != expectedId) {
        return;
      }
      state = AsyncData(
        latest.copyWith(
          technicalDetails: TechnicalDetailsOperationState.loaded(details),
        ),
      );
    } on ClientFailure catch (failure) {
      if (!ref.mounted) return;
      final latest = state.value;
      if (latest is! StartupStateStartupFailed ||
          latest.runtimeInstanceId != expectedId) {
        return;
      }
      if (_isStale(failure)) {
        state = AsyncData(
          latest.copyWith(
            technicalDetails: TechnicalDetailsOperationState.failed(failure),
          ),
        );
        unawaited(reconcileRuntime());
        return;
      }
      state = AsyncData(
        latest.copyWith(
          technicalDetails: TechnicalDetailsOperationState.failed(failure),
        ),
      );
    }
  }

  /// Invokes the advertised open-data-directory capability.
  Future<void> openDataDirectory() async {
    final current = state.value;
    if (current is! StartupStateStartupFailed || _mutationInFlight) return;
    if (current.openDirectoryOperation is OpenDirectoryOperationStateRunning) {
      return;
    }
    if (!_advertises(current, RecoveryActionKind.openDataDirectory)) return;
    final expectedId = current.runtimeInstanceId;
    state = AsyncData(
      current.copyWith(
        openDirectoryOperation: const OpenDirectoryOperationState.running(),
      ),
    );
    try {
      await ref
          .read(diagnosticsApiProvider)
          .openStartupDataDirectory(expectedId);
      if (!ref.mounted) return;
      final latest = state.value;
      if (latest is! StartupStateStartupFailed ||
          latest.runtimeInstanceId != expectedId) {
        return;
      }
      state = AsyncData(
        latest.copyWith(
          openDirectoryOperation: const OpenDirectoryOperationState.idle(),
        ),
      );
    } on ClientFailure catch (failure) {
      if (!ref.mounted) return;
      final latest = state.value;
      if (latest is! StartupStateStartupFailed ||
          latest.runtimeInstanceId != expectedId) {
        return;
      }
      if (_isStale(failure)) {
        state = AsyncData(
          latest.copyWith(
            openDirectoryOperation: OpenDirectoryOperationState.failed(failure),
          ),
        );
        unawaited(reconcileRuntime());
        return;
      }
      state = AsyncData(
        latest.copyWith(
          openDirectoryOperation: OpenDirectoryOperationState.failed(failure),
        ),
      );
    }
  }

  void _adopt(RuntimeState runtimeState) {
    final next = switch (runtimeState) {
      RuntimeStateUninitialized(:final runtimeInstanceId) =>
        StartupState.uninitialized(runtimeInstanceId: runtimeInstanceId),
      RuntimeStateStarting(:final runtimeInstanceId, :final phase) =>
        StartupState.starting(
          runtimeInstanceId: runtimeInstanceId,
          phase: phase,
        ),
      RuntimeStateReady(:final runtimeInstanceId) => StartupState.ready(
        runtimeInstanceId: runtimeInstanceId,
      ),
      RuntimeStateStartupFailed(:final runtimeInstanceId, :final failure) =>
        _adoptFailed(runtimeInstanceId, failure),
      RuntimeStateShuttingDown(:final runtimeInstanceId) =>
        StartupState.shuttingDown(runtimeInstanceId: runtimeInstanceId),
      RuntimeStateStopped(:final runtimeInstanceId) => StartupState.stopped(
        runtimeInstanceId: runtimeInstanceId,
      ),
    };
    state = AsyncData(next);
  }

  /// Adopts a failed runtime snapshot.
  ///
  /// A same-generation authoritative refresh preserves generation-bound local
  /// state (cached details, export/open-directory results, recovery errors);
  /// only a replacement generation resets that state to idle.
  StartupState _adoptFailed(
    RuntimeInstanceId runtimeInstanceId,
    StartupFailure failure,
  ) {
    final current = state.value;
    if (current is StartupStateStartupFailed &&
        current.runtimeInstanceId == runtimeInstanceId) {
      return current.copyWith(failure: failure);
    }
    return StartupState.startupFailed(
      runtimeInstanceId: runtimeInstanceId,
      failure: failure,
      recoveryOperation: const RecoveryOperationState.idle(),
      exportOperation: const ExportOperationState.idle(),
      technicalDetails: const TechnicalDetailsOperationState.idle(),
      openDirectoryOperation: const OpenDirectoryOperationState.idle(),
    );
  }

  void _enterUncertain(ClientFailure cause, StartupRuntimeContext lastKnown) {
    state = AsyncData(
      StartupState.runtimeUnavailable(
        cause: cause,
        lastKnownRuntime: lastKnown,
        reconciliationOperation: const ReconciliationOperationState.running(),
      ),
    );
    unawaited(reconcileRuntime());
  }

  void _subscribeToEvents(EventsApi events) {
    _eventSubscription?.cancel();
    final token = ++_eventToken;
    _eventSubscription = events.events.listen(
      (event) {
        if (token != _eventToken) return;
        final payload = event.payload;
        // Only runtime/startup notifications are reconciliation hints.
        // AppearanceSettingsChanged is deliberately ignored in this slice.
        if (payload is RuntimeEventPayloadRuntimeStateChanged ||
            payload is RuntimeEventPayloadStartupFailed) {
          unawaited(_reconcileFromEvent());
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        // Event/stream degradation never regresses startup authority;
        // request/response reads remain the correctness path.
      },
      onDone: () {
        // The root client owns native reconnection; the provider-change
        // listener below owns resubscription after a root-client replacement.
        // A closed mapped stream must never trigger a recursive resubscription
        // loop.
      },
      cancelOnError: false,
    );
  }

  Future<void> _reconcileFromEvent() async {
    // Runtime A lifecycle notifications published while a generation-changing
    // mutation is in flight are intermediates; the mutation's returned
    // RuntimeState remains authoritative.
    if (_mutationInFlight) return;
    final current = state.value;
    // Once Ready has admitted the shell, later notifications or transient
    // transport degradation must not return the app to the pre-ready gate.
    if (current is StartupStateReady || current is StartupStateStopped) return;
    await reconcileRuntime();
  }

  bool _advertises(StartupStateStartupFailed state, RecoveryActionKind kind) =>
      state.failure.recoveryActions.any((action) => action.kind == kind);

  bool _isStale(ClientFailure failure) =>
      failure is ApplicationFailure &&
      failure.error.code.value == _staleInstanceCode;

  StartupRuntimeContext _contextFor(StartupStateStartupFailed state) =>
      StartupRuntimeContext(
        runtimeInstanceId: state.runtimeInstanceId,
        lifecycle: RuntimeLifecycle.startupFailed,
        phase: state.failure.phase,
      );
}
