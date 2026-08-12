use std::cell::Cell;
use std::marker::PhantomData;
use std::rc::Rc;

use argus_application::{
    ApplicationError, ApplicationPortError, ApplicationSeverity, ArchitectureClass, ErrorCategory,
    ErrorCode, FailureRole, LogEvent, LogLevel, MigrationOutcome, ObservabilitySink,
    OperationContext, OperationName, PathClass, PlatformClass, Recoverability, RetryPolicy,
    SafeContext, SafeContextError, SafeContextField, SafeContextValue, StartupCollector,
    TechnicalClass, TraceEvent, TraceEventPhase, TraceId, TraceIdError, UnitOfWork,
    UnitOfWorkFactory, Version,
};

fn context() -> OperationContext {
    OperationContext::new(
        TraceId::try_from([1; 16]).expect("non-zero trace"),
        argus_application::SubsystemName::try_from("test").expect("subsystem"),
        OperationName::try_from("contract").expect("operation"),
    )
}

#[test]
fn trace_id_uses_nonzero_bytes_and_exact_lowercase_hex() {
    assert_eq!(TraceId::try_from([0; 16]), Err(TraceIdError::Zero));
    assert_eq!(
        TraceId::try_from([0xab; 16]).expect("trace").to_string(),
        "abababababababababababababababab"
    );
}

#[test]
fn safe_context_is_closed_typed_bounded_and_rejects_duplicates() {
    let mut context = SafeContext::new();
    context
        .try_insert(
            SafeContextField::Stage,
            SafeContextValue::Stage(argus_application::DiagnosticStage::Persistence),
        )
        .expect("stage");
    assert_eq!(
        context.try_insert(
            SafeContextField::Stage,
            SafeContextValue::Stage(argus_application::DiagnosticStage::Environment),
        ),
        Err(SafeContextError::DuplicateField)
    );
    assert_eq!(
        context.try_insert(SafeContextField::Stage, SafeContextValue::MigrationCount(1),),
        Err(SafeContextError::WrongValueType)
    );
    assert!(Version::try_from("/Users/private").is_err());
    assert!(Version::try_from(r"C:\Users\private").is_err());
    assert!(Version::try_from("SELECT").is_err());
    assert!(Version::try_from("password").is_err());
    assert!(Version::try_from("secret").is_err());
    assert!(Version::try_from("token").is_err());
    assert!(Version::try_from("api_key").is_err());
}

#[test]
fn safe_context_accepts_each_slice_002_field_with_its_declared_value() {
    let mut context = SafeContext::new();
    let values = [
        (
            SafeContextField::Stage,
            SafeContextValue::Stage(argus_application::DiagnosticStage::Environment),
        ),
        (
            SafeContextField::PathClass,
            SafeContextValue::PathClass(PathClass::ExplicitOverride),
        ),
        (
            SafeContextField::MigrationCount,
            SafeContextValue::MigrationCount(1),
        ),
        (
            SafeContextField::SchemaVersion,
            SafeContextValue::SchemaVersion(1),
        ),
        (
            SafeContextField::MigrationOutcome,
            SafeContextValue::MigrationOutcome(MigrationOutcome::Applied),
        ),
        (
            SafeContextField::ApplicationVersion,
            SafeContextValue::ApplicationVersion(Version::try_from("0.1.0").expect("version")),
        ),
        (
            SafeContextField::BackendVersion,
            SafeContextValue::BackendVersion(Version::try_from("0.1.0").expect("version")),
        ),
        (
            SafeContextField::Platform,
            SafeContextValue::Platform(PlatformClass::Unix),
        ),
        (
            SafeContextField::Architecture,
            SafeContextValue::Architecture(ArchitectureClass::X8664),
        ),
        (
            SafeContextField::TechnicalClass,
            SafeContextValue::TechnicalClass(TechnicalClass::Internal),
        ),
        (
            SafeContextField::FailureRole,
            SafeContextValue::FailureRole(FailureRole::Primary),
        ),
    ];
    for (field, value) in values {
        context.try_insert(field, value).expect("declared field");
    }
    assert_eq!(context.len(), 11);
}

#[test]
fn safe_context_rejects_wrong_value_types_for_every_closed_field() {
    let wrong_values = [
        (
            SafeContextField::Stage,
            SafeContextValue::PathClass(PathClass::ExplicitOverride),
        ),
        (
            SafeContextField::PathClass,
            SafeContextValue::Stage(argus_application::DiagnosticStage::Environment),
        ),
        (
            SafeContextField::MigrationCount,
            SafeContextValue::SchemaVersion(1),
        ),
        (
            SafeContextField::SchemaVersion,
            SafeContextValue::MigrationCount(1),
        ),
        (
            SafeContextField::MigrationOutcome,
            SafeContextValue::FailureRole(FailureRole::Primary),
        ),
        (
            SafeContextField::ApplicationVersion,
            SafeContextValue::BackendVersion(Version::try_from("0.1.0").unwrap()),
        ),
        (
            SafeContextField::BackendVersion,
            SafeContextValue::ApplicationVersion(Version::try_from("0.1.0").unwrap()),
        ),
        (
            SafeContextField::Platform,
            SafeContextValue::Architecture(ArchitectureClass::X8664),
        ),
        (
            SafeContextField::Architecture,
            SafeContextValue::Platform(PlatformClass::Unix),
        ),
        (
            SafeContextField::TechnicalClass,
            SafeContextValue::FailureRole(FailureRole::Primary),
        ),
        (
            SafeContextField::FailureRole,
            SafeContextValue::TechnicalClass(TechnicalClass::Internal),
        ),
    ];
    for (field, value) in wrong_values {
        assert_eq!(
            SafeContext::new().try_insert(field, value),
            Err(SafeContextError::WrongValueType),
            "field {field:?} accepted a mismatched value"
        );
    }
}

#[test]
fn application_catalog_contains_exactly_the_seven_slice_002_codes() {
    let codes = ErrorCode::all();
    assert_eq!(codes.len(), 7);
    let names: Vec<_> = codes.iter().map(|code| code.as_str()).collect();
    assert_eq!(
        names,
        vec![
            "ARGUS.V1.CONFIGURATION.INVALID",
            "ARGUS.V1.FILESYSTEM.PERMISSION_DENIED",
            "ARGUS.V1.PERSISTENCE.DATABASE_OPEN_FAILED",
            "ARGUS.V1.PERSISTENCE.DATABASE_LOCKED",
            "ARGUS.V1.PERSISTENCE.MIGRATION_FAILED",
            "ARGUS.V1.PERSISTENCE.INCOMPATIBLE_SCHEMA",
            "ARGUS.V1.INTERNAL.UNEXPECTED",
        ]
    );
    assert!(names.iter().all(|code| code.starts_with("ARGUS.V1.")));
}

#[test]
fn application_catalog_policies_are_exact() {
    let expected = [
        (
            ErrorCode::ConfigurationInvalid,
            ErrorCategory::Configuration,
            ApplicationSeverity::Error,
            Recoverability::UserAction,
            RetryPolicy::Never,
            "errors.configuration.invalid",
        ),
        (
            ErrorCode::FilesystemPermissionDenied,
            ErrorCategory::Filesystem,
            ApplicationSeverity::Error,
            Recoverability::UserAction,
            RetryPolicy::UserInitiated,
            "errors.filesystem.permission_denied",
        ),
        (
            ErrorCode::PersistenceDatabaseOpenFailed,
            ErrorCategory::Persistence,
            ApplicationSeverity::Error,
            Recoverability::Retry,
            RetryPolicy::Backoff,
            "errors.persistence.database_open_failed",
        ),
        (
            ErrorCode::PersistenceDatabaseLocked,
            ErrorCategory::Persistence,
            ApplicationSeverity::Warning,
            Recoverability::Retry,
            RetryPolicy::Backoff,
            "errors.persistence.database_locked",
        ),
        (
            ErrorCode::PersistenceMigrationFailed,
            ErrorCategory::Persistence,
            ApplicationSeverity::Error,
            Recoverability::ManualIntervention,
            RetryPolicy::UserInitiated,
            "errors.persistence.migration_failed",
        ),
        (
            ErrorCode::PersistenceIncompatibleSchema,
            ErrorCategory::Persistence,
            ApplicationSeverity::Error,
            Recoverability::ManualIntervention,
            RetryPolicy::Never,
            "errors.persistence.incompatible_schema",
        ),
        (
            ErrorCode::InternalUnexpected,
            ErrorCategory::Internal,
            ApplicationSeverity::Error,
            Recoverability::ManualIntervention,
            RetryPolicy::Never,
            "errors.internal.unexpected",
        ),
    ];
    for (code, category, severity, recoverability, retry, message_key) in expected {
        let policy = code.policy();
        assert_eq!(policy.category, category);
        assert_eq!(policy.severity, severity);
        assert_eq!(policy.recoverability, recoverability);
        assert_eq!(policy.retry_policy, retry);
        assert_eq!(policy.message_key.as_str(), message_key);
        assert!(policy.allowed_context_fields.len() <= SafeContextField::ALL.len());
        let error = ApplicationError::from_code(
            code,
            TraceId::try_from([1; 16]).unwrap(),
            SafeContext::new(),
        )
        .expect("empty context is valid");
        assert_eq!(error.code, code);
    }
}

#[test]
fn application_error_rejects_context_fields_not_allowed_by_catalog() {
    let mut context = SafeContext::new();
    context
        .try_insert(
            SafeContextField::MigrationCount,
            SafeContextValue::MigrationCount(1),
        )
        .expect("typed field");
    assert!(
        ApplicationError::from_code(
            ErrorCode::ConfigurationInvalid,
            TraceId::try_from([1; 16]).unwrap(),
            context,
        )
        .is_err()
    );
}

#[test]
fn startup_collector_keeps_logs_and_traces_as_separate_bounded_records() {
    let mut collector = StartupCollector::new();
    let context = context();
    let fields = SafeContext::new();
    collector
        .record_trace(TraceEvent::new(
            1,
            context.clone(),
            argus_application::EventName::try_from("runtime.startup.started").unwrap(),
            TraceEventPhase::Started,
            fields.clone(),
            None,
            None,
        ))
        .expect("trace");
    collector
        .record_log(LogEvent::new(
            1,
            LogLevel::Info,
            context,
            argus_application::EventName::try_from("runtime.startup.started").unwrap(),
            fields,
            None,
        ))
        .expect("log");
    assert_eq!(collector.traces().len(), 1);
    assert_eq!(collector.logs().len(), 1);
}

struct RecordingUnitOfWork<'scope> {
    terminal_action: Rc<Cell<Option<&'static str>>>,
    terminal: bool,
    marker: PhantomData<&'scope mut ()>,
}

impl UnitOfWork for RecordingUnitOfWork<'_> {
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
fn consuming_factory_requires_explicit_commit_and_drops_uncommitted_scope() {
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
        .expect("uncommitted scope is still a successful callback");
    assert_eq!(terminal_action.get(), Some("rollback"));
}

/// ```compile_fail
/// use argus_application::{ApplicationPortError, OperationContext, UnitOfWorkFactory};
///
/// fn reuse_is_rejected<F: UnitOfWorkFactory>(factory: &F, context: &OperationContext) {
///     let _ = factory.execute(context, |scope| {
///         let _ = scope.commit();
///         let _ = scope.rollback();
///         Ok::<(), ApplicationPortError>(())
///     });
/// }
/// ```
fn _compile_fail_scope_reuse() {}
