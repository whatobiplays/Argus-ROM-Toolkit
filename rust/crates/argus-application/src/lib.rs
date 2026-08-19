//! Technology-neutral contracts for Argus application use cases and ports.
//!
//! This crate defines the stable vocabulary shared by runtime composition,
//! application handlers, and infrastructure adapters. It intentionally does not
//! expose persistence-driver, bridge, filesystem, or asynchronous-runtime types.

mod diagnostics;
mod errors;
mod events;
mod jobs;
mod observability;
mod settings;
mod sources;
mod unit_of_work;

pub use argus_domain::{
    AppearanceSettings, JobRunId, JobRunIdError, LibraryRootId, LibraryRootIdError,
    LibrarySourceId, LibrarySourceIdError, ScanRunId, ScanRunIdError, SourceEntryId,
    SourceEntryIdError, ThemeMode, ThemeModeParseError,
};
pub use diagnostics::{
    DiagnosticArtifact, DiagnosticContributor, DiagnosticContributorError, HealthSnapshot,
    SubsystemHealthState,
};
pub use errors::{
    ApplicationError, ApplicationErrorError, ApplicationPortError, ApplicationSeverity,
    ErrorCategory, ErrorCode, ErrorPolicy, MessageKey, PersistenceError, Recoverability,
    RetryPolicy,
};
pub use events::{
    AppearanceSettingsChanged, AppearanceSettingsSubscriber, ApplicationEvent, EventRecorder,
    EventRecordingError, EventSubscriberError, JobProgressChanged, JobStateChanged, JobsSubscriber,
    SourceEntriesChangeScope, SourceEntriesChanged, SourceEntriesSubscriber,
};
pub use jobs::{
    ActiveScanOwnership, AdmittedLibraryScanJob, AdmittedScan, ApplicationEventSink,
    BackgroundOperationHandler, BackgroundOperationStopReason, CancelJobResult,
    JobControlAvailability, JobDetail, JobProgress, JobProgressError, JobProgressReporter,
    JobRunProjection, JobRunRepository, JobRunState, JobRunStateParseError, JobSummary,
    JobSummaryPage, JobsQueries, JobsService, LibraryScanAdmissionContext,
    LibraryScanAdmissionContextRepository, LibraryScanAdmissionExclusion,
    LibraryScanAdmissionResult, LibraryScanAllAdmissionResult, LibraryScanAllRequestIdentity,
    LibraryScanAllRequestIdentityError, LibraryScanAllRequestLookup, LibraryScanChildCompletion,
    LibraryScanExecutionPlan, LibraryScanInvocationKind, LibraryScanInvocationKindParseError,
    LibraryScanJobDetail, LibraryScanRecoveryHandler, LibraryScanRetryEvaluation,
    LibraryScanRootSummary, LibraryScanTarget, LibraryScanTargetEligibility,
    LibraryScanTargetExclusionReason, LibraryScanTargetKind, LibraryScanTargetRepository,
    ListJobsQuery, ListJobsScope, NativeIdentityMatch, NewJobRun, NewLibraryScanAdmissionContext,
    NewLibraryScanTarget, NewScanRun, NewSourceEntry, OPERATION_TYPE_LIBRARY_SCAN,
    OperationCompletion, OperationDetail, OperationHandle, RetryJobAdmissionResult,
    RetryJobCommand, RetryJobHandler, RetryJobResult, RetryNotAdmittedReason,
    ScanAdmissionReference, ScanProgressFacts, ScanRunProjection, ScanRunRepository, ScanRunStatus,
    ScanRunStatusParseError, SourceEntryRecord, SourceEntryRepository, StaleLibraryScanJob,
    StaleLibraryScanQueries, StaleLibraryScanRun, StartLibraryScanAllResult,
    StartLibraryScanResult, aggregate_library_scan_state, evaluate_retry_eligibility,
    evaluate_retry_eligibility_with_trace,
};
pub use observability::{
    ArchitectureClass, DiagnosticStage, EventName, FailureRole, LogEvent, LogLevel,
    MigrationOutcome, NameError, ObservabilitySink, ObservabilitySinkError, OperationContext,
    OperationName, PathClass, PersistedSettingsReason, PlatformClass, SafeContext,
    SafeContextError, SafeContextField, SafeContextValue, SettingsDomain, StartupCollector,
    SubsystemName, TechnicalClass, TraceEvent, TraceEventPhase, TraceId, TraceIdError, Version,
};
pub use settings::{
    AppearanceSettingsQueries, AppearanceSettingsRepository, GetAppearanceSettingsHandler,
    GetAppearanceSettingsQuery, SettingsService, UpdateAppearanceSettingsCommand,
    UpdateAppearanceSettingsHandler,
};
pub use sources::{
    AddLocalLibraryRootAndScanCommand, AddLocalLibraryRootAndScanHandler,
    AddLocalLibraryRootAndScanResult, AddLocalLibraryRootCommand, AddLocalLibraryRootHandler,
    AddLocalLibraryRootResult, DiscoveryPath, DiscoverySegment, EnumerationOutcome,
    EnumerationResult, GetLibraryRootHandler, GetLibraryRootQuery, GetSourceEntryHandler,
    GetSourceEntryQuery, LibraryRootActiveScanSummary, LibraryRootAvailability, LibraryRootChanged,
    LibraryRootConfiguration, LibraryRootLastScanStatus, LibraryRootLastScanSummary,
    LibraryRootPage, LibraryRootProjection, LibraryRootQueries, LibraryRootRepository,
    LibraryRootScanConfiguration, LibraryRootsChanged, LibraryRootsSubscriber,
    LibraryScanChildAdmission, LibraryScanChildAdmissionIssue, LibraryScanOperationHandler,
    LibraryService, LibrarySourceAccess, LibrarySourceRepository, ListLibraryRootsHandler,
    ListLibraryRootsQuery, ListSourceEntryChildrenHandler, ListSourceEntryChildrenQuery,
    LocalFilesystemBrowseBreadcrumb, LocalFilesystemBrowseCursor, LocalFilesystemBrowseDirectory,
    LocalFilesystemBrowseLocation, LocalFilesystemBrowsePage, LocalFilesystemBrowseProvider,
    LocalFilesystemBrowseRoot, LocalFilesystemProvider, LocalFilesystemRootSelection,
    MAX_LOCAL_FILESYSTEM_BROWSE_PAGE_SIZE, MAX_MOUNTED_LOCAL_FILESYSTEM_VOLUMES,
    MountedLocalFilesystemVolume, NewLibraryRoot, ObservedEntryKind, ProviderError,
    RelativeSourceLocator, RemoveLibraryRootCommand, RemoveLibraryRootHandler,
    RemoveLibraryRootResult, ResolvedRoot, RootLocator, RootRelationship, SourceAccessError,
    SourceEntryChildrenPage, SourceEntryClassification, SourceEntryCursor, SourceEntryCursorError,
    SourceEntryDetailProjection, SourceEntryKind, SourceEntryProjection, SourceEntryQueries,
    SourceLocatorKey, SourceObservation, SourceProviderType, SourceProviderTypeError,
    StartLibraryScanAllCommand, StartLibraryScanAllHandler, StartLibraryScanCommand,
    StartLibraryScanHandler, SyncLocalFilesystemMountedVolumesCommand, ValidatedLocalRoot,
};
pub use unit_of_work::{UnitOfWork, UnitOfWorkFactory};
