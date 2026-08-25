//! Phase 000 startup coordination: the real eight-phase pipeline, timing,
//! cleanup registration, LIFO cleanup, and active readiness validation.

use std::path::PathBuf;
use std::sync::Arc;

use argus_application::{
    ApplicationError, ArchitectureClass, DiagnosticStage, ErrorCode, FailureRole,
    GetAppearanceSettingsQuery, JobsService, LibraryScanRecoveryHandler, LibraryService, LogLevel,
    OperationContext, PathClass, PlatformClass, RetryPolicy, SafeContext, SafeContextField,
    SafeContextValue, SettingsService, StartupCollector, TraceEventPhase, TraceId,
};
use argus_infrastructure::artwork_store::ArtworkObjectStore;
use argus_infrastructure::local_filesystem::LocalFilesystemProvider as InfraLocalFilesystemProvider;
use argus_infrastructure::sqlite::{
    DEFAULT_QUEUE_CAPACITY, SqliteAppearanceSettingsQueries, SqliteDatabaseExecutor,
    SqliteJobsQueries, SqliteLibraryRootQueries, SqliteSourceEntryQueries,
};

use crate::background::{BackgroundManagerConfig, BackgroundOperationManager};
use crate::{
    AppearanceResetCapability, EventBoundary, EventBus, FailedRuntimeRecoveryContext,
    FailedStartupDiagnostics, KernelBootstrap, KernelBootstrapOptions, KernelMigrationSummary,
    KernelUnitOfWorkFactory, RecoveryAction, RecoveryActionKind, RuntimeEventPublisher,
    RuntimeEventSubscriber, RuntimeInstanceId, RuntimeNotificationSink, RuntimeState,
    StartupFailure, StartupPhase, StartupPhaseOutcome, StartupPhaseRecord, architecture_class,
    emit, env_path, insert, new_trace_id, platform_class, resolve_data_directory,
    settings_operation_context, startup_context,
};

/// Deterministic clock seam for startup phase timing.
pub trait Clock {
    /// Returns the current wall-clock time in milliseconds.
    fn now_millis(&self) -> i64;
}

/// Observes phase transitions so the owning runtime can publish status.
pub(crate) trait StartupPhaseObserver {
    /// Called immediately before a phase begins.
    fn phase_started(&self, phase: StartupPhase);
}

/// Settings-integrity read port used by the settings and readiness phases.
pub(crate) trait SettingsReadPort {
    /// Reads the authoritative appearance aggregate.
    fn read(
        &self,
        context: &OperationContext,
    ) -> Result<argus_application::AppearanceSettings, ApplicationError>;
}

/// Production settings read port over the initialized service.
pub(crate) struct KernelSettingsReadPort<'a> {
    service: &'a SettingsService<SqliteAppearanceSettingsQueries, SqliteDatabaseExecutor>,
}

impl SettingsReadPort for KernelSettingsReadPort<'_> {
    fn read(
        &self,
        context: &OperationContext,
    ) -> Result<argus_application::AppearanceSettings, ApplicationError> {
        self.service
            .get_appearance_settings(GetAppearanceSettingsQuery, context.clone())
    }
}

/// Production clock backed by the system clock.
pub struct SystemClock;

impl Clock for SystemClock {
    fn now_millis(&self) -> i64 {
        crate::now_millis()
    }
}

/// Secondary cleanup failure; never replaces the primary startup failure.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct CleanupError;

type Cleanup = Box<dyn FnOnce(&mut StartupResources) -> Result<(), CleanupError> + Send>;

/// Terminal startup result consumed by `ApplicationRuntime`.
pub struct StartupResult {
    /// The startup operation trace identity.
    pub trace_id: TraceId,
    /// The authoritative terminal runtime state.
    pub state: RuntimeState,
    /// Assembled kernel on success; retained partial resources on failure.
    pub kernel: Option<KernelBootstrap>,
    /// Per-phase outcome records with real durations.
    pub history: Vec<StartupPhaseRecord>,
    /// Typed failure context when startup did not reach readiness.
    pub failure: Option<StartupFailure>,
    /// Bounded capabilities retained for failed-runtime recovery.
    pub(crate) recovery_context: Option<FailedRuntimeRecoveryContext>,
    /// The runtime-owned background manager for the ready generation.
    pub background: Option<Arc<BackgroundOperationManager<KernelUnitOfWorkFactory>>>,
}

#[derive(Default)]
struct StartupResources {
    path_class: Option<PathClass>,
    platform: Option<PlatformClass>,
    architecture: Option<ArchitectureClass>,
    data_directory: Option<PathBuf>,
    migration_summary: Option<KernelMigrationSummary>,
    executor: Option<SqliteDatabaseExecutor>,
    settings_service:
        Option<SettingsService<SqliteAppearanceSettingsQueries, SqliteDatabaseExecutor>>,
    library_service: Option<
        LibraryService<
            SqliteLibraryRootQueries,
            SqliteSourceEntryQueries,
            SqliteDatabaseExecutor,
            InfraLocalFilesystemProvider,
        >,
    >,
    jobs_service: Option<JobsService<SqliteJobsQueries, KernelUnitOfWorkFactory>>,
    unit_of_work: Option<KernelUnitOfWorkFactory>,
    artwork_store: Option<Arc<ArtworkObjectStore>>,
    event_bus: Option<Arc<EventBus>>,
    diagnostics_ready: bool,
    data_directory_ready: bool,
    core_services_ready: bool,
}

/// The single authoritative Phase 000 startup orchestrator.
pub struct StartupCoordinator {
    options: KernelBootstrapOptions,
    generation: RuntimeInstanceId,
    trace_id: TraceId,
    context: OperationContext,
    collector: StartupCollector,
    resources: StartupResources,
    cleanups: Vec<Cleanup>,
    history: Vec<StartupPhaseRecord>,
    settings_read: Option<Box<dyn SettingsReadPort>>,
}

impl StartupCoordinator {
    /// Runs the fixed eight mandatory phases and returns a terminal result.
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn run(
        options: KernelBootstrapOptions,
        generation: RuntimeInstanceId,
        boundary: Arc<EventBoundary>,
        clock: &dyn Clock,
        observer: &dyn StartupPhaseObserver,
        should_cancel: &dyn Fn() -> bool,
        settings_read: Option<Box<dyn SettingsReadPort>>,
        outward_sink: Option<Arc<dyn RuntimeNotificationSink>>,
    ) -> StartupResult {
        let mut coordinator = Self::new(options);
        coordinator.generation = generation;
        coordinator.settings_read = settings_read;
        coordinator.emit_started();
        let result = coordinator.phase(
            StartupPhase::EnvironmentInitialization,
            clock,
            observer,
            should_cancel,
            |this| this.environment(),
        );
        let result = result.and_then(|_| {
            coordinator.phase(
                StartupPhase::ObservabilityInitialization,
                clock,
                observer,
                should_cancel,
                |this| this.observability(),
            )
        });
        let result = result.and_then(|_| {
            coordinator.phase(
                StartupPhase::ConfigurationInitialization,
                clock,
                observer,
                should_cancel,
                |this| this.configuration(),
            )
        });
        let result = result.and_then(|_| {
            coordinator.phase(
                StartupPhase::PersistenceInitialization,
                clock,
                observer,
                should_cancel,
                |this| this.persistence(),
            )
        });
        let result = result.and_then(|_| {
            coordinator.phase(
                StartupPhase::SettingsInitialization,
                clock,
                observer,
                should_cancel,
                |this| this.settings(),
            )
        });
        let result = result.and_then(|_| {
            coordinator.phase(
                StartupPhase::CoreServicesInitialization,
                clock,
                observer,
                should_cancel,
                |this| this.core_services(),
            )
        });
        let result = result.and_then(|_| {
            coordinator.phase(
                StartupPhase::EventInfrastructureInitialization,
                clock,
                observer,
                should_cancel,
                |this| this.event_infrastructure(Arc::clone(&boundary), outward_sink.clone()),
            )
        });
        let result = result.and_then(|_| {
            coordinator.phase(
                StartupPhase::ReadinessValidation,
                clock,
                observer,
                should_cancel,
                |this| this.readiness(),
            )
        });

        match result {
            Ok(()) => coordinator.finish_ready(),
            Err(error) => coordinator.finish_failed(error),
        }
    }

    fn new(options: KernelBootstrapOptions) -> Self {
        let trace_id = new_trace_id();
        Self {
            options,
            generation: RuntimeInstanceId::new(),
            trace_id,
            context: startup_context(trace_id),
            collector: StartupCollector::new(),
            resources: StartupResources::default(),
            cleanups: Vec::new(),
            history: Vec::new(),
            settings_read: None,
        }
    }

    fn emit_started(&mut self) {
        emit(
            &mut self.collector,
            &self.context,
            "runtime.startup.started",
            TraceEventPhase::Started,
            SafeContext::new(),
            None,
            LogLevel::Info,
            None,
        );
    }

    /// Test-only cleanup registration seam.
    #[cfg(test)]
    fn push_cleanup_for_tests(&mut self, cleanup: Cleanup) {
        self.cleanups.push(cleanup);
    }

    fn phase(
        &mut self,
        phase: StartupPhase,
        clock: &dyn Clock,
        observer: &dyn StartupPhaseObserver,
        should_cancel: &dyn Fn() -> bool,
        body: impl FnOnce(&mut Self) -> Result<(), ApplicationError>,
    ) -> Result<(), ApplicationError> {
        if should_cancel() {
            return Err(crate::operations::cancelled_error_with_trace(self.trace_id));
        }
        observer.phase_started(phase);
        if should_cancel() {
            return Err(crate::operations::cancelled_error_with_trace(self.trace_id));
        }
        let started = clock.now_millis();
        let outcome = body(self);
        let duration_ms = (clock.now_millis() - started).max(0) as u64;
        match outcome {
            Ok(()) => {
                self.history.push(StartupPhaseRecord {
                    phase,
                    outcome: StartupPhaseOutcome::Succeeded,
                    duration_ms,
                });
                let mut fields = SafeContext::new();
                insert(
                    &mut fields,
                    SafeContextField::Stage,
                    SafeContextValue::Stage(diagnostic_stage(phase)),
                );
                emit(
                    &mut self.collector,
                    &self.context,
                    "runtime.startup.phase.completed",
                    TraceEventPhase::Completed,
                    fields,
                    None,
                    LogLevel::Info,
                    None,
                );
                Ok(())
            }
            Err(error) => {
                self.history.push(StartupPhaseRecord {
                    phase,
                    outcome: StartupPhaseOutcome::Failed,
                    duration_ms,
                });
                let mut fields = SafeContext::new();
                insert(
                    &mut fields,
                    SafeContextField::Stage,
                    SafeContextValue::Stage(diagnostic_stage(phase)),
                );
                insert(
                    &mut fields,
                    SafeContextField::FailureRole,
                    SafeContextValue::FailureRole(FailureRole::Primary),
                );
                emit(
                    &mut self.collector,
                    &self.context,
                    "runtime.startup.phase.failed",
                    TraceEventPhase::Failed,
                    fields,
                    Some(error.code),
                    LogLevel::Error,
                    Some(error.clone()),
                );
                Err(error)
            }
        }
    }

    fn environment(&mut self) -> Result<(), ApplicationError> {
        let platform = crate::Platform::current();
        let platform_class = platform_class(platform);
        let architecture = architecture_class();
        let home = env_path("HOME");
        let local_app_data = env_path("LOCALAPPDATA");
        let xdg_data_home = env_path("XDG_DATA_HOME");
        let data_directory = resolve_data_directory(
            platform,
            home.as_deref(),
            local_app_data.as_deref(),
            xdg_data_home.as_deref(),
            self.options.data_directory_override.clone(),
            self.options.standard_data_directory.clone(),
        )
        .map_err(|_| configuration_error(self.trace_id))?;
        std::fs::create_dir_all(&data_directory).map_err(|error| {
            if error.kind() == std::io::ErrorKind::PermissionDenied {
                permission_error(self.trace_id)
            } else {
                configuration_error(self.trace_id)
            }
        })?;
        self.resources.path_class = Some(if self.options.data_directory_override.is_some() {
            PathClass::ExplicitOverride
        } else {
            PathClass::StandardApplicationData
        });
        self.resources.platform = Some(platform_class);
        self.resources.architecture = Some(architecture);
        self.resources.data_directory = Some(data_directory);
        self.resources.data_directory_ready = true;
        Ok(())
    }

    fn observability(&mut self) -> Result<(), ApplicationError> {
        self.resources.diagnostics_ready = true;
        Ok(())
    }

    fn configuration(&mut self) -> Result<(), ApplicationError> {
        if let Some(override_path) = &self.options.data_directory_override {
            crate::validate_absolute_root(
                override_path,
                crate::DataDirectoryError::InvalidOverride,
            )
            .map_err(|_| configuration_error(self.trace_id))?;
        }
        Ok(())
    }

    fn persistence(&mut self) -> Result<(), ApplicationError> {
        let data_directory = self
            .resources
            .data_directory
            .as_ref()
            .ok_or_else(|| configuration_error(self.trace_id))?;
        let database_path = data_directory.join("argus.sqlite3");
        let executor =
            SqliteDatabaseExecutor::open_with_capacity(&database_path, DEFAULT_QUEUE_CAPACITY)
                .map_err(|error| persistence_error(self.trace_id, error))?;
        let artwork_store = ArtworkObjectStore::new(data_directory.join("artwork-assets"))
            .map_err(|_| {
                persistence_error(
                    self.trace_id,
                    argus_infrastructure::sqlite::SqliteExecutorError::Internal,
                )
            })?;
        let migration_summary = KernelMigrationSummary::from(executor.migration_summary());
        let settings_service = SettingsService::new(
            SqliteAppearanceSettingsQueries::new(executor.clone()),
            executor.clone(),
        );
        self.resources.executor = Some(executor);
        self.resources.artwork_store = Some(Arc::new(artwork_store));
        self.resources.settings_service = Some(settings_service);
        self.resources.migration_summary = Some(migration_summary);
        self.cleanups.push(Box::new(|resources| {
            if let Some(executor) = resources.executor.take() {
                executor.shutdown().map_err(|_| CleanupError)?;
            }
            Ok(())
        }));
        Ok(())
    }

    fn settings(&mut self) -> Result<(), ApplicationError> {
        let context = settings_operation_context("settings_integrity", self.trace_id);
        if let Some(port) = &self.settings_read {
            return port.read(&context).map(|_| ());
        }
        let service = self
            .resources
            .settings_service
            .as_ref()
            .ok_or_else(|| configuration_error(self.trace_id))?;
        KernelSettingsReadPort { service }
            .read(&context)
            .map(|_| ())
    }

    fn core_services(&mut self) -> Result<(), ApplicationError> {
        if self.resources.settings_service.is_none() {
            return Err(core_service_error(self.trace_id));
        }
        if let Some(executor) = &self.resources.executor {
            let unit_of_work = KernelUnitOfWorkFactory::new(executor.clone());
            let jobs_service = JobsService::new(
                SqliteJobsQueries::new(executor.clone()),
                unit_of_work.clone(),
            );
            let library_service = LibraryService::new(
                SqliteLibraryRootQueries::new(executor.clone()),
                SqliteSourceEntryQueries::new(executor.clone()),
                executor.clone(),
                InfraLocalFilesystemProvider::default(),
            );
            self.resources.unit_of_work = Some(unit_of_work);
            self.resources.jobs_service = Some(jobs_service);
            self.resources.library_service = Some(library_service);
            LibraryScanRecoveryHandler::new(
                SqliteJobsQueries::new(executor.clone()),
                self.resources
                    .unit_of_work
                    .clone()
                    .expect("unit of work composed above"),
            )
            .handle(&self.context)
            .map_err(|_| core_service_error(self.trace_id))?;
        }
        self.resources.core_services_ready = true;
        Ok(())
    }

    fn event_infrastructure(
        &mut self,
        boundary: Arc<EventBoundary>,
        outward_sink: Option<Arc<dyn RuntimeNotificationSink>>,
    ) -> Result<(), ApplicationError> {
        if outward_sink.is_none() {
            return Err(not_ready_error(self.trace_id));
        }
        let sink = outward_sink.as_ref().expect("checked above");
        let publisher = RuntimeEventPublisher::new(self.generation, Arc::clone(&boundary));
        sink.bind(Arc::clone(&publisher))
            .map_err(|_| not_ready_error(self.trace_id))?;
        sink.validate()
            .map_err(|_| not_ready_error(self.trace_id))?;
        let subscriber = RuntimeEventSubscriber {
            outward: outward_sink,
        };
        let bus = Arc::new(EventBus::new(
            vec![Box::new(subscriber.clone())],
            vec![Box::new(subscriber.clone())],
            vec![Box::new(subscriber.clone())],
            vec![Box::new(subscriber)],
        ));
        if bus.subscriber_count() == 0 {
            return Err(core_service_error(self.trace_id));
        }
        self.resources.event_bus = Some(bus);
        Ok(())
    }

    fn readiness(&mut self) -> Result<(), ApplicationError> {
        if !self.resources.data_directory_ready
            || self.resources.executor.is_none()
            || self.resources.settings_service.is_none()
            || self.resources.library_service.is_none()
            || self.resources.jobs_service.is_none()
            || self.resources.unit_of_work.is_none()
            || self.resources.artwork_store.is_none()
            || self.resources.event_bus.is_none()
            || !self.resources.core_services_ready
        {
            return Err(not_ready_error(self.trace_id));
        }
        let context = settings_operation_context("readiness_validation", self.trace_id);
        let result = if let Some(port) = &self.settings_read {
            port.read(&context)
        } else {
            let service = self
                .resources
                .settings_service
                .as_ref()
                .ok_or_else(|| not_ready_error(self.trace_id))?;
            KernelSettingsReadPort { service }.read(&context)
        };
        result
            .map(|_| ())
            .map_err(|_| not_ready_error(self.trace_id))
    }

    fn finish_ready(mut self) -> StartupResult {
        let settings_service = self
            .resources
            .settings_service
            .take()
            .expect("readiness validated settings");
        let library_service = self
            .resources
            .library_service
            .take()
            .expect("readiness validated library service");
        let jobs_service = self
            .resources
            .jobs_service
            .take()
            .expect("readiness validated jobs service");
        let unit_of_work = self
            .resources
            .unit_of_work
            .take()
            .expect("readiness validated unit of work");
        let artwork_store = self
            .resources
            .artwork_store
            .take()
            .expect("readiness validated artwork store");
        let event_bus = self
            .resources
            .event_bus
            .take()
            .expect("readiness validated event bus");
        let background = Some(Arc::new(BackgroundOperationManager::new(
            unit_of_work.clone(),
            Arc::clone(&event_bus),
            BackgroundManagerConfig::default(),
        )));
        let migration_summary = self
            .resources
            .migration_summary
            .take()
            .expect("readiness validated migration summary");
        let path_class = self
            .resources
            .path_class
            .expect("readiness validated path class");
        let kernel = KernelBootstrap::from_parts(
            self.trace_id,
            path_class,
            migration_summary,
            unit_of_work,
            settings_service,
            library_service,
            jobs_service,
            artwork_store,
            event_bus,
            self.collector,
            self.options.enrichment_session_factory(),
        );
        StartupResult {
            trace_id: self.trace_id,
            state: RuntimeState::Ready {
                runtime_instance_id: self.generation,
            },
            kernel: Some(kernel),
            background,
            history: self.history,
            failure: None,
            recovery_context: None,
        }
    }

    fn finish_failed(mut self, error: ApplicationError) -> StartupResult {
        let phase = failed_phase(&self.history);
        let recovery_actions = recovery_actions_for(&self.resources, phase, &error);
        let failure = StartupFailure {
            phase,
            error,
            recovery_actions,
            diagnostics_available: self.resources.diagnostics_ready,
            data_directory_available: self.resources.data_directory_ready,
        };

        let isolated_appearance_failure = phase == StartupPhase::SettingsInitialization
            && failure.error.code == ErrorCode::ConfigurationPersistedSettingsInvalid;
        let appearance_reset = if isolated_appearance_failure {
            self.resources
                .executor
                .take()
                .map(AppearanceResetCapability::new)
        } else {
            None
        };
        let data_directory = if self.resources.data_directory_ready {
            self.resources.data_directory.take()
        } else {
            None
        };
        let mut cleanup_failures = 0usize;
        while let Some(cleanup) = self.cleanups.pop() {
            if cleanup(&mut self.resources).is_err() {
                cleanup_failures += 1;
            }
        }
        if cleanup_failures > 0 {
            let mut fields = SafeContext::new();
            insert(
                &mut fields,
                SafeContextField::FailureRole,
                SafeContextValue::FailureRole(FailureRole::Secondary),
            );
            emit(
                &mut self.collector,
                &self.context,
                "runtime.startup.cleanup.failed",
                TraceEventPhase::Failed,
                fields,
                Some(ErrorCode::InternalUnexpected),
                LogLevel::Error,
                None,
            );
        }
        let diagnostics = if self.resources.diagnostics_ready {
            Some(FailedStartupDiagnostics {
                collector: std::mem::replace(&mut self.collector, StartupCollector::new()),
                migration_summary: self.resources.migration_summary.take(),
                path_class: self.resources.path_class,
                platform: self.resources.platform,
                architecture: self.resources.architecture,
                trace_id: self.trace_id,
                failure: failure.clone(),
            })
        } else {
            None
        };
        StartupResult {
            trace_id: self.trace_id,
            state: RuntimeState::StartupFailed {
                runtime_instance_id: self.generation,
                failure: failure.clone(),
            },
            kernel: None,
            background: None,
            history: self.history,
            failure: Some(failure),
            recovery_context: Some(FailedRuntimeRecoveryContext {
                appearance_reset,
                data_directory,
                diagnostics,
            }),
        }
    }
}

fn diagnostic_stage(phase: StartupPhase) -> DiagnosticStage {
    match phase {
        StartupPhase::EnvironmentInitialization => DiagnosticStage::Environment,
        StartupPhase::ObservabilityInitialization => DiagnosticStage::Observability,
        StartupPhase::PersistenceInitialization => DiagnosticStage::Persistence,
        _ => DiagnosticStage::Persistence,
    }
}

fn failed_phase(history: &[StartupPhaseRecord]) -> StartupPhase {
    history
        .iter()
        .rev()
        .find(|record| record.outcome == StartupPhaseOutcome::Failed)
        .map(|record| record.phase)
        .unwrap_or(StartupPhase::EnvironmentInitialization)
}

fn recovery_actions_for(
    resources: &StartupResources,
    phase: StartupPhase,
    error: &ApplicationError,
) -> Vec<RecoveryAction> {
    let mut actions = vec![RecoveryAction {
        kind: RecoveryActionKind::Exit,
    }];
    if error.code.policy().retry_policy != RetryPolicy::Never {
        actions.push(RecoveryAction {
            kind: RecoveryActionKind::RetryStartup,
        });
    }
    if resources.diagnostics_ready {
        actions.push(RecoveryAction {
            kind: RecoveryActionKind::ExportDiagnostics,
        });
        actions.push(RecoveryAction {
            kind: RecoveryActionKind::CopyTechnicalDetails,
        });
    }
    if resources.data_directory_ready {
        actions.push(RecoveryAction {
            kind: RecoveryActionKind::OpenDataDirectory,
        });
    }
    if phase == StartupPhase::SettingsInitialization
        && error.code == ErrorCode::ConfigurationPersistedSettingsInvalid
    {
        actions.insert(
            1,
            RecoveryAction {
                kind: RecoveryActionKind::ResetAppearanceSettings,
            },
        );
    }
    actions
}

fn configuration_error(trace_id: TraceId) -> ApplicationError {
    ApplicationError::from_code(
        ErrorCode::ConfigurationInvalid,
        trace_id,
        SafeContext::new(),
    )
    .expect("configuration error uses an allowlisted empty context")
}

fn permission_error(trace_id: TraceId) -> ApplicationError {
    ApplicationError::from_code(
        ErrorCode::FilesystemPermissionDenied,
        trace_id,
        SafeContext::new(),
    )
    .expect("filesystem error uses an allowlisted empty context")
}

fn persistence_error(
    trace_id: TraceId,
    error: argus_infrastructure::sqlite::SqliteExecutorError,
) -> ApplicationError {
    let code = match error {
        argus_infrastructure::sqlite::SqliteExecutorError::DatabaseLocked => {
            ErrorCode::PersistenceDatabaseLocked
        }
        argus_infrastructure::sqlite::SqliteExecutorError::DatabaseOpenFailed => {
            ErrorCode::PersistenceDatabaseOpenFailed
        }
        argus_infrastructure::sqlite::SqliteExecutorError::MigrationFailed { .. } => {
            ErrorCode::PersistenceMigrationFailed
        }
        argus_infrastructure::sqlite::SqliteExecutorError::IncompatibleSchema => {
            ErrorCode::PersistenceIncompatibleSchema
        }
        _ => ErrorCode::InternalUnexpected,
    };
    ApplicationError::from_code(code, trace_id, SafeContext::new())
        .expect("persistence error uses an allowlisted empty context")
}

fn core_service_error(trace_id: TraceId) -> ApplicationError {
    ApplicationError::from_code(
        ErrorCode::RuntimeCoreServiceInitializationFailed,
        trace_id,
        SafeContext::new(),
    )
    .expect("core-service error uses an allowlisted empty context")
}

fn not_ready_error(trace_id: TraceId) -> ApplicationError {
    ApplicationError::from_code(ErrorCode::RuntimeNotReady, trace_id, SafeContext::new())
        .expect("readiness error uses an allowlisted empty context")
}

#[cfg(test)]
mod tests {
    use std::io::Read;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::{Arc, Mutex};

    use argus_application::{ApplicationError, ErrorCode, SafeContext};

    use crate::diagnostics::export_with_contributors;
    use crate::startup::{
        CleanupError, Clock, StartupCoordinator, StartupPhaseObserver, StartupPhaseOutcome,
        StartupResources, configuration_error, recovery_actions_for,
    };
    use crate::{
        EventBoundary, InProcessNotificationSink, KernelBootstrapOptions, NotificationSinkError,
        RecoveryActionKind, RuntimeEventPayload, RuntimeInstanceId, RuntimeNotificationSink,
        StartupPhase,
    };

    #[derive(Default)]
    struct FakeClock {
        values: Mutex<Vec<i64>>,
    }

    struct NoopObserver;

    impl StartupPhaseObserver for NoopObserver {
        fn phase_started(&self, _phase: StartupPhase) {}
    }

    struct FailingSink;

    impl RuntimeNotificationSink for FailingSink {
        fn bind(
            &self,
            _publisher: std::sync::Arc<crate::RuntimeEventPublisher>,
        ) -> Result<(), NotificationSinkError> {
            Err(NotificationSinkError::Unavailable)
        }

        fn validate(&self) -> Result<(), NotificationSinkError> {
            Err(NotificationSinkError::Unavailable)
        }

        fn publish(&self, _event: RuntimeEventPayload) -> Result<(), NotificationSinkError> {
            Err(NotificationSinkError::Unavailable)
        }
    }

    impl FakeClock {
        fn with_values(values: Vec<i64>) -> Self {
            Self {
                values: Mutex::new(values),
            }
        }
    }

    impl Clock for FakeClock {
        fn now_millis(&self) -> i64 {
            self.values
                .lock()
                .expect("clock values")
                .pop()
                .unwrap_or_default()
        }
    }

    #[test]
    fn success_records_eight_phases_with_injected_timing() {
        let directory = tempfile::tempdir().expect("temporary directory");
        let options = KernelBootstrapOptions::with_data_directory(directory.path());
        let generation = RuntimeInstanceId::new();
        let boundary = EventBoundary::new();
        let clock = FakeClock::with_values((0..=32).rev().collect());

        let result = StartupCoordinator::run(
            options,
            generation,
            boundary,
            &clock,
            &NoopObserver,
            &|| false,
            None,
            Some(Arc::new(InProcessNotificationSink::new())),
        );

        assert!(matches!(result.state, crate::RuntimeState::Ready { .. }));
        assert_eq!(result.history.len(), StartupPhase::phase_000().len());
        for (record, expected) in result.history.iter().zip(StartupPhase::phase_000().iter()) {
            assert_eq!(record.phase, *expected);
            assert_eq!(record.outcome, StartupPhaseOutcome::Succeeded);
            assert_eq!(record.duration_ms, 1);
        }
    }

    #[test]
    fn host_standard_data_directory_is_classified_as_standard_application_data() {
        let directory = tempfile::tempdir().expect("temporary directory");
        let options = KernelBootstrapOptions::with_standard_data_directory(directory.path());
        let generation = RuntimeInstanceId::new();
        let boundary = EventBoundary::new();
        let clock = FakeClock::with_values((0..=32).rev().collect());

        let result = StartupCoordinator::run(
            options,
            generation,
            boundary,
            &clock,
            &NoopObserver,
            &|| false,
            None,
            Some(Arc::new(InProcessNotificationSink::new())),
        );

        assert!(matches!(result.state, crate::RuntimeState::Ready { .. }));
        assert_eq!(
            result.kernel.expect("ready kernel").path_class(),
            argus_application::PathClass::StandardApplicationData,
        );
    }

    #[test]
    fn explicit_data_directory_override_remains_explicit_override() {
        let directory = tempfile::tempdir().expect("temporary directory");
        let options = KernelBootstrapOptions::with_data_directory(directory.path());
        let generation = RuntimeInstanceId::new();
        let boundary = EventBoundary::new();
        let clock = FakeClock::with_values((0..=32).rev().collect());

        let result = StartupCoordinator::run(
            options,
            generation,
            boundary,
            &clock,
            &NoopObserver,
            &|| false,
            None,
            Some(Arc::new(InProcessNotificationSink::new())),
        );

        assert!(matches!(result.state, crate::RuntimeState::Ready { .. }));
        assert_eq!(
            result.kernel.expect("ready kernel").path_class(),
            argus_application::PathClass::ExplicitOverride,
        );
    }

    #[test]
    fn first_failure_stops_later_phases() {
        let options = KernelBootstrapOptions::with_data_directory("relative/path");
        let generation = RuntimeInstanceId::new();
        let boundary = EventBoundary::new();
        let clock = FakeClock::with_values(vec![10, 0]);

        let result = StartupCoordinator::run(
            options,
            generation,
            boundary,
            &clock,
            &NoopObserver,
            &|| false,
            None,
            None,
        );

        assert!(matches!(
            result.state,
            crate::RuntimeState::StartupFailed { .. }
        ));
        assert_eq!(result.history.len(), 1);
        assert_eq!(
            result.history[0].phase,
            StartupPhase::EnvironmentInitialization
        );
        assert_eq!(result.history[0].outcome, StartupPhaseOutcome::Failed);
    }

    #[test]
    fn recovery_eligibility_is_capability_specific() {
        let trace = crate::new_trace_id();
        let settings_error = ApplicationError::from_code(
            ErrorCode::ConfigurationPersistedSettingsInvalid,
            trace,
            SafeContext::new(),
        )
        .expect("settings error");
        let resources = StartupResources {
            diagnostics_ready: true,
            data_directory_ready: false,
            ..Default::default()
        };

        let actions = recovery_actions_for(
            &resources,
            StartupPhase::SettingsInitialization,
            &settings_error,
        );
        assert!(
            actions
                .iter()
                .any(|action| action.kind == RecoveryActionKind::ResetAppearanceSettings)
        );
        assert!(
            actions
                .iter()
                .any(|action| action.kind == RecoveryActionKind::ExportDiagnostics)
        );
        assert!(
            !actions
                .iter()
                .any(|action| action.kind == RecoveryActionKind::OpenDataDirectory)
        );

        let configuration_error = crate::startup::configuration_error(trace);
        let actions = recovery_actions_for(
            &resources,
            StartupPhase::SettingsInitialization,
            &configuration_error,
        );
        assert!(
            !actions
                .iter()
                .any(|action| action.kind == RecoveryActionKind::ResetAppearanceSettings)
        );
    }

    #[test]
    fn shutdown_cancellation_stops_later_phases() {
        let directory = tempfile::tempdir().expect("temporary directory");
        let options = KernelBootstrapOptions::with_data_directory(directory.path());
        let generation = RuntimeInstanceId::new();
        let boundary = EventBoundary::new();
        let clock = FakeClock::with_values((0..=32).rev().collect());
        let calls = AtomicUsize::new(0);
        let should_cancel = || calls.fetch_add(1, Ordering::SeqCst) >= 1;

        let result = StartupCoordinator::run(
            options,
            generation,
            boundary,
            &clock,
            &NoopObserver,
            &should_cancel,
            None,
            Some(Arc::new(InProcessNotificationSink::new())),
        );

        assert!(matches!(
            result.state,
            crate::RuntimeState::StartupFailed { .. }
        ));
        assert!(result.history.len() <= 1);
        assert_eq!(
            result.failure.as_ref().expect("failure").error.code,
            ErrorCode::OperationCancelled
        );
        assert_eq!(
            result.failure.as_ref().expect("failure").error.trace_id,
            result.trace_id
        );
    }

    #[test]
    fn missing_notification_sink_fails_readiness() {
        let directory = tempfile::tempdir().expect("temporary directory");
        let options = KernelBootstrapOptions::with_data_directory(directory.path());
        let generation = RuntimeInstanceId::new();
        let boundary = EventBoundary::new();
        let clock = FakeClock::with_values((0..=32).rev().collect());

        let result = StartupCoordinator::run(
            options,
            generation,
            boundary,
            &clock,
            &NoopObserver,
            &|| false,
            None,
            None,
        );

        assert!(matches!(
            result.state,
            crate::RuntimeState::StartupFailed { .. }
        ));
        assert_eq!(
            result.failure.expect("failure").phase,
            StartupPhase::EventInfrastructureInitialization
        );
    }

    #[test]
    fn unusable_notification_sink_fails_readiness() {
        let directory = tempfile::tempdir().expect("temporary directory");
        let options = KernelBootstrapOptions::with_data_directory(directory.path());
        let generation = RuntimeInstanceId::new();
        let boundary = EventBoundary::new();
        let clock = FakeClock::with_values((0..=32).rev().collect());

        let result = StartupCoordinator::run(
            options,
            generation,
            boundary,
            &clock,
            &NoopObserver,
            &|| false,
            None,
            Some(Arc::new(FailingSink)),
        );

        assert!(matches!(
            result.state,
            crate::RuntimeState::StartupFailed { .. }
        ));
        assert_eq!(
            result.failure.expect("failure").phase,
            StartupPhase::EventInfrastructureInitialization
        );
    }

    #[test]
    fn cleanup_stack_runs_lifo_and_keeps_primary_error() {
        let order = std::sync::Arc::new(std::sync::Mutex::new(Vec::new()));
        let mut coordinator = StartupCoordinator::new(KernelBootstrapOptions::default());
        coordinator.resources.diagnostics_ready = true;
        let order1 = std::sync::Arc::clone(&order);
        coordinator.push_cleanup_for_tests(Box::new(move |_| {
            order1.lock().expect("order").push("cleanup1");
            Ok(())
        }));
        let order2 = std::sync::Arc::clone(&order);
        coordinator.push_cleanup_for_tests(Box::new(move |_| {
            order2.lock().expect("order").push("cleanup2");
            Err(CleanupError)
        }));
        let order3 = std::sync::Arc::clone(&order);
        coordinator.push_cleanup_for_tests(Box::new(move |_| {
            order3.lock().expect("order").push("cleanup3");
            Ok(())
        }));

        let trace_id = coordinator.trace_id;
        let result = coordinator.finish_failed(configuration_error(trace_id));

        assert_eq!(
            *order.lock().expect("order"),
            vec!["cleanup3", "cleanup2", "cleanup1"]
        );
        let failure = result.failure.expect("failure");
        assert_eq!(failure.error.code, ErrorCode::ConfigurationInvalid);
        let recovery = result.recovery_context.expect("recovery context");
        let diagnostics = recovery.diagnostics.expect("diagnostics");
        assert!(
            diagnostics
                .collector
                .logs()
                .iter()
                .any(|log| log.event_name.as_str() == "runtime.startup.cleanup.failed"),
            "secondary cleanup failure must be retained"
        );

        let directory = tempfile::tempdir().expect("tempdir");
        let destination = directory.path().join("cleanup-diagnostics.zip");
        let export = export_with_contributors(
            &diagnostics,
            RuntimeInstanceId::new(),
            &destination,
            trace_id,
            Vec::new(),
        )
        .expect("export");
        assert_eq!(export.outcome, crate::DiagnosticsExportOutcome::Created);
        let file = std::fs::File::open(destination).expect("archive");
        let mut archive = zip::ZipArchive::new(file).expect("zip");
        let mut logs = String::new();
        archive
            .by_name("logs/argus.ndjson")
            .expect("logs")
            .read_to_string(&mut logs)
            .expect("read logs");
        assert!(
            logs.contains("runtime.startup.cleanup.failed"),
            "exported logs must contain bounded secondary cleanup evidence"
        );
    }
}
