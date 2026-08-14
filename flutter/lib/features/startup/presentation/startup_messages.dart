import 'package:argus/core/client/client.dart';

/// Maps a backend message key to user-safe presentation text.
String messageForKey(String key) => switch (key) {
  'errors.configuration.persisted_settings_invalid' =>
    'Saved appearance settings are invalid and prevented startup.',
  'errors.configuration.invalid' => 'Argus configuration is invalid.',
  'errors.filesystem.permission_denied' =>
    'Argus does not have permission to access its data files.',
  'errors.persistence.database_locked' =>
    'The Argus database is locked by another process.',
  'errors.persistence.database_open_failed' =>
    'The Argus database could not be opened.',
  'errors.persistence.migration_failed' =>
    'The Argus database could not be updated to the current version.',
  'errors.persistence.incompatible_schema' =>
    'The Argus database is not compatible with this version of the app.',
  'errors.runtime.stale_instance' =>
    'Argus changed state while the recovery action was being prepared.',
  'errors.internal.unexpected' =>
    'Argus could not start due to an unexpected error.',
  _ => 'Argus could not start.',
};

/// User-safe bootstrap-failure message. Raw failure strings are never shown.
String bootstrapFailureMessage(Object failure) {
  if (failure is TransportFailure) {
    return 'Argus could not connect to its native runtime.';
  }
  if (failure is ApplicationFailure) {
    return messageForKey(failure.error.messageKey.value);
  }
  return 'Argus could not initialize.';
}

/// User-safe message for a failed recovery/diagnostic operation.
String operationFailureMessage(Object failure) {
  if (failure is ApplicationFailure) {
    return messageForKey(failure.error.messageKey.value);
  }
  if (failure is TransportFailure) {
    return 'The operation could not reach the Argus runtime.';
  }
  return 'The operation could not be completed.';
}

/// Responsibility-oriented startup-phase context, never implementation detail.
String startupPhaseContext(StartupPhase phase) => switch (phase) {
  StartupPhase.environmentInitialization => 'Initial environment setup failed.',
  StartupPhase.observabilityInitialization => 'Diagnostics setup failed.',
  StartupPhase.configurationInitialization =>
    'Configuration could not be loaded.',
  StartupPhase.persistenceInitialization => 'Database initialization failed.',
  StartupPhase.settingsInitialization => 'Settings could not be loaded.',
  StartupPhase.coreServicesInitialization =>
    'Core services could not be initialized.',
  StartupPhase.eventInfrastructureInitialization =>
    'Event infrastructure could not be initialized.',
  StartupPhase.readinessValidation => 'Final startup validation failed.',
};

/// Non-color, non-authoritative label for a last-known runtime context.
String lastKnownLifecycleLabel(RuntimeLifecycle lifecycle) =>
    switch (lifecycle) {
      RuntimeLifecycle.uninitialized => 'not initialized',
      RuntimeLifecycle.starting => 'starting',
      RuntimeLifecycle.ready => 'ready',
      RuntimeLifecycle.startupFailed => 'startup failed',
      RuntimeLifecycle.shuttingDown => 'closing',
      RuntimeLifecycle.stopped => 'stopped',
    };
