//! Cross-platform LocalFilesystem provider contract tests.
//!
//! These tests execute real native filesystem operations and are intended to
//! run on Windows, Linux, and macOS CI. They cover only Phase 001 provider
//! contract facts not already owned by the existing `sources.rs` and
//! `jobs.rs` infrastructure tests (root validation/relationships, link-like
//! root rejection, nested enumeration, link retention, namespace-escape
//! rejection, root resolution for missing/link-like roots, and
//! pre-enumeration cancellation).

use std::fs;

use argus_application::{
    EnumerationOutcome, LibrarySourceAccess, LocalFilesystemProvider, LocalFilesystemRootSelection,
    ObservedEntryKind, ProviderError, RelativeSourceLocator, RootLocator, SourceAccessError,
};
use argus_infrastructure::local_filesystem::{
    LocalFilesystemProvider as LocalFilesystemProviderImpl, LocalFilesystemSourceAccess,
};

#[test]
fn direct_enumeration_classifies_files_and_directories_explicitly() {
    let directory = tempfile::tempdir().expect("tempdir");
    let root = directory.path().join("Library");
    fs::create_dir_all(root.join("Sub")).expect("subdirectory");
    fs::write(root.join("rom.bin"), b"rom").expect("file");

    let access = LocalFilesystemSourceAccess::new(&RootLocator::from_provider(
        root.to_string_lossy().into_owned(),
    ));
    let resolved = access.resolve_root().expect("resolve");
    let scope = access
        .enumerate_root_direct_children(&resolved, &|| false)
        .expect("root scope");

    assert_eq!(scope.outcome(), EnumerationOutcome::Complete);
    let by_name = |name: &str| {
        scope
            .observations()
            .iter()
            .find(|observation| observation.display_name() == name)
            .unwrap_or_else(|| panic!("missing observation {name:?}"))
    };
    assert_eq!(by_name("Sub").observed_kind(), ObservedEntryKind::Directory);
    assert_eq!(by_name("rom.bin").observed_kind(), ObservedEntryKind::File);
}

#[test]
fn cancellation_mid_enumeration_is_honored_after_partial_progress() {
    let directory = tempfile::tempdir().expect("tempdir");
    let root = directory.path().join("Library");
    fs::create_dir(&root).expect("root");
    for index in 0..5 {
        fs::write(root.join(format!("entry-{index}.bin")), b"data").expect("entry");
    }

    let access = LocalFilesystemSourceAccess::new(&RootLocator::from_provider(
        root.to_string_lossy().into_owned(),
    ));
    let resolved = access.resolve_root().expect("resolve");

    // The enumeration loop checks cancellation before every entry, so the
    // first two calls observe entries and the third call terminates the
    // enumeration with a typed cancellation instead of an outcome.
    let checks = std::cell::Cell::new(0);
    let is_cancelled = || {
        checks.set(checks.get() + 1);
        checks.get() > 2
    };
    assert_eq!(
        access.enumerate_root_direct_children(&resolved, &is_cancelled),
        Err(SourceAccessError::Cancelled)
    );

    // Cancellation is per invocation: the same access remains usable and
    // later completes without fabricating a cancellation outcome.
    let completed = access
        .enumerate_root_direct_children(&resolved, &|| false)
        .expect("later scope");
    assert_eq!(completed.outcome(), EnumerationOutcome::Complete);
    assert_eq!(completed.observations().len(), 5);
}

#[test]
fn native_identity_is_provider_owned_and_never_fabricated() {
    let directory = tempfile::tempdir().expect("tempdir");
    let root = directory.path().join("Library");
    fs::create_dir(&root).expect("root");
    fs::write(root.join("rom.bin"), b"rom").expect("file");

    let access = LocalFilesystemSourceAccess::new(&RootLocator::from_provider(
        root.to_string_lossy().into_owned(),
    ));
    let resolved = access.resolve_root().expect("resolve");
    let identity_of_file = || {
        let scope = access
            .enumerate_root_direct_children(&resolved, &|| false)
            .expect("root scope");
        scope
            .observations()
            .iter()
            .find(|observation| observation.display_name() == "rom.bin")
            .expect("file observation")
            .provider_native_identity()
            .map(str::to_owned)
    };

    #[cfg(unix)]
    {
        // Unix native identity is derived from stable device/inode facts, so
        // an unchanged file must produce byte-identical evidence across
        // independent enumerations. That stability is what makes move
        // reconciliation trustworthy at the application layer.
        let first = identity_of_file().expect("unix identity");
        let second = identity_of_file().expect("second unix identity");
        assert!(first.starts_with("unix:"), "unexpected identity {first:?}");
        assert_eq!(first, second);
    }

    #[cfg(not(unix))]
    {
        // Non-Unix platforms without a provider-supported native identity
        // must report None rather than fabricating a plausible-looking value.
        assert!(identity_of_file().is_none());
    }
}

#[test]
fn resolve_root_rejects_a_non_directory_regular_file() {
    let directory = tempfile::tempdir().expect("tempdir");
    let file_path = directory.path().join("rom.bin");
    fs::write(&file_path, b"rom").expect("file");

    let access = LocalFilesystemSourceAccess::new(&RootLocator::from_provider(
        file_path.to_string_lossy().into_owned(),
    ));
    assert_eq!(
        access.resolve_root(),
        Err(SourceAccessError::InvalidLocator)
    );
}

#[test]
fn unresolvable_nested_scope_is_rejected_without_guessing() {
    let directory = tempfile::tempdir().expect("tempdir");
    let root = directory.path().join("Library");
    fs::create_dir_all(root.join("Sub")).expect("nested directory");

    let access = LocalFilesystemSourceAccess::new(&RootLocator::from_provider(
        root.to_string_lossy().into_owned(),
    ));
    let resolved = access.resolve_root().expect("resolve");

    // SPEC-BE-011 root-boundary enforcement rejects every relative scope the
    // provider cannot prove is inside the resolved root. A missing nested
    // scope cannot be canonicalized into the root namespace, so it maps to
    // InvalidLocator rather than guessing at an absence outcome. This keeps
    // nested entry disappearance free of absence authority.
    assert_eq!(
        access.enumerate_direct_children(
            &resolved,
            &RelativeSourceLocator::from_provider("Sub/missing".to_owned()),
            &|| false,
        ),
        Err(SourceAccessError::InvalidLocator)
    );
}

#[cfg(unix)]
#[test]
fn inaccessible_root_maps_to_permission_denied_when_the_runner_can_create_it() {
    use std::os::unix::fs::PermissionsExt;

    let directory = tempfile::tempdir().expect("tempdir");
    let root = directory.path().join("blocked");
    fs::create_dir(&root).expect("blocked root");
    fs::set_permissions(&root, fs::Permissions::from_mode(0o000)).expect("chmod");

    // Root-like runners can still read 0o000 directories; permission-denied
    // evidence is only meaningful where the environment genuinely denies.
    if fs::read_dir(&root).is_ok() {
        eprintln!("skipping permission-denied assertions: runner can read a 0o000 directory");
        fs::set_permissions(&root, fs::Permissions::from_mode(0o755)).expect("restore");
        return;
    }

    let provider = LocalFilesystemProviderImpl;
    let selection = LocalFilesystemRootSelection::new(root.to_string_lossy().into_owned());
    assert_eq!(
        provider.validate(&selection),
        Err(ProviderError::PermissionDenied)
    );

    let access = LocalFilesystemSourceAccess::new(&RootLocator::from_provider(
        root.to_string_lossy().into_owned(),
    ));
    assert_eq!(
        access.resolve_root(),
        Err(SourceAccessError::PermissionDenied)
    );

    fs::set_permissions(&root, fs::Permissions::from_mode(0o755)).expect("restore");
}

#[cfg(windows)]
#[test]
fn windows_junction_roots_and_children_follow_the_link_like_contract_when_creatable() {
    let directory = tempfile::tempdir().expect("tempdir");
    let target = directory.path().join("target");
    fs::create_dir(&target).expect("target");
    let root = directory.path().join("Library");
    fs::create_dir(&root).expect("library root");
    let junction = root.join("junction");

    // Junction creation does not require Developer Mode, but it can still be
    // unavailable on restricted runners. The test skips cleanly in that case
    // instead of requiring a privileged environment.
    let created = std::process::Command::new("cmd")
        .args(["/C", "mklink", "/J"])
        .arg(&junction)
        .arg(&target)
        .status();
    if created.map(|status| !status.success()).unwrap_or(true) {
        eprintln!("skipping junction assertions: mklink /J is unavailable");
        return;
    }

    // A junction root is link-like and must be rejected by validation and
    // root resolution rather than traversed.
    let provider = LocalFilesystemProviderImpl;
    let selection = LocalFilesystemRootSelection::new(junction.to_string_lossy().into_owned());
    assert_eq!(
        provider.validate(&selection),
        Err(ProviderError::LinkLikeRoot)
    );

    let access = LocalFilesystemSourceAccess::new(&RootLocator::from_provider(
        junction.to_string_lossy().into_owned(),
    ));
    assert_eq!(
        access.resolve_root(),
        Err(SourceAccessError::InvalidLocator)
    );

    // A junction child is retained as link-like evidence but never traversed:
    // requesting its scope as a relative locator must fail boundary
    // enforcement instead of following the outside target.
    let root_access = LocalFilesystemSourceAccess::new(&RootLocator::from_provider(
        root.to_string_lossy().into_owned(),
    ));
    let resolved = root_access.resolve_root().expect("resolve");
    let scope = root_access
        .enumerate_root_direct_children(&resolved, &|| false)
        .expect("root scope");
    let junction_observation = scope
        .observations()
        .iter()
        .find(|observation| observation.display_name() == "junction")
        .expect("junction observation");
    assert_eq!(
        junction_observation.observed_kind(),
        ObservedEntryKind::LinkLike
    );
    assert_eq!(
        root_access.enumerate_direct_children(
            &resolved,
            junction_observation.relative_locator(),
            &|| false,
        ),
        Err(SourceAccessError::InvalidLocator)
    );
}
