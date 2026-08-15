use std::sync::{Arc, Mutex};

use argus_application::{
    AppearanceSettings, AppearanceSettingsSubscriber, EventSubscriberError, ThemeMode,
};
use argus_runtime::{EventBus, KernelBootstrapOptions, bootstrap_kernel_with_event_bus};
use tempfile::tempdir;

#[derive(Clone)]
struct CountingSubscriber {
    calls: Arc<Mutex<usize>>,
    fail: bool,
}

impl AppearanceSettingsSubscriber for CountingSubscriber {
    fn appearance_settings_changed(
        &self,
        _event: argus_application::AppearanceSettingsChanged,
    ) -> Result<(), EventSubscriberError> {
        *self.calls.lock().expect("subscriber lock") += 1;
        if self.fail {
            Err(EventSubscriberError::Failed)
        } else {
            Ok(())
        }
    }
}

#[test]
fn kernel_query_and_update_round_trip_through_the_authoritative_backend() {
    let directory = tempdir().expect("temporary directory");
    let kernel = argus_runtime::bootstrap_kernel(KernelBootstrapOptions::with_data_directory(
        directory.path(),
    ))
    .expect("kernel");

    assert_eq!(
        kernel.get_appearance_settings().expect("fresh appearance"),
        AppearanceSettings::new(ThemeMode::System)
    );
    kernel
        .update_appearance_settings(AppearanceSettings::new(ThemeMode::Dark))
        .expect("update");
    assert_eq!(
        kernel
            .get_appearance_settings()
            .expect("updated appearance"),
        AppearanceSettings::new(ThemeMode::Dark)
    );
    kernel.shutdown().expect("shutdown");
}

#[test]
fn no_op_update_does_not_publish_and_change_publishes_once() {
    let directory = tempdir().expect("temporary directory");
    let calls = Arc::new(Mutex::new(0));
    let bus = EventBus::new(
        vec![Box::new(CountingSubscriber {
            calls: Arc::clone(&calls),
            fail: false,
        })],
        Vec::new(),
        Vec::new(),
        Vec::new(),
    );
    let kernel = bootstrap_kernel_with_event_bus(
        KernelBootstrapOptions::with_data_directory(directory.path()),
        bus,
    )
    .expect("kernel");

    kernel
        .update_appearance_settings(AppearanceSettings::new(ThemeMode::System))
        .expect("no-op");
    assert_eq!(*calls.lock().expect("subscriber lock"), 0);
    kernel
        .update_appearance_settings(AppearanceSettings::new(ThemeMode::Light))
        .expect("change");
    assert_eq!(*calls.lock().expect("subscriber lock"), 1);
    kernel.shutdown().expect("shutdown");
}

#[test]
fn subscriber_failure_isolated_after_commit_and_is_not_retried() {
    let directory = tempdir().expect("temporary directory");
    let failing_calls = Arc::new(Mutex::new(0));
    let later_calls = Arc::new(Mutex::new(0));
    let bus = EventBus::new(
        vec![
            Box::new(CountingSubscriber {
                calls: Arc::clone(&failing_calls),
                fail: true,
            }),
            Box::new(CountingSubscriber {
                calls: Arc::clone(&later_calls),
                fail: false,
            }),
        ],
        Vec::new(),
        Vec::new(),
        Vec::new(),
    );
    let kernel = bootstrap_kernel_with_event_bus(
        KernelBootstrapOptions::with_data_directory(directory.path()),
        bus,
    )
    .expect("kernel");

    kernel
        .update_appearance_settings(AppearanceSettings::new(ThemeMode::Dark))
        .expect("committed update");
    assert_eq!(*failing_calls.lock().expect("subscriber lock"), 1);
    assert_eq!(*later_calls.lock().expect("subscriber lock"), 1);
    let publication_logs = kernel.publication_logs();
    assert_eq!(publication_logs.len(), 1);
    assert_eq!(
        publication_logs[0].event_name.as_str(),
        "event.subscriber.failed"
    );
    assert_eq!(publication_logs[0].level, argus_application::LogLevel::Warn);
    assert_eq!(
        kernel
            .get_appearance_settings()
            .expect("authoritative value"),
        AppearanceSettings::new(ThemeMode::Dark)
    );
    kernel.shutdown().expect("shutdown");
}
