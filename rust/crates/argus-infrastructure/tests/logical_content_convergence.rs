#![cfg(feature = "test-support")]

use argus_application::{
    ContentIdentity, ContentType, GameListCursor, GetGameResult, IdentificationService,
    IdentityConvergenceStore, IdentityDigest, LibraryRootAvailability, LibraryRootRepository,
    LibrarySourceAccess, ListGamesQuery, LogicalContentUnitOfWork, LogicalLibraryQueries,
    OperationContext, OperationName, PlatformId, RelativeSourceLocator, RootLocator,
    SourceEntryRepository, SourceVersionEvidence, SubsystemName, TraceId, UnitOfWork,
    ValidatedContentDerivation,
};
use argus_infrastructure::content::ContentReader;
use argus_infrastructure::local_filesystem::LocalFilesystemSourceAccess;
use argus_infrastructure::sqlite::{SqliteDatabaseExecutor, SqliteValue};
use tempfile::tempdir;

fn context() -> OperationContext {
    OperationContext::new(
        TraceId::try_from(131_u128).expect("trace"),
        SubsystemName::try_from("logical").expect("subsystem"),
        OperationName::try_from("convergence").expect("operation"),
    )
}

fn derivation(source: &str, scan: &str, fingerprint: &str) -> ValidatedContentDerivation {
    derivation_with_digest(source, scan, fingerprint, 9, "Fallback Game Boy")
}

fn derivation_with_digest(
    source: &str,
    scan: &str,
    fingerprint: &str,
    digest_byte: u8,
    display_title: &str,
) -> ValidatedContentDerivation {
    let source_entry_id = argus_application::SourceEntryId::try_from(source).expect("source");
    ValidatedContentDerivation::new(
        source_entry_id,
        SourceVersionEvidence::new(
            source_entry_id,
            Some(fingerprint.to_owned()),
            argus_application::ScanRunId::try_from(scan).expect("scan"),
        ),
        PlatformId::NintendoGb,
        ContentType::CartridgeImage,
        ContentIdentity::new(
            "argus.content.identity.nintendo-gb.cartridge.v1",
            1,
            IdentityDigest::from_bytes([digest_byte; 32]),
        ),
        "raw".to_owned(),
        display_title.to_owned(),
    )
}

fn converge(
    executor: &SqliteDatabaseExecutor,
    derivation: ValidatedContentDerivation,
) -> argus_application::ConvergenceOutcome {
    executor
        .with_unit_of_work(context(), move |mut work| {
            let outcome = {
                let mut logical = work.logical_content();
                logical
                    .converge_identity(&derivation)
                    .map_err(argus_application::ApplicationPortError::from)?
            };
            work.commit()?;
            Ok(outcome)
        })
        .expect("convergence")
}

fn seed_source(
    executor: &SqliteDatabaseExecutor,
    root: &str,
    job: &str,
    scan: &str,
    source: &str,
    fingerprint: &str,
) {
    let root = root.to_owned();
    let job = job.to_owned();
    let scan = scan.to_owned();
    let source = source.to_owned();
    let fingerprint = fingerprint.to_owned();
    executor
        .with_connection_for_tests(context(), move |connection| {
            connection.execute_with_values(
                "INSERT OR IGNORE INTO library_source
                    (library_source_id, source_provider_type, display_name, provider_config,
                     config_revision, created_at, updated_at)
                 VALUES (?1, 'local_filesystem', 'Local', '{}', 1, 1, 1)",
                &[SqliteValue::Text(
                    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".to_owned(),
                )],
            )?;
            connection.execute_with_values(
                "INSERT OR IGNORE INTO library_root
                    (library_root_id, library_source_id, root_locator, display_name,
                     safe_location_presentation, availability_status, config_revision,
                     created_at, updated_at)
                 VALUES (?1, ?2, '/tmp/argus', 'Root', '/tmp/argus', 'available', 1, 1, 1)",
                &[
                    SqliteValue::Text(root.clone()),
                    SqliteValue::Text("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".to_owned()),
                ],
            )?;
            connection.execute_with_values(
                "INSERT OR IGNORE INTO job_run
                    (job_run_id, operation_type, state, created_at)
                 VALUES (?1, 'library_scan', 'completed', 1)",
                &[SqliteValue::Text(job.clone())],
            )?;
            connection.execute_with_values(
                "INSERT OR IGNORE INTO scan_run
                    (scan_run_id, job_run_id, historical_library_root_id, root_locator,
                     root_display_name, safe_location_display, source_config_revision,
                     root_config_revision, status, started_at)
                 VALUES (?1, ?2, ?3, '/tmp/argus', 'Root', '/tmp/argus', 1, 1, 'complete', 1)",
                &[
                    SqliteValue::Text(scan.clone()),
                    SqliteValue::Text(job.clone()),
                    SqliteValue::Text(root.clone()),
                ],
            )?;
            connection.execute_with_values(
                "INSERT OR IGNORE INTO source_entry
                    (source_entry_id, library_root_id, relative_locator, locator_key,
                     display_name, display_location, kind, classification,
                     source_fingerprint, last_observed_scan_id, created_at, updated_at)
                 VALUES (?1, ?2, ?3, ?3, 'game.gb', 'game.gb', 'file',
                         'content_candidate', ?4, ?5, 1, 1)",
                &[
                    SqliteValue::Text(source.clone()),
                    SqliteValue::Text(root.clone()),
                    SqliteValue::Text(source.clone()),
                    SqliteValue::Text(fingerprint.clone()),
                    SqliteValue::Text(scan.clone()),
                ],
            )?;
            Ok(())
        })
        .expect("seed source");
}

#[test]
fn duplicate_identity_converges_to_one_content_and_game_with_two_sources() {
    let directory = tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("logical.sqlite3")).expect("database");
    let root = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    let job = "cccccccccccccccccccccccccccccccc";
    let scan_one = "dddddddddddddddddddddddddddddddd";
    let scan_two = "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee";
    let source_one = "11111111111111111111111111111111";
    let source_two = "22222222222222222222222222222222";
    seed_source(&executor, root, job, scan_one, source_one, "v1:32:1");
    seed_source(&executor, root, job, scan_two, source_two, "v1:32:2");

    let first = derivation(source_one, scan_one, "v1:32:1");
    let first_outcome = executor
        .with_unit_of_work(context(), move |mut work| {
            let outcome = {
                let mut logical = work.logical_content();
                assert!(
                    logical
                        .source_version_matches(first.source_version())
                        .map_err(argus_application::ApplicationPortError::from)?
                );
                logical
                    .converge_identity(&first)
                    .map_err(argus_application::ApplicationPortError::from)?
            };
            work.commit()?;
            Ok(outcome)
        })
        .expect("first convergence");
    let game_id = match first_outcome {
        argus_application::ConvergenceOutcome::Created { game_id, .. }
        | argus_application::ConvergenceOutcome::Attached { game_id, .. } => game_id,
    };

    let second = derivation(source_two, scan_two, "v1:32:2");
    executor
        .with_unit_of_work(context(), move |mut work| {
            let outcome = {
                let mut logical = work.logical_content();
                logical
                    .converge_identity(&second)
                    .map_err(argus_application::ApplicationPortError::from)?
            };
            work.commit()?;
            Ok(outcome)
        })
        .expect("duplicate convergence");

    let counts = executor
        .with_connection_for_tests(context(), |connection| {
            Ok((
                connection.scalar_i64("SELECT COUNT(*) FROM game_content")?,
                connection.scalar_i64("SELECT COUNT(*) FROM game")?,
                connection
                    .scalar_i64("SELECT COUNT(*) FROM game_membership WHERE is_current = 1")?,
                connection
                    .scalar_i64("SELECT COUNT(*) FROM game_content_source WHERE is_current = 1")?,
                connection.scalar_i64("SELECT source_count FROM game_library_row")?,
            ))
        })
        .expect("counts");
    assert_eq!(counts, (1, 1, 1, 2, 2));

    let detail = executor
        .with_unit_of_work(context(), move |mut work| {
            let result = {
                let mut logical = work.logical_content();
                logical
                    .get_game(game_id)
                    .map_err(argus_application::ApplicationPortError::from)?
            };
            work.rollback()?;
            Ok(result)
        })
        .expect("duplicate detail");
    let GetGameResult::Found(detail) = detail else {
        panic!("duplicate game must remain addressable");
    };
    let summary = &detail.content()[0];
    assert_eq!(summary.source_count(), 2);
    assert_eq!(
        summary
            .provenance()
            .expect("current identity has proving source")
            .source_entry_id(),
        argus_application::SourceEntryId::try_from(source_one).expect("first source")
    );
    executor.shutdown().expect("shutdown");
}

#[test]
fn ambiguous_retained_identity_does_not_reconnect_arbitrarily() {
    let directory = tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("logical.sqlite3")).expect("database");
    let root = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    let job = "cccccccccccccccccccccccccccccccc";
    let scan = "dddddddddddddddddddddddddddddddd";
    let source = "11111111111111111111111111111111";
    seed_source(&executor, root, job, scan, source, "v1:32:1");

    executor
        .with_connection_for_tests(context(), |connection| {
            for (content_id, identity_id) in [
                (
                    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1",
                ),
                (
                    "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                    "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb2",
                ),
            ] {
                connection.execute_with_values(
                    "INSERT INTO game_content
                        (game_content_id, platform_id, content_type, presence_state,
                         identification_state, grouping_revision, created_at, updated_at)
                     VALUES (?1, 'nintendo.gb', 'CartridgeImage', 'orphaned',
                             'needs_reidentification', 1, '1', '1')",
                    &[SqliteValue::Text(content_id.to_owned())],
                )?;
                connection.execute_with_values(
                    "INSERT INTO content_identity
                        (content_identity_id, game_content_id, scheme_id, identity_revision,
                         identity_value, is_current, created_at, updated_at)
                     VALUES (?1, ?2, 'argus.content.identity.nintendo-gb.cartridge.v1',
                             1, ?3, 0, '1', '1')",
                    &[
                        SqliteValue::Text(identity_id.to_owned()),
                        SqliteValue::Text(content_id.to_owned()),
                        SqliteValue::Text("09".repeat(32)),
                    ],
                )?;
            }
            Ok(())
        })
        .expect("historical retained evidence");

    let outcome = converge(&executor, derivation(source, scan, "v1:32:1"));
    assert!(
        matches!(
            outcome,
            argus_application::ConvergenceOutcome::Created { .. }
        ),
        "ambiguous historical evidence must create under ordinary conflict policy"
    );

    let counts = executor
        .with_connection_for_tests(context(), |connection| {
            Ok((
                connection.scalar_i64("SELECT COUNT(*) FROM game_content")?,
                connection
                    .scalar_i64("SELECT COUNT(*) FROM content_identity WHERE is_current = 1")?,
                connection
                    .scalar_i64("SELECT COUNT(*) FROM content_identity WHERE is_current = 0")?,
            ))
        })
        .expect("ambiguous counts");
    assert_eq!(counts, (3, 1, 2));
    executor.shutdown().expect("shutdown");
}

#[test]
fn temporary_root_unavailability_preserves_identity_and_active_game() {
    let directory = tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("logical.sqlite3")).expect("database");
    let root = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    let job = "cccccccccccccccccccccccccccccccc";
    let scan = "dddddddddddddddddddddddddddddddd";
    let source = "11111111111111111111111111111111";
    seed_source(&executor, root, job, scan, source, "v1:32:1");
    let derivation = derivation(source, scan, "v1:32:1");
    let game_id = executor
        .with_unit_of_work(context(), move |mut work| {
            let outcome = {
                let mut logical = work.logical_content();
                logical
                    .converge_identity(&derivation)
                    .map_err(argus_application::ApplicationPortError::from)?
            };
            work.commit()?;
            Ok(match outcome {
                argus_application::ConvergenceOutcome::Created { game_id, .. }
                | argus_application::ConvergenceOutcome::Attached { game_id, .. } => game_id,
            })
        })
        .expect("convergence");

    executor
        .with_unit_of_work(context(), move |mut work| {
            let root_id = argus_application::LibraryRootId::try_from(root).expect("root");
            work.library_roots()
                .set_availability(root_id, LibraryRootAvailability::Unavailable)
                .map_err(argus_application::ApplicationPortError::from)?;
            work.commit()?;
            Ok(())
        })
        .expect("temporary unavailability");

    let detail = executor
        .with_unit_of_work(context(), move |mut work| {
            let result = {
                let mut logical = work.logical_content();
                logical
                    .get_game(game_id)
                    .map_err(argus_application::ApplicationPortError::from)?
            };
            work.rollback()?;
            Ok(result)
        })
        .expect("get unavailable game");
    let GetGameResult::Found(detail) = detail else {
        panic!("temporarily unavailable game remains addressable");
    };
    assert_eq!(
        detail.content()[0].presence(),
        argus_domain::GameContentPresence::Unavailable
    );
    assert_eq!(
        detail.content()[0].identification(),
        argus_domain::IdentificationState::Identified
    );
    assert_eq!(detail.lifecycle(), argus_domain::GameLifecycle::Active);
    assert_eq!(
        detail.availability_state(),
        argus_domain::AvailabilityState::Unavailable
    );
    executor.shutdown().expect("shutdown");
}

#[test]
fn independent_reidentification_reactivates_orphaned_content_and_game() {
    let directory = tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("logical.sqlite3")).expect("database");
    let root = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    let job_one = "cccccccccccccccccccccccccccccccc";
    let scan_one = "dddddddddddddddddddddddddddddddd";
    let source_one = "11111111111111111111111111111111";
    seed_source(&executor, root, job_one, scan_one, source_one, "v1:32:1");
    let first = derivation(source_one, scan_one, "v1:32:1");
    let (content_id, game_id) = executor
        .with_unit_of_work(context(), move |mut work| {
            let outcome = {
                let mut logical = work.logical_content();
                logical
                    .converge_identity(&first)
                    .map_err(argus_application::ApplicationPortError::from)?
            };
            work.commit()?;
            Ok(match outcome {
                argus_application::ConvergenceOutcome::Created {
                    game_content_id,
                    game_id,
                }
                | argus_application::ConvergenceOutcome::Attached {
                    game_content_id,
                    game_id,
                } => (game_content_id, game_id),
            })
        })
        .expect("first convergence");

    let root_for_delete = root.to_owned();
    let source_for_delete = source_one.to_owned();
    executor
        .with_unit_of_work(context(), move |mut work| {
            let root_id =
                argus_application::LibraryRootId::try_from(root_for_delete.as_str()).expect("root");
            let source_id = argus_application::SourceEntryId::try_from(source_for_delete.as_str())
                .expect("source");
            work.source_entries()
                .delete_subtree(root_id, source_id)
                .map_err(argus_application::ApplicationPortError::from)?;
            work.commit()?;
            Ok(())
        })
        .expect("final absence");

    let job_two = "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee";
    let scan_two = "ffffffffffffffffffffffffffffffff";
    let source_two = "22222222222222222222222222222222";
    seed_source(&executor, root, job_two, scan_two, source_two, "v1:32:2");
    let second = derivation(source_two, scan_two, "v1:32:2");
    let reidentified = executor
        .with_unit_of_work(context(), move |mut work| {
            let outcome = {
                let mut logical = work.logical_content();
                logical
                    .source_version_matches(second.source_version())
                    .map_err(argus_application::ApplicationPortError::from)?;
                logical
                    .converge_identity(&second)
                    .map_err(argus_application::ApplicationPortError::from)?
            };
            work.commit()?;
            Ok(outcome)
        })
        .expect("independent re-identification");
    assert_eq!(
        reidentified,
        argus_application::ConvergenceOutcome::Attached {
            game_content_id: content_id,
            game_id,
        }
    );

    let counts = executor
        .with_connection_for_tests(context(), |connection| {
            Ok((
                connection.scalar_i64("SELECT COUNT(*) FROM game_content")?,
                connection.scalar_i64("SELECT COUNT(*) FROM game")?,
                connection
                    .scalar_i64("SELECT COUNT(*) FROM game_content_source WHERE is_current = 1")?,
                connection
                    .scalar_i64("SELECT COUNT(*) FROM content_identity WHERE is_current = 1")?,
            ))
        })
        .expect("reidentification counts");
    assert_eq!(counts, (1, 1, 1, 1));
    executor.shutdown().expect("shutdown");
}

#[test]
fn final_source_absence_separates_orphan_presence_from_reidentification_state() {
    let directory = tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("logical.sqlite3")).expect("database");
    let root = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    let job = "cccccccccccccccccccccccccccccccc";
    let scan = "dddddddddddddddddddddddddddddddd";
    let source = "11111111111111111111111111111111";
    seed_source(&executor, root, job, scan, source, "v1:32:1");
    let derivation = derivation(source, scan, "v1:32:1");

    let created = executor
        .with_unit_of_work(context(), move |mut work| {
            let outcome = {
                let mut logical = work.logical_content();
                logical
                    .converge_identity(&derivation)
                    .map_err(argus_application::ApplicationPortError::from)?
            };
            work.commit()?;
            Ok(outcome)
        })
        .expect("convergence");
    let game_id = match created {
        argus_application::ConvergenceOutcome::Created { game_id, .. } => game_id,
        _ => panic!("expected a new provisional game"),
    };

    executor
        .with_unit_of_work(context(), move |mut work| {
            let root_id = argus_application::LibraryRootId::try_from(root).expect("root");
            let source_id = argus_application::SourceEntryId::try_from(source).expect("source");
            work.source_entries()
                .delete_subtree(root_id, source_id)
                .map_err(argus_application::ApplicationPortError::from)?;
            work.commit()?;
            Ok(())
        })
        .expect("final absence");

    let detail = executor
        .with_unit_of_work(context(), move |mut work| {
            let result = {
                let mut logical = work.logical_content();
                logical
                    .get_game(game_id)
                    .map_err(argus_application::ApplicationPortError::from)?
            };
            work.rollback()?;
            Ok(result)
        })
        .expect("get orphaned game");
    let GetGameResult::Found(detail) = detail else {
        panic!("orphaned games remain addressable by GetGame");
    };
    assert_eq!(
        detail.content()[0].presence(),
        argus_domain::GameContentPresence::Orphaned
    );
    assert_eq!(
        detail.content()[0].identification(),
        argus_domain::IdentificationState::NeedsReidentification
    );
    assert_eq!(
        detail.lifecycle(),
        argus_domain::GameLifecycle::InactiveOrphan
    );
    assert_eq!(
        detail.availability_state(),
        argus_domain::AvailabilityState::InactiveOrphan
    );

    executor.shutdown().expect("shutdown");
}

#[test]
fn source_version_mismatch_returns_published_source_changed_error_without_convergence() {
    let directory = tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("logical.sqlite3")).expect("database");
    let root = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    let job = "cccccccccccccccccccccccccccccccc";
    let scan = "dddddddddddddddddddddddddddddddd";
    let source = "11111111111111111111111111111111";
    seed_source(&executor, root, job, scan, source, "v1:32:actual");
    let derivation = derivation(source, scan, "v1:32:snapshot");

    let error_code = executor
        .with_unit_of_work(context(), move |mut work| {
            let result = {
                let mut logical = work.logical_content();
                IdentificationService::converge(&mut logical, derivation, context())
            };
            work.rollback()?;
            Ok(result.expect_err("source change must fail").code)
        })
        .expect("callback completes");
    assert_eq!(
        error_code,
        argus_application::ErrorCode::OperationSourceChangedDuringProcessing
    );

    let counts = executor
        .with_connection_for_tests(context(), |connection| {
            Ok((
                connection.scalar_i64("SELECT COUNT(*) FROM game_content")?,
                connection.scalar_i64("SELECT COUNT(*) FROM game")?,
            ))
        })
        .expect("counts");
    assert_eq!(counts, (0, 0));
    executor.shutdown().expect("shutdown");
}

#[test]
fn changed_local_source_evidence_reaches_source_changed_error_without_persistence() {
    let directory = tempdir().expect("tempdir");
    let source_path = directory.path().join("changed.bin");
    std::fs::write(&source_path, b"scan snapshot").expect("write initial source");

    let locator = RootLocator::from_provider(directory.path().to_string_lossy().into_owned());
    let access = LocalFilesystemSourceAccess::new(&locator);
    let root = access.resolve_root().expect("resolve source root");
    let initial_reader = access
        .open_entry_reader(
            &root,
            &RelativeSourceLocator::from_provider("changed.bin".to_owned()),
        )
        .expect("open initial source reader");
    let initial_fingerprint = initial_reader.source_fingerprint().to_owned();
    drop(initial_reader);

    std::fs::write(&source_path, b"source changed after the scan snapshot").expect("mutate source");

    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("logical.sqlite3")).expect("database");
    let root_id = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    let job = "cccccccccccccccccccccccccccccccc";
    let scan = "dddddddddddddddddddddddddddddddd";
    let source = "11111111111111111111111111111111";
    seed_source(&executor, root_id, job, scan, source, &initial_fingerprint);

    let mut current_reader = access
        .open_entry_reader(
            &root,
            &RelativeSourceLocator::from_provider("changed.bin".to_owned()),
        )
        .expect("open changed source reader");
    let mut observed = [0_u8; 8];
    current_reader
        .read_at(0, &mut observed)
        .expect("read changed source");
    let current_fingerprint = current_reader.source_fingerprint().to_owned();
    assert_ne!(current_fingerprint, initial_fingerprint);

    let source_entry_id = argus_application::SourceEntryId::try_from(source).expect("source");
    let derivation = ValidatedContentDerivation::new(
        source_entry_id,
        SourceVersionEvidence::new(
            source_entry_id,
            Some(current_fingerprint),
            argus_application::ScanRunId::try_from(scan).expect("scan"),
        ),
        PlatformId::NintendoGb,
        ContentType::CartridgeImage,
        ContentIdentity::new(
            "argus.content.identity.nintendo-gb.cartridge.v1",
            1,
            IdentityDigest::from_bytes([7; 32]),
        ),
        "raw".to_owned(),
        "changed.bin".to_owned(),
    );

    let error_code = executor
        .with_unit_of_work(context(), move |mut work| {
            let result = {
                let mut logical = work.logical_content();
                IdentificationService::converge(&mut logical, derivation, context())
            };
            work.rollback()?;
            Ok(result.expect_err("changed source must fail").code)
        })
        .expect("callback completes");
    assert_eq!(
        error_code,
        argus_application::ErrorCode::OperationSourceChangedDuringProcessing
    );

    let counts = executor
        .with_connection_for_tests(context(), |connection| {
            Ok((
                connection.scalar_i64("SELECT COUNT(*) FROM game_content")?,
                connection.scalar_i64("SELECT COUNT(*) FROM content_identity")?,
            ))
        })
        .expect("counts");
    assert_eq!(counts, (0, 0));
    executor.shutdown().expect("shutdown");
}

#[test]
fn baseline_list_and_get_use_durable_projection_only() {
    let directory = tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("logical.sqlite3")).expect("database");
    let root = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    let job = "cccccccccccccccccccccccccccccccc";
    let scan = "dddddddddddddddddddddddddddddddd";
    let source = "11111111111111111111111111111111";
    seed_source(&executor, root, job, scan, source, "v1:32:1");
    let derivation = derivation(source, scan, "v1:32:1");
    let page = executor
        .with_unit_of_work(context(), move |mut work| {
            let page = {
                let mut logical = work.logical_content();
                logical
                    .converge_identity(&derivation)
                    .map_err(argus_application::ApplicationPortError::from)?;
                logical
                    .list_games(
                        &ListGamesQuery::builder()
                            .page_size(10)
                            .build()
                            .expect("query"),
                    )
                    .map_err(argus_application::ApplicationPortError::from)?
            };
            work.commit()?;
            Ok(page)
        })
        .expect("list");
    assert_eq!(page.items().len(), 1);
    assert_eq!(
        page.items()[0].hydration_state(),
        argus_domain::HydrationState::PartiallyHydrated
    );
    assert!(page.next_cursor().is_none());
    executor.shutdown().expect("shutdown");
}

#[test]
fn baseline_list_uses_opaque_keyset_cursor_paging() {
    let directory = tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("logical.sqlite3")).expect("database");
    let root = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    let job = "cccccccccccccccccccccccccccccccc";
    let entries = [
        (
            "dddddddddddddddddddddddddddddddd",
            "11111111111111111111111111111111",
            "v1:32:1",
            1,
            "Alpha Game",
        ),
        (
            "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
            "22222222222222222222222222222222",
            "v1:32:2",
            2,
            "Bravo Game",
        ),
        (
            "ffffffffffffffffffffffffffffffff",
            "33333333333333333333333333333333",
            "v1:32:3",
            3,
            "Charlie Game",
        ),
    ];
    for (scan, source, fingerprint, digest_byte, title) in entries {
        seed_source(&executor, root, job, scan, source, fingerprint);
        converge(
            &executor,
            derivation_with_digest(source, scan, fingerprint, digest_byte, title),
        );
    }

    let first_page = executor
        .with_unit_of_work(context(), |mut work| {
            let page = {
                let mut logical = work.logical_content();
                logical
                    .list_games(
                        &ListGamesQuery::builder()
                            .page_size(2)
                            .build()
                            .expect("query"),
                    )
                    .map_err(argus_application::ApplicationPortError::from)?
            };
            work.rollback()?;
            Ok(page)
        })
        .expect("first page");
    assert_eq!(
        first_page
            .items()
            .iter()
            .map(|row| row.display_title())
            .collect::<Vec<_>>(),
        vec!["Alpha Game", "Bravo Game"]
    );
    let cursor = first_page.next_cursor().cloned().expect("next cursor");
    let external_cursor = cursor.as_str().to_owned();
    assert!(external_cursor.starts_with("v1:"));
    assert!(!external_cursor.contains("Alpha Game"));
    let parsed_cursor = GameListCursor::try_from_external(external_cursor).expect("opaque cursor");

    let second_page = executor
        .with_unit_of_work(context(), move |mut work| {
            let page = {
                let mut logical = work.logical_content();
                logical
                    .list_games(
                        &ListGamesQuery::builder()
                            .cursor(Some(parsed_cursor))
                            .page_size(2)
                            .build()
                            .expect("query"),
                    )
                    .map_err(argus_application::ApplicationPortError::from)?
            };
            work.rollback()?;
            Ok(page)
        })
        .expect("second page");
    assert_eq!(second_page.items().len(), 1);
    assert_eq!(second_page.items()[0].display_title(), "Charlie Game");
    assert!(second_page.next_cursor().is_none());
    executor.shutdown().expect("shutdown");
}

#[test]
fn get_game_returns_redirects_and_missing_games_without_broadening_detail() {
    let directory = tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("logical.sqlite3")).expect("database");
    let root = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    let job = "cccccccccccccccccccccccccccccccc";
    let scan_one = "dddddddddddddddddddddddddddddddd";
    let scan_two = "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee";
    let source_one = "11111111111111111111111111111111";
    let source_two = "22222222222222222222222222222222";
    seed_source(&executor, root, job, scan_one, source_one, "v1:32:1");
    seed_source(&executor, root, job, scan_two, source_two, "v1:32:2");
    let first = converge(
        &executor,
        derivation_with_digest(source_one, scan_one, "v1:32:1", 1, "Canonical Game"),
    );
    let second = converge(
        &executor,
        derivation_with_digest(source_two, scan_two, "v1:32:2", 2, "Redirected Game"),
    );
    let first_game = match first {
        argus_application::ConvergenceOutcome::Created { game_id, .. }
        | argus_application::ConvergenceOutcome::Attached { game_id, .. } => game_id,
    };
    let canonical_game = match second {
        argus_application::ConvergenceOutcome::Created { game_id, .. }
        | argus_application::ConvergenceOutcome::Attached { game_id, .. } => game_id,
    };

    executor
        .with_connection_for_tests(context(), move |connection| {
            connection.execute_with_values(
                "INSERT INTO game_redirect
                    (game_id, canonical_game_id, created_at)
                 VALUES (?1, ?2, 1)",
                &[
                    SqliteValue::Text(first_game.to_string()),
                    SqliteValue::Text(canonical_game.to_string()),
                ],
            )?;
            Ok(())
        })
        .expect("redirect");

    let redirected = executor
        .with_unit_of_work(context(), move |mut work| {
            let result = {
                let mut logical = work.logical_content();
                logical
                    .get_game(first_game)
                    .map_err(argus_application::ApplicationPortError::from)?
            };
            work.rollback()?;
            Ok(result)
        })
        .expect("redirected lookup");
    assert_eq!(redirected, GetGameResult::Redirected(canonical_game));

    let missing = executor
        .with_unit_of_work(context(), move |mut work| {
            let result = {
                let mut logical = work.logical_content();
                logical
                    .get_game(
                        argus_application::GameId::try_from("eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee")
                            .expect("missing game"),
                    )
                    .map_err(argus_application::ApplicationPortError::from)?
            };
            work.rollback()?;
            Ok(result)
        })
        .expect("missing lookup");
    assert_eq!(missing, GetGameResult::NotFound);
    executor.shutdown().expect("shutdown");
}
