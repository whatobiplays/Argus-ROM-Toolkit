"""Public API for validating and staging owner-authorized fixture data.

Private implementation modules separate authority parsing, content validation,
host transfers, authenticated native export dispatch, durable recovery, and
orchestration. Production staging remains fail closed until native identity,
owner consent, and kernel isolation have been verified.
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
    FIXTURE_SNAPSHOT_MANIFEST_SCHEMA_VERSION,
    MAX_PRIVATE_DOCUMENT_BYTES,
    authorize_fixture_staging,
)
from ._fixture_staging_destination import FilesystemFixtureDestination
from ._fixture_staging_native import (
    ProductionOwnerExportPreparation,
    create_production_owner_export_preparation,
    create_owner_session_export_client,
    SnapshotSupport,
    ValidatedNativeContractResult,
    ValidatedSnapshotContract,
    select_verified_native_installation,
    validate_native_contract_result,
    validate_snapshot_contract_for_grant,
)
from ._fixture_staging_session import OwnerExportDispatch
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
    'OwnerExportDispatch',
    'ProductionOwnerExportPreparation',
    'RecoveryObligation',
    'SnapshotSupport',
    'ValidatedNativeContractResult',
    'ValidatedSnapshotContract',
    'FIXTURE_MANIFEST_SCHEMA_VERSION',
    'FIXTURE_PLAN_SCHEMA_VERSION',
    'FIXTURE_SNAPSHOT_MANIFEST_SCHEMA_VERSION',
    'MAX_PRIVATE_DOCUMENT_BYTES',
    'authorize_fixture_staging',
    'cleanup_fixture_staging',
    'create_owner_session_export_client',
    'create_production_owner_export_preparation',
    'stage_fixtures',
    'select_verified_native_installation',
    'validate_native_contract_result',
    'validate_snapshot_contract_for_grant',
]
