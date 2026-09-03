//! Shared migration and filesystem fixtures for infrastructure integration tests.

#![allow(dead_code)]

use std::path::Path;

use argus_application::{LocalFilesystemProvider, LocalFilesystemRootSelection, RootLocator};
use argus_infrastructure::local_filesystem::{
    LocalFilesystemProvider as LocalFilesystemProviderImpl, LocalFilesystemSourceAccess,
};
use argus_infrastructure::sqlite::MigrationRegistry;

/// Builds the complete embedded migration chain as an explicitly custom registry.
///
/// Historical integration fixtures use this registry when reopening a
/// database seeded at an older schema. The explicit no-floor constructor keeps
/// this registry independent of the production embedded registry's
/// minimum-compatible-schema policy.
#[allow(dead_code)]
pub fn current_registry() -> MigrationRegistry {
    MigrationRegistry::embedded_without_compatibility_floor()
}

/// Builds a historical registry from the authoritative embedded migration
/// chain without applying the production compatibility floor.
pub fn registry_through(version: usize) -> MigrationRegistry {
    MigrationRegistry::embedded_through_for_tests(version)
}

/// Builds a valid local-root selection for a test directory.
pub fn selection(path: &Path) -> LocalFilesystemRootSelection {
    #[cfg(target_os = "macos")]
    {
        LocalFilesystemRootSelection::macos_authorized(
            path.to_string_lossy().into_owned(),
            argus_infrastructure::local_filesystem::macos_test_bookmark_for_directory(path),
        )
    }
    #[cfg(not(target_os = "macos"))]
    {
        LocalFilesystemRootSelection::path(path.to_string_lossy().into_owned())
    }
}

/// Builds a selection whose submitted path differs from the authorized path.
pub fn selection_with_authorization_path(
    selected_path: &Path,
    authorization_path: &Path,
) -> LocalFilesystemRootSelection {
    #[cfg(target_os = "macos")]
    {
        LocalFilesystemRootSelection::macos_authorized(
            selected_path.to_string_lossy().into_owned(),
            argus_infrastructure::local_filesystem::macos_test_bookmark_for_directory(
                authorization_path,
            ),
        )
    }
    #[cfg(not(target_os = "macos"))]
    {
        let _ = authorization_path;
        LocalFilesystemRootSelection::path(selected_path.to_string_lossy().into_owned())
    }
}

/// Returns the provider-owned locator for a valid test directory.
pub fn locator(path: &Path) -> RootLocator {
    LocalFilesystemProviderImpl::default()
        .validate(&selection(path))
        .expect("valid test root")
        .locator()
        .clone()
}

/// Creates source access backed by a valid test directory.
pub fn access(path: &Path) -> LocalFilesystemSourceAccess {
    LocalFilesystemSourceAccess::new(&locator(path))
}
