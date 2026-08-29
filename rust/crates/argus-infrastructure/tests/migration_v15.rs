#![cfg(feature = "test-support")]

use argus_application::{
    ApplicationPortError, JobRunRepository, LibraryRootAvailability, LibraryRootRepository,
    LibrarySourceRepository, NewJobRun, NewLibraryRoot, NewScanRun, OperationContext,
    OperationName, RootLocator, ScanRunRepository, SourceEntryId, SubsystemName, TraceId,
    UnitOfWork, UnitOfWorkFactory,
};
use argus_infrastructure::sqlite::{
    Migration, MigrationRegistry, SqliteDatabaseExecutor, SqliteValue,
};
use tempfile::tempdir;

fn context() -> OperationContext {
    OperationContext::new(
        TraceId::try_from(15_u128).expect("trace id"),
        SubsystemName::try_from("test").expect("subsystem"),
        OperationName::try_from("migration_test").expect("operation"),
    )
}

fn registry_v14() -> MigrationRegistry {
    MigrationRegistry::new(vec![
        Migration::sql(
            1,
            "0001_initial",
            include_bytes!("../src/sqlite/migrations/sql/0001_initial.sql"),
        ),
        Migration::sql(
            2,
            "0002_sources",
            include_bytes!("../src/sqlite/migrations/sql/0002_sources.sql"),
        ),
        Migration::sql(
            3,
            "0003_jobs_scans",
            include_bytes!("../src/sqlite/migrations/sql/0003_jobs_scans.sql"),
        ),
        Migration::sql(
            4,
            "0004_source_reconciliation",
            include_bytes!("../src/sqlite/migrations/sql/0004_source_reconciliation.sql"),
        ),
        Migration::sql(
            5,
            "0005_source_hierarchy",
            include_bytes!("../src/sqlite/migrations/sql/0005_source_hierarchy.sql"),
        ),
        Migration::sql(
            6,
            "0006_retry_and_progress",
            include_bytes!("../src/sqlite/migrations/sql/0006_retry_and_progress.sql"),
        ),
        Migration::sql(
            7,
            "0007_scan_all_recovery",
            include_bytes!("../src/sqlite/migrations/sql/0007_scan_all_recovery.sql"),
        ),
        Migration::sql(
            8,
            "0008_logical_library",
            include_bytes!("../src/sqlite/migrations/sql/0008_logical_library.sql"),
        ),
        Migration::sql(
            9,
            "0009_metadata_providers_and_artwork",
            include_bytes!("../src/sqlite/migrations/sql/0009_metadata_providers_and_artwork.sql"),
        ),
        Migration::sql(
            10,
            "0010_phase_003_product_state",
            include_bytes!("../src/sqlite/migrations/sql/0010_phase_003_product_state.sql"),
        ),
        Migration::sql(
            11,
            "0011_phase_003_refresh_invocation",
            include_bytes!("../src/sqlite/migrations/sql/0011_phase_003_refresh_invocation.sql"),
        ),
        Migration::sql(
            12,
            "0012_content_identity_catalog_expansion",
            include_bytes!(
                "../src/sqlite/migrations/sql/0012_content_identity_catalog_expansion.sql"
            ),
        ),
        Migration::sql(
            13,
            "0013_optical_content_and_provenance",
            include_bytes!("../src/sqlite/migrations/sql/0013_optical_content_and_provenance.sql"),
        ),
        Migration::sql(
            14,
            "0014_derived_source_entries",
            include_bytes!("../src/sqlite/migrations/sql/0014_derived_source_entries.sql"),
        ),
    ])
    .expect("v14 registry")
}

#[test]
fn migration_v15_adds_bounded_library_projection_columns_and_indexes() {
    let directory = tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("logical.sqlite3")).expect("database");

    assert_eq!(executor.migration_summary().current_version, 17);

    executor
        .with_connection_for_tests(context(), |connection| {
            for column in [
                "presentation_region",
                "selected_cover_asset_id",
                "release_date",
                "search_text",
            ] {
                let present = connection.scalar_i64(&format!(
                    "SELECT EXISTS(
                        SELECT 1 FROM pragma_table_info('game_library_row')
                        WHERE name = '{column}'
                    )"
                ))?;
                assert_eq!(present, 1, "missing column {column}");
            }
            Ok(())
        })
        .expect("columns");

    executor
        .with_connection_for_tests(context(), |connection| {
            for index in [
                "idx_game_library_row_search",
                "idx_game_library_row_platform",
                "idx_game_library_row_release_date",
                "idx_game_library_row_release_date_desc",
                "idx_game_library_row_updated_at",
                "idx_game_library_row_updated_at_desc",
            ] {
                let present = connection.scalar_i64(&format!(
                    "SELECT EXISTS(
                        SELECT 1 FROM sqlite_master
                        WHERE type = 'index' AND name = '{index}'
                    )"
                ))?;
                assert_eq!(present, 1, "missing index {index}");
            }
            let release_index = connection.scalar_text(
                "SELECT sql FROM sqlite_master
                 WHERE type = 'index' AND name = 'idx_game_library_row_release_date'",
            )?;
            assert!(release_index.contains("CASE WHEN release_date IS NULL THEN 1 ELSE 0 END"));
            assert!(release_index.contains("platform_id"));
            let updated_index = connection.scalar_text(
                "SELECT sql FROM sqlite_master
                 WHERE type = 'index' AND name = 'idx_game_library_row_updated_at'",
            )?;
            assert!(updated_index.contains("strftime('%s', updated_at)"));
            Ok(())
        })
        .expect("indexes");

    executor.shutdown().expect("shutdown");
}

#[test]
fn migration_v15_preserves_populated_logical_and_enrichment_identity() {
    let directory = tempdir().expect("tempdir");
    let database = directory.path().join("populated-v14.sqlite3");
    let old = SqliteDatabaseExecutor::open_with_registry(&database, registry_v14())
        .expect("v14 database");

    let (root, scan) = old
        .execute(&context(), move |mut scope| {
            let source = scope.library_source().ensure_local_filesystem_source()?;
            let root = scope.library_roots().insert(NewLibraryRoot::new(
                source,
                RootLocator::from_provider("/library/Games".to_owned()),
                "Games".to_owned(),
                "/library/Games".to_owned(),
                LibraryRootAvailability::Available,
                1,
            ))?;
            let job = scope
                .job_runs()
                .insert(NewJobRun::new("library_scan", 1_000))?;
            let scan = scope.scan_runs().insert(NewScanRun::new(
                job,
                root,
                RootLocator::from_provider("/library/Games".to_owned()),
                "Games",
                "/library/Games",
                1,
                1,
                1_000,
            ))?;
            scope.commit()?;
            Ok::<_, ApplicationPortError>((root, scan))
        })
        .expect("seed v14 root and scan");

    let game_id = "11111111111111111111111111111111";
    let canonical_game_id = "22222222222222222222222222222222";
    let fallback_game_id = "99999999999999999999999999999999";
    let content_id = "33333333333333333333333333333333";
    let membership_id = "44444444444444444444444444444444";
    let source_entry_id =
        SourceEntryId::try_from("55555555555555555555555555555555").expect("source entry id");
    let game_content_source_id = "66666666666666666666666666666666";
    let reference_id = "77777777777777777777777777777777";
    let asset_id = "88888888888888888888888888888888";

    old.with_connection_for_tests(context(), move |connection| {
        connection.execute_with_values(
            "INSERT INTO game (game_id, platform_id, lifecycle_state, grouping_revision,
                 fallback_title, fallback_title_provenance, hydration_state, created_at, updated_at)
             VALUES (?1, 'nintendo.gb', 'active', 1, 'Legacy Fallback', 'local_fallback',
                 'hydrated', '1000', '1000'),
                    (?2, 'nintendo.gb', 'active', 1, 'Canonical Game', 'local_fallback',
                 'hydrated', '1000', '1000')",
            &[
                SqliteValue::Text(game_id.to_owned()),
                SqliteValue::Text(canonical_game_id.to_owned()),
            ],
        )?;
        connection.execute_with_values(
            "INSERT INTO game (game_id, platform_id, lifecycle_state, grouping_revision,
                 fallback_title, fallback_title_provenance, hydration_state, created_at, updated_at)
             VALUES (?1, 'nintendo.gb', 'active', 1, 'Canonical Fallback', 'local_fallback',
                 'unmatched', '1000', '1000')",
            &[SqliteValue::Text(fallback_game_id.to_owned())],
        )?;
        connection.execute_with_values(
            "INSERT INTO game_content (
                 game_content_id, platform_id, content_type, presence_state,
                 identification_state, grouping_revision, created_at, updated_at
             ) VALUES (?1, 'nintendo.gb', 'CartridgeImage', 'available', 'identified',
                 1, '1000', '1000')",
            &[SqliteValue::Text(content_id.to_owned())],
        )?;
        connection.execute_with_values(
            "INSERT INTO game_membership (
                 game_membership_id, game_id, game_content_id, relationship,
                 grouping_basis, grouping_revision, is_current, created_at, updated_at
             ) VALUES (?1, ?2, ?3, 'primary_content', 'exact_content_identity', 1, 1, '1000', '1000')",
            &[
                SqliteValue::Text(membership_id.to_owned()),
                SqliteValue::Text(game_id.to_owned()),
                SqliteValue::Text(content_id.to_owned()),
            ],
        )?;
        connection.execute_with_values(
            "INSERT INTO source_entry (
                 source_entry_id, library_root_id, parent_source_entry_id, coordinate_kind,
                 relative_locator, locator_key, display_name, display_location, kind,
                 classification, provider_native_identity, source_fingerprint,
                 last_observed_scan_id, created_at, updated_at
             ) VALUES (?1, ?2, NULL, 'provider', 'legacy.gb', 'legacy.gb', 'legacy.gb',
                 'legacy.gb', 'file', 'content_candidate', 'native:legacy', 'fingerprint:legacy',
                 ?3, 1000, 1000)",
            &[
                SqliteValue::Text(source_entry_id.to_string()),
                SqliteValue::Text(root.to_string()),
                SqliteValue::Text(scan.to_string()),
            ],
        )?;
        connection.execute_with_values(
            "INSERT INTO game_content_source (
                 game_content_source_id, game_content_id, source_entry_id, association_key,
                 source_fingerprint, last_observed_scan_id, is_current, created_at, updated_at
             ) VALUES (?1, ?2, ?3, 'primary', 'fingerprint:legacy', ?4, 1, '1000', '1000')",
            &[
                SqliteValue::Text(game_content_source_id.to_owned()),
                SqliteValue::Text(content_id.to_owned()),
                SqliteValue::Text(source_entry_id.to_string()),
                SqliteValue::Text(scan.to_string()),
            ],
        )?;
        connection.execute_with_values(
            "INSERT INTO game_library_row (
                 game_id, display_title, display_title_provenance, platform_id,
                 hydration_state, availability_state, content_count, source_count, updated_at
             ) VALUES (?1, 'Legacy Fallback', 'local_fallback', 'nintendo.gb',
                 'hydrated', 'available', 1, 1, '1000'),
                    (?2, 'Canonical Game', 'local_fallback', 'nintendo.gb',
                 'hydrated', 'available', 0, 0, '1000'),
                    (?3, 'Legacy Row Title', 'local_fallback', 'nintendo.gb',
                 'unmatched', 'available', 0, 0, '1000')",
            &[
                SqliteValue::Text(game_id.to_owned()),
                SqliteValue::Text(canonical_game_id.to_owned()),
                SqliteValue::Text(fallback_game_id.to_owned()),
            ],
        )?;
        connection.execute_with_values(
            "INSERT INTO game_redirect (game_id, canonical_game_id, created_at)
             VALUES (?1, ?2, '1000')",
            &[
                SqliteValue::Text(game_id.to_owned()),
                SqliteValue::Text(canonical_game_id.to_owned()),
            ],
        )?;
        connection.execute_with_values(
            "INSERT INTO resolved_metadata (
                 game_id, display_title, sort_title, description, release_date,
                 developers, publishers, genres, languages, presentation_region,
                 field_provenance, resolution_revision, resolved_at
             ) VALUES (?1, 'Resolved Migrated Title', 'resolved migrated title',
                 'Description retained across migration', '1991-04-21', 'Developer',
                 'Publisher', 'Action', 'English', 'us', '{\"title\":\"provider\"}', 1, '1001')",
            &[SqliteValue::Text(game_id.to_owned())],
        )?;
        connection.execute_with_values(
            "INSERT INTO artwork_reference (
                 reference_id, provider_id, external_game_id, artwork_type, source_kind,
                 source_value, thumbnail_value, width, height, format, mime_type, region,
                 language, tags, quality, discovered_at, provider_revision
             ) VALUES (?1, 'gametdb', 'legacy-game', 'cover_front',
                 'provider_asset_locator', 'provider:cover', NULL, 640, 480, 'png',
                 'image/png', 'us', 'en', '', 90, '1001', 1)",
            &[SqliteValue::Text(reference_id.to_owned())],
        )?;
        connection.execute_with_values(
            "INSERT INTO artwork_asset (
                 asset_id, width, height, mime_type, byte_size, storage_key, created_at
             ) VALUES (?1, 640, 480, 'image/png', 128, 'asset/legacy-cover', '1001')",
            &[SqliteValue::Text(asset_id.to_owned())],
        )?;
        connection.execute_with_values(
            "INSERT INTO resolved_artwork (
                 game_id, artwork_type, reference_id, asset_id, ordering,
                 selection_reason, resolution_revision, resolved_at
             ) VALUES (?1, 'cover_front', ?2, ?3, 0, 'best_cover', 1, '1001')",
            &[
                SqliteValue::Text(game_id.to_owned()),
                SqliteValue::Text(reference_id.to_owned()),
                SqliteValue::Text(asset_id.to_owned()),
            ],
        )?;
        Ok::<_, argus_infrastructure::sqlite::SqliteOperationError>(())
    })
    .expect("seed populated v14 rows");
    old.shutdown().expect("shutdown v14");

    let current = SqliteDatabaseExecutor::open(&database).expect("v15-v17 upgrade");
    assert_eq!(current.migration_summary().current_version, 17);
    assert_eq!(current.migration_summary().applied_count, 3);

    current
        .with_connection_for_tests(context(), move |connection| {
            assert_eq!(
                connection.scalar_i64(&format!(
                    "SELECT COUNT(*) FROM game WHERE game_id IN ('{game_id}', '{canonical_game_id}')"
                ))?,
                2
            );
            assert_eq!(
                connection.scalar_i64(&format!(
                    "SELECT COUNT(*) FROM game_content WHERE game_content_id = '{content_id}'"
                ))?,
                1
            );
            assert_eq!(
                connection.scalar_i64(&format!(
                    "SELECT COUNT(*) FROM game_membership
                     WHERE game_membership_id = '{membership_id}' AND game_id = '{game_id}'"
                ))?,
                1
            );
            assert_eq!(
                connection.scalar_i64(&format!(
                    "SELECT COUNT(*) FROM game_content_source
                     WHERE game_content_source_id = '{game_content_source_id}'
                       AND source_entry_id = '{source_entry_id}'"
                ))?,
                1
            );
            assert_eq!(
                connection.scalar_i64(&format!(
                    "SELECT COUNT(*) FROM game_redirect
                     WHERE game_id = '{game_id}' AND canonical_game_id = '{canonical_game_id}'"
                ))?,
                1
            );
            let metadata = connection.scalar_text(&format!(
                "SELECT display_title || '|' || presentation_region || '|' || release_date
                 FROM resolved_metadata WHERE game_id = '{game_id}'"
            ))?;
            assert_eq!(metadata, "Resolved Migrated Title|us|1991-04-21");
            assert_eq!(
                connection.scalar_i64(&format!(
                    "SELECT COUNT(*) FROM resolved_artwork
                     WHERE game_id = '{game_id}' AND asset_id = '{asset_id}'"
                ))?,
                1
            );
            let projection = connection.scalar_text(&format!(
                "SELECT display_title || '|' || display_title_provenance || '|'
                     || presentation_region || '|' || selected_cover_asset_id || '|'
                     || release_date || '|' || search_text
                 FROM game_library_row WHERE game_id = '{game_id}'"
            ))?;
            assert!(projection.starts_with(
                "Resolved Migrated Title|resolved_metadata|us|88888888888888888888888888888888|1991-04-21|"
            ));
            assert!(projection.ends_with("resolved migrated title legacy fallback"));
            let fallback_projection = connection.scalar_text(&format!(
                "SELECT display_title || '|' || display_title_provenance || '|' || search_text
                 FROM game_library_row WHERE game_id = '{fallback_game_id}'"
            ))?;
            assert_eq!(
                fallback_projection,
                "Canonical Fallback|local_fallback|canonical fallback"
            );
            Ok::<_, argus_infrastructure::sqlite::SqliteOperationError>(())
        })
        .expect("verify migrated logical and enrichment rows");
    current.shutdown().expect("shutdown v15-v17");
}

#[test]
fn migration_v16_bounds_existing_library_projection_keys() {
    let directory = tempdir().expect("tempdir");
    let database = directory.path().join("oversized-projection-v14.sqlite3");
    let old = SqliteDatabaseExecutor::open_with_registry(&database, registry_v14())
        .expect("v14 database");
    let game_id = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    let display_title = format!("\0Legacy {}", "😀".repeat(300));
    let release_date = format!("\02020-01-01{}", "😀".repeat(20));
    let expected_display_title = argus_application::bounded_library_display_title(&display_title);
    let expected_release_date = argus_application::bounded_library_release_date(&release_date);

    old.with_connection_for_tests(context(), move |connection| {
        connection.execute_with_values(
            "INSERT INTO game (
                 game_id, platform_id, lifecycle_state, grouping_revision, fallback_title,
                 fallback_title_provenance, hydration_state, created_at, updated_at
             ) VALUES (?1, 'nintendo.gb', 'active', 1, 'Legacy Fallback', 'local_fallback',
                 'hydrated', '1000', '1000')",
            &[SqliteValue::Text(game_id.to_owned())],
        )?;
        connection.execute_with_values(
            "INSERT INTO game_library_row (
                 game_id, display_title, display_title_provenance, platform_id,
                 hydration_state, availability_state, content_count, source_count, updated_at
             ) VALUES (?1, 'Legacy Row', 'local_fallback', 'nintendo.gb',
                 'hydrated', 'available', 0, 0, '1000')",
            &[SqliteValue::Text(game_id.to_owned())],
        )?;
        connection.execute_with_values(
            "INSERT INTO resolved_metadata (
                 game_id, display_title, sort_title, description, release_date,
                 developers, publishers, genres, languages, presentation_region,
                 field_provenance, resolution_revision, resolved_at
             ) VALUES (?1, ?2, 'legacy', 'description', ?3, '', '', '', '', 'us', '{}', 1, '1000')",
            &[
                SqliteValue::Text(game_id.to_owned()),
                SqliteValue::Text(display_title),
                SqliteValue::Text(release_date),
            ],
        )?;
        Ok::<_, argus_infrastructure::sqlite::SqliteOperationError>(())
    })
    .expect("seed oversized v14 projection inputs");
    old.shutdown().expect("shutdown v14");

    let current = SqliteDatabaseExecutor::open(&database).expect("v15-v17 upgrade");
    assert_eq!(current.migration_summary().current_version, 17);
    assert_eq!(current.migration_summary().applied_count, 3);

    current
        .with_connection_for_tests(context(), move |connection| {
            let persisted_title = connection.scalar_text(
                "SELECT display_title
                 FROM game_library_row WHERE game_id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'",
            )?;
            let persisted_release_date = connection.scalar_text(
                "SELECT release_date
                 FROM game_library_row WHERE game_id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'",
            )?;
            let title_bytes = connection.scalar_i64(
                "SELECT length(CAST(display_title AS BLOB))
                 FROM game_library_row WHERE game_id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'",
            )?;
            let release_date_bytes = connection.scalar_i64(
                "SELECT length(CAST(release_date AS BLOB))
                 FROM game_library_row WHERE game_id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'",
            )?;
            assert_eq!(persisted_title, expected_display_title);
            assert_eq!(persisted_release_date, expected_release_date);
            assert!(title_bytes <= 1024);
            assert!(release_date_bytes <= 64);
            Ok::<_, argus_infrastructure::sqlite::SqliteOperationError>(())
        })
        .expect("verify bounded v16 projection keys");
    current.shutdown().expect("shutdown v17");
}

#[test]
fn migration_v17_backfills_only_provable_derived_proof_versions() {
    let directory = tempdir().expect("tempdir");
    let database = directory.path().join("derived-proof-v14.sqlite3");
    let old = SqliteDatabaseExecutor::open_with_registry(&database, registry_v14())
        .expect("v14 database");

    old.with_connection_for_tests(context(), |connection| {
        let (library_source_id, display_name) = ("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "Test");
        connection.execute_with_values(
            "INSERT INTO library_source (
                 library_source_id, source_provider_type, display_name,
                 provider_config, config_revision, created_at, updated_at
             ) VALUES (?1, 'local_filesystem', ?2, '{}', 1, '1000', '1000')",
            &[
                SqliteValue::Text(library_source_id.to_owned()),
                SqliteValue::Text(display_name.to_owned()),
            ],
        )?;
        connection.execute_with_values(
            "INSERT INTO library_root (
                 library_root_id, library_source_id, root_locator, display_name,
                 safe_location_presentation, availability_status, config_revision,
                 created_at, updated_at
             ) VALUES (?1, ?2, '/library', 'Test Root', '/library', 'available', 1,
                 '1000', '1000')",
            &[
                SqliteValue::Text("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb".to_owned()),
                SqliteValue::Text("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".to_owned()),
            ],
        )?;
        for (job_run_id, scan_run_id, started_at) in [
            (
                "cccccccccccccccccccccccccccccccc",
                "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
                1000_i64,
            ),
            (
                "dddddddddddddddddddddddddddddddd",
                "ffffffffffffffffffffffffffffffff",
                900_i64,
            ),
        ] {
            connection.execute_with_values(
                "INSERT INTO job_run (job_run_id, operation_type, state, created_at)
                 VALUES (?1, 'library_scan', 'completed', ?2)",
                &[
                    SqliteValue::Text(job_run_id.to_owned()),
                    SqliteValue::Integer(started_at),
                ],
            )?;
            connection.execute_with_values(
                "INSERT INTO scan_run (
                     scan_run_id, job_run_id, historical_library_root_id, root_locator,
                     root_display_name, safe_location_display, source_config_revision,
                     root_config_revision, status, started_at, completed_at
                 ) VALUES (?1, ?2, ?3, '/library', 'Test Root', '/library', 1, 1,
                     'complete', ?4, ?4)",
                &[
                    SqliteValue::Text(scan_run_id.to_owned()),
                    SqliteValue::Text(job_run_id.to_owned()),
                    SqliteValue::Text("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb".to_owned()),
                    SqliteValue::Integer(started_at),
                ],
            )?;
        }
        connection.execute_with_values(
            "INSERT INTO source_entry (
                 source_entry_id, library_root_id, parent_source_entry_id, coordinate_kind,
                 relative_locator, locator_key, display_name, display_location, kind,
                 classification, provider_native_identity, source_fingerprint,
                 last_observed_scan_id, created_at, updated_at
             ) VALUES (?1, ?2, NULL, 'provider', 'parent', 'parent', 'Parent', 'Parent',
                 'directory', 'container', NULL, 'provider-v1', ?3, 1000, 1000)",
            &[
                SqliteValue::Text("11111111111111111111111111111111".to_owned()),
                SqliteValue::Text("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb".to_owned()),
                SqliteValue::Text("eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee".to_owned()),
            ],
        )?;
        connection.execute_with_values(
            "INSERT INTO source_entry (
                 source_entry_id, library_root_id, parent_source_entry_id, coordinate_kind,
                 relative_locator, locator_key, display_name, display_location, kind,
                 classification, provider_native_identity, source_fingerprint,
                 derived_locator, derived_entry_key, derived_fingerprint,
                 derivation_transformation_id, derivation_revision,
                 last_observed_scan_id, created_at, updated_at
             ) VALUES (?1, ?2, ?3, 'derived', NULL, NULL, 'Derived', 'Derived', 'file',
                 'content_candidate', NULL, NULL, 'child', 'child', 'derived-v1',
                 'test.transform', 1, ?4, 1000, 1000)",
            &[
                SqliteValue::Text("22222222222222222222222222222222".to_owned()),
                SqliteValue::Text("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb".to_owned()),
                SqliteValue::Text("11111111111111111111111111111111".to_owned()),
                SqliteValue::Text("eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee".to_owned()),
            ],
        )?;

        for (game_content_id, identity_id, identity_value) in [
            (
                "33333333333333333333333333333333",
                "44444444444444444444444444444444",
                "identity-exact",
            ),
            (
                "55555555555555555555555555555555",
                "66666666666666666666666666666666",
                "identity-stale",
            ),
            (
                "77777777777777777777777777777777",
                "88888888888888888888888888888888",
                "identity-provider",
            ),
            (
                "99999999999999999999999999999999",
                "abababababababababababababababab",
                "identity-missing",
            ),
        ] {
            connection.execute_with_values(
                "INSERT INTO game_content (
                     game_content_id, platform_id, content_type, presence_state,
                     identification_state, grouping_revision, created_at, updated_at
                 ) VALUES (?1, 'nintendo.gb', 'CartridgeImage', 'available', 'identified',
                     1, '1000', '1000')",
                &[SqliteValue::Text(game_content_id.to_owned())],
            )?;
            connection.execute_with_values(
                "INSERT INTO content_identity (
                     content_identity_id, game_content_id, scheme_id, identity_revision,
                     identity_value, is_current, proving_source_entry_id,
                     proving_association_key, proving_source_fingerprint, proving_scan_run_id,
                     created_at, updated_at
                 ) VALUES (?1, ?2, 'test', 1, ?3, 1, ?4, 'primary', ?5, ?6,
                     '1000', '1000')",
                &[
                    SqliteValue::Text(identity_id.to_owned()),
                    SqliteValue::Text(game_content_id.to_owned()),
                    SqliteValue::Text(identity_value.to_owned()),
                    SqliteValue::Text(
                        match identity_value {
                            "identity-exact" | "identity-stale" => {
                                "22222222222222222222222222222222"
                            }
                            "identity-provider" => "11111111111111111111111111111111",
                            _ => "cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd",
                        }
                        .to_owned(),
                    ),
                    match identity_value {
                        "identity-exact" => {
                            SqliteValue::Text("legacy-provider-fingerprint".to_owned())
                        }
                        _ => SqliteValue::Null,
                    },
                    SqliteValue::Text(
                        match identity_value {
                            "identity-stale" => "ffffffffffffffffffffffffffffffff",
                            _ => "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
                        }
                        .to_owned(),
                    ),
                ],
            )?;
        }

        for (provenance_id, identity_id, source_entry_id, scan_run_id) in [
            (
                "acacacacacacacacacacacacacacacac",
                "44444444444444444444444444444444",
                "22222222222222222222222222222222",
                "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
            ),
            (
                "adadadadadadadadadadadadadadadad",
                "66666666666666666666666666666666",
                "22222222222222222222222222222222",
                "ffffffffffffffffffffffffffffffff",
            ),
            (
                "aeaeaeaeaeaeaeaeaeaeaeaeaeaeaeae",
                "88888888888888888888888888888888",
                "11111111111111111111111111111111",
                "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
            ),
            (
                "afafafafafafafafafafafafafafafaf",
                "abababababababababababababababab",
                "cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd",
                "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
            ),
        ] {
            connection.execute_with_values(
                "INSERT INTO content_identity_provenance (
                     provenance_member_id, content_identity_id, role, association_key,
                     source_entry_id, source_fingerprint, last_observed_scan_id,
                     identity_is_current, created_at, updated_at
                 ) VALUES (?1, ?2, 'primary', 'primary', ?3, NULL, ?4, 1,
                     '1000', '1000')",
                &[
                    SqliteValue::Text(provenance_id.to_owned()),
                    SqliteValue::Text(identity_id.to_owned()),
                    SqliteValue::Text(source_entry_id.to_owned()),
                    SqliteValue::Text(scan_run_id.to_owned()),
                ],
            )?;
        }

        for (index, (game_content_id, source_entry_id, scan_run_id)) in [
            (
                "33333333333333333333333333333333",
                "22222222222222222222222222222222",
                "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
            ),
            (
                "55555555555555555555555555555555",
                "22222222222222222222222222222222",
                "ffffffffffffffffffffffffffffffff",
            ),
            (
                "77777777777777777777777777777777",
                "11111111111111111111111111111111",
                "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
            ),
        ]
        .into_iter()
        .enumerate()
        {
            connection.execute_with_values(
                "INSERT INTO game_content_source (
                     game_content_source_id, game_content_id, source_entry_id,
                     association_key, source_fingerprint, last_observed_scan_id,
                     is_current, created_at, updated_at
                 ) VALUES (?1, ?2, ?3, 'primary', ?4, ?5, 1, '1000', '1000')",
                &[
                    SqliteValue::Text(format!("{index:032x}")),
                    SqliteValue::Text(game_content_id.to_owned()),
                    SqliteValue::Text(source_entry_id.to_owned()),
                    SqliteValue::Null,
                    SqliteValue::Text(scan_run_id.to_owned()),
                ],
            )?;
        }

        for (evidence_id, source_entry_id, scan_run_id) in [
            (
                "bcbcbcbcbcbcbcbcbcbcbcbcbcbcbcbc",
                "22222222222222222222222222222222",
                "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
            ),
            (
                "bdbdbdbdbdbdbdbdbdbdbdbdbdbdbdbd",
                "22222222222222222222222222222222",
                "ffffffffffffffffffffffffffffffff",
            ),
            (
                "bebebebebebebebebebebebebebebebe",
                "11111111111111111111111111111111",
                "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
            ),
        ] {
            connection.execute_with_values(
                "INSERT INTO grouping_evidence (
                     grouping_evidence_id, evidence_kind, playlist_source_entry_id,
                     source_fingerprint, last_observed_scan_id, is_current,
                     created_at, updated_at
                 ) VALUES (?1, 'm3u', ?2, NULL, ?3, 1, '1000', '1000')",
                &[
                    SqliteValue::Text(evidence_id.to_owned()),
                    SqliteValue::Text(source_entry_id.to_owned()),
                    SqliteValue::Text(scan_run_id.to_owned()),
                ],
            )?;
            connection.execute_with_values(
                "INSERT INTO grouping_evidence_member (
                     grouping_evidence_id, member_game_content_id, member_source_entry_id,
                     member_source_fingerprint, member_last_observed_scan_id, ordinal
                 ) VALUES (?1, '33333333333333333333333333333333', ?2, NULL, ?3, 0)",
                &[
                    SqliteValue::Text(evidence_id.to_owned()),
                    SqliteValue::Text(source_entry_id.to_owned()),
                    SqliteValue::Text(scan_run_id.to_owned()),
                ],
            )?;
        }
        Ok::<_, argus_infrastructure::sqlite::SqliteOperationError>(())
    })
    .expect("seed v14 proof rows");
    old.shutdown().expect("shutdown v14");

    let current = SqliteDatabaseExecutor::open(&database).expect("v17 upgrade");
    assert_eq!(current.migration_summary().current_version, 17);
    assert_eq!(current.migration_summary().applied_count, 3);
    current
        .with_connection_for_tests(context(), |connection| {
            for (table, column, id, expected) in [
                (
                    "content_identity",
                    "proving_derived_fingerprint",
                    "44444444444444444444444444444444",
                    None,
                ),
                (
                    "content_identity_provenance",
                    "derived_fingerprint",
                    "acacacacacacacacacacacacacacacac",
                    Some("derived-v1"),
                ),
                (
                    "game_content_source",
                    "derived_fingerprint",
                    "00000000000000000000000000000000",
                    Some("derived-v1"),
                ),
                (
                    "grouping_evidence",
                    "derived_fingerprint",
                    "bcbcbcbcbcbcbcbcbcbcbcbcbcbcbcbc",
                    Some("derived-v1"),
                ),
                (
                    "grouping_evidence_member",
                    "member_derived_fingerprint",
                    "bcbcbcbcbcbcbcbcbcbcbcbcbcbcbcbc",
                    Some("derived-v1"),
                ),
            ] {
                let value = match table {
                    "content_identity" => connection.scalar_text(&format!(
                        "SELECT COALESCE({column}, '') FROM {table} WHERE content_identity_id = '{id}'"
                    ))?,
                    "content_identity_provenance" => connection.scalar_text(&format!(
                        "SELECT COALESCE({column}, '') FROM {table} WHERE provenance_member_id = '{id}'"
                    ))?,
                    "game_content_source" => connection.scalar_text(&format!(
                        "SELECT COALESCE({column}, '') FROM {table} WHERE game_content_source_id = '{id}'"
                    ))?,
                    "grouping_evidence" => connection.scalar_text(&format!(
                        "SELECT COALESCE({column}, '') FROM {table} WHERE grouping_evidence_id = '{id}'"
                    ))?,
                    "grouping_evidence_member" => connection.scalar_text(&format!(
                        "SELECT COALESCE({column}, '') FROM {table} WHERE grouping_evidence_id = '{id}'"
                    ))?,
                    _ => unreachable!(),
                };
                assert_eq!(Some(value.as_str()).filter(|value| !value.is_empty()), expected);
            }

            for (table, column, where_clause) in [
                (
                    "content_identity",
                    "proving_derived_fingerprint",
                    "content_identity_id = '66666666666666666666666666666666'",
                ),
                (
                    "content_identity",
                    "proving_derived_fingerprint",
                    "content_identity_id = '88888888888888888888888888888888'",
                ),
                (
                    "content_identity",
                    "proving_derived_fingerprint",
                    "content_identity_id = 'abababababababababababababababab'",
                ),
                (
                    "content_identity_provenance",
                    "derived_fingerprint",
                    "provenance_member_id = 'adadadadadadadadadadadadadadadad'",
                ),
                (
                    "content_identity_provenance",
                    "derived_fingerprint",
                    "provenance_member_id = 'aeaeaeaeaeaeaeaeaeaeaeaeaeaeaeae'",
                ),
                (
                    "content_identity_provenance",
                    "derived_fingerprint",
                    "provenance_member_id = 'afafafafafafafafafafafafafafafaf'",
                ),
            ] {
                assert_eq!(
                    connection.scalar_i64(&format!(
                        "SELECT {column} IS NULL FROM {table} WHERE {where_clause}"
                    ))?,
                    1,
                    "unexpected historical derived backfill in {table}.{column}"
                );
            }
            Ok::<_, argus_infrastructure::sqlite::SqliteOperationError>(())
        })
        .expect("verify v17 proof backfill");
    current.shutdown().expect("shutdown v17");
}
