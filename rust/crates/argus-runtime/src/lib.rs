//! Bridge-neutral composition for the Phase 000 runtime and persistence kernel.
//!
//! The runtime boundary does not export infrastructure SQLite connection or
//! value types:
//!
//! ```compile_fail
//! use argus_runtime::{SqliteConnection, SqliteValue};
//! ```

pub mod diagnostics;
mod events;
mod notification_sink;
pub mod operations;
pub mod recovery;
mod recovery_context;
mod runtime;
pub mod startup;

use std::fmt;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use argus_application::{
    AddLocalLibraryRootCommand, AddLocalLibraryRootResult, AppearanceSettings,
    AppearanceSettingsRepository, ApplicationError, ApplicationPortError, ArchitectureClass,
    ArtworkRepository, ArtworkResolutionPolicy, CancelJobResult, ContentIdentity,
    ContentProvenanceRole, ContentType, ConvergenceOutcome, CredentialMutationError,
    DerivedScopeIdentity, DiagnosticStage, EnrichmentProviderSession, EnrichmentUnitOfWork,
    ErrorCode, EventName, FailureRole, GameContentId, GameId, GameLibraryPage,
    GetAppearanceSettingsQuery, GetGameResult, GetLibraryRootQuery, GetSourceEntryQuery,
    HydrationReport, HydrationTarget, IdentificationService, IdentityConvergenceStore,
    IdentitySchemeCatalog, JobDetail, JobRunId, JobRunRepository, JobRunState, JobSummaryPage,
    JobsService, LibraryFacetQuery, LibraryFacets, LibraryOnboardingState,
    LibraryProviderSetupDecision, LibraryRefreshAdmissionResult, LibraryRefreshCoordinator,
    LibraryRootId, LibraryRootPage, LibraryRootProjection, LibraryRootRepository,
    LibraryScanAdmissionResult, LibraryScanAllAdmissionResult, LibraryScanAllRequestIdentity,
    LibraryScanAllRequestLookup, LibraryScope, LibraryService, LibrarySort, LibrarySourceAccess,
    LibrarySourceRepository, ListGamesQuery, ListJobsQuery, ListLibraryRootsQuery,
    ListSourceEntryChildrenQuery, LocalFilesystemBrowseCursor, LocalFilesystemBrowseLocation,
    LocalFilesystemBrowsePage, LocalFilesystemBrowseRoot, LocalFilesystemRootSelection, LogEvent,
    LogLevel, LogicalContentRepository, LogicalContentUnitOfWork, LogicalLibraryQueries,
    M3uGroupingMember, MetadataProviderReadiness, MetadataProviderReadinessProjection,
    MetadataProviderRegistry, MetadataProviderService, MetadataProviderSettings,
    MetadataRepository, MetadataResolutionPolicy, MetadataSettings, MigrationOutcome, NewJobRun,
    NewLibraryScanAdmissionContext, ObservabilitySink, OperationContext, OperationHandle,
    OperationName, PathClass, PersistenceError, PlatformClass, PlatformId, PrivacyConsent,
    ProvenanceMember, ProviderError, ProviderId, ProviderReadinessState, RefreshLibraryCommand,
    RefreshMode, RemoveLibraryRootCommand, RemoveLibraryRootResult, SafeContext, SafeContextField,
    SafeContextValue, SettingsService, SourceEntryChildrenPage, SourceEntryDetailProjection,
    SourceEntryId, SourceEntryKind, SourceEntryRecord, SourceEntryRepository,
    SourceVersionEvidence, StartLibraryScanAllCommand, StartLibraryScanAllResult,
    StartLibraryScanCommand, StartupCollector, SubsystemName,
    SyncLocalFilesystemMountedVolumesCommand, TechnicalClass, TraceEvent, TraceEventPhase, TraceId,
    TransformationFailure, TransformationRegistry, UnitOfWork, UnitOfWorkFactory,
    UpdateAppearanceSettingsCommand, ValidatedContentDerivation, ValidatedM3uGrouping, Version,
    evaluate_archive_eligibility, map_transformation_failure, reconcile_derived_scope,
};
use argus_infrastructure::artwork_store::ArtworkObjectStore;
use argus_infrastructure::content::{
    ContentReader, ContentRecognitionError, ContentSourceResolver, OpticalError,
    OpticalRecognition, ParsingSession,
};
use argus_infrastructure::credentials::KeyringSecureCredentialStore;
use argus_infrastructure::local_filesystem::{
    LocalFilesystemProvider as InfraLocalFilesystemProvider, LocalFilesystemSourceAccess,
};
use argus_infrastructure::providers::{
    ProductionProviderSessionFactory, SteamGridDbCredentialValidator, UreqTransport,
};
use argus_infrastructure::sqlite::{
    MigrationOutcome as InfrastructureMigrationOutcome, MigrationSummary,
    SqliteAppearanceSettingsQueries, SqliteAppearanceSettingsRepository, SqliteArtworkRepository,
    SqliteDatabaseExecutor, SqliteExecutorError, SqliteJobRunRepository, SqliteJobsQueries,
    SqliteLibraryRootQueries, SqliteLibraryRootRepository,
    SqliteLibraryScanAdmissionContextRepository, SqliteLibraryScanTargetRepository,
    SqliteLibrarySourceRepository, SqliteLogicalContentRepository, SqliteMetadataRepository,
    SqliteScanRunRepository, SqliteSourceEntryQueries, SqliteSourceEntryRepository,
    SqliteUnitOfWork,
};

pub mod background;
pub use events::EventBus;
use events::{
    PendingEventCollector, PublicationDiagnostics, finalize_appearance_update,
    finalize_library_roots_update,
};
pub use notification_sink::{
    InProcessNotificationSink, NotificationSinkError, RuntimeEventPublisher,
    RuntimeNotificationSink,
};
pub use recovery::RecoveryCoordinator;
pub(crate) use recovery_context::{
    AppearanceResetCapability, FailedRuntimeRecoveryContext, FailedStartupDiagnostics,
};
pub(crate) use runtime::RuntimeEventSubscriber;
pub use runtime::*;
pub(crate) use startup::StartupPhaseObserver;
pub use startup::{Clock, StartupCoordinator, StartupResult, SystemClock};

const STEAMGRIDDB_API_BASE_URL: &str = "https://www.steamgriddb.com/api/v2";

type RuntimeCredentialService = MetadataProviderService<
    KeyringSecureCredentialStore,
    SteamGridDbCredentialValidator<UreqTransport>,
>;

type EnrichmentSessionFactory =
    dyn Fn() -> Vec<Box<dyn EnrichmentProviderSession>> + Send + Sync + 'static;

fn production_enrichment_session_factory() -> Arc<EnrichmentSessionFactory> {
    Arc::new(|| ProductionProviderSessionFactory::new().create_sessions())
}

fn sessions_require_credentials(
    registry: &MetadataProviderRegistry,
    sessions: &[Box<dyn EnrichmentProviderSession>],
) -> bool {
    sessions.iter().any(|session| {
        registry
            .descriptor(session.provider_id())
            .requires_credential()
    })
}

#[cfg(feature = "test-support")]
// Keep this registry outside the public options struct so existing embedding
// callers that construct the two public fields directly remain source-compatible.
static TEST_ENRICHMENT_SESSION_FACTORIES: std::sync::OnceLock<
    Mutex<std::collections::HashMap<PathBuf, Arc<EnrichmentSessionFactory>>>,
> = std::sync::OnceLock::new();

/// Platform naming policy used by the private path-resolution seam.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum Platform {
    Windows,
    MacOs,
    Unix,
    Android,
}

impl Platform {
    fn current() -> Self {
        if cfg!(target_os = "android") {
            Self::Android
        } else if cfg!(target_os = "windows") {
            Self::Windows
        } else if cfg!(target_os = "macos") {
            Self::MacOs
        } else {
            Self::Unix
        }
    }
}

/// Path-resolution failures that never expose the candidate path publicly.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum DataDirectoryError {
    MissingHome,
    InvalidOverride,
    InvalidRoot,
    Unavailable,
}

impl fmt::Display for DataDirectoryError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(match self {
            Self::MissingHome => "application home directory is unavailable",
            Self::InvalidOverride => "application data directory override is invalid",
            Self::InvalidRoot => "application data directory root is invalid",
            Self::Unavailable => "application data directory is unavailable",
        })
    }
}

impl std::error::Error for DataDirectoryError {}

/// Resolves the name-based application data directory.
pub(crate) fn resolve_data_directory(
    platform: Platform,
    home: Option<&Path>,
    local_app_data: Option<&Path>,
    xdg_data_home: Option<&Path>,
    override_directory: Option<PathBuf>,
    standard_data_directory: Option<PathBuf>,
) -> Result<PathBuf, DataDirectoryError> {
    if let Some(directory) = override_directory {
        if !directory.is_absolute() || has_dot_component(&directory) {
            return Err(DataDirectoryError::InvalidOverride);
        }
        validate_absolute_root(&directory, DataDirectoryError::InvalidOverride)?;
        return Ok(directory);
    }
    if let Some(directory) = standard_data_directory {
        validate_absolute_root(&directory, DataDirectoryError::InvalidRoot)?;
        return Ok(directory);
    }
    match platform {
        Platform::Windows => local_app_data
            .map(|directory| {
                validate_absolute_root(directory, DataDirectoryError::InvalidRoot)?;
                Ok(directory.join("Argus ROM Toolkit"))
            })
            .unwrap_or(Err(DataDirectoryError::Unavailable)),
        Platform::MacOs => home
            .map(|directory| {
                validate_absolute_root(directory, DataDirectoryError::InvalidRoot)?;
                Ok(directory.join("Library/Application Support/Argus ROM Toolkit"))
            })
            .unwrap_or(Err(DataDirectoryError::MissingHome)),
        Platform::Unix => {
            if let Some(directory) = xdg_data_home {
                validate_absolute_root(directory, DataDirectoryError::InvalidRoot)?;
                Ok(directory.join("argus-rom-toolkit"))
            } else {
                home.map(|directory| {
                    validate_absolute_root(directory, DataDirectoryError::InvalidRoot)?;
                    Ok(directory.join(".local/share").join("argus-rom-toolkit"))
                })
                .unwrap_or(Err(DataDirectoryError::MissingHome))
            }
        }
        Platform::Android => Err(DataDirectoryError::Unavailable),
    }
}

pub(crate) fn validate_absolute_root(
    directory: &Path,
    error: DataDirectoryError,
) -> Result<(), DataDirectoryError> {
    if !directory.is_absolute() || has_dot_component(directory) {
        return Err(error);
    }
    Ok(())
}

fn has_dot_component(directory: &Path) -> bool {
    directory
        .as_os_str()
        .to_string_lossy()
        .split(['/', '\\'])
        .any(|component| matches!(component, "." | ".."))
}

/// Options for one bridge-neutral kernel bootstrap.
#[derive(Clone, Debug, Default)]
pub struct KernelBootstrapOptions {
    /// Optional absolute root used by tests or an embedding host.
    pub data_directory_override: Option<PathBuf>,
    /// Optional host-supplied standard application-data root (Android).
    pub standard_data_directory: Option<PathBuf>,
}

impl KernelBootstrapOptions {
    /// Creates options with an explicit test/embedding data root.
    pub fn with_data_directory(directory: impl Into<PathBuf>) -> Self {
        Self {
            data_directory_override: Some(directory.into()),
            standard_data_directory: None,
        }
    }

    /// Creates options with a host-supplied standard application-data root.
    pub fn with_standard_data_directory(directory: impl Into<PathBuf>) -> Self {
        Self {
            data_directory_override: None,
            standard_data_directory: Some(directory.into()),
        }
    }

    /// Installs a deterministic provider-session factory for integration tests.
    #[cfg(feature = "test-support")]
    #[doc(hidden)]
    pub fn with_provider_session_factory_for_tests<F>(self, factory: F) -> Self
    where
        F: Fn() -> Vec<Box<dyn EnrichmentProviderSession>> + Send + Sync + 'static,
    {
        if let Some(directory) = &self.data_directory_override {
            TEST_ENRICHMENT_SESSION_FACTORIES
                .get_or_init(|| Mutex::new(std::collections::HashMap::new()))
                .lock()
                .expect("test provider-session registry lock")
                .insert(directory.clone(), Arc::new(factory));
        }
        self
    }

    pub(crate) fn enrichment_session_factory(&self) -> Arc<EnrichmentSessionFactory> {
        #[cfg(feature = "test-support")]
        if let Some(directory) = &self.data_directory_override
            && let Some(factory) = TEST_ENRICHMENT_SESSION_FACTORIES
                .get_or_init(|| Mutex::new(std::collections::HashMap::new()))
                .lock()
                .ok()
                .and_then(|factories| factories.get(directory).cloned())
        {
            return factory;
        }
        production_enrichment_session_factory()
    }
}

pub(crate) fn env_path(name: &str) -> Option<PathBuf> {
    std::env::var_os(name)
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
}

/// Startup phases attributed by the kernel bootstrap.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum KernelBootstrapStage {
    Environment,
    Observability,
    Persistence,
}

impl KernelBootstrapStage {
    fn diagnostic(self) -> DiagnosticStage {
        match self {
            Self::Environment => DiagnosticStage::Environment,
            Self::Observability => DiagnosticStage::Observability,
            Self::Persistence => DiagnosticStage::Persistence,
        }
    }

    fn as_str(self) -> &'static str {
        match self {
            Self::Environment => "environment",
            Self::Observability => "observability",
            Self::Persistence => "persistence",
        }
    }
}

/// Stable shutdown failure for the bridge-neutral kernel boundary.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum KernelShutdownError {
    Internal,
}

impl fmt::Display for KernelShutdownError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("kernel shutdown failed")
    }
}

impl std::error::Error for KernelShutdownError {}

/// Bridge-neutral migration state established by the kernel bootstrap.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct KernelMigrationSummary {
    /// Number of migrations applied during this bootstrap.
    pub applied_count: u32,
    /// Highest migration version validated after startup.
    pub current_version: u32,
    /// Whether startup applied migrations or found the database current.
    pub outcome: KernelMigrationOutcome,
}

/// Stable migration outcome exposed by the runtime bootstrap boundary.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum KernelMigrationOutcome {
    Applied,
    AlreadyCurrent,
}

impl From<&MigrationSummary> for KernelMigrationSummary {
    fn from(summary: &MigrationSummary) -> Self {
        Self {
            applied_count: summary.applied_count,
            current_version: summary.current_version,
            outcome: match summary.outcome {
                InfrastructureMigrationOutcome::Applied => KernelMigrationOutcome::Applied,
                InfrastructureMigrationOutcome::AlreadyCurrent => {
                    KernelMigrationOutcome::AlreadyCurrent
                }
            },
        }
    }
}

/// A sanitized, bridge-neutral failure returned by kernel startup.
#[derive(Clone, Debug)]
pub struct KernelBootstrapFailure {
    trace_id: TraceId,
    stage: KernelBootstrapStage,
    error: Box<ApplicationError>,
    collector: Box<StartupCollector>,
}

impl KernelBootstrapFailure {
    /// Returns the startup operation trace identity.
    pub fn trace_id(&self) -> TraceId {
        self.trace_id
    }

    /// Returns the architectural stage that failed.
    pub fn stage(&self) -> KernelBootstrapStage {
        self.stage
    }

    /// Returns the stable published application failure.
    pub fn error(&self) -> &ApplicationError {
        &self.error
    }

    /// Returns startup trace records captured before and including failure.
    pub fn events(&self) -> &[TraceEvent] {
        self.collector.traces()
    }

    /// Returns independently recorded startup logs in emission order.
    pub fn logs(&self) -> &[LogEvent] {
        self.collector.logs()
    }
}

impl fmt::Display for KernelBootstrapFailure {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            formatter,
            "kernel bootstrap failed during {} ({})",
            self.stage.as_str(),
            self.error.code.as_str()
        )
    }
}

impl std::error::Error for KernelBootstrapFailure {}

/// Successful bridge-neutral persistence kernel state.
pub struct KernelBootstrap {
    trace_id: TraceId,
    path_class: PathClass,
    migration_summary: KernelMigrationSummary,
    executor: Option<SqliteDatabaseExecutor>,
    settings_service: SettingsService<SqliteAppearanceSettingsQueries, SqliteDatabaseExecutor>,
    library_service: LibraryService<
        SqliteLibraryRootQueries,
        SqliteSourceEntryQueries,
        SqliteDatabaseExecutor,
        InfraLocalFilesystemProvider,
    >,
    jobs_service: JobsService<SqliteJobsQueries, KernelUnitOfWorkFactory>,
    unit_of_work: KernelUnitOfWorkFactory,
    metadata_provider_registry: MetadataProviderRegistry,
    provider_session_factory: Arc<EnrichmentSessionFactory>,
    credential_service: Arc<Mutex<RuntimeCredentialService>>,
    artwork_store: Arc<ArtworkObjectStore>,
    event_bus: Arc<EventBus>,
    publication_diagnostics: Mutex<PublicationDiagnostics>,
    transformation_registry: TransformationRegistry,
    transformation_staging_root: PathBuf,
    collector: StartupCollector,
    #[cfg(test)]
    fail_shutdown: bool,
}

/// Bounded artwork bytes returned by the runtime without storage paths or
/// provider locators.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ArtworkAssetBytes {
    asset_id: argus_domain::ArtworkAssetId,
    bytes: Vec<u8>,
    mime_type: String,
    width: u32,
    height: u32,
}

impl ArtworkAssetBytes {
    /// Returns the immutable content-addressed asset identity.
    pub const fn asset_id(&self) -> argus_domain::ArtworkAssetId {
        self.asset_id
    }

    /// Returns the original validated bytes.
    pub fn bytes(&self) -> &[u8] {
        &self.bytes
    }

    /// Returns the validated media type.
    pub fn mime_type(&self) -> &str {
        &self.mime_type
    }

    /// Returns the decoded width.
    pub const fn width(&self) -> u32 {
        self.width
    }

    /// Returns the decoded height.
    pub const fn height(&self) -> u32 {
        self.height
    }
}

/// Technology-neutral transaction scope exposed by the runtime boundary.
///
/// The concrete SQLite transaction remains owned by infrastructure. This
/// wrapper intentionally exposes only the consuming application `UnitOfWork`
/// contract so callers cannot depend on SQLite statements or value types.
pub struct KernelUnitOfWork<'scope> {
    inner: SqliteUnitOfWork<'scope>,
}

/// Cloneable technology-neutral transaction factory over the shared SQLite
/// executor. Used by the kernel, background workers, and operation handlers;
/// the SQLite worker remains the single database authority.
#[derive(Clone)]
pub struct KernelUnitOfWorkFactory {
    executor: SqliteDatabaseExecutor,
}

impl KernelUnitOfWorkFactory {
    /// Creates a factory over the existing shared executor.
    pub const fn new(executor: SqliteDatabaseExecutor) -> Self {
        Self { executor }
    }
}

impl UnitOfWorkFactory for KernelUnitOfWorkFactory {
    type Scope<'scope>
        = KernelUnitOfWork<'scope>
    where
        Self: 'scope;

    fn execute<T, F>(
        &self,
        context: &OperationContext,
        operation: F,
    ) -> Result<T, ApplicationPortError>
    where
        T: Send + 'static,
        F: for<'scope> FnOnce(Self::Scope<'scope>) -> Result<T, ApplicationPortError>
            + Send
            + 'static,
    {
        self.executor.execute(context, move |scope| {
            operation(KernelUnitOfWork::new(scope))
        })
    }
}

impl<'scope> KernelUnitOfWork<'scope> {
    pub(crate) fn new(inner: SqliteUnitOfWork<'scope>) -> Self {
        Self { inner }
    }

    /// Atomically restores the canonical System appearance row.
    pub(crate) fn reset_appearance_settings(&mut self) -> Result<(), ApplicationPortError> {
        self.inner
            .reset_appearance_theme_mode()
            .map_err(ApplicationPortError::Persistence)
    }
}

/// Technology-neutral transaction-bound appearance repository wrapper.
pub struct KernelAppearanceSettingsRepository<'scope, 'connection> {
    inner: SqliteAppearanceSettingsRepository<'scope, 'connection>,
}

/// Technology-neutral transaction-scoped library-source repository wrapper.
pub struct KernelLibrarySourceRepository<'scope, 'connection> {
    inner: SqliteLibrarySourceRepository<'scope, 'connection>,
}

impl LibrarySourceRepository for KernelLibrarySourceRepository<'_, '_> {
    fn ensure_local_filesystem_source(
        &mut self,
    ) -> Result<argus_application::LibrarySourceId, PersistenceError> {
        self.inner.ensure_local_filesystem_source()
    }
}

/// Technology-neutral transaction-scoped library-root repository wrapper.
pub struct KernelLibraryRootRepository<'scope, 'connection> {
    inner: SqliteLibraryRootRepository<'scope, 'connection>,
}

/// Technology-neutral transaction-scoped generic job-run repository wrapper.
pub struct KernelJobRunRepository<'scope, 'connection> {
    inner: SqliteJobRunRepository<'scope, 'connection>,
}

impl argus_application::JobRunRepository for KernelJobRunRepository<'_, '_> {
    fn insert(
        &mut self,
        new: argus_application::NewJobRun,
    ) -> Result<argus_application::JobRunId, PersistenceError> {
        self.inner.insert(new)
    }

    fn insert_retry_link(
        &mut self,
        source_job_run_id: argus_application::JobRunId,
        successor_job_run_id: argus_application::JobRunId,
    ) -> Result<(), PersistenceError> {
        self.inner
            .insert_retry_link(source_job_run_id, successor_job_run_id)
    }

    fn request_cancellation(
        &mut self,
        job_run_id: argus_application::JobRunId,
    ) -> Result<Option<bool>, PersistenceError> {
        self.inner.request_cancellation(job_run_id)
    }

    fn set_state(
        &mut self,
        job_run_id: argus_application::JobRunId,
        state: argus_application::JobRunState,
        timestamp_ms: i64,
    ) -> Result<bool, PersistenceError> {
        self.inner.set_state(job_run_id, state, timestamp_ms)
    }

    fn set_progress(
        &mut self,
        job_run_id: argus_application::JobRunId,
        progress: &argus_application::JobProgress,
    ) -> Result<bool, PersistenceError> {
        self.inner.set_progress(job_run_id, progress)
    }

    fn set_terminal_failure(
        &mut self,
        job_run_id: argus_application::JobRunId,
        state: argus_application::JobRunState,
        terminal_error_code: Option<String>,
        terminal_safe_context: Option<String>,
        timestamp_ms: i64,
    ) -> Result<bool, PersistenceError> {
        self.inner.set_terminal_failure(
            job_run_id,
            state,
            terminal_error_code,
            terminal_safe_context,
            timestamp_ms,
        )
    }
}

/// Technology-neutral transaction-scoped scan-run repository wrapper.
pub struct KernelScanRunRepository<'scope, 'connection> {
    inner: SqliteScanRunRepository<'scope, 'connection>,
}

impl argus_application::ScanRunRepository for KernelScanRunRepository<'_, '_> {
    fn insert(
        &mut self,
        new: argus_application::NewScanRun,
    ) -> Result<argus_application::ScanRunId, PersistenceError> {
        self.inner.insert(new)
    }

    fn set_status(
        &mut self,
        scan_run_id: argus_application::ScanRunId,
        status: argus_application::ScanRunStatus,
        completed_at_ms: Option<i64>,
        failure_reason: Option<String>,
    ) -> Result<bool, PersistenceError> {
        self.inner
            .set_status(scan_run_id, status, completed_at_ms, failure_reason)
    }

    fn set_progress_facts(
        &mut self,
        scan_run_id: argus_application::ScanRunId,
        entries_observed: u64,
        entries_committed: u64,
        issue_count: u64,
    ) -> Result<bool, PersistenceError> {
        self.inner.set_progress_facts(
            scan_run_id,
            entries_observed,
            entries_committed,
            issue_count,
        )
    }

    fn find_active_ownership(
        &mut self,
        library_root_id: argus_application::LibraryRootId,
    ) -> Result<Option<argus_application::ActiveScanOwnership>, PersistenceError> {
        self.inner.find_active_ownership(library_root_id)
    }

    fn find_last_scan(
        &mut self,
        library_root_id: argus_application::LibraryRootId,
    ) -> Result<Option<argus_application::LibraryRootLastScanSummary>, PersistenceError> {
        self.inner.find_last_scan(library_root_id)
    }

    fn list_by_job(
        &mut self,
        job_run_id: argus_application::JobRunId,
    ) -> Result<Vec<argus_application::ScanRunProjection>, PersistenceError> {
        self.inner.list_by_job(job_run_id)
    }
}

/// Technology-neutral transaction-scoped source-entry repository wrapper.
pub struct KernelSourceEntryRepository<'scope, 'connection> {
    inner: SqliteSourceEntryRepository<'scope, 'connection>,
}

impl argus_application::SourceEntryRepository for KernelSourceEntryRepository<'_, '_> {
    fn upsert(
        &mut self,
        entry: argus_application::NewSourceEntry,
    ) -> Result<argus_application::SourceEntryId, PersistenceError> {
        self.inner.upsert(entry)
    }

    fn upsert_derived(
        &mut self,
        entry: argus_application::NewSourceEntry,
    ) -> Result<argus_application::SourceEntryId, PersistenceError> {
        self.inner.upsert_derived(entry)
    }

    fn library_root_id_for_entry(
        &mut self,
        source_entry_id: argus_application::SourceEntryId,
    ) -> Result<argus_application::LibraryRootId, PersistenceError> {
        self.inner.library_root_id_for_entry(source_entry_id)
    }

    fn find_by_locator_key(
        &mut self,
        library_root_id: argus_application::LibraryRootId,
        locator_key: &argus_application::SourceLocatorKey,
    ) -> Result<Option<argus_application::SourceEntryRecord>, PersistenceError> {
        self.inner.find_by_locator_key(library_root_id, locator_key)
    }

    fn find_derived_child(
        &mut self,
        parent: argus_application::SourceEntryId,
        transformation_id: &str,
        revision: u32,
        key: &argus_application::DerivedEntryKey,
    ) -> Result<Option<argus_application::SourceEntryRecord>, PersistenceError> {
        self.inner
            .find_derived_child(parent, transformation_id, revision, key)
    }

    fn find_native_identity(
        &mut self,
        library_root_id: argus_application::LibraryRootId,
        provider_native_identity: &str,
    ) -> Result<argus_application::NativeIdentityMatch, PersistenceError> {
        self.inner
            .find_native_identity(library_root_id, provider_native_identity)
    }

    fn reconcile_move(
        &mut self,
        entry: argus_application::NewSourceEntry,
        existing_source_entry_id: argus_application::SourceEntryId,
    ) -> Result<argus_application::SourceEntryId, PersistenceError> {
        self.inner.reconcile_move(entry, existing_source_entry_id)
    }

    fn list_children(
        &mut self,
        library_root_id: argus_application::LibraryRootId,
        parent_source_entry_id: Option<argus_application::SourceEntryId>,
        offset: u32,
        limit: u32,
    ) -> Result<Vec<argus_application::SourceEntryRecord>, PersistenceError> {
        self.inner
            .list_children(library_root_id, parent_source_entry_id, offset, limit)
    }

    fn delete_subtree(
        &mut self,
        library_root_id: argus_application::LibraryRootId,
        source_entry_id: argus_application::SourceEntryId,
    ) -> Result<bool, PersistenceError> {
        self.inner.delete_subtree(library_root_id, source_entry_id)
    }

    fn finalize_absent_scope(
        &mut self,
        library_root_id: argus_application::LibraryRootId,
        parent_source_entry_id: Option<argus_application::SourceEntryId>,
        observed_scan_id: argus_application::ScanRunId,
    ) -> Result<u64, PersistenceError> {
        self.inner
            .finalize_absent_scope(library_root_id, parent_source_entry_id, observed_scan_id)
    }

    fn finalize_absent_derived_scope(
        &mut self,
        parent: argus_application::SourceEntryId,
        transformation_id: &str,
        revision: u32,
        observation_run_id: argus_application::ScanRunId,
    ) -> Result<u64, PersistenceError> {
        self.inner.finalize_absent_derived_scope(
            parent,
            transformation_id,
            revision,
            observation_run_id,
        )
    }

    fn delete_for_root(
        &mut self,
        library_root_id: argus_application::LibraryRootId,
    ) -> Result<(), PersistenceError> {
        self.inner.delete_for_root(library_root_id)
    }
}

/// Technology-neutral transaction-scoped logical-content repository wrapper.
pub struct KernelLogicalContentRepository<'scope, 'connection> {
    inner: SqliteLogicalContentRepository<'scope, 'connection>,
}

impl IdentityConvergenceStore for KernelLogicalContentRepository<'_, '_> {
    fn source_version_matches(
        &mut self,
        evidence: &SourceVersionEvidence,
    ) -> Result<bool, PersistenceError> {
        self.inner.source_version_matches(evidence)
    }

    fn converge_identity(
        &mut self,
        derivation: &ValidatedContentDerivation,
    ) -> Result<argus_application::ConvergenceOutcome, PersistenceError> {
        self.inner.converge_identity(derivation)
    }
}

impl LogicalLibraryQueries for KernelLogicalContentRepository<'_, '_> {
    fn list_games(&mut self, query: &ListGamesQuery) -> Result<GameLibraryPage, PersistenceError> {
        self.inner.list_games(query)
    }

    fn get_library_facets(
        &mut self,
        query: &LibraryFacetQuery,
    ) -> Result<LibraryFacets, PersistenceError> {
        self.inner.get_library_facets(query)
    }

    fn get_game(&mut self, game_id: GameId) -> Result<GetGameResult, PersistenceError> {
        self.inner.get_game(game_id)
    }
}

impl LogicalContentRepository for KernelLogicalContentRepository<'_, '_> {
    fn finalize_source_absence(
        &mut self,
        source_entry_ids: &[SourceEntryId],
    ) -> Result<u64, PersistenceError> {
        self.inner.finalize_source_absence(source_entry_ids)
    }

    fn apply_m3u_grouping(
        &mut self,
        grouping: &argus_application::ValidatedM3uGrouping,
    ) -> Result<GameId, PersistenceError> {
        self.inner.apply_m3u_grouping(grouping)
    }

    fn reconcile_m3u_grouping_evidence(
        &mut self,
        active_playlist_source_ids: &[SourceEntryId],
    ) -> Result<(), PersistenceError> {
        self.inner
            .reconcile_m3u_grouping_evidence(active_playlist_source_ids)
    }
}

/// Technology-neutral transaction-scoped metadata repository wrapper.
pub struct KernelMetadataRepository<'scope, 'connection> {
    inner: SqliteMetadataRepository<'scope, 'connection>,
}

impl argus_application::MetadataRepository for KernelMetadataRepository<'_, '_> {
    fn save_mapping(
        &mut self,
        mapping: &argus_application::ExternalIdentityMapping,
    ) -> Result<(), PersistenceError> {
        self.inner.save_mapping(mapping)
    }

    fn save_provider_metadata(
        &mut self,
        metadata: &argus_application::ProviderMetadata,
    ) -> Result<(), PersistenceError> {
        self.inner.save_provider_metadata(metadata)
    }

    fn save_resolved_metadata(
        &mut self,
        game_id: argus_domain::GameId,
        metadata: &argus_application::ResolvedMetadata,
    ) -> Result<(), PersistenceError> {
        self.inner.save_resolved_metadata(game_id, metadata)
    }

    fn save_settings(
        &mut self,
        settings: &argus_application::MetadataSettings,
    ) -> Result<(), PersistenceError> {
        self.inner.save_settings(settings)
    }

    fn settings(&mut self) -> Result<argus_application::MetadataSettings, PersistenceError> {
        self.inner.settings()
    }

    fn settings_revision(&mut self) -> Result<u64, PersistenceError> {
        self.inner.settings_revision()
    }

    fn save_provider_settings(
        &mut self,
        settings: &argus_application::MetadataProviderSettings,
    ) -> Result<(), PersistenceError> {
        self.inner.save_provider_settings(settings)
    }

    fn provider_settings(
        &mut self,
    ) -> Result<argus_application::MetadataProviderSettings, PersistenceError> {
        self.inner.provider_settings()
    }

    fn provider_metadata_for_content(
        &mut self,
        game_content_id: argus_domain::GameContentId,
    ) -> Result<Vec<argus_application::ProviderMetadata>, PersistenceError> {
        self.inner.provider_metadata_for_content(game_content_id)
    }

    fn mappings_for_content(
        &mut self,
        game_content_id: argus_domain::GameContentId,
    ) -> Result<Vec<argus_application::ExternalIdentityMapping>, PersistenceError> {
        self.inner.mappings_for_content(game_content_id)
    }

    fn resolved_metadata_for_game(
        &mut self,
        game_id: argus_domain::GameId,
    ) -> Result<Option<argus_application::ResolvedMetadata>, PersistenceError> {
        self.inner.resolved_metadata_for_game(game_id)
    }

    fn library_onboarding_progress(
        &mut self,
    ) -> Result<argus_application::LibraryOnboardingProgress, PersistenceError> {
        self.inner.library_onboarding_progress()
    }

    fn save_library_onboarding_progress(
        &mut self,
        progress: &argus_application::LibraryOnboardingProgress,
    ) -> Result<(), PersistenceError> {
        self.inner.save_library_onboarding_progress(progress)
    }
}

/// Technology-neutral transaction-scoped artwork repository wrapper.
pub struct KernelArtworkRepository<'scope, 'connection> {
    inner: SqliteArtworkRepository<'scope, 'connection>,
}

impl argus_application::ArtworkRepository for KernelArtworkRepository<'_, '_> {
    fn save_reference(
        &mut self,
        reference: &argus_application::ArtworkReference,
    ) -> Result<(), PersistenceError> {
        self.inner.save_reference(reference)
    }

    fn save_resolved_artwork(
        &mut self,
        resolved: &argus_application::ResolvedArtwork,
    ) -> Result<(), PersistenceError> {
        self.inner.save_resolved_artwork(resolved)
    }

    fn replace_resolved_artwork_for_game(
        &mut self,
        game_id: argus_domain::GameId,
        resolved: &[argus_application::ResolvedArtwork],
    ) -> Result<(), PersistenceError> {
        self.inner
            .replace_resolved_artwork_for_game(game_id, resolved)
    }

    fn save_asset(
        &mut self,
        asset: &argus_application::ArtworkAsset,
    ) -> Result<(), PersistenceError> {
        self.inner.save_asset(asset)
    }

    fn references_for_external_game(
        &mut self,
        provider_id: argus_application::ProviderId,
        external_game_id: &str,
    ) -> Result<Vec<argus_application::ArtworkReference>, PersistenceError> {
        self.inner
            .references_for_external_game(provider_id, external_game_id)
    }

    fn resolved_artwork_for_game(
        &mut self,
        game_id: argus_domain::GameId,
    ) -> Result<Vec<argus_application::ResolvedArtwork>, PersistenceError> {
        self.inner.resolved_artwork_for_game(game_id)
    }
}

/// Technology-neutral transaction-scoped admission-target repository wrapper.
pub struct KernelLibraryScanTargetRepository<'scope, 'connection> {
    inner: SqliteLibraryScanTargetRepository<'scope, 'connection>,
}

impl argus_application::LibraryScanTargetRepository for KernelLibraryScanTargetRepository<'_, '_> {
    fn insert(
        &mut self,
        target: argus_application::NewLibraryScanTarget,
    ) -> Result<(), PersistenceError> {
        self.inner.insert(target)
    }

    fn list_by_job(
        &mut self,
        job_run_id: argus_application::JobRunId,
    ) -> Result<Vec<argus_application::LibraryScanTarget>, PersistenceError> {
        self.inner.list_by_job(job_run_id)
    }
}

/// Technology-neutral transaction-scoped LibraryScan admission-context wrapper.
pub struct KernelLibraryScanAdmissionContextRepository<'scope, 'connection> {
    inner: SqliteLibraryScanAdmissionContextRepository<'scope, 'connection>,
}

impl argus_application::LibraryScanAdmissionContextRepository
    for KernelLibraryScanAdmissionContextRepository<'_, '_>
{
    fn insert(&mut self, new: NewLibraryScanAdmissionContext) -> Result<(), PersistenceError> {
        self.inner.insert(new)
    }

    fn get_by_job(
        &mut self,
        job_run_id: argus_application::JobRunId,
    ) -> Result<Option<argus_application::LibraryScanAdmissionContext>, PersistenceError> {
        self.inner.get_by_job(job_run_id)
    }
}

impl LibraryRootRepository for KernelLibraryRootRepository<'_, '_> {
    fn insert(
        &mut self,
        root: argus_application::NewLibraryRoot,
    ) -> Result<LibraryRootId, PersistenceError> {
        self.inner.insert(root)
    }

    fn delete(&mut self, root_id: LibraryRootId) -> Result<bool, PersistenceError> {
        self.inner.delete(root_id)
    }

    fn exists(&mut self, root_id: LibraryRootId) -> Result<bool, PersistenceError> {
        self.inner.exists(root_id)
    }

    fn set_availability(
        &mut self,
        root_id: LibraryRootId,
        availability: argus_application::LibraryRootAvailability,
    ) -> Result<bool, PersistenceError> {
        self.inner.set_availability(root_id, availability)
    }

    fn set_last_scan(
        &mut self,
        root_id: LibraryRootId,
        summary: Option<argus_application::LibraryRootLastScanSummary>,
    ) -> Result<bool, PersistenceError> {
        self.inner.set_last_scan(root_id, summary)
    }

    fn get_scan_authority(
        &mut self,
        root_id: LibraryRootId,
    ) -> Result<Option<argus_application::LibraryRootScanConfiguration>, PersistenceError> {
        self.inner.get_scan_authority(root_id)
    }
}

impl AppearanceSettingsRepository for KernelAppearanceSettingsRepository<'_, '_> {
    fn get(&mut self) -> Result<argus_application::AppearanceSettings, PersistenceError> {
        self.inner.get()
    }

    fn save(
        &mut self,
        settings: &argus_application::AppearanceSettings,
    ) -> Result<(), PersistenceError> {
        self.inner.save(settings)
    }
}

impl<'connection> argus_application::UnitOfWork for KernelUnitOfWork<'connection> {
    type AppearanceSettingsRepository<'scope>
        = KernelAppearanceSettingsRepository<'scope, 'connection>
    where
        Self: 'scope;
    type LibrarySourceRepository<'scope>
        = KernelLibrarySourceRepository<'scope, 'connection>
    where
        Self: 'scope;
    type LibraryRootRepository<'scope>
        = KernelLibraryRootRepository<'scope, 'connection>
    where
        Self: 'scope;
    type JobRunRepository<'scope>
        = KernelJobRunRepository<'scope, 'connection>
    where
        Self: 'scope;
    type ScanRunRepository<'scope>
        = KernelScanRunRepository<'scope, 'connection>
    where
        Self: 'scope;
    type SourceEntryRepository<'scope>
        = KernelSourceEntryRepository<'scope, 'connection>
    where
        Self: 'scope;
    type LibraryScanTargetRepository<'scope>
        = KernelLibraryScanTargetRepository<'scope, 'connection>
    where
        Self: 'scope;
    type LibraryScanAdmissionContextRepository<'scope>
        = KernelLibraryScanAdmissionContextRepository<'scope, 'connection>
    where
        Self: 'scope;

    fn appearance_settings(&mut self) -> Self::AppearanceSettingsRepository<'_> {
        KernelAppearanceSettingsRepository {
            inner: self.inner.appearance_settings(),
        }
    }

    fn library_source(&mut self) -> Self::LibrarySourceRepository<'_> {
        KernelLibrarySourceRepository {
            inner: self.inner.library_source(),
        }
    }

    fn library_roots(&mut self) -> Self::LibraryRootRepository<'_> {
        KernelLibraryRootRepository {
            inner: self.inner.library_roots(),
        }
    }

    fn job_runs(&mut self) -> Self::JobRunRepository<'_> {
        KernelJobRunRepository {
            inner: self.inner.job_runs(),
        }
    }

    fn scan_runs(&mut self) -> Self::ScanRunRepository<'_> {
        KernelScanRunRepository {
            inner: self.inner.scan_runs(),
        }
    }

    fn source_entries(&mut self) -> Self::SourceEntryRepository<'_> {
        KernelSourceEntryRepository {
            inner: self.inner.source_entries(),
        }
    }

    fn library_scan_targets(&mut self) -> Self::LibraryScanTargetRepository<'_> {
        KernelLibraryScanTargetRepository {
            inner: self.inner.library_scan_targets(),
        }
    }

    fn library_scan_admission_context(
        &mut self,
    ) -> Self::LibraryScanAdmissionContextRepository<'_> {
        KernelLibraryScanAdmissionContextRepository {
            inner: self.inner.library_scan_admission_context(),
        }
    }

    fn commit(self) -> Result<(), ApplicationPortError> {
        self.inner.commit()
    }

    fn rollback(self) -> Result<(), ApplicationPortError> {
        self.inner.rollback()
    }
}

impl<'connection> LogicalContentUnitOfWork for KernelUnitOfWork<'connection> {
    type LogicalContentRepository<'scope>
        = KernelLogicalContentRepository<'scope, 'connection>
    where
        Self: 'scope;

    fn logical_content(&mut self) -> Self::LogicalContentRepository<'_> {
        KernelLogicalContentRepository {
            inner: self.inner.logical_content(),
        }
    }
}

impl<'connection> argus_application::EnrichmentUnitOfWork for KernelUnitOfWork<'connection> {
    type MetadataRepository<'scope>
        = KernelMetadataRepository<'scope, 'connection>
    where
        Self: 'scope;

    type ArtworkRepository<'scope>
        = KernelArtworkRepository<'scope, 'connection>
    where
        Self: 'scope;

    fn metadata(&mut self) -> Self::MetadataRepository<'_> {
        KernelMetadataRepository {
            inner: self.inner.metadata(),
        }
    }

    fn artwork(&mut self) -> Self::ArtworkRepository<'_> {
        KernelArtworkRepository {
            inner: self.inner.artwork(),
        }
    }
}

impl KernelBootstrap {
    /// Assembles a kernel from coordinator-owned startup resources.
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn from_parts(
        trace_id: TraceId,
        path_class: PathClass,
        migration_summary: KernelMigrationSummary,
        unit_of_work: KernelUnitOfWorkFactory,
        settings_service: SettingsService<SqliteAppearanceSettingsQueries, SqliteDatabaseExecutor>,
        library_service: LibraryService<
            SqliteLibraryRootQueries,
            SqliteSourceEntryQueries,
            SqliteDatabaseExecutor,
            InfraLocalFilesystemProvider,
        >,
        jobs_service: JobsService<SqliteJobsQueries, KernelUnitOfWorkFactory>,
        artwork_store: Arc<ArtworkObjectStore>,
        event_bus: Arc<EventBus>,
        collector: StartupCollector,
        provider_session_factory: Arc<EnrichmentSessionFactory>,
        transformation_staging_root: PathBuf,
    ) -> Self {
        Self {
            trace_id,
            path_class,
            migration_summary,
            executor: Some(unit_of_work.executor.clone()),
            settings_service,
            library_service,
            jobs_service,
            unit_of_work,
            metadata_provider_registry: MetadataProviderRegistry::production(),
            provider_session_factory,
            credential_service: Arc::new(Mutex::new(MetadataProviderService::new(
                KeyringSecureCredentialStore::new(),
                SteamGridDbCredentialValidator::new(UreqTransport::new(), STEAMGRIDDB_API_BASE_URL),
            ))),
            artwork_store,
            event_bus,
            publication_diagnostics: Mutex::new(PublicationDiagnostics::new()),
            transformation_registry: TransformationRegistry::production(),
            transformation_staging_root,
            collector,
            #[cfg(test)]
            fail_shutdown: false,
        }
    }

    /// Test-only failing-shutdown kernel fixture.
    #[cfg(test)]
    pub(crate) fn failing_shutdown_kernel_for_tests(directory: &Path) -> KernelBootstrap {
        let executor = SqliteDatabaseExecutor::open_with_capacity(
            directory.join("argus.sqlite3"),
            argus_infrastructure::sqlite::DEFAULT_QUEUE_CAPACITY,
        )
        .expect("fixture executor");
        let settings_service = SettingsService::new(
            SqliteAppearanceSettingsQueries::new(executor.clone()),
            executor.clone(),
        );
        let library_service = LibraryService::new(
            SqliteLibraryRootQueries::new(executor.clone()),
            SqliteSourceEntryQueries::new(executor.clone()),
            executor.clone(),
            InfraLocalFilesystemProvider::default(),
        );
        let unit_of_work = KernelUnitOfWorkFactory::new(executor.clone());
        let jobs_service = JobsService::new(
            SqliteJobsQueries::new(executor.clone()),
            unit_of_work.clone(),
        );
        let mut kernel = KernelBootstrap::from_parts(
            new_trace_id(),
            PathClass::ExplicitOverride,
            KernelMigrationSummary {
                applied_count: 0,
                current_version: 1,
                outcome: KernelMigrationOutcome::AlreadyCurrent,
            },
            unit_of_work,
            settings_service,
            library_service,
            jobs_service,
            Arc::new(
                ArtworkObjectStore::new(directory.join("artwork-assets"))
                    .expect("fixture artwork store"),
            ),
            Arc::new(EventBus::new(
                Vec::new(),
                Vec::new(),
                Vec::new(),
                Vec::new(),
            )),
            StartupCollector::new(),
            production_enrichment_session_factory(),
            directory.join(argus_infrastructure::content::TRANSFORMATION_STAGING_DIRECTORY),
        );
        kernel.fail_next_shutdown_for_tests();
        kernel
    }

    /// Returns the startup operation trace identity.
    pub fn trace_id(&self) -> TraceId {
        self.trace_id
    }

    /// Returns the sanitized logical class of the resolved data root.
    pub fn path_class(&self) -> PathClass {
        self.path_class
    }

    /// Returns migration state established before the kernel was returned.
    pub fn migration_summary(&self) -> &KernelMigrationSummary {
        &self.migration_summary
    }

    /// Returns startup trace records for local diagnostics.
    pub fn startup_events(&self) -> &[TraceEvent] {
        self.collector.traces()
    }

    /// Returns independently recorded startup logs for local diagnostics.
    pub fn startup_logs(&self) -> &[LogEvent] {
        self.collector.logs()
    }

    /// Returns the immutable production transformation registry used by
    /// composed source processing and identity dispatch.
    pub(crate) fn transformation_registry(&self) -> &TransformationRegistry {
        &self.transformation_registry
    }

    /// Returns the application-private root for operation-scoped staging.
    pub(crate) fn transformation_staging_root(&self) -> &Path {
        &self.transformation_staging_root
    }

    /// Returns bounded structured diagnostics from post-commit publication.
    pub fn publication_logs(&self) -> Vec<LogEvent> {
        self.publication_diagnostics
            .lock()
            .map(|collector| collector.logs().to_vec())
            .unwrap_or_default()
    }

    /// Reads the authoritative appearance aggregate in a fresh operation.
    pub fn get_appearance_settings(&self) -> Result<AppearanceSettings, ApplicationError> {
        let context = settings_operation_context("read", self.trace_id);
        self.get_appearance_settings_with_context(&context)
    }

    /// Reads the authoritative appearance aggregate under an admitted context.
    pub fn get_appearance_settings_with_context(
        &self,
        context: &OperationContext,
    ) -> Result<AppearanceSettings, ApplicationError> {
        self.settings_service
            .get_appearance_settings(GetAppearanceSettingsQuery, context.clone())
    }

    /// Updates the complete appearance aggregate and publishes after commit.
    pub fn update_appearance_settings(
        &self,
        settings: AppearanceSettings,
    ) -> Result<(), ApplicationError> {
        let context = settings_operation_context("update", self.trace_id);
        self.update_appearance_settings_with_context(
            &context,
            settings,
            Arc::new(|| false),
            Arc::new(|| false),
        )
    }

    /// Updates appearance settings under an admitted operation context.
    pub fn update_appearance_settings_with_context(
        &self,
        context: &OperationContext,
        settings: AppearanceSettings,
        is_cancelled: Arc<dyn Fn() -> bool + Send + Sync>,
        pre_commit: Arc<dyn Fn() -> bool + Send + Sync>,
    ) -> Result<(), ApplicationError> {
        if is_cancelled() {
            return Err(ApplicationError::from_code(
                ErrorCode::OperationCancelled,
                context.trace_id(),
                SafeContext::new(),
            )
            .expect("operation cancelled uses an allowlisted empty context"));
        }
        let collector = PendingEventCollector::new();
        let recorder = collector.recorder();
        let result = self.settings_service.update_appearance_settings(
            UpdateAppearanceSettingsCommand::new(settings),
            context.clone(),
            recorder,
            pre_commit,
        );
        finalize_appearance_update(
            result,
            context,
            collector,
            &self.event_bus,
            &self.publication_diagnostics,
        )
    }

    /// Reads the authoritative configured-root list.
    pub fn list_library_roots(
        &self,
        query: ListLibraryRootsQuery,
    ) -> Result<LibraryRootPage, ApplicationError> {
        let context = sources_operation_context("list", self.trace_id);
        self.list_library_roots_with_context(&query, &context)
    }

    /// Reads the authoritative configured-root list under an admitted context.
    pub fn list_library_roots_with_context(
        &self,
        query: &ListLibraryRootsQuery,
        context: &OperationContext,
    ) -> Result<LibraryRootPage, ApplicationError> {
        self.library_service
            .list_library_roots(*query, context.clone())
    }

    /// Reads the bounded baseline logical-library page in a short transaction.
    ///
    /// The transaction contains only SQLite projection reads and commit
    /// bookkeeping. Content I/O and identification are owned by the internal
    /// identification capability and complete before convergence begins.
    pub fn list_games_with_context(
        &self,
        query: &ListGamesQuery,
        context: &OperationContext,
    ) -> Result<GameLibraryPage, ApplicationError> {
        let query = query.clone();
        self.execute(context, move |mut work| {
            let mut logical = work.logical_content();
            let page = logical
                .list_games(&query)
                .map_err(ApplicationPortError::Persistence)?;
            work.commit()?;
            Ok(page)
        })
        .map_err(|error| map_application_port_error(context.trace_id(), error))
    }

    /// Reads facet counts for a bounded logical-library query shape.
    pub fn get_library_facets_with_context(
        &self,
        query: &LibraryFacetQuery,
        context: &OperationContext,
    ) -> Result<LibraryFacets, ApplicationError> {
        let query = query.clone();
        self.execute(context, move |mut work| {
            let mut logical = work.logical_content();
            let facets = logical
                .get_library_facets(&query)
                .map_err(ApplicationPortError::Persistence)?;
            work.commit()?;
            Ok(facets)
        })
        .map_err(|error| map_application_port_error(context.trace_id(), error))
    }

    /// Enumerates canonical Game identities through the bounded Library
    /// projection for a background local-resolution pass.
    pub fn list_game_ids_with_context(
        &self,
        context: &OperationContext,
    ) -> Result<Vec<GameId>, ApplicationError> {
        let mut game_ids = Vec::new();
        let mut cursor = None;
        loop {
            let query = ListGamesQuery::builder()
                .scope(LibraryScope::All)
                .search(None)
                .filters_empty(true)
                .sort(LibrarySort::DisplayTitleAscending)
                .cursor(cursor.clone())
                .page_size(500)
                .build()
                .map_err(|_| {
                    application_error_from_code(
                        ErrorCode::ValidationInvalidArgument,
                        context.trace_id(),
                    )
                })?;
            let page = self.list_games_with_context(&query, context)?;
            game_ids.extend(page.items().iter().map(|row| row.game_id()));
            cursor = page.next_cursor().cloned();
            if cursor.is_none() {
                break;
            }
        }
        Ok(game_ids)
    }

    /// Reads one focused durable logical-game result in a short transaction.
    pub fn get_game_with_context(
        &self,
        game_id: GameId,
        context: &OperationContext,
    ) -> Result<GetGameResult, ApplicationError> {
        self.execute(context, move |mut work| {
            let result = {
                let mut logical = work.logical_content();
                logical
                    .get_game(game_id)
                    .map_err(ApplicationPortError::Persistence)?
            };
            let result = match result {
                GetGameResult::Found(detail) => {
                    let canonical_game_id = detail.game_id();
                    let resolved_metadata = {
                        let mut metadata = work.metadata();
                        metadata
                            .resolved_metadata_for_game(canonical_game_id)
                            .map_err(ApplicationPortError::Persistence)?
                    };
                    let resolved_artwork = {
                        let mut artwork = work.artwork();
                        artwork
                            .resolved_artwork_for_game(canonical_game_id)
                            .map_err(ApplicationPortError::Persistence)?
                    };
                    GetGameResult::Found(
                        detail.with_enrichment(resolved_metadata, resolved_artwork),
                    )
                }
                other => other,
            };
            work.commit()?;
            Ok(result)
        })
        .map_err(|error| map_application_port_error(context.trace_id(), error))
    }

    /// Reads the durable onboarding record and composes it with the current
    /// root and credential facts owned by their focused capabilities.
    pub fn library_onboarding_state_with_context(
        &self,
        context: &OperationContext,
    ) -> Result<LibraryOnboardingState, ApplicationError> {
        let progress = self
            .unit_of_work
            .execute(context, |mut work| {
                let progress = {
                    let mut metadata = work.metadata();
                    metadata
                        .library_onboarding_progress()
                        .map_err(ApplicationPortError::Persistence)?
                };
                work.commit()?;
                Ok(progress)
            })
            .map_err(|error| map_application_port_error(context.trace_id(), error))?;
        let roots = self
            .library_service
            .list_library_roots(ListLibraryRootsQuery::new(0, 1), context.clone())?;
        let readiness = self.metadata_provider_readiness_with_context(context)?;
        let credential_configured = readiness.iter().any(|provider| {
            provider.provider_id() == ProviderId::SteamGridDb && provider.credential_configured()
        });
        Ok(LibraryOnboardingState::new(
            progress,
            argus_application::CURRENT_PRIVACY_TERMS_VERSION,
            roots.items().is_empty(),
            credential_configured,
        ))
    }

    /// Reads the one Settings-owned privacy-consent projection.
    pub fn privacy_consent_with_context(
        &self,
        context: &OperationContext,
    ) -> Result<PrivacyConsent, ApplicationError> {
        self.unit_of_work
            .execute(context, |mut work| {
                let progress = {
                    let mut metadata = work.metadata();
                    metadata
                        .library_onboarding_progress()
                        .map_err(ApplicationPortError::Persistence)?
                };
                let consent = PrivacyConsent::new(
                    progress.accepted_privacy_terms_version().map(str::to_owned),
                    progress.accepted_privacy_at_ms(),
                    argus_application::CURRENT_PRIVACY_TERMS_VERSION,
                );
                work.commit()?;
                Ok(consent)
            })
            .map_err(|error| map_application_port_error(context.trace_id(), error))
    }

    /// Accepts only the backend-advertised current privacy-terms version.
    pub fn accept_privacy_terms_with_context(
        &self,
        context: &OperationContext,
        terms_version: String,
        accepted_at_ms: i64,
    ) -> Result<PrivacyConsent, ApplicationError> {
        if terms_version != argus_application::CURRENT_PRIVACY_TERMS_VERSION {
            return Err(application_error_from_code(
                ErrorCode::ValidationInvalidArgument,
                context.trace_id(),
            ));
        }
        self.unit_of_work
            .execute(context, move |mut work| {
                let mut progress = {
                    let mut metadata = work.metadata();
                    metadata
                        .library_onboarding_progress()
                        .map_err(ApplicationPortError::Persistence)?
                };
                progress.accept_privacy_terms(terms_version, accepted_at_ms);
                {
                    let mut metadata = work.metadata();
                    metadata
                        .save_library_onboarding_progress(&progress)
                        .map_err(ApplicationPortError::Persistence)?;
                }
                work.commit()?;
                Ok(())
            })
            .map_err(|error| map_application_port_error(context.trace_id(), error))?;
        self.privacy_consent_with_context(context)
    }

    /// Persists metadata preferences and marks the onboarding preference step
    /// complete in one transaction.
    pub fn confirm_library_metadata_preferences_with_context(
        &self,
        context: &OperationContext,
        settings: MetadataSettings,
    ) -> Result<LibraryOnboardingState, ApplicationError> {
        self.unit_of_work
            .execute(context, move |mut work| {
                {
                    let mut metadata = work.metadata();
                    metadata
                        .save_settings(&settings)
                        .map_err(ApplicationPortError::Persistence)?;
                }
                let mut progress = {
                    let mut metadata = work.metadata();
                    metadata
                        .library_onboarding_progress()
                        .map_err(ApplicationPortError::Persistence)?
                };
                progress.confirm_metadata_preferences();
                {
                    let mut metadata = work.metadata();
                    metadata
                        .save_library_onboarding_progress(&progress)
                        .map_err(ApplicationPortError::Persistence)?;
                }
                work.commit()?;
                Ok(())
            })
            .map_err(|error| map_application_port_error(context.trace_id(), error))?;
        self.library_onboarding_state_with_context(context)
    }

    /// Records a validated provider-setup decision. Configured is accepted
    /// only when the credential readiness authority confirms the credential.
    pub fn record_library_provider_setup_with_context(
        &self,
        context: &OperationContext,
        decision: LibraryProviderSetupDecision,
    ) -> Result<LibraryOnboardingState, ApplicationError> {
        let readiness = self.metadata_provider_readiness_with_context(context)?;
        let steamgriddb = readiness
            .iter()
            .find(|provider| provider.provider_id() == ProviderId::SteamGridDb);
        let credential_configured =
            steamgriddb.is_some_and(|provider| provider.credential_configured());
        let credential_accepted = steamgriddb.is_some_and(|provider| {
            provider.credential_configured()
                && provider.capability_readiness().iter().all(|capability| {
                    matches!(
                        capability.state(),
                        ProviderReadinessState::Ready | ProviderReadinessState::Unavailable
                    )
                })
        });
        if (matches!(decision, LibraryProviderSetupDecision::Configured) && !credential_accepted)
            || (matches!(decision, LibraryProviderSetupDecision::Skipped) && credential_configured)
        {
            return Err(application_error_from_code(
                ErrorCode::ValidationInvalidArgument,
                context.trace_id(),
            ));
        }
        self.unit_of_work
            .execute(context, move |mut work| {
                let mut progress = {
                    let mut metadata = work.metadata();
                    metadata
                        .library_onboarding_progress()
                        .map_err(ApplicationPortError::Persistence)?
                };
                progress.record_provider_setup(decision);
                {
                    let mut metadata = work.metadata();
                    metadata
                        .save_library_onboarding_progress(&progress)
                        .map_err(ApplicationPortError::Persistence)?;
                }
                work.commit()?;
                Ok(())
            })
            .map_err(|error| map_application_port_error(context.trace_id(), error))?;
        self.library_onboarding_state_with_context(context)
    }

    /// Commits onboarding completion only after all prerequisite facts are
    /// already present. Refresh admission is intentionally a separate child.
    pub fn complete_library_onboarding_with_context(
        &self,
        context: &OperationContext,
    ) -> Result<LibraryOnboardingState, ApplicationError> {
        let state = self.library_onboarding_state_with_context(context)?;
        let progress = state.progress();
        let provider_ready = matches!(
            progress.provider_setup_outcome(),
            argus_application::LibraryProviderSetupOutcome::Configured
                | argus_application::LibraryProviderSetupOutcome::Skipped
        );
        if state.requires_privacy_acceptance()
            || state.requires_root_selection()
            || !progress.metadata_preferences_confirmed()
            || !provider_ready
        {
            return Err(application_error_from_code(
                ErrorCode::ValidationInvalidArgument,
                context.trace_id(),
            ));
        }
        let completed_at_ms = crate::now_millis();
        self.unit_of_work
            .execute(context, move |mut work| {
                let mut progress = {
                    let mut metadata = work.metadata();
                    metadata
                        .library_onboarding_progress()
                        .map_err(ApplicationPortError::Persistence)?
                };
                progress.complete(completed_at_ms);
                {
                    let mut metadata = work.metadata();
                    metadata
                        .save_library_onboarding_progress(&progress)
                        .map_err(ApplicationPortError::Persistence)?;
                }
                work.commit()?;
                Ok(())
            })
            .map_err(|error| map_application_port_error(context.trace_id(), error))?;
        self.library_onboarding_state_with_context(context)
    }

    /// Reads local metadata preferences without starting resolution work.
    pub fn metadata_settings_with_context(
        &self,
        context: &OperationContext,
    ) -> Result<MetadataSettings, ApplicationError> {
        self.unit_of_work
            .execute(context, |mut work| {
                let settings = {
                    let mut metadata = work.metadata();
                    metadata
                        .settings()
                        .map_err(ApplicationPortError::Persistence)?
                };
                work.commit()?;
                Ok(settings)
            })
            .map_err(|error| map_application_port_error(context.trace_id(), error))
    }

    /// Reads provider enablement without starting provider or resolution work.
    pub fn metadata_provider_settings_with_context(
        &self,
        context: &OperationContext,
    ) -> Result<MetadataProviderSettings, ApplicationError> {
        self.unit_of_work
            .execute(context, |mut work| {
                let settings = {
                    let mut metadata = work.metadata();
                    metadata
                        .provider_settings()
                        .map_err(ApplicationPortError::Persistence)?
                };
                work.commit()?;
                Ok(settings)
            })
            .map_err(|error| map_application_port_error(context.trace_id(), error))
    }

    /// Commits local metadata preferences and reports whether the durable value
    /// changed. Resolution admission is owned by the host-level coordinator.
    pub fn update_metadata_settings_with_context(
        &self,
        context: &OperationContext,
        settings: MetadataSettings,
    ) -> Result<(MetadataSettings, bool), ApplicationError> {
        self.unit_of_work
            .execute(context, move |mut work| {
                let current = {
                    let mut metadata = work.metadata();
                    metadata
                        .settings()
                        .map_err(ApplicationPortError::Persistence)?
                };
                let changed = current != settings;
                if changed {
                    let mut metadata = work.metadata();
                    metadata
                        .save_settings(&settings)
                        .map_err(ApplicationPortError::Persistence)?;
                }
                work.commit()?;
                Ok((settings, changed))
            })
            .map_err(|error| map_application_port_error(context.trace_id(), error))
    }

    /// Reads the committed metadata-settings revision used by resolution jobs.
    pub fn metadata_settings_revision_with_context(
        &self,
        context: &OperationContext,
    ) -> Result<u64, ApplicationError> {
        self.unit_of_work
            .execute(context, |mut work| {
                let revision = {
                    let mut metadata = work.metadata();
                    metadata
                        .settings_revision()
                        .map_err(ApplicationPortError::Persistence)?
                };
                work.commit()?;
                Ok(revision)
            })
            .map_err(|error| map_application_port_error(context.trace_id(), error))
    }

    /// Commits provider enablement and reports whether the durable value
    /// changed. The host admits local-only resolution after commit.
    pub fn update_metadata_provider_settings_with_context(
        &self,
        context: &OperationContext,
        settings: MetadataProviderSettings,
    ) -> Result<(MetadataProviderSettings, bool), ApplicationError> {
        self.unit_of_work
            .execute(context, move |mut work| {
                let current = {
                    let mut metadata = work.metadata();
                    metadata
                        .provider_settings()
                        .map_err(ApplicationPortError::Persistence)?
                };
                let changed = current != settings;
                if changed {
                    let mut metadata = work.metadata();
                    metadata
                        .save_provider_settings(&settings)
                        .map_err(ApplicationPortError::Persistence)?;
                }
                work.commit()?;
                Ok((settings, changed))
            })
            .map_err(|error| map_application_port_error(context.trace_id(), error))
    }

    /// Durably admits a bounded Game refresh intent. The execution handler is
    /// registered by the runtime; no generic workflow graph is introduced.
    pub fn admit_game_refresh_with_context(
        &self,
        context: &OperationContext,
        game_ids: Vec<GameId>,
        mode: RefreshMode,
    ) -> Result<OperationHandle, ApplicationError> {
        if game_ids.is_empty() || (matches!(mode, RefreshMode::Force) && game_ids.len() != 1) {
            return Err(application_error_from_code(
                ErrorCode::ValidationInvalidArgument,
                context.trace_id(),
            ));
        }
        let created_at_ms = crate::now_millis();
        let job_run_id = self
            .unit_of_work
            .execute(context, move |mut work| {
                let job_run_id = work.job_runs().insert(NewJobRun::new(
                    argus_application::OPERATION_TYPE_GAME_REFRESH,
                    created_at_ms,
                ))?;
                work.job_runs()
                    .insert_game_refresh_intent(job_run_id, &game_ids, mode)?;
                work.commit()?;
                Ok(job_run_id)
            })
            .map_err(|error| map_application_port_error(context.trace_id(), error))?;
        Ok(OperationHandle::new(
            job_run_id,
            argus_application::OPERATION_TYPE_GAME_REFRESH,
        ))
    }

    /// Durably admits one local-only metadata-resolution intent.
    pub fn admit_library_resolution_refresh_with_context(
        &self,
        context: &OperationContext,
        settings_revision: u64,
    ) -> Result<OperationHandle, ApplicationError> {
        let created_at_ms = crate::now_millis();
        let job_run_id = self
            .unit_of_work
            .execute(context, move |mut work| {
                let job_run_id = work.job_runs().insert(NewJobRun::new(
                    argus_application::OPERATION_TYPE_LIBRARY_RESOLUTION_REFRESH,
                    created_at_ms,
                ))?;
                work.job_runs()
                    .insert_library_resolution_refresh_intent(job_run_id, settings_revision)?;
                work.commit()?;
                Ok(job_run_id)
            })
            .map_err(|error| map_application_port_error(context.trace_id(), error))?;
        Ok(OperationHandle::new(
            job_run_id,
            argus_application::OPERATION_TYPE_LIBRARY_RESOLUTION_REFRESH,
        ))
    }

    /// Reads provider enablement and safe credential readiness without
    /// resolving metadata or starting provider work.
    pub fn metadata_provider_readiness_with_context(
        &self,
        context: &OperationContext,
    ) -> Result<Vec<MetadataProviderReadinessProjection>, ApplicationError> {
        let executor = self.executor.clone().ok_or_else(|| {
            application_error_from_code(ErrorCode::RuntimeStopped, context.trace_id())
        })?;
        let credential_service = Arc::clone(&self.credential_service);
        let credential_readiness = executor
            .execute_on_worker(context.clone(), move || {
                let mut service = credential_service
                    .lock()
                    .map_err(|_| SqliteExecutorError::Internal)?;
                // A secure-store read failure is a provider readiness fact,
                // not permission to fall back to normal application storage.
                // The service retains the safe Unavailable projection so the
                // readiness query can report it without exposing a native
                // storage error or secret material.
                match service.refresh_readiness_from_store() {
                    Ok(_) | Err(_) => Ok(service.readiness()),
                }
            })
            .map_err(|error| map_sqlite_executor_error(context.trace_id(), error))?;

        let settings = self
            .unit_of_work
            .execute(context, |mut work| {
                let settings = {
                    let mut metadata = work.metadata();
                    metadata
                        .provider_settings()
                        .map_err(ApplicationPortError::Persistence)?
                };
                work.commit()?;
                Ok(settings)
            })
            .map_err(|error| map_application_port_error(context.trace_id(), error))?;
        Ok(self
            .metadata_provider_registry
            .readiness_projection(&settings, credential_readiness))
    }

    /// Hydrates one already identified target on a dedicated backend worker.
    ///
    /// This is an internal reusable capability for a later composed workflow;
    /// it does not admit a JobRun, publish a job event, or react to settings
    /// mutations. Provider I/O is kept off the SQLite worker and therefore off
    /// any Flutter/UI caller. Settings are read once to build local policies,
    /// then the application coordinator owns the short persistence commits.
    pub fn hydrate_game_content_with_context(
        &self,
        target: HydrationTarget,
        context: &OperationContext,
        now: i64,
    ) -> Result<HydrationReport, ApplicationError> {
        let validation_target = target.clone();
        let target_is_current = self
            .unit_of_work
            .execute(context, move |mut work| {
                let game = {
                    let mut logical = work.logical_content();
                    logical
                        .get_game(validation_target.game_id())
                        .map_err(ApplicationPortError::Persistence)?
                };
                let valid = match game {
                    GetGameResult::Found(detail) => {
                        validation_target.validate_against_game(&detail).is_ok()
                    }
                    GetGameResult::Redirected(_) | GetGameResult::NotFound => false,
                };
                work.commit()?;
                Ok(valid)
            })
            .map_err(|error| map_application_port_error(context.trace_id(), error))?;
        if !target_is_current {
            return Err(application_error_from_code(
                ErrorCode::ValidationInvalidArgument,
                context.trace_id(),
            ));
        }
        let trace_id = context.trace_id();
        let unit_of_work = self.unit_of_work.clone();
        let registry = self.metadata_provider_registry.clone();
        let credential_service = Arc::clone(&self.credential_service);
        let artwork_store = Arc::clone(&self.artwork_store);
        let worker_context = context.clone();
        let worker = std::thread::Builder::new()
            .name("argus-enrichment-worker".to_owned())
            .spawn(move || {
                let (metadata_settings, provider_settings) =
                    unit_of_work.execute(&worker_context, |mut work| {
                        let metadata_settings = {
                            let mut metadata = work.metadata();
                            metadata
                                .settings()
                                .map_err(ApplicationPortError::Persistence)?
                        };
                        let provider_settings = {
                            let mut metadata = work.metadata();
                            metadata
                                .provider_settings()
                                .map_err(ApplicationPortError::Persistence)?
                        };
                        work.commit()?;
                        Ok((metadata_settings, provider_settings))
                    })?;

                let credential_readiness = {
                    let mut service = credential_service.lock().map_err(|_| {
                        ApplicationPortError::Persistence(PersistenceError::Internal)
                    })?;
                    match service.refresh_readiness_from_store() {
                        Ok(readiness) => readiness,
                        Err(_) => service.readiness(),
                    }
                };
                let readiness =
                    registry.readiness_projection(&provider_settings, credential_readiness);
                let metadata_policy = MetadataResolutionPolicy::new(
                    provider_settings.enabled().clone(),
                    metadata_settings.preferred_regions().to_vec(),
                    metadata_settings.preferred_languages().to_vec(),
                );
                let mut artwork_policy = ArtworkResolutionPolicy::default();
                for provider_id in registry.provider_ids() {
                    artwork_policy.set_enabled(
                        provider_id,
                        provider_settings.enabled().contains(&provider_id),
                    );
                }
                artwork_policy.set_locale_preferences(
                    metadata_settings.preferred_regions().to_vec(),
                    metadata_settings.preferred_languages().to_vec(),
                );
                let session_factory = ProductionProviderSessionFactory::new();
                let mut sessions = session_factory.create_sessions();
                LibraryRefreshCoordinator::new(unit_of_work).hydrate(
                    &worker_context,
                    target,
                    metadata_policy,
                    artwork_policy,
                    &registry,
                    &readiness,
                    &mut sessions,
                    artwork_store.as_ref(),
                    now,
                )
            })
            .map_err(|_| application_error_from_code(ErrorCode::InternalUnexpected, trace_id))?;
        let result = worker
            .join()
            .map_err(|_| application_error_from_code(ErrorCode::InternalUnexpected, trace_id))?;
        result.map_err(|error| map_application_port_error(trace_id, error))
    }

    /// Hydrates one already identified target with sessions owned by the
    /// enclosing composed refresh.
    ///
    /// The public single-content API keeps its worker boundary and production
    /// session construction. This internal variant is used only after a
    /// committed scan checkpoint and lets the parent refresh reuse one
    /// deterministic session set across all affected content.
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn hydrate_game_content_with_sessions_with_context(
        &self,
        target: HydrationTarget,
        context: &OperationContext,
        now: i64,
        sessions: &mut [Box<dyn EnrichmentProviderSession>],
    ) -> Result<HydrationReport, ApplicationError> {
        let validation_target = target.clone();
        let target_is_current = self
            .unit_of_work
            .execute(context, move |mut work| {
                let game = {
                    let mut logical = work.logical_content();
                    logical
                        .get_game(validation_target.game_id())
                        .map_err(ApplicationPortError::Persistence)?
                };
                let valid = match game {
                    GetGameResult::Found(detail) => {
                        validation_target.validate_against_game(&detail).is_ok()
                    }
                    GetGameResult::Redirected(_) | GetGameResult::NotFound => false,
                };
                work.commit()?;
                Ok(valid)
            })
            .map_err(|error| map_application_port_error(context.trace_id(), error))?;
        if !target_is_current {
            return Err(application_error_from_code(
                ErrorCode::ValidationInvalidArgument,
                context.trace_id(),
            ));
        }

        let (metadata_settings, provider_settings) = self
            .unit_of_work
            .execute(context, |mut work| {
                let metadata_settings = {
                    let mut metadata = work.metadata();
                    metadata
                        .settings()
                        .map_err(ApplicationPortError::Persistence)?
                };
                let provider_settings = {
                    let mut metadata = work.metadata();
                    metadata
                        .provider_settings()
                        .map_err(ApplicationPortError::Persistence)?
                };
                work.commit()?;
                Ok((metadata_settings, provider_settings))
            })
            .map_err(|error| map_application_port_error(context.trace_id(), error))?;

        // A missing provider-session composition cannot consume credential
        // readiness. Avoid touching the platform secure store in that case;
        // real provider sessions still use the existing readiness path.
        let readiness = if sessions.is_empty() {
            Vec::new()
        } else {
            let credential_readiness = {
                let requires_credentials =
                    sessions_require_credentials(&self.metadata_provider_registry, sessions);
                let mut service = self.credential_service.lock().map_err(|_| {
                    application_error_from_code(ErrorCode::InternalUnexpected, context.trace_id())
                })?;
                if requires_credentials {
                    match service.refresh_readiness_from_store() {
                        Ok(readiness) => readiness,
                        Err(_) => service.readiness(),
                    }
                } else {
                    // Non-credentialed sessions still receive the cached
                    // readiness projection, but must not touch the secure
                    // store merely because the enclosing refresh has a
                    // provider session set.
                    service.readiness()
                }
            };
            self.metadata_provider_registry
                .readiness_projection(&provider_settings, credential_readiness)
        };
        let metadata_policy = MetadataResolutionPolicy::new(
            provider_settings.enabled().clone(),
            metadata_settings.preferred_regions().to_vec(),
            metadata_settings.preferred_languages().to_vec(),
        );
        let mut artwork_policy = ArtworkResolutionPolicy::default();
        for provider_id in self.metadata_provider_registry.provider_ids() {
            artwork_policy.set_enabled(
                provider_id,
                provider_settings.enabled().contains(&provider_id),
            );
        }
        artwork_policy.set_locale_preferences(
            metadata_settings.preferred_regions().to_vec(),
            metadata_settings.preferred_languages().to_vec(),
        );

        LibraryRefreshCoordinator::new(self.unit_of_work.clone())
            .hydrate(
                context,
                target,
                metadata_policy,
                artwork_policy,
                &self.metadata_provider_registry,
                &readiness,
                sessions,
                self.artwork_store.as_ref(),
                now,
            )
            .map_err(|error| map_application_port_error(context.trace_id(), error))
    }

    /// Consumes only source entries committed by the supplied scan checkpoint.
    ///
    /// Filesystem reads and representation recognition happen outside the
    fn reconcile_derived_scope_with_context(
        &self,
        plan: &argus_application::LibraryScanExecutionPlan,
        context: &OperationContext,
        parent: &SourceEntryRecord,
        observed_at_seconds: i64,
        scope: &argus_infrastructure::content::DerivedScopeResult,
    ) -> Result<Vec<SourceEntryRecord>, ApplicationError> {
        let transformation_id = scope.transformation_id().ok_or_else(|| {
            application_error_from_code(ErrorCode::InternalInvariantViolation, context.trace_id())
        })?;
        let transformation_revision = scope.transformation_revision().ok_or_else(|| {
            application_error_from_code(ErrorCode::InternalInvariantViolation, context.trace_id())
        })?;
        let registered = self
            .transformation_registry()
            .descriptors()
            .iter()
            .any(|descriptor| {
                descriptor.id() == transformation_id
                    && descriptor.revision() == transformation_revision
                    && matches!(
                        descriptor.output(),
                        argus_application::TransformationOutput::DerivedScope
                    )
            });
        if !registered {
            return Err(application_error_from_code(
                ErrorCode::InternalInvariantViolation,
                context.trace_id(),
            ));
        }

        let parent_source_entry_id = parent.source_entry_id();
        let observations = scope.observations().to_vec();
        let outcome = scope.outcome();
        let observation_run_id = plan.scan_run_id();
        self.unit_of_work
            .execute(context, move |mut work| {
                let mut source_entries = work.source_entries();
                let scope_identity = DerivedScopeIdentity {
                    parent_source_entry_id,
                    transformation_id,
                    transformation_revision,
                };
                reconcile_derived_scope(
                    &mut source_entries,
                    &scope_identity,
                    &observations,
                    observation_run_id,
                    observed_at_seconds,
                    true,
                    outcome,
                )?;
                let mut reconciled = Vec::with_capacity(observations.len());
                for observation in &observations {
                    if let Some(entry) = source_entries.find_derived_child(
                        parent_source_entry_id,
                        transformation_id,
                        transformation_revision,
                        observation.derived_entry_key(),
                    )? {
                        reconciled.push(entry);
                    }
                }
                work.commit()?;
                Ok(reconciled)
            })
            .map_err(|error| map_application_port_error(context.trace_id(), error))
    }

    #[allow(clippy::too_many_arguments)]
    fn process_source_tree(
        &self,
        plan: &argus_application::LibraryScanExecutionPlan,
        context: &OperationContext,
        access: &LocalFilesystemSourceAccess,
        resolved_root: &argus_application::ResolvedRoot,
        entry: &SourceEntryRecord,
        entries: &mut Vec<SourceEntryRecord>,
        session: &mut ParsingSession<'_>,
        observed_at_seconds: i64,
        catalog: &IdentitySchemeCatalog,
        is_cancelled: &dyn Fn() -> bool,
    ) -> Result<SourceTreeResult, TransformationFailure> {
        if is_cancelled() {
            return Err(TransformationFailure::Cancelled);
        }
        if entry.kind() != SourceEntryKind::File {
            return Ok(SourceTreeResult::empty());
        }

        let parent_version = source_version_for_entry(entry)?;
        let mut reader = {
            let resolver = ContentSourceResolver::new(access, resolved_root, entries.as_slice());
            resolver.open(entry, session)?
        };
        session.enter_container()?;
        let scope_result = argus_infrastructure::content::enumerate_derived_container(
            &mut *reader,
            &parent_version,
            session,
        );
        session.leave_container();
        let scope = match scope_result {
            Ok(Some(scope)) => scope,
            Ok(None) => {
                if is_m3u_entry(entry) {
                    let playlist = self.recognize_derived_playlist(
                        entry,
                        access,
                        resolved_root,
                        entries.as_slice(),
                        session,
                    )?;
                    return Ok(SourceTreeResult {
                        candidates: Vec::new(),
                        derived_playlists: playlist.into_iter().collect(),
                        issue_codes: Vec::new(),
                    });
                }
                if is_optical_descriptor_entry(entry)
                    && matches!(
                        entry.coordinates(),
                        argus_application::SourceEntryCoordinates::Derived { .. }
                    )
                {
                    let candidate = self.recognize_derived_descriptor(
                        entry,
                        access,
                        resolved_root,
                        entries.as_slice(),
                        session,
                        catalog,
                        is_cancelled,
                    )?;
                    return Ok(SourceTreeResult {
                        candidates: candidate.into_iter().collect(),
                        derived_playlists: Vec::new(),
                        issue_codes: Vec::new(),
                    });
                }
                let candidate = self.recognize_source_reader(
                    entry,
                    &mut *reader,
                    session,
                    catalog,
                    is_cancelled,
                )?;
                return Ok(SourceTreeResult {
                    candidates: candidate.into_iter().collect(),
                    derived_playlists: Vec::new(),
                    issue_codes: Vec::new(),
                });
            }
            Err(error) => return Err(error),
        };
        if !reader
            .source_version_is_unchanged()
            .map_err(|_| TransformationFailure::ReadFailure)?
        {
            return Err(TransformationFailure::SourceChanged);
        }

        let children = self
            .reconcile_derived_scope_with_context(plan, context, entry, observed_at_seconds, &scope)
            .map_err(|_| TransformationFailure::ReadFailure)?;
        let mut candidates = Vec::new();
        let mut derived_playlists = Vec::new();
        let mut issue_codes = Vec::new();
        for child in &children {
            if child.kind() == SourceEntryKind::File
                && !entries
                    .iter()
                    .any(|existing| existing.source_entry_id() == child.source_entry_id())
            {
                entries.push(child.clone());
            }
        }
        for child in children {
            if child.kind() != SourceEntryKind::File {
                continue;
            }
            match self.process_source_tree(
                plan,
                context,
                access,
                resolved_root,
                &child,
                entries,
                session,
                observed_at_seconds,
                catalog,
                is_cancelled,
            ) {
                Ok(result) => {
                    candidates.extend(result.candidates);
                    derived_playlists.extend(result.derived_playlists);
                    issue_codes.extend(result.issue_codes);
                }
                Err(TransformationFailure::Cancelled) => {
                    return Err(TransformationFailure::Cancelled);
                }
                Err(TransformationFailure::SourceChanged) => {
                    return Err(TransformationFailure::SourceChanged);
                }
                Err(TransformationFailure::ResourceLimitExceeded) => {
                    return Err(TransformationFailure::ResourceLimitExceeded);
                }
                Err(failure) => issue_codes.push(map_transformation_failure(failure)),
            }
        }

        let mut grouped_candidate_ids = std::collections::HashSet::new();
        let mut families = Vec::<(ContentIdentity, Vec<SourceEntryId>)>::new();
        for playlist in &derived_playlists {
            let group = candidates
                .iter()
                .filter(|candidate| {
                    playlist
                        .members
                        .iter()
                        .any(|member| member.source_entry_id() == candidate.entry.source_entry_id())
                })
                .collect::<Vec<_>>();
            if let Some(first_identity) = group.first().map(|candidate| candidate.identity.clone())
            {
                let mut ids = Vec::with_capacity(group.len());
                for candidate in group {
                    grouped_candidate_ids.insert(candidate.entry.source_entry_id());
                    ids.push(candidate.entry.source_entry_id());
                }
                families.push((first_identity, ids));
            }
        }
        for candidate in &candidates {
            if !grouped_candidate_ids.contains(&candidate.entry.source_entry_id()) {
                families.push((
                    candidate.identity.clone(),
                    vec![candidate.entry.source_entry_id()],
                ));
            }
        }
        let family_identities: Vec<ContentIdentity> = families
            .iter()
            .map(|(identity, _)| identity.clone())
            .collect();
        let candidates = match evaluate_archive_eligibility(&family_identities) {
            Ok(argus_application::ArchiveEligibility::NoSupportedGame) => Vec::new(),
            Ok(argus_application::ArchiveEligibility::SingleGame(identity)) => {
                let allowed_ids = families
                    .iter()
                    .filter(|(family_identity, _)| family_identity == &identity)
                    .flat_map(|(_, ids)| ids.iter().copied())
                    .collect::<std::collections::HashSet<_>>();
                candidates
                    .into_iter()
                    .filter(|candidate| allowed_ids.contains(&candidate.entry.source_entry_id()))
                    .collect()
            }
            Err(argus_application::ArchiveAdmissionError::MultiGameUnsupported) => {
                issue_codes.push(map_transformation_failure(
                    TransformationFailure::MultiGameUnsupported,
                ));
                Vec::new()
            }
        };
        Ok(SourceTreeResult {
            candidates,
            derived_playlists,
            issue_codes,
        })
    }

    fn recognize_derived_playlist(
        &self,
        entry: &SourceEntryRecord,
        access: &LocalFilesystemSourceAccess,
        resolved_root: &argus_application::ResolvedRoot,
        entries: &[SourceEntryRecord],
        session: &mut ParsingSession<'_>,
    ) -> Result<Option<DerivedPlaylistGroup>, TransformationFailure> {
        let resolver = ContentSourceResolver::new(access, resolved_root, entries);
        let mut reader = resolver.open(entry, session)?;
        let bytes = read_content_bytes(&mut *reader, 1024 * 1024, session)?;
        let parsed =
            argus_infrastructure::content::parse_m3u(&bytes).map_err(|error| match error {
                argus_infrastructure::content::M3uError::ResourceLimitExceeded => {
                    TransformationFailure::ResourceLimitExceeded
                }
                argus_infrastructure::content::M3uError::Malformed
                | argus_infrastructure::content::M3uError::InvalidMember
                | argus_infrastructure::content::M3uError::DuplicateMember => {
                    TransformationFailure::Malformed
                }
            })?;
        let parent_id = entry
            .parent_source_entry_id()
            .ok_or(TransformationFailure::Malformed)?;
        let candidates = entries
            .iter()
            .filter(|candidate| candidate.parent_source_entry_id() == Some(parent_id))
            .map(|candidate| {
                argus_application::ContentDependencyCandidate::new(
                    candidate.clone(),
                    candidate.display_location().to_owned(),
                )
            })
            .collect::<Vec<_>>();
        let members = argus_application::resolve_content_dependencies(
            entry.display_location(),
            parsed.members(),
            &candidates,
        )
        .map_err(|error| match error {
            argus_application::OpticalDependencyError::ResourceLimitExceeded => {
                TransformationFailure::ResourceLimitExceeded
            }
            argus_application::OpticalDependencyError::Missing
            | argus_application::OpticalDependencyError::Ambiguous
            | argus_application::OpticalDependencyError::Duplicate => {
                TransformationFailure::MissingDependency
            }
            argus_application::OpticalDependencyError::InvalidReference
            | argus_application::OpticalDependencyError::CrossRoot => {
                TransformationFailure::UnsupportedFeature
            }
        })?;
        Ok(Some(DerivedPlaylistGroup {
            playlist: entry.clone(),
            members,
        }))
    }

    #[allow(clippy::too_many_arguments)]
    fn recognize_derived_descriptor(
        &self,
        entry: &SourceEntryRecord,
        access: &LocalFilesystemSourceAccess,
        resolved_root: &argus_application::ResolvedRoot,
        entries: &[SourceEntryRecord],
        session: &mut ParsingSession<'_>,
        catalog: &IdentitySchemeCatalog,
        is_cancelled: &dyn Fn() -> bool,
    ) -> Result<Option<ProcessedContentCandidate>, TransformationFailure> {
        session.check_cancelled()?;
        let resolver = ContentSourceResolver::new(access, resolved_root, entries);
        let mut descriptor_reader = resolver.open(entry, session)?;
        let descriptor_bytes = read_content_bytes(&mut *descriptor_reader, 1024 * 1024, session)?;
        let descriptor = argus_infrastructure::content::parse_descriptor(&descriptor_bytes)
            .map_err(map_optical_failure)?;

        let parent_id = entry
            .parent_source_entry_id()
            .ok_or(TransformationFailure::Malformed)?;
        let candidates: Vec<argus_application::ContentDependencyCandidate> = entries
            .iter()
            .filter(|candidate| candidate.parent_source_entry_id() == Some(parent_id))
            .map(|candidate| {
                argus_application::ContentDependencyCandidate::new(
                    candidate.clone(),
                    candidate.display_location().to_owned(),
                )
            })
            .collect();
        let dependencies = argus_application::resolve_content_dependencies(
            entry.display_location(),
            descriptor.dependencies(),
            &candidates,
        )
        .map_err(|error| match error {
            argus_application::OpticalDependencyError::ResourceLimitExceeded => {
                TransformationFailure::ResourceLimitExceeded
            }
            argus_application::OpticalDependencyError::Missing
            | argus_application::OpticalDependencyError::Ambiguous
            | argus_application::OpticalDependencyError::Duplicate => {
                TransformationFailure::MissingDependency
            }
            argus_application::OpticalDependencyError::InvalidReference
            | argus_application::OpticalDependencyError::CrossRoot => {
                TransformationFailure::UnsupportedFeature
            }
        })?;

        let mut readers: Vec<Box<dyn ContentReader>> = Vec::with_capacity(dependencies.len());
        for dependency in &dependencies {
            readers.push(resolver.open(dependency, session)?);
        }
        let dependency_bytes = readers.iter().try_fold(0_u64, |total, reader| {
            total
                .checked_add(
                    reader
                        .len()
                        .map_err(|_| TransformationFailure::ReadFailure)?,
                )
                .ok_or(TransformationFailure::ResourceLimitExceeded)
        })?;
        session.charge_parser_work(dependency_bytes)?;

        let recognition = {
            let mut sources = Vec::with_capacity(readers.len());
            for (name, reader) in descriptor.dependencies().iter().zip(readers.iter_mut()) {
                sources.push(argus_infrastructure::content::OpticalSource::new(
                    name.clone(),
                    &mut **reader,
                ));
            }
            argus_infrastructure::content::canonicalize_descriptor_with_cancel(
                &descriptor,
                &mut sources,
                is_cancelled,
            )
            .map_err(map_optical_failure)?
        };
        session.check_cancelled()?;
        let Some(identity) = catalog.select_identity(
            recognition.platform(),
            recognition.content_type(),
            recognition.source_representation(),
            recognition.identity_digest(),
        ) else {
            return Err(TransformationFailure::UnsupportedFeature);
        };

        let mut provenance = Vec::with_capacity(dependencies.len() + 1);
        for (index, dependency) in dependencies.iter().enumerate() {
            let role = if index == 0 {
                ContentProvenanceRole::Primary
            } else {
                ContentProvenanceRole::RequiredData
            };
            provenance.push(ProvenanceMember::new(
                role,
                Some("disc".to_owned()),
                source_version_for_entry(dependency)?,
            ));
        }
        provenance.push(ProvenanceMember::new(
            ContentProvenanceRole::Descriptor,
            Some("disc".to_owned()),
            source_version_for_entry(entry)?,
        ));
        let derivation = ValidatedContentDerivation::try_with_provenance(
            provenance,
            recognition.platform(),
            recognition.content_type(),
            identity.clone(),
            entry.display_name().to_owned(),
        )
        .map_err(|_| TransformationFailure::Malformed)?;
        Ok(Some(ProcessedContentCandidate {
            entry: entry.clone(),
            identity,
            derivation,
            platform: recognition.platform(),
            content_type: recognition.content_type(),
            optical_dependency_ids: dependencies
                .iter()
                .map(SourceEntryRecord::source_entry_id)
                .collect(),
        }))
    }

    fn recognize_source_reader(
        &self,
        entry: &SourceEntryRecord,
        reader: &mut dyn ContentReader,
        session: &mut ParsingSession<'_>,
        catalog: &IdentitySchemeCatalog,
        is_cancelled: &dyn Fn() -> bool,
    ) -> Result<Option<ProcessedContentCandidate>, TransformationFailure> {
        let source_length = reader
            .len()
            .map_err(|_| TransformationFailure::ReadFailure)?;
        session.validate_representation_length(source_length)?;
        if let Some(recognition) =
            argus_infrastructure::content::recognize_alternate_optical(reader, session)
                .map_err(map_optical_failure)?
        {
            ensure_reader_stable(reader)?;
            return self.make_optical_candidate(entry, recognition, catalog);
        }

        session.charge_parser_work(source_length)?;
        let native = match argus_infrastructure::content::recognize_native_optical_with_cancel(
            reader,
            is_cancelled,
        ) {
            Ok(recognition) => Some(recognition),
            Err(OpticalError::Cancelled) => return Err(TransformationFailure::Cancelled),
            Err(OpticalError::ResourceLimitExceeded) => {
                return Err(TransformationFailure::ResourceLimitExceeded);
            }
            Err(OpticalError::AmbiguousPlatform) => {
                return Err(TransformationFailure::AmbiguousRecognition);
            }
            Err(OpticalError::ReadFailure) => return Err(TransformationFailure::ReadFailure),
            Err(_) => None,
        };
        if let Some(recognition) = native {
            ensure_reader_stable(reader)?;
            return self.make_optical_candidate(entry, recognition, catalog);
        }

        let recognition = match argus_infrastructure::content::recognize_content(reader) {
            Ok(recognition) => recognition,
            Err(ContentRecognitionError::ResourceLimitExceeded) => {
                return Err(TransformationFailure::ResourceLimitExceeded);
            }
            Err(ContentRecognitionError::AmbiguousContentRecognition) => {
                return Err(TransformationFailure::AmbiguousRecognition);
            }
            Err(ContentRecognitionError::ReadFailure) => {
                return Err(TransformationFailure::ReadFailure);
            }
            Err(_) => return Ok(None),
        };
        if !reader
            .source_version_is_unchanged()
            .map_err(|_| TransformationFailure::ReadFailure)?
        {
            return Err(TransformationFailure::SourceChanged);
        }
        let Some(identity) = catalog.select_identity(
            recognition.platform(),
            recognition.content_type(),
            recognition.source_representation(),
            recognition.identity_digest(),
        ) else {
            return Err(TransformationFailure::UnsupportedFeature);
        };
        if !self
            .transformation_registry()
            .supports(recognition.source_representation())
        {
            return Err(TransformationFailure::UnsupportedFeature);
        }
        let source_version = source_version_for_entry(entry)?;
        let derivation = ValidatedContentDerivation::new(
            entry.source_entry_id(),
            source_version,
            recognition.platform(),
            recognition.content_type(),
            identity.clone(),
            "raw".to_owned(),
            entry.display_name().to_owned(),
        );
        Ok(Some(ProcessedContentCandidate {
            entry: entry.clone(),
            identity,
            derivation,
            platform: recognition.platform(),
            content_type: recognition.content_type(),
            optical_dependency_ids: Vec::new(),
        }))
    }

    fn make_optical_candidate(
        &self,
        entry: &SourceEntryRecord,
        recognition: OpticalRecognition,
        catalog: &IdentitySchemeCatalog,
    ) -> Result<Option<ProcessedContentCandidate>, TransformationFailure> {
        if !self
            .transformation_registry()
            .supports(recognition.source_representation())
        {
            return Err(TransformationFailure::UnsupportedFeature);
        }
        let Some(identity) = catalog.select_identity(
            recognition.platform(),
            recognition.content_type(),
            recognition.source_representation(),
            recognition.identity_digest(),
        ) else {
            return Err(TransformationFailure::UnsupportedFeature);
        };
        let source_version = source_version_for_entry(entry)?;
        let derivation = ValidatedContentDerivation::new(
            entry.source_entry_id(),
            source_version,
            recognition.platform(),
            recognition.content_type(),
            identity.clone(),
            "optical".to_owned(),
            entry.display_name().to_owned(),
        );
        Ok(Some(ProcessedContentCandidate {
            entry: entry.clone(),
            identity,
            derivation,
            platform: recognition.platform(),
            content_type: recognition.content_type(),
            optical_dependency_ids: Vec::new(),
        }))
    }

    /// transaction. Identification rechecks the persisted source version in
    /// its own short transaction, and hydration then commits each content unit
    /// through the existing coordinator.
    pub(crate) fn refresh_committed_root_with_context(
        &self,
        plan: &argus_application::LibraryScanExecutionPlan,
        context: &OperationContext,
        sessions: &mut [Box<dyn EnrichmentProviderSession>],
        parsing_session: &mut ParsingSession<'_>,
        timestamps: ContentRefreshTimestamps,
        is_cancelled: &dyn Fn() -> bool,
    ) -> Result<(usize, u64), ApplicationError> {
        if is_cancelled() {
            return Err(cancelled_sources_error(context.trace_id()));
        }
        let access = LocalFilesystemSourceAccess::new(plan.root_locator());
        let resolved_root = access.resolve_root().map_err(|_| {
            application_error_from_code(
                ErrorCode::FilesystemInvalidRootSelection,
                context.trace_id(),
            )
        })?;
        let mut entries = self.list_committed_scan_files_with_context(plan, context)?;
        let catalog = IdentitySchemeCatalog::production();
        let mut game_ids = Vec::new();
        let mut optical_sources = Vec::new();
        let mut playlist_entries = Vec::new();
        let mut derived_playlist_groups = Vec::new();
        let mut issue_count = 0_u64;
        let mut transformation_issue_codes = Vec::new();
        let mut transformed_source_entries = std::collections::HashSet::new();

        // Process every non-relationship provider file through the same source
        // graph. Provider-native files are identified here as well, while
        // generic containers first reconcile their complete derived scopes and
        // apply the single-game admission rule before convergence.
        let provider_entries = entries.clone();
        for entry in &provider_entries {
            if entry.kind() != SourceEntryKind::File
                || is_m3u_entry(entry)
                || is_optical_descriptor_entry(entry)
            {
                continue;
            }
            transformed_source_entries.insert(entry.source_entry_id());
            match self.process_source_tree(
                plan,
                context,
                &access,
                &resolved_root,
                entry,
                &mut entries,
                parsing_session,
                timestamps.derived_observed_at_seconds,
                &catalog,
                is_cancelled,
            ) {
                Ok(result) => {
                    transformation_issue_codes.extend(result.issue_codes);
                    derived_playlist_groups.extend(result.derived_playlists);
                    for candidate in result.candidates {
                        match self.identify_committed_source_entry_with_context(
                            candidate.derivation.clone(),
                            context,
                        ) {
                            Ok(outcome) => {
                                let (game_content_id, game_id) = convergence_ids(outcome);
                                add_game_id(&mut game_ids, game_id);
                                if is_optical_content(candidate.content_type) {
                                    for source_entry_id in
                                        std::iter::once(candidate.entry.source_entry_id())
                                            .chain(candidate.optical_dependency_ids.iter().copied())
                                    {
                                        add_optical_source(
                                            &mut optical_sources,
                                            source_entry_id,
                                            game_content_id,
                                            candidate.platform,
                                        );
                                    }
                                }
                            }
                            Err(_) => issue_count = issue_count.saturating_add(1),
                        }
                    }
                }
                Err(TransformationFailure::Cancelled) if is_cancelled() => {
                    return Err(cancelled_sources_error(context.trace_id()));
                }
                Err(failure) => {
                    if matches!(failure, TransformationFailure::Cancelled) {
                        return Err(cancelled_sources_error(context.trace_id()));
                    }
                    transformation_issue_codes.push(map_transformation_failure(failure));
                }
            }
        }

        for entry in &entries {
            if is_cancelled() {
                return Err(cancelled_sources_error(context.trace_id()));
            }
            if transformed_source_entries.contains(&entry.source_entry_id()) {
                continue;
            }
            if matches!(
                entry.coordinates(),
                argus_application::SourceEntryCoordinates::Derived { .. }
            ) {
                continue;
            }
            if is_m3u_entry(entry) {
                playlist_entries.push(entry.clone());
                continue;
            }

            let Some(entry_locator) = entry.relative_locator() else {
                issue_count = issue_count.saturating_add(1);
                continue;
            };

            if is_optical_descriptor_entry(entry) {
                let resolver = ContentSourceResolver::new(&access, &resolved_root, &entries);
                let mut descriptor_reader = match resolver.open(entry, parsing_session) {
                    Ok(reader) => reader,
                    Err(TransformationFailure::Cancelled) => {
                        return Err(cancelled_sources_error(context.trace_id()));
                    }
                    Err(_) => {
                        issue_count = issue_count.saturating_add(1);
                        continue;
                    }
                };
                let descriptor_bytes =
                    match read_content_bytes(&mut *descriptor_reader, 1024 * 1024, parsing_session)
                    {
                        Ok(bytes) => bytes,
                        Err(TransformationFailure::Cancelled) => {
                            return Err(cancelled_sources_error(context.trace_id()));
                        }
                        Err(_) => {
                            issue_count = issue_count.saturating_add(1);
                            continue;
                        }
                    };
                let descriptor =
                    match argus_infrastructure::content::parse_descriptor(&descriptor_bytes) {
                        Ok(descriptor) => descriptor,
                        Err(_) => {
                            if is_cancelled() {
                                return Err(cancelled_sources_error(context.trace_id()));
                            }
                            issue_count = issue_count.saturating_add(1);
                            continue;
                        }
                    };
                let resolved_dependencies = match argus_application::resolve_optical_dependencies(
                    entry_locator,
                    descriptor.dependencies(),
                    &entries,
                ) {
                    Ok(dependencies) => dependencies,
                    Err(_) => {
                        issue_count = issue_count.saturating_add(1);
                        continue;
                    }
                };
                let mut readers: Vec<Box<dyn ContentReader>> =
                    Vec::with_capacity(resolved_dependencies.len());
                let mut opened = true;
                for dependency in &resolved_dependencies {
                    match resolver.open(dependency, parsing_session) {
                        Ok(reader) => readers.push(reader),
                        Err(TransformationFailure::Cancelled) => {
                            return Err(cancelled_sources_error(context.trace_id()));
                        }
                        Err(_) => {
                            opened = false;
                            break;
                        }
                    }
                }
                if !opened {
                    issue_count = issue_count.saturating_add(1);
                    continue;
                }
                let recognition = {
                    let mut sources = Vec::with_capacity(readers.len());
                    for (name, reader) in descriptor.dependencies().iter().zip(readers.iter_mut()) {
                        sources.push(argus_infrastructure::content::OpticalSource::new(
                            name.clone(),
                            &mut **reader,
                        ));
                    }
                    match argus_infrastructure::content::canonicalize_descriptor_with_cancel(
                        &descriptor,
                        &mut sources,
                        is_cancelled,
                    ) {
                        Ok(recognition) => recognition,
                        Err(argus_infrastructure::content::OpticalError::Cancelled) => {
                            return Err(cancelled_sources_error(context.trace_id()));
                        }
                        Err(_) => {
                            issue_count = issue_count.saturating_add(1);
                            continue;
                        }
                    }
                };
                if !ensure_reader_stable(&*descriptor_reader).is_ok()
                    || readers
                        .iter()
                        .any(|reader| !ensure_reader_stable(&**reader).is_ok())
                {
                    issue_count = issue_count.saturating_add(1);
                    continue;
                }
                let Some(identity) = catalog.select_identity(
                    recognition.platform(),
                    recognition.content_type(),
                    recognition.source_representation(),
                    recognition.identity_digest(),
                ) else {
                    issue_count = issue_count.saturating_add(1);
                    continue;
                };
                let mut provenance = Vec::with_capacity(readers.len() + 1);
                for (index, dependency) in resolved_dependencies.iter().enumerate() {
                    let role = if index == 0 {
                        ContentProvenanceRole::Primary
                    } else {
                        ContentProvenanceRole::RequiredData
                    };
                    provenance.push(ProvenanceMember::new(
                        role,
                        Some("disc".to_owned()),
                        source_version_for_entry(dependency).map_err(|_| {
                            application_error_from_code(
                                ErrorCode::InternalInvariantViolation,
                                context.trace_id(),
                            )
                        })?,
                    ));
                }
                provenance.push(ProvenanceMember::new(
                    ContentProvenanceRole::Descriptor,
                    Some("disc".to_owned()),
                    source_version_for_entry(entry).map_err(|_| {
                        application_error_from_code(
                            ErrorCode::InternalInvariantViolation,
                            context.trace_id(),
                        )
                    })?,
                ));
                let derivation = ValidatedContentDerivation::try_with_provenance(
                    provenance,
                    recognition.platform(),
                    recognition.content_type(),
                    identity,
                    entry.display_name().to_owned(),
                )
                .expect("descriptor provenance is non-empty");
                let outcome =
                    match self.identify_committed_source_entry_with_context(derivation, context) {
                        Ok(outcome) => outcome,
                        Err(_) => {
                            issue_count = issue_count.saturating_add(1);
                            continue;
                        }
                    };
                let (game_content_id, game_id) = convergence_ids(outcome);
                add_game_id(&mut game_ids, game_id);
                for source_id in std::iter::once(entry.source_entry_id()).chain(
                    resolved_dependencies
                        .iter()
                        .map(SourceEntryRecord::source_entry_id),
                ) {
                    add_optical_source(
                        &mut optical_sources,
                        source_id,
                        game_content_id,
                        recognition.platform(),
                    );
                }
                continue;
            }

            let mut reader = match access.open_entry_reader(&resolved_root, entry_locator) {
                Ok(reader) => reader,
                Err(_) => {
                    issue_count = issue_count.saturating_add(1);
                    continue;
                }
            };
            let native_optical =
                match argus_infrastructure::content::recognize_native_optical_with_cancel(
                    &mut reader,
                    is_cancelled,
                ) {
                    Ok(recognized) => Some(recognized),
                    Err(argus_infrastructure::content::OpticalError::Cancelled) => {
                        return Err(cancelled_sources_error(context.trace_id()));
                    }
                    Err(_) => None,
                };
            if let Some(recognized) = native_optical {
                if !reader.source_version_is_unchanged().unwrap_or(false) {
                    issue_count = issue_count.saturating_add(1);
                    continue;
                }
                let Some(identity) = catalog.select_identity(
                    recognized.platform(),
                    recognized.content_type(),
                    recognized.source_representation(),
                    recognized.identity_digest(),
                ) else {
                    issue_count = issue_count.saturating_add(1);
                    continue;
                };
                let derivation = ValidatedContentDerivation::try_with_provenance(
                    vec![ProvenanceMember::new(
                        ContentProvenanceRole::Primary,
                        Some("raw".to_owned()),
                        SourceVersionEvidence::new(
                            entry.source_entry_id(),
                            Some(reader.source_fingerprint().to_owned()),
                            entry.last_observed_scan_id(),
                        ),
                    )],
                    recognized.platform(),
                    recognized.content_type(),
                    identity,
                    entry.display_name().to_owned(),
                )
                .expect("raw optical provenance is non-empty");
                let outcome =
                    match self.identify_committed_source_entry_with_context(derivation, context) {
                        Ok(outcome) => outcome,
                        Err(_) => {
                            issue_count = issue_count.saturating_add(1);
                            continue;
                        }
                    };
                let (game_content_id, game_id) = convergence_ids(outcome);
                add_game_id(&mut game_ids, game_id);
                add_optical_source(
                    &mut optical_sources,
                    entry.source_entry_id(),
                    game_content_id,
                    recognized.platform(),
                );
                continue;
            }

            let recognized = match argus_infrastructure::content::recognize_content(&mut reader) {
                Ok(recognized) => recognized,
                Err(_) => {
                    issue_count = issue_count.saturating_add(1);
                    continue;
                }
            };
            if !reader.source_version_is_unchanged().unwrap_or(false) {
                issue_count = issue_count.saturating_add(1);
                continue;
            }
            let Some(identity) = catalog.select_identity(
                recognized.platform(),
                recognized.content_type(),
                recognized.source_representation(),
                recognized.identity_digest(),
            ) else {
                issue_count = issue_count.saturating_add(1);
                continue;
            };
            let derivation = ValidatedContentDerivation::new(
                entry.source_entry_id(),
                SourceVersionEvidence::new(
                    entry.source_entry_id(),
                    Some(reader.source_fingerprint().to_owned()),
                    entry.last_observed_scan_id(),
                ),
                recognized.platform(),
                recognized.content_type(),
                identity,
                "raw".to_owned(),
                entry.display_name().to_owned(),
            );
            let outcome =
                match self.identify_committed_source_entry_with_context(derivation, context) {
                    Ok(outcome) => outcome,
                    Err(_) => {
                        issue_count = issue_count.saturating_add(1);
                        continue;
                    }
                };
            let (_, game_id) = convergence_ids(outcome);
            add_game_id(&mut game_ids, game_id);
        }

        let mut active_playlists = Vec::new();
        for playlist in &playlist_entries {
            if is_cancelled() {
                return Err(cancelled_sources_error(context.trace_id()));
            }
            let Some(playlist_locator) = playlist.relative_locator() else {
                issue_count = issue_count.saturating_add(1);
                continue;
            };
            let resolver = ContentSourceResolver::new(&access, &resolved_root, &entries);
            let mut playlist_reader = match resolver.open(playlist, parsing_session) {
                Ok(reader) => reader,
                Err(TransformationFailure::Cancelled) => {
                    return Err(cancelled_sources_error(context.trace_id()));
                }
                Err(_) => {
                    issue_count = issue_count.saturating_add(1);
                    continue;
                }
            };
            let bytes =
                match read_content_bytes(&mut *playlist_reader, 1024 * 1024, parsing_session) {
                    Ok(bytes) => bytes,
                    Err(TransformationFailure::Cancelled) => {
                        return Err(cancelled_sources_error(context.trace_id()));
                    }
                    Err(_) => {
                        issue_count = issue_count.saturating_add(1);
                        continue;
                    }
                };
            let parsed =
                match argus_infrastructure::content::parse_m3u(&bytes).map_err(map_m3u_error) {
                    Ok(parsed) => parsed,
                    Err(TransformationFailure::Cancelled) => {
                        return Err(cancelled_sources_error(context.trace_id()));
                    }
                    Err(_) => {
                        issue_count = issue_count.saturating_add(1);
                        continue;
                    }
                };
            let resolved_members = match argus_application::resolve_optical_dependencies(
                playlist_locator,
                parsed.members(),
                &entries,
            ) {
                Ok(members) => members,
                Err(_) => {
                    issue_count = issue_count.saturating_add(1);
                    continue;
                }
            };
            let mut member_platform = None;
            let mut grouping_members = Vec::with_capacity(resolved_members.len());
            let mut valid = true;
            for (ordinal, member_entry) in resolved_members.iter().enumerate() {
                let Some(source) = optical_sources
                    .iter()
                    .find(|source| source.source_entry_id == member_entry.source_entry_id())
                else {
                    valid = false;
                    break;
                };
                if let Some(expected) = member_platform {
                    if expected != source.platform {
                        valid = false;
                        break;
                    }
                } else {
                    member_platform = Some(source.platform);
                }
                grouping_members.push(M3uGroupingMember::new(
                    source.game_content_id,
                    match source_version_for_entry(member_entry) {
                        Ok(version) => version,
                        Err(_) => {
                            valid = false;
                            break;
                        }
                    },
                    ordinal as u32,
                ));
            }
            if !valid {
                issue_count = issue_count.saturating_add(1);
                continue;
            }
            if !ensure_reader_stable(&*playlist_reader).is_ok() {
                issue_count = issue_count.saturating_add(1);
                continue;
            }
            let grouping = match ValidatedM3uGrouping::new(
                match source_version_for_entry(playlist) {
                    Ok(version) => version,
                    Err(_) => {
                        issue_count = issue_count.saturating_add(1);
                        continue;
                    }
                },
                grouping_members,
            ) {
                Ok(grouping) => grouping,
                Err(_) => {
                    issue_count = issue_count.saturating_add(1);
                    continue;
                }
            };
            let grouping_result = self.unit_of_work.execute(context, move |mut work| {
                let game_id = {
                    let mut logical = work.logical_content();
                    logical
                        .apply_m3u_grouping(&grouping)
                        .map_err(ApplicationPortError::Persistence)?
                };
                work.commit()?;
                Ok(game_id)
            });
            match grouping_result {
                Ok(game_id) => {
                    add_game_id(&mut game_ids, game_id);
                    active_playlists.push(playlist.source_entry_id());
                }
                Err(_) => {
                    issue_count = issue_count.saturating_add(1);
                }
            }
        }

        for playlist in &derived_playlist_groups {
            if is_cancelled() {
                return Err(cancelled_sources_error(context.trace_id()));
            }
            let mut member_platform = None;
            let mut grouping_members = Vec::with_capacity(playlist.members.len());
            let mut valid = true;
            for (ordinal, member_entry) in playlist.members.iter().enumerate() {
                let Some(source) = optical_sources
                    .iter()
                    .find(|source| source.source_entry_id == member_entry.source_entry_id())
                else {
                    valid = false;
                    break;
                };
                if let Some(expected) = member_platform {
                    if expected != source.platform {
                        valid = false;
                        break;
                    }
                } else {
                    member_platform = Some(source.platform);
                }
                let source_version = match source_version_for_entry(member_entry) {
                    Ok(version) => version,
                    Err(_) => {
                        valid = false;
                        break;
                    }
                };
                grouping_members.push(M3uGroupingMember::new(
                    source.game_content_id,
                    source_version,
                    ordinal as u32,
                ));
            }
            if !valid {
                issue_count = issue_count.saturating_add(1);
                continue;
            }
            let playlist_version = match source_version_for_entry(&playlist.playlist) {
                Ok(version) => version,
                Err(_) => {
                    issue_count = issue_count.saturating_add(1);
                    continue;
                }
            };
            let grouping = match ValidatedM3uGrouping::new(playlist_version, grouping_members) {
                Ok(grouping) => grouping,
                Err(_) => {
                    issue_count = issue_count.saturating_add(1);
                    continue;
                }
            };
            let grouping_result = self.unit_of_work.execute(context, move |mut work| {
                let game_id = {
                    let mut logical = work.logical_content();
                    logical
                        .apply_m3u_grouping(&grouping)
                        .map_err(ApplicationPortError::Persistence)?
                };
                work.commit()?;
                Ok(game_id)
            });
            match grouping_result {
                Ok(game_id) => {
                    add_game_id(&mut game_ids, game_id);
                    active_playlists.push(playlist.playlist.source_entry_id());
                }
                Err(_) => issue_count = issue_count.saturating_add(1),
            }
        }

        let active_playlists_for_reconcile = active_playlists.clone();
        if self
            .unit_of_work
            .execute(context, move |mut work| {
                {
                    let mut logical = work.logical_content();
                    logical
                        .reconcile_m3u_grouping_evidence(&active_playlists_for_reconcile)
                        .map_err(ApplicationPortError::Persistence)?;
                }
                work.commit()?;
                Ok(())
            })
            .is_err()
        {
            issue_count = issue_count.saturating_add(1);
        }

        // Grouping may redirect one or more provisional Games to the stable
        // survivor. Resolve those identities before hydration so every
        // identified optical Game reaches the existing provider path exactly
        // once and redirected historical IDs do not become false issues.
        let mut hydration_game_ids = Vec::new();
        for game_id in game_ids {
            if is_cancelled() {
                return Err(cancelled_sources_error(context.trace_id()));
            }
            match self.get_game_with_context(game_id, context) {
                Ok(GetGameResult::Found(detail)) => {
                    add_game_id(&mut hydration_game_ids, detail.game_id());
                }
                Ok(GetGameResult::Redirected(canonical_game_id)) => {
                    add_game_id(&mut hydration_game_ids, canonical_game_id);
                }
                Ok(GetGameResult::NotFound) | Err(_) => {
                    issue_count = issue_count.saturating_add(1);
                }
            }
        }

        for game_id in &hydration_game_ids {
            if is_cancelled() {
                return Err(cancelled_sources_error(context.trace_id()));
            }
            match self.hydrate_committed_game_with_context(
                *game_id,
                context,
                sessions,
                timestamps.now_millis,
            ) {
                Ok(game_issues) => {
                    issue_count = issue_count.saturating_add(game_issues);
                }
                Err(_) => {
                    issue_count = issue_count.saturating_add(1);
                }
            }
        }
        issue_count = issue_count.saturating_add(transformation_issue_codes.len() as u64);
        Ok((hydration_game_ids.len(), issue_count))
    }

    pub(crate) fn create_enrichment_sessions(&self) -> Vec<Box<dyn EnrichmentProviderSession>> {
        (self.provider_session_factory)()
    }

    fn list_committed_scan_files_with_context(
        &self,
        plan: &argus_application::LibraryScanExecutionPlan,
        context: &OperationContext,
    ) -> Result<Vec<SourceEntryRecord>, ApplicationError> {
        let root_id = plan.library_root_id();
        let scan_id = plan.scan_run_id();
        self.unit_of_work
            .execute(context, move |mut work| {
                let mut pending = std::collections::VecDeque::from([None]);
                let mut files = Vec::new();
                while let Some(parent) = pending.pop_front() {
                    let mut offset = 0_u32;
                    loop {
                        let page = {
                            let mut source_entries = work.source_entries();
                            source_entries
                                .list_children(root_id, parent, offset, 500)
                                .map_err(ApplicationPortError::Persistence)?
                        };
                        let page_len = page.len();
                        for entry in page {
                            if entry.kind() == SourceEntryKind::Directory {
                                pending.push_back(Some(entry.source_entry_id()));
                            } else if entry.kind() == SourceEntryKind::File
                                && entry.last_observed_scan_id() == scan_id
                            {
                                files.push(entry);
                            }
                        }
                        if page_len < 500 {
                            break;
                        }
                        offset = offset.saturating_add(page_len as u32);
                    }
                }
                work.commit()?;
                Ok(files)
            })
            .map_err(|error| map_application_port_error(context.trace_id(), error))
    }

    fn identify_committed_source_entry_with_context(
        &self,
        derivation: ValidatedContentDerivation,
        context: &OperationContext,
    ) -> Result<ConvergenceOutcome, ApplicationError> {
        let identification_context = context.clone();
        self.unit_of_work
            .execute(context, move |mut work| {
                let outcome = {
                    let mut logical = work.logical_content();
                    IdentificationService::converge(
                        &mut logical,
                        derivation,
                        identification_context,
                    )
                    .map_err(|error| {
                        if error.code == ErrorCode::OperationSourceChangedDuringProcessing {
                            ApplicationPortError::Persistence(PersistenceError::Conflict)
                        } else {
                            ApplicationPortError::Persistence(PersistenceError::Internal)
                        }
                    })?
                };
                work.commit()?;
                Ok(outcome)
            })
            .map_err(|error| map_application_port_error(context.trace_id(), error))
    }

    fn hydrate_committed_game_with_context(
        &self,
        game_id: GameId,
        context: &OperationContext,
        sessions: &mut [Box<dyn EnrichmentProviderSession>],
        now: i64,
    ) -> Result<u64, ApplicationError> {
        let detail = match self.get_game_with_context(game_id, context)? {
            GetGameResult::Found(detail) => detail,
            GetGameResult::Redirected(_) | GetGameResult::NotFound => {
                return Err(application_error_from_code(
                    ErrorCode::ConfigurationGameNotFound,
                    context.trace_id(),
                ));
            }
        };
        let mut issue_count = 0_u64;
        for content in detail.content() {
            if content.identification() != argus_domain::IdentificationState::Identified {
                continue;
            }
            let Some(identity) = content.identity() else {
                continue;
            };
            let target = HydrationTarget::new(
                detail.game_id(),
                content.game_content_id(),
                content.platform_id(),
                hex_encode_bytes(&identity.digest().as_bytes()),
                content.platform_id().as_str(),
            )
            .with_observed_at(now);
            match self
                .hydrate_game_content_with_sessions_with_context(target, context, now, sessions)
            {
                Ok(report) => {
                    issue_count = issue_count.saturating_add(report.issues().len() as u64);
                }
                Err(_) => {
                    issue_count = issue_count.saturating_add(1);
                }
            }
        }
        Ok(issue_count)
    }

    /// Refreshes every currently identified content member of one bounded
    /// logical Game through the existing hydration capability. The method only
    /// assembles committed target facts; provider matching, metadata policy,
    /// and artwork policy remain owned by the hydration subsystem.
    pub fn refresh_game_with_context(
        &self,
        game_id: GameId,
        context: &OperationContext,
        now: i64,
    ) -> Result<u64, ApplicationError> {
        let detail = match self.get_game_with_context(game_id, context)? {
            GetGameResult::Found(detail) => detail,
            GetGameResult::Redirected(_) | GetGameResult::NotFound => {
                return Err(application_error_from_code(
                    ErrorCode::ConfigurationGameNotFound,
                    context.trace_id(),
                ));
            }
        };
        let mut issue_count = 0_u64;
        for content in detail.content() {
            if content.identification() != argus_domain::IdentificationState::Identified {
                continue;
            }
            let Some(identity) = content.identity() else {
                continue;
            };
            let target = HydrationTarget::new(
                detail.game_id(),
                content.game_content_id(),
                content.platform_id(),
                hex_encode_bytes(&identity.digest().as_bytes()),
                content.platform_id().as_str(),
            )
            .with_observed_at(now);
            let report = self.hydrate_game_content_with_context(target, context, now)?;
            issue_count = issue_count.saturating_add(report.issues().len() as u64);
        }
        Ok(issue_count)
    }

    /// Resolves every identified content member of one logical Game from
    /// committed mappings, provider metadata, and artwork references.
    ///
    /// This pass deliberately stops at local persistence. It does not create
    /// provider sessions, perform matching, fetch metadata, or download
    /// artwork. The existing hydration coordinator remains the authority for
    /// deterministic metadata and artwork selection.
    pub fn resolve_game_with_context(
        &self,
        game_id: GameId,
        context: &OperationContext,
        now: i64,
    ) -> Result<u64, ApplicationError> {
        let detail = match self.get_game_with_context(game_id, context)? {
            GetGameResult::Found(detail) => detail,
            GetGameResult::Redirected(_) | GetGameResult::NotFound => {
                return Err(application_error_from_code(
                    ErrorCode::ConfigurationGameNotFound,
                    context.trace_id(),
                ));
            }
        };
        let content_facts = detail
            .content()
            .iter()
            .filter_map(|content| {
                if content.identification() != argus_domain::IdentificationState::Identified {
                    return None;
                }
                let identity = content.identity()?;
                Some((
                    content.game_content_id(),
                    content.platform_id(),
                    hex_encode_bytes(&identity.digest().as_bytes()),
                ))
            })
            .collect::<Vec<_>>();

        let content_facts_for_mappings = content_facts.clone();
        let (metadata_settings, provider_settings, mappings) = self
            .unit_of_work
            .execute(context, move |mut work| {
                let mut metadata = work.metadata();
                let metadata_settings = metadata
                    .settings()
                    .map_err(ApplicationPortError::Persistence)?;
                let provider_settings = metadata
                    .provider_settings()
                    .map_err(ApplicationPortError::Persistence)?;
                let mappings = content_facts_for_mappings
                    .iter()
                    .map(|(game_content_id, _, _)| {
                        metadata
                            .mappings_for_content(*game_content_id)
                            .map(|mappings| (*game_content_id, mappings))
                            .map_err(ApplicationPortError::Persistence)
                    })
                    .collect::<Result<Vec<_>, _>>()?;
                work.commit()?;
                Ok((metadata_settings, provider_settings, mappings))
            })
            .map_err(|error| map_application_port_error(context.trace_id(), error))?;

        let metadata_policy = MetadataResolutionPolicy::new(
            provider_settings.enabled().clone(),
            metadata_settings.preferred_regions().to_vec(),
            metadata_settings.preferred_languages().to_vec(),
        );
        let mut artwork_policy = ArtworkResolutionPolicy::default();
        for provider_id in self.metadata_provider_registry.provider_ids() {
            artwork_policy.set_enabled(
                provider_id,
                provider_settings.enabled().contains(&provider_id),
            );
        }
        artwork_policy.set_locale_preferences(
            metadata_settings.preferred_regions().to_vec(),
            metadata_settings.preferred_languages().to_vec(),
        );

        let coordinator = LibraryRefreshCoordinator::new(self.unit_of_work.clone());
        let mut issue_count = 0_u64;
        for ((game_content_id, platform_id, submitted_identity), (_, existing_mappings)) in
            content_facts.into_iter().zip(mappings)
        {
            let target = HydrationTarget::new(
                detail.game_id(),
                game_content_id,
                platform_id,
                submitted_identity,
                platform_id.as_str(),
            )
            .with_existing_mappings(existing_mappings)
            .with_observed_at(now);
            let report = coordinator
                .resolve_existing(
                    context,
                    target,
                    metadata_policy.clone(),
                    artwork_policy.clone(),
                    now,
                )
                .map_err(|error| map_application_port_error(context.trace_id(), error))?;
            issue_count = issue_count.saturating_add(report.issues().len() as u64);
        }
        Ok(issue_count)
    }

    /// Securely stores and validates a provider credential. The secret is
    /// consumed on a backend worker and no secret-bearing value is returned.
    pub fn set_metadata_provider_credential_with_context(
        &self,
        provider_id: ProviderId,
        secret: Vec<u8>,
        context: &OperationContext,
    ) -> Result<MetadataProviderReadiness, ApplicationError> {
        let executor = self.executor.clone().ok_or_else(|| {
            application_error_from_code(ErrorCode::RuntimeStopped, context.trace_id())
        })?;
        let credential_service = Arc::clone(&self.credential_service);
        let secret = zeroize::Zeroizing::new(secret);
        executor
            .execute_on_worker(context.clone(), move || {
                let mut service = credential_service
                    .lock()
                    .map_err(|_| SqliteExecutorError::Internal)?;
                Ok(service.set_credential(provider_id, secret.as_slice()))
            })
            .map_err(|error| map_sqlite_executor_error(context.trace_id(), error))?
            .map_err(|error| map_credential_mutation_error(context.trace_id(), error))
    }

    /// Removes a provider credential without exposing prior secret state.
    pub fn remove_metadata_provider_credential_with_context(
        &self,
        provider_id: ProviderId,
        context: &OperationContext,
    ) -> Result<MetadataProviderReadiness, ApplicationError> {
        let executor = self.executor.clone().ok_or_else(|| {
            application_error_from_code(ErrorCode::RuntimeStopped, context.trace_id())
        })?;
        let credential_service = Arc::clone(&self.credential_service);
        executor
            .execute_on_worker(context.clone(), move || {
                let mut service = credential_service
                    .lock()
                    .map_err(|_| SqliteExecutorError::Internal)?;
                Ok(service.remove_credential(provider_id))
            })
            .map_err(|error| map_sqlite_executor_error(context.trace_id(), error))?
            .map_err(|error| map_credential_mutation_error(context.trace_id(), error))
    }

    /// Reads one validated immutable artwork object on the backend worker.
    pub fn get_artwork_asset_bytes_with_context(
        &self,
        asset_id: argus_domain::ArtworkAssetId,
        context: &OperationContext,
    ) -> Result<ArtworkAssetBytes, ApplicationError> {
        let executor = self.executor.clone().ok_or_else(|| {
            application_error_from_code(ErrorCode::RuntimeStopped, context.trace_id())
        })?;
        let artwork_store = Arc::clone(&self.artwork_store);
        let result = executor
            .execute_on_worker(context.clone(), move || {
                Ok(artwork_store.read_asset(asset_id))
            })
            .map_err(|error| map_sqlite_executor_error(context.trace_id(), error))?;
        let (asset, bytes) =
            result.map_err(|error| map_artwork_store_error(context.trace_id(), error))?;
        Ok(ArtworkAssetBytes {
            asset_id: asset.asset_id(),
            bytes,
            mime_type: asset.mime_type().to_owned(),
            width: asset.width(),
            height: asset.height(),
        })
    }

    /// Synchronizes current native LocalFilesystem mounts and reconciles root
    /// availability after provider I/O completes.
    pub fn sync_local_filesystem_mounted_volumes_with_context(
        &self,
        command: SyncLocalFilesystemMountedVolumesCommand,
        context: &OperationContext,
    ) -> Result<(), ApplicationError> {
        let collector = PendingEventCollector::new();
        let recorder = collector.recorder();
        let result = self.library_service.sync_local_filesystem_mounted_volumes(
            command,
            context.clone(),
            recorder,
        );
        finalize_library_roots_update(
            result,
            context,
            collector,
            &self.event_bus,
            &self.publication_diagnostics,
        )
    }

    /// Lists the current safe mounted browse roots.
    pub fn list_local_filesystem_browse_roots_with_context(
        &self,
        context: &OperationContext,
    ) -> Result<Vec<LocalFilesystemBrowseRoot>, ApplicationError> {
        self.library_service
            .list_local_filesystem_browse_roots()
            .map_err(|error| application_error_from_provider(context.trace_id(), error))
    }

    /// Lists one current safe direct-child browse page.
    pub fn list_local_filesystem_browse_directories_with_context(
        &self,
        location: &LocalFilesystemBrowseLocation,
        cursor: Option<&LocalFilesystemBrowseCursor>,
        page_size: u32,
        context: &OperationContext,
    ) -> Result<LocalFilesystemBrowsePage, ApplicationError> {
        self.library_service
            .list_local_filesystem_browse_directories(location, cursor, page_size)
            .map_err(|error| application_error_from_provider(context.trace_id(), error))
    }

    /// Reads one authoritative configured root.
    pub fn get_library_root(
        &self,
        root_id: LibraryRootId,
    ) -> Result<LibraryRootProjection, ApplicationError> {
        let context = sources_operation_context("get", self.trace_id);
        self.get_library_root_with_context(root_id, &context)
    }

    /// Reads one authoritative configured root under an admitted context.
    pub fn get_library_root_with_context(
        &self,
        root_id: LibraryRootId,
        context: &OperationContext,
    ) -> Result<LibraryRootProjection, ApplicationError> {
        self.library_service
            .get_library_root(GetLibraryRootQuery::new(root_id), context.clone())
    }

    /// Reads one bounded authoritative direct-child page under an admitted
    /// operation context.
    pub fn list_source_entry_children_with_context(
        &self,
        query: &ListSourceEntryChildrenQuery,
        context: &OperationContext,
    ) -> Result<SourceEntryChildrenPage, ApplicationError> {
        self.library_service
            .list_source_entry_children(query.clone(), context.clone())
    }

    /// Reads one authoritative source-entry detail under an admitted
    /// operation context.
    pub fn get_source_entry_with_context(
        &self,
        source_entry_id: SourceEntryId,
        context: &OperationContext,
    ) -> Result<SourceEntryDetailProjection, ApplicationError> {
        self.library_service
            .get_source_entry(GetSourceEntryQuery::new(source_entry_id), context.clone())
    }

    /// Configures one root-only local library folder and publishes after commit.
    pub fn add_local_library_root(
        &self,
        selection: LocalFilesystemRootSelection,
    ) -> Result<AddLocalLibraryRootResult, ApplicationError> {
        let context = sources_operation_context("add", self.trace_id);
        self.add_local_library_root_with_context(&context, selection, Arc::new(|| false))
    }

    /// Configures one root under an admitted operation context.
    pub fn add_local_library_root_with_context(
        &self,
        context: &OperationContext,
        selection: LocalFilesystemRootSelection,
        is_cancelled: Arc<dyn Fn() -> bool + Send + Sync>,
    ) -> Result<AddLocalLibraryRootResult, ApplicationError> {
        if is_cancelled() {
            return Err(cancelled_sources_error(context.trace_id()));
        }
        let collector = PendingEventCollector::new();
        let recorder = collector.recorder();
        let result = self.library_service.add_local_library_root(
            AddLocalLibraryRootCommand::new(selection),
            context.clone(),
            recorder,
        );
        finalize_library_roots_update(
            result,
            context,
            collector,
            &self.event_bus,
            &self.publication_diagnostics,
        )
    }

    /// Removes one configured root and publishes after commit.
    pub fn remove_library_root(
        &self,
        root_id: LibraryRootId,
    ) -> Result<RemoveLibraryRootResult, ApplicationError> {
        let context = sources_operation_context("remove", self.trace_id);
        self.remove_library_root_with_context(&context, root_id, Arc::new(|| false))
    }

    /// Removes one configured root under an admitted operation context.
    pub fn remove_library_root_with_context(
        &self,
        context: &OperationContext,
        root_id: LibraryRootId,
        is_cancelled: Arc<dyn Fn() -> bool + Send + Sync>,
    ) -> Result<RemoveLibraryRootResult, ApplicationError> {
        if is_cancelled() {
            return Err(cancelled_sources_error(context.trace_id()));
        }
        let collector = PendingEventCollector::new();
        let recorder = collector.recorder();
        let result = self.library_service.remove_library_root(
            RemoveLibraryRootCommand::new(root_id),
            context.clone(),
            recorder,
        );
        finalize_library_roots_update(
            result,
            context,
            collector,
            &self.event_bus,
            &self.publication_diagnostics,
        )
    }

    /// Admits one durable single-root library scan under an admitted context.
    pub fn start_library_scan_with_context(
        &self,
        context: &OperationContext,
        root_id: LibraryRootId,
        is_cancelled: Arc<dyn Fn() -> bool + Send + Sync>,
    ) -> Result<LibraryScanAdmissionResult, ApplicationError> {
        if is_cancelled() {
            return Err(cancelled_sources_error(context.trace_id()));
        }
        let collector = PendingEventCollector::new();
        let recorder = collector.recorder();
        let result = self.library_service.start_library_scan(
            StartLibraryScanCommand::new(root_id),
            context.clone(),
            recorder,
        );
        finalize_library_roots_update(
            result,
            context,
            collector,
            &self.event_bus,
            &self.publication_diagnostics,
        )
    }

    /// Admits one composed Library refresh under the shared focused root-plan
    /// admission boundary. No public Scan-All identity is involved.
    pub fn start_library_refresh_with_context(
        &self,
        context: &OperationContext,
        is_cancelled: Arc<dyn Fn() -> bool + Send + Sync>,
        trigger: argus_application::LibraryRefreshTrigger,
    ) -> Result<LibraryRefreshAdmissionResult, ApplicationError> {
        if is_cancelled() {
            return Err(cancelled_sources_error(context.trace_id()));
        }
        let collector = PendingEventCollector::new();
        let recorder = collector.recorder();
        let result = self.library_service.start_library_refresh(
            RefreshLibraryCommand::new(RefreshMode::EligibleOnly),
            context.clone(),
            recorder,
            trigger,
        );
        finalize_library_roots_update(
            result,
            context,
            collector,
            &self.event_bus,
            &self.publication_diagnostics,
        )
    }

    /// Admits one durable multi-root Scan All under an admitted context.
    pub fn start_library_scan_all_with_context(
        &self,
        context: &OperationContext,
        request_identity: LibraryScanAllRequestIdentity,
        is_cancelled: Arc<dyn Fn() -> bool + Send + Sync>,
    ) -> Result<LibraryScanAllAdmissionResult, ApplicationError> {
        if is_cancelled() {
            return Err(cancelled_sources_error(context.trace_id()));
        }
        let collector = PendingEventCollector::new();
        let recorder = collector.recorder();
        let executor = self
            .executor
            .clone()
            .ok_or_else(|| cancelled_sources_error(context.trace_id()))?;
        let lookup = SqliteJobsQueries::new(executor);
        let result = self.library_service.start_library_scan_all(
            StartLibraryScanAllCommand::new(request_identity),
            context.clone(),
            &lookup,
            recorder,
        );
        finalize_library_roots_update(
            result,
            context,
            collector,
            &self.event_bus,
            &self.publication_diagnostics,
        )
    }

    /// Resolves one durable Scan All request identity to its accepted
    /// admission or authoritative no-admission proof.
    pub fn resolve_scan_all_request_with_context(
        &self,
        context: &OperationContext,
        request_identity: LibraryScanAllRequestIdentity,
    ) -> Result<Option<StartLibraryScanAllResult>, ApplicationError> {
        let executor = self
            .executor
            .clone()
            .ok_or_else(|| cancelled_sources_error(context.trace_id()))?;
        SqliteJobsQueries::new(executor).find_existing(context, &request_identity)
    }

    /// Terminalizes an admitted run whose manager registration failed.
    pub fn fail_unregistered_scan_with_context(
        &self,
        context: &OperationContext,
        root_id: LibraryRootId,
        job_run_id: JobRunId,
    ) -> Result<(), ApplicationError> {
        let collector = PendingEventCollector::new();
        let recorder = collector.recorder();
        let result = self.library_service.fail_unregistered_scan(
            root_id,
            job_run_id,
            context.clone(),
            recorder,
        );
        finalize_library_roots_update(
            result,
            context,
            collector,
            &self.event_bus,
            &self.publication_diagnostics,
        )
    }

    /// Terminalizes a durably admitted non-scan run when background-manager
    /// registration fails before its focused handler can execute.
    pub fn fail_unregistered_job_with_context(
        &self,
        context: &OperationContext,
        job_run_id: JobRunId,
        error_code: ErrorCode,
    ) -> Result<(), ApplicationError> {
        self.unit_of_work
            .clone()
            .execute(context, move |mut work| {
                work.job_runs().set_terminal_failure(
                    job_run_id,
                    JobRunState::Failed,
                    Some(error_code.as_str().to_owned()),
                    None,
                    crate::now_millis(),
                )?;
                work.commit()
            })
            .map_err(|error| map_application_port_error(context.trace_id(), error))
    }

    /// Reads one authoritative job detail under an admitted context.
    pub fn get_job_with_context(
        &self,
        context: &OperationContext,
        job_run_id: JobRunId,
    ) -> Result<JobDetail, ApplicationError> {
        self.jobs_service.get_job(job_run_id, context.clone())
    }

    /// Lists one closed Jobs scope under an admitted context.
    pub fn list_jobs_with_context(
        &self,
        context: &OperationContext,
        query: ListJobsQuery,
    ) -> Result<JobSummaryPage, ApplicationError> {
        self.jobs_service.list_jobs(query, context.clone())
    }

    /// Persists durable cancellation intent under an admitted context.
    pub fn cancel_job_with_context(
        &self,
        context: &OperationContext,
        job_run_id: JobRunId,
    ) -> Result<CancelJobResult, ApplicationError> {
        let collector = PendingEventCollector::new();
        let recorder = collector.recorder();
        let result = self
            .jobs_service
            .cancel_job(job_run_id, context.clone(), recorder);
        finalize_library_roots_update(
            result,
            context,
            collector,
            &self.event_bus,
            &self.publication_diagnostics,
        )
    }

    /// Returns the shared transaction factory used by background workers.
    pub fn unit_of_work_factory(&self) -> &KernelUnitOfWorkFactory {
        &self.unit_of_work
    }

    /// Returns the shared event bus used for post-commit publication.
    pub fn event_bus(&self) -> &Arc<EventBus> {
        &self.event_bus
    }

    /// Replaces only the appearance aggregate with its canonical recovery
    /// value. This deliberately bypasses the normal read-before-write path so
    /// a missing or malformed persisted value can be repaired only after an
    /// explicit generation-bound recovery request.
    pub fn reset_appearance_settings(&self) -> Result<(), ApplicationError> {
        let context = settings_operation_context("reset", self.trace_id);
        self.reset_appearance_settings_with_context(&context)
    }

    /// Resets appearance settings under an explicit recovery operation context.
    pub fn reset_appearance_settings_with_context(
        &self,
        context: &OperationContext,
    ) -> Result<(), ApplicationError> {
        let result = self.execute(context, |mut work| {
            let mut appearance = work.appearance_settings();
            appearance.save(&AppearanceSettings::new(
                argus_application::ThemeMode::System,
            ))?;
            work.commit()
        });
        result.map_err(|error| map_application_port_error(context.trace_id(), error))
    }

    /// Shuts down the worker and consumes the kernel.
    pub fn shutdown(mut self) -> Result<(), KernelShutdownError> {
        #[cfg(test)]
        if self.fail_shutdown {
            return Err(KernelShutdownError::Internal);
        }
        self.executor.take().map_or(Ok(()), |executor| {
            executor
                .shutdown()
                .map_err(|_| KernelShutdownError::Internal)
        })
    }

    /// Test-only seam to force the next shutdown to fail.
    #[cfg(test)]
    pub(crate) fn fail_next_shutdown_for_tests(&mut self) {
        self.fail_shutdown = true;
    }
}

impl UnitOfWorkFactory for KernelBootstrap {
    type Scope<'scope>
        = KernelUnitOfWork<'scope>
    where
        Self: 'scope;

    fn execute<T, F>(
        &self,
        context: &OperationContext,
        operation: F,
    ) -> Result<T, ApplicationPortError>
    where
        T: Send + 'static,
        F: for<'scope> FnOnce(Self::Scope<'scope>) -> Result<T, ApplicationPortError>
            + Send
            + 'static,
    {
        self.unit_of_work.execute(context, operation)
    }
}

impl Drop for KernelBootstrap {
    fn drop(&mut self) {
        if let Some(executor) = self.executor.take() {
            let _ = executor.shutdown();
        }
    }
}

/// Starts the minimum persistence/startup kernel for Phase 000.
pub fn bootstrap_kernel(
    options: KernelBootstrapOptions,
) -> Result<KernelBootstrap, KernelBootstrapFailure> {
    bootstrap_kernel_with_event_bus(options, EventBus::default())
}

/// Starts the kernel with an explicitly composed Phase 000 event bus.
pub fn bootstrap_kernel_with_event_bus(
    options: KernelBootstrapOptions,
    event_bus: EventBus,
) -> Result<KernelBootstrap, KernelBootstrapFailure> {
    let provider_session_factory = options.enrichment_session_factory();
    let trace_id = new_trace_id();
    let context = startup_context(trace_id);
    // Host-standard data (including the Android production root) remains
    // StandardApplicationData; only the explicit test/embedding seam is
    // classified as an override.
    let path_class = if options.data_directory_override.is_some() {
        PathClass::ExplicitOverride
    } else {
        PathClass::StandardApplicationData
    };
    let platform = Platform::current();
    let platform_class = platform_class(platform);
    let architecture = architecture_class();
    let mut collector = StartupCollector::new();
    emit(
        &mut collector,
        &context,
        "runtime.startup.started",
        TraceEventPhase::Started,
        SafeContext::new(),
        None,
        LogLevel::Info,
        None,
    );

    let home = env_path("HOME");
    let local_app_data = env_path("LOCALAPPDATA");
    let xdg_data_home = env_path("XDG_DATA_HOME");
    let data_directory = resolve_data_directory(
        platform,
        home.as_deref(),
        local_app_data.as_deref(),
        xdg_data_home.as_deref(),
        options.data_directory_override,
        options.standard_data_directory,
    )
    .map_err(|_| {
        failure(
            trace_id,
            KernelBootstrapStage::Environment,
            ErrorCode::ConfigurationInvalid,
            TechnicalClass::ConfigurationInvalid,
            path_class,
            platform_class,
            architecture,
            collector.clone(),
        )
    })?;

    std::fs::create_dir_all(&data_directory).map_err(|error| {
        let (code, technical) = if error.kind() == std::io::ErrorKind::PermissionDenied {
            (
                ErrorCode::FilesystemPermissionDenied,
                TechnicalClass::FilesystemPermissionDenied,
            )
        } else {
            (
                ErrorCode::ConfigurationInvalid,
                TechnicalClass::ConfigurationInvalid,
            )
        };
        failure(
            trace_id,
            KernelBootstrapStage::Environment,
            code,
            technical,
            path_class,
            platform_class,
            architecture,
            collector.clone(),
        )
    })?;

    let environment_context = environment_fields(path_class, platform_class, architecture);
    emit(
        &mut collector,
        &context,
        "runtime.startup.environment",
        TraceEventPhase::Completed,
        environment_context,
        None,
        LogLevel::Info,
        None,
    );

    let database_path = data_directory.join("argus.sqlite3");
    let executor = SqliteDatabaseExecutor::open_with_capacity(
        &database_path,
        argus_infrastructure::sqlite::DEFAULT_QUEUE_CAPACITY,
    )
    .map_err(|error| {
        let (code, technical) = error_class(&error);
        failure(
            trace_id,
            KernelBootstrapStage::Persistence,
            code,
            technical,
            path_class,
            platform_class,
            architecture,
            collector.clone(),
        )
    })?;
    let artwork_store =
        ArtworkObjectStore::new(data_directory.join("artwork-assets")).map_err(|_| {
            failure(
                trace_id,
                KernelBootstrapStage::Persistence,
                ErrorCode::ConfigurationInvalid,
                TechnicalClass::ConfigurationInvalid,
                path_class,
                platform_class,
                architecture,
                collector.clone(),
            )
        })?;
    let summary = KernelMigrationSummary::from(executor.migration_summary());
    let settings_service = SettingsService::new(
        SqliteAppearanceSettingsQueries::new(executor.clone()),
        executor.clone(),
    );
    let library_service = LibraryService::new(
        SqliteLibraryRootQueries::new(executor.clone()),
        SqliteSourceEntryQueries::new(executor.clone()),
        executor.clone(),
        InfraLocalFilesystemProvider::default(),
    );
    let unit_of_work = KernelUnitOfWorkFactory::new(executor.clone());
    let jobs_service = JobsService::new(
        SqliteJobsQueries::new(executor.clone()),
        unit_of_work.clone(),
    );
    let mut migration_fields = environment_fields(path_class, platform_class, architecture);
    insert(
        &mut migration_fields,
        SafeContextField::MigrationCount,
        SafeContextValue::MigrationCount(summary.applied_count),
    );
    insert(
        &mut migration_fields,
        SafeContextField::SchemaVersion,
        SafeContextValue::SchemaVersion(summary.current_version),
    );
    insert(
        &mut migration_fields,
        SafeContextField::MigrationOutcome,
        SafeContextValue::MigrationOutcome(match summary.outcome {
            KernelMigrationOutcome::Applied => MigrationOutcome::Applied,
            KernelMigrationOutcome::AlreadyCurrent => MigrationOutcome::AlreadyCurrent,
        }),
    );
    emit(
        &mut collector,
        &context,
        "database.migration.completed",
        TraceEventPhase::Completed,
        migration_fields,
        None,
        LogLevel::Info,
        None,
    );
    emit(
        &mut collector,
        &context,
        "runtime.kernel.initialized",
        TraceEventPhase::Completed,
        SafeContext::new(),
        None,
        LogLevel::Info,
        None,
    );
    Ok(KernelBootstrap {
        trace_id,
        path_class,
        migration_summary: summary,
        executor: Some(executor),
        settings_service,
        library_service,
        jobs_service,
        unit_of_work,
        metadata_provider_registry: MetadataProviderRegistry::production(),
        provider_session_factory,
        credential_service: Arc::new(Mutex::new(MetadataProviderService::new(
            KeyringSecureCredentialStore::new(),
            SteamGridDbCredentialValidator::new(UreqTransport::new(), STEAMGRIDDB_API_BASE_URL),
        ))),
        artwork_store: Arc::new(artwork_store),
        event_bus: Arc::new(event_bus),
        publication_diagnostics: Mutex::new(PublicationDiagnostics::new()),
        transformation_registry: TransformationRegistry::production(),
        transformation_staging_root: data_directory
            .join(argus_infrastructure::content::TRANSFORMATION_STAGING_DIRECTORY),
        collector,
        #[cfg(test)]
        fail_shutdown: false,
    })
}

pub(crate) fn settings_operation_context(
    operation: &'static str,
    startup_trace_id: TraceId,
) -> OperationContext {
    let trace_id = loop {
        let candidate = new_trace_id();
        if candidate != startup_trace_id {
            break candidate;
        }
    };
    OperationContext::new(
        trace_id,
        SubsystemName::try_from("settings").expect("static subsystem is valid"),
        OperationName::try_from(operation).expect("static operation is valid"),
    )
}

pub(crate) fn sources_operation_context(
    operation: &'static str,
    startup_trace_id: TraceId,
) -> OperationContext {
    let trace_id = loop {
        let candidate = new_trace_id();
        if candidate != startup_trace_id {
            break candidate;
        }
    };
    OperationContext::new(
        trace_id,
        SubsystemName::try_from("sources").expect("static subsystem is valid"),
        OperationName::try_from(operation).expect("static operation is valid"),
    )
}

#[derive(Clone, Copy)]
struct OpticalSourceLink {
    source_entry_id: SourceEntryId,
    game_content_id: GameContentId,
    platform: PlatformId,
}

#[derive(Clone, Copy, Debug)]
pub(crate) struct ContentRefreshTimestamps {
    pub(crate) now_millis: i64,
    pub(crate) derived_observed_at_seconds: i64,
}

impl ContentRefreshTimestamps {
    pub(crate) fn from_millis(now_millis: i64) -> Self {
        Self {
            now_millis,
            derived_observed_at_seconds: now_millis.div_euclid(1_000),
        }
    }
}

#[derive(Default)]
struct SourceTreeResult {
    candidates: Vec<ProcessedContentCandidate>,
    derived_playlists: Vec<DerivedPlaylistGroup>,
    issue_codes: Vec<ErrorCode>,
}

impl SourceTreeResult {
    fn empty() -> Self {
        Self {
            candidates: Vec::new(),
            derived_playlists: Vec::new(),
            issue_codes: Vec::new(),
        }
    }
}

struct DerivedPlaylistGroup {
    playlist: SourceEntryRecord,
    members: Vec<SourceEntryRecord>,
}

#[derive(Clone)]
struct ProcessedContentCandidate {
    entry: SourceEntryRecord,
    identity: ContentIdentity,
    derivation: ValidatedContentDerivation,
    platform: PlatformId,
    content_type: ContentType,
    optical_dependency_ids: Vec<SourceEntryId>,
}

fn source_version_for_entry(
    entry: &SourceEntryRecord,
) -> Result<SourceVersionEvidence, TransformationFailure> {
    match entry.coordinates() {
        argus_application::SourceEntryCoordinates::Provider {
            source_fingerprint, ..
        } => Ok(SourceVersionEvidence::provider(
            entry.source_entry_id(),
            source_fingerprint.clone(),
            entry.last_observed_scan_id(),
        )),
        argus_application::SourceEntryCoordinates::Derived {
            derived_fingerprint,
            ..
        } => Ok(SourceVersionEvidence::derived(
            entry.source_entry_id(),
            derived_fingerprint.clone(),
            entry.last_observed_scan_id(),
        )),
    }
}

fn read_content_probe(
    reader: &mut dyn ContentReader,
    source_length: u64,
    requested: usize,
) -> Result<Vec<u8>, TransformationFailure> {
    let length = source_length.min(requested as u64) as usize;
    if length == 0 {
        return Ok(Vec::new());
    }
    let max_read_size = reader.max_read_size();
    if max_read_size == 0 {
        return Err(TransformationFailure::ReadFailure);
    }
    let mut output = vec![0_u8; length];
    let mut offset = 0_usize;
    while offset < output.len() {
        let end = (offset + max_read_size).min(output.len());
        let count = reader
            .read_at(offset as u64, &mut output[offset..end])
            .map_err(|error| match error {
                argus_infrastructure::content::ContentReadError::OutOfRange => {
                    TransformationFailure::Malformed
                }
                argus_infrastructure::content::ContentReadError::RequestTooLarge => {
                    TransformationFailure::ResourceLimitExceeded
                }
                argus_infrastructure::content::ContentReadError::Io => {
                    TransformationFailure::ReadFailure
                }
            })?;
        if count == 0 {
            return Err(TransformationFailure::ReadFailure);
        }
        offset = offset
            .checked_add(count)
            .ok_or(TransformationFailure::ResourceLimitExceeded)?;
    }
    Ok(output)
}

fn read_content_bytes(
    reader: &mut dyn ContentReader,
    max_bytes: usize,
    session: &mut ParsingSession<'_>,
) -> Result<Vec<u8>, TransformationFailure> {
    let length = reader
        .len()
        .map_err(|_| TransformationFailure::ReadFailure)?;
    if length > max_bytes as u64 {
        return Err(TransformationFailure::ResourceLimitExceeded);
    }
    let length =
        usize::try_from(length).map_err(|_| TransformationFailure::ResourceLimitExceeded)?;
    session.charge_parser_work(length as u64)?;
    read_content_probe(reader, length as u64, length)
}

fn ensure_reader_stable(reader: &dyn ContentReader) -> Result<(), TransformationFailure> {
    if reader
        .source_version_is_unchanged()
        .map_err(|_| TransformationFailure::ReadFailure)?
    {
        Ok(())
    } else {
        Err(TransformationFailure::SourceChanged)
    }
}

fn map_optical_failure(error: OpticalError) -> TransformationFailure {
    match error {
        OpticalError::Malformed | OpticalError::Truncated => TransformationFailure::Malformed,
        OpticalError::MissingDependency | OpticalError::ConflictingDependency => {
            TransformationFailure::MissingDependency
        }
        OpticalError::Traversal => TransformationFailure::UnsupportedFeature,
        OpticalError::UnsupportedRepresentation => TransformationFailure::UnsupportedFeature,
        OpticalError::AmbiguousPlatform => TransformationFailure::AmbiguousRecognition,
        OpticalError::ResourceLimitExceeded => TransformationFailure::ResourceLimitExceeded,
        OpticalError::Cancelled => TransformationFailure::Cancelled,
        OpticalError::ReadFailure => TransformationFailure::ReadFailure,
    }
}

fn map_m3u_error(error: argus_infrastructure::content::M3uError) -> TransformationFailure {
    match error {
        argus_infrastructure::content::M3uError::Malformed
        | argus_infrastructure::content::M3uError::InvalidMember
        | argus_infrastructure::content::M3uError::DuplicateMember => {
            TransformationFailure::Malformed
        }
        argus_infrastructure::content::M3uError::ResourceLimitExceeded => {
            TransformationFailure::ResourceLimitExceeded
        }
    }
}

fn is_optical_content(content_type: ContentType) -> bool {
    matches!(
        content_type,
        ContentType::OpticalDiscCd
            | ContentType::OpticalDiscGd
            | ContentType::OpticalDiscDvd
            | ContentType::OpticalDiscGameCube
            | ContentType::OpticalDiscWii
            | ContentType::OpticalDiscUmd
    )
}

fn convergence_ids(outcome: ConvergenceOutcome) -> (GameContentId, GameId) {
    match outcome {
        ConvergenceOutcome::Created {
            game_content_id,
            game_id,
        }
        | ConvergenceOutcome::Attached {
            game_content_id,
            game_id,
        } => (game_content_id, game_id),
    }
}

fn add_game_id(game_ids: &mut Vec<GameId>, game_id: GameId) {
    if !game_ids.contains(&game_id) {
        game_ids.push(game_id);
    }
}

fn add_optical_source(
    sources: &mut Vec<OpticalSourceLink>,
    source_entry_id: SourceEntryId,
    game_content_id: GameContentId,
    platform: PlatformId,
) {
    if sources
        .iter()
        .any(|source| source.source_entry_id == source_entry_id)
    {
        return;
    }
    sources.push(OpticalSourceLink {
        source_entry_id,
        game_content_id,
        platform,
    });
}

fn entry_extension(entry: &SourceEntryRecord) -> Option<String> {
    entry
        .display_name()
        .rsplit_once('.')
        .map(|(_, extension)| extension.to_ascii_lowercase())
}

fn is_optical_descriptor_entry(entry: &SourceEntryRecord) -> bool {
    matches!(entry_extension(entry).as_deref(), Some("cue" | "gdi"))
}

fn is_m3u_entry(entry: &SourceEntryRecord) -> bool {
    matches!(entry_extension(entry).as_deref(), Some("m3u" | "m3u8"))
}

fn cancelled_sources_error(trace_id: TraceId) -> ApplicationError {
    ApplicationError::from_code(ErrorCode::OperationCancelled, trace_id, SafeContext::new())
        .expect("operation cancelled uses an allowlisted empty context")
}

fn application_error_from_provider(trace_id: TraceId, error: ProviderError) -> ApplicationError {
    let code = match error {
        ProviderError::PermissionDenied => ErrorCode::FilesystemPermissionDenied,
        ProviderError::InvalidSelection
        | ProviderError::NotADirectory
        | ProviderError::LinkLikeRoot
        | ProviderError::Unavailable
        | ProviderError::InvalidBrowseRequest => ErrorCode::FilesystemInvalidRootSelection,
        ProviderError::Internal => ErrorCode::InternalUnexpected,
    };
    ApplicationError::from_code(code, trace_id, SafeContext::new())
        .expect("provider browse error uses an allowlisted empty context")
}

pub(crate) fn map_application_port_error(
    trace_id: TraceId,
    error: ApplicationPortError,
) -> ApplicationError {
    let code = match error {
        ApplicationPortError::Persistence(PersistenceError::DatabaseLocked) => {
            ErrorCode::PersistenceDatabaseLocked
        }
        ApplicationPortError::Persistence(PersistenceError::Cancelled) => {
            ErrorCode::OperationCancelled
        }
        ApplicationPortError::Persistence(PersistenceError::MigrationFailed) => {
            ErrorCode::PersistenceMigrationFailed
        }
        ApplicationPortError::Persistence(PersistenceError::CorruptOrIncompatible) => {
            ErrorCode::PersistenceIncompatibleSchema
        }
        ApplicationPortError::Persistence(PersistenceError::PersistedSettingsInvalid(_)) => {
            ErrorCode::ConfigurationPersistedSettingsInvalid
        }
        ApplicationPortError::Persistence(_) | ApplicationPortError::EventRecording => {
            ErrorCode::InternalUnexpected
        }
    };
    ApplicationError::from_code(code, trace_id, SafeContext::new())
        .expect("runtime recovery error uses an allowlisted empty context")
}

fn application_error_from_code(code: ErrorCode, trace_id: TraceId) -> ApplicationError {
    ApplicationError::from_code(code, trace_id, SafeContext::new())
        .expect("runtime bridge error uses an allowlisted empty context")
}

fn map_sqlite_executor_error(trace_id: TraceId, error: SqliteExecutorError) -> ApplicationError {
    let (code, _) = error_class(&error);
    application_error_from_code(code, trace_id)
}

fn map_credential_mutation_error(
    trace_id: TraceId,
    error: CredentialMutationError,
) -> ApplicationError {
    let code = match error {
        CredentialMutationError::StoreUnavailable => {
            ErrorCode::ConfigurationCredentialStoreUnavailable
        }
        CredentialMutationError::UnsupportedProvider => ErrorCode::ProviderConfigurationInvalid,
    };
    application_error_from_code(code, trace_id)
}

fn map_artwork_store_error(
    trace_id: TraceId,
    error: argus_infrastructure::artwork_store::ArtworkObjectStoreError,
) -> ApplicationError {
    let code = match error {
        argus_infrastructure::artwork_store::ArtworkObjectStoreError::NotFound => {
            ErrorCode::FilesystemArtworkAssetNotFound
        }
        argus_infrastructure::artwork_store::ArtworkObjectStoreError::TooLarge
        | argus_infrastructure::artwork_store::ArtworkObjectStoreError::InvalidImage
        | argus_infrastructure::artwork_store::ArtworkObjectStoreError::DimensionsTooLarge
        | argus_infrastructure::artwork_store::ArtworkObjectStoreError::Corrupt
        | argus_infrastructure::artwork_store::ArtworkObjectStoreError::Io
        | argus_infrastructure::artwork_store::ArtworkObjectStoreError::InvalidConfiguration => {
            ErrorCode::InternalUnexpected
        }
    };
    application_error_from_code(code, trace_id)
}

/// Runs the targeted appearance reset through a narrow recovery executor.
pub(crate) fn reset_appearance_with_executor(
    executor: &SqliteDatabaseExecutor,
    context: &OperationContext,
) -> Result<(), ApplicationError> {
    executor
        .execute(context, |scope| {
            let mut work = KernelUnitOfWork::new(scope);
            work.reset_appearance_settings()?;
            work.commit()
        })
        .map_err(|error| map_application_port_error(context.trace_id(), error))
}

static EMERGENCY_TRACE_COUNTER: AtomicU64 = AtomicU64::new(1);

pub fn new_trace_id() -> TraceId {
    let mut bytes = [0_u8; 16];
    if getrandom::fill(&mut bytes).is_ok()
        && let Ok(trace_id) = TraceId::try_from(bytes)
    {
        return trace_id;
    }
    trace_id_from_entropy(None)
}

fn trace_id_from_entropy(entropy: Option<[u8; 16]>) -> TraceId {
    if let Some(bytes) = entropy
        && let Ok(trace_id) = TraceId::try_from(bytes)
    {
        return trace_id;
    }
    loop {
        let counter = EMERGENCY_TRACE_COUNTER.fetch_add(1, Ordering::SeqCst);
        if counter == 0 {
            continue;
        }
        let mut bytes = [0_u8; 16];
        bytes[..8].copy_from_slice(b"ARGUS-ID");
        bytes[8..].copy_from_slice(&counter.to_be_bytes());
        return TraceId::try_from(bytes).expect("emergency trace identity is non-zero");
    }
}

pub(crate) fn startup_context(trace_id: TraceId) -> OperationContext {
    OperationContext::new(
        trace_id,
        SubsystemName::try_from("runtime").expect("static subsystem is valid"),
        OperationName::try_from("startup").expect("static operation is valid"),
    )
}

pub(crate) fn platform_class(platform: Platform) -> PlatformClass {
    match platform {
        Platform::Windows => PlatformClass::Windows,
        Platform::MacOs => PlatformClass::MacOs,
        Platform::Unix => PlatformClass::Unix,
        Platform::Android => PlatformClass::Android,
    }
}

pub(crate) fn architecture_class() -> ArchitectureClass {
    match std::env::consts::ARCH {
        "x86_64" => ArchitectureClass::X8664,
        "aarch64" => ArchitectureClass::Aarch64,
        "x86" => ArchitectureClass::X86,
        "arm" => ArchitectureClass::Arm,
        _ => ArchitectureClass::Unknown,
    }
}

pub(crate) fn application_version() -> Version {
    Version::try_from(env!("CARGO_PKG_VERSION")).expect("package version is safe context")
}

pub(crate) fn environment_fields(
    path_class: PathClass,
    platform: PlatformClass,
    architecture: ArchitectureClass,
) -> SafeContext {
    let mut fields = SafeContext::new();
    insert(
        &mut fields,
        SafeContextField::ApplicationVersion,
        SafeContextValue::ApplicationVersion(application_version()),
    );
    insert(
        &mut fields,
        SafeContextField::BackendVersion,
        SafeContextValue::BackendVersion(application_version()),
    );
    insert(
        &mut fields,
        SafeContextField::Platform,
        SafeContextValue::Platform(platform),
    );
    insert(
        &mut fields,
        SafeContextField::Architecture,
        SafeContextValue::Architecture(architecture),
    );
    insert(
        &mut fields,
        SafeContextField::PathClass,
        SafeContextValue::PathClass(path_class),
    );
    fields
}

#[allow(clippy::too_many_arguments)]
fn failure(
    trace_id: TraceId,
    stage: KernelBootstrapStage,
    code: ErrorCode,
    technical: TechnicalClass,
    path_class: PathClass,
    platform: PlatformClass,
    architecture: ArchitectureClass,
    mut collector: StartupCollector,
) -> KernelBootstrapFailure {
    let context = startup_context(trace_id);
    let mut fields = SafeContext::new();
    insert(
        &mut fields,
        SafeContextField::Stage,
        SafeContextValue::Stage(stage.diagnostic()),
    );
    insert(
        &mut fields,
        SafeContextField::TechnicalClass,
        SafeContextValue::TechnicalClass(technical),
    );
    insert(
        &mut fields,
        SafeContextField::FailureRole,
        SafeContextValue::FailureRole(FailureRole::Primary),
    );
    if code != ErrorCode::PersistenceDatabaseLocked {
        insert(
            &mut fields,
            SafeContextField::PathClass,
            SafeContextValue::PathClass(path_class),
        );
        insert(
            &mut fields,
            SafeContextField::Platform,
            SafeContextValue::Platform(platform),
        );
        insert(
            &mut fields,
            SafeContextField::Architecture,
            SafeContextValue::Architecture(architecture),
        );
    }
    let error = ApplicationError::from_code(code, trace_id, fields.clone())
        .expect("failure fields follow catalog policy");
    emit(
        &mut collector,
        &context,
        "runtime.startup.failed",
        TraceEventPhase::Failed,
        fields,
        Some(code),
        LogLevel::Error,
        Some(error.clone()),
    );
    KernelBootstrapFailure {
        trace_id,
        stage,
        error: Box::new(error),
        collector: Box::new(collector),
    }
}

fn error_class(error: &SqliteExecutorError) -> (ErrorCode, TechnicalClass) {
    match error {
        SqliteExecutorError::DatabaseLocked => (
            ErrorCode::PersistenceDatabaseLocked,
            TechnicalClass::DatabaseLocked,
        ),
        SqliteExecutorError::DatabaseOpenFailed => (
            ErrorCode::PersistenceDatabaseOpenFailed,
            TechnicalClass::DatabaseOpenFailed,
        ),
        SqliteExecutorError::MigrationFailed { .. } => (
            ErrorCode::PersistenceMigrationFailed,
            TechnicalClass::MigrationFailed,
        ),
        SqliteExecutorError::IncompatibleSchema => (
            ErrorCode::PersistenceIncompatibleSchema,
            TechnicalClass::IncompatibleSchema,
        ),
        SqliteExecutorError::Poisoned
        | SqliteExecutorError::Shutdown
        | SqliteExecutorError::ReentrantSubmission
        | SqliteExecutorError::Disconnected
        | SqliteExecutorError::Internal
        | SqliteExecutorError::ApplicationCallback(_) => {
            (ErrorCode::InternalUnexpected, TechnicalClass::Internal)
        }
    }
}

pub(crate) fn insert(context: &mut SafeContext, field: SafeContextField, value: SafeContextValue) {
    context
        .try_insert(field, value)
        .expect("static startup diagnostic field is valid and unique");
}

#[allow(clippy::too_many_arguments)]
pub(crate) fn emit(
    collector: &mut StartupCollector,
    context: &OperationContext,
    name: &str,
    phase: TraceEventPhase,
    fields: SafeContext,
    error_code: Option<ErrorCode>,
    level: LogLevel,
    application_error: Option<ApplicationError>,
) {
    let event_name = EventName::try_from(name).expect("static event name is valid");
    let timestamp = now_millis();
    collector
        .record_trace(TraceEvent::new(
            timestamp,
            context.clone(),
            event_name.clone(),
            phase,
            fields.clone(),
            None,
            error_code,
        ))
        .expect("startup trace collector capacity");
    collector
        .record_log(LogEvent::new(
            timestamp,
            level,
            context.clone(),
            event_name,
            fields,
            application_error,
        ))
        .expect("startup log collector capacity");
}

pub(crate) fn now_millis() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_millis().min(i64::MAX as u128) as i64)
        .unwrap_or(0)
}

fn hex_encode_bytes(bytes: &[u8]) -> String {
    let mut output = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        use std::fmt::Write as _;
        let _ = write!(output, "{byte:02x}");
    }
    output
}

#[cfg(test)]
mod tests {
    use super::{
        Platform, resolve_data_directory, sessions_require_credentials, trace_id_from_entropy,
    };
    use argus_application::{EnrichmentProviderSession, MetadataProviderRegistry, ProviderId};
    use std::path::PathBuf;

    struct TestProviderSession(ProviderId);

    impl EnrichmentProviderSession for TestProviderSession {
        fn provider_id(&self) -> ProviderId {
            self.0
        }
    }

    #[test]
    fn credential_refresh_is_required_only_for_credentialed_sessions() {
        let registry = MetadataProviderRegistry::production();
        let local_sessions: Vec<Box<dyn EnrichmentProviderSession>> =
            vec![Box::new(TestProviderSession(ProviderId::GameTdb))];
        let credentialed_sessions: Vec<Box<dyn EnrichmentProviderSession>> =
            vec![Box::new(TestProviderSession(ProviderId::SteamGridDb))];

        assert!(!sessions_require_credentials(&registry, &local_sessions));
        assert!(sessions_require_credentials(
            &registry,
            &credentialed_sessions
        ));
    }

    #[test]
    fn resolves_name_based_platform_paths() {
        let home = PathBuf::from("/home/tester");
        let local = PathBuf::from("/windows/Users/tester/AppData/Local");
        let xdg = PathBuf::from("/tmp/xdg-data");

        assert_eq!(
            resolve_data_directory(
                Platform::Windows,
                Some(&home),
                Some(&local),
                None,
                None,
                None
            )
            .expect("Windows data root"),
            local.join("Argus ROM Toolkit")
        );
        assert_eq!(
            resolve_data_directory(Platform::MacOs, Some(&home), None, None, None, None)
                .expect("macOS data root"),
            home.join("Library/Application Support/Argus ROM Toolkit")
        );
        assert_eq!(
            resolve_data_directory(Platform::Unix, Some(&home), None, Some(&xdg), None, None)
                .expect("XDG data root"),
            xdg.join("argus-rom-toolkit")
        );
        assert_eq!(
            resolve_data_directory(Platform::Unix, Some(&home), None, None, None, None)
                .expect("Unix fallback data root"),
            home.join(".local/share/argus-rom-toolkit")
        );
    }

    #[test]
    fn rejects_relative_and_traversing_roots() {
        assert!(
            resolve_data_directory(
                Platform::Unix,
                None,
                None,
                None,
                Some(PathBuf::from("relative")),
                None,
            )
            .is_err()
        );
        assert!(
            resolve_data_directory(
                Platform::Unix,
                None,
                None,
                None,
                Some(PathBuf::from("/tmp/../unsafe")),
                None,
            )
            .is_err()
        );
        assert!(
            resolve_data_directory(
                Platform::Unix,
                None,
                None,
                None,
                Some(PathBuf::from("/tmp/./unsafe")),
                None,
            )
            .is_err()
        );
        assert!(
            resolve_data_directory(
                Platform::Unix,
                None,
                None,
                None,
                Some(PathBuf::from("/tmp/unsafe/.")),
                None,
            )
            .is_err()
        );
        assert!(
            resolve_data_directory(
                Platform::Unix,
                Some(PathBuf::from("/home/tester").as_path()),
                None,
                Some(PathBuf::from("relative-xdg").as_path()),
                None,
                None,
            )
            .is_err()
        );
    }

    #[test]
    fn android_requires_a_host_standard_data_directory_when_not_explicitly_overridden() {
        let home = PathBuf::from("/home/tester");
        let xdg = PathBuf::from("/tmp/xdg-data");

        assert!(
            resolve_data_directory(
                Platform::Android,
                Some(home.as_path()),
                None,
                Some(xdg.as_path()),
                None,
                None,
            )
            .is_err()
        );
    }

    #[test]
    fn android_accepts_a_host_standard_data_directory() {
        let standard = PathBuf::from("/data/user/0/com.argusromtoolkit.argus/files/argus");

        assert_eq!(
            resolve_data_directory(
                Platform::Android,
                None,
                None,
                None,
                None,
                Some(standard.clone()),
            )
            .expect("Android host-standard data root"),
            standard,
        );
    }

    #[test]
    fn explicit_override_precedes_host_standard_directory() {
        let explicit = PathBuf::from("/tmp/explicit");
        let standard = PathBuf::from("/data/user/0/com.argusromtoolkit.argus/files/argus");

        assert_eq!(
            resolve_data_directory(
                Platform::Android,
                None,
                None,
                None,
                Some(explicit.clone()),
                Some(standard),
            )
            .expect("explicit override precedes host-standard"),
            explicit,
        );
    }

    #[test]
    fn host_standard_directory_precedes_desktop_defaults() {
        let home = PathBuf::from("/home/tester");
        let standard = PathBuf::from("/data/user/0/com.argusromtoolkit.argus/files/argus");

        assert_eq!(
            resolve_data_directory(
                Platform::Unix,
                Some(home.as_path()),
                None,
                None,
                None,
                Some(standard.clone()),
            )
            .expect("host-standard precedes desktop defaults"),
            standard,
        );
    }

    #[test]
    fn rejects_invalid_host_standard_directories() {
        assert!(
            resolve_data_directory(
                Platform::Android,
                None,
                None,
                None,
                None,
                Some(PathBuf::from("relative")),
            )
            .is_err()
        );
        assert!(
            resolve_data_directory(
                Platform::Android,
                None,
                None,
                None,
                None,
                Some(PathBuf::from("/tmp/../unsafe")),
            )
            .is_err()
        );
    }

    #[test]
    fn android_platform_class_maps_to_android() {
        assert_eq!(
            super::platform_class(Platform::Android),
            argus_application::PlatformClass::Android,
        );
    }

    #[test]
    fn entropy_failure_fallback_is_nonzero_and_unique() {
        let first = trace_id_from_entropy(None);
        let second = trace_id_from_entropy(None);
        assert_ne!(first, second);
        assert_ne!(first.to_string(), "00000000000000000000000000000000");
        assert_ne!(second.to_string(), "00000000000000000000000000000000");
    }

    #[test]
    fn settings_operations_receive_fresh_contexts_separate_from_startup() {
        let startup = super::startup_context(super::new_trace_id());
        let read = super::settings_operation_context("read", startup.trace_id());
        let update = super::settings_operation_context("update", startup.trace_id());
        assert_ne!(read.trace_id(), update.trace_id());
        assert_ne!(read.trace_id(), startup.trace_id());
        assert_ne!(read.operation().as_str(), "startup");
        assert_ne!(update.operation().as_str(), "startup");
    }
}
