//! Pure-Rust CHD decoding at the existing optical recognition boundary.
//!
//! CHD is a transport format, not an identity format. This adapter validates
//! the CHD header and media metadata, exposes the decoded logical sectors to
//! the established optical recognizers, and changes only the reported storage
//! representation. It never creates a CHD-specific identity scheme.

use std::collections::HashMap;
use std::fs::File;
use std::io::{Read, Seek, SeekFrom};

use argus_application::TransformationFailure;
use chd::metadata::{Metadata, MetadataTag};
use chd::{Chd, Error as ChdError};

use super::content_optical::{
    OpticalDescriptor, OpticalError, OpticalRecognition, OpticalSource, canonicalize_descriptor,
    parse_cue, parse_gdi, recognize_native_optical_with_cancel,
};
use super::content_session::ParsingSession;
use super::content_stream::{ContentReadError, ContentReader};

const CD_USER_DATA_OFFSET: u64 = 16;
const CD_USER_SECTOR_BYTES: u64 = 2_048;
const MAX_CHD_TRACKS: usize = 99;
const MAX_CHD_METADATA_BYTES: usize = 1024 * 1024;
const CHD_METADATA_HEADER_BYTES: u64 = 16;
const CHD_CD_TAGS: [[u8; 4]; 2] = [*b"CHTR", *b"CHT2"];
const CHD_GD_TAG: [u8; 4] = *b"CHGD";
const CHD_DVD_TAG: [u8; 4] = *b"DVD ";
const CHD_UMD_TAG: [u8; 4] = *b"UMD ";

/// Recognizes one CHD-backed optical representation.
///
/// The source is staged before the parser receives it so CHD's seekable API
/// cannot observe a changing provider stream. Every decoded logical byte and
/// media-metadata parsing unit is charged to the caller's shared session.
pub fn recognize_chd(
    reader: &mut dyn ContentReader,
    session: &mut ParsingSession<'_>,
) -> Result<OpticalRecognition, OpticalError> {
    session.check_cancelled().map_err(map_session_error)?;
    let staged = session
        .stage_content_reader("chd", reader)
        .map_err(map_session_error)?;
    let file = staged.reopen().map_err(|_| OpticalError::ReadFailure)?;
    let mut chd = Chd::open(file, None).map_err(map_chd_error)?;
    let metadata = read_metadata(&mut chd, session)?;
    let media = classify_media(&metadata)?;
    let logical_bytes = chd.header().logical_bytes();
    let hunk_count = u64::from(chd.header().hunk_count());
    if logical_bytes == 0 || chd.header().hunk_size() == 0 {
        return Err(OpticalError::Malformed);
    }
    let hunk_size = u64::from(chd.header().hunk_size());
    session
        .charge_parser_work(
            hunk_count
                .checked_mul(hunk_size)
                .ok_or(OpticalError::ResourceLimitExceeded)?,
        )
        .map_err(map_session_error)?;
    match media {
        ChdMedia::Cd(mut tracks) => {
            let output_length = prepare_cd_geometry(
                &mut tracks,
                logical_bytes,
                u64::from(chd.header().unit_bytes()),
            )?;
            session
                .charge_expanded(output_length)
                .map_err(map_session_error)?;
            let mut decoded =
                ChdPayloadReader::new(chd, ChdPayloadKind::Cd(tracks.clone()), session)?;
            session
                .charge_parser_work(output_length)
                .map_err(map_session_error)?;
            let cancelled = || session.check_cancelled().is_err();
            let descriptor = cue_descriptor(&tracks)?;
            let mut source = [OpticalSource::new("chd-track.bin", &mut decoded)];
            let recognition = canonicalize_descriptor(&descriptor, &mut source)
                .map_err(|error| map_decoded_optical_error(error, &cancelled))?;
            Ok(recognition.with_source_representation("chd-cd"))
        }
        ChdMedia::Gd(mut tracks) => {
            let output_length = prepare_cd_geometry(
                &mut tracks,
                logical_bytes,
                u64::from(chd.header().unit_bytes()),
            )?;
            session
                .charge_expanded(output_length)
                .map_err(map_session_error)?;
            let mut decoded =
                ChdPayloadReader::new(chd, ChdPayloadKind::Cd(tracks.clone()), session)?;
            session
                .charge_parser_work(output_length)
                .map_err(map_session_error)?;
            let cancelled = || session.check_cancelled().is_err();
            let descriptor = gdi_descriptor(&tracks)?;
            let mut source = [OpticalSource::new("chd-track.bin", &mut decoded)];
            let recognition = canonicalize_descriptor(&descriptor, &mut source)
                .map_err(|error| map_decoded_optical_error(error, &cancelled))?;
            if recognition.content_type() != argus_application::ContentType::OpticalDiscGd {
                return Err(OpticalError::UnsupportedRepresentation);
            }
            Ok(recognition.with_source_representation("chd-gd"))
        }
        ChdMedia::Direct(tag) => {
            if chd.header().unit_bytes() != CD_USER_SECTOR_BYTES as u32
                || !logical_bytes.is_multiple_of(CD_USER_SECTOR_BYTES)
            {
                return Err(OpticalError::Malformed);
            }
            session
                .charge_expanded(logical_bytes)
                .map_err(map_session_error)?;
            let mut decoded = ChdPayloadReader::new(chd, ChdPayloadKind::Direct, session)?;
            session
                .charge_parser_work(logical_bytes)
                .map_err(map_session_error)?;
            let cancelled = || session.check_cancelled().is_err();
            let recognition = recognize_native_optical_with_cancel(&mut decoded, &cancelled)?;
            let representation = if recognition.content_type()
                == argus_application::ContentType::OpticalDiscUmd
            {
                "chd-umd"
            } else if recognition.content_type() == argus_application::ContentType::OpticalDiscDvd {
                "chd-dvd"
            } else {
                return Err(OpticalError::UnsupportedRepresentation);
            };
            let expected_tag = if representation == "chd-umd" {
                CHD_UMD_TAG
            } else {
                CHD_DVD_TAG
            };
            if tag != expected_tag {
                return Err(OpticalError::UnsupportedRepresentation);
            }
            Ok(recognition.with_source_representation(representation))
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
enum ChdMedia {
    Cd(Vec<ChdTrack>),
    Gd(Vec<ChdTrack>),
    Direct([u8; 4]),
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct ChdTrack {
    number: u32,
    frames: u64,
    pregap: u64,
    postgap: u64,
    stored_pregap: bool,
    start_frame: u64,
    output_offset: u64,
    output_frames: u64,
    data_offset: u64,
    mode: ChdTrackMode,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum ChdTrackMode {
    Audio,
    Mode1_2048,
    Mode1_2352,
    Mode2_2336,
    Mode2_2352,
}

impl ChdTrackMode {
    fn sector_bytes(self) -> u64 {
        match self {
            Self::Audio | Self::Mode1_2352 | Self::Mode2_2352 => 2_352,
            Self::Mode1_2048 => 2_048,
            Self::Mode2_2336 => 2_336,
        }
    }

    fn cue_mode(self) -> &'static str {
        match self {
            Self::Audio => "AUDIO",
            Self::Mode1_2048 => "MODE1/2048",
            Self::Mode1_2352 => "MODE1/2352",
            Self::Mode2_2336 => "MODE2/2336",
            Self::Mode2_2352 => "MODE2/2352",
        }
    }

    fn gdi_type(self) -> u32 {
        match self {
            Self::Audio => 0,
            Self::Mode1_2048 | Self::Mode1_2352 | Self::Mode2_2336 | Self::Mode2_2352 => 4,
        }
    }

    fn data_offset(self, unit_bytes: u64) -> Result<u64, OpticalError> {
        let offset = if self == Self::Mode1_2048 && unit_bytes > CD_USER_SECTOR_BYTES {
            CD_USER_DATA_OFFSET
        } else {
            0
        };
        if offset
            .checked_add(self.sector_bytes())
            .is_none_or(|end| end > unit_bytes)
        {
            return Err(OpticalError::UnsupportedRepresentation);
        }
        Ok(offset)
    }
}

fn read_metadata(
    chd: &mut Chd<File>,
    session: &mut ParsingSession<'_>,
) -> Result<Vec<Metadata>, OpticalError> {
    let Some(mut offset) = chd.header().meta_offset() else {
        return Ok(Vec::new());
    };
    let mut result = Vec::new();
    let mut indices = HashMap::<u32, u32>::new();
    let mut seen_offsets = std::collections::HashSet::new();
    let mut total = 0_usize;
    while offset != 0 {
        if !seen_offsets.insert(offset) {
            return Err(OpticalError::Malformed);
        }
        session.check_cancelled().map_err(map_session_error)?;
        session
            .charge_parser_work(CHD_METADATA_HEADER_BYTES)
            .map_err(map_session_error)?;
        let mut header = [0_u8; CHD_METADATA_HEADER_BYTES as usize];
        chd.inner()
            .seek(SeekFrom::Start(offset))
            .map_err(map_metadata_io_error)?;
        chd.inner()
            .read_exact(&mut header)
            .map_err(map_metadata_io_error)?;
        let metatag = u32::from_be_bytes(header[..4].try_into().expect("metadata tag"));
        let raw_length = u32::from_be_bytes(header[4..8].try_into().expect("metadata length"));
        let length = raw_length & 0x00ff_ffff;
        total = total
            .checked_add(length as usize)
            .ok_or(OpticalError::ResourceLimitExceeded)?;
        if total > MAX_CHD_METADATA_BYTES {
            return Err(OpticalError::ResourceLimitExceeded);
        }
        session
            .charge_parser_work(u64::from(length))
            .map_err(map_session_error)?;
        let next = u64::from_be_bytes(header[8..16].try_into().expect("metadata next"));
        if next != 0 && next <= offset {
            return Err(OpticalError::Malformed);
        }
        let mut value = vec![0_u8; length as usize];
        let value_offset = offset
            .checked_add(CHD_METADATA_HEADER_BYTES)
            .ok_or(OpticalError::ResourceLimitExceeded)?;
        chd.inner()
            .seek(SeekFrom::Start(value_offset))
            .map_err(map_metadata_io_error)?;
        chd.inner()
            .read_exact(&mut value)
            .map_err(map_metadata_io_error)?;
        let index = indices.entry(metatag).or_insert(0);
        let metadata = Metadata {
            metatag,
            value,
            flags: (raw_length >> 24) as u8,
            index: *index,
            length,
        };
        *index = (*index)
            .checked_add(1)
            .ok_or(OpticalError::ResourceLimitExceeded)?;
        result.push(metadata);
        offset = next;
    }
    Ok(result)
}

fn classify_media(metadata: &[Metadata]) -> Result<ChdMedia, OpticalError> {
    let mut tracks = Vec::new();
    let mut direct = None;
    for entry in metadata {
        let tag = tag_bytes(entry.metatag());
        if CHD_CD_TAGS.contains(&tag) || tag == CHD_GD_TAG {
            tracks.push(parse_track(entry)?);
        } else if (tag == CHD_DVD_TAG || tag == CHD_UMD_TAG) && direct.replace(tag).is_some() {
            return Err(OpticalError::Malformed);
        }
    }
    if !tracks.is_empty() && direct.is_some() {
        return Err(OpticalError::Malformed);
    }
    if let Some(tag) = direct {
        return Ok(ChdMedia::Direct(tag));
    }
    if tracks.is_empty() {
        return Err(OpticalError::UnsupportedRepresentation);
    }
    let is_gd = metadata
        .iter()
        .any(|entry| tag_bytes(entry.metatag()) == CHD_GD_TAG);
    if is_gd {
        Ok(ChdMedia::Gd(tracks))
    } else {
        Ok(ChdMedia::Cd(tracks))
    }
}

fn parse_track(metadata: &Metadata) -> Result<ChdTrack, OpticalError> {
    let value = metadata
        .value
        .strip_suffix(&[0])
        .unwrap_or(metadata.value.as_slice());
    let text = std::str::from_utf8(value).map_err(|_| OpticalError::Malformed)?;
    let mut number = None;
    let mut frames = None;
    let mut pregap = 0_u64;
    let mut postgap = 0_u64;
    let mut mode = None;
    let mut subtype = None;
    let mut pregap_virtual = false;
    let mut pregap_mode = None;
    let mut pregap_subtype = None;
    for field in text.split_whitespace() {
        let Some((key, value)) = field.split_once(':') else {
            return Err(OpticalError::Malformed);
        };
        match key {
            "TRACK" => {
                number = Some(
                    u32::try_from(parse_metadata_u64(value)?)
                        .map_err(|_| OpticalError::ResourceLimitExceeded)?,
                );
            }
            "TYPE" => {
                mode = Some(parse_track_mode(value)?);
            }
            "FRAMES" => frames = Some(parse_metadata_u64(value)?),
            "PREGAP" => pregap = parse_metadata_u64(value)?,
            "POSTGAP" => postgap = parse_metadata_u64(value)?,
            "PGTYPE" => {
                if value.eq_ignore_ascii_case("V") {
                    pregap_virtual = true;
                } else {
                    pregap_mode = Some(parse_track_mode(value)?);
                }
            }
            "SUBTYPE" => subtype = Some(value.to_ascii_uppercase()),
            "PGSUB" => pregap_subtype = Some(value.to_ascii_uppercase()),
            "PAD" => {}
            _ => return Err(OpticalError::Malformed),
        }
    }
    let number = number.ok_or(OpticalError::Malformed)?;
    let frames = frames.ok_or(OpticalError::Malformed)?;
    let mode = mode.ok_or(OpticalError::Malformed)?;
    if number == 0 || frames == 0 {
        return Err(OpticalError::Malformed);
    }
    let stored_pregap = pregap != 0 && !pregap_virtual;
    if stored_pregap && pregap_mode.is_some_and(|pregap_mode| pregap_mode != mode) {
        return Err(OpticalError::UnsupportedRepresentation);
    }
    if stored_pregap
        && subtype
            .as_ref()
            .zip(pregap_subtype.as_ref())
            .is_some_and(|(subtype, pregap_subtype)| subtype != pregap_subtype)
    {
        return Err(OpticalError::UnsupportedRepresentation);
    }
    Ok(ChdTrack {
        number,
        frames,
        pregap,
        postgap,
        stored_pregap,
        start_frame: 0,
        output_offset: 0,
        output_frames: frames,
        data_offset: 0,
        mode,
    })
}

fn parse_track_mode(value: &str) -> Result<ChdTrackMode, OpticalError> {
    match value.to_ascii_uppercase().as_str() {
        "AUDIO" => Ok(ChdTrackMode::Audio),
        "MODE1" => Ok(ChdTrackMode::Mode1_2048),
        "MODE1_RAW" => Ok(ChdTrackMode::Mode1_2352),
        "MODE2" => Ok(ChdTrackMode::Mode2_2336),
        "MODE2_RAW" => Ok(ChdTrackMode::Mode2_2352),
        _ => Err(OpticalError::UnsupportedRepresentation),
    }
}

fn prepare_cd_geometry(
    tracks: &mut [ChdTrack],
    logical_bytes: u64,
    unit_bytes: u64,
) -> Result<u64, OpticalError> {
    if tracks.is_empty() || tracks.len() > MAX_CHD_TRACKS {
        return Err(OpticalError::Malformed);
    }
    if unit_bytes == 0 || !logical_bytes.is_multiple_of(unit_bytes) {
        return Err(OpticalError::Malformed);
    }
    let frame_count = logical_bytes / unit_bytes;
    let mut expected_number = 1_u32;
    let mut start_frame = 0_u64;
    let mut output_offset = 0_u64;
    for track in tracks {
        if track.number != expected_number {
            return Err(OpticalError::Malformed);
        }
        let data_offset = track.mode.data_offset(unit_bytes)?;
        if track.stored_pregap && track.pregap >= track.frames {
            return Err(OpticalError::Malformed);
        }
        let output_frames = track.frames;
        let output_bytes = output_frames
            .checked_mul(track.mode.sector_bytes())
            .ok_or(OpticalError::ResourceLimitExceeded)?;
        track.start_frame = start_frame;
        track.output_offset = output_offset;
        track.output_frames = output_frames;
        track.data_offset = data_offset;
        expected_number = expected_number
            .checked_add(1)
            .ok_or(OpticalError::ResourceLimitExceeded)?;
        let end = start_frame
            .checked_add(track.frames)
            .ok_or(OpticalError::ResourceLimitExceeded)?;
        if end > frame_count {
            return Err(OpticalError::Truncated);
        }
        let padding = (4 - (track.frames % 4)) % 4;
        start_frame = end
            .checked_add(padding)
            .ok_or(OpticalError::ResourceLimitExceeded)?;
        output_offset = output_offset
            .checked_add(output_bytes)
            .ok_or(OpticalError::ResourceLimitExceeded)?;
    }
    if start_frame != frame_count {
        return Err(OpticalError::Malformed);
    }
    Ok(output_offset)
}

fn cue_descriptor(tracks: &[ChdTrack]) -> Result<OpticalDescriptor, OpticalError> {
    let mut text = String::new();
    for track in tracks {
        let sector_bytes = track.mode.sector_bytes();
        if !track.output_offset.is_multiple_of(sector_bytes) {
            return Err(OpticalError::UnsupportedRepresentation);
        }
        let file_frame = track.output_offset / sector_bytes;
        let minutes = file_frame / (60 * 75);
        let seconds = file_frame / 75 % 60;
        let frames = file_frame % 75;
        let index_one = if track.stored_pregap {
            file_frame
                .checked_add(track.pregap)
                .ok_or(OpticalError::ResourceLimitExceeded)?
        } else {
            file_frame
        };
        let index_one_minutes = index_one / (60 * 75);
        let index_one_seconds = index_one / 75 % 60;
        let index_one_frames = index_one % 75;
        text.push_str(&format!(
            "FILE \"chd-track.bin\" BINARY\nTRACK {:02} {}\n",
            track.number,
            track.mode.cue_mode()
        ));
        if track.stored_pregap {
            text.push_str(&format!("INDEX 00 {minutes:02}:{seconds:02}:{frames:02}\n"));
        } else if track.pregap != 0 {
            let pregap_minutes = track.pregap / (60 * 75);
            let pregap_seconds = track.pregap / 75 % 60;
            let pregap_frames = track.pregap % 75;
            text.push_str(&format!(
                "PREGAP {pregap_minutes:02}:{pregap_seconds:02}:{pregap_frames:02}\n"
            ));
        }
        text.push_str(&format!(
            "INDEX 01 {index_one_minutes:02}:{index_one_seconds:02}:{index_one_frames:02}\n"
        ));
        if track.postgap != 0 {
            let postgap_minutes = track.postgap / (60 * 75);
            let postgap_seconds = track.postgap / 75 % 60;
            let postgap_frames = track.postgap % 75;
            text.push_str(&format!(
                "POSTGAP {postgap_minutes:02}:{postgap_seconds:02}:{postgap_frames:02}\n"
            ));
        }
    }
    parse_cue(&text).map(OpticalDescriptor::Cue)
}

fn gdi_descriptor(tracks: &[ChdTrack]) -> Result<OpticalDescriptor, OpticalError> {
    let mut text = format!("{}\n", tracks.len());
    for track in tracks {
        let offset = track.output_offset;
        text.push_str(&format!(
            "{} {} {} {} \"chd-track.bin\" {offset}\n",
            track.number,
            track.start_frame,
            track.mode.gdi_type(),
            track.mode.sector_bytes(),
        ));
    }
    parse_gdi(&text).map(OpticalDescriptor::Gdi)
}

fn parse_metadata_u64(value: &str) -> Result<u64, OpticalError> {
    value.parse().map_err(|_| OpticalError::Malformed)
}

fn tag_bytes(value: u32) -> [u8; 4] {
    value.to_be_bytes()
}

struct ChdPayloadReader {
    chd: Chd<File>,
    output_length: u64,
    raw_length: u64,
    hunk_size: u64,
    unit_bytes: u64,
    kind: ChdPayloadKind,
    cached_hunk: Option<(u32, Vec<u8>)>,
    compressed: Vec<u8>,
}

#[derive(Clone)]
enum ChdPayloadKind {
    Direct,
    Cd(Vec<ChdTrack>),
}

impl ChdPayloadReader {
    fn new(
        chd: Chd<File>,
        kind: ChdPayloadKind,
        session: &ParsingSession<'_>,
    ) -> Result<Self, OpticalError> {
        let raw_length = chd.header().logical_bytes();
        let hunk_size = u64::from(chd.header().hunk_size());
        if hunk_size == 0 {
            return Err(OpticalError::Malformed);
        }
        session
            .validate_representation_length(hunk_size)
            .map_err(map_session_error)?;
        let unit_bytes = u64::from(chd.header().unit_bytes());
        if unit_bytes == 0 {
            return Err(OpticalError::Malformed);
        }
        let output_length = match &kind {
            ChdPayloadKind::Direct => raw_length,
            ChdPayloadKind::Cd(tracks) => tracks.iter().try_fold(0_u64, |total, track| {
                total
                    .checked_add(
                        track
                            .output_frames
                            .checked_mul(track.mode.sector_bytes())
                            .ok_or(OpticalError::ResourceLimitExceeded)?,
                    )
                    .ok_or(OpticalError::ResourceLimitExceeded)
            })?,
        };
        Ok(Self {
            chd,
            output_length,
            raw_length,
            hunk_size,
            unit_bytes,
            kind,
            cached_hunk: None,
            compressed: Vec::new(),
        })
    }

    fn read_raw_at(&mut self, offset: u64, destination: &mut [u8]) -> Result<(), ContentReadError> {
        let end = offset
            .checked_add(destination.len() as u64)
            .ok_or(ContentReadError::OutOfRange)?;
        if end > self.raw_length {
            return Err(ContentReadError::OutOfRange);
        }
        let mut position = offset;
        let mut written = 0_usize;
        while written < destination.len() {
            let hunk_number = position / self.hunk_size;
            let hunk_offset = usize::try_from(position % self.hunk_size)
                .map_err(|_| ContentReadError::OutOfRange)?;
            self.load_hunk(hunk_number)?;
            let cached = self.cached_hunk.as_ref().ok_or(ContentReadError::Io)?;
            let count = (cached.1.len() - hunk_offset).min(destination.len() - written);
            destination[written..written + count]
                .copy_from_slice(&cached.1[hunk_offset..hunk_offset + count]);
            position = position
                .checked_add(count as u64)
                .ok_or(ContentReadError::OutOfRange)?;
            written += count;
        }
        Ok(())
    }

    fn load_hunk(&mut self, hunk_number: u64) -> Result<(), ContentReadError> {
        let hunk_number = u32::try_from(hunk_number).map_err(|_| ContentReadError::OutOfRange)?;
        if self
            .cached_hunk
            .as_ref()
            .is_some_and(|(cached, _)| *cached == hunk_number)
        {
            return Ok(());
        }
        let mut hunk = self
            .chd
            .hunk(hunk_number)
            .map_err(|_| ContentReadError::Io)?;
        let mut decoded = vec![0_u8; self.hunk_size as usize];
        let decoded_length = hunk
            .read_hunk_in(&mut self.compressed, &mut decoded)
            .map_err(|_| ContentReadError::Io)?;
        if decoded_length != decoded.len() {
            return Err(ContentReadError::OutOfRange);
        }
        self.cached_hunk = Some((hunk_number, decoded));
        Ok(())
    }
}

impl ContentReader for ChdPayloadReader {
    fn len(&self) -> Result<u64, ContentReadError> {
        Ok(self.output_length)
    }

    fn read_at(&mut self, offset: u64, destination: &mut [u8]) -> Result<usize, ContentReadError> {
        if destination.is_empty() {
            return Ok(0);
        }
        let end = offset
            .checked_add(destination.len() as u64)
            .ok_or(ContentReadError::OutOfRange)?;
        if end > self.output_length {
            return Err(ContentReadError::OutOfRange);
        }
        let kind = self.kind.clone();
        match kind {
            ChdPayloadKind::Direct => self.read_raw_at(offset, destination)?,
            ChdPayloadKind::Cd(tracks) => {
                let mut position = offset;
                let mut written = 0_usize;
                while written < destination.len() {
                    let track_index = tracks.partition_point(|track| {
                        track.output_offset + track.output_frames * track.mode.sector_bytes()
                            <= position
                    });
                    let track = tracks
                        .get(track_index)
                        .ok_or(ContentReadError::OutOfRange)?;
                    let output_offset = track.output_offset;
                    let output_frames = track.output_frames;
                    let sector_bytes = track.mode.sector_bytes();
                    let start_frame = track.start_frame;
                    let data_offset = track.data_offset;
                    let within_track = position
                        .checked_sub(output_offset)
                        .ok_or(ContentReadError::OutOfRange)?;
                    if within_track >= output_frames * sector_bytes {
                        return Err(ContentReadError::OutOfRange);
                    }
                    let frame = within_track / sector_bytes;
                    let in_sector = within_track % sector_bytes;
                    let count =
                        (sector_bytes - in_sector).min((destination.len() - written) as u64);
                    let raw_offset = start_frame
                        .checked_add(frame)
                        .and_then(|value| value.checked_mul(self.unit_bytes))
                        .and_then(|value| value.checked_add(data_offset))
                        .and_then(|value| value.checked_add(in_sector))
                        .ok_or(ContentReadError::OutOfRange)?;
                    self.read_raw_at(
                        raw_offset,
                        &mut destination[written..written + count as usize],
                    )?;
                    position += count;
                    written += count as usize;
                }
            }
        }
        Ok(destination.len())
    }

    fn max_read_size(&self) -> usize {
        64 * 1024
    }
}

fn map_chd_error(error: ChdError) -> OpticalError {
    match error {
        ChdError::OutOfMemory => OpticalError::ResourceLimitExceeded,
        ChdError::UnsupportedFormat | ChdError::UnsupportedVersion | ChdError::NotSupported => {
            OpticalError::UnsupportedRepresentation
        }
        ChdError::ReadError | ChdError::RequiresParent | ChdError::HunkOutOfRange => {
            OpticalError::Truncated
        }
        ChdError::DecompressionError => OpticalError::Malformed,
        ChdError::InvalidFile
        | ChdError::InvalidParameter
        | ChdError::InvalidData
        | ChdError::InvalidParent
        | ChdError::InvalidMetadata
        | ChdError::MetadataNotFound
        | ChdError::InvalidMetadataSize
        | ChdError::CodecError => OpticalError::Malformed,
        _ => OpticalError::Malformed,
    }
}

fn map_metadata_io_error(error: std::io::Error) -> OpticalError {
    if error.kind() == std::io::ErrorKind::UnexpectedEof {
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

fn map_decoded_optical_error(error: OpticalError, cancelled: &dyn Fn() -> bool) -> OpticalError {
    if cancelled() {
        OpticalError::Cancelled
    } else {
        match error {
            OpticalError::ReadFailure => OpticalError::Malformed,
            other => other,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{OpticalError, parse_track};
    use chd::metadata::Metadata;

    #[test]
    fn stored_pregap_mode_must_match_the_track_mode() {
        let value = b"TRACK:1 TYPE:MODE1 SUBTYPE:NONE FRAMES:4 PREGAP:1 PGTYPE:MODE2 PGSUB:NONE POSTGAP:0\0";
        let metadata = Metadata {
            metatag: u32::from_be_bytes(*b"CHT2"),
            value: value.to_vec(),
            flags: 0,
            index: 0,
            length: value.len() as u32,
        };

        assert_eq!(
            parse_track(&metadata),
            Err(OpticalError::UnsupportedRepresentation)
        );
    }
}
