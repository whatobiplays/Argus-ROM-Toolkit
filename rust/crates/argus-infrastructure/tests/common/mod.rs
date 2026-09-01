//! Shared migration fixtures for infrastructure integration tests.

use argus_infrastructure::sqlite::{Migration, MigrationRegistry};

/// Builds the complete migration chain as an explicitly custom registry.
///
/// Historical integration fixtures use this registry when reopening a
/// database seeded at an older schema. Calling `MigrationRegistry::new`
/// intentionally keeps the registry independent of the production embedded
/// registry's minimum-compatible-schema policy.
pub fn current_registry() -> MigrationRegistry {
    MigrationRegistry::new(vec![
        Migration::sql(
            1,
            "0001_initial",
            include_bytes!("../../src/sqlite/migrations/sql/0001_initial.sql"),
        ),
        Migration::sql(
            2,
            "0002_sources",
            include_bytes!("../../src/sqlite/migrations/sql/0002_sources.sql"),
        ),
        Migration::sql(
            3,
            "0003_jobs_scans",
            include_bytes!("../../src/sqlite/migrations/sql/0003_jobs_scans.sql"),
        ),
        Migration::sql(
            4,
            "0004_source_reconciliation",
            include_bytes!("../../src/sqlite/migrations/sql/0004_source_reconciliation.sql"),
        ),
        Migration::sql(
            5,
            "0005_source_hierarchy",
            include_bytes!("../../src/sqlite/migrations/sql/0005_source_hierarchy.sql"),
        ),
        Migration::sql(
            6,
            "0006_retry_and_progress",
            include_bytes!("../../src/sqlite/migrations/sql/0006_retry_and_progress.sql"),
        ),
        Migration::sql(
            7,
            "0007_scan_all_recovery",
            include_bytes!("../../src/sqlite/migrations/sql/0007_scan_all_recovery.sql"),
        ),
        Migration::sql(
            8,
            "0008_logical_library",
            include_bytes!("../../src/sqlite/migrations/sql/0008_logical_library.sql"),
        ),
        Migration::sql(
            9,
            "0009_metadata_providers_and_artwork",
            include_bytes!(
                "../../src/sqlite/migrations/sql/0009_metadata_providers_and_artwork.sql"
            ),
        ),
        Migration::sql(
            10,
            "0010_phase_003_product_state",
            include_bytes!("../../src/sqlite/migrations/sql/0010_phase_003_product_state.sql"),
        ),
        Migration::sql(
            11,
            "0011_phase_003_refresh_invocation",
            include_bytes!("../../src/sqlite/migrations/sql/0011_phase_003_refresh_invocation.sql"),
        ),
        Migration::sql(
            12,
            "0012_content_identity_catalog_expansion",
            include_bytes!(
                "../../src/sqlite/migrations/sql/0012_content_identity_catalog_expansion.sql"
            ),
        ),
        Migration::sql(
            13,
            "0013_optical_content_and_provenance",
            include_bytes!(
                "../../src/sqlite/migrations/sql/0013_optical_content_and_provenance.sql"
            ),
        ),
        Migration::sql(
            14,
            "0014_derived_source_entries",
            include_bytes!("../../src/sqlite/migrations/sql/0014_derived_source_entries.sql"),
        ),
        Migration::sql(
            15,
            "0015_library_browsing_projection",
            include_bytes!("../../src/sqlite/migrations/sql/0015_library_browsing_projection.sql"),
        ),
        Migration::sql(
            16,
            "0016_bounded_library_projection_keys",
            include_bytes!(
                "../../src/sqlite/migrations/sql/0016_bounded_library_projection_keys.sql"
            ),
        ),
        Migration::sql(
            17,
            "0017_derived_provenance_fingerprints",
            include_bytes!(
                "../../src/sqlite/migrations/sql/0017_derived_provenance_fingerprints.sql"
            ),
        ),
    ])
    .expect("current custom migration registry")
}
