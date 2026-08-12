//! Bridge-neutral composition for the Phase 000 kernel bootstrap.
//!
//! This module intentionally stops before `ApplicationRuntime::Ready`: it
//! establishes the environment, startup diagnostics, SQLite capability, and
//! migration state needed by later startup slices.
//!
//! The runtime boundary does not export infrastructure SQLite connection or
//! value types:
//!
//! ```compile_fail
//! use argus_runtime::{SqliteConnection, SqliteValue};
//! ```

use std::fmt;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

use argus_application::{
    ApplicationError, ApplicationPortError, ArchitectureClass, DiagnosticStage, ErrorCode,
    EventName, FailureRole, LogEvent, LogLevel, MigrationOutcome, ObservabilitySink,
    OperationContext, OperationName, PathClass, PlatformClass, SafeContext, SafeContextField,
    SafeContextValue, StartupCollector, SubsystemName, TechnicalClass, TraceEvent, TraceEventPhase,
    TraceId, UnitOfWorkFactory, Version,
};
use argus_infrastructure::sqlite::{
    MigrationOutcome as InfrastructureMigrationOutcome, MigrationSummary, SqliteDatabaseExecutor,
    SqliteExecutorError, SqliteUnitOfWork,
};

/// Platform naming policy used by the private path-resolution seam.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Platform {
    Windows,
    MacOs,
    Unix,
}

impl Platform {
    fn current() -> Self {
        if cfg!(target_os = "windows") {
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
enum DataDirectoryError {
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
fn resolve_data_directory(
    platform: Platform,
    home: Option<&Path>,
    local_app_data: Option<&Path>,
    xdg_data_home: Option<&Path>,
    override_directory: Option<PathBuf>,
) -> Result<PathBuf, DataDirectoryError> {
    if let Some(directory) = override_directory {
        if !directory.is_absolute() || has_dot_component(&directory) {
            return Err(DataDirectoryError::InvalidOverride);
        }
        validate_absolute_root(&directory, DataDirectoryError::InvalidOverride)?;
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
    }
}

fn validate_absolute_root(
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
}

impl KernelBootstrapOptions {
    /// Creates options with an explicit test/embedding data root.
    pub fn with_data_directory(directory: impl Into<PathBuf>) -> Self {
        Self {
            data_directory_override: Some(directory.into()),
        }
    }
}

fn env_path(name: &str) -> Option<PathBuf> {
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
    collector: StartupCollector,
}

/// Technology-neutral transaction scope exposed by the runtime boundary.
///
/// The concrete SQLite transaction remains owned by infrastructure. This
/// wrapper intentionally exposes only the consuming application `UnitOfWork`
/// contract so callers cannot depend on SQLite statements or value types.
pub struct KernelUnitOfWork<'scope> {
    inner: SqliteUnitOfWork<'scope>,
}

impl<'scope> KernelUnitOfWork<'scope> {
    fn new(inner: SqliteUnitOfWork<'scope>) -> Self {
        Self { inner }
    }
}

impl argus_application::UnitOfWork for KernelUnitOfWork<'_> {
    fn commit(self) -> Result<(), ApplicationPortError> {
        self.inner.commit()
    }

    fn rollback(self) -> Result<(), ApplicationPortError> {
        self.inner.rollback()
    }
}

impl KernelBootstrap {
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

    /// Shuts down the worker and consumes the kernel.
    pub fn shutdown(mut self) -> Result<(), KernelShutdownError> {
        self.executor.take().map_or(Ok(()), |executor| {
            executor
                .shutdown()
                .map_err(|_| KernelShutdownError::Internal)
        })
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
        self.executor
            .as_ref()
            .ok_or(ApplicationPortError::Persistence(
                argus_application::PersistenceError::Unavailable,
            ))?
            .execute(context, move |scope| {
                operation(KernelUnitOfWork::new(scope))
            })
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
    let trace_id = new_trace_id();
    let context = startup_context(trace_id);
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
        collector,
    })
}

static EMERGENCY_TRACE_COUNTER: AtomicU64 = AtomicU64::new(1);

fn new_trace_id() -> TraceId {
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

fn startup_context(trace_id: TraceId) -> OperationContext {
    OperationContext::new(
        trace_id,
        SubsystemName::try_from("runtime").expect("static subsystem is valid"),
        OperationName::try_from("startup").expect("static operation is valid"),
    )
}

fn platform_class(platform: Platform) -> PlatformClass {
    match platform {
        Platform::Windows => PlatformClass::Windows,
        Platform::MacOs => PlatformClass::MacOs,
        Platform::Unix => PlatformClass::Unix,
    }
}

fn architecture_class() -> ArchitectureClass {
    match std::env::consts::ARCH {
        "x86_64" => ArchitectureClass::X8664,
        "aarch64" => ArchitectureClass::Aarch64,
        "x86" => ArchitectureClass::X86,
        "arm" => ArchitectureClass::Arm,
        _ => ArchitectureClass::Unknown,
    }
}

fn application_version() -> Version {
    Version::try_from(env!("CARGO_PKG_VERSION")).expect("package version is safe context")
}

fn environment_fields(
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

fn insert(context: &mut SafeContext, field: SafeContextField, value: SafeContextValue) {
    context
        .try_insert(field, value)
        .expect("static startup diagnostic field is valid and unique");
}

#[allow(clippy::too_many_arguments)]
fn emit(
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

fn now_millis() -> i64 {
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
            resolve_data_directory(Platform::Windows, Some(&home), Some(&local), None, None)
                .expect("Windows data root"),
            local.join("Argus ROM Toolkit")
        );
        assert_eq!(
            resolve_data_directory(Platform::MacOs, Some(&home), None, None, None)
                .expect("macOS data root"),
            home.join("Library/Application Support/Argus ROM Toolkit")
        );
        assert_eq!(
            resolve_data_directory(Platform::Unix, Some(&home), None, Some(&xdg), None)
                .expect("XDG data root"),
            xdg.join("argus-rom-toolkit")
        );
        assert_eq!(
            resolve_data_directory(Platform::Unix, Some(&home), None, None, None)
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
            )
            .is_err()
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
}
