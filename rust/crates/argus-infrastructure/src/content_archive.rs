//! Bounded, read-only archive and compressed-stream transformations.
//!
//! This module deliberately owns the format-specific coordinates and member
//! index. The application layer receives observations and later persists only
//! the opaque derived coordinates; it never needs to parse a decoder library's
//! path or offset representation.

use std::borrow::Cow;
use std::fs::File;
use std::io::{BufReader, Read};

use argus_application::{
    DerivedEntryKey, DerivedEntryObservation, DerivedFingerprint, DerivedLocator,
    DerivedScopeOutcome, SourceEntryKind, SourceVersionEvidence, SourceVersionKind,
    TransformationFailure,
};
use flate2::bufread::GzDecoder;
use lzma_rust2::XzReader;
use oxiarc_bzip2::BzDecoder;
use oxiarc_core::error::OxiArcError;
use sevenz_rust2::{ArchiveReader, Password};
use sha2::{Digest, Sha256};
use zip::{ZipArchive, result::ZipError};

use super::content_session::{ParsingSession, StagedRepresentation};
use super::content_stream::{ContentReadError, ContentReader, TAR_MAGIC, TAR_MAGIC_OFFSET};

const ZIP_LOCAL_MAGIC: &[u8] = b"PK\x03\x04";
const ZIP_EMPTY_MAGIC: &[u8] = b"PK\x05\x06";
const ZIP_SPLIT_MAGIC: &[u8] = b"PK\x07\x08";
const SEVEN_Z_MAGIC: &[u8] = b"7z\xbc\xaf\x27\x1c";
const RAR_MAGIC: &[u8] = b"Rar!\x1a\x07";
const GZIP_MAGIC: &[u8] = b"\x1f\x8b";
const BZIP2_MAGIC: &[u8] = b"BZh";
const XZ_MAGIC: &[u8] = b"\xfd7zXZ\0";
const TAR_BLOCK_BYTES: usize = 512;
const UNKNOWN_SIZE: Option<u64> = None;

const ZIP_TRANSFORMATION: &str = "argus.transformation.zip.v1";
const SEVEN_Z_TRANSFORMATION: &str = "argus.transformation.sevenzip.v1";
const TAR_TRANSFORMATION: &str = "argus.transformation.tar.v1";
const GZIP_TRANSFORMATION: &str = "argus.transformation.gzip.v1";
const BZIP2_TRANSFORMATION: &str = "argus.transformation.bzip2.v1";
const XZ_TRANSFORMATION: &str = "argus.transformation.xz.v1";

/// The transient index for members admitted by one transformation attempt.
///
/// The index is intentionally not a persistence model. It retains operation-
/// scoped staged handles so dependency resolution can reopen a validated
/// member without interpreting a provider path or a decoder offset.
#[derive(Debug, Default)]
pub struct DerivedMemberIndex {
    members: Vec<DerivedMember>,
}

#[derive(Debug)]
struct DerivedMember {
    key: DerivedEntryKey,
    display_name: String,
    kind: SourceEntryKind,
    staged: Option<StagedRepresentation>,
}

impl DerivedMemberIndex {
    /// Returns the number of safely enumerated members.
    pub fn len(&self) -> usize {
        self.members.len()
    }

    /// Returns whether no members were enumerated.
    pub fn is_empty(&self) -> bool {
        self.members.is_empty()
    }

    /// Reopens one file member from operation-scoped staging.
    pub fn open(&self, key: &DerivedEntryKey) -> std::io::Result<File> {
        self.members
            .iter()
            .find(|member| member.key == *key)
            .and_then(|member| member.staged.as_ref())
            .ok_or_else(|| {
                std::io::Error::new(std::io::ErrorKind::NotFound, "staged member not found")
            })?
            .reopen()
    }

    /// Returns the operation-scoped path for one staged file member.
    pub fn staged_path(&self, key: &DerivedEntryKey) -> Option<&std::path::Path> {
        self.members
            .iter()
            .find(|member| member.key == *key)
            .and_then(|member| member.staged.as_ref())
            .map(StagedRepresentation::path)
    }

    /// Returns the length of one staged file member.
    pub fn member_len(&self, key: &DerivedEntryKey) -> Option<u64> {
        self.members
            .iter()
            .find(|member| member.key == *key)
            .and_then(|member| member.staged.as_ref())
            .map(StagedRepresentation::len)
    }

    /// Returns the safe presentation name for one member key.
    pub fn display_name(&self, key: &DerivedEntryKey) -> Option<&str> {
        self.members
            .iter()
            .find(|member| member.key == *key)
            .map(|member| member.display_name.as_str())
    }

    /// Returns the source-entry kind for one member key.
    pub fn kind(&self, key: &DerivedEntryKey) -> Option<SourceEntryKind> {
        self.members
            .iter()
            .find(|member| member.key == *key)
            .map(|member| member.kind)
    }

    fn push(
        &mut self,
        key: DerivedEntryKey,
        display_name: String,
        kind: SourceEntryKind,
        staged: Option<StagedRepresentation>,
    ) -> Result<(), TransformationFailure> {
        if self.members.iter().any(|member| member.key == key) {
            return Err(TransformationFailure::Malformed);
        }
        self.members.push(DerivedMember {
            key,
            display_name,
            kind,
            staged,
        });
        Ok(())
    }
}

/// The complete result of one stable derived enumeration.
#[derive(Debug)]
pub struct DerivedScopeResult {
    observations: Vec<DerivedEntryObservation>,
    outcome: DerivedScopeOutcome,
    member_index: DerivedMemberIndex,
    transformation_id: Option<&'static str>,
    transformation_revision: Option<u32>,
}

impl DerivedScopeResult {
    /// Creates a transformation result from validated observations and its
    /// transient member index.
    pub fn new(
        observations: Vec<DerivedEntryObservation>,
        outcome: DerivedScopeOutcome,
        member_index: DerivedMemberIndex,
    ) -> Self {
        Self {
            observations,
            outcome,
            member_index,
            transformation_id: None,
            transformation_revision: None,
        }
    }

    /// Creates a result tied to the transformation that produced it.
    pub fn with_transformation(
        observations: Vec<DerivedEntryObservation>,
        outcome: DerivedScopeOutcome,
        member_index: DerivedMemberIndex,
        transformation_id: &'static str,
        transformation_revision: u32,
    ) -> Self {
        Self {
            observations,
            outcome,
            member_index,
            transformation_id: Some(transformation_id),
            transformation_revision: Some(transformation_revision),
        }
    }

    /// Returns all safely enumerated member observations.
    pub fn observations(&self) -> &[DerivedEntryObservation] {
        &self.observations
    }

    /// Returns the scope outcome that controls absence authority.
    pub const fn outcome(&self) -> DerivedScopeOutcome {
        self.outcome
    }

    /// Returns the transient index for decoded member access.
    pub fn member_index(&self) -> &DerivedMemberIndex {
        &self.member_index
    }

    /// Returns the stable producing transformation, when known.
    pub const fn transformation_id(&self) -> Option<&'static str> {
        self.transformation_id
    }

    /// Returns the producing transformation revision, when known.
    pub const fn transformation_revision(&self) -> Option<u32> {
        self.transformation_revision
    }
}

/// Format-specific decoder interface used by the derived-container dispatcher.
pub trait DerivedContainerDecoder {
    /// Returns the stable transformation registration identifier.
    fn transformation_id(&self) -> &'static str;

    /// Returns the transformation contract revision.
    fn revision(&self) -> u32 {
        1
    }

    /// Enumerates validated members using the caller-owned cumulative session.
    fn enumerate(
        &self,
        reader: &mut dyn ContentReader,
        parent_version: &SourceVersionEvidence,
        session: &mut ParsingSession<'_>,
    ) -> Result<DerivedScopeResult, TransformationFailure>;
}

struct ZipContainerDecoder;
struct SevenZipContainerDecoder;
struct TarContainerDecoder;
struct GzipContainerDecoder;
struct Bzip2ContainerDecoder;
struct XzContainerDecoder;

trait SingleStreamDecoder: Read {
    fn ensure_no_trailing_data(self) -> std::io::Result<()>
    where
        Self: Sized;
}

impl SingleStreamDecoder for GzDecoder<BufReader<File>> {
    fn ensure_no_trailing_data(self) -> std::io::Result<()> {
        if !self.get_ref().buffer().is_empty() {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                "trailing gzip data",
            ));
        }
        let mut source = self.into_inner();
        let mut byte = [0_u8; 1];
        if source.read(&mut byte)? != 0 {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                "trailing gzip data",
            ));
        }
        Ok(())
    }
}

impl SingleStreamDecoder for XzReader<File> {
    fn ensure_no_trailing_data(self) -> std::io::Result<()> {
        let mut source = self.into_inner();
        let mut byte = [0_u8; 1];
        if source.read(&mut byte)? != 0 {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                "trailing xz data",
            ));
        }
        Ok(())
    }
}

/// Enumerates a supported generic archive or compressed stream.
///
/// `Ok(None)` means the input is not one of the registered generic
/// transformations. Recognized-but-unsupported inputs return an explicit
/// failure, so callers cannot accidentally grant absence authority.
pub fn enumerate_derived_container(
    reader: &mut dyn ContentReader,
    parent_version: &SourceVersionEvidence,
    session: &mut ParsingSession<'_>,
) -> Result<Option<DerivedScopeResult>, TransformationFailure> {
    let source_length = reader.len().map_err(map_content_read_error)?;
    if source_length == 0 {
        return Ok(None);
    }
    let probe_length = source_length.min(512) as usize;
    let probe = read_content_range(reader, 0, probe_length, session)?;
    let wrapper = probe_wrapper(&probe);

    match wrapper {
        WrapperProbe::NotApplicable => Ok(None),
        WrapperProbe::Rar | WrapperProbe::SplitArchive => {
            Err(TransformationFailure::UnsupportedFeature)
        }
        WrapperProbe::Zip => Ok(Some(ZipContainerDecoder.enumerate(
            reader,
            parent_version,
            session,
        )?)),
        WrapperProbe::SevenZip => Ok(Some(SevenZipContainerDecoder.enumerate(
            reader,
            parent_version,
            session,
        )?)),
        WrapperProbe::Tar => Ok(Some(TarContainerDecoder.enumerate(
            reader,
            parent_version,
            session,
        )?)),
        WrapperProbe::Gzip => Ok(Some(GzipContainerDecoder.enumerate(
            reader,
            parent_version,
            session,
        )?)),
        WrapperProbe::Bzip2 => Ok(Some(Bzip2ContainerDecoder.enumerate(
            reader,
            parent_version,
            session,
        )?)),
        WrapperProbe::Xz => Ok(Some(XzContainerDecoder.enumerate(
            reader,
            parent_version,
            session,
        )?)),
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum WrapperProbe {
    NotApplicable,
    Zip,
    SevenZip,
    Tar,
    Gzip,
    Bzip2,
    Xz,
    Rar,
    SplitArchive,
}

fn probe_wrapper(bytes: &[u8]) -> WrapperProbe {
    if bytes.len() >= RAR_MAGIC.len() && bytes.starts_with(RAR_MAGIC) {
        return WrapperProbe::Rar;
    }
    if bytes.len() >= ZIP_SPLIT_MAGIC.len() && bytes.starts_with(ZIP_SPLIT_MAGIC) {
        return WrapperProbe::SplitArchive;
    }
    if bytes.len() >= ZIP_LOCAL_MAGIC.len()
        && (bytes.starts_with(ZIP_LOCAL_MAGIC) || bytes.starts_with(ZIP_EMPTY_MAGIC))
    {
        return WrapperProbe::Zip;
    }
    if bytes.len() >= SEVEN_Z_MAGIC.len() && bytes.starts_with(SEVEN_Z_MAGIC) {
        return WrapperProbe::SevenZip;
    }
    if bytes.len() >= GZIP_MAGIC.len() && bytes.starts_with(GZIP_MAGIC) {
        return WrapperProbe::Gzip;
    }
    if bytes.len() >= BZIP2_MAGIC.len() && bytes.starts_with(BZIP2_MAGIC) {
        return WrapperProbe::Bzip2;
    }
    if bytes.len() >= XZ_MAGIC.len() && bytes.starts_with(XZ_MAGIC) {
        return WrapperProbe::Xz;
    }
    if bytes.len() >= TAR_MAGIC_OFFSET + TAR_MAGIC.len()
        && &bytes[TAR_MAGIC_OFFSET..TAR_MAGIC_OFFSET + TAR_MAGIC.len()] == TAR_MAGIC
    {
        return WrapperProbe::Tar;
    }
    WrapperProbe::NotApplicable
}

impl DerivedContainerDecoder for ZipContainerDecoder {
    fn transformation_id(&self) -> &'static str {
        ZIP_TRANSFORMATION
    }

    fn enumerate(
        &self,
        reader: &mut dyn ContentReader,
        parent_version: &SourceVersionEvidence,
        session: &mut ParsingSession<'_>,
    ) -> Result<DerivedScopeResult, TransformationFailure> {
        let staged = stage_input(reader, session)?;
        let file = staged
            .reopen()
            .map_err(|_| TransformationFailure::ReadFailure)?;
        let mut archive = ZipArchive::new(file).map_err(map_zip_error)?;
        let mut observations = Vec::new();
        let mut member_index = DerivedMemberIndex::default();

        for index in 0..archive.len() {
            session.check_cancelled()?;
            let mut member = archive.by_index(index).map_err(map_zip_error)?;
            if member.encrypted() {
                return Err(TransformationFailure::EncryptedUnsupported);
            }
            if member.is_symlink() {
                return Err(TransformationFailure::UnsupportedFeature);
            }
            let raw_name = member.name().to_owned();
            let (safe_name, display_name) = normalize_member_name(&raw_name)?;
            let key = DerivedEntryKey::from_transformation(format!("member:{safe_name}"));
            let locator = DerivedLocator::from_transformation(format!("zip:member:{safe_name}"));
            let kind = if member.is_dir() {
                SourceEntryKind::Directory
            } else {
                SourceEntryKind::File
            };
            let size = member.size();
            let staged = if kind == SourceEntryKind::Directory {
                if size != 0 {
                    return Err(TransformationFailure::Malformed);
                }
                None
            } else {
                Some(collect_decoded(&mut member, Some(size), session)?)
            };
            let metadata = format!(
                "raw={raw_name:?};compressed={};size={size};crc={};method={:?}",
                member.compressed_size(),
                member.crc32(),
                member.compression()
            );
            add_member(
                &mut observations,
                &mut member_index,
                session,
                parent_version,
                self.transformation_id(),
                self.revision(),
                locator,
                key,
                safe_name,
                display_name,
                kind,
                Some(size),
                metadata.as_bytes(),
                staged,
            )?;
        }

        Ok(complete_scope(self, observations, member_index))
    }
}

impl DerivedContainerDecoder for SevenZipContainerDecoder {
    fn transformation_id(&self) -> &'static str {
        SEVEN_Z_TRANSFORMATION
    }

    fn enumerate(
        &self,
        reader: &mut dyn ContentReader,
        parent_version: &SourceVersionEvidence,
        session: &mut ParsingSession<'_>,
    ) -> Result<DerivedScopeResult, TransformationFailure> {
        let staged = stage_input(reader, session)?;
        let file = staged
            .reopen()
            .map_err(|_| TransformationFailure::ReadFailure)?;
        let mut archive = ArchiveReader::new(file, Password::empty()).map_err(map_seven_z_error)?;
        let mut observations = Vec::new();
        let mut member_index = DerivedMemberIndex::default();
        let mut callback_failure = None;

        let result = archive.for_each_entries(|entry, entry_reader| {
            let result = (|| {
                session.check_cancelled()?;
                if entry.is_anti_item {
                    return Err(TransformationFailure::UnsupportedFeature);
                }
                let (safe_name, display_name) = normalize_member_name(entry.name())?;
                let key = DerivedEntryKey::from_transformation(format!("member:{safe_name}"));
                let locator =
                    DerivedLocator::from_transformation(format!("sevenzip:member:{safe_name}"));
                let kind = if entry.is_directory {
                    SourceEntryKind::Directory
                } else {
                    SourceEntryKind::File
                };
                let staged = if kind == SourceEntryKind::Directory {
                    if entry.size != 0 || entry.has_stream {
                        return Err(TransformationFailure::Malformed);
                    }
                    None
                } else if entry.has_stream {
                    Some(collect_decoded(entry_reader, Some(entry.size), session)?)
                } else {
                    if entry.size != 0 {
                        return Err(TransformationFailure::Malformed);
                    }
                    Some(session.stage_bytes("archive-member", &[])?)
                };
                let metadata = format!(
                    "raw={:?};compressed={};size={};crc={};has_crc={}",
                    entry.name, entry.compressed_size, entry.size, entry.crc, entry.has_crc
                );
                add_member(
                    &mut observations,
                    &mut member_index,
                    session,
                    parent_version,
                    self.transformation_id(),
                    self.revision(),
                    locator,
                    key,
                    safe_name,
                    display_name,
                    kind,
                    Some(entry.size),
                    metadata.as_bytes(),
                    staged,
                )
            })();
            match result {
                Ok(()) => Ok(true),
                Err(failure) => {
                    callback_failure = Some(failure);
                    Err(sevenz_rust2::Error::Unsupported(Cow::Borrowed(
                        "Argus transformation callback rejected the member",
                    )))
                }
            }
        });

        if let Some(failure) = callback_failure {
            return Err(failure);
        }
        result.map_err(map_seven_z_error)?;
        Ok(complete_scope(self, observations, member_index))
    }
}

impl DerivedContainerDecoder for TarContainerDecoder {
    fn transformation_id(&self) -> &'static str {
        TAR_TRANSFORMATION
    }

    fn enumerate(
        &self,
        reader: &mut dyn ContentReader,
        parent_version: &SourceVersionEvidence,
        session: &mut ParsingSession<'_>,
    ) -> Result<DerivedScopeResult, TransformationFailure> {
        let staged = stage_input(reader, session)?;
        let mut file = staged
            .reopen()
            .map_err(|_| TransformationFailure::ReadFailure)?;
        let mut observations = Vec::new();
        let mut member_index = DerivedMemberIndex::default();
        let mut index = 0_u64;

        loop {
            session.check_cancelled()?;
            let mut header = [0_u8; TAR_BLOCK_BYTES];
            match read_file_exact(&mut file, &mut header, session, true)? {
                FileReadStatus::Eof => return Err(TransformationFailure::Malformed),
                FileReadStatus::Complete => {}
            }
            if header.iter().all(|byte| *byte == 0) {
                let mut second = [0_u8; TAR_BLOCK_BYTES];
                match read_file_exact(&mut file, &mut second, session, true)? {
                    FileReadStatus::Eof => return Err(TransformationFailure::Malformed),
                    FileReadStatus::Complete if second.iter().any(|byte| *byte != 0) => {
                        return Err(TransformationFailure::Malformed);
                    }
                    FileReadStatus::Complete => {}
                }
                ensure_zero_tail(&mut file, session)?;
                break;
            }
            validate_tar_checksum(&header)?;
            let raw_name = tar_member_name(&header)?;
            let (safe_name, display_name) = normalize_member_name(&raw_name)?;
            let size = parse_tar_octal(&header[124..136])?;
            let typeflag = header[156];
            let kind = match typeflag {
                0 | b'0' => SourceEntryKind::File,
                b'5' => SourceEntryKind::Directory,
                _ => return Err(TransformationFailure::UnsupportedFeature),
            };
            let staged = if kind == SourceEntryKind::Directory {
                if size != 0 {
                    return Err(TransformationFailure::Malformed);
                }
                None
            } else {
                read_file_contents(&mut file, size, session)?
            };
            if kind == SourceEntryKind::Directory {
                skip_file_bytes(&mut file, size, session)?;
            }
            let padding =
                (TAR_BLOCK_BYTES as u64 - (size % TAR_BLOCK_BYTES as u64)) % TAR_BLOCK_BYTES as u64;
            skip_file_bytes(&mut file, padding, session)?;
            let key = DerivedEntryKey::from_transformation(format!("member:{safe_name}"));
            let locator = DerivedLocator::from_transformation(format!("tar:member:{safe_name}"));
            let metadata = format!("raw={raw_name:?};size={size};type={typeflag}");
            add_member(
                &mut observations,
                &mut member_index,
                session,
                parent_version,
                self.transformation_id(),
                self.revision(),
                locator,
                key,
                safe_name,
                display_name,
                kind,
                Some(size),
                metadata.as_bytes(),
                staged,
            )?;
            index = index
                .checked_add(1)
                .ok_or(TransformationFailure::ResourceLimitExceeded)?;
        }

        Ok(complete_scope(self, observations, member_index))
    }
}

impl DerivedContainerDecoder for GzipContainerDecoder {
    fn transformation_id(&self) -> &'static str {
        GZIP_TRANSFORMATION
    }

    fn enumerate(
        &self,
        reader: &mut dyn ContentReader,
        parent_version: &SourceVersionEvidence,
        session: &mut ParsingSession<'_>,
    ) -> Result<DerivedScopeResult, TransformationFailure> {
        enumerate_single_stream(self, reader, parent_version, session, |file| {
            GzDecoder::new(BufReader::new(file))
        })
    }
}

impl DerivedContainerDecoder for Bzip2ContainerDecoder {
    fn transformation_id(&self) -> &'static str {
        BZIP2_TRANSFORMATION
    }

    fn enumerate(
        &self,
        reader: &mut dyn ContentReader,
        parent_version: &SourceVersionEvidence,
        session: &mut ParsingSession<'_>,
    ) -> Result<DerivedScopeResult, TransformationFailure> {
        let staged = stage_input(reader, session)?;
        let file = staged
            .reopen()
            .map_err(|_| TransformationFailure::ReadFailure)?;
        let decoder = BzDecoder::new(file).map_err(map_oxiarc_error)?;
        let mut decoded = Bzip2DecodedReader {
            decoder,
            pending: Vec::new(),
            offset: 0,
        };
        let staged = session.stage_decoded_reader("bzip2-output", &mut decoded, UNKNOWN_SIZE)?;
        single_stream_scope(self, parent_version, session, staged)
    }
}

impl DerivedContainerDecoder for XzContainerDecoder {
    fn transformation_id(&self) -> &'static str {
        XZ_TRANSFORMATION
    }

    fn enumerate(
        &self,
        reader: &mut dyn ContentReader,
        parent_version: &SourceVersionEvidence,
        session: &mut ParsingSession<'_>,
    ) -> Result<DerivedScopeResult, TransformationFailure> {
        enumerate_single_stream(self, reader, parent_version, session, |file| {
            XzReader::new(file, false)
        })
    }
}

fn enumerate_single_stream<D, R, F>(
    decoder: &D,
    reader: &mut dyn ContentReader,
    parent_version: &SourceVersionEvidence,
    session: &mut ParsingSession<'_>,
    make_decoder: F,
) -> Result<DerivedScopeResult, TransformationFailure>
where
    D: DerivedContainerDecoder,
    R: SingleStreamDecoder,
    F: FnOnce(File) -> R,
{
    let staged = stage_input(reader, session)?;
    let file = staged
        .reopen()
        .map_err(|_| TransformationFailure::ReadFailure)?;
    let mut decoded = make_decoder(file);
    let staged = session.stage_decoded_reader("compressed-output", &mut decoded, UNKNOWN_SIZE)?;
    decoded
        .ensure_no_trailing_data()
        .map_err(|_| TransformationFailure::Malformed)?;
    single_stream_scope(decoder, parent_version, session, staged)
}

fn single_stream_scope<D: DerivedContainerDecoder>(
    decoder: &D,
    parent_version: &SourceVersionEvidence,
    session: &mut ParsingSession<'_>,
    staged: StagedRepresentation,
) -> Result<DerivedScopeResult, TransformationFailure> {
    let key = DerivedEntryKey::from_transformation("stream:0".to_owned());
    let locator =
        DerivedLocator::from_transformation(format!("{}:stream:0", decoder.transformation_id()));
    let mut observations = Vec::new();
    let mut member_index = DerivedMemberIndex::default();
    add_member(
        &mut observations,
        &mut member_index,
        session,
        parent_version,
        decoder.transformation_id(),
        decoder.revision(),
        locator,
        key,
        "stream".to_owned(),
        "stream".to_owned(),
        SourceEntryKind::File,
        Some(staged.len()),
        b"single-stream",
        Some(staged),
    )?;
    Ok(complete_scope(decoder, observations, member_index))
}

fn stage_input(
    reader: &mut dyn ContentReader,
    session: &mut ParsingSession<'_>,
) -> Result<StagedRepresentation, TransformationFailure> {
    session.stage_content_reader("derived-input", reader)
}

fn collect_decoded<R: Read + ?Sized>(
    reader: &mut R,
    declared_size: Option<u64>,
    session: &mut ParsingSession<'_>,
) -> Result<StagedRepresentation, TransformationFailure> {
    session.stage_decoded_reader("archive-member", reader, declared_size)
}

#[allow(clippy::too_many_arguments)]
fn add_member(
    observations: &mut Vec<DerivedEntryObservation>,
    member_index: &mut DerivedMemberIndex,
    session: &mut ParsingSession<'_>,
    parent_version: &SourceVersionEvidence,
    transformation_id: &'static str,
    revision: u32,
    locator: DerivedLocator,
    key: DerivedEntryKey,
    safe_name: String,
    display_name: String,
    kind: SourceEntryKind,
    cheap_size: Option<u64>,
    metadata: &[u8],
    staged: Option<StagedRepresentation>,
) -> Result<(), TransformationFailure> {
    session.charge_derived_entry()?;
    let fingerprint = derived_fingerprint(
        parent_version,
        transformation_id,
        revision,
        &key,
        &display_name,
        kind,
        cheap_size,
        metadata,
    );
    member_index.push(key.clone(), display_name.clone(), kind, staged)?;
    observations.push(
        DerivedEntryObservation::new(locator, key, display_name, kind, cheap_size, fingerprint)
            .with_display_location(safe_name),
    );
    Ok(())
}

fn complete_scope(
    decoder: &dyn DerivedContainerDecoder,
    observations: Vec<DerivedEntryObservation>,
    member_index: DerivedMemberIndex,
) -> DerivedScopeResult {
    DerivedScopeResult::with_transformation(
        observations,
        DerivedScopeOutcome::Complete,
        member_index,
        decoder.transformation_id(),
        decoder.revision(),
    )
}

#[allow(clippy::too_many_arguments)]
fn derived_fingerprint(
    parent_version: &SourceVersionEvidence,
    transformation_id: &str,
    revision: u32,
    key: &DerivedEntryKey,
    display_name: &str,
    kind: SourceEntryKind,
    cheap_size: Option<u64>,
    metadata: &[u8],
) -> DerivedFingerprint {
    let mut hasher = Sha256::new();
    hash_field(&mut hasher, b"argus-derived-fingerprint-v1");
    hash_field(
        &mut hasher,
        parent_version.source_entry_id().to_string().as_bytes(),
    );
    match parent_version.version() {
        SourceVersionKind::Provider(fingerprint) => {
            hash_field(&mut hasher, b"provider");
            hash_field(&mut hasher, fingerprint.as_deref().unwrap_or("").as_bytes());
        }
        SourceVersionKind::Derived(fingerprint) => {
            hash_field(&mut hasher, b"derived");
            hash_field(
                &mut hasher,
                fingerprint.as_transformation_value().as_bytes(),
            );
        }
    }
    hash_field(&mut hasher, transformation_id.as_bytes());
    hash_field(&mut hasher, &revision.to_be_bytes());
    hash_field(&mut hasher, key.as_transformation_value().as_bytes());
    hash_field(&mut hasher, display_name.as_bytes());
    hash_field(&mut hasher, kind.as_str().as_bytes());
    hash_field(
        &mut hasher,
        &cheap_size.map_or(u64::MAX, |size| size).to_be_bytes(),
    );
    hash_field(&mut hasher, metadata);
    let digest = hasher.finalize();
    let mut text = String::with_capacity(digest.len() * 2);
    for byte in digest {
        text.push_str(&format!("{byte:02x}"));
    }
    DerivedFingerprint::from_transformation(text)
}

fn hash_field(hasher: &mut Sha256, field: &[u8]) {
    hasher.update((field.len() as u64).to_be_bytes());
    hasher.update(field);
}

fn normalize_member_name(name: &str) -> Result<(String, String), TransformationFailure> {
    if name.is_empty()
        || name.as_bytes().contains(&0)
        || name.starts_with('/')
        || name.starts_with('\\')
    {
        return Err(TransformationFailure::Malformed);
    }
    let bytes = name.as_bytes();
    if bytes.len() >= 2 && bytes[0].is_ascii_alphabetic() && bytes[1] == b':' {
        return Err(TransformationFailure::Malformed);
    }
    let mut components = Vec::new();
    let trailing_separator = name.ends_with('/') || name.ends_with('\\');
    let component_count = name.split(['/', '\\']).count();
    for (index, component) in name.split(['/', '\\']).enumerate() {
        if component.is_empty() {
            if !(trailing_separator && index + 1 == component_count) {
                return Err(TransformationFailure::Malformed);
            }
            continue;
        }
        if component == "." || component == ".." {
            return Err(TransformationFailure::Malformed);
        }
        components.push(component);
    }
    if components.is_empty() {
        return Err(TransformationFailure::Malformed);
    }
    let safe_name = components.join("/");
    let display_name = components.last().copied().unwrap_or_default().to_owned();
    Ok((safe_name, display_name))
}

fn read_content_range(
    reader: &mut dyn ContentReader,
    offset: u64,
    length: usize,
    session: &mut ParsingSession<'_>,
) -> Result<Vec<u8>, TransformationFailure> {
    if length == 0 {
        return Ok(Vec::new());
    }
    let source_length = reader.len().map_err(map_content_read_error)?;
    let end = offset
        .checked_add(length as u64)
        .ok_or(TransformationFailure::ResourceLimitExceeded)?;
    if end > source_length {
        return Err(TransformationFailure::Malformed);
    }
    let max_read_size = reader.max_read_size();
    if max_read_size == 0 {
        return Err(TransformationFailure::ReadFailure);
    }
    let chunk_size = max_read_size.min(64 * 1024);
    let mut bytes = vec![0_u8; length];
    let mut position = 0;
    while position < length {
        session.check_cancelled()?;
        let end = (position + chunk_size).min(length);
        let count = reader
            .read_at(offset + position as u64, &mut bytes[position..end])
            .map_err(map_content_read_error)?;
        if count == 0 || count > end - position {
            return Err(TransformationFailure::ReadFailure);
        }
        session.charge_parser_work(1)?;
        position += count;
    }
    Ok(bytes)
}

fn map_content_read_error(error: ContentReadError) -> TransformationFailure {
    match error {
        ContentReadError::OutOfRange => TransformationFailure::Malformed,
        ContentReadError::RequestTooLarge => TransformationFailure::ResourceLimitExceeded,
        ContentReadError::Io => TransformationFailure::ReadFailure,
    }
}

fn map_zip_error(error: ZipError) -> TransformationFailure {
    match error {
        ZipError::Io(_) => TransformationFailure::ReadFailure,
        ZipError::InvalidPassword | ZipError::UnsupportedArchive(ZipError::PASSWORD_REQUIRED) => {
            TransformationFailure::EncryptedUnsupported
        }
        ZipError::CompressionMethodNotSupported(_) => TransformationFailure::UnsupportedFeature,
        ZipError::InvalidArchive(_) | ZipError::FileNotFound | ZipError::UnsupportedArchive(_) => {
            TransformationFailure::Malformed
        }
        _ => TransformationFailure::Malformed,
    }
}

fn map_seven_z_error(error: sevenz_rust2::Error) -> TransformationFailure {
    match error {
        sevenz_rust2::Error::PasswordRequired | sevenz_rust2::Error::MaybeBadPassword(_) => {
            TransformationFailure::EncryptedUnsupported
        }
        sevenz_rust2::Error::Io(_, _) | sevenz_rust2::Error::FileOpen(_, _) => {
            TransformationFailure::ReadFailure
        }
        sevenz_rust2::Error::Unsupported(message) if contains_encryption_hint(&message) => {
            TransformationFailure::EncryptedUnsupported
        }
        sevenz_rust2::Error::UnsupportedCompressionMethod(method)
            if contains_encryption_hint(&method) =>
        {
            TransformationFailure::EncryptedUnsupported
        }
        sevenz_rust2::Error::UnsupportedCompressionMethod(_)
        | sevenz_rust2::Error::ExternalUnsupported
        | sevenz_rust2::Error::Unsupported(_) => TransformationFailure::UnsupportedFeature,
        sevenz_rust2::Error::Other(message) if contains_encryption_hint(&message) => {
            TransformationFailure::EncryptedUnsupported
        }
        sevenz_rust2::Error::MaxMemLimited { .. } => TransformationFailure::ResourceLimitExceeded,
        _ => TransformationFailure::Malformed,
    }
}

/// Adapts oxiarc's block-oriented bzip2 decoder to the streaming staging
/// interface. At most one decoder block is retained while the operation
/// copies output to disk.
struct Bzip2DecodedReader {
    decoder: BzDecoder<File>,
    pending: Vec<u8>,
    offset: usize,
}

impl Read for Bzip2DecodedReader {
    fn read(&mut self, destination: &mut [u8]) -> std::io::Result<usize> {
        if destination.is_empty() {
            return Ok(0);
        }
        loop {
            if self.offset < self.pending.len() {
                let count = (self.pending.len() - self.offset).min(destination.len());
                destination[..count]
                    .copy_from_slice(&self.pending[self.offset..self.offset + count]);
                self.offset += count;
                return Ok(count);
            }
            self.pending.clear();
            self.offset = 0;
            match self.decoder.read_block().map_err(map_bzip2_error)? {
                Some(block) => self.pending = block,
                None => return Ok(0),
            }
        }
    }
}

fn map_bzip2_error(error: OxiArcError) -> std::io::Error {
    match error {
        OxiArcError::Io(error) => error,
        error @ OxiArcError::UnexpectedEof { .. } => {
            std::io::Error::new(std::io::ErrorKind::UnexpectedEof, error.to_string())
        }
        error => std::io::Error::new(std::io::ErrorKind::InvalidData, error.to_string()),
    }
}

fn contains_encryption_hint(message: &str) -> bool {
    let message = message.to_ascii_lowercase();
    message.contains("encrypt") || message.contains("password") || message.contains("aes")
}

fn map_oxiarc_error<E: std::fmt::Debug>(_: E) -> TransformationFailure {
    TransformationFailure::Malformed
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum FileReadStatus {
    Eof,
    Complete,
}

fn read_file_exact(
    file: &mut File,
    destination: &mut [u8],
    session: &mut ParsingSession<'_>,
    allow_eof_at_start: bool,
) -> Result<FileReadStatus, TransformationFailure> {
    let mut position = 0;
    while position < destination.len() {
        session.check_cancelled()?;
        let count = file
            .read(&mut destination[position..])
            .map_err(|_| TransformationFailure::ReadFailure)?;
        if count == 0 {
            if position == 0 && allow_eof_at_start {
                return Ok(FileReadStatus::Eof);
            }
            return Err(TransformationFailure::Malformed);
        }
        session.charge_parser_work(1)?;
        position += count;
    }
    Ok(FileReadStatus::Complete)
}

fn ensure_zero_tail(
    file: &mut File,
    session: &mut ParsingSession<'_>,
) -> Result<(), TransformationFailure> {
    let mut buffer = [0_u8; 64 * 1024];
    loop {
        session.check_cancelled()?;
        let count = file
            .read(&mut buffer)
            .map_err(|_| TransformationFailure::ReadFailure)?;
        if count == 0 {
            return Ok(());
        }
        session.charge_parser_work(1)?;
        if buffer[..count].iter().any(|byte| *byte != 0) {
            return Err(TransformationFailure::Malformed);
        }
    }
}

fn read_file_contents(
    file: &mut File,
    length: u64,
    session: &mut ParsingSession<'_>,
) -> Result<Option<StagedRepresentation>, TransformationFailure> {
    Ok(Some(session.stage_reader("tar-member", length, file)?))
}

fn skip_file_bytes(
    file: &mut File,
    length: u64,
    session: &mut ParsingSession<'_>,
) -> Result<(), TransformationFailure> {
    if length == 0 {
        return Ok(());
    }
    let mut remaining = length;
    let mut buffer = [0_u8; 64 * 1024];
    while remaining > 0 {
        session.check_cancelled()?;
        let request = remaining.min(buffer.len() as u64) as usize;
        read_file_exact(file, &mut buffer[..request], session, false)?;
        remaining -= request as u64;
    }
    Ok(())
}

fn validate_tar_checksum(header: &[u8; TAR_BLOCK_BYTES]) -> Result<(), TransformationFailure> {
    let stored = parse_tar_octal(&header[148..156])?;
    let mut sum = 0_u64;
    for (index, byte) in header.iter().enumerate() {
        sum = sum
            .checked_add(if (148..156).contains(&index) {
                u64::from(b' ')
            } else {
                u64::from(*byte)
            })
            .ok_or(TransformationFailure::ResourceLimitExceeded)?;
    }
    if stored != sum {
        return Err(TransformationFailure::Malformed);
    }
    Ok(())
}

fn tar_member_name(header: &[u8; TAR_BLOCK_BYTES]) -> Result<String, TransformationFailure> {
    let name = field_string(&header[..100])?;
    let prefix = field_string(&header[345..500])?;
    if prefix.is_empty() {
        Ok(name)
    } else if name.is_empty() {
        Ok(prefix)
    } else {
        Ok(format!("{prefix}/{name}"))
    }
}

fn field_string(field: &[u8]) -> Result<String, TransformationFailure> {
    let end = field
        .iter()
        .position(|byte| *byte == 0)
        .unwrap_or(field.len());
    String::from_utf8(field[..end].to_vec()).map_err(|_| TransformationFailure::Malformed)
}

fn parse_tar_octal(field: &[u8]) -> Result<u64, TransformationFailure> {
    let start = field
        .iter()
        .position(|byte| *byte != b' ' && *byte != 0)
        .ok_or(TransformationFailure::Malformed)?;
    let end = field[start..]
        .iter()
        .position(|byte| !byte.is_ascii_digit())
        .map_or(field.len(), |offset| start + offset);
    let digits = &field[start..end];
    if digits.is_empty()
        || digits.iter().any(|byte| !(b'0'..=b'7').contains(byte))
        || field[end..].iter().any(|byte| *byte != b' ' && *byte != 0)
    {
        return Err(TransformationFailure::Malformed);
    }
    digits.iter().copied().try_fold(0_u64, |value, digit| {
        value
            .checked_mul(8)
            .and_then(|value| value.checked_add(u64::from(digit - b'0')))
            .ok_or(TransformationFailure::ResourceLimitExceeded)
    })
}

#[cfg(test)]
mod tests {
    use std::io::Read as _;

    use oxiarc_bzip2::{CompressionLevel, compress};
    use oxiarc_core::error::OxiArcError;

    use super::{Bzip2DecodedReader, map_bzip2_error};

    #[test]
    fn bzip2_non_eof_io_error_preserves_underlying_error_kind() {
        let error = map_bzip2_error(OxiArcError::Io(std::io::Error::new(
            std::io::ErrorKind::PermissionDenied,
            "staging read failed",
        )));

        assert_eq!(error.kind(), std::io::ErrorKind::PermissionDenied);
    }

    #[test]
    fn truncated_bzip2_input_preserves_unexpected_eof() {
        let mut compressed = compress(b"truncated bzip2 payload", CompressionLevel::new(1))
            .expect("compress test payload");
        compressed.pop();
        let file = tempfile::NamedTempFile::new().expect("temporary compressed file");
        std::fs::write(file.path(), compressed).expect("write truncated payload");
        let decoder = oxiarc_bzip2::BzDecoder::new(file.reopen().expect("reopen payload"))
            .expect("decoder header");
        let mut reader = Bzip2DecodedReader {
            decoder,
            pending: Vec::new(),
            offset: 0,
        };
        let error = reader
            .read_to_end(&mut Vec::new())
            .expect_err("truncated payload must fail");
        assert_eq!(error.kind(), std::io::ErrorKind::UnexpectedEof);
    }
}
