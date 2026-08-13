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

/// Native stream adapter. The generation argument is a logical admission
/// guard; the FRB operation itself reads the authoritative current generation.
abstract interface class EventGateway {
  Stream<RuntimeEvent> subscribeEvents(RuntimeInstanceId generation);
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
        EventGateway {}
