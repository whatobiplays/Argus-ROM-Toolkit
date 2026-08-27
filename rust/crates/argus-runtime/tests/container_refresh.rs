#![cfg(feature = "test-support")]

use std::fs;
use std::io::Write;
use std::path::Path;
use std::time::{Duration, Instant};

use argus_application::{
    AddLocalLibraryRootResult, EnrichmentProviderSession, JobRunState, LibraryRootId,
    ListGamesQuery, ListSourceEntryChildrenQuery, LocalFilesystemRootSelection, SourceEntryId,
};
use argus_runtime::{ApplicationHost, KernelBootstrapOptions};
use tempfile::TempDir;
use zip::{ZipWriter, write::SimpleFileOptions};

const GBA_LOGO: [u8; 156] = [
    0x24, 0xFF, 0xAE, 0x51, 0x69, 0x9A, 0xA2, 0x21, 0x3D, 0x84, 0x82, 0x0A, 0x84, 0xE4, 0x09, 0xAD,
    0x11, 0x24, 0x8B, 0x98, 0xC0, 0x81, 0x7F, 0x21, 0xA3, 0x52, 0xBE, 0x19, 0x93, 0x09, 0xCE, 0x20,
    0x10, 0x46, 0x4A, 0x4A, 0xF8, 0x27, 0x31, 0xEC, 0x58, 0xC7, 0xE8, 0x33, 0x82, 0xE3, 0xCE, 0xBF,
    0x85, 0xF4, 0xDF, 0x94, 0xCE, 0x4B, 0x09, 0xC1, 0x94, 0x56, 0x8A, 0xC0, 0x13, 0x72, 0xA7, 0xFC,
    0x9F, 0x84, 0x4D, 0x73, 0xA3, 0xCA, 0x9A, 0x61, 0x58, 0x97, 0xA3, 0x27, 0xFC, 0x03, 0x98, 0x76,
    0x23, 0x1D, 0xC7, 0x61, 0x03, 0x04, 0xAE, 0x56, 0xBF, 0x38, 0x84, 0x00, 0x40, 0xA7, 0x0E, 0xFD,
    0xFF, 0x52, 0xFE, 0x03, 0x6F, 0x95, 0x30, 0xF1, 0x97, 0xFB, 0xC0, 0x85, 0x60, 0xD6, 0x80, 0x25,
    0xA9, 0x63, 0xBE, 0x03, 0x01, 0x4E, 0x38, 0xE2, 0xF9, 0xA2, 0x34, 0xFF, 0xBB, 0x3E, 0x03, 0x44,
    0x78, 0x00, 0x90, 0xCB, 0x88, 0x11, 0x3A, 0x94, 0x65, 0xC0, 0x7C, 0x63, 0x87, 0xF0, 0x3C, 0xAF,
    0xD6, 0x25, 0xE4, 0x8B, 0x38, 0x0A, 0xAC, 0x72, 0x21, 0xD4, 0xF8, 0x07,
];

fn gba_fixture(marker: u8) -> Vec<u8> {
    let mut bytes = vec![0_u8; 0x8000];
    bytes[0x00..0x04].copy_from_slice(&[0x2E, 0x00, 0x00, 0xEA]);
    bytes[0x04..0xa0].copy_from_slice(&GBA_LOGO);
    bytes[0xa0..0xac].copy_from_slice(b"TEST TITLE  ");
    bytes[0xac..0xb2].copy_from_slice(b"TEST01");
    bytes[0xb2] = 0x96;
    bytes[0x200] = marker;
    let sum = bytes[0xa0..0xbd]
        .iter()
        .fold(0_u8, |sum, byte| sum.wrapping_add(*byte))
        .wrapping_add(0x19);
    bytes[0xbd] = 0_u8.wrapping_sub(sum);
    bytes
}

fn zip_fixture(game: &[u8], second_game: Option<&[u8]>) -> Vec<u8> {
    let mut bytes = Vec::new();
    let mut writer = ZipWriter::new(std::io::Cursor::new(&mut bytes));
    writer
        .start_file("game.gba", SimpleFileOptions::default())
        .expect("game member");
    writer.write_all(game).expect("game bytes");
    writer
        .start_file("README.txt", SimpleFileOptions::default())
        .expect("sidecar member");
    writer.write_all(b"sidecar").expect("sidecar bytes");
    if let Some(second_game) = second_game {
        writer
            .start_file("second.gba", SimpleFileOptions::default())
            .expect("second member");
        writer.write_all(second_game).expect("second bytes");
    }
    writer.finish().expect("zip finish");
    bytes
}

fn add_root(host: &ApplicationHost, path: &Path) -> LibraryRootId {
    match host
        .add_local_library_root(LocalFilesystemRootSelection::new(
            path.to_string_lossy().into_owned(),
        ))
        .expect("add root")
    {
        AddLocalLibraryRootResult::Added(root) => root.root_id(),
        other => panic!("unexpected root result: {other:?}"),
    }
}

fn wait_terminal(host: &ApplicationHost, job_run_id: argus_application::JobRunId) {
    let deadline = Instant::now() + Duration::from_secs(15);
    loop {
        if host
            .get_job(job_run_id)
            .expect("job detail")
            .job()
            .state()
            .is_terminal()
        {
            return;
        }
        assert!(Instant::now() < deadline, "timed out waiting for refresh");
        std::thread::sleep(Duration::from_millis(10));
    }
}

fn refresh(host: &ApplicationHost) {
    let handle = host.refresh_library().expect("refresh admission");
    wait_terminal(host, handle.job_run_id());
    assert!(matches!(
        host.get_job(handle.job_run_id())
            .expect("refresh detail")
            .job()
            .state(),
        JobRunState::Completed | JobRunState::CompletedWithIssues
    ));
}

fn setup() -> (TempDir, ApplicationHost, LibraryRootId) {
    let directory = tempfile::tempdir().expect("tempdir");
    let host = ApplicationHost::new(
        KernelBootstrapOptions::with_data_directory(directory.path().join("data"))
            .with_provider_session_factory_for_tests(|| {
                Vec::<Box<dyn EnrichmentProviderSession>>::new()
            }),
    );
    host.initialize().expect("initialize");
    let library = directory.path().join("Library");
    fs::create_dir_all(&library).expect("library root");
    let root_id = add_root(&host, &library);
    (directory, host, root_id)
}

fn archive_source_id(host: &ApplicationHost, root_id: LibraryRootId) -> SourceEntryId {
    host.list_source_entry_children(ListSourceEntryChildrenQuery::new(root_id, None, None, 100))
        .expect("root entries")
        .items()
        .iter()
        .find(|entry| entry.display_name() == "game.zip")
        .expect("archive source")
        .source_entry_id()
}

#[test]
fn refresh_identifies_one_game_archive_and_stabilizes_source_ids() {
    let (directory, host, root_id) = setup();
    let library = directory.path().join("Library");
    fs::write(library.join("game.zip"), zip_fixture(&gba_fixture(1), None)).expect("write archive");

    refresh(&host);
    let first_page = host
        .list_games(
            ListGamesQuery::builder()
                .page_size(50)
                .filters_empty(true)
                .build()
                .expect("games query"),
        )
        .expect("games page");
    assert_eq!(first_page.items().len(), 1);
    let game_id = first_page.items()[0].game_id();
    let archive_id = archive_source_id(&host, root_id);
    let first_children = host
        .list_source_entry_children(ListSourceEntryChildrenQuery::new(
            root_id,
            Some(archive_id),
            None,
            100,
        ))
        .expect("derived children");
    let game_child = first_children
        .items()
        .iter()
        .find(|entry| entry.display_name() == "game.gba")
        .expect("derived game member")
        .source_entry_id();

    refresh(&host);
    let second_page = host
        .list_games(
            ListGamesQuery::builder()
                .page_size(50)
                .filters_empty(true)
                .build()
                .expect("games query"),
        )
        .expect("games page");
    assert_eq!(second_page.items().len(), 1);
    assert_eq!(second_page.items()[0].game_id(), game_id);
    let second_archive_id = archive_source_id(&host, root_id);
    assert_eq!(second_archive_id, archive_id);
    let second_child = host
        .list_source_entry_children(ListSourceEntryChildrenQuery::new(
            root_id,
            Some(second_archive_id),
            None,
            100,
        ))
        .expect("derived children")
        .items()
        .iter()
        .find(|entry| entry.display_name() == "game.gba")
        .expect("derived game member")
        .source_entry_id();
    assert_eq!(second_child, game_child);
    host.general_shutdown().expect("shutdown");
}

#[test]
fn multi_game_archive_keeps_derived_truth_without_creating_games() {
    let (directory, host, root_id) = setup();
    let library = directory.path().join("Library");
    fs::write(
        library.join("game.zip"),
        zip_fixture(&gba_fixture(1), Some(&gba_fixture(2))),
    )
    .expect("write archive");

    refresh(&host);
    let page = host
        .list_games(
            ListGamesQuery::builder()
                .page_size(50)
                .filters_empty(true)
                .build()
                .expect("games query"),
        )
        .expect("games page");
    assert!(page.items().is_empty());
    let archive_id = archive_source_id(&host, root_id);
    let children = host
        .list_source_entry_children(ListSourceEntryChildrenQuery::new(
            root_id,
            Some(archive_id),
            None,
            100,
        ))
        .expect("derived children");
    assert!(
        children
            .items()
            .iter()
            .any(|entry| entry.display_name() == "game.gba")
    );
    assert!(
        children
            .items()
            .iter()
            .any(|entry| entry.display_name() == "second.gba")
    );
    host.general_shutdown().expect("shutdown");
}
