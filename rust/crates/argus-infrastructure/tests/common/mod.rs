//! Shared migration fixtures for infrastructure integration tests.

use argus_infrastructure::sqlite::MigrationRegistry;

/// Builds the complete embedded migration chain as an explicitly custom registry.
///
/// Historical integration fixtures use this registry when reopening a
/// database seeded at an older schema. The explicit no-floor constructor keeps
/// this registry independent of the production embedded registry's
/// minimum-compatible-schema policy.
pub fn current_registry() -> MigrationRegistry {
    MigrationRegistry::embedded_without_compatibility_floor()
}
