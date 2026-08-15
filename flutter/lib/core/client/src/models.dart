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
    required int entriesCommitted,
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

/// Typed outcome of one cancel request.
enum CancelJobResult { cancellationRequested, noLongerCancellable }

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
  });

  final String scanRunId;
  final String jobRunId;

  @override
  bool operator ==(Object other) =>
      other is LibraryRootActiveScan &&
      other.scanRunId == scanRunId &&
      other.jobRunId == jobRunId;

  @override
  int get hashCode => Object.hash(scanRunId, jobRunId);
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

/// Untrusted typed local-folder selection from the native picker seam.
final class LocalFilesystemRootSelection {
  const LocalFilesystemRootSelection(this.selectedFolderPath);

  final String selectedFolderPath;
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
