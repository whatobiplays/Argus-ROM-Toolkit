//! Safe structural RVZ/WIA decoding for complete GameCube and Wii images.
//!
//! RVZ is a transport format. This adapter validates its metadata, reconstructs
//! raw groups, and reconstitutes Wii partition hash/encryption blocks before
//! exposing the logical disc to the existing native optical recognizer.

use aes::Aes128;
use aes::cipher::{BlockEncrypt, KeyInit};
use std::fs::File;
use std::io::{self, Cursor, Read, Seek, SeekFrom};

use argus_application::{ContentType, PlatformId, TransformationFailure};
use oxiarc_lzma::{Lzma2Decoder, LzmaProperties};
use ruzstd::decoding::StreamingDecoder;
use sha1::{Digest as Sha1Digest, Sha1};

use super::content_optical::{
    OpticalError, OpticalRecognition, recognize_native_optical_with_cancel,
};
use super::content_session::ParsingSession;
use super::content_stream::{ContentReadError, ContentReader};

const RVZ_FILE_HEAD_BYTES: usize = 0x48;
const RVZ_DISC_BYTES: usize = 0xdc;
const RVZ_RAW_DATA_BYTES: usize = 24;
const RVZ_GROUP_BYTES: usize = 12;
const RVZ_DHEAD_BYTES: usize = 0x80;
const RVZ_MIN_CHUNK_BYTES: u64 = 32 * 1024;
const RVZ_LARGE_CHUNK_BOUNDARY: u64 = 2 * 1024 * 1024;
const RVZ_MAX_CHUNK_BYTES: u64 = 16 * 1024 * 1024;
const RVZ_MAX_METADATA_BYTES: u64 = 16 * 1024 * 1024;
const RVZ_MAX_LZMA_DICTIONARY_BYTES: u32 = 256 * 1024 * 1024;
const RVZ_COMPRESSED_FLAG: u32 = 0x8000_0000;
const RVZ_SIZE_MASK: u32 = 0x7fff_ffff;
const RVZ_EXCEPTION_BYTES: usize = 0x16;
const RVZ_MAX_EXCEPTIONS_PER_LIST: usize = 4_096;
const WII_BLOCK_HEADER_BYTES: usize = 0x400;
const WII_BLOCK_DATA_BYTES: usize = 0x7c00;
const WII_BLOCK_TOTAL_BYTES: usize = 0x8000;
const WII_BLOCKS_PER_GROUP: usize = 0x40;
const WII_GROUP_TOTAL_BYTES: usize = WII_BLOCK_TOTAL_BYTES * WII_BLOCKS_PER_GROUP;

/// Recognizes one complete GameCube or Wii RVZ/WIA logical disc.
///
/// The source is staged first so the parser sees a stable seekable file.  The
/// logical groups remain disk-backed and are decoded on demand while the
/// existing native optical recognizer performs platform validation and
/// canonical hashing.
pub fn recognize_rvz(
    reader: &mut dyn ContentReader,
    session: &mut ParsingSession<'_>,
) -> Result<OpticalRecognition, OpticalError> {
    session.check_cancelled().map_err(map_session_error)?;
    let staged = session
        .stage_content_reader("rvz", reader)
        .map_err(map_session_error)?;
    let mut file = staged.reopen().map_err(|_| OpticalError::ReadFailure)?;
    let layout = parse_layout(&mut file, staged.len(), session)?;

    let cancelled = || session.check_cancelled().is_err();
    let mut decoded = RvzReader::new(file, layout, &cancelled);
    let mut dhead = [0_u8; RVZ_DHEAD_BYTES];
    read_content_exact(&mut decoded, 0, &mut dhead, &cancelled)?;
    if dhead != decoded.layout.dhead {
        return Err(OpticalError::Malformed);
    }
    let recognition = recognize_native_optical_with_cancel(&mut decoded, &cancelled);
    if let Some(error) = decoded.take_failure() {
        return Err(error);
    }
    let recognition = recognition?;
    let expected_platform = match decoded.layout.disc_type {
        1 => PlatformId::NintendoGameCube,
        2 => PlatformId::NintendoWii,
        _ => return Err(OpticalError::Malformed),
    };
    if recognition.platform() != expected_platform
        || !matches!(
            recognition.content_type(),
            ContentType::OpticalDiscGameCube | ContentType::OpticalDiscWii
        )
    {
        return Err(OpticalError::UnsupportedRepresentation);
    }
    Ok(recognition.with_source_representation("rvz"))
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum RvzCodec {
    None,
    Bzip2,
    Lzma,
    Lzma2,
    Zstd,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct RvzGroup {
    data_offset: u64,
    data_size: u64,
    compressed: bool,
    packed_size: u64,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct RvzSpan {
    logical_offset: u64,
    logical_size: u64,
    group_index: usize,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct RvzPartitionData {
    first_sector: u64,
    sector_count: u64,
    group_index: usize,
    group_count: usize,
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct RvzPartition {
    key: [u8; 16],
    first_sector: u64,
    total_sectors: u64,
    data: [Option<RvzPartitionData>; 2],
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct RvzException {
    hash_group_index: u64,
    offset: usize,
    hash: [u8; 20],
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct RvzLayout {
    logical_length: u64,
    disc_type: u32,
    codec: RvzCodec,
    chunk_size: u64,
    dhead: [u8; RVZ_DHEAD_BYTES],
    compressor_data: [u8; 7],
    groups: Vec<RvzGroup>,
    spans: Vec<RvzSpan>,
    partitions: Vec<RvzPartition>,
}

fn parse_layout(
    file: &mut File,
    source_length: u64,
    session: &mut ParsingSession<'_>,
) -> Result<RvzLayout, OpticalError> {
    if source_length < RVZ_FILE_HEAD_BYTES as u64 {
        return Err(OpticalError::Truncated);
    }
    let head = read_file_range(file, source_length, 0, RVZ_FILE_HEAD_BYTES as u64)?;
    if !matches!(head[..4], [b'W', b'I', b'A', 1] | [b'R', b'V', b'Z', 1]) {
        return Err(OpticalError::UnsupportedRepresentation);
    }
    if read_u32_be(&head, 8)? == 0 {
        return Err(OpticalError::Malformed);
    }
    if read_u32_be(&head, 12)? != RVZ_DISC_BYTES as u32 {
        return Err(OpticalError::UnsupportedRepresentation);
    }
    let disc_size = u64::from(read_u32_be(&head, 12)?);
    let logical_length = read_u64_be(&head, 0x20)?;
    if logical_length == 0 {
        return Err(OpticalError::Malformed);
    }
    let declared_file_length = read_u64_be(&head, 0x28)?;
    if declared_file_length != 0 && declared_file_length != source_length {
        return Err(OpticalError::Malformed);
    }
    verify_optional_sha1(&head[..0x34], &head[0x34..0x48])?;

    let disc = read_file_range(file, source_length, RVZ_FILE_HEAD_BYTES as u64, disc_size)?;
    verify_optional_sha1(&disc, &head[0x10..0x24])?;
    let disc_type = read_u32_be(&disc, 0)?;
    if !matches!(disc_type, 1 | 2) {
        return Err(OpticalError::UnsupportedRepresentation);
    }
    let codec = match read_u32_be(&disc, 4)? {
        0 => RvzCodec::None,
        1 => return Err(OpticalError::UnsupportedRepresentation),
        2 => RvzCodec::Bzip2,
        3 => RvzCodec::Lzma,
        4 => RvzCodec::Lzma2,
        5 => RvzCodec::Zstd,
        _ => return Err(OpticalError::UnsupportedRepresentation),
    };
    let chunk_size = u64::from(read_u32_be(&disc, 12)?);
    validate_chunk_size(chunk_size)?;
    let mut dhead = [0_u8; RVZ_DHEAD_BYTES];
    dhead.copy_from_slice(&disc[0x10..0x90]);

    let n_part = usize::try_from(read_u32_be(&disc, 0x90)?)
        .map_err(|_| OpticalError::ResourceLimitExceeded)?;
    if n_part > 64 {
        return Err(OpticalError::ResourceLimitExceeded);
    }
    let part_t_size = usize::try_from(read_u32_be(&disc, 0x94)?)
        .map_err(|_| OpticalError::ResourceLimitExceeded)?;
    let part_offset = read_u64_be(&disc, 0x98)?;
    let part_hash = &disc[0xa0..0xb4];
    let part_table = if n_part == 0 {
        if part_hash.iter().any(|byte| *byte != 0) {
            return Err(OpticalError::Malformed);
        }
        Vec::new()
    } else {
        if part_t_size == 0 {
            return Err(OpticalError::UnsupportedRepresentation);
        }
        let table_size = u64::try_from(
            n_part
                .checked_mul(part_t_size)
                .ok_or(OpticalError::ResourceLimitExceeded)?,
        )
        .map_err(|_| OpticalError::ResourceLimitExceeded)?;
        if table_size > RVZ_MAX_METADATA_BYTES {
            return Err(OpticalError::ResourceLimitExceeded);
        }
        let table = read_file_range(file, source_length, part_offset, table_size)?;
        verify_optional_sha1(&table, part_hash)?;
        table
    };
    let n_raw_data = usize::try_from(read_u32_be(&disc, 0xb4)?)
        .map_err(|_| OpticalError::ResourceLimitExceeded)?;
    let raw_data_offset = read_u64_be(&disc, 0xb8)?;
    let raw_data_size = u64::from(read_u32_be(&disc, 0xc0)?);
    let n_groups = usize::try_from(read_u32_be(&disc, 0xc4)?)
        .map_err(|_| OpticalError::ResourceLimitExceeded)?;
    let group_offset = read_u64_be(&disc, 0xc8)?;
    let group_size = u64::from(read_u32_be(&disc, 0xd0)?);
    let compressor_data_len = usize::from(disc[0xd4]);
    if compressor_data_len > disc[0xd5..0xdc].len()
        || !valid_compressor_data_length(codec, compressor_data_len)
    {
        return Err(OpticalError::Malformed);
    }
    let mut compressor_data = [0_u8; 7];
    compressor_data.copy_from_slice(&disc[0xd5..0xdc]);

    if n_raw_data == 0 || n_groups == 0 {
        return Err(OpticalError::Malformed);
    }
    let expected_raw_size = u64::try_from(
        n_raw_data
            .checked_mul(RVZ_RAW_DATA_BYTES)
            .ok_or(OpticalError::ResourceLimitExceeded)?,
    )
    .map_err(|_| OpticalError::ResourceLimitExceeded)?;
    let expected_group_size = u64::try_from(
        n_groups
            .checked_mul(RVZ_GROUP_BYTES)
            .ok_or(OpticalError::ResourceLimitExceeded)?,
    )
    .map_err(|_| OpticalError::ResourceLimitExceeded)?;
    if expected_raw_size > RVZ_MAX_METADATA_BYTES || expected_group_size > RVZ_MAX_METADATA_BYTES {
        return Err(OpticalError::ResourceLimitExceeded);
    }
    session
        .charge_parser_work(
            source_length
                .checked_add(raw_data_size)
                .and_then(|value| value.checked_add(group_size))
                .ok_or(OpticalError::ResourceLimitExceeded)?,
        )
        .map_err(map_session_error)?;
    session
        .charge_expanded(logical_length)
        .map_err(map_session_error)?;

    let raw_table = read_metadata_table(
        file,
        source_length,
        raw_data_offset,
        raw_data_size,
        expected_raw_size,
        codec,
        &compressor_data,
    )?;
    let group_table = read_metadata_table(
        file,
        source_length,
        group_offset,
        group_size,
        expected_group_size,
        codec,
        &compressor_data,
    )?;
    let groups = parse_groups(&group_table, source_length, n_groups)?;
    let spans = parse_raw_spans(&raw_table, logical_length, chunk_size, n_raw_data, n_groups)?;
    let partitions = parse_partitions(
        &part_table,
        n_part,
        part_t_size,
        logical_length,
        chunk_size,
        n_groups,
    )?;
    validate_group_references(&spans, &partitions, &groups, chunk_size)?;
    validate_logical_coverage(logical_length, &spans, &partitions)?;
    Ok(RvzLayout {
        logical_length,
        disc_type,
        codec,
        chunk_size,
        dhead,
        compressor_data,
        groups,
        spans,
        partitions,
    })
}

fn validate_chunk_size(chunk_size: u64) -> Result<(), OpticalError> {
    if !(RVZ_MIN_CHUNK_BYTES..=RVZ_MAX_CHUNK_BYTES).contains(&chunk_size) {
        return Err(OpticalError::ResourceLimitExceeded);
    }
    if !chunk_size.is_multiple_of(WII_BLOCK_TOTAL_BYTES as u64) {
        return Err(OpticalError::Malformed);
    }
    if chunk_size < RVZ_LARGE_CHUNK_BOUNDARY {
        if !chunk_size.is_power_of_two() {
            return Err(OpticalError::Malformed);
        }
    } else if !chunk_size.is_multiple_of(RVZ_LARGE_CHUNK_BOUNDARY) {
        return Err(OpticalError::Malformed);
    }
    Ok(())
}

fn valid_compressor_data_length(codec: RvzCodec, length: usize) -> bool {
    match codec {
        RvzCodec::None | RvzCodec::Bzip2 | RvzCodec::Zstd => length == 0,
        RvzCodec::Lzma => length == 5,
        RvzCodec::Lzma2 => length == 1,
    }
}

fn read_metadata_table(
    file: &mut File,
    source_length: u64,
    offset: u64,
    stored_size: u64,
    expected_size: u64,
    codec: RvzCodec,
    compressor_data: &[u8; 7],
) -> Result<Vec<u8>, OpticalError> {
    if stored_size == 0 || stored_size > RVZ_MAX_METADATA_BYTES {
        return Err(OpticalError::Malformed);
    }
    let stored = read_file_range(file, source_length, offset, stored_size)?;
    if codec == RvzCodec::None {
        if stored_size != expected_size {
            return Err(OpticalError::Malformed);
        }
        return Ok(stored);
    }
    decode_compressed_payload(codec, &stored, expected_size, compressor_data)
}

fn parse_groups(
    table: &[u8],
    source_length: u64,
    count: usize,
) -> Result<Vec<RvzGroup>, OpticalError> {
    let expected = count
        .checked_mul(RVZ_GROUP_BYTES)
        .ok_or(OpticalError::ResourceLimitExceeded)?;
    if table.len() != expected {
        return Err(OpticalError::Malformed);
    }
    let mut groups = Vec::with_capacity(count);
    let mut ranges = Vec::with_capacity(count);
    for index in 0..count {
        let offset = index * RVZ_GROUP_BYTES;
        let data_offset = u64::from(read_u32_be(table, offset)?)
            .checked_mul(4)
            .ok_or(OpticalError::ResourceLimitExceeded)?;
        let data_descriptor = read_u32_be(table, offset + 4)?;
        let data_size = u64::from(data_descriptor & RVZ_SIZE_MASK);
        let compressed = data_descriptor & RVZ_COMPRESSED_FLAG != 0;
        let packed_size = u64::from(read_u32_be(table, offset + 8)?);
        if packed_size > RVZ_MAX_CHUNK_BYTES {
            return Err(OpticalError::ResourceLimitExceeded);
        }
        if data_size != 0 {
            if data_size > RVZ_MAX_CHUNK_BYTES {
                return Err(OpticalError::ResourceLimitExceeded);
            }
            let end = data_offset
                .checked_add(data_size)
                .ok_or(OpticalError::ResourceLimitExceeded)?;
            if end > source_length {
                return Err(OpticalError::Truncated);
            }
            ranges.push((data_offset, end));
        } else if packed_size != 0 {
            return Err(OpticalError::Malformed);
        }
        groups.push(RvzGroup {
            data_offset,
            data_size,
            compressed,
            packed_size,
        });
    }
    ranges.sort_unstable();
    if ranges.windows(2).any(|pair| pair[0].1 > pair[1].0) {
        return Err(OpticalError::Malformed);
    }
    Ok(groups)
}

fn parse_raw_spans(
    table: &[u8],
    logical_length: u64,
    chunk_size: u64,
    count: usize,
    total_group_count: usize,
) -> Result<Vec<RvzSpan>, OpticalError> {
    if table.len()
        != count
            .checked_mul(RVZ_RAW_DATA_BYTES)
            .ok_or(OpticalError::ResourceLimitExceeded)?
    {
        return Err(OpticalError::Malformed);
    }
    let mut spans = Vec::new();
    for index in 0..count {
        let offset = index * RVZ_RAW_DATA_BYTES;
        let raw_logical_offset = read_u64_be(table, offset)?;
        let raw_logical_size = read_u64_be(table, offset + 8)?;
        let group_index = usize::try_from(read_u32_be(table, offset + 16)?)
            .map_err(|_| OpticalError::ResourceLimitExceeded)?;
        let entry_group_count = usize::try_from(read_u32_be(table, offset + 20)?)
            .map_err(|_| OpticalError::ResourceLimitExceeded)?;
        if raw_logical_size == 0 || entry_group_count == 0 {
            return Err(OpticalError::Malformed);
        }
        let skipped = raw_logical_offset % WII_BLOCK_TOTAL_BYTES as u64;
        let logical_offset = raw_logical_offset
            .checked_sub(skipped)
            .ok_or(OpticalError::ResourceLimitExceeded)?;
        let logical_size = raw_logical_size
            .checked_add(skipped)
            .ok_or(OpticalError::ResourceLimitExceeded)?;
        let logical_end = logical_offset
            .checked_add(logical_size)
            .ok_or(OpticalError::ResourceLimitExceeded)?;
        if logical_end > logical_length {
            return Err(OpticalError::Malformed);
        }
        let end_group = group_index
            .checked_add(entry_group_count)
            .ok_or(OpticalError::ResourceLimitExceeded)?;
        if end_group > total_group_count {
            return Err(OpticalError::Malformed);
        }
        let mut remaining = logical_size;
        let mut logical_cursor = logical_offset;
        for group in 0..entry_group_count {
            let group_length = remaining.min(chunk_size);
            if group_length == 0 {
                return Err(OpticalError::Malformed);
            }
            spans.push(RvzSpan {
                logical_offset: logical_cursor,
                logical_size: group_length,
                group_index: group_index + group,
            });
            logical_cursor = logical_cursor
                .checked_add(group_length)
                .ok_or(OpticalError::ResourceLimitExceeded)?;
            remaining -= group_length;
        }
        if remaining != 0 {
            return Err(OpticalError::Malformed);
        }
    }
    if spans.is_empty() {
        return Err(OpticalError::Malformed);
    }
    spans.sort_unstable_by_key(|span| span.logical_offset);
    if spans.windows(2).any(|pair| {
        pair[0]
            .logical_offset
            .checked_add(pair[0].logical_size)
            .is_none_or(|end| end > pair[1].logical_offset)
    }) {
        return Err(OpticalError::Malformed);
    }
    Ok(spans)
}

fn parse_partitions(
    table: &[u8],
    count: usize,
    entry_size: usize,
    logical_length: u64,
    chunk_size: u64,
    total_group_count: usize,
) -> Result<Vec<RvzPartition>, OpticalError> {
    if count == 0 {
        return Ok(Vec::new());
    }
    let expected_size = count
        .checked_mul(entry_size)
        .ok_or(OpticalError::ResourceLimitExceeded)?;
    if table.len() != expected_size || !logical_length.is_multiple_of(WII_BLOCK_TOTAL_BYTES as u64)
    {
        return Err(OpticalError::Malformed);
    }
    let mut partitions = Vec::with_capacity(count);
    for index in 0..count {
        let entry_start = index * entry_size;
        let entry = &table[entry_start..entry_start + entry_size];
        let mut key = [0_u8; 16];
        if let Some(bytes) = entry.get(..16) {
            key.copy_from_slice(bytes);
        }
        let mut data = [None; 2];
        for (data_index, slot) in data.iter_mut().enumerate() {
            let field_start = 16 + data_index * 16;
            let first_sector = read_optional_u32_be(entry, field_start)?;
            let sector_count = read_optional_u32_be(entry, field_start + 4)?;
            let group_index = usize::try_from(read_optional_u32_be(entry, field_start + 8)?)
                .map_err(|_| OpticalError::ResourceLimitExceeded)?;
            let group_count = usize::try_from(read_optional_u32_be(entry, field_start + 12)?)
                .map_err(|_| OpticalError::ResourceLimitExceeded)?;
            if first_sector == 0 && sector_count == 0 && group_index == 0 && group_count == 0 {
                continue;
            }
            if sector_count == 0 || group_count == 0 {
                return Err(OpticalError::Malformed);
            }
            let end_sector = first_sector
                .checked_add(sector_count)
                .ok_or(OpticalError::ResourceLimitExceeded)?;
            if end_sector
                .checked_mul(WII_BLOCK_TOTAL_BYTES as u64)
                .is_none_or(|end| end > logical_length)
            {
                return Err(OpticalError::Malformed);
            }
            let physical_size = sector_count
                .checked_mul(WII_BLOCK_TOTAL_BYTES as u64)
                .ok_or(OpticalError::ResourceLimitExceeded)?;
            let expected_group_count = physical_size
                .checked_add(chunk_size - 1)
                .ok_or(OpticalError::ResourceLimitExceeded)?
                / chunk_size;
            if expected_group_count != group_count as u64
                || group_index
                    .checked_add(group_count)
                    .is_none_or(|end| end > total_group_count)
            {
                return Err(OpticalError::Malformed);
            }
            *slot = Some(RvzPartitionData {
                first_sector,
                sector_count,
                group_index,
                group_count,
            });
        }
        let Some(first) = data[0] else {
            return Err(OpticalError::Malformed);
        };
        if let Some(second) = data[1]
            && second.first_sector != first.first_sector + first.sector_count
        {
            return Err(OpticalError::UnsupportedRepresentation);
        }
        let last = data[1].unwrap_or(first);
        let total_sectors = last
            .first_sector
            .checked_add(last.sector_count)
            .and_then(|end| end.checked_sub(first.first_sector))
            .ok_or(OpticalError::ResourceLimitExceeded)?;
        partitions.push(RvzPartition {
            key,
            first_sector: first.first_sector,
            total_sectors,
            data,
        });
    }
    partitions.sort_unstable_by_key(|partition| partition.first_sector);
    if partitions.windows(2).any(|pair| {
        pair[0]
            .first_sector
            .checked_add(pair[0].total_sectors)
            .is_none_or(|end| end > pair[1].first_sector)
    }) {
        return Err(OpticalError::Malformed);
    }
    Ok(partitions)
}

fn read_optional_u32_be(bytes: &[u8], offset: usize) -> Result<u64, OpticalError> {
    let Some(field) = bytes.get(offset..offset.saturating_add(4)) else {
        return Ok(0);
    };
    Ok(u64::from(read_u32_be(field, 0)?))
}

fn validate_group_references(
    spans: &[RvzSpan],
    partitions: &[RvzPartition],
    groups: &[RvzGroup],
    chunk_size: u64,
) -> Result<(), OpticalError> {
    let mut used = vec![false; groups.len()];
    for span in spans {
        let group = groups
            .get(span.group_index)
            .ok_or(OpticalError::Malformed)?;
        if used[span.group_index] {
            return Err(OpticalError::Malformed);
        }
        used[span.group_index] = true;
        if !group.compressed
            && group.data_size != 0
            && group.packed_size == 0
            && group.data_size != span.logical_size
        {
            return Err(OpticalError::Malformed);
        }
    }
    for partition in partitions {
        for data in partition.data.into_iter().flatten() {
            for (group_index, used_flag) in used
                .iter_mut()
                .enumerate()
                .skip(data.group_index)
                .take(data.group_count)
            {
                if *used_flag {
                    return Err(OpticalError::Malformed);
                }
                *used_flag = true;
                let group = groups.get(group_index).ok_or(OpticalError::Malformed)?;
                if !group.compressed && group.data_size != 0 {
                    if group.packed_size != 0 {
                        return Err(OpticalError::Malformed);
                    }
                    let group_number = group_index - data.group_index;
                    let physical_size = data
                        .sector_count
                        .checked_mul(WII_BLOCK_TOTAL_BYTES as u64)
                        .ok_or(OpticalError::ResourceLimitExceeded)?;
                    let group_start = (group_number as u64)
                        .checked_mul(chunk_size)
                        .ok_or(OpticalError::ResourceLimitExceeded)?;
                    let physical_group_size = physical_size
                        .checked_sub(group_start)
                        .ok_or(OpticalError::Malformed)?
                        .min(chunk_size);
                    let main_size = physical_group_size / WII_BLOCK_TOTAL_BYTES as u64
                        * WII_BLOCK_DATA_BYTES as u64;
                    let list_count = partition_exception_list_count(chunk_size)?;
                    let minimum = list_count
                        .checked_mul(2)
                        .and_then(|value| value.checked_add(main_size as usize))
                        .ok_or(OpticalError::ResourceLimitExceeded)?;
                    if u64::try_from(minimum).unwrap_or(u64::MAX) > group.data_size {
                        return Err(OpticalError::Malformed);
                    }
                }
            }
        }
    }
    if used.iter().any(|value| !value) {
        return Err(OpticalError::Malformed);
    }
    Ok(())
}

fn validate_logical_coverage(
    logical_length: u64,
    spans: &[RvzSpan],
    partitions: &[RvzPartition],
) -> Result<(), OpticalError> {
    let mut ranges = Vec::with_capacity(spans.len() + partitions.len());
    ranges.extend(
        spans
            .iter()
            .map(|span| (span.logical_offset, span.logical_offset + span.logical_size)),
    );
    for partition in partitions {
        let start = partition
            .first_sector
            .checked_mul(WII_BLOCK_TOTAL_BYTES as u64)
            .ok_or(OpticalError::ResourceLimitExceeded)?;
        let end = partition
            .first_sector
            .checked_add(partition.total_sectors)
            .and_then(|value| value.checked_mul(WII_BLOCK_TOTAL_BYTES as u64))
            .ok_or(OpticalError::ResourceLimitExceeded)?;
        ranges.push((start, end));
    }
    ranges.sort_unstable();
    let mut cursor = 0_u64;
    for (start, end) in ranges {
        if end > logical_length || start < cursor {
            return Err(OpticalError::Malformed);
        }
        if start > cursor {
            return Err(OpticalError::UnsupportedRepresentation);
        }
        cursor = end;
    }
    if cursor != logical_length {
        return Err(OpticalError::UnsupportedRepresentation);
    }
    Ok(())
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum RvzLocation {
    Raw(RvzSpan),
    Partition {
        partition_index: usize,
        logical_offset: u64,
        logical_size: u64,
    },
}

struct DecodedPartitionGroup {
    data: Vec<u8>,
    exceptions: Vec<RvzException>,
}

type PartitionGroupKey = (usize, usize, usize);
type PartitionBlock = (Vec<u8>, Option<PartitionGroupKey>, Vec<RvzException>);

struct RvzReader<'a> {
    file: File,
    layout: RvzLayout,
    is_cancelled: &'a dyn Fn() -> bool,
    cached_group: Option<(usize, Vec<u8>)>,
    cached_partition_group: Option<(usize, usize, usize, DecodedPartitionGroup)>,
    cached_encrypted_partition_group: Option<(usize, u64, Vec<u8>)>,
    failure: Option<OpticalError>,
}

impl<'a> RvzReader<'a> {
    fn new(file: File, layout: RvzLayout, is_cancelled: &'a dyn Fn() -> bool) -> Self {
        Self {
            file,
            layout,
            is_cancelled,
            cached_group: None,
            cached_partition_group: None,
            cached_encrypted_partition_group: None,
            failure: None,
        }
    }

    fn take_failure(&mut self) -> Option<OpticalError> {
        self.failure.take()
    }

    fn fail<T>(&mut self, error: OpticalError) -> Result<T, ContentReadError> {
        self.failure = Some(error);
        Err(ContentReadError::Io)
    }

    fn locate(&self, position: u64) -> Option<RvzLocation> {
        if let Some(span) = self.layout.spans.iter().find(|span| {
            span.logical_offset <= position && position < span.logical_offset + span.logical_size
        }) {
            return Some(RvzLocation::Raw(*span));
        }
        self.layout
            .partitions
            .iter()
            .enumerate()
            .find_map(|(partition_index, partition)| {
                let logical_offset = partition
                    .first_sector
                    .checked_mul(WII_BLOCK_TOTAL_BYTES as u64)?;
                let logical_size = partition
                    .total_sectors
                    .checked_mul(WII_BLOCK_TOTAL_BYTES as u64)?;
                (logical_offset <= position && position < logical_offset + logical_size).then_some(
                    RvzLocation::Partition {
                        partition_index,
                        logical_offset,
                        logical_size,
                    },
                )
            })
    }

    fn group_bytes(&mut self, span: RvzSpan) -> Result<&[u8], ContentReadError> {
        if self
            .cached_group
            .as_ref()
            .is_some_and(|(index, _)| *index == span.group_index)
        {
            return Ok(&self.cached_group.as_ref().expect("cached group").1);
        }
        if (self.is_cancelled)() {
            return self.fail(OpticalError::Cancelled);
        }
        let group = *self
            .layout
            .groups
            .get(span.group_index)
            .ok_or(ContentReadError::OutOfRange)?;
        let compressed = if group.data_size == 0 {
            Vec::new()
        } else {
            let source_length = file_len(&mut self.file)?;
            read_file_range(
                &mut self.file,
                source_length,
                group.data_offset,
                group.data_size,
            )
            .map_err(|error| {
                self.failure = Some(error);
                ContentReadError::Io
            })?
        };
        let codec = if group.compressed {
            self.layout.codec
        } else {
            RvzCodec::None
        };
        let decoded = match decode_group(
            codec,
            group,
            &compressed,
            usize::try_from(span.logical_size).map_err(|_| ContentReadError::OutOfRange)?,
            &self.layout.compressor_data,
            span.logical_offset,
        ) {
            Ok(bytes) => bytes,
            Err(error) => return self.fail(error),
        };
        if (self.is_cancelled)() {
            return self.fail(OpticalError::Cancelled);
        }
        self.cached_group = Some((span.group_index, decoded));
        Ok(&self.cached_group.as_ref().expect("cached group").1)
    }

    fn partition_group(
        &mut self,
        partition_index: usize,
        data_index: usize,
        group_number: usize,
    ) -> Result<&DecodedPartitionGroup, OpticalError> {
        if self.cached_partition_group.as_ref().is_some_and(
            |(cached_partition, cached_data, cached_group, _)| {
                *cached_partition == partition_index
                    && *cached_data == data_index
                    && *cached_group == group_number
            },
        ) {
            return Ok(&self
                .cached_partition_group
                .as_ref()
                .expect("cached partition group")
                .3);
        }
        if (self.is_cancelled)() {
            return Err(OpticalError::Cancelled);
        }
        let partition = self
            .layout
            .partitions
            .get(partition_index)
            .ok_or(OpticalError::Malformed)?
            .clone();
        let data = partition.data[data_index].ok_or(OpticalError::Malformed)?;
        if group_number >= data.group_count {
            return Err(OpticalError::Malformed);
        }
        let group_index = data
            .group_index
            .checked_add(group_number)
            .ok_or(OpticalError::ResourceLimitExceeded)?;
        let group = *self
            .layout
            .groups
            .get(group_index)
            .ok_or(OpticalError::Malformed)?;
        let physical_size = data
            .sector_count
            .checked_mul(WII_BLOCK_TOTAL_BYTES as u64)
            .ok_or(OpticalError::ResourceLimitExceeded)?;
        let group_start = (group_number as u64)
            .checked_mul(self.layout_chunk_size())
            .ok_or(OpticalError::ResourceLimitExceeded)?;
        let physical_group_size = physical_size
            .checked_sub(group_start)
            .ok_or(OpticalError::Malformed)?
            .min(self.layout_chunk_size());
        if physical_group_size == 0
            || !physical_group_size.is_multiple_of(WII_BLOCK_TOTAL_BYTES as u64)
        {
            return Err(OpticalError::Malformed);
        }
        let expected_main = usize::try_from(
            physical_group_size / WII_BLOCK_TOTAL_BYTES as u64 * WII_BLOCK_DATA_BYTES as u64,
        )
        .map_err(|_| OpticalError::ResourceLimitExceeded)?;
        let group_physical_offset = data
            .first_sector
            .checked_sub(partition.first_sector)
            .and_then(|sectors| sectors.checked_mul(WII_BLOCK_TOTAL_BYTES as u64))
            .and_then(|offset| offset.checked_add(group_start))
            .ok_or(OpticalError::ResourceLimitExceeded)?;
        let stored = if group.data_size == 0 {
            Vec::new()
        } else {
            let source_length = file_len(&mut self.file).map_err(|_| OpticalError::ReadFailure)?;
            read_file_range(
                &mut self.file,
                source_length,
                group.data_offset,
                group.data_size,
            )?
        };
        let codec = if group.compressed {
            self.layout.codec
        } else {
            RvzCodec::None
        };
        let decoded = decode_partition_group(
            codec,
            group,
            &stored,
            expected_main,
            self.layout_chunk_size(),
            group_physical_offset,
            &self.layout.compressor_data,
        )?;
        if (self.is_cancelled)() {
            return Err(OpticalError::Cancelled);
        }
        self.cached_partition_group = Some((partition_index, data_index, group_number, decoded));
        Ok(&self
            .cached_partition_group
            .as_ref()
            .expect("cached partition group")
            .3)
    }

    fn layout_chunk_size(&self) -> u64 {
        self.layout.chunk_size
    }

    fn partition_data_block(
        &mut self,
        partition_index: usize,
        relative_sector: u64,
    ) -> Result<PartitionBlock, OpticalError> {
        let partition = self
            .layout
            .partitions
            .get(partition_index)
            .ok_or(OpticalError::Malformed)?
            .clone();
        let absolute_sector = partition
            .first_sector
            .checked_add(relative_sector)
            .ok_or(OpticalError::ResourceLimitExceeded)?;
        for (data_index, data) in partition.data.into_iter().enumerate() {
            let Some(data) = data else { continue };
            let data_end = data
                .first_sector
                .checked_add(data.sector_count)
                .ok_or(OpticalError::ResourceLimitExceeded)?;
            if !(data.first_sector..data_end).contains(&absolute_sector) {
                continue;
            }
            let sector_in_data = absolute_sector - data.first_sector;
            let sectors_per_group = self.layout_chunk_size() / WII_BLOCK_TOTAL_BYTES as u64;
            if sectors_per_group == 0 {
                return Err(OpticalError::Malformed);
            }
            let group_number = usize::try_from(sector_in_data / sectors_per_group)
                .map_err(|_| OpticalError::ResourceLimitExceeded)?;
            let sector_in_group = sector_in_data % sectors_per_group;
            let group = self.partition_group(partition_index, data_index, group_number)?;
            let offset = usize::try_from(sector_in_group)
                .ok()
                .and_then(|sector| sector.checked_mul(WII_BLOCK_DATA_BYTES))
                .ok_or(OpticalError::ResourceLimitExceeded)?;
            let end = offset
                .checked_add(WII_BLOCK_DATA_BYTES)
                .ok_or(OpticalError::ResourceLimitExceeded)?;
            if end > group.data.len() {
                return Err(OpticalError::Truncated);
            }
            return Ok((
                group.data[offset..end].to_vec(),
                Some((partition_index, data_index, group_number)),
                group.exceptions.clone(),
            ));
        }
        Ok((vec![0_u8; WII_BLOCK_DATA_BYTES], None, Vec::new()))
    }

    fn encrypted_partition_group(
        &mut self,
        partition_index: usize,
        hash_group_index: u64,
    ) -> Result<&[u8], OpticalError> {
        if self.cached_encrypted_partition_group.as_ref().is_some_and(
            |(cached_partition, cached_group, _)| {
                *cached_partition == partition_index && *cached_group == hash_group_index
            },
        ) {
            return Ok(&self
                .cached_encrypted_partition_group
                .as_ref()
                .expect("cached encrypted partition group")
                .2);
        }
        let partition = self
            .layout
            .partitions
            .get(partition_index)
            .ok_or(OpticalError::Malformed)?
            .clone();
        let mut data_blocks = vec![[0_u8; WII_BLOCK_DATA_BYTES]; WII_BLOCKS_PER_GROUP];
        let mut exceptions = Vec::new();
        let mut seen_groups = Vec::new();
        for (block_index, data_block) in data_blocks.iter_mut().enumerate() {
            let relative_sector = hash_group_index
                .checked_mul(WII_BLOCKS_PER_GROUP as u64)
                .and_then(|value| value.checked_add(block_index as u64))
                .ok_or(OpticalError::ResourceLimitExceeded)?;
            if relative_sector >= partition.total_sectors {
                continue;
            }
            let (data, group_key, group_exceptions) =
                self.partition_data_block(partition_index, relative_sector)?;
            data_block.copy_from_slice(&data);
            if let Some(group_key) = group_key
                && !seen_groups.contains(&group_key)
            {
                seen_groups.push(group_key);
                exceptions.extend(group_exceptions);
            }
        }

        let mut hash_blocks = vec![[0_u8; WII_BLOCK_HEADER_BYTES]; WII_BLOCKS_PER_GROUP];
        for (index, hash_block) in hash_blocks.iter_mut().enumerate() {
            for hash_index in 0..31 {
                let digest =
                    Sha1::digest(&data_blocks[index][hash_index * 0x400..(hash_index + 1) * 0x400]);
                hash_block[hash_index * 20..(hash_index + 1) * 20].copy_from_slice(&digest);
            }
        }
        for group in 0..8 {
            let first = group * 8;
            let mut h1 = [0_u8; 8 * 20];
            for index in 0..8 {
                let digest = Sha1::digest(&hash_blocks[first + index][..31 * 20]);
                h1[index * 20..(index + 1) * 20].copy_from_slice(&digest);
            }
            for hash_block in hash_blocks.iter_mut().skip(first).take(8) {
                hash_block[0x280..0x320].copy_from_slice(&h1);
            }
            let digest = Sha1::digest(h1);
            hash_blocks[0][0x340 + group * 20..0x340 + (group + 1) * 20].copy_from_slice(&digest);
        }
        let h2 = hash_blocks[0][0x340..0x3e0].to_owned();
        for hash_block in hash_blocks.iter_mut().skip(1) {
            hash_block[0x340..0x3e0].copy_from_slice(&h2);
        }
        for exception in exceptions {
            if exception.hash_group_index != hash_group_index
                || exception
                    .offset
                    .checked_add(exception.hash.len())
                    .is_none_or(|end| end > WII_BLOCKS_PER_GROUP * WII_BLOCK_HEADER_BYTES)
            {
                continue;
            }
            let block_index = exception.offset / WII_BLOCK_HEADER_BYTES;
            let offset = exception.offset % WII_BLOCK_HEADER_BYTES;
            if offset + exception.hash.len() > WII_BLOCK_HEADER_BYTES {
                return Err(OpticalError::Malformed);
            }
            hash_blocks[block_index][offset..offset + exception.hash.len()]
                .copy_from_slice(&exception.hash);
        }

        let cipher = Aes128::new_from_slice(&partition.key).map_err(|_| OpticalError::Malformed)?;
        let mut encrypted = vec![0_u8; WII_GROUP_TOTAL_BYTES];
        for index in 0..WII_BLOCKS_PER_GROUP {
            let offset = index * WII_BLOCK_TOTAL_BYTES;
            cbc_encrypt(
                &cipher,
                &hash_blocks[index],
                &mut encrypted[offset..offset + WII_BLOCK_HEADER_BYTES],
                [0_u8; 16],
            );
            let mut iv = [0_u8; 16];
            iv.copy_from_slice(&encrypted[offset + 0x3d0..offset + 0x3e0]);
            cbc_encrypt(
                &cipher,
                &data_blocks[index],
                &mut encrypted[offset + WII_BLOCK_HEADER_BYTES..offset + WII_BLOCK_TOTAL_BYTES],
                iv,
            );
        }
        self.cached_encrypted_partition_group =
            Some((partition_index, hash_group_index, encrypted));
        Ok(&self
            .cached_encrypted_partition_group
            .as_ref()
            .expect("cached encrypted partition group")
            .2)
    }
}

impl ContentReader for RvzReader<'_> {
    fn len(&self) -> Result<u64, ContentReadError> {
        Ok(self.layout.logical_length)
    }

    fn read_at(&mut self, offset: u64, destination: &mut [u8]) -> Result<usize, ContentReadError> {
        if destination.len() > 64 * 1024 {
            return Err(ContentReadError::RequestTooLarge);
        }
        let end = offset
            .checked_add(destination.len() as u64)
            .ok_or(ContentReadError::OutOfRange)?;
        if end > self.layout.logical_length {
            return Err(ContentReadError::OutOfRange);
        }
        let mut position = offset;
        let mut written = 0_usize;
        while written < destination.len() {
            if (self.is_cancelled)() {
                return self.fail(OpticalError::Cancelled);
            }
            if position < RVZ_DHEAD_BYTES as u64 {
                let count = (RVZ_DHEAD_BYTES as u64 - position)
                    .min((destination.len() - written) as u64) as usize;
                destination[written..written + count].copy_from_slice(
                    &self.layout.dhead[position as usize..position as usize + count],
                );
                written += count;
                position += count as u64;
                continue;
            }
            let Some(location) = self.locate(position) else {
                return self.fail(OpticalError::UnsupportedRepresentation);
            };
            match location {
                RvzLocation::Raw(span) => {
                    let group = self.group_bytes(span)?;
                    let within = usize::try_from(position - span.logical_offset)
                        .map_err(|_| ContentReadError::OutOfRange)?;
                    let count = group
                        .len()
                        .saturating_sub(within)
                        .min(destination.len() - written);
                    if count == 0 {
                        return self.fail(OpticalError::Malformed);
                    }
                    destination[written..written + count]
                        .copy_from_slice(&group[within..within + count]);
                    written += count;
                    position += count as u64;
                }
                RvzLocation::Partition {
                    partition_index,
                    logical_offset,
                    logical_size,
                } => {
                    let relative = position - logical_offset;
                    let hash_group = relative / WII_GROUP_TOTAL_BYTES as u64;
                    let group = match self.encrypted_partition_group(partition_index, hash_group) {
                        Ok(group) => group,
                        Err(error) => return self.fail(error),
                    };
                    let within = usize::try_from(relative % WII_GROUP_TOTAL_BYTES as u64)
                        .map_err(|_| ContentReadError::OutOfRange)?;
                    let remaining_region = usize::try_from(logical_size - relative)
                        .map_err(|_| ContentReadError::OutOfRange)?;
                    let count = (group.len() - within)
                        .min(remaining_region)
                        .min(destination.len() - written);
                    if count == 0 {
                        return self.fail(OpticalError::Malformed);
                    }
                    destination[written..written + count]
                        .copy_from_slice(&group[within..within + count]);
                    written += count;
                    position += count as u64;
                }
            }
        }
        Ok(written)
    }
}

fn partition_exception_list_count(chunk_size: u64) -> Result<usize, OpticalError> {
    let count = if chunk_size < RVZ_LARGE_CHUNK_BOUNDARY {
        1
    } else {
        chunk_size / RVZ_LARGE_CHUNK_BOUNDARY
    };
    usize::try_from(count).map_err(|_| OpticalError::ResourceLimitExceeded)
}

fn max_partition_exception_bytes(list_count: usize) -> Result<usize, OpticalError> {
    list_count
        .checked_mul(
            2usize
                .checked_add(
                    RVZ_MAX_EXCEPTIONS_PER_LIST
                        .checked_mul(RVZ_EXCEPTION_BYTES)
                        .ok_or(OpticalError::ResourceLimitExceeded)?,
                )
                .ok_or(OpticalError::ResourceLimitExceeded)?,
        )
        .and_then(|bytes| bytes.checked_add(3))
        .ok_or(OpticalError::ResourceLimitExceeded)
}

fn decode_partition_group(
    codec: RvzCodec,
    group: RvzGroup,
    stored: &[u8],
    expected_main: usize,
    chunk_size: u64,
    physical_offset: u64,
    compressor_data: &[u8; 7],
) -> Result<DecodedPartitionGroup, OpticalError> {
    let list_count = partition_exception_list_count(chunk_size)?;
    let max_exception_bytes = max_partition_exception_bytes(list_count)?;
    let packed_size = if group.packed_size == 0 {
        expected_main
    } else {
        usize::try_from(group.packed_size).map_err(|_| OpticalError::ResourceLimitExceeded)?
    };
    let max_decoded_size = max_exception_bytes
        .checked_add(packed_size)
        .ok_or(OpticalError::ResourceLimitExceeded)?;
    if max_decoded_size as u64 > RVZ_MAX_CHUNK_BYTES + max_exception_bytes as u64 {
        return Err(OpticalError::ResourceLimitExceeded);
    }
    if group.data_size == 0 {
        if group.packed_size != 0 {
            return Err(OpticalError::Malformed);
        }
        return Ok(DecodedPartitionGroup {
            data: vec![0_u8; expected_main],
            exceptions: Vec::new(),
        });
    }
    let decoded = if codec == RvzCodec::None {
        if stored.len() > max_decoded_size {
            return Err(OpticalError::Malformed);
        }
        stored.to_vec()
    } else {
        decode_compressed_payload_bounded(codec, stored, max_decoded_size, compressor_data)?
    };
    let mut cursor = 0_usize;
    let mut exceptions = Vec::new();
    for list_index in 0..list_count {
        let count_end = cursor
            .checked_add(2)
            .ok_or(OpticalError::ResourceLimitExceeded)?;
        let count_bytes = decoded
            .get(cursor..count_end)
            .ok_or(OpticalError::Truncated)?;
        let count = usize::from(u16::from_be_bytes(
            count_bytes.try_into().expect("exception count"),
        ));
        if count > RVZ_MAX_EXCEPTIONS_PER_LIST {
            return Err(OpticalError::ResourceLimitExceeded);
        }
        cursor = count_end;
        for _ in 0..count {
            let end = cursor
                .checked_add(RVZ_EXCEPTION_BYTES)
                .ok_or(OpticalError::ResourceLimitExceeded)?;
            let entry = decoded.get(cursor..end).ok_or(OpticalError::Truncated)?;
            let raw_offset = usize::from(u16::from_be_bytes(
                entry[..2].try_into().expect("exception offset"),
            ));
            let mut hash = [0_u8; 20];
            hash.copy_from_slice(&entry[2..]);
            let group_offset = physical_offset
                .checked_add(
                    u64::try_from(list_index)
                        .map_err(|_| OpticalError::ResourceLimitExceeded)?
                        .checked_mul(RVZ_LARGE_CHUNK_BOUNDARY)
                        .ok_or(OpticalError::ResourceLimitExceeded)?,
                )
                .ok_or(OpticalError::ResourceLimitExceeded)?;
            let hash_group_index = group_offset / WII_GROUP_TOTAL_BYTES as u64;
            let additional_offset = usize::try_from(
                group_offset % WII_GROUP_TOTAL_BYTES as u64 / WII_BLOCK_TOTAL_BYTES as u64
                    * WII_BLOCK_HEADER_BYTES as u64,
            )
            .map_err(|_| OpticalError::ResourceLimitExceeded)?;
            let offset = raw_offset
                .checked_add(additional_offset)
                .ok_or(OpticalError::ResourceLimitExceeded)?;
            if offset + 20 > WII_BLOCKS_PER_GROUP * WII_BLOCK_HEADER_BYTES {
                return Err(OpticalError::Malformed);
            }
            exceptions.push(RvzException {
                hash_group_index,
                offset,
                hash,
            });
            cursor = end;
        }
    }
    if codec == RvzCodec::None {
        cursor = cursor.next_multiple_of(4);
    }
    let payload = decoded.get(cursor..).ok_or(OpticalError::Truncated)?;
    let data = if group.packed_size == 0 {
        exact_length(payload.to_vec(), expected_main)?
    } else {
        let packed = exact_length(payload.to_vec(), packed_size)?;
        unpack_rvz(
            &packed,
            expected_main,
            physical_offset / WII_BLOCK_TOTAL_BYTES as u64 * WII_BLOCK_DATA_BYTES as u64,
        )?
    };
    Ok(DecodedPartitionGroup { data, exceptions })
}

fn decode_compressed_payload_bounded(
    codec: RvzCodec,
    compressed: &[u8],
    maximum_size: usize,
    compressor_data: &[u8; 7],
) -> Result<Vec<u8>, OpticalError> {
    if maximum_size as u64
        > RVZ_MAX_CHUNK_BYTES
            + max_partition_exception_bytes(partition_exception_list_count(RVZ_MAX_CHUNK_BYTES)?)?
                as u64
    {
        return Err(OpticalError::ResourceLimitExceeded);
    }
    match codec {
        RvzCodec::None => {
            if compressed.len() > maximum_size {
                Err(OpticalError::Malformed)
            } else {
                Ok(compressed.to_vec())
            }
        }
        RvzCodec::Bzip2 => oxiarc_bzip2::decompress_with_limit(compressed, maximum_size)
            .map_err(|_| OpticalError::Malformed),
        RvzCodec::Lzma => decode_lzma_bounded(compressed, maximum_size, compressor_data),
        RvzCodec::Lzma2 => decode_lzma2_bounded(compressed, maximum_size, compressor_data),
        RvzCodec::Zstd => decode_zstd_bounded(compressed, maximum_size),
    }
}

fn decode_lzma_bounded(
    compressed: &[u8],
    maximum_size: usize,
    compressor_data: &[u8; 7],
) -> Result<Vec<u8>, OpticalError> {
    let properties =
        LzmaProperties::from_byte(compressor_data[0]).ok_or(OpticalError::Malformed)?;
    let dictionary = u32::from_le_bytes(compressor_data[1..5].try_into().expect("LZMA properties"));
    if dictionary == 0 || dictionary > RVZ_MAX_LZMA_DICTIONARY_BYTES {
        return Err(OpticalError::ResourceLimitExceeded);
    }
    let bytes = oxiarc_lzma::decompress_raw(
        Cursor::new(compressed),
        properties,
        dictionary,
        Some(maximum_size as u64),
    )
    .map_err(|_| OpticalError::Malformed)?;
    if bytes.len() > maximum_size {
        Err(OpticalError::Malformed)
    } else {
        Ok(bytes)
    }
}

fn decode_lzma2_bounded(
    compressed: &[u8],
    maximum_size: usize,
    compressor_data: &[u8; 7],
) -> Result<Vec<u8>, OpticalError> {
    let dictionary = oxiarc_lzma::dict_size_from_props(compressor_data[0]);
    if dictionary == u32::MAX || dictionary > RVZ_MAX_LZMA_DICTIONARY_BYTES {
        return Err(OpticalError::ResourceLimitExceeded);
    }
    preflight_lzma2_output(compressed, maximum_size)?;
    let mut decoder = Lzma2Decoder::new(dictionary);
    let mut cursor = Cursor::new(compressed);
    let mut output = Vec::with_capacity(maximum_size.min(RVZ_MAX_CHUNK_BYTES as usize));
    loop {
        let produced = decoder
            .decode_chunk(&mut cursor, &mut output)
            .map_err(|_| OpticalError::Malformed)?;
        if output.len() > maximum_size {
            return Err(OpticalError::Malformed);
        }
        if !produced {
            break;
        }
    }
    Ok(output)
}

fn decode_zstd_bounded(compressed: &[u8], maximum_size: usize) -> Result<Vec<u8>, OpticalError> {
    let mut decoder =
        StreamingDecoder::new(Cursor::new(compressed)).map_err(|_| OpticalError::Malformed)?;
    let mut output = Vec::with_capacity(maximum_size);
    let mut buffer = [0_u8; 64 * 1024];
    loop {
        let remaining = maximum_size.saturating_sub(output.len());
        let count = remaining.saturating_add(1).min(buffer.len());
        if count == 0 {
            return Err(OpticalError::Malformed);
        }
        let read = decoder
            .read(&mut buffer[..count])
            .map_err(|_| OpticalError::Malformed)?;
        if read == 0 {
            break;
        }
        if output.len().saturating_add(read) > maximum_size {
            return Err(OpticalError::Malformed);
        }
        output.extend_from_slice(&buffer[..read]);
    }
    Ok(output)
}

fn cbc_encrypt(cipher: &Aes128, input: &[u8], output: &mut [u8], initial_vector: [u8; 16]) {
    debug_assert_eq!(input.len(), output.len());
    debug_assert!(input.len().is_multiple_of(16));
    let mut previous = initial_vector;
    for (source, destination) in input.chunks_exact(16).zip(output.chunks_exact_mut(16)) {
        let mut block = aes::cipher::Block::<Aes128>::default();
        for index in 0..16 {
            block[index] = source[index] ^ previous[index];
        }
        cipher.encrypt_block(&mut block);
        destination.copy_from_slice(&block);
        previous.copy_from_slice(&block);
    }
}

fn decode_group(
    codec: RvzCodec,
    group: RvzGroup,
    stored: &[u8],
    expected_size: usize,
    compressor_data: &[u8; 7],
    logical_offset: u64,
) -> Result<Vec<u8>, OpticalError> {
    let packed_expected = if group.packed_size == 0 {
        expected_size
    } else {
        usize::try_from(group.packed_size).map_err(|_| OpticalError::ResourceLimitExceeded)?
    };
    let decoded = if group.data_size == 0 {
        if group.packed_size != 0 {
            return Err(OpticalError::Malformed);
        }
        vec![0_u8; packed_expected]
    } else if group.compressed {
        decode_compressed_payload(codec, stored, packed_expected as u64, compressor_data)?
    } else {
        if stored.len() != packed_expected {
            return Err(OpticalError::Malformed);
        }
        stored.to_vec()
    };
    if group.packed_size == 0 {
        if decoded.len() != expected_size {
            return Err(OpticalError::Truncated);
        }
        return Ok(decoded);
    }
    unpack_rvz(decoded.as_slice(), expected_size, logical_offset)
}

fn decode_compressed_payload(
    codec: RvzCodec,
    compressed: &[u8],
    expected_size: u64,
    compressor_data: &[u8; 7],
) -> Result<Vec<u8>, OpticalError> {
    let expected =
        usize::try_from(expected_size).map_err(|_| OpticalError::ResourceLimitExceeded)?;
    if expected as u64 > RVZ_MAX_CHUNK_BYTES {
        return Err(OpticalError::ResourceLimitExceeded);
    }
    match codec {
        RvzCodec::None => {
            if compressed.len() != expected {
                return Err(OpticalError::Malformed);
            }
            Ok(compressed.to_vec())
        }
        RvzCodec::Bzip2 => oxiarc_bzip2::decompress_with_limit(compressed, expected)
            .map_err(|_| OpticalError::Malformed)
            .and_then(|bytes| exact_length(bytes, expected)),
        RvzCodec::Lzma => decode_lzma(compressed, expected, compressor_data),
        RvzCodec::Lzma2 => decode_lzma2(compressed, expected, compressor_data),
        RvzCodec::Zstd => decode_zstd(compressed, expected),
    }
}

fn decode_lzma(
    compressed: &[u8],
    expected: usize,
    compressor_data: &[u8; 7],
) -> Result<Vec<u8>, OpticalError> {
    let properties =
        LzmaProperties::from_byte(compressor_data[0]).ok_or(OpticalError::Malformed)?;
    let dictionary = u32::from_le_bytes(compressor_data[1..5].try_into().expect("LZMA properties"));
    if dictionary == 0 || dictionary > RVZ_MAX_LZMA_DICTIONARY_BYTES {
        return Err(OpticalError::ResourceLimitExceeded);
    }
    oxiarc_lzma::decompress_raw(
        Cursor::new(compressed),
        properties,
        dictionary,
        Some(expected as u64),
    )
    .map_err(|_| OpticalError::Malformed)
    .and_then(|bytes| exact_length(bytes, expected))
}

fn decode_lzma2(
    compressed: &[u8],
    expected: usize,
    compressor_data: &[u8; 7],
) -> Result<Vec<u8>, OpticalError> {
    let dictionary = oxiarc_lzma::dict_size_from_props(compressor_data[0]);
    if dictionary == u32::MAX || dictionary > RVZ_MAX_LZMA_DICTIONARY_BYTES {
        return Err(OpticalError::ResourceLimitExceeded);
    }
    preflight_lzma2_output(compressed, expected)?;
    let mut decoder = Lzma2Decoder::new(dictionary);
    let mut cursor = Cursor::new(compressed);
    let mut output = Vec::with_capacity(expected);
    loop {
        let produced = decoder
            .decode_chunk(&mut cursor, &mut output)
            .map_err(|_| OpticalError::Malformed)?;
        if output.len() > expected {
            return Err(OpticalError::Malformed);
        }
        if !produced {
            break;
        }
    }
    exact_length(output, expected)
}

/// Verifies every LZMA2 chunk declaration before handing bytes to oxiarc.
///
/// `Lzma2Decoder::decode_chunk` allocates the declared uncompressed size before
/// it reads the chunk payload. The decoder contract guarantees that a chunk
/// produces exactly that declaration, so checking the cumulative declarations
/// first makes the caller's output bound effective before any decoder buffer
/// can grow beyond it.
fn preflight_lzma2_output(compressed: &[u8], maximum_size: usize) -> Result<(), OpticalError> {
    let maximum_size =
        u64::try_from(maximum_size).map_err(|_| OpticalError::ResourceLimitExceeded)?;
    let mut cursor = 0_usize;
    let mut total = 0_u64;
    loop {
        let control = *compressed.get(cursor).ok_or(OpticalError::Malformed)?;
        cursor += 1;
        if control == 0 {
            return Ok(());
        }

        let uncompressed_size = if control == 1 || control == 2 {
            read_u16_be_at(compressed, &mut cursor)? as u64 + 1
        } else if control >= 0x80 {
            let high = u64::from(control & 0x1f) << 16;
            let low = u64::from(read_u16_be_at(compressed, &mut cursor)?);
            let uncompressed_size = high | low;
            let compressed_size = u64::from(read_u16_be_at(compressed, &mut cursor)?) + 1;
            if ((control >> 5) & 0x03) >= 2 {
                let _ = compressed.get(cursor).ok_or(OpticalError::Malformed)?;
                cursor += 1;
            }
            total = total
                .checked_add(uncompressed_size + 1)
                .ok_or(OpticalError::ResourceLimitExceeded)?;
            if total > maximum_size {
                return Err(OpticalError::Malformed);
            }
            skip_bytes(compressed, &mut cursor, compressed_size as usize)?;
            continue;
        } else {
            return Err(OpticalError::Malformed);
        };

        total = total
            .checked_add(uncompressed_size)
            .ok_or(OpticalError::ResourceLimitExceeded)?;
        if total > maximum_size {
            return Err(OpticalError::Malformed);
        }
        skip_bytes(
            compressed,
            &mut cursor,
            usize::try_from(uncompressed_size).map_err(|_| OpticalError::ResourceLimitExceeded)?,
        )?;
    }
}

fn read_u16_be_at(bytes: &[u8], cursor: &mut usize) -> Result<u16, OpticalError> {
    let end = cursor
        .checked_add(2)
        .ok_or(OpticalError::ResourceLimitExceeded)?;
    let value = bytes.get(*cursor..end).ok_or(OpticalError::Malformed)?;
    *cursor = end;
    Ok(u16::from_be_bytes(
        value.try_into().expect("two-byte LZMA2 field"),
    ))
}

fn skip_bytes(bytes: &[u8], cursor: &mut usize, count: usize) -> Result<(), OpticalError> {
    let end = cursor
        .checked_add(count)
        .ok_or(OpticalError::ResourceLimitExceeded)?;
    if end > bytes.len() {
        return Err(OpticalError::Malformed);
    }
    *cursor = end;
    Ok(())
}

fn decode_zstd(compressed: &[u8], expected: usize) -> Result<Vec<u8>, OpticalError> {
    let mut decoder =
        StreamingDecoder::new(Cursor::new(compressed)).map_err(|_| OpticalError::Malformed)?;
    let mut output = Vec::with_capacity(expected);
    let mut buffer = [0_u8; 64 * 1024];
    loop {
        let remaining = expected.saturating_sub(output.len());
        let count = remaining.saturating_add(1).min(buffer.len());
        if count == 0 {
            return Err(OpticalError::Malformed);
        }
        let read = decoder
            .read(&mut buffer[..count])
            .map_err(|_| OpticalError::Malformed)?;
        if read == 0 {
            break;
        }
        if output.len().saturating_add(read) > expected {
            return Err(OpticalError::Malformed);
        }
        output.extend_from_slice(&buffer[..read]);
    }
    exact_length(output, expected)
}

fn exact_length(bytes: Vec<u8>, expected: usize) -> Result<Vec<u8>, OpticalError> {
    if bytes.len() == expected {
        Ok(bytes)
    } else if bytes.len() < expected {
        Err(OpticalError::Truncated)
    } else {
        Err(OpticalError::Malformed)
    }
}

fn unpack_rvz(
    packed: &[u8],
    expected_size: usize,
    logical_offset: u64,
) -> Result<Vec<u8>, OpticalError> {
    let mut output = Vec::with_capacity(expected_size);
    let mut cursor = 0_usize;
    while cursor < packed.len() {
        let end = cursor
            .checked_add(4)
            .ok_or(OpticalError::ResourceLimitExceeded)?;
        if end > packed.len() {
            return Err(OpticalError::Truncated);
        }
        let descriptor = u32::from_be_bytes(packed[cursor..end].try_into().expect("packing size"));
        cursor = end;
        let generated = descriptor & RVZ_COMPRESSED_FLAG != 0;
        let size = usize::try_from(descriptor & RVZ_SIZE_MASK)
            .map_err(|_| OpticalError::ResourceLimitExceeded)?;
        if output.len().saturating_add(size) > expected_size {
            return Err(OpticalError::Malformed);
        }
        if generated {
            let seed_end = cursor
                .checked_add(68)
                .ok_or(OpticalError::ResourceLimitExceeded)?;
            if seed_end > packed.len() {
                return Err(OpticalError::Truncated);
            }
            let seed: [u8; 68] = packed[cursor..seed_end].try_into().expect("RVZ PRNG seed");
            cursor = seed_end;
            let offset = logical_offset
                .checked_add(output.len() as u64)
                .ok_or(OpticalError::ResourceLimitExceeded)?;
            append_prng_bytes(&mut output, size, &seed, offset)?;
        } else {
            let data_end = cursor
                .checked_add(size)
                .ok_or(OpticalError::ResourceLimitExceeded)?;
            if data_end > packed.len() {
                return Err(OpticalError::Truncated);
            }
            output.extend_from_slice(&packed[cursor..data_end]);
            cursor = data_end;
        }
    }
    exact_length(output, expected_size)
}

fn append_prng_bytes(
    output: &mut Vec<u8>,
    size: usize,
    seed: &[u8; 68],
    offset: u64,
) -> Result<(), OpticalError> {
    let mut state = [0_u32; 521];
    for (index, word) in state[..17].iter_mut().enumerate() {
        let start = index * 4;
        *word = u32::from_be_bytes(seed[start..start + 4].try_into().expect("PRNG word"));
    }
    for index in 17..state.len() {
        state[index] = (state[index - 17] << 23) ^ (state[index - 16] >> 9) ^ state[index - 1];
    }
    for _ in 0..4 {
        advance_prng(&mut state);
    }
    let mut index = 0_usize;
    for _ in 0..(offset % 0x8000) {
        let _ = next_prng_byte(&mut state, &mut index);
    }
    for _ in 0..size {
        output.push(next_prng_byte(&mut state, &mut index));
    }
    Ok(())
}

fn advance_prng(state: &mut [u32; 521]) {
    for index in 0..32 {
        state[index] ^= state[index + 521 - 32];
    }
    for index in 32..521 {
        state[index] ^= state[index - 32];
    }
}

fn next_prng_byte(state: &mut [u32; 521], index: &mut usize) -> u8 {
    if *index == 521 * 4 {
        advance_prng(state);
        *index = 0;
    }
    let word = state[*index / 4];
    let byte = *index % 4;
    *index += 1;
    match byte {
        0 => (word >> 24) as u8,
        1 => (word >> 16) as u8,
        2 => (word >> 8) as u8,
        _ => word as u8,
    }
}

fn read_content_exact(
    reader: &mut dyn ContentReader,
    offset: u64,
    destination: &mut [u8],
    is_cancelled: &dyn Fn() -> bool,
) -> Result<(), OpticalError> {
    let mut position = offset;
    let mut written = 0_usize;
    while written < destination.len() {
        if is_cancelled() {
            return Err(OpticalError::Cancelled);
        }
        let end = (written + 64 * 1024).min(destination.len());
        let count = reader
            .read_at(position, &mut destination[written..end])
            .map_err(|_| OpticalError::ReadFailure)?;
        if count == 0 {
            return Err(OpticalError::Truncated);
        }
        written += count;
        position = position
            .checked_add(count as u64)
            .ok_or(OpticalError::ResourceLimitExceeded)?;
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

fn file_len(file: &mut File) -> Result<u64, ContentReadError> {
    file.metadata()
        .map(|metadata| metadata.len())
        .map_err(|_| ContentReadError::Io)
}

fn map_io_error(error: io::Error) -> OpticalError {
    if error.kind() == io::ErrorKind::UnexpectedEof {
        OpticalError::Truncated
    } else {
        OpticalError::ReadFailure
    }
}

fn verify_optional_sha1(bytes: &[u8], expected: &[u8]) -> Result<(), OpticalError> {
    if expected.iter().all(|byte| *byte == 0) {
        return Ok(());
    }
    let digest = Sha1::digest(bytes);
    if digest.as_slice() == expected {
        Ok(())
    } else {
        Err(OpticalError::Malformed)
    }
}

fn read_u32_be(bytes: &[u8], offset: usize) -> Result<u32, OpticalError> {
    let end = offset
        .checked_add(4)
        .ok_or(OpticalError::ResourceLimitExceeded)?;
    let value = bytes.get(offset..end).ok_or(OpticalError::Truncated)?;
    Ok(u32::from_be_bytes(value.try_into().expect("u32 field")))
}

fn read_u64_be(bytes: &[u8], offset: usize) -> Result<u64, OpticalError> {
    let end = offset
        .checked_add(8)
        .ok_or(OpticalError::ResourceLimitExceeded)?;
    let value = bytes.get(offset..end).ok_or(OpticalError::Truncated)?;
    Ok(u64::from_be_bytes(value.try_into().expect("u64 field")))
}

fn map_session_error(error: TransformationFailure) -> OpticalError {
    match error {
        TransformationFailure::Cancelled => OpticalError::Cancelled,
        TransformationFailure::ResourceLimitExceeded => OpticalError::ResourceLimitExceeded,
        TransformationFailure::ReadFailure => OpticalError::ReadFailure,
        _ => OpticalError::Malformed,
    }
}

#[cfg(test)]
mod tests {
    use super::{OpticalError, decode_lzma2_bounded, preflight_lzma2_output, unpack_rvz};

    #[test]
    fn lzma2_preflight_rejects_declared_output_before_decoder_growth() {
        let malformed = [0x01, 0xff, 0xff];

        assert_eq!(
            preflight_lzma2_output(&malformed, 1024),
            Err(OpticalError::Malformed)
        );
        assert_eq!(
            decode_lzma2_bounded(&malformed, 1024, &[0; 7]),
            Err(OpticalError::Malformed)
        );
    }

    #[test]
    fn lzma2_bound_is_enforced_before_an_earlier_chunk_can_grow_output() {
        let malformed = [0x01, 0x00, 0x00, b'a', 0x01, 0xff, 0xff, 0x00];

        assert_eq!(
            decode_lzma2_bounded(&malformed, 1, &[0; 7]),
            Err(OpticalError::Malformed)
        );
    }

    #[test]
    fn lzma2_uncompressed_chunks_still_decode_within_the_bound() {
        let encoded = [0x01, 0x00, 0x01, b'a', b'b', 0x00];

        assert_eq!(
            decode_lzma2_bounded(&encoded, 2, &[0; 7]).expect("bounded LZMA2"),
            b"ab"
        );
    }

    #[test]
    fn rvz_prng_packing_emits_all_four_bytes_of_each_word() {
        let seed: [u8; 68] = core::array::from_fn(|index| index as u8);
        let mut packed = Vec::with_capacity(4 + seed.len());
        packed.extend_from_slice(&(0x8000_000c_u32).to_be_bytes());
        packed.extend_from_slice(&seed);

        assert_eq!(
            unpack_rvz(&packed, 12, 0).expect("packed data"),
            [
                0x1d, 0xd7, 0x7e, 0x0b, 0x64, 0xd2, 0x64, 0x56, 0xb7, 0xe7, 0x5f, 0x37,
            ]
        );
    }
}
