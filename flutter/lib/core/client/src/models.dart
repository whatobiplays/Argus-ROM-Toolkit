import 'package:freezed_annotation/freezed_annotation.dart';

import 'failures.dart';

part 'models.freezed.dart';

/// Opaque identity for one native runtime generation.
final class RuntimeInstanceId {
  const RuntimeInstanceId(this.value);

  final String value;

  bool get isValid =>
      RegExp(r'^[0-9a-f]{32}$').hasMatch(value) &&
      value.split('').any((character) => character != '0');

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) =>
      other is RuntimeInstanceId && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// Stable machine-readable application error code.
final class ErrorCode {
  const ErrorCode(this.value);

  final String value;

  bool get isValid =>
      RegExp(r'^ARGUS\.V[0-9]+\.[A-Z0-9_]+(\.[A-Z0-9_]+)*$').hasMatch(value);

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) => other is ErrorCode && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// Canonical non-zero 128-bit operation trace identity.
final class TraceId {
  const TraceId(this.value);

  final String value;

  bool get isValid =>
      RegExp(r'^[0-9a-f]{32}$').hasMatch(value) &&
      value != '00000000000000000000000000000000';

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) => other is TraceId && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// Stable localization key owned by the backend catalog.
final class MessageKey {
  const MessageKey(this.value);

  final String value;

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) => other is MessageKey && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// Broad stable backend error classification.
enum ErrorCategory {
  validation,
  persistence,
  filesystem,
  provider,
  runtime,
  configuration,
  operation,
  internal;

  static ErrorCategory fromWire(String value) => switch (value) {
    'validation' => ErrorCategory.validation,
    'persistence' => ErrorCategory.persistence,
    'filesystem' => ErrorCategory.filesystem,
    'provider' => ErrorCategory.provider,
    'runtime' => ErrorCategory.runtime,
    'configuration' => ErrorCategory.configuration,
    'operation' => ErrorCategory.operation,
    'internal' => ErrorCategory.internal,
    _ => throw const TransportFailure(
      'Unknown error category',
      kind: TransportFailureKind.contractMismatch,
    ),
  };
}

/// Application impact of a published failure.
enum ApplicationSeverity {
  info,
  warning,
  error,
  fatal;

  static ApplicationSeverity fromWire(String value) => switch (value) {
    'Info' => ApplicationSeverity.info,
    'Warning' => ApplicationSeverity.warning,
    'Error' => ApplicationSeverity.error,
    'Fatal' => ApplicationSeverity.fatal,
    _ => throw const TransportFailure(
      'Unknown application severity',
      kind: TransportFailureKind.contractMismatch,
    ),
  };
}

/// Recovery precondition communicated by a published failure.
enum Recoverability {
  none,
  retry,
  userAction,
  restartRequired,
  manualIntervention;

  static Recoverability fromWire(String value) => switch (value) {
    'None' => Recoverability.none,
    'Retry' => Recoverability.retry,
    'UserAction' => Recoverability.userAction,
    'RestartRequired' => Recoverability.restartRequired,
    'ManualIntervention' => Recoverability.manualIntervention,
    _ => throw const TransportFailure(
      'Unknown recoverability',
      kind: TransportFailureKind.contractMismatch,
    ),
  };
}

/// Stable retry strategy communicated by a published failure.
enum RetryPolicy {
  never,
  immediate,
  backoff,
  userInitiated;

  static RetryPolicy fromWire(String value) => switch (value) {
    'Never' => RetryPolicy.never,
    'Immediate' => RetryPolicy.immediate,
    'Backoff' => RetryPolicy.backoff,
    'UserInitiated' => RetryPolicy.userInitiated,
    _ => throw const TransportFailure(
      'Unknown retry policy',
      kind: TransportFailureKind.contractMismatch,
    ),
  };
}

/// Closed vocabulary of allowlisted safe-context fields.
enum SafeContextField {
  stage,
  pathClass,
  migrationCount,
  schemaVersion,
  migrationOutcome,
  applicationVersion,
  backendVersion,
  platform,
  architecture,
  technicalClass,
  failureRole,
  settingsDomain,
  persistedSettingsReason;

  static SafeContextField fromWire(String value) => switch (value) {
    'stage' => SafeContextField.stage,
    'path_class' => SafeContextField.pathClass,
    'migration_count' => SafeContextField.migrationCount,
    'schema_version' => SafeContextField.schemaVersion,
    'migration_outcome' => SafeContextField.migrationOutcome,
    'application_version' => SafeContextField.applicationVersion,
    'backend_version' => SafeContextField.backendVersion,
    'platform' => SafeContextField.platform,
    'architecture' => SafeContextField.architecture,
    'technical_class' => SafeContextField.technicalClass,
    'failure_role' => SafeContextField.failureRole,
    'settings_domain' => SafeContextField.settingsDomain,
    'persisted_settings_reason' => SafeContextField.persistedSettingsReason,
    _ => throw const TransportFailure(
      'Unknown safe-context field',
      kind: TransportFailureKind.contractMismatch,
    ),
  };
}

/// Bounded scalar value permitted in frontend safe context.
@freezed
sealed class SafeContextValue with _$SafeContextValue {
  const factory SafeContextValue.string(String value) = SafeContextValueString;

  const factory SafeContextValue.integer(int value) = SafeContextValueInteger;
}

/// Runtime lifecycle states exposed by the root client.
enum RuntimeLifecycle {
  uninitialized,
  starting,
  ready,
  startupFailed,
  shuttingDown,
  stopped,
}

/// Fixed Phase 000 startup phase vocabulary.
enum StartupPhase {
  environmentInitialization,
  observabilityInitialization,
  configurationInitialization,
  persistenceInitialization,
  settingsInitialization,
  coreServicesInitialization,
  eventInfrastructureInitialization,
  readinessValidation,
}

/// Declarative failed-startup actions.
enum RecoveryActionKind {
  retryStartup,
  resetAppearanceSettings,
  exportDiagnostics,
  copyTechnicalDetails,
  openDataDirectory,
  exit,
}

/// Stable application error projected from Rust.
@freezed
sealed class ClientApplicationError with _$ClientApplicationError {
  const factory ClientApplicationError({
    required ErrorCode code,
    required ErrorCategory category,
    required ApplicationSeverity severity,
    required Recoverability recoverability,
    required RetryPolicy retryPolicy,
    required MessageKey messageKey,
    required TraceId traceId,
    required List<SafeContextEntry> safeContext,
  }) = _ClientApplicationError;
}

/// One bounded allowlisted structured diagnostic entry.
@freezed
sealed class SafeContextEntry with _$SafeContextEntry {
  const factory SafeContextEntry({
    required SafeContextField field,
    required SafeContextValue value,
  }) = _SafeContextEntry;
}

/// One generation-bound recovery action.
@freezed
sealed class RecoveryAction with _$RecoveryAction {
  const factory RecoveryAction({required RecoveryActionKind kind}) =
      _RecoveryAction;
}

/// Authoritative failed-startup context.
@freezed
sealed class StartupFailure with _$StartupFailure {
  const factory StartupFailure({
    required StartupPhase phase,
    required ClientApplicationError error,
    required List<RecoveryAction> recoveryActions,
  }) = _StartupFailure;
}

/// Canonical runtime snapshot. Its lifecycle and failure fields are the sole
/// state authority used by the client and later feature layers.
@freezed
sealed class RuntimeState with _$RuntimeState {
  const factory RuntimeState.uninitialized({
    required RuntimeInstanceId runtimeInstanceId,
  }) = RuntimeStateUninitialized;

  const factory RuntimeState.starting({
    required RuntimeInstanceId runtimeInstanceId,
    StartupPhase? phase,
  }) = RuntimeStateStarting;

  const factory RuntimeState.ready({
    required RuntimeInstanceId runtimeInstanceId,
  }) = RuntimeStateReady;

  const factory RuntimeState.startupFailed({
    required RuntimeInstanceId runtimeInstanceId,
    required StartupFailure failure,
  }) = RuntimeStateStartupFailed;

  const factory RuntimeState.shuttingDown({
    required RuntimeInstanceId runtimeInstanceId,
  }) = RuntimeStateShuttingDown;

  const factory RuntimeState.stopped({
    required RuntimeInstanceId runtimeInstanceId,
  }) = RuntimeStateStopped;
}

/// Canonical appearance aggregate.
enum ThemeMode { system, light, dark }

@freezed
sealed class AppearanceSettings with _$AppearanceSettings {
  const factory AppearanceSettings({required ThemeMode themeMode}) =
      _AppearanceSettings;
}

/// Terminal diagnostics export result.
enum DiagnosticsExportOutcome { created, partial }

@freezed
sealed class DiagnosticsExport with _$DiagnosticsExport {
  const factory DiagnosticsExport({
    required DiagnosticsExportOutcome outcome,
    required String destinationClassification,
  }) = _DiagnosticsExport;
}

@freezed
sealed class TechnicalDetails with _$TechnicalDetails {
  const factory TechnicalDetails({required String text}) = _TechnicalDetails;
}

/// Typed outward runtime notifications. The sequence remains visible so a
/// reconnect cannot silently claim that notifications were reconciled.
@freezed
sealed class RuntimeEventPayload with _$RuntimeEventPayload {
  const factory RuntimeEventPayload.runtimeStateChanged({
    required RuntimeLifecycle lifecycle,
  }) = RuntimeEventPayloadRuntimeStateChanged;

  const factory RuntimeEventPayload.startupFailed({
    required StartupPhase phase,
  }) = RuntimeEventPayloadStartupFailed;

  const factory RuntimeEventPayload.appearanceSettingsChanged() =
      RuntimeEventPayloadAppearanceSettingsChanged;
}

@freezed
sealed class RuntimeEvent with _$RuntimeEvent {
  const factory RuntimeEvent({
    required RuntimeInstanceId runtimeInstanceId,
    required BigInt sequence,
    required BigInt occurredAtMs,
    required RuntimeEventPayload payload,
  }) = _RuntimeEvent;
}
