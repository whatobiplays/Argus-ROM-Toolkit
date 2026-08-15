use std::marker::PhantomData;
use std::sync::{Arc, Mutex};

mod common;

use argus_application::{
    AppearanceSettings, AppearanceSettingsQueries, AppearanceSettingsRepository, ApplicationEvent,
    ApplicationPortError, EventRecorder, EventRecordingError, GetAppearanceSettingsHandler,
    GetAppearanceSettingsQuery, LibrarySourceId, LibrarySourceRepository, OperationContext,
    OperationName, PersistenceError, SafeContextField, SafeContextValue, SettingsDomain,
    SettingsService, SubsystemName, ThemeMode, TraceId, UnitOfWork, UnitOfWorkFactory,
    UpdateAppearanceSettingsCommand,
};
use common::{
    NoopJobRunRepository, NoopLibraryRootRepository, NoopLibraryScanTargetRepository,
    NoopScanRunRepository, NoopSourceEntryRepository,
};

#[derive(Clone)]
struct FakeState {
    current: AppearanceSettings,
    saves: usize,
    commits: usize,
}

#[derive(Clone)]
struct FakeQueries {
    state: Arc<Mutex<FakeState>>,
}

impl AppearanceSettingsQueries for FakeQueries {
    fn get(&self, _context: &OperationContext) -> Result<AppearanceSettings, PersistenceError> {
        Ok(self.state.lock().expect("state lock").current)
    }
}

struct FakeRepository<'scope> {
    state: Arc<Mutex<FakeState>>,
    marker: PhantomData<&'scope mut ()>,
}

struct NoopLibrarySourceRepository<'scope> {
    marker: PhantomData<&'scope mut ()>,
}

impl LibrarySourceRepository for NoopLibrarySourceRepository<'_> {
    fn ensure_local_filesystem_source(&mut self) -> Result<LibrarySourceId, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }
}

impl AppearanceSettingsRepository for FakeRepository<'_> {
    fn get(&mut self) -> Result<AppearanceSettings, PersistenceError> {
        let current = self.state.lock().expect("state lock").current;
        Ok(current)
    }

    fn save(&mut self, settings: &AppearanceSettings) -> Result<(), PersistenceError> {
        let mut state = self.state.lock().expect("state lock");
        state.current = *settings;
        state.saves += 1;
        Ok(())
    }
}

struct FakeUnitOfWork<'scope> {
    state: Arc<Mutex<FakeState>>,
    original: AppearanceSettings,
    terminal: bool,
    marker: PhantomData<&'scope mut ()>,
}

impl UnitOfWork for FakeUnitOfWork<'_> {
    type AppearanceSettingsRepository<'scope>
        = FakeRepository<'scope>
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

    fn appearance_settings(&mut self) -> Self::AppearanceSettingsRepository<'_> {
        FakeRepository {
            state: Arc::clone(&self.state),
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

    fn commit(mut self) -> Result<(), ApplicationPortError> {
        self.state.lock().expect("state lock").commits += 1;
        self.terminal = true;
        Ok(())
    }

    fn rollback(mut self) -> Result<(), ApplicationPortError> {
        self.state.lock().expect("state lock").current = self.original;
        self.terminal = true;
        Ok(())
    }
}

impl Drop for FakeUnitOfWork<'_> {
    fn drop(&mut self) {
        if !self.terminal {
            self.state.lock().expect("state lock").current = self.original;
        }
    }
}

#[derive(Clone)]
struct FakeFactory {
    state: Arc<Mutex<FakeState>>,
}

impl UnitOfWorkFactory for FakeFactory {
    type Scope<'scope>
        = FakeUnitOfWork<'scope>
    where
        Self: 'scope;

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
        let original = self.state.lock().expect("state lock").current;
        let scope = FakeUnitOfWork {
            state: Arc::clone(&self.state),
            original,
            terminal: false,
            marker: PhantomData,
        };
        operation(scope)
    }
}

#[derive(Clone, Default)]
struct RecordingRecorder {
    events: Arc<Mutex<Vec<ApplicationEvent>>>,
}

impl EventRecorder for RecordingRecorder {
    fn record(&self, event: ApplicationEvent) -> Result<(), EventRecordingError> {
        self.events.lock().expect("event lock").push(event);
        Ok(())
    }
}

fn context() -> OperationContext {
    OperationContext::new(
        TraceId::try_from(7_u128).expect("trace"),
        SubsystemName::try_from("settings").expect("subsystem"),
        OperationName::try_from("appearance").expect("operation"),
    )
}

fn service() -> (
    SettingsService<FakeQueries, FakeFactory>,
    Arc<Mutex<FakeState>>,
) {
    let state = Arc::new(Mutex::new(FakeState {
        current: AppearanceSettings::new(ThemeMode::System),
        saves: 0,
        commits: 0,
    }));
    (
        SettingsService::new(
            FakeQueries {
                state: Arc::clone(&state),
            },
            FakeFactory {
                state: Arc::clone(&state),
            },
        ),
        state,
    )
}

#[test]
fn query_returns_the_authoritative_aggregate_without_a_unit_of_work() {
    let state = Arc::new(Mutex::new(FakeState {
        current: AppearanceSettings::new(ThemeMode::System),
        saves: 0,
        commits: 0,
    }));
    let handler = GetAppearanceSettingsHandler::new(FakeQueries {
        state: Arc::clone(&state),
    });
    assert_eq!(
        handler
            .handle(GetAppearanceSettingsQuery, context())
            .expect("query"),
        AppearanceSettings::new(ThemeMode::System)
    );
    assert_eq!(state.lock().expect("state lock").commits, 0);
}

#[test]
fn changed_update_saves_once_and_records_one_payload_free_event() {
    let (service, state) = service();
    let recorder = RecordingRecorder::default();
    service
        .update_appearance_settings(
            UpdateAppearanceSettingsCommand::new(AppearanceSettings::new(ThemeMode::Dark)),
            context(),
            recorder.clone(),
            Arc::new(|| false),
        )
        .expect("update");

    let state = state.lock().expect("state lock");
    assert_eq!(state.current.theme_mode, ThemeMode::Dark);
    assert_eq!(state.saves, 1);
    assert_eq!(state.commits, 1);
    drop(state);
    assert_eq!(
        recorder.events.lock().expect("event lock").as_slice(),
        &[ApplicationEvent::AppearanceSettingsChanged(
            argus_application::AppearanceSettingsChanged,
        )]
    );
}

#[test]
fn semantic_noop_commits_without_save_or_event() {
    let (service, state) = service();
    let recorder = RecordingRecorder::default();
    service
        .update_appearance_settings(
            UpdateAppearanceSettingsCommand::new(AppearanceSettings::new(ThemeMode::System)),
            context(),
            recorder.clone(),
            Arc::new(|| false),
        )
        .expect("no-op");

    let state = state.lock().expect("state lock");
    assert_eq!(state.saves, 0);
    assert_eq!(state.commits, 1);
    drop(state);
    assert!(recorder.events.lock().expect("event lock").is_empty());
}

#[test]
fn event_recording_failure_is_an_update_failure() {
    #[derive(Clone)]
    struct FailingRecorder;

    impl EventRecorder for FailingRecorder {
        fn record(&self, _event: ApplicationEvent) -> Result<(), EventRecordingError> {
            Err(EventRecordingError::CapacityExceeded)
        }
    }

    let (service, state) = service();
    let error = service
        .update_appearance_settings(
            UpdateAppearanceSettingsCommand::new(AppearanceSettings::new(ThemeMode::Dark)),
            context(),
            FailingRecorder,
            Arc::new(|| false),
        )
        .expect_err("recording failure");
    assert_eq!(error.code.as_str(), "ARGUS.V1.INTERNAL.UNEXPECTED");
    assert_eq!(
        state.lock().expect("state lock").current.theme_mode,
        ThemeMode::System
    );
}

#[test]
fn pre_commit_cancellation_rolls_back_and_reports_operation_cancelled() {
    let (service, state) = service();
    let recorder = RecordingRecorder::default();
    let error = service
        .update_appearance_settings(
            UpdateAppearanceSettingsCommand::new(AppearanceSettings::new(ThemeMode::Dark)),
            context(),
            recorder.clone(),
            Arc::new(|| true),
        )
        .expect_err("pre-commit cancellation");
    assert_eq!(error.code.as_str(), "ARGUS.V1.OPERATION.CANCELLED");
    let state = state.lock().expect("state lock");
    assert_eq!(state.current.theme_mode, ThemeMode::System);
    assert_eq!(state.commits, 0);
}

#[test]
fn persisted_settings_port_error_maps_to_sanitized_integrity_error() {
    let (_, state) = service();
    let service = SettingsService::new(FailingQueries, FakeFactory { state });
    let error = service
        .get_appearance_settings(GetAppearanceSettingsQuery, context())
        .expect_err("integrity error");
    assert_eq!(
        error.code.as_str(),
        "ARGUS.V1.CONFIGURATION.PERSISTED_SETTINGS_INVALID"
    );
    assert_eq!(error.safe_context.len(), 2);
    assert_eq!(
        error.safe_context.get(&SafeContextField::SettingsDomain),
        Some(&SafeContextValue::SettingsDomain(
            SettingsDomain::Appearance
        ))
    );
    assert_eq!(
        error
            .safe_context
            .get(&SafeContextField::PersistedSettingsReason),
        Some(&SafeContextValue::PersistedSettingsReason(
            argus_application::PersistedSettingsReason::Missing
        ))
    );
}

struct FailingQueries;

impl AppearanceSettingsQueries for FailingQueries {
    fn get(&self, _context: &OperationContext) -> Result<AppearanceSettings, PersistenceError> {
        Err(PersistenceError::PersistedSettingsInvalid(
            argus_application::PersistedSettingsReason::Missing,
        ))
    }
}
