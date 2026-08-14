import 'dart:async';
import 'dart:io';

import 'package:argus/core/bridge/generated/frb_generated.dart' as frb;
import 'package:argus/core/bridge/generated/lib.dart' as dto;
import 'package:argus/core/client/client.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated_io.dart'
    as frb_io;

/// FRB 2.12 adapter translating generated transport types into pure-Dart
/// client models and typed application/transport failures.
final class FrbArgusClientGateway implements ArgusClientGateway {
  FrbArgusClientGateway({
    frb.RustLibApi? api,
    Future<void> Function()? initializeNative,
    String? dataDirectoryOverride,
    Stream<dto.RuntimeEventDto> Function()? eventStreamFactory,
  }) : // The public seam keeps callers independent of private field names.
       // ignore: prefer_initializing_formals
       _api = api,
       _initializeNative = initializeNative ?? _initializeFrb,
       // ignore: prefer_initializing_formals
       _dataDirectoryOverride = dataDirectoryOverride,
       // ignore: prefer_initializing_formals
       _eventStreamFactory = eventStreamFactory;

  final frb.RustLibApi? _api;
  final Future<void> Function() _initializeNative;
  final String? _dataDirectoryOverride;
  final Stream<dto.RuntimeEventDto> Function()? _eventStreamFactory;
  Future<void>? _initialization;

  // The generated entrypoint intentionally exposes its initialized API via an
  // internal getter; this adapter is the only place that reaches it.
  // ignore: invalid_use_of_internal_member
  frb.RustLibApi get _rustApi => _api ?? frb.RustLib.instance.api;

  Future<void> _ensureInitialized() {
    return _initialization ??= _initializeNative().catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      throw TransportFailure(
        'Native bridge is unavailable',
        kind: TransportFailureKind.bridgeUnavailable,
        cause: error,
        stackTrace: stackTrace,
      );
    });
  }

  /// Uses process-linked symbols on macOS and the conventional executable
  /// sibling library location on Windows/Linux. The generated FRB loader
  /// remains the fallback for development/test layouts.
  static Future<void> _initializeFrb() async {
    if (Platform.isMacOS) {
      await frb.RustLib.init(
        externalLibrary: frb_io.ExternalLibrary.process(iKnowHowToUseIt: true),
      );
      return;
    }
    final executableDirectory = File(Platform.resolvedExecutable).parent.path;
    final libraryName = Platform.isWindows
        ? 'argus_bridge.dll'
        : 'libargus_bridge.so';
    final candidate = Platform.isLinux
        ? File('$executableDirectory/lib/$libraryName')
        : File('$executableDirectory/$libraryName');
    await frb.RustLib.init(
      externalLibrary: candidate.existsSync()
          ? frb_io.ExternalLibrary.open(candidate.path)
          : null,
    );
  }

  @override
  Future<RuntimeState> getRuntimeState() => _call(
    () async => runtimeStateFromDto(await _rustApi.crateGetRuntimeState()),
  );

  @override
  Future<RuntimeState> initialize() => _call(() async {
    final dto = _dataDirectoryOverride == null
        ? await _rustApi.crateInitialize()
        : await _rustApi.crateInitializeWithDataDirectory(
            dataDirectory: _dataDirectoryOverride,
          );
    return runtimeStateFromDto(dto);
  });

  @override
  Future<RuntimeState> retryStartup(RuntimeInstanceId expected) => _call(
    () async => runtimeStateFromDto(
      await _rustApi.crateRetryStartup(
        expectedRuntimeInstanceId: expected.value,
      ),
    ),
  );

  @override
  Future<RuntimeState> resetAppearanceSettings(RuntimeInstanceId expected) =>
      _call(
        () async => runtimeStateFromDto(
          await _rustApi.crateResetAppearanceSettings(
            expectedRuntimeInstanceId: expected.value,
          ),
        ),
      );

  @override
  Future<RuntimeState> exitFailedRuntime(RuntimeInstanceId expected) => _call(
    () async => runtimeStateFromDto(
      await _rustApi.crateExitFailedRuntime(
        expectedRuntimeInstanceId: expected.value,
      ),
    ),
  );

  @override
  Future<void> generalShutdown() =>
      _callVoid(() => _rustApi.crateGeneralShutdown());

  @override
  Future<void> closeEventConnection() =>
      _callVoid(() => _rustApi.crateCloseEventConnection());

  @override
  Future<AppearanceSettings> getAppearanceSettings() => _call(
    () async =>
        appearanceSettingsFromDto(await _rustApi.crateGetAppearanceSettings()),
  );

  @override
  Future<void> updateAppearanceSettings(AppearanceSettings settings) =>
      _callVoid(
        () => _rustApi.crateUpdateAppearanceSettings(
          request: dto.UpdateAppearanceSettingsRequestDto(
            themeMode: themeModeToDto(settings.themeMode),
          ),
        ),
      );

  @override
  Future<DiagnosticsExport> exportStartupDiagnostics(
    RuntimeInstanceId expected,
    String destination,
  ) => _call(
    () async => diagnosticsExportFromDto(
      await _rustApi.crateExportStartupDiagnostics(
        expectedRuntimeInstanceId: expected.value,
        request: dto.DiagnosticsExportRequestDto(destination: destination),
      ),
    ),
  );

  @override
  Future<TechnicalDetails> startupTechnicalDetails(
    RuntimeInstanceId expected,
  ) => _call(
    () async => technicalDetailsFromDto(
      await _rustApi.crateStartupTechnicalDetails(
        expectedRuntimeInstanceId: expected.value,
      ),
    ),
  );

  @override
  Future<void> openStartupDataDirectory(RuntimeInstanceId expected) =>
      _callVoid(
        () => _rustApi.crateOpenStartupDataDirectory(
          expectedRuntimeInstanceId: expected.value,
        ),
      );

  @override
  Stream<RuntimeEvent> subscribeEvents(RuntimeInstanceId generation) async* {
    try {
      await _ensureInitialized();
      // Re-read the current admission epoch so a fresh subscription after
      // client teardown is admitted while a stale delayed attach is rejected.
      final factory = _eventStreamFactory;
      final events = factory != null
          ? factory()
          : _rustApi.crateSubscribeEvents(
              attachEpoch: await _rustApi.crateGetEventAttachEpoch(),
            );
      await for (final event in events) {
        final mapped = runtimeEventFromDto(event);
        if (mapped.runtimeInstanceId == generation) yield mapped;
      }
    } catch (error, stackTrace) {
      throw _mapFailure(error, stackTrace);
    }
  }

  Future<T> _call<T>(Future<T> Function() operation) async {
    try {
      await _ensureInitialized();
      return await operation();
    } catch (error, stackTrace) {
      throw _mapFailure(error, stackTrace);
    }
  }

  Future<void> _callVoid(Future<void> Function() operation) =>
      _call<void>(operation);

  ClientFailure _mapFailure(Object error, StackTrace stackTrace) {
    if (error is dto.ApplicationErrorDto) {
      return ApplicationFailure(
        applicationErrorFromDto(error),
        cause: error,
        stackTrace: stackTrace,
      );
    }
    if (error is dto.BridgeTransportError) {
      return TransportFailure(
        'Native bridge transport failed: ${error.name}',
        cause: error,
        stackTrace: stackTrace,
        kind: TransportFailureKind.communicationFailed,
      );
    }
    if (error is ClientFailure) return error;
    return TransportFailure(
      'Native bridge transport failed',
      cause: error,
      stackTrace: stackTrace,
      kind: TransportFailureKind.unexpectedTransportFailure,
    );
  }
}

ClientApplicationError applicationErrorFromDto(dto.ApplicationErrorDto value) =>
    _validatedApplicationError(
      code: value.code,
      category: ErrorCategory.fromWire(value.category),
      severity: ApplicationSeverity.fromWire(value.severity),
      recoverability: Recoverability.fromWire(value.recoverability),
      retryPolicy: RetryPolicy.fromWire(value.retryPolicy),
      messageKey: value.messageKey,
      traceId: value.traceId,
      safeContext: [
        for (final entry in value.safeContext) safeContextEntryFromDto(entry),
      ],
    );

ClientApplicationError _validatedApplicationError({
  required String code,
  required ErrorCategory category,
  required ApplicationSeverity severity,
  required Recoverability recoverability,
  required RetryPolicy retryPolicy,
  required String messageKey,
  required String traceId,
  required List<SafeContextEntry> safeContext,
}) {
  final errorCode = ErrorCode(code);
  final errorTrace = TraceId(traceId);
  if (!errorCode.isValid || !errorTrace.isValid || messageKey.isEmpty) {
    throw const TransportFailure(
      'Malformed application error representation',
      kind: TransportFailureKind.contractMismatch,
    );
  }
  return ClientApplicationError(
    code: errorCode,
    category: category,
    severity: severity,
    recoverability: recoverability,
    retryPolicy: retryPolicy,
    messageKey: MessageKey(messageKey),
    traceId: errorTrace,
    safeContext: safeContext,
  );
}

SafeContextEntry safeContextEntryFromDto(dto.SafeContextEntryDto value) {
  final field = SafeContextField.fromWire(value.field);
  final parsed = switch (field) {
    SafeContextField.migrationCount ||
    SafeContextField.schemaVersion => SafeContextValue.integer(
      int.tryParse(value.value) ??
          (throw const TransportFailure(
            'Invalid integer safe-context value',
            kind: TransportFailureKind.contractMismatch,
          )),
    ),
    _ => SafeContextValue.string(value.value),
  };
  return SafeContextEntry(field: field, value: parsed);
}

RuntimeState runtimeStateFromDto(dto.RuntimeStateDto value) {
  final id = runtimeInstanceIdFromDto(value.runtimeInstanceId);
  final phase = value.startupPhase == null
      ? null
      : startupPhaseFromDto(value.startupPhase!);
  final failure = value.startupFailure == null
      ? null
      : startupFailureFromDto(value.startupFailure!);
  switch (value.lifecycleState) {
    case dto.RuntimeLifecycleDto.uninitialized:
      _requireNoStartupFields(phase, failure);
      return RuntimeState.uninitialized(runtimeInstanceId: id);
    case dto.RuntimeLifecycleDto.starting:
      if (failure != null) {
        throw const TransportFailure(
          'Native runtime state contains an invalid startup failure',
          kind: TransportFailureKind.contractMismatch,
        );
      }
      return RuntimeState.starting(runtimeInstanceId: id, phase: phase);
    case dto.RuntimeLifecycleDto.ready:
      _requireNoStartupFields(phase, failure);
      return RuntimeState.ready(runtimeInstanceId: id);
    case dto.RuntimeLifecycleDto.startupFailed:
      if (phase == null || failure == null || phase != failure.phase) {
        throw const TransportFailure(
          'Native runtime state contains an incomplete startup failure',
          kind: TransportFailureKind.contractMismatch,
        );
      }
      return RuntimeState.startupFailed(
        runtimeInstanceId: id,
        failure: failure,
      );
    case dto.RuntimeLifecycleDto.shuttingDown:
      _requireNoStartupFields(phase, failure);
      return RuntimeState.shuttingDown(runtimeInstanceId: id);
    case dto.RuntimeLifecycleDto.stopped:
      _requireNoStartupFields(phase, failure);
      return RuntimeState.stopped(runtimeInstanceId: id);
  }
}

RuntimeInstanceId runtimeInstanceIdFromDto(String value) {
  final id = RuntimeInstanceId(value);
  if (!id.isValid) {
    throw const TransportFailure(
      'Native runtime identity is invalid',
      kind: TransportFailureKind.contractMismatch,
    );
  }
  return id;
}

void _requireNoStartupFields(StartupPhase? phase, StartupFailure? failure) {
  if (phase != null || failure != null) {
    throw const TransportFailure(
      'Native runtime state contains unexpected startup fields',
      kind: TransportFailureKind.contractMismatch,
    );
  }
}

StartupFailure startupFailureFromDto(dto.StartupFailureDto value) =>
    StartupFailure(
      phase: startupPhaseFromDto(value.phase),
      error: applicationErrorFromDto(value.error),
      recoveryActions: [
        for (final action in value.recoveryActions)
          RecoveryAction(kind: recoveryActionKindFromDto(action.kind)),
      ],
    );

StartupPhase startupPhaseFromDto(dto.StartupPhaseDto value) => switch (value) {
  dto.StartupPhaseDto.environmentInitialization =>
    StartupPhase.environmentInitialization,
  dto.StartupPhaseDto.observabilityInitialization =>
    StartupPhase.observabilityInitialization,
  dto.StartupPhaseDto.configurationInitialization =>
    StartupPhase.configurationInitialization,
  dto.StartupPhaseDto.persistenceInitialization =>
    StartupPhase.persistenceInitialization,
  dto.StartupPhaseDto.settingsInitialization =>
    StartupPhase.settingsInitialization,
  dto.StartupPhaseDto.coreServicesInitialization =>
    StartupPhase.coreServicesInitialization,
  dto.StartupPhaseDto.eventInfrastructureInitialization =>
    StartupPhase.eventInfrastructureInitialization,
  dto.StartupPhaseDto.readinessValidation => StartupPhase.readinessValidation,
};

RecoveryActionKind recoveryActionKindFromDto(dto.RecoveryActionKindDto value) =>
    switch (value) {
      dto.RecoveryActionKindDto.retryStartup => RecoveryActionKind.retryStartup,
      dto.RecoveryActionKindDto.resetAppearanceSettings =>
        RecoveryActionKind.resetAppearanceSettings,
      dto.RecoveryActionKindDto.exportDiagnostics =>
        RecoveryActionKind.exportDiagnostics,
      dto.RecoveryActionKindDto.copyTechnicalDetails =>
        RecoveryActionKind.copyTechnicalDetails,
      dto.RecoveryActionKindDto.openDataDirectory =>
        RecoveryActionKind.openDataDirectory,
      dto.RecoveryActionKindDto.exit => RecoveryActionKind.exit,
    };

AppearanceSettings appearanceSettingsFromDto(dto.AppearanceSettingsDto value) =>
    AppearanceSettings(themeMode: themeModeFromDto(value.themeMode));

ThemeMode themeModeFromDto(dto.ThemeModeDto value) => switch (value) {
  dto.ThemeModeDto.system => ThemeMode.system,
  dto.ThemeModeDto.light => ThemeMode.light,
  dto.ThemeModeDto.dark => ThemeMode.dark,
};

dto.ThemeModeDto themeModeToDto(ThemeMode value) => switch (value) {
  ThemeMode.system => dto.ThemeModeDto.system,
  ThemeMode.light => dto.ThemeModeDto.light,
  ThemeMode.dark => dto.ThemeModeDto.dark,
};

DiagnosticsExport diagnosticsExportFromDto(
  dto.DiagnosticsExportDto value,
) => DiagnosticsExport(
  outcome: switch (value.outcome) {
    dto.DiagnosticsExportOutcomeDto.created => DiagnosticsExportOutcome.created,
    dto.DiagnosticsExportOutcomeDto.partial => DiagnosticsExportOutcome.partial,
  },
  destinationClassification: value.destinationClassification,
);

TechnicalDetails technicalDetailsFromDto(dto.TechnicalDetailsDto value) =>
    TechnicalDetails(text: value.text);

RuntimeEvent runtimeEventFromDto(dto.RuntimeEventDto value) {
  final generation = runtimeInstanceIdFromDto(value.runtimeInstanceId);
  final payload = value.payload.map(
    runtimeStateChanged: (event) => RuntimeEventPayload.runtimeStateChanged(
      lifecycle: runtimeLifecycleFromDto(event.lifecycle),
    ),
    startupFailed: (event) => RuntimeEventPayload.startupFailed(
      phase: startupPhaseFromDto(event.phase),
    ),
    appearanceSettingsChanged: (_) =>
        const RuntimeEventPayload.appearanceSettingsChanged(),
  );
  return RuntimeEvent(
    runtimeInstanceId: generation,
    sequence: value.sequence,
    occurredAtMs: value.occurredAtMs,
    payload: payload,
  );
}

RuntimeLifecycle runtimeLifecycleFromDto(dto.RuntimeLifecycleDto value) =>
    switch (value) {
      dto.RuntimeLifecycleDto.uninitialized => RuntimeLifecycle.uninitialized,
      dto.RuntimeLifecycleDto.starting => RuntimeLifecycle.starting,
      dto.RuntimeLifecycleDto.ready => RuntimeLifecycle.ready,
      dto.RuntimeLifecycleDto.startupFailed => RuntimeLifecycle.startupFailed,
      dto.RuntimeLifecycleDto.shuttingDown => RuntimeLifecycle.shuttingDown,
      dto.RuntimeLifecycleDto.stopped => RuntimeLifecycle.stopped,
    };
