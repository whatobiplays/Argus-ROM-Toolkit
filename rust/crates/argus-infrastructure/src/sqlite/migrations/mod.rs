//! Exact-byte SQL migration registry and authoritative history validation.

use std::time::{SystemTime, UNIX_EPOCH};

use sha2::{Digest, Sha256};

use super::errors::MigrationError;

mod runner;

pub(crate) use runner::apply_migrations;

/// The migration implementation kind recorded in history.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum MigrationKind {
    Sql,
    Rust,
}

impl MigrationKind {
    pub(crate) fn as_str(self) -> &'static str {
        match self {
            Self::Sql => "sql",
            Self::Rust => "rust",
        }
    }
}

/// One immutable migration definition.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Migration {
    pub version: u32,
    pub name: String,
    pub kind: MigrationKind,
    pub bytes: Vec<u8>,
}

impl Migration {
    /// Creates an SQL migration whose checksum is based on the supplied bytes exactly.
    pub fn sql(version: u32, name: impl Into<String>, bytes: impl AsRef<[u8]>) -> Self {
        Self {
            version,
            name: name.into(),
            kind: MigrationKind::Sql,
            bytes: bytes.as_ref().to_vec(),
        }
    }

    /// Creates a Rust-assisted migration definition for history validation.
    pub fn rust(version: u32, name: impl Into<String>, bytes: impl AsRef<[u8]>) -> Self {
        Self {
            version,
            name: name.into(),
            kind: MigrationKind::Rust,
            bytes: bytes.as_ref().to_vec(),
        }
    }

    pub(crate) fn checksum(&self) -> String {
        let digest = Sha256::digest(&self.bytes);
        digest.iter().map(|byte| format!("{byte:02x}")).collect()
    }
}

/// Ordered immutable migration definitions used for one database startup.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct MigrationRegistry {
    migrations: Vec<Migration>,
    minimum_compatible_version: Option<u32>,
    #[cfg(feature = "test-support")]
    final_validation_failure: bool,
}

impl MigrationRegistry {
    /// Validates and constructs a registry. Versions must be exactly 1, 2, ... N.
    pub fn new(migrations: Vec<Migration>) -> Result<Self, MigrationError> {
        let mut names = std::collections::BTreeSet::new();
        for (expected, migration) in (1..).zip(migrations.iter()) {
            if migration.version != expected {
                return Err(MigrationError::InvalidOrdering);
            }
            if migration.name.is_empty() || !names.insert(migration.name.clone()) {
                return Err(MigrationError::Duplicate);
            }
            if migration.kind == MigrationKind::Sql
                && std::str::from_utf8(&migration.bytes).is_err()
            {
                return Err(MigrationError::InvalidSql);
            }
        }
        Ok(Self {
            migrations,
            minimum_compatible_version: None,
            #[cfg(feature = "test-support")]
            final_validation_failure: false,
        })
    }

    /// Returns the embedded production migration registry.
    ///
    /// Production startup rejects databases whose recorded history predates
    /// schema version 8. Custom registries keep independent compatibility
    /// semantics unless they opt into a floor explicitly.
    pub fn embedded() -> Self {
        Self::embedded_without_compatibility_floor().with_minimum_compatible_version(8)
    }

    /// Returns the complete embedded migration chain without a compatibility floor.
    ///
    /// This is the explicit custom-registry form for historical fixtures and
    /// other callers that intentionally own a different compatibility policy.
    /// The normal production open path always uses [`Self::embedded`], which
    /// applies the production minimum-supported schema.
    pub fn embedded_without_compatibility_floor() -> Self {
        Self::new(vec![
            Migration::sql(1, "0001_initial", include_bytes!("sql/0001_initial.sql")),
            Migration::sql(2, "0002_sources", include_bytes!("sql/0002_sources.sql")),
            Migration::sql(
                3,
                "0003_jobs_scans",
                include_bytes!("sql/0003_jobs_scans.sql"),
            ),
            Migration::sql(
                4,
                "0004_source_reconciliation",
                include_bytes!("sql/0004_source_reconciliation.sql"),
            ),
            Migration::sql(
                5,
                "0005_source_hierarchy",
                include_bytes!("sql/0005_source_hierarchy.sql"),
            ),
            Migration::sql(
                6,
                "0006_retry_and_progress",
                include_bytes!("sql/0006_retry_and_progress.sql"),
            ),
            Migration::sql(
                7,
                "0007_scan_all_recovery",
                include_bytes!("sql/0007_scan_all_recovery.sql"),
            ),
            Migration::sql(
                8,
                "0008_logical_library",
                include_bytes!("sql/0008_logical_library.sql"),
            ),
            Migration::sql(
                9,
                "0009_metadata_providers_and_artwork",
                include_bytes!("sql/0009_metadata_providers_and_artwork.sql"),
            ),
            Migration::sql(
                10,
                "0010_phase_003_product_state",
                include_bytes!("sql/0010_phase_003_product_state.sql"),
            ),
            Migration::sql(
                11,
                "0011_phase_003_refresh_invocation",
                include_bytes!("sql/0011_phase_003_refresh_invocation.sql"),
            ),
            Migration::sql(
                12,
                "0012_content_identity_catalog_expansion",
                include_bytes!("sql/0012_content_identity_catalog_expansion.sql"),
            ),
            Migration::sql(
                13,
                "0013_optical_content_and_provenance",
                include_bytes!("sql/0013_optical_content_and_provenance.sql"),
            ),
            Migration::sql(
                14,
                "0014_derived_source_entries",
                include_bytes!("sql/0014_derived_source_entries.sql"),
            ),
            Migration::sql(
                15,
                "0015_library_browsing_projection",
                include_bytes!("sql/0015_library_browsing_projection.sql"),
            ),
            Migration::sql(
                16,
                "0016_bounded_library_projection_keys",
                include_bytes!("sql/0016_bounded_library_projection_keys.sql"),
            ),
            Migration::sql(
                17,
                "0017_derived_provenance_fingerprints",
                include_bytes!("sql/0017_derived_provenance_fingerprints.sql"),
            ),
        ])
        .expect("embedded migration registry is valid")
    }

    /// Returns an explicitly custom historical registry for infrastructure
    /// tests. The selected prefix is derived from the same embedded migration
    /// definitions used by production, so fixture history cannot drift when a
    /// migration name, checksum, or ordering changes.
    #[cfg(feature = "test-support")]
    #[doc(hidden)]
    pub fn embedded_through_for_tests(version: usize) -> Self {
        let mut registry = Self::embedded_without_compatibility_floor();
        assert!(
            version > 0 && version <= registry.migrations.len(),
            "historical test registry version {version} is outside the embedded migration chain"
        );
        registry.migrations.truncate(version);
        registry
    }

    pub(crate) fn as_slice(&self) -> &[Migration] {
        &self.migrations
    }

    /// Applies an explicit minimum compatible schema to this registry.
    ///
    /// Registries created with [`Self::new`] have no compatibility floor by
    /// default. Callers that need one must opt in explicitly; this is separate
    /// from the production policy applied by [`Self::embedded`].
    ///
    /// # Panics
    ///
    /// Panics if `version` is outside the registry's supported schema range.
    pub fn with_minimum_compatible_version(mut self, version: u32) -> Self {
        let final_version = self
            .migrations
            .last()
            .map(|migration| migration.version)
            .unwrap_or(0);
        assert!(
            version > 0 && version <= final_version,
            "minimum compatible schema {version} must be within registry's supported version range 1..={final_version}"
        );
        self.minimum_compatible_version = Some(version);
        self
    }

    pub(crate) fn minimum_compatible_version(&self) -> Option<u32> {
        self.minimum_compatible_version
    }

    /// Enables a deterministic validator failure for rollback regression
    /// tests. This seam is compiled only for infrastructure test support.
    #[cfg(feature = "test-support")]
    #[doc(hidden)]
    pub fn with_final_validation_failure_for_tests(mut self) -> Self {
        self.final_validation_failure = true;
        self
    }

    #[cfg(feature = "test-support")]
    pub(crate) fn final_validation_should_fail(&self) -> bool {
        self.final_validation_failure
    }
}

/// Summary emitted by startup diagnostics after migration validation/application.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct MigrationSummary {
    pub applied_count: u32,
    pub current_version: u32,
    pub outcome: MigrationOutcome,
}

/// Stable migration outcome.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum MigrationOutcome {
    Applied,
    AlreadyCurrent,
}

impl Default for MigrationRegistry {
    fn default() -> Self {
        Self::embedded()
    }
}

pub(crate) fn timestamp() -> String {
    let seconds = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs())
        .unwrap_or(0);
    format!("{seconds}")
}
