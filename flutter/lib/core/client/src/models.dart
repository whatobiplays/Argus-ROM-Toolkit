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

/// Opaque identity for one configured library root.
final class LibraryRootId {
  const LibraryRootId(this.value);

  final String value;

  /// Parses one canonical lowercase hex identity, or returns null when the
  /// value is malformed. Route boundaries use this to keep invalid identifiers
  /// out of feature state.
  static LibraryRootId? tryParse(String value) {
    final id = LibraryRootId(value);
    return id.isValid ? id : null;
  }

  bool get isValid =>
      RegExp(r'^[0-9a-f]{32}$').hasMatch(value) &&
      value.split('').any((character) => character != '0');

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) =>
      other is LibraryRootId && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// Opaque identity for one background execution attempt.
final class JobRunId {
  const JobRunId(this.value);

  final String value;

  /// Parses one canonical lowercase hex identity, or returns null when the
  /// value is malformed.
  static JobRunId? tryParse(String value) {
    final id = JobRunId(value);
    return id.isValid ? id : null;
  }

  bool get isValid =>
      RegExp(r'^[0-9a-f]{32}$').hasMatch(value) &&
      value.split('').any((character) => character != '0');

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) => other is JobRunId && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// Opaque identity for one root-specific scan run.
final class ScanRunId {
  const ScanRunId(this.value);

  final String value;

  bool get isValid =>
      RegExp(r'^[0-9a-f]{32}$').hasMatch(value) &&
      value.split('').any((character) => character != '0');

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) => other is ScanRunId && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// Opaque identity for one persisted source-graph entry.
final class SourceEntryId {
  const SourceEntryId(this.value);

  final String value;

  /// Parses one canonical lowercase hex identity, or returns null when the
  /// value is malformed.
  static SourceEntryId? tryParse(String value) {
    final id = SourceEntryId(value);
    return id.isValid ? id : null;
  }

  bool get isValid =>
      RegExp(r'^[0-9a-f]{32}$').hasMatch(value) &&
      value.split('').any((character) => character != '0');

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) =>
      other is SourceEntryId && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// Durable client-generated identity for one Scan All request.
///
/// The identity is used only for Scan All transport-ambiguity
/// reconciliation; it is never a logical Job identity.
final class ScanAllRequestIdentity {
  const ScanAllRequestIdentity(this.value);

  static const int maxBytes = 256;

  final String value;

  /// Parses one canonical request identity, or returns null when the value
  /// is malformed (empty, too long, or containing characters outside the
  /// canonical ASCII alphanumeric `-_.` alphabet).
  static ScanAllRequestIdentity? tryParse(String value) {
    final identity = ScanAllRequestIdentity(value);
    return identity.isValid ? identity : null;
  }

  bool get isValid =>
      value.isNotEmpty &&
      value.length <= maxBytes &&
      RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(value);

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) =>
      other is ScanAllRequestIdentity && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// Minimal identity-only handle returned by successful background admission.
final class OperationHandle {
  const OperationHandle({required this.jobRunId, required this.operationType});

  final JobRunId jobRunId;
  final String operationType;

  @override
  bool operator ==(Object other) =>
      other is OperationHandle &&
      other.jobRunId == jobRunId &&
      other.operationType == operationType;

  @override
  int get hashCode => Object.hash(jobRunId, operationType);
}

/// Canonical persisted job lifecycle vocabulary.
enum JobLifecycleState {
  queued,
  preparing,
  running,
  completed,
  completedWithIssues,
  failed,
  cancelled,
  interrupted,
  abandoned;

  static JobLifecycleState fromWire(String value) => switch (value) {
    'queued' => JobLifecycleState.queued,
    'preparing' => JobLifecycleState.preparing,
    'running' => JobLifecycleState.running,
    'completed' => JobLifecycleState.completed,
    'completed_with_issues' => JobLifecycleState.completedWithIssues,
    'failed' => JobLifecycleState.failed,
    'cancelled' => JobLifecycleState.cancelled,
    'interrupted' => JobLifecycleState.interrupted,
    'abandoned' => JobLifecycleState.abandoned,
    _ => throw const TransportFailure(
      'Unknown job lifecycle state',
      kind: TransportFailureKind.contractMismatch,
    ),
  };

  bool get isTerminal => switch (this) {
    JobLifecycleState.completed ||
    JobLifecycleState.completedWithIssues ||
    JobLifecycleState.failed ||
    JobLifecycleState.cancelled ||
    JobLifecycleState.interrupted ||
    JobLifecycleState.abandoned => true,
    _ => false,
  };
}

/// Canonical per-root scan status.
enum JobScanStatus {
  running,
  complete,
  partial,
  failed,
  cancelled,
  abandoned;

  static JobScanStatus fromWire(String value) => switch (value) {
    'running' => JobScanStatus.running,
    'complete' => JobScanStatus.complete,
    'partial' => JobScanStatus.partial,
    'failed' => JobScanStatus.failed,
    'cancelled' => JobScanStatus.cancelled,
    'abandoned' => JobScanStatus.abandoned,
    _ => throw const TransportFailure(
      'Unknown scan status',
      kind: TransportFailureKind.contractMismatch,
    ),
  };
}

/// Bounded list-row projection for Jobs landing and shell summaries.
@freezed
sealed class JobListItem with _$JobListItem {
  const factory JobListItem({
    required JobRunId jobRunId,
    required String operationType,
    required JobLifecycleState lifecycleState,
    String? phase,
    required int createdAtMs,
    int? startedAtMs,
    int? terminalAtMs,
    required bool cancellationRequested,
    String? safeContextSummary,
  }) = _JobListItem;
}

/// Backend-authoritative control availability.
@freezed
sealed class JobControlAvailability with _$JobControlAvailability {
  const factory JobControlAvailability({
    required bool canCancel,
    required bool canRetry,
  }) = _JobControlAvailability;
}

/// Bounded terminal failure projection.
@freezed
sealed class BoundedTerminalFailure with _$BoundedTerminalFailure {
  const factory BoundedTerminalFailure({
    String? errorCode,
    String? safeContext,
  }) = _BoundedTerminalFailure;
}

/// Capability-neutral generic execution projection.
@freezed
sealed class JobRunProjection with _$JobRunProjection {
  const factory JobRunProjection({
    required JobRunId jobRunId,
    required String operationType,
    required JobLifecycleState lifecycleState,
    String? phase,
    int? completedUnits,
    int? totalUnits,
    String? statusKey,
    required int createdAtMs,
    int? queuedAtMs,
    int? startedAtMs,
    int? terminalAtMs,
    required bool cancellationRequested,
    required JobControlAvailability controls,
    BoundedTerminalFailure? boundedTerminalFailure,
  }) = _JobRunProjection;
}

/// One per-root scan projection with its historical display snapshot.
@freezed
sealed class ScanRunSummary with _$ScanRunSummary {
  const factory ScanRunSummary({
    required ScanRunId scanRunId,
    required JobRunId jobRunId,
    required LibraryRootId libraryRootId,
    required String displayName,
    required String safeLocationDisplay,
    required JobScanStatus status,
    required int startedAtMs,
    int? completedAtMs,
  }) = _ScanRunSummary;
}

/// Bounded historical root display summary.
@freezed
sealed class LibraryScanRootSummary with _$LibraryScanRootSummary {
  const factory LibraryScanRootSummary({
    required LibraryRootId libraryRootId,
    required String displayName,
    required String safeLocationDisplay,
  }) = _LibraryScanRootSummary;
}

/// One durable typed admission exclusion.
@freezed
sealed class LibraryScanAdmissionExclusion
    with _$LibraryScanAdmissionExclusion {
  const factory LibraryScanAdmissionExclusion({
    required LibraryRootId libraryRootId,
    required String reason,
    JobRunId? activeJobRunId,
    ScanRunId? activeScanRunId,
    ClientApplicationError? applicationError,
  }) = _LibraryScanAdmissionExclusion;
}

/// Scan-specific structured progress facts.
@freezed
sealed class ScanProgressFacts with _$ScanProgressFacts {
  const factory ScanProgressFacts({
    String? phase,
    int? completedUnits,
    int? totalUnits,
    String? statusKey,
    required int rootsRequested,
    required int rootsAdmitted,
    required int rootsTerminal,
    int? entriesObserved,
    int? entriesCommitted,
    int? issueCount,
  }) = _ScanProgressFacts;
}

/// Typed LibraryScan operation detail.
@freezed
sealed class LibraryScanJobDetail with _$LibraryScanJobDetail {
  const factory LibraryScanJobDetail({
    required List<LibraryScanRootSummary> requestedRoots,
    required List<LibraryScanRootSummary> admittedRoots,
    required List<LibraryScanAdmissionExclusion> exclusions,
    required List<ScanRunSummary> scanRuns,
    required ScanProgressFacts progress,
    JobRunId? retrySourceJobRunId,
    JobRunId? retrySuccessorJobRunId,
  }) = _LibraryScanJobDetail;
}

/// Closed typed operation-detail union.
@freezed
sealed class OperationDetail with _$OperationDetail {
  const factory OperationDetail.libraryScan(LibraryScanJobDetail detail) =
      OperationDetailLibraryScan;
}

/// Authoritative job detail with typed operation detail.
@freezed
sealed class JobDetail with _$JobDetail {
  const factory JobDetail({
    required JobRunProjection job,
    required OperationDetail operationDetail,
  }) = _JobDetail;
}

/// Bounded authoritative job-row page.
final class JobSummaryPage {
  const JobSummaryPage({
    required this.items,
    required this.totalCount,
    this.nextOffset,
  });

  final List<JobListItem> items;
  final int totalCount;
  final int? nextOffset;
}

/// Narrow active-job facts needed by the shell indicator.
@freezed
sealed class ActiveJobSummary with _$ActiveJobSummary {
  const factory ActiveJobSummary({
    required int activeCount,
    JobRunId? soleActiveJobRunId,
  }) = _ActiveJobSummary;
}

/// Typed outcome of one single-root scan admission.
@freezed
sealed class StartLibraryScanResult with _$StartLibraryScanResult {
  const factory StartLibraryScanResult.admitted(OperationHandle handle) =
      StartLibraryScanResultAdmitted;

  const factory StartLibraryScanResult.alreadyScanning({
    required LibraryRootId libraryRootId,
    required JobRunId activeJobRunId,
    required ScanRunId activeScanRunId,
  }) = StartLibraryScanResultAlreadyScanning;
}

/// Typed outcome of one multi-root Scan All admission.
@freezed
sealed class StartLibraryScanAllResult with _$StartLibraryScanAllResult {
  const factory StartLibraryScanAllResult.admitted({
    required OperationHandle handle,
    required List<LibraryRootId> admittedRoots,
    required List<LibraryScanAdmissionExclusion> exclusions,
  }) = StartLibraryScanAllResultAdmitted;

  const factory StartLibraryScanAllResult.nothingEligible({
    required List<LibraryScanAdmissionExclusion> exclusions,
  }) = StartLibraryScanAllResultNothingEligible;
}

/// Authoritative resolution of one Scan All request identity after
/// transport ambiguity.
@freezed
sealed class LibraryScanAllRequestResolution
    with _$LibraryScanAllRequestResolution {
  const factory LibraryScanAllRequestResolution.admitted({
    required OperationHandle handle,
    required List<LibraryRootId> admittedRoots,
    required List<LibraryScanAdmissionExclusion> exclusions,
  }) = LibraryScanAllRequestResolutionAdmitted;

  const factory LibraryScanAllRequestResolution.nothingAdmitted() =
      LibraryScanAllRequestResolutionNothingAdmitted;
}

/// Typed outcome of one cancel request.
enum CancelJobResult { cancellationRequested, noLongerCancellable }

/// Typed reason one retry request was not admitted.
@freezed
sealed class RetryNotAdmittedReason with _$RetryNotAdmittedReason {
  const factory RetryNotAdmittedReason.sourceRunNotTerminal() =
      RetryNotAdmittedReasonSourceRunNotTerminal;

  const factory RetryNotAdmittedReason.operationNotRetryable() =
      RetryNotAdmittedReasonOperationNotRetryable;

  const factory RetryNotAdmittedReason.noEligibleTargets(
    List<LibraryScanAdmissionExclusion> exclusions,
  ) = RetryNotAdmittedReasonNoEligibleTargets;
}

/// Typed outcome of one retry request.
@freezed
sealed class RetryJobResult with _$RetryJobResult {
  const factory RetryJobResult.admitted(OperationHandle handle) =
      RetryJobResultAdmitted;

  const factory RetryJobResult.alreadyRetried(JobRunId existingJobRunId) =
      RetryJobResultAlreadyRetried;

  const factory RetryJobResult.notAdmitted(RetryNotAdmittedReason reason) =
      RetryJobResultNotAdmitted;
}

/// Explicit source-graph invalidation scope union.
///
/// `entryChildren` preserves the exact parent identity end-to-end; the scope
/// is an invalidation hint only and never becomes data authority.
@freezed
sealed class SourceEntriesChangeScope with _$SourceEntriesChangeScope {
  const factory SourceEntriesChangeScope.rootChildren() =
      SourceEntriesChangeScopeRootChildren;

  const factory SourceEntriesChangeScope.entryChildren({
    required SourceEntryId parentSourceEntryId,
  }) = SourceEntriesChangeScopeEntryChildren;

  const factory SourceEntriesChangeScope.entireRootHierarchy() =
      SourceEntriesChangeScopeEntireRootHierarchy;
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

/// Application-owned root availability vocabulary.
enum LibraryRootAvailability {
  available,
  unavailable,
  unknown;

  static LibraryRootAvailability fromWire(String value) => switch (value) {
    'available' => LibraryRootAvailability.available,
    'unavailable' => LibraryRootAvailability.unavailable,
    'unknown' => LibraryRootAvailability.unknown,
    _ => throw const TransportFailure(
      'Unknown root availability',
      kind: TransportFailureKind.contractMismatch,
    ),
  };
}

/// Provider-owned overlap vocabulary projected from the backend.
enum RootRelationship {
  same,
  ancestor,
  descendant,
  disjoint,
  unknown;

  static RootRelationship fromWire(String value) => switch (value) {
    'same' => RootRelationship.same,
    'ancestor' => RootRelationship.ancestor,
    'descendant' => RootRelationship.descendant,
    'disjoint' => RootRelationship.disjoint,
    'unknown' => RootRelationship.unknown,
    _ => throw const TransportFailure(
      'Unknown root relationship',
      kind: TransportFailureKind.contractMismatch,
    ),
  };
}

/// Closed historical root last-scan status vocabulary.
enum LibraryRootLastScanStatus {
  complete,
  partial,
  unavailable,
  cancelled,
  failed,
  abandoned;

  static LibraryRootLastScanStatus fromWire(String value) => switch (value) {
    'complete' => LibraryRootLastScanStatus.complete,
    'partial' => LibraryRootLastScanStatus.partial,
    'unavailable' => LibraryRootLastScanStatus.unavailable,
    'cancelled' => LibraryRootLastScanStatus.cancelled,
    'failed' => LibraryRootLastScanStatus.failed,
    'abandoned' => LibraryRootLastScanStatus.abandoned,
    _ => throw const TransportFailure(
      'Unknown root last-scan status',
      kind: TransportFailureKind.contractMismatch,
    ),
  };
}

/// Application-owned persisted source-entry kind vocabulary.
enum SourceEntryKind {
  directory,
  file,
  linkLike,
  unknown;

  static SourceEntryKind fromWire(String value) => switch (value) {
    'directory' => SourceEntryKind.directory,
    'file' => SourceEntryKind.file,
    'link_like' => SourceEntryKind.linkLike,
    'unknown' => SourceEntryKind.unknown,
    _ => throw const TransportFailure(
      'Unknown source-entry kind',
      kind: TransportFailureKind.contractMismatch,
    ),
  };
}

/// Application-owned source-entry classification vocabulary.
enum SourceEntryClassification {
  container,
  contentCandidate,
  supportingEntry,
  ignored,
  unknown;

  static SourceEntryClassification fromWire(String value) => switch (value) {
    'container' => SourceEntryClassification.container,
    'content_candidate' => SourceEntryClassification.contentCandidate,
    'supporting_entry' => SourceEntryClassification.supportingEntry,
    'ignored' => SourceEntryClassification.ignored,
    'unknown' => SourceEntryClassification.unknown,
    _ => throw const TransportFailure(
      'Unknown source-entry classification',
      kind: TransportFailureKind.contractMismatch,
    ),
  };
}

/// Bounded terminal scan-history summary carried by a root projection.
final class LibraryRootLastScan {
  const LibraryRootLastScan({
    required this.scanRunId,
    required this.jobRunId,
    required this.status,
    required this.startedAtMs,
    this.completedAtMs,
  });

  final String scanRunId;
  final String jobRunId;
  final LibraryRootLastScanStatus status;
  final int startedAtMs;
  final int? completedAtMs;

  @override
  bool operator ==(Object other) =>
      other is LibraryRootLastScan &&
      other.scanRunId == scanRunId &&
      other.jobRunId == jobRunId &&
      other.status == status &&
      other.startedAtMs == startedAtMs &&
      other.completedAtMs == completedAtMs;

  @override
  int get hashCode =>
      Object.hash(scanRunId, jobRunId, status, startedAtMs, completedAtMs);
}

/// Bounded active scan-ownership summary carried by a root projection.
final class LibraryRootActiveScan {
  const LibraryRootActiveScan({
    required this.scanRunId,
    required this.jobRunId,
    required this.owningJobRootCount,
  });

  final String scanRunId;
  final String jobRunId;
  final int owningJobRootCount;

  @override
  bool operator ==(Object other) =>
      other is LibraryRootActiveScan &&
      other.scanRunId == scanRunId &&
      other.jobRunId == jobRunId &&
      other.owningJobRootCount == owningJobRootCount;

  @override
  int get hashCode => Object.hash(scanRunId, jobRunId, owningJobRootCount);
}

/// Authoritative immutable projection of one configured library root.
@freezed
sealed class LibraryRoot with _$LibraryRoot {
  const factory LibraryRoot({
    required LibraryRootId id,
    required String displayName,
    required String safeLocationPresentation,
    required LibraryRootAvailability availability,
    LibraryRootLastScan? lastScan,
    LibraryRootActiveScan? activeScan,
  }) = _LibraryRoot;
}

/// Bounded authoritative configured-root page.
final class LibraryRootPage {
  const LibraryRootPage({
    required this.items,
    required this.offset,
    required this.pageSize,
    required this.totalCount,
  });

  final List<LibraryRoot> items;
  final int offset;
  final int pageSize;
  final int totalCount;
}

/// Opaque identity for one durable logical game.
final class GameId {
  const GameId(this.value);

  final String value;

  static GameId? tryParse(String value) {
    final id = GameId(value);
    return id.isValid ? id : null;
  }

  bool get isValid =>
      RegExp(r'^[0-9a-f]{32}$').hasMatch(value) &&
      value.split('').any((character) => character != '0');

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) => other is GameId && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// Opaque identity for one durable logical content unit.
final class ContentId {
  const ContentId(this.value);

  final String value;

  static ContentId? tryParse(String value) {
    final id = ContentId(value);
    return id.isValid ? id : null;
  }

  bool get isValid =>
      RegExp(r'^[0-9a-f]{32}$').hasMatch(value) &&
      value.split('').any((character) => character != '0');

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) => other is ContentId && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// Production platform identity used by logical-library projections.
enum PlatformId {
  nintendoGb,
  nintendoGbc,
  nintendoGba;

  static PlatformId fromWire(String value) => switch (value) {
    'nintendo_gb' => PlatformId.nintendoGb,
    'nintendo_gbc' => PlatformId.nintendoGbc,
    'nintendo_gba' => PlatformId.nintendoGba,
    _ => throw const TransportFailure(
      'Unknown logical-library platform',
      kind: TransportFailureKind.contractMismatch,
    ),
  };
}

/// Content representation exposed by the focused logical-library read.
enum ContentType { cartridgeImage }

/// Content availability/presence, independent from identification proof.
enum ContentPresence { available, partiallyUnavailable, unavailable, orphaned }

/// Current identity-proof state, independent from content availability.
enum IdentificationState { identified, needsReidentification, unidentified }

/// Durable logical-game lifecycle.
enum GameLifecycle { active, inactiveOrphan, redirected }

/// Local fallback hydration state.
enum HydrationState { hydrated, partiallyHydrated, unmatched, refreshing }

/// Provider readiness state projected by Rust without secret material.
enum ProviderReadinessState {
  ready,
  disabled,
  missingCredentials,
  invalidCredentials,
  misconfigured,
  unavailable;

  static ProviderReadinessState fromWire(String value) => switch (value) {
    'ready' => ProviderReadinessState.ready,
    'disabled' => ProviderReadinessState.disabled,
    'missing_credentials' => ProviderReadinessState.missingCredentials,
    'invalid_credentials' => ProviderReadinessState.invalidCredentials,
    'misconfigured' => ProviderReadinessState.misconfigured,
    'unavailable' => ProviderReadinessState.unavailable,
    _ => throw const TransportFailure(
      'Unknown provider readiness state',
      kind: TransportFailureKind.contractMismatch,
    ),
  };
}

/// Provider capability vocabulary used by readiness projections.
enum ProviderCapability {
  contentMatching,
  metadataRefresh,
  artworkDiscovery;

  static ProviderCapability fromWire(String value) => switch (value) {
    'content_matching' => ProviderCapability.contentMatching,
    'metadata_refresh' => ProviderCapability.metadataRefresh,
    'artwork_discovery' => ProviderCapability.artworkDiscovery,
    _ => throw const TransportFailure(
      'Unknown provider capability',
      kind: TransportFailureKind.contractMismatch,
    ),
  };
}

/// Local fallback availability state.
enum AvailabilityState {
  available,
  partiallyUnavailable,
  unavailable,
  inactiveOrphan,
}

/// Current game membership role.
enum MembershipRelationship { primary, secondary }

/// Current grouping evidence basis.
enum GroupingBasis { exactContentIdentity, provisional }

/// Safe current identity proof summary.
final class ContentIdentitySummary {
  const ContentIdentitySummary({
    required this.schemeId,
    required this.revision,
    required this.digest,
  });

  final String schemeId;
  final int revision;
  final String digest;
}

/// Safe exact proving provenance summary. Raw paths and locators are absent.
final class ContentProvenanceSummary {
  const ContentProvenanceSummary({
    required this.sourceEntryId,
    required this.associationKey,
    required this.sourceFingerprint,
    required this.lastObservedScanId,
  });

  final SourceEntryId sourceEntryId;
  final String associationKey;
  final String? sourceFingerprint;
  final String lastObservedScanId;
}

/// Focused durable logical-content summary.
final class ContentSummary {
  const ContentSummary({
    required this.gameContentId,
    required this.platformId,
    required this.contentType,
    required this.presence,
    required this.identification,
    required this.sourceCount,
    required this.identity,
    required this.provenance,
  });

  final ContentId gameContentId;
  final PlatformId platformId;
  final ContentType contentType;
  final ContentPresence presence;
  final IdentificationState identification;
  final int sourceCount;
  final ContentIdentitySummary? identity;
  final ContentProvenanceSummary? provenance;
}

/// Focused durable membership summary.
final class GameMembershipSummary {
  const GameMembershipSummary({
    required this.gameContentId,
    required this.relationship,
    required this.groupingBasis,
    required this.groupingRevision,
  });

  final ContentId gameContentId;
  final MembershipRelationship relationship;
  final GroupingBasis groupingBasis;
  final int groupingRevision;
}

/// Bounded logical-library list row.
final class GameLibraryRow {
  const GameLibraryRow({
    required this.gameId,
    required this.displayTitle,
    required this.platformId,
    required this.hydrationState,
    required this.contentCount,
    required this.sourceCount,
    required this.availabilityState,
    required this.updatedAtMs,
  });

  final GameId gameId;
  final String displayTitle;
  final PlatformId platformId;
  final HydrationState hydrationState;
  final int contentCount;
  final int sourceCount;
  final AvailabilityState availabilityState;
  final int updatedAtMs;
}

/// Bounded logical-library page with an opaque continuation cursor.
final class GamePage {
  const GamePage({required this.items, this.nextCursor});

  final List<GameLibraryRow> items;
  final String? nextCursor;
}

/// Focused durable logical-game detail.
final class GameDetail {
  const GameDetail({
    required this.gameId,
    required this.platformId,
    required this.lifecycle,
    required this.hydrationState,
    required this.fallbackTitle,
    required this.memberships,
    required this.content,
    required this.availabilityState,
    this.resolvedMetadata,
    this.resolvedArtwork = const <ResolvedArtwork>[],
  });

  final GameId gameId;
  final PlatformId platformId;
  final GameLifecycle lifecycle;
  final HydrationState hydrationState;
  final String fallbackTitle;
  final List<GameMembershipSummary> memberships;
  final List<ContentSummary> content;
  final AvailabilityState availabilityState;
  final ResolvedMetadata? resolvedMetadata;
  final List<ResolvedArtwork> resolvedArtwork;
}

/// Safe field-level provenance for resolved metadata.
final class MetadataFieldProvenance {
  const MetadataFieldProvenance({
    required this.field,
    required this.providerId,
    required this.externalGameId,
    required this.source,
  });

  final String field;
  final String? providerId;
  final String? externalGameId;
  final String source;
}

/// Game-level derived metadata returned with focused detail reads.
final class ResolvedMetadata {
  const ResolvedMetadata({
    required this.displayTitle,
    required this.sortTitle,
    required this.description,
    required this.releaseDate,
    required this.developers,
    required this.publishers,
    required this.genres,
    required this.presentationRegion,
    required this.presentationLanguages,
    required this.fieldProvenance,
    required this.resolutionRevision,
    required this.resolvedAt,
    required this.providerId,
  });

  final String? displayTitle;
  final String? sortTitle;
  final String? description;
  final String? releaseDate;
  final List<String> developers;
  final List<String> publishers;
  final List<String> genres;
  final String? presentationRegion;
  final List<String> presentationLanguages;
  final List<MetadataFieldProvenance> fieldProvenance;
  final int resolutionRevision;
  final int resolvedAt;
  final String? providerId;
}

/// Game-level artwork selection. Provider locators are deliberately absent.
final class ResolvedArtwork {
  const ResolvedArtwork({
    required this.artworkType,
    required this.referenceId,
    required this.assetId,
    required this.ordering,
    required this.selectionReason,
    required this.resolutionRevision,
    required this.resolvedAt,
  });

  final String artworkType;
  final String referenceId;
  final String? assetId;
  final int ordering;
  final String selectionReason;
  final int resolutionRevision;
  final int resolvedAt;
}

/// Safe provider readiness projection for capability inspection.
final class MetadataProviderReadiness {
  const MetadataProviderReadiness({
    required this.providerId,
    required this.enabled,
    required this.capabilityReadiness,
    required this.credentialConfigured,
  });

  final String providerId;
  final bool enabled;
  final List<ProviderCapabilityReadiness> capabilityReadiness;
  final bool credentialConfigured;
}

/// Readiness of one provider capability.
final class ProviderCapabilityReadiness {
  const ProviderCapabilityReadiness({
    required this.capability,
    required this.state,
  });

  final ProviderCapability capability;
  final ProviderReadinessState state;
}

/// Safe result of a write-only credential mutation.
final class ProviderCredentialReadiness {
  const ProviderCredentialReadiness({
    required this.providerId,
    required this.state,
    required this.credentialConfigured,
  });

  final String providerId;
  final ProviderReadinessState state;
  final bool credentialConfigured;
}

/// Original validated artwork bytes addressed by their content digest.
final class ArtworkAssetBytes {
  const ArtworkAssetBytes({
    required this.assetId,
    required this.bytes,
    required this.mimeType,
    required this.width,
    required this.height,
  });

  final String assetId;
  final List<int> bytes;
  final String mimeType;
  final int width;
  final int height;
}

/// Focused logical-game lookup result.
sealed class GetGameResult {
  const GetGameResult();
}

final class GetGameFound extends GetGameResult {
  const GetGameFound(this.detail);

  final GameDetail detail;
}

final class GetGameRedirected extends GetGameResult {
  const GetGameRedirected(this.canonicalGameId);

  final GameId canonicalGameId;
}

/// Closed BE-008 logical-library scope vocabulary.
sealed class LibraryScope {
  const LibraryScope._();

  const factory LibraryScope.all() = LibraryScopeAll;
  const factory LibraryScope.platform(String platformId) = LibraryScopePlatform;
  const factory LibraryScope.source(String sourceId) = LibraryScopeSource;
  const factory LibraryScope.libraryRoot(String libraryRootId) =
      LibraryScopeLibraryRoot;
}

final class LibraryScopeAll extends LibraryScope {
  const LibraryScopeAll() : super._();
}

final class LibraryScopePlatform extends LibraryScope {
  const LibraryScopePlatform(this.platformId) : super._();

  final String platformId;
}

final class LibraryScopeSource extends LibraryScope {
  const LibraryScopeSource(this.sourceId) : super._();

  final String sourceId;
}

final class LibraryScopeLibraryRoot extends LibraryScope {
  const LibraryScopeLibraryRoot(this.libraryRootId) : super._();

  final String libraryRootId;
}

/// Closed BE-008 sort-field vocabulary.
enum LibrarySortField { displayTitle, platform, releaseDate, updatedAt }

/// Closed BE-008 sort-direction vocabulary.
enum LibrarySortDirection { ascending, descending }

/// Structurally valid BE-008 filter shape.
final class LibraryFilter {
  const LibraryFilter({
    this.platformIds = const [],
    this.regions = const [],
    this.hydrationStates = const [],
    this.availabilityStates = const [],
  });

  final List<String> platformIds;
  final List<String> regions;
  final List<HydrationState> hydrationStates;
  final List<AvailabilityState> availabilityStates;

  bool get isEmpty =>
      platformIds.isEmpty &&
      regions.isEmpty &&
      hydrationStates.isEmpty &&
      availabilityStates.isEmpty;
}

/// Structurally valid BE-008 sort shape.
final class LibrarySort {
  const LibrarySort({
    this.field = LibrarySortField.displayTitle,
    this.direction = LibrarySortDirection.ascending,
  });

  final LibrarySortField field;
  final LibrarySortDirection direction;
}

/// Full logical-library query shape. P03-001 activates only its baseline
/// values; unsupported values are rejected by the native bridge.
final class ListGamesRequest {
  const ListGamesRequest({
    this.scope = const LibraryScopeAll(),
    this.searchText,
    this.filters = const LibraryFilter(),
    this.sort = const LibrarySort(),
    this.cursor,
    this.pageSize = 50,
  });

  final LibraryScope scope;
  final String? searchText;
  final LibraryFilter filters;
  final LibrarySort sort;
  final String? cursor;
  final int pageSize;
}

/// Safe authoritative row projection for one source entry.
@freezed
sealed class SourceEntry with _$SourceEntry {
  const factory SourceEntry({
    required SourceEntryId sourceEntryId,
    SourceEntryId? parentSourceEntryId,
    required String displayName,
    required String displayLocation,
    required SourceEntryKind kind,
    required SourceEntryClassification classification,
  }) = _SourceEntry;
}

/// Safe authoritative detail projection for one source entry.
@freezed
sealed class SourceEntryDetail with _$SourceEntryDetail {
  const factory SourceEntryDetail({
    required SourceEntryId sourceEntryId,
    SourceEntryId? parentSourceEntryId,
    required String displayName,
    required String displayLocation,
    required SourceEntryKind kind,
    required SourceEntryClassification classification,
  }) = _SourceEntryDetail;
}

/// One bounded authoritative direct-child page.
final class SourceEntryChildrenPage {
  const SourceEntryChildrenPage({required this.items, this.nextCursor});

  final List<SourceEntry> items;

  /// Opaque continuation token. Flutter never parses or synthesizes it.
  final String? nextCursor;
}

/// Opaque provider-owned location returned by the local-filesystem browser.
final class LocalFilesystemBrowseLocation {
  const LocalFilesystemBrowseLocation(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      other is LocalFilesystemBrowseLocation && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// Safe mounted browse root projection.
final class LocalFilesystemBrowseRoot {
  const LocalFilesystemBrowseRoot({
    required this.location,
    required this.displayName,
    required this.safeLocationPresentation,
  });

  final LocalFilesystemBrowseLocation location;
  final String displayName;
  final String safeLocationPresentation;
}

/// Safe provider-generated breadcrumb projection.
final class LocalFilesystemBrowseBreadcrumb {
  const LocalFilesystemBrowseBreadcrumb({
    required this.location,
    required this.displayName,
  });

  final LocalFilesystemBrowseLocation location;
  final String displayName;
}

/// Safe selectable direct-child directory projection.
final class LocalFilesystemBrowseDirectory {
  const LocalFilesystemBrowseDirectory({
    required this.location,
    required this.displayName,
  });

  final LocalFilesystemBrowseLocation location;
  final String displayName;
}

/// One bounded local-filesystem browse page.
final class LocalFilesystemBrowsePage {
  const LocalFilesystemBrowsePage({
    required this.current,
    required this.breadcrumbs,
    required this.directories,
    required this.nextCursor,
  });

  final LocalFilesystemBrowseRoot current;
  final List<LocalFilesystemBrowseBreadcrumb> breadcrumbs;
  final List<LocalFilesystemBrowseDirectory> directories;
  final String? nextCursor;
}

/// Closed local-folder selection union.
///
/// The unnamed constructor remains a compatibility factory for desktop
/// callers that already provide a validated picker path. Android browse
/// selections use [LocalFilesystemRootSelection.providerSelection] and carry
/// only the provider-issued opaque identity.
sealed class LocalFilesystemRootSelection {
  const LocalFilesystemRootSelection._();

  /// Compatibility path-selection constructor for existing desktop callers.
  const factory LocalFilesystemRootSelection(String selectedFolderPath) =
      LocalFilesystemRootSelectionPath;

  /// Explicit desktop/native path selection.
  const factory LocalFilesystemRootSelection.path(String selectedFolderPath) =
      LocalFilesystemRootSelectionPath;

  /// Opaque provider-issued browse selection.
  const factory LocalFilesystemRootSelection.providerSelection(
    String selectionIdentity,
  ) = LocalFilesystemRootSelectionProvider;

  /// Returns the path for a path selection.
  ///
  /// Provider selections do not have a path and must be handled as the
  /// provider identity they carry instead.
  String get selectedFolderPath => switch (this) {
    LocalFilesystemRootSelectionPath(:final selectedFolderPath) =>
      selectedFolderPath,
    LocalFilesystemRootSelectionProvider() => throw StateError(
      'Provider selections do not expose a filesystem path',
    ),
  };
}

/// Path variant of [LocalFilesystemRootSelection].
final class LocalFilesystemRootSelectionPath
    extends LocalFilesystemRootSelection {
  const LocalFilesystemRootSelectionPath(this.selectedFolderPath) : super._();

  @override
  final String selectedFolderPath;
}

/// Provider-identity variant of [LocalFilesystemRootSelection].
final class LocalFilesystemRootSelectionProvider
    extends LocalFilesystemRootSelection {
  const LocalFilesystemRootSelectionProvider(this.selectionIdentity)
    : super._();

  final String selectionIdentity;
}

/// Typed outcome of one root-only add operation.
@freezed
sealed class AddLocalLibraryRootResult with _$AddLocalLibraryRootResult {
  const factory AddLocalLibraryRootResult.added(LibraryRoot root) =
      AddLocalLibraryRootResultAdded;

  const factory AddLocalLibraryRootResult.alreadyConfigured(
    LibraryRootId existingLibraryRootId,
  ) = AddLocalLibraryRootResultAlreadyConfigured;

  const factory AddLocalLibraryRootResult.overlapsExisting({
    required LibraryRootId existingLibraryRootId,
    required RootRelationship relationship,
  }) = AddLocalLibraryRootResultOverlapsExisting;
}

/// Typed child LibraryScan admission issue for an Add & Scan workflow.
@freezed
sealed class LibraryScanChildAdmissionIssue
    with _$LibraryScanChildAdmissionIssue {
  const factory LibraryScanChildAdmissionIssue.alreadyScanning({
    required LibraryRootId libraryRootId,
    required JobRunId activeJobRunId,
    required ScanRunId activeScanRunId,
  }) = LibraryScanChildAdmissionIssueAlreadyScanning;

  const factory LibraryScanChildAdmissionIssue.admissionFailure(
    ClientApplicationError error,
  ) = LibraryScanChildAdmissionIssueAdmissionFailure;
}

/// Typed outcome of one Add & Scan composite workflow.
@freezed
sealed class AddLocalLibraryRootAndScanResult
    with _$AddLocalLibraryRootAndScanResult {
  const factory AddLocalLibraryRootAndScanResult.addedAndScanAdmitted({
    required LibraryRoot root,
    required OperationHandle handle,
  }) = AddLocalLibraryRootAndScanResultAddedAndScanAdmitted;

  const factory AddLocalLibraryRootAndScanResult.addedButScanNotAdmitted({
    required LibraryRoot root,
    required LibraryScanChildAdmissionIssue issue,
  }) = AddLocalLibraryRootAndScanResultAddedButScanNotAdmitted;

  const factory AddLocalLibraryRootAndScanResult.alreadyConfigured(
    LibraryRootId existingLibraryRootId,
  ) = AddLocalLibraryRootAndScanResultAlreadyConfigured;

  const factory AddLocalLibraryRootAndScanResult.overlapsExisting({
    required LibraryRootId existingLibraryRootId,
    required RootRelationship relationship,
  }) = AddLocalLibraryRootAndScanResultOverlapsExisting;
}

/// One authoritative scan-run admission reference for a historical root.
final class LibraryRootScanAdmission {
  const LibraryRootScanAdmission({
    required this.jobRunId,
    required this.scanRunId,
  });

  final JobRunId jobRunId;
  final ScanRunId scanRunId;

  @override
  bool operator ==(Object other) =>
      other is LibraryRootScanAdmission &&
      other.jobRunId == jobRunId &&
      other.scanRunId == scanRunId;

  @override
  int get hashCode => Object.hash(jobRunId, scanRunId);
}

/// Typed outcome of one root-removal operation for the active slice.
@freezed
sealed class RemoveLibraryRootResult with _$RemoveLibraryRootResult {
  const factory RemoveLibraryRootResult.removed() =
      RemoveLibraryRootResultRemoved;

  const factory RemoveLibraryRootResult.rootHasActiveScan({
    required LibraryRootId libraryRootId,
    required JobRunId jobRunId,
    required ScanRunId scanRunId,
    required int owningJobRootCount,
  }) = RemoveLibraryRootResultRootHasActiveScan;
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

  const factory RuntimeEventPayload.libraryRootsChanged() =
      RuntimeEventPayloadLibraryRootsChanged;

  const factory RuntimeEventPayload.libraryRootChanged({
    required LibraryRootId libraryRootId,
  }) = RuntimeEventPayloadLibraryRootChanged;

  const factory RuntimeEventPayload.jobStateChanged({
    required JobRunId jobRunId,
  }) = RuntimeEventPayloadJobStateChanged;

  const factory RuntimeEventPayload.jobProgress({
    required JobRunId jobRunId,
    required String phase,
    int? completedUnits,
    int? totalUnits,
    String? statusKey,
  }) = RuntimeEventPayloadJobProgress;

  const factory RuntimeEventPayload.sourceEntriesChanged({
    required LibraryRootId libraryRootId,
    required SourceEntriesChangeScope scope,
  }) = RuntimeEventPayloadSourceEntriesChanged;
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
