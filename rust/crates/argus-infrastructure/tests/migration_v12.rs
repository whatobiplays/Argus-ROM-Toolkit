#![cfg(feature = "test-support")]

use argus_application::{OperationContext, OperationName, SubsystemName, TraceId};
use argus_infrastructure::sqlite::{
    Migration, MigrationRegistry, SqliteDatabaseExecutor, SqliteValue,
};
use tempfile::tempdir;

fn context() -> OperationContext {
    OperationContext::new(
        TraceId::try_from(412_u128).expect("trace"),
        SubsystemName::try_from("migration").expect("subsystem"),
        OperationName::try_from("v12").expect("operation"),
    )
}

fn v11_registry() -> MigrationRegistry {
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
    ])
    .expect("v11 registry")
}

#[test]
fn v11_rows_and_relationships_survive_content_catalog_expansion() {
    let directory = tempdir().expect("tempdir");
    let database = directory.path().join("argus.sqlite3");
    let old = SqliteDatabaseExecutor::open_with_registry(&database, v11_registry())
        .expect("v11 database");
    assert_eq!(old.migration_summary().current_version, 11);

    old.with_connection_for_tests(context(), |connection| {
        connection.execute_batch(
            "
            INSERT INTO library_source
                (library_source_id, source_provider_type, display_name, provider_config,
                 config_revision, created_at, updated_at)
            VALUES ('source-library', 'local_filesystem', 'Local', '{}', 1, '1', '1');
            INSERT INTO library_root
                (library_root_id, library_source_id, root_locator, display_name,
                 safe_location_presentation, availability_status, config_revision,
                 created_at, updated_at)
            VALUES ('root-library', 'source-library', '/tmp/argus', 'Root', '/tmp/argus',
                    'available', 1, '1', '1');
            INSERT INTO job_run
                (job_run_id, operation_type, state, created_at)
            VALUES ('job-v11', 'library_scan', 'completed', 1);
            INSERT INTO scan_run
                (scan_run_id, job_run_id, historical_library_root_id, root_locator,
                 root_display_name, safe_location_display, source_config_revision,
                 root_config_revision, status, started_at)
            VALUES ('scan-v11', 'job-v11', 'root-library', '/tmp/argus', 'Root', '/tmp/argus',
                    1, 1, 'complete', 1);
            INSERT INTO source_entry
                (source_entry_id, library_root_id, relative_locator, locator_key,
                 display_name, display_location, kind, classification,
                 source_fingerprint, last_observed_scan_id, created_at, updated_at)
            VALUES ('entry-v11', 'root-library', 'game.gb', 'game.gb', 'game.gb',
                    '/tmp/argus/game.gb', 'file', 'content_candidate', 'v1:file:32768:1',
                    'scan-v11', 1, 1);
            INSERT INTO game_content
                (game_content_id, platform_id, content_type, presence_state,
                 identification_state, grouping_revision, created_at, updated_at)
            VALUES ('content-v11', 'nintendo.gb', 'CartridgeImage', 'available',
                    'identified', 1, '1', '1');
            INSERT INTO content_identity
                (content_identity_id, game_content_id, scheme_id, identity_revision,
                 identity_value, is_current, proving_source_entry_id,
                 proving_association_key, proving_source_fingerprint, proving_scan_run_id,
                 created_at, updated_at)
            VALUES ('identity-v11', 'content-v11',
                    'argus.content.identity.nintendo-gb.cartridge.v1', 1,
                    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 1,
                    'entry-v11', 'raw', 'v1:file:32768:1', 'scan-v11', '1', '1');
            INSERT INTO content_identity
                (content_identity_id, game_content_id, scheme_id, identity_revision,
                 identity_value, is_current, proving_source_entry_id,
                 proving_association_key, proving_source_fingerprint, proving_scan_run_id,
                 created_at, updated_at)
            VALUES ('identity-v11-retained', 'content-v11',
                    'argus.content.identity.nintendo-gb.cartridge.v1', 1,
                    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', 0,
                    'entry-v11', 'retained', 'v1:file:32768:1', 'scan-v11', '1', '1');
            INSERT INTO game_content_source
                (game_content_source_id, game_content_id, source_entry_id, association_key,
                 source_fingerprint, last_observed_scan_id, is_current, created_at, updated_at)
            VALUES ('provenance-v11', 'content-v11', 'entry-v11', 'raw',
                    'v1:file:32768:1', 'scan-v11', 1, '1', '1');
            INSERT INTO game
                (game_id, platform_id, lifecycle_state, grouping_revision, fallback_title,
                 fallback_title_provenance, hydration_state, created_at, updated_at)
            VALUES ('game-v11', 'nintendo.gb', 'active', 1, 'Game Boy Fixture',
                    'local_fallback', 'hydrated', '1', '1');
            INSERT INTO game
                (game_id, platform_id, lifecycle_state, grouping_revision, fallback_title,
                 fallback_title_provenance, hydration_state, created_at, updated_at)
            VALUES ('game-v11-redirect', 'nintendo.gb', 'redirected', 1, 'Old Fixture',
                    'local_fallback', 'unmatched', '1', '1');
            INSERT INTO game_membership
                (game_membership_id, game_id, game_content_id, relationship, grouping_basis,
                 grouping_revision, is_current, created_at, updated_at)
            VALUES ('membership-v11', 'game-v11', 'content-v11', 'primary',
                    'exact_content_identity', 1, 1, '1', '1');
            INSERT INTO game_redirect
                (game_id, canonical_game_id, created_at)
            VALUES ('game-v11-redirect', 'game-v11', '1');
            INSERT INTO game_library_row
                (game_id, display_title, display_title_provenance, platform_id,
                 hydration_state, availability_state, content_count, source_count, updated_at)
            VALUES ('game-v11', 'Game Boy Fixture', 'local_fallback', 'nintendo.gb',
                    'hydrated', 'available', 1, 1, '1');
            INSERT INTO external_identity_mapping
                (mapping_id, game_content_id, provider_id, external_game_id,
                 provider_platform_id, match_basis, provider_revision, state,
                 matched_at, last_validated_at)
            VALUES ('mapping-v11', 'content-v11', 'gametdb', 'tdb-1', 'nintendo.gb',
                    'existing_exact_mapping', 1, 'current', '1', '1');
            INSERT INTO provider_metadata
                (provider_metadata_id, provider_id, external_game_id, provider_revision,
                 fetched_at, provenance)
            VALUES ('metadata-v11', 'gametdb', 'tdb-1', 1, '1', 'fixture');
            INSERT INTO resolved_metadata
                (game_id, display_title, resolution_revision, resolved_at)
            VALUES ('game-v11', 'Resolved Fixture', 1, '1');
            INSERT INTO artwork_reference
                (reference_id, provider_id, external_game_id, artwork_type, source_kind,
                 source_value, discovered_at, provider_revision)
            VALUES ('reference-v11', 'gametdb', 'tdb-1', 'cover_front',
                    'credential_free_url', 'https://example.invalid/cover', '1', 1);
            INSERT INTO artwork_asset
                (asset_id, width, height, mime_type, byte_size, storage_key, created_at)
            VALUES ('asset-v11', 1, 1, 'image/png', 1, 'asset-v11', '1');
            INSERT INTO resolved_artwork
                (game_id, artwork_type, reference_id, asset_id, ordering, selection_reason,
                 resolution_revision, resolved_at)
            VALUES ('game-v11', 'cover_front', 'reference-v11', 'asset-v11', 0,
                    'fixture', 1, '1');
            ",
        )?;
        Ok(())
    })
    .expect("seed v11 rows");
    old.shutdown().expect("shutdown v11");

    let current = SqliteDatabaseExecutor::open(&database).expect("v12 upgrade");
    assert_eq!(current.migration_summary().current_version, 15);
    assert_eq!(current.migration_summary().applied_count, 4);
    current
        .with_connection_for_tests(context(), |connection| {
            for (table, expected) in [
                ("game_content", 1),
                ("content_identity", 2),
                ("game_content_source", 1),
                ("game_membership", 1),
                ("game_redirect", 1),
                ("game_library_row", 1),
                ("external_identity_mapping", 1),
                ("provider_metadata", 1),
                ("resolved_metadata", 1),
                ("artwork_reference", 1),
                ("artwork_asset", 1),
                ("resolved_artwork", 1),
            ] {
                assert_eq!(
                    connection.scalar_i64(&format!("SELECT count(*) FROM {table}"))?,
                    expected
                );
            }
            assert_eq!(
                connection.scalar_text("SELECT game_content_id FROM content_identity")?,
                "content-v11"
            );
            assert_eq!(
                connection.scalar_i64("SELECT count(*) FROM content_identity_provenance")?,
                2
            );
            assert_eq!(
                connection.scalar_i64(
                    "SELECT count(*) FROM content_identity_provenance
                     WHERE identity_is_current = 1",
                )?,
                1
            );
            assert_eq!(
                connection.scalar_i64(
                    "SELECT count(*) FROM content_identity_provenance
                     WHERE identity_is_current = 0",
                )?,
                1
            );
            assert_eq!(
                connection.scalar_text("SELECT game_id FROM resolved_metadata")?,
                "game-v11"
            );
            connection.execute_with_values(
                "INSERT INTO game_content
                    (game_content_id, platform_id, content_type, presence_state,
                     identification_state, grouping_revision, created_at, updated_at)
                VALUES (?1, 'nintendo.fds', 'MagneticDiskImage', 'orphaned',
                         'unidentified', 1, '2', '2')",
                &[SqliteValue::Text("content-fds".to_owned())],
            )?;
            connection.execute_with_values(
                "INSERT INTO game_content
                    (game_content_id, platform_id, content_type, presence_state,
                     identification_state, grouping_revision, created_at, updated_at)
                VALUES (?1, 'nintendo.nes', 'CartridgeImage', 'orphaned',
                         'unidentified', 1, '2', '2')",
                &[SqliteValue::Text("content-nes".to_owned())],
            )?;
            assert!(
                connection
                    .execute_with_values(
                        "INSERT INTO game_content
                        (game_content_id, platform_id, content_type, presence_state,
                         identification_state, grouping_revision, created_at, updated_at)
                    VALUES (?1, 'nintendo.gb', 'MagneticDiskImage', 'orphaned',
                             'unidentified', 1, '2', '2')",
                        &[SqliteValue::Text(
                            "content-invalid-cartridge-pair".to_owned()
                        )],
                    )
                    .is_err()
            );
            assert!(
                connection
                    .execute_with_values(
                        "INSERT INTO game_content
                        (game_content_id, platform_id, content_type, presence_state,
                         identification_state, grouping_revision, created_at, updated_at)
                    VALUES (?1, 'nintendo.fds', 'CartridgeImage', 'orphaned',
                             'unidentified', 1, '2', '2')",
                        &[SqliteValue::Text("content-invalid-disk-pair".to_owned())],
                    )
                    .is_err()
            );
            Ok(())
        })
        .expect("preservation and expanded checks");
    current.shutdown().expect("shutdown v12");
}
