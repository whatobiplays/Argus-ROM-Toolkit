//! Safe WBFS sparse-disc recognition.
//!
//! WBFS stores a Wii disc as fixed-size logical blocks addressed by a
//! big-endian WLBA table.  This adapter validates the container geometry and
//! allocation map, then hashes only the allocated logical extents through the
//! existing Wii sparse identity envelope.  WBFS metadata and absent blocks are
//! never treated as game payload.

use std::collections::BTreeSet;
use std::fs::File;
use std::io::{self, Read, Seek, SeekFrom};

use argus_application::{ContentType, PlatformId, TransformationFailure};

use super::content_optical::{OpticalError, OpticalRecognition, WII_PREFIX, finish_recognition};
use super::content_session::ParsingSession;
use super::content_stream::{CanonicalHasher, ContentReader, update_u32, update_u64};

const WBFS_HEADER_BYTES: u64 = 12;
const WBFS_HEADER_MIN_SECTOR_SHIFT: u8 = 9;
const WBFS_DISC_INFO_HEADER_BYTES: u64 = 0x100;
const WII_SECTOR_BYTES: u64 = 0x8000;
const WII_SECTORS_PER_MAX_DISC: u64 = 143_432 * 2;
const MAX_WBFS_METADATA_BYTES: u64 = 16 * 1024 * 1024;
const MAX_WBFS_BLOCK_BYTES: u64 = 64 * 1024 * 1024;
const STREAM_CHUNK_BYTES: usize = 64 * 1024;

/// Recognizes one Wii WBFS sparse logical disc.
///
/// The input is staged before validation so all metadata and payload reads use
/// one stable operation-scoped representation.  The returned identity is
/// based on the logical capacity, ordered allocated extents, and exact bytes
/// in those extents only.
pub fn recognize_wbfs(
    reader: &mut dyn ContentReader,
    session: &mut ParsingSession<'_>,
) -> Result<OpticalRecognition, OpticalError> {
    session.check_cancelled().map_err(map_session_error)?;
    let staged = session
        .stage_content_reader("wbfs", reader)
        .map_err(map_session_error)?;
    let mut file = staged.reopen().map_err(|_| OpticalError::ReadFailure)?;
    let layout = parse_layout(&mut file, staged.len(), session)?;

    session
        .charge_expanded(
            layout
                .extents
                .iter()
                .map(|extent| extent.byte_len)
                .sum::<u64>(),
        )
        .map_err(map_session_error)?;
    let mut hasher = CanonicalHasher::new();
    hasher.update(WII_PREFIX);
    update_u64(&mut hasher, layout.logical_length);
    update_u32(
        &mut hasher,
        u32::try_from(layout.extents.len()).map_err(|_| OpticalError::ResourceLimitExceeded)?,
    );
    for extent in &layout.extents {
        session.check_cancelled().map_err(map_session_error)?;
        update_u64(&mut hasher, extent.logical_offset);
        update_u64(&mut hasher, extent.byte_len);
        hash_file_range(
            &mut file,
            staged.len(),
            extent.physical_offset,
            extent.byte_len,
            &mut hasher,
            session,
        )?;
    }
    Ok(finish_recognition(
        PlatformId::NintendoWii,
        ContentType::OpticalDiscWii,
        "wbfs",
        hasher,
    ))
}

#[derive(Clone, Copy, Debug, Eq, Ord, PartialEq, PartialOrd)]
struct PreservedExtent {
    logical_offset: u64,
    byte_len: u64,
    physical_offset: u64,
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct WbfsLayout {
    logical_length: u64,
    extents: Vec<PreservedExtent>,
}

fn parse_layout(
    file: &mut File,
    source_length: u64,
    session: &mut ParsingSession<'_>,
) -> Result<WbfsLayout, OpticalError> {
    if source_length < WBFS_HEADER_BYTES {
        return Err(OpticalError::Truncated);
    }
    session
        .charge_parser_work(WBFS_HEADER_BYTES)
        .map_err(map_session_error)?;
    let header = read_file_range(file, source_length, 0, WBFS_HEADER_BYTES)?;
    if &header[..4] != b"WBFS" {
        return Err(OpticalError::UnsupportedRepresentation);
    }
    let n_hd_sec = u64::from(read_u32_be(&header, 4)?);
    let hd_sec_shift = header[8];
    let wbfs_sec_shift = header[9];
    if !(WBFS_HEADER_MIN_SECTOR_SHIFT..63).contains(&hd_sec_shift)
        || !(15..63).contains(&wbfs_sec_shift)
        || wbfs_sec_shift < hd_sec_shift
    {
        return Err(OpticalError::Malformed);
    }
    let hd_sec_bytes = 1_u64
        .checked_shl(u32::from(hd_sec_shift))
        .ok_or(OpticalError::ResourceLimitExceeded)?;
    let wbfs_sec_bytes = 1_u64
        .checked_shl(u32::from(wbfs_sec_shift))
        .ok_or(OpticalError::ResourceLimitExceeded)?;
    if wbfs_sec_bytes > MAX_WBFS_BLOCK_BYTES || !wbfs_sec_bytes.is_multiple_of(WII_SECTOR_BYTES) {
        return Err(OpticalError::ResourceLimitExceeded);
    }
    let declared_length = n_hd_sec
        .checked_mul(hd_sec_bytes)
        .ok_or(OpticalError::ResourceLimitExceeded)?;
    if n_hd_sec == 0
        || declared_length != source_length
        || !source_length.is_multiple_of(hd_sec_bytes)
    {
        return Err(OpticalError::Malformed);
    }

    let shift_delta = u32::from(wbfs_sec_shift - 15);
    let n_wii_sec = n_hd_sec
        .checked_mul(hd_sec_bytes)
        .and_then(|bytes| bytes.checked_div(WII_SECTOR_BYTES))
        .ok_or(OpticalError::ResourceLimitExceeded)?;
    let n_wbfs_sec = n_wii_sec
        .checked_shr(shift_delta)
        .ok_or(OpticalError::ResourceLimitExceeded)?;
    let n_wbfs_sec_per_disc = WII_SECTORS_PER_MAX_DISC
        .checked_shr(shift_delta)
        .ok_or(OpticalError::ResourceLimitExceeded)?;
    if n_wbfs_sec < 2 || n_wbfs_sec > u64::from(u16::MAX) || n_wbfs_sec_per_disc == 0 {
        return Err(OpticalError::Malformed);
    }

    let disc_info_bytes = WBFS_DISC_INFO_HEADER_BYTES
        .checked_add(
            n_wbfs_sec_per_disc
                .checked_mul(2)
                .ok_or(OpticalError::ResourceLimitExceeded)?,
        )
        .and_then(|bytes| align_up(bytes, hd_sec_bytes))
        .ok_or(OpticalError::ResourceLimitExceeded)?;
    if disc_info_bytes > MAX_WBFS_METADATA_BYTES {
        return Err(OpticalError::ResourceLimitExceeded);
    }
    let free_table_bytes = (n_wbfs_sec / 8).max(1);
    if free_table_bytes >= wbfs_sec_bytes {
        return Err(OpticalError::Malformed);
    }
    let free_table_lba = (wbfs_sec_bytes - free_table_bytes) / hd_sec_bytes;
    let disc_info_lba = disc_info_bytes / hd_sec_bytes;
    if free_table_lba <= 1 || disc_info_lba == 0 {
        return Err(OpticalError::Malformed);
    }
    let max_disc_from_free_table = (free_table_lba - 1) / disc_info_lba;
    let max_disc_from_header = hd_sec_bytes
        .checked_sub(WBFS_HEADER_BYTES)
        .ok_or(OpticalError::Malformed)?;
    let max_disc = max_disc_from_free_table.min(max_disc_from_header);
    if max_disc == 0 || max_disc > usize::MAX as u64 {
        return Err(OpticalError::Malformed);
    }

    let header_length = WBFS_HEADER_BYTES
        .checked_add(max_disc)
        .ok_or(OpticalError::ResourceLimitExceeded)?;
    session
        .charge_parser_work(max_disc)
        .map_err(map_session_error)?;
    let header = read_file_range(file, source_length, 0, header_length)?;
    let mut occupied = Vec::new();
    for index in 0..usize::try_from(max_disc).map_err(|_| OpticalError::ResourceLimitExceeded)? {
        if header
            .get(usize::try_from(WBFS_HEADER_BYTES).expect("header size") + index)
            .is_some_and(|value| *value != 0)
        {
            occupied.push(index);
        }
    }
    if occupied.is_empty() {
        return Err(OpticalError::Malformed);
    }
    if occupied.len() != 1 {
        return Err(OpticalError::UnsupportedRepresentation);
    }
    let disc_index = occupied[0] as u64;
    let disc_offset = hd_sec_bytes
        .checked_add(
            disc_index
                .checked_mul(disc_info_bytes)
                .ok_or(OpticalError::ResourceLimitExceeded)?,
        )
        .ok_or(OpticalError::ResourceLimitExceeded)?;
    session
        .charge_parser_work(disc_info_bytes)
        .map_err(map_session_error)?;
    let disc = read_file_range(file, source_length, disc_offset, disc_info_bytes)?;
    let table_start = usize::try_from(WBFS_DISC_INFO_HEADER_BYTES).expect("WLBA offset");
    let table_count =
        usize::try_from(n_wbfs_sec_per_disc).map_err(|_| OpticalError::ResourceLimitExceeded)?;
    let table_end = table_start
        .checked_add(
            table_count
                .checked_mul(2)
                .ok_or(OpticalError::ResourceLimitExceeded)?,
        )
        .ok_or(OpticalError::ResourceLimitExceeded)?;
    if table_end > disc.len() {
        return Err(OpticalError::Malformed);
    }
    let first_physical_block = u16::from_be_bytes(
        disc[table_start..table_start + 2]
            .try_into()
            .expect("first WLBA entry"),
    );
    if first_physical_block == 0 {
        return Err(OpticalError::Malformed);
    }
    if &disc[0x18..0x1c] != [0x5d, 0x1c, 0x9e, 0xa3].as_slice()
        || disc[..6].iter().all(|byte| *byte == 0)
    {
        return Err(OpticalError::Malformed);
    }
    let mut used_physical = BTreeSet::new();
    let mut extents: Vec<PreservedExtent> = Vec::new();
    for logical_block in 0..table_count {
        session.charge_parser_work(1).map_err(map_session_error)?;
        let physical_block = u64::from(u16::from_be_bytes(
            disc[table_start + logical_block * 2..table_start + logical_block * 2 + 2]
                .try_into()
                .expect("WLBA entry"),
        ));
        if physical_block == 0 {
            continue;
        }
        if physical_block >= n_wbfs_sec || !used_physical.insert(physical_block) {
            return Err(OpticalError::Malformed);
        }
        let logical_offset = (logical_block as u64)
            .checked_mul(wbfs_sec_bytes)
            .ok_or(OpticalError::ResourceLimitExceeded)?;
        let physical_offset = physical_block
            .checked_mul(wbfs_sec_bytes)
            .ok_or(OpticalError::ResourceLimitExceeded)?;
        if physical_offset
            .checked_add(wbfs_sec_bytes)
            .is_none_or(|end| end > source_length)
        {
            return Err(OpticalError::Truncated);
        }
        let extent = PreservedExtent {
            logical_offset,
            byte_len: wbfs_sec_bytes,
            physical_offset,
        };
        if let Some(previous) = extents.last_mut()
            && previous.logical_offset + previous.byte_len == extent.logical_offset
            && previous.physical_offset + previous.byte_len == extent.physical_offset
        {
            previous.byte_len = previous
                .byte_len
                .checked_add(extent.byte_len)
                .ok_or(OpticalError::ResourceLimitExceeded)?;
        } else {
            extents.push(extent);
        }
    }
    if extents.is_empty() {
        return Err(OpticalError::Malformed);
    }
    Ok(WbfsLayout {
        logical_length: n_wbfs_sec_per_disc
            .checked_mul(wbfs_sec_bytes)
            .ok_or(OpticalError::ResourceLimitExceeded)?,
        extents,
    })
}

fn hash_file_range(
    file: &mut File,
    source_length: u64,
    offset: u64,
    length: u64,
    hasher: &mut CanonicalHasher,
    session: &mut ParsingSession<'_>,
) -> Result<(), OpticalError> {
    let end = offset
        .checked_add(length)
        .ok_or(OpticalError::ResourceLimitExceeded)?;
    if end > source_length {
        return Err(OpticalError::Truncated);
    }
    file.seek(SeekFrom::Start(offset))
        .map_err(|_| OpticalError::ReadFailure)?;
    let mut buffer = [0_u8; STREAM_CHUNK_BYTES];
    let mut remaining = length;
    while remaining > 0 {
        session.check_cancelled().map_err(map_session_error)?;
        let count = remaining.min(buffer.len() as u64) as usize;
        file.read_exact(&mut buffer[..count])
            .map_err(map_io_error)?;
        hasher.update(&buffer[..count]);
        session
            .charge_parser_work(count as u64)
            .map_err(map_session_error)?;
        remaining -= count as u64;
    }
    Ok(())
}

fn read_file_range(
    file: &mut File,
    source_length: u64,
    offset: u64,
    length: u64,
) -> Result<Vec<u8>, OpticalError> {
    let end = offset
        .checked_add(length)
        .ok_or(OpticalError::ResourceLimitExceeded)?;
    if end > source_length {
        return Err(OpticalError::Truncated);
    }
    let length = usize::try_from(length).map_err(|_| OpticalError::ResourceLimitExceeded)?;
    let mut bytes = vec![0_u8; length];
    file.seek(SeekFrom::Start(offset))
        .map_err(|_| OpticalError::ReadFailure)?;
    file.read_exact(&mut bytes).map_err(map_io_error)?;
    Ok(bytes)
}

fn align_up(value: u64, alignment: u64) -> Option<u64> {
    if alignment == 0 {
        return None;
    }
    let remainder = value % alignment;
    if remainder == 0 {
        Some(value)
    } else {
        value.checked_add(alignment - remainder)
    }
}

fn read_u32_be(bytes: &[u8], offset: usize) -> Result<u32, OpticalError> {
    let end = offset
        .checked_add(4)
        .ok_or(OpticalError::ResourceLimitExceeded)?;
    let value = bytes.get(offset..end).ok_or(OpticalError::Truncated)?;
    Ok(u32::from_be_bytes(value.try_into().expect("u32 field")))
}

fn map_io_error(error: io::Error) -> OpticalError {
    if error.kind() == io::ErrorKind::UnexpectedEof {
        OpticalError::Truncated
    } else {
        OpticalError::ReadFailure
    }
}

fn map_session_error(error: TransformationFailure) -> OpticalError {
    match error {
        TransformationFailure::Cancelled => OpticalError::Cancelled,
        TransformationFailure::ResourceLimitExceeded => OpticalError::ResourceLimitExceeded,
        TransformationFailure::ReadFailure => OpticalError::ReadFailure,
        _ => OpticalError::Malformed,
    }
}
