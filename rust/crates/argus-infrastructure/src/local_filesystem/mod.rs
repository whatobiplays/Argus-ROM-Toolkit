//! Concrete LocalFilesystem source-provider adapter.
//!
//! This adapter owns all filesystem parsing, normalization, validation,
//! locator construction, and root-relationship semantics for the
//! `local_filesystem` provider family. Generic application, persistence,
//! bridge, and Flutter code never interprets the provider-owned locator
//! values produced here.

use std::path::Path;

use argus_application::{
    LocalFilesystemProvider as LocalFilesystemProviderPort, LocalFilesystemRootSelection,
    ProviderError, RootLocator, RootRelationship, ValidatedLocalRoot,
};

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
