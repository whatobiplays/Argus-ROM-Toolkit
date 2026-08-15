use std::path::PathBuf;

use argus_application::{
    ApplicationPortError, ErrorCode, FailureRole, OperationContext, OperationName, PathClass,
    SafeContextField, SafeContextValue, SubsystemName, TraceEventPhase, TraceId, UnitOfWork,
    UnitOfWorkFactory,
};
use argus_runtime::{KernelBootstrapOptions, bootstrap_kernel};
use tempfile::tempdir;

#[test]
fn persistence_startup_failure_is_sanitized_and_classified() {
    let directory = tempdir().expect("temporary directory");
    let data_root = directory.path().join("persistence-failure");
    std::fs::create_dir_all(data_root.join("argus.sqlite3")).expect("database path directory");
    let options = KernelBootstrapOptions {
        data_directory_override: Some(data_root.clone()),
    };
    let failure = match bootstrap_kernel(options) {
        Ok(kernel) => {
            let _ = kernel.shutdown();
            panic!("database directory unexpectedly opened")
        }
        Err(failure) => failure,
    };
    assert_eq!(
        failure.stage(),
        argus_runtime::KernelBootstrapStage::Persistence
    );
    assert_eq!(
        failure.error().code,
        ErrorCode::PersistenceDatabaseOpenFailed
    );
    assert_ne!(
        failure.trace_id().to_string(),
        "00000000000000000000000000000000"
    );
    assert_eq!(
        failure
            .events()
            .iter()
            .filter(|event| event.event_name.as_str() == "runtime.startup.failed")
            .count(),
        1
    );
    assert_eq!(
        failure
            .logs()
            .iter()
            .filter(|event| event.level == argus_application::LogLevel::Error)
            .count(),
        1
    );
    let diagnostic = format!("{:?}", failure.error());
    assert!(!diagnostic.contains(data_root.to_string_lossy().as_ref()));
    assert!(!diagnostic.contains("argus.sqlite3"));
    assert!(!diagnostic.contains("CREATE TABLE"));
    assert!(!diagnostic.contains("sqlite3_open"));
}

#[test]
fn bootstrap_reports_sanitized_path_class_and_ordered_startup_diagnostics() {
    let directory = tempdir().expect("temporary directory");
    let kernel = bootstrap_kernel(KernelBootstrapOptions::with_data_directory(
        directory.path().join("data"),
    ))
    .expect("bootstrap kernel");
    assert_ne!(
        kernel.trace_id().to_string(),
        "00000000000000000000000000000000"
    );
    assert_eq!(kernel.path_class(), PathClass::ExplicitOverride);
    assert_eq!(kernel.migration_summary().current_version, 5);

    let names: Vec<_> = kernel
        .startup_events()
        .iter()
        .map(|event| event.event_name.as_str())
        .collect();
    assert_eq!(
        names,
        vec![
            "runtime.startup.started",
            "runtime.startup.environment",
            "database.migration.completed",
            "runtime.kernel.initialized",
        ]
    );
    assert!(names.iter().all(|name| *name != "runtime.started"));
    for event in kernel.startup_events() {
        assert_eq!(event.context.trace_id(), kernel.trace_id());
    }
    let environment = &kernel.startup_events()[1].fields;
    assert!(
        environment
            .get(&SafeContextField::ApplicationVersion)
            .is_some()
    );
    assert!(environment.get(&SafeContextField::BackendVersion).is_some());
    assert!(environment.get(&SafeContextField::Platform).is_some());
    assert!(environment.get(&SafeContextField::Architecture).is_some());
    assert_eq!(
        environment.get(&SafeContextField::PathClass),
        Some(&SafeContextValue::PathClass(PathClass::ExplicitOverride))
    );
    let migration = &kernel.startup_events()[2].fields;
    assert!(migration.get(&SafeContextField::MigrationCount).is_some());
    assert!(migration.get(&SafeContextField::SchemaVersion).is_some());
    assert!(migration.get(&SafeContextField::MigrationOutcome).is_some());
    assert_eq!(kernel.startup_logs().len(), kernel.startup_events().len());
    assert!(kernel.startup_logs().iter().all(|event| {
        event.context.trace_id() == kernel.trace_id()
            && event.level == argus_application::LogLevel::Info
    }));

    let context = OperationContext::new(
        TraceId::try_from([2; 16]).expect("trace"),
        SubsystemName::try_from("runtime").expect("subsystem"),
        OperationName::try_from("kernel").expect("operation"),
    );
    assert_eq!(
        kernel
            .execute(&context, |work| {
                work.commit()?;
                Ok::<_, ApplicationPortError>(7_u8)
            })
            .expect("unit of work"),
        7
    );
    kernel.shutdown().expect("shutdown kernel");
}

#[test]
fn bootstrap_failure_has_one_primary_error_log_and_one_terminal_failed_trace() {
    let options = KernelBootstrapOptions::with_data_directory(PathBuf::from("relative/path"));
    let failure = match bootstrap_kernel(options) {
        Ok(kernel) => {
            let _ = kernel.shutdown();
            panic!("relative directory unexpectedly bootstrapped")
        }
        Err(failure) => failure,
    };
    assert_ne!(
        failure.trace_id().to_string(),
        "00000000000000000000000000000000"
    );
    assert!(!failure.to_string().contains("relative/path"));
    let failed: Vec<_> = failure
        .events()
        .iter()
        .filter(|event| event.event_name.as_str() == "runtime.startup.failed")
        .collect();
    assert_eq!(failed.len(), 1);
    assert_eq!(failed[0].phase, TraceEventPhase::Failed);
    assert_eq!(failed[0].error_code, Some(ErrorCode::ConfigurationInvalid));
    assert_eq!(
        failed[0].fields.get(&SafeContextField::FailureRole),
        Some(&SafeContextValue::FailureRole(FailureRole::Primary))
    );
    assert!(
        failure
            .events()
            .iter()
            .all(|event| event.context.trace_id() == failure.trace_id())
    );
    let primary_errors: Vec<_> = failure
        .logs()
        .iter()
        .filter(|event| event.level == argus_application::LogLevel::Error)
        .collect();
    assert_eq!(primary_errors.len(), 1);
    assert_eq!(
        primary_errors[0].application_error.as_ref(),
        Some(failure.error())
    );
    assert_eq!(
        primary_errors[0].fields.get(&SafeContextField::FailureRole),
        Some(&SafeContextValue::FailureRole(FailureRole::Primary))
    );
}
