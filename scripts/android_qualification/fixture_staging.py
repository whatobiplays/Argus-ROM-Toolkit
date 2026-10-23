"""Public host-only API for validating and staging fixture expectations.

Private implementation modules separate authority parsing, content validation,
transfers, durable destination recovery, and orchestration.
"""

from ._fixture_staging_model import (
    CapacityObservation,
    CompanionEdge,
    CoverageMode,
    FixtureCleanupResult,
    FixtureCoverage,
    FixtureExpectation,
    FixtureFileExpectation,
    FixtureStagingError,
    FixtureStagingErrorCode,
    FixtureStagingGrant,
    FixtureStagingResult,
    IdentityEvidenceKind,
    RecoveryObligation,
)
from ._fixture_staging_manifest import (
    FIXTURE_MANIFEST_SCHEMA_VERSION,
    FIXTURE_PLAN_SCHEMA_VERSION,
    MAX_PRIVATE_DOCUMENT_BYTES,
    authorize_fixture_staging,
)
from ._fixture_staging_destination import FilesystemFixtureDestination
from ._fixture_staging_orchestration import cleanup_fixture_staging, stage_fixtures

__all__ = [
    'CapacityObservation',
    'CompanionEdge',
    'CoverageMode',
    'FixtureCleanupResult',
    'FixtureCoverage',
    'FixtureExpectation',
    'FixtureFileExpectation',
    'FixtureStagingError',
    'FixtureStagingErrorCode',
    'FixtureStagingGrant',
    'FixtureStagingResult',
    'FilesystemFixtureDestination',
    'IdentityEvidenceKind',
    'RecoveryObligation',
    'FIXTURE_MANIFEST_SCHEMA_VERSION',
    'FIXTURE_PLAN_SCHEMA_VERSION',
    'MAX_PRIVATE_DOCUMENT_BYTES',
    'authorize_fixture_staging',
    'cleanup_fixture_staging',
    'stage_fixtures',
]
