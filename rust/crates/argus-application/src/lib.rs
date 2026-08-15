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
    ActiveScanOwnership, AdmittedScan, ApplicationEventSink, BackgroundOperationHandler,
    CancelJobResult, JobControlAvailability, JobDetail, JobProgress, JobProgressError,
    JobProgressReporter, JobRunProjection, JobRunRepository, JobRunState, JobRunStateParseError,
    JobSummary, JobSummaryPage, JobsQueries, JobsService, LibraryScanAdmissionExclusion,
    LibraryScanAdmissionResult, LibraryScanExecutionPlan, LibraryScanJobDetail,
    LibraryScanRootSummary, LibraryScanTarget, LibraryScanTargetExclusionReason,
    LibraryScanTargetKind, LibraryScanTargetRepository, ListJobsQuery, ListJobsScope,
    NativeIdentityMatch, NewJobRun, NewLibraryScanTarget, NewScanRun, NewSourceEntry,
    OPERATION_TYPE_LIBRARY_SCAN, OperationCompletion, OperationDetail, OperationHandle,
    ScanProgressFacts, ScanRunProjection, ScanRunRepository, ScanRunStatus,
    ScanRunStatusParseError, SourceEntryRecord, SourceEntryRepository, StartLibraryScanResult,
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
    AddLocalLibraryRootCommand, AddLocalLibraryRootHandler, AddLocalLibraryRootResult,
    DiscoveryPath, DiscoverySegment, EnumerationOutcome, EnumerationResult, GetLibraryRootHandler,
    GetLibraryRootQuery, GetSourceEntryHandler, GetSourceEntryQuery, LibraryRootActiveScanSummary,
    LibraryRootAvailability, LibraryRootChanged, LibraryRootConfiguration,
    LibraryRootLastScanStatus, LibraryRootLastScanSummary, LibraryRootPage, LibraryRootProjection,
    LibraryRootQueries, LibraryRootRepository, LibraryRootScanConfiguration, LibraryRootsChanged,
    LibraryRootsSubscriber, LibraryScanOperationHandler, LibraryService, LibrarySourceAccess,
    LibrarySourceRepository, ListLibraryRootsHandler, ListLibraryRootsQuery,
    ListSourceEntryChildrenHandler, ListSourceEntryChildrenQuery, LocalFilesystemProvider,
    LocalFilesystemRootSelection, NewLibraryRoot, ObservedEntryKind, ProviderError,
    RelativeSourceLocator, RemoveLibraryRootCommand, RemoveLibraryRootHandler,
    RemoveLibraryRootResult, ResolvedRoot, RootLocator, RootRelationship, SourceAccessError,
    SourceEntryChildrenPage, SourceEntryClassification, SourceEntryCursor, SourceEntryCursorError,
    SourceEntryDetailProjection, SourceEntryKind, SourceEntryProjection, SourceEntryQueries,
    SourceLocatorKey, SourceObservation, SourceProviderType, SourceProviderTypeError,
    StartLibraryScanCommand, StartLibraryScanHandler, ValidatedLocalRoot,
};
pub use unit_of_work::{UnitOfWork, UnitOfWorkFactory};
