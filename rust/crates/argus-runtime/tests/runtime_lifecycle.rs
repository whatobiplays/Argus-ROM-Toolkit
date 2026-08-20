use std::sync::Arc;
use std::{fs::File, io::Read};

use argus_application::{
    AppearanceSettings, OperationContext, OperationName, SubsystemName, ThemeMode,
};
use argus_infrastructure::sqlite::{DEFAULT_QUEUE_CAPACITY, SqliteDatabaseExecutor};
use argus_runtime::{
    ApplicationHost, InProcessNotificationSink, KernelBootstrapOptions, NotificationSinkError,
    RecoveryActionKind, RuntimeEventPayload, RuntimeEventPublisher, RuntimeLifecycle,
    RuntimeNotificationSink, RuntimeState, STARTUP_DIAGNOSTICS_ARTIFACT_RELATIVE_PATH,
    StartupPhase,
};
use tempfile::tempdir;

fn malformed_settings_host() -> (tempfile::TempDir, ApplicationHost) {
    let directory = tempdir().expect("temporary directory");
    let options = KernelBootstrapOptions::with_data_directory(directory.path());
    let seed = ApplicationHost::new(options.clone());
    seed.initialize().expect("seed startup");
    seed.general_shutdown().expect("seed shutdown");

    let corrupt_executor = SqliteDatabaseExecutor::open_with_capacity(
        directory.path().join("argus.sqlite3"),
        DEFAULT_QUEUE_CAPACITY,
    )
    .expect("corrupt executor");
    corrupt_executor
        .with_connection_for_tests(
            OperationContext::new(
                argus_runtime::new_trace_id(),
                SubsystemName::try_from("test").expect("subsystem"),
                OperationName::try_from("corrupt_settings").expect("operation"),
            ),
            |connection| {
                connection.execute(
                    "CREATE TABLE IF NOT EXISTS unrelated_data (id INTEGER PRIMARY KEY, value TEXT NOT NULL)",
                )?;
                connection.execute(
                    "INSERT OR IGNORE INTO unrelated_data (id, value) VALUES (1, 'preserved')",
                )?;
                connection.execute("DELETE FROM appearance_settings WHERE singleton_key = 1")
            },
        )
        .expect("inject missing settings row");
    corrupt_executor.shutdown().expect("corrupt shutdown");

    let host = ApplicationHost::new(options);
    let failed = host.initialize().expect("inspectable settings failure");
    assert!(matches!(failed, RuntimeState::StartupFailed { .. }));
    let failure = failed.startup_failure().expect("failure");
    assert_eq!(
        failure.error.code.as_str(),
        "ARGUS.V1.CONFIGURATION.PERSISTED_SETTINGS_INVALID"
    );
    (directory, host)
}

#[test]
fn host_starts_a_ready_generation_through_all_mandatory_phases() {
    let directory = tempdir().expect("temporary directory");
    let host = ApplicationHost::new(KernelBootstrapOptions::with_data_directory(
        directory.path(),
    ));

    let state = host.initialize().expect("startup snapshot");
    assert_eq!(state.lifecycle(), RuntimeLifecycle::Ready);
    assert!(state.runtime_instance_id().is_nonzero());
    assert_eq!(state.startup_phase(), None);
    assert_eq!(host.startup_phases(), StartupPhase::phase_000());
    assert_eq!(host.current_state().lifecycle(), RuntimeLifecycle::Ready);
}

#[test]
fn reopened_database_stays_ready() {
    let directory = tempdir().expect("temporary directory");
    let options = KernelBootstrapOptions::with_data_directory(directory.path());
    let seed = ApplicationHost::new(options.clone());
    seed.initialize().expect("seed startup");
    seed.general_shutdown().expect("seed shutdown");
    let host = ApplicationHost::new(options);
    assert_eq!(
        host.initialize().expect("reopened startup").lifecycle(),
        RuntimeLifecycle::Ready
    );
}

#[test]
fn second_executor_open_then_host_stays_ready() {
    let directory = tempdir().expect("temporary directory");
    let options = KernelBootstrapOptions::with_data_directory(directory.path());
    let seed = ApplicationHost::new(options.clone());
    seed.initialize().expect("seed startup");
    seed.general_shutdown().expect("seed shutdown");
    let executor = SqliteDatabaseExecutor::open_with_capacity(
        directory.path().join("argus.sqlite3"),
        DEFAULT_QUEUE_CAPACITY,
    )
    .expect("second executor");
    executor.shutdown().expect("second executor shutdown");
    let host = ApplicationHost::new(options);
    assert_eq!(
        host.initialize().expect("reopened startup").lifecycle(),
        RuntimeLifecycle::Ready
    );
}

#[test]
fn failed_generation_is_inspectable_and_retry_replaces_its_identity() {
    let (_directory, host) = malformed_settings_host();

    let failed = host.current_state();
    let failed_id = failed.runtime_instance_id();
    assert_eq!(failed.lifecycle(), RuntimeLifecycle::StartupFailed);
    assert!(failed.startup_failure().is_some());
    assert!(
        failed
            .startup_failure()
            .expect("failure")
            .recovery_actions
            .iter()
            .any(|action| action.kind == RecoveryActionKind::RetryStartup)
    );

    let replacement = host.retry_startup(failed_id).expect("replacement");
    assert_ne!(replacement.runtime_instance_id(), failed_id);
    assert!(matches!(
        replacement.lifecycle(),
        RuntimeLifecycle::Ready | RuntimeLifecycle::StartupFailed
    ));
}

#[test]
fn stale_runtime_bound_recovery_is_rejected_without_retargeting() {
    let (_directory, host) = malformed_settings_host();
    let first = host.current_state();
    let first_id = first.runtime_instance_id();
    let _replacement = host.retry_startup(first_id).expect("replacement attempt");

    let error = host
        .reset_appearance_settings(first_id)
        .expect_err("stale generation");
    assert_eq!(error.code.as_str(), "ARGUS.V1.RUNTIME.STALE_INSTANCE");
    assert_ne!(host.current_state().runtime_instance_id(), first_id);
}

#[test]
fn outward_events_have_generation_sequence_and_reconnect_without_duplicates() {
    let directory = tempdir().expect("temporary directory");
    let host = Arc::new(ApplicationHost::new(
        KernelBootstrapOptions::with_data_directory(directory.path()),
    ));
    let _ = host.initialize().expect("startup");
    let first = host.subscribe_events().expect("subscription");
    let second = host
        .subscribe_events_for_generation(host.current_state().runtime_instance_id())
        .expect("same generation reconnect");
    assert_eq!(host.active_event_subscription_count(), 1);
    drop(first);
    drop(second);
    assert_eq!(host.active_event_subscription_count(), 0);
}

#[test]
fn retry_creates_fresh_generation_identity() {
    let (_directory, host) = malformed_settings_host();
    let failed = host.current_state();
    let old_id = failed.runtime_instance_id();
    let replacement = host.retry_startup(old_id).expect("retry");
    assert_ne!(replacement.runtime_instance_id(), old_id);
}

#[test]
fn reset_appearance_settings_recovers_malformed_settings() {
    let (directory, host) = malformed_settings_host();
    let failed = host.current_state();
    let id = failed.runtime_instance_id();
    let failure = failed.startup_failure().expect("failure");
    assert!(
        failure
            .recovery_actions
            .iter()
            .any(|action| action.kind == RecoveryActionKind::ResetAppearanceSettings)
    );

    let replacement = host.reset_appearance_settings(id).expect("reset");
    assert_eq!(replacement.lifecycle(), RuntimeLifecycle::Ready);
    assert_ne!(replacement.runtime_instance_id(), id);
    assert_eq!(
        host.get_appearance_settings().expect("settings").theme_mode,
        ThemeMode::System
    );
    let connection =
        rusqlite::Connection::open(directory.path().join("argus.sqlite3")).expect("sqlite");
    let unrelated: String = connection
        .query_row("SELECT value FROM unrelated_data WHERE id = 1", [], |row| {
            row.get(0)
        })
        .expect("unrelated data preserved");
    assert_eq!(unrelated, "preserved");
}

#[test]
fn non_retryable_failures_do_not_offer_retry() {
    let host = ApplicationHost::new(KernelBootstrapOptions::with_data_directory("relative/path"));
    let failed = host.initialize().expect("failed startup snapshot");
    let failure = failed.startup_failure().expect("failure");
    assert!(
        !failure
            .recovery_actions
            .iter()
            .any(|action| action.kind == RecoveryActionKind::RetryStartup)
    );
}

#[test]
fn operation_admission_closes_during_shutdown() {
    let directory = tempdir().expect("temporary directory");
    let host = ApplicationHost::new(KernelBootstrapOptions::with_data_directory(
        directory.path(),
    ));
    let _ = host.initialize().expect("startup");
    host.general_shutdown().expect("shutdown");
    assert_eq!(host.active_event_subscription_count(), 0);
    assert!(matches!(host.current_state(), RuntimeState::Stopped { .. }));
    let error = host
        .get_appearance_settings()
        .expect_err("admission is closed after shutdown");
    assert_eq!(
        error.code.as_str(),
        "ARGUS.V1.OPERATION.CANCELLED",
        "pre-dispatch cancellation wins after shutdown intent"
    );
}

#[test]
fn full_event_queue_drops_oldest_without_reordering_remaining_events() {
    let directory = tempdir().expect("temporary directory");
    let host = ApplicationHost::new(KernelBootstrapOptions::with_data_directory(
        directory.path(),
    ));
    host.initialize().expect("startup");
    let subscription = host.subscribe_events().expect("subscription");
    for index in 0..70 {
        let theme = match index % 3 {
            0 => ThemeMode::System,
            1 => ThemeMode::Light,
            _ => ThemeMode::Dark,
        };
        host.update_appearance_settings(AppearanceSettings::new(theme))
            .expect("appearance update");
    }
    let mut sequences = Vec::new();
    while let Ok(event) = subscription.try_recv() {
        let Some(event) = event else { break };
        sequences.push(event.sequence);
    }
    assert!(sequences.len() <= 64);
    assert!(sequences.windows(2).all(|window| window[0] < window[1]));
    assert!(sequences.first().is_some_and(|sequence| *sequence > 1));
}

#[test]
fn one_committed_update_crosses_adapter_and_stream_once() {
    let directory = tempdir().expect("temporary directory");
    let sink = std::sync::Arc::new(InProcessNotificationSink::new());
    let host = ApplicationHost::with_notification_sink(
        KernelBootstrapOptions::with_data_directory(directory.path()),
        std::sync::Arc::clone(&sink) as std::sync::Arc<dyn argus_runtime::RuntimeNotificationSink>,
    );
    host.initialize().expect("startup");
    let subscription = host.subscribe_events().expect("subscription");
    host.update_appearance_settings(AppearanceSettings::new(ThemeMode::Dark))
        .expect("update");

    let mut appearance_events = 0usize;
    while let Ok(Some(event)) = subscription.try_recv() {
        if matches!(
            event.payload,
            RuntimeEventPayload::AppearanceSettingsChanged
        ) {
            appearance_events += 1;
        }
    }
    assert_eq!(appearance_events, 1);
    assert_eq!(sink.len(), 2);
}

struct NonEmittingSink;

impl RuntimeNotificationSink for NonEmittingSink {
    fn bind(
        &self,
        _publisher: std::sync::Arc<RuntimeEventPublisher>,
    ) -> Result<(), NotificationSinkError> {
        Ok(())
    }

    fn validate(&self) -> Result<(), NotificationSinkError> {
        Ok(())
    }

    fn publish(&self, _event: RuntimeEventPayload) -> Result<(), NotificationSinkError> {
        Ok(())
    }
}

#[test]
fn disabling_adapter_prevents_outward_native_delivery() {
    let directory = tempdir().expect("temporary directory");
    let host = ApplicationHost::with_notification_sink(
        KernelBootstrapOptions::with_data_directory(directory.path()),
        std::sync::Arc::new(NonEmittingSink),
    );
    host.initialize().expect("startup");
    let subscription = host.subscribe_events().expect("subscription");
    host.update_appearance_settings(AppearanceSettings::new(ThemeMode::Light))
        .expect("update");

    let mut appearance_events = 0usize;
    while let Ok(Some(event)) = subscription.try_recv() {
        if matches!(
            event.payload,
            RuntimeEventPayload::AppearanceSettingsChanged
        ) {
            appearance_events += 1;
        }
    }
    assert_eq!(appearance_events, 0);
}

#[test]
fn lifecycle_notifications_use_injected_sink_and_deliver_once() {
    let directory = tempdir().expect("temporary directory");
    let sink = std::sync::Arc::new(InProcessNotificationSink::new());
    let host = ApplicationHost::with_notification_sink(
        KernelBootstrapOptions::with_data_directory(directory.path()),
        std::sync::Arc::clone(&sink) as std::sync::Arc<dyn argus_runtime::RuntimeNotificationSink>,
    );
    let subscription = host
        .subscribe_events()
        .expect("subscription before startup");
    host.initialize().expect("startup");

    let mut events = Vec::new();
    while let Ok(Some(event)) = subscription.try_recv() {
        events.push(event);
    }
    let ready = events
        .iter()
        .filter(|event| {
            matches!(
                event.payload,
                RuntimeEventPayload::RuntimeStateChanged {
                    lifecycle: RuntimeLifecycle::Ready
                }
            )
        })
        .count();
    assert_eq!(ready, 1);
    assert_eq!(sink.len(), 1);

    let shutdown_subscription = host.subscribe_events().expect("subscription for shutdown");
    host.general_shutdown().expect("shutdown");
    let mut transitions = Vec::new();
    while let Ok(Some(event)) = shutdown_subscription.try_recv() {
        if let RuntimeEventPayload::RuntimeStateChanged { lifecycle } = event.payload {
            transitions.push(lifecycle);
        }
    }
    assert_eq!(
        transitions,
        vec![RuntimeLifecycle::ShuttingDown, RuntimeLifecycle::Stopped,]
    );
}

#[test]
fn non_emitting_sink_blocks_all_payload_families() {
    let directory = tempdir().expect("temporary directory");
    let host = ApplicationHost::with_notification_sink(
        KernelBootstrapOptions::with_data_directory(directory.path()),
        std::sync::Arc::new(NonEmittingSink),
    );
    let subscription = host.subscribe_events().expect("subscription");
    host.initialize().expect("startup");
    host.update_appearance_settings(AppearanceSettings::new(ThemeMode::Dark))
        .expect("update");
    host.general_shutdown().expect("shutdown");
    let mut count = 0usize;
    while let Ok(Some(_)) = subscription.try_recv() {
        count += 1;
    }
    assert_eq!(count, 0);

    let failed_directory = tempdir().expect("tempdir");
    let failed_host = ApplicationHost::with_notification_sink(
        KernelBootstrapOptions::with_data_directory("relative"),
        std::sync::Arc::new(NonEmittingSink),
    );
    let failed_subscription = failed_host.subscribe_events().expect("failed subscription");
    failed_host.initialize().expect("failed startup snapshot");
    let mut failed_count = 0usize;
    while let Ok(Some(_)) = failed_subscription.try_recv() {
        failed_count += 1;
    }
    assert_eq!(failed_count, 0);
    let _ = failed_directory;
}

#[test]
fn unavailable_diagnostics_are_rejected_for_environment_failure() {
    let directory = tempdir().expect("tempdir");
    let host = ApplicationHost::new(KernelBootstrapOptions::with_data_directory("relative"));
    let failed = host.initialize().expect("inspectable failure");
    let id = failed.runtime_instance_id();
    let failure = failed.startup_failure().expect("failure");
    for kind in [
        RecoveryActionKind::ExportDiagnostics,
        RecoveryActionKind::CopyTechnicalDetails,
        RecoveryActionKind::OpenDataDirectory,
    ] {
        assert!(
            !failure
                .recovery_actions
                .iter()
                .any(|action| action.kind == kind),
            "unavailable action {kind:?} must not be offered"
        );
    }
    assert!(host.startup_technical_details(id).is_err());
    let archive_path = directory.path().join("startup-diagnostics.zip");
    assert!(host.export_startup_diagnostics(id, &archive_path).is_err());
}

#[test]
fn sharing_diagnostics_atomically_publishes_the_backend_owned_artifact() {
    let (directory, host) = malformed_settings_host();
    let failed = host.current_state();
    let id = failed.runtime_instance_id();

    let export = host
        .export_startup_diagnostics_for_sharing(id)
        .expect("backend-owned diagnostics export");
    assert_eq!(
        export.destination_classification,
        "backend_owned_diagnostics"
    );
    assert!(
        !export
            .destination_classification
            .contains(directory.path().to_string_lossy().as_ref())
    );

    let artifact = directory
        .path()
        .join(STARTUP_DIAGNOSTICS_ARTIFACT_RELATIVE_PATH);
    assert!(artifact.is_file(), "completed artifact must be present");

    let publication_directory = artifact.parent().expect("artifact parent");
    let temporary_artifacts = std::fs::read_dir(publication_directory)
        .expect("publication directory")
        .filter_map(Result::ok)
        .filter(|entry| {
            entry
                .file_name()
                .to_string_lossy()
                .starts_with(".startup-diagnostics-v1.zip.")
        })
        .count();
    assert_eq!(
        temporary_artifacts, 0,
        "atomic staging files must be removed"
    );

    let mut archive = zip::ZipArchive::new(File::open(&artifact).expect("archive file"))
        .expect("Rust must publish a valid ZIP archive");
    let mut manifest = String::new();
    archive
        .by_name("manifest.json")
        .expect("manifest")
        .read_to_string(&mut manifest)
        .expect("manifest text");
    assert!(manifest.contains("\"trace_id\""));
}

#[test]
fn exit_retires_failed_generation_through_shutdown_transitions() {
    let (_directory, host) = malformed_settings_host();
    let failed = host.current_state();
    let id = failed.runtime_instance_id();

    host.exit_failed_runtime(id).expect("exit");

    assert!(matches!(host.current_state(), RuntimeState::Stopped { .. }));
}

#[test]
fn retry_uses_a_fresh_startup_trace_and_generation() {
    let (_directory, host) = malformed_settings_host();
    let failed = host.current_state();
    let old_id = failed.runtime_instance_id();
    let old_trace = failed.startup_failure().expect("failure").error.trace_id;

    let replacement = host.retry_startup(old_id).expect("retry");
    let new_trace = replacement
        .startup_failure()
        .expect("replacement failure")
        .error
        .trace_id;

    assert_ne!(replacement.runtime_instance_id(), old_id);
    assert_ne!(new_trace, old_trace);
}
