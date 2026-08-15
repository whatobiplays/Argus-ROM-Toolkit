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

  Future<RemoveLibraryRootResult> removeLibraryRoot(
    LibraryRootId libraryRootId,
  );

  Future<StartLibraryScanResult> startLibraryScan(LibraryRootId libraryRootId);

  Future<SourceEntryChildrenPage> listSourceEntryChildren({
    required LibraryRootId libraryRootId,
    SourceEntryId? parentSourceEntryId,
    String? cursor,
    required int pageSize,
  });

  Future<SourceEntryDetail> getSourceEntry(SourceEntryId sourceEntryId);
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

  Future<RemoveLibraryRootResult> removeLibraryRoot(
    LibraryRootId libraryRootId,
  );

  Future<StartLibraryScanResult> startLibraryScan(LibraryRootId libraryRootId);

  Future<SourceEntryChildrenPage> listSourceEntryChildren({
    required LibraryRootId libraryRootId,
    SourceEntryId? parentSourceEntryId,
    String? cursor,
    required int pageSize,
  });

  Future<SourceEntryDetail> getSourceEntry(SourceEntryId sourceEntryId);
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
