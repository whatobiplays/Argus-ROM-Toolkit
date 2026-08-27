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
        TraceId::try_from(14).expect("trace"),
        SubsystemName::try_from("migration").expect("subsystem"),
        OperationName::try_from("v14").expect("operation"),
    )
}

fn registry_v13() -> MigrationRegistry {
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
    ])
    .expect("v13 registry")
}

#[test]
fn v13_provider_ids_and_parent_relationships_survive_v14_coordinate_migration() {
    let directory = tempdir().expect("tempdir");
    let database = directory.path().join("argus.sqlite3");
    let old = SqliteDatabaseExecutor::open_with_registry(&database, registry_v13())
        .expect("v13 database");

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
        .expect("seed v13 root and scan");
    let parent = SourceEntryId::try_from("44444444444444444444444444444444").expect("parent id");
    let child = SourceEntryId::try_from("55555555555555555555555555555555").expect("child id");
    old.with_connection_for_tests(context(), move |connection| {
        let parent_values = vec![
            SqliteValue::Text(parent.to_string()),
            SqliteValue::Text(root.to_string()),
            SqliteValue::Null,
            SqliteValue::Text("archive.zip".to_owned()),
            SqliteValue::Text("archive.zip".to_owned()),
            SqliteValue::Text("archive.zip".to_owned()),
            SqliteValue::Text("archive.zip".to_owned()),
            SqliteValue::Text("file".to_owned()),
            SqliteValue::Text("container".to_owned()),
            SqliteValue::Text("native:archive".to_owned()),
            SqliteValue::Text("provider:archive".to_owned()),
            SqliteValue::Text(scan.to_string()),
            SqliteValue::Integer(1_000),
            SqliteValue::Integer(1_000),
        ];
        connection.execute_with_values(
            "INSERT INTO source_entry (
                 source_entry_id, library_root_id, parent_source_entry_id,
                 relative_locator, locator_key, display_name, display_location,
                 kind, classification, provider_native_identity, source_fingerprint,
                 last_observed_scan_id, created_at, updated_at
             ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14)",
            &parent_values,
        )?;

        let child_values = vec![
            SqliteValue::Text(child.to_string()),
            SqliteValue::Text(root.to_string()),
            SqliteValue::Text(parent.to_string()),
            SqliteValue::Text("archive.zip/readme.txt".to_owned()),
            SqliteValue::Text("archive.zip/readme.txt".to_owned()),
            SqliteValue::Text("readme.txt".to_owned()),
            SqliteValue::Text("archive.zip/readme.txt".to_owned()),
            SqliteValue::Text("file".to_owned()),
            SqliteValue::Text("supporting_entry".to_owned()),
            SqliteValue::Null,
            SqliteValue::Text("provider:readme".to_owned()),
            SqliteValue::Text(scan.to_string()),
            SqliteValue::Integer(1_001),
            SqliteValue::Integer(1_001),
        ];
        connection.execute_with_values(
            "INSERT INTO source_entry (
                 source_entry_id, library_root_id, parent_source_entry_id,
                 relative_locator, locator_key, display_name, display_location,
                 kind, classification, provider_native_identity, source_fingerprint,
                 last_observed_scan_id, created_at, updated_at
             ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14)",
            &child_values,
        )?;
        Ok::<_, argus_infrastructure::sqlite::SqliteOperationError>(())
    })
    .expect("seed v13 rows");
    old.shutdown().expect("shutdown v13");

    let current = SqliteDatabaseExecutor::open(&database).expect("v14 upgrade");
    assert_eq!(current.migration_summary().current_version, 16);
    assert_eq!(current.migration_summary().applied_count, 3);

    current
        .with_connection_for_tests(context(), move |connection| {
            let parent_id = parent.to_string();
            let child_id = child.to_string();
            assert_eq!(
                connection.scalar_i64(&format!(
                    "SELECT COUNT(*) FROM source_entry
                         WHERE source_entry_id = '{parent_id}'
                           AND coordinate_kind = 'provider'
                           AND relative_locator = 'archive.zip'
                           AND locator_key = 'archive.zip'
                           AND provider_native_identity = 'native:archive'
                           AND source_fingerprint = 'provider:archive'"
                ))?,
                1
            );
            assert_eq!(
                connection.scalar_i64(&format!(
                    "SELECT COUNT(*) FROM source_entry
                         WHERE source_entry_id = '{child_id}'
                           AND parent_source_entry_id = '{parent_id}'
                           AND coordinate_kind = 'provider'"
                ))?,
                1
            );
            assert_eq!(
                connection.scalar_i64(
                    "SELECT COUNT(*) FROM sqlite_master
                     WHERE type = 'index' AND name = 'uq_source_entry_provider_locator'"
                )?,
                1
            );
            Ok(())
        })
        .expect("verify migrated rows");
    current.shutdown().expect("shutdown v14");
}
