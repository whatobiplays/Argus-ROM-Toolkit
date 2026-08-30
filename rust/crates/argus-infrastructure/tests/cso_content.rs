use std::io::Write;

use argus_application::{ContentType, PlatformId, TransformationBudget};
use argus_infrastructure::content::{
    ContentReadError, ContentReader, OpticalError, ParsingSession, recognize_cso,
    recognize_native_optical,
};
use flate2::{Compression, write::DeflateEncoder};
use tempfile::tempdir;

const ISO_SECTOR_BYTES: usize = 2_048;

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
    recognize_cso(&mut reader, &mut session)
}

fn set_u32_le(bytes: &mut [u8], offset: usize, value: u32) {
    bytes[offset..offset + 4].copy_from_slice(&value.to_le_bytes());
}

fn set_iso_both_u16(bytes: &mut [u8], offset: usize, value: u16) {
    bytes[offset..offset + 2].copy_from_slice(&value.to_le_bytes());
    bytes[offset + 2..offset + 4].copy_from_slice(&value.to_be_bytes());
}

fn set_iso_both_u32(bytes: &mut [u8], offset: usize, value: u32) {
    bytes[offset..offset + 4].copy_from_slice(&value.to_le_bytes());
    bytes[offset + 4..offset + 8].copy_from_slice(&value.to_be_bytes());
}

fn write_iso_dir_record(
    image: &mut [u8],
    offset: usize,
    name: &[u8],
    extent: u32,
    size: u32,
    flags: u8,
) -> usize {
    let record_length = 33 + name.len() + usize::from(name.len().is_multiple_of(2));
    image[offset..offset + record_length].fill(0);
    image[offset] = record_length as u8;
    set_iso_both_u32(&mut image[offset..], 2, extent);
    set_iso_both_u32(&mut image[offset..], 10, size);
    image[offset + 25] = flags;
    image[offset + 28..offset + 30].copy_from_slice(&1_u16.to_le_bytes());
    image[offset + 30..offset + 32].copy_from_slice(&1_u16.to_be_bytes());
    image[offset + 32] = name.len() as u8;
    image[offset + 33..offset + 33 + name.len()].copy_from_slice(name);
    record_length
}

fn base_iso(sector_count: usize) -> Vec<u8> {
    let mut image = vec![0_u8; sector_count * ISO_SECTOR_BYTES];
    let pvd_offset = 16 * ISO_SECTOR_BYTES;
    image[pvd_offset] = 1;
    image[pvd_offset + 1..pvd_offset + 6].copy_from_slice(b"CD001");
    image[pvd_offset + 6] = 1;
    image[pvd_offset + 40..pvd_offset + 48].copy_from_slice(b"ARGUSISO");
    set_iso_both_u32(&mut image[pvd_offset..], 80, sector_count as u32);
    set_iso_both_u16(&mut image[pvd_offset..], 120, 1);
    set_iso_both_u16(&mut image[pvd_offset..], 124, 1);
    set_iso_both_u16(&mut image[pvd_offset..], 128, ISO_SECTOR_BYTES as u16);
    set_iso_both_u32(&mut image[pvd_offset..], 132, 10);
    set_u32_le(&mut image[pvd_offset..], 140, 18);
    image[pvd_offset + 148..pvd_offset + 152].copy_from_slice(&18_u32.to_be_bytes());
    write_iso_dir_record(
        &mut image,
        pvd_offset + 156,
        &[0],
        20,
        ISO_SECTOR_BYTES as u32,
        0x02,
    );
    let terminator_offset = 17 * ISO_SECTOR_BYTES;
    image[terminator_offset] = 0xff;
    image[terminator_offset + 1..terminator_offset + 6].copy_from_slice(b"CD001");
    image[terminator_offset + 6] = 1;
    let path_table_offset = 18 * ISO_SECTOR_BYTES;
    image[path_table_offset] = 1;
    set_u32_le(&mut image[path_table_offset..], 2, 20);
    image[path_table_offset + 6..path_table_offset + 8].copy_from_slice(&1_u16.to_le_bytes());
    image
}

fn psp_param_sfo() -> Vec<u8> {
    let bootable = 1_u32.to_le_bytes();
    let values = [
        ("DISC_ID", b"ULUS-00000\0".as_slice(), 0x0204_u16),
        ("BOOTABLE", bootable.as_slice(), 0x0404_u16),
        ("CATEGORY", b"UG\0".as_slice(), 0x0204_u16),
        ("PSP_SYSTEM_VER", b"6.61\0".as_slice(), 0x0204_u16),
    ];
    let key_bytes: Vec<u8> = values
        .iter()
        .flat_map(|(key, _, _)| key.as_bytes().iter().copied().chain(std::iter::once(0)))
        .collect();
    let key_start = 20 + values.len() * 16;
    let data_start = key_start + key_bytes.len();
    let data_bytes: usize = values.iter().map(|(_, value, _)| value.len()).sum();
    let mut result = vec![0_u8; data_start + data_bytes];
    result[..4].copy_from_slice(b"\0PSF");
    set_u32_le(&mut result, 8, key_start as u32);
    set_u32_le(&mut result, 12, data_start as u32);
    set_u32_le(&mut result, 16, values.len() as u32);
    result[key_start..data_start].copy_from_slice(&key_bytes);
    let mut key_offset = 0_u16;
    let mut data_offset = 0_u32;
    for (index, (_, value, value_type)) in values.iter().enumerate() {
        let entry_offset = 20 + index * 16;
        result[entry_offset..entry_offset + 2].copy_from_slice(&key_offset.to_le_bytes());
        result[entry_offset + 2..entry_offset + 4].copy_from_slice(&value_type.to_le_bytes());
        set_u32_le(&mut result, entry_offset + 4, value.len() as u32);
        set_u32_le(&mut result, entry_offset + 8, value.len() as u32);
        set_u32_le(&mut result, entry_offset + 12, data_offset);
        let start = data_start + data_offset as usize;
        result[start..start + value.len()].copy_from_slice(value);
        key_offset += values[index].0.len() as u16 + 1;
        data_offset += value.len() as u32;
    }
    result
}

fn build_psp_iso() -> Vec<u8> {
    let mut image = base_iso(64);
    let param = psp_param_sfo();
    let eboot = vec![0_u8; 0x100];
    let umd_data = b"ULUS-00000\n";
    let root = 20 * ISO_SECTOR_BYTES;
    let mut cursor = root;
    cursor += write_iso_dir_record(&mut image, cursor, &[0], 20, 2048, 2);
    cursor += write_iso_dir_record(&mut image, cursor, &[1], 20, 2048, 2);
    cursor += write_iso_dir_record(&mut image, cursor, b"PSP_GAME", 21, 2048, 2);
    cursor += write_iso_dir_record(
        &mut image,
        cursor,
        b"UMD_DATA.BIN;1",
        25,
        umd_data.len() as u32,
        0,
    );
    let directory = vec![
        (
            21_u32,
            vec![
                (b"PARAM.SFO;1".as_slice(), 22_u32, param.len() as u32, 0),
                (b"SYSDIR".as_slice(), 23_u32, 2048, 2),
            ],
        ),
        (
            23_u32,
            vec![(b"EBOOT.BIN;1".as_slice(), 24_u32, eboot.len() as u32, 0)],
        ),
    ];
    image[22 * ISO_SECTOR_BYTES..22 * ISO_SECTOR_BYTES + param.len()].copy_from_slice(&param);
    image[24 * ISO_SECTOR_BYTES..24 * ISO_SECTOR_BYTES + eboot.len()].copy_from_slice(&eboot);
    image[25 * ISO_SECTOR_BYTES..25 * ISO_SECTOR_BYTES + umd_data.len()].copy_from_slice(umd_data);
    for (extent, entries) in directory {
        let mut offset = extent as usize * ISO_SECTOR_BYTES;
        image[offset..offset + ISO_SECTOR_BYTES].fill(0);
        offset += write_iso_dir_record(&mut image, offset, &[0], extent, 2048, 2);
        offset += write_iso_dir_record(&mut image, offset, &[1], extent, 2048, 2);
        for (name, entry_extent, size, flags) in entries {
            offset += write_iso_dir_record(&mut image, offset, name, entry_extent, size, flags);
        }
        assert!(offset <= extent as usize * ISO_SECTOR_BYTES + ISO_SECTOR_BYTES);
    }
    let _ = cursor;
    image
}

fn cso_image(logical: &[u8], plain_blocks: &[usize], align: u8) -> Vec<u8> {
    assert!(logical.len().is_multiple_of(ISO_SECTOR_BYTES));
    assert!(align < 16);
    let block_count = logical.len() / ISO_SECTOR_BYTES;
    let unit = 1_usize << align;
    let index_bytes = (block_count + 1) * 4;
    let payload_start = (24 + index_bytes).div_ceil(unit) * unit;
    let mut result = vec![0_u8; payload_start];
    let mut indexes = Vec::with_capacity(block_count + 1);
    for block in 0..block_count {
        let data = &logical[block * ISO_SECTOR_BYTES..(block + 1) * ISO_SECTOR_BYTES];
        let mut compressed = DeflateEncoder::new(Vec::new(), Compression::fast());
        compressed.write_all(data).expect("compress");
        let compressed = compressed.finish().expect("finish compression");
        let plain = plain_blocks.contains(&block) || compressed.len() >= data.len();
        while !result.len().is_multiple_of(unit) {
            result.push(0);
        }
        let offset = result.len() / unit;
        indexes.push((offset as u32) | if plain { 0x8000_0000 } else { 0 });
        if plain {
            result.extend_from_slice(data);
        } else {
            result.extend_from_slice(&compressed);
        }
    }
    while !result.len().is_multiple_of(unit) {
        result.push(0);
    }
    indexes.push((result.len() / unit) as u32);

    let mut header = vec![0_u8; 24];
    header[..4].copy_from_slice(b"CISO");
    header[4..8].copy_from_slice(&24_u32.to_le_bytes());
    header[8..16].copy_from_slice(&(logical.len() as u64).to_le_bytes());
    header[16..20].copy_from_slice(&(ISO_SECTOR_BYTES as u32).to_le_bytes());
    header[20] = 1;
    header[21] = align;
    result[..24].copy_from_slice(&header);
    for (index, value) in indexes.into_iter().enumerate() {
        result[24 + index * 4..28 + index * 4].copy_from_slice(&value.to_le_bytes());
    }
    result
}

#[test]
fn cso_plain_and_deflate_blocks_reuse_psp_identity() {
    let native_bytes = build_psp_iso();
    let mut native = MemoryReader::new(native_bytes.clone());
    let expected = recognize_native_optical(&mut native).expect("native UMD");
    let cso = cso_image(&native_bytes, &[0, 4], 0);
    let actual = recognize(cso, 10_000_000).expect("CSO UMD");
    assert_eq!(expected.platform(), PlatformId::SonyPsp);
    assert_eq!(expected.content_type(), ContentType::OpticalDiscUmd);
    assert_eq!(actual.platform(), PlatformId::SonyPsp);
    assert_eq!(actual.content_type(), ContentType::OpticalDiscUmd);
    assert_eq!(actual.identity_digest(), expected.identity_digest());
    assert_eq!(actual.source_representation(), "cso");
}

#[test]
fn cso_nonzero_index_alignment_and_eof_are_validated() {
    let native_bytes = build_psp_iso();
    let cso = cso_image(&native_bytes, &[0, 4], 2);
    let actual = recognize(cso, 10_000_000).expect("aligned CSO");
    assert_eq!(actual.source_representation(), "cso");

    let mut truncated = cso_image(&native_bytes, &[], 0);
    truncated.truncate(truncated.len() - 1);
    assert!(matches!(
        recognize(truncated, 10_000_000),
        Err(OpticalError::Malformed | OpticalError::Truncated | OpticalError::ReadFailure)
    ));
}

#[test]
fn cso_plain_blocks_allow_alignment_padding_between_blocks() {
    let native_bytes = build_psp_iso();
    let all_blocks = (0..native_bytes.len() / ISO_SECTOR_BYTES).collect::<Vec<_>>();
    let cso = cso_image(&native_bytes, &all_blocks, 12);

    let mut native = MemoryReader::new(native_bytes);
    let expected = recognize_native_optical(&mut native).expect("native UMD");
    let actual = recognize(cso, 10_000_000).expect("plain aligned CSO");
    assert_eq!(expected.platform(), PlatformId::SonyPsp);
    assert_eq!(expected.content_type(), ContentType::OpticalDiscUmd);
    assert_eq!(actual.platform(), PlatformId::SonyPsp);
    assert_eq!(actual.content_type(), ContentType::OpticalDiscUmd);
    assert_eq!(actual.identity_digest(), expected.identity_digest());
    assert_eq!(actual.source_representation(), "cso");
}

#[test]
fn cso_rejects_impossible_index_order() {
    let native_bytes = build_psp_iso();
    let mut cso = cso_image(&native_bytes, &[], 0);
    let first = u32::from_le_bytes(cso[24..28].try_into().expect("index"));
    cso[28..32].copy_from_slice(&first.saturating_sub(1).to_le_bytes());
    assert!(matches!(
        recognize(cso, 10_000_000),
        Err(OpticalError::Malformed | OpticalError::Truncated)
    ));
}

#[test]
fn cso_cancellation_and_work_budget_are_terminal() {
    let native_bytes = build_psp_iso();
    let staging = tempdir().expect("staging");
    let mut cancelled = ParsingSession::for_tests(budget(10_000_000), staging.path(), || true);
    let mut reader = MemoryReader::new(cso_image(&native_bytes, &[], 0));
    assert_eq!(
        recognize_cso(&mut reader, &mut cancelled),
        Err(OpticalError::Cancelled)
    );
    assert!(matches!(
        recognize(cso_image(&native_bytes, &[], 0), 1),
        Err(OpticalError::ResourceLimitExceeded)
    ));
}
