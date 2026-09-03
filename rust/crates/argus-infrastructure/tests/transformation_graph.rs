#![cfg(feature = "test-support")]

mod common;

use std::io::{Cursor, Write};
use std::thread;
use std::time::Duration;

use argus_application::{
    LibrarySourceAccess, ScanRunId, SourceEntryClassification, SourceEntryId, SourceEntryKind,
    SourceEntryRecord, SourceLocatorKey, SourceVersionEvidence, TransformationBudget,
    TransformationFailure,
};
use argus_infrastructure::content::{
    ContentReadError, ContentReader, ContentSourceResolver, DerivedScopeResult, ParsingSession,
    enumerate_derived_container,
};
use argus_infrastructure::local_filesystem::LocalFilesystemSourceAccess;
use tempfile::tempdir;
use zip::{ZipWriter, write::SimpleFileOptions};

const ZIP_TRANSFORMATION: &str = "argus.transformation.zip.v1";

fn scan_id() -> ScanRunId {
    ScanRunId::try_from("22222222222222222222222222222222").expect("scan id")
}

fn budget() -> TransformationBudget {
    TransformationBudget::new(
        1024 * 1024,
        4 * 1024 * 1024,
        32,
        4,
        4 * 1024 * 1024,
        16 * 1024 * 1024,
    )
}

fn zip_bytes(name: &str, bytes: &[u8]) -> Vec<u8> {
    let mut output = Cursor::new(Vec::new());
    let mut writer = ZipWriter::new(&mut output);
    writer
        .start_file(name, SimpleFileOptions::default())
        .expect("zip member");
    writer.write_all(bytes).expect("zip bytes");
    writer.finish().expect("zip finish");
    output.into_inner()
}

fn enumerate_bytes(bytes: &[u8], parent: &SourceVersionEvidence) -> DerivedScopeResult {
    let staging = tempdir().expect("staging root");
    let mut session = ParsingSession::for_tests(budget(), staging.path(), || false);
    let mut reader = BytesReader::new(bytes.to_vec());
    enumerate_derived_container(&mut reader, parent, &mut session)
        .expect("zip enumeration")
        .expect("zip wrapper")
}

fn derived_record(
    source_entry_id: SourceEntryId,
    parent_source_entry_id: SourceEntryId,
    display_name: &str,
    observation: &argus_application::DerivedEntryObservation,
) -> SourceEntryRecord {
    SourceEntryRecord::from_coordinates(
        source_entry_id,
        Some(parent_source_entry_id),
        display_name,
        display_name,
        SourceEntryKind::File,
        SourceEntryClassification::SupportingEntry,
        argus_application::SourceEntryCoordinates::Derived {
            derived_locator: observation.derived_locator().clone(),
            derived_entry_key: observation.derived_entry_key().clone(),
            derived_fingerprint: observation.derived_fingerprint().clone(),
            transformation_id: ZIP_TRANSFORMATION.to_owned(),
            transformation_revision: 1,
        },
        scan_id(),
    )
}

fn graph_fixture() -> (
    tempfile::TempDir,
    LocalFilesystemSourceAccess,
    Vec<SourceEntryRecord>,
) {
    let directory = tempdir().expect("source directory");
    let game = b"synthetic-game-bytes";
    let inner = zip_bytes("game.gba", game);
    let outer = zip_bytes("inner.7z", &inner);
    let source_path = directory.path().join("source.zip");
    std::fs::write(&source_path, &outer).expect("source archive");

    let root_id = SourceEntryId::try_from("11111111111111111111111111111111").expect("root id");
    let outer_id = SourceEntryId::try_from("33333333333333333333333333333333").expect("outer id");
    let game_id = SourceEntryId::try_from("55555555555555555555555555555555").expect("game id");
    let access = common::access(directory.path());
    let resolved_root = access.resolve_root().expect("root");
    let source_reader = access
        .open_entry_reader(
            &resolved_root,
            &argus_application::RelativeSourceLocator::from_provider("source.zip".to_owned()),
        )
        .expect("source reader");
    let source_fingerprint = source_reader.source_fingerprint().to_owned();
    let root = SourceEntryRecord::new(
        root_id,
        None,
        argus_application::RelativeSourceLocator::from_provider("source.zip".to_owned()),
        SourceLocatorKey::from_provider("source.zip".to_owned()),
        "source.zip",
        "source.zip",
        SourceEntryKind::File,
        SourceEntryClassification::Container,
        None,
        Some(source_fingerprint),
        scan_id(),
    );
    let root_version = SourceVersionEvidence::provider(
        root_id,
        root.source_fingerprint().map(str::to_owned),
        scan_id(),
    );
    let outer_scope = enumerate_bytes(&outer, &root_version);
    let outer_observation = &outer_scope.observations()[0];
    let mut outer_file = outer_scope
        .member_index()
        .open(outer_observation.derived_entry_key())
        .expect("outer member file");
    let mut outer_bytes = Vec::new();
    std::io::Read::read_to_end(&mut outer_file, &mut outer_bytes).expect("outer member bytes");
    let outer_record = derived_record(outer_id, root_id, "inner.7z", outer_observation);
    let inner_version = SourceVersionEvidence::derived(
        outer_id,
        outer_observation.derived_fingerprint().clone(),
        scan_id(),
    );
    let inner_scope = enumerate_bytes(&outer_bytes, &inner_version);
    let inner_observation = &inner_scope.observations()[0];
    let game_record = derived_record(game_id, outer_id, "game.gba", inner_observation);
    let records = vec![root, outer_record, game_record];
    (directory, access, records)
}

#[test]
fn nested_derived_content_reopens_through_the_persisted_transformation_chain() {
    let (_directory, access, records) = graph_fixture();
    let root = access.resolve_root().expect("root");
    let target = records.last().expect("target");
    let staging = tempdir().expect("staging");
    let mut session = ParsingSession::for_tests(budget(), staging.path(), || false);
    let resolver = ContentSourceResolver::new(&access, &root, &records);
    let mut reader = resolver.open(target, &mut session).expect("reopen chain");
    let mut bytes = vec![0; reader.len().expect("length") as usize];
    reader.read_at(0, &mut bytes).expect("read target");
    assert_eq!(bytes, b"synthetic-game-bytes");
}

#[test]
fn provider_mutation_invalidates_derived_proof_before_reuse() {
    let (directory, access, records) = graph_fixture();
    thread::sleep(Duration::from_millis(2));
    let source_path = directory.path().join("source.zip");
    let changed = zip_bytes("inner.7z", b"changed-source-bytes");
    std::fs::write(source_path, changed).expect("mutate source");
    let root = access.resolve_root().expect("root");
    let staging = tempdir().expect("staging");
    let mut session = ParsingSession::for_tests(budget(), staging.path(), || false);
    let resolver = ContentSourceResolver::new(&access, &root, &records);
    assert!(matches!(
        resolver.open(records.last().expect("target"), &mut session),
        Err(TransformationFailure::SourceChanged)
    ));
}

struct BytesReader {
    bytes: Vec<u8>,
}

impl BytesReader {
    fn new(bytes: Vec<u8>) -> Self {
        Self { bytes }
    }
}

impl ContentReader for BytesReader {
    fn len(&self) -> Result<u64, ContentReadError> {
        Ok(self.bytes.len() as u64)
    }

    fn read_at(&mut self, offset: u64, destination: &mut [u8]) -> Result<usize, ContentReadError> {
        let start = usize::try_from(offset).map_err(|_| ContentReadError::OutOfRange)?;
        let end = start
            .checked_add(destination.len())
            .ok_or(ContentReadError::OutOfRange)?;
        let source = self
            .bytes
            .get(start..end)
            .ok_or(ContentReadError::OutOfRange)?;
        destination.copy_from_slice(source);
        Ok(source.len())
    }
}
