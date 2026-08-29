//! Safe, bounded CSO (CISO) decoding for PSP optical content.
//!
//! CSO is treated as a transport representation only. The decoder validates
//! the complete block index, reconstructs exact 2048-byte logical sectors, and
//! delegates platform recognition and identity hashing to the existing native
//! optical implementation. CSO headers, indexes, and compression boundaries
//! never participate in the logical identity.

use std::fs::File;
use std::io::{Read, Seek, SeekFrom};

use argus_application::TransformationFailure;
use flate2::read::DeflateDecoder;

use super::content_optical::{
    OpticalError, OpticalRecognition, recognize_native_optical_with_cancel,
};
use super::content_session::ParsingSession;
use super::content_stream::{ContentReadError, ContentReader};

const CSO_HEADER_BYTES: usize = 24;
const MAX_CSO_HEADER_BYTES: u64 = 1024 * 1024;
const CSO_BLOCK_BYTES: u32 = 2_048;
const CSO_INDEX_FLAG_PLAIN: u32 = 0x8000_0000;
const CSO_INDEX_OFFSET_MASK: u32 = 0x7fff_ffff;

/// Recognizes one CSO-backed PSP UMD representation.
///
/// The complete CSO is staged before its index is parsed. This gives the
/// decoder a stable seekable source while keeping all staging, expansion,
/// parser-work, and cancellation accounting in the caller-owned session.
pub fn recognize_cso(
    reader: &mut dyn ContentReader,
    session: &mut ParsingSession<'_>,
) -> Result<OpticalRecognition, OpticalError> {
    session.check_cancelled().map_err(map_session_error)?;
    let staged = session
        .stage_content_reader("cso", reader)
        .map_err(map_session_error)?;
    let mut file = staged.reopen().map_err(|_| OpticalError::ReadFailure)?;
    let layout = parse_layout(&mut file, staged.len(), session)?;

    let cancelled = || session.check_cancelled().is_err();
    let mut decoded = CsoReader::new(file, layout, &cancelled);
    let recognition = recognize_native_optical_with_cancel(&mut decoded, &cancelled);
    if let Some(error) = decoded.take_failure() {
        return Err(error);
    }
    let recognition = recognition?;
    if recognition.content_type() != argus_application::ContentType::OpticalDiscUmd {
        return Err(OpticalError::UnsupportedRepresentation);
    }
    Ok(recognition.with_source_representation("cso"))
}

struct CsoLayout {
    total_bytes: u64,
    block_size: u64,
    indexes: Vec<CsoIndex>,
}

#[derive(Clone, Copy)]
struct CsoIndex {
    offset: u64,
    plain: bool,
}

fn parse_layout(
    file: &mut File,
    source_length: u64,
    session: &mut ParsingSession<'_>,
) -> Result<CsoLayout, OpticalError> {
    if source_length < CSO_HEADER_BYTES as u64 {
        return Err(OpticalError::Truncated);
    }
    let mut header = [0_u8; CSO_HEADER_BYTES];
    read_exact_at(file, 0, &mut header)?;
    if &header[..4] != b"CISO" {
        return Err(OpticalError::UnsupportedRepresentation);
    }

    let header_size = u64::from(read_u32_le(&header, 4));
    let total_bytes = read_u64_le(&header, 8);
    let block_size = u64::from(read_u32_le(&header, 16));
    let version = header[20];
    let alignment = header[21];
    if !(CSO_HEADER_BYTES as u64..=MAX_CSO_HEADER_BYTES).contains(&header_size)
        || header_size > source_length
        || version != 1
        || alignment >= 32
        || total_bytes == 0
        || block_size != u64::from(CSO_BLOCK_BYTES)
        || !total_bytes.is_multiple_of(block_size)
    {
        return Err(OpticalError::Malformed);
    }

    let block_count = total_bytes
        .checked_div(block_size)
        .ok_or(OpticalError::ResourceLimitExceeded)?;
    let index_count = block_count
        .checked_add(1)
        .ok_or(OpticalError::ResourceLimitExceeded)?;
    let index_bytes = index_count
        .checked_mul(4)
        .ok_or(OpticalError::ResourceLimitExceeded)?;
    let index_end = header_size
        .checked_add(index_bytes)
        .ok_or(OpticalError::ResourceLimitExceeded)?;
    if index_end > source_length {
        return Err(OpticalError::Truncated);
    }
    session
        .validate_representation_length(index_bytes)
        .map_err(map_session_error)?;
    session
        .charge_parser_work(index_bytes)
        .map_err(map_session_error)?;
    session
        .charge_expanded(total_bytes)
        .map_err(map_session_error)?;
    session
        .charge_parser_work(total_bytes)
        .map_err(map_session_error)?;

    let index_bytes_usize =
        usize::try_from(index_bytes).map_err(|_| OpticalError::ResourceLimitExceeded)?;
    let mut raw_indexes = vec![0_u8; index_bytes_usize];
    read_exact_at(file, header_size, &mut raw_indexes)?;
    let unit = 1_u64
        .checked_shl(u32::from(alignment))
        .ok_or(OpticalError::Malformed)?;
    let mut indexes = Vec::with_capacity(
        usize::try_from(index_count).map_err(|_| OpticalError::ResourceLimitExceeded)?,
    );
    for chunk in raw_indexes.chunks_exact(4) {
        let raw = u32::from_le_bytes(chunk.try_into().expect("chunks_exact supplies four bytes"));
        let offset_units = u64::from(raw & CSO_INDEX_OFFSET_MASK);
        let offset = offset_units
            .checked_mul(unit)
            .ok_or(OpticalError::Malformed)?;
        indexes.push(CsoIndex {
            offset,
            plain: raw & CSO_INDEX_FLAG_PLAIN != 0,
        });
    }

    let mut previous = index_end;
    for pair in indexes.windows(2) {
        let start = pair[0].offset;
        let end = pair[1].offset;
        if start < index_end || start < previous || end <= start || end > source_length {
            return Err(if end > source_length {
                OpticalError::Truncated
            } else {
                OpticalError::Malformed
            });
        }
        previous = end;
    }
    Ok(CsoLayout {
        total_bytes,
        block_size,
        indexes,
    })
}

struct CsoReader<'a> {
    file: File,
    total_bytes: u64,
    block_size: u64,
    indexes: Vec<CsoIndex>,
    cancelled: &'a dyn Fn() -> bool,
    cached_block: Option<(u64, Vec<u8>)>,
    failure: Option<OpticalError>,
}

impl<'a> CsoReader<'a> {
    fn new(file: File, layout: CsoLayout, cancelled: &'a dyn Fn() -> bool) -> Self {
        Self {
            file,
            total_bytes: layout.total_bytes,
            block_size: layout.block_size,
            indexes: layout.indexes,
            cancelled,
            cached_block: None,
            failure: None,
        }
    }

    fn take_failure(&mut self) -> Option<OpticalError> {
        self.failure.take()
    }

    fn record_failure(&mut self, error: OpticalError) -> ContentReadError {
        self.failure = Some(error);
        ContentReadError::Io
    }

    fn load_block(&mut self, block: u64) -> Result<(), ContentReadError> {
        if self
            .cached_block
            .as_ref()
            .is_some_and(|(cached, _)| *cached == block)
        {
            return Ok(());
        }
        if (self.cancelled)() {
            return Err(self.record_failure(OpticalError::Cancelled));
        }
        let block_index = usize::try_from(block).map_err(|_| ContentReadError::OutOfRange)?;
        let current = self
            .indexes
            .get(block_index)
            .copied()
            .ok_or(ContentReadError::OutOfRange)?;
        let next = self
            .indexes
            .get(block_index + 1)
            .copied()
            .ok_or(ContentReadError::OutOfRange)?;
        let compressed_length = next
            .offset
            .checked_sub(current.offset)
            .ok_or(ContentReadError::OutOfRange)?;
        let expected_length =
            usize::try_from(self.block_size).map_err(|_| ContentReadError::OutOfRange)?;
        let decoded = if current.plain {
            if compressed_length < self.block_size {
                return Err(self.record_failure(OpticalError::Malformed));
            }
            let mut decoded = vec![0_u8; expected_length];
            read_exact_at(&mut self.file, current.offset, &mut decoded)
                .map_err(|error| self.record_failure(error))?;
            decoded
        } else {
            self.file
                .seek(SeekFrom::Start(current.offset))
                .map_err(|_| self.record_failure(OpticalError::ReadFailure))?;
            let decoder = DeflateDecoder::new((&mut self.file).take(compressed_length));
            let mut decoded = Vec::with_capacity(expected_length + 1);
            decoder
                .take((expected_length + 1) as u64)
                .read_to_end(&mut decoded)
                .map_err(|_| self.record_failure(OpticalError::Malformed))?;
            if decoded.len() < expected_length {
                return Err(self.record_failure(OpticalError::Truncated));
            }
            if decoded.len() > expected_length {
                return Err(self.record_failure(OpticalError::Malformed));
            }
            decoded
        };
        self.cached_block = Some((block, decoded));
        Ok(())
    }
}

impl ContentReader for CsoReader<'_> {
    fn len(&self) -> Result<u64, ContentReadError> {
        Ok(self.total_bytes)
    }

    fn read_at(&mut self, offset: u64, destination: &mut [u8]) -> Result<usize, ContentReadError> {
        if destination.is_empty() {
            return Ok(0);
        }
        if (self.cancelled)() {
            return Err(self.record_failure(OpticalError::Cancelled));
        }
        let end = offset
            .checked_add(destination.len() as u64)
            .ok_or(ContentReadError::OutOfRange)?;
        if end > self.total_bytes {
            return Err(ContentReadError::OutOfRange);
        }
        let mut position = offset;
        let mut written = 0_usize;
        while written < destination.len() {
            let block = position / self.block_size;
            let in_block = usize::try_from(position % self.block_size)
                .map_err(|_| ContentReadError::OutOfRange)?;
            self.load_block(block)?;
            let cached = self.cached_block.as_ref().ok_or(ContentReadError::Io)?;
            let count = (cached.1.len() - in_block).min(destination.len() - written);
            destination[written..written + count]
                .copy_from_slice(&cached.1[in_block..in_block + count]);
            position = position
                .checked_add(count as u64)
                .ok_or(ContentReadError::OutOfRange)?;
            written += count;
        }
        Ok(destination.len())
    }

    fn max_read_size(&self) -> usize {
        64 * 1024
    }
}

fn read_exact_at(file: &mut File, offset: u64, destination: &mut [u8]) -> Result<(), OpticalError> {
    file.seek(SeekFrom::Start(offset))
        .map_err(|_| OpticalError::ReadFailure)?;
    file.read_exact(destination).map_err(|error| {
        if error.kind() == std::io::ErrorKind::UnexpectedEof {
            OpticalError::Truncated
        } else {
            OpticalError::ReadFailure
        }
    })
}

fn read_u32_le(bytes: &[u8], offset: usize) -> u32 {
    u32::from_le_bytes(
        bytes[offset..offset + 4]
            .try_into()
            .expect("fixed header field"),
    )
}

fn read_u64_le(bytes: &[u8], offset: usize) -> u64 {
    u64::from_le_bytes(
        bytes[offset..offset + 8]
            .try_into()
            .expect("fixed header field"),
    )
}

fn map_session_error(error: TransformationFailure) -> OpticalError {
    match error {
        TransformationFailure::Cancelled => OpticalError::Cancelled,
        TransformationFailure::ResourceLimitExceeded => OpticalError::ResourceLimitExceeded,
        TransformationFailure::ReadFailure => OpticalError::ReadFailure,
        _ => OpticalError::Malformed,
    }
}
