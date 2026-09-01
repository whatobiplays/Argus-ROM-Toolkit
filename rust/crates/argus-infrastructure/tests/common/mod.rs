//! Shared migration fixtures for infrastructure integration tests.

use argus_infrastructure::sqlite::MigrationRegistry;

/// Builds the complete embedded migration chain as an explicitly custom registry.
///
/// Historical integration fixtures use this registry when reopening a
/// database seeded at an older schema. The explicit no-floor constructor keeps
/// this registry independent of the production embedded registry's
/// minimum-compatible-schema policy.
#[allow(dead_code)]
pub fn current_registry() -> MigrationRegistry {
    MigrationRegistry::embedded_without_compatibility_floor()
}

/// Builds a historical registry from the authoritative embedded migration
/// chain without applying the production compatibility floor.
pub fn registry_through(version: usize) -> MigrationRegistry {
    MigrationRegistry::embedded_through_for_tests(version)
}
