use argus_application::TransformationBudget;
use argus_infrastructure::content::{
    ContentReadError, ContentReader, OpticalError, ParsingSession, recognize_native_optical,
    recognize_wbfs,
};
use tempfile::tempdir;

const WBFS_HEADER_BYTES: usize = 512;
const WBFS_BLOCK_BYTES: usize = 2 * 1024 * 1024;
const WII_SECTOR_BYTES: usize = 32 * 1024;
const WII_BLOCK_COUNT: usize = 4_482;
const DISC_INFO_BYTES: usize = 0x100 + WII_BLOCK_COUNT * 2;
const DISC_INFO_ALIGNED_BYTES: usize =
    DISC_INFO_BYTES.div_ceil(WBFS_HEADER_BYTES) * WBFS_HEADER_BYTES;

struct MemoryReader {
    bytes: Vec<u8>,
}

impl MemoryReader {
    fn new(bytes: Vec<u8>) -> Self {
        Self { bytes }
    }
}

impl ContentReader for MemoryReader {
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

fn budget(max_work: u64) -> TransformationBudget {
    TransformationBudget::new(
        128 * 1024 * 1024,
        256 * 1024 * 1024,
        65_536,
        4,
        128 * 1024 * 1024,
        max_work,
    )
}

fn recognize(
    bytes: Vec<u8>,
    max_work: u64,
) -> Result<argus_infrastructure::content::OpticalRecognition, OpticalError> {
    let staging = tempdir().expect("staging");
    let mut session = ParsingSession::for_tests(budget(max_work), staging.path(), || false);
    let mut reader = MemoryReader::new(bytes);
    recognize_wbfs(&mut reader, &mut session)
}

fn set_u16_be(bytes: &mut [u8], offset: usize, value: u16) {
    bytes[offset..offset + 2].copy_from_slice(&value.to_be_bytes());
}

fn set_u32_be(bytes: &mut [u8], offset: usize, value: u32) {
    bytes[offset..offset + 4].copy_from_slice(&value.to_be_bytes());
}

fn build_valid_wii_image() -> Vec<u8> {
    let mut image = vec![0_u8; WII_SECTOR_BYTES * 16];
    image[..6].copy_from_slice(b"RMCP01");
    image[0x18..0x1c].copy_from_slice(&[0x5d, 0x1c, 0x9e, 0xa3]);
    set_u32_be(&mut image, 0x4fffc, 0xc3f8_1a8e);
    set_u32_be(&mut image, 0x40000, 1);
    set_u32_be(&mut image, 0x40004, 0x100);
    set_u32_be(&mut image, 0x40400, 0x50000 >> 2);
    set_u32_be(&mut image, 0x40404, 0);
    set_u32_be(&mut image, 0x50000 + 0x2b8, 0x4000 >> 2);
    set_u32_be(&mut image, 0x50000 + 0x2bc, 0x20000 >> 2);
    image
}

fn wbfs_image(logical: &[u8], block_indexes: &[u16]) -> Vec<u8> {
    assert!(logical.len().is_multiple_of(WII_SECTOR_BYTES));
    assert!(logical.len() <= block_indexes.len() * WBFS_BLOCK_BYTES);
    let disc_info_offset = WBFS_HEADER_BYTES;
    let data_block_count = block_indexes.iter().copied().max().unwrap_or(0) as usize + 1;
    let file_len = data_block_count * WBFS_BLOCK_BYTES;
    let mut result = vec![
        0_u8;
        file_len
            .max(disc_info_offset + DISC_INFO_ALIGNED_BYTES)
            .max(16 * 1024 * 1024)
    ];

    result[..4].copy_from_slice(b"WBFS");
    let header_sector_count = (result.len() / WBFS_HEADER_BYTES) as u32;
    set_u32_be(&mut result, 4, header_sector_count);
    result[8] = 9;
    result[9] = 21;
    result[12] = 1;

    let disc_info = disc_info_offset;
    result[disc_info..disc_info + 6].copy_from_slice(b"RMCP01");
    result[disc_info + 0x18..disc_info + 0x1c].copy_from_slice(&[0x5d, 0x1c, 0x9e, 0xa3]);
    for (logical_block, &physical_block) in block_indexes.iter().enumerate() {
        set_u16_be(
            &mut result,
            disc_info + 0x100 + logical_block * 2,
            physical_block,
        );
    }

    for (logical_block, &physical_block) in block_indexes.iter().enumerate() {
        let logical_start = logical_block * WBFS_BLOCK_BYTES;
        let logical_end = (logical_start + WBFS_BLOCK_BYTES).min(logical.len());
        if logical_start >= logical.len() {
            break;
        }
        let physical_start = usize::from(physical_block) * WBFS_BLOCK_BYTES;
        result[physical_start..physical_start + (logical_end - logical_start)]
            .copy_from_slice(&logical[logical_start..logical_end]);
    }
    result
}

#[test]
fn matching_wbfs_sparse_extents_converge_without_hashing_container_metadata() {
    let logical = build_valid_wii_image();
    let block_indexes = [1_u16];
    let first = wbfs_image(&logical, &block_indexes);
    let mut second = first.clone();
    second[10] ^= 0x55;
    second[WBFS_HEADER_BYTES + 0x20] ^= 0x33;

    let first_recognition = recognize(first, 100_000_000).expect("WBFS first");
    let second_recognition = recognize(second, 100_000_000).expect("WBFS second");
    assert_eq!(
        first_recognition.platform(),
        argus_application::PlatformId::NintendoWii
    );
    assert_eq!(
        first_recognition.content_type(),
        argus_application::ContentType::OpticalDiscWii
    );
    assert_eq!(
        first_recognition.identity_digest(),
        second_recognition.identity_digest()
    );
    assert_eq!(first_recognition.source_representation(), "wbfs");
}

#[test]
fn changed_preserved_wbfs_bytes_change_identity_and_scrubbing_does_not_converge_with_complete_wii()
{
    let logical = build_valid_wii_image();
    let block_indexes = [1_u16];
    let first = wbfs_image(&logical, &block_indexes);
    let mut changed = first.clone();
    changed[WBFS_BLOCK_BYTES + 0x1234] ^= 0x80;

    let first_recognition = recognize(first, 100_000_000).expect("WBFS first");
    let changed_recognition = recognize(changed, 100_000_000).expect("WBFS changed");
    assert_ne!(
        first_recognition.identity_digest(),
        changed_recognition.identity_digest()
    );

    let mut raw_reader = MemoryReader::new(logical);
    let raw = recognize_native_optical(&mut raw_reader).expect("complete raw Wii");
    assert_ne!(first_recognition.identity_digest(), raw.identity_digest());
}

#[test]
fn wbfs_rejects_invalid_geometry_and_honors_cancellation_or_work_limits() {
    let logical = build_valid_wii_image();
    let valid = wbfs_image(&logical, &[1]);

    let mut bad_map = valid.clone();
    set_u16_be(&mut bad_map, WBFS_HEADER_BYTES + 0x100, 0xffff);
    assert!(matches!(
        recognize(bad_map, 100_000_000),
        Err(OpticalError::Malformed | OpticalError::Truncated)
    ));

    let staging = tempdir().expect("staging");
    let mut cancelled = ParsingSession::for_tests(budget(100_000_000), staging.path(), || true);
    let mut reader = MemoryReader::new(valid.clone());
    assert_eq!(
        recognize_wbfs(&mut reader, &mut cancelled),
        Err(OpticalError::Cancelled)
    );
    assert!(matches!(
        recognize(valid, 1),
        Err(OpticalError::ResourceLimitExceeded)
    ));
}

#[test]
fn wbfs_logical_capacity_accounts_for_partial_hard_disk_sectors() {
    let logical = build_valid_wii_image();
    let larger = wbfs_image(&logical, &[8]);
    assert_eq!(
        recognize(larger, 100_000_000)
            .expect("WBFS with the ninth backing block")
            .source_representation(),
        "wbfs"
    );
}
