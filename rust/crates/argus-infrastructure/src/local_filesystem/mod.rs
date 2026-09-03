//! Concrete LocalFilesystem source-provider adapter.
//!
//! This adapter owns all filesystem parsing, normalization, validation,
//! locator construction, and root-relationship semantics for the
//! `local_filesystem` provider family. Generic application, persistence,
//! bridge, and Flutter code never interprets the provider-owned locator
//! values produced here.

use std::collections::BTreeMap;
use std::io::{Read, Seek, SeekFrom};
use std::path::{Component, Path, PathBuf};
#[cfg(target_os = "android")]
use std::sync::OnceLock;
use std::sync::{Arc, Mutex, RwLock};
use std::time::UNIX_EPOCH;

#[cfg(target_os = "macos")]
use objc2::rc::Retained;
#[cfg(target_os = "macos")]
use objc2::runtime::Bool;
#[cfg(all(target_os = "macos", any(test, feature = "test-support")))]
use objc2_foundation::NSURLBookmarkCreationOptions;
#[cfg(target_os = "macos")]
use objc2_foundation::{NSData, NSURL, NSURLBookmarkResolutionOptions};

use crate::content::{ContentReadError, ContentReader};
use argus_application::{
    DiscoveryPath, DiscoverySegment, EnumerationOutcome, EnumerationResult, LibrarySourceAccess,
    LocalFilesystemBrowseBreadcrumb, LocalFilesystemBrowseCursor, LocalFilesystemBrowseDirectory,
    LocalFilesystemBrowseLocation, LocalFilesystemBrowsePage, LocalFilesystemBrowseProvider,
    LocalFilesystemBrowseRoot, LocalFilesystemProvider as LocalFilesystemProviderPort,
    LocalFilesystemRootSelection, MAX_LOCAL_FILESYSTEM_BROWSE_PAGE_SIZE,
    MAX_MOUNTED_LOCAL_FILESYSTEM_VOLUMES, MountedLocalFilesystemVolume, ObservedEntryKind,
    ProviderError, RelativeSourceLocator, ResolvedRoot, RootLocator, RootRelationship,
    SourceAccessError, SourceLocatorKey, SourceObservation, SourceReadHandle, ValidatedLocalRoot,
};

const ROOT_LOCATOR_PREFIX: &str = "argus-local-root-v2";
const BROWSE_LOCATION_PREFIX: &str = "argus-local-browse-v1";
const BROWSE_CURSOR_PREFIX: &str = "argus-local-cursor-v1";
const PRIMARY_VOLUME_ID: &str = "primary";

#[cfg(target_os = "macos")]
const MACOS_ROOT_LOCATOR_PREFIX: &str = "argus.local.macos-root.v1";
#[cfg(target_os = "macos")]
const MAX_MACOS_ROOT_PATH_BYTES: usize = 32 * 1024;
#[cfg(target_os = "macos")]
const MAX_MACOS_BOOKMARK_BYTES: usize = 1024 * 1024;

#[derive(Clone, Debug)]
struct MountedVolume {
    provider_volume_id: String,
    canonical_mount_path: PathBuf,
    display_name: String,
    is_primary: bool,
}

#[derive(Clone, Debug, Default)]
struct MountedVolumeRegistry {
    volumes: BTreeMap<String, MountedVolume>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct BrowseCoordinate {
    provider_volume_id: String,
    relative: PathBuf,
}

/// Concrete execution-scoped local-filesystem source access.
///
/// The adapter owns all native path interpretation, locator keys, identity
/// facts, and error translation for one scan execution attempt. It is never
/// persisted and never reused across runtime generations.
pub struct LocalFilesystemSourceAccess {
    locator: String,
    resolved_root: Mutex<Option<ResolvedRootState>>,
    mounted_volumes: Option<Arc<RwLock<MountedVolumeRegistry>>>,
    #[cfg(all(test, target_os = "macos"))]
    test_bookmark_resolver: Option<TestBookmarkResolver>,
}

struct ResolvedRootState {
    path: PathBuf,
    #[cfg(target_os = "macos")]
    _security_scope: Option<MacosSecurityScope>,
}

#[cfg(target_os = "macos")]
struct MacosSecurityScope {
    url: Retained<NSURL>,
    #[cfg(test)]
    test_stop_count: Option<Arc<std::sync::atomic::AtomicUsize>>,
}

#[cfg(all(test, target_os = "macos"))]
type TestBookmarkResolver =
    Arc<dyn Fn(&[u8]) -> Result<MacosSecurityScope, SourceAccessError> + Send + Sync>;

#[cfg(all(test, target_os = "macos"))]
impl MacosSecurityScope {
    fn test_started(url: Retained<NSURL>, stop_count: Arc<std::sync::atomic::AtomicUsize>) -> Self {
        Self {
            url,
            test_stop_count: Some(stop_count),
        }
    }
}

#[cfg(target_os = "macos")]
#[allow(unsafe_code)]
impl Drop for MacosSecurityScope {
    fn drop(&mut self) {
        #[cfg(test)]
        if let Some(stop_count) = self.test_stop_count.take() {
            stop_count.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            return;
        }

        // SAFETY: The URL was retained from successful bookmark resolution
        // and startAccessingSecurityScopedResource, so it remains a valid
        // security-scoped resource until this guard is dropped.
        unsafe { self.url.stopAccessingSecurityScopedResource() };
    }
}

/// Seek-backed bounded reader used by the general content recognizer.
///
/// The reader retains only the open file handle and the source metadata
/// observed when processing began. Each request is range-bounded, and the
/// caller can validate the source metadata again before persistence begins.
pub struct LocalContentReader {
    file: std::fs::File,
    path: PathBuf,
    length: u64,
    initial_fingerprint: String,
    initial_change_evidence: String,
    initial_identity_evidence: Option<String>,
    initial_handle_change_time: Option<i64>,
    initial_handle_usn: Option<i64>,
}

impl LocalContentReader {
    fn open(path: PathBuf, metadata: &std::fs::Metadata) -> Result<Self, SourceAccessError> {
        let file = std::fs::File::open(&path).map_err(classify_entry_access_error)?;
        let handle_metadata = file.metadata().map_err(classify_entry_access_error)?;
        let initial_handle_change_time = native_handle_change_time(&file);
        let initial_handle_usn = native_handle_usn(&file);
        let initial_change_evidence =
            source_change_evidence(&handle_metadata, ObservedEntryKind::File);
        let initial_identity_evidence =
            source_identity_evidence(&file, &handle_metadata, ObservedEntryKind::File);
        Ok(Self {
            file,
            path,
            length: handle_metadata.len(),
            initial_fingerprint: source_fingerprint(metadata, ObservedEntryKind::File),
            initial_change_evidence,
            initial_identity_evidence,
            initial_handle_change_time,
            initial_handle_usn,
        })
    }

    /// Returns whether the source still has the version observed at open.
    pub fn source_version_is_unchanged(&self) -> Result<bool, SourceAccessError> {
        let path_metadata =
            std::fs::symlink_metadata(&self.path).map_err(classify_entry_access_error)?;
        if !path_metadata.file_type().is_file() {
            return Ok(false);
        }
        let handle_metadata = self.file.metadata().map_err(classify_entry_access_error)?;
        if !handle_metadata.is_file() {
            return Ok(false);
        }
        // The path identity detects atomic replacement, while the opened
        // handle's native/high-resolution evidence detects in-place changes.
        // The initial handle snapshot is intentional: path-level timestamps
        // can be stale on networked or virtual filesystems. The persisted
        // fingerprint remains in the historical millisecond format.
        let current_identity_evidence = current_path_identity_evidence(&self.path, &path_metadata)?;
        if current_identity_evidence.is_none()
            || current_identity_evidence != self.initial_identity_evidence
            || source_change_evidence(&handle_metadata, ObservedEntryKind::File)
                != self.initial_change_evidence
        {
            return Ok(false);
        }
        if native_handle_change_time(&self.file) != self.initial_handle_change_time {
            return Ok(false);
        }
        if native_handle_usn(&self.file) != self.initial_handle_usn {
            return Ok(false);
        }
        Ok(true)
    }

    /// Returns the source-version fingerprint observed when the reader opened.
    pub fn source_fingerprint(&self) -> &str {
        &self.initial_fingerprint
    }
}

impl ContentReader for LocalContentReader {
    fn len(&self) -> Result<u64, ContentReadError> {
        Ok(self.length)
    }

    fn read_at(&mut self, offset: u64, destination: &mut [u8]) -> Result<usize, ContentReadError> {
        const MAX_READ_BYTES: usize = 64 * 1024;
        if destination.len() > MAX_READ_BYTES {
            return Err(ContentReadError::RequestTooLarge);
        }
        let end = offset
            .checked_add(destination.len() as u64)
            .ok_or(ContentReadError::OutOfRange)?;
        if end > self.length {
            return Err(ContentReadError::OutOfRange);
        }
        self.file
            .seek(SeekFrom::Start(offset))
            .map_err(|_| ContentReadError::Io)?;
        self.file
            .read(destination)
            .map_err(|_| ContentReadError::Io)
    }
}

impl SourceReadHandle for LocalContentReader {
    fn len(&self) -> Result<u64, SourceAccessError> {
        Ok(self.length)
    }

    fn read_at(&mut self, offset: u64, destination: &mut [u8]) -> Result<usize, SourceAccessError> {
        const MAX_READ_BYTES: usize = 64 * 1024;
        if destination.len() > MAX_READ_BYTES {
            return Err(SourceAccessError::InvalidResponse);
        }
        let end = offset
            .checked_add(destination.len() as u64)
            .ok_or(SourceAccessError::InvalidResponse)?;
        if end > self.length {
            return Err(SourceAccessError::InvalidResponse);
        }
        self.file
            .seek(SeekFrom::Start(offset))
            .map_err(|_| SourceAccessError::IoFailure)?;
        self.file
            .read(destination)
            .map_err(|_| SourceAccessError::IoFailure)
    }

    fn max_read_size(&self) -> usize {
        64 * 1024
    }

    fn source_fingerprint(&self) -> Option<&str> {
        Some(LocalContentReader::source_fingerprint(self))
    }

    fn source_version_is_unchanged(&self) -> Result<bool, SourceAccessError> {
        LocalContentReader::source_version_is_unchanged(self)
    }
}

impl LocalFilesystemSourceAccess {
    /// Creates access bound to one configured root locator.
    pub fn new(locator: &RootLocator) -> Self {
        Self::new_with_registry(locator, None)
    }

    fn new_with_registry(
        locator: &RootLocator,
        mounted_volumes: Option<Arc<RwLock<MountedVolumeRegistry>>>,
    ) -> Self {
        Self {
            locator: locator.as_provider_value().to_owned(),
            resolved_root: Mutex::new(None),
            mounted_volumes,
            #[cfg(all(test, target_os = "macos"))]
            test_bookmark_resolver: None,
        }
    }

    #[cfg(all(test, target_os = "macos"))]
    fn new_with_test_bookmark_resolver(
        locator: &RootLocator,
        resolver: TestBookmarkResolver,
    ) -> Self {
        Self {
            locator: locator.as_provider_value().to_owned(),
            resolved_root: Mutex::new(None),
            mounted_volumes: None,
            test_bookmark_resolver: Some(resolver),
        }
    }
}

impl LibrarySourceAccess for LocalFilesystemSourceAccess {
    fn resolve_root(&self) -> Result<ResolvedRoot, SourceAccessError> {
        #[cfg(all(test, target_os = "macos"))]
        let resolved = match self.test_bookmark_resolver.as_deref() {
            Some(resolver) => resolve_locator_path_with_bookmark_resolver(
                &self.locator,
                self.mounted_volumes.as_ref(),
                resolver,
            )?,
            None => resolve_locator_path(&self.locator, self.mounted_volumes.as_ref())?,
        };
        #[cfg(not(all(test, target_os = "macos")))]
        let resolved = resolve_locator_path(&self.locator, self.mounted_volumes.as_ref())?;
        let token = resolved.path.to_string_lossy().into_owned();
        *self
            .resolved_root
            .lock()
            .map_err(|_| SourceAccessError::IoFailure)? = Some(resolved);
        Ok(ResolvedRoot::from_provider(token))
    }

    fn enumerate_root_direct_children(
        &self,
        root: &ResolvedRoot,
        is_cancelled: &dyn Fn() -> bool,
    ) -> Result<EnumerationResult, SourceAccessError> {
        if is_cancelled() {
            return Err(SourceAccessError::Cancelled);
        }
        let root_path = self.current_root(root)?;
        enumerate_scope(&root_path, &root_path, &[], is_cancelled)
    }

    fn enumerate_direct_children(
        &self,
        root: &ResolvedRoot,
        relative: &RelativeSourceLocator,
        is_cancelled: &dyn Fn() -> bool,
    ) -> Result<EnumerationResult, SourceAccessError> {
        if is_cancelled() {
            return Err(SourceAccessError::Cancelled);
        }
        let root_path = self.current_root(root)?;
        let relative_path = Path::new(relative.as_provider_value());
        let scope_path = root_path.join(relative_path);
        if !is_within_root(&root_path, &scope_path) {
            return Err(SourceAccessError::InvalidLocator);
        }
        let prefix: Vec<String> = relative_path
            .components()
            .filter_map(|component| match component {
                std::path::Component::Normal(value) => Some(value.to_string_lossy().into_owned()),
                _ => None,
            })
            .collect();
        enumerate_scope(&root_path, &scope_path, &prefix, is_cancelled)
    }

    fn open_entry_read(
        &self,
        root: &ResolvedRoot,
        relative: &RelativeSourceLocator,
    ) -> Result<Box<dyn SourceReadHandle>, SourceAccessError> {
        self.open_entry_reader(root, relative)
            .map(|reader| Box::new(reader) as Box<dyn SourceReadHandle>)
    }
}

impl LocalFilesystemSourceAccess {
    /// Opens one validated file entry for bounded range recognition.
    pub fn open_entry_reader(
        &self,
        root: &ResolvedRoot,
        relative: &RelativeSourceLocator,
    ) -> Result<LocalContentReader, SourceAccessError> {
        let root_path = self.current_root(root)?;
        let entry_path = resolve_entry_path(&root_path, relative)?;
        let metadata =
            std::fs::symlink_metadata(&entry_path).map_err(classify_entry_access_error)?;
        if !metadata.file_type().is_file() {
            return Err(SourceAccessError::UnsupportedOperation);
        }
        LocalContentReader::open(entry_path, &metadata)
    }

    fn current_root(&self, root: &ResolvedRoot) -> Result<std::path::PathBuf, SourceAccessError> {
        let resolved = self
            .resolved_root
            .lock()
            .map_err(|_| SourceAccessError::IoFailure)?;
        let resolved = resolved.as_ref().ok_or(SourceAccessError::InvalidLocator)?;
        let canonical = resolved.path.to_string_lossy();
        if canonical != root.as_provider_value() {
            return Err(SourceAccessError::InvalidLocator);
        }
        Ok(resolved.path.clone())
    }
}

fn enumerate_scope(
    root_path: &Path,
    scope_path: &Path,
    prefix: &[String],
    is_cancelled: &dyn Fn() -> bool,
) -> Result<EnumerationResult, SourceAccessError> {
    let entries = std::fs::read_dir(scope_path).map_err(classify_access_error)?;
    let mut observations = Vec::new();
    for entry in entries {
        if is_cancelled() {
            return Err(SourceAccessError::Cancelled);
        }
        let entry = match entry {
            Ok(entry) => entry,
            Err(_) => {
                return Ok(EnumerationResult::new(
                    observations,
                    EnumerationOutcome::Partial,
                ));
            }
        };
        let metadata = match std::fs::symlink_metadata(entry.path()) {
            Ok(metadata) => metadata,
            Err(_) => {
                return Ok(EnumerationResult::new(
                    observations,
                    EnumerationOutcome::Partial,
                ));
            }
        };
        let name = entry.file_name().to_string_lossy().into_owned();
        let mut segments: Vec<DiscoverySegment> =
            prefix.iter().cloned().map(DiscoverySegment::new).collect();
        segments.push(DiscoverySegment::new(name.clone()));
        let relative = if prefix.is_empty() {
            name.clone()
        } else {
            let mut value = prefix.join("/");
            value.push('/');
            value.push_str(&name);
            value
        };
        let observed_kind = observed_kind_of(&metadata);
        observations.push(SourceObservation::new(
            RelativeSourceLocator::from_provider(relative.clone()),
            SourceLocatorKey::from_provider(relative),
            DiscoveryPath::new(segments),
            observed_kind,
            name,
            native_identity(&metadata),
            Some(source_fingerprint(&metadata, observed_kind)),
            Some(metadata.len()),
            modified_at_ms(&metadata),
        ));
        // Link-like entries are retained but never traversed. Their targets
        // are not followed for boundary validation: an in-root link whose
        // target resolves outside the root must not fail the containing
        // scope. Actual traversal requests are still rejected by
        // `enumerate_direct_children`, which validates the resolved target
        // namespace before any enumeration begins.
        if !is_link_like(&metadata)
            && !is_within_root(root_path, &scope_path.join(entry.file_name()))
        {
            return Ok(EnumerationResult::new(
                observations,
                EnumerationOutcome::Failed,
            ));
        }
    }
    if is_cancelled() {
        return Err(SourceAccessError::Cancelled);
    }
    Ok(EnumerationResult::new(
        observations,
        EnumerationOutcome::Complete,
    ))
}

fn resolve_entry_path(
    root_path: &Path,
    relative: &RelativeSourceLocator,
) -> Result<PathBuf, SourceAccessError> {
    let relative_path = Path::new(relative.as_provider_value());
    let components = relative_components(relative_path).ok_or(SourceAccessError::InvalidLocator)?;
    if components.is_empty() {
        return Err(SourceAccessError::InvalidLocator);
    }

    let mut candidate = root_path.to_path_buf();
    for (index, component) in components.iter().enumerate() {
        candidate.push(component);
        let metadata =
            std::fs::symlink_metadata(&candidate).map_err(classify_entry_access_error)?;
        if is_link_like(&metadata) {
            return if index + 1 == components.len() {
                Err(SourceAccessError::UnsupportedOperation)
            } else {
                Err(SourceAccessError::InvalidLocator)
            };
        }
    }

    let canonical = std::fs::canonicalize(&candidate).map_err(classify_entry_access_error)?;
    if !canonical.starts_with(root_path) {
        return Err(SourceAccessError::InvalidLocator);
    }
    Ok(canonical)
}

fn classify_entry_access_error(error: std::io::Error) -> SourceAccessError {
    match error.kind() {
        std::io::ErrorKind::NotFound => SourceAccessError::EntryNotFound,
        std::io::ErrorKind::PermissionDenied => SourceAccessError::PermissionDenied,
        _ => SourceAccessError::IoFailure,
    }
}

fn is_within_root(root_path: &Path, candidate: &Path) -> bool {
    match std::fs::canonicalize(candidate) {
        Ok(canonical) => canonical.starts_with(root_path),
        Err(_) => false,
    }
}

fn observed_kind_of(metadata: &std::fs::Metadata) -> ObservedEntryKind {
    if is_link_like(metadata) {
        ObservedEntryKind::LinkLike
    } else if metadata.is_dir() {
        ObservedEntryKind::Directory
    } else if metadata.is_file() {
        ObservedEntryKind::File
    } else {
        ObservedEntryKind::Other
    }
}

fn is_link_like(metadata: &std::fs::Metadata) -> bool {
    if metadata.file_type().is_symlink() {
        return true;
    }
    #[cfg(windows)]
    {
        use std::os::windows::fs::MetadataExt;
        const FILE_ATTRIBUTE_REPARSE_POINT: u32 = 0x400;
        return metadata.file_attributes() & FILE_ATTRIBUTE_REPARSE_POINT != 0;
    }
    #[cfg(not(windows))]
    {
        false
    }
}

fn native_identity(metadata: &std::fs::Metadata) -> Option<String> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        Some(format!("unix:{}:{}", metadata.dev(), metadata.ino()))
    }
    #[cfg(not(unix))]
    {
        let _ = metadata;
        None
    }
}

fn source_fingerprint(metadata: &std::fs::Metadata, kind: ObservedEntryKind) -> String {
    let modified = modified_at_ms(metadata).unwrap_or(0);
    format!("v1:{}:{}:{}", kind.as_str(), metadata.len(), modified)
}

fn source_identity_evidence(
    file: &std::fs::File,
    metadata: &std::fs::Metadata,
    kind: ObservedEntryKind,
) -> Option<String> {
    #[cfg(windows)]
    {
        let _ = metadata;
        native_handle_identity(file, kind)
    }
    #[cfg(not(windows))]
    {
        let _ = file;
        Some(source_identity_evidence_from_metadata(metadata, kind))
    }
}

fn current_path_identity_evidence(
    path: &Path,
    metadata: &std::fs::Metadata,
) -> Result<Option<String>, SourceAccessError> {
    #[cfg(windows)]
    {
        let _ = metadata;
        let path_file = std::fs::File::open(path).map_err(classify_entry_access_error)?;
        let path_handle_metadata = path_file.metadata().map_err(classify_entry_access_error)?;
        if !path_handle_metadata.is_file() {
            return Ok(None);
        }
        Ok(source_identity_evidence(
            &path_file,
            &path_handle_metadata,
            ObservedEntryKind::File,
        ))
    }
    #[cfg(not(windows))]
    {
        let _ = path;
        Ok(Some(source_identity_evidence_from_metadata(
            metadata,
            ObservedEntryKind::File,
        )))
    }
}

#[cfg(windows)]
#[allow(unsafe_code)]
fn native_handle_identity(file: &std::fs::File, kind: ObservedEntryKind) -> Option<String> {
    use std::mem::zeroed;
    use std::os::windows::io::AsRawHandle;
    use windows_sys::Win32::Storage::FileSystem::{
        BY_HANDLE_FILE_INFORMATION, GetFileInformationByHandle,
    };

    let mut information = unsafe { zeroed::<BY_HANDLE_FILE_INFORMATION>() };
    let succeeded =
        unsafe { GetFileInformationByHandle(file.as_raw_handle() as _, &mut information) };
    if succeeded == 0 {
        return None;
    }
    let file_index =
        (u64::from(information.nFileIndexHigh) << 32) | u64::from(information.nFileIndexLow);
    Some(format!(
        "windows:{}:{}:{}",
        kind.as_str(),
        information.dwVolumeSerialNumber,
        file_index,
    ))
}

#[cfg(unix)]
fn source_identity_evidence_from_metadata(
    metadata: &std::fs::Metadata,
    kind: ObservedEntryKind,
) -> String {
    use std::os::unix::fs::MetadataExt;

    format!(
        "unix:{}:{}:{}",
        kind.as_str(),
        metadata.dev(),
        metadata.ino()
    )
}

#[cfg(not(any(unix, windows)))]
fn source_identity_evidence_from_metadata(
    _metadata: &std::fs::Metadata,
    kind: ObservedEntryKind,
) -> String {
    format!("native:{}", kind.as_str())
}

fn source_change_evidence(metadata: &std::fs::Metadata, kind: ObservedEntryKind) -> String {
    #[cfg(windows)]
    {
        use std::os::windows::fs::MetadataExt;

        format!(
            "windows:{}:{}:{}:{}",
            kind.as_str(),
            metadata.len(),
            metadata.creation_time(),
            metadata.last_write_time(),
        )
    }

    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;

        format!(
            "unix:{}:{}:{}:{}:{}:{}:{}",
            kind.as_str(),
            metadata.len(),
            metadata.dev(),
            metadata.ino(),
            modified_at_ns(metadata).unwrap_or(0),
            metadata.ctime(),
            metadata.ctime_nsec(),
        )
    }

    #[cfg(not(any(unix, windows)))]
    {
        format!(
            "native:{}:{}:{}",
            kind.as_str(),
            metadata.len(),
            modified_at_ns(metadata).unwrap_or(0),
        )
    }
}

#[cfg(windows)]
#[allow(unsafe_code)]
fn native_handle_change_time(file: &std::fs::File) -> Option<i64> {
    use std::mem::size_of;
    use std::os::windows::io::AsRawHandle;
    use windows_sys::Win32::Storage::FileSystem::{
        FILE_BASIC_INFO, FileBasicInfo, GetFileInformationByHandleEx,
    };

    let mut information = FILE_BASIC_INFO::default();
    let succeeded = unsafe {
        GetFileInformationByHandleEx(
            file.as_raw_handle() as _,
            FileBasicInfo,
            (&mut information as *mut FILE_BASIC_INFO).cast(),
            size_of::<FILE_BASIC_INFO>() as u32,
        )
    };
    (succeeded != 0).then_some(information.ChangeTime)
}

#[cfg(not(windows))]
fn native_handle_change_time(_file: &std::fs::File) -> Option<i64> {
    None
}

#[cfg(windows)]
#[allow(unsafe_code)]
fn native_handle_usn(file: &std::fs::File) -> Option<i64> {
    use std::mem::size_of;
    use std::os::windows::io::AsRawHandle;
    use windows_sys::Win32::System::IO::DeviceIoControl;
    use windows_sys::Win32::System::Ioctl::{FSCTL_READ_FILE_USN_DATA, READ_FILE_USN_DATA};

    let input = READ_FILE_USN_DATA {
        MinMajorVersion: 2,
        MaxMajorVersion: 3,
    };
    let mut output = [0_u8; 1024];
    let mut bytes_returned = 0_u32;
    let succeeded = unsafe {
        DeviceIoControl(
            file.as_raw_handle() as _,
            FSCTL_READ_FILE_USN_DATA,
            (&input as *const READ_FILE_USN_DATA).cast(),
            size_of::<READ_FILE_USN_DATA>() as u32,
            output.as_mut_ptr().cast(),
            output.len() as u32,
            &mut bytes_returned,
            std::ptr::null_mut(),
        )
    };
    if succeeded == 0 || bytes_returned < 8 {
        return None;
    }

    let returned = usize::try_from(bytes_returned).ok()?;
    let record_length = usize::try_from(u32::from_ne_bytes(
        output[..4].try_into().expect("USN record length"),
    ))
    .ok()?;
    if record_length > returned {
        return None;
    }

    match u16::from_ne_bytes(output[4..6].try_into().expect("USN major version")) {
        2 if record_length >= 32 => Some(i64::from_ne_bytes(
            output[24..32].try_into().expect("USN v2"),
        )),
        3 if record_length >= 48 => Some(i64::from_ne_bytes(
            output[40..48].try_into().expect("USN v3"),
        )),
        _ => None,
    }
}

#[cfg(not(windows))]
fn native_handle_usn(_file: &std::fs::File) -> Option<i64> {
    None
}

fn modified_at_ns(metadata: &std::fs::Metadata) -> Option<u128> {
    metadata
        .modified()
        .ok()
        .and_then(|time| time.duration_since(UNIX_EPOCH).ok())
        .map(|duration| duration.as_nanos())
}

#[cfg(test)]
mod tests {
    use std::fs;

    use super::LocalContentReader;

    #[test]
    fn source_validation_uses_the_open_handle_when_path_metadata_is_stale() {
        let directory = tempfile::tempdir().expect("tempdir");
        let path = directory.path().join("source.bin");
        let stale_path = directory.path().join("stale.bin");
        fs::write(&path, b"source").expect("source");
        fs::write(&stale_path, b"stale metadata").expect("stale metadata");
        let stale_metadata = fs::metadata(stale_path).expect("metadata");

        let reader = LocalContentReader::open(path, &stale_metadata).expect("reader");

        assert!(reader.source_version_is_unchanged().expect("version check"));
    }
}

#[cfg(all(test, target_os = "macos"))]
mod macos_comparison_tests {
    use super::*;
    use std::fs;
    use std::sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    };

    fn macos_locator(path: &Path, authorization: u8) -> RootLocator {
        RootLocator::from_provider(format!(
            "{MACOS_ROOT_LOCATOR_PREFIX}.{}.{}",
            hex_encode_bytes(path.to_string_lossy().as_bytes()),
            hex_encode_bytes(&[authorization]),
        ))
    }

    fn resolver_for(
        roots: Arc<BTreeMap<u8, PathBuf>>,
        starts: Arc<AtomicUsize>,
        stops: Arc<AtomicUsize>,
    ) -> impl Fn(&[u8]) -> Result<MacosSecurityScope, SourceAccessError> {
        move |authorization| {
            let [authorization] = authorization else {
                return Err(SourceAccessError::AuthorizationUnavailable);
            };
            let path = roots
                .get(authorization)
                .ok_or(SourceAccessError::AuthorizationUnavailable)?;
            starts.fetch_add(1, Ordering::Relaxed);
            Ok(MacosSecurityScope::test_started(
                NSURL::from_directory_path(path).expect("directory URL"),
                Arc::clone(&stops),
            ))
        }
    }

    fn assert_authorized_relationship(
        left: &Path,
        left_authorization: u8,
        right: &Path,
        right_authorization: u8,
        expected: RootRelationship,
    ) {
        let starts = Arc::new(AtomicUsize::new(0));
        let stops = Arc::new(AtomicUsize::new(0));
        let roots = Arc::new(BTreeMap::from([
            (left_authorization, left.to_path_buf()),
            (right_authorization, right.to_path_buf()),
        ]));
        let resolver = resolver_for(roots, Arc::clone(&starts), Arc::clone(&stops));

        assert_eq!(
            compare_roots_with_bookmark_resolver(
                &macos_locator(left, left_authorization),
                &macos_locator(right, right_authorization),
                &resolver,
            ),
            expected,
        );
        assert_eq!(starts.load(Ordering::Relaxed), 2);
        assert_eq!(stops.load(Ordering::Relaxed), 2);
    }

    #[test]
    fn authorized_relationships_hold_both_scopes_until_comparison_finishes() {
        let directory = tempfile::tempdir().expect("tempdir");
        let root = directory.path().join("Library");
        let child = root.join("Games");
        let sibling = directory.path().join("Other");
        fs::create_dir(&root).expect("root");
        fs::create_dir(&child).expect("child");
        fs::create_dir(&sibling).expect("sibling");

        assert_authorized_relationship(&root, 1, &root, 2, RootRelationship::Same);
        assert_authorized_relationship(&root, 1, &child, 2, RootRelationship::Ancestor);
        assert_authorized_relationship(&child, 1, &root, 2, RootRelationship::Descendant);
        assert_authorized_relationship(&root, 1, &sibling, 2, RootRelationship::Disjoint);
    }

    #[test]
    fn mixed_legacy_and_authorized_relationships_require_reachable_paths() {
        let directory = tempfile::tempdir().expect("tempdir");
        let root = directory.path().join("Library");
        let child = root.join("Games");
        fs::create_dir(&root).expect("root");
        fs::create_dir(&child).expect("child");

        let starts = Arc::new(AtomicUsize::new(0));
        let stops = Arc::new(AtomicUsize::new(0));
        let roots = Arc::new(BTreeMap::from([(1, root.clone())]));
        let resolver = resolver_for(roots, Arc::clone(&starts), Arc::clone(&stops));
        let legacy_root = RootLocator::from_provider(root.to_string_lossy().into_owned());
        let authorized_root = macos_locator(&root, 1);
        assert_eq!(
            compare_roots_with_bookmark_resolver(&authorized_root, &legacy_root, &resolver,),
            RootRelationship::Same,
        );
        assert_eq!(
            compare_roots_with_bookmark_resolver(&legacy_root, &authorized_root, &resolver,),
            RootRelationship::Same,
        );
        assert_eq!(starts.load(Ordering::Relaxed), 2);
        assert_eq!(stops.load(Ordering::Relaxed), 2);

        let starts = Arc::new(AtomicUsize::new(0));
        let stops = Arc::new(AtomicUsize::new(0));
        let roots = Arc::new(BTreeMap::from([(1, child.clone())]));
        let resolver = resolver_for(roots, Arc::clone(&starts), Arc::clone(&stops));
        let authorized_child = macos_locator(&child, 1);
        assert_eq!(
            compare_roots_with_bookmark_resolver(&authorized_child, &legacy_root, &resolver,),
            RootRelationship::Descendant,
        );
        assert_eq!(
            compare_roots_with_bookmark_resolver(&legacy_root, &authorized_child, &resolver,),
            RootRelationship::Ancestor,
        );
        assert_eq!(starts.load(Ordering::Relaxed), 2);
        assert_eq!(stops.load(Ordering::Relaxed), 2);

        let missing = RootLocator::from_provider(
            directory
                .path()
                .join("Missing")
                .to_string_lossy()
                .into_owned(),
        );
        let starts = Arc::new(AtomicUsize::new(0));
        let stops = Arc::new(AtomicUsize::new(0));
        let resolver = resolver_for(
            Arc::new(BTreeMap::from([(1, root)])),
            Arc::clone(&starts),
            Arc::clone(&stops),
        );
        assert_eq!(
            compare_roots_with_bookmark_resolver(&authorized_root, &missing, &resolver),
            RootRelationship::Unknown,
        );
        assert_eq!(starts.load(Ordering::Relaxed), 1);
        assert_eq!(stops.load(Ordering::Relaxed), 1);
    }

    #[test]
    fn legacy_operand_does_not_prevent_authorized_scope_resolution() {
        let directory = tempfile::tempdir().expect("tempdir");
        let authorized_path = directory.path().join("Library");
        let unavailable_legacy_path = directory.path().join("Unavailable");
        fs::create_dir(&authorized_path).expect("authorized root");

        let starts = Arc::new(AtomicUsize::new(0));
        let stops = Arc::new(AtomicUsize::new(0));
        let resolver = resolver_for(
            Arc::new(BTreeMap::from([(1, authorized_path.clone())])),
            Arc::clone(&starts),
            Arc::clone(&stops),
        );
        let legacy =
            RootLocator::from_provider(unavailable_legacy_path.to_string_lossy().into_owned());
        let authorized = macos_locator(&authorized_path, 1);

        assert_eq!(
            compare_roots_with_bookmark_resolver(&legacy, &authorized, &resolver),
            RootRelationship::Unknown,
        );
        assert_eq!(starts.load(Ordering::Relaxed), 1);
        assert_eq!(stops.load(Ordering::Relaxed), 1);
    }

    #[test]
    fn comparison_releases_successful_scope_when_the_second_resolution_fails() {
        let directory = tempfile::tempdir().expect("tempdir");
        let first = directory.path().join("First");
        let second = directory.path().join("Second");
        fs::create_dir(&first).expect("first");
        fs::create_dir(&second).expect("second");
        let starts = Arc::new(AtomicUsize::new(0));
        let stops = Arc::new(AtomicUsize::new(0));
        let resolver = {
            let starts = Arc::clone(&starts);
            let stops = Arc::clone(&stops);
            let first = first.clone();
            move |authorization: &[u8]| {
                if authorization == [1] {
                    starts.fetch_add(1, Ordering::Relaxed);
                    return Ok(MacosSecurityScope::test_started(
                        NSURL::from_directory_path(&first).expect("directory URL"),
                        Arc::clone(&stops),
                    ));
                }
                Err(SourceAccessError::AuthorizationUnavailable)
            }
        };

        assert_eq!(
            compare_roots_with_bookmark_resolver(
                &macos_locator(&first, 1),
                &macos_locator(&second, 2),
                &resolver,
            ),
            RootRelationship::Unknown,
        );
        assert_eq!(starts.load(Ordering::Relaxed), 1);
        assert_eq!(stops.load(Ordering::Relaxed), 1);
    }

    #[test]
    fn malformed_or_unavailable_authorization_never_starts_or_stops_a_scope() {
        let starts = Arc::new(AtomicUsize::new(0));
        let stops = Arc::new(AtomicUsize::new(0));
        let resolver = resolver_for(
            Arc::new(BTreeMap::new()),
            Arc::clone(&starts),
            Arc::clone(&stops),
        );
        let malformed =
            RootLocator::from_provider(format!("{MACOS_ROOT_LOCATOR_PREFIX}.not-hex.aa"));
        let unavailable = RootLocator::from_provider(format!(
            "{MACOS_ROOT_LOCATOR_PREFIX}.{}.01",
            hex_encode_bytes(b"/tmp/library")
        ));

        assert_eq!(
            compare_roots_with_bookmark_resolver(&malformed, &unavailable, &resolver),
            RootRelationship::Unknown,
        );
        assert_eq!(starts.load(Ordering::Relaxed), 0);
        assert_eq!(stops.load(Ordering::Relaxed), 0);
    }
}

fn modified_at_ms(metadata: &std::fs::Metadata) -> Option<i64> {
    metadata
        .modified()
        .ok()
        .and_then(|time| time.duration_since(UNIX_EPOCH).ok())
        .map(|duration| duration.as_millis().min(i64::MAX as u128) as i64)
}

fn classify_access_error(error: std::io::Error) -> SourceAccessError {
    match error.kind() {
        std::io::ErrorKind::NotFound => SourceAccessError::SourceUnavailable,
        std::io::ErrorKind::PermissionDenied => SourceAccessError::PermissionDenied,
        _ => SourceAccessError::IoFailure,
    }
}

/// The concrete local-filesystem provider adapter.
#[derive(Clone, Debug)]
pub struct LocalFilesystemProvider {
    mounted_volumes: Arc<RwLock<MountedVolumeRegistry>>,
}

impl Default for LocalFilesystemProvider {
    fn default() -> Self {
        Self {
            mounted_volumes: mounted_volume_registry(),
        }
    }
}

/// Returns the transient mount registry used by one provider instance.
///
/// Android runtime scan registration may construct a provider adapter after
/// the application-owned adapter has refreshed mounted-volume facts. Android
/// provider instances therefore share one process-local registry, while
/// desktop instances retain isolated registries for independent embeddings
/// and tests. The registry contains only current mount facts; durable root
/// identity remains the opaque provider-volume/relative locator.
fn mounted_volume_registry() -> Arc<RwLock<MountedVolumeRegistry>> {
    #[cfg(target_os = "android")]
    {
        static REGISTRY: OnceLock<Arc<RwLock<MountedVolumeRegistry>>> = OnceLock::new();
        return Arc::clone(
            REGISTRY.get_or_init(|| Arc::new(RwLock::new(MountedVolumeRegistry::default()))),
        );
    }

    #[cfg(not(target_os = "android"))]
    {
        Arc::new(RwLock::new(MountedVolumeRegistry::default()))
    }
}

impl LocalFilesystemProviderPort for LocalFilesystemProvider {
    fn validate(
        &self,
        selection: &LocalFilesystemRootSelection,
    ) -> Result<ValidatedLocalRoot, ProviderError> {
        match selection {
            LocalFilesystemRootSelection::Path {
                selected_folder_path,
            } => self.validate_path_selection(selected_folder_path),
            LocalFilesystemRootSelection::ProviderSelection { selection_identity } => {
                let coordinate = decode_coordinate(selection_identity, BROWSE_LOCATION_PREFIX)
                    .ok_or(ProviderError::InvalidSelection)?;
                let registry = self
                    .mounted_volumes
                    .read()
                    .map_err(|_| ProviderError::Internal)?;
                let (volume, _path) = resolve_browse_path(&registry, &coordinate)?;
                let display_name = browse_display_name(&volume, &coordinate.relative);
                Ok(ValidatedLocalRoot::new(
                    RootLocator::from_provider(encode_coordinate(ROOT_LOCATOR_PREFIX, &coordinate)),
                    display_name,
                    browse_location_presentation(&volume, &coordinate.relative),
                ))
            }
            LocalFilesystemRootSelection::MacosAuthorized {
                selected_folder_path,
                authorization,
            } => self.validate_macos_selection(selected_folder_path, authorization),
        }
    }

    fn compare_roots(&self, left: &RootLocator, right: &RootLocator) -> RootRelationship {
        #[cfg(target_os = "macos")]
        {
            compare_roots_with_bookmark_resolver(left, right, &resolve_macos_bookmark)
        }

        #[cfg(not(target_os = "macos"))]
        {
            let left_android = decode_coordinate(left.as_provider_value(), ROOT_LOCATOR_PREFIX);
            let right_android = decode_coordinate(right.as_provider_value(), ROOT_LOCATOR_PREFIX);
            match (left_android, right_android) {
                (Some(left), Some(right)) => {
                    if left.provider_volume_id != right.provider_volume_id {
                        return RootRelationship::Disjoint;
                    }
                    compare_relative_paths(&left.relative, &right.relative)
                }
                (Some(_), None) | (None, Some(_)) => RootRelationship::Unknown,
                (None, None) => {
                    let Ok(left_canonical) =
                        std::fs::canonicalize(Path::new(left.as_provider_value()))
                    else {
                        return RootRelationship::Unknown;
                    };
                    let Ok(right_canonical) =
                        std::fs::canonicalize(Path::new(right.as_provider_value()))
                    else {
                        return RootRelationship::Unknown;
                    };
                    if left_canonical == right_canonical {
                        RootRelationship::Same
                    } else if left_canonical.starts_with(&right_canonical) {
                        RootRelationship::Descendant
                    } else if right_canonical.starts_with(&left_canonical) {
                        RootRelationship::Ancestor
                    } else {
                        RootRelationship::Disjoint
                    }
                }
            }
        }
    }

    fn open_access(
        &self,
        locator: &RootLocator,
    ) -> Result<Box<dyn LibrarySourceAccess>, SourceAccessError> {
        Ok(Box::new(LocalFilesystemSourceAccess::new_with_registry(
            locator,
            Some(Arc::clone(&self.mounted_volumes)),
        )))
    }
}

impl LocalFilesystemProvider {
    #[cfg(not(target_os = "macos"))]
    fn validate_path_selection(&self, raw: &str) -> Result<ValidatedLocalRoot, ProviderError> {
        let path = Path::new(raw);
        if !path.is_absolute() {
            return Err(ProviderError::InvalidSelection);
        }

        let metadata = std::fs::symlink_metadata(path).map_err(classify_stat_error)?;
        if is_link_like(&metadata) {
            return Err(ProviderError::LinkLikeRoot);
        }
        if !metadata.is_dir() {
            return Err(ProviderError::NotADirectory);
        }
        std::fs::read_dir(path).map_err(classify_open_error)?;

        let display_name = path
            .file_name()
            .map(|name| name.to_string_lossy().into_owned())
            .unwrap_or_else(|| raw.to_owned());
        Ok(ValidatedLocalRoot::new(
            RootLocator::from_provider(raw.to_owned()),
            display_name,
            raw.to_owned(),
        ))
    }

    #[cfg(target_os = "macos")]
    fn validate_path_selection(&self, _raw: &str) -> Result<ValidatedLocalRoot, ProviderError> {
        Err(ProviderError::PermissionDenied)
    }

    #[cfg(target_os = "macos")]
    fn validate_macos_selection(
        &self,
        raw_path: &str,
        authorization: &[u8],
    ) -> Result<ValidatedLocalRoot, ProviderError> {
        let path = Path::new(raw_path);
        if !path.is_absolute() {
            return Err(ProviderError::InvalidSelection);
        }
        let scope =
            resolve_macos_bookmark(authorization).map_err(|_| ProviderError::PermissionDenied)?;
        let authorized_path = macos_url_path(&scope.url).ok_or(ProviderError::PermissionDenied)?;
        let authorized_metadata = std::fs::symlink_metadata(&authorized_path)
            .map_err(|_| ProviderError::PermissionDenied)?;
        if is_link_like(&authorized_metadata) || !authorized_metadata.is_dir() {
            return Err(ProviderError::PermissionDenied);
        }
        let authorized_canonical =
            std::fs::canonicalize(&authorized_path).map_err(|_| ProviderError::PermissionDenied)?;
        let selected_metadata = std::fs::symlink_metadata(path).map_err(classify_stat_error)?;
        if is_link_like(&selected_metadata) {
            return Err(ProviderError::LinkLikeRoot);
        }
        if !selected_metadata.is_dir() {
            return Err(ProviderError::NotADirectory);
        }
        let selected_canonical = std::fs::canonicalize(path).map_err(classify_stat_error)?;
        if selected_canonical != authorized_canonical {
            return Err(ProviderError::PermissionDenied);
        }
        std::fs::read_dir(&selected_canonical).map_err(classify_open_error)?;

        let canonical_path = selected_canonical.to_string_lossy().into_owned();
        let locator = encode_macos_root_locator(&canonical_path, authorization)
            .ok_or(ProviderError::PermissionDenied)?;
        let display_name = selected_canonical
            .file_name()
            .map(|name| name.to_string_lossy().into_owned())
            .unwrap_or_else(|| raw_path.to_owned());
        Ok(ValidatedLocalRoot::new(
            RootLocator::from_provider(locator),
            display_name,
            raw_path.to_owned(),
        ))
    }

    #[cfg(not(target_os = "macos"))]
    fn validate_macos_selection(
        &self,
        _raw_path: &str,
        _authorization: &[u8],
    ) -> Result<ValidatedLocalRoot, ProviderError> {
        Err(ProviderError::InvalidSelection)
    }
}

impl LocalFilesystemBrowseProvider for LocalFilesystemProvider {
    fn replace_mounted_volumes(
        &self,
        volumes: &[MountedLocalFilesystemVolume],
    ) -> Result<(), ProviderError> {
        let replacement = validate_snapshot(volumes)?;
        let mut registry = self
            .mounted_volumes
            .write()
            .map_err(|_| ProviderError::Internal)?;
        registry.volumes = replacement;
        Ok(())
    }

    fn list_browse_roots(&self) -> Result<Vec<LocalFilesystemBrowseRoot>, ProviderError> {
        let registry = self
            .mounted_volumes
            .read()
            .map_err(|_| ProviderError::Internal)?;
        let mut volumes: Vec<&MountedVolume> = registry.volumes.values().collect();
        volumes.sort_by(|left, right| {
            right
                .is_primary
                .cmp(&left.is_primary)
                .then_with(|| left.display_name.cmp(&right.display_name))
                .then_with(|| left.provider_volume_id.cmp(&right.provider_volume_id))
        });
        let mut roots = Vec::new();
        for volume in volumes {
            let coordinate = BrowseCoordinate {
                provider_volume_id: volume.provider_volume_id.clone(),
                relative: PathBuf::new(),
            };
            if resolve_browse_path(&registry, &coordinate).is_err() {
                continue;
            }
            roots.push(LocalFilesystemBrowseRoot::new(
                LocalFilesystemBrowseLocation::from_provider(encode_coordinate(
                    BROWSE_LOCATION_PREFIX,
                    &coordinate,
                )),
                volume.display_name.clone(),
                volume.display_name.clone(),
            ));
        }
        Ok(roots)
    }

    fn list_browse_directories(
        &self,
        location: &LocalFilesystemBrowseLocation,
        cursor: Option<&LocalFilesystemBrowseCursor>,
        page_size: u32,
    ) -> Result<LocalFilesystemBrowsePage, ProviderError> {
        if !(1..=MAX_LOCAL_FILESYSTEM_BROWSE_PAGE_SIZE).contains(&page_size) {
            return Err(ProviderError::InvalidBrowseRequest);
        }
        let coordinate = decode_coordinate(location.as_provider_value(), BROWSE_LOCATION_PREFIX)
            .ok_or(ProviderError::InvalidBrowseRequest)?;
        let cursor_name = cursor
            .map(|value| decode_cursor(value.as_provider_value()))
            .transpose()?
            .map(|(cursor_location, name)| {
                if cursor_location != coordinate {
                    Err(ProviderError::InvalidBrowseRequest)
                } else {
                    Ok(name)
                }
            })
            .transpose()?;
        let registry = self
            .mounted_volumes
            .read()
            .map_err(|_| ProviderError::Internal)?;
        let (volume, path) = resolve_browse_path(&registry, &coordinate)?;
        let mut names = Vec::new();
        for entry in std::fs::read_dir(path).map_err(classify_browse_error)? {
            let entry = entry.map_err(classify_browse_error)?;
            let name = entry.file_name().to_string_lossy().into_owned();
            if cursor_name
                .as_deref()
                .is_some_and(|cursor| name.as_str() <= cursor)
            {
                continue;
            }
            let metadata =
                std::fs::symlink_metadata(entry.path()).map_err(classify_browse_error)?;
            if is_link_like(&metadata) || !metadata.is_dir() {
                continue;
            }
            names.push(name);
            names.sort();
            if names.len() > page_size as usize + 1 {
                names.pop();
            }
        }
        let has_more = names.len() > page_size as usize;
        names.truncate(page_size as usize);
        let directories = names
            .iter()
            .map(|name| {
                let mut relative = coordinate.relative.clone();
                relative.push(name);
                let child = BrowseCoordinate {
                    provider_volume_id: coordinate.provider_volume_id.clone(),
                    relative,
                };
                LocalFilesystemBrowseDirectory::new(
                    LocalFilesystemBrowseLocation::from_provider(encode_coordinate(
                        BROWSE_LOCATION_PREFIX,
                        &child,
                    )),
                    name.clone(),
                )
            })
            .collect::<Vec<_>>();
        let next_cursor = has_more.then(|| {
            LocalFilesystemBrowseCursor::from_provider(encode_cursor(
                &coordinate,
                names.last().expect("page has a row"),
            ))
        });
        Ok(LocalFilesystemBrowsePage::new(
            LocalFilesystemBrowseRoot::new(
                location.clone(),
                browse_display_name(&volume, &coordinate.relative),
                browse_location_presentation(&volume, &coordinate.relative),
            ),
            build_breadcrumbs(&volume, &coordinate),
            directories,
            next_cursor,
        ))
    }
}

fn validate_snapshot(
    volumes: &[MountedLocalFilesystemVolume],
) -> Result<BTreeMap<String, MountedVolume>, ProviderError> {
    if volumes.is_empty() || volumes.len() > MAX_MOUNTED_LOCAL_FILESYSTEM_VOLUMES {
        return Err(ProviderError::InvalidBrowseRequest);
    }
    let mut primary_count = 0;
    let mut registry = BTreeMap::new();
    let mut canonical_paths = BTreeMap::<PathBuf, ()>::new();
    for volume in volumes {
        if volume.provider_volume_id().is_empty()
            || volume.display_name().trim().is_empty()
            || !Path::new(volume.mount_path()).is_absolute()
            || registry.contains_key(volume.provider_volume_id())
            || (volume.is_primary() != (volume.provider_volume_id() == PRIMARY_VOLUME_ID))
        {
            return Err(ProviderError::InvalidBrowseRequest);
        }
        if volume.is_primary() {
            primary_count += 1;
        }
        let mount_path = PathBuf::from(volume.mount_path());
        let metadata = std::fs::symlink_metadata(&mount_path)
            .map_err(|_| ProviderError::InvalidBrowseRequest)?;
        if is_link_like(&metadata) || !metadata.is_dir() {
            return Err(ProviderError::InvalidBrowseRequest);
        }
        std::fs::read_dir(&mount_path).map_err(|_| ProviderError::InvalidBrowseRequest)?;
        let canonical_mount_path =
            std::fs::canonicalize(&mount_path).map_err(|_| ProviderError::InvalidBrowseRequest)?;
        if canonical_paths
            .insert(canonical_mount_path.clone(), ())
            .is_some()
        {
            return Err(ProviderError::InvalidBrowseRequest);
        }
        registry.insert(
            volume.provider_volume_id().to_owned(),
            MountedVolume {
                provider_volume_id: volume.provider_volume_id().to_owned(),
                canonical_mount_path,
                display_name: volume.display_name().to_owned(),
                is_primary: volume.is_primary(),
            },
        );
    }
    if primary_count != 1 {
        return Err(ProviderError::InvalidBrowseRequest);
    }
    Ok(registry)
}

fn resolve_browse_path(
    registry: &MountedVolumeRegistry,
    coordinate: &BrowseCoordinate,
) -> Result<(MountedVolume, PathBuf), ProviderError> {
    let volume = registry
        .volumes
        .get(&coordinate.provider_volume_id)
        .cloned()
        .ok_or(ProviderError::Unavailable)?;
    let path = resolve_volume_relative_path(&volume, &coordinate.relative)
        .map_err(map_browse_access_error)?;
    Ok((volume, path))
}

fn resolve_volume_relative_path(
    volume: &MountedVolume,
    relative: &Path,
) -> Result<PathBuf, SourceAccessError> {
    let components = relative_components(relative).ok_or(SourceAccessError::InvalidLocator)?;
    let mut candidate = volume.canonical_mount_path.clone();
    for component in components {
        candidate.push(&component);
        let metadata = std::fs::symlink_metadata(&candidate).map_err(classify_access_error)?;
        if is_link_like(&metadata) {
            return Err(SourceAccessError::InvalidLocator);
        }
    }
    let canonical = std::fs::canonicalize(&candidate).map_err(classify_access_error)?;
    if !canonical.starts_with(&volume.canonical_mount_path) {
        return Err(SourceAccessError::InvalidLocator);
    }
    let metadata = std::fs::symlink_metadata(&canonical).map_err(classify_access_error)?;
    if is_link_like(&metadata) || !metadata.is_dir() {
        return Err(SourceAccessError::InvalidLocator);
    }
    std::fs::read_dir(&canonical).map_err(classify_access_error)?;
    Ok(canonical)
}

#[cfg(target_os = "macos")]
fn resolve_locator_path(
    locator: &str,
    mounted_volumes: Option<&Arc<RwLock<MountedVolumeRegistry>>>,
) -> Result<ResolvedRootState, SourceAccessError> {
    resolve_locator_path_with_bookmark_resolver(locator, mounted_volumes, &resolve_macos_bookmark)
}

#[cfg(target_os = "macos")]
fn resolve_locator_path_with_bookmark_resolver(
    locator: &str,
    mounted_volumes: Option<&Arc<RwLock<MountedVolumeRegistry>>>,
    resolve_bookmark: &dyn Fn(&[u8]) -> Result<MacosSecurityScope, SourceAccessError>,
) -> Result<ResolvedRootState, SourceAccessError> {
    if locator.starts_with(ROOT_LOCATOR_PREFIX) {
        let coordinate = decode_coordinate(locator, ROOT_LOCATOR_PREFIX)
            .ok_or(SourceAccessError::InvalidLocator)?;
        let registry = mounted_volumes.ok_or(SourceAccessError::SourceUnavailable)?;
        let registry = registry.read().map_err(|_| SourceAccessError::IoFailure)?;
        let volume = registry
            .volumes
            .get(&coordinate.provider_volume_id)
            .ok_or(SourceAccessError::SourceUnavailable)?;
        return resolve_volume_relative_path(volume, &coordinate.relative).map(resolved_root_state);
    }

    let macos_locator =
        decode_macos_root_locator(locator).ok_or(SourceAccessError::AuthorizationUnavailable)?;
    let scope = resolve_bookmark(&macos_locator.authorization)?;
    let authorized_path =
        macos_url_path(&scope.url).ok_or(SourceAccessError::AuthorizationUnavailable)?;
    let submitted_path = Path::new(&macos_locator.path);
    let submitted_metadata = std::fs::symlink_metadata(submitted_path)
        .map_err(|_| SourceAccessError::AuthorizationUnavailable)?;
    if is_link_like(&submitted_metadata) || !submitted_metadata.is_dir() {
        return Err(SourceAccessError::AuthorizationUnavailable);
    }
    let submitted_canonical = std::fs::canonicalize(submitted_path)
        .map_err(|_| SourceAccessError::AuthorizationUnavailable)?;
    let authorized_metadata = std::fs::symlink_metadata(&authorized_path)
        .map_err(|_| SourceAccessError::AuthorizationUnavailable)?;
    if is_link_like(&authorized_metadata) || !authorized_metadata.is_dir() {
        return Err(SourceAccessError::AuthorizationUnavailable);
    }
    let authorized_canonical = std::fs::canonicalize(&authorized_path)
        .map_err(|_| SourceAccessError::AuthorizationUnavailable)?;
    if submitted_canonical != authorized_canonical {
        return Err(SourceAccessError::AuthorizationUnavailable);
    }
    std::fs::read_dir(&submitted_canonical)
        .map_err(|_| SourceAccessError::AuthorizationUnavailable)?;
    Ok(ResolvedRootState {
        path: submitted_canonical,
        _security_scope: Some(scope),
    })
}

#[cfg(not(target_os = "macos"))]
fn resolve_locator_path(
    locator: &str,
    mounted_volumes: Option<&Arc<RwLock<MountedVolumeRegistry>>>,
) -> Result<ResolvedRootState, SourceAccessError> {
    if locator.starts_with(ROOT_LOCATOR_PREFIX) {
        let coordinate = decode_coordinate(locator, ROOT_LOCATOR_PREFIX)
            .ok_or(SourceAccessError::InvalidLocator)?;
        let registry = mounted_volumes.ok_or(SourceAccessError::SourceUnavailable)?;
        let registry = registry.read().map_err(|_| SourceAccessError::IoFailure)?;
        let volume = registry
            .volumes
            .get(&coordinate.provider_volume_id)
            .ok_or(SourceAccessError::SourceUnavailable)?;
        return resolve_volume_relative_path(volume, &coordinate.relative).map(resolved_root_state);
    }
    let path = Path::new(locator);
    let original_metadata = std::fs::symlink_metadata(path).map_err(classify_access_error)?;
    if is_link_like(&original_metadata) {
        return Err(SourceAccessError::InvalidLocator);
    }
    let canonical = std::fs::canonicalize(path).map_err(classify_access_error)?;
    let metadata = std::fs::symlink_metadata(&canonical).map_err(classify_access_error)?;
    if !metadata.is_dir() {
        return Err(SourceAccessError::InvalidLocator);
    }
    std::fs::read_dir(&canonical).map_err(classify_access_error)?;
    Ok(resolved_root_state(canonical))
}

fn resolved_root_state(path: PathBuf) -> ResolvedRootState {
    ResolvedRootState {
        path,
        #[cfg(target_os = "macos")]
        _security_scope: None,
    }
}

#[cfg(target_os = "macos")]
struct MacosRootLocator {
    path: String,
    authorization: Vec<u8>,
}

#[cfg(target_os = "macos")]
fn encode_macos_root_locator(path: &str, authorization: &[u8]) -> Option<String> {
    if path.is_empty()
        || path.len() > MAX_MACOS_ROOT_PATH_BYTES
        || authorization.is_empty()
        || authorization.len() > MAX_MACOS_BOOKMARK_BYTES
    {
        return None;
    }
    Some(format!(
        "{MACOS_ROOT_LOCATOR_PREFIX}.{}.{}",
        hex_encode_bytes(path.as_bytes()),
        hex_encode_bytes(authorization),
    ))
}

#[cfg(target_os = "macos")]
fn decode_macos_root_locator(value: &str) -> Option<MacosRootLocator> {
    let rest = value
        .strip_prefix(MACOS_ROOT_LOCATOR_PREFIX)?
        .strip_prefix('.')?;
    let (path_hex, authorization_hex) = rest.split_once('.')?;
    if authorization_hex.contains('.') {
        return None;
    }
    if path_hex.is_empty()
        || authorization_hex.is_empty()
        || !path_hex.len().is_multiple_of(2)
        || !authorization_hex.len().is_multiple_of(2)
        || path_hex.len() > MAX_MACOS_ROOT_PATH_BYTES.saturating_mul(2)
        || authorization_hex.len() > MAX_MACOS_BOOKMARK_BYTES.saturating_mul(2)
    {
        return None;
    }
    let path = String::from_utf8(hex_decode_bytes(path_hex)?).ok()?;
    let authorization = hex_decode_bytes(authorization_hex)?;
    if !Path::new(&path).is_absolute()
        || path.len() > MAX_MACOS_ROOT_PATH_BYTES
        || authorization.is_empty()
        || authorization.len() > MAX_MACOS_BOOKMARK_BYTES
    {
        return None;
    }
    Some(MacosRootLocator {
        path,
        authorization,
    })
}

#[cfg(target_os = "macos")]
#[allow(unsafe_code)]
fn resolve_macos_bookmark(authorization: &[u8]) -> Result<MacosSecurityScope, SourceAccessError> {
    if authorization.is_empty() || authorization.len() > MAX_MACOS_BOOKMARK_BYTES {
        return Err(SourceAccessError::AuthorizationUnavailable);
    }
    let bookmark = NSData::with_bytes(authorization);
    let mut is_stale = Bool::NO;
    // SAFETY: The generated Foundation call borrows `bookmark` for the
    // duration of the call, writes only to the valid `is_stale` out-parameter,
    // and returns an owned `Retained<NSURL>` on success.
    let url = unsafe {
        NSURL::URLByResolvingBookmarkData_options_relativeToURL_bookmarkDataIsStale_error(
            &bookmark,
            NSURLBookmarkResolutionOptions::WithoutUI
                | NSURLBookmarkResolutionOptions::WithSecurityScope
                | NSURLBookmarkResolutionOptions::WithoutImplicitStartAccessing,
            None,
            &mut is_stale,
        )
    }
    .map_err(|_| SourceAccessError::AuthorizationUnavailable)?;
    if is_stale.as_bool() || !url.isFileURL() {
        return Err(SourceAccessError::AuthorizationUnavailable);
    }
    // SAFETY: `url` is the retained file URL returned by the successful
    // bookmark resolution above. A `true` result transfers the matching stop
    // obligation to the guard returned from this function.
    let started = unsafe { url.startAccessingSecurityScopedResource() };
    if !started {
        return Err(SourceAccessError::AuthorizationUnavailable);
    }
    Ok(MacosSecurityScope {
        url,
        #[cfg(test)]
        test_stop_count: None,
    })
}

#[cfg(target_os = "macos")]
fn macos_url_path(url: &NSURL) -> Option<PathBuf> {
    url.path().map(|path| PathBuf::from(path.to_string()))
}

#[cfg(target_os = "macos")]
struct MacosComparisonRoot {
    path: PathBuf,
    _security_scope: Option<MacosSecurityScope>,
}

#[cfg(target_os = "macos")]
enum MacosComparisonLocator {
    Android(BrowseCoordinate),
    Authorized(MacosRootLocator),
    Legacy(PathBuf),
    Invalid,
}

#[cfg(target_os = "macos")]
fn compare_roots_with_bookmark_resolver(
    left: &RootLocator,
    right: &RootLocator,
    resolve_bookmark: &dyn Fn(&[u8]) -> Result<MacosSecurityScope, SourceAccessError>,
) -> RootRelationship {
    let left_locator = classify_macos_comparison_locator(left);
    let right_locator = classify_macos_comparison_locator(right);
    match (&left_locator, &right_locator) {
        (MacosComparisonLocator::Android(left), MacosComparisonLocator::Android(right)) => {
            if left.provider_volume_id != right.provider_volume_id {
                return RootRelationship::Disjoint;
            }
            compare_relative_paths(&left.relative, &right.relative)
        }
        (MacosComparisonLocator::Android(_), _)
        | (_, MacosComparisonLocator::Android(_))
        | (MacosComparisonLocator::Invalid, _)
        | (_, MacosComparisonLocator::Invalid) => RootRelationship::Unknown,
        _ => {
            let left_scope = match resolve_macos_comparison_scope(&left_locator, resolve_bookmark) {
                Ok(scope) => scope,
                Err(_) => return RootRelationship::Unknown,
            };
            let right_scope = match resolve_macos_comparison_scope(&right_locator, resolve_bookmark)
            {
                Ok(scope) => scope,
                Err(_) => return RootRelationship::Unknown,
            };
            let Some(left_root) = comparison_root(left_locator, left_scope) else {
                return RootRelationship::Unknown;
            };
            let Some(right_root) = comparison_root(right_locator, right_scope) else {
                return RootRelationship::Unknown;
            };
            compare_canonical_paths(&left_root.path, &right_root.path)
        }
    }
}

#[cfg(target_os = "macos")]
fn classify_macos_comparison_locator(locator: &RootLocator) -> MacosComparisonLocator {
    let raw = locator.as_provider_value();
    if let Some(coordinate) = decode_coordinate(raw, ROOT_LOCATOR_PREFIX) {
        return MacosComparisonLocator::Android(coordinate);
    }
    if raw.starts_with(ROOT_LOCATOR_PREFIX) || raw.starts_with(MACOS_ROOT_LOCATOR_PREFIX) {
        return decode_macos_root_locator(raw)
            .map(MacosComparisonLocator::Authorized)
            .unwrap_or(MacosComparisonLocator::Invalid);
    }
    MacosComparisonLocator::Legacy(PathBuf::from(raw))
}

#[cfg(target_os = "macos")]
fn resolve_macos_comparison_scope(
    locator: &MacosComparisonLocator,
    resolve_bookmark: &dyn Fn(&[u8]) -> Result<MacosSecurityScope, SourceAccessError>,
) -> Result<Option<MacosSecurityScope>, SourceAccessError> {
    match locator {
        MacosComparisonLocator::Authorized(macos_locator) => {
            resolve_bookmark(&macos_locator.authorization).map(Some)
        }
        MacosComparisonLocator::Android(_)
        | MacosComparisonLocator::Legacy(_)
        | MacosComparisonLocator::Invalid => Ok(None),
    }
}

#[cfg(target_os = "macos")]
fn comparison_root(
    locator: MacosComparisonLocator,
    security_scope: Option<MacosSecurityScope>,
) -> Option<MacosComparisonRoot> {
    match locator {
        MacosComparisonLocator::Authorized(macos_locator) => {
            let scope = security_scope?;
            let authorized_path = macos_url_path(&scope.url)?;
            let submitted_path = Path::new(&macos_locator.path);
            let submitted_metadata = std::fs::symlink_metadata(submitted_path).ok()?;
            let authorized_metadata = std::fs::symlink_metadata(&authorized_path).ok()?;
            if is_link_like(&submitted_metadata)
                || !submitted_metadata.is_dir()
                || is_link_like(&authorized_metadata)
                || !authorized_metadata.is_dir()
            {
                return None;
            }
            let submitted_canonical = std::fs::canonicalize(submitted_path).ok()?;
            let authorized_canonical = std::fs::canonicalize(authorized_path).ok()?;
            if submitted_canonical != authorized_canonical {
                return None;
            }
            std::fs::read_dir(&submitted_canonical).ok()?;
            Some(MacosComparisonRoot {
                path: submitted_canonical,
                _security_scope: Some(scope),
            })
        }
        MacosComparisonLocator::Legacy(path) => {
            let metadata = std::fs::symlink_metadata(&path).ok()?;
            if is_link_like(&metadata) || !metadata.is_dir() {
                return None;
            }
            let canonical = std::fs::canonicalize(&path).ok()?;
            let canonical_metadata = std::fs::symlink_metadata(&canonical).ok()?;
            if is_link_like(&canonical_metadata) || !canonical_metadata.is_dir() {
                return None;
            }
            std::fs::read_dir(&canonical).ok()?;
            Some(MacosComparisonRoot {
                path: canonical,
                _security_scope: None,
            })
        }
        MacosComparisonLocator::Android(_) | MacosComparisonLocator::Invalid => None,
    }
}

#[cfg(target_os = "macos")]
fn compare_canonical_paths(left: &Path, right: &Path) -> RootRelationship {
    if left == right {
        RootRelationship::Same
    } else if left.starts_with(right) {
        RootRelationship::Descendant
    } else if right.starts_with(left) {
        RootRelationship::Ancestor
    } else {
        RootRelationship::Disjoint
    }
}

fn relative_components(relative: &Path) -> Option<Vec<String>> {
    relative
        .components()
        .map(|component| match component {
            Component::Normal(value) => Some(value.to_string_lossy().into_owned()),
            Component::CurDir => None,
            Component::ParentDir | Component::RootDir | Component::Prefix(_) => None,
        })
        .collect()
}

fn browse_display_name(volume: &MountedVolume, relative: &Path) -> String {
    relative
        .file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .unwrap_or_else(|| volume.display_name.clone())
}

fn browse_location_presentation(volume: &MountedVolume, relative: &Path) -> String {
    let mut value = volume.display_name.clone();
    for component in relative_components(relative).unwrap_or_default() {
        value.push_str(" / ");
        value.push_str(&component);
    }
    value
}

fn build_breadcrumbs(
    volume: &MountedVolume,
    coordinate: &BrowseCoordinate,
) -> Vec<LocalFilesystemBrowseBreadcrumb> {
    let mut breadcrumbs = Vec::new();
    let mut relative = PathBuf::new();
    breadcrumbs.push(LocalFilesystemBrowseBreadcrumb::new(
        LocalFilesystemBrowseLocation::from_provider(encode_coordinate(
            BROWSE_LOCATION_PREFIX,
            &BrowseCoordinate {
                provider_volume_id: coordinate.provider_volume_id.clone(),
                relative: relative.clone(),
            },
        )),
        volume.display_name.clone(),
    ));
    for component in relative_components(&coordinate.relative).unwrap_or_default() {
        relative.push(&component);
        breadcrumbs.push(LocalFilesystemBrowseBreadcrumb::new(
            LocalFilesystemBrowseLocation::from_provider(encode_coordinate(
                BROWSE_LOCATION_PREFIX,
                &BrowseCoordinate {
                    provider_volume_id: coordinate.provider_volume_id.clone(),
                    relative: relative.clone(),
                },
            )),
            component,
        ));
    }
    breadcrumbs
}

fn compare_relative_paths(left: &Path, right: &Path) -> RootRelationship {
    let Some(left) = relative_components(left) else {
        return RootRelationship::Unknown;
    };
    let Some(right) = relative_components(right) else {
        return RootRelationship::Unknown;
    };
    if left == right {
        return RootRelationship::Same;
    }
    if left.len() < right.len() && right.starts_with(&left) {
        return RootRelationship::Ancestor;
    }
    if right.len() < left.len() && left.starts_with(&right) {
        return RootRelationship::Descendant;
    }
    RootRelationship::Disjoint
}

fn encode_coordinate(prefix: &str, coordinate: &BrowseCoordinate) -> String {
    format!(
        "{prefix}:{}:{}",
        hex_encode(&coordinate.provider_volume_id),
        hex_encode(&relative_string(&coordinate.relative)),
    )
}

fn decode_coordinate(value: &str, prefix: &str) -> Option<BrowseCoordinate> {
    let rest = value.strip_prefix(prefix)?.strip_prefix(':')?;
    let (volume, relative) = rest.split_once(':')?;
    let relative = hex_decode(relative)?;
    let relative = if relative.is_empty() {
        PathBuf::new()
    } else {
        PathBuf::from(relative)
    };
    let coordinate = BrowseCoordinate {
        provider_volume_id: hex_decode(volume)?,
        relative,
    };
    relative_components(&coordinate.relative)?;
    (!coordinate.provider_volume_id.is_empty()).then_some(coordinate)
}

fn encode_cursor(coordinate: &BrowseCoordinate, last_name: &str) -> String {
    format!(
        "{BROWSE_CURSOR_PREFIX}:{}:{}",
        hex_encode(&encode_coordinate(BROWSE_LOCATION_PREFIX, coordinate)),
        hex_encode(last_name),
    )
}

fn decode_cursor(value: &str) -> Result<(BrowseCoordinate, String), ProviderError> {
    let rest = value
        .strip_prefix(BROWSE_CURSOR_PREFIX)
        .and_then(|value| value.strip_prefix(':'))
        .ok_or(ProviderError::InvalidBrowseRequest)?;
    let (location, name) = rest
        .split_once(':')
        .ok_or(ProviderError::InvalidBrowseRequest)?;
    let location = hex_decode(location).ok_or(ProviderError::InvalidBrowseRequest)?;
    let name = hex_decode(name).ok_or(ProviderError::InvalidBrowseRequest)?;
    let coordinate = decode_coordinate(&location, BROWSE_LOCATION_PREFIX)
        .ok_or(ProviderError::InvalidBrowseRequest)?;
    if name.is_empty() || name.contains('/') {
        return Err(ProviderError::InvalidBrowseRequest);
    }
    Ok((coordinate, name))
}

fn relative_string(relative: &Path) -> String {
    relative_components(relative).unwrap_or_default().join("/")
}

fn hex_encode(value: &str) -> String {
    hex_encode_bytes(value.as_bytes())
}

fn hex_encode_bytes(value: &[u8]) -> String {
    value.iter().map(|byte| format!("{byte:02x}")).collect()
}

fn hex_decode(value: &str) -> Option<String> {
    String::from_utf8(hex_decode_bytes(value)?).ok()
}

fn hex_decode_bytes(value: &str) -> Option<Vec<u8>> {
    let bytes = value.as_bytes();
    if !bytes.len().is_multiple_of(2) {
        return None;
    }
    bytes
        .chunks_exact(2)
        .map(|pair| {
            let high = hex_digit(pair[0])?;
            let low = hex_digit(pair[1])?;
            Some((high << 4) | low)
        })
        .collect()
}

fn hex_digit(value: u8) -> Option<u8> {
    match value {
        b'0'..=b'9' => Some(value - b'0'),
        b'a'..=b'f' => Some(value - b'a' + 10),
        b'A'..=b'F' => Some(value - b'A' + 10),
        _ => None,
    }
}

fn map_browse_access_error(error: SourceAccessError) -> ProviderError {
    match error {
        SourceAccessError::SourceUnavailable => ProviderError::Unavailable,
        SourceAccessError::PermissionDenied => ProviderError::PermissionDenied,
        SourceAccessError::InvalidLocator => ProviderError::InvalidBrowseRequest,
        _ => ProviderError::Internal,
    }
}

fn classify_browse_error(error: std::io::Error) -> ProviderError {
    match error.kind() {
        std::io::ErrorKind::NotFound => ProviderError::Unavailable,
        std::io::ErrorKind::PermissionDenied => ProviderError::PermissionDenied,
        _ => ProviderError::Internal,
    }
}

#[cfg(all(target_os = "macos", any(test, feature = "test-support")))]
fn create_macos_security_scoped_bookmark(path: &Path) -> Vec<u8> {
    let url = NSURL::from_directory_path(path).expect("directory URL");
    url.bookmarkDataWithOptions_includingResourceValuesForKeys_relativeToURL_error(
        NSURLBookmarkCreationOptions::WithSecurityScope,
        None,
        None,
    )
    .expect("security-scoped bookmark")
    .to_vec()
}

/// Creates a real security-scoped bookmark for macOS integration fixtures.
///
/// This helper is available only to the `test-support` feature and is not part
/// of the production provider surface. It gives runtime tests the same durable
/// authorization shape that the native folder picker gives the application.
#[cfg(all(feature = "test-support", target_os = "macos"))]
pub fn macos_test_bookmark_for_directory(path: &Path) -> Vec<u8> {
    create_macos_security_scoped_bookmark(path)
}

fn classify_stat_error(error: std::io::Error) -> ProviderError {
    match error.kind() {
        std::io::ErrorKind::NotFound => ProviderError::InvalidSelection,
        std::io::ErrorKind::PermissionDenied => ProviderError::PermissionDenied,
        _ => ProviderError::Internal,
    }
}

fn classify_open_error(error: std::io::Error) -> ProviderError {
    match error.kind() {
        std::io::ErrorKind::NotFound => ProviderError::Unavailable,
        std::io::ErrorKind::PermissionDenied => ProviderError::PermissionDenied,
        _ => ProviderError::Internal,
    }
}

#[cfg(all(test, target_os = "macos"))]
mod macos_tests {
    use super::*;
    use std::fs;
    use std::sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    };

    fn bookmark_for_directory(path: &Path) -> Vec<u8> {
        super::create_macos_security_scoped_bookmark(path)
    }

    #[test]
    fn authorized_root_is_admitted_and_restored_by_a_fresh_access_instance() {
        let directory = tempfile::tempdir().expect("tempdir");
        let root = directory.path().join("Library");
        fs::create_dir(&root).expect("root");
        fs::write(root.join("rom.bin"), b"unchanged").expect("rom");
        let before = fs::read(root.join("rom.bin")).expect("before");
        let authorization = bookmark_for_directory(&root);

        let provider = LocalFilesystemProvider::default();
        let selection = LocalFilesystemRootSelection::macos_authorized(
            root.to_string_lossy().into_owned(),
            authorization,
        );
        let validated = provider.validate(&selection).expect("admit root");
        let locator = validated.locator().clone();
        assert!(
            locator
                .as_provider_value()
                .starts_with(MACOS_ROOT_LOCATOR_PREFIX)
        );

        let access = LocalFilesystemSourceAccess::new(&locator);
        let resolved = access.resolve_root().expect("restore root");
        let page = access
            .enumerate_root_direct_children(&resolved, &|| false)
            .expect("enumerate root");
        assert_eq!(page.outcome(), EnumerationOutcome::Complete);
        assert_eq!(page.observations().len(), 1);
        let bytes = access
            .read_entry_bytes(
                &resolved,
                &RelativeSourceLocator::from_provider("rom.bin".to_owned()),
                1024,
            )
            .expect("read root entry");
        assert_eq!(bytes, b"unchanged");
        assert_eq!(fs::read(root.join("rom.bin")).expect("after"), before);

        let fresh_access = LocalFilesystemSourceAccess::new(&locator);
        fresh_access
            .resolve_root()
            .expect("restore in fresh access");
    }

    #[test]
    fn bookmark_path_mismatch_is_rejected_without_rewriting_the_selection() {
        let directory = tempfile::tempdir().expect("tempdir");
        let selected = directory.path().join("Selected");
        let authorized = directory.path().join("Authorized");
        fs::create_dir(&selected).expect("selected");
        fs::create_dir(&authorized).expect("authorized");
        let selection = LocalFilesystemRootSelection::macos_authorized(
            selected.to_string_lossy().into_owned(),
            bookmark_for_directory(&authorized),
        );
        let provider = LocalFilesystemProvider::default();

        assert_eq!(
            provider.validate(&selection),
            Err(ProviderError::PermissionDenied)
        );
        assert_eq!(
            selection.selected_folder_path(),
            Some(selected.to_string_lossy().as_ref())
        );
    }

    #[test]
    fn malformed_or_unavailable_authorization_is_non_destructive() {
        let directory = tempfile::tempdir().expect("tempdir");
        let root = directory.path().join("Library");
        fs::create_dir(&root).expect("root");
        fs::write(root.join("rom.bin"), b"unchanged").expect("rom");
        let before = fs::read(root.join("rom.bin")).expect("before");
        let locator = encode_macos_root_locator(&root.to_string_lossy(), &[0xde, 0xad, 0xbe, 0xef])
            .expect("locator");
        let access = LocalFilesystemSourceAccess::new(&RootLocator::from_provider(locator.clone()));

        assert_eq!(
            access.resolve_root(),
            Err(SourceAccessError::AuthorizationUnavailable)
        );
        assert_eq!(
            RootLocator::from_provider(locator).as_provider_value(),
            access.locator
        );
        assert_eq!(fs::read(root.join("rom.bin")).expect("after"), before);
        assert!(decode_macos_root_locator("argus.local.macos-root.v1.bad").is_none());
    }

    #[test]
    fn macos_root_locator_rejects_oversized_encoded_segments_before_decoding() {
        let oversized_path = format!(
            "{MACOS_ROOT_LOCATOR_PREFIX}.{}.aa",
            "41".repeat(MAX_MACOS_ROOT_PATH_BYTES + 1)
        );
        assert!(decode_macos_root_locator(&oversized_path).is_none());

        let path_hex = hex_encode_bytes(b"/tmp/argus");
        let oversized_authorization = format!(
            "{MACOS_ROOT_LOCATOR_PREFIX}.{path_hex}.{}",
            "aa".repeat(MAX_MACOS_BOOKMARK_BYTES + 1)
        );
        assert!(decode_macos_root_locator(&oversized_authorization).is_none());
    }

    #[test]
    fn macos_root_locator_rejects_odd_malformed_and_extra_segments() {
        let prefix = MACOS_ROOT_LOCATOR_PREFIX;
        assert!(decode_macos_root_locator(&format!("{prefix}.2f746d.1")).is_none());
        assert!(decode_macos_root_locator(&format!("{prefix}.2f746d.aa1")).is_none());
        assert!(decode_macos_root_locator(&format!("{prefix}.not-hex.aa")).is_none());
        assert!(decode_macos_root_locator(&format!("{prefix}.2f746d.not-hex")).is_none());
        assert!(decode_macos_root_locator(&format!("{prefix}.2f746d.aa.extra")).is_none());
        assert!(decode_macos_root_locator(&format!("{prefix}.\u{20ac}a.aa")).is_none());
    }

    struct TestScopeFactory {
        starts: Arc<AtomicUsize>,
        stops: Arc<AtomicUsize>,
        allow_start: bool,
    }

    impl TestScopeFactory {
        fn resolver(self, path: PathBuf) -> TestBookmarkResolver {
            Arc::new(move |_authorization| {
                if !self.allow_start {
                    return Err(SourceAccessError::AuthorizationUnavailable);
                }
                self.starts.fetch_add(1, Ordering::Relaxed);
                Ok(MacosSecurityScope::test_started(
                    NSURL::from_directory_path(&path).expect("directory URL"),
                    Arc::clone(&self.stops),
                ))
            })
        }
    }

    #[test]
    fn security_scope_lifecycle_is_owned_by_access_and_has_no_global_state() {
        let directory = tempfile::tempdir().expect("tempdir");
        let root = directory.path().join("Library");
        fs::create_dir(&root).expect("root");
        let starts = Arc::new(AtomicUsize::new(0));
        let stops = Arc::new(AtomicUsize::new(0));
        let factory = TestScopeFactory {
            starts: Arc::clone(&starts),
            stops: Arc::clone(&stops),
            allow_start: true,
        };
        let locator = RootLocator::from_provider(
            encode_macos_root_locator(&root.to_string_lossy(), &[0xab]).expect("test locator"),
        );
        let access = LocalFilesystemSourceAccess::new_with_test_bookmark_resolver(
            &locator,
            factory.resolver(root.clone()),
        );

        access.resolve_root().expect("first scope starts");
        assert_eq!(starts.load(Ordering::Relaxed), 1);
        assert_eq!(stops.load(Ordering::Relaxed), 0);

        access.resolve_root().expect("replacement scope starts");
        assert_eq!(starts.load(Ordering::Relaxed), 2);
        assert_eq!(stops.load(Ordering::Relaxed), 1);

        let failed_factory = TestScopeFactory {
            starts: Arc::new(AtomicUsize::new(0)),
            stops: Arc::new(AtomicUsize::new(0)),
            allow_start: false,
        };
        let failed_starts = Arc::clone(&failed_factory.starts);
        let failed_stops = Arc::clone(&failed_factory.stops);
        let failed_access = LocalFilesystemSourceAccess::new_with_test_bookmark_resolver(
            &locator,
            failed_factory.resolver(root),
        );
        assert_eq!(
            failed_access.resolve_root(),
            Err(SourceAccessError::AuthorizationUnavailable)
        );
        assert_eq!(failed_starts.load(Ordering::Relaxed), 0);
        assert_eq!(failed_stops.load(Ordering::Relaxed), 0);

        drop(access);
        assert_eq!(stops.load(Ordering::Relaxed), 2);
    }
}
