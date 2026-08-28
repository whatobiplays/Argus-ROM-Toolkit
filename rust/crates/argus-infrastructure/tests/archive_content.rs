use std::io::{self, Cursor, Read, Write};

use argus_application::{
    DerivedScopeOutcome, ScanRunId, SourceEntryId, SourceEntryKind, SourceVersionEvidence,
    TransformationBudget, TransformationFailure,
};
use argus_infrastructure::content::{
    enumerate_derived_container, ContentReadError, ContentReader, DerivedScopeResult,
    ParsingSession,
};
use flate2::{write::GzEncoder, Compression};
use tempfile::tempdir;
use zip::{write::SimpleFileOptions, CompressionMethod, ZipWriter};

const SEVEN_Z_LZMA2_FIXTURE: &[u8] = &[
    0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c, 0x00, 0x04, 0xbb, 0xac, 0x85, 0xb8, 0x0d, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x5a, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x6a, 0xdb, 0x9b, 0x0f,
    0x01, 0x00, 0x08, 0x67, 0x61, 0x6d, 0x65, 0x2d, 0x64, 0x61, 0x74, 0x61, 0x00, 0x01, 0x04, 0x06,
    0x00, 0x01, 0x09, 0x0d, 0x00, 0x07, 0x0b, 0x01, 0x00, 0x01, 0x21, 0x21, 0x01, 0x00, 0x0c, 0x09,
    0x00, 0x08, 0x0a, 0x01, 0xe0, 0x2c, 0xf4, 0xc5, 0x00, 0x00, 0x05, 0x01, 0x19, 0x0c, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x11, 0x13, 0x00, 0x67, 0x00, 0x61,
    0x00, 0x6d, 0x00, 0x65, 0x00, 0x2e, 0x00, 0x67, 0x00, 0x62, 0x00, 0x61, 0x00, 0x00, 0x00, 0x19,
    0x00, 0x14, 0x0a, 0x01, 0x00, 0x33, 0x65, 0xa5, 0x79, 0x99, 0x35, 0xdd, 0x01, 0x15, 0x06, 0x01,
    0x00, 0x20, 0x80, 0xa4, 0x81, 0x00, 0x00,
];

const SEVEN_Z_LZMA_FIXTURE: &[u8] = &[
    0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c, 0x00, 0x04, 0x79, 0xd0, 0xd8, 0xc6, 0x0e, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x5a, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xc2, 0x98, 0xf3, 0xdf,
    0x00, 0x33, 0x98, 0x49, 0xfd, 0xfa, 0x6d, 0xa0, 0x59, 0x02, 0xce, 0xc7, 0xa6, 0x58, 0x01, 0x04,
    0x06, 0x00, 0x01, 0x09, 0x0e, 0x00, 0x07, 0x0b, 0x01, 0x00, 0x01, 0x23, 0x03, 0x01, 0x01, 0x05,
    0x5d, 0x00, 0x10, 0x00, 0x00, 0x0c, 0x09, 0x00, 0x08, 0x0a, 0x01, 0xe0, 0x2c, 0xf4, 0xc5, 0x00,
    0x00, 0x05, 0x01, 0x19, 0x06, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x11, 0x13, 0x00, 0x67, 0x00,
    0x61, 0x00, 0x6d, 0x00, 0x65, 0x00, 0x2e, 0x00, 0x67, 0x00, 0x62, 0x00, 0x61, 0x00, 0x00, 0x00,
    0x19, 0x00, 0x14, 0x0a, 0x01, 0x00, 0xed, 0x63, 0x62, 0x6d, 0x9c, 0x35, 0xdd, 0x01, 0x15, 0x06,
    0x01, 0x00, 0x20, 0x80, 0xa4, 0x81, 0x00, 0x00,
];

const ENCRYPTED_SEVEN_Z_FIXTURE: &[u8] = &[
    0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c, 0x00, 0x04, 0x3b, 0x6b, 0x00, 0xf4, 0x80, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x2e, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xdc, 0xbd, 0x81, 0xc9,
    0x26, 0x70, 0x42, 0x0c, 0x06, 0x28, 0xb2, 0x83, 0xa7, 0xc6, 0x4b, 0x25, 0x59, 0x54, 0x36, 0x92,
    0x6d, 0xc3, 0xea, 0x1f, 0xa2, 0x90, 0x08, 0x67, 0x26, 0xb9, 0x1e, 0x3b, 0xfb, 0x85, 0xd3, 0xd3,
    0x3d, 0x77, 0xf5, 0xd5, 0x1d, 0xb3, 0x12, 0xa2, 0xb3, 0xb0, 0x16, 0x16, 0x3f, 0x37, 0x39, 0x0e,
    0x40, 0x03, 0x89, 0x70, 0x4d, 0x5c, 0x1e, 0x88, 0x0d, 0xca, 0x99, 0x21, 0xc4, 0x1b, 0xb3, 0x5d,
    0x57, 0x5e, 0x33, 0xd0, 0x58, 0x6d, 0x96, 0x8b, 0x9d, 0x70, 0x10, 0x49, 0x1b, 0x53, 0x28, 0xc6,
    0x0d, 0xef, 0xf0, 0x34, 0x83, 0x6a, 0xad, 0xf6, 0xa0, 0x9e, 0x7d, 0xa7, 0x6f, 0xe2, 0x50, 0x10,
    0xe4, 0x4b, 0x21, 0x61, 0x26, 0x76, 0x5e, 0xe4, 0x5e, 0x78, 0xef, 0xa5, 0x14, 0xa1, 0xad, 0x32,
    0xb5, 0x8c, 0x0e, 0xb5, 0x67, 0x1f, 0x87, 0x7c, 0x04, 0xb2, 0x15, 0xa3, 0x93, 0xc6, 0xe9, 0x4d,
    0x17, 0x06, 0x10, 0x01, 0x09, 0x70, 0x00, 0x07, 0x0b, 0x01, 0x00, 0x01, 0x24, 0x06, 0xf1, 0x07,
    0x01, 0x12, 0x53, 0x0f, 0x52, 0x0b, 0xf8, 0xda, 0x78, 0xe5, 0x76, 0xc3, 0xdd, 0xea, 0xba, 0xb1,
    0x94, 0x66, 0x42, 0x90, 0x0c, 0x6a, 0x0a, 0x01, 0x1a, 0x03, 0x5d, 0x7b, 0x00, 0x00,
];

const BZIP2_FIXTURE: &[u8] = &[
    0x42, 0x5a, 0x68, 0x39, 0x31, 0x41, 0x59, 0x26, 0x53, 0x59, 0x63, 0x7f, 0xd7, 0x3c, 0x00, 0x00,
    0x03, 0x11, 0x80, 0x00, 0x02, 0x26, 0x82, 0x04, 0x00, 0x20, 0x00, 0x31, 0x0c, 0x01, 0x06, 0x99,
    0xa7, 0x92, 0x30, 0xda, 0x2e, 0xe4, 0x8a, 0x70, 0xa1, 0x20, 0xc6, 0xff, 0xae, 0x78,
];

const XZ_FIXTURE: &[u8] = &[
    0xfd, 0x37, 0x7a, 0x58, 0x5a, 0x00, 0x00, 0x04, 0xe6, 0xd6, 0xb4, 0x46, 0x04, 0xc0, 0x0d, 0x09,
    0x21, 0x01, 0x16, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x5f, 0x4f, 0x33, 0xe4,
    0x01, 0x00, 0x08, 0x67, 0x61, 0x6d, 0x65, 0x2d, 0x64, 0x61, 0x74, 0x61, 0x00, 0x00, 0x00, 0x00,
    0xf5, 0xb4, 0x76, 0x52, 0x20, 0x3b, 0xae, 0x6b, 0x00, 0x01, 0x29, 0x09, 0x64, 0x92, 0x1c, 0x1d,
    0x1f, 0xb6, 0xf3, 0x7d, 0x01, 0x00, 0x00, 0x00, 0x00, 0x04, 0x59, 0x5a,
];

fn budget(
    max_single: u64,
    max_expanded: u64,
    max_entries: u64,
    max_depth: u32,
    max_staged: u64,
    max_work: u64,
) -> TransformationBudget {
    TransformationBudget::new(
        max_single,
        max_expanded,
        max_entries,
        max_depth,
        max_staged,
        max_work,
    )
}

fn parent_version() -> SourceVersionEvidence {
    SourceVersionEvidence::provider(
        SourceEntryId::try_from("11111111111111111111111111111111").expect("source id"),
        Some("provider-version-1".to_owned()),
        ScanRunId::try_from("22222222222222222222222222222222").expect("scan id"),
    )
}

fn enumerate(
    bytes: Vec<u8>,
    limits: TransformationBudget,
) -> Result<Option<DerivedScopeResult>, TransformationFailure> {
    enumerate_with_parent(bytes, limits, parent_version())
}

fn enumerate_with_parent(
    bytes: Vec<u8>,
    limits: TransformationBudget,
    parent: SourceVersionEvidence,
) -> Result<Option<DerivedScopeResult>, TransformationFailure> {
    let staging = tempdir().expect("staging root");
    let mut session = ParsingSession::for_tests(limits, staging.path(), || false);
    let mut reader = BytesReader { bytes };
    enumerate_derived_container(&mut reader, &parent, &mut session)
}

fn assert_complete(
    result: Result<Option<DerivedScopeResult>, TransformationFailure>,
    names: &[&str],
) {
    let result = result
        .expect("wrapper should decode")
        .expect("wrapper should be applicable");
    assert_eq!(result.outcome(), DerivedScopeOutcome::Complete);
    assert_eq!(result.observations().len(), names.len());
    for (observation, expected) in result.observations().iter().zip(names) {
        assert_eq!(observation.display_name(), *expected);
        assert_eq!(observation.kind(), SourceEntryKind::File);
        assert!(!observation
            .derived_fingerprint()
            .as_transformation_value()
            .is_empty());
    }
    assert_eq!(result.member_index().len(), names.len());
}

#[test]
fn zip_stored_and_deflate_members_are_enumerated_as_one_complete_scope() {
    let bytes = zip_fixture(&[
        ("game.gba", b"stored-game", CompressionMethod::Stored),
        ("README.txt", b"sidecar", CompressionMethod::Deflated),
    ]);
    assert_complete(
        enumerate(bytes, budget(1024, 1024, 16, 4, 1024, 4096)),
        &["game.gba", "README.txt"],
    );
}

#[test]
fn decoded_members_are_reopened_from_operation_staging() {
    let staging = tempdir().expect("staging root");
    let mut session = ParsingSession::for_tests(
        budget(4096, 4096, 16, 4, 4096, 16 * 1024),
        staging.path(),
        || false,
    );
    let mut reader = BytesReader {
        bytes: zip_fixture(&[("game.gba", b"staged-game", CompressionMethod::Stored)]),
    };
    let result = enumerate_derived_container(&mut reader, &parent_version(), &mut session)
        .expect("zip should decode")
        .expect("zip should be applicable");
    let key = result.observations()[0].derived_entry_key();
    let mut staged = result
        .member_index()
        .open(key)
        .expect("decoded member should have a staged file");
    let mut bytes = Vec::new();
    staged
        .read_to_end(&mut bytes)
        .expect("staged member should read");
    assert_eq!(bytes, b"staged-game");
    assert!(result
        .member_index()
        .staged_path(key)
        .expect("staged path")
        .starts_with(session.operation_directory()));
}

#[test]
fn member_coordinates_follow_normalized_names_instead_of_archive_order() {
    let first = enumerate(
        zip_fixture(&[
            ("games/one.gba", b"one", CompressionMethod::Stored),
            ("games/two.gba", b"two", CompressionMethod::Stored),
        ]),
        budget(4096, 4096, 16, 4, 4096, 16 * 1024),
    )
    .expect("first archive")
    .expect("first wrapper");
    let second = enumerate(
        zip_fixture(&[
            ("games/two.gba", b"two", CompressionMethod::Stored),
            ("games/one.gba", b"one", CompressionMethod::Stored),
        ]),
        budget(4096, 4096, 16, 4, 4096, 16 * 1024),
    )
    .expect("second archive")
    .expect("second wrapper");

    for name in ["one.gba", "two.gba"] {
        let first_observation = first
            .observations()
            .iter()
            .find(|observation| observation.display_name() == name)
            .expect("first member");
        let second_observation = second
            .observations()
            .iter()
            .find(|observation| observation.display_name() == name)
            .expect("second member");
        assert_eq!(
            first_observation.derived_entry_key(),
            second_observation.derived_entry_key()
        );
        assert_eq!(
            first_observation.derived_locator(),
            second_observation.derived_locator()
        );
        assert_eq!(
            first_observation.derived_fingerprint(),
            second_observation.derived_fingerprint()
        );
    }
}

#[test]
fn duplicate_normalized_member_names_are_rejected() {
    let bytes = zip_fixture(&[
        ("games/game.gba", b"first", CompressionMethod::Stored),
        ("games\\game.gba", b"second", CompressionMethod::Stored),
    ]);
    assert!(matches!(
        enumerate(bytes, budget(4096, 4096, 16, 4, 4096, 16 * 1024)),
        Err(TransformationFailure::Malformed)
    ));
}

#[test]
fn seven_zip_lzma2_members_are_enumerated() {
    assert_complete(
        enumerate(
            SEVEN_Z_LZMA2_FIXTURE.to_vec(),
            budget(1024, 1024, 16, 4, 1024, 4096),
        ),
        &["game.gba"],
    );
}

#[test]
fn seven_zip_lzma_members_are_enumerated() {
    assert_complete(
        enumerate(
            SEVEN_Z_LZMA_FIXTURE.to_vec(),
            budget(1024, 1024, 16, 4, 1024, 4096),
        ),
        &["game.gba"],
    );
}

#[test]
fn tar_regular_file_and_directory_members_are_enumerated() {
    let bytes = tar_fixture(&[("folder/", b"", true), ("folder/game.gba", b"game", false)]);
    let result = enumerate(bytes, budget(4096, 1024, 16, 4, 4096, 4096))
        .expect("tar should decode")
        .expect("tar should be applicable");
    assert_eq!(result.outcome(), DerivedScopeOutcome::Complete);
    assert_eq!(result.observations().len(), 2);
    assert_eq!(result.observations()[0].display_name(), "folder");
    assert_eq!(result.observations()[0].kind(), SourceEntryKind::Directory);
    assert_eq!(result.observations()[1].display_name(), "game.gba");
    assert_eq!(result.observations()[1].kind(), SourceEntryKind::File);
}

#[test]
fn single_stream_wrappers_expose_one_stable_stream_child() {
    let mut gzip = GzEncoder::new(Vec::new(), Compression::default());
    gzip.write_all(b"game-data").expect("gzip input");
    let gzip = gzip.finish().expect("gzip fixture");

    for (label, bytes) in [
        ("gzip", gzip),
        ("bzip2", BZIP2_FIXTURE.to_vec()),
        ("xz", XZ_FIXTURE.to_vec()),
    ] {
        let result = enumerate(bytes, budget(1024, 1024, 16, 4, 2048, 4096))
            .unwrap_or_else(|error| panic!("{label} should decode: {error:?}"))
            .unwrap_or_else(|| panic!("{label} should be applicable"));
        assert_eq!(result.outcome(), DerivedScopeOutcome::Complete);
        assert_eq!(result.observations().len(), 1);
        assert_eq!(
            result.observations()[0]
                .derived_entry_key()
                .as_transformation_value(),
            "stream:0"
        );
        assert_eq!(result.member_index().len(), 1);
    }
}

#[test]
fn single_stream_wrappers_reject_trailing_bytes() {
    let mut gzip = GzEncoder::new(Vec::new(), Compression::default());
    gzip.write_all(b"game-data").expect("gzip input");
    let mut gzip = gzip.finish().expect("gzip fixture");
    gzip.extend_from_slice(b"trailing");

    for (label, mut bytes) in [
        ("gzip", gzip),
        ("bzip2", BZIP2_FIXTURE.to_vec()),
        ("xz", XZ_FIXTURE.to_vec()),
    ] {
        if label != "gzip" {
            bytes.extend_from_slice(b"trailing");
        }
        assert!(
            matches!(
                enumerate(bytes, budget(4096, 4096, 16, 4, 4096, 16 * 1024)),
                Err(TransformationFailure::Malformed)
            ),
            "{label} should reject trailing data"
        );
    }
}

#[test]
fn unchanged_parent_bytes_keep_the_same_derived_fingerprint_across_scans() {
    let bytes = zip_fixture(&[("game.gba", b"game", CompressionMethod::Stored)]);
    let first = enumerate_with_parent(
        bytes.clone(),
        budget(1024, 1024, 16, 4, 1024, 4096),
        SourceVersionEvidence::provider(
            SourceEntryId::try_from("11111111111111111111111111111111").expect("source id"),
            Some("provider-version-1".to_owned()),
            ScanRunId::try_from("22222222222222222222222222222222").expect("scan id"),
        ),
    )
    .expect("first scan")
    .expect("zip scope");
    let second = enumerate_with_parent(
        bytes,
        budget(1024, 1024, 16, 4, 1024, 4096),
        SourceVersionEvidence::provider(
            SourceEntryId::try_from("11111111111111111111111111111111").expect("source id"),
            Some("provider-version-1".to_owned()),
            ScanRunId::try_from("33333333333333333333333333333333").expect("scan id"),
        ),
    )
    .expect("second scan")
    .expect("zip scope");
    assert_eq!(
        first.observations()[0].derived_fingerprint(),
        second.observations()[0].derived_fingerprint()
    );
}

#[test]
fn unsafe_member_names_are_rejected_without_partial_scope_success() {
    for name in [
        "../game.gba",
        "/absolute/game.gba",
        "C:\\games\\game.gba",
        "bad\0name",
    ] {
        let bytes = zip_fixture(&[(name, b"game", CompressionMethod::Stored)]);
        assert!(matches!(
            enumerate(bytes, budget(1024, 1024, 16, 4, 1024, 4096)),
            Err(TransformationFailure::Malformed)
        ));
    }
}

#[test]
fn encrypted_rar_and_split_inputs_map_to_explicit_failures() {
    let encrypted_zip = encrypted_zip_fixture();
    assert!(matches!(
        enumerate(encrypted_zip, budget(1024, 1024, 16, 4, 1024, 4096)),
        Err(TransformationFailure::EncryptedUnsupported)
    ));
    let encrypted_seven_z = enumerate(
        ENCRYPTED_SEVEN_Z_FIXTURE.to_vec(),
        budget(1024, 1024, 16, 4, 1024, 4096),
    );
    assert!(matches!(
        encrypted_seven_z,
        Err(TransformationFailure::EncryptedUnsupported)
    ));
    assert!(matches!(
        enumerate(
            b"Rar!\x1a\x07\x00".to_vec(),
            budget(1024, 1024, 16, 4, 1024, 4096)
        ),
        Err(TransformationFailure::UnsupportedFeature)
    ));
    assert!(matches!(
        enumerate(
            b"PK\x07\x08".to_vec(),
            budget(1024, 1024, 16, 4, 1024, 4096)
        ),
        Err(TransformationFailure::UnsupportedFeature)
    ));
}

#[test]
fn expansion_budget_failure_cannot_be_reported_as_complete() {
    let mut gzip = GzEncoder::new(Vec::new(), Compression::default());
    gzip.write_all(&[7; 4096]).expect("gzip input");
    let gzip = gzip.finish().expect("gzip fixture");
    assert!(matches!(
        enumerate(gzip, budget(1024, 32, 16, 4, 1024, 4096)),
        Err(TransformationFailure::ResourceLimitExceeded)
    ));
}

#[test]
fn unsupported_bytes_are_not_claimed_by_the_derived_container_path() {
    assert!(enumerate(
        b"not a supported wrapper".to_vec(),
        budget(1024, 1024, 16, 4, 1024, 4096)
    )
    .expect("probe")
    .is_none());
}

struct BytesReader {
    bytes: Vec<u8>,
}

impl ContentReader for BytesReader {
    fn len(&self) -> Result<u64, ContentReadError> {
        Ok(self.bytes.len() as u64)
    }

    fn read_at(&mut self, offset: u64, destination: &mut [u8]) -> Result<usize, ContentReadError> {
        let offset = usize::try_from(offset).map_err(|_| ContentReadError::OutOfRange)?;
        let end = offset
            .checked_add(destination.len())
            .ok_or(ContentReadError::OutOfRange)?;
        if end > self.bytes.len() {
            return Err(ContentReadError::OutOfRange);
        }
        destination.copy_from_slice(&self.bytes[offset..end]);
        Ok(destination.len())
    }
}

fn zip_fixture(entries: &[(&str, &[u8], CompressionMethod)]) -> Vec<u8> {
    let mut writer = ZipWriter::new(Cursor::new(Vec::new()));
    for (name, contents, method) in entries {
        let options = SimpleFileOptions::default().compression_method(*method);
        writer.start_file(*name, options).expect("zip member");
        writer.write_all(contents).expect("zip contents");
    }
    writer.finish().expect("zip finish").into_inner()
}

fn encrypted_zip_fixture() -> Vec<u8> {
    let mut bytes = zip_fixture(&[("game.gba", b"game", CompressionMethod::Stored)]);
    let local_flags = u16::from_le_bytes([bytes[6], bytes[7]]) | 1;
    bytes[6..8].copy_from_slice(&local_flags.to_le_bytes());
    let central = bytes
        .windows(4)
        .position(|window| window == b"PK\x01\x02")
        .expect("central directory");
    let central_flags = u16::from_le_bytes([bytes[central + 8], bytes[central + 9]]) | 1;
    bytes[central + 8..central + 10].copy_from_slice(&central_flags.to_le_bytes());
    bytes
}

fn tar_fixture(entries: &[(&str, &[u8], bool)]) -> Vec<u8> {
    let mut archive = Vec::new();
    for (name, contents, directory) in entries {
        let mut header = [0_u8; 512];
        header[..name.len()].copy_from_slice(name.as_bytes());
        header[100..108].copy_from_slice(b"0000644\0");
        header[108..116].copy_from_slice(b"0000000\0");
        header[116..124].copy_from_slice(b"0000000\0");
        let size = if *directory { 0 } else { contents.len() };
        let size_text = format!("{size:011o}\0");
        header[124..136].copy_from_slice(size_text.as_bytes());
        header[136..148].copy_from_slice(b"00000000000\0");
        header[148..156].fill(b' ');
        header[156] = if *directory { b'5' } else { b'0' };
        header[257..263].copy_from_slice(b"ustar\0");
        header[263..265].copy_from_slice(b"00");
        let checksum: u32 = header.iter().map(|byte| u32::from(*byte)).sum();
        let checksum_text = format!("{checksum:06o}\0 ");
        header[148..156].copy_from_slice(checksum_text.as_bytes());
        archive.extend_from_slice(&header);
        archive.extend_from_slice(contents);
        let padding = (512 - (contents.len() % 512)) % 512;
        archive.resize(archive.len() + padding, 0);
    }
    archive.resize(archive.len() + 1024, 0);
    archive
}

#[allow(dead_code)]
fn read_all(mut file: std::fs::File) -> io::Result<Vec<u8>> {
    let mut bytes = Vec::new();
    file.read_to_end(&mut bytes)?;
    Ok(bytes)
}
