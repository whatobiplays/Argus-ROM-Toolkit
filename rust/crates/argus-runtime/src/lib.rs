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
    CancelJobResult, DiagnosticStage, ErrorCode, EventName, FailureRole,
    GetAppearanceSettingsQuery, GetLibraryRootQuery, GetSourceEntryQuery, JobDetail, JobRunId,
    JobSummaryPage, JobsService, LibraryRootId, LibraryRootPage, LibraryRootProjection,
    LibraryRootRepository, LibraryScanAdmissionResult, LibraryScanAllAdmissionResult,
    LibraryScanAllRequestIdentity, LibraryScanAllRequestLookup, LibraryService,
    LibrarySourceRepository, ListJobsQuery, ListLibraryRootsQuery, ListSourceEntryChildrenQuery,
    LocalFilesystemBrowseCursor, LocalFilesystemBrowseLocation, LocalFilesystemBrowsePage,
    LocalFilesystemBrowseRoot, LocalFilesystemRootSelection, LogEvent, LogLevel, MigrationOutcome,
    NewLibraryScanAdmissionContext, ObservabilitySink, OperationContext, OperationName, PathClass,
    PersistenceError, PlatformClass, ProviderError, RemoveLibraryRootCommand,
    RemoveLibraryRootResult, SafeContext, SafeContextField, SafeContextValue, SettingsService,
    SourceEntryChildrenPage, SourceEntryDetailProjection, SourceEntryId,
    StartLibraryScanAllCommand, StartLibraryScanAllResult, StartLibraryScanCommand,
    StartupCollector, SubsystemName, SyncLocalFilesystemMountedVolumesCommand, TechnicalClass,
    TraceEvent, TraceEventPhase, TraceId, UnitOfWork, UnitOfWorkFactory,
    UpdateAppearanceSettingsCommand, Version,
};
use argus_infrastructure::local_filesystem::LocalFilesystemProvider as InfraLocalFilesystemProvider;
use argus_infrastructure::sqlite::{
    MigrationOutcome as InfrastructureMigrationOutcome, MigrationSummary,
    SqliteAppearanceSettingsQueries, SqliteAppearanceSettingsRepository, SqliteDatabaseExecutor,
    SqliteExecutorError, SqliteJobRunRepository, SqliteJobsQueries, SqliteLibraryRootQueries,
    SqliteLibraryRootRepository, SqliteLibraryScanAdmissionContextRepository,
    SqliteLibraryScanTargetRepository, SqliteLibrarySourceRepository, SqliteScanRunRepository,
    SqliteSourceEntryQueries, SqliteSourceEntryRepository, SqliteUnitOfWork,
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
    event_bus: Arc<EventBus>,
    publication_diagnostics: Mutex<PublicationDiagnostics>,
    collector: StartupCollector,
    #[cfg(test)]
    fail_shutdown: bool,
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

    fn find_by_locator_key(
        &mut self,
        library_root_id: argus_application::LibraryRootId,
        locator_key: &argus_application::SourceLocatorKey,
    ) -> Result<Option<argus_application::SourceEntryRecord>, PersistenceError> {
        self.inner.find_by_locator_key(library_root_id, locator_key)
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

    fn delete_for_root(
        &mut self,
        library_root_id: argus_application::LibraryRootId,
    ) -> Result<(), PersistenceError> {
        self.inner.delete_for_root(library_root_id)
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
        event_bus: Arc<EventBus>,
        collector: StartupCollector,
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
            event_bus,
            publication_diagnostics: Mutex::new(PublicationDiagnostics::new()),
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
            Arc::new(EventBus::new(
                Vec::new(),
                Vec::new(),
                Vec::new(),
                Vec::new(),
            )),
            StartupCollector::new(),
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
        event_bus: Arc::new(event_bus),
        publication_diagnostics: Mutex::new(PublicationDiagnostics::new()),
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

#[cfg(test)]
mod tests {
    use super::{Platform, resolve_data_directory, trace_id_from_entropy};
    use std::path::PathBuf;

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
        let standard = PathBuf::from("/data/user/0/dev.argusromtoolkit.argus/files/argus");

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
        let standard = PathBuf::from("/data/user/0/dev.argusromtoolkit.argus/files/argus");

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
        let standard = PathBuf::from("/data/user/0/dev.argusromtoolkit.argus/files/argus");

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
