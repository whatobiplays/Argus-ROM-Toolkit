//! Technology-neutral contracts for Argus application use cases and ports.
//!
//! This crate defines the stable vocabulary shared by runtime composition,
//! application handlers, and infrastructure adapters. It intentionally does not
//! expose persistence-driver, bridge, filesystem, or asynchronous-runtime types.

mod artwork;
mod content;
mod diagnostics;
mod errors;
mod events;
mod grouping;
mod hydration;
mod jobs;
mod library;
mod logical;
mod metadata;
mod observability;
mod settings;
mod sources;
mod unit_of_work;

pub use argus_domain::{
    AppearanceSettings, ArtworkAssetId, ArtworkAssetIdError, AvailabilityState, ContentType, Game,
    GameContent, GameContentId, GameContentIdError, GameContentPresence, GameContentSource, GameId,
    GameIdError, GameLifecycle, GameMembership, GameRedirect, GroupingBasis, HydrationState,
    IdentificationState, InvalidContentType, InvalidPlatformId, JobRunId, JobRunIdError,
    LibraryRootId, LibraryRootIdError, LibrarySourceId, LibrarySourceIdError,
    MembershipRelationship, PlatformId, ScanRunId, ScanRunIdError, SourceEntryId,
    SourceEntryIdError, ThemeMode, ThemeModeParseError,
};
pub use artwork::{
    ArtworkAsset, ArtworkCandidate, ArtworkReference, ArtworkRepository, ArtworkResolutionPolicy,
    ArtworkSource, ArtworkType, ResolvedArtwork, ResolvedArtworkSet, resolve_artwork,
};
pub use content::{
    IdentityDigest, IdentitySchemeCatalog, IdentitySchemeDescriptor, TransformationDescriptor,
    TransformationRegistry,
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
pub use grouping::{
    GroupingValidationError, RedirectGraph, validate_continuity_anchor, validate_memberships,
};
pub use hydration::{
    ArtworkAssetStore, ArtworkAssetStoreError, EnrichmentProviderSession, HydrationCoordinator,
    HydrationIssue, HydrationIssueKind, HydrationMappingCandidate, HydrationPlanner,
    HydrationProviderError, HydrationReport, HydrationTarget, HydrationTargetValidationError,
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
pub use library::{
    ContentIdentitySummary, ContentProvenanceSummary, GameContentSummary, GameDetail,
    GameLibraryPage, GameLibraryRow, GameListCursor, GameMembershipSummary, GetGameResult,
    LibraryScope, LibrarySort, ListGamesQuery, ListGamesQueryBuilder, LogicalLibraryQueries,
    QueryValidationError,
};
pub use logical::{
    ContentIdentity, ConvergenceOutcome, IdentificationService, IdentityConvergenceStore,
    LogicalContentRepository, LogicalContentUnitOfWork, SourceVersionEvidence,
    ValidatedContentDerivation,
};
pub use metadata::{
    CredentialMutationError, CredentialValidationError, CredentialValidator, ExactMatchEvidence,
    ExternalIdentityMapping, MappingState, MatchBasis, MetadataCandidate, MetadataFieldProvenance,
    MetadataProviderReadiness, MetadataProviderReadinessProjection, MetadataProviderRegistry,
    MetadataProviderService, MetadataProviderSettings, MetadataRepository,
    MetadataResolutionPolicy, MetadataSettings, ProviderCapability, ProviderCapabilityReadiness,
    ProviderDescriptor, ProviderId, ProviderMetadata, ProviderReadinessState, ResolvedMetadata,
    SecureCredentialStore, accept_exact_mapping, accept_exact_mappings, resolve_metadata,
    resolve_provider_metadata,
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
pub use unit_of_work::{EnrichmentUnitOfWork, UnitOfWork, UnitOfWorkFactory};
