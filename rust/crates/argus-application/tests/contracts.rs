use std::cell::Cell;
use std::marker::PhantomData;
use std::rc::Rc;

mod common;

use argus_application::{
    AppearanceSettings, AppearanceSettingsRepository, ApplicationError, ApplicationPortError,
    ApplicationSeverity, ErrorCategory, ErrorCode, EventName, LibrarySourceId,
    LibrarySourceRepository, LogEvent, LogLevel, ObservabilitySink, OperationContext,
    OperationName, PathClass, PersistenceError, Recoverability, RetryPolicy, SafeContext,
    SafeContextError, SafeContextField, SafeContextValue, StartupCollector, SubsystemName,
    ThemeMode, TraceEvent, TraceEventPhase, TraceId, TraceIdError, UnitOfWork, UnitOfWorkFactory,
    Version,
};
use common::{
    NoopJobRunRepository, NoopLibraryRootRepository, NoopLibraryScanAdmissionContextRepository,
    NoopLibraryScanTargetRepository, NoopScanRunRepository, NoopSourceEntryRepository,
};

fn trace_id() -> TraceId {
    TraceId::try_from([
        0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70, 0x80, 0x90, 0xa0, 0xb0, 0xc0, 0xd0, 0xe0, 0xf0, 1,
    ])
    .expect("non-zero trace id")
}

fn context() -> OperationContext {
    OperationContext::new(
        trace_id(),
        SubsystemName::try_from("runtime").expect("valid subsystem"),
        OperationName::try_from("startup").expect("valid operation"),
    )
}

#[test]
fn trace_id_rejects_zero_and_formats_lowercase_hex() {
    assert_eq!(TraceId::try_from([0; 16]), Err(TraceIdError::Zero));
    assert_eq!(trace_id().to_string(), "102030405060708090a0b0c0d0e0f001");
}

#[test]
fn safe_context_accepts_closed_typed_fields_and_rejects_hostile_values() {
    let mut fields = SafeContext::new();
    fields
        .try_insert(
            SafeContextField::PathClass,
            SafeContextValue::PathClass(PathClass::ExplicitOverride),
        )
        .expect("typed field");
    assert_eq!(
        fields.try_insert(
            SafeContextField::PathClass,
            SafeContextValue::PathClass(PathClass::StandardApplicationData),
        ),
        Err(SafeContextError::DuplicateField)
    );
    assert_eq!(
        fields.try_insert(SafeContextField::Stage, SafeContextValue::MigrationCount(1),),
        Err(SafeContextError::WrongValueType)
    );
    assert!(Version::try_from("/Users/tester/private.sqlite3").is_err());
    assert!(Version::try_from(r"C:\Users\tester\private.sqlite3").is_err());
    assert!(Version::try_from("SELECT secret FROM users").is_err());
    assert!(Version::try_from("token=secret").is_err());
}

#[test]
fn currently_implemented_phase_000_catalog_subset_contains_codes_and_metadata() {
    let expected = [
        (
            ErrorCode::ValidationInvalidArgument,
            "ARGUS.V1.VALIDATION.INVALID_ARGUMENT",
            ErrorCategory::Validation,
            ApplicationSeverity::Warning,
            Recoverability::UserAction,
            RetryPolicy::Never,
            "errors.validation.invalid_argument",
        ),
        (
            ErrorCode::ConfigurationInvalid,
            "ARGUS.V1.CONFIGURATION.INVALID",
            ErrorCategory::Configuration,
            ApplicationSeverity::Error,
            Recoverability::UserAction,
            RetryPolicy::Never,
            "errors.configuration.invalid",
        ),
        (
            ErrorCode::ConfigurationPersistedSettingsInvalid,
            "ARGUS.V1.CONFIGURATION.PERSISTED_SETTINGS_INVALID",
            ErrorCategory::Configuration,
            ApplicationSeverity::Error,
            Recoverability::UserAction,
            RetryPolicy::UserInitiated,
            "errors.configuration.persisted_settings_invalid",
        ),
        (
            ErrorCode::FilesystemPermissionDenied,
            "ARGUS.V1.FILESYSTEM.PERMISSION_DENIED",
            ErrorCategory::Filesystem,
            ApplicationSeverity::Error,
            Recoverability::UserAction,
            RetryPolicy::UserInitiated,
            "errors.filesystem.permission_denied",
        ),
        (
            ErrorCode::PersistenceDatabaseOpenFailed,
            "ARGUS.V1.PERSISTENCE.DATABASE_OPEN_FAILED",
            ErrorCategory::Persistence,
            ApplicationSeverity::Error,
            Recoverability::Retry,
            RetryPolicy::Backoff,
            "errors.persistence.database_open_failed",
        ),
        (
            ErrorCode::PersistenceDatabaseLocked,
            "ARGUS.V1.PERSISTENCE.DATABASE_LOCKED",
            ErrorCategory::Persistence,
            ApplicationSeverity::Warning,
            Recoverability::Retry,
            RetryPolicy::Backoff,
            "errors.persistence.database_locked",
        ),
        (
            ErrorCode::PersistenceMigrationFailed,
            "ARGUS.V1.PERSISTENCE.MIGRATION_FAILED",
            ErrorCategory::Persistence,
            ApplicationSeverity::Error,
            Recoverability::ManualIntervention,
            RetryPolicy::UserInitiated,
            "errors.persistence.migration_failed",
        ),
        (
            ErrorCode::PersistenceIncompatibleSchema,
            "ARGUS.V1.PERSISTENCE.INCOMPATIBLE_SCHEMA",
            ErrorCategory::Persistence,
            ApplicationSeverity::Error,
            Recoverability::ManualIntervention,
            RetryPolicy::Never,
            "errors.persistence.incompatible_schema",
        ),
        (
            ErrorCode::InternalUnexpected,
            "ARGUS.V1.INTERNAL.UNEXPECTED",
            ErrorCategory::Internal,
            ApplicationSeverity::Error,
            Recoverability::ManualIntervention,
            RetryPolicy::Never,
            "errors.internal.unexpected",
        ),
    ];
    assert_eq!(ErrorCode::all().len(), expected.len());
    for (code, name, category, severity, recoverability, retry, message) in expected {
        assert_eq!(code.as_str(), name);
        let policy = code.policy();
        assert_eq!(policy.category, category);
        assert_eq!(policy.severity, severity);
        assert_eq!(policy.recoverability, recoverability);
        assert_eq!(policy.retry_policy, retry);
        assert_eq!(policy.message_key.as_str(), message);
        ApplicationError::from_code(code, trace_id(), SafeContext::new()).expect("catalog entry");
    }
}

#[test]
fn phase_000_catalog_snapshot_is_exact() {
    let expected: [(
        &str,
        ErrorCategory,
        ApplicationSeverity,
        Recoverability,
        RetryPolicy,
        &str,
    ); 18] = [
        (
            "ARGUS.V1.VALIDATION.INVALID_ARGUMENT",
            ErrorCategory::Validation,
            ApplicationSeverity::Warning,
            Recoverability::UserAction,
            RetryPolicy::Never,
            "errors.validation.invalid_argument",
        ),
        (
            "ARGUS.V1.CONFIGURATION.INVALID",
            ErrorCategory::Configuration,
            ApplicationSeverity::Error,
            Recoverability::UserAction,
            RetryPolicy::Never,
            "errors.configuration.invalid",
        ),
        (
            "ARGUS.V1.CONFIGURATION.PERSISTED_SETTINGS_INVALID",
            ErrorCategory::Configuration,
            ApplicationSeverity::Error,
            Recoverability::UserAction,
            RetryPolicy::UserInitiated,
            "errors.configuration.persisted_settings_invalid",
        ),
        (
            "ARGUS.V1.PERSISTENCE.DATABASE_OPEN_FAILED",
            ErrorCategory::Persistence,
            ApplicationSeverity::Error,
            Recoverability::Retry,
            RetryPolicy::Backoff,
            "errors.persistence.database_open_failed",
        ),
        (
            "ARGUS.V1.PERSISTENCE.DATABASE_LOCKED",
            ErrorCategory::Persistence,
            ApplicationSeverity::Warning,
            Recoverability::Retry,
            RetryPolicy::Backoff,
            "errors.persistence.database_locked",
        ),
        (
            "ARGUS.V1.PERSISTENCE.MIGRATION_FAILED",
            ErrorCategory::Persistence,
            ApplicationSeverity::Error,
            Recoverability::ManualIntervention,
            RetryPolicy::UserInitiated,
            "errors.persistence.migration_failed",
        ),
        (
            "ARGUS.V1.PERSISTENCE.INCOMPATIBLE_SCHEMA",
            ErrorCategory::Persistence,
            ApplicationSeverity::Error,
            Recoverability::ManualIntervention,
            RetryPolicy::Never,
            "errors.persistence.incompatible_schema",
        ),
        (
            "ARGUS.V1.FILESYSTEM.PERMISSION_DENIED",
            ErrorCategory::Filesystem,
            ApplicationSeverity::Error,
            Recoverability::UserAction,
            RetryPolicy::UserInitiated,
            "errors.filesystem.permission_denied",
        ),
        (
            "ARGUS.V1.RUNTIME.BRIDGE_INITIALIZATION_FAILED",
            ErrorCategory::Runtime,
            ApplicationSeverity::Error,
            Recoverability::RestartRequired,
            RetryPolicy::UserInitiated,
            "errors.runtime.bridge_initialization_failed",
        ),
        (
            "ARGUS.V1.RUNTIME.CORE_SERVICE_INITIALIZATION_FAILED",
            ErrorCategory::Runtime,
            ApplicationSeverity::Error,
            Recoverability::RestartRequired,
            RetryPolicy::UserInitiated,
            "errors.runtime.core_service_initialization_failed",
        ),
        (
            "ARGUS.V1.RUNTIME.NOT_READY",
            ErrorCategory::Runtime,
            ApplicationSeverity::Warning,
            Recoverability::Retry,
            RetryPolicy::UserInitiated,
            "errors.runtime.not_ready",
        ),
        (
            "ARGUS.V1.RUNTIME.STARTUP_FAILED",
            ErrorCategory::Runtime,
            ApplicationSeverity::Error,
            Recoverability::RestartRequired,
            RetryPolicy::UserInitiated,
            "errors.runtime.startup_failed",
        ),
        (
            "ARGUS.V1.RUNTIME.SHUTTING_DOWN",
            ErrorCategory::Runtime,
            ApplicationSeverity::Warning,
            Recoverability::RestartRequired,
            RetryPolicy::UserInitiated,
            "errors.runtime.shutting_down",
        ),
        (
            "ARGUS.V1.RUNTIME.STOPPED",
            ErrorCategory::Runtime,
            ApplicationSeverity::Warning,
            Recoverability::RestartRequired,
            RetryPolicy::UserInitiated,
            "errors.runtime.stopped",
        ),
        (
            "ARGUS.V1.RUNTIME.STALE_INSTANCE",
            ErrorCategory::Runtime,
            ApplicationSeverity::Warning,
            Recoverability::UserAction,
            RetryPolicy::Never,
            "errors.runtime.stale_instance",
        ),
        (
            "ARGUS.V1.OPERATION.CANCELLED",
            ErrorCategory::Operation,
            ApplicationSeverity::Info,
            Recoverability::None,
            RetryPolicy::Never,
            "errors.operation.cancelled",
        ),
        (
            "ARGUS.V1.INTERNAL.UNEXPECTED",
            ErrorCategory::Internal,
            ApplicationSeverity::Error,
            Recoverability::ManualIntervention,
            RetryPolicy::Never,
            "errors.internal.unexpected",
        ),
        (
            "ARGUS.V1.INTERNAL.INVARIANT_VIOLATION",
            ErrorCategory::Internal,
            ApplicationSeverity::Fatal,
            Recoverability::RestartRequired,
            RetryPolicy::Never,
            "errors.internal.invariant_violation",
        ),
    ];

    assert_eq!(ErrorCode::phase_000_all().len(), expected.len());
    for (code, (name, category, severity, recoverability, retry, message)) in
        ErrorCode::phase_000_all().iter().zip(expected.iter())
    {
        assert_eq!(code.as_str(), *name);
        let policy = code.policy();
        assert_eq!(policy.category, *category);
        assert_eq!(policy.severity, *severity);
        assert_eq!(policy.recoverability, *recoverability);
        assert_eq!(policy.retry_policy, *retry);
        assert_eq!(policy.message_key.as_str(), *message);
        ApplicationError::from_code(*code, trace_id(), SafeContext::new()).expect("catalog entry");
    }
}

#[test]
fn phase_001_catalog_snapshot_is_additive_and_exact() {
    let phase_000 = ErrorCode::phase_000_all();
    let phase_001 = ErrorCode::phase_001_all();

    assert_eq!(phase_001.len(), phase_000.len() + 5);
    assert_eq!(&phase_001[..phase_000.len()], phase_000);

    let expected: [(
        &str,
        ErrorCategory,
        ApplicationSeverity,
        Recoverability,
        RetryPolicy,
        &str,
    ); 5] = [
        (
            "ARGUS.V1.CONFIGURATION.LIBRARY_ROOT_NOT_FOUND",
            ErrorCategory::Configuration,
            ApplicationSeverity::Error,
            Recoverability::UserAction,
            RetryPolicy::Never,
            "errors.configuration.library_root_not_found",
        ),
        (
            "ARGUS.V1.FILESYSTEM.INVALID_ROOT_SELECTION",
            ErrorCategory::Filesystem,
            ApplicationSeverity::Error,
            Recoverability::UserAction,
            RetryPolicy::Never,
            "errors.filesystem.invalid_root_selection",
        ),
        (
            "ARGUS.V1.JOBS.JOB_RUN_NOT_FOUND",
            ErrorCategory::Operation,
            ApplicationSeverity::Warning,
            Recoverability::UserAction,
            RetryPolicy::Never,
            "errors.jobs.job_run_not_found",
        ),
        (
            "ARGUS.V1.OPERATION.CAPACITY_UNAVAILABLE",
            ErrorCategory::Operation,
            ApplicationSeverity::Warning,
            Recoverability::Retry,
            RetryPolicy::UserInitiated,
            "errors.operation.capacity_unavailable",
        ),
        (
            "ARGUS.V1.CONFIGURATION.SOURCE_ENTRY_NOT_FOUND",
            ErrorCategory::Configuration,
            ApplicationSeverity::Error,
            Recoverability::UserAction,
            RetryPolicy::Never,
            "errors.configuration.source_entry_not_found",
        ),
    ];

    for (code, (name, category, severity, recoverability, retry, message)) in
        phase_001[phase_000.len()..].iter().zip(expected.iter())
    {
        assert_eq!(code.as_str(), *name);
        let policy = code.policy();
        assert_eq!(policy.category, *category);
        assert_eq!(policy.severity, *severity);
        assert_eq!(policy.recoverability, *recoverability);
        assert_eq!(policy.retry_policy, *retry);
        assert_eq!(policy.message_key.as_str(), *message);
        ApplicationError::from_code(*code, trace_id(), SafeContext::new()).expect("catalog entry");
    }
}

#[test]
fn application_error_enforces_catalog_owned_context_policy() {
    let mut fields = SafeContext::new();
    fields
        .try_insert(
            SafeContextField::MigrationCount,
            SafeContextValue::MigrationCount(2),
        )
        .expect("typed field");
    assert!(
        ApplicationError::from_code(ErrorCode::ConfigurationInvalid, trace_id(), fields,).is_err()
    );
    assert_eq!(
        PersistenceError::MigrationFailed.category(),
        ErrorCategory::Persistence
    );
}

#[test]
fn log_and_trace_records_are_separate() {
    let event_name = EventName::try_from("runtime.startup.started").expect("valid event");
    let fields = SafeContext::new();
    let mut collector = StartupCollector::new();
    collector
        .record_log(LogEvent::new(
            1,
            LogLevel::Info,
            context(),
            event_name.clone(),
            fields.clone(),
            None,
        ))
        .expect("log");
    collector
        .record_trace(TraceEvent::new(
            1,
            context(),
            event_name,
            TraceEventPhase::Started,
            fields,
            None,
            None,
        ))
        .expect("trace");
    assert_eq!(collector.logs().len(), 1);
    assert_eq!(collector.traces().len(), 1);
}

struct RecordingUnitOfWork<'scope> {
    terminal_action: Rc<Cell<Option<&'static str>>>,
    terminal: bool,
    marker: PhantomData<&'scope mut ()>,
}

struct NoopAppearanceRepository<'scope> {
    marker: PhantomData<&'scope mut ()>,
}

impl AppearanceSettingsRepository for NoopAppearanceRepository<'_> {
    fn get(&mut self) -> Result<AppearanceSettings, PersistenceError> {
        Ok(AppearanceSettings::new(ThemeMode::System))
    }

    fn save(&mut self, _settings: &AppearanceSettings) -> Result<(), PersistenceError> {
        Ok(())
    }
}

struct NoopLibrarySourceRepository<'scope> {
    marker: PhantomData<&'scope mut ()>,
}

impl LibrarySourceRepository for NoopLibrarySourceRepository<'_> {
    fn ensure_local_filesystem_source(&mut self) -> Result<LibrarySourceId, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }
}

impl UnitOfWork for RecordingUnitOfWork<'_> {
    type AppearanceSettingsRepository<'scope>
        = NoopAppearanceRepository<'scope>
    where
        Self: 'scope;
    type LibrarySourceRepository<'scope>
        = NoopLibrarySourceRepository<'scope>
    where
        Self: 'scope;
    type LibraryRootRepository<'scope>
        = NoopLibraryRootRepository<'scope>
    where
        Self: 'scope;
    type JobRunRepository<'scope>
        = NoopJobRunRepository<'scope>
    where
        Self: 'scope;
    type ScanRunRepository<'scope>
        = NoopScanRunRepository<'scope>
    where
        Self: 'scope;
    type SourceEntryRepository<'scope>
        = NoopSourceEntryRepository<'scope>
    where
        Self: 'scope;
    type LibraryScanTargetRepository<'scope>
        = NoopLibraryScanTargetRepository<'scope>
    where
        Self: 'scope;
    type LibraryScanAdmissionContextRepository<'scope>
        = NoopLibraryScanAdmissionContextRepository<'scope>
    where
        Self: 'scope;

    fn appearance_settings(&mut self) -> Self::AppearanceSettingsRepository<'_> {
        NoopAppearanceRepository {
            marker: PhantomData,
        }
    }

    fn library_source(&mut self) -> Self::LibrarySourceRepository<'_> {
        NoopLibrarySourceRepository {
            marker: PhantomData,
        }
    }

    fn library_roots(&mut self) -> Self::LibraryRootRepository<'_> {
        NoopLibraryRootRepository {
            marker: PhantomData,
        }
    }

    fn job_runs(&mut self) -> Self::JobRunRepository<'_> {
        NoopJobRunRepository {
            marker: PhantomData,
        }
    }

    fn scan_runs(&mut self) -> Self::ScanRunRepository<'_> {
        NoopScanRunRepository {
            marker: PhantomData,
        }
    }

    fn source_entries(&mut self) -> Self::SourceEntryRepository<'_> {
        NoopSourceEntryRepository {
            marker: PhantomData,
        }
    }

    fn library_scan_targets(&mut self) -> Self::LibraryScanTargetRepository<'_> {
        NoopLibraryScanTargetRepository {
            marker: PhantomData,
        }
    }

    fn library_scan_admission_context(
        &mut self,
    ) -> Self::LibraryScanAdmissionContextRepository<'_> {
        NoopLibraryScanAdmissionContextRepository {
            marker: PhantomData,
        }
    }

    fn commit(mut self) -> Result<(), ApplicationPortError> {
        self.terminal = true;
        self.terminal_action.set(Some("commit"));
        Ok(())
    }

    fn rollback(mut self) -> Result<(), ApplicationPortError> {
        self.terminal = true;
        self.terminal_action.set(Some("rollback"));
        Ok(())
    }
}

impl Drop for RecordingUnitOfWork<'_> {
    fn drop(&mut self) {
        if !self.terminal {
            self.terminal_action.set(Some("rollback"));
        }
    }
}

struct RecordingFactory {
    terminal_action: Rc<Cell<Option<&'static str>>>,
}

impl UnitOfWorkFactory for RecordingFactory {
    type Scope<'scope> = RecordingUnitOfWork<'scope>;

    fn execute<T, F>(
        &self,
        _context: &OperationContext,
        operation: F,
    ) -> Result<T, ApplicationPortError>
    where
        T: Send + 'static,
        F: for<'scope> FnOnce(Self::Scope<'scope>) -> Result<T, ApplicationPortError>
            + Send
            + 'static,
    {
        operation(RecordingUnitOfWork {
            terminal_action: self.terminal_action.clone(),
            terminal: false,
            marker: PhantomData,
        })
    }
}

#[test]
fn consuming_uow_requires_explicit_terminal_action() {
    let terminal_action = Rc::new(Cell::new(None));
    let factory = RecordingFactory {
        terminal_action: terminal_action.clone(),
    };
    factory
        .execute(&context(), |scope| {
            scope.commit()?;
            Ok::<_, ApplicationPortError>(())
        })
        .expect("commit");
    assert_eq!(terminal_action.get(), Some("commit"));

    terminal_action.set(None);
    factory
        .execute(&context(), |_scope| Ok::<_, ApplicationPortError>(()))
        .expect("drop rollback");
    assert_eq!(terminal_action.get(), Some("rollback"));
}

/// ```compile_fail
/// use argus_application::{ApplicationPortError, OperationContext, UnitOfWorkFactory};
/// fn reuse_is_rejected<F: UnitOfWorkFactory>(factory: &F, context: &OperationContext) {
///     let _ = factory.execute(context, |scope| {
///         let _ = scope.commit();
///         let _ = scope.rollback();
///         Ok::<(), ApplicationPortError>(())
///     });
/// }
/// ```
fn _compile_fail_scope_reuse() {}
