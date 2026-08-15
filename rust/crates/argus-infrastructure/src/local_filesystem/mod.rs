//! Concrete LocalFilesystem source-provider adapter.
//!
//! This adapter owns all filesystem parsing, normalization, validation,
//! locator construction, and root-relationship semantics for the
//! `local_filesystem` provider family. Generic application, persistence,
//! bridge, and Flutter code never interprets the provider-owned locator
//! values produced here.

use std::path::Path;
use std::sync::Mutex;
use std::time::UNIX_EPOCH;

use argus_application::{
    DiscoveryPath, DiscoverySegment, EnumerationOutcome, EnumerationResult, LibrarySourceAccess,
    LocalFilesystemProvider as LocalFilesystemProviderPort, LocalFilesystemRootSelection,
    ObservedEntryKind, ProviderError, RelativeSourceLocator, ResolvedRoot, RootLocator,
    RootRelationship, SourceAccessError, SourceLocatorKey, SourceObservation, ValidatedLocalRoot,
};

/// Concrete execution-scoped local-filesystem source access.
///
/// The adapter owns all native path interpretation, locator keys, identity
/// facts, and error translation for one scan execution attempt. It is never
/// persisted and never reused across runtime generations.
pub struct LocalFilesystemSourceAccess {
    locator: String,
    resolved_root: Mutex<Option<std::path::PathBuf>>,
}

impl LocalFilesystemSourceAccess {
    /// Creates access bound to one configured root locator.
    pub fn new(locator: &RootLocator) -> Self {
        Self {
            locator: locator.as_provider_value().to_owned(),
            resolved_root: Mutex::new(None),
        }
    }
}

impl LibrarySourceAccess for LocalFilesystemSourceAccess {
    fn resolve_root(&self) -> Result<ResolvedRoot, SourceAccessError> {
        let path = Path::new(&self.locator);
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
}

impl LocalFilesystemSourceAccess {
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
        if !is_within_root(root_path, &scope_path.join(entry.file_name())) {
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
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct LocalFilesystemProvider;

impl LocalFilesystemProviderPort for LocalFilesystemProvider {
    fn validate(
        &self,
        selection: &LocalFilesystemRootSelection,
    ) -> Result<ValidatedLocalRoot, ProviderError> {
        let raw = selection.selected_folder_path();
        let path = Path::new(raw);
        if !path.is_absolute() {
            return Err(ProviderError::InvalidSelection);
        }

        let metadata = std::fs::symlink_metadata(path).map_err(classify_stat_error)?;
        if metadata.file_type().is_symlink() {
            return Err(ProviderError::LinkLikeRoot);
        }
        #[cfg(windows)]
        {
            use std::os::windows::fs::MetadataExt;
            const FILE_ATTRIBUTE_REPARSE_POINT: u32 = 0x400;
            if metadata.file_attributes() & FILE_ATTRIBUTE_REPARSE_POINT != 0 {
                return Err(ProviderError::LinkLikeRoot);
            }
        }
        if !metadata.is_dir() {
            return Err(ProviderError::NotADirectory);
        }

        // Successful validation must establish that the directory is
        // currently reachable and enumerable. Opening the directory handle
        // proves access without recursively reading or scanning contents.
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

    fn compare_roots(&self, left: &RootLocator, right: &RootLocator) -> RootRelationship {
        // Comparison uses actual resolved filesystem semantics only. There
        // are no blanket platform case-folding rules: canonicalization either
        // proves the relationship or the provider returns Unknown. The
        // persisted locator is never rewritten by this comparison.
        let Ok(left_canonical) = std::fs::canonicalize(Path::new(left.as_provider_value())) else {
            return RootRelationship::Unknown;
        };
        let Ok(right_canonical) = std::fs::canonicalize(Path::new(right.as_provider_value()))
        else {
            return RootRelationship::Unknown;
        };
        if left_canonical == right_canonical {
            return RootRelationship::Same;
        }
        if left_canonical.starts_with(&right_canonical) {
            return RootRelationship::Descendant;
        }
        if right_canonical.starts_with(&left_canonical) {
            return RootRelationship::Ancestor;
        }
        RootRelationship::Disjoint
    }

    fn open_access(
        &self,
        locator: &RootLocator,
    ) -> Result<Box<dyn LibrarySourceAccess>, SourceAccessError> {
        Ok(Box::new(LocalFilesystemSourceAccess::new(locator)))
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
