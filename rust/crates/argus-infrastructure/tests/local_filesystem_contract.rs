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
    EnumerationOutcome, LibrarySourceAccess, LocalFilesystemBrowseProvider,
    LocalFilesystemProvider, LocalFilesystemRootSelection, MountedLocalFilesystemVolume,
    ObservedEntryKind, ProviderError, RelativeSourceLocator, RootLocator, RootRelationship,
    SourceAccessError,
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
fn bounded_entry_bytes_never_returns_more_than_the_requested_limit() {
    let directory = tempfile::tempdir().expect("tempdir");
    let root = directory.path().join("Library");
    fs::create_dir_all(root.join("nested")).expect("root");
    fs::write(root.join("rom.bin"), b"0123456789").expect("file");

    let access = LocalFilesystemSourceAccess::new(&RootLocator::from_provider(
        root.to_string_lossy().into_owned(),
    ));
    let resolved = access.resolve_root().expect("resolve");
    let locator = RelativeSourceLocator::from_provider("rom.bin".to_owned());

    assert_eq!(
        access.read_entry_bytes(&resolved, &locator, 4),
        Err(SourceAccessError::UnsupportedOperation)
    );
    assert_eq!(
        access
            .read_entry_bytes(&resolved, &locator, 10)
            .expect("bounded bytes"),
        b"0123456789"
    );
    assert_eq!(
        access.read_entry_bytes(
            &resolved,
            &RelativeSourceLocator::from_provider("../rom.bin".to_owned()),
            10,
        ),
        Err(SourceAccessError::InvalidLocator)
    );
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

    let provider = LocalFilesystemProviderImpl::default();
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
    let provider = LocalFilesystemProviderImpl::default();
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

#[test]
fn mounted_volume_replacement_is_atomic_and_bounded() {
    let directory = tempfile::tempdir().expect("tempdir");
    let primary = directory.path().join("primary");
    let removable = directory.path().join("removable");
    fs::create_dir(&primary).expect("primary");
    fs::create_dir(&removable).expect("removable");
    let provider = LocalFilesystemProviderImpl::default();

    let valid = vec![
        MountedLocalFilesystemVolume::new(
            "primary".to_owned(),
            primary.to_string_lossy().into_owned(),
            "Internal storage".to_owned(),
            true,
            false,
        ),
        MountedLocalFilesystemVolume::new(
            "removable-1".to_owned(),
            removable.to_string_lossy().into_owned(),
            "Game card".to_owned(),
            false,
            true,
        ),
    ];
    provider
        .replace_mounted_volumes(&valid)
        .expect("valid snapshot");
    assert_eq!(provider.list_browse_roots().expect("roots").len(), 2);

    let invalid = vec![
        valid[0].clone(),
        MountedLocalFilesystemVolume::new(
            "primary".to_owned(),
            removable.to_string_lossy().into_owned(),
            "Duplicate".to_owned(),
            false,
            true,
        ),
    ];
    assert_eq!(
        provider.replace_mounted_volumes(&invalid),
        Err(ProviderError::InvalidBrowseRequest)
    );
    assert_eq!(
        provider.list_browse_roots().expect("unchanged roots").len(),
        2
    );
}

#[test]
fn provider_clones_observe_one_transient_mount_registry() {
    let directory = tempfile::tempdir().expect("tempdir");
    let primary = directory.path().join("primary");
    fs::create_dir(&primary).expect("primary");
    let provider = LocalFilesystemProviderImpl::default();
    let clone = provider.clone();
    provider
        .replace_mounted_volumes(&[MountedLocalFilesystemVolume::new(
            "primary".to_owned(),
            primary.to_string_lossy().into_owned(),
            "Internal storage".to_owned(),
            true,
            false,
        )])
        .expect("snapshot");
    assert_eq!(clone.list_browse_roots().expect("shared roots").len(), 1);
}

#[test]
fn browse_pages_are_directory_only_sorted_and_cursor_bounded() {
    let directory = tempfile::tempdir().expect("tempdir");
    let primary = directory.path().join("primary");
    fs::create_dir(&primary).expect("primary");
    fs::create_dir(primary.join("z-last")).expect("z directory");
    fs::create_dir(primary.join("a-first")).expect("a directory");
    fs::write(primary.join("rom.bin"), b"rom").expect("file");
    let provider = LocalFilesystemProviderImpl::default();
    provider
        .replace_mounted_volumes(&[MountedLocalFilesystemVolume::new(
            "primary".to_owned(),
            primary.to_string_lossy().into_owned(),
            "Internal storage".to_owned(),
            true,
            false,
        )])
        .expect("snapshot");

    let root = provider
        .list_browse_roots()
        .expect("roots")
        .into_iter()
        .next()
        .expect("primary root");
    let first = provider
        .list_browse_directories(root.location(), None, 1)
        .expect("first page");
    assert_eq!(
        first
            .directories()
            .iter()
            .map(|directory| directory.display_name())
            .collect::<Vec<_>>(),
        vec!["a-first"]
    );
    let second = provider
        .list_browse_directories(root.location(), first.next_cursor(), 1)
        .expect("second page");
    assert_eq!(second.directories()[0].display_name(), "z-last");
    assert!(second.next_cursor().is_none());
}

#[test]
fn stable_provider_root_locator_survives_remount_at_a_new_path() {
    let directory = tempfile::tempdir().expect("tempdir");
    let primary = directory.path().join("primary");
    let mount_a = directory.path().join("mount-a");
    let mount_b = directory.path().join("mount-b");
    fs::create_dir(&primary).expect("primary");
    fs::create_dir(&mount_a).expect("mount a");
    fs::create_dir(&mount_b).expect("mount b");
    fs::create_dir(mount_a.join("Games")).expect("games a");
    fs::create_dir(mount_b.join("Games")).expect("games b");
    let provider = LocalFilesystemProviderImpl::default();
    provider
        .replace_mounted_volumes(&[
            MountedLocalFilesystemVolume::new(
                "primary".to_owned(),
                primary.to_string_lossy().into_owned(),
                "Internal storage".to_owned(),
                true,
                false,
            ),
            MountedLocalFilesystemVolume::new(
                "removable-1".to_owned(),
                mount_a.to_string_lossy().into_owned(),
                "Game card".to_owned(),
                false,
                true,
            ),
        ])
        .expect("mount a snapshot");
    let removable_root = provider
        .list_browse_roots()
        .expect("roots")
        .into_iter()
        .find(|root| root.display_name() == "Game card")
        .expect("removable root");
    let validated = provider
        .validate(&LocalFilesystemRootSelection::provider_selection(
            removable_root.location().as_provider_value().to_owned(),
        ))
        .expect("provider root selection");
    let locator = validated.locator().clone();
    assert!(
        !locator
            .as_provider_value()
            .contains(&mount_a.to_string_lossy().to_string())
    );

    provider
        .replace_mounted_volumes(&[
            MountedLocalFilesystemVolume::new(
                "primary".to_owned(),
                primary.to_string_lossy().into_owned(),
                "Internal storage".to_owned(),
                true,
                false,
            ),
            MountedLocalFilesystemVolume::new(
                "removable-1".to_owned(),
                mount_b.to_string_lossy().into_owned(),
                "Game card".to_owned(),
                false,
                true,
            ),
        ])
        .expect("mount b snapshot");
    let access = provider.open_access(&locator).expect("access");
    let resolved = access.resolve_root().expect("remounted root");
    assert_eq!(
        resolved.as_provider_value(),
        std::fs::canonicalize(&mount_b)
            .expect("canonical mount b")
            .to_string_lossy()
    );
}

#[test]
fn provider_selection_opens_shared_access_and_enumerates_nested_content() {
    let directory = tempfile::tempdir().expect("tempdir");
    let primary = directory.path().join("primary");
    let mount = directory.path().join("mounted");
    fs::create_dir(&primary).expect("primary");
    fs::create_dir_all(mount.join("Games/Nested")).expect("nested games");
    fs::write(mount.join("Games/rom.bin"), b"rom").expect("rom");
    fs::write(mount.join("Games/Nested/save.dat"), b"save").expect("save");

    let provider = LocalFilesystemProviderImpl::default();
    provider
        .replace_mounted_volumes(&[
            MountedLocalFilesystemVolume::new(
                "primary".to_owned(),
                primary.to_string_lossy().into_owned(),
                "Internal storage".to_owned(),
                true,
                false,
            ),
            MountedLocalFilesystemVolume::new(
                "android-volume".to_owned(),
                mount.to_string_lossy().into_owned(),
                "Game card".to_owned(),
                false,
                true,
            ),
        ])
        .expect("mounted snapshot");

    let mounted_root = provider
        .list_browse_roots()
        .expect("browse roots")
        .into_iter()
        .find(|root| root.display_name() == "Game card")
        .expect("mounted browse root");
    let games_page = provider
        .list_browse_directories(mounted_root.location(), None, 10)
        .expect("games page");
    let games = games_page
        .directories()
        .iter()
        .find(|directory| directory.display_name() == "Games")
        .expect("games directory");
    let validated = provider
        .validate(&LocalFilesystemRootSelection::provider_selection(
            games.location().as_provider_value().to_owned(),
        ))
        .expect("provider selection");
    let locator = validated.locator().clone();
    assert!(
        !locator
            .as_provider_value()
            .contains(&mount.to_string_lossy().to_string())
    );

    let access = provider.open_access(&locator).expect("source access");
    let resolved = access.resolve_root().expect("resolved root");
    let root_scope = access
        .enumerate_root_direct_children(&resolved, &|| false)
        .expect("root scope");
    assert_eq!(root_scope.outcome(), EnumerationOutcome::Complete);
    let nested = root_scope
        .observations()
        .iter()
        .find(|observation| observation.display_name() == "Nested")
        .expect("nested directory");
    assert!(
        root_scope
            .observations()
            .iter()
            .any(|observation| observation.display_name() == "rom.bin")
    );

    let nested_scope = access
        .enumerate_direct_children(&resolved, nested.relative_locator(), &|| false)
        .expect("nested scope");
    assert!(
        nested_scope
            .observations()
            .iter()
            .any(|observation| observation.display_name() == "save.dat")
    );
}

#[cfg(unix)]
#[test]
fn provider_selection_preserves_unix_identity_for_an_in_filesystem_rename() {
    let directory = tempfile::tempdir().expect("tempdir");
    let primary = directory.path().join("primary");
    let mount = directory.path().join("mounted");
    fs::create_dir(&primary).expect("primary");
    fs::create_dir_all(mount.join("Games")).expect("games");
    fs::write(mount.join("Games/move.bin"), b"move").expect("move file");

    let provider = LocalFilesystemProviderImpl::default();
    provider
        .replace_mounted_volumes(&[
            MountedLocalFilesystemVolume::new(
                "primary".to_owned(),
                primary.to_string_lossy().into_owned(),
                "Internal storage".to_owned(),
                true,
                false,
            ),
            MountedLocalFilesystemVolume::new(
                "android-volume".to_owned(),
                mount.to_string_lossy().into_owned(),
                "Game card".to_owned(),
                false,
                true,
            ),
        ])
        .expect("mounted snapshot");
    let mounted_root = provider
        .list_browse_roots()
        .expect("browse roots")
        .into_iter()
        .find(|root| root.display_name() == "Game card")
        .expect("mounted browse root");
    let games_page = provider
        .list_browse_directories(mounted_root.location(), None, 10)
        .expect("games page");
    let games = games_page
        .directories()
        .iter()
        .find(|directory| directory.display_name() == "Games")
        .expect("games directory");
    let locator = provider
        .validate(&LocalFilesystemRootSelection::provider_selection(
            games.location().as_provider_value().to_owned(),
        ))
        .expect("provider selection")
        .locator()
        .clone();
    let access = provider.open_access(&locator).expect("source access");
    let resolved = access.resolve_root().expect("resolved root");

    let first = access
        .enumerate_root_direct_children(&resolved, &|| false)
        .expect("first scope");
    let first_observation = first
        .observations()
        .iter()
        .find(|observation| observation.display_name() == "move.bin")
        .expect("move candidate");
    let identity = first_observation
        .provider_native_identity()
        .expect("provider-native identity")
        .to_owned();

    fs::rename(
        mount.join("Games/move.bin"),
        mount.join("Games/renamed.bin"),
    )
    .expect("rename");
    let second = access
        .enumerate_root_direct_children(&resolved, &|| false)
        .expect("second scope");
    let renamed = second
        .observations()
        .iter()
        .find(|observation| observation.display_name() == "renamed.bin")
        .expect("renamed candidate");
    assert_eq!(renamed.provider_native_identity(), Some(identity.as_str()));
}

#[cfg(unix)]
#[test]
fn provider_selected_root_retains_but_never_traverses_link_like_children() {
    use std::os::unix::fs::symlink;

    let directory = tempfile::tempdir().expect("tempdir");
    let primary = directory.path().join("primary");
    let mount = directory.path().join("mounted");
    let outside = directory.path().join("outside");
    fs::create_dir(&primary).expect("primary");
    fs::create_dir_all(mount.join("Games")).expect("games");
    fs::create_dir(&outside).expect("outside");
    fs::write(outside.join("outside.bin"), b"outside").expect("outside file");
    symlink(&outside, mount.join("Games/link-like")).expect("link-like child");

    let provider = LocalFilesystemProviderImpl::default();
    provider
        .replace_mounted_volumes(&[
            MountedLocalFilesystemVolume::new(
                "primary".to_owned(),
                primary.to_string_lossy().into_owned(),
                "Internal storage".to_owned(),
                true,
                false,
            ),
            MountedLocalFilesystemVolume::new(
                "android-volume".to_owned(),
                mount.to_string_lossy().into_owned(),
                "Game card".to_owned(),
                false,
                true,
            ),
        ])
        .expect("mounted snapshot");
    let mounted_root = provider
        .list_browse_roots()
        .expect("browse roots")
        .into_iter()
        .find(|root| root.display_name() == "Game card")
        .expect("mounted browse root");
    let games_page = provider
        .list_browse_directories(mounted_root.location(), None, 10)
        .expect("games page");
    let games = games_page
        .directories()
        .iter()
        .find(|directory| directory.display_name() == "Games")
        .expect("games directory");
    let locator = provider
        .validate(&LocalFilesystemRootSelection::provider_selection(
            games.location().as_provider_value().to_owned(),
        ))
        .expect("provider selection")
        .locator()
        .clone();
    let access = provider.open_access(&locator).expect("source access");
    let resolved = access.resolve_root().expect("resolved root");
    let scope = access
        .enumerate_root_direct_children(&resolved, &|| false)
        .expect("root scope");
    let link_like = scope
        .observations()
        .iter()
        .find(|observation| observation.display_name() == "link-like")
        .expect("link-like observation");
    assert_eq!(link_like.observed_kind(), ObservedEntryKind::LinkLike);
    assert_eq!(
        access.enumerate_direct_children(&resolved, link_like.relative_locator(), &|| false),
        Err(SourceAccessError::InvalidLocator)
    );
}

#[test]
fn missing_provider_volume_makes_provider_selected_access_unavailable() {
    let directory = tempfile::tempdir().expect("tempdir");
    let primary = directory.path().join("primary");
    let mount = directory.path().join("mounted");
    fs::create_dir(&primary).expect("primary");
    fs::create_dir_all(mount.join("Games")).expect("games");
    let provider = LocalFilesystemProviderImpl::default();
    provider
        .replace_mounted_volumes(&[
            MountedLocalFilesystemVolume::new(
                "primary".to_owned(),
                primary.to_string_lossy().into_owned(),
                "Internal storage".to_owned(),
                true,
                false,
            ),
            MountedLocalFilesystemVolume::new(
                "android-volume".to_owned(),
                mount.to_string_lossy().into_owned(),
                "Game card".to_owned(),
                false,
                true,
            ),
        ])
        .expect("mounted snapshot");
    let mounted_root = provider
        .list_browse_roots()
        .expect("browse roots")
        .into_iter()
        .find(|root| root.display_name() == "Game card")
        .expect("mounted browse root");
    let games_page = provider
        .list_browse_directories(mounted_root.location(), None, 10)
        .expect("games page");
    let games = games_page
        .directories()
        .iter()
        .find(|directory| directory.display_name() == "Games")
        .expect("games directory");
    let locator = provider
        .validate(&LocalFilesystemRootSelection::provider_selection(
            games.location().as_provider_value().to_owned(),
        ))
        .expect("provider selection")
        .locator()
        .clone();

    provider
        .replace_mounted_volumes(&[MountedLocalFilesystemVolume::new(
            "primary".to_owned(),
            primary.to_string_lossy().into_owned(),
            "Internal storage".to_owned(),
            true,
            false,
        )])
        .expect("volume removal");
    let access = provider.open_access(&locator).expect("source access");
    assert_eq!(
        access.resolve_root(),
        Err(SourceAccessError::SourceUnavailable)
    );
}

#[test]
fn stable_android_relationships_remain_comparable_when_volume_is_absent() {
    let directory = tempfile::tempdir().expect("tempdir");
    let primary = directory.path().join("primary");
    let mount = directory.path().join("mount");
    fs::create_dir(&primary).expect("primary");
    fs::create_dir_all(mount.join("Games/SNES")).expect("nested removable root");
    let provider = LocalFilesystemProviderImpl::default();
    provider
        .replace_mounted_volumes(&[
            MountedLocalFilesystemVolume::new(
                "primary".to_owned(),
                primary.to_string_lossy().into_owned(),
                "Internal storage".to_owned(),
                true,
                false,
            ),
            MountedLocalFilesystemVolume::new(
                "removable-1".to_owned(),
                mount.to_string_lossy().into_owned(),
                "Game card".to_owned(),
                false,
                true,
            ),
        ])
        .expect("snapshot");
    let root = provider
        .list_browse_roots()
        .expect("roots")
        .into_iter()
        .find(|root| root.display_name() == "Game card")
        .expect("removable root");
    let games = provider
        .list_browse_directories(root.location(), None, 100)
        .expect("games page")
        .directories()[0]
        .location()
        .clone();
    let root_locator = provider
        .validate(&LocalFilesystemRootSelection::provider_selection(
            root.location().as_provider_value().to_owned(),
        ))
        .expect("root selection")
        .locator()
        .clone();
    let child_locator = provider
        .validate(&LocalFilesystemRootSelection::provider_selection(
            games.as_provider_value().to_owned(),
        ))
        .expect("child selection")
        .locator()
        .clone();
    provider
        .replace_mounted_volumes(&[MountedLocalFilesystemVolume::new(
            "primary".to_owned(),
            primary.to_string_lossy().into_owned(),
            "Internal storage".to_owned(),
            true,
            false,
        )])
        .expect("removable absent");

    assert_eq!(
        provider.compare_roots(&root_locator, &root_locator),
        RootRelationship::Same
    );
    assert_eq!(
        provider.compare_roots(&root_locator, &child_locator),
        RootRelationship::Ancestor
    );
}
