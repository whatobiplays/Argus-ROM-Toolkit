//! Production native/raw content recognition and identity hashing.

use argus_application::{ContentType, IdentityDigest, PlatformId};
use sha2::{Digest, Sha256};
use std::fmt;

#[path = "content_nintendo.rs"]
mod content_nintendo;
#[path = "content_optical.rs"]
mod content_optical;
#[path = "content_sega.rs"]
mod content_sega;
#[path = "content_stream.rs"]
mod content_stream;

pub use content_optical::{
    CueDescriptor, CueTrack, CueTrackMode, GdiDescriptor, GdiTrack, M3uDescriptor, M3uError,
    OpticalDescriptor, OpticalError, OpticalRecognition, OpticalSource, canonicalize_descriptor,
    canonicalize_descriptor_with_cancel, parse_cue, parse_descriptor, parse_gdi, parse_m3u,
    recognize_native_optical, recognize_native_optical_with_cancel,
};
pub use content_stream::{
    ContentProcessingLimits, ContentReadError, ContentReader, ContentRecognitionError,
    StreamRecognizedContent, recognize_content, recognize_content_with_budget,
    recognize_content_with_limits,
};

pub(crate) const GB_LOGO: [u8; 48] = [
    0xCE, 0xED, 0x66, 0x66, 0xCC, 0x0D, 0x00, 0x0B, 0x03, 0x73, 0x00, 0x83, 0x00, 0x0C, 0x00, 0x0D,
    0x00, 0x08, 0x11, 0x1F, 0x88, 0x89, 0x00, 0x0E, 0xDC, 0xCC, 0x6E, 0xE6, 0xDD, 0xDD, 0xD9, 0x99,
    0xBB, 0xBB, 0x67, 0x63, 0x6E, 0x0E, 0xEC, 0xCC, 0xDD, 0xDC, 0x99, 0x9F, 0xBB, 0xB9, 0x33, 0x3E,
];

// GBATEK's authoritative 156-byte compressed Nintendo logo for the GBA header.
pub(crate) const GBA_LOGO: [u8; 156] = [
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

/// Recognition failure for a raw supported cartridge representation.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RecognitionError {
    /// The source is shorter than the representation's required header.
    Truncated,
    /// The source has a valid-looking header but an unsupported length.
    UnsupportedRepresentation,
    /// The GB-family logo is invalid.
    InvalidNintendoLogo,
    /// The GB-family cartridge type is not in the supported contract.
    InvalidCartridgeType,
    /// The GB-family ROM-size code is not supported.
    InvalidRomSize,
    /// The GB-family header checksum is invalid.
    InvalidHeaderChecksum,
    /// A GB-family CGB flag is not one of the exact recognized values.
    InvalidCgbFlag,
    /// The GBA fixed/header complement contract is invalid.
    InvalidGbaHeader,
    /// The source exceeds the configured processing budget.
    ResourceLimitExceeded,
}

/// Upper bound used by the internal cartridge transformation capability.
pub const DEFAULT_CONTENT_PROCESSING_BUDGET_BYTES: usize = 64 * 1024 * 1024;

impl fmt::Display for RecognitionError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(match self {
            Self::Truncated => "cartridge header is truncated",
            Self::UnsupportedRepresentation => {
                "raw cartridge representation has unsupported length"
            }
            Self::InvalidNintendoLogo => "Nintendo logo validation failed",
            Self::InvalidCartridgeType => "cartridge type is unsupported",
            Self::InvalidRomSize => "ROM size code is unsupported",
            Self::InvalidHeaderChecksum => "cartridge header checksum is invalid",
            Self::InvalidCgbFlag => "CGB capability flag is invalid",
            Self::InvalidGbaHeader => "GBA cartridge header validation failed",
            Self::ResourceLimitExceeded => "content processing resource limit exceeded",
        })
    }
}

impl std::error::Error for RecognitionError {}

/// Validated representation and canonical identity facts.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RecognizedContent {
    platform: PlatformId,
    content_type: ContentType,
    canonical_bytes: Vec<u8>,
    identity_digest: IdentityDigest,
    source_representation: &'static str,
}

impl RecognizedContent {
    /// Returns the authoritative recognized platform.
    pub const fn platform(&self) -> PlatformId {
        self.platform
    }

    /// Returns the authoritative recognized content type.
    pub const fn content_type(&self) -> ContentType {
        self.content_type
    }

    /// Returns the legacy source representation accepted by this adapter.
    pub const fn source_representation(&self) -> &'static str {
        self.source_representation
    }

    /// Returns canonical bytes retained for the caller's out-of-transaction use.
    pub fn canonical_bytes(&self) -> &[u8] {
        &self.canonical_bytes
    }

    /// Returns the SHA-256 identity digest.
    pub const fn identity_digest(&self) -> IdentityDigest {
        self.identity_digest
    }
}

/// Recognizes and hashes one complete raw cartridge representation.
pub fn recognize_raw_cartridge(bytes: &[u8]) -> Result<RecognizedContent, RecognitionError> {
    recognize_raw_cartridge_with_budget(bytes, DEFAULT_CONTENT_PROCESSING_BUDGET_BYTES)
}

/// Recognizes and hashes one cartridge while enforcing a caller-supplied
/// processing budget before allocating or hashing the source bytes.
pub fn recognize_raw_cartridge_with_budget(
    bytes: &[u8],
    budget_bytes: usize,
) -> Result<RecognizedContent, RecognitionError> {
    if bytes.len() > budget_bytes {
        return Err(RecognitionError::ResourceLimitExceeded);
    }
    let (platform, canonical_bytes) = if bytes.len() >= 0x150 && bytes[0x104..0x134] == GB_LOGO {
        recognize_gb_family(bytes)?
    } else if bytes.len() >= 0xc0 && bytes[0x04..0xa0] == GBA_LOGO {
        recognize_gba(bytes)?
    } else if bytes.len() < 0xc0 {
        return Err(RecognitionError::Truncated);
    } else {
        return Err(RecognitionError::InvalidNintendoLogo);
    };

    let content_type = ContentType::CartridgeImage;
    let mut hasher = Sha256::new();
    for chunk in canonical_bytes.chunks(64 * 1024) {
        hasher.update(chunk);
    }
    let digest: [u8; 32] = hasher.finalize().into();
    Ok(RecognizedContent {
        platform,
        content_type,
        canonical_bytes,
        identity_digest: IdentityDigest::from_bytes(digest),
        source_representation: "raw-cartridge-image",
    })
}

pub(crate) fn recognize_gb_family(bytes: &[u8]) -> Result<(PlatformId, Vec<u8>), RecognitionError> {
    let cgb_flag = bytes[0x143];
    let platform = match cgb_flag {
        0x00 => PlatformId::NintendoGb,
        0x80 | 0xc0 => PlatformId::NintendoGbc,
        _ => return Err(RecognitionError::InvalidCgbFlag),
    };
    if !valid_cartridge_type(bytes[0x147]) {
        return Err(RecognitionError::InvalidCartridgeType);
    }
    let declared_len = gb_rom_length(bytes[0x148]).ok_or(RecognitionError::InvalidRomSize)?;
    if bytes.len() != declared_len {
        return Err(RecognitionError::UnsupportedRepresentation);
    }
    let mut checksum = 0_u8;
    for byte in &bytes[0x134..0x14d] {
        checksum = checksum.wrapping_sub(*byte).wrapping_sub(1);
    }
    if checksum != bytes[0x14d] {
        return Err(RecognitionError::InvalidHeaderChecksum);
    }
    Ok((platform, bytes.to_vec()))
}

pub(crate) fn recognize_gba(bytes: &[u8]) -> Result<(PlatformId, Vec<u8>), RecognitionError> {
    if bytes.len() < 0xc0
        || !bytes.len().is_multiple_of(4)
        || !valid_gba_entry_point(bytes)
        || bytes[0x04..0xa0] != GBA_LOGO
    {
        return Err(RecognitionError::InvalidGbaHeader);
    }
    if !bytes[0xa0..0xac]
        .iter()
        .all(|byte| *byte == b' ' || byte.is_ascii_graphic())
        || !bytes[0xac..0xb2]
            .iter()
            .all(|byte| byte.is_ascii_uppercase() || byte.is_ascii_digit())
        || bytes[0xb2] != 0x96
        || bytes[0xb3] != 0
        || bytes[0xb4] != 0
        || bytes[0xb5..0xbc].iter().any(|byte| *byte != 0)
        || bytes[0xbe..0xc0].iter().any(|byte| *byte != 0)
    {
        return Err(RecognitionError::InvalidGbaHeader);
    }
    let sum = bytes[0xa0..0xbd]
        .iter()
        .fold(0_u8, |sum, byte| sum.wrapping_add(*byte))
        .wrapping_add(0x19)
        .wrapping_add(bytes[0xbd]);
    if sum != 0 {
        return Err(RecognitionError::InvalidGbaHeader);
    }
    Ok((PlatformId::NintendoGba, bytes.to_vec()))
}

pub(crate) fn valid_gba_entry_point(bytes: &[u8]) -> bool {
    let opcode = u32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]);
    let is_arm_branch =
        (opcode >> 28) == 0xE && ((opcode >> 25) & 0b111) == 0b101 && ((opcode >> 24) & 1) == 0;
    if !is_arm_branch {
        return false;
    }

    let signed_offset = (((opcode & 0x00FF_FFFF) as i32) << 8) >> 6;
    let target_offset = 8_i64 + i64::from(signed_offset);
    target_offset >= 0 && target_offset % 4 == 0 && (target_offset as usize) < bytes.len()
}

pub(crate) fn gb_rom_length(code: u8) -> Option<usize> {
    match code {
        0x00 => Some(0x8000),
        0x01 => Some(0x10000),
        0x02 => Some(0x20000),
        0x03 => Some(0x40000),
        0x04 => Some(0x80000),
        0x05 => Some(0x100000),
        0x06 => Some(0x200000),
        0x07 => Some(0x400000),
        0x08 => Some(0x800000),
        0x52 => Some(0x120000),
        0x53 => Some(0x140000),
        0x54 => Some(0x180000),
        _ => None,
    }
}

pub(crate) fn valid_cartridge_type(value: u8) -> bool {
    matches!(
        value,
        0x00 | 0x01
            | 0x02
            | 0x03
            | 0x05
            | 0x06
            | 0x08
            | 0x09
            | 0x0b
            | 0x0c
            | 0x0d
            | 0x0f
            | 0x10
            | 0x11
            | 0x12
            | 0x13
            | 0x19
            | 0x1a
            | 0x1b
            | 0x1c
            | 0x1d
            | 0x1e
            | 0x20
            | 0x22
            | 0xfc
            | 0xfd
            | 0xfe
            | 0xff
    )
}
