import 'dart:async';

import 'package:argus/core/client/client.dart';
import 'package:argus/features/startup/startup.dart';

/// Deterministic [ClientBootstrap] fake with completers for every attempt.
final class FakeClientBootstrap implements ClientBootstrap {
  int initializeCalls = 0;
  final List<Completer<RuntimeState>> completers = <Completer<RuntimeState>>[];

  @override
  Future<RuntimeState> initialize() {
    initializeCalls++;
    final completer = Completer<RuntimeState>();
    completers.add(completer);
    return completer.future;
  }
}

/// One recorded runtime request with its completion handle.
final class FakeRuntimeRequest {
  FakeRuntimeRequest(this.runtimeInstanceId, this.completer);

  final RuntimeInstanceId runtimeInstanceId;
  final Completer<RuntimeState> completer;
}

/// Deterministic [RuntimeApi] fake.
final class FakeRuntimeApi implements RuntimeApi {
  RuntimeState getRuntimeStateResult = RuntimeState.ready(
    runtimeInstanceId: RuntimeInstanceId('f' * 32),
  );
  Object? getRuntimeStateError;
  Completer<RuntimeState>? getRuntimeStateCompleter;
  int getRuntimeStateCalls = 0;
  final List<FakeRuntimeRequest> retryRequests = <FakeRuntimeRequest>[];
  final List<FakeRuntimeRequest> resetRequests = <FakeRuntimeRequest>[];
  final List<FakeRuntimeRequest> exitRequests = <FakeRuntimeRequest>[];
  int generalShutdownCalls = 0;

  @override
  Future<RuntimeState> getRuntimeState() {
    getRuntimeStateCalls++;
    final error = getRuntimeStateError;
    if (error != null) {
      return Future<RuntimeState>.error(error);
    }
    final completer = getRuntimeStateCompleter;
    if (completer != null) {
      return completer.future;
    }
    return Future<RuntimeState>.value(getRuntimeStateResult);
  }

  @override
  Future<RuntimeState> retryStartup(RuntimeInstanceId expected) {
    final request = FakeRuntimeRequest(expected, Completer<RuntimeState>());
    retryRequests.add(request);
    return request.completer.future;
  }

  @override
  Future<RuntimeState> resetAppearanceSettings(RuntimeInstanceId expected) {
    final request = FakeRuntimeRequest(expected, Completer<RuntimeState>());
    resetRequests.add(request);
    return request.completer.future;
  }

  @override
  Future<RuntimeState> exitFailedRuntime(RuntimeInstanceId expected) {
    final request = FakeRuntimeRequest(expected, Completer<RuntimeState>());
    exitRequests.add(request);
    return request.completer.future;
  }

  @override
  Future<void> generalShutdown() {
    generalShutdownCalls++;
    return Future<void>.value();
  }
}

/// Deterministic [DiagnosticsApi] fake.
final class FakeDiagnosticsApi implements DiagnosticsApi {
  final List<FakeRuntimeRequest> exportRequests = <FakeRuntimeRequest>[];
  final List<FakeRuntimeRequest> detailsRequests = <FakeRuntimeRequest>[];
  final List<FakeRuntimeRequest> openRequests = <FakeRuntimeRequest>[];
  final List<String?> exportDestinations = <String?>[];
  DiagnosticsExport exportResult = const DiagnosticsExport(
    outcome: DiagnosticsExportOutcome.created,
    destinationClassification: 'user_selected',
  );
  TechnicalDetails detailsResult = const TechnicalDetails(text: 'safe details');

  @override
  Future<DiagnosticsExport> exportStartupDiagnostics(
    RuntimeInstanceId expected,
    String destination,
  ) {
    exportDestinations.add(destination);
    final request = FakeRuntimeRequest(expected, Completer<RuntimeState>());
    exportRequests.add(request);
    return request.completer.future.then(
      (_) => exportResult,
      onError: (Object error, StackTrace stackTrace) =>
          Future<DiagnosticsExport>.error(error, stackTrace),
    );
  }

  @override
  Future<TechnicalDetails> startupTechnicalDetails(RuntimeInstanceId expected) {
    final request = FakeRuntimeRequest(expected, Completer<RuntimeState>());
    detailsRequests.add(request);
    return request.completer.future.then(
      (_) => detailsResult,
      onError: (Object error, StackTrace stackTrace) =>
          Future<TechnicalDetails>.error(error, stackTrace),
    );
  }

  @override
  Future<void> openStartupDataDirectory(RuntimeInstanceId expected) {
    final request = FakeRuntimeRequest(expected, Completer<RuntimeState>());
    openRequests.add(request);
    return request.completer.future.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) =>
          Future<void>.error(error, stackTrace),
    );
  }
}

/// Deterministic mapped runtime-event projection fake.
final class FakeEventsApi implements EventsApi {
  final StreamController<RuntimeEvent> _controller =
      StreamController<RuntimeEvent>.broadcast();
  int totalListens = 0;
  int activeListens = 0;

  @override
  Stream<RuntimeEvent> get events => _controller.stream.asBroadcastStream(
    onListen: (_) {
      totalListens++;
      activeListens++;
    },
    onCancel: (_) {
      activeListens--;
    },
  );

  void emit(RuntimeEvent event) => _controller.add(event);

  void emitError(Object error) => _controller.addError(error);

  Future<void> close() => _controller.close();
}

/// Builds a valid runtime identity for tests.
RuntimeInstanceId testId(String fill) => RuntimeInstanceId(fill * 32);

/// Builds a typed application failure with the given code and message key.
ApplicationFailure applicationFailure({
  String code = 'ARGUS.V1.INTERNAL.UNEXPECTED',
  String messageKey = 'errors.internal.unexpected',
}) {
  return ApplicationFailure(
    ClientApplicationError(
      code: ErrorCode(code),
      category: ErrorCategory.internal,
      severity: ApplicationSeverity.error,
      recoverability: Recoverability.none,
      retryPolicy: RetryPolicy.never,
      messageKey: MessageKey(messageKey),
      traceId: const TraceId('01010101010101010101010101010101'),
      safeContext: const <SafeContextEntry>[],
    ),
  );
}

/// Builds a stale-generation application failure.
ApplicationFailure staleInstanceFailure() => applicationFailure(
  code: 'ARGUS.V1.RUNTIME.STALE_INSTANCE',
  messageKey: 'errors.runtime.stale_instance',
);

/// Builds a failed runtime snapshot with the supplied advertised actions.
RuntimeState failedRuntime({
  required String id,
  List<RecoveryActionKind> actions = const <RecoveryActionKind>[
    RecoveryActionKind.resetAppearanceSettings,
    RecoveryActionKind.retryStartup,
    RecoveryActionKind.exportDiagnostics,
    RecoveryActionKind.copyTechnicalDetails,
    RecoveryActionKind.openDataDirectory,
    RecoveryActionKind.exit,
  ],
}) {
  return RuntimeState.startupFailed(
    runtimeInstanceId: testId(id),
    failure: StartupFailure(
      phase: StartupPhase.settingsInitialization,
      error: ClientApplicationError(
        code: const ErrorCode(
          'ARGUS.V1.CONFIGURATION.PERSISTED_SETTINGS_INVALID',
        ),
        category: ErrorCategory.configuration,
        severity: ApplicationSeverity.error,
        recoverability: Recoverability.userAction,
        retryPolicy: RetryPolicy.userInitiated,
        messageKey: const MessageKey(
          'errors.configuration.persisted_settings_invalid',
        ),
        traceId: const TraceId('02020202020202020202020202020202'),
        safeContext: const <SafeContextEntry>[],
      ),
      recoveryActions: <RecoveryAction>[
        for (final kind in actions) RecoveryAction(kind: kind),
      ],
    ),
  );
}

/// Builds the frontend failed state for one generation.
StartupStateStartupFailed failedStartupState({
  required String id,
  List<RecoveryActionKind> actions = const <RecoveryActionKind>[
    RecoveryActionKind.resetAppearanceSettings,
    RecoveryActionKind.retryStartup,
    RecoveryActionKind.exportDiagnostics,
    RecoveryActionKind.copyTechnicalDetails,
    RecoveryActionKind.openDataDirectory,
    RecoveryActionKind.exit,
  ],
}) {
  final runtime =
      failedRuntime(id: id, actions: actions) as RuntimeStateStartupFailed;
  final state = StartupState.startupFailed(
    runtimeInstanceId: runtime.runtimeInstanceId,
    failure: runtime.failure,
    recoveryOperation: const RecoveryOperationState.idle(),
    exportOperation: const ExportOperationState.idle(),
    technicalDetails: const TechnicalDetailsOperationState.idle(),
    openDirectoryOperation: const OpenDirectoryOperationState.idle(),
  );
  return state as StartupStateStartupFailed;
}

/// Builds a runtime-unavailable frontend state.
StartupStateRuntimeUnavailable unavailableState({
  required String lastKnownId,
  ReconciliationOperationState reconciliation =
      const ReconciliationOperationState.idle(),
}) {
  final state = StartupState.runtimeUnavailable(
    cause: const TransportFailure('reconciliation failed'),
    lastKnownRuntime: StartupRuntimeContext(
      runtimeInstanceId: testId(lastKnownId),
      lifecycle: RuntimeLifecycle.startupFailed,
      phase: StartupPhase.settingsInitialization,
    ),
    reconciliationOperation: reconciliation,
  );
  return state as StartupStateRuntimeUnavailable;
}

/// Gateway fake whose native stream bind count is observable.
final class CountingGateway implements ArgusClientGateway {
  CountingGateway(this.id) : state = RuntimeState.ready(runtimeInstanceId: id);

  final RuntimeInstanceId id;
  RuntimeState state;
  int initializeCalls = 0;
  int listenCount = 0;
  int closeEventConnectionCalls = 0;
  final StreamController<RuntimeEvent> _events =
      StreamController<RuntimeEvent>.broadcast();

  @override
  Future<RuntimeState> initialize() {
    initializeCalls++;
    return Future<RuntimeState>.value(state);
  }

  @override
  Future<RuntimeState> getRuntimeState() => Future<RuntimeState>.value(state);

  @override
  Future<RuntimeState> retryStartup(RuntimeInstanceId expected) =>
      Future<RuntimeState>.value(state);

  @override
  Future<RuntimeState> resetAppearanceSettings(RuntimeInstanceId expected) =>
      Future<RuntimeState>.value(state);

  @override
  Future<RuntimeState> exitFailedRuntime(RuntimeInstanceId expected) =>
      Future<RuntimeState>.value(state);

  @override
  Future<void> generalShutdown() => Future<void>.value();

  @override
  Future<void> closeEventConnection() {
    closeEventConnectionCalls++;
    return Future<void>.value();
  }

  @override
  Future<AppearanceSettings> getAppearanceSettings() =>
      Future<AppearanceSettings>.value(
        const AppearanceSettings(themeMode: ThemeMode.system),
      );

  @override
  Future<void> updateAppearanceSettings(AppearanceSettings settings) =>
      Future<void>.value();

  @override
  Future<DiagnosticsExport> exportStartupDiagnostics(
    RuntimeInstanceId expected,
    String destination,
  ) => Future<DiagnosticsExport>.value(
    const DiagnosticsExport(
      outcome: DiagnosticsExportOutcome.created,
      destinationClassification: 'test',
    ),
  );

  @override
  Future<TechnicalDetails> startupTechnicalDetails(
    RuntimeInstanceId expected,
  ) => Future<TechnicalDetails>.value(const TechnicalDetails(text: 'details'));

  @override
  Future<void> openStartupDataDirectory(RuntimeInstanceId expected) =>
      Future<void>.value();

  @override
  Stream<RuntimeEvent> subscribeEvents(RuntimeInstanceId generation) {
    listenCount++;
    return _events.stream;
  }
}
