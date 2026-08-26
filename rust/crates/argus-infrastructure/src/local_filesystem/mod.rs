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

use crate::content::{ContentReadError, ContentReader};
use argus_application::{
    DiscoveryPath, DiscoverySegment, EnumerationOutcome, EnumerationResult, LibrarySourceAccess,
    LocalFilesystemBrowseBreadcrumb, LocalFilesystemBrowseCursor, LocalFilesystemBrowseDirectory,
    LocalFilesystemBrowseLocation, LocalFilesystemBrowsePage, LocalFilesystemBrowseProvider,
    LocalFilesystemBrowseRoot, LocalFilesystemProvider as LocalFilesystemProviderPort,
    LocalFilesystemRootSelection, MAX_LOCAL_FILESYSTEM_BROWSE_PAGE_SIZE,
    MAX_MOUNTED_LOCAL_FILESYSTEM_VOLUMES, MountedLocalFilesystemVolume, ObservedEntryKind,
    ProviderError, RelativeSourceLocator, ResolvedRoot, RootLocator, RootRelationship,
    SourceAccessError, SourceLocatorKey, SourceObservation, ValidatedLocalRoot,
};

const ROOT_LOCATOR_PREFIX: &str = "argus-local-root-v2";
const BROWSE_LOCATION_PREFIX: &str = "argus-local-browse-v1";
const BROWSE_CURSOR_PREFIX: &str = "argus-local-cursor-v1";
const PRIMARY_VOLUME_ID: &str = "primary";

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
    resolved_root: Mutex<Option<std::path::PathBuf>>,
    mounted_volumes: Option<Arc<RwLock<MountedVolumeRegistry>>>,
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
}

impl LocalContentReader {
    fn open(path: PathBuf, metadata: &std::fs::Metadata) -> Result<Self, SourceAccessError> {
        let file = std::fs::File::open(&path).map_err(classify_entry_access_error)?;
        Ok(Self {
            file,
            path,
            length: metadata.len(),
            initial_fingerprint: source_fingerprint(metadata, ObservedEntryKind::File),
        })
    }

    /// Returns whether the source still has the version observed at open.
    pub fn source_version_is_unchanged(&self) -> Result<bool, SourceAccessError> {
        let metadata = std::fs::metadata(&self.path).map_err(classify_entry_access_error)?;
        if !metadata.is_file() {
            return Ok(false);
        }
        Ok(source_fingerprint(&metadata, ObservedEntryKind::File) == self.initial_fingerprint)
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
        }
    }
}

impl LibrarySourceAccess for LocalFilesystemSourceAccess {
    fn resolve_root(&self) -> Result<ResolvedRoot, SourceAccessError> {
        let canonical = resolve_locator_path(&self.locator, self.mounted_volumes.as_ref())?;
        let token = canonical.to_string_lossy().into_owned();
        *self
            .resolved_root
            .lock()
            .map_err(|_| SourceAccessError::IoFailure)? = Some(canonical);
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

    fn read_entry_bytes(
        &self,
        root: &ResolvedRoot,
        relative: &RelativeSourceLocator,
        max_bytes: usize,
    ) -> Result<Vec<u8>, SourceAccessError> {
        let root_path = self.current_root(root)?;
        let entry_path = resolve_entry_path(&root_path, relative)?;
        let metadata = std::fs::metadata(&entry_path).map_err(classify_entry_access_error)?;
        if !metadata.is_file() {
            return Err(SourceAccessError::UnsupportedOperation);
        }
        if metadata.len() > max_bytes as u64 {
            return Err(SourceAccessError::UnsupportedOperation);
        }

        let mut file = std::fs::File::open(&entry_path).map_err(classify_entry_access_error)?;
        let mut bytes = Vec::with_capacity(metadata.len().min(max_bytes as u64) as usize);
        let read = file
            .by_ref()
            .take(max_bytes as u64 + 1)
            .read_to_end(&mut bytes)
            .map_err(classify_entry_access_error)?;
        if read > max_bytes {
            return Err(SourceAccessError::UnsupportedOperation);
        }
        Ok(bytes)
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
        let metadata = std::fs::metadata(&entry_path).map_err(classify_entry_access_error)?;
        if !metadata.is_file() {
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
        let canonical = resolved.to_string_lossy();
        if canonical != root.as_provider_value() {
            return Err(SourceAccessError::InvalidLocator);
        }
        Ok(resolved.clone())
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
    for component in components {
        candidate.push(component);
        let metadata =
            std::fs::symlink_metadata(&candidate).map_err(classify_entry_access_error)?;
        if is_link_like(&metadata) {
            return Err(SourceAccessError::InvalidLocator);
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
        }
    }

    fn compare_roots(&self, left: &RootLocator, right: &RootLocator) -> RootRelationship {
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
                let Ok(left_canonical) = std::fs::canonicalize(Path::new(left.as_provider_value()))
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

fn resolve_locator_path(
    locator: &str,
    mounted_volumes: Option<&Arc<RwLock<MountedVolumeRegistry>>>,
) -> Result<PathBuf, SourceAccessError> {
    if locator.starts_with(ROOT_LOCATOR_PREFIX) {
        let coordinate = decode_coordinate(locator, ROOT_LOCATOR_PREFIX)
            .ok_or(SourceAccessError::InvalidLocator)?;
        let registry = mounted_volumes.ok_or(SourceAccessError::SourceUnavailable)?;
        let registry = registry.read().map_err(|_| SourceAccessError::IoFailure)?;
        let volume = registry
            .volumes
            .get(&coordinate.provider_volume_id)
            .ok_or(SourceAccessError::SourceUnavailable)?;
        return resolve_volume_relative_path(volume, &coordinate.relative);
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
    Ok(canonical)
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
    value
        .as_bytes()
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect()
}

fn hex_decode(value: &str) -> Option<String> {
    if !value.len().is_multiple_of(2) {
        return None;
    }
    let bytes = (0..value.len())
        .step_by(2)
        .map(|index| u8::from_str_radix(&value[index..index + 2], 16).ok())
        .collect::<Option<Vec<_>>>()?;
    String::from_utf8(bytes).ok()
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
