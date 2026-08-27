use argus_application::{
    ArchiveAdmissionError, ArchiveEligibility, DerivedEntryKey, DerivedEntryObservation,
    DerivedFingerprint, DerivedLocator, DerivedScopeIdentity, DerivedScopeOutcome, LibraryRootId,
    NativeIdentityMatch, NewSourceEntry, PersistenceError, RelativeSourceLocator, ScanRunId,
    SourceEntryCoordinates, SourceEntryId, SourceEntryKind, SourceEntryRecord,
    SourceEntryRepository, SourceLocatorKey, evaluate_archive_eligibility, reconcile_derived_scope,
};

fn id(value: &str) -> SourceEntryId {
    SourceEntryId::try_from(value).expect("source id")
}

fn root(value: &str) -> LibraryRootId {
    LibraryRootId::try_from(value).expect("root id")
}

fn scan(value: &str) -> ScanRunId {
    ScanRunId::try_from(value).expect("scan id")
}

fn observation(key: &str, name: &str, fingerprint: &str) -> DerivedEntryObservation {
    DerivedEntryObservation::new(
        DerivedLocator::from_transformation(format!("zip:{key}")),
        DerivedEntryKey::from_transformation(key.to_owned()),
        name.to_owned(),
        SourceEntryKind::File,
        Some(4),
        DerivedFingerprint::from_transformation(fingerprint.to_owned()),
    )
}

fn scope(parent: SourceEntryId) -> DerivedScopeIdentity<'static> {
    DerivedScopeIdentity {
        parent_source_entry_id: parent,
        transformation_id: "argus.transformation.zip.v1",
        transformation_revision: 1,
    }
}

#[test]
fn unchanged_derived_members_keep_ids_and_complete_scopes_remove_absent_members() {
    let parent = id("11111111111111111111111111111111");
    let mut repository = FakeRepository::new(root("22222222222222222222222222222222"));
    let first_observations = vec![
        observation("member:game", "game.gba", "fingerprint-game"),
        observation("member:readme", "README.txt", "fingerprint-readme"),
        observation("member:old", "old.nfo", "fingerprint-old"),
    ];
    let first = reconcile_derived_scope(
        &mut repository,
        &scope(parent),
        &first_observations,
        scan("33333333333333333333333333333333"),
        true,
        DerivedScopeOutcome::Complete,
    )
    .expect("first scope");

    let second = reconcile_derived_scope(
        &mut repository,
        &scope(parent),
        &first_observations[..2],
        scan("44444444444444444444444444444444"),
        true,
        DerivedScopeOutcome::Complete,
    )
    .expect("second scope");

    assert_eq!(&first[..2], second.as_slice());
    assert_eq!(repository.entries.len(), 2);
    assert_eq!(repository.finalized_scopes, 2);
    assert!(
        repository
            .entries
            .iter()
            .all(|entry| entry.derived_entry_key().is_some())
    );
}

#[test]
fn incomplete_or_unstable_scopes_never_authorize_absence() {
    let parent = id("11111111111111111111111111111111");
    let mut repository = FakeRepository::new(root("22222222222222222222222222222222"));
    let observations = vec![
        observation("member:game", "game.gba", "fingerprint-game"),
        observation("member:readme", "README.txt", "fingerprint-readme"),
    ];
    reconcile_derived_scope(
        &mut repository,
        &scope(parent),
        &observations,
        scan("33333333333333333333333333333333"),
        true,
        DerivedScopeOutcome::Complete,
    )
    .expect("seed scope");

    reconcile_derived_scope(
        &mut repository,
        &scope(parent),
        &observations[..1],
        scan("44444444444444444444444444444444"),
        true,
        DerivedScopeOutcome::Partial,
    )
    .expect("partial scope");
    assert_eq!(repository.entries.len(), 2);
    assert_eq!(repository.finalized_scopes, 1);

    reconcile_derived_scope(
        &mut repository,
        &scope(parent),
        &observations[..1],
        scan("55555555555555555555555555555555"),
        false,
        DerivedScopeOutcome::Complete,
    )
    .expect("unstable scope");
    assert_eq!(repository.entries.len(), 2);
    assert_eq!(repository.finalized_scopes, 1);
}

#[test]
fn archive_eligibility_ignores_sidecars_and_rejects_multiple_game_families_before_convergence() {
    assert_eq!(
        evaluate_archive_eligibility::<String>(&[]).expect("no game is not an error"),
        ArchiveEligibility::NoSupportedGame
    );
    assert_eq!(
        evaluate_archive_eligibility(&["game.gba".to_owned()]).expect("one game"),
        ArchiveEligibility::SingleGame("game.gba".to_owned())
    );
    assert_eq!(
        evaluate_archive_eligibility(&["mario.nes".to_owned(), "zelda.nes".to_owned()]),
        Err(ArchiveAdmissionError::MultiGameUnsupported)
    );
}

struct FakeRepository {
    root: LibraryRootId,
    entries: Vec<SourceEntryRecord>,
    finalized_scopes: usize,
}

impl FakeRepository {
    fn new(root: LibraryRootId) -> Self {
        Self {
            root,
            entries: Vec::new(),
            finalized_scopes: 0,
        }
    }
}

impl SourceEntryRepository for FakeRepository {
    fn upsert(&mut self, _entry: NewSourceEntry) -> Result<SourceEntryId, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn upsert_derived(&mut self, entry: NewSourceEntry) -> Result<SourceEntryId, PersistenceError> {
        let source_entry_id = entry
            .source_entry_id()
            .ok_or(PersistenceError::ConstraintViolation)?;
        let record = SourceEntryRecord::from_coordinates(
            source_entry_id,
            entry.parent_source_entry_id(),
            entry.display_name(),
            entry.display_location(),
            entry.kind(),
            entry.classification(),
            entry.coordinates().clone(),
            entry.last_observed_scan_id(),
        );
        if let Some(existing) = self
            .entries
            .iter_mut()
            .find(|existing| existing.source_entry_id() == source_entry_id)
        {
            *existing = record;
        } else {
            self.entries.push(record);
        }
        Ok(source_entry_id)
    }

    fn find_by_locator_key(
        &mut self,
        _library_root_id: LibraryRootId,
        _locator_key: &SourceLocatorKey,
    ) -> Result<Option<SourceEntryRecord>, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn find_derived_child(
        &mut self,
        parent: SourceEntryId,
        transformation_id: &str,
        revision: u32,
        key: &DerivedEntryKey,
    ) -> Result<Option<SourceEntryRecord>, PersistenceError> {
        Ok(self
            .entries
            .iter()
            .find(|entry| {
                entry.parent_source_entry_id() == Some(parent)
                    && entry.transformation_id() == Some(transformation_id)
                    && entry.transformation_revision() == Some(revision)
                    && entry.derived_entry_key() == Some(key)
            })
            .cloned())
    }

    fn find_native_identity(
        &mut self,
        _library_root_id: LibraryRootId,
        _provider_native_identity: &str,
    ) -> Result<NativeIdentityMatch, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn reconcile_move(
        &mut self,
        _entry: NewSourceEntry,
        _existing_source_entry_id: SourceEntryId,
    ) -> Result<SourceEntryId, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn list_children(
        &mut self,
        _library_root_id: LibraryRootId,
        _parent_source_entry_id: Option<SourceEntryId>,
        _offset: u32,
        _limit: u32,
    ) -> Result<Vec<SourceEntryRecord>, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn delete_subtree(
        &mut self,
        _library_root_id: LibraryRootId,
        _source_entry_id: SourceEntryId,
    ) -> Result<bool, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn finalize_absent_scope(
        &mut self,
        _library_root_id: LibraryRootId,
        _parent_source_entry_id: Option<SourceEntryId>,
        _observed_scan_id: ScanRunId,
    ) -> Result<u64, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn finalize_absent_derived_scope(
        &mut self,
        parent: SourceEntryId,
        transformation_id: &str,
        revision: u32,
        observation_run_id: ScanRunId,
    ) -> Result<u64, PersistenceError> {
        let before = self.entries.len();
        self.entries.retain(|entry| {
            !(entry.parent_source_entry_id() == Some(parent)
                && entry.transformation_id() == Some(transformation_id)
                && entry.transformation_revision() == Some(revision)
                && entry.last_observed_scan_id() != observation_run_id)
        });
        self.finalized_scopes += 1;
        Ok((before - self.entries.len()) as u64)
    }

    fn delete_for_root(&mut self, _library_root_id: LibraryRootId) -> Result<(), PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn library_root_id_for_entry(
        &mut self,
        _source_entry_id: SourceEntryId,
    ) -> Result<LibraryRootId, PersistenceError> {
        Ok(self.root)
    }
}

#[allow(dead_code)]
fn _provider_coordinate_type_is_still_distinct() {
    let _ = SourceEntryCoordinates::Provider {
        relative_locator: RelativeSourceLocator::from_provider("unused".to_owned()),
        locator_key: SourceLocatorKey::from_provider("unused".to_owned()),
        provider_native_identity: None,
        source_fingerprint: None,
    };
}
