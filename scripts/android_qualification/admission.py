"""Shared structural host-validation seam for both qualification entrypoints.

Despite the historical admission terminology in the qualification contract,
`admit_host_only` performs manifest structure checks only. It does not
establish SPEC-X-003 session authorization or session admission, inspect a
device, or permit qualification execution.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import NoReturn

from .manifest import QualificationManifest, StateMode, load_manifest


@dataclass(frozen=True)
class HostValidationResult:
    """A structurally valid manifest; no session has been admitted."""

    manifest: QualificationManifest


class LiveExecutionBlocked(Exception):
    """Raised when execution is requested before live admission exists."""

    def __init__(self) -> None:
        super().__init__("live authorization/device admission not implemented")


def admit_host_only(
    manifest_path: Path,
    expected_state_mode: StateMode,
) -> HostValidationResult:
    """Perform structural host validation only.

    `HOST_VALIDATED` does not establish session authorization or admission
    under SPEC-X-003 and does not begin a qualification session.
    """

    return HostValidationResult(
        manifest=load_manifest(manifest_path, expected_state_mode)
    )


def request_live_execution(_validation: HostValidationResult) -> NoReturn:
    """Refuse live execution until the later admission controls are implemented."""

    raise LiveExecutionBlocked()
