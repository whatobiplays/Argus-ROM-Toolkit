//! Bounded native optical-media parsing and canonicalization.
//!
//! This module deliberately stops at a source-reader boundary. It parses
//! descriptor grammar and canonicalizes bytes from readers supplied by the
//! caller; it never looks up source entries, follows filesystem paths, or
//! consults persistence. The application/runtime layer owns that admission.

use std::fmt;

use argus_application::{ContentType, IdentityDigest, PlatformId};

use super::content_stream::{CanonicalHasher, ContentReader, update_u32, update_u64};

const CD_SECTOR_BYTES: usize = 2_352;
const ISO_SECTOR_BYTES: usize = 2_048;
const MAX_DESCRIPTOR_BYTES: usize = 1024 * 1024;
const MAX_M3U_BYTES: usize = 1024 * 1024;
const MAX_M3U_MEMBERS: usize = 128;
const CD_PREFIX: &[u8] = b"ARGUS-CD-LOGICAL-V1";
const GD_PREFIX: &[u8] = b"ARGUS-GD-LOGICAL-V1";
const PS2_DVD_PREFIX: &[u8] = b"ARGUS-PS2-DVD-V1";
const PSP_PREFIX: &[u8] = b"ARGUS-PSP-UMD-V1";
const GAMECUBE_PREFIX: &[u8] = b"ARGUS-GAMECUBE-DISC-V1";
pub(crate) const WII_PREFIX: &[u8] = b"ARGUS-WII-DISC-V1";
const MAX_ISO_DESCRIPTOR_COUNT: u64 = 64;
const MAX_ISO_DIRECTORY_BYTES: u64 = 16 * 1024 * 1024;
const MAX_ISO_FILE_BYTES: u64 = 16 * 1024 * 1024;
const MAX_ISO_DIRECTORY_ENTRIES: usize = 16_384;
const MAX_PSF_ENTRIES: u32 = 256;
const DREAMCAST_HIGH_DENSITY_LBA: u64 = 45_000;
const MAX_CD_LOGICAL_SECTORS: u64 = 360_000;
const NINTENDO_ALIGNMENT: u64 = 32 * 1024;
const GAMECUBE_BOOT_OFFSET: u64 = 0x2_440;
const WII_PARTITION_TABLE_OFFSET: u64 = 0x40_000;

/// Failure while parsing or canonicalizing one native optical representation.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum OpticalError {
    /// The descriptor grammar or media structure is malformed.
    Malformed,
    /// The source reader ended before a required range was available.
    Truncated,
    /// A referenced source was not supplied by the application-owned resolver.
    MissingDependency,
    /// The dependency set contains duplicate or conflicting entries.
    ConflictingDependency,
    /// A dependency reference escapes the descriptor's admitted scope.
    Traversal,
    /// The representation is valid-looking but outside the activated subset.
    UnsupportedRepresentation,
    /// Two authoritative platform recognizers succeeded.
    AmbiguousPlatform,
    /// A bounded read or canonicalization budget was exceeded.
    ResourceLimitExceeded,
    /// The caller stopped the cancellable operation.
    Cancelled,
    /// The source reader returned an I/O failure.
    ReadFailure,
}

/// Failure while parsing an M3U relationship-evidence playlist.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum M3uError {
    /// The playlist is not bounded UTF-8 text.
    Malformed,
    /// The playlist contains too many bytes or members.
    ResourceLimitExceeded,
    /// A playlist member is empty or contains an unsafe NUL byte.
    InvalidMember,
    /// The same member occurs more than once.
    DuplicateMember,
}

/// Ordered M3U references. This value is relationship evidence only; it is
/// never passed to the content identity catalog.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct M3uDescriptor {
    members: Vec<String>,
}

impl M3uDescriptor {
    /// Returns members in the exact order declared by the playlist.
    pub fn members(&self) -> &[String] {
        &self.members
    }
}

impl fmt::Display for OpticalError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(match self {
            Self::Malformed => "optical structure is malformed",
            Self::Truncated => "optical source is truncated",
            Self::MissingDependency => "optical descriptor dependency is missing",
            Self::ConflictingDependency => "optical dependencies conflict",
            Self::Traversal => "optical dependency escapes its admitted root",
            Self::UnsupportedRepresentation => "optical representation is unsupported",
            Self::AmbiguousPlatform => "optical platform recognition is ambiguous",
            Self::ResourceLimitExceeded => "optical processing resource limit exceeded",
            Self::Cancelled => "optical processing was cancelled",
            Self::ReadFailure => "optical source read failed",
        })
    }
}

impl std::error::Error for OpticalError {}

/// Track sector geometry accepted by the native CUE parser.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CueTrackMode {
    /// 2352-byte PCM audio sectors.
    Audio,
    /// 2048-byte Mode 1 user sectors.
    Mode1_2048,
    /// 2352-byte raw Mode 1 sectors.
    Mode1_2352,
    /// 2336-byte Mode 2 sectors without the raw sync/header.
    Mode2_2336,
    /// 2352-byte raw Mode 2/XA sectors.
    Mode2_2352,
}

impl CueTrackMode {
    fn sector_bytes(self) -> u64 {
        match self {
            Self::Audio | Self::Mode1_2352 | Self::Mode2_2352 => 2_352,
            Self::Mode1_2048 => 2_048,
            Self::Mode2_2336 => 2_336,
        }
    }

    fn track_mode_byte(self) -> u8 {
        match self {
            Self::Audio => 0x01,
            Self::Mode1_2048 | Self::Mode1_2352 => 0x02,
            Self::Mode2_2336 | Self::Mode2_2352 => 0x03,
        }
    }
}

/// One validated CUE track declaration.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CueTrack {
    number: u32,
    mode: CueTrackMode,
    source_name: String,
    index_zero: Option<u64>,
    index_one: u64,
    has_index_one: bool,
    pregap: Option<u64>,
    postgap: u64,
}

impl CueTrack {
    /// Returns the one-based track number.
    pub const fn number(&self) -> u32 {
        self.number
    }

    /// Returns the validated sector mode.
    pub const fn mode(&self) -> CueTrackMode {
        self.mode
    }

    /// Returns the descriptor's source reference.
    pub fn source_name(&self) -> &str {
        &self.source_name
    }

    /// Returns the INDEX 00 frame, when stored pregap bytes exist.
    pub const fn index_zero(&self) -> Option<u64> {
        self.index_zero
    }

    /// Returns the INDEX 01 frame.
    pub const fn index_one(&self) -> u64 {
        self.index_one
    }

    /// Returns the synthesized PREGAP frame count, when declared.
    pub const fn pregap(&self) -> Option<u64> {
        self.pregap
    }

    /// Returns the declared postgap frame count.
    pub const fn postgap(&self) -> u64 {
        self.postgap
    }
}

/// A parsed CUE descriptor with no filesystem or persistence dependency.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CueDescriptor {
    tracks: Vec<CueTrack>,
    dependencies: Vec<String>,
}

impl CueDescriptor {
    /// Returns the tracks in physical descriptor order.
    pub fn tracks(&self) -> &[CueTrack] {
        &self.tracks
    }

    /// Returns each unique source reference in first-use order.
    pub fn dependencies(&self) -> &[String] {
        &self.dependencies
    }
}

/// One validated GDI track declaration.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct GdiTrack {
    number: u32,
    lba: u64,
    track_type: u32,
    sector_bytes: u32,
    source_name: String,
    source_offset: u64,
}

impl GdiTrack {
    /// Returns the track number.
    pub const fn number(&self) -> u32 {
        self.number
    }

    /// Returns the logical start LBA.
    pub const fn lba(&self) -> u64 {
        self.lba
    }

    /// Returns the validated GDI track type.
    pub const fn track_type(&self) -> u32 {
        self.track_type
    }

    /// Returns the physical sector size.
    pub const fn sector_bytes(&self) -> u32 {
        self.sector_bytes
    }

    /// Returns the source reference.
    pub fn source_name(&self) -> &str {
        &self.source_name
    }

    /// Returns the source byte offset.
    pub const fn source_offset(&self) -> u64 {
        self.source_offset
    }
}

/// A parsed GDI descriptor with no dependency-resolution behavior.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct GdiDescriptor {
    tracks: Vec<GdiTrack>,
    dependencies: Vec<String>,
}

impl GdiDescriptor {
    /// Returns the tracks in physical order.
    pub fn tracks(&self) -> &[GdiTrack] {
        &self.tracks
    }

    /// Returns each unique source reference in first-use order.
    pub fn dependencies(&self) -> &[String] {
        &self.dependencies
    }
}

/// One descriptor representation accepted by the native optical path.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum OpticalDescriptor {
    /// CUE/BIN-style CD or Dreamcast descriptor.
    Cue(CueDescriptor),
    /// Dreamcast GDI descriptor.
    Gdi(GdiDescriptor),
}

impl OpticalDescriptor {
    /// Returns the source references required by the descriptor.
    pub fn dependencies(&self) -> &[String] {
        match self {
            Self::Cue(value) => value.dependencies(),
            Self::Gdi(value) => value.dependencies(),
        }
    }
}

/// A caller-admitted reader bound to one descriptor dependency.
pub struct OpticalSource<'a> {
    name: String,
    reader: &'a mut dyn ContentReader,
}

impl<'a> OpticalSource<'a> {
    /// Binds one exact application-resolved name to a bounded reader.
    pub fn new(name: impl Into<String>, reader: &'a mut dyn ContentReader) -> Self {
        Self {
            name: name.into(),
            reader,
        }
    }

    fn matches(&self, name: &str) -> bool {
        self.name == name
    }
}

/// Validated platform, media class, representation, and canonical digest.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct OpticalRecognition {
    platform: PlatformId,
    content_type: ContentType,
    source_representation: &'static str,
    identity_digest: IdentityDigest,
    canonical_length: u64,
}

impl OpticalRecognition {
    /// Returns the authoritative platform.
    pub const fn platform(self) -> PlatformId {
        self.platform
    }

    /// Returns the authoritative media/content class.
    pub const fn content_type(self) -> ContentType {
        self.content_type
    }

    /// Returns the validated storage representation.
    pub const fn source_representation(self) -> &'static str {
        self.source_representation
    }

    /// Returns the canonical identity digest.
    pub const fn identity_digest(self) -> IdentityDigest {
        self.identity_digest
    }

    /// Returns the canonical byte count fed to the digest.
    pub const fn canonical_length(self) -> u64 {
        self.canonical_length
    }

    pub(crate) const fn with_source_representation(
        self,
        source_representation: &'static str,
    ) -> Self {
        Self {
            source_representation,
            ..self
        }
    }
}

/// Parses a descriptor using its authoritative grammar.
pub fn parse_descriptor(bytes: &[u8]) -> Result<OpticalDescriptor, OpticalError> {
    if bytes.len() > MAX_DESCRIPTOR_BYTES {
        return Err(OpticalError::ResourceLimitExceeded);
    }
    let text = std::str::from_utf8(bytes).map_err(|_| OpticalError::Malformed)?;
    let first = text
        .lines()
        .map(str::trim)
        .find(|line| !line.is_empty() && !line.starts_with(';'))
        .ok_or(OpticalError::Malformed)?;
    if first.split_whitespace().next() == Some("FILE") {
        parse_cue(text).map(OpticalDescriptor::Cue)
    } else if first
        .split_whitespace()
        .next()
        .is_some_and(|value| value.parse::<u32>().is_ok())
    {
        parse_gdi(text).map(OpticalDescriptor::Gdi)
    } else {
        Err(OpticalError::UnsupportedRepresentation)
    }
}

/// Parses an ordered UTF-8 M3U playlist without resolving any filesystem path.
pub fn parse_m3u(bytes: &[u8]) -> Result<M3uDescriptor, M3uError> {
    if bytes.len() > MAX_M3U_BYTES {
        return Err(M3uError::ResourceLimitExceeded);
    }
    let text = std::str::from_utf8(bytes).map_err(|_| M3uError::Malformed)?;
    let mut members = Vec::new();
    for (line_index, raw_line) in text.lines().enumerate() {
        let line = raw_line.trim();
        let line = if line_index == 0 {
            line.strip_prefix('\u{feff}').unwrap_or(line)
        } else {
            line
        };
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if line.contains('\0') {
            return Err(M3uError::InvalidMember);
        }
        if members.iter().any(|member| member == line) {
            return Err(M3uError::DuplicateMember);
        }
        if members.len() == MAX_M3U_MEMBERS {
            return Err(M3uError::ResourceLimitExceeded);
        }
        members.push(line.to_owned());
    }
    if members.is_empty() {
        return Err(M3uError::Malformed);
    }
    Ok(M3uDescriptor { members })
}

/// Parses a CUE descriptor and returns only validated layout facts.
pub fn parse_cue(text: &str) -> Result<CueDescriptor, OpticalError> {
    let mut current_file: Option<String> = None;
    let mut tracks = Vec::new();
    let mut dependencies = Vec::new();
    for raw_line in text.lines() {
        let line = raw_line.trim();
        if line.is_empty() || line.starts_with(';') || line.starts_with("REM ") {
            continue;
        }
        let keyword = line
            .split_whitespace()
            .next()
            .ok_or(OpticalError::Malformed)?;
        match keyword {
            "FILE" => {
                let (name, file_type) = parse_file_line(line)?;
                if file_type != "BINARY" {
                    return Err(OpticalError::UnsupportedRepresentation);
                }
                validate_dependency_name(&name)?;
                if !dependencies.iter().any(|value| value == &name) {
                    dependencies.push(name.clone());
                }
                current_file = Some(name);
            }
            "TRACK" => {
                let mut fields = line.split_whitespace();
                fields.next();
                let number = fields
                    .next()
                    .ok_or(OpticalError::Malformed)?
                    .parse::<u32>()
                    .map_err(|_| OpticalError::Malformed)?;
                let mode = parse_cue_mode(fields.next().ok_or(OpticalError::Malformed)?)?;
                let source_name = current_file.clone().ok_or(OpticalError::Malformed)?;
                if tracks.iter().any(|track: &CueTrack| track.number == number) {
                    return Err(OpticalError::ConflictingDependency);
                }
                tracks.push(CueTrack {
                    number,
                    mode,
                    source_name,
                    index_zero: None,
                    index_one: 0,
                    has_index_one: false,
                    pregap: None,
                    postgap: 0,
                });
            }
            "INDEX" => {
                let mut fields = line.split_whitespace();
                fields.next();
                let index = fields
                    .next()
                    .ok_or(OpticalError::Malformed)?
                    .parse::<u32>()
                    .map_err(|_| OpticalError::Malformed)?;
                let frame = parse_msf(fields.next().ok_or(OpticalError::Malformed)?)?;
                let track = tracks.last_mut().ok_or(OpticalError::Malformed)?;
                match index {
                    0 => track.index_zero = Some(frame),
                    1 => {
                        track.index_one = frame;
                        track.has_index_one = true;
                    }
                    _ => return Err(OpticalError::UnsupportedRepresentation),
                }
            }
            "PREGAP" => {
                let frame = parse_msf(
                    line.split_whitespace()
                        .nth(1)
                        .ok_or(OpticalError::Malformed)?,
                )?;
                let track = tracks.last_mut().ok_or(OpticalError::Malformed)?;
                if track.pregap.replace(frame).is_some() {
                    return Err(OpticalError::ConflictingDependency);
                }
            }
            "POSTGAP" => {
                let frame = parse_msf(
                    line.split_whitespace()
                        .nth(1)
                        .ok_or(OpticalError::Malformed)?,
                )?;
                let track = tracks.last_mut().ok_or(OpticalError::Malformed)?;
                if track.postgap != 0 {
                    return Err(OpticalError::ConflictingDependency);
                }
                track.postgap = frame;
            }
            "CATALOG" | "ISRC" | "TITLE" | "PERFORMER" | "SONGWRITER" => {}
            _ => return Err(OpticalError::UnsupportedRepresentation),
        }
    }
    if tracks.is_empty()
        || tracks
            .iter()
            .any(|track| track.index_zero.is_some() && track.pregap.is_some())
        || tracks.iter().any(|track| !track.has_index_one)
    {
        return Err(OpticalError::Malformed);
    }
    for pair in tracks.windows(2) {
        if pair[0].number >= pair[1].number {
            return Err(OpticalError::Malformed);
        }
    }
    Ok(CueDescriptor {
        tracks,
        dependencies,
    })
}

/// Parses a Dreamcast GDI descriptor.
pub fn parse_gdi(text: &str) -> Result<GdiDescriptor, OpticalError> {
    let mut lines = text.lines().map(str::trim).filter(|line| !line.is_empty());
    let count = lines
        .next()
        .ok_or(OpticalError::Malformed)?
        .parse::<usize>()
        .map_err(|_| OpticalError::Malformed)?;
    if count == 0 || count > 99 {
        return Err(OpticalError::Malformed);
    }
    let mut tracks = Vec::with_capacity(count);
    let mut dependencies = Vec::new();
    for _ in 0..count {
        let fields = split_quoted_fields(lines.next().ok_or(OpticalError::Malformed)?);
        if fields.len() != 6 {
            return Err(OpticalError::Malformed);
        }
        let number = fields[0]
            .parse::<u32>()
            .map_err(|_| OpticalError::Malformed)?;
        let lba = fields[1]
            .parse::<u64>()
            .map_err(|_| OpticalError::Malformed)?;
        let track_type = fields[2]
            .parse::<u32>()
            .map_err(|_| OpticalError::Malformed)?;
        let sector_bytes = fields[3]
            .parse::<u32>()
            .map_err(|_| OpticalError::Malformed)?;
        let source_name = fields[4].clone();
        let source_offset = fields[5]
            .parse::<u64>()
            .map_err(|_| OpticalError::Malformed)?;
        if !matches!(sector_bytes, 2_048 | 2_336 | 2_352)
            || !matches!(track_type, 0 | 4)
            || !validate_dependency_name(&source_name).is_ok()
            || tracks.iter().any(|track: &GdiTrack| track.number == number)
        {
            return Err(OpticalError::UnsupportedRepresentation);
        }
        if tracks
            .last()
            .is_some_and(|previous: &GdiTrack| previous.lba >= lba)
        {
            return Err(OpticalError::Malformed);
        }
        if !dependencies.iter().any(|value| value == &source_name) {
            dependencies.push(source_name.clone());
        }
        tracks.push(GdiTrack {
            number,
            lba,
            track_type,
            sector_bytes,
            source_name,
            source_offset,
        });
    }
    if lines.next().is_some() {
        return Err(OpticalError::Malformed);
    }
    Ok(GdiDescriptor {
        tracks,
        dependencies,
    })
}

/// Canonicalizes a descriptor from application-admitted dependency readers.
pub fn canonicalize_descriptor(
    descriptor: &OpticalDescriptor,
    sources: &mut [OpticalSource<'_>],
) -> Result<OpticalRecognition, OpticalError> {
    canonicalize_descriptor_with_cancel(descriptor, sources, &never_cancelled)
}

/// Canonicalizes a descriptor while polling a caller-owned cancellation check.
///
/// The callback is consulted between bounded reads and sector records. It is
/// intentionally supplied by the operation coordinator so this infrastructure
/// module remains independent from durable job state.
pub fn canonicalize_descriptor_with_cancel(
    descriptor: &OpticalDescriptor,
    sources: &mut [OpticalSource<'_>],
    is_cancelled: &dyn Fn() -> bool,
) -> Result<OpticalRecognition, OpticalError> {
    check_cancelled(is_cancelled)?;
    let dependencies = descriptor.dependencies();
    if sources.len() != dependencies.len()
        || dependencies.iter().enumerate().any(|(index, name)| {
            !sources
                .iter()
                .skip(index)
                .any(|source| source.matches(name))
        })
    {
        return Err(OpticalError::MissingDependency);
    }
    match descriptor {
        OpticalDescriptor::Cue(value) => canonicalize_cue(value, sources, is_cancelled),
        OpticalDescriptor::Gdi(value) => canonicalize_gdi(value, sources, is_cancelled),
    }
}

/// Recognizes one complete native 2048-byte ISO or raw GameCube/Wii image.
pub fn recognize_native_optical(
    reader: &mut dyn ContentReader,
) -> Result<OpticalRecognition, OpticalError> {
    recognize_native_optical_with_cancel(reader, &never_cancelled)
}

/// Recognizes native/raw optical content while polling a caller-owned
/// cancellation check between bounded reads.
pub fn recognize_native_optical_with_cancel(
    reader: &mut dyn ContentReader,
    is_cancelled: &dyn Fn() -> bool,
) -> Result<OpticalRecognition, OpticalError> {
    check_cancelled(is_cancelled)?;
    let length = reader.len().map_err(map_reader_error)?;
    if length == 0 {
        return Err(OpticalError::Truncated);
    }
    let first = read_small_cancellable(
        reader,
        0,
        usize::try_from(length.min(0x40)).unwrap_or(0),
        is_cancelled,
    )?;
    let gamecube_magic = first.len() >= 0x20 && first[0x1c..0x20] == [0xc2, 0x33, 0x9f, 0x3d];
    let wii_magic = first.len() >= 0x1c && first[0x18..0x1c] == [0x5d, 0x1c, 0x9e, 0xa3];
    if gamecube_magic && wii_magic {
        return Err(OpticalError::AmbiguousPlatform);
    }
    if gamecube_magic || wii_magic {
        return canonicalize_raw_nintendo_disc(reader, length, wii_magic, is_cancelled);
    }
    canonicalize_iso(reader, length, is_cancelled)
}

fn canonicalize_cue(
    descriptor: &CueDescriptor,
    sources: &mut [OpticalSource<'_>],
    is_cancelled: &dyn Fn() -> bool,
) -> Result<OpticalRecognition, OpticalError> {
    let mut hasher = CanonicalHasher::new();
    hasher.update(CD_PREFIX);
    update_u32(&mut hasher, 1);
    update_u32(&mut hasher, descriptor.tracks[0].number);
    update_u32(
        &mut hasher,
        descriptor
            .tracks
            .last()
            .ok_or(OpticalError::Malformed)?
            .number,
    );
    let mut spans = Vec::with_capacity(descriptor.tracks.len());
    for (index, track) in descriptor.tracks.iter().enumerate() {
        check_cancelled(is_cancelled)?;
        let source_index = source_index(sources, &track.source_name)?;
        let source_length = sources[source_index]
            .reader
            .len()
            .map_err(map_reader_error)?;
        let sector_bytes = track.mode.sector_bytes();
        let start = track
            .index_one
            .checked_mul(sector_bytes)
            .ok_or(OpticalError::ResourceLimitExceeded)?;
        let end = match descriptor.tracks.get(index + 1) {
            Some(next) if next.source_name == track.source_name => next
                .index_zero
                .unwrap_or(next.index_one)
                .checked_mul(next.mode.sector_bytes())
                .ok_or(OpticalError::ResourceLimitExceeded)?,
            _ => source_length,
        };
        if end < start || (end - start) % sector_bytes != 0 {
            return Err(OpticalError::Malformed);
        }
        let stored_pregap = track.index_zero.map(|frame| {
            frame
                .checked_mul(sector_bytes)
                .ok_or(OpticalError::ResourceLimitExceeded)
                .and_then(|offset| start.checked_sub(offset).ok_or(OpticalError::Malformed))
        });
        let stored_pregap = match stored_pregap {
            Some(value) => Some(value?),
            None => None,
        };
        if track.index_zero.is_some() && stored_pregap == Some(0) {
            return Err(OpticalError::Malformed);
        }
        update_u32(&mut hasher, track.number);
        hasher.update(&[track.mode.track_mode_byte()]);
        update_u64(&mut hasher, track.index_one as i64 as u64);
        let pregap_mode = track.mode.track_mode_byte();
        let pregap_kind = if stored_pregap.is_some() {
            0x01
        } else if let Some(frame_count) = track.pregap {
            if frame_count == 0 {
                return Err(OpticalError::Malformed);
            }
            0x02
        } else {
            0x00
        };
        hasher.update(&[pregap_kind, if pregap_kind == 0 { 0 } else { pregap_mode }]);
        let pregap_sectors = stored_pregap
            .map(|value| value / sector_bytes)
            .or(track.pregap)
            .unwrap_or(0);
        update_u64(&mut hasher, pregap_sectors);
        if let Some(stored_bytes) = stored_pregap {
            let stored_offset = start
                .checked_sub(stored_bytes)
                .ok_or(OpticalError::Malformed)?;
            hash_cd_track(
                sources[source_index].reader,
                stored_bytes / sector_bytes,
                sector_bytes,
                stored_offset,
                track.mode,
                &mut hasher,
                is_cancelled,
            )?;
        }
        let main_sectors = (end - start) / sector_bytes;
        update_u64(&mut hasher, main_sectors);
        hash_cd_track(
            sources[source_index].reader,
            main_sectors,
            sector_bytes,
            start,
            track.mode,
            &mut hasher,
            is_cancelled,
        )?;
        spans.push(TrackSpan {
            source_index,
            offset: start,
            sectors: main_sectors,
            sector_bytes,
            mode: track.mode,
            lba: None,
        });
        update_u64(&mut hasher, track.postgap);
    }
    classify_cd_tracks(
        sources,
        &spans,
        hasher,
        "cue-bin",
        false,
        true,
        is_cancelled,
    )
}

fn canonicalize_gdi(
    descriptor: &GdiDescriptor,
    sources: &mut [OpticalSource<'_>],
    is_cancelled: &dyn Fn() -> bool,
) -> Result<OpticalRecognition, OpticalError> {
    let mut hasher = CanonicalHasher::new();
    hasher.update(GD_PREFIX);
    let high_density = descriptor
        .tracks
        .iter()
        .any(|track| track.lba >= DREAMCAST_HIGH_DENSITY_LBA);
    let session_boundary = descriptor
        .tracks
        .iter()
        .position(|track| track.lba >= DREAMCAST_HIGH_DENSITY_LBA)
        .unwrap_or(descriptor.tracks.len());
    if descriptor.tracks.first().is_none_or(|track| track.lba != 0)
        || !high_density
        || session_boundary == 0
        || session_boundary == descriptor.tracks.len()
    {
        return Err(OpticalError::UnsupportedRepresentation);
    }
    let session_count =
        if high_density && session_boundary > 0 && session_boundary < descriptor.tracks.len() {
            2
        } else {
            1
        };
    update_u32(&mut hasher, session_count as u32);
    if session_count == 2 {
        hasher.update(&[0x01]);
        update_u32(&mut hasher, descriptor.tracks[0].number);
        update_u32(&mut hasher, descriptor.tracks[session_boundary - 1].number);
        hasher.update(&[0x02]);
        update_u32(&mut hasher, descriptor.tracks[session_boundary].number);
        update_u32(
            &mut hasher,
            descriptor
                .tracks
                .last()
                .ok_or(OpticalError::Malformed)?
                .number,
        );
    } else {
        hasher.update(&[0x02]);
        update_u32(&mut hasher, descriptor.tracks[0].number);
        update_u32(
            &mut hasher,
            descriptor
                .tracks
                .last()
                .ok_or(OpticalError::Malformed)?
                .number,
        );
    }
    let mut spans = Vec::with_capacity(descriptor.tracks.len());
    for (index, track) in descriptor.tracks.iter().enumerate() {
        check_cancelled(is_cancelled)?;
        let source_index = source_index(sources, &track.source_name)?;
        let source_length = sources[source_index]
            .reader
            .len()
            .map_err(map_reader_error)?;
        let sector_bytes = u64::from(track.sector_bytes);
        let next_offset = descriptor
            .tracks
            .get(index + 1)
            .and_then(|next| (next.source_name == track.source_name).then_some(next.source_offset));
        let end = next_offset.unwrap_or(source_length);
        if end < track.source_offset || !(end - track.source_offset).is_multiple_of(sector_bytes) {
            return Err(OpticalError::Malformed);
        }
        let mode = match (track.track_type, track.sector_bytes) {
            (0, 2_352) => CueTrackMode::Audio,
            (4, 2_048) => CueTrackMode::Mode1_2048,
            (4, 2_336) => CueTrackMode::Mode2_2336,
            (4, 2_352) => CueTrackMode::Mode1_2352,
            _ => return Err(OpticalError::UnsupportedRepresentation),
        };
        let density = if track.lba >= DREAMCAST_HIGH_DENSITY_LBA {
            0x02
        } else {
            0x01
        };
        update_u32(&mut hasher, track.number);
        hasher.update(&[density, mode.track_mode_byte()]);
        update_u64(&mut hasher, track.lba);
        let sector_count = (end - track.source_offset) / sector_bytes;
        update_u64(&mut hasher, sector_count);
        hash_cd_track(
            sources[source_index].reader,
            sector_count,
            sector_bytes,
            track.source_offset,
            mode,
            &mut hasher,
            is_cancelled,
        )?;
        spans.push(TrackSpan {
            source_index,
            offset: track.source_offset,
            sectors: sector_count,
            sector_bytes,
            mode,
            lba: Some(track.lba),
        });
    }
    classify_cd_tracks(sources, &spans, hasher, "gdi", true, true, is_cancelled)
}

fn canonicalize_iso(
    reader: &mut dyn ContentReader,
    length: u64,
    is_cancelled: &dyn Fn() -> bool,
) -> Result<OpticalRecognition, OpticalError> {
    canonicalize_iso_structural(reader, length, is_cancelled)
}

fn canonicalize_raw_nintendo_disc(
    reader: &mut dyn ContentReader,
    length: u64,
    wii: bool,
    is_cancelled: &dyn Fn() -> bool,
) -> Result<OpticalRecognition, OpticalError> {
    if !length.is_multiple_of(NINTENDO_ALIGNMENT) {
        return Err(OpticalError::UnsupportedRepresentation);
    }
    if wii {
        validate_wii_disc(reader, length, is_cancelled)?;
    } else {
        validate_gamecube_disc(reader, length, is_cancelled)?;
    }
    let mut hasher = CanonicalHasher::new();
    if wii {
        hasher.update(WII_PREFIX);
        update_u64(&mut hasher, length);
        update_u32(&mut hasher, 1);
        update_u64(&mut hasher, 0);
        update_u64(&mut hasher, length);
    } else {
        hasher.update(GAMECUBE_PREFIX);
        update_u64(&mut hasher, length);
    }
    hash_range_cancellable(reader, 0, length, &mut hasher, is_cancelled)?;
    let (identity_digest, canonical_length) = hasher.finish();
    Ok(OpticalRecognition {
        platform: if wii {
            PlatformId::NintendoWii
        } else {
            PlatformId::NintendoGameCube
        },
        content_type: if wii {
            ContentType::OpticalDiscWii
        } else {
            ContentType::OpticalDiscGameCube
        },
        source_representation: "raw-disc-image",
        identity_digest,
        canonical_length,
    })
}

#[allow(clippy::too_many_arguments)]
fn hash_cd_track(
    reader: &mut dyn ContentReader,
    sector_count: u64,
    sector_bytes: u64,
    offset: u64,
    mode: CueTrackMode,
    hasher: &mut CanonicalHasher,
    is_cancelled: &dyn Fn() -> bool,
) -> Result<(), OpticalError> {
    let physical_size =
        usize::try_from(sector_bytes).map_err(|_| OpticalError::ResourceLimitExceeded)?;
    if physical_size > CD_SECTOR_BYTES {
        return Err(OpticalError::UnsupportedRepresentation);
    }
    let mut sector = vec![0_u8; physical_size];
    for index in 0..sector_count {
        check_cancelled(is_cancelled)?;
        let sector_offset = offset
            .checked_add(
                index
                    .checked_mul(sector_bytes)
                    .ok_or(OpticalError::ResourceLimitExceeded)?,
            )
            .ok_or(OpticalError::ResourceLimitExceeded)?;
        read_exact_cancellable(reader, sector_offset, &mut sector, is_cancelled)?;
        append_canonical_sector(mode, &sector, hasher)?;
    }
    Ok(())
}

fn append_canonical_sector(
    mode: CueTrackMode,
    sector: &[u8],
    hasher: &mut CanonicalHasher,
) -> Result<(), OpticalError> {
    match mode {
        CueTrackMode::Audio => {
            if sector.len() != 2_352 {
                return Err(OpticalError::Malformed);
            }
            hasher.update(&[0x01]);
            hasher.update(sector);
        }
        CueTrackMode::Mode1_2048 => {
            if sector.len() != 2_048 {
                return Err(OpticalError::Malformed);
            }
            hasher.update(&[0x02]);
            hasher.update(sector);
        }
        CueTrackMode::Mode1_2352 => {
            validate_raw_header(sector, 1)?;
            hasher.update(&[0x02]);
            hasher.update(&sector[16..2064]);
        }
        CueTrackMode::Mode2_2336 => {
            if sector.len() != 2_336 {
                return Err(OpticalError::Malformed);
            }
            hasher.update(&[0x03]);
            hasher.update(sector);
        }
        CueTrackMode::Mode2_2352 => {
            validate_raw_header(sector, 2)?;
            let first = &sector[16..20];
            let second = &sector[20..24];
            if first != second {
                return Err(OpticalError::Malformed);
            }
            let form2 = first[2] & 0x20 != 0;
            let payload = if form2 {
                &sector[24..2348]
            } else {
                &sector[24..2072]
            };
            hasher.update(&[if form2 { 0x05 } else { 0x04 }]);
            hasher.update(first);
            hasher.update(payload);
        }
    }
    Ok(())
}

fn validate_raw_header(sector: &[u8], mode: u8) -> Result<(), OpticalError> {
    if sector.len() != 2_352
        || sector[..12]
            != [
                0, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0,
            ]
        || sector[15] != mode
    {
        return Err(OpticalError::Malformed);
    }
    Ok(())
}

pub(crate) fn finish_recognition(
    platform: PlatformId,
    content_type: ContentType,
    source_representation: &'static str,
    hasher: CanonicalHasher,
) -> OpticalRecognition {
    let (identity_digest, canonical_length) = hasher.finish();
    OpticalRecognition {
        platform,
        content_type,
        source_representation,
        identity_digest,
        canonical_length,
    }
}

#[derive(Clone, Copy)]
struct TrackSpan {
    source_index: usize,
    offset: u64,
    sectors: u64,
    sector_bytes: u64,
    mode: CueTrackMode,
    lba: Option<u64>,
}

struct LogicalTrack<'a> {
    reader: &'a mut dyn ContentReader,
    span: TrackSpan,
}

impl LogicalTrack<'_> {
    fn read_user_sector(
        &mut self,
        index: u64,
        is_cancelled: &dyn Fn() -> bool,
    ) -> Result<Vec<u8>, OpticalError> {
        if index >= self.span.sectors {
            return Err(OpticalError::Truncated);
        }
        let physical_size = usize::try_from(self.span.sector_bytes)
            .map_err(|_| OpticalError::ResourceLimitExceeded)?;
        let offset = self
            .span
            .offset
            .checked_add(
                index
                    .checked_mul(self.span.sector_bytes)
                    .ok_or(OpticalError::ResourceLimitExceeded)?,
            )
            .ok_or(OpticalError::ResourceLimitExceeded)?;
        let physical = read_small_cancellable(self.reader, offset, physical_size, is_cancelled)?;
        logical_sector(self.span.mode, &physical)
    }
}

fn logical_sector(mode: CueTrackMode, sector: &[u8]) -> Result<Vec<u8>, OpticalError> {
    match mode {
        CueTrackMode::Mode1_2048 => {
            if sector.len() != ISO_SECTOR_BYTES {
                return Err(OpticalError::Malformed);
            }
            Ok(sector.to_vec())
        }
        CueTrackMode::Mode1_2352 => {
            validate_raw_header(sector, 1)?;
            Ok(sector[16..2064].to_vec())
        }
        CueTrackMode::Audio | CueTrackMode::Mode2_2336 | CueTrackMode::Mode2_2352 => {
            Err(OpticalError::UnsupportedRepresentation)
        }
    }
}

#[derive(Clone, Debug)]
struct IsoDirectoryEntry {
    name: String,
    extent: u32,
    size: u32,
    directory: bool,
}

#[derive(Clone, Copy)]
struct IsoVolume {
    sector_count: u64,
    root_extent: u32,
    root_size: u32,
}

impl IsoVolume {
    fn parse(
        track: &mut LogicalTrack<'_>,
        is_cancelled: &dyn Fn() -> bool,
    ) -> Result<Self, OpticalError> {
        if track.span.sectors < 18 {
            return Err(OpticalError::UnsupportedRepresentation);
        }
        let pvd = track.read_user_sector(16, is_cancelled)?;
        validate_iso_descriptor(&pvd, 1)?;
        let sector_count = read_iso_both_u32(&pvd, 80)? as u64;
        let volume_set_size = u32::from(read_iso_both_u16(&pvd, 120)?);
        let volume_sequence = u32::from(read_iso_both_u16(&pvd, 124)?);
        let block_size = u32::from(read_iso_both_u16(&pvd, 128)?);
        let path_table_size = read_iso_both_u32(&pvd, 132)? as u64;
        if sector_count == 0
            || sector_count != track.span.sectors
            || volume_set_size != 1
            || volume_sequence != 1
            || block_size as usize != ISO_SECTOR_BYTES
        {
            return Err(OpticalError::Malformed);
        }

        let root = parse_iso_directory_entry(&pvd[156..], true)?;
        if !root.directory || root.extent == 0 || root.size == 0 {
            return Err(OpticalError::Malformed);
        }
        validate_iso_extent(u64::from(root.extent), u64::from(root.size), sector_count)?;

        let mut terminator_found = false;
        for index in 16..sector_count.min(16 + MAX_ISO_DESCRIPTOR_COUNT) {
            let descriptor = track.read_user_sector(index, is_cancelled)?;
            let descriptor_type = descriptor[0];
            if descriptor_type == 0xff {
                validate_iso_descriptor(&descriptor, 0xff)?;
                terminator_found = true;
                break;
            }
            validate_iso_descriptor(&descriptor, descriptor_type)?;
            if index == 16 && descriptor_type != 1 {
                return Err(OpticalError::Malformed);
            }
        }
        if !terminator_found {
            return Err(OpticalError::Malformed);
        }

        if path_table_size == 0 || path_table_size > MAX_ISO_DIRECTORY_BYTES {
            return Err(OpticalError::Malformed);
        }
        let path_table_l = u64::from(read_u32_le(&pvd, 140)?);
        let path_table_m = u64::from(read_u32_be(&pvd, 148)?);
        validate_iso_extent(path_table_l, path_table_size, sector_count)?;
        validate_iso_extent(path_table_m, path_table_size, sector_count)?;
        let path_table = read_logical_range(track, path_table_l, path_table_size, is_cancelled)?;
        validate_path_table(&path_table, root.extent)?;

        Ok(Self {
            sector_count,
            root_extent: root.extent,
            root_size: root.size,
        })
    }

    fn read_file(
        &self,
        track: &mut LogicalTrack<'_>,
        path: &str,
        is_cancelled: &dyn Fn() -> bool,
    ) -> Result<Option<Vec<u8>>, OpticalError> {
        let components = path
            .split('/')
            .filter(|component| !component.is_empty())
            .collect::<Vec<_>>();
        if components.is_empty() || components.len() > 16 {
            return Ok(None);
        }
        let mut extent = self.root_extent;
        let mut size = self.root_size;
        for (component_index, component) in components.iter().enumerate() {
            let entries = self.read_directory(track, extent, size, is_cancelled)?;
            let Some(entry) = entries
                .into_iter()
                .find(|entry| iso_name_matches(&entry.name, component))
            else {
                return Ok(None);
            };
            let last = component_index + 1 == components.len();
            if last {
                if entry.directory {
                    return Ok(None);
                }
                validate_iso_extent(
                    u64::from(entry.extent),
                    u64::from(entry.size),
                    self.sector_count,
                )?;
                if u64::from(entry.size) > MAX_ISO_FILE_BYTES {
                    return Err(OpticalError::ResourceLimitExceeded);
                }
                return read_logical_range(
                    track,
                    u64::from(entry.extent),
                    u64::from(entry.size),
                    is_cancelled,
                )
                .map(Some);
            }
            if !entry.directory {
                return Ok(None);
            }
            validate_iso_extent(
                u64::from(entry.extent),
                u64::from(entry.size),
                self.sector_count,
            )?;
            extent = entry.extent;
            size = entry.size;
        }
        Ok(None)
    }

    fn read_directory(
        &self,
        track: &mut LogicalTrack<'_>,
        extent: u32,
        size: u32,
        is_cancelled: &dyn Fn() -> bool,
    ) -> Result<Vec<IsoDirectoryEntry>, OpticalError> {
        if u64::from(size) > MAX_ISO_DIRECTORY_BYTES {
            return Err(OpticalError::ResourceLimitExceeded);
        }
        validate_iso_extent(u64::from(extent), u64::from(size), self.sector_count)?;
        let bytes = read_logical_range(track, u64::from(extent), u64::from(size), is_cancelled)?;
        let mut entries = Vec::new();
        let mut offset = 0_usize;
        while offset < bytes.len() {
            if bytes[offset] == 0 {
                let next_sector = ((offset / ISO_SECTOR_BYTES) + 1) * ISO_SECTOR_BYTES;
                offset = next_sector.min(bytes.len());
                continue;
            }
            let length = usize::from(bytes[offset]);
            if length < 34 || offset + length > bytes.len() {
                return Err(OpticalError::Malformed);
            }
            let entry = parse_iso_directory_entry(&bytes[offset..offset + length], false)?;
            if !entry.name.is_empty() {
                entries.push(entry);
                if entries.len() > MAX_ISO_DIRECTORY_ENTRIES {
                    return Err(OpticalError::ResourceLimitExceeded);
                }
            }
            offset += length;
        }
        Ok(entries)
    }
}

#[derive(Clone, Copy)]
struct PlatformEvidence {
    platform: PlatformId,
    content_type: ContentType,
}

fn canonicalize_iso_structural(
    reader: &mut dyn ContentReader,
    length: u64,
    is_cancelled: &dyn Fn() -> bool,
) -> Result<OpticalRecognition, OpticalError> {
    if length < 18 * ISO_SECTOR_BYTES as u64 || !length.is_multiple_of(ISO_SECTOR_BYTES as u64) {
        return Err(OpticalError::UnsupportedRepresentation);
    }
    let sector_count = length / ISO_SECTOR_BYTES as u64;
    let span = TrackSpan {
        source_index: 0,
        offset: 0,
        sectors: sector_count,
        sector_bytes: ISO_SECTOR_BYTES as u64,
        mode: CueTrackMode::Mode1_2048,
        lba: Some(0),
    };
    let evidence = {
        let mut track = LogicalTrack { reader, span };
        let volume = IsoVolume::parse(&mut track, is_cancelled)?;
        let dvd = native_dvd_representation(&mut track, is_cancelled)?;
        structural_platform_evidence(&mut track, &volume, false, dvd, is_cancelled)?
    };
    let evidence = select_platform_evidence(evidence)?;
    let mut hasher = CanonicalHasher::new();
    if evidence.content_type == ContentType::OpticalDiscUmd {
        hasher.update(PSP_PREFIX);
        update_u64(&mut hasher, sector_count);
        hash_range_cancellable(reader, 0, length, &mut hasher, is_cancelled)?;
        return Ok(finish_recognition(
            evidence.platform,
            evidence.content_type,
            "iso-2048",
            hasher,
        ));
    }
    if evidence.content_type == ContentType::OpticalDiscDvd {
        hasher.update(PS2_DVD_PREFIX);
        update_u64(&mut hasher, sector_count);
        hash_range_cancellable(reader, 0, length, &mut hasher, is_cancelled)?;
        return Ok(finish_recognition(
            evidence.platform,
            evidence.content_type,
            "iso-2048",
            hasher,
        ));
    }
    hasher.update(CD_PREFIX);
    update_u32(&mut hasher, 1);
    update_u32(&mut hasher, 1);
    update_u32(&mut hasher, 1);
    update_u32(&mut hasher, 1);
    hasher.update(&[0x02]);
    update_u64(&mut hasher, 0);
    hasher.update(&[0x00, 0x00]);
    update_u64(&mut hasher, 0);
    update_u64(&mut hasher, sector_count);
    let mut sector = vec![0_u8; ISO_SECTOR_BYTES];
    for index in 0..sector_count {
        check_cancelled(is_cancelled)?;
        let offset = index
            .checked_mul(ISO_SECTOR_BYTES as u64)
            .ok_or(OpticalError::ResourceLimitExceeded)?;
        read_exact_cancellable(reader, offset, &mut sector, is_cancelled)?;
        hasher.update(&[0x02]);
        hasher.update(&sector);
    }
    update_u64(&mut hasher, 0);
    Ok(finish_recognition(
        evidence.platform,
        evidence.content_type,
        "iso-2048-cd",
        hasher,
    ))
}

fn classify_cd_tracks(
    sources: &mut [OpticalSource<'_>],
    spans: &[TrackSpan],
    hasher: CanonicalHasher,
    representation: &'static str,
    high_density: bool,
    allow_dreamcast: bool,
    is_cancelled: &dyn Fn() -> bool,
) -> Result<OpticalRecognition, OpticalError> {
    let span = if high_density {
        spans.iter().find(|span| {
            span.lba
                .is_some_and(|lba| lba >= DREAMCAST_HIGH_DENSITY_LBA)
        })
    } else {
        spans.iter().find(|span| span.mode != CueTrackMode::Audio)
    }
    .ok_or(OpticalError::UnsupportedRepresentation)?;
    if high_density && span.mode == CueTrackMode::Audio {
        return Err(OpticalError::UnsupportedRepresentation);
    }
    let evidence = {
        let mut track = LogicalTrack {
            reader: sources[span.source_index].reader,
            span: *span,
        };
        let volume = IsoVolume::parse(&mut track, is_cancelled)?;
        structural_platform_evidence(&mut track, &volume, allow_dreamcast, false, is_cancelled)?
    };
    let evidence = select_platform_evidence(evidence)?;
    Ok(finish_recognition(
        evidence.platform,
        evidence.content_type,
        representation,
        hasher,
    ))
}

fn select_platform_evidence(
    evidence: Vec<PlatformEvidence>,
) -> Result<PlatformEvidence, OpticalError> {
    match evidence.as_slice() {
        [single] => Ok(*single),
        [] => Err(OpticalError::UnsupportedRepresentation),
        _ => Err(OpticalError::AmbiguousPlatform),
    }
}

fn structural_platform_evidence(
    track: &mut LogicalTrack<'_>,
    volume: &IsoVolume,
    allow_dreamcast: bool,
    dvd: bool,
    is_cancelled: &dyn Fn() -> bool,
) -> Result<Vec<PlatformEvidence>, OpticalError> {
    let bootstrap = track.read_user_sector(0, is_cancelled)?;
    if bootstrap.starts_with(b"SEGADATADISC") {
        return Err(OpticalError::UnsupportedRepresentation);
    }
    let mut evidence = Vec::new();
    if validate_sega_cd_bootstrap(&bootstrap) {
        evidence.push(PlatformEvidence {
            platform: PlatformId::SegaCd,
            content_type: ContentType::OpticalDiscCd,
        });
    }
    if validate_saturn_bootstrap(&bootstrap) {
        evidence.push(PlatformEvidence {
            platform: PlatformId::SegaSaturn,
            content_type: ContentType::OpticalDiscCd,
        });
    }
    if allow_dreamcast && validate_dreamcast_bootstrap(track, volume, &bootstrap, is_cancelled)? {
        evidence.push(PlatformEvidence {
            platform: PlatformId::SegaDreamcast,
            content_type: ContentType::OpticalDiscGd,
        });
    }
    if validate_psp_content(track, volume, is_cancelled)? {
        evidence.push(PlatformEvidence {
            platform: PlatformId::SonyPsp,
            content_type: ContentType::OpticalDiscUmd,
        });
    }
    if validate_ps2_content(track, volume, is_cancelled)? {
        evidence.push(PlatformEvidence {
            platform: PlatformId::SonyPlaystation2,
            content_type: if dvd {
                ContentType::OpticalDiscDvd
            } else {
                ContentType::OpticalDiscCd
            },
        });
    }
    if validate_ps1_content(track, volume, is_cancelled)? {
        evidence.push(PlatformEvidence {
            platform: PlatformId::SonyPlaystation,
            content_type: ContentType::OpticalDiscCd,
        });
    }
    Ok(evidence)
}

fn validate_sega_cd_bootstrap(bytes: &[u8]) -> bool {
    bytes.len() >= 16
        && &bytes[..14] == b"SEGADISCSYSTEM"
        && bytes[14..16].iter().all(|byte| *byte == 0 || *byte == b' ')
        && matches!(read_u32_be(bytes, 0x30), Ok(0x200))
        && big_endian_range(bytes, 0x34, 0x200, 0x2_000)
        && matches!(read_u32_be(bytes, 0x40), Ok(0x800) | Ok(0x1_000))
        && big_endian_range(bytes, 0x44, 0x1_000, 0x10_000)
        && !bytes.starts_with(b"SEGADATADISC")
}

fn validate_saturn_bootstrap(bytes: &[u8]) -> bool {
    bytes.starts_with(b"SEGA SEGASATURN ")
}

fn validate_dreamcast_bootstrap(
    track: &mut LogicalTrack<'_>,
    volume: &IsoVolume,
    bytes: &[u8],
    is_cancelled: &dyn Fn() -> bool,
) -> Result<bool, OpticalError> {
    if !bytes.starts_with(b"SEGA SEGAKATANA ")
        || !ascii_field_is(
            bytes.get(0x10..0x20).unwrap_or_default(),
            b"SEGA ENTERPRISES",
        )
        || !ascii_field_is(bytes.get(0x40..0x4a).unwrap_or_default(), b"HDR-")
        || !ascii_field_is(bytes.get(0x4a..0x50).unwrap_or_default(), b"V")
        || !bytes
            .get(0x50..0x58)
            .is_some_and(|date| date.iter().all(u8::is_ascii_digit))
    {
        return Ok(false);
    }
    let Some(boot_name) = ascii_field(bytes.get(0x60..0x70).unwrap_or_default()) else {
        return Ok(false);
    };
    let Some(boot) = volume.read_file(track, &boot_name, is_cancelled)? else {
        return Ok(false);
    };
    Ok(boot.len() >= 8)
}

fn validate_ps1_content(
    track: &mut LogicalTrack<'_>,
    volume: &IsoVolume,
    is_cancelled: &dyn Fn() -> bool,
) -> Result<bool, OpticalError> {
    let Some(system_cnf) = volume.read_file(track, "SYSTEM.CNF", is_cancelled)? else {
        return Ok(false);
    };
    let Some(boot_path) = parse_boot_path(&system_cnf, "BOOT") else {
        return Ok(false);
    };
    let Some(boot) = volume.read_file(track, &boot_path, is_cancelled)? else {
        return Ok(false);
    };
    Ok(boot.len() >= 0x800 && boot.starts_with(b"PS-X EXE"))
}

fn validate_ps2_content(
    track: &mut LogicalTrack<'_>,
    volume: &IsoVolume,
    is_cancelled: &dyn Fn() -> bool,
) -> Result<bool, OpticalError> {
    let Some(system_cnf) = volume.read_file(track, "SYSTEM.CNF", is_cancelled)? else {
        return Ok(false);
    };
    let Some(boot_path) = parse_boot_path(&system_cnf, "BOOT2") else {
        return Ok(false);
    };
    let Some(boot) = volume.read_file(track, &boot_path, is_cancelled)? else {
        return Ok(false);
    };
    Ok(!boot.is_empty())
}

fn validate_psp_content(
    track: &mut LogicalTrack<'_>,
    volume: &IsoVolume,
    is_cancelled: &dyn Fn() -> bool,
) -> Result<bool, OpticalError> {
    let Some(param) = volume.read_file(track, "PSP_GAME/PARAM.SFO", is_cancelled)? else {
        return Ok(false);
    };
    let Some(umd_data) = volume.read_file(track, "UMD_DATA.BIN", is_cancelled)? else {
        return Ok(false);
    };
    if umd_data.is_empty() || !validate_param_sfo(&param) {
        return Ok(false);
    }
    let eboot = volume
        .read_file(track, "PSP_GAME/SYSDIR/EBOOT.BIN", is_cancelled)?
        .or(volume.read_file(track, "PSP_GAME/SYSDIR/BOOT.BIN", is_cancelled)?);
    Ok(eboot.is_some_and(|bytes| !bytes.is_empty()))
}

fn parse_boot_path(bytes: &[u8], key: &str) -> Option<String> {
    let text = std::str::from_utf8(bytes).ok()?;
    for line in text.lines() {
        let Some((name, value)) = line.split_once('=') else {
            continue;
        };
        if !name.trim().eq_ignore_ascii_case(key) {
            continue;
        }
        let token = value.split_whitespace().next()?.trim_matches('"');
        let (_, path) = token.split_once('\\')?;
        let path = path.trim_matches('\\').replace('\\', "/");
        if path.is_empty() || path.contains('\0') {
            return None;
        }
        return Some(path);
    }
    None
}

fn validate_param_sfo(bytes: &[u8]) -> bool {
    if bytes.len() < 20 || &bytes[..4] != b"\0PSF" {
        return false;
    }
    let Some(key_start) = read_u32_le(bytes, 8).ok().map(|value| value as usize) else {
        return false;
    };
    let Some(data_start) = read_u32_le(bytes, 12).ok().map(|value| value as usize) else {
        return false;
    };
    let Ok(entry_count) = read_u32_le(bytes, 16) else {
        return false;
    };
    if entry_count == 0 || entry_count > MAX_PSF_ENTRIES {
        return false;
    }
    let Some(entries_end) = 20_usize.checked_add(entry_count as usize * 16) else {
        return false;
    };
    if key_start < entries_end || data_start < key_start || data_start > bytes.len() {
        return false;
    }
    let mut disc_id = false;
    let mut bootable = false;
    let mut category = false;
    let mut system_version = false;
    for index in 0..entry_count as usize {
        let offset = 20 + index * 16;
        let Ok(key_offset) = read_u16_le(bytes, offset) else {
            return false;
        };
        let Ok(value_type) = read_u16_le(bytes, offset + 2) else {
            return false;
        };
        let Ok(data_length) = read_u32_le(bytes, offset + 4) else {
            return false;
        };
        let Ok(data_max_length) = read_u32_le(bytes, offset + 8) else {
            return false;
        };
        let Ok(data_offset) = read_u32_le(bytes, offset + 12) else {
            return false;
        };
        if data_length > data_max_length
            || key_start + usize::from(key_offset) >= data_start
            || data_start
                .checked_add(data_offset as usize)
                .and_then(|start| start.checked_add(data_length as usize))
                .is_none_or(|end| end > bytes.len())
        {
            return false;
        }
        let key_bytes = &bytes[key_start + usize::from(key_offset)..data_start];
        let Some(key_end) = key_bytes.iter().position(|byte| *byte == 0) else {
            return false;
        };
        let Ok(key) = std::str::from_utf8(&key_bytes[..key_end]) else {
            return false;
        };
        let data_start_offset = data_start + data_offset as usize;
        let value = &bytes[data_start_offset..data_start_offset + data_length as usize];
        match key {
            "DISC_ID" => {
                disc_id = value.starts_with(b"UL") || value.starts_with(b"UC");
            }
            "BOOTABLE" => {
                bootable = value_type == 0x0404 && value.len() >= 4 && value[..4] == [1, 0, 0, 0];
            }
            "CATEGORY" => category = value.starts_with(b"UG"),
            "PSP_SYSTEM_VER" => system_version = value.iter().any(|byte| *byte != 0),
            _ => {}
        }
    }
    disc_id && bootable && category && system_version
}

fn native_dvd_representation(
    track: &mut LogicalTrack<'_>,
    is_cancelled: &dyn Fn() -> bool,
) -> Result<bool, OpticalError> {
    if track.span.sectors > MAX_CD_LOGICAL_SECTORS {
        return Ok(true);
    }
    if track.span.sectors <= 258 {
        return Ok(false);
    }
    let first = track.read_user_sector(256, is_cancelled)?;
    if first.get(1..6) != Some(b"BEA01") {
        return Ok(false);
    }
    let second = track.read_user_sector(257, is_cancelled)?;
    let third = track.read_user_sector(258, is_cancelled)?;
    Ok(second.get(1..6) == Some(b"NSR02")
        || second.get(1..6) == Some(b"NSR03")
        || third.get(1..6) == Some(b"TEA01"))
}

fn validate_iso_descriptor(bytes: &[u8], expected_type: u8) -> Result<(), OpticalError> {
    if bytes.len() != ISO_SECTOR_BYTES
        || bytes[0] != expected_type
        || &bytes[1..6] != b"CD001"
        || bytes[6] != 1
    {
        return Err(OpticalError::Malformed);
    }
    Ok(())
}

fn parse_iso_directory_entry(
    bytes: &[u8],
    allow_root_prefix: bool,
) -> Result<IsoDirectoryEntry, OpticalError> {
    if bytes.len() < 33 || usize::from(bytes[0]) > bytes.len() || bytes[0] < 34 {
        return Err(OpticalError::Malformed);
    }
    let record_length = usize::from(bytes[0]);
    let name_length = usize::from(bytes[32]);
    if 33 + name_length > record_length {
        return Err(OpticalError::Malformed);
    }
    let name_bytes = &bytes[33..33 + name_length];
    let name = if name_bytes == [0] || name_bytes == [1] {
        String::new()
    } else {
        std::str::from_utf8(name_bytes)
            .map_err(|_| OpticalError::Malformed)?
            .to_owned()
    };
    if allow_root_prefix && !name.is_empty() {
        return Err(OpticalError::Malformed);
    }
    let extent = read_iso_both_u32(bytes, 2)?;
    let size = read_iso_both_u32(bytes, 10)?;
    Ok(IsoDirectoryEntry {
        name,
        extent,
        size,
        directory: bytes[25] & 0x02 != 0,
    })
}

fn validate_path_table(bytes: &[u8], root_extent: u32) -> Result<(), OpticalError> {
    if bytes.len() < 10 {
        return Err(OpticalError::Malformed);
    }
    let mut offset = 0_usize;
    let mut first = true;
    let mut count = 0_usize;
    while offset < bytes.len() {
        if bytes[offset] == 0 {
            break;
        }
        if offset + 8 > bytes.len() {
            return Err(OpticalError::Malformed);
        }
        let name_length = usize::from(bytes[offset]);
        let record_length = 8 + name_length + usize::from(name_length % 2 == 1);
        if record_length < 8 || offset + record_length > bytes.len() {
            return Err(OpticalError::Malformed);
        }
        let extent = read_u32_le(bytes, offset + 2)?;
        let parent = read_u16_le(bytes, offset + 6)?;
        if first && (extent != root_extent || parent != 1 || name_length != 1) {
            return Err(OpticalError::Malformed);
        }
        first = false;
        count += 1;
        if count > MAX_ISO_DIRECTORY_ENTRIES {
            return Err(OpticalError::ResourceLimitExceeded);
        }
        offset += record_length;
    }
    if first {
        return Err(OpticalError::Malformed);
    }
    Ok(())
}

fn read_logical_range(
    track: &mut LogicalTrack<'_>,
    first_sector: u64,
    length: u64,
    is_cancelled: &dyn Fn() -> bool,
) -> Result<Vec<u8>, OpticalError> {
    if length > MAX_ISO_FILE_BYTES {
        return Err(OpticalError::ResourceLimitExceeded);
    }
    let last_sector = first_sector
        .checked_add(length.saturating_add((ISO_SECTOR_BYTES - 1) as u64) / ISO_SECTOR_BYTES as u64)
        .ok_or(OpticalError::ResourceLimitExceeded)?;
    if last_sector > track.span.sectors {
        return Err(OpticalError::Truncated);
    }
    let mut result =
        vec![0_u8; usize::try_from(length).map_err(|_| OpticalError::ResourceLimitExceeded)?];
    let mut written = 0_usize;
    let mut sector = first_sector;
    while written < result.len() {
        let bytes = track.read_user_sector(sector, is_cancelled)?;
        let count = (result.len() - written).min(ISO_SECTOR_BYTES);
        result[written..written + count].copy_from_slice(&bytes[..count]);
        written += count;
        sector += 1;
    }
    Ok(result)
}

fn validate_iso_extent(extent: u64, size: u64, sector_count: u64) -> Result<(), OpticalError> {
    let sectors = size.saturating_add((ISO_SECTOR_BYTES - 1) as u64) / ISO_SECTOR_BYTES as u64;
    if extent == 0
        || extent
            .checked_add(sectors)
            .is_none_or(|end| end > sector_count)
    {
        return Err(OpticalError::Malformed);
    }
    Ok(())
}

fn iso_name_matches(name: &str, requested: &str) -> bool {
    name.eq_ignore_ascii_case(requested)
        || (!requested.contains(';')
            && name
                .strip_suffix(";1")
                .is_some_and(|without_version| without_version.eq_ignore_ascii_case(requested)))
}

fn ascii_field(bytes: &[u8]) -> Option<String> {
    let end = bytes
        .iter()
        .position(|byte| *byte == 0)
        .unwrap_or(bytes.len());
    let field = &bytes[..end];
    if field.is_empty()
        || field
            .iter()
            .any(|byte| !byte.is_ascii_graphic() && *byte != b' ')
    {
        return None;
    }
    let value = std::str::from_utf8(field).ok()?.trim().to_owned();
    (!value.is_empty()).then_some(value)
}

fn ascii_field_is(bytes: &[u8], prefix: &[u8]) -> bool {
    ascii_field(bytes).is_some_and(|value| value.as_bytes().starts_with(prefix))
}

fn big_endian_range(bytes: &[u8], offset: usize, minimum: u32, maximum: u32) -> bool {
    read_u32_be(bytes, offset).is_ok_and(|value| (minimum..=maximum).contains(&value))
}

fn validate_gamecube_disc(
    reader: &mut dyn ContentReader,
    length: u64,
    is_cancelled: &dyn Fn() -> bool,
) -> Result<(), OpticalError> {
    if length < NINTENDO_ALIGNMENT {
        return Err(OpticalError::UnsupportedRepresentation);
    }
    let header = read_range_vec(reader, 0, 0x430, is_cancelled)?;
    if &header[0x1c..0x20] != [0xc2, 0x33, 0x9f, 0x3d].as_slice()
        || header[..6].iter().all(|byte| *byte == 0)
    {
        return Err(OpticalError::Malformed);
    }
    let app_header = read_range_vec(reader, GAMECUBE_BOOT_OFFSET, 0x20, is_cancelled)?;
    let app_size = u64::from(read_u32_be(&app_header, 0x14)?);
    let trailer_size = u64::from(read_u32_be(&app_header, 0x18)?);
    let app_end = GAMECUBE_BOOT_OFFSET
        .checked_add(0x20)
        .and_then(|value| value.checked_add(app_size))
        .and_then(|value| value.checked_add(trailer_size))
        .ok_or(OpticalError::ResourceLimitExceeded)?;
    if app_size == 0 || app_end > length {
        return Err(OpticalError::Malformed);
    }
    let dol_offset = u64::from(read_u32_be(&header, 0x420)?);
    let fst_offset = u64::from(read_u32_be(&header, 0x424)?);
    let fst_size = u64::from(read_u32_be(&header, 0x428)?);
    let fst_max_size = u64::from(read_u32_be(&header, 0x42c)?);
    if fst_size < 24
        || fst_max_size < fst_size
        || fst_offset < app_end
        || fst_offset
            .checked_add(fst_size)
            .is_none_or(|end| end > length)
    {
        return Err(OpticalError::Malformed);
    }
    validate_gamecube_dol(reader, dol_offset, length, is_cancelled)?;
    let fst = read_range_vec(
        reader,
        fst_offset,
        usize::try_from(fst_size).map_err(|_| OpticalError::ResourceLimitExceeded)?,
        is_cancelled,
    )?;
    validate_gamecube_fst(&fst, length)
}

fn validate_gamecube_dol(
    reader: &mut dyn ContentReader,
    offset: u64,
    length: u64,
    is_cancelled: &dyn Fn() -> bool,
) -> Result<(), OpticalError> {
    let header = read_range_vec(reader, offset, 0x100, is_cancelled)?;
    let mut sections = 0_usize;
    for index in 0..18 {
        let section_offset = u64::from(read_u32_be(&header, index * 4)?);
        let size_offset = if index < 7 {
            0x90 + index * 4
        } else {
            0xac + (index - 7) * 4
        };
        let section_size = u64::from(read_u32_be(&header, size_offset)?);
        if section_offset == 0 && section_size == 0 {
            continue;
        }
        if section_offset < offset
            || section_offset
                .checked_add(section_size)
                .is_none_or(|end| end > length)
        {
            return Err(OpticalError::Malformed);
        }
        sections += 1;
    }
    if sections == 0 {
        return Err(OpticalError::Malformed);
    }
    Ok(())
}

fn validate_gamecube_fst(fst: &[u8], length: u64) -> Result<(), OpticalError> {
    if fst.len() < 24 || fst[0] == 0 {
        return Err(OpticalError::Malformed);
    }
    let entry_count =
        usize::try_from(read_u32_be(fst, 8)?).map_err(|_| OpticalError::ResourceLimitExceeded)?;
    if !(2..=MAX_ISO_DIRECTORY_ENTRIES).contains(&entry_count) || entry_count * 12 > fst.len() {
        return Err(OpticalError::Malformed);
    }
    let string_start = entry_count * 12;
    if string_start >= fst.len() || fst[string_start..].iter().all(|byte| *byte != 0) {
        return Err(OpticalError::Malformed);
    }
    let root_next = read_u32_be(fst, 8)? as usize;
    if root_next != entry_count || read_u32_be(fst, 4)? != 0 {
        return Err(OpticalError::Malformed);
    }
    for index in 0..entry_count {
        let entry = &fst[index * 12..index * 12 + 12];
        let name_offset = (read_u32_be(entry, 0)? & 0x00ff_ffff) as usize;
        if name_offset >= fst.len() - string_start {
            return Err(OpticalError::Malformed);
        }
        let name_start = string_start + name_offset;
        if fst[name_start..]
            .iter()
            .position(|byte| *byte == 0)
            .is_none()
        {
            return Err(OpticalError::Malformed);
        }
        let directory = entry[0] != 0;
        if directory {
            let parent = read_u32_be(entry, 4)? as usize;
            let next = read_u32_be(entry, 8)? as usize;
            if index == 0 {
                if parent != 0 || next != entry_count {
                    return Err(OpticalError::Malformed);
                }
            } else if parent >= index || next <= index || next > entry_count {
                return Err(OpticalError::Malformed);
            }
        } else {
            let file_offset = u64::from(read_u32_be(entry, 4)?);
            let file_size = u64::from(read_u32_be(entry, 8)?);
            if file_offset
                .checked_add(file_size)
                .is_none_or(|end| end > length)
            {
                return Err(OpticalError::Malformed);
            }
        }
    }
    Ok(())
}

fn validate_wii_disc(
    reader: &mut dyn ContentReader,
    length: u64,
    is_cancelled: &dyn Fn() -> bool,
) -> Result<(), OpticalError> {
    if length < WII_PARTITION_TABLE_OFFSET + 8 {
        return Err(OpticalError::UnsupportedRepresentation);
    }
    let header = read_range_vec(reader, 0, 0x400, is_cancelled)?;
    if &header[0x18..0x1c] != [0x5d, 0x1c, 0x9e, 0xa3].as_slice()
        || header[..6].iter().all(|byte| *byte == 0)
    {
        return Err(OpticalError::Malformed);
    }
    let table_header = read_range_vec(reader, WII_PARTITION_TABLE_OFFSET, 8, is_cancelled)?;
    let partition_count = u64::from(read_u32_be(&table_header, 0)?);
    let table_offset_words = u64::from(read_u32_be(&table_header, 4)?);
    if partition_count == 0 || partition_count > 64 {
        return Err(OpticalError::Malformed);
    }
    let table_start = WII_PARTITION_TABLE_OFFSET
        .checked_add(
            table_offset_words
                .checked_mul(4)
                .ok_or(OpticalError::ResourceLimitExceeded)?,
        )
        .ok_or(OpticalError::ResourceLimitExceeded)?;
    let table_length = partition_count
        .checked_mul(8)
        .ok_or(OpticalError::ResourceLimitExceeded)?;
    if table_start
        .checked_add(table_length)
        .is_none_or(|end| end > length)
    {
        return Err(OpticalError::Malformed);
    }
    let table = read_range_vec(
        reader,
        table_start,
        usize::try_from(table_length).map_err(|_| OpticalError::ResourceLimitExceeded)?,
        is_cancelled,
    )?;
    let mut ranges = Vec::with_capacity(partition_count as usize);
    let mut has_data = false;
    for index in 0..partition_count as usize {
        let entry = &table[index * 8..index * 8 + 8];
        let partition_offset = u64::from(read_u32_be(entry, 0)?)
            .checked_mul(4)
            .ok_or(OpticalError::ResourceLimitExceeded)?;
        let partition_type = read_u32_be(entry, 4)?;
        if !matches!(partition_type, 0..=2)
            || partition_offset < 0x50_000
            || !partition_offset.is_multiple_of(NINTENDO_ALIGNMENT)
            || partition_offset
                .checked_add(0x2c0)
                .is_none_or(|end| end > length)
        {
            return Err(OpticalError::Malformed);
        }
        let partition_header = read_range_vec(reader, partition_offset, 0x2c0, is_cancelled)?;
        let data_offset = u64::from(read_u32_be(&partition_header, 0x2b8)?)
            .checked_mul(4)
            .ok_or(OpticalError::ResourceLimitExceeded)?;
        let data_size = u64::from(read_u32_be(&partition_header, 0x2bc)?)
            .checked_mul(4)
            .ok_or(OpticalError::ResourceLimitExceeded)?;
        let data_start = partition_offset
            .checked_add(data_offset)
            .ok_or(OpticalError::ResourceLimitExceeded)?;
        let data_end = data_start
            .checked_add(data_size)
            .ok_or(OpticalError::ResourceLimitExceeded)?;
        if data_size == 0 || data_start < partition_offset + 0x2c0 || data_end > length {
            return Err(OpticalError::Malformed);
        }
        ranges.push((partition_offset, data_end));
        has_data |= partition_type == 0;
    }
    ranges.sort_unstable_by_key(|(start, _)| *start);
    if ranges.windows(2).any(|pair| pair[0].1 > pair[1].0) || !has_data {
        return Err(OpticalError::Malformed);
    }
    Ok(())
}

fn read_range_vec(
    reader: &mut dyn ContentReader,
    offset: u64,
    length: usize,
    is_cancelled: &dyn Fn() -> bool,
) -> Result<Vec<u8>, OpticalError> {
    if length == 0 || length > 16 * 1024 * 1024 {
        return Err(OpticalError::ResourceLimitExceeded);
    }
    let mut bytes = vec![0_u8; length];
    read_exact_cancellable(reader, offset, &mut bytes, is_cancelled)?;
    Ok(bytes)
}

fn read_u16_le(bytes: &[u8], offset: usize) -> Result<u16, OpticalError> {
    let end = offset
        .checked_add(2)
        .ok_or(OpticalError::ResourceLimitExceeded)?;
    let value = bytes.get(offset..end).ok_or(OpticalError::Malformed)?;
    Ok(u16::from_le_bytes([value[0], value[1]]))
}

fn read_u16_be(bytes: &[u8], offset: usize) -> Result<u16, OpticalError> {
    let end = offset
        .checked_add(2)
        .ok_or(OpticalError::ResourceLimitExceeded)?;
    let value = bytes.get(offset..end).ok_or(OpticalError::Malformed)?;
    Ok(u16::from_be_bytes([value[0], value[1]]))
}

fn read_u32_le(bytes: &[u8], offset: usize) -> Result<u32, OpticalError> {
    let end = offset
        .checked_add(4)
        .ok_or(OpticalError::ResourceLimitExceeded)?;
    let value = bytes.get(offset..end).ok_or(OpticalError::Malformed)?;
    Ok(u32::from_le_bytes([value[0], value[1], value[2], value[3]]))
}

fn read_u32_be(bytes: &[u8], offset: usize) -> Result<u32, OpticalError> {
    let end = offset
        .checked_add(4)
        .ok_or(OpticalError::ResourceLimitExceeded)?;
    let value = bytes.get(offset..end).ok_or(OpticalError::Malformed)?;
    Ok(u32::from_be_bytes([value[0], value[1], value[2], value[3]]))
}

fn read_iso_both_u32(bytes: &[u8], offset: usize) -> Result<u32, OpticalError> {
    let little = read_u32_le(bytes, offset)?;
    let big = read_u32_be(bytes, offset + 4)?;
    if little != big {
        return Err(OpticalError::Malformed);
    }
    Ok(little)
}

fn read_iso_both_u16(bytes: &[u8], offset: usize) -> Result<u16, OpticalError> {
    let little = read_u16_le(bytes, offset)?;
    let big = read_u16_be(bytes, offset + 2)?;
    if little != big {
        return Err(OpticalError::Malformed);
    }
    Ok(little)
}

fn source_index(sources: &[OpticalSource<'_>], name: &str) -> Result<usize, OpticalError> {
    let mut found = None;
    for (index, source) in sources.iter().enumerate() {
        if source.matches(name) {
            if found.is_some() {
                return Err(OpticalError::ConflictingDependency);
            }
            found = Some(index);
        }
    }
    found.ok_or(OpticalError::MissingDependency)
}

fn parse_file_line(line: &str) -> Result<(String, String), OpticalError> {
    let rest = line
        .strip_prefix("FILE")
        .ok_or(OpticalError::Malformed)?
        .trim();
    let quote_start = rest.find('"').ok_or(OpticalError::Malformed)?;
    let quote_end = rest[quote_start + 1..]
        .find('"')
        .map(|index| quote_start + 1 + index)
        .ok_or(OpticalError::Malformed)?;
    let name = rest[quote_start + 1..quote_end].to_owned();
    let file_type = rest[quote_end + 1..]
        .split_whitespace()
        .next()
        .ok_or(OpticalError::Malformed)?
        .to_ascii_uppercase();
    Ok((name, file_type))
}

fn parse_cue_mode(value: &str) -> Result<CueTrackMode, OpticalError> {
    match value.to_ascii_uppercase().as_str() {
        "AUDIO" => Ok(CueTrackMode::Audio),
        "MODE1/2048" => Ok(CueTrackMode::Mode1_2048),
        "MODE1/2352" => Ok(CueTrackMode::Mode1_2352),
        "MODE2/2336" => Ok(CueTrackMode::Mode2_2336),
        "MODE2/2352" => Ok(CueTrackMode::Mode2_2352),
        _ => Err(OpticalError::UnsupportedRepresentation),
    }
}

fn parse_msf(value: &str) -> Result<u64, OpticalError> {
    let mut fields = value.split(':');
    let minutes = fields
        .next()
        .ok_or(OpticalError::Malformed)?
        .parse::<u64>()
        .map_err(|_| OpticalError::Malformed)?;
    let seconds = fields
        .next()
        .ok_or(OpticalError::Malformed)?
        .parse::<u64>()
        .map_err(|_| OpticalError::Malformed)?;
    let frames = fields
        .next()
        .ok_or(OpticalError::Malformed)?
        .parse::<u64>()
        .map_err(|_| OpticalError::Malformed)?;
    if fields.next().is_some() || seconds >= 60 || frames >= 75 {
        return Err(OpticalError::Malformed);
    }
    minutes
        .checked_mul(60 * 75)
        .and_then(|value| value.checked_add(seconds * 75))
        .and_then(|value| value.checked_add(frames))
        .ok_or(OpticalError::ResourceLimitExceeded)
}

fn split_quoted_fields(line: &str) -> Vec<String> {
    let mut fields = Vec::new();
    let mut current = String::new();
    let mut quoted = false;
    for character in line.chars() {
        match character {
            '"' => quoted = !quoted,
            value if value.is_whitespace() && !quoted => {
                if !current.is_empty() {
                    fields.push(std::mem::take(&mut current));
                }
            }
            value => current.push(value),
        }
    }
    if !current.is_empty() {
        fields.push(current);
    }
    fields
}

fn validate_dependency_name(name: &str) -> Result<(), OpticalError> {
    if name.is_empty()
        || name.starts_with('/')
        || name.starts_with('\\')
        || name.contains(':')
        || name
            .split(['/', '\\'])
            .any(|part| part == ".." || part.is_empty())
    {
        return Err(OpticalError::Traversal);
    }
    Ok(())
}

fn read_small_cancellable(
    reader: &mut dyn ContentReader,
    offset: u64,
    length: usize,
    is_cancelled: &dyn Fn() -> bool,
) -> Result<Vec<u8>, OpticalError> {
    check_cancelled(is_cancelled)?;
    if length == 0 || length > reader.max_read_size() {
        return Err(OpticalError::ResourceLimitExceeded);
    }
    let mut bytes = vec![0_u8; length];
    read_exact_cancellable(reader, offset, &mut bytes, is_cancelled)?;
    Ok(bytes)
}

fn read_exact_cancellable(
    reader: &mut dyn ContentReader,
    offset: u64,
    destination: &mut [u8],
    is_cancelled: &dyn Fn() -> bool,
) -> Result<(), OpticalError> {
    if destination.is_empty() {
        return Ok(());
    }
    let chunk_size = reader.max_read_size().min(64 * 1024);
    if chunk_size == 0 {
        return Err(OpticalError::ResourceLimitExceeded);
    }
    let mut position = offset;
    let mut written = 0_usize;
    while written < destination.len() {
        check_cancelled(is_cancelled)?;
        let end = written + (destination.len() - written).min(chunk_size);
        let count = reader
            .read_at(position, &mut destination[written..end])
            .map_err(map_reader_error)?;
        if count == 0 {
            return Err(OpticalError::Truncated);
        }
        position = position
            .checked_add(count as u64)
            .ok_or(OpticalError::ResourceLimitExceeded)?;
        written += count;
    }
    Ok(())
}

fn hash_range_cancellable(
    reader: &mut dyn ContentReader,
    offset: u64,
    length: u64,
    hasher: &mut CanonicalHasher,
    is_cancelled: &dyn Fn() -> bool,
) -> Result<(), OpticalError> {
    let buffer_size = reader.max_read_size().min(64 * 1024);
    if buffer_size == 0 {
        return Err(OpticalError::ResourceLimitExceeded);
    }
    let mut buffer = vec![0_u8; buffer_size];
    let mut position = offset;
    let mut remaining = length;
    while remaining > 0 {
        check_cancelled(is_cancelled)?;
        let count = remaining.min(buffer.len() as u64) as usize;
        read_exact_cancellable(reader, position, &mut buffer[..count], is_cancelled)?;
        hasher.update(&buffer[..count]);
        position = position
            .checked_add(count as u64)
            .ok_or(OpticalError::ResourceLimitExceeded)?;
        remaining -= count as u64;
    }
    Ok(())
}

fn check_cancelled(is_cancelled: &dyn Fn() -> bool) -> Result<(), OpticalError> {
    if is_cancelled() {
        Err(OpticalError::Cancelled)
    } else {
        Ok(())
    }
}

fn never_cancelled() -> bool {
    false
}

fn map_reader_error(error: super::content_stream::ContentReadError) -> OpticalError {
    match error {
        super::content_stream::ContentReadError::OutOfRange => OpticalError::Truncated,
        super::content_stream::ContentReadError::RequestTooLarge => {
            OpticalError::ResourceLimitExceeded
        }
        super::content_stream::ContentReadError::Io => OpticalError::ReadFailure,
    }
}
