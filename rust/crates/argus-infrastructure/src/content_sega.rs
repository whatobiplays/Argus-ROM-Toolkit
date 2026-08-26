//! Sega cartridge recognizers for bounded runtime dispatch.

use argus_application::{ContentType, PlatformId};

use super::content_stream::{
    CanonicalHasher, ContentReader, ContentRecognitionError, ProbeResult, candidate, hash_range,
    hash_transformed_range, read_exact, read_small,
};

const SMD_COPIER_HEADER_BYTES: u64 = 512;
const SMD_BLOCK_BYTES: u64 = 0x4000;

/// Probes Sega cartridge representations without materializing the source.
pub(crate) fn probe(reader: &mut dyn ContentReader, source_length: u64) -> ProbeResult {
    if source_length >= 0x104 {
        if source_length >= 0x3d0 {
            let marker = match read_small(reader, 0x3c0, 16) {
                Ok(marker) => marker,
                Err(error) => return ProbeResult::Failure(error),
            };
            if marker.starts_with(b"MARS CHECK MODE") {
                return probe_32x_linear(reader, source_length);
            }
        }
        let magic = match read_small(reader, 0x100, 4) {
            Ok(magic) => magic,
            Err(error) => return ProbeResult::Failure(error),
        };
        if magic == b"SEGA" {
            return probe_genesis_linear(reader, source_length);
        }
    }

    match probe_genesis_smd(reader, source_length) {
        ProbeResult::NotApplicable => probe_sms_or_game_gear(reader, source_length),
        result => result,
    }
}

fn probe_genesis_linear(reader: &mut dyn ContentReader, source_length: u64) -> ProbeResult {
    if source_length < 0x200 {
        return ProbeResult::Failure(ContentRecognitionError::Truncated);
    }
    let header = match read_small(reader, 0x100, 0x100) {
        Ok(header) => header,
        Err(error) => return ProbeResult::Failure(error),
    };
    if let Err(error) = validate_genesis_header(&header, source_length) {
        return ProbeResult::Failure(error);
    }
    if let Err(error) = validate_genesis_checksum(reader, 0, source_length, &header) {
        return ProbeResult::Failure(error);
    }
    let mut hasher = CanonicalHasher::new();
    if let Err(error) = hash_range(reader, 0, source_length, &mut hasher) {
        return ProbeResult::Failure(error);
    }
    ProbeResult::Candidate(candidate(
        PlatformId::SegaGenesis,
        ContentType::CartridgeImage,
        "genesis-linear-be",
        hasher,
    ))
}

fn probe_32x_linear(reader: &mut dyn ContentReader, source_length: u64) -> ProbeResult {
    if source_length < 0x3f0 {
        return ProbeResult::Failure(ContentRecognitionError::Truncated);
    }
    if let Err(error) = validate_32x_user_header(reader, source_length) {
        return ProbeResult::Failure(error);
    }
    let header = match read_small(reader, 0x100, 0x100) {
        Ok(header) => header,
        Err(error) => return ProbeResult::Failure(error),
    };
    if let Err(error) = validate_genesis_header(&header, source_length) {
        return ProbeResult::Failure(error);
    }
    if let Err(error) = validate_genesis_checksum(reader, 0, source_length, &header) {
        return ProbeResult::Failure(error);
    }
    let mut hasher = CanonicalHasher::new();
    if let Err(error) = hash_range(reader, 0, source_length, &mut hasher) {
        return ProbeResult::Failure(error);
    }
    ProbeResult::Candidate(candidate(
        PlatformId::Sega32x,
        ContentType::CartridgeImage,
        "genesis-linear-be",
        hasher,
    ))
}

fn validate_32x_user_header(
    reader: &mut dyn ContentReader,
    source_length: u64,
) -> Result<(), ContentRecognitionError> {
    let header = read_small(reader, 0x3c0, 0x30)?;
    if &header[..0x10] != b"MARS CHECK MODE " {
        return Err(ContentRecognitionError::Malformed);
    }
    let version = u32::from_be_bytes([header[0x10], header[0x11], header[0x12], header[0x13]]);
    let source = u64::from(u32::from_be_bytes([
        header[0x14],
        header[0x15],
        header[0x16],
        header[0x17],
    ]));
    let destination = u64::from(u32::from_be_bytes([
        header[0x18],
        header[0x19],
        header[0x1a],
        header[0x1b],
    ]));
    let size = u64::from(u32::from_be_bytes([
        header[0x1c],
        header[0x1d],
        header[0x1e],
        header[0x1f],
    ]));
    let master_start = u64::from(u32::from_be_bytes([
        header[0x20],
        header[0x21],
        header[0x22],
        header[0x23],
    ]));
    let slave_start = u64::from(u32::from_be_bytes([
        header[0x24],
        header[0x25],
        header[0x26],
        header[0x27],
    ]));
    let master_vbr = u64::from(u32::from_be_bytes([
        header[0x28],
        header[0x29],
        header[0x2a],
        header[0x2b],
    ]));
    let slave_vbr = u64::from(u32::from_be_bytes([
        header[0x2c],
        header[0x2d],
        header[0x2e],
        header[0x2f],
    ]));
    if version != 0
        || size == 0
        || ![
            source,
            destination,
            size,
            master_start,
            slave_start,
            master_vbr,
            slave_vbr,
        ]
        .iter()
        .all(|value| value.is_multiple_of(4))
        || size % 4 != 0
        || source
            .checked_add(size)
            .is_none_or(|end| end > source_length)
    {
        return Err(ContentRecognitionError::Malformed);
    }
    Ok(())
}

fn probe_genesis_smd(reader: &mut dyn ContentReader, source_length: u64) -> ProbeResult {
    if source_length < SMD_COPIER_HEADER_BYTES + SMD_BLOCK_BYTES
        || !(source_length - SMD_COPIER_HEADER_BYTES).is_multiple_of(SMD_BLOCK_BYTES)
    {
        return ProbeResult::NotApplicable;
    }

    let mut first_block =
        match read_small(reader, SMD_COPIER_HEADER_BYTES, SMD_BLOCK_BYTES as usize) {
            Ok(block) => block,
            Err(error) => return ProbeResult::Failure(error),
        };
    let smd_header = match read_small(reader, 0, SMD_COPIER_HEADER_BYTES as usize) {
        Ok(header) => header,
        Err(error) => return ProbeResult::Failure(error),
    };
    let block_count = (source_length - SMD_COPIER_HEADER_BYTES) / SMD_BLOCK_BYTES;
    let expected_block_count = if block_count > u64::from(u8::MAX) {
        0
    } else {
        block_count as u8
    };
    if smd_header[0] != expected_block_count
        || smd_header[1] != 0x03
        || smd_header[2] != 0
        || smd_header[8] != 0xaa
        || smd_header[9] != 0xbb
    {
        return ProbeResult::NotApplicable;
    }
    deinterleave_smd_block(&mut first_block);
    if first_block.get(0x100..0x104) != Some(b"SEGA") {
        return ProbeResult::NotApplicable;
    }
    if first_block.starts_with_at(0x3c0, b"MARS CHECK MODE") {
        return ProbeResult::Failure(ContentRecognitionError::UnsupportedRepresentation);
    }
    if let Err(error) =
        validate_genesis_header(&first_block[0x100..0x200], block_count * SMD_BLOCK_BYTES)
    {
        return ProbeResult::Failure(error);
    }
    if let Err(error) = validate_genesis_smd_checksum(
        reader,
        block_count * SMD_BLOCK_BYTES,
        &first_block[0x100..0x200],
    ) {
        return ProbeResult::Failure(error);
    }

    let mut hasher = CanonicalHasher::new();
    if let Err(error) = hash_transformed_range(
        reader,
        SMD_COPIER_HEADER_BYTES,
        source_length - SMD_COPIER_HEADER_BYTES,
        SMD_BLOCK_BYTES as usize,
        deinterleave_smd_blocks,
        &mut hasher,
    ) {
        return ProbeResult::Failure(error);
    }
    ProbeResult::Candidate(candidate(
        PlatformId::SegaGenesis,
        ContentType::CartridgeImage,
        "genesis-smd",
        hasher,
    ))
}

trait StartsWithAt {
    fn starts_with_at(&self, offset: usize, marker: &[u8]) -> bool;
}

impl StartsWithAt for [u8] {
    fn starts_with_at(&self, offset: usize, marker: &[u8]) -> bool {
        self.get(offset..offset.saturating_add(marker.len())) == Some(marker)
    }
}

fn deinterleave_smd_block(block: &mut [u8]) {
    let half = block.len() / 2;
    let mut canonical = vec![0_u8; block.len()];
    for index in 0..half {
        canonical[index * 2] = block[half + index];
        canonical[index * 2 + 1] = block[index];
    }
    block.copy_from_slice(&canonical);
}

fn deinterleave_smd_blocks(bytes: &mut [u8]) {
    for block in bytes.chunks_exact_mut(SMD_BLOCK_BYTES as usize) {
        deinterleave_smd_block(block);
    }
}

fn probe_sms_or_game_gear(reader: &mut dyn ContentReader, source_length: u64) -> ProbeResult {
    let mut evidence = Vec::new();
    let mut valid_platforms = Vec::new();
    let mut invalid_evidence = false;
    for offset in [0x1ff0_u64, 0x3ff0, 0x7ff0] {
        if offset + 16 > source_length {
            continue;
        }
        let header = match read_small(reader, offset, 16) {
            Ok(header) => header,
            Err(error) => return ProbeResult::Failure(error),
        };
        if &header[..8] != b"TMR SEGA" {
            continue;
        }
        let platform = match header[15] >> 4 {
            0x3 | 0x4 => PlatformId::SegaSms,
            0x5..=0x7 => PlatformId::SegaGameGear,
            _ => return ProbeResult::Failure(ContentRecognitionError::AmbiguousContentRecognition),
        };
        if !evidence.contains(&platform) {
            evidence.push(platform);
        }
        let size_code = header[15] & 0x0f;
        let minimum_length = match sms_rom_length(size_code) {
            Some(length) => length,
            None => return ProbeResult::Failure(ContentRecognitionError::Malformed),
        };
        if source_length < minimum_length {
            invalid_evidence = true;
            continue;
        }
        let stored_checksum = u16::from_le_bytes([header[10], header[11]]);
        if platform == PlatformId::SegaSms && stored_checksum != 0 {
            let actual = match sms_checksum(reader, source_length, offset, size_code) {
                Ok(value) => value,
                Err(error) => return ProbeResult::Failure(error),
            };
            if actual != stored_checksum {
                invalid_evidence = true;
                continue;
            }
        }
        if !valid_platforms.contains(&platform) {
            valid_platforms.push(platform);
        }
    }

    match evidence.as_slice() {
        [] => ProbeResult::NotApplicable,
        [_sms, _game_gear] => {
            ProbeResult::Failure(ContentRecognitionError::AmbiguousContentRecognition)
        }
        [platform] if invalid_evidence => ProbeResult::Failure(ContentRecognitionError::Malformed),
        [platform] if valid_platforms.as_slice() == [*platform] => {
            let mut hasher = CanonicalHasher::new();
            if let Err(error) = hash_range(reader, 0, source_length, &mut hasher) {
                return ProbeResult::Failure(error);
            }
            ProbeResult::Candidate(candidate(
                *platform,
                ContentType::CartridgeImage,
                "raw-cartridge-image",
                hasher,
            ))
        }
        _ => ProbeResult::Failure(ContentRecognitionError::AmbiguousContentRecognition),
    }
}

fn validate_genesis_header(
    header: &[u8],
    canonical_length: u64,
) -> Result<(), ContentRecognitionError> {
    if header.len() < 0x100
        || header[0..4] != *b"SEGA"
        || !header[0..0x10]
            .iter()
            .skip(4)
            .any(|byte| byte.is_ascii_graphic() || *byte == b' ')
        || !matches!(&header[0x80..0x82], b"GM" | b"AL")
    {
        return Err(ContentRecognitionError::Malformed);
    }
    let rom_start = u64::from(u32::from_be_bytes([
        header[0xa0],
        header[0xa1],
        header[0xa2],
        header[0xa3],
    ]));
    let rom_end = u64::from(u32::from_be_bytes([
        header[0xa4],
        header[0xa5],
        header[0xa6],
        header[0xa7],
    ]));
    if rom_start != 0 || rom_end.checked_add(1) != Some(canonical_length) {
        return Err(ContentRecognitionError::Malformed);
    }
    Ok(())
}

fn validate_genesis_checksum(
    reader: &mut dyn ContentReader,
    source_offset: u64,
    source_length: u64,
    header: &[u8],
) -> Result<(), ContentRecognitionError> {
    let stored = u16::from_be_bytes([header[0x8e], header[0x8f]]);
    if stored == 0 {
        return Ok(());
    }
    let actual = genesis_checksum(reader, source_offset, source_length)?;
    if actual == stored {
        Ok(())
    } else {
        Err(ContentRecognitionError::Malformed)
    }
}

fn validate_genesis_smd_checksum(
    reader: &mut dyn ContentReader,
    canonical_length: u64,
    header: &[u8],
) -> Result<(), ContentRecognitionError> {
    let stored = u16::from_be_bytes([header[0x8e], header[0x8f]]);
    if stored == 0 {
        return Ok(());
    }
    let actual = genesis_smd_checksum(reader, canonical_length)?;
    if actual == stored {
        Ok(())
    } else {
        Err(ContentRecognitionError::Malformed)
    }
}

fn genesis_checksum(
    reader: &mut dyn ContentReader,
    source_offset: u64,
    source_length: u64,
) -> Result<u16, ContentRecognitionError> {
    let mut buffer = vec![0_u8; super::content_stream::STREAM_CHUNK_BYTES];
    let mut sum = 0_u16;
    let mut offset = source_offset + 0x200;
    let end = source_offset + source_length;
    while offset < end {
        let count = (end - offset).min(buffer.len() as u64) as usize;
        read_exact(reader, offset, &mut buffer[..count])?;
        for (index, byte) in buffer[..count].iter().enumerate() {
            if (offset - source_offset + index as u64).is_multiple_of(2) {
                sum = sum.wrapping_add(u16::from(*byte) << 8);
            } else {
                sum = sum.wrapping_add(u16::from(*byte));
            }
        }
        offset += count as u64;
    }
    Ok(sum)
}

fn genesis_smd_checksum(
    reader: &mut dyn ContentReader,
    canonical_length: u64,
) -> Result<u16, ContentRecognitionError> {
    let mut buffer = vec![0_u8; super::content_stream::STREAM_CHUNK_BYTES];
    let mut sum = 0_u16;
    let mut source_offset = SMD_COPIER_HEADER_BYTES;
    let source_end = SMD_COPIER_HEADER_BYTES + canonical_length;
    let mut canonical_offset = 0_u64;
    while source_offset < source_end {
        let count = (source_end - source_offset).min(buffer.len() as u64) as usize;
        if !count.is_multiple_of(SMD_BLOCK_BYTES as usize) {
            return Err(ContentRecognitionError::Malformed);
        }
        read_exact(reader, source_offset, &mut buffer[..count])?;
        deinterleave_smd_blocks(&mut buffer[..count]);
        for (index, byte) in buffer[..count].iter().enumerate() {
            let absolute = canonical_offset + index as u64;
            if absolute < 0x200 {
                continue;
            }
            if (absolute - 0x200).is_multiple_of(2) {
                sum = sum.wrapping_add(u16::from(*byte) << 8);
            } else {
                sum = sum.wrapping_add(u16::from(*byte));
            }
        }
        source_offset += count as u64;
        canonical_offset += count as u64;
    }
    Ok(sum)
}

fn sms_rom_length(size_code: u8) -> Option<u64> {
    Some(match size_code {
        0x0a => 8 * 1024,
        0x0b => 16 * 1024,
        0x0c => 32 * 1024,
        0x0d => 48 * 1024,
        0x0e => 64 * 1024,
        0x0f => 128 * 1024,
        0x00 => 256 * 1024,
        0x01 => 512 * 1024,
        0x02 => 1024 * 1024,
        _ => return None,
    })
}

fn sms_checksum(
    reader: &mut dyn ContentReader,
    source_length: u64,
    header_offset: u64,
    size_code: u8,
) -> Result<u16, ContentRecognitionError> {
    let mut buffer = vec![0_u8; super::content_stream::STREAM_CHUNK_BYTES];
    let mut sum = 0_u16;
    let mut ranges = vec![(0_u64, header_offset)];
    match size_code {
        0x0e | 0x0f => ranges.push((0x8000, source_length.min(0x20_000))),
        0x00..=0x02 => ranges.push((0x8000, source_length.min(0x40_000))),
        0x0a..=0x0d => {}
        _ => return Err(ContentRecognitionError::Malformed),
    }
    for (start, end) in ranges {
        if start > end || end > source_length {
            return Err(ContentRecognitionError::Malformed);
        }
        let mut offset = start;
        while offset < end {
            let count = (end - offset).min(buffer.len() as u64) as usize;
            read_exact(reader, offset, &mut buffer[..count])?;
            for byte in &buffer[..count] {
                sum = sum.wrapping_add(u16::from(*byte));
            }
            offset += count as u64;
        }
    }
    Ok(sum)
}
