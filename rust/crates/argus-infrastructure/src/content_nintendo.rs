//! Nintendo cartridge and disk format recognizers.

use argus_application::{ContentType, PlatformId};

use super::content_stream::{
    CanonicalHasher, ContentReader, ContentRecognitionError, ProbeResult, candidate, hash_range,
    hash_transformed_range, in_range, read_small, update_u32, update_u64,
};
use super::{GB_LOGO, GBA_LOGO, gb_rom_length, valid_cartridge_type};

const FDS_SIDE_BYTES: u64 = 65_500;

pub(crate) fn probe(reader: &mut dyn ContentReader, source_length: u64) -> ProbeResult {
    if source_length >= 4 {
        let magic = match read_small(reader, 0, 4) {
            Ok(magic) => magic,
            Err(error) => return ProbeResult::Failure(error),
        };
        if magic == b"NES\x1a" {
            return probe_nes(reader, source_length);
        }
        if magic == b"FDS\x1a" {
            return probe_fds_headered(reader, source_length);
        }
        if let Some(order) = n64_order(&magic) {
            return probe_n64(reader, source_length, order);
        }
    }

    if source_length >= 0x104 {
        match read_small(reader, 0x100, 4) {
            Ok(magic) if magic == b"NCSD" => return probe_3ds(reader, source_length),
            Ok(_) => {}
            Err(error) => return ProbeResult::Failure(error),
        }
    }

    if source_length >= 0x150 {
        let logo = match read_small(reader, 0x104, GB_LOGO.len()) {
            Ok(logo) => logo,
            Err(error) => return ProbeResult::Failure(error),
        };
        if logo == GB_LOGO {
            return probe_gb(reader, source_length);
        }
    }

    if source_length >= 0xc0 {
        let logo = match read_small(reader, 0x04, GBA_LOGO.len()) {
            Ok(logo) => logo,
            Err(error) => return ProbeResult::Failure(error),
        };
        if logo == GBA_LOGO {
            return probe_gba(reader, source_length);
        }
    }

    if source_length >= 0x200 {
        match probe_nds(reader, source_length) {
            ProbeResult::NotApplicable => {}
            result => return result,
        }
    }

    probe_fds_headerless(reader, source_length).or_snes(reader, source_length)
}

trait ProbeFallback {
    fn or_snes(self, reader: &mut dyn ContentReader, source_length: u64) -> ProbeResult;
}

impl ProbeFallback for ProbeResult {
    fn or_snes(self, reader: &mut dyn ContentReader, source_length: u64) -> ProbeResult {
        match self {
            ProbeResult::NotApplicable => probe_snes(reader, source_length),
            result => result,
        }
    }
}

fn probe_gb(reader: &mut dyn ContentReader, source_length: u64) -> ProbeResult {
    let header = match read_small(reader, 0x100, 0x50) {
        Ok(header) => header,
        Err(error) => return ProbeResult::Failure(error),
    };
    let cgb_flag = header[0x43];
    let platform = match cgb_flag {
        0x00 => PlatformId::NintendoGb,
        0x80 | 0xc0 => PlatformId::NintendoGbc,
        _ => return ProbeResult::Failure(ContentRecognitionError::Malformed),
    };
    if !valid_cartridge_type(header[0x47]) {
        return ProbeResult::Failure(ContentRecognitionError::UnsupportedRepresentation);
    }
    let Some(expected_length) = gb_rom_length(header[0x48]) else {
        return ProbeResult::Failure(ContentRecognitionError::UnsupportedRepresentation);
    };
    if source_length != expected_length as u64 {
        return ProbeResult::Failure(ContentRecognitionError::UnsupportedRepresentation);
    }
    let mut checksum = 0_u8;
    for byte in &header[0x34..0x4d] {
        checksum = checksum.wrapping_sub(*byte).wrapping_sub(1);
    }
    if checksum != header[0x4d] {
        return ProbeResult::Failure(ContentRecognitionError::Malformed);
    }
    let mut hasher = CanonicalHasher::new();
    if let Err(error) = hash_range(reader, 0, source_length, &mut hasher) {
        return ProbeResult::Failure(error);
    }
    ProbeResult::Candidate(candidate(
        platform,
        ContentType::CartridgeImage,
        "raw-cartridge-image",
        hasher,
    ))
}

fn probe_gba(reader: &mut dyn ContentReader, source_length: u64) -> ProbeResult {
    if !source_length.is_multiple_of(4) {
        return ProbeResult::Failure(ContentRecognitionError::Malformed);
    }
    let header = match read_small(reader, 0, 0xc0) {
        Ok(header) => header,
        Err(error) => return ProbeResult::Failure(error),
    };
    if !valid_gba_entry_point(&header, source_length)
        || header[0x04..0xa0] != GBA_LOGO
        || !header[0xa0..0xac]
            .iter()
            .all(|byte| *byte == b' ' || byte.is_ascii_graphic())
        || !header[0xac..0xb2]
            .iter()
            .all(|byte| byte.is_ascii_uppercase() || byte.is_ascii_digit())
        || header[0xb2] != 0x96
        || header[0xb3] != 0
        || header[0xb4] != 0
        || header[0xb5..0xbc].iter().any(|byte| *byte != 0)
        || header[0xbe..0xc0].iter().any(|byte| *byte != 0)
    {
        return ProbeResult::Failure(ContentRecognitionError::Malformed);
    }
    let sum = header[0xa0..0xbd]
        .iter()
        .fold(0_u8, |sum, byte| sum.wrapping_add(*byte))
        .wrapping_add(0x19)
        .wrapping_add(header[0xbd]);
    if sum != 0 {
        return ProbeResult::Failure(ContentRecognitionError::Malformed);
    }
    let mut hasher = CanonicalHasher::new();
    if let Err(error) = hash_range(reader, 0, source_length, &mut hasher) {
        return ProbeResult::Failure(error);
    }
    ProbeResult::Candidate(candidate(
        PlatformId::NintendoGba,
        ContentType::CartridgeImage,
        "raw-cartridge-image",
        hasher,
    ))
}

fn valid_gba_entry_point(header: &[u8], source_length: u64) -> bool {
    let opcode = u32::from_le_bytes([header[0], header[1], header[2], header[3]]);
    let is_arm_branch =
        (opcode >> 28) == 0xE && ((opcode >> 25) & 0b111) == 0b101 && ((opcode >> 24) & 1) == 0;
    if !is_arm_branch {
        return false;
    }
    let signed_offset = (((opcode & 0x00FF_FFFF) as i32) << 8) >> 6;
    let target_offset = 8_i64 + i64::from(signed_offset);
    target_offset >= 0 && target_offset % 4 == 0 && (target_offset as u64) < source_length
}

fn probe_nes(reader: &mut dyn ContentReader, source_length: u64) -> ProbeResult {
    if source_length < 16 {
        return ProbeResult::Failure(ContentRecognitionError::Truncated);
    }
    let header = match read_small(reader, 0, 16) {
        Ok(header) => header,
        Err(error) => return ProbeResult::Failure(error),
    };
    let nes2 = (header[7] & 0x0c) == 0x08;
    if !nes2 && (header[7] & 0x0c != 0 || header[12..16].iter().any(|byte| *byte != 0)) {
        return ProbeResult::Failure(ContentRecognitionError::UnsupportedRepresentation);
    }
    let console_class = header[7] & 0x03;
    if console_class != 0 {
        return ProbeResult::Failure(ContentRecognitionError::UnsupportedRepresentation);
    }
    let prg_length = match nes_rom_size(header[4], header[9] & 0x0f, nes2, 16 * 1024) {
        Ok(length) => length,
        Err(error) => return ProbeResult::Failure(error),
    };
    let chr_length = match nes_rom_size(header[5], header[9] >> 4, nes2, 8 * 1024) {
        Ok(length) => length,
        Err(error) => return ProbeResult::Failure(error),
    };
    let trainer_length = u64::from((header[6] & 0x04 != 0) as u8) * 512;
    let mapper = u32::from(header[6] >> 4)
        | u32::from(header[7] & 0xf0)
        | if nes2 {
            u32::from(header[8] & 0x0f) << 8
        } else {
            0
        };
    let submapper = if nes2 {
        u32::from(header[8] >> 4)
    } else {
        u32::MAX
    };
    if !supported_nes_mapper(mapper, submapper) {
        return ProbeResult::Failure(ContentRecognitionError::UnsupportedRepresentation);
    }
    let payload_start = 16_u64
        .checked_add(trainer_length)
        .ok_or(ContentRecognitionError::ResourceLimitExceeded);
    let payload_length = prg_length
        .checked_add(chr_length)
        .ok_or(ContentRecognitionError::ResourceLimitExceeded);
    let (Ok(payload_start), Ok(payload_length)) = (payload_start, payload_length) else {
        return ProbeResult::Failure(ContentRecognitionError::ResourceLimitExceeded);
    };
    let payload_end = payload_start
        .checked_add(payload_length)
        .ok_or(ContentRecognitionError::ResourceLimitExceeded);
    let Ok(payload_end) = payload_end else {
        return ProbeResult::Failure(ContentRecognitionError::ResourceLimitExceeded);
    };
    if !in_range(payload_start, payload_length, source_length) {
        return ProbeResult::Failure(ContentRecognitionError::Truncated);
    }
    let timing_class = if nes2 {
        u32::from(header[12] & 0x03)
    } else {
        u32::from(header[9] & 0x01)
    };
    let miscellaneous_count = if nes2 {
        u32::from(header[14] & 0x03)
    } else {
        0
    };
    if miscellaneous_count != 0 {
        // NES 2.0 records the count but does not provide boundaries for
        // independently hashed miscellaneous regions. Accepting an arbitrary
        // equal split would manufacture identity semantics.
        return ProbeResult::Failure(ContentRecognitionError::UnsupportedRepresentation);
    }
    if source_length != payload_end {
        return ProbeResult::Failure(ContentRecognitionError::UnsupportedRepresentation);
    }
    let (prg_ram, prg_nvram, chr_ram, chr_nvram) = nes_memory_sizes(&header, nes2);
    let mut hasher = CanonicalHasher::new();
    hasher.update(b"ARGUS-NES-CART-V1");
    update_u32(&mut hasher, u32::from(console_class));
    update_u32(&mut hasher, timing_class);
    update_u32(&mut hasher, mapper);
    update_u32(&mut hasher, submapper);
    update_u32(&mut hasher, u32::from(header[6] & 0x01));
    update_u32(&mut hasher, u32::from((header[6] >> 3) & 0x01));
    update_u32(&mut hasher, u32::from((header[6] >> 1) & 0x01));
    update_u32(&mut hasher, u32::from((header[6] >> 2) & 0x01));
    update_u64(&mut hasher, prg_ram);
    update_u64(&mut hasher, prg_nvram);
    update_u64(&mut hasher, chr_ram);
    update_u64(&mut hasher, chr_nvram);
    update_u64(&mut hasher, trainer_length);
    update_u64(&mut hasher, prg_length);
    update_u64(&mut hasher, chr_length);
    if let Err(error) = hash_range(reader, 16, trainer_length, &mut hasher)
        .and_then(|_| hash_range(reader, payload_start, prg_length, &mut hasher))
        .and_then(|_| hash_range(reader, payload_start + prg_length, chr_length, &mut hasher))
    {
        return ProbeResult::Failure(error);
    }
    update_u32(&mut hasher, miscellaneous_count);
    ProbeResult::Candidate(candidate(
        PlatformId::NintendoNes,
        ContentType::CartridgeImage,
        if nes2 { "nes-2" } else { "nes-ines" },
        hasher,
    ))
}

fn nes_rom_size(
    size_byte: u8,
    size_extension: u8,
    nes2: bool,
    linear_unit: u64,
) -> Result<u64, ContentRecognitionError> {
    let size_extension = if nes2 { size_extension } else { 0 };
    if size_extension != 0x0f {
        return u64::from(size_byte)
            .checked_add(u64::from(size_extension) << 8)
            .and_then(|units| units.checked_mul(linear_unit))
            .ok_or(ContentRecognitionError::ResourceLimitExceeded);
    }
    let exponent = u32::from(size_byte >> 2);
    let multiplier = 2 * u64::from(size_byte & 0x03) + 1;
    1_u64
        .checked_shl(exponent)
        .and_then(|base| base.checked_mul(multiplier))
        .ok_or(ContentRecognitionError::ResourceLimitExceeded)
}

fn supported_nes_mapper(mapper: u32, submapper: u32) -> bool {
    // Mapper identity is header evidence, not an emulation capability. Every
    // iNES/NES 2.0 mapper and submapper that fits the format's fixed-width
    // fields has a deterministic canonical descriptor here.
    mapper <= 0x0fff && (submapper <= 0x0f || submapper == u32::MAX)
}

fn nes_memory_sizes(header: &[u8], nes2: bool) -> (u64, u64, u64, u64) {
    if nes2 {
        (
            nes_ram_size(header[10] & 0x0f),
            nes_ram_size(header[10] >> 4),
            nes_ram_size(header[11] & 0x0f),
            nes_ram_size(header[11] >> 4),
        )
    } else {
        (
            u64::from(header[8]) * 8 * 1024,
            if header[6] & 0x02 != 0 {
                u64::from(header[8].max(1)) * 8 * 1024
            } else {
                0
            },
            0,
            0,
        )
    }
}

fn nes_ram_size(shift: u8) -> u64 {
    if shift == 0 { 0 } else { 64_u64 << shift }
}

fn probe_fds_headered(reader: &mut dyn ContentReader, source_length: u64) -> ProbeResult {
    if source_length < 16 {
        return ProbeResult::Failure(ContentRecognitionError::Truncated);
    }
    let header = match read_small(reader, 0, 16) {
        Ok(header) => header,
        Err(error) => return ProbeResult::Failure(error),
    };
    if header[5..].iter().any(|byte| *byte != 0) {
        return ProbeResult::Failure(ContentRecognitionError::Malformed);
    }
    let side_count = u64::from(header[4]);
    let expected_length = 16_u64.saturating_add(side_count.saturating_mul(FDS_SIDE_BYTES));
    if side_count == 0 || source_length != expected_length {
        return ProbeResult::Failure(ContentRecognitionError::UnsupportedRepresentation);
    }
    build_fds_candidate(reader, source_length, 16, side_count, "fds-fw")
}

fn probe_fds_headerless(reader: &mut dyn ContentReader, source_length: u64) -> ProbeResult {
    if source_length == 0 || !source_length.is_multiple_of(FDS_SIDE_BYTES) {
        return ProbeResult::NotApplicable;
    }
    let side_count = source_length / FDS_SIDE_BYTES;
    let prefix = match read_small(reader, 0, 64) {
        Ok(prefix) => prefix,
        Err(error) => return ProbeResult::Failure(error),
    };
    if !contains_fds_marker(&prefix) {
        return ProbeResult::NotApplicable;
    }
    build_fds_candidate(reader, source_length, 0, side_count, "fds-headerless")
}

fn build_fds_candidate(
    reader: &mut dyn ContentReader,
    source_length: u64,
    source_offset: u64,
    side_count: u64,
    representation: &'static str,
) -> ProbeResult {
    let payload_length = side_count.saturating_mul(FDS_SIDE_BYTES);
    let Some(payload_end) = source_offset.checked_add(payload_length) else {
        return ProbeResult::Failure(ContentRecognitionError::ResourceLimitExceeded);
    };
    if side_count == 0 || side_count > u64::from(u32::MAX) || payload_end > source_length {
        return ProbeResult::Failure(ContentRecognitionError::Truncated);
    }
    for side in 0..side_count {
        let side_offset = source_offset + side * FDS_SIDE_BYTES;
        if let Err(error) = validate_fds_side(reader, side_offset) {
            return ProbeResult::Failure(error);
        }
    }
    let mut hasher = CanonicalHasher::new();
    hasher.update(b"ARGUS-FDS-DISK-V1");
    update_u32(&mut hasher, side_count as u32);
    for side in 0..side_count {
        let side_offset = source_offset + side * FDS_SIDE_BYTES;
        update_u64(&mut hasher, FDS_SIDE_BYTES);
        if let Err(error) = hash_range(reader, side_offset, FDS_SIDE_BYTES, &mut hasher) {
            return ProbeResult::Failure(error);
        }
    }
    ProbeResult::Candidate(candidate(
        PlatformId::NintendoFds,
        ContentType::MagneticDiskImage,
        representation,
        hasher,
    ))
}

fn validate_fds_side(
    reader: &mut dyn ContentReader,
    side_offset: u64,
) -> Result<(), ContentRecognitionError> {
    let disk_info = read_small(reader, side_offset, 56)?;
    if disk_info[0] != 1 || &disk_info[1..15] != b"*NINTENDO-HVC*" {
        return Err(ContentRecognitionError::Malformed);
    }
    let file_count = read_small(reader, side_offset + 56, 2)?;
    if file_count[0] != 2 {
        return Err(ContentRecognitionError::Malformed);
    }
    // The BIOS count describes the files it normally loads. Retail disks can
    // append hidden block-3/block-4 pairs, so physical block order—not that
    // count or the file-number field—defines the side's remaining structure.
    let _bios_file_count = file_count[1];
    let side_end = side_offset + FDS_SIDE_BYTES;
    let mut cursor = side_offset + 58;
    while cursor < side_end {
        let marker = read_small(reader, cursor, 1)?[0];
        match marker {
            0 => {
                let mut padding_offset = cursor;
                while padding_offset < side_end {
                    let length = (side_end - padding_offset)
                        .min(super::content_stream::STREAM_CHUNK_BYTES as u64)
                        as usize;
                    let padding = read_small(reader, padding_offset, length)?;
                    if padding.iter().any(|byte| *byte != 0) {
                        return Err(ContentRecognitionError::Malformed);
                    }
                    padding_offset += length as u64;
                }
                break;
            }
            3 => {
                let header = read_small(reader, cursor, 16)?;
                if header[15] > 2 {
                    return Err(ContentRecognitionError::Malformed);
                }
                let file_length = u64::from(u16::from_le_bytes([header[13], header[14]]));
                cursor = cursor
                    .checked_add(16)
                    .ok_or(ContentRecognitionError::ResourceLimitExceeded)?;
                let data_marker = read_small(reader, cursor, 1)?;
                if data_marker[0] != 4 {
                    return Err(ContentRecognitionError::Malformed);
                }
                cursor = cursor
                    .checked_add(1)
                    .and_then(|value| value.checked_add(file_length))
                    .ok_or(ContentRecognitionError::ResourceLimitExceeded)?;
                if cursor > side_end {
                    return Err(ContentRecognitionError::Truncated);
                }
            }
            _ => return Err(ContentRecognitionError::Malformed),
        }
    }
    Ok(())
}

fn contains_fds_marker(prefix: &[u8]) -> bool {
    prefix.get(1..15) == Some(b"*NINTENDO-HVC*")
}

#[derive(Clone, Copy)]
enum N64Order {
    Native,
    Swapped16,
    Swapped32,
}

fn n64_order(magic: &[u8]) -> Option<N64Order> {
    match magic {
        [0x80, 0x37, 0x12, 0x40] => Some(N64Order::Native),
        [0x37, 0x80, 0x40, 0x12] => Some(N64Order::Swapped16),
        [0x40, 0x12, 0x37, 0x80] => Some(N64Order::Swapped32),
        _ => None,
    }
}

fn probe_n64(reader: &mut dyn ContentReader, source_length: u64, order: N64Order) -> ProbeResult {
    if source_length < 0x40 || !source_length.is_multiple_of(4) {
        return ProbeResult::Failure(ContentRecognitionError::Malformed);
    }
    let mut header = match read_small(reader, 0, 0x40) {
        Ok(header) => header,
        Err(error) => return ProbeResult::Failure(error),
    };
    normalize_n64(&mut header, order);
    if header[0..4] != [0x80, 0x37, 0x12, 0x40] || header[0x3c] == 0 {
        return ProbeResult::Failure(ContentRecognitionError::Malformed);
    }
    let mut hasher = CanonicalHasher::new();
    let result = match order {
        N64Order::Native => hash_range(reader, 0, source_length, &mut hasher),
        N64Order::Swapped16 => hash_transformed_range(
            reader,
            0,
            source_length,
            2,
            |bytes| {
                for pair in bytes.chunks_exact_mut(2) {
                    pair.swap(0, 1);
                }
            },
            &mut hasher,
        ),
        N64Order::Swapped32 => hash_transformed_range(
            reader,
            0,
            source_length,
            4,
            |bytes| {
                for word in bytes.chunks_exact_mut(4) {
                    word.reverse();
                }
            },
            &mut hasher,
        ),
    };
    if let Err(error) = result {
        return ProbeResult::Failure(error);
    }
    ProbeResult::Candidate(candidate(
        PlatformId::NintendoN64,
        ContentType::CartridgeImage,
        match order {
            N64Order::Native => "n64-native",
            N64Order::Swapped16 => "n64-byteswapped16",
            N64Order::Swapped32 => "n64-byteswapped32",
        },
        hasher,
    ))
}

fn normalize_n64(header: &mut [u8], order: N64Order) {
    match order {
        N64Order::Native => {}
        N64Order::Swapped16 => {
            for pair in header.chunks_exact_mut(2) {
                pair.swap(0, 1);
            }
        }
        N64Order::Swapped32 => {
            for word in header.chunks_exact_mut(4) {
                word.reverse();
            }
        }
    }
}

fn probe_snes(reader: &mut dyn ContentReader, source_length: u64) -> ProbeResult {
    let mut candidates = Vec::new();
    for (prefix, header_offset, representation) in [
        (0_u64, 0x7fc0_u64, "snes-linear"),
        (512_u64, 0x7fc0_u64, "snes-copier-headered"),
        (0_u64, 0xffc0_u64, "snes-linear"),
        (512_u64, 0xffc0_u64, "snes-copier-headered"),
        (0_u64, 0x40ffc0_u64, "snes-linear"),
        (512_u64, 0x40ffc0_u64, "snes-copier-headered"),
    ] {
        let absolute_header = prefix + header_offset;
        if !in_range(absolute_header, 0x40, source_length) {
            continue;
        }
        let header = match read_small(reader, absolute_header, 0x40) {
            Ok(header) => header,
            Err(error) => return ProbeResult::Failure(error),
        };
        if !valid_snes_header(&header) {
            continue;
        }
        let rom_length = source_length - prefix;
        if rom_length < 0x8000 || !rom_length.is_multiple_of(0x8000) {
            continue;
        }
        if header[0x27] != 0 {
            let declared = 1024_u64.checked_shl(u32::from(header[0x27])).unwrap_or(0);
            if declared != rom_length {
                continue;
            }
        }
        let mut hasher = CanonicalHasher::new();
        if let Err(error) = hash_range(reader, prefix, rom_length, &mut hasher) {
            return ProbeResult::Failure(error);
        }
        candidates.push(candidate(
            PlatformId::NintendoSnes,
            ContentType::CartridgeImage,
            representation,
            hasher,
        ));
    }
    match candidates.as_slice() {
        [] => ProbeResult::NotApplicable,
        [candidate] => ProbeResult::Candidate(*candidate),
        _ => ProbeResult::Failure(ContentRecognitionError::AmbiguousContentRecognition),
    }
}

fn valid_snes_header(header: &[u8]) -> bool {
    if !matches!(header[0x15], 0x20 | 0x21 | 0x25 | 0x30 | 0x31 | 0x35)
        || u16::from_le_bytes([header[0x3c], header[0x3d]]) == 0
        || !header[0..0x15]
            .iter()
            .any(|byte| byte.is_ascii_graphic() || *byte == b' ')
    {
        return false;
    }
    let complement = u16::from_le_bytes([header[0x1c], header[0x1d]]);
    let checksum = u16::from_le_bytes([header[0x1e], header[0x1f]]);
    (complement == 0 && checksum == 0) || complement ^ checksum == 0xffff
}

fn probe_nds(reader: &mut dyn ContentReader, source_length: u64) -> ProbeResult {
    let header = match read_small(reader, 0, 0x200) {
        Ok(header) => header,
        Err(error) => return ProbeResult::Failure(error),
    };
    if !header[0x0c..0x10]
        .iter()
        .all(|byte| byte.is_ascii_uppercase() || byte.is_ascii_digit())
        || header[0xc0..0x15c] != GBA_LOGO
    {
        return ProbeResult::NotApplicable;
    }
    let stored_logo_crc = u16::from_le_bytes([header[0x15c], header[0x15d]]);
    if crc16(&header[0xc0..0x15c]) != stored_logo_crc {
        return ProbeResult::Failure(ContentRecognitionError::Malformed);
    }
    let stored_crc = u16::from_le_bytes([header[0x15e], header[0x15f]]);
    if crc16(&header[..0x15e]) != stored_crc {
        return ProbeResult::Failure(ContentRecognitionError::Malformed);
    }
    let total_used = read_header_u32(&header, 0x80);
    let header_size = read_header_u32(&header, 0x84);
    if total_used < 0x200
        || !total_used.is_multiple_of(4)
        || header_size != 0x4000
        || header_size > total_used
    {
        return ProbeResult::Failure(ContentRecognitionError::Malformed);
    }
    if total_used > source_length {
        return ProbeResult::Failure(ContentRecognitionError::Truncated);
    }

    let mut regions = Vec::new();
    for (start_offset, size_offset, optional) in [
        (0x20, 0x2c, false),
        (0x30, 0x3c, false),
        (0x40, 0x44, false),
        (0x48, 0x4c, false),
        (0x50, 0x54, true),
        (0x58, 0x5c, true),
    ] {
        let start = read_header_u32(&header, start_offset);
        let length = read_header_u32(&header, size_offset);
        if start == 0 && length == 0 && optional {
            continue;
        }
        if start == 0
            || length == 0
            || !start.is_multiple_of(4)
            || !length.is_multiple_of(4)
            || start < header_size
        {
            return ProbeResult::Failure(ContentRecognitionError::Malformed);
        }
        let Some(end) = start.checked_add(length) else {
            return ProbeResult::Failure(ContentRecognitionError::ResourceLimitExceeded);
        };
        if end > total_used {
            return ProbeResult::Failure(ContentRecognitionError::Malformed);
        }
        if end > source_length {
            return ProbeResult::Failure(ContentRecognitionError::Truncated);
        }
        regions.push((start, end));
    }
    for (index, (start, end)) in regions.iter().enumerate() {
        if regions
            .iter()
            .skip(index + 1)
            .any(|(other_start, other_end)| *start < *other_end && *other_start < *end)
        {
            return ProbeResult::Failure(ContentRecognitionError::Malformed);
        }
    }
    if let Err(error) = validate_nds_filesystem(
        reader,
        total_used,
        read_header_u32(&header, 0x40),
        read_header_u32(&header, 0x44),
        read_header_u32(&header, 0x48),
        read_header_u32(&header, 0x4c),
        read_header_u32(&header, 0x50),
        read_header_u32(&header, 0x54),
        read_header_u32(&header, 0x58),
        read_header_u32(&header, 0x5c),
    ) {
        return ProbeResult::Failure(error);
    }
    let mut hasher = CanonicalHasher::new();
    if let Err(error) = hash_range(reader, 0, total_used, &mut hasher) {
        return ProbeResult::Failure(error);
    }
    ProbeResult::Candidate(candidate(
        PlatformId::NintendoNds,
        ContentType::CartridgeImage,
        "raw-cartridge-image",
        hasher,
    ))
}

fn read_header_u32(header: &[u8], offset: usize) -> u64 {
    u64::from(u32::from_le_bytes([
        header[offset],
        header[offset + 1],
        header[offset + 2],
        header[offset + 3],
    ]))
}

#[allow(clippy::too_many_arguments)]
fn validate_nds_filesystem(
    reader: &mut dyn ContentReader,
    logical_length: u64,
    fnt_offset: u64,
    fnt_length: u64,
    fat_offset: u64,
    fat_length: u64,
    arm9_overlay_offset: u64,
    arm9_overlay_length: u64,
    arm7_overlay_offset: u64,
    arm7_overlay_length: u64,
) -> Result<(), ContentRecognitionError> {
    if fnt_length == 0 || fat_length == 0 || !fat_length.is_multiple_of(8) {
        return Err(ContentRecognitionError::Malformed);
    }
    if !in_range(fnt_offset, fnt_length, logical_length)
        || !in_range(fat_offset, fat_length, logical_length)
    {
        return Err(ContentRecognitionError::Malformed);
    }

    let root = read_small(reader, fnt_offset, 8)?;
    let directory_count = u64::from(u16::from_le_bytes([root[6], root[7]]));
    let directory_table_length = directory_count
        .checked_mul(8)
        .ok_or(ContentRecognitionError::ResourceLimitExceeded)?;
    if directory_count == 0
        || directory_table_length > fnt_length
        || u64::from(u32::from_le_bytes([root[0], root[1], root[2], root[3]]))
            < directory_table_length
        || u64::from(u32::from_le_bytes([root[0], root[1], root[2], root[3]])) >= fnt_length
    {
        return Err(ContentRecognitionError::Malformed);
    }

    let fat_file_count = fat_length / 8;
    let fnt_end = fnt_offset + fnt_length;
    let fat_end = fat_offset + fat_length;
    let mut file_count = 0_u64;
    for directory_index in 0..directory_count {
        let entry = read_small(reader, fnt_offset + directory_index * 8, 8)?;
        let subtable_offset =
            u64::from(u32::from_le_bytes([entry[0], entry[1], entry[2], entry[3]]));
        if subtable_offset < directory_table_length || subtable_offset >= fnt_length {
            return Err(ContentRecognitionError::Malformed);
        }
        let mut cursor = fnt_offset + subtable_offset;
        loop {
            if cursor >= fnt_end {
                return Err(ContentRecognitionError::Malformed);
            }
            let length_byte = read_small(reader, cursor, 1)?[0];
            cursor += 1;
            if length_byte == 0 {
                break;
            }
            let name_length = u64::from(length_byte & 0x7f);
            if name_length == 0
                || cursor
                    .checked_add(name_length)
                    .is_none_or(|end| end > fnt_end)
            {
                return Err(ContentRecognitionError::Malformed);
            }
            cursor += name_length;
            if length_byte & 0x80 != 0 {
                if cursor.checked_add(2).is_none_or(|end| end > fnt_end) {
                    return Err(ContentRecognitionError::Malformed);
                }
                let child_directory = read_u16_le(reader, cursor)?;
                if u64::from(child_directory) < 0xf001
                    || u64::from(child_directory) >= 0xf000 + directory_count
                {
                    return Err(ContentRecognitionError::Malformed);
                }
                cursor += 2;
            } else {
                if file_count >= fat_file_count {
                    return Err(ContentRecognitionError::Malformed);
                }
                file_count += 1;
            }
        }
    }
    if file_count != fat_file_count {
        return Err(ContentRecognitionError::Malformed);
    }

    for file_index in 0..fat_file_count {
        let entry = read_small(reader, fat_offset + file_index * 8, 8)?;
        let start = u64::from(u32::from_le_bytes([entry[0], entry[1], entry[2], entry[3]]));
        let end = u64::from(u32::from_le_bytes([entry[4], entry[5], entry[6], entry[7]]));
        if start > end || end > logical_length || !start.is_multiple_of(4) || !end.is_multiple_of(4)
        {
            return Err(ContentRecognitionError::Malformed);
        }
    }
    if fat_end > logical_length || fnt_end > logical_length {
        return Err(ContentRecognitionError::Malformed);
    }
    for (offset, length) in [
        (arm9_overlay_offset, arm9_overlay_length),
        (arm7_overlay_offset, arm7_overlay_length),
    ] {
        if length == 0 {
            if offset != 0 {
                return Err(ContentRecognitionError::Malformed);
            }
            continue;
        }
        if offset == 0 || !length.is_multiple_of(32) || !in_range(offset, length, logical_length) {
            return Err(ContentRecognitionError::Malformed);
        }
        for entry_offset in (offset..offset + length).step_by(32) {
            let entry = read_small(reader, entry_offset, 32)?;
            let file_id = u64::from(u32::from_le_bytes([
                entry[0x18],
                entry[0x19],
                entry[0x1a],
                entry[0x1b],
            ]));
            if file_id >= fat_file_count {
                return Err(ContentRecognitionError::Malformed);
            }
        }
    }
    Ok(())
}

fn read_u16_le(
    reader: &mut dyn ContentReader,
    offset: u64,
) -> Result<u16, ContentRecognitionError> {
    let bytes = read_small(reader, offset, 2)?;
    Ok(u16::from_le_bytes([bytes[0], bytes[1]]))
}

fn crc16(bytes: &[u8]) -> u16 {
    let mut crc = 0xffff_u16;
    for byte in bytes {
        crc ^= u16::from(*byte);
        for _ in 0..8 {
            crc = if crc & 1 != 0 {
                (crc >> 1) ^ 0xa001
            } else {
                crc >> 1
            };
        }
    }
    crc
}

fn read_u32_at(
    reader: &mut dyn ContentReader,
    offset: u64,
) -> Result<u32, ContentRecognitionError> {
    let bytes = read_small(reader, offset, 4)?;
    Ok(u32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]))
}

fn validate_ncch_regions(
    reader: &mut dyn ContentReader,
    ncch_offset: u64,
    content_length: u64,
    partition_end: u64,
) -> Result<(), ContentRecognitionError> {
    if ncch_offset + content_length > partition_end {
        return Err(ContentRecognitionError::Malformed);
    }
    let exheader_size = u64::from(read_u32_at(reader, ncch_offset + 0x180)?);
    let mut regions = Vec::new();
    if exheader_size != 0 {
        let end = 0x200_u64
            .checked_add(exheader_size)
            .ok_or(ContentRecognitionError::ResourceLimitExceeded)?;
        if end > content_length {
            return Err(ContentRecognitionError::Malformed);
        }
        regions.push((0x200, end));
    }
    for (offset_field, length_field, hash_field) in [
        (0x190_u64, 0x194_u64, None),
        (0x198, 0x19c, None),
        (0x1a0, 0x1a4, Some(0x1a8_u64)),
        (0x1b0, 0x1b4, Some(0x1b8_u64)),
    ] {
        let relative_offset = u64::from(read_u32_at(reader, ncch_offset + offset_field)?);
        let length = u64::from(read_u32_at(reader, ncch_offset + length_field)?);
        if relative_offset == 0 && length == 0 {
            if let Some(hash_field) = hash_field
                && read_u32_at(reader, ncch_offset + hash_field)? != 0
            {
                return Err(ContentRecognitionError::Malformed);
            }
            continue;
        }
        if relative_offset == 0 || length == 0 {
            return Err(ContentRecognitionError::Malformed);
        }
        let start = relative_offset
            .checked_mul(0x200)
            .ok_or(ContentRecognitionError::ResourceLimitExceeded)?;
        let end = start
            .checked_add(length.saturating_mul(0x200))
            .ok_or(ContentRecognitionError::ResourceLimitExceeded)?;
        if end > content_length || start < 0x200 {
            return Err(ContentRecognitionError::Malformed);
        }
        if let Some(hash_field) = hash_field {
            let hash_size = u64::from(read_u32_at(reader, ncch_offset + hash_field)?);
            if hash_size > length {
                return Err(ContentRecognitionError::Malformed);
            }
        }
        regions.push((start, end));
    }
    regions.sort_unstable_by_key(|(start, _)| *start);
    if regions.windows(2).any(|pair| pair[0].1 > pair[1].0) {
        return Err(ContentRecognitionError::Malformed);
    }
    Ok(())
}

fn probe_3ds(reader: &mut dyn ContentReader, source_length: u64) -> ProbeResult {
    if source_length < 0x200 {
        return ProbeResult::Failure(ContentRecognitionError::Truncated);
    }
    let header = match read_small(reader, 0, 0x200) {
        Ok(header) => header,
        Err(error) => return ProbeResult::Failure(error),
    };
    let media_units = u64::from(u32::from_le_bytes([
        header[0x104],
        header[0x105],
        header[0x106],
        header[0x107],
    ]));
    let logical_length = media_units.saturating_mul(0x200);
    if logical_length < 0x200 || logical_length > source_length {
        return ProbeResult::Failure(ContentRecognitionError::Malformed);
    }
    let mut partitions = Vec::new();
    for index in 0..8 {
        let base = 0x120 + index * 8;
        let offset = u64::from(u32::from_le_bytes([
            header[base],
            header[base + 1],
            header[base + 2],
            header[base + 3],
        ])) * 0x200;
        let length = u64::from(u32::from_le_bytes([
            header[base + 4],
            header[base + 5],
            header[base + 6],
            header[base + 7],
        ])) * 0x200;
        if length == 0 {
            if offset != 0 {
                return ProbeResult::Failure(ContentRecognitionError::Malformed);
            }
            continue;
        }
        if offset < 0x200 || length < 0x200 || !in_range(offset, length, logical_length) {
            return ProbeResult::Failure(ContentRecognitionError::Malformed);
        }
        let partition_end = offset + length;
        let partition_magic = match read_small(reader, offset + 0x100, 4) {
            Ok(magic) => magic,
            Err(error) => return ProbeResult::Failure(error),
        };
        if partition_magic != b"NCCH" {
            return ProbeResult::Failure(ContentRecognitionError::Malformed);
        }
        let content_size = match read_u32_at(reader, offset + 0x104) {
            Ok(value) => value,
            Err(error) => return ProbeResult::Failure(error),
        };
        let declared_partition_length = u64::from(content_size).saturating_mul(0x200);
        if declared_partition_length == 0
            || declared_partition_length > length
            || offset + declared_partition_length > logical_length
        {
            return ProbeResult::Failure(ContentRecognitionError::Malformed);
        }
        let flags = match read_small(reader, offset + 0x188, 8) {
            Ok(flags) => flags,
            Err(error) => return ProbeResult::Failure(error),
        };
        if flags[7] & 0x04 == 0 {
            return ProbeResult::Failure(ContentRecognitionError::EncryptedContentUnsupported);
        }
        if let Err(error) =
            validate_ncch_regions(reader, offset, declared_partition_length, partition_end)
        {
            return ProbeResult::Failure(error);
        }
        partitions.push((offset, partition_end));
    }
    if partitions.is_empty() {
        return ProbeResult::Failure(ContentRecognitionError::Malformed);
    }
    partitions.sort_unstable_by_key(|(offset, _)| *offset);
    if partitions.windows(2).any(|pair| pair[0].1 > pair[1].0) {
        return ProbeResult::Failure(ContentRecognitionError::Malformed);
    }
    let mut hasher = CanonicalHasher::new();
    if let Err(error) = hash_range(reader, 0, logical_length, &mut hasher) {
        return ProbeResult::Failure(error);
    }
    ProbeResult::Candidate(candidate(
        PlatformId::Nintendo3ds,
        ContentType::CartridgeImage,
        "ncsd-nocrypto",
        hasher,
    ))
}

#[cfg(test)]
mod tests {
    use super::{GBA_LOGO, crc16};

    #[test]
    fn nds_crc16_uses_fixed_reflected_vectors() {
        assert_eq!(crc16(b"123456789"), 0x4b37);
        assert_eq!(crc16(&GBA_LOGO), 0xcf56);
    }
}
