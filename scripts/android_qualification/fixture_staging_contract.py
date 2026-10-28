"""Shared values and result types for local fixture staging."""

from __future__ import annotations

import os
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping


DEFAULT_MINIMUM_FREE_BYTES = 256 * 1024 * 1024

class _StagingFailure(Exception):
    def __init__(self, code: str) -> None:
        self.code = code
        super().__init__(code)


@dataclass(frozen=True)
class FixtureFile:
    """One manifest-validated file and its expected bytes."""

    path: str
    role: str
    size: int
    sha256: str


@dataclass(frozen=True)
class FixtureCompanion:
    """An ordered relationship between two files in one fixture."""

    source: str
    target: str


@dataclass(frozen=True)
class FixtureSpec:
    """A fixture after its complete manifest entry has been validated."""

    fixture_id: str
    group_id: str
    order: int
    platform: str
    representation: str
    entrypoint: str
    expected_identity: Mapping[str, str | int | bool]
    structural_expectations: Mapping[str, str | int | bool]
    files: tuple[FixtureFile, ...]
    companions: tuple[FixtureCompanion, ...]
    identity_evidence: Mapping[str, object] | None
    identity_support: str
    qualification_status: str


@dataclass(frozen=True)
class FixturePlan:
    """Validated fixture selection rules and their canonical manifest digest."""

    manifest_sha256: str
    coverage_mode: str
    required_fixture_ids: tuple[str, ...]
    mandatory_fixture_ids: tuple[str, ...]
    fixtures: Mapping[str, FixtureSpec]


@dataclass(frozen=True)
class FixtureAssessment:
    """Separate verified bytes from identity evidence and qualification."""

    fixture_id: str
    byte_integrity: str
    structural_expectations: str
    identity_support: str
    owner_approval: str
    qualification_status: str

@dataclass(frozen=True)
class StagingResult:
    """Outcome of staging or inspecting one selected fixture set."""

    status: str
    run_id: str | None = None
    run_directory: Path | None = None
    published_path: Path | None = None
    manifest_sha256: str | None = None
    fixture_ids: tuple[str, ...] = ()
    file_count: int = 0
    byte_count: int = 0
    assessments: tuple[FixtureAssessment, ...] = ()
    error_code: str | None = None

@dataclass(frozen=True)
class CleanupResult:
    """Best-effort cleanup outcome for a recognizable staging run."""

    status: str
    run_id: str
    removed_files: int = 0
    error_code: str | None = None

def default_staging_root() -> Path:
    """Return a user-owned location outside the repository and source trees."""

    override = os.environ.get("ARGUS_FIXTURE_STAGING_ROOT")
    if override:
        return Path(override).expanduser()
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support" / "ArgusROMToolkit" / "FixtureStaging"
    state_home = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local" / "state"))
    return state_home / "argus-rom-toolkit" / "fixture-staging"
