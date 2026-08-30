use argus_application::{ContentType, TransformationBudget};
use argus_application::{
    IdentityDigest, LibrarySourceAccess, PlatformId, RelativeSourceLocator, RootLocator,
    SourceAccessError, SourceReadHandle,
};
use argus_infrastructure::content::{
    ContentProcessingLimits, ContentReadError, ContentReader, ContentRecognitionError,
    ParsingSession, RecognitionError, SourceReadContentReader, recognize_alternate_optical,
    recognize_content, recognize_content_with_budget, recognize_content_with_limits,
    recognize_raw_cartridge, recognize_raw_cartridge_with_budget,
};
use sha2::{Digest, Sha256};
use tempfile::tempdir;

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

fn nes_fixture(nes2: bool) -> Vec<u8> {
    let mut bytes = vec![0_u8; 16 + 0x4000 + 0x2000];
    bytes[0..4].copy_from_slice(b"NES\x1a");
    bytes[4] = 1;
    bytes[5] = 1;
    bytes[6] = 0x03;
    bytes[7] = if nes2 { 0x08 } else { 0 };
    if nes2 {
        bytes[8] = 0;
        bytes[9] = 0;
    }
    for (index, byte) in bytes[16..].iter_mut().enumerate() {
        *byte = (index as u8).wrapping_mul(17).wrapping_add(3);
    }
    bytes
}

fn nes_mapper_fixture(nes2: bool, mapper: u16, submapper: u8) -> Vec<u8> {
    let mut bytes = nes_fixture(nes2);
    bytes[6] = (bytes[6] & 0x0f) | ((mapper as u8 & 0x0f) << 4);
    bytes[7] = if nes2 {
        0x08 | (mapper as u8 & 0xf0)
    } else {
        mapper as u8 & 0xf0
    };
    if nes2 {
        bytes[8] = (submapper << 4) | ((mapper >> 8) as u8 & 0x0f);
    }
    bytes
}

fn fds_side_fixture() -> Vec<u8> {
    let mut side = vec![0_u8; 65_500];
    side[0] = 1;
    side[1..15].copy_from_slice(b"*NINTENDO-HVC*");
    side[0x0f] = 0;
    side[0x10..0x13].copy_from_slice(b"TST");
    side[0x13] = b' ';
    side[0x17] = 1;
    let mut cursor = 56;
    side[cursor] = 2;
    side[cursor + 1] = 1;
    cursor += 2;
    append_fds_file(&mut side, cursor, 0, 1, b"PAYLOAD!");
    side
}

fn append_fds_file(
    side: &mut [u8],
    cursor: usize,
    file_number: u8,
    file_id: u8,
    payload: &[u8],
) -> usize {
    let end = cursor + 17 + payload.len();
    assert!(end <= side.len());
    side[cursor] = 3;
    side[cursor + 1] = file_number;
    side[cursor + 2] = file_id;
    side[cursor + 3..cursor + 11].copy_from_slice(b"TESTFILE");
    side[cursor + 11..cursor + 13].copy_from_slice(&0x6000_u16.to_le_bytes());
    side[cursor + 13..cursor + 15].copy_from_slice(
        &(u16::try_from(payload.len()).expect("FDS payload length")).to_le_bytes(),
    );
    side[cursor + 15] = 0;
    side[cursor + 16] = 4;
    side[cursor + 17..end].copy_from_slice(payload);
    end
}

fn snes_fixture() -> Vec<u8> {
    let mut bytes = vec![0_u8; 0x8000];
    for (index, byte) in bytes.iter_mut().enumerate() {
        *byte = (index as u8).wrapping_mul(19).wrapping_add(7);
    }
    let header = &mut bytes[0x7fc0..0x8000];
    header[0..0x15].fill(b' ');
    header[0x15] = 0x20;
    header[0x27] = 0;
    header[0x1c..0x20].fill(0);
    header[0x3c..0x3e].copy_from_slice(&[0x00, 0x80]);
    bytes
}

fn n64_fixture() -> Vec<u8> {
    let mut bytes = vec![0_u8; 0x200];
    bytes[0..4].copy_from_slice(&[0x80, 0x37, 0x12, 0x40]);
    bytes[0x3c] = 1;
    for (index, byte) in bytes[0x40..].iter_mut().enumerate() {
        *byte = (index as u8).wrapping_mul(23).wrapping_add(9);
    }
    bytes
}

fn n64_swapped16_fixture(native: &[u8]) -> Vec<u8> {
    let mut bytes = native.to_vec();
    for pair in bytes.chunks_exact_mut(2) {
        pair.swap(0, 1);
    }
    bytes
}

fn n64_swapped32_fixture(native: &[u8]) -> Vec<u8> {
    let mut bytes = native.to_vec();
    for word in bytes.chunks_exact_mut(4) {
        word.reverse();
    }
    bytes
}

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

fn genesis_smd_fixture(linear: &[u8]) -> Vec<u8> {
    let mut bytes = vec![0_u8; 512 + linear.len()];
    bytes[0] = (linear.len() / 0x4000) as u8;
    bytes[1] = 0x03;
    bytes[8] = 0xaa;
    bytes[9] = 0xbb;
    for (source, canonical) in linear
        .chunks_exact(0x4000)
        .zip(bytes[512..].chunks_exact_mut(0x4000))
    {
        for index in 0..0x2000 {
            canonical[index] = source[index * 2 + 1];
            canonical[0x2000 + index] = source[index * 2];
        }
    }
    bytes
}

fn sega_header_fixture(region: u8) -> Vec<u8> {
    let mut bytes = vec![0_u8; 0x8000];
    bytes[0x7ff0..0x7ff8].copy_from_slice(b"TMR SEGA");
    bytes[0x7fff] = region | 0x0c;
    bytes
}

fn sms_checksum_fixture() -> Vec<u8> {
    let mut bytes = vec![0_u8; 0x8000];
    for (index, byte) in bytes.iter_mut().enumerate() {
        *byte = (index as u8).wrapping_mul(7).wrapping_add(3);
    }
    bytes[0x7ff0..0x7ff8].copy_from_slice(b"TMR SEGA");
    bytes[0x7fff] = 0x4c;
    let checksum = bytes[..0x7ff0]
        .iter()
        .fold(0_u16, |sum, byte| sum.wrapping_add(u16::from(*byte)));
    bytes[0x7ffa..0x7ffc].copy_from_slice(&checksum.to_le_bytes());
    bytes
}

fn sms_large_fixture(
    length: usize,
    region: u8,
    size_code: u8,
    stored_checksum: Option<u16>,
) -> Vec<u8> {
    let mut bytes = vec![0_u8; length];
    for (index, byte) in bytes.iter_mut().enumerate() {
        *byte = (index as u8).wrapping_mul(11).wrapping_add(5);
    }
    bytes[0x7ff0..0x7ff8].copy_from_slice(b"TMR SEGA");
    bytes[0x7fff] = region << 4 | size_code;
    let checksum = sms_fixture_checksum(&bytes, size_code);
    bytes[0x7ffa..0x7ffc].copy_from_slice(&stored_checksum.unwrap_or(checksum).to_le_bytes());
    bytes
}

fn sms_fixture_checksum(bytes: &[u8], size_code: u8) -> u16 {
    let mut sum = 0_u16;
    for byte in &bytes[..0x7ff0] {
        sum = sum.wrapping_add(u16::from(*byte));
    }
    let checksum_end = match size_code {
        0x0e | 0x0f => 0x20_000,
        0x00..=0x02 => 0x40_000,
        _ => 0x8000,
    };
    for byte in &bytes[0x8000..checksum_end.min(bytes.len())] {
        sum = sum.wrapping_add(u16::from(*byte));
    }
    sum
}

fn nds_fixture(with_padding: bool) -> Vec<u8> {
    let logical_length = 0x4200;
    let mut bytes = vec![0_u8; if with_padding { 0x4400 } else { logical_length }];
    bytes[0x0c..0x10].copy_from_slice(b"ABCD");
    bytes[0xc0..0x15c].copy_from_slice(&AUTHORITATIVE_GBA_LOGO);
    bytes[0x20..0x24].copy_from_slice(&0x4000_u32.to_le_bytes());
    bytes[0x2c..0x30].copy_from_slice(&0x20_u32.to_le_bytes());
    bytes[0x30..0x34].copy_from_slice(&0x4020_u32.to_le_bytes());
    bytes[0x3c..0x40].copy_from_slice(&0x20_u32.to_le_bytes());
    bytes[0x40..0x44].copy_from_slice(&0x4040_u32.to_le_bytes());
    bytes[0x44..0x48].copy_from_slice(&0x20_u32.to_le_bytes());
    bytes[0x48..0x4c].copy_from_slice(&0x4060_u32.to_le_bytes());
    bytes[0x4c..0x50].copy_from_slice(&0x08_u32.to_le_bytes());
    bytes[0x50..0x54].copy_from_slice(&0x4080_u32.to_le_bytes());
    bytes[0x54..0x58].copy_from_slice(&0x20_u32.to_le_bytes());
    bytes[0x58..0x5c].copy_from_slice(&0x40a0_u32.to_le_bytes());
    bytes[0x5c..0x60].copy_from_slice(&0x20_u32.to_le_bytes());
    bytes[0x80..0x84].copy_from_slice(&0x4200_u32.to_le_bytes());
    bytes[0x84..0x88].copy_from_slice(&0x4000_u32.to_le_bytes());
    bytes[0x4040..0x4044].copy_from_slice(&0x08_u32.to_le_bytes());
    bytes[0x4046..0x4048].copy_from_slice(&1_u16.to_le_bytes());
    bytes[0x4048] = 1;
    bytes[0x4049] = b'x';
    bytes[0x404a] = 0;
    bytes[0x4080 + 0x18..0x4080 + 0x1c].copy_from_slice(&0_u32.to_le_bytes());
    bytes[0x40a0 + 0x18..0x40a0 + 0x1c].copy_from_slice(&0_u32.to_le_bytes());
    bytes[0x4060..0x4064].copy_from_slice(&0x40c0_u32.to_le_bytes());
    bytes[0x4064..0x4068].copy_from_slice(&0x40c8_u32.to_le_bytes());
    bytes[0x40c0..0x40c8].copy_from_slice(b"PAYLOAD!");
    bytes[0x15c..0x15e].copy_from_slice(&0xcf56_u16.to_le_bytes());
    bytes[0x15e..0x160].copy_from_slice(&0xd45e_u16.to_le_bytes());
    bytes
}

#[derive(Clone, Copy)]
struct CartridgeIdentityFixture {
    platform: PlatformId,
    content_type: ContentType,
    representation: &'static str,
    fixture_name: &'static str,
    build: fn() -> Vec<u8>,
}

fn nes_ines_identity_fixture() -> Vec<u8> {
    nes_fixture(false)
}

fn nes2_identity_fixture() -> Vec<u8> {
    nes_fixture(true)
}

fn fds_fw_identity_fixture() -> Vec<u8> {
    let mut headered = b"FDS\x1a".to_vec();
    headered.push(1);
    headered.extend_from_slice(&[0; 11]);
    headered.extend_from_slice(&fds_side_fixture());
    headered
}

fn fds_headerless_identity_fixture() -> Vec<u8> {
    fds_side_fixture()
}

fn snes_linear_identity_fixture() -> Vec<u8> {
    snes_fixture()
}

fn snes_copier_headered_identity_fixture() -> Vec<u8> {
    let mut headered = vec![0xa5_u8; 512];
    headered.extend_from_slice(&snes_fixture());
    headered
}

fn gb_identity_fixture() -> Vec<u8> {
    gb_fixture(0x00, 0x8000)
}

fn gbc_identity_fixture() -> Vec<u8> {
    gb_fixture(0x80, 0x8000)
}

fn gba_identity_fixture() -> Vec<u8> {
    gba_fixture(0x100)
}

fn n64_native_identity_fixture() -> Vec<u8> {
    n64_fixture()
}

fn n64_byteswapped16_identity_fixture() -> Vec<u8> {
    n64_swapped16_fixture(&n64_fixture())
}

fn n64_byteswapped32_identity_fixture() -> Vec<u8> {
    n64_swapped32_fixture(&n64_fixture())
}

fn nds_identity_fixture() -> Vec<u8> {
    nds_fixture(false)
}

fn key_free_3ds_identity_fixture() -> Vec<u8> {
    sparse_3ds_header(2)
}

fn sms_identity_fixture() -> Vec<u8> {
    sega_header_fixture(0x40)
}

fn game_gear_identity_fixture() -> Vec<u8> {
    sega_header_fixture(0x50)
}

fn genesis_linear_identity_fixture() -> Vec<u8> {
    genesis_fixture()
}

fn genesis_smd_identity_fixture() -> Vec<u8> {
    genesis_smd_fixture(&genesis_fixture())
}

fn thirty_two_x_identity_fixture() -> Vec<u8> {
    let mut bytes = genesis_fixture();
    bytes[0x100..0x110].copy_from_slice(b"SEGA 32X        ");
    bytes[0x3c0..0x3d0].copy_from_slice(b"MARS CHECK MODE ");
    bytes[0x3d0..0x3d4].copy_from_slice(&0_u32.to_be_bytes());
    bytes[0x3d4..0x3d8].copy_from_slice(&0_u32.to_be_bytes());
    bytes[0x3d8..0x3dc].copy_from_slice(&0x0600_0120_u32.to_be_bytes());
    bytes[0x3dc..0x3e0].copy_from_slice(&0x4000_u32.to_be_bytes());
    bytes[0x3e0..0x3e4].copy_from_slice(&0x0600_2000_u32.to_be_bytes());
    bytes[0x3e4..0x3e8].copy_from_slice(&0x0600_0000_u32.to_be_bytes());
    bytes[0x3e8..0x3ec].copy_from_slice(&0x0600_2000_u32.to_be_bytes());
    bytes[0x3ec..0x3f0].copy_from_slice(&0x0600_0000_u32.to_be_bytes());
    bytes
}

#[test]
fn every_cartridge_identity_row_has_an_explicit_owned_fixture() {
    let fixtures = [
        CartridgeIdentityFixture {
            platform: PlatformId::NintendoNes,
            content_type: ContentType::CartridgeImage,
            representation: "nes-ines",
            fixture_name: "nes-ines-header",
            build: nes_ines_identity_fixture,
        },
        CartridgeIdentityFixture {
            platform: PlatformId::NintendoNes,
            content_type: ContentType::CartridgeImage,
            representation: "nes-2",
            fixture_name: "nes-2-header",
            build: nes2_identity_fixture,
        },
        CartridgeIdentityFixture {
            platform: PlatformId::NintendoFds,
            content_type: ContentType::MagneticDiskImage,
            representation: "fds-fw",
            fixture_name: "fds-fw-header",
            build: fds_fw_identity_fixture,
        },
        CartridgeIdentityFixture {
            platform: PlatformId::NintendoFds,
            content_type: ContentType::MagneticDiskImage,
            representation: "fds-headerless",
            fixture_name: "fds-headerless-side",
            build: fds_headerless_identity_fixture,
        },
        CartridgeIdentityFixture {
            platform: PlatformId::NintendoSnes,
            content_type: ContentType::CartridgeImage,
            representation: "snes-linear",
            fixture_name: "snes-linear-image",
            build: snes_linear_identity_fixture,
        },
        CartridgeIdentityFixture {
            platform: PlatformId::NintendoSnes,
            content_type: ContentType::CartridgeImage,
            representation: "snes-copier-headered",
            fixture_name: "snes-copier-headered-image",
            build: snes_copier_headered_identity_fixture,
        },
        CartridgeIdentityFixture {
            platform: PlatformId::NintendoGb,
            content_type: ContentType::CartridgeImage,
            representation: "raw-cartridge-image",
            fixture_name: "game-boy-header",
            build: gb_identity_fixture,
        },
        CartridgeIdentityFixture {
            platform: PlatformId::NintendoGbc,
            content_type: ContentType::CartridgeImage,
            representation: "raw-cartridge-image",
            fixture_name: "game-boy-color-header",
            build: gbc_identity_fixture,
        },
        CartridgeIdentityFixture {
            platform: PlatformId::NintendoGba,
            content_type: ContentType::CartridgeImage,
            representation: "raw-cartridge-image",
            fixture_name: "game-boy-advance-header",
            build: gba_identity_fixture,
        },
        CartridgeIdentityFixture {
            platform: PlatformId::NintendoN64,
            content_type: ContentType::CartridgeImage,
            representation: "n64-native",
            fixture_name: "n64-native-byte-order",
            build: n64_native_identity_fixture,
        },
        CartridgeIdentityFixture {
            platform: PlatformId::NintendoN64,
            content_type: ContentType::CartridgeImage,
            representation: "n64-byteswapped16",
            fixture_name: "n64-16-bit-byte-order",
            build: n64_byteswapped16_identity_fixture,
        },
        CartridgeIdentityFixture {
            platform: PlatformId::NintendoN64,
            content_type: ContentType::CartridgeImage,
            representation: "n64-byteswapped32",
            fixture_name: "n64-32-bit-byte-order",
            build: n64_byteswapped32_identity_fixture,
        },
        CartridgeIdentityFixture {
            platform: PlatformId::NintendoNds,
            content_type: ContentType::CartridgeImage,
            representation: "raw-cartridge-image",
            fixture_name: "nintendo-ds-trimmed-image",
            build: nds_identity_fixture,
        },
        CartridgeIdentityFixture {
            platform: PlatformId::Nintendo3ds,
            content_type: ContentType::CartridgeImage,
            representation: "ncsd-nocrypto",
            fixture_name: "key-free-ncsd-header",
            build: key_free_3ds_identity_fixture,
        },
        CartridgeIdentityFixture {
            platform: PlatformId::SegaSms,
            content_type: ContentType::CartridgeImage,
            representation: "raw-cartridge-image",
            fixture_name: "master-system-header",
            build: sms_identity_fixture,
        },
        CartridgeIdentityFixture {
            platform: PlatformId::SegaGameGear,
            content_type: ContentType::CartridgeImage,
            representation: "raw-cartridge-image",
            fixture_name: "game-gear-header",
            build: game_gear_identity_fixture,
        },
        CartridgeIdentityFixture {
            platform: PlatformId::SegaGenesis,
            content_type: ContentType::CartridgeImage,
            representation: "genesis-linear-be",
            fixture_name: "genesis-linear-header",
            build: genesis_linear_identity_fixture,
        },
        CartridgeIdentityFixture {
            platform: PlatformId::SegaGenesis,
            content_type: ContentType::CartridgeImage,
            representation: "genesis-smd",
            fixture_name: "genesis-smd-interleaved-image",
            build: genesis_smd_identity_fixture,
        },
        CartridgeIdentityFixture {
            platform: PlatformId::Sega32x,
            content_type: ContentType::CartridgeImage,
            representation: "genesis-linear-be",
            fixture_name: "32x-startup-header",
            build: thirty_two_x_identity_fixture,
        },
    ];

    let mut fixture_names = std::collections::BTreeSet::new();
    for fixture in fixtures {
        assert!(
            fixture_names.insert(fixture.fixture_name),
            "fixture name reused: {}",
            fixture.fixture_name
        );
        let bytes = (fixture.build)();
        assert!(!bytes.is_empty(), "empty fixture: {}", fixture.fixture_name);
        let mut reader = BoundedReader::new(bytes, 64 * 1024);
        let recognized = recognize_content_with_budget(&mut reader, 0x100000)
            .unwrap_or_else(|error| panic!("{}: {error:?}", fixture.fixture_name));
        assert_eq!(
            recognized.platform(),
            fixture.platform,
            "{}",
            fixture.fixture_name
        );
        assert_eq!(
            recognized.content_type(),
            fixture.content_type,
            "{}",
            fixture.fixture_name
        );
        assert_eq!(
            recognized.source_representation(),
            fixture.representation,
            "{}",
            fixture.fixture_name
        );
    }
    assert_eq!(fixture_names.len(), fixtures.len());
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

struct BoundedReader {
    bytes: Vec<u8>,
    max_request: usize,
    largest_request: usize,
}

struct SparseReader {
    length: u64,
    segments: Vec<(u64, Vec<u8>)>,
    max_request: usize,
    largest_request: usize,
}

impl SparseReader {
    fn new(length: u64, segments: Vec<(u64, Vec<u8>)>, max_request: usize) -> Self {
        Self {
            length,
            segments,
            max_request,
            largest_request: 0,
        }
    }
}

impl BoundedReader {
    fn new(bytes: Vec<u8>, max_request: usize) -> Self {
        Self {
            bytes,
            max_request,
            largest_request: 0,
        }
    }
}

impl ContentReader for BoundedReader {
    fn len(&self) -> Result<u64, ContentReadError> {
        Ok(self.bytes.len() as u64)
    }

    fn read_at(&mut self, offset: u64, destination: &mut [u8]) -> Result<usize, ContentReadError> {
        if destination.len() > self.max_request {
            return Err(ContentReadError::RequestTooLarge);
        }
        self.largest_request = self.largest_request.max(destination.len());
        let offset = usize::try_from(offset).map_err(|_| ContentReadError::OutOfRange)?;
        if offset >= self.bytes.len() {
            return Ok(0);
        }
        let end = (offset + destination.len()).min(self.bytes.len());
        let count = end - offset;
        destination[..count].copy_from_slice(&self.bytes[offset..end]);
        Ok(count)
    }

    fn max_read_size(&self) -> usize {
        self.max_request
    }
}

impl ContentReader for SparseReader {
    fn len(&self) -> Result<u64, ContentReadError> {
        Ok(self.length)
    }

    fn read_at(&mut self, offset: u64, destination: &mut [u8]) -> Result<usize, ContentReadError> {
        if destination.len() > self.max_request {
            return Err(ContentReadError::RequestTooLarge);
        }
        let end = offset
            .checked_add(destination.len() as u64)
            .ok_or(ContentReadError::OutOfRange)?;
        if end > self.length {
            return Err(ContentReadError::OutOfRange);
        }
        self.largest_request = self.largest_request.max(destination.len());
        destination.fill(0);
        for (segment_offset, segment) in &self.segments {
            let segment_end = segment_offset
                .checked_add(segment.len() as u64)
                .ok_or(ContentReadError::OutOfRange)?;
            let overlap_start = offset.max(*segment_offset);
            let overlap_end = end.min(segment_end);
            if overlap_start >= overlap_end {
                continue;
            }
            let destination_start = usize::try_from(overlap_start - offset)
                .map_err(|_| ContentReadError::OutOfRange)?;
            let segment_start = usize::try_from(overlap_start - *segment_offset)
                .map_err(|_| ContentReadError::OutOfRange)?;
            let count = usize::try_from(overlap_end - overlap_start)
                .map_err(|_| ContentReadError::OutOfRange)?;
            destination[destination_start..destination_start + count]
                .copy_from_slice(&segment[segment_start..segment_start + count]);
        }
        Ok(destination.len())
    }
}

struct OverreportingSource;

impl SourceReadHandle for OverreportingSource {
    fn len(&self) -> Result<u64, SourceAccessError> {
        Ok(1)
    }

    fn read_at(
        &mut self,
        _offset: u64,
        destination: &mut [u8],
    ) -> Result<usize, SourceAccessError> {
        Ok(destination.len() + 1)
    }
}

#[test]
fn source_read_adapter_rejects_a_provider_count_larger_than_the_destination() {
    let mut source = OverreportingSource;
    let mut reader = SourceReadContentReader::new(&mut source);
    let mut destination = [0_u8; 1];

    assert_eq!(
        reader.read_at(0, &mut destination),
        Err(ContentReadError::Io)
    );
}

fn sparse_3ds_header(media_units: u32) -> Vec<u8> {
    let mut header = vec![0_u8; 0x400];
    header[0x100..0x104].copy_from_slice(b"NCSD");
    header[0x104..0x108].copy_from_slice(&media_units.to_le_bytes());
    header[0x120..0x124].copy_from_slice(&1_u32.to_le_bytes());
    header[0x124..0x128].copy_from_slice(&(media_units - 1).to_le_bytes());
    header[0x300..0x304].copy_from_slice(b"NCCH");
    header[0x304..0x308].copy_from_slice(&1_u32.to_le_bytes());
    header[0x38f] = 0x04;
    header
}

#[test]
fn general_dispatcher_hashes_gb_incrementally_without_whole_file_reads() {
    let mut bytes = gb_fixture(0x00, 0x100000);
    bytes[0x148] = 0x05;
    let mut checksum = 0_u8;
    for byte in &bytes[0x134..0x14d] {
        checksum = checksum.wrapping_sub(*byte).wrapping_sub(1);
    }
    bytes[0x14d] = checksum;
    let mut reader = BoundedReader::new(bytes, 64 * 1024);
    let recognized = recognize_content_with_budget(&mut reader, 0x100000).expect("GB fixture");

    assert_eq!(recognized.platform(), PlatformId::NintendoGb);
    assert_eq!(recognized.source_representation(), "raw-cartridge-image");
    assert!(reader.largest_request <= 64 * 1024);
    assert!(reader.largest_request < 0x100000);
    assert_eq!(recognized.canonical_length(), 0x100000);
}

#[test]
fn local_source_reader_detects_mutation_after_stream_recognition() {
    let directory = tempdir().expect("tempdir");
    let source_path = directory.path().join("game.gb");
    std::fs::write(&source_path, gb_fixture(0x00, 0x8000)).expect("write source");

    let locator = RootLocator::from_provider(directory.path().to_string_lossy().into_owned());
    let access = argus_infrastructure::local_filesystem::LocalFilesystemSourceAccess::new(&locator);
    let root = access.resolve_root().expect("resolve source root");
    let mut reader = access
        .open_entry_reader(
            &root,
            &RelativeSourceLocator::from_provider("game.gb".to_owned()),
        )
        .expect("open bounded source reader");
    recognize_content_with_budget(&mut reader, 0x100000).expect("stream recognition");

    std::fs::write(&source_path, vec![0_u8; 0x10000]).expect("mutate source");
    assert!(
        !reader
            .source_version_is_unchanged()
            .expect("re-read source version")
    );
}

#[test]
fn legacy_raw_adapter_does_not_accept_general_platform_candidates() {
    let mut bytes = vec![0_u8; 0x1000];
    bytes[0..4].copy_from_slice(&[0x80, 0x37, 0x12, 0x40]);
    let error = recognize_raw_cartridge(&bytes).expect_err("not a GB/GBC/GBA image");
    assert_eq!(error, RecognitionError::InvalidNintendoLogo);
}

#[test]
fn general_dispatcher_exposes_typed_truncation_for_unknown_short_source() {
    let mut reader = BoundedReader::new(b"NES\x1a\0\0\0\0".to_vec(), 64 * 1024);
    assert_eq!(
        recognize_content_with_budget(&mut reader, 0x20).expect_err("unsupported source"),
        ContentRecognitionError::Truncated
    );
}

#[test]
fn complete_unknown_source_is_unsupported_instead_of_truncated() {
    let mut reader = BoundedReader::new(vec![0_u8; 0x20], 64 * 1024);
    assert_eq!(
        recognize_content_with_budget(&mut reader, 0x20).expect_err("unknown source"),
        ContentRecognitionError::UnsupportedRepresentation
    );
}

#[test]
fn alternate_optical_dispatch_reads_bounded_probe_and_leaves_native_sources_unmatched() {
    let staging = tempdir().expect("staging root");
    let mut reader = BoundedReader::new(gb_fixture(0x00, 0x8000), 4);
    let mut session = ParsingSession::for_tests(
        TransformationBudget::new(0x100000, 0x100000, 16, 2, 0x100000, 0x100000),
        staging.path(),
        || false,
    );

    assert_eq!(
        recognize_alternate_optical(&mut reader, &mut session).expect("alternate dispatch"),
        None
    );
    assert!(reader.largest_request <= 4);
}

#[test]
fn overlapping_sega_header_evidence_is_ambiguous() {
    let mut bytes = vec![0_u8; 0x10000];
    bytes[0x1ff0..0x1ff8].copy_from_slice(b"TMR SEGA");
    bytes[0x1fff] = 0x4a;
    bytes[0x3ff0..0x3ff8].copy_from_slice(b"TMR SEGA");
    bytes[0x3fff] = 0x5b;
    let mut reader = BoundedReader::new(bytes, 64 * 1024);

    assert_eq!(
        recognize_content_with_budget(&mut reader, 0x100000).expect_err("conflicting Sega headers"),
        ContentRecognitionError::AmbiguousContentRecognition
    );
}

#[test]
fn nes_representations_are_recognized_with_bounded_canonical_hashing() {
    for (bytes, representation) in [
        (nes_fixture(false), "nes-ines"),
        (nes_fixture(true), "nes-2"),
    ] {
        let mut reader = BoundedReader::new(bytes, 64 * 1024);
        let recognized = recognize_content_with_budget(&mut reader, 0x100000).expect("NES fixture");
        assert_eq!(recognized.platform(), PlatformId::NintendoNes);
        assert_eq!(recognized.source_representation(), representation);
        assert!(reader.largest_request <= 64 * 1024);
    }
}

#[test]
fn common_nonzero_nes_mappers_are_recognized_in_ines_and_nes2_headers() {
    for (bytes, representation) in [
        (nes_mapper_fixture(false, 1, 0), "nes-ines"),
        (nes_mapper_fixture(false, 4, 0), "nes-ines"),
        (nes_mapper_fixture(true, 4, 1), "nes-2"),
    ] {
        let mut reader = BoundedReader::new(bytes, 64 * 1024);
        let recognized =
            recognize_content_with_budget(&mut reader, 0x100000).expect("non-zero NES mapper");
        assert_eq!(recognized.platform(), PlatformId::NintendoNes);
        assert_eq!(recognized.source_representation(), representation);
        assert!(reader.largest_request <= 64 * 1024);
    }
}

#[test]
fn ambiguous_legacy_nes_headers_are_not_authoritatively_recognized() {
    let mut archaic = nes_fixture(false);
    archaic[7] = 0x04;
    let mut archaic_reader = BoundedReader::new(archaic, 64 * 1024);
    assert_eq!(
        recognize_content_with_budget(&mut archaic_reader, 0x100000)
            .expect_err("archaic iNES ambiguity"),
        ContentRecognitionError::UnsupportedRepresentation
    );

    let mut polluted = nes_fixture(false);
    polluted[12] = 1;
    let mut polluted_reader = BoundedReader::new(polluted, 64 * 1024);
    assert_eq!(
        recognize_content_with_budget(&mut polluted_reader, 0x100000)
            .expect_err("legacy iNES ambiguity"),
        ContentRecognitionError::UnsupportedRepresentation
    );
}

#[test]
fn fds_headered_and_headerless_sides_converge_without_header_bytes() {
    let side = fds_side_fixture();
    let mut headered = b"FDS\x1a".to_vec();
    headered.push(1);
    headered.extend_from_slice(&[0; 11]);
    headered.extend_from_slice(&side);

    let mut headered_reader = BoundedReader::new(headered, 64 * 1024);
    let headered_result =
        recognize_content_with_budget(&mut headered_reader, 0x100000).expect("headered FDS");
    let mut headerless_reader = BoundedReader::new(side, 64 * 1024);
    let headerless_result =
        recognize_content_with_budget(&mut headerless_reader, 0x100000).expect("headerless FDS");

    assert_eq!(headered_result.platform(), PlatformId::NintendoFds);
    assert_eq!(headered_result.source_representation(), "fds-fw");
    assert_eq!(headerless_result.source_representation(), "fds-headerless");
    assert_eq!(
        headered_result.identity_digest(),
        headerless_result.identity_digest()
    );
}

#[test]
fn fds_marker_only_random_side_is_malformed() {
    let mut bytes = vec![0_u8; 65_500];
    bytes[1..15].copy_from_slice(b"*NINTENDO-HVC*");
    let mut reader = BoundedReader::new(bytes, 64 * 1024);
    assert_eq!(
        recognize_content_with_budget(&mut reader, 0x100000).expect_err("marker-only FDS side"),
        ContentRecognitionError::Malformed
    );
}

#[test]
fn fds_hidden_file_pairs_after_the_bios_count_are_part_of_the_side() {
    let base_side = fds_side_fixture();
    let mut side = fds_side_fixture();
    let first_end = 58 + 17 + 8;
    append_fds_file(&mut side, first_end, 7, 2, b"HIDE");

    let mut reader = BoundedReader::new(side, 64 * 1024);
    let recognized = recognize_content_with_budget(&mut reader, 0x100000).expect("hidden FDS file");
    let mut base_reader = BoundedReader::new(base_side, 64 * 1024);
    let base = recognize_content_with_budget(&mut base_reader, 0x100000).expect("base FDS side");
    assert_eq!(recognized.platform(), PlatformId::NintendoFds);
    assert_eq!(recognized.canonical_length(), 65_529);
    assert_ne!(recognized.identity_digest(), base.identity_digest());
}

#[test]
fn fds_file_numbers_need_not_be_sequential_when_file_ids_are_valid() {
    let mut side = fds_side_fixture();
    side[59] = 9;
    let first_end = 58 + 17 + 8;
    append_fds_file(&mut side, first_end, 9, 2, b"HIDE");

    let mut reader = BoundedReader::new(side, 64 * 1024);
    recognize_content_with_budget(&mut reader, 0x100000)
        .expect("duplicate non-sequential FDS file numbers");
}

#[test]
fn malformed_fds_hidden_file_order_and_length_are_rejected() {
    let first_end = 58 + 17 + 8;

    let mut wrong_order = fds_side_fixture();
    wrong_order[first_end] = 4;
    let mut wrong_order_reader = BoundedReader::new(wrong_order, 64 * 1024);
    assert_eq!(
        recognize_content_with_budget(&mut wrong_order_reader, 0x100000)
            .expect_err("hidden FDS block order"),
        ContentRecognitionError::Malformed
    );

    let mut too_long = fds_side_fixture();
    too_long[first_end] = 3;
    too_long[first_end + 16] = 4;
    too_long[first_end + 13..first_end + 15].copy_from_slice(&u16::MAX.to_le_bytes());
    let mut too_long_reader = BoundedReader::new(too_long, 64 * 1024);
    assert_eq!(
        recognize_content_with_budget(&mut too_long_reader, 0x100000)
            .expect_err("hidden FDS file length"),
        ContentRecognitionError::Truncated
    );
}

#[test]
fn snes_linear_and_validated_copier_headered_representations_converge() {
    let linear = snes_fixture();
    let mut headered = vec![0xa5_u8; 512];
    headered.extend_from_slice(&linear);

    let mut linear_reader = BoundedReader::new(linear, 64 * 1024);
    let linear_result =
        recognize_content_with_budget(&mut linear_reader, 0x100000).expect("linear SNES");
    let mut headered_reader = BoundedReader::new(headered, 64 * 1024);
    let headered_result = recognize_content_with_budget(&mut headered_reader, 0x100000)
        .expect("copier-headered SNES");

    assert_eq!(linear_result.platform(), PlatformId::NintendoSnes);
    assert_eq!(linear_result.source_representation(), "snes-linear");
    assert_eq!(
        headered_result.source_representation(),
        "snes-copier-headered"
    );
    assert_eq!(
        linear_result.identity_digest(),
        headered_result.identity_digest()
    );
}

#[test]
fn n64_byte_orders_converge_to_native_big_endian_identity() {
    let native = n64_fixture();
    let swapped16 = n64_swapped16_fixture(&native);
    let swapped32 = n64_swapped32_fixture(&native);

    let mut native_reader = BoundedReader::new(native, 64 * 1024);
    let native_result =
        recognize_content_with_budget(&mut native_reader, 0x100000).expect("native N64");
    let mut swapped16_reader = BoundedReader::new(swapped16, 64 * 1024);
    let swapped16_result =
        recognize_content_with_budget(&mut swapped16_reader, 0x100000).expect("16-bit swapped N64");
    let mut swapped32_reader = BoundedReader::new(swapped32, 64 * 1024);
    let swapped32_result =
        recognize_content_with_budget(&mut swapped32_reader, 0x100000).expect("32-bit swapped N64");

    assert_eq!(native_result.source_representation(), "n64-native");
    assert_eq!(
        swapped16_result.source_representation(),
        "n64-byteswapped16"
    );
    assert_eq!(
        swapped32_result.source_representation(),
        "n64-byteswapped32"
    );
    assert_eq!(
        native_result.identity_digest(),
        swapped16_result.identity_digest()
    );
    assert_eq!(
        native_result.identity_digest(),
        swapped32_result.identity_digest()
    );
}

#[test]
fn genesis_linear_and_smd_representations_converge() {
    let linear = genesis_fixture();
    let smd = genesis_smd_fixture(&linear);

    let mut linear_reader = BoundedReader::new(linear, 64 * 1024);
    let linear_result =
        recognize_content_with_budget(&mut linear_reader, 0x100000).expect("linear Genesis");
    let mut smd_reader = BoundedReader::new(smd, 64 * 1024);
    let smd_result = recognize_content_with_budget(&mut smd_reader, 0x100000).expect("SMD Genesis");

    assert_eq!(linear_result.platform(), PlatformId::SegaGenesis);
    assert_eq!(linear_result.source_representation(), "genesis-linear-be");
    assert_eq!(smd_result.source_representation(), "genesis-smd");
    assert_eq!(
        linear_result.identity_digest(),
        smd_result.identity_digest()
    );
}

#[test]
fn valid_32x_startup_evidence_is_distinct_from_generic_genesis() {
    let mut bytes = genesis_fixture();
    bytes[0x100..0x110].copy_from_slice(b"SEGA 32X        ");
    bytes[0x3c0..0x3d0].copy_from_slice(b"MARS CHECK MODE ");
    bytes[0x3d0..0x3d4].copy_from_slice(&0_u32.to_be_bytes());
    bytes[0x3d4..0x3d8].copy_from_slice(&0_u32.to_be_bytes());
    bytes[0x3d8..0x3dc].copy_from_slice(&0x0600_0120_u32.to_be_bytes());
    bytes[0x3dc..0x3e0].copy_from_slice(&0x4000_u32.to_be_bytes());
    bytes[0x3e0..0x3e4].copy_from_slice(&0x0600_2000_u32.to_be_bytes());
    bytes[0x3e4..0x3e8].copy_from_slice(&0x0600_0000_u32.to_be_bytes());
    bytes[0x3e8..0x3ec].copy_from_slice(&0x0600_2000_u32.to_be_bytes());
    bytes[0x3ec..0x3f0].copy_from_slice(&0x0600_0000_u32.to_be_bytes());
    let mut reader = BoundedReader::new(bytes, 64 * 1024);

    let recognized = recognize_content_with_budget(&mut reader, 0x100000).expect("32X cartridge");
    assert_eq!(recognized.platform(), PlatformId::Sega32x);
    assert_eq!(recognized.source_representation(), "genesis-linear-be");
}

#[test]
fn thirty_two_x_marker_without_a_contained_user_payload_is_malformed() {
    let mut bytes = genesis_fixture();
    bytes[0x3c0..0x3d0].copy_from_slice(b"MARS CHECK MODE ");
    bytes[0x3d8..0x3dc].copy_from_slice(&0x7fff_ffff_u32.to_be_bytes());
    let mut reader = BoundedReader::new(bytes, 64 * 1024);

    assert_eq!(
        recognize_content_with_budget(&mut reader, 0x100000).expect_err("invalid 32X header"),
        ContentRecognitionError::Malformed
    );
}

#[test]
fn sms_and_game_gear_use_explicit_header_region_evidence() {
    let mut sms_reader = BoundedReader::new(sega_header_fixture(0x40), 64 * 1024);
    let sms = recognize_content_with_budget(&mut sms_reader, 0x100000).expect("SMS");
    let mut game_gear_reader = BoundedReader::new(sega_header_fixture(0x50), 64 * 1024);
    let game_gear =
        recognize_content_with_budget(&mut game_gear_reader, 0x100000).expect("Game Gear");

    assert_eq!(sms.platform(), PlatformId::SegaSms);
    assert_eq!(game_gear.platform(), PlatformId::SegaGameGear);
}

#[test]
fn sms_checksum_uses_byte_accumulation_outside_the_header() {
    let mut reader = BoundedReader::new(sms_checksum_fixture(), 64 * 1024);
    let recognized =
        recognize_content_with_budget(&mut reader, 0x100000).expect("non-zero SMS checksum");
    assert_eq!(recognized.platform(), PlatformId::SegaSms);

    let mut corrupted = sms_checksum_fixture();
    corrupted[0x100] ^= 1;
    let mut corrupted_reader = BoundedReader::new(corrupted, 64 * 1024);
    assert_eq!(
        recognize_content_with_budget(&mut corrupted_reader, 0x100000)
            .expect_err("incorrect SMS checksum"),
        ContentRecognitionError::Malformed
    );
}

#[test]
fn sms_large_cartridges_keep_the_full_extent_and_use_the_header_checksum_range() {
    for (length, size_code) in [(64 * 1024, 0x0e), (128 * 1024, 0x0f), (256 * 1024, 0x0f)] {
        let mut reader =
            BoundedReader::new(sms_large_fixture(length, 0x4, size_code, None), 64 * 1024);
        let recognized =
            recognize_content_with_budget(&mut reader, 0x100000).expect("large SMS cartridge");
        assert_eq!(recognized.platform(), PlatformId::SegaSms);
        assert_eq!(recognized.canonical_length(), length as u64);
    }
}

#[test]
fn game_gear_does_not_require_a_historically_accurate_checksum() {
    let mut reader = BoundedReader::new(
        sms_large_fixture(128 * 1024, 0x5, 0x0f, Some(0x1234)),
        64 * 1024,
    );
    let recognized = recognize_content_with_budget(&mut reader, 0x100000)
        .expect("Game Gear checksum is advisory");
    assert_eq!(recognized.platform(), PlatformId::SegaGameGear);
    assert_eq!(recognized.canonical_length(), 128 * 1024);
}

#[test]
fn nds_trimmed_and_zero_or_ff_padded_sources_converge() {
    let mut logical_reader = BoundedReader::new(nds_fixture(false), 64 * 1024);
    let logical =
        recognize_content_with_budget(&mut logical_reader, 0x100000).expect("logical NDS");
    let mut padded_reader = BoundedReader::new(nds_fixture(true), 64 * 1024);
    let padded = recognize_content_with_budget(&mut padded_reader, 0x100000).expect("padded NDS");
    let mut ff_padded = nds_fixture(true);
    ff_padded[0x4200..].fill(0xff);
    let mut ff_reader = BoundedReader::new(ff_padded, 64 * 1024);
    let ff = recognize_content_with_budget(&mut ff_reader, 0x100000).expect("FF-padded NDS");

    assert_eq!(logical.platform(), PlatformId::NintendoNds);
    assert_eq!(logical.identity_digest(), padded.identity_digest());
    assert_eq!(logical.identity_digest(), ff.identity_digest());
    assert_eq!(padded.canonical_length(), 0x4200);
}

#[test]
fn nds_declared_identity_region_outside_total_used_is_invalid() {
    let mut bytes = nds_fixture(true);
    bytes[0x20..0x24].copy_from_slice(&0x4300_u32.to_le_bytes());
    let mut reader = BoundedReader::new(bytes, 64 * 1024);
    assert_eq!(
        recognize_content_with_budget(&mut reader, 0x100000)
            .expect_err("NDS region beyond declared extent"),
        ContentRecognitionError::Malformed
    );
}

#[test]
fn nds_zero_crc_fields_do_not_bypass_required_validation() {
    let mut bytes = nds_fixture(false);
    bytes[0x15c..0x160].fill(0);
    let mut reader = BoundedReader::new(bytes, 64 * 1024);
    assert_eq!(
        recognize_content_with_budget(&mut reader, 0x100000).expect_err("zero NDS CRC"),
        ContentRecognitionError::Malformed
    );
}

#[test]
fn nes_exponent_multiplier_size_is_decoded_as_bytes() {
    let mut bytes = vec![0_u8; 16 + 64];
    bytes[0..4].copy_from_slice(b"NES\x1a");
    bytes[4] = 0x18;
    bytes[7] = 0x08;
    bytes[9] = 0x0f;
    for (index, byte) in bytes[16..].iter_mut().enumerate() {
        *byte = index as u8;
    }
    let mut reader = BoundedReader::new(bytes, 64 * 1024);
    let recognized = recognize_content_with_budget(&mut reader, 0x100000).expect("NES 2.0 size");
    assert_eq!(recognized.platform(), PlatformId::NintendoNes);
    assert_eq!(recognized.canonical_length(), 173);
}

#[test]
fn nes_nonvolatile_ram_semantics_are_identity_bearing() {
    let mut first = nes_fixture(true);
    first[10] = 0x07;
    let mut second = first.clone();
    second[10] = 0x70;
    let first = recognize_content_with_budget(&mut BoundedReader::new(first, 64 * 1024), 0x100000)
        .expect("NES RAM semantics");
    let second =
        recognize_content_with_budget(&mut BoundedReader::new(second, 64 * 1024), 0x100000)
            .expect("NES NVRAM semantics");
    assert_ne!(first.identity_digest(), second.identity_digest());
}

#[test]
fn nes_miscellaneous_count_uses_only_the_defined_low_bits() {
    let mut bytes = nes_fixture(true);
    bytes[14] = 0x04;
    let mut reader = BoundedReader::new(bytes, 64 * 1024);
    let recognized = recognize_content_with_budget(&mut reader, 0x100000).expect("NES misc bits");
    assert_eq!(recognized.platform(), PlatformId::NintendoNes);
}

#[test]
fn key_free_3ds_is_recognized_and_encrypted_ncch_is_rejected() {
    let mut bytes = vec![0_u8; 0x400];
    bytes[0x100..0x104].copy_from_slice(b"NCSD");
    bytes[0x104..0x108].copy_from_slice(&2_u32.to_le_bytes());
    bytes[0x120..0x124].copy_from_slice(&1_u32.to_le_bytes());
    bytes[0x124..0x128].copy_from_slice(&1_u32.to_le_bytes());
    bytes[0x300..0x304].copy_from_slice(b"NCCH");
    bytes[0x304..0x308].copy_from_slice(&1_u32.to_le_bytes());
    bytes[0x38f] = 0x04;
    let mut reader = BoundedReader::new(bytes.clone(), 64 * 1024);
    let recognized = recognize_content_with_budget(&mut reader, 0x100000).expect("key-free 3DS");
    assert_eq!(recognized.platform(), PlatformId::Nintendo3ds);
    assert_eq!(recognized.source_representation(), "ncsd-nocrypto");

    bytes[0x38f] = 0;
    let mut encrypted_reader = BoundedReader::new(bytes, 64 * 1024);
    assert_eq!(
        recognize_content_with_budget(&mut encrypted_reader, 0x100000).expect_err("encrypted NCCH"),
        ContentRecognitionError::EncryptedContentUnsupported
    );
}

#[test]
fn production_budget_admits_a_four_gib_sparse_ncsd_with_bounded_reads() {
    let four_gib = 4_u64 * 1024 * 1024 * 1024;
    let media_units = u32::try_from(four_gib / 0x200).expect("4 GiB media units");
    let mut reader = SparseReader::new(
        four_gib,
        vec![(0, sparse_3ds_header(media_units))],
        64 * 1024,
    );
    let recognized = recognize_content(&mut reader).expect("4 GiB sparse NCSD");

    assert_eq!(recognized.platform(), PlatformId::Nintendo3ds);
    assert_eq!(recognized.canonical_length(), four_gib);
    assert!(reader.largest_request <= 64 * 1024);
}

#[test]
fn production_budget_rejects_a_representation_larger_than_four_gib() {
    let four_gib_and_one = 4_u64 * 1024 * 1024 * 1024 + 1;
    let mut reader = SparseReader::new(four_gib_and_one, Vec::new(), 64 * 1024);
    assert_eq!(
        recognize_content(&mut reader).expect_err("over-limit 3DS source"),
        ContentRecognitionError::ResourceLimitExceeded
    );
}

#[test]
fn three_ds_rejects_overlapping_ncsd_partitions() {
    let mut bytes = vec![0_u8; 0x400];
    bytes[0x100..0x104].copy_from_slice(b"NCSD");
    bytes[0x104..0x108].copy_from_slice(&2_u32.to_le_bytes());
    for base in [0x120, 0x128] {
        bytes[base..base + 4].copy_from_slice(&1_u32.to_le_bytes());
        bytes[base + 4..base + 8].copy_from_slice(&1_u32.to_le_bytes());
    }
    bytes[0x300..0x304].copy_from_slice(b"NCCH");
    bytes[0x304..0x308].copy_from_slice(&1_u32.to_le_bytes());
    bytes[0x38f] = 0x04;
    let mut reader = BoundedReader::new(bytes, 64 * 1024);
    assert_eq!(
        recognize_content_with_budget(&mut reader, 0x100000).expect_err("overlapping partitions"),
        ContentRecognitionError::Malformed
    );
}

#[test]
fn three_ds_rejects_inconsistent_internal_ncch_regions() {
    let mut bytes = vec![0_u8; 0x400];
    bytes[0x100..0x104].copy_from_slice(b"NCSD");
    bytes[0x104..0x108].copy_from_slice(&2_u32.to_le_bytes());
    bytes[0x120..0x124].copy_from_slice(&1_u32.to_le_bytes());
    bytes[0x124..0x128].copy_from_slice(&1_u32.to_le_bytes());
    bytes[0x300..0x304].copy_from_slice(b"NCCH");
    bytes[0x304..0x308].copy_from_slice(&1_u32.to_le_bytes());
    bytes[0x3a0..0x3a4].copy_from_slice(&1_u32.to_le_bytes());
    bytes[0x3a4..0x3a8].copy_from_slice(&1_u32.to_le_bytes());
    bytes[0x3a8..0x3ac].copy_from_slice(&2_u32.to_le_bytes());
    bytes[0x38f] = 0x04;
    let mut reader = BoundedReader::new(bytes, 64 * 1024);
    assert_eq!(
        recognize_content_with_budget(&mut reader, 0x100000).expect_err("internal NCCH region"),
        ContentRecognitionError::Malformed
    );
}

#[test]
fn general_default_budget_supports_large_bounded_nds_sources() {
    let mut bytes = nds_fixture(true);
    bytes.resize(64 * 1024 * 1024 + 1, 0);
    let mut reader = BoundedReader::new(bytes, 64 * 1024);
    let recognized = recognize_content(&mut reader).expect("large NDS source");
    assert_eq!(recognized.platform(), PlatformId::NintendoNds);
    assert!(reader.largest_request <= 64 * 1024);
}

#[test]
fn cumulative_resource_budget_is_shared_across_all_probes() {
    let mut reader = BoundedReader::new(nds_fixture(false), 64 * 1024);
    let limits = ContentProcessingLimits {
        max_representation_bytes: 0x100000,
        max_read_buffer_bytes: 64 * 1024,
        max_cumulative_read_bytes: 0x200,
        max_cumulative_work_bytes: 0x200,
    };
    assert_eq!(
        recognize_content_with_limits(&mut reader, limits).expect_err("cumulative budget"),
        ContentRecognitionError::ResourceLimitExceeded
    );
}

#[test]
fn archives_and_deferred_containers_are_explicitly_unsupported() {
    for prefix in [
        b"PK\x03\x04".as_slice(),
        b"PK\x05\x06".as_slice(),
        b"PK\x07\x08".as_slice(),
        b"7z\xbc\xaf\x27\x1c".as_slice(),
        b"Rar!\x1a\x07".as_slice(),
        b"MComprHD".as_slice(),
        b"CISO".as_slice(),
        b"WBFS".as_slice(),
        b"RVZ\x01".as_slice(),
        b"WIA\x01".as_slice(),
        b"\x1f\x8b".as_slice(),
        b"BZh".as_slice(),
        b"\xfd7zXZ\0".as_slice(),
    ] {
        let mut bytes = gb_fixture(0x80, 32 * 1024);
        bytes[..prefix.len()].copy_from_slice(prefix);
        let mut reader = BoundedReader::new(bytes, 64 * 1024);
        assert_eq!(
            recognize_content_with_budget(&mut reader, 0x100000).expect_err("deferred container"),
            ContentRecognitionError::UnsupportedRepresentation
        );
    }

    let mut tar = gb_fixture(0x80, 32 * 1024);
    tar[257..262].copy_from_slice(b"ustar");
    let mut reader = BoundedReader::new(tar, 64 * 1024);
    assert_eq!(
        recognize_content_with_budget(&mut reader, 0x100000).expect_err("tar container"),
        ContentRecognitionError::UnsupportedRepresentation
    );
}
