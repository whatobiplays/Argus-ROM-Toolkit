#![cfg(feature = "test-support")]

//! Runtime-level Slice 002 background-operation integration tests.

use std::fs;
use std::path::{Path, PathBuf};
use std::sync::mpsc;
#[cfg(feature = "test-support")]
use std::sync::{Arc, Condvar, Mutex};
use std::time::{Duration, Instant};

use argus_application::{
    AddLocalLibraryRootResult, CancelJobResult, JobRunId, JobRunState, LibraryRefreshTrigger,
    LibraryRootId, LibraryRootLastScanStatus, ListGamesQuery, ListJobsQuery, ListJobsScope,
    ListLibraryRootsQuery, MetadataSettings, MetadataSettingsUpdateResult, OperationDetail,
    RefreshMode, StartLibraryScanResult,
};
#[cfg(feature = "test-support")]
use argus_application::{
    ArtworkCandidate, ArtworkReference, ArtworkType, EnrichmentProviderSession, ErrorCode,
    ExactMatchEvidence, GetGameResult, HydrationMappingCandidate, HydrationProviderError,
    HydrationTarget, LibraryRefreshJobDetail, LibraryScope, LibrarySort, PlatformId, ProviderId,
    ProviderMetadata, RefreshIssueKind, RefreshIssueReason,
};
#[cfg(feature = "test-support")]
use argus_infrastructure::content::{ContentReadError, ContentReader};
use argus_runtime::{
    ApplicationHost, KernelBootstrapOptions, RefreshExecutionCheckpoint, RuntimeEventPayload,
    RuntimeLifecycle, test_support,
};

fn context_ready(host: &ApplicationHost) {
    let state = host.initialize().expect("initialize");
    assert_eq!(state.lifecycle(), RuntimeLifecycle::Ready);
}

fn make_library(root: &Path, file_count: usize) {
    fs::create_dir_all(root).expect("library root");
    for index in 0..file_count {
        fs::write(root.join(format!("rom-{index:05}.bin")), b"rom").expect("file");
    }
    fs::create_dir_all(root.join("Sub")).expect("subdir");
    fs::write(root.join("Sub/nested.txt"), b"nested").expect("nested");
}

#[cfg(feature = "test-support")]
const GB_LOGO: [u8; 48] = [
    0xCE, 0xED, 0x66, 0x66, 0xCC, 0x0D, 0x00, 0x0B, 0x03, 0x73, 0x00, 0x83, 0x00, 0x0C, 0x00, 0x0D,
    0x00, 0x08, 0x11, 0x1F, 0x88, 0x89, 0x00, 0x0E, 0xDC, 0xCC, 0x6E, 0xE6, 0xDD, 0xDD, 0xD9, 0x99,
    0xBB, 0xBB, 0x67, 0x63, 0x6E, 0x0E, 0xEC, 0xCC, 0xDD, 0xDC, 0x99, 0x9F, 0xBB, 0xB9, 0x33, 0x3E,
];

#[cfg(feature = "test-support")]
fn gb_fixture(marker: u8) -> Vec<u8> {
    let mut bytes = vec![0_u8; 0x8000];
    bytes[0x143] = 0x00;
    bytes[0x147] = 0x00;
    bytes[0x148] = 0x00;
    bytes[0x149] = 0x00;
    bytes[0x14a] = 0x01;
    bytes[0x14b] = 0x33;
    bytes[0x104..0x134].copy_from_slice(&GB_LOGO);
    bytes[0x200] = marker;
    let mut checksum = 0_u8;
    for byte in &bytes[0x134..0x14d] {
        checksum = checksum.wrapping_sub(*byte).wrapping_sub(1);
    }
    bytes[0x14d] = checksum;
    bytes
}

#[cfg(feature = "test-support")]
fn nes_fixture() -> Vec<u8> {
    let mut bytes = vec![0_u8; 16 + 0x4000 + 0x2000];
    bytes[0..4].copy_from_slice(b"NES\x1a");
    bytes[4] = 1;
    bytes[5] = 1;
    bytes[6] = 0x03;
    for (index, byte) in bytes[16..].iter_mut().enumerate() {
        *byte = (index as u8).wrapping_mul(17).wrapping_add(3);
    }
    bytes
}

#[cfg(feature = "test-support")]
fn genesis_fixture() -> Vec<u8> {
    let mut bytes = vec![0_u8; 0x8000];
    bytes[0x100..0x110].copy_from_slice(b"SEGA GENESIS    ");
    bytes[0x180..0x182].copy_from_slice(b"GM");
    bytes[0x1a0..0x1a4].copy_from_slice(&0_u32.to_be_bytes());
    bytes[0x1a4..0x1a8].copy_from_slice(&0x7fff_u32.to_be_bytes());
    for (index, byte) in bytes[0x200..].iter_mut().enumerate() {
        *byte = (index as u8).wrapping_mul(29).wrapping_add(11);
    }
    bytes
}

#[cfg(feature = "test-support")]
struct FixtureContentReader {
    bytes: Vec<u8>,
}

#[cfg(feature = "test-support")]
impl ContentReader for FixtureContentReader {
    fn len(&self) -> Result<u64, ContentReadError> {
        Ok(self.bytes.len() as u64)
    }

    fn read_at(&mut self, offset: u64, destination: &mut [u8]) -> Result<usize, ContentReadError> {
        let offset = usize::try_from(offset).map_err(|_| ContentReadError::OutOfRange)?;
        if offset >= self.bytes.len() {
            return Ok(0);
        }
        let count = destination.len().min(self.bytes.len() - offset);
        destination[..count].copy_from_slice(&self.bytes[offset..offset + count]);
        Ok(count)
    }
}

#[cfg(feature = "test-support")]
fn hex_digest(bytes: &[u8]) -> String {
    argus_infrastructure::content::recognize_raw_cartridge(bytes)
        .expect("fixture recognition")
        .identity_digest()
        .as_bytes()
        .into_iter()
        .map(|byte| format!("{byte:02x}"))
        .collect()
}

#[cfg(feature = "test-support")]
fn stream_hex_digest(bytes: Vec<u8>) -> String {
    let mut reader = FixtureContentReader { bytes };
    argus_infrastructure::content::recognize_content(&mut reader)
        .expect("stream fixture recognition")
        .identity_digest()
        .as_bytes()
        .into_iter()
        .map(|byte| format!("{byte:02x}"))
        .collect()
}

#[derive(Default)]
#[cfg(feature = "test-support")]
struct ProviderTrace {
    session_factory_calls: usize,
    matching_calls: usize,
    metadata_calls: usize,
    artwork_calls: usize,
    download_calls: usize,
    /// Identities whose exact matching deterministically fails, paired with
    /// the normalized provider error the fixture session reports.
    matching_failures: Vec<(String, HydrationProviderError)>,
}

#[cfg(feature = "test-support")]
struct FixtureProviderSession {
    trace: Arc<Mutex<ProviderTrace>>,
}

#[cfg(feature = "test-support")]
impl EnrichmentProviderSession for FixtureProviderSession {
    fn provider_id(&self) -> ProviderId {
        ProviderId::GameTdb
    }

    fn match_exact(
        &mut self,
        target: &HydrationTarget,
    ) -> Result<Vec<HydrationMappingCandidate>, HydrationProviderError> {
        let mut trace = self.trace.lock().expect("provider trace");
        trace.matching_calls += 1;
        if let Some((_, error)) = trace
            .matching_failures
            .iter()
            .find(|(identity, _)| identity == target.submitted_identity())
        {
            return Err(*error);
        }
        Ok(vec![HydrationMappingCandidate::new(
            target.game_content_id(),
            ProviderId::GameTdb,
            "fixture-game",
            None,
            target.provider_platform_id(),
            Some(100),
            ExactMatchEvidence::GameTdb {
                game_content_id: target.game_content_id(),
                platform_id: target.platform_id(),
                external_game_id: "fixture-game".to_owned(),
                native_identifier: target.submitted_identity().to_owned(),
                validated_identifier: target.submitted_identity().to_owned(),
            },
            1,
            target.observed_at(),
        )])
    }

    fn fetch_metadata(
        &mut self,
        _target: &HydrationTarget,
        mapping: &argus_application::ExternalIdentityMapping,
    ) -> Result<Option<ProviderMetadata>, HydrationProviderError> {
        self.trace.lock().expect("provider trace").metadata_calls += 1;
        Ok(Some(ProviderMetadata::new(
            ProviderId::GameTdb,
            mapping.external_game_id(),
            1,
            Some("us".to_owned()),
            Some("en".to_owned()),
            100,
            None,
            Some("Fixture Game".to_owned()),
            Vec::new(),
            Some("deterministic fixture metadata".to_owned()),
            None,
            Vec::new(),
            Vec::new(),
            vec!["action".to_owned()],
            vec!["en".to_owned()],
            100,
            "fixture:gametdb",
        )))
    }

    fn discover_artwork(
        &mut self,
        _mapping: &argus_application::ExternalIdentityMapping,
    ) -> Result<Vec<ArtworkCandidate>, HydrationProviderError> {
        self.trace.lock().expect("provider trace").artwork_calls += 1;
        Ok(vec![
            ArtworkCandidate::new(
                ProviderId::GameTdb,
                "fixture-cover",
                ArtworkType::CoverFront,
                "https://fixture.invalid/cover.png",
                1,
            )
            .with_details(Some("us"), Some("en"), Some(640), Some(960), 100)
            .with_discovered_at(100),
        ])
    }

    fn download_artwork(
        &mut self,
        _reference: &ArtworkReference,
    ) -> Result<Vec<u8>, HydrationProviderError> {
        self.trace.lock().expect("provider trace").download_calls += 1;
        Ok(vec![
            137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1,
            8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 248, 207,
            192, 240, 31, 0, 5, 0, 1, 255, 137, 153, 61, 29, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66,
            96, 130,
        ])
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum GateState {
    Disarmed,
    Armed,
    Entered,
    Released,
}

struct RefreshExecutionGate {
    checkpoint: RefreshExecutionCheckpoint,
    state: Mutex<GateState>,
    wake: Condvar,
}

impl RefreshExecutionGate {
    fn new(checkpoint: RefreshExecutionCheckpoint) -> Arc<Self> {
        Arc::new(Self {
            checkpoint,
            state: Mutex::new(GateState::Disarmed),
            wake: Condvar::new(),
        })
    }

    fn arm(&self) {
        *self.state.lock().expect("refresh gate") = GateState::Armed;
    }

    fn hook(&self, checkpoint: RefreshExecutionCheckpoint) {
        if checkpoint != self.checkpoint {
            return;
        }
        let mut state = self.state.lock().expect("refresh gate");
        if *state != GateState::Armed {
            return;
        }
        *state = GateState::Entered;
        self.wake.notify_all();
        while *state != GateState::Released {
            state = self.wake.wait(state).expect("refresh gate wait");
        }
    }

    fn wait_until_entered(&self) {
        let state = self.state.lock().expect("refresh gate");
        let (state, timeout) = self
            .wake
            .wait_timeout_while(state, Duration::from_secs(5), |value| {
                *value != GateState::Entered
            })
            .expect("refresh gate entered wait");
        assert!(
            !timeout.timed_out(),
            "refresh execution never reached the gate"
        );
        assert_eq!(*state, GateState::Entered);
    }

    fn release(&self) {
        *self.state.lock().expect("refresh gate") = GateState::Released;
        self.wake.notify_all();
    }
}

fn wait_until<F>(mut predicate: F, timeout: Duration) -> bool
where
    F: FnMut() -> bool,
{
    let deadline = Instant::now() + timeout;
    while Instant::now() < deadline {
        if predicate() {
            return true;
        }
        std::thread::sleep(Duration::from_millis(10));
    }
    predicate()
}

fn assert_foreground_returns<T: Send + 'static>(
    label: &'static str,
    operation: impl FnOnce() -> T + Send + 'static,
) -> T {
    let (sender, receiver) = mpsc::sync_channel(1);
    std::thread::spawn(move || {
        let _ = sender.send(operation());
    });
    receiver
        .recv_timeout(Duration::from_secs(2))
        .unwrap_or_else(|_| panic!("{label} was starved by background refresh"))
}

#[test]
#[cfg(feature = "test-support")]
fn library_refresh_does_not_starve_foreground_queries_or_job_control() {
    let directory = tempfile::tempdir().expect("tempdir");
    let gate = RefreshExecutionGate::new(RefreshExecutionCheckpoint::CommittedRoot);
    let gate_for_hook = Arc::clone(&gate);
    let options = KernelBootstrapOptions::with_data_directory(directory.path().join("data"))
        .with_provider_session_factory_for_tests(Vec::new)
        .with_refresh_execution_hook_for_tests(move |checkpoint| gate_for_hook.hook(checkpoint));
    let host = Arc::new(ApplicationHost::new(options));
    context_ready(&host);

    let library = directory.path().join("Library");
    fs::create_dir_all(&library).expect("library root");
    fs::write(library.join("game.gb"), gb_fixture(1)).expect("game content");
    add_root(&host, &library);
    warm_onboarding_read(&host);

    gate.arm();
    let refresh_job_run_id = host
        .refresh_library()
        .expect("refresh admission")
        .job_run_id();
    gate.wait_until_entered();

    let games_query = ListGamesQuery::builder()
        .scope(argus_application::LibraryScope::All)
        .search(None)
        .filters_empty(true)
        .sort(argus_application::LibrarySort::DisplayTitleAscending)
        .page_size(50)
        .build()
        .expect("bounded Library query");

    assert_foreground_returns("Library read", {
        let host = Arc::clone(&host);
        move || host.list_games(games_query)
    })
    .expect("Library read while refresh is blocked");

    assert_foreground_returns("Sources read", {
        let host = Arc::clone(&host);
        move || host.list_library_roots(ListLibraryRootsQuery::new(0, 100))
    })
    .expect("Sources read while refresh is blocked");

    assert_foreground_returns("Jobs read", {
        let host = Arc::clone(&host);
        move || host.list_jobs(ListJobsQuery::new(ListJobsScope::Active))
    })
    .expect("Jobs read while refresh is blocked");

    assert_foreground_returns("Job detail", {
        let host = Arc::clone(&host);
        move || host.get_job(refresh_job_run_id)
    })
    .expect("Job detail while refresh is blocked");

    assert_foreground_returns("Onboarding read", {
        let host = Arc::clone(&host);
        move || {
            let (context, _guard) = host
                .begin_operation("library", "foreground_onboarding_probe")
                .expect("onboarding probe admission");
            host.library_onboarding_state_with_context(&context)
        }
    })
    .expect("onboarding read while refresh is blocked");

    let cancel = assert_foreground_returns("Cancellation", {
        let host = Arc::clone(&host);
        move || host.cancel_job(refresh_job_run_id)
    })
    .expect("cancel while refresh is blocked");
    assert!(matches!(
        cancel,
        CancelJobResult::CancellationRequested | CancelJobResult::NoLongerCancellable
    ));

    gate.release();
    assert!(terminal_state(&host, refresh_job_run_id).is_terminal());
    host.general_shutdown().expect("shutdown");
}

fn assert_focused_refresh_queries(host: &Arc<ApplicationHost>, job_run_id: JobRunId) {
    let games_query = ListGamesQuery::builder()
        .scope(LibraryScope::All)
        .search(None)
        .filters_empty(true)
        .sort(LibrarySort::DisplayTitleAscending)
        .page_size(50)
        .build()
        .expect("bounded Library query");

    assert_foreground_returns("Library read", {
        let host = Arc::clone(host);
        move || host.list_games(games_query)
    })
    .expect("Library read while refresh is blocked");

    assert_foreground_returns("Jobs read", {
        let host = Arc::clone(host);
        move || host.list_jobs(ListJobsQuery::new(ListJobsScope::Active))
    })
    .expect("Jobs read while refresh is blocked");

    assert_foreground_returns("Job detail", {
        let host = Arc::clone(host);
        move || host.get_job(job_run_id)
    })
    .expect("Job detail while refresh is blocked");

    assert_foreground_returns("Onboarding read", {
        let host = Arc::clone(host);
        move || {
            let (context, _guard) = host
                .begin_operation("library", "focused_onboarding_probe")
                .expect("onboarding probe admission");
            host.library_onboarding_state_with_context(&context)
        }
    })
    .expect("onboarding read while refresh is blocked");
}

fn warm_onboarding_read(host: &Arc<ApplicationHost>) {
    let (context, _guard) = host
        .begin_operation("library", "onboarding_read_warmup")
        .expect("onboarding warmup admission");
    host.library_onboarding_state_with_context(&context)
        .expect("onboarding warmup read");
}

fn seed_identified_game(
    directory: &Path,
    checkpoint: RefreshExecutionCheckpoint,
) -> (Arc<ApplicationHost>, Arc<RefreshExecutionGate>, JobRunId) {
    let gate = RefreshExecutionGate::new(checkpoint);
    let gate_for_hook = Arc::clone(&gate);
    let options = KernelBootstrapOptions::with_data_directory(directory.join("data"))
        .with_provider_session_factory_for_tests(Vec::new)
        .with_refresh_execution_hook_for_tests(move |checkpoint| gate_for_hook.hook(checkpoint));
    let host = Arc::new(ApplicationHost::new(options));
    context_ready(&host);

    let library = directory.join("Library");
    fs::create_dir_all(&library).expect("library root");
    fs::write(library.join("game.gb"), gb_fixture(1)).expect("game content");
    add_root(&host, &library);
    let initial_job_run_id = host
        .refresh_library()
        .expect("initial refresh admission")
        .job_run_id();
    assert!(terminal_state(&host, initial_job_run_id).is_terminal());
    warm_onboarding_read(&host);

    (host, gate, initial_job_run_id)
}

#[test]
#[cfg(feature = "test-support")]
fn game_refresh_does_not_starve_foreground_queries() {
    let directory = tempfile::tempdir().expect("tempdir");
    let (host, gate, _) = seed_identified_game(directory.path(), RefreshExecutionCheckpoint::Game);
    let game_id = host
        .list_games(
            ListGamesQuery::builder()
                .scope(LibraryScope::All)
                .search(None)
                .filters_empty(true)
                .sort(LibrarySort::DisplayTitleAscending)
                .page_size(50)
                .build()
                .expect("bounded Library query"),
        )
        .expect("seeded Library query")
        .items()[0]
        .game_id();

    gate.arm();
    let (context, _guard) = host
        .begin_operation("library", "game_refresh_concurrency")
        .expect("Game refresh admission context");
    let job_run_id = host
        .start_game_refresh_with_context(vec![game_id], RefreshMode::EligibleOnly, &context)
        .expect("Game refresh admission")
        .job_run_id();
    gate.wait_until_entered();

    assert_focused_refresh_queries(&host, job_run_id);

    gate.release();
    assert!(terminal_state(&host, job_run_id).is_terminal());
    host.general_shutdown().expect("shutdown");
}

#[test]
#[cfg(feature = "test-support")]
fn library_resolution_refresh_does_not_starve_foreground_queries() {
    let directory = tempfile::tempdir().expect("tempdir");
    let (host, gate, _) = seed_identified_game(
        directory.path(),
        RefreshExecutionCheckpoint::LibraryResolution,
    );

    gate.arm();
    let (context, _guard) = host
        .begin_operation("settings", "library_resolution_concurrency")
        .expect("resolution admission context");
    let update = host
        .update_metadata_settings_with_context(&context, MetadataSettings::new(["jp"], ["ja"]))
        .expect("metadata settings update");
    let job_run_id = match update {
        MetadataSettingsUpdateResult::CommittedAndResolutionAdmitted(_, handle) => {
            handle.job_run_id()
        }
        other => panic!("expected admitted resolution refresh, got {other:?}"),
    };
    gate.wait_until_entered();

    assert_focused_refresh_queries(&host, job_run_id);

    gate.release();
    assert!(terminal_state(&host, job_run_id).is_terminal());
    host.general_shutdown().expect("shutdown");
}

fn add_root(host: &ApplicationHost, path: &Path) -> LibraryRootId {
    let result = host
        .add_local_library_root(test_support::local_filesystem_root_selection(path))
        .expect("add root");
    match result {
        AddLocalLibraryRootResult::Added(root) => root.root_id(),
        _ => panic!("expected added root"),
    }
}

fn start_scan(host: &ApplicationHost, root_id: LibraryRootId) -> JobRunId {
    match host.start_library_scan(root_id).expect("start scan") {
        StartLibraryScanResult::Admitted(handle) => handle.job_run_id(),
        StartLibraryScanResult::AlreadyScanning { .. } => panic!("expected admitted"),
    }
}

fn terminal_state(host: &ApplicationHost, job_run_id: JobRunId) -> JobRunState {
    wait_until(
        || {
            host.get_job(job_run_id)
                .map(|detail| detail.job().state().is_terminal())
                .unwrap_or(false)
        },
        Duration::from_secs(15),
    );
    host.get_job(job_run_id).expect("get job").job().state()
}

#[test]
fn library_scan_completes_durably_and_updates_root_projections() {
    let directory = tempfile::tempdir().expect("tempdir");
    let host = ApplicationHost::new(KernelBootstrapOptions::with_data_directory(
        directory.path().join("data"),
    ));
    context_ready(&host);
    let library = directory.path().join("Library");
    make_library(&library, 300);
    let root_id = add_root(&host, &library);
    let job_run_id = start_scan(&host, root_id);

    let detail = host.get_job(job_run_id).expect("job detail during scan");
    let observed_state = detail.job().state();
    assert!(
        matches!(
            observed_state,
            JobRunState::Queued
                | JobRunState::Preparing
                | JobRunState::Running
                | JobRunState::Completed
        ),
        "unexpected scan state after admission: {observed_state:?}"
    );
    assert_eq!(terminal_state(&host, job_run_id), JobRunState::Completed);

    let root = host.get_library_root(root_id).expect("root projection");
    assert!(root.active_scan().is_none());
    assert_eq!(
        root.last_scan().expect("last scan").status(),
        LibraryRootLastScanStatus::Complete
    );

    let recent = host
        .list_jobs(ListJobsQuery::new(ListJobsScope::RecentTerminal {
            offset: 0,
            page_size: 20,
        }))
        .expect("recent jobs");
    assert_eq!(recent.total_count(), 1);
    assert_eq!(recent.items()[0].job_run_id(), job_run_id);
    host.general_shutdown().expect("shutdown");
}

/// Guards the Jobs landing contract: every durable terminal run stays listed
/// after a runtime restart, so `/jobs` never depends on in-memory session
/// state to show its recent terminal history.
#[test]
#[cfg(feature = "test-support")]
fn jobs_listing_retains_every_durable_terminal_run_across_restart() {
    let directory = tempfile::tempdir().expect("tempdir");
    let data_directory = directory.path().join("data");
    let options = KernelBootstrapOptions::with_data_directory(data_directory.clone())
        .with_provider_session_factory_for_tests(Vec::new);
    let host = ApplicationHost::new(options);
    context_ready(&host);
    let library = directory.path().join("Library");
    make_library(&library, 2);
    let root_id = add_root(&host, &library);
    let scan_job_run_id = start_scan(&host, root_id);
    assert_eq!(
        terminal_state(&host, scan_job_run_id),
        JobRunState::Completed
    );
    let refresh_job_run_id = host
        .refresh_library()
        .expect("refresh admission")
        .job_run_id();
    assert_eq!(
        terminal_state(&host, refresh_job_run_id),
        JobRunState::Completed
    );

    let recent = host
        .list_jobs(ListJobsQuery::new(ListJobsScope::RecentTerminal {
            offset: 0,
            page_size: 20,
        }))
        .expect("recent jobs");
    assert_eq!(
        recent.total_count(),
        2,
        "every durable terminal run is returned for the Jobs landing"
    );
    let listed: Vec<_> = recent
        .items()
        .iter()
        .map(|item| item.job_run_id())
        .collect();
    assert!(listed.contains(&scan_job_run_id));
    assert!(listed.contains(&refresh_job_run_id));
    host.general_shutdown().expect("shutdown");

    let reopened =
        ApplicationHost::new(KernelBootstrapOptions::with_data_directory(data_directory));
    context_ready(&reopened);
    let reopened_recent = reopened
        .list_jobs(ListJobsQuery::new(ListJobsScope::RecentTerminal {
            offset: 0,
            page_size: 20,
        }))
        .expect("recent jobs after restart");
    assert_eq!(
        reopened_recent.total_count(),
        2,
        "terminal history is durable rather than session state"
    );
    let reopened_listed: Vec<_> = reopened_recent
        .items()
        .iter()
        .map(|item| item.job_run_id())
        .collect();
    assert!(reopened_listed.contains(&scan_job_run_id));
    assert!(reopened_listed.contains(&refresh_job_run_id));
    reopened.general_shutdown().expect("second shutdown");
}

#[test]
fn manual_library_refresh_has_one_canonical_refresh_intent() {
    let directory = tempfile::tempdir().expect("tempdir");
    let host = ApplicationHost::new(KernelBootstrapOptions::with_data_directory(
        directory.path().join("data"),
    ));
    context_ready(&host);
    let library = directory.path().join("Library");
    make_library(&library, 1);
    add_root(&host, &library);

    let handle = host.refresh_library().expect("manual refresh admission");
    assert_eq!(handle.operation_type(), "library_refresh");

    let detail = host
        .get_job(handle.job_run_id())
        .expect("refresh job detail");
    assert_eq!(detail.job().operation_type(), "library_refresh");
    match detail.operation_detail() {
        OperationDetail::LibraryRefresh(refresh) => {
            assert_eq!(refresh.trigger(), LibraryRefreshTrigger::Manual);
            assert_eq!(refresh.mode(), RefreshMode::EligibleOnly);
            assert_eq!(refresh.requested_root_ids().len(), 1);
        }
        other => panic!("unexpected operation detail: {other:?}"),
    }
    host.general_shutdown().expect("shutdown");
}

#[test]
#[cfg(feature = "test-support")]
fn manual_library_refresh_composes_committed_scan_identification_grouping_and_hydration() {
    let directory = tempfile::tempdir().expect("tempdir");
    let good = gb_fixture(1);
    let good_second = gb_fixture(3);
    let bad = gb_fixture(2);
    let trace = Arc::new(Mutex::new(ProviderTrace {
        matching_failures: vec![(hex_digest(&bad), HydrationProviderError::Unavailable)],
        ..ProviderTrace::default()
    }));
    let provider_trace = Arc::clone(&trace);
    let options = KernelBootstrapOptions::with_data_directory(directory.path().join("data"))
        .with_provider_session_factory_for_tests(move || {
            provider_trace
                .lock()
                .expect("provider trace")
                .session_factory_calls += 1;
            vec![Box::new(FixtureProviderSession {
                trace: Arc::clone(&provider_trace),
            }) as Box<dyn EnrichmentProviderSession>]
        });
    let host = ApplicationHost::new(options);
    context_ready(&host);

    let library = directory.path().join("Library");
    fs::create_dir_all(&library).expect("library root");
    fs::write(library.join("good-a.gb"), &good).expect("good content");
    fs::write(library.join("good-copy.gb"), &good).expect("duplicate content");
    fs::write(library.join("good-second.gb"), &good_second).expect("second good content");
    fs::write(library.join("bad.gb"), &bad).expect("failing content");
    add_root(&host, &library);

    let handle = host.refresh_library().expect("manual refresh admission");
    assert_eq!(handle.operation_type(), "library_refresh");
    assert_eq!(
        terminal_state(&host, handle.job_run_id()),
        JobRunState::CompletedWithIssues
    );

    let recent = host
        .list_jobs(ListJobsQuery::new(ListJobsScope::RecentTerminal {
            offset: 0,
            page_size: 20,
        }))
        .expect("recent jobs");
    assert_eq!(
        recent.total_count(),
        1,
        "scan work must not create a nested job"
    );
    assert_eq!(recent.items()[0].job_run_id(), handle.job_run_id());
    assert_eq!(recent.items()[0].operation_type(), "library_refresh");

    let detail = host.get_job(handle.job_run_id()).expect("refresh detail");
    let refresh = match detail.operation_detail() {
        OperationDetail::LibraryRefresh(refresh) => refresh,
        other => panic!("unexpected operation detail: {other:?}"),
    };
    assert_eq!(refresh.scan_runs().len(), 1);
    assert_eq!(
        refresh.scan_runs()[0].status(),
        argus_application::ScanRunStatus::Complete
    );
    assert_eq!(
        refresh.progress().phase(),
        Some("library_refresh.completed")
    );
    assert_eq!(
        refresh.progress().completed_units(),
        refresh.progress().total_units()
    );
    assert_eq!(
        refresh.progress().status_key(),
        Some("completed_with_issues")
    );
    // The composed refresh owns its issue accounting: the nested scan run is
    // Complete, so a projection that reused scan intake counters would report
    // "Issues: 0" for a refresh that legitimately terminalized with issues.
    assert_eq!(
        refresh.progress().issue_count(),
        Some(1),
        "a provider failure is an unsatisfied scope the refresh must account for"
    );
    let issues = refresh.progress().issues();
    assert_eq!(issues.len(), 1, "one bounded typed fact per identity");
    assert_eq!(issues[0].kind(), RefreshIssueKind::Matching);
    assert_eq!(issues[0].reason(), RefreshIssueReason::ProviderUnavailable);
    assert_eq!(issues[0].provider_id(), Some(ProviderId::GameTdb));
    assert_eq!(issues[0].occurrences(), 1);
    assert!(
        !issues
            .iter()
            .any(|fact| fact.provider_id() == Some(ProviderId::SteamGridDb)),
        "an unconfigured provider capability is an exclusion, not an issue"
    );
    assert!(
        !format!("{issues:?}").contains("fixture.invalid"),
        "durable issue detail must not carry provider locators"
    );

    let query = ListGamesQuery::builder()
        .scope(LibraryScope::All)
        .search(None)
        .filters_empty(true)
        .sort(LibrarySort::DisplayTitleAscending)
        .page_size(50)
        .build()
        .expect("baseline library query");
    let page = host.list_games(query).expect("logical library page");
    assert_eq!(
        page.items().len(),
        3,
        "duplicate identity should group into one game"
    );
    let details = page
        .items()
        .iter()
        .map(
            |row| match host.get_game(row.game_id()).expect("game detail") {
                GetGameResult::Found(detail) => detail,
                other => panic!("unexpected game result: {other:?}"),
            },
        )
        .collect::<Vec<_>>();
    let grouped = details
        .iter()
        .find(|detail| {
            detail
                .content()
                .iter()
                .any(|content| content.source_count() == 2)
        })
        .expect("duplicate physical sources should share one logical game");
    assert_eq!(
        grouped
            .resolved_metadata()
            .and_then(|metadata| metadata.display_title()),
        Some("Fixture Game")
    );
    assert_eq!(grouped.resolved_artwork().len(), 1);
    let failed = details
        .iter()
        .find(|detail| detail.fallback_title() == "bad.gb")
        .expect("provider failure must not discard committed identification");
    assert_eq!(failed.content().len(), 1);
    assert_eq!(failed.content()[0].source_count(), 1);

    let trace = trace.lock().expect("provider trace");
    assert_eq!(
        trace.session_factory_calls, 1,
        "one provider session per refresh job"
    );
    assert!(
        trace.matching_calls >= 3,
        "each affected content reaches matching"
    );
    assert!(
        trace.metadata_calls >= 2,
        "successful content reaches metadata hydration"
    );
    assert!(
        trace.artwork_calls >= 2,
        "successful content reaches artwork discovery"
    );
    assert!(
        trace.download_calls >= 1,
        "resolved artwork is downloaded and committed"
    );
    host.general_shutdown().expect("shutdown");
}

#[test]
#[cfg(feature = "test-support")]
fn manual_refresh_recognizes_new_nintendo_and_sega_content_with_provider_isolation() {
    let directory = tempfile::tempdir().expect("tempdir");
    let nes = nes_fixture();
    let genesis = genesis_fixture();
    let mut provider_failure = genesis.clone();
    provider_failure[0x200] ^= 0x01;
    let trace = Arc::new(Mutex::new(ProviderTrace {
        matching_failures: vec![(
            stream_hex_digest(provider_failure.clone()),
            HydrationProviderError::Unavailable,
        )],
        ..ProviderTrace::default()
    }));
    let provider_trace = Arc::clone(&trace);
    let options = KernelBootstrapOptions::with_data_directory(directory.path().join("data"))
        .with_provider_session_factory_for_tests(move || {
            provider_trace
                .lock()
                .expect("provider trace")
                .session_factory_calls += 1;
            vec![Box::new(FixtureProviderSession {
                trace: Arc::clone(&provider_trace),
            }) as Box<dyn EnrichmentProviderSession>]
        });
    let host = ApplicationHost::new(options);
    context_ready(&host);

    let library = directory.path().join("Library");
    fs::create_dir_all(&library).expect("library root");
    fs::write(library.join("nes-primary.nes"), &nes).expect("write NES content");
    fs::write(library.join("nes-copy.bin"), &nes).expect("write duplicate NES content");
    fs::write(library.join("genesis.bin"), &genesis).expect("write Genesis content");
    fs::write(
        library.join("genesis-provider-failure.bin"),
        &provider_failure,
    )
    .expect("write Genesis failure content");
    add_root(&host, &library);

    let handle = host.refresh_library().expect("manual refresh admission");
    assert_eq!(
        terminal_state(&host, handle.job_run_id()),
        JobRunState::CompletedWithIssues
    );

    let page = host
        .list_games(
            ListGamesQuery::builder()
                .scope(LibraryScope::All)
                .filters_empty(true)
                .sort(LibrarySort::DisplayTitleAscending)
                .page_size(50)
                .build()
                .expect("library query"),
        )
        .expect("logical library page");
    assert_eq!(
        page.items().len(),
        3,
        "duplicate NES sources must group once"
    );

    let details = page
        .items()
        .iter()
        .map(
            |row| match host.get_game(row.game_id()).expect("game detail") {
                GetGameResult::Found(detail) => detail,
                other => panic!("unexpected game result: {other:?}"),
            },
        )
        .collect::<Vec<_>>();
    let nes_detail = details
        .iter()
        .find(|detail| detail.platform_id() == PlatformId::NintendoNes)
        .expect("NES game");
    assert_eq!(nes_detail.content()[0].source_count(), 2);
    assert!(
        nes_detail.resolved_metadata().is_some(),
        "successful Nintendo enrichment should remain committed"
    );
    assert!(
        details
            .iter()
            .any(|detail| detail.platform_id() == PlatformId::SegaGenesis)
    );
    let failed = details
        .iter()
        .find(|detail| detail.fallback_title() == "genesis-provider-failure.bin")
        .expect("provider failure must preserve Genesis identity");
    assert_eq!(failed.content().len(), 1);

    let trace = trace.lock().expect("provider trace");
    assert!(trace.matching_calls >= 3);
    assert!(trace.metadata_calls >= 2);
    host.general_shutdown().expect("shutdown");
}

#[test]
fn duplicate_same_root_admission_returns_already_scanning() {
    let directory = tempfile::tempdir().expect("tempdir");
    let host = ApplicationHost::new(KernelBootstrapOptions::with_data_directory(
        directory.path().join("data"),
    ));
    context_ready(&host);
    let library = directory.path().join("Library");
    make_library(&library, 3_000);
    let root_id = add_root(&host, &library);
    let first = start_scan(&host, root_id);
    let second = host.start_library_scan(root_id).expect("second admission");
    match second {
        StartLibraryScanResult::AlreadyScanning {
            library_root_id,
            active_job_run_id,
            active_scan_run_id: _,
        } => {
            assert_eq!(library_root_id, root_id);
            assert_eq!(active_job_run_id, first);
        }
        StartLibraryScanResult::Admitted(_) => panic!("expected already scanning"),
    }
    assert_eq!(terminal_state(&host, first), JobRunState::Completed);
    host.general_shutdown().expect("shutdown");
}

#[test]
fn cancellation_reaches_a_durable_terminal_boundary() {
    let directory = tempfile::tempdir().expect("tempdir");
    let host = ApplicationHost::new(KernelBootstrapOptions::with_data_directory(
        directory.path().join("data"),
    ));
    context_ready(&host);
    let library = directory.path().join("Library");
    make_library(&library, 3_000);
    let root_id = add_root(&host, &library);
    let job_run_id = start_scan(&host, root_id);
    let cancel = host.cancel_job(job_run_id).expect("cancel");
    match cancel {
        CancelJobResult::CancellationRequested => {
            assert_eq!(terminal_state(&host, job_run_id), JobRunState::Cancelled);
            let detail = host.get_job(job_run_id).expect("job detail");
            assert!(detail.job().cancellation_requested());
        }
        CancelJobResult::NoLongerCancellable => {
            assert_eq!(terminal_state(&host, job_run_id), JobRunState::Completed);
        }
    }
    host.general_shutdown().expect("shutdown");
}

#[test]
fn shutdown_coordinates_active_background_work() {
    let directory = tempfile::tempdir().expect("tempdir");
    let host = ApplicationHost::new(KernelBootstrapOptions::with_data_directory(
        directory.path().join("data"),
    ));
    context_ready(&host);
    let library = directory.path().join("Library");
    make_library(&library, 3_000);
    let root_id = add_root(&host, &library);
    let job_run_id = start_scan(&host, root_id);
    std::thread::sleep(Duration::from_millis(20));
    host.general_shutdown().expect("shutdown");

    // The worker cancels at its next checkpoint, so the durable job must be
    // terminal (Cancelled or Completed) rather than left Running.
    let reopened = ApplicationHost::new(KernelBootstrapOptions::with_data_directory(
        directory.path().join("data"),
    ));
    context_ready(&reopened);
    let state = reopened
        .get_job(job_run_id)
        .expect("job after restart")
        .job()
        .state();
    assert!(
        matches!(state, JobRunState::Cancelled | JobRunState::Completed),
        "unexpected post-shutdown state: {state:?}"
    );
    reopened.general_shutdown().expect("second shutdown");
}

#[test]
fn job_state_events_cross_the_unified_runtime_stream() {
    let directory = tempfile::tempdir().expect("tempdir");
    let host = ApplicationHost::new(KernelBootstrapOptions::with_data_directory(
        directory.path().join("data"),
    ));
    context_ready(&host);
    let subscription = host.subscribe_events().expect("subscribe");
    let (sender, receiver) = mpsc::channel();
    std::thread::spawn(move || {
        while let Ok(event) = subscription.recv() {
            if matches!(event.payload, RuntimeEventPayload::JobStateChanged { .. }) {
                let _ = sender.send(());
                break;
            }
        }
    });
    let library = directory.path().join("Library");
    make_library(&library, 100);
    let root_id = add_root(&host, &library);
    let job_run_id = start_scan(&host, root_id);
    receiver
        .recv_timeout(Duration::from_secs(15))
        .expect("job state event");
    assert_eq!(terminal_state(&host, job_run_id), JobRunState::Completed);
    host.general_shutdown().expect("shutdown");
}

#[test]
#[cfg(feature = "test-support")]
fn registration_spawn_failure_terminalizes_the_admitted_run() {
    let directory = tempfile::tempdir().expect("tempdir");
    let host = ApplicationHost::new(KernelBootstrapOptions::with_data_directory(
        directory.path().join("data"),
    ));
    context_ready(&host);
    let library = directory.path().join("Library");
    make_library(&library, 50);
    let root_id = add_root(&host, &library);

    host.background_manager_for_tests()
        .expect("manager")
        .fail_next_spawn_for_tests();
    let error = host
        .start_library_scan(root_id)
        .expect_err("spawn failure must surface as a registration failure");
    assert_eq!(error.code, ErrorCode::InternalUnexpected);

    let recent = host
        .list_jobs(ListJobsQuery::new(ListJobsScope::RecentTerminal {
            offset: 0,
            page_size: 20,
        }))
        .expect("recent jobs");
    assert_eq!(recent.total_count(), 1, "no orphan nonterminal JobRun");
    assert_eq!(recent.items()[0].state(), JobRunState::Failed);
    let failed_job_run_id = recent.items()[0].job_run_id();
    let failed_detail = host.get_job(failed_job_run_id).expect("failed job detail");
    let argus_application::OperationDetail::LibraryScan(failed_scan) =
        failed_detail.operation_detail()
    else {
        panic!("expected library scan operation detail");
    };
    assert_eq!(failed_scan.scan_runs().len(), 1);
    assert_eq!(
        failed_scan.scan_runs()[0].status(),
        argus_application::ScanRunStatus::Failed,
        "no orphan active ScanRun"
    );

    let root = host.get_library_root(root_id).expect("root projection");
    assert!(root.active_scan().is_none(), "no orphan active ScanRun");
    assert_eq!(
        root.last_scan().expect("last scan").status(),
        LibraryRootLastScanStatus::Failed
    );

    // A fresh admission proceeds normally after the reconciled failure.
    let second = start_scan(&host, root_id);
    assert_eq!(terminal_state(&host, second), JobRunState::Completed);
    host.general_shutdown().expect("shutdown");
}

/// Creates one host whose enrichment provider is the deterministic fixture
/// session, so refresh tests never reach a real provider or the owner's
/// credential store.
#[cfg(feature = "test-support")]
fn fixture_provider_host(
    data_directory: PathBuf,
    trace: &Arc<Mutex<ProviderTrace>>,
) -> ApplicationHost {
    let provider_trace = Arc::clone(trace);
    let options = KernelBootstrapOptions::with_data_directory(data_directory)
        .with_provider_session_factory_for_tests(move || {
            provider_trace
                .lock()
                .expect("provider trace")
                .session_factory_calls += 1;
            vec![Box::new(FixtureProviderSession {
                trace: Arc::clone(&provider_trace),
            }) as Box<dyn EnrichmentProviderSession>]
        });
    ApplicationHost::new(options)
}

/// Returns the composed refresh detail for one terminal refresh job.
#[cfg(feature = "test-support")]
fn refresh_operation_detail(
    host: &ApplicationHost,
    job_run_id: JobRunId,
) -> LibraryRefreshJobDetail {
    let detail = host.get_job(job_run_id).expect("refresh job detail");
    match detail.operation_detail() {
        OperationDetail::LibraryRefresh(refresh) => refresh.clone(),
        other => panic!("unexpected operation detail: {other:?}"),
    }
}

#[test]
#[cfg(feature = "test-support")]
fn satisfied_library_refresh_persists_an_explicit_zero_issue_summary() {
    let directory = tempfile::tempdir().expect("tempdir");
    let trace = Arc::new(Mutex::new(ProviderTrace::default()));
    let host = fixture_provider_host(directory.path().join("data"), &trace);
    context_ready(&host);
    let library = directory.path().join("Library");
    fs::create_dir_all(&library).expect("library root");
    fs::write(library.join("good.gb"), gb_fixture(21)).expect("good content");
    add_root(&host, &library);

    let handle = host.refresh_library().expect("refresh admission");
    assert_eq!(
        terminal_state(&host, handle.job_run_id()),
        JobRunState::Completed,
        "a fully satisfied eligible refresh is a clean completion"
    );

    let refresh = refresh_operation_detail(&host, handle.job_run_id());
    assert_eq!(
        refresh.progress().phase(),
        Some("library_refresh.completed")
    );
    assert_eq!(refresh.progress().status_key(), Some("completed"));
    assert_eq!(
        refresh.progress().issue_count(),
        Some(0),
        "a v18 execution persists an explicit zero-issue summary"
    );
    assert!(
        refresh.progress().issues().is_empty(),
        "a satisfied refresh must not invent issue detail"
    );

    host.general_shutdown().expect("shutdown");
    let reopened = ApplicationHost::new(KernelBootstrapOptions::with_data_directory(
        directory.path().join("data"),
    ));
    context_ready(&reopened);
    let reopened_detail = reopened
        .get_job(handle.job_run_id())
        .expect("refresh detail after reopen");
    assert_eq!(reopened_detail.job().state(), JobRunState::Completed);
    let OperationDetail::LibraryRefresh(refresh) = reopened_detail.operation_detail() else {
        panic!("expected composed refresh detail after reopen");
    };
    assert_eq!(
        refresh.progress().issue_count(),
        Some(0),
        "the persisted zero-issue summary survives a runtime reopen"
    );
    assert!(refresh.progress().issues().is_empty());
    reopened.general_shutdown().expect("second shutdown");
}

#[test]
#[cfg(feature = "test-support")]
fn refresh_without_executable_provider_scope_stays_completed() {
    let directory = tempfile::tempdir().expect("tempdir");
    let options = KernelBootstrapOptions::with_data_directory(directory.path().join("data"))
        .with_provider_session_factory_for_tests(Vec::new);
    let host = ApplicationHost::new(options);
    context_ready(&host);
    let library = directory.path().join("Library");
    fs::create_dir_all(&library).expect("library root");
    fs::write(library.join("good.gb"), gb_fixture(31)).expect("good content");
    add_root(&host, &library);

    let handle = host.refresh_library().expect("refresh admission");
    assert_eq!(
        terminal_state(&host, handle.job_run_id()),
        JobRunState::Completed,
        "a provider capability that never became executable scope is an exclusion"
    );

    let refresh = refresh_operation_detail(&host, handle.job_run_id());
    assert_eq!(refresh.progress().status_key(), Some("completed"));
    assert_eq!(
        refresh.progress().issue_count(),
        Some(0),
        "an unconfigured provider capability must not create a false issue"
    );
    assert!(refresh.progress().issues().is_empty());

    // Provider-independent work still commits, which is why the exclusion
    // cannot be reported as an unsatisfied scope.
    let page = host
        .list_games(
            ListGamesQuery::builder()
                .scope(LibraryScope::All)
                .filters_empty(true)
                .sort(LibrarySort::DisplayTitleAscending)
                .page_size(50)
                .build()
                .expect("bounded Library query"),
        )
        .expect("Library page");
    assert_eq!(page.items().len(), 1);
    host.general_shutdown().expect("shutdown");
}

#[test]
#[cfg(feature = "test-support")]
fn independent_refresh_failures_aggregate_into_deterministic_typed_facts() {
    let directory = tempfile::tempdir().expect("tempdir");
    let good = gb_fixture(41);
    let timed_out = gb_fixture(43);
    let unavailable = gb_fixture(47);
    let removed = gb_fixture(53);
    let gate = RefreshExecutionGate::new(RefreshExecutionCheckpoint::CommittedRoot);
    let gate_for_hook = Arc::clone(&gate);
    let trace = Arc::new(Mutex::new(ProviderTrace {
        matching_failures: vec![
            (hex_digest(&timed_out), HydrationProviderError::Timeout),
            (
                hex_digest(&unavailable),
                HydrationProviderError::Unavailable,
            ),
        ],
        ..ProviderTrace::default()
    }));
    let provider_trace = Arc::clone(&trace);
    let options = KernelBootstrapOptions::with_data_directory(directory.path().join("data"))
        .with_provider_session_factory_for_tests(move || {
            provider_trace
                .lock()
                .expect("provider trace")
                .session_factory_calls += 1;
            vec![Box::new(FixtureProviderSession {
                trace: Arc::clone(&provider_trace),
            }) as Box<dyn EnrichmentProviderSession>]
        })
        .with_refresh_execution_hook_for_tests(move |checkpoint| gate_for_hook.hook(checkpoint));
    let host = ApplicationHost::new(options);
    context_ready(&host);
    let library = directory.path().join("Library");
    fs::create_dir_all(&library).expect("library root");
    fs::write(library.join("good.gb"), &good).expect("good content");
    fs::write(library.join("timed-out.gb"), &timed_out).expect("timeout content");
    fs::write(library.join("unavailable.gb"), &unavailable).expect("unavailable content");
    fs::write(library.join("removed.gb"), &removed).expect("removable content");
    add_root(&host, &library);

    // The committed child scan is complete before refresh-level content work
    // starts, so removing one admitted file here deterministically fails only
    // the refresh's own local read rather than the scan.
    gate.arm();
    let handle = host.refresh_library().expect("refresh admission");
    gate.wait_until_entered();
    fs::remove_file(library.join("removed.gb")).expect("remove admitted content");
    gate.release();

    assert_eq!(
        terminal_state(&host, handle.job_run_id()),
        JobRunState::CompletedWithIssues
    );
    let refresh = refresh_operation_detail(&host, handle.job_run_id());
    assert_eq!(
        refresh.progress().status_key(),
        Some("completed_with_issues")
    );
    assert_eq!(refresh.scan_runs().len(), 1);
    assert_eq!(
        refresh.scan_runs()[0].status(),
        argus_application::ScanRunStatus::Complete,
        "the nested scan is still complete; only refresh scope stayed unsatisfied"
    );

    let facts = refresh.progress().issues();
    assert_eq!(
        refresh.progress().issue_count(),
        Some(3),
        "every independent failure is counted exactly once"
    );
    assert_eq!(facts.len(), 3, "distinct typed identities never merge");
    // Deterministic ordering: kind, then reason, then provider.
    assert_eq!(facts[0].kind(), RefreshIssueKind::Matching);
    assert_eq!(facts[0].reason(), RefreshIssueReason::ProviderTimeout);
    assert_eq!(facts[0].provider_id(), Some(ProviderId::GameTdb));
    assert_eq!(facts[0].occurrences(), 1);
    assert_eq!(facts[1].kind(), RefreshIssueKind::Matching);
    assert_eq!(facts[1].reason(), RefreshIssueReason::ProviderUnavailable);
    assert_eq!(facts[1].provider_id(), Some(ProviderId::GameTdb));
    assert_eq!(facts[1].occurrences(), 1);
    assert_eq!(facts[2].kind(), RefreshIssueKind::Content);
    assert_eq!(facts[2].reason(), RefreshIssueReason::ContentUnavailable);
    assert_eq!(facts[2].provider_id(), None);
    assert_eq!(facts[2].occurrences(), 1);

    // Successful provider-independent work stays committed alongside the
    // partial failures.
    let page = host
        .list_games(
            ListGamesQuery::builder()
                .scope(LibraryScope::All)
                .filters_empty(true)
                .sort(LibrarySort::DisplayTitleAscending)
                .page_size(50)
                .build()
                .expect("bounded Library query"),
        )
        .expect("Library page");
    let titles = page
        .items()
        .iter()
        .map(|row| row.display_title().to_owned())
        .collect::<Vec<_>>();
    assert!(
        titles.iter().any(|title| title == "Fixture Game"),
        "clean content must still commit its hydration: {titles:?}"
    );
    host.general_shutdown().expect("shutdown");
}

#[test]
#[cfg(feature = "test-support")]
fn library_refresh_missing_root_after_complete_scan_reports_content_unavailable() {
    let directory = tempfile::tempdir().expect("tempdir");
    let gate = RefreshExecutionGate::new(RefreshExecutionCheckpoint::CommittedRoot);
    let gate_for_hook = Arc::clone(&gate);
    let options = KernelBootstrapOptions::with_data_directory(directory.path().join("data"))
        .with_provider_session_factory_for_tests(Vec::new)
        .with_refresh_execution_hook_for_tests(move |checkpoint| gate_for_hook.hook(checkpoint));
    let host = ApplicationHost::new(options);
    context_ready(&host);

    let library = directory.path().join("Library");
    fs::create_dir_all(&library).expect("library root");
    fs::write(library.join("game.gb"), gb_fixture(61)).expect("game content");
    add_root(&host, &library);

    // The checkpoint runs after the child scan commits but before refresh-level
    // root resolution, so removing the directory isolates the refresh failure.
    gate.arm();
    let handle = host.refresh_library().expect("refresh admission");
    gate.wait_until_entered();
    fs::remove_dir_all(&library).expect("remove admitted root");
    gate.release();

    assert_eq!(
        terminal_state(&host, handle.job_run_id()),
        JobRunState::CompletedWithIssues
    );
    let refresh = refresh_operation_detail(&host, handle.job_run_id());
    assert_eq!(refresh.scan_runs().len(), 1);
    assert_eq!(
        refresh.scan_runs()[0].status(),
        argus_application::ScanRunStatus::Complete,
        "the child scan remains durably complete despite later root loss"
    );
    assert_eq!(refresh.progress().issue_count(), Some(1));
    let facts = refresh.progress().issues();
    assert_eq!(facts.len(), 1);
    assert_eq!(facts[0].kind(), RefreshIssueKind::Content);
    assert_eq!(facts[0].reason(), RefreshIssueReason::ContentUnavailable);
    assert_ne!(facts[0].reason(), RefreshIssueReason::ContentRefreshFailed);

    host.general_shutdown().expect("shutdown");
}

#[test]
#[cfg(feature = "test-support")]
fn clean_library_refresh_persists_an_explicit_zero_issue_summary() {
    let directory = tempfile::tempdir().expect("tempdir");
    let data_directory = directory.path().join("data");
    let host = ApplicationHost::new(KernelBootstrapOptions::with_data_directory(
        data_directory.clone(),
    ));
    context_ready(&host);
    let library = directory.path().join("Library");
    fs::create_dir_all(&library).expect("library root");
    add_root(&host, &library);

    let handle = host.refresh_library().expect("refresh admission");
    assert_eq!(
        terminal_state(&host, handle.job_run_id()),
        JobRunState::Completed
    );
    let live = refresh_operation_detail(&host, handle.job_run_id());
    assert_eq!(live.progress().issue_count(), Some(0));
    assert!(live.progress().issues().is_empty());
    host.general_shutdown().expect("shutdown");

    let reopened =
        ApplicationHost::new(KernelBootstrapOptions::with_data_directory(data_directory));
    context_ready(&reopened);
    let detail = reopened
        .get_job(handle.job_run_id())
        .expect("clean refresh detail after reopen");
    let OperationDetail::LibraryRefresh(refresh) = detail.operation_detail() else {
        panic!("expected composed refresh detail after reopen");
    };
    assert_eq!(refresh.progress().issue_count(), Some(0));
    assert!(refresh.progress().issues().is_empty());
    reopened.general_shutdown().expect("second shutdown");
}

#[test]
#[cfg(feature = "test-support")]
fn direct_descriptor_and_playlist_failures_keep_typed_content_reasons() {
    let directory = tempfile::tempdir().expect("tempdir");
    let host = ApplicationHost::new(KernelBootstrapOptions::with_data_directory(
        directory.path().join("data"),
    ));
    context_ready(&host);
    let library = directory.path().join("Library");
    fs::create_dir_all(&library).expect("library root");

    // Direct descriptor reads and M3U parsing have separate bounded inputs.
    // Both resource-limit failures must retain that normalized reason.
    fs::write(library.join("oversized.cue"), vec![b' '; 1024 * 1024 + 1])
        .expect("oversized descriptor");
    let too_many_playlist_members = (0..129)
        .map(|index| format!("missing-{index}.iso\n"))
        .collect::<String>();
    fs::write(library.join("too-many.m3u"), too_many_playlist_members)
        .expect("oversized playlist scope");

    // Different backend parse outcomes still share the broad malformed or
    // unsupported product reason, and identical typed facts aggregate.
    fs::write(library.join("empty.cue"), b"").expect("malformed descriptor");
    fs::write(library.join("unsupported.cue"), b"NOT A DESCRIPTOR\n")
        .expect("unsupported descriptor");
    fs::write(library.join("empty.m3u"), b"").expect("malformed playlist");
    add_root(&host, &library);

    let handle = host.refresh_library().expect("refresh admission");
    assert_eq!(
        terminal_state(&host, handle.job_run_id()),
        JobRunState::CompletedWithIssues
    );
    let refresh = refresh_operation_detail(&host, handle.job_run_id());
    assert_eq!(refresh.progress().issue_count(), Some(5));
    assert_eq!(refresh.progress().issues().len(), 2);
    let resource_limit = refresh
        .progress()
        .issues()
        .iter()
        .find(|fact| fact.reason() == RefreshIssueReason::ContentResourceLimitExceeded)
        .expect("resource-limit explanation");
    assert_eq!(resource_limit.kind(), RefreshIssueKind::Content);
    assert_eq!(resource_limit.occurrences(), 2);
    let malformed = refresh
        .progress()
        .issues()
        .iter()
        .find(|fact| fact.reason() == RefreshIssueReason::ContentMalformedOrUnsupported)
        .expect("malformed/unsupported explanation");
    assert_eq!(malformed.kind(), RefreshIssueKind::Content);
    assert_eq!(malformed.occurrences(), 3);
    host.general_shutdown().expect("shutdown");
}

#[test]
#[cfg(feature = "test-support")]
fn cancelled_refresh_detail_without_a_summary_remains_unknown_after_reopen() {
    let directory = tempfile::tempdir().expect("tempdir");
    let data_directory = directory.path().join("data");
    let host = ApplicationHost::new(KernelBootstrapOptions::with_data_directory(
        data_directory.clone(),
    ));
    context_ready(&host);
    let library = directory.path().join("Library");
    fs::create_dir_all(&library).expect("library root");
    add_root(&host, &library);

    let handle = host.refresh_library().expect("refresh admission");
    assert_eq!(
        terminal_state(&host, handle.job_run_id()),
        JobRunState::Completed
    );
    host.general_shutdown().expect("shutdown");

    // Model an accepted cancellation after the terminal lifecycle has been
    // persisted. A non-success historical run has no finalized refresh issue
    // summary, so GetJob must keep its issue projection unknown.
    let job_run_id = handle.job_run_id();
    let rewrite = format!(
        "DELETE FROM library_refresh_issue_fact WHERE job_run_id = '{job_run_id}';
         DELETE FROM library_refresh_issue_summary WHERE job_run_id = '{job_run_id}';
         UPDATE job_run SET state = 'cancelled' WHERE job_run_id = '{job_run_id}';"
    );
    rewrite_refresh_issue_projection(&data_directory, &rewrite);

    let reopened =
        ApplicationHost::new(KernelBootstrapOptions::with_data_directory(data_directory));
    context_ready(&reopened);
    let detail = reopened
        .get_job(handle.job_run_id())
        .expect("cancelled refresh detail after reopen");
    let OperationDetail::LibraryRefresh(refresh) = detail.operation_detail() else {
        panic!("expected composed refresh detail after reopen");
    };
    assert_eq!(detail.job().state(), JobRunState::Cancelled);
    assert_eq!(refresh.progress().issue_count(), None);
    assert!(refresh.progress().issues().is_empty());
    reopened.general_shutdown().expect("second shutdown");
}

#[test]
#[cfg(feature = "test-support")]
fn refresh_issue_projection_survives_runtime_reopen() {
    let directory = tempfile::tempdir().expect("tempdir");
    let failing = gb_fixture(59);
    let trace = Arc::new(Mutex::new(ProviderTrace {
        matching_failures: vec![(hex_digest(&failing), HydrationProviderError::RateLimited)],
        ..ProviderTrace::default()
    }));
    let host = fixture_provider_host(directory.path().join("data"), &trace);
    context_ready(&host);
    let library = directory.path().join("Library");
    fs::create_dir_all(&library).expect("library root");
    fs::write(library.join("failing.gb"), &failing).expect("failing content");
    add_root(&host, &library);

    let handle = host.refresh_library().expect("refresh admission");
    assert_eq!(
        terminal_state(&host, handle.job_run_id()),
        JobRunState::CompletedWithIssues
    );
    let live = refresh_operation_detail(&host, handle.job_run_id());
    assert_eq!(live.progress().issue_count(), Some(1));
    assert_eq!(live.progress().issues().len(), 1);
    assert_eq!(
        live.progress().issues()[0].reason(),
        RefreshIssueReason::ProviderRateLimited
    );
    host.general_shutdown().expect("shutdown");

    let reopened = ApplicationHost::new(KernelBootstrapOptions::with_data_directory(
        directory.path().join("data"),
    ));
    context_ready(&reopened);
    let reopened_detail = reopened
        .get_job(handle.job_run_id())
        .expect("refresh detail after reopen");
    assert_eq!(
        reopened_detail.job().state(),
        JobRunState::CompletedWithIssues,
        "the durable lifecycle state is not re-derived from current controllers"
    );
    let OperationDetail::LibraryRefresh(refresh) = reopened_detail.operation_detail() else {
        panic!("expected composed refresh detail after reopen");
    };
    assert_eq!(
        refresh.progress().status_key(),
        Some("completed_with_issues")
    );
    assert_eq!(refresh.progress().issue_count(), Some(1));
    assert_eq!(
        refresh.progress().issues(),
        live.progress().issues(),
        "the bounded explanation is durable rather than reconstructed"
    );
    reopened.general_shutdown().expect("second shutdown");
}

/// Rewrites the durable refresh issue projection for one fixture job.
///
/// The database is opened separately from the running host so one test can
/// exercise every contradictory representation without restarting the runtime,
/// and through the plain driver so the fixture only changes data rows.
#[cfg(feature = "test-support")]
fn rewrite_refresh_issue_projection(data_directory: &Path, statement: &str) {
    let connection =
        rusqlite::Connection::open(data_directory.join("argus.sqlite3")).expect("fixture database");
    connection
        .busy_timeout(Duration::from_secs(5))
        .expect("fixture busy timeout");
    connection
        .execute_batch(statement)
        .expect("refresh issue fixture");
}

#[test]
#[cfg(feature = "test-support")]
fn contradictory_persisted_refresh_issue_projection_is_rejected() {
    let directory = tempfile::tempdir().expect("tempdir");
    let data_directory = directory.path().join("data");
    let failing = gb_fixture(67);
    let trace = Arc::new(Mutex::new(ProviderTrace {
        matching_failures: vec![(hex_digest(&failing), HydrationProviderError::Unavailable)],
        ..ProviderTrace::default()
    }));
    let host = fixture_provider_host(data_directory.clone(), &trace);
    context_ready(&host);
    let library = directory.path().join("Library");
    fs::create_dir_all(&library).expect("library root");
    fs::write(library.join("failing.gb"), &failing).expect("failing content");
    add_root(&host, &library);

    let handle = host.refresh_library().expect("refresh admission");
    assert_eq!(
        terminal_state(&host, handle.job_run_id()),
        JobRunState::CompletedWithIssues
    );
    let job_run_id = handle.job_run_id();

    // Restoring the truthful projection before every corruption keeps each
    // contradiction independently responsible for its rejection.
    const RESTORE: &str = "DELETE FROM library_refresh_issue_fact;
         INSERT INTO library_refresh_issue_fact
             (job_run_id, issue_ordinal, issue_kind, issue_reason, provider_id, occurrences)
         SELECT job_run_id, 0, 'matching', 'provider_unavailable', 'gametdb', 1
         FROM library_refresh_issue_summary;
         UPDATE library_refresh_issue_summary SET issue_count = 1;";
    let corruptions = [
        (
            "a summary total that no longer matches the checked fact sum",
            "UPDATE library_refresh_issue_summary SET issue_count = 9;",
        ),
        (
            "a persisted occurrence that is not positive",
            "PRAGMA ignore_check_constraints = ON;
             UPDATE library_refresh_issue_fact SET occurrences = 0;",
        ),
        (
            "a persisted summary total outside the representable domain",
            "PRAGMA ignore_check_constraints = ON;
             UPDATE library_refresh_issue_summary SET issue_count = -1;",
        ),
        (
            "a persisted reason outside the closed vocabulary",
            "PRAGMA ignore_check_constraints = ON;
             UPDATE library_refresh_issue_fact
             SET issue_reason = 'raw provider transport failure text';",
        ),
        (
            "a checked fact sum that cannot be represented",
            "PRAGMA ignore_check_constraints = ON;
             UPDATE library_refresh_issue_fact SET occurrences = 9223372036854775807;
             INSERT INTO library_refresh_issue_fact
                 (job_run_id, issue_ordinal, issue_kind, issue_reason, provider_id, occurrences)
             SELECT job_run_id, 1, 'content', 'content_unavailable', NULL, 9223372036854775807
             FROM library_refresh_issue_summary;",
        ),
    ];

    for (label, corruption) in corruptions {
        let batch = format!("{RESTORE}\n{corruption}");
        rewrite_refresh_issue_projection(&data_directory, &batch);
        let error = host
            .get_job(job_run_id)
            .expect_err("a contradictory durable projection is not a valid job detail");
        assert_eq!(
            error.code,
            ErrorCode::PersistenceIncompatibleSchema,
            "{label}"
        );
    }

    // The truthful projection is readable again, so the rejection comes from
    // the contradiction rather than from an unreadable job.
    rewrite_refresh_issue_projection(&data_directory, RESTORE);
    let refresh = refresh_operation_detail(&host, job_run_id);
    assert_eq!(refresh.progress().issue_count(), Some(1));
    host.general_shutdown().expect("shutdown");
}

#[test]
#[cfg(feature = "test-support")]
fn fatal_refresh_execution_failure_remains_failed() {
    let directory = tempfile::tempdir().expect("tempdir");
    let data_directory = directory.path().join("data");
    let trace = Arc::new(Mutex::new(ProviderTrace::default()));
    let host = fixture_provider_host(data_directory.clone(), &trace);
    context_ready(&host);
    let library = directory.path().join("Library");
    fs::create_dir_all(&library).expect("library root");
    fs::write(library.join("good.gb"), gb_fixture(71)).expect("good content");
    add_root(&host, &library);

    // The refresh cannot start its content pipeline without a usable staging
    // directory. That failure is propagated by the owning execution path, so
    // it must stay fatal instead of becoming a bounded refresh issue.
    let staging = directory
        .path()
        .join("data")
        .join(argus_infrastructure::content::TRANSFORMATION_STAGING_DIRECTORY);
    if staging.is_dir() {
        fs::remove_dir_all(&staging).expect("clear staging directory");
    }
    fs::write(&staging, b"staging path is not a directory").expect("staging sabotage");

    let handle = host.refresh_library().expect("refresh admission");
    assert_eq!(
        terminal_state(&host, handle.job_run_id()),
        JobRunState::Failed,
        "a propagated execution failure stays fatal"
    );
    let refresh = refresh_operation_detail(&host, handle.job_run_id());
    assert_ne!(
        refresh.progress().status_key(),
        Some("completed_with_issues"),
        "a fatal run is never relabeled as a partial success"
    );
    assert_eq!(
        refresh.progress().issue_count(),
        None,
        "a fatal run never persists a bounded issue summary"
    );
    assert!(refresh.progress().issues().is_empty());
    host.general_shutdown().expect("shutdown");

    fs::remove_file(&staging).expect("remove staging sabotage");
    let reopened =
        ApplicationHost::new(KernelBootstrapOptions::with_data_directory(data_directory));
    context_ready(&reopened);
    let detail = reopened
        .get_job(handle.job_run_id())
        .expect("failed refresh detail after reopen");
    let OperationDetail::LibraryRefresh(refresh) = detail.operation_detail() else {
        panic!("expected composed refresh detail after reopen");
    };
    assert_eq!(detail.job().state(), JobRunState::Failed);
    assert_eq!(refresh.progress().issue_count(), None);
    assert!(refresh.progress().issues().is_empty());
    reopened.general_shutdown().expect("second shutdown");
}

#[test]
#[cfg(feature = "test-support")]
fn historical_refresh_without_a_summary_reports_an_unknown_issue_projection() {
    let directory = tempfile::tempdir().expect("tempdir");
    let data_directory = directory.path().join("data");
    let failing = gb_fixture(73);
    let trace = Arc::new(Mutex::new(ProviderTrace {
        matching_failures: vec![(hex_digest(&failing), HydrationProviderError::Unavailable)],
        ..ProviderTrace::default()
    }));
    let host = fixture_provider_host(data_directory.clone(), &trace);
    context_ready(&host);
    let library = directory.path().join("Library");
    fs::create_dir_all(&library).expect("library root");
    fs::write(library.join("failing.gb"), &failing).expect("failing content");
    add_root(&host, &library);

    let handle = host.refresh_library().expect("refresh admission");
    assert_eq!(
        terminal_state(&host, handle.job_run_id()),
        JobRunState::CompletedWithIssues
    );

    // A pre-v18 execution has no refresh-issue rows at all. The projection is
    // then unknown rather than fabricated from the nested scan run.
    rewrite_refresh_issue_projection(
        &data_directory,
        "DELETE FROM library_refresh_issue_fact;
         DELETE FROM library_refresh_issue_summary;",
    );
    let refresh = refresh_operation_detail(&host, handle.job_run_id());
    assert_eq!(
        refresh.progress().issue_count(),
        None,
        "an unknown historical projection is not zero"
    );
    assert!(refresh.progress().issues().is_empty());
    assert_eq!(
        refresh.progress().status_key(),
        Some("completed_with_issues")
    );
    host.general_shutdown().expect("shutdown");
}
