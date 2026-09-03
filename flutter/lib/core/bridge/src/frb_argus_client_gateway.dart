import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:argus/core/bridge/generated/frb_generated.dart' as frb;
import 'package:argus/core/bridge/generated/lib.dart' as dto;
import 'package:argus/core/client/client.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated_io.dart'
    as frb_io;

/// Framework-neutral native fact used only to refresh Rust's transient mount
/// registry before a provider-dependent Sources operation.
final class MountedLocalFilesystemVolumeFact {
  const MountedLocalFilesystemVolumeFact({
    required this.providerVolumeId,
    required this.transientMountPath,
    required this.safeDisplayName,
    required this.isPrimary,
    required this.isRemovable,
  });

  final String providerVolumeId;
  final String transientMountPath;
  final String safeDisplayName;
  final bool isPrimary;
  final bool isRemovable;
}

/// FRB 2.12 adapter translating generated transport types into pure-Dart
/// client models and typed application/transport failures.
final class FrbArgusClientGateway
    implements
        ArgusClientGateway,
        DiagnosticsSharingGateway,
        LibraryGateway,
        LibraryPhase003Gateway,
        PrivacyGateway,
        MetadataProvidersGateway,
        ArtworkGateway {
  FrbArgusClientGateway({
    frb.RustLibApi? api,
    Future<void> Function()? initializeNative,
    String? dataDirectoryOverride,
    String? standardApplicationDataDirectory,
    Stream<dto.RuntimeEventDto> Function()? eventStreamFactory,
    Future<List<MountedLocalFilesystemVolumeFact>> Function()?
    mountedVolumesReader,
    Future<void> Function()? publishCompletedDiagnostics,
  }) : // The public seam keeps callers independent of private field names.
       // ignore: prefer_initializing_formals
       _api = api,
       _initializeNative = initializeNative ?? _initializeFrb,
       // ignore: prefer_initializing_formals
       _dataDirectoryOverride = dataDirectoryOverride,
       // ignore: prefer_initializing_formals
       _standardApplicationDataDirectory = standardApplicationDataDirectory,
       // ignore: prefer_initializing_formals
       _eventStreamFactory = eventStreamFactory,
       // ignore: prefer_initializing_formals
       _mountedVolumesReader = mountedVolumesReader,
       // ignore: prefer_initializing_formals
       _publishCompletedDiagnostics = publishCompletedDiagnostics;

  final frb.RustLibApi? _api;
  final Future<void> Function() _initializeNative;
  final String? _dataDirectoryOverride;
  final String? _standardApplicationDataDirectory;
  final Stream<dto.RuntimeEventDto> Function()? _eventStreamFactory;
  final Future<List<MountedLocalFilesystemVolumeFact>> Function()?
  _mountedVolumesReader;
  final Future<void> Function()? _publishCompletedDiagnostics;
  Future<void>? _initialization;
  Future<void>? _mountRefresh;

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
  /// sibling library location on Windows/Linux. Android loads the packaged
  /// native library through the generated FRB loader; the generated loader
  /// remains the fallback for development/test layouts on other platforms.
  static Future<void> _initializeFrb() async {
    if (Platform.isAndroid) {
      await frb.RustLib.init();
      return;
    }
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
    final dto = switch ((
      _dataDirectoryOverride,
      _standardApplicationDataDirectory,
    )) {
      (final String override, _) =>
        await _rustApi.crateInitializeWithDataDirectory(
          dataDirectory: override,
        ),
      (null, final String standard) =>
        await _rustApi.crateInitializeWithStandardDataDirectory(
          dataDirectory: standard,
        ),
      (null, null) => await _rustApi.crateInitialize(),
    };
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
  Future<PrivacyConsent> getPrivacyConsent() => _call(
    () async => privacyConsentFromDto(await _rustApi.crateGetPrivacyConsent()),
  );

  @override
  Future<PrivacyConsent> acceptPrivacyTerms(PrivacyTermsVersion termsVersion) =>
      _call(
        () async => privacyConsentFromDto(
          await _rustApi.crateAcceptPrivacyTerms(
            request: dto.AcceptPrivacyTermsRequestDto(
              termsVersion: termsVersion.value,
            ),
          ),
        ),
      );

  @override
  Future<LibraryOnboardingState> getLibraryOnboardingState() => _call(
    () async => libraryOnboardingStateFromDto(
      await _rustApi.crateGetLibraryOnboardingState(),
    ),
  );

  @override
  Future<LibraryOnboardingState> confirmLibraryMetadataPreferences(
    MetadataSettings settings,
  ) => _call(
    () async => libraryOnboardingStateFromDto(
      await _rustApi.crateConfirmLibraryMetadataPreferences(
        settings: metadataSettingsToDto(settings),
      ),
    ),
  );

  @override
  Future<LibraryOnboardingState> recordLibraryProviderSetup(
    LibraryProviderSetupDecision decision,
  ) => _call(
    () async => libraryOnboardingStateFromDto(
      await _rustApi.crateRecordLibraryProviderSetup(
        decision: libraryProviderSetupDecisionToDto(decision),
      ),
    ),
  );

  @override
  Future<CompleteLibraryOnboardingAndRefreshResult>
  completeLibraryOnboardingAndRefresh() => _call(
    () async => completeLibraryOnboardingAndRefreshResultFromDto(
      await _rustApi.crateCompleteLibraryOnboardingAndRefresh(),
    ),
  );

  @override
  Future<AddLibraryRootAndRefreshResult> addLibraryRootAndRefresh(
    LocalFilesystemRootSelection selection,
  ) => _call(
    () async => addLibraryRootAndRefreshResultFromDto(
      await _rustApi.crateAddLibraryRootAndRefresh(
        selection: selectionToDto(selection),
      ),
    ),
  );

  @override
  Future<MetadataSettings> getMetadataSettings() => _call(
    () async =>
        metadataSettingsFromDto(await _rustApi.crateGetMetadataSettings()),
  );

  @override
  Future<MetadataProviderSettings> getMetadataProviderSettings() => _call(
    () async => metadataProviderSettingsFromDto(
      await _rustApi.crateGetMetadataProviderSettings(),
    ),
  );

  @override
  Future<MetadataSettingsUpdateResult> updateMetadataSettings(
    MetadataSettings settings,
  ) => _call(
    () async => metadataSettingsUpdateResultFromDto(
      await _rustApi.crateUpdateMetadataSettings(
        settings: metadataSettingsToDto(settings),
      ),
    ),
  );

  @override
  Future<MetadataProviderSettingsUpdateResult> updateMetadataProviderSettings(
    MetadataProviderSettings settings,
  ) => _call(
    () async => metadataProviderSettingsUpdateResultFromDto(
      await _rustApi.crateUpdateMetadataProviderSettings(
        settings: metadataProviderSettingsToDto(settings),
      ),
    ),
  );

  @override
  Future<OperationHandle> startGameRefresh({
    required List<GameId> gameIds,
    required RefreshMode mode,
  }) => _call(
    () async => operationHandleFromDto(
      await _rustApi.crateStartGameRefresh(
        request: dto.StartGameRefreshRequestDto(
          gameIds: [for (final gameId in gameIds) gameId.value],
          mode: refreshModeToDto(mode),
        ),
      ),
    ),
  );

  @override
  Future<OperationHandle> refreshLibrary() => _call(
    () async => operationHandleFromDto(await _rustApi.crateRefreshLibrary()),
  );

  @override
  Future<LibraryRootPage> listLibraryRoots({
    required int offset,
    required int pageSize,
  }) => _call(
    () async => _sourcesCall(
      () async => libraryRootPageFromDto(
        await _rustApi.crateListLibraryRoots(
          request: dto.ListLibraryRootsRequestDto(
            offset: offset,
            pageSize: pageSize,
          ),
        ),
      ),
    ),
  );

  @override
  Future<LibraryRoot> getLibraryRoot(LibraryRootId libraryRootId) => _call(
    () async => _sourcesCall(
      () async => libraryRootFromDto(
        await _rustApi.crateGetLibraryRoot(libraryRootId: libraryRootId.value),
      ),
    ),
  );

  @override
  Future<GamePage> listGames(ListGamesRequest request) => _call(
    () async => gamePageFromDto(
      await _rustApi.crateListGames(request: listGamesRequestToDto(request)),
    ),
  );

  @override
  Future<LibraryFacets> getLibraryFacets(LibraryFacetQuery request) => _call(
    () async => libraryFacetsFromDto(
      await _rustApi.crateGetLibraryFacets(
        request: libraryFacetQueryToDto(request),
      ),
    ),
  );

  @override
  Future<GetGameResult> getGame(GameId gameId) => _call(
    () async =>
        getGameResultFromDto(await _rustApi.crateGetGame(gameId: gameId.value)),
  );

  @override
  Future<List<MetadataProviderReadiness>> listMetadataProviderReadiness() =>
      _call(
        () async => (await _rustApi.crateListMetadataProviderReadiness())
            .map(metadataProviderReadinessFromDto)
            .toList(growable: false),
      );

  @override
  Future<ProviderCredentialReadiness> setMetadataProviderCredential({
    required String providerId,
    required List<int> credentialInput,
  }) => _call(
    () async => providerCredentialReadinessFromDto(
      await _rustApi.crateSetMetadataProviderCredential(
        request: dto.SetMetadataProviderCredentialRequestDto(
          providerId: providerId,
          credentialInput: Uint8List.fromList(credentialInput),
        ),
      ),
    ),
  );

  @override
  Future<ProviderCredentialReadiness> removeMetadataProviderCredential(
    String providerId,
  ) => _call(
    () async => providerCredentialReadinessFromDto(
      await _rustApi.crateRemoveMetadataProviderCredential(
        request: dto.RemoveMetadataProviderCredentialRequestDto(
          providerId: providerId,
        ),
      ),
    ),
  );

  @override
  Future<ArtworkAssetBytes> getArtworkAssetBytes(String assetId) => _call(
    () async => artworkAssetBytesFromDto(
      await _rustApi.crateGetArtworkAssetBytes(assetId: assetId),
    ),
  );

  @override
  Future<AddLocalLibraryRootResult> addLocalLibraryRoot(
    LocalFilesystemRootSelection selection,
  ) => _call(
    () async => _sourcesCall(
      () async => addLocalLibraryRootResultFromDto(
        await _rustApi.crateAddLocalLibraryRoot(
          selection: selectionToDto(selection),
        ),
      ),
    ),
  );

  @override
  Future<AddLocalLibraryRootAndScanResult> addLocalLibraryRootAndScan(
    LocalFilesystemRootSelection selection,
  ) => _call(
    () async => _sourcesCall(
      () async => addLocalLibraryRootAndScanResultFromDto(
        await _rustApi.crateAddLocalLibraryRootAndScan(
          selection: selectionToDto(selection),
        ),
      ),
    ),
  );

  @override
  Future<List<LocalFilesystemBrowseRoot>> listLocalFilesystemBrowseRoots() =>
      _call(
        () async => _sourcesCall(
          () async => (await _rustApi.crateListLocalFilesystemBrowseRoots())
              .map(localFilesystemBrowseRootFromDto)
              .toList(growable: false),
        ),
      );

  @override
  Future<LocalFilesystemBrowsePage> listLocalFilesystemBrowseDirectories({
    required LocalFilesystemBrowseLocation location,
    String? cursor,
    required int pageSize,
  }) => _call(
    () async => _sourcesCall(
      () async => localFilesystemBrowsePageFromDto(
        await _rustApi.crateListLocalFilesystemBrowseDirectories(
          request: dto.ListLocalFilesystemBrowseDirectoriesRequestDto(
            location: location.value,
            cursor: cursor,
            pageSize: pageSize,
          ),
        ),
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
    () async => _sourcesCall(
      () async => startLibraryScanResultFromDto(
        await _rustApi.crateStartLibraryScan(
          libraryRootId: libraryRootId.value,
        ),
      ),
    ),
  );

  @override
  Future<StartLibraryScanAllResult> startLibraryScanAll(
    ScanAllRequestIdentity requestIdentity,
  ) => _call(
    () async => _sourcesCall(
      () async => startLibraryScanAllResultFromDto(
        await _rustApi.crateStartLibraryScanAll(
          requestIdentity: requestIdentity.value,
        ),
      ),
    ),
  );

  @override
  Future<SourceEntryChildrenPage> listSourceEntryChildren({
    required LibraryRootId libraryRootId,
    SourceEntryId? parentSourceEntryId,
    String? cursor,
    required int pageSize,
  }) => _call(
    () async => sourceEntryChildrenPageFromDto(
      await _rustApi.crateListSourceEntryChildren(
        request: dto.ListSourceEntryChildrenRequestDto(
          libraryRootId: libraryRootId.value,
          parentSourceEntryId: parentSourceEntryId?.value,
          cursor: cursor,
          pageSize: pageSize,
        ),
      ),
    ),
  );

  @override
  Future<SourceEntryDetail> getSourceEntry(SourceEntryId sourceEntryId) =>
      _call(
        () async => sourceEntryDetailFromDto(
          await _rustApi.crateGetSourceEntry(
            sourceEntryId: sourceEntryId.value,
          ),
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
  Future<RetryJobResult> retryJob(JobRunId jobRunId) => _call(
    () async => retryJobResultFromDto(
      await _rustApi.crateRetryJob(jobRunId: jobRunId.value),
    ),
  );

  @override
  Future<LibraryRootScanAdmission?> getRootScanAdmission(
    LibraryRootId libraryRootId,
  ) => _call(
    () async => libraryRootScanAdmissionFromDto(
      await _rustApi.crateGetRootScanAdmission(
        libraryRootId: libraryRootId.value,
      ),
    ),
  );

  @override
  Future<LibraryScanAllRequestResolution> resolveScanAllRequest(
    ScanAllRequestIdentity requestIdentity,
  ) => _call(
    () async => libraryScanAllRequestResolutionFromDto(
      await _rustApi.crateResolveScanAllRequest(
        requestIdentity: requestIdentity.value,
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
  bool get supportsDiagnosticsSharing => _publishCompletedDiagnostics != null;

  @override
  Future<DiagnosticsExport> exportStartupDiagnosticsForSharing(
    RuntimeInstanceId expected,
  ) => _call(() async {
    final publish = _publishCompletedDiagnostics;
    if (publish == null) {
      throw const TransportFailure(
        'Diagnostics sharing is unavailable',
        kind: TransportFailureKind.contractMismatch,
      );
    }
    final export = diagnosticsExportFromDto(
      await _rustApi.crateExportStartupDiagnosticsForSharing(
        expectedRuntimeInstanceId: expected.value,
      ),
    );
    await publish();
    return export;
  });

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

  /// Runs one provider-dependent Sources operation after a serialized native
  /// mount snapshot refresh. Desktop gateways omit the reader and therefore
  /// retain their existing call sequence exactly.
  Future<T> _sourcesCall<T>(Future<T> Function() operation) async {
    await _refreshMountedVolumes();
    return operation();
  }

  Future<void> _refreshMountedVolumes() async {
    final reader = _mountedVolumesReader;
    if (reader == null) return;
    final inFlight = _mountRefresh;
    if (inFlight != null) {
      await inFlight;
      return;
    }

    final refresh = () async {
      final facts = await reader();
      await _rustApi.crateSyncLocalFilesystemMountedVolumes(
        request: dto.SyncLocalFilesystemMountedVolumesRequestDto(
          volumes: facts
              .map(
                (fact) => dto.MountedLocalFilesystemVolumeDto(
                  providerVolumeId: fact.providerVolumeId,
                  transientMountPath: fact.transientMountPath,
                  safeDisplayName: fact.safeDisplayName,
                  isPrimary: fact.isPrimary,
                  isRemovable: fact.isRemovable,
                ),
              )
              .toList(growable: false),
        ),
      );
    }();
    _mountRefresh = refresh;
    try {
      await refresh;
    } finally {
      if (identical(_mountRefresh, refresh)) _mountRefresh = null;
    }
  }

  Future<void> _callVoid(Future<void> Function() operation) =>
      _call<void>(operation);

  ClientFailure _mapFailure(Object error, StackTrace stackTrace) {
    return mapFrbFailure(error, stackTrace);
  }
}

/// Translates generated FRB failures into the framework-independent failure
/// hierarchy shared by all bridge adapters.
ClientFailure mapFrbFailure(Object error, StackTrace stackTrace) {
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

LibraryOnboardingProgress libraryOnboardingProgressFromDto(
  dto.LibraryOnboardingProgressDto value,
) => LibraryOnboardingProgress(
  acceptedPrivacyTermsVersion: value.acceptedPrivacyTermsVersion,
  acceptedPrivacyAtMs: value.acceptedPrivacyAtMs?.toInt(),
  metadataPreferencesConfirmed: value.metadataPreferencesConfirmed,
  providerSetupOutcome: LibraryProviderSetupOutcome.fromWire(
    value.providerSetupOutcome,
  ),
  completedAtMs: value.completedAtMs?.toInt(),
);

LibraryOnboardingState libraryOnboardingStateFromDto(
  dto.LibraryOnboardingStateDto value,
) => LibraryOnboardingState(
  progress: libraryOnboardingProgressFromDto(value.progress),
  requiredPrivacyTermsVersion: value.requiredPrivacyTermsVersion,
  requiresPrivacyAcceptance: value.requiresPrivacyAcceptance,
  requiresRootSelection: value.requiresRootSelection,
  credentialConfigured: value.credentialConfigured,
  complete: value.complete,
);

PrivacyConsent privacyConsentFromDto(dto.PrivacyConsentDto value) =>
    PrivacyConsent(
      acceptedTermsVersion: value.acceptedTermsVersion == null
          ? null
          : PrivacyTermsVersion(value.acceptedTermsVersion!),
      acceptedAtMs: value.acceptedAtMs?.toInt(),
      requiredTermsVersion: PrivacyTermsVersion(value.requiredTermsVersion),
      satisfiesCurrentRequiredTerms: value.satisfiesCurrentRequiredTerms,
    );

dto.LibraryProviderSetupDecisionDto libraryProviderSetupDecisionToDto(
  LibraryProviderSetupDecision value,
) => switch (value) {
  LibraryProviderSetupDecision.configured =>
    dto.LibraryProviderSetupDecisionDto.configured,
  LibraryProviderSetupDecision.skipped =>
    dto.LibraryProviderSetupDecisionDto.skipped,
};

MetadataSettings metadataSettingsFromDto(dto.MetadataSettingsDto value) =>
    MetadataSettings(
      preferredRegions: value.preferredRegions,
      preferredLanguages: value.preferredLanguages,
    );

dto.MetadataSettingsDto metadataSettingsToDto(MetadataSettings value) =>
    dto.MetadataSettingsDto(
      preferredRegions: value.preferredRegions,
      preferredLanguages: value.preferredLanguages,
    );

MetadataProviderSettings metadataProviderSettingsFromDto(
  dto.MetadataProviderSettingsDto value,
) => MetadataProviderSettings(enabledProviders: value.enabledProviders);

dto.MetadataProviderSettingsDto metadataProviderSettingsToDto(
  MetadataProviderSettings value,
) => dto.MetadataProviderSettingsDto(enabledProviders: value.enabledProviders);

CompleteLibraryOnboardingAndRefreshResult
completeLibraryOnboardingAndRefreshResultFromDto(
  dto.CompleteLibraryOnboardingAndRefreshResultDto value,
) => switch (value) {
  dto.CompleteLibraryOnboardingAndRefreshResultDto_OnboardingCompletedAndRefreshAdmitted(
    :final field0,
    :final field1,
  ) =>
    CompleteLibraryOnboardingAndRefreshResult.admitted(
      state: libraryOnboardingStateFromDto(field0),
      handle: operationHandleFromDto(field1),
    ),
  dto.CompleteLibraryOnboardingAndRefreshResultDto_OnboardingCompletedButRefreshNotAdmitted(
    :final field0,
    :final field1,
  ) =>
    CompleteLibraryOnboardingAndRefreshResult.notAdmitted(
      state: libraryOnboardingStateFromDto(field0),
      error: applicationErrorFromDto(field1),
    ),
};

AddLibraryRootAndRefreshResult addLibraryRootAndRefreshResultFromDto(
  dto.AddLibraryRootAndRefreshResultDto value,
) => switch (value) {
  dto.AddLibraryRootAndRefreshResultDto_AddedAndRefreshAdmitted(
    :final field0,
    :final field1,
  ) =>
    AddLibraryRootAndRefreshResult.addedAndRefreshAdmitted(
      root: libraryRootFromDto(field0),
      handle: operationHandleFromDto(field1),
    ),
  dto.AddLibraryRootAndRefreshResultDto_AddedButRefreshNotAdmitted(
    :final field0,
    :final field1,
  ) =>
    AddLibraryRootAndRefreshResult.addedButRefreshNotAdmitted(
      root: libraryRootFromDto(field0),
      error: applicationErrorFromDto(field1),
    ),
  dto.AddLibraryRootAndRefreshResultDto_AlreadyConfigured(:final field0) =>
    AddLibraryRootAndRefreshResult.alreadyConfigured(
      existingLibraryRootId: libraryRootIdFromDto(field0),
    ),
  dto.AddLibraryRootAndRefreshResultDto_OverlapsExisting(
    :final field0,
    :final field1,
  ) =>
    AddLibraryRootAndRefreshResult.overlapsExisting(
      existingLibraryRootId: libraryRootIdFromDto(field0),
      relationship: rootRelationshipFromDto(field1),
    ),
};

MetadataSettingsUpdateResult metadataSettingsUpdateResultFromDto(
  dto.MetadataSettingsUpdateResultDto value,
) => switch (value) {
  dto.MetadataSettingsUpdateResultDto_CommittedNoResolutionWork(
    :final field0,
  ) =>
    MetadataSettingsUpdateResult.committedNoResolutionWork(
      metadataSettingsFromDto(field0),
    ),
  dto.MetadataSettingsUpdateResultDto_CommittedAndResolutionAdmitted(
    :final field0,
    :final field1,
  ) =>
    MetadataSettingsUpdateResult.committedAndResolutionAdmitted(
      metadataSettingsFromDto(field0),
      operationHandleFromDto(field1),
    ),
  dto.MetadataSettingsUpdateResultDto_CommittedButResolutionNotAdmitted(
    :final field0,
    :final field1,
  ) =>
    MetadataSettingsUpdateResult.committedButResolutionNotAdmitted(
      metadataSettingsFromDto(field0),
      applicationErrorFromDto(field1),
    ),
};

MetadataProviderSettingsUpdateResult
metadataProviderSettingsUpdateResultFromDto(
  dto.MetadataProviderSettingsUpdateResultDto value,
) => switch (value) {
  dto.MetadataProviderSettingsUpdateResultDto_CommittedNoResolutionWork(
    :final field0,
  ) =>
    MetadataProviderSettingsUpdateResult.committedNoResolutionWork(
      metadataProviderSettingsFromDto(field0),
    ),
  dto.MetadataProviderSettingsUpdateResultDto_CommittedAndResolutionAdmitted(
    :final field0,
    :final field1,
  ) =>
    MetadataProviderSettingsUpdateResult.committedAndResolutionAdmitted(
      metadataProviderSettingsFromDto(field0),
      operationHandleFromDto(field1),
    ),
  dto.MetadataProviderSettingsUpdateResultDto_CommittedButResolutionNotAdmitted(
    :final field0,
    :final field1,
  ) =>
    MetadataProviderSettingsUpdateResult.committedButResolutionNotAdmitted(
      metadataProviderSettingsFromDto(field0),
      applicationErrorFromDto(field1),
    ),
};

dto.RefreshModeDto refreshModeToDto(RefreshMode value) => switch (value) {
  RefreshMode.eligibleOnly => dto.RefreshModeDto.eligibleOnly,
  RefreshMode.force => dto.RefreshModeDto.force,
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
          owningJobRootCount: value.activeScan!.owningJobRootCount,
        ),
);

LibraryRootPage libraryRootPageFromDto(dto.LibraryRootPageDto value) =>
    LibraryRootPage(
      items: [for (final item in value.items) libraryRootFromDto(item)],
      offset: value.offset,
      pageSize: value.pageSize,
      totalCount: value.totalCount,
    );

dto.ListGamesRequestDto listGamesRequestToDto(ListGamesRequest value) =>
    dto.ListGamesRequestDto(
      scope: libraryScopeToDto(value.scope),
      searchText: value.searchText,
      filters: libraryFilterToDto(value.filters),
      sort: dto.LibrarySortDto(
        field: librarySortFieldToDto(value.sort.field),
        direction: librarySortDirectionToDto(value.sort.direction),
      ),
      cursor: value.cursor,
      pageSize: value.pageSize,
    );

dto.LibraryFacetQueryDto libraryFacetQueryToDto(LibraryFacetQuery value) =>
    dto.LibraryFacetQueryDto(
      scope: libraryScopeToDto(value.scope),
      searchText: value.searchText,
      filters: libraryFilterToDto(value.filters),
    );

dto.LibraryFilterDto libraryFilterToDto(LibraryFilter value) =>
    dto.LibraryFilterDto(
      platformIds: value.platformIds,
      regions: value.regions,
      hydrationStates: value.hydrationStates
          .map(hydrationStateToFilterDto)
          .toList(growable: false),
      availabilityStates: value.availabilityStates
          .map(availabilityStateToFilterDto)
          .toList(growable: false),
    );

dto.LibraryScopeDto libraryScopeToDto(LibraryScope value) => switch (value) {
  LibraryScopeAll() => dto.LibraryScopeDto.all(),
  LibraryScopePlatform(:final platformId) => dto.LibraryScopeDto.platform(
    platformId: platformId,
  ),
  LibraryScopeSource(:final sourceId) => dto.LibraryScopeDto.source(
    sourceId: sourceId,
  ),
  LibraryScopeLibraryRoot(:final libraryRootId) =>
    dto.LibraryScopeDto.libraryRoot(libraryRootId: libraryRootId),
};

dto.LibraryHydrationStateDto hydrationStateToFilterDto(HydrationState value) =>
    switch (value) {
      HydrationState.hydrated => dto.LibraryHydrationStateDto.hydrated,
      HydrationState.partiallyHydrated =>
        dto.LibraryHydrationStateDto.partiallyHydrated,
      HydrationState.unmatched => dto.LibraryHydrationStateDto.unmatched,
      HydrationState.refreshing => dto.LibraryHydrationStateDto.refreshing,
    };

dto.LibraryAvailabilityStateDto availabilityStateToFilterDto(
  AvailabilityState value,
) => switch (value) {
  AvailabilityState.available => dto.LibraryAvailabilityStateDto.available,
  AvailabilityState.partiallyUnavailable =>
    dto.LibraryAvailabilityStateDto.partiallyUnavailable,
  AvailabilityState.unavailable => dto.LibraryAvailabilityStateDto.unavailable,
  AvailabilityState.inactiveOrphan =>
    dto.LibraryAvailabilityStateDto.inactiveOrphan,
};

dto.LibrarySortFieldDto librarySortFieldToDto(LibrarySortField value) =>
    switch (value) {
      LibrarySortField.displayTitle => dto.LibrarySortFieldDto.displayTitle,
      LibrarySortField.platform => dto.LibrarySortFieldDto.platform,
      LibrarySortField.releaseDate => dto.LibrarySortFieldDto.releaseDate,
      LibrarySortField.updatedAt => dto.LibrarySortFieldDto.updatedAt,
    };

dto.LibrarySortDirectionDto librarySortDirectionToDto(
  LibrarySortDirection value,
) => switch (value) {
  LibrarySortDirection.ascending => dto.LibrarySortDirectionDto.ascending,
  LibrarySortDirection.descending => dto.LibrarySortDirectionDto.descending,
};

GamePage gamePageFromDto(dto.GamePageDto value) => GamePage(
  items: [for (final item in value.items) gameLibraryRowFromDto(item)],
  nextCursor: value.nextCursor,
);

GameLibraryRow gameLibraryRowFromDto(dto.GameLibraryRowDto value) =>
    GameLibraryRow(
      gameId: gameIdFromDto(value.gameId),
      displayTitle: value.displayTitle,
      platformId: platformIdFromDto(value.platformId),
      presentationRegion: value.presentationRegion,
      selectedCoverAssetId: value.selectedCoverAssetId,
      hydrationState: hydrationStateFromDto(value.hydrationState),
      contentCount: value.contentCount,
      sourceCount: value.sourceCount,
      availabilityState: availabilityStateFromDto(value.availabilityState),
      updatedAtMs: value.updatedAtMs.toInt(),
    );

LibraryFacets libraryFacetsFromDto(dto.LibraryFacetsDto value) => LibraryFacets(
  platforms: [
    for (final bucket in value.platforms)
      PlatformFacetBucket(
        platformId: platformFacetPlatformIdFromWire(bucket.platformId),
        count: bucket.count,
      ),
  ],
  regions: [
    for (final bucket in value.regions)
      RegionFacetBucket(region: bucket.region, count: bucket.count),
  ],
  hydrationStates: [
    for (final bucket in value.hydrationStates)
      HydrationStateFacetBucket(
        hydrationState: hydrationStateFromFilterDto(bucket.hydrationState),
        count: bucket.count,
      ),
  ],
  availabilityStates: [
    for (final bucket in value.availabilityStates)
      AvailabilityStateFacetBucket(
        availabilityState: availabilityStateFromFilterDto(
          bucket.availabilityState,
        ),
        count: bucket.count,
      ),
  ],
);

PlatformId platformFacetPlatformIdFromWire(String value) {
  final normalized = switch (value) {
    'sega.sega-cd' => 'sega_cd',
    _ => value.replaceFirst('.', '_'),
  };
  return PlatformId.fromWire(normalized);
}

GetGameResult getGameResultFromDto(dto.GetGameResultDto value) =>
    switch (value) {
      dto.GetGameResultDto_Found(:final field0) => GetGameFound(
        gameDetailFromDto(field0),
      ),
      dto.GetGameResultDto_Redirected(:final canonicalGameId) =>
        GetGameRedirected(gameIdFromDto(canonicalGameId)),
    };

GameDetail gameDetailFromDto(dto.GameDetailDto value) => GameDetail(
  gameId: gameIdFromDto(value.gameId),
  platformId: platformIdFromDto(value.platformId),
  lifecycle: gameLifecycleFromDto(value.lifecycle),
  hydrationState: hydrationStateFromDto(value.hydrationState),
  fallbackTitle: value.fallbackTitle,
  memberships: [
    for (final membership in value.memberships)
      gameMembershipSummaryFromDto(membership),
  ],
  content: [
    for (final summary in value.content) contentSummaryFromDto(summary),
  ],
  availabilityState: availabilityStateFromDto(value.availabilityState),
  resolvedMetadata: value.resolvedMetadata == null
      ? null
      : resolvedMetadataFromDto(value.resolvedMetadata!),
  resolvedArtwork: [
    for (final artwork
        in value.resolvedArtwork ?? const <dto.ResolvedArtworkDto>[])
      resolvedArtworkFromDto(artwork),
  ],
);

MetadataProviderReadiness metadataProviderReadinessFromDto(
  dto.MetadataProviderReadinessDto value,
) => MetadataProviderReadiness(
  providerId: value.providerId,
  enabled: value.enabled,
  capabilityReadiness: [
    for (final readiness in value.capabilityReadiness)
      ProviderCapabilityReadiness(
        capability: ProviderCapability.fromWire(readiness.capability),
        state: ProviderReadinessState.fromWire(readiness.state),
      ),
  ],
  credentialConfigured: value.credentialConfigured,
);

ProviderCredentialReadiness providerCredentialReadinessFromDto(
  dto.ProviderCredentialReadinessDto value,
) => ProviderCredentialReadiness(
  providerId: value.providerId,
  state: ProviderReadinessState.fromWire(value.state),
  credentialConfigured: value.credentialConfigured,
);

ResolvedMetadata resolvedMetadataFromDto(dto.ResolvedMetadataDto value) =>
    ResolvedMetadata(
      displayTitle: value.displayTitle,
      sortTitle: value.sortTitle,
      description: value.description,
      releaseDate: value.releaseDate,
      developers: value.developers,
      publishers: value.publishers,
      genres: value.genres,
      presentationRegion: value.presentationRegion,
      presentationLanguages: value.presentationLanguages,
      fieldProvenance: [
        for (final provenance in value.fieldProvenance)
          MetadataFieldProvenance(
            field: provenance.field,
            providerId: provenance.providerId,
            externalGameId: provenance.externalGameId,
            source: provenance.source,
          ),
      ],
      resolutionRevision: value.resolutionRevision.toInt(),
      resolvedAt: value.resolvedAt.toInt(),
      providerId: value.providerId,
    );

ResolvedArtwork resolvedArtworkFromDto(dto.ResolvedArtworkDto value) =>
    ResolvedArtwork(
      artworkType: value.artworkType,
      referenceId: value.referenceId,
      assetId: value.assetId,
      ordering: value.ordering,
      selectionReason: value.selectionReason,
      resolutionRevision: value.resolutionRevision.toInt(),
      resolvedAt: value.resolvedAt.toInt(),
    );

ArtworkAssetBytes artworkAssetBytesFromDto(dto.ArtworkAssetBytesDto value) =>
    ArtworkAssetBytes(
      assetId: value.assetId,
      bytes: value.bytes,
      mimeType: value.mimeType,
      width: value.width,
      height: value.height,
    );

ContentSummary contentSummaryFromDto(
  dto.ContentSummaryDto value,
) => ContentSummary(
  gameContentId: contentIdFromDto(value.gameContentId),
  platformId: platformIdFromDto(value.platformId),
  contentType: contentTypeFromDto(value.contentType),
  presence: contentPresenceFromDto(value.presence),
  identification: identificationStateFromDto(value.identification),
  sourceCount: value.sourceCount,
  identity: value.identity == null
      ? null
      : ContentIdentitySummary(
          schemeId: value.identity!.schemeId,
          revision: value.identity!.revision,
          digest: value.identity!.digest,
        ),
  provenance: value.provenance == null
      ? null
      : ContentProvenanceSummary(
          sourceEntryId: sourceEntryIdFromDto(value.provenance!.sourceEntryId),
          associationKey: value.provenance!.associationKey,
          sourceFingerprint: value.provenance!.sourceFingerprint,
          derivedFingerprint: value.provenance!.derivedFingerprint,
          lastObservedScanId: value.provenance!.lastObservedScanId,
          members: [
            for (final member in value.provenance!.members)
              ContentProvenanceMember(
                role: member.role,
                associationKey: member.associationKey,
                sourceEntryId: sourceEntryIdFromDto(member.sourceEntryId),
                sourceFingerprint: member.sourceFingerprint,
                derivedFingerprint: member.derivedFingerprint,
                lastObservedScanId: member.lastObservedScanId,
              ),
          ],
        ),
  sources: [
    for (final source in value.sources) gameContentSourceSummaryFromDto(source),
  ],
);

GameContentSourceSummary gameContentSourceSummaryFromDto(
  dto.GameContentSourceSummaryDto value,
) => GameContentSourceSummary(
  sourceEntryId: sourceEntryIdFromDto(value.sourceEntryId),
  librarySourceId: librarySourceIdFromDto(value.librarySourceId),
  sourceDisplayName: value.sourceDisplayName,
  libraryRootId: libraryRootIdFromDto(value.libraryRootId),
  rootDisplayName: value.rootDisplayName,
  safeLocationPresentation: value.safeLocationPresentation,
);

LibrarySourceId librarySourceIdFromDto(String value) {
  final id = LibrarySourceId.tryParse(value);
  if (id == null) {
    throw const TransportFailure(
      'Native library-source identity is invalid',
      kind: TransportFailureKind.contractMismatch,
    );
  }
  return id;
}

GameMembershipSummary gameMembershipSummaryFromDto(
  dto.GameMembershipSummaryDto value,
) => GameMembershipSummary(
  gameContentId: contentIdFromDto(value.gameContentId),
  relationship: membershipRelationshipFromDto(value.relationship),
  groupingBasis: groupingBasisFromDto(value.groupingBasis),
  groupingRevision: value.groupingRevision,
);

GameId gameIdFromDto(String value) {
  final id = GameId.tryParse(value);
  if (id == null) {
    throw const TransportFailure(
      'Native game identity is invalid',
      kind: TransportFailureKind.contractMismatch,
    );
  }
  return id;
}

ContentId contentIdFromDto(String value) {
  final id = ContentId.tryParse(value);
  if (id == null) {
    throw const TransportFailure(
      'Native game-content identity is invalid',
      kind: TransportFailureKind.contractMismatch,
    );
  }
  return id;
}

PlatformId platformIdFromDto(dto.PlatformIdDto value) => switch (value) {
  dto.PlatformIdDto.nintendoNes => PlatformId.nintendoNes,
  dto.PlatformIdDto.nintendoFds => PlatformId.nintendoFds,
  dto.PlatformIdDto.nintendoSnes => PlatformId.nintendoSnes,
  dto.PlatformIdDto.nintendoGb => PlatformId.nintendoGb,
  dto.PlatformIdDto.nintendoGbc => PlatformId.nintendoGbc,
  dto.PlatformIdDto.nintendoGba => PlatformId.nintendoGba,
  dto.PlatformIdDto.nintendoN64 => PlatformId.nintendoN64,
  dto.PlatformIdDto.nintendoNds => PlatformId.nintendoNds,
  dto.PlatformIdDto.nintendo3Ds => PlatformId.nintendo3ds,
  dto.PlatformIdDto.segaSms => PlatformId.segaSms,
  dto.PlatformIdDto.segaGameGear => PlatformId.segaGameGear,
  dto.PlatformIdDto.segaGenesis => PlatformId.segaGenesis,
  dto.PlatformIdDto.sega32X => PlatformId.sega32x,
  dto.PlatformIdDto.nintendoGameCube => PlatformId.nintendoGameCube,
  dto.PlatformIdDto.nintendoWii => PlatformId.nintendoWii,
  dto.PlatformIdDto.segaCd => PlatformId.segaCd,
  dto.PlatformIdDto.segaSaturn => PlatformId.segaSaturn,
  dto.PlatformIdDto.segaDreamcast => PlatformId.segaDreamcast,
  dto.PlatformIdDto.sonyPlaystation => PlatformId.sonyPlaystation,
  dto.PlatformIdDto.sonyPlaystation2 => PlatformId.sonyPlaystation2,
  dto.PlatformIdDto.sonyPsp => PlatformId.sonyPsp,
};

ContentType contentTypeFromDto(dto.ContentTypeDto value) => switch (value) {
  dto.ContentTypeDto.cartridgeImage => ContentType.cartridgeImage,
  dto.ContentTypeDto.magneticDiskImage => ContentType.magneticDiskImage,
  dto.ContentTypeDto.opticalDiscCd => ContentType.opticalDiscCd,
  dto.ContentTypeDto.opticalDiscGd => ContentType.opticalDiscGd,
  dto.ContentTypeDto.opticalDiscDvd => ContentType.opticalDiscDvd,
  dto.ContentTypeDto.opticalDiscGameCube => ContentType.opticalDiscGameCube,
  dto.ContentTypeDto.opticalDiscWii => ContentType.opticalDiscWii,
  dto.ContentTypeDto.opticalDiscUmd => ContentType.opticalDiscUmd,
};

ContentPresence contentPresenceFromDto(dto.ContentPresenceDto value) =>
    switch (value) {
      dto.ContentPresenceDto.available => ContentPresence.available,
      dto.ContentPresenceDto.partiallyUnavailable =>
        ContentPresence.partiallyUnavailable,
      dto.ContentPresenceDto.unavailable => ContentPresence.unavailable,
      dto.ContentPresenceDto.orphaned => ContentPresence.orphaned,
    };

IdentificationState identificationStateFromDto(
  dto.IdentificationStateDto value,
) => switch (value) {
  dto.IdentificationStateDto.identified => IdentificationState.identified,
  dto.IdentificationStateDto.needsReidentification =>
    IdentificationState.needsReidentification,
  dto.IdentificationStateDto.unidentified => IdentificationState.unidentified,
};

GameLifecycle gameLifecycleFromDto(dto.GameLifecycleDto value) =>
    switch (value) {
      dto.GameLifecycleDto.active => GameLifecycle.active,
      dto.GameLifecycleDto.inactiveOrphan => GameLifecycle.inactiveOrphan,
      dto.GameLifecycleDto.redirected => GameLifecycle.redirected,
    };

HydrationState hydrationStateFromDto(dto.HydrationStateDto value) =>
    switch (value) {
      dto.HydrationStateDto.hydrated => HydrationState.hydrated,
      dto.HydrationStateDto.partiallyHydrated =>
        HydrationState.partiallyHydrated,
      dto.HydrationStateDto.unmatched => HydrationState.unmatched,
      dto.HydrationStateDto.refreshing => HydrationState.refreshing,
    };

HydrationState hydrationStateFromFilterDto(
  dto.LibraryHydrationStateDto value,
) => switch (value) {
  dto.LibraryHydrationStateDto.hydrated => HydrationState.hydrated,
  dto.LibraryHydrationStateDto.partiallyHydrated =>
    HydrationState.partiallyHydrated,
  dto.LibraryHydrationStateDto.unmatched => HydrationState.unmatched,
  dto.LibraryHydrationStateDto.refreshing => HydrationState.refreshing,
};

AvailabilityState availabilityStateFromDto(
  dto.GameAvailabilityStateDto value,
) => switch (value) {
  dto.GameAvailabilityStateDto.available => AvailabilityState.available,
  dto.GameAvailabilityStateDto.partiallyUnavailable =>
    AvailabilityState.partiallyUnavailable,
  dto.GameAvailabilityStateDto.unavailable => AvailabilityState.unavailable,
  dto.GameAvailabilityStateDto.inactiveOrphan =>
    AvailabilityState.inactiveOrphan,
};

AvailabilityState availabilityStateFromFilterDto(
  dto.LibraryAvailabilityStateDto value,
) => switch (value) {
  dto.LibraryAvailabilityStateDto.available => AvailabilityState.available,
  dto.LibraryAvailabilityStateDto.partiallyUnavailable =>
    AvailabilityState.partiallyUnavailable,
  dto.LibraryAvailabilityStateDto.unavailable => AvailabilityState.unavailable,
  dto.LibraryAvailabilityStateDto.inactiveOrphan =>
    AvailabilityState.inactiveOrphan,
};

MembershipRelationship membershipRelationshipFromDto(
  dto.MembershipRelationshipDto value,
) => switch (value) {
  dto.MembershipRelationshipDto.primary => MembershipRelationship.primary,
  dto.MembershipRelationshipDto.secondary => MembershipRelationship.secondary,
  dto.MembershipRelationshipDto.primaryContent =>
    MembershipRelationship.primaryContent,
  dto.MembershipRelationshipDto.regionalVariant =>
    MembershipRelationship.regionalVariant,
  dto.MembershipRelationshipDto.languageVariant =>
    MembershipRelationship.languageVariant,
  dto.MembershipRelationshipDto.revisionVariant =>
    MembershipRelationship.revisionVariant,
  dto.MembershipRelationshipDto.disc => MembershipRelationship.disc,
  dto.MembershipRelationshipDto.equivalentReleaseRepresentation =>
    MembershipRelationship.equivalentReleaseRepresentation,
};

GroupingBasis groupingBasisFromDto(dto.GroupingBasisDto value) =>
    switch (value) {
      dto.GroupingBasisDto.exactContentIdentity =>
        GroupingBasis.exactContentIdentity,
      dto.GroupingBasisDto.provisional => GroupingBasis.provisional,
      dto.GroupingBasisDto.explicitRelationshipEvidence =>
        GroupingBasis.explicitRelationshipEvidence,
    };

SourceEntryId sourceEntryIdFromDto(String value) {
  final id = SourceEntryId(value);
  if (!id.isValid) {
    throw const TransportFailure(
      'Native source-entry identity is invalid',
      kind: TransportFailureKind.contractMismatch,
    );
  }
  return id;
}

SourceEntryKind sourceEntryKindFromDto(dto.SourceEntryKindDto value) =>
    switch (value) {
      dto.SourceEntryKindDto.directory => SourceEntryKind.directory,
      dto.SourceEntryKindDto.file => SourceEntryKind.file,
      dto.SourceEntryKindDto.linkLike => SourceEntryKind.linkLike,
      dto.SourceEntryKindDto.unknown => SourceEntryKind.unknown,
    };

SourceEntryClassification sourceEntryClassificationFromDto(
  dto.SourceEntryClassificationDto value,
) => switch (value) {
  dto.SourceEntryClassificationDto.container =>
    SourceEntryClassification.container,
  dto.SourceEntryClassificationDto.contentCandidate =>
    SourceEntryClassification.contentCandidate,
  dto.SourceEntryClassificationDto.supportingEntry =>
    SourceEntryClassification.supportingEntry,
  dto.SourceEntryClassificationDto.ignored => SourceEntryClassification.ignored,
  dto.SourceEntryClassificationDto.unknown => SourceEntryClassification.unknown,
};

SourceEntry sourceEntryFromDto(dto.SourceEntryDto value) => SourceEntry(
  sourceEntryId: sourceEntryIdFromDto(value.sourceEntryId),
  parentSourceEntryId: value.parentSourceEntryId == null
      ? null
      : sourceEntryIdFromDto(value.parentSourceEntryId!),
  displayName: value.displayName,
  displayLocation: value.displayLocation,
  kind: sourceEntryKindFromDto(value.kind),
  classification: sourceEntryClassificationFromDto(value.classification),
);

SourceEntryDetail sourceEntryDetailFromDto(dto.SourceEntryDetailDto value) =>
    SourceEntryDetail(
      sourceEntryId: sourceEntryIdFromDto(value.sourceEntryId),
      parentSourceEntryId: value.parentSourceEntryId == null
          ? null
          : sourceEntryIdFromDto(value.parentSourceEntryId!),
      displayName: value.displayName,
      displayLocation: value.displayLocation,
      kind: sourceEntryKindFromDto(value.kind),
      classification: sourceEntryClassificationFromDto(value.classification),
    );

SourceEntryChildrenPage sourceEntryChildrenPageFromDto(
  dto.SourceEntryChildrenPageDto value,
) => SourceEntryChildrenPage(
  items: [for (final item in value.items) sourceEntryFromDto(item)],
  nextCursor: value.nextCursor,
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

AddLocalLibraryRootAndScanResult addLocalLibraryRootAndScanResultFromDto(
  dto.AddLocalLibraryRootAndScanResultDto value,
) => switch (value) {
  dto.AddLocalLibraryRootAndScanResultDto_AddedAndScanAdmitted(
    :final field0,
    :final field1,
  ) =>
    AddLocalLibraryRootAndScanResult.addedAndScanAdmitted(
      root: libraryRootFromDto(field0),
      handle: operationHandleFromDto(field1),
    ),
  dto.AddLocalLibraryRootAndScanResultDto_AddedButScanNotAdmitted(
    :final field0,
    :final field1,
  ) =>
    AddLocalLibraryRootAndScanResult.addedButScanNotAdmitted(
      root: libraryRootFromDto(field0),
      issue: switch (field1) {
        dto.LibraryScanChildAdmissionIssueDto_AlreadyScanning(
          :final libraryRootId,
          :final activeJobRunId,
          :final activeScanRunId,
        ) =>
          LibraryScanChildAdmissionIssue.alreadyScanning(
            libraryRootId: libraryRootIdFromDto(libraryRootId),
            activeJobRunId: jobRunIdFromDto(activeJobRunId),
            activeScanRunId: scanRunIdFromDto(activeScanRunId),
          ),
        dto.LibraryScanChildAdmissionIssueDto_AdmissionFailure(:final field0) =>
          LibraryScanChildAdmissionIssue.admissionFailure(
            applicationErrorFromDto(field0),
          ),
      },
    ),
  dto.AddLocalLibraryRootAndScanResultDto_AlreadyConfigured(:final field0) =>
    AddLocalLibraryRootAndScanResult.alreadyConfigured(
      libraryRootIdFromDto(field0),
    ),
  dto.AddLocalLibraryRootAndScanResultDto_OverlapsExisting(
    :final field0,
    :final field1,
  ) =>
    AddLocalLibraryRootAndScanResult.overlapsExisting(
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
) => switch (selection) {
  LocalFilesystemRootSelectionPath(:final selectedFolderPath) =>
    dto.LocalFilesystemRootSelectionDto.path(
      selectedFolderPath: selectedFolderPath,
    ),
  LocalFilesystemRootSelectionProvider(:final selectionIdentity) =>
    dto.LocalFilesystemRootSelectionDto.providerSelection(
      selectionIdentity: selectionIdentity,
    ),
  LocalFilesystemRootSelectionMacos(
    :final selectedFolderPath,
    :final authorization,
  ) =>
    dto.LocalFilesystemRootSelectionDto.macosAuthorized(
      selectedFolderPath: selectedFolderPath,
      authorization: dto.MacosAuthorization(
        field0: Uint8List.fromList(authorization),
      ),
    ),
};

LocalFilesystemBrowseRoot localFilesystemBrowseRootFromDto(
  dto.LocalFilesystemBrowseRootDto value,
) => LocalFilesystemBrowseRoot(
  location: LocalFilesystemBrowseLocation(value.location),
  displayName: value.displayName,
  safeLocationPresentation: value.safeLocationPresentation,
);

LocalFilesystemBrowsePage localFilesystemBrowsePageFromDto(
  dto.LocalFilesystemBrowsePageDto value,
) => LocalFilesystemBrowsePage(
  current: localFilesystemBrowseRootFromDto(value.current),
  breadcrumbs: value.breadcrumbs
      .map(
        (breadcrumb) => LocalFilesystemBrowseBreadcrumb(
          location: LocalFilesystemBrowseLocation(breadcrumb.location),
          displayName: breadcrumb.displayName,
        ),
      )
      .toList(growable: false),
  directories: value.directories
      .map(
        (directory) => LocalFilesystemBrowseDirectory(
          location: LocalFilesystemBrowseLocation(directory.location),
          displayName: directory.displayName,
        ),
      )
      .toList(growable: false),
  nextCursor: value.nextCursor,
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
    const SourceEntriesChangeScope.rootChildren(),
  dto.SourceEntriesChangeScopeDto_EntryChildren(:final field0) =>
    SourceEntriesChangeScope.entryChildren(
      parentSourceEntryId: sourceEntryIdFromDto(field0),
    ),
  dto.SourceEntriesChangeScopeDto_EntireRootHierarchy() =>
    const SourceEntriesChangeScope.entireRootHierarchy(),
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

LibraryScanAdmissionExclusion libraryScanAdmissionExclusionFromDto(
  dto.LibraryScanAdmissionExclusionDto value,
) => LibraryScanAdmissionExclusion(
  libraryRootId: libraryRootIdFromDto(value.libraryRootId),
  reason: value.reason,
  activeJobRunId: value.activeJobRunId == null
      ? null
      : jobRunIdFromDto(value.activeJobRunId!),
  activeScanRunId: value.activeScanRunId == null
      ? null
      : scanRunIdFromDto(value.activeScanRunId!),
  applicationError: value.applicationError == null
      ? null
      : applicationErrorFromDto(value.applicationError!),
);

StartLibraryScanAllResult startLibraryScanAllResultFromDto(
  dto.StartLibraryScanAllResultDto value,
) => switch (value) {
  dto.StartLibraryScanAllResultDto_Admitted(
    :final operationHandle,
    :final admittedRoots,
    :final exclusions,
  ) =>
    StartLibraryScanAllResult.admitted(
      handle: operationHandleFromDto(operationHandle),
      admittedRoots: [
        for (final rootId in admittedRoots) libraryRootIdFromDto(rootId),
      ],
      exclusions: [
        for (final exclusion in exclusions)
          libraryScanAdmissionExclusionFromDto(exclusion),
      ],
    ),
  dto.StartLibraryScanAllResultDto_NothingEligible(:final exclusions) =>
    StartLibraryScanAllResult.nothingEligible(
      exclusions: [
        for (final exclusion in exclusions)
          libraryScanAdmissionExclusionFromDto(exclusion),
      ],
    ),
};

LibraryScanAllRequestResolution libraryScanAllRequestResolutionFromDto(
  dto.LibraryScanAllRequestResolutionDto value,
) => switch (value) {
  dto.LibraryScanAllRequestResolutionDto_Admitted(
    :final operationHandle,
    :final admittedRoots,
    :final exclusions,
  ) =>
    LibraryScanAllRequestResolution.admitted(
      handle: operationHandleFromDto(operationHandle),
      admittedRoots: [
        for (final rootId in admittedRoots) libraryRootIdFromDto(rootId),
      ],
      exclusions: [
        for (final exclusion in exclusions)
          libraryScanAdmissionExclusionFromDto(exclusion),
      ],
    ),
  dto.LibraryScanAllRequestResolutionDto_NothingAdmitted() =>
    const LibraryScanAllRequestResolution.nothingAdmitted(),
};

OperationHandle operationHandleFromDto(dto.OperationHandleDto value) =>
    OperationHandle(
      jobRunId: jobRunIdFromDto(value.jobRunId),
      operationType: value.operationType,
    );

LibraryRootScanAdmission? libraryRootScanAdmissionFromDto(
  dto.LibraryRootScanAdmissionReferenceDto? value,
) => value == null
    ? null
    : LibraryRootScanAdmission(
        jobRunId: jobRunIdFromDto(value.jobRunId),
        scanRunId: scanRunIdFromDto(value.scanRunId),
      );

RetryJobResult retryJobResultFromDto(dto.RetryJobResultDto value) =>
    switch (value) {
      dto.RetryJobResultDto_Admitted(:final field0) => RetryJobResult.admitted(
        operationHandleFromDto(field0),
      ),
      dto.RetryJobResultDto_AlreadyRetried(:final field0) =>
        RetryJobResult.alreadyRetried(jobRunIdFromDto(field0)),
      dto.RetryJobResultDto_NotAdmitted(:final field0) =>
        RetryJobResult.notAdmitted(switch (field0) {
          dto.RetryNotAdmittedReasonDto_SourceRunNotTerminal() =>
            const RetryNotAdmittedReason.sourceRunNotTerminal(),
          dto.RetryNotAdmittedReasonDto_OperationNotRetryable() =>
            const RetryNotAdmittedReason.operationNotRetryable(),
          dto.RetryNotAdmittedReasonDto_NoEligibleTargets(:final field0) =>
            RetryNotAdmittedReason.noEligibleTargets([
              for (final exclusion in field0)
                libraryScanAdmissionExclusionFromDto(exclusion),
            ]),
        }),
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
      dto.OperationDetailDto_LibraryRefresh(:final field0) =>
        OperationDetail.libraryRefresh(libraryRefreshJobDetailFromDto(field0)),
      dto.OperationDetailDto_GameRefresh(:final field0) =>
        OperationDetail.gameRefresh(gameRefreshJobDetailFromDto(field0)),
      dto.OperationDetailDto_LibraryResolutionRefresh(:final field0) =>
        OperationDetail.libraryResolutionRefresh(
          libraryResolutionRefreshJobDetailFromDto(field0),
        ),
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
      libraryScanAdmissionExclusionFromDto(exclusion),
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
    entriesObserved: value.progress.entriesObserved?.toInt(),
    entriesCommitted: value.progress.entriesCommitted?.toInt(),
    issueCount: value.progress.issueCount?.toInt(),
  ),
  retrySourceJobRunId: value.retrySourceJobRunId == null
      ? null
      : jobRunIdFromDto(value.retrySourceJobRunId!),
  retrySuccessorJobRunId: value.retrySuccessorJobRunId == null
      ? null
      : jobRunIdFromDto(value.retrySuccessorJobRunId!),
);

LibraryRefreshJobDetail libraryRefreshJobDetailFromDto(
  dto.LibraryRefreshJobDetailDto value,
) => LibraryRefreshJobDetail(
  trigger: value.trigger,
  triggerRootId: value.triggerRootId,
  mode: value.mode,
  requestedRootIds: [
    for (final rootId in value.requestedRootIds) libraryRootIdFromDto(rootId),
  ],
  scanRuns: [for (final scan in value.scanRuns) scanRunSummaryFromDto(scan)],
  progress: refreshProgressFactsFromDto(value.progress),
  retrySourceJobRunId: value.retrySourceJobRunId == null
      ? null
      : jobRunIdFromDto(value.retrySourceJobRunId!),
  retrySuccessorJobRunId: value.retrySuccessorJobRunId == null
      ? null
      : jobRunIdFromDto(value.retrySuccessorJobRunId!),
);

GameRefreshJobDetail gameRefreshJobDetailFromDto(
  dto.GameRefreshJobDetailDto value,
) => GameRefreshJobDetail(
  gameIds: [for (final gameId in value.gameIds) gameIdFromDto(gameId)],
  mode: value.mode,
  progress: refreshProgressFactsFromDto(value.progress),
  retrySourceJobRunId: value.retrySourceJobRunId == null
      ? null
      : jobRunIdFromDto(value.retrySourceJobRunId!),
  retrySuccessorJobRunId: value.retrySuccessorJobRunId == null
      ? null
      : jobRunIdFromDto(value.retrySuccessorJobRunId!),
);

LibraryResolutionRefreshJobDetail libraryResolutionRefreshJobDetailFromDto(
  dto.LibraryResolutionRefreshJobDetailDto value,
) => LibraryResolutionRefreshJobDetail(
  jobRunId: jobRunIdFromDto(value.jobRunId),
  settingsRevision: value.settingsRevision.toInt(),
  progress: refreshProgressFactsFromDto(value.progress),
  retrySourceJobRunId: value.retrySourceJobRunId == null
      ? null
      : jobRunIdFromDto(value.retrySourceJobRunId!),
  retrySuccessorJobRunId: value.retrySuccessorJobRunId == null
      ? null
      : jobRunIdFromDto(value.retrySuccessorJobRunId!),
);

RefreshProgressFacts refreshProgressFactsFromDto(
  dto.RefreshProgressFactsDto value,
) => RefreshProgressFacts(
  phase: value.phase,
  completedUnits: value.completedUnits?.toInt(),
  totalUnits: value.totalUnits?.toInt(),
  statusKey: value.statusKey,
  issueCount: value.issueCount?.toInt(),
);

ScanRunSummary scanRunSummaryFromDto(dto.ScanRunDto value) => ScanRunSummary(
  scanRunId: scanRunIdFromDto(value.scanRunId),
  jobRunId: jobRunIdFromDto(value.jobRunId),
  libraryRootId: libraryRootIdFromDto(value.libraryRootId),
  displayName: value.displayName,
  safeLocationDisplay: value.safeLocationDisplay,
  status: jobScanStatusFromDto(value.status),
  startedAtMs: value.startedAtMs.toInt(),
  completedAtMs: value.completedAtMs?.toInt(),
);
