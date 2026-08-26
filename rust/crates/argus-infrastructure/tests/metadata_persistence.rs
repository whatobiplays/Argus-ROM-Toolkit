#![cfg(feature = "test-support")]

use argus_application::{
    ArtworkReference, ArtworkRepository, ArtworkSource, ArtworkType, EnrichmentUnitOfWork,
    MetadataRepository, MetadataSettings, OperationContext, OperationName, ProviderId,
    SubsystemName, TraceId,
};
use argus_infrastructure::sqlite::SqliteDatabaseExecutor;
use tempfile::tempdir;

fn context() -> OperationContext {
    OperationContext::new(
        TraceId::try_from(303_u128).expect("trace"),
        SubsystemName::try_from("metadata").expect("subsystem"),
        OperationName::try_from("persistence").expect("operation"),
    )
}

#[test]
fn enrichment_migration_is_forward_safe_and_creates_two_owned_storage_families() {
    let directory = tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("metadata.sqlite3")).expect("open");

    assert_eq!(executor.migration_summary().current_version, 12);
    executor
        .with_connection_for_tests(context(), |connection| {
            for table in [
                "external_identity_mapping",
                "provider_metadata",
                "resolved_metadata",
                "artwork_reference",
                "resolved_artwork",
                "artwork_asset",
                "metadata_settings",
                "metadata_provider_settings",
            ] {
                assert!(connection.table_exists(table)?, "missing {table}");
            }
            Ok(())
        })
        .expect("schema query");
    executor.shutdown().expect("shutdown");
}

#[test]
fn metadata_repository_round_trips_typed_settings_inside_one_unit_of_work() {
    let directory = tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("metadata.sqlite3")).expect("open");
    let expected = MetadataSettings::new(["us", "jp"], ["en", "ja"]);
    let expected_for_save = expected.clone();

    executor
        .with_unit_of_work(context(), move |mut work| {
            work.metadata().save_settings(&expected_for_save)?;
            work.commit()
        })
        .expect("settings commit");

    let actual = executor
        .with_unit_of_work(context(), |mut work| {
            let result = work.metadata().settings();
            work.rollback()?;
            Ok(result?)
        })
        .expect("settings read");
    assert_eq!(actual, expected);
    executor.shutdown().expect("shutdown");
}

#[test]
fn artwork_repository_round_trips_quality_and_freshness_without_a_storage_path() {
    let directory = tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("metadata.sqlite3")).expect("open");
    let expected = ArtworkReference::new(
        "reference-1",
        ProviderId::GameTdb,
        "game-1",
        ArtworkType::CoverFront,
        ArtworkSource::ProviderAssetLocator("asset:cover-1".to_owned()),
        Some(600),
        Some(900),
        Some("png".to_owned()),
        Some("image/png".to_owned()),
        Some("us".to_owned()),
        Some("en".to_owned()),
        4,
    )
    .with_quality(88)
    .with_discovered_at(42);
    let expected_for_save = expected.clone();

    executor
        .with_unit_of_work(context(), move |mut work| {
            work.artwork().save_reference(&expected_for_save)?;
            work.commit()
        })
        .expect("reference commit");

    let actual = executor
        .with_unit_of_work(context(), |mut work| {
            let result = work
                .artwork()
                .references_for_external_game(ProviderId::GameTdb, "game-1");
            work.rollback()?;
            Ok(result?)
        })
        .expect("reference read");

    assert_eq!(actual, vec![expected]);
    executor.shutdown().expect("shutdown");
}
