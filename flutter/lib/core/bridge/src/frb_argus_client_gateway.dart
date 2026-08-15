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
  Future<LibraryRootPage> listLibraryRoots({
    required int offset,
    required int pageSize,
  }) => _call(
    () async => libraryRootPageFromDto(
      await _rustApi.crateListLibraryRoots(
        request: dto.ListLibraryRootsRequestDto(
          offset: offset,
          pageSize: pageSize,
        ),
      ),
    ),
  );

  @override
  Future<LibraryRoot> getLibraryRoot(LibraryRootId libraryRootId) => _call(
    () async => libraryRootFromDto(
      await _rustApi.crateGetLibraryRoot(libraryRootId: libraryRootId.value),
    ),
  );

  @override
  Future<AddLocalLibraryRootResult> addLocalLibraryRoot(
    LocalFilesystemRootSelection selection,
  ) => _call(
    () async => addLocalLibraryRootResultFromDto(
      await _rustApi.crateAddLocalLibraryRoot(
        selection: selectionToDto(selection),
      ),
    ),
  );

  @override
  Future<RemoveLibraryRootResult> removeLibraryRoot(
    LibraryRootId libraryRootId,
  ) => _call(
    () async => removeLibraryRootResultFromDto(
      await _rustApi.crateRemoveLibraryRoot(libraryRootId: libraryRootId.value),
    ),
  );

  @override
  Future<StartLibraryScanResult> startLibraryScan(
    LibraryRootId libraryRootId,
  ) => _call(
    () async => startLibraryScanResultFromDto(
      await _rustApi.crateStartLibraryScan(libraryRootId: libraryRootId.value),
    ),
  );

  @override
  Future<JobSummaryPage> listActiveJobs() => _call(
    () async => jobSummaryPageFromDto(
      await _rustApi.crateListJobs(
        request: dto.ListJobsRequestDto(scope: dto.ListJobsScopeDto.active()),
      ),
    ),
  );

  @override
  Future<JobSummaryPage> listRecentTerminalJobs({
    required int offset,
    required int pageSize,
  }) => _call(
    () async => jobSummaryPageFromDto(
      await _rustApi.crateListJobs(
        request: dto.ListJobsRequestDto(
          scope: dto.ListJobsScopeDto.recentTerminal(
            offset: offset,
            pageSize: pageSize,
          ),
        ),
      ),
    ),
  );

  @override
  Future<JobDetail> getJob(JobRunId jobRunId) => _call(
    () async =>
        jobDetailFromDto(await _rustApi.crateGetJob(jobRunId: jobRunId.value)),
  );

  @override
  Future<CancelJobResult> cancelJob(JobRunId jobRunId) => _call(
    () async => cancelJobResultFromDto(
      await _rustApi.crateCancelJob(jobRunId: jobRunId.value),
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
  Future<EventBindResult> subscribeEvents(RuntimeInstanceId generation) async {
    try {
      await _ensureInitialized();
      final factory = _eventStreamFactory;
      if (factory != null) {
        return EventBindResult(
          stream: _mapEvents(factory(), generation),
          nativeAttached: false,
        );
      }
      // Re-read the current admission epoch so a fresh subscription after
      // client teardown is admitted while a stale delayed attach is rejected.
      final epoch = await _rustApi.crateGetEventAttachEpoch();
      // Bridge-private native-attachment acknowledgement: this completes only
      // after the one native event connection for this epoch has attached (or
      // was deterministically rejected as lifecycle-expected).
      final attached = await _rustApi.crateAttachEventSubscription(
        attachEpoch: epoch,
      );
      return EventBindResult(
        stream: _mapEvents(
          _rustApi.crateSubscribeEvents(attachEpoch: epoch),
          generation,
        ),
        nativeAttached: attached,
      );
    } catch (error, stackTrace) {
      throw _mapFailure(error, stackTrace);
    }
  }

  Stream<RuntimeEvent> _mapEvents(
    Stream<dto.RuntimeEventDto> events,
    RuntimeInstanceId generation,
  ) async* {
    try {
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
    libraryRootsChanged: (_) => const RuntimeEventPayload.libraryRootsChanged(),
    libraryRootChanged: (event) => RuntimeEventPayload.libraryRootChanged(
      libraryRootId: libraryRootIdFromDto(event.libraryRootId),
    ),
    jobStateChanged: (event) => RuntimeEventPayload.jobStateChanged(
      jobRunId: jobRunIdFromDto(event.jobRunId),
    ),
    jobProgress: (event) => RuntimeEventPayload.jobProgress(
      jobRunId: jobRunIdFromDto(event.jobRunId),
      phase: event.phase,
      completedUnits: event.completedUnits?.toInt(),
      totalUnits: event.totalUnits?.toInt(),
      statusKey: event.statusKey,
    ),
    sourceEntriesChanged: (event) => RuntimeEventPayload.sourceEntriesChanged(
      libraryRootId: libraryRootIdFromDto(event.libraryRootId),
      scope: sourceEntriesChangeScopeFromDto(event.scope),
    ),
  );
  return RuntimeEvent(
    runtimeInstanceId: generation,
    sequence: value.sequence,
    occurredAtMs: value.occurredAtMs,
    payload: payload,
  );
}

LibraryRootId libraryRootIdFromDto(String value) {
  final id = LibraryRootId(value);
  if (!id.isValid) {
    throw const TransportFailure(
      'Native library-root identity is invalid',
      kind: TransportFailureKind.contractMismatch,
    );
  }
  return id;
}

LibraryRoot libraryRootFromDto(dto.LibraryRootDto value) => LibraryRoot(
  id: libraryRootIdFromDto(value.libraryRootId),
  displayName: value.displayName,
  safeLocationPresentation: value.safeLocationPresentation,
  availability: libraryRootAvailabilityFromDto(value.availability),
  lastScan: value.lastScan == null
      ? null
      : LibraryRootLastScan(
          scanRunId: value.lastScan!.scanRunId,
          jobRunId: value.lastScan!.jobRunId,
          status: libraryRootLastScanStatusFromDto(value.lastScan!.status),
          startedAtMs: value.lastScan!.startedAtMs.toInt(),
          completedAtMs: value.lastScan!.completedAtMs?.toInt(),
        ),
  activeScan: value.activeScan == null
      ? null
      : LibraryRootActiveScan(
          scanRunId: value.activeScan!.scanRunId,
          jobRunId: value.activeScan!.jobRunId,
        ),
);

LibraryRootPage libraryRootPageFromDto(dto.LibraryRootPageDto value) =>
    LibraryRootPage(
      items: [for (final item in value.items) libraryRootFromDto(item)],
      offset: value.offset,
      pageSize: value.pageSize,
      totalCount: value.totalCount,
    );

AddLocalLibraryRootResult addLocalLibraryRootResultFromDto(
  dto.AddLocalLibraryRootResultDto value,
) => switch (value) {
  dto.AddLocalLibraryRootResultDto_Added(:final field0) =>
    AddLocalLibraryRootResult.added(libraryRootFromDto(field0)),
  dto.AddLocalLibraryRootResultDto_AlreadyConfigured(:final field0) =>
    AddLocalLibraryRootResult.alreadyConfigured(libraryRootIdFromDto(field0)),
  dto.AddLocalLibraryRootResultDto_OverlapsExisting(
    :final field0,
    :final field1,
  ) =>
    AddLocalLibraryRootResult.overlapsExisting(
      existingLibraryRootId: libraryRootIdFromDto(field0),
      relationship: rootRelationshipFromDto(field1),
    ),
};

RemoveLibraryRootResult removeLibraryRootResultFromDto(
  dto.RemoveLibraryRootResultDto value,
) => switch (value) {
  dto.RemoveLibraryRootResultDto_Removed() => RemoveLibraryRootResult.removed(),
  dto.RemoveLibraryRootResultDto_RootHasActiveScan(
    :final libraryRootId,
    :final jobRunId,
    :final scanRunId,
    :final owningJobRootCount,
  ) =>
    RemoveLibraryRootResult.rootHasActiveScan(
      libraryRootId: libraryRootIdFromDto(libraryRootId),
      jobRunId: jobRunIdFromDto(jobRunId),
      scanRunId: scanRunIdFromDto(scanRunId),
      owningJobRootCount: owningJobRootCount,
    ),
};

dto.LocalFilesystemRootSelectionDto selectionToDto(
  LocalFilesystemRootSelection selection,
) => dto.LocalFilesystemRootSelectionDto(
  selectedFolderPath: selection.selectedFolderPath,
);

LibraryRootAvailability libraryRootAvailabilityFromDto(
  dto.LibraryRootAvailabilityDto value,
) => switch (value) {
  dto.LibraryRootAvailabilityDto.available => LibraryRootAvailability.available,
  dto.LibraryRootAvailabilityDto.unavailable =>
    LibraryRootAvailability.unavailable,
  dto.LibraryRootAvailabilityDto.unknown => LibraryRootAvailability.unknown,
};

LibraryRootLastScanStatus libraryRootLastScanStatusFromDto(
  dto.LibraryRootLastScanStatusDto value,
) => switch (value) {
  dto.LibraryRootLastScanStatusDto.complete =>
    LibraryRootLastScanStatus.complete,
  dto.LibraryRootLastScanStatusDto.partial => LibraryRootLastScanStatus.partial,
  dto.LibraryRootLastScanStatusDto.unavailable =>
    LibraryRootLastScanStatus.unavailable,
  dto.LibraryRootLastScanStatusDto.cancelled =>
    LibraryRootLastScanStatus.cancelled,
  dto.LibraryRootLastScanStatusDto.failed => LibraryRootLastScanStatus.failed,
  dto.LibraryRootLastScanStatusDto.abandoned =>
    LibraryRootLastScanStatus.abandoned,
};

RootRelationship rootRelationshipFromDto(dto.RootRelationshipDto value) =>
    switch (value) {
      dto.RootRelationshipDto.same => RootRelationship.same,
      dto.RootRelationshipDto.ancestor => RootRelationship.ancestor,
      dto.RootRelationshipDto.descendant => RootRelationship.descendant,
      dto.RootRelationshipDto.disjoint => RootRelationship.disjoint,
      dto.RootRelationshipDto.unknown => RootRelationship.unknown,
    };

RuntimeLifecycle runtimeLifecycleFromDto(dto.RuntimeLifecycleDto value) =>
    switch (value) {
      dto.RuntimeLifecycleDto.uninitialized => RuntimeLifecycle.uninitialized,
      dto.RuntimeLifecycleDto.starting => RuntimeLifecycle.starting,
      dto.RuntimeLifecycleDto.ready => RuntimeLifecycle.ready,
      dto.RuntimeLifecycleDto.startupFailed => RuntimeLifecycle.startupFailed,
      dto.RuntimeLifecycleDto.shuttingDown => RuntimeLifecycle.shuttingDown,
      dto.RuntimeLifecycleDto.stopped => RuntimeLifecycle.stopped,
    };

JobRunId jobRunIdFromDto(String value) {
  final id = JobRunId(value);
  if (!id.isValid) {
    throw const TransportFailure(
      'Native job-run identity is invalid',
      kind: TransportFailureKind.contractMismatch,
    );
  }
  return id;
}

ScanRunId scanRunIdFromDto(String value) {
  final id = ScanRunId(value);
  if (!id.isValid) {
    throw const TransportFailure(
      'Native scan-run identity is invalid',
      kind: TransportFailureKind.contractMismatch,
    );
  }
  return id;
}

JobLifecycleState jobLifecycleStateFromDto(dto.JobRunStateDto value) =>
    switch (value) {
      dto.JobRunStateDto.queued => JobLifecycleState.queued,
      dto.JobRunStateDto.preparing => JobLifecycleState.preparing,
      dto.JobRunStateDto.running => JobLifecycleState.running,
      dto.JobRunStateDto.completed => JobLifecycleState.completed,
      dto.JobRunStateDto.completedWithIssues =>
        JobLifecycleState.completedWithIssues,
      dto.JobRunStateDto.failed => JobLifecycleState.failed,
      dto.JobRunStateDto.cancelled => JobLifecycleState.cancelled,
      dto.JobRunStateDto.interrupted => JobLifecycleState.interrupted,
      dto.JobRunStateDto.abandoned => JobLifecycleState.abandoned,
    };

JobScanStatus jobScanStatusFromDto(dto.ScanRunStatusDto value) =>
    switch (value) {
      dto.ScanRunStatusDto.running => JobScanStatus.running,
      dto.ScanRunStatusDto.complete => JobScanStatus.complete,
      dto.ScanRunStatusDto.partial => JobScanStatus.partial,
      dto.ScanRunStatusDto.failed => JobScanStatus.failed,
      dto.ScanRunStatusDto.cancelled => JobScanStatus.cancelled,
      dto.ScanRunStatusDto.abandoned => JobScanStatus.abandoned,
    };

SourceEntriesChangeScope sourceEntriesChangeScopeFromDto(
  dto.SourceEntriesChangeScopeDto value,
) => switch (value) {
  dto.SourceEntriesChangeScopeDto_RootChildren() =>
    SourceEntriesChangeScope.rootChildren,
  dto.SourceEntriesChangeScopeDto_EntryChildren() =>
    SourceEntriesChangeScope.entryChildren,
  dto.SourceEntriesChangeScopeDto_EntireRootHierarchy() =>
    SourceEntriesChangeScope.entireRootHierarchy,
};

StartLibraryScanResult startLibraryScanResultFromDto(
  dto.StartLibraryScanResultDto value,
) => switch (value) {
  dto.StartLibraryScanResultDto_Admitted(:final field0) =>
    StartLibraryScanResult.admitted(
      OperationHandle(
        jobRunId: jobRunIdFromDto(field0.jobRunId),
        operationType: field0.operationType,
      ),
    ),
  dto.StartLibraryScanResultDto_AlreadyScanning(
    :final libraryRootId,
    :final activeJobRunId,
    :final activeScanRunId,
  ) =>
    StartLibraryScanResult.alreadyScanning(
      libraryRootId: libraryRootIdFromDto(libraryRootId),
      activeJobRunId: jobRunIdFromDto(activeJobRunId),
      activeScanRunId: scanRunIdFromDto(activeScanRunId),
    ),
};

CancelJobResult cancelJobResultFromDto(dto.CancelJobResultDto value) =>
    switch (value) {
      dto.CancelJobResultDto.cancellationRequested =>
        CancelJobResult.cancellationRequested,
      dto.CancelJobResultDto.noLongerCancellable =>
        CancelJobResult.noLongerCancellable,
    };

JobSummaryPage jobSummaryPageFromDto(dto.JobSummaryPageDto value) =>
    JobSummaryPage(
      items: [for (final item in value.items) jobListItemFromDto(item)],
      totalCount: value.totalCount,
      nextOffset: value.nextOffset,
    );

JobListItem jobListItemFromDto(dto.JobSummaryDto value) => JobListItem(
  jobRunId: jobRunIdFromDto(value.jobRunId),
  operationType: value.operationType,
  lifecycleState: jobLifecycleStateFromDto(value.state),
  phase: value.phase,
  createdAtMs: value.createdAtMs.toInt(),
  startedAtMs: value.startedAtMs?.toInt(),
  terminalAtMs: value.terminalAtMs?.toInt(),
  cancellationRequested: value.cancellationRequested,
  safeContextSummary: value.safeContextSummary,
);

JobDetail jobDetailFromDto(dto.JobDetailDto value) => JobDetail(
  job: jobRunProjectionFromDto(value.job),
  operationDetail: operationDetailFromDto(value.operationDetail),
);

JobRunProjection jobRunProjectionFromDto(dto.JobRunDto value) =>
    JobRunProjection(
      jobRunId: jobRunIdFromDto(value.jobRunId),
      operationType: value.operationType,
      lifecycleState: jobLifecycleStateFromDto(value.state),
      phase: value.phase,
      completedUnits: value.completedUnits?.toInt(),
      totalUnits: value.totalUnits?.toInt(),
      statusKey: value.statusKey,
      createdAtMs: value.createdAtMs.toInt(),
      queuedAtMs: value.queuedAtMs?.toInt(),
      startedAtMs: value.startedAtMs?.toInt(),
      terminalAtMs: value.terminalAtMs?.toInt(),
      cancellationRequested: value.cancellationRequested,
      controls: JobControlAvailability(
        canCancel: value.controls.canCancel,
        canRetry: value.controls.canRetry,
      ),
      boundedTerminalFailure: value.boundedTerminalFailure == null
          ? null
          : BoundedTerminalFailure(
              errorCode: value.boundedTerminalFailure!.errorCode,
              safeContext: value.boundedTerminalFailure!.safeContext,
            ),
    );

OperationDetail operationDetailFromDto(dto.OperationDetailDto value) =>
    switch (value) {
      dto.OperationDetailDto_LibraryScan(:final field0) =>
        OperationDetail.libraryScan(libraryScanJobDetailFromDto(field0)),
    };

LibraryScanJobDetail libraryScanJobDetailFromDto(
  dto.LibraryScanJobDetailDto value,
) => LibraryScanJobDetail(
  requestedRoots: [
    for (final root in value.requestedRoots)
      LibraryScanRootSummary(
        libraryRootId: libraryRootIdFromDto(root.libraryRootId),
        displayName: root.displayName,
        safeLocationDisplay: root.safeLocationDisplay,
      ),
  ],
  admittedRoots: [
    for (final root in value.admittedRoots)
      LibraryScanRootSummary(
        libraryRootId: libraryRootIdFromDto(root.libraryRootId),
        displayName: root.displayName,
        safeLocationDisplay: root.safeLocationDisplay,
      ),
  ],
  exclusions: [
    for (final exclusion in value.exclusions)
      LibraryScanAdmissionExclusion(
        libraryRootId: libraryRootIdFromDto(exclusion.libraryRootId),
        reason: exclusion.reason,
        activeJobRunId: exclusion.activeJobRunId == null
            ? null
            : jobRunIdFromDto(exclusion.activeJobRunId!),
        activeScanRunId: exclusion.activeScanRunId == null
            ? null
            : scanRunIdFromDto(exclusion.activeScanRunId!),
      ),
  ],
  scanRuns: [
    for (final scan in value.scanRuns)
      ScanRunSummary(
        scanRunId: scanRunIdFromDto(scan.scanRunId),
        jobRunId: jobRunIdFromDto(scan.jobRunId),
        libraryRootId: libraryRootIdFromDto(scan.libraryRootId),
        displayName: scan.displayName,
        safeLocationDisplay: scan.safeLocationDisplay,
        status: jobScanStatusFromDto(scan.status),
        startedAtMs: scan.startedAtMs.toInt(),
        completedAtMs: scan.completedAtMs?.toInt(),
      ),
  ],
  progress: ScanProgressFacts(
    phase: value.progress.phase,
    completedUnits: value.progress.completedUnits?.toInt(),
    totalUnits: value.progress.totalUnits?.toInt(),
    statusKey: value.progress.statusKey,
    rootsRequested: value.progress.rootsRequested,
    rootsAdmitted: value.progress.rootsAdmitted,
    rootsTerminal: value.progress.rootsTerminal,
    entriesCommitted: value.progress.entriesCommitted.toInt(),
  ),
  retrySourceJobRunId: value.retrySourceJobRunId == null
      ? null
      : jobRunIdFromDto(value.retrySourceJobRunId!),
  retrySuccessorJobRunId: value.retrySuccessorJobRunId == null
      ? null
      : jobRunIdFromDto(value.retrySuccessorJobRunId!),
);
