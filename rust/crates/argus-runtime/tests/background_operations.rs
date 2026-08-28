//! Runtime-level Slice 002 background-operation integration tests.

use std::fs;
use std::path::Path;
use std::sync::mpsc;
#[cfg(feature = "test-support")]
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use argus_application::{
    AddLocalLibraryRootResult, CancelJobResult, JobRunId, JobRunState, LibraryRefreshTrigger,
    LibraryRootId, LibraryRootLastScanStatus, ListJobsQuery, ListJobsScope,
    LocalFilesystemRootSelection, OperationDetail, RefreshMode, StartLibraryScanResult,
};
#[cfg(feature = "test-support")]
use argus_application::{
    ArtworkCandidate, ArtworkReference, ArtworkType, EnrichmentProviderSession, ErrorCode,
    ExactMatchEvidence, GetGameResult, HydrationMappingCandidate, HydrationProviderError,
    HydrationTarget, LibraryScope, LibrarySort, ListGamesQuery, PlatformId, ProviderId,
    ProviderMetadata,
};
#[cfg(feature = "test-support")]
use argus_infrastructure::content::{ContentReadError, ContentReader};
use argus_runtime::{
    ApplicationHost, KernelBootstrapOptions, RuntimeEventPayload, RuntimeLifecycle,
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
    failed_identity: Option<String>,
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
        if trace.failed_identity.as_deref() == Some(target.submitted_identity()) {
            return Err(HydrationProviderError::Unavailable);
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

fn add_root(host: &ApplicationHost, path: &Path) -> LibraryRootId {
    let result = host
        .add_local_library_root(LocalFilesystemRootSelection::new(
            path.to_string_lossy().into_owned(),
        ))
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
        failed_identity: Some(hex_digest(&bad)),
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
        failed_identity: Some(stream_hex_digest(provider_failure.clone())),
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
