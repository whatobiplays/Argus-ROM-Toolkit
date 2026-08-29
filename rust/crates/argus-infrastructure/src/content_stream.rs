//! Bounded source access and streaming identity recognition.

use std::fmt;

use argus_application::{ContentType, IdentityDigest, PlatformId, SourceReadHandle};
use sha2::{Digest, Sha256};

use super::{content_nintendo, content_sega};

/// Maximum buffer used by a streaming canonicalization pass.
pub(crate) const STREAM_CHUNK_BYTES: usize = 64 * 1024;

const BLOCKED_TAR_MAGIC_OFFSET: usize = 257;

/// Provider-backed range access used by the general content recognizer.
///
/// Implementations must not expose provider locators. The recognizer only
/// receives the source length and bounded byte ranges, which keeps format
/// validation independent of the filesystem or transport implementation.
pub trait ContentReader {
    /// Returns the immutable source length observed for this processing pass.
    fn len(&self) -> Result<u64, ContentReadError>;

    /// Returns whether the observed source has no bytes.
    fn is_empty(&self) -> Result<bool, ContentReadError> {
        Ok(self.len()? == 0)
    }

    /// Reads a bounded range beginning at `offset` into `destination`.
    fn read_at(&mut self, offset: u64, destination: &mut [u8]) -> Result<usize, ContentReadError>;

    /// Returns the largest buffer that this reader accepts in one request.
    ///
    /// The default keeps existing source adapters compatible while allowing
    /// the runtime wrapper to enforce a smaller operation-specific bound.
    fn max_read_size(&self) -> usize {
        STREAM_CHUNK_BYTES
    }

    /// Returns provider version evidence when the reader owns a mutable
    /// source handle. In-memory decoded readers remain stable by default.
    fn source_fingerprint(&self) -> Option<&str> {
        None
    }

    /// Revalidates the source version captured by this reader.
    fn source_version_is_unchanged(&self) -> Result<bool, ContentReadError> {
        Ok(true)
    }
}

/// Adapts an application-owned source handle to the parser-facing reader.
///
/// The adapter translates provider errors into the intentionally smaller
/// content-reading vocabulary and keeps provider locators and filesystem
/// details outside the representation recognizers.
pub struct SourceReadContentReader<'a> {
    source: &'a mut dyn SourceReadHandle,
}

impl<'a> SourceReadContentReader<'a> {
    /// Borrows one operation-scoped source handle for parser use.
    pub fn new(source: &'a mut dyn SourceReadHandle) -> Self {
        Self { source }
    }
}

impl ContentReader for SourceReadContentReader<'_> {
    fn len(&self) -> Result<u64, ContentReadError> {
        self.source.len().map_err(|_| ContentReadError::Io)
    }

    fn read_at(&mut self, offset: u64, destination: &mut [u8]) -> Result<usize, ContentReadError> {
        if destination.len() > self.source.max_read_size() {
            return Err(ContentReadError::RequestTooLarge);
        }
        let end = offset
            .checked_add(destination.len() as u64)
            .ok_or(ContentReadError::OutOfRange)?;
        if end > self.len()? {
            return Err(ContentReadError::OutOfRange);
        }
        let count = self
            .source
            .read_at(offset, destination)
            .map_err(|_| ContentReadError::Io)?;
        if count > destination.len() {
            return Err(ContentReadError::Io);
        }
        Ok(count)
    }

    fn max_read_size(&self) -> usize {
        self.source.max_read_size()
    }

    fn source_fingerprint(&self) -> Option<&str> {
        self.source.source_fingerprint()
    }

    fn source_version_is_unchanged(&self) -> Result<bool, ContentReadError> {
        self.source
            .source_version_is_unchanged()
            .map_err(|_| ContentReadError::Io)
    }
}

/// Failure while reading a bounded source range.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ContentReadError {
    /// The requested range is outside the source.
    OutOfRange,
    /// The caller requested a buffer larger than the source adapter allows.
    RequestTooLarge,
    /// The source provider could not complete the read.
    Io,
}

impl fmt::Display for ContentReadError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(match self {
            Self::OutOfRange => "content range is outside the source",
            Self::RequestTooLarge => "content range request is too large",
            Self::Io => "content source read failed",
        })
    }
}

impl std::error::Error for ContentReadError {}

/// Stable failures emitted by the general representation dispatcher.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ContentRecognitionError {
    /// The source cannot contain the minimum structure required for recognition.
    Truncated,
    /// The source matches a known family but its representation is not supported.
    UnsupportedRepresentation,
    /// A recognized representation violates its structural contract.
    Malformed,
    /// More than one incompatible platform interpretation remains valid.
    AmbiguousContentRecognition,
    /// The source requires cryptographic material outside the active contract.
    EncryptedContentUnsupported,
    /// The source or canonical output exceeds the operation budget.
    ResourceLimitExceeded,
    /// The provider failed while supplying a bounded source range.
    ReadFailure,
}

impl fmt::Display for ContentRecognitionError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(match self {
            Self::Truncated => "content source is truncated",
            Self::UnsupportedRepresentation => "content representation is unsupported",
            Self::Malformed => "content representation is malformed",
            Self::AmbiguousContentRecognition => "content recognition is ambiguous",
            Self::EncryptedContentUnsupported => "encrypted content is unsupported",
            Self::ResourceLimitExceeded => "content processing resource limit exceeded",
            Self::ReadFailure => "content source read failed",
        })
    }
}

impl std::error::Error for ContentRecognitionError {}

/// Streaming recognition result containing no whole-file canonical buffer.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct StreamRecognizedContent {
    platform: PlatformId,
    content_type: ContentType,
    source_representation: &'static str,
    identity_digest: IdentityDigest,
    canonical_length: u64,
}

impl StreamRecognizedContent {
    /// Returns the authoritative platform established from source bytes.
    pub const fn platform(self) -> PlatformId {
        self.platform
    }

    /// Returns the authoritative content type established from source bytes.
    pub const fn content_type(self) -> ContentType {
        self.content_type
    }

    /// Returns the exact representation recognized by the dispatcher.
    pub const fn source_representation(self) -> &'static str {
        self.source_representation
    }

    /// Returns the SHA-256 digest of the canonical logical representation.
    pub const fn identity_digest(self) -> IdentityDigest {
        self.identity_digest
    }

    /// Returns the number of bytes fed to the canonical digest.
    pub const fn canonical_length(self) -> u64 {
        self.canonical_length
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) struct Candidate {
    pub(crate) platform: PlatformId,
    pub(crate) content_type: ContentType,
    pub(crate) source_representation: &'static str,
    pub(crate) identity_digest: IdentityDigest,
    pub(crate) canonical_length: u64,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum ProbeResult {
    NotApplicable,
    Candidate(Candidate),
    Failure(ContentRecognitionError),
}

/// Independent bounds applied to one streaming recognition operation.
///
/// The representation bound is deliberately separate from the read-buffer
/// bound. A large source is therefore processed through small range reads,
/// while the cumulative counters cap total provider I/O and parser/hash work
/// across every recognition probe.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ContentProcessingLimits {
    /// Maximum source and canonical-representation size accepted by the
    /// operation.
    pub max_representation_bytes: u64,
    /// Maximum bytes held in one provider-read buffer.
    pub max_read_buffer_bytes: usize,
    /// Maximum bytes read from the source across all probes.
    pub max_cumulative_read_bytes: u64,
    /// Maximum parser and canonicalization work charged across all probes.
    pub max_cumulative_work_bytes: u64,
}

impl ContentProcessingLimits {
    /// Returns the finite production limits for the runtime recognition path.
    pub const fn production() -> Self {
        Self {
            // 4 GiB is the largest physical 3DS game-card representation in
            // the supported key-free NCSD contract.
            max_representation_bytes: 4 * 1024 * 1024 * 1024,
            max_read_buffer_bytes: STREAM_CHUNK_BYTES,
            // Header probes and validation reads are charged in addition to
            // the complete canonical pass over a maximum-size card.
            max_cumulative_read_bytes: 8 * 1024 * 1024 * 1024,
            max_cumulative_work_bytes: 8 * 1024 * 1024 * 1024,
        }
    }

    fn for_legacy_budget(budget_bytes: usize) -> Self {
        let max_representation_bytes = u64::try_from(budget_bytes).unwrap_or(u64::MAX);
        Self {
            max_representation_bytes,
            max_read_buffer_bytes: STREAM_CHUNK_BYTES,
            max_cumulative_read_bytes: u64::MAX,
            max_cumulative_work_bytes: u64::MAX,
        }
    }
}

impl Default for ContentProcessingLimits {
    fn default() -> Self {
        Self::production()
    }
}

struct BudgetedReader<'a> {
    inner: &'a mut dyn ContentReader,
    limits: ContentProcessingLimits,
    cumulative_read_bytes: u64,
    cumulative_work_bytes: u64,
}

impl<'a> BudgetedReader<'a> {
    fn new(inner: &'a mut dyn ContentReader, limits: ContentProcessingLimits) -> Self {
        Self {
            inner,
            limits,
            cumulative_read_bytes: 0,
            cumulative_work_bytes: 0,
        }
    }

    fn charge(&mut self, count: usize) -> Result<(), ContentReadError> {
        let count = u64::try_from(count).map_err(|_| ContentReadError::RequestTooLarge)?;
        let next_read = self
            .cumulative_read_bytes
            .checked_add(count)
            .ok_or(ContentReadError::RequestTooLarge)?;
        let next_work = self
            .cumulative_work_bytes
            .checked_add(count)
            .ok_or(ContentReadError::RequestTooLarge)?;
        if next_read > self.limits.max_cumulative_read_bytes
            || next_work > self.limits.max_cumulative_work_bytes
        {
            return Err(ContentReadError::RequestTooLarge);
        }
        self.cumulative_read_bytes = next_read;
        self.cumulative_work_bytes = next_work;
        Ok(())
    }
}

impl ContentReader for BudgetedReader<'_> {
    fn len(&self) -> Result<u64, ContentReadError> {
        self.inner.len()
    }

    fn read_at(&mut self, offset: u64, destination: &mut [u8]) -> Result<usize, ContentReadError> {
        if destination.len() > self.max_read_size() {
            return Err(ContentReadError::RequestTooLarge);
        }
        let count = self.inner.read_at(offset, destination)?;
        if count > destination.len() {
            return Err(ContentReadError::Io);
        }
        self.charge(count)?;
        Ok(count)
    }

    fn max_read_size(&self) -> usize {
        self.limits
            .max_read_buffer_bytes
            .min(self.inner.max_read_size())
            .min(STREAM_CHUNK_BYTES)
    }
}

fn map_read_error(error: ContentReadError) -> ContentRecognitionError {
    match error {
        ContentReadError::OutOfRange => ContentRecognitionError::Truncated,
        ContentReadError::RequestTooLarge => ContentRecognitionError::ResourceLimitExceeded,
        ContentReadError::Io => ContentRecognitionError::ReadFailure,
    }
}

/// Recognizes one provider-backed source using the default bounded budget.
pub fn recognize_content(
    reader: &mut dyn ContentReader,
) -> Result<StreamRecognizedContent, ContentRecognitionError> {
    recognize_content_with_limits(reader, ContentProcessingLimits::production())
}

/// Recognizes one provider-backed source through bounded range reads.
pub fn recognize_content_with_budget(
    reader: &mut dyn ContentReader,
    budget_bytes: usize,
) -> Result<StreamRecognizedContent, ContentRecognitionError> {
    recognize_content_with_limits(
        reader,
        ContentProcessingLimits::for_legacy_budget(budget_bytes),
    )
}

/// Recognizes one source under explicit representation, buffer, and
/// operation-wide cumulative limits.
pub fn recognize_content_with_limits(
    reader: &mut dyn ContentReader,
    limits: ContentProcessingLimits,
) -> Result<StreamRecognizedContent, ContentRecognitionError> {
    let source_length = reader.len().map_err(map_read_error)?;
    if source_length > limits.max_representation_bytes {
        return Err(ContentRecognitionError::ResourceLimitExceeded);
    }
    let mut reader = BudgetedReader::new(reader, limits);
    if is_blocked_container(&mut reader, source_length)? {
        return Err(ContentRecognitionError::UnsupportedRepresentation);
    }

    let mut candidates = Vec::new();
    let mut failure = None;
    for result in [
        content_nintendo::probe(&mut reader, source_length),
        content_sega::probe(&mut reader, source_length),
    ] {
        match result {
            ProbeResult::NotApplicable => {}
            ProbeResult::Candidate(candidate) => candidates.push(candidate),
            ProbeResult::Failure(error) => {
                if failure.is_none() {
                    failure = Some(error);
                }
            }
        }
    }

    if let Some(error) = failure {
        return Err(error);
    }
    let candidate = match candidates.as_slice() {
        [candidate] => *candidate,
        [] => return Err(ContentRecognitionError::UnsupportedRepresentation),
        _ => return Err(ContentRecognitionError::AmbiguousContentRecognition),
    };
    if candidate.canonical_length > limits.max_representation_bytes {
        return Err(ContentRecognitionError::ResourceLimitExceeded);
    }
    Ok(StreamRecognizedContent {
        platform: candidate.platform,
        content_type: candidate.content_type,
        source_representation: candidate.source_representation,
        identity_digest: candidate.identity_digest,
        canonical_length: candidate.canonical_length,
    })
}

fn is_blocked_container(
    reader: &mut dyn ContentReader,
    source_length: u64,
) -> Result<bool, ContentRecognitionError> {
    let probe_length = source_length.min(512) as usize;
    if probe_length == 0 {
        return Ok(false);
    }
    let mut probe = vec![0_u8; probe_length];
    read_exact(reader, 0, &mut probe)?;

    let starts_with = |magic: &[u8]| probe.starts_with(magic);
    Ok(starts_with(b"PK\x03\x04")
        || starts_with(b"PK\x05\x06")
        || starts_with(b"PK\x07\x08")
        || starts_with(b"7z\xbc\xaf\x27\x1c")
        || starts_with(b"Rar!\x1a\x07")
        || starts_with(b"\x1f\x8b")
        || starts_with(b"BZh")
        || starts_with(b"\xfd7zXZ\0")
        || starts_with(b"MComprHD")
        || starts_with(b"CISO")
        || starts_with(b"WBFS")
        || starts_with(b"RVZ\x01")
        || starts_with(b"WIA\x01")
        || (probe.len() >= BLOCKED_TAR_MAGIC_OFFSET + 5
            && &probe[BLOCKED_TAR_MAGIC_OFFSET..BLOCKED_TAR_MAGIC_OFFSET + 5] == b"ustar"))
}

pub(crate) fn read_exact(
    reader: &mut dyn ContentReader,
    offset: u64,
    destination: &mut [u8],
) -> Result<(), ContentRecognitionError> {
    if destination.is_empty() {
        return Ok(());
    }
    let chunk_size = reader.max_read_size().min(STREAM_CHUNK_BYTES);
    if chunk_size == 0 {
        return Err(ContentRecognitionError::ResourceLimitExceeded);
    }
    let mut position = offset;
    let mut written = 0;
    while written < destination.len() {
        let end = written + (destination.len() - written).min(chunk_size);
        let count = reader
            .read_at(position, &mut destination[written..end])
            .map_err(map_read_error)?;
        if count == 0 {
            return Err(ContentRecognitionError::Truncated);
        }
        position = position
            .checked_add(count as u64)
            .ok_or(ContentRecognitionError::ResourceLimitExceeded)?;
        written += count;
    }
    Ok(())
}

pub(crate) fn read_small(
    reader: &mut dyn ContentReader,
    offset: u64,
    length: usize,
) -> Result<Vec<u8>, ContentRecognitionError> {
    if length > reader.max_read_size().min(STREAM_CHUNK_BYTES) {
        return Err(ContentRecognitionError::ResourceLimitExceeded);
    }
    let mut bytes = vec![0_u8; length];
    read_exact(reader, offset, &mut bytes)?;
    Ok(bytes)
}

pub(crate) fn hash_range(
    reader: &mut dyn ContentReader,
    offset: u64,
    length: u64,
    hasher: &mut CanonicalHasher,
) -> Result<(), ContentRecognitionError> {
    let buffer_size = reader.max_read_size().min(STREAM_CHUNK_BYTES);
    if buffer_size == 0 {
        return Err(ContentRecognitionError::ResourceLimitExceeded);
    }
    let mut buffer = vec![0_u8; buffer_size];
    let mut position = offset;
    let mut remaining = length;
    while remaining > 0 {
        let count = remaining.min(buffer.len() as u64) as usize;
        read_exact(reader, position, &mut buffer[..count])?;
        hasher.update(&buffer[..count]);
        position = position
            .checked_add(count as u64)
            .ok_or(ContentRecognitionError::ResourceLimitExceeded)?;
        remaining -= count as u64;
    }
    Ok(())
}

pub(crate) fn hash_transformed_range(
    reader: &mut dyn ContentReader,
    offset: u64,
    length: u64,
    unit: usize,
    transform: impl Fn(&mut [u8]),
    hasher: &mut CanonicalHasher,
) -> Result<(), ContentRecognitionError> {
    let buffer_size = reader.max_read_size().min(STREAM_CHUNK_BYTES);
    if unit == 0 || unit > buffer_size {
        return Err(ContentRecognitionError::ResourceLimitExceeded);
    }
    let chunk_length = buffer_size - (buffer_size % unit);
    if chunk_length == 0 {
        return Err(ContentRecognitionError::ResourceLimitExceeded);
    }
    let mut buffer = vec![0_u8; chunk_length];
    let mut position = offset;
    let mut remaining = length;
    while remaining > 0 {
        let count = remaining.min(buffer.len() as u64) as usize;
        if !count.is_multiple_of(unit) {
            return Err(ContentRecognitionError::Malformed);
        }
        read_exact(reader, position, &mut buffer[..count])?;
        transform(&mut buffer[..count]);
        hasher.update(&buffer[..count]);
        position = position
            .checked_add(count as u64)
            .ok_or(ContentRecognitionError::ResourceLimitExceeded)?;
        remaining -= count as u64;
    }
    Ok(())
}

pub(crate) struct CanonicalHasher {
    hasher: Sha256,
    length: u64,
}

impl CanonicalHasher {
    pub(crate) fn new() -> Self {
        Self {
            hasher: Sha256::new(),
            length: 0,
        }
    }

    pub(crate) fn update(&mut self, bytes: &[u8]) {
        self.hasher.update(bytes);
        self.length = self.length.saturating_add(bytes.len() as u64);
    }

    pub(crate) fn finish(self) -> (IdentityDigest, u64) {
        let digest: [u8; 32] = self.hasher.finalize().into();
        (IdentityDigest::from_bytes(digest), self.length)
    }
}

pub(crate) fn candidate(
    platform: PlatformId,
    content_type: ContentType,
    source_representation: &'static str,
    hasher: CanonicalHasher,
) -> Candidate {
    let (identity_digest, canonical_length) = hasher.finish();
    Candidate {
        platform,
        content_type,
        source_representation,
        identity_digest,
        canonical_length,
    }
}

pub(crate) fn update_u32(hasher: &mut CanonicalHasher, value: u32) {
    hasher.update(&value.to_be_bytes());
}

pub(crate) fn update_u64(hasher: &mut CanonicalHasher, value: u64) {
    hasher.update(&value.to_be_bytes());
}

pub(crate) fn in_range(offset: u64, length: u64, source_length: u64) -> bool {
    offset
        .checked_add(length)
        .is_some_and(|end| end <= source_length)
}
