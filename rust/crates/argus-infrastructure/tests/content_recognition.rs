use argus_application::{IdentityDigest, PlatformId};
use argus_infrastructure::content::{
    RecognitionError, recognize_raw_cartridge, recognize_raw_cartridge_with_budget,
};
use sha2::{Digest, Sha256};

const GB_LOGO: [u8; 48] = [
    0xCE, 0xED, 0x66, 0x66, 0xCC, 0x0D, 0x00, 0x0B, 0x03, 0x73, 0x00, 0x83, 0x00, 0x0C, 0x00, 0x0D,
    0x00, 0x08, 0x11, 0x1F, 0x88, 0x89, 0x00, 0x0E, 0xDC, 0xCC, 0x6E, 0xE6, 0xDD, 0xDD, 0xD9, 0x99,
    0xBB, 0xBB, 0x67, 0x63, 0x6E, 0x0E, 0xEC, 0xCC, 0xDD, 0xDC, 0x99, 0x9F, 0xBB, 0xB9, 0x33, 0x3E,
];

// Independent GBATEK fixture data; do not derive this from production code.
const AUTHORITATIVE_GBA_LOGO: [u8; 156] = [
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

const PREVIOUS_REPEATED_LOGO_PATTERN: [u8; 12] = [
    0x9F, 0x84, 0x4D, 0x73, 0xA3, 0xCA, 0x9A, 0x61, 0x58, 0x97, 0xA7, 0xFC,
];

fn gb_fixture(cgb_flag: u8, length: usize) -> Vec<u8> {
    let mut bytes = vec![0_u8; length];
    bytes[0x143] = cgb_flag;
    bytes[0x147] = 0x00;
    bytes[0x148] = 0x00;
    bytes[0x149] = 0x00;
    bytes[0x14a] = 0x01;
    bytes[0x14b] = 0x33;
    bytes[0x104..0x134].copy_from_slice(&GB_LOGO);
    let mut checksum = 0_u8;
    for byte in &bytes[0x134..0x14d] {
        checksum = checksum.wrapping_sub(*byte).wrapping_sub(1);
    }
    bytes[0x14d] = checksum;
    bytes
}

fn gba_fixture(length: usize) -> Vec<u8> {
    let mut bytes = vec![0_u8; length];
    bytes[0x00..0x04].copy_from_slice(&[0x2E, 0x00, 0x00, 0xEA]);
    bytes[0x04..0xa0].copy_from_slice(&AUTHORITATIVE_GBA_LOGO);
    bytes[0xa0..0xac].copy_from_slice(b"TEST TITLE  ");
    bytes[0xac..0xb2].copy_from_slice(b"TEST01");
    bytes[0xb2] = 0x96;
    let sum = bytes[0xa0..0xbd]
        .iter()
        .fold(0_u8, |sum, byte| sum.wrapping_add(*byte))
        .wrapping_add(0x19);
    bytes[0xbd] = 0_u8.wrapping_sub(sum);
    bytes
}

#[test]
fn valid_gb_and_gbc_headers_classify_by_exact_cgb_flag() {
    let gb = recognize_raw_cartridge(&gb_fixture(0x00, 0x8000)).expect("GB fixture");
    assert_eq!(gb.platform(), PlatformId::NintendoGb);
    assert_eq!(gb.canonical_bytes().len(), 0x8000);

    let gbc = recognize_raw_cartridge(&gb_fixture(0x80, 0x8000)).expect("GBC fixture");
    assert_eq!(gbc.platform(), PlatformId::NintendoGbc);

    let gbc_dual = recognize_raw_cartridge(&gb_fixture(0xc0, 0x8000)).expect("dual fixture");
    assert_eq!(gbc_dual.platform(), PlatformId::NintendoGbc);
}

#[test]
fn non_exact_gb_length_is_unsupported_without_trimming() {
    let error = recognize_raw_cartridge(&gb_fixture(0x00, 0x8001)).expect_err("padding");
    assert_eq!(error, RecognitionError::UnsupportedRepresentation);
}

#[test]
fn unsupported_cgb_flags_are_not_guessed() {
    let error = recognize_raw_cartridge(&gb_fixture(0x40, 0x8000)).expect_err("invalid flag");
    assert_eq!(error, RecognitionError::InvalidCgbFlag);
}

#[test]
fn gb_header_validation_rejects_logo_type_size_and_checksum_errors() {
    let mut bad_logo = gb_fixture(0x00, 0x8000);
    bad_logo[0x104] ^= 0xff;
    assert_eq!(
        recognize_raw_cartridge(&bad_logo).expect_err("logo"),
        RecognitionError::InvalidNintendoLogo
    );

    let mut bad_type = gb_fixture(0x00, 0x8000);
    bad_type[0x147] = 0x04;
    assert_eq!(
        recognize_raw_cartridge(&bad_type).expect_err("type"),
        RecognitionError::InvalidCartridgeType
    );

    let mut bad_size = gb_fixture(0x00, 0x8000);
    bad_size[0x148] = 0x09;
    assert_eq!(
        recognize_raw_cartridge(&bad_size).expect_err("size"),
        RecognitionError::InvalidRomSize
    );

    let mut bad_checksum = gb_fixture(0x00, 0x8000);
    bad_checksum[0x14d] ^= 0x01;
    assert_eq!(
        recognize_raw_cartridge(&bad_checksum).expect_err("checksum"),
        RecognitionError::InvalidHeaderChecksum
    );
}

#[test]
fn identity_digest_is_sha256_of_the_canonical_bytes() {
    let recognized = recognize_raw_cartridge(&gb_fixture(0x00, 0x8000)).expect("GB fixture");
    let mut hasher = Sha256::new();
    hasher.update(recognized.canonical_bytes());
    let expected: [u8; 32] = hasher.finalize().into();
    assert_eq!(
        recognized.identity_digest(),
        IdentityDigest::from_bytes(expected)
    );
}

#[test]
fn valid_gba_uses_the_complete_source_as_canonical_representation() {
    let short = recognize_raw_cartridge(&gba_fixture(0x100)).expect("GBA fixture");
    assert_eq!(short.platform(), PlatformId::NintendoGba);
    assert_eq!(short.canonical_bytes().len(), 0x100);

    let longer = recognize_raw_cartridge(&gba_fixture(0x104)).expect("complete GBA fixture");
    assert_eq!(longer.canonical_bytes().len(), 0x104);
    assert_ne!(short.identity_digest(), longer.identity_digest());
}

#[test]
fn gba_header_validation_rejects_fixed_field_and_complement_errors() {
    let mut bad_fixed = gba_fixture(0x100);
    bad_fixed[0xb2] = 0;
    assert_eq!(
        recognize_raw_cartridge(&bad_fixed).expect_err("fixed field"),
        RecognitionError::InvalidGbaHeader
    );

    let mut bad_complement = gba_fixture(0x100);
    bad_complement[0xbd] ^= 0xff;
    assert_eq!(
        recognize_raw_cartridge(&bad_complement).expect_err("complement"),
        RecognitionError::InvalidGbaHeader
    );
}

#[test]
fn previous_repeated_pattern_pseudo_logo_is_rejected() {
    let mut pseudo_logo = gba_fixture(0x100);
    for (index, byte) in pseudo_logo[0x44..0xa0].iter_mut().enumerate() {
        *byte = PREVIOUS_REPEATED_LOGO_PATTERN[index % PREVIOUS_REPEATED_LOGO_PATTERN.len()];
    }
    assert_eq!(
        recognize_raw_cartridge(&pseudo_logo).expect_err("pseudo-logo"),
        RecognitionError::InvalidNintendoLogo
    );
}

#[test]
fn gba_entry_point_must_be_an_in_image_arm_branch() {
    let mut zero_entry = gba_fixture(0x100);
    zero_entry[0x00..0x04].fill(0);
    assert_eq!(
        recognize_raw_cartridge(&zero_entry).expect_err("zero entry point"),
        RecognitionError::InvalidGbaHeader
    );

    let mut thumb_entry = gba_fixture(0x100);
    thumb_entry[0x00..0x04].copy_from_slice(&[0x00, 0x00, 0x00, 0xE3]);
    assert_eq!(
        recognize_raw_cartridge(&thumb_entry).expect_err("non-branch entry point"),
        RecognitionError::InvalidGbaHeader
    );

    let mut outside_entry = gba_fixture(0x100);
    outside_entry[0x00..0x04].copy_from_slice(&[0xFF, 0xFF, 0x7F, 0xEA]);
    assert_eq!(
        recognize_raw_cartridge(&outside_entry).expect_err("outside entry point"),
        RecognitionError::InvalidGbaHeader
    );
}

#[test]
fn recognition_rejects_truncated_source() {
    assert_eq!(
        recognize_raw_cartridge(&[0_u8; 0xbf]).expect_err("truncated"),
        RecognitionError::Truncated
    );
}

#[test]
fn recognition_budget_fails_before_processing() {
    let bytes = gb_fixture(0x00, 0x8000);
    assert_eq!(
        recognize_raw_cartridge_with_budget(&bytes, bytes.len() - 1).expect_err("budget"),
        RecognitionError::ResourceLimitExceeded
    );
}
