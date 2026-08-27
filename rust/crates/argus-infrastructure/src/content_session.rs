//! Operation-scoped accounting and disk-backed staging for transformations.
//!
//! A parsing session is deliberately independent of any parser library. It
//! owns the cumulative limits, cancellation checks, and temporary files that
//! every transformation in one operation must share.

use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use argus_application::{
    SourceAccessError, SourceReadHandle, TransformationBudget, TransformationFailure,
};
use fs2::available_space;

/// Directory below the application-private data directory used for temporary
/// transformation files.
pub const TRANSFORMATION_STAGING_DIRECTORY: &str = "transformation-staging";

/// Prefix identifying an operation directory owned by Argus.
pub const STAGING_DIRECTORY_PREFIX: &str = "argus-transform-";

/// Marker file required before startup cleanup may remove an operation
/// directory.
pub const STAGING_MARKER_FILE: &str = ".argus-staging-marker";

/// Exact marker contents written to a newly created operation directory.
pub const STAGING_MARKER_VALUE: &[u8] = b"argus-transformation-staging-v1\n";

const STAGING_CHUNK_BYTES: usize = 64 * 1024;
const DIRECTORY_CREATION_ATTEMPTS: u32 = 16;

/// Provides the available bytes at one application-private staging root.
pub trait StagingSpaceProbe: Send + Sync {
    /// Returns the currently available space without exposing platform-native
    /// filesystem values to transformation code.
    fn available_bytes(&self, staging_root: &Path) -> io::Result<u64>;
}

/// Production disk-space probe backed by the filesystem containing the staging
/// root.
#[derive(Clone, Copy, Debug, Default)]
pub struct FilesystemStagingSpaceProbe;

impl StagingSpaceProbe for FilesystemStagingSpaceProbe {
    fn available_bytes(&self, staging_root: &Path) -> io::Result<u64> {
        available_space(staging_root)
    }
}

/// One completed, read-only representation staged for a parser that needs a
/// stable seekable file.
#[derive(Debug)]
pub struct StagedRepresentation {
    path: PathBuf,
    file: File,
    length: u64,
}

impl StagedRepresentation {
    /// Returns the operation-private path of the completed file.
    pub fn path(&self) -> &Path {
        &self.path
    }

    /// Returns the number of bytes copied into the completed file.
    pub const fn len(&self) -> u64 {
        self.length
    }

    /// Returns whether the staged representation contains no bytes.
    pub const fn is_empty(&self) -> bool {
        self.length == 0
    }

    /// Reopens the completed representation as a read-only file handle.
    pub fn reopen(&self) -> io::Result<File> {
        self.file.try_clone()
    }
}

struct SessionStaging {
    root: PathBuf,
    operation_directory: Option<PathBuf>,
    next_file_id: u64,
    space_probe: Arc<dyn StagingSpaceProbe>,
}

impl SessionStaging {
    fn new(root: impl AsRef<Path>, space_probe: Arc<dyn StagingSpaceProbe>) -> io::Result<Self> {
        let root = root.as_ref().to_owned();
        fs::create_dir_all(&root)?;
        let operation_directory = create_operation_directory(&root)?;
        let marker_path = operation_directory.join(STAGING_MARKER_FILE);
        let marker_result = (|| {
            let mut marker = OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(&marker_path)?;
            marker.write_all(STAGING_MARKER_VALUE)?;
            marker.sync_all()
        })();
        if let Err(error) = marker_result {
            let _ = fs::remove_dir_all(&operation_directory);
            return Err(error);
        }
        Ok(Self {
            root,
            operation_directory: Some(operation_directory),
            next_file_id: 0,
            space_probe,
        })
    }

    fn operation_directory(&self) -> &Path {
        self.operation_directory
            .as_deref()
            .expect("session staging remains live until session drop")
    }

    fn next_file_path(&mut self) -> PathBuf {
        let file_id = self.next_file_id;
        self.next_file_id = self.next_file_id.saturating_add(1);
        self.operation_directory()
            .join(format!("representation-{file_id:016x}.bin"))
    }

    fn finish(&mut self) -> io::Result<()> {
        let Some(operation_directory) = self.operation_directory.take() else {
            return Ok(());
        };
        match fs::remove_dir_all(operation_directory) {
            Ok(()) => Ok(()),
            Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
            Err(error) => Err(error),
        }
    }
}

impl Drop for SessionStaging {
    fn drop(&mut self) {
        let _ = self.finish();
    }
}

/// One operation-scoped transformation budget and staging lifetime.
pub struct ParsingSession<'a> {
    budget: TransformationBudget,
    expanded_bytes: u64,
    staged_bytes: u64,
    derived_entries: u64,
    nesting_depth: u32,
    parser_work: u64,
    staging: SessionStaging,
    is_cancelled: Box<dyn Fn() -> bool + 'a>,
}

impl<'a> ParsingSession<'a> {
    /// Creates a production session below an application-private staging root.
    pub fn new<C>(
        budget: TransformationBudget,
        staging_root: impl AsRef<Path>,
        is_cancelled: C,
    ) -> Result<Self, TransformationFailure>
    where
        C: Fn() -> bool + 'a,
    {
        Self::new_with_probe(
            budget,
            staging_root,
            Arc::new(FilesystemStagingSpaceProbe),
            is_cancelled,
        )
    }

    /// Creates a session with an injected space probe for deterministic tests
    /// and infrastructure fault simulation.
    pub fn new_with_probe<C>(
        budget: TransformationBudget,
        staging_root: impl AsRef<Path>,
        space_probe: Arc<dyn StagingSpaceProbe>,
        is_cancelled: C,
    ) -> Result<Self, TransformationFailure>
    where
        C: Fn() -> bool + 'a,
    {
        let staging = SessionStaging::new(staging_root, space_probe)
            .map_err(|_| TransformationFailure::ReadFailure)?;
        Ok(Self {
            budget,
            expanded_bytes: 0,
            staged_bytes: 0,
            derived_entries: 0,
            nesting_depth: 0,
            parser_work: 0,
            staging,
            is_cancelled: Box::new(is_cancelled),
        })
    }

    /// Test-oriented constructor using the production filesystem-space probe.
    pub fn for_tests<C>(
        budget: TransformationBudget,
        staging_root: impl AsRef<Path>,
        is_cancelled: C,
    ) -> Self
    where
        C: Fn() -> bool + 'a,
    {
        Self::new(budget, staging_root, is_cancelled).expect("test staging root is usable")
    }

    /// Test-oriented constructor with deterministic free-space behavior.
    pub fn for_tests_with_probe<C>(
        budget: TransformationBudget,
        staging_root: impl AsRef<Path>,
        space_probe: Arc<dyn StagingSpaceProbe>,
        is_cancelled: C,
    ) -> Self
    where
        C: Fn() -> bool + 'a,
    {
        Self::new_with_probe(budget, staging_root, space_probe, is_cancelled)
            .expect("test staging root is usable")
    }

    /// Returns the operation-private directory owned by this session.
    pub fn operation_directory(&self) -> &Path {
        self.staging.operation_directory()
    }

    /// Returns the cumulative expanded-byte count.
    pub const fn expanded_bytes(&self) -> u64 {
        self.expanded_bytes
    }

    /// Returns the cumulative staged-byte count.
    pub const fn staged_bytes(&self) -> u64 {
        self.staged_bytes
    }

    /// Returns the cumulative derived-entry count.
    pub const fn derived_entries(&self) -> u64 {
        self.derived_entries
    }

    /// Returns the current nesting depth.
    pub const fn nesting_depth(&self) -> u32 {
        self.nesting_depth
    }

    /// Returns the cumulative parser-work count.
    pub const fn parser_work(&self) -> u64 {
        self.parser_work
    }

    /// Finishes the session and removes its operation directory.
    pub fn finish(mut self) -> Result<(), TransformationFailure> {
        self.staging
            .finish()
            .map_err(|_| TransformationFailure::ReadFailure)
    }

    /// Charges cumulative expanded representation bytes.
    pub fn charge_expanded(&mut self, bytes: u64) -> Result<(), TransformationFailure> {
        self.check_cancelled()?;
        Self::charge(
            &mut self.expanded_bytes,
            bytes,
            self.budget.max_expanded_bytes(),
        )
    }

    /// Charges cumulative staged bytes.
    pub fn charge_staged(&mut self, bytes: u64) -> Result<(), TransformationFailure> {
        self.check_cancelled()?;
        Self::charge(
            &mut self.staged_bytes,
            bytes,
            self.budget.max_staged_bytes(),
        )
    }

    /// Charges one safely enumerated derived entry.
    pub fn charge_derived_entry(&mut self) -> Result<(), TransformationFailure> {
        self.check_cancelled()?;
        Self::charge(
            &mut self.derived_entries,
            1,
            self.budget.max_derived_entries(),
        )
    }

    /// Charges parser work units shared by every nested transformation.
    pub fn charge_parser_work(&mut self, units: u64) -> Result<(), TransformationFailure> {
        self.check_cancelled()?;
        Self::charge(&mut self.parser_work, units, self.budget.max_parser_work())
    }

    /// Enters one nested container scope.
    pub fn enter_container(&mut self) -> Result<(), TransformationFailure> {
        self.check_cancelled()?;
        let next_depth = self
            .nesting_depth
            .checked_add(1)
            .ok_or(TransformationFailure::ResourceLimitExceeded)?;
        if next_depth > self.budget.max_nesting_depth() {
            return Err(TransformationFailure::ResourceLimitExceeded);
        }
        self.nesting_depth = next_depth;
        Ok(())
    }

    /// Leaves one nested container scope.
    pub fn leave_container(&mut self) {
        self.nesting_depth = self.nesting_depth.saturating_sub(1);
    }

    /// Runs a nested container operation against the same session counters.
    pub fn with_container<T>(
        &mut self,
        operation: impl FnOnce(&mut Self) -> Result<T, TransformationFailure>,
    ) -> Result<T, TransformationFailure> {
        self.enter_container()?;
        let result = operation(self);
        self.leave_container();
        result
    }

    /// Stops work when the operation's cancellation source is set.
    pub fn check_cancelled(&self) -> Result<(), TransformationFailure> {
        if (self.is_cancelled)() {
            Err(TransformationFailure::Cancelled)
        } else {
            Ok(())
        }
    }

    /// Rejects a representation larger than the single-input ceiling.
    pub fn validate_representation_length(&self, bytes: u64) -> Result<(), TransformationFailure> {
        if bytes > self.budget.max_single_representation_bytes() {
            Err(TransformationFailure::ResourceLimitExceeded)
        } else {
            Ok(())
        }
    }

    /// Stages an in-memory representation through the same bounded copy path
    /// used by file-backed transformation inputs.
    pub fn stage_bytes(
        &mut self,
        label: &str,
        bytes: &[u8],
    ) -> Result<StagedRepresentation, TransformationFailure> {
        let mut reader = io::Cursor::new(bytes);
        self.stage_reader(label, bytes.len() as u64, &mut reader)
    }

    /// Stages a known-length reader into the operation directory.
    pub fn stage_reader(
        &mut self,
        _label: &str,
        length: u64,
        reader: &mut dyn Read,
    ) -> Result<StagedRepresentation, TransformationFailure> {
        self.stage_with_length(length, STAGING_CHUNK_BYTES, |_, destination| {
            reader
                .read(destination)
                .map_err(|_| TransformationFailure::ReadFailure)
        })
    }

    /// Stages a provider-owned range-readable source entry.
    pub fn stage_source_read(
        &mut self,
        _label: &str,
        reader: &mut dyn SourceReadHandle,
    ) -> Result<StagedRepresentation, TransformationFailure> {
        let length = reader.len().map_err(map_source_read_error)?;
        let max_read_size = reader.max_read_size();
        if max_read_size == 0 && length != 0 {
            return Err(TransformationFailure::ReadFailure);
        }
        let chunk_size = STAGING_CHUNK_BYTES.min(max_read_size.max(1));
        self.stage_with_length(length, chunk_size, |offset, destination| {
            reader
                .read_at(offset, destination)
                .map_err(map_source_read_error)
        })
    }

    /// Stages a parser-facing reader into the operation directory.
    ///
    /// Representation decoders receive [`ContentReader`] values so they do
    /// not depend on provider APIs. This adapter preserves the same length,
    /// available-space, cumulative staging, and bounded-read checks used by
    /// provider-backed staging.
    pub fn stage_content_reader(
        &mut self,
        _label: &str,
        reader: &mut dyn super::content_stream::ContentReader,
    ) -> Result<StagedRepresentation, TransformationFailure> {
        let length = reader.len().map_err(map_content_read_error)?;
        let max_read_size = reader.max_read_size();
        if max_read_size == 0 && length != 0 {
            return Err(TransformationFailure::ReadFailure);
        }
        let chunk_size = STAGING_CHUNK_BYTES.min(max_read_size.max(1));
        self.stage_with_length(length, chunk_size, |offset, destination| {
            reader
                .read_at(offset, destination)
                .map_err(map_content_read_error)
        })
    }

    /// Stages a decoder output whose final length is discovered while it is
    /// read. Decoder output is written directly to the operation directory;
    /// it is never accumulated as an in-memory representation.
    pub fn stage_decoded_reader<R: Read + ?Sized>(
        &mut self,
        _label: &str,
        reader: &mut R,
        expected_length: Option<u64>,
    ) -> Result<StagedRepresentation, TransformationFailure> {
        self.check_cancelled()?;
        if let Some(length) = expected_length {
            self.validate_representation_length(length)?;
        }
        let path = self.staging.next_file_path();
        let result = self.copy_decoded_to_path(&path, reader, expected_length);
        match result {
            Ok((file, length)) => Ok(StagedRepresentation { path, file, length }),
            Err(error) => {
                let _ = fs::remove_file(path);
                Err(error)
            }
        }
    }

    fn stage_with_length<F>(
        &mut self,
        length: u64,
        chunk_size: usize,
        mut read_chunk: F,
    ) -> Result<StagedRepresentation, TransformationFailure>
    where
        F: FnMut(u64, &mut [u8]) -> Result<usize, TransformationFailure>,
    {
        self.check_cancelled()?;
        self.validate_representation_length(length)?;
        let next_staged = self
            .staged_bytes
            .checked_add(length)
            .ok_or(TransformationFailure::ResourceLimitExceeded)?;
        if next_staged > self.budget.max_staged_bytes() {
            return Err(TransformationFailure::ResourceLimitExceeded);
        }
        let available = self
            .staging
            .space_probe
            .available_bytes(&self.staging.root)
            .map_err(|_| TransformationFailure::ReadFailure)?;
        if available < length {
            return Err(TransformationFailure::ResourceLimitExceeded);
        }
        self.staged_bytes = next_staged;

        let path = self.staging.next_file_path();
        let result = self.copy_to_path(&path, length, chunk_size, &mut read_chunk);
        match result {
            Ok(file) => Ok(StagedRepresentation { path, file, length }),
            Err(error) => {
                let _ = fs::remove_file(path);
                Err(error)
            }
        }
    }

    fn copy_to_path<F>(
        &mut self,
        path: &Path,
        length: u64,
        chunk_size: usize,
        read_chunk: &mut F,
    ) -> Result<File, TransformationFailure>
    where
        F: FnMut(u64, &mut [u8]) -> Result<usize, TransformationFailure>,
    {
        let mut output = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(path)
            .map_err(|_| TransformationFailure::ReadFailure)?;
        let mut buffer = vec![0_u8; chunk_size];
        let mut offset = 0_u64;
        while offset < length {
            self.check_cancelled()?;
            let request_size = (length - offset).min(chunk_size as u64) as usize;
            self.charge_parser_work(request_size as u64)?;
            let count = read_chunk(offset, &mut buffer[..request_size])?;
            self.check_cancelled()?;
            if count == 0 || count > request_size {
                return Err(TransformationFailure::ReadFailure);
            }
            output
                .write_all(&buffer[..count])
                .map_err(|_| TransformationFailure::ReadFailure)?;
            offset = offset
                .checked_add(count as u64)
                .ok_or(TransformationFailure::ResourceLimitExceeded)?;
        }
        output
            .sync_all()
            .map_err(|_| TransformationFailure::ReadFailure)?;
        drop(output);
        OpenOptions::new()
            .read(true)
            .open(path)
            .map_err(|_| TransformationFailure::ReadFailure)
    }

    fn copy_decoded_to_path<R: Read + ?Sized>(
        &mut self,
        path: &Path,
        reader: &mut R,
        expected_length: Option<u64>,
    ) -> Result<(File, u64), TransformationFailure> {
        let mut output = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(path)
            .map_err(|_| TransformationFailure::ReadFailure)?;
        let mut buffer = [0_u8; STAGING_CHUNK_BYTES];
        let mut length = 0_u64;
        loop {
            self.check_cancelled()?;
            let count = reader
                .read(&mut buffer)
                .map_err(|_| TransformationFailure::Malformed)?;
            if count == 0 {
                break;
            }
            let next_length = length
                .checked_add(count as u64)
                .ok_or(TransformationFailure::ResourceLimitExceeded)?;
            self.validate_representation_length(next_length)?;
            if let Some(expected) = expected_length
                && next_length > expected
            {
                return Err(TransformationFailure::Malformed);
            }
            self.charge_expanded(count as u64)?;
            self.charge_staged(count as u64)?;
            self.charge_parser_work(count as u64)?;
            let available = self
                .staging
                .space_probe
                .available_bytes(&self.staging.root)
                .map_err(|_| TransformationFailure::ReadFailure)?;
            if available < count as u64 {
                return Err(TransformationFailure::ResourceLimitExceeded);
            }
            output
                .write_all(&buffer[..count])
                .map_err(|_| TransformationFailure::ReadFailure)?;
            length = next_length;
        }
        if let Some(expected) = expected_length
            && length != expected
        {
            return Err(TransformationFailure::Malformed);
        }
        output
            .sync_all()
            .map_err(|_| TransformationFailure::ReadFailure)?;
        drop(output);
        let file = OpenOptions::new()
            .read(true)
            .open(path)
            .map_err(|_| TransformationFailure::ReadFailure)?;
        Ok((file, length))
    }

    fn charge(counter: &mut u64, delta: u64, limit: u64) -> Result<(), TransformationFailure> {
        let next = counter
            .checked_add(delta)
            .ok_or(TransformationFailure::ResourceLimitExceeded)?;
        if next > limit {
            return Err(TransformationFailure::ResourceLimitExceeded);
        }
        *counter = next;
        Ok(())
    }
}

fn map_source_read_error(error: SourceAccessError) -> TransformationFailure {
    match error {
        SourceAccessError::Cancelled => TransformationFailure::Cancelled,
        SourceAccessError::InvalidResponse => TransformationFailure::Malformed,
        _ => TransformationFailure::ReadFailure,
    }
}

fn map_content_read_error(error: super::content_stream::ContentReadError) -> TransformationFailure {
    match error {
        super::content_stream::ContentReadError::OutOfRange => TransformationFailure::Malformed,
        super::content_stream::ContentReadError::RequestTooLarge => {
            TransformationFailure::ResourceLimitExceeded
        }
        super::content_stream::ContentReadError::Io => TransformationFailure::ReadFailure,
    }
}

/// Removes only abandoned operation directories with the exact Argus prefix
/// and marker value.
pub fn cleanup_abandoned_staging(root: &Path) -> io::Result<u64> {
    let entries = match fs::read_dir(root) {
        Ok(entries) => entries,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(0),
        Err(error) => return Err(error),
    };
    let mut removed = 0_u64;
    for entry in entries {
        let entry = entry?;
        let path = entry.path();
        let name = entry.file_name();
        let Some(name) = name.to_str() else {
            continue;
        };
        if !name.starts_with(STAGING_DIRECTORY_PREFIX) {
            continue;
        }
        let file_type = entry.file_type()?;
        if !file_type.is_dir() || !has_valid_marker(&path) {
            continue;
        }
        match fs::remove_dir_all(path) {
            Ok(()) => removed = removed.saturating_add(1),
            Err(error) if error.kind() == io::ErrorKind::NotFound => {}
            Err(error) => return Err(error),
        }
    }
    Ok(removed)
}

fn has_valid_marker(directory: &Path) -> bool {
    let marker = directory.join(STAGING_MARKER_FILE);
    let Ok(metadata) = fs::symlink_metadata(&marker) else {
        return false;
    };
    metadata.file_type().is_file()
        && fs::read(marker)
            .map(|value| value == STAGING_MARKER_VALUE)
            .unwrap_or(false)
}

fn create_operation_directory(root: &Path) -> io::Result<PathBuf> {
    static OPERATION_COUNTER: AtomicU64 = AtomicU64::new(1);
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_nanos())
        .unwrap_or(0);
    for attempt in 0..DIRECTORY_CREATION_ATTEMPTS {
        let counter = OPERATION_COUNTER.fetch_add(1, Ordering::Relaxed);
        let candidate = root.join(format!(
            "{STAGING_DIRECTORY_PREFIX}{timestamp:032x}-{counter:016x}-{attempt:02x}"
        ));
        match fs::create_dir(&candidate) {
            Ok(()) => return Ok(candidate),
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(error) => return Err(error),
        }
    }
    Err(io::Error::new(
        io::ErrorKind::AlreadyExists,
        "could not allocate a unique transformation staging directory",
    ))
}
