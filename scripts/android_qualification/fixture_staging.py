"""Public best-effort fixture staging API."""

from __future__ import annotations

from scripts.android_qualification.fixture_staging_contract import (
    CleanupResult,
    FixtureAssessment,
    StagingResult,
    default_staging_root,
)
from scripts.android_qualification.fixture_staging_orchestration import stage_fixtures
from scripts.android_qualification.fixture_staging_runs import cleanup_staging, inspect_staging

__all__ = [
    "CleanupResult",
    "FixtureAssessment",
    "StagingResult",
    "cleanup_staging",
    "default_staging_root",
    "inspect_staging",
    "stage_fixtures",
]
