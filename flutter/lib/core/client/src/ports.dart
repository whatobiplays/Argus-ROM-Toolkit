import 'models.dart';

/// Framework-neutral operations implemented by the native bridge adapter.
abstract interface class RuntimeGateway {
  Future<RuntimeState> getRuntimeState();

  Future<RuntimeState> initialize();

  Future<RuntimeState> retryStartup(
    RuntimeInstanceId expectedRuntimeInstanceId,
  );

  Future<RuntimeState> resetAppearanceSettings(
    RuntimeInstanceId expectedRuntimeInstanceId,
  );

  Future<RuntimeState> exitFailedRuntime(
    RuntimeInstanceId expectedRuntimeInstanceId,
  );

  Future<void> generalShutdown();

  /// Closes the current native event connection without changing runtime
  /// lifecycle state. Used by client teardown so a parked native subscription
  /// can return deterministically before local disposal.
  Future<void> closeEventConnection();
}

/// Focused runtime capability exposed to startup and recovery consumers.
abstract interface class RuntimeApi {
  Future<RuntimeState> getRuntimeState();

  Future<RuntimeState> retryStartup(
    RuntimeInstanceId expectedRuntimeInstanceId,
  );

  Future<RuntimeState> resetAppearanceSettings(
    RuntimeInstanceId expectedRuntimeInstanceId,
  );

  Future<RuntimeState> exitFailedRuntime(
    RuntimeInstanceId expectedRuntimeInstanceId,
  );

  Future<void> generalShutdown();
}

/// Framework-neutral appearance operations.
abstract interface class AppearanceGateway {
  Future<AppearanceSettings> getAppearanceSettings();

  Future<void> updateAppearanceSettings(AppearanceSettings settings);
}

/// Focused appearance-settings capability. The complete aggregate is the
/// only mutation input and successful updates do not echo a state snapshot.
abstract interface class SettingsApi {
  Future<AppearanceSettings> getAppearanceSettings();

  Future<void> updateAppearanceSettings(AppearanceSettings settings);
}

/// Framework-neutral configured library-root operations.
abstract interface class SourcesGateway {
  Future<LibraryRootPage> listLibraryRoots({
    required int offset,
    required int pageSize,
  });

  Future<LibraryRoot> getLibraryRoot(LibraryRootId libraryRootId);

  Future<AddLocalLibraryRootResult> addLocalLibraryRoot(
    LocalFilesystemRootSelection selection,
  );

  Future<AddLocalLibraryRootAndScanResult> addLocalLibraryRootAndScan(
    LocalFilesystemRootSelection selection,
  );

  Future<RemoveLibraryRootResult> removeLibraryRoot(
    LibraryRootId libraryRootId,
  );

  Future<StartLibraryScanResult> startLibraryScan(LibraryRootId libraryRootId);

  Future<StartLibraryScanAllResult> startLibraryScanAll(
    ScanAllRequestIdentity requestIdentity,
  );

  Future<SourceEntryChildrenPage> listSourceEntryChildren({
    required LibraryRootId libraryRootId,
    SourceEntryId? parentSourceEntryId,
    String? cursor,
    required int pageSize,
  });

  Future<SourceEntryDetail> getSourceEntry(SourceEntryId sourceEntryId);

  /// Lists currently mounted safe local-filesystem browse roots.
  Future<List<LocalFilesystemBrowseRoot>> listLocalFilesystemBrowseRoots();

  /// Lists one bounded direct-child local-filesystem browse page.
  Future<LocalFilesystemBrowsePage> listLocalFilesystemBrowseDirectories({
    required LocalFilesystemBrowseLocation location,
    String? cursor,
    required int pageSize,
  });
}

/// Focused Sources capability. Queries return immutable authoritative
/// snapshots; mutations return typed outcomes and never fabricate read state.
abstract interface class SourcesApi {
  Future<LibraryRootPage> listLibraryRoots({
    required int offset,
    required int pageSize,
  });

  Future<LibraryRoot> getLibraryRoot(LibraryRootId libraryRootId);

  Future<AddLocalLibraryRootResult> addLocalLibraryRoot(
    LocalFilesystemRootSelection selection,
  );

  Future<AddLocalLibraryRootAndScanResult> addLocalLibraryRootAndScan(
    LocalFilesystemRootSelection selection,
  );

  Future<RemoveLibraryRootResult> removeLibraryRoot(
    LibraryRootId libraryRootId,
  );

  Future<StartLibraryScanResult> startLibraryScan(LibraryRootId libraryRootId);

  Future<StartLibraryScanAllResult> startLibraryScanAll(
    ScanAllRequestIdentity requestIdentity,
  );

  Future<SourceEntryChildrenPage> listSourceEntryChildren({
    required LibraryRootId libraryRootId,
    SourceEntryId? parentSourceEntryId,
    String? cursor,
    required int pageSize,
  });

  Future<SourceEntryDetail> getSourceEntry(SourceEntryId sourceEntryId);

  /// Lists currently mounted safe local-filesystem browse roots.
  Future<List<LocalFilesystemBrowseRoot>> listLocalFilesystemBrowseRoots();

  /// Lists one bounded direct-child local-filesystem browse page.
  Future<LocalFilesystemBrowsePage> listLocalFilesystemBrowseDirectories({
    required LocalFilesystemBrowseLocation location,
    String? cursor,
    required int pageSize,
  });
}

/// Framework-neutral durable logical-library reads.
abstract interface class LibraryGateway {
  Future<GamePage> listGames(ListGamesRequest request);

  Future<GetGameResult> getGame(GameId gameId);
}

/// Focused logical-library capability. It exposes durable local state only;
/// provider metadata, rich presentation data, raw locators, and parser details
/// remain out.
abstract interface class LibraryReads {
  Future<GamePage> listGames(ListGamesRequest request);

  Future<GetGameResult> getGame(GameId gameId);
}

/// Optional metadata-provider capability. Implementations expose readiness and
/// write-only credential mutations; they never provide secret reads.
abstract interface class MetadataProvidersGateway {
  Future<List<MetadataProviderReadiness>> listMetadataProviderReadiness();

  Future<ProviderCredentialReadiness> setMetadataProviderCredential({
    required String providerId,
    required List<int> credentialInput,
  });

  Future<ProviderCredentialReadiness> removeMetadataProviderCredential(
    String providerId,
  );
}

/// Convenience extension for the only credentialed provider in the current
/// production roster. The generic gateway remains the authoritative seam.
extension MetadataProvidersGatewaySteamGridDb on MetadataProvidersGateway {
  Future<ProviderCredentialReadiness> setSteamgriddbCredential(
    List<int> secret,
  ) => setMetadataProviderCredential(
    providerId: 'steamgriddb',
    credentialInput: secret,
  );

  Future<ProviderCredentialReadiness> removeSteamgriddbCredential() =>
      removeMetadataProviderCredential('steamgriddb');
}

/// Optional bounded artwork-byte capability.
abstract interface class ArtworkGateway {
  Future<ArtworkAssetBytes> getArtworkAssetBytes(String assetId);
}

/// Focused metadata-provider capability exposed to application consumers.
abstract interface class MetadataProvidersApi {
  Future<List<MetadataProviderReadiness>> listMetadataProviderReadiness();

  Future<ProviderCredentialReadiness> setMetadataProviderCredential({
    required String providerId,
    required List<int> credentialInput,
  });

  Future<ProviderCredentialReadiness> removeMetadataProviderCredential(
    String providerId,
  );
}

/// Convenience extension for SteamGridDB credential callers.
extension MetadataProvidersApiSteamGridDb on MetadataProvidersApi {
  Future<ProviderCredentialReadiness> setSteamgriddbCredential(
    List<int> secret,
  ) => setMetadataProviderCredential(
    providerId: 'steamgriddb',
    credentialInput: secret,
  );

  Future<ProviderCredentialReadiness> removeSteamgriddbCredential() =>
      removeMetadataProviderCredential('steamgriddb');
}

/// Focused artwork-byte capability exposed to application consumers.
abstract interface class ArtworkApi {
  Future<ArtworkAssetBytes> getArtworkAssetBytes(String assetId);
}

/// Framework-neutral durable job observation and control operations.
abstract interface class JobsGateway {
  Future<JobSummaryPage> listActiveJobs();

  Future<JobSummaryPage> listRecentTerminalJobs({
    required int offset,
    required int pageSize,
  });

  Future<JobDetail> getJob(JobRunId jobRunId);

  Future<CancelJobResult> cancelJob(JobRunId jobRunId);

  Future<RetryJobResult> retryJob(JobRunId jobRunId);

  /// Jobs-authoritative newest scan-run admission for one root.
  ///
  /// This focused query powers Add & Scan transport-ambiguity reconciliation;
  /// child admission must never be inferred from root `lastScan` alone.
  Future<LibraryRootScanAdmission?> getRootScanAdmission(
    LibraryRootId libraryRootId,
  );

  /// Authoritative Scan All request-identity reconciliation.
  Future<LibraryScanAllRequestResolution> resolveScanAllRequest(
    ScanAllRequestIdentity requestIdentity,
  );
}

/// Focused Jobs capability. Queries return immutable authoritative
/// snapshots; controls never fabricate lifecycle state.
abstract interface class JobsApi {
  Future<JobSummaryPage> listActiveJobs();

  Future<JobSummaryPage> listRecentTerminalJobs({
    required int offset,
    required int pageSize,
  });

  Future<JobDetail> getJob(JobRunId jobRunId);

  Future<CancelJobResult> cancelJob(JobRunId jobRunId);

  Future<RetryJobResult> retryJob(JobRunId jobRunId);

  Future<LibraryRootScanAdmission?> getRootScanAdmission(
    LibraryRootId libraryRootId,
  );

  /// Authoritative Scan All request-identity reconciliation.
  Future<LibraryScanAllRequestResolution> resolveScanAllRequest(
    ScanAllRequestIdentity requestIdentity,
  );

  /// Narrow active-job summary for the application shell.
  Future<ActiveJobSummary> getActiveJobSummary();
}

/// Framework-neutral diagnostics operations.
abstract interface class DiagnosticsGateway {
  Future<DiagnosticsExport> exportStartupDiagnostics(
    RuntimeInstanceId expectedRuntimeInstanceId,
    String destination,
  );

  Future<TechnicalDetails> startupTechnicalDetails(
    RuntimeInstanceId expectedRuntimeInstanceId,
  );

  Future<void> openStartupDataDirectory(
    RuntimeInstanceId expectedRuntimeInstanceId,
  );
}

/// Focused failed-startup diagnostics capability.
abstract interface class DiagnosticsApi {
  Future<DiagnosticsExport> exportStartupDiagnostics(
    RuntimeInstanceId expectedRuntimeInstanceId,
    String destination,
  );

  Future<TechnicalDetails> startupTechnicalDetails(
    RuntimeInstanceId expectedRuntimeInstanceId,
  );

  Future<void> openStartupDataDirectory(
    RuntimeInstanceId expectedRuntimeInstanceId,
  );
}

/// Optional additive capability for hosts that can publish a backend-owned
/// diagnostics artifact through a system share surface. The existing
/// destination-based [DiagnosticsApi] contract remains unchanged for desktop.
abstract interface class DiagnosticsSharingGateway {
  bool get supportsDiagnosticsSharing;

  Future<DiagnosticsExport> exportStartupDiagnosticsForSharing(
    RuntimeInstanceId expectedRuntimeInstanceId,
  );
}

/// Focused no-destination diagnostics-sharing capability.
abstract interface class DiagnosticsSharingApi {
  Future<DiagnosticsExport> exportStartupDiagnosticsForSharing(
    RuntimeInstanceId expectedRuntimeInstanceId,
  );
}

/// Outcome of one event-bind attempt.
///
/// [stream] is the mapped runtime-event stream. [nativeAttached] reports
/// whether this attempt actually established the one native event connection;
/// a lifecycle-expected rejection (stale admission epoch or closed boundary)
/// returns a normally-completing stream with `nativeAttached == false`.
final class EventBindResult {
  const EventBindResult({required this.stream, required this.nativeAttached});

  final Stream<RuntimeEvent> stream;
  final bool nativeAttached;
}

/// Native stream adapter. The generation argument is a logical admission
/// guard; the FRB operation itself reads the authoritative current generation.
/// The returned future completes only after the one native event connection
/// for that generation has attached (or was deterministically rejected), so
/// callers can distinguish native connection readiness from local
/// stream-listener installation.
abstract interface class EventGateway {
  Future<EventBindResult> subscribeEvents(RuntimeInstanceId generation);
}

/// Focused mapped notification stream. Generated stream handles and native
/// transport objects remain private to the bridge-backed root client.
abstract interface class EventsApi {
  Stream<RuntimeEvent> get events;
}

/// Composition seam used by embedding/tests before production startup adopts
/// the client in Slice 006.
abstract interface class ClientBootstrap {
  Future<RuntimeState> initialize();
}

/// Complete gateway surface required by [ArgusClient].
abstract interface class ArgusClientGateway
    implements
        RuntimeGateway,
        AppearanceGateway,
        DiagnosticsGateway,
        JobsGateway,
        SourcesGateway,
        EventGateway {}
