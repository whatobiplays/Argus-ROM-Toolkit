"""Shared synthetic inputs and setup for host fixture staging tests."""

from __future__ import annotations

import copy
import hashlib
import importlib
import json
import tempfile
import time
import unittest
from pathlib import Path
from typing import Any
from unittest.mock import patch

from scripts.android_qualification import manifest
from scripts.android_qualification import _fixture_staging_destination as staging_destination
from scripts.android_qualification import _fixture_staging_manifest as staging_manifest
from scripts.android_qualification import _fixture_staging_model as staging_model
from scripts.android_qualification import _fixture_staging_orchestration
from scripts.android_qualification import _fixture_staging_ownership as staging_ownership
from scripts.android_qualification import fixture_staging
from scripts.android_qualification.test_manifest import (
    NOW,
    QUALIFICATION_PACKAGE,
    approval_document,
    authorization_document,
    write_private_json,
)


class _SyntheticCapacityObserverMixin:
    """Supply deterministic capacity only through private test adapters."""

    _synthetic_capacity_observer = None

    def _read_capacity_observation(self):
        observer = self._synthetic_capacity_observer
        if observer is None:
            return super()._read_capacity_observation()
        try:
            return observer(self.root)
        except staging_model.FixtureStagingError:
            raise
        except Exception:
            raise staging_model.FixtureStagingError(
                staging_model.FixtureStagingErrorCode.CAPACITY_UNPROVEN
            ) from None


class _SyntheticFixtureStagingOwnership(
    staging_ownership.FixtureStagingOwnership
):
    """Enable durability mechanics only for an explicitly synthetic owner."""

    _mutation_origin = "synthetic"

    def __init__(
        self,
        root: Path,
        *,
        capability,
        session_id_factory=None,
    ) -> None:
        self._synthetic_owner = staging_ownership._synthetic_namespace_owner(
            capability
        )
        super().__init__(
            root,
            session_id_factory=session_id_factory,
        )
        self._capability = capability

    def _require_mutation_capability(self, capability=None):
        staging_ownership._require_namespace_capability(
            capability,
            origin="synthetic",
            owner=self._synthetic_owner,
        )
        return capability


class _SyntheticAdmissionMixin:
    """Bind one explicit synthetic capability inside a private mechanics adapter."""

    _admission_origin = "synthetic"

    def __init__(
        self,
        root: Path,
        *,
        capability,
        capacity_observer=None,
        session_id_factory=None,
    ) -> None:
        staging_ownership._require_namespace_capability(
            capability, origin="synthetic"
        )
        self._synthetic_capability = capability
        self._synthetic_session_id_factory = session_id_factory
        self._synthetic_capacity_observer = capacity_observer
        super().__init__(root)

    def _new_ownership(self):
        return _SyntheticFixtureStagingOwnership(
            self.root,
            capability=self._synthetic_capability,
            session_id_factory=self._synthetic_session_id_factory,
        )

    def _synthetic_eligible_root(self, session_id: str, *, grant):
        """Resolve eligibility only for explicit private synthetic mechanics."""

        return self._eligible_root_impl(
            session_id,
            grant=grant,
            capability=self._synthetic_capability,
        )

    def _synthetic_final_path(self, session_id: str) -> Path:
        """Resolve a test-owned final pathname without claiming publication.

        Tests use this private helper to inspect both published and failed
        synthetic runs. Production eligibility must still use
        `_synthetic_eligible_root` and the published grant gate.
        """
        self._require_admitted_capability(self._synthetic_capability)
        return self._ownership.final_root(session_id)
    def _synthetic_temporary_path(self, session_id: str) -> Path:
        """Resolve a test-owned quarantine pathname for recovery inspection."""
        self._require_admitted_capability(self._synthetic_capability)
        return self._ownership.temporary_root(session_id)
    def _synthetic_file_mtime_ns(
        self,
        session_id: str,
        fixture_id: str,
        relative_path: str,
        *,
        grant,
    ) -> int:
        """Read a verified member's timestamp through private mechanics."""
        return self._file_mtime_ns(
            session_id,
            fixture_id,
            relative_path,
            grant=grant,
            capability=self._synthetic_capability,
        )
class _SyntheticFilesystemFixtureDestination(
    _SyntheticCapacityObserverMixin,
    _SyntheticAdmissionMixin,
    staging_destination.FilesystemFixtureDestination,
):
    """Exercise destination mechanics without claiming production isolation."""


def _canonical_sha256(document: object) -> str:
    encoded = json.dumps(
        document,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()

def _sync_oracle(fixture: dict[str, Any]) -> None:
    """Keep synthetic fixtures owner-approved without claiming an oracle."""
    fixture.pop("oracle", None)
    fixture["identity_evidence"] = "owner_approved_expectation_match"

def _stage_fixtures_for_synthetic_mechanics(
    capability,
    grant: staging_model.FixtureStagingGrant,
    **kwargs: Any,
) -> staging_model.FixtureStagingResult:
    """Exercise transfer mechanics with no production isolation claim.

    This adapter is private to the test support module. Existing tests use it
    to verify ownership, streaming, publication, and recovery mechanics on a
    synthetic destination. It cannot establish that a production destination
    namespace is isolated from another process running as the same user.
    """

    kwargs.pop("now", None)
    kwargs.pop("capability", None)
    monotonic_clock = kwargs.pop("monotonic_clock", None)
    if monotonic_clock is not None:
        owner = staging_ownership._synthetic_namespace_owner(capability)
        capability = staging_ownership._issue_synthetic_namespace_capability(
            owner=owner,
            monotonic_clock=monotonic_clock
        )
    staging_ownership._require_namespace_capability(capability, origin="synthetic")
    return _fixture_staging_orchestration._stage_fixtures_with_capability(
        grant,
        capability=capability,
        **kwargs,
    )


def _cleanup_fixture_staging_for_synthetic_mechanics(
    capability,
    grant: staging_model.FixtureStagingGrant,
    **kwargs: Any,
) -> staging_model.FixtureCleanupResult:
    """Exercise cleanup mechanics without claiming production isolation."""

    kwargs.pop("now", None)
    kwargs.pop("capability", None)
    staging_ownership._require_namespace_capability(capability, origin="synthetic")
    return _fixture_staging_orchestration._cleanup_fixture_staging_with_capability(
        grant,
        capability=capability,
        **kwargs,
    )


def _fixture_documents() -> tuple[dict[str, Any], dict[str, Any]]:
    """Return a pinned full-plan and one-fixture manifest for synthetic data."""
    rules = {"expectation_policy": "owner-approved-expectation-match"}
    plan = {
        "schema_version": 1,
        "rules": rules,
        "scenario_ids": ["scenario-synthetic"],
        "fixture_coverage": {
            "mode": "mandatory_full_plan",
            "required_fixture_ids": ["fixture-synthetic"],
            "selected_fixture_ids": ["fixture-synthetic"],
            "mandatory_fixture_ids": ["fixture-synthetic"],
        },
        "host_reserve_bytes": 0,
    }
    data = b"synthetic-rom-content-v1"
    digest = hashlib.sha256(data).hexdigest()
    companion_graph: list[dict[str, object]] = []
    fixture = {
        "fixture_id": "fixture-synthetic",
        "platform": "Synthetic Platform",
        "representation": "raw-file",
        "identity": "Synthetic Game",
        "group_id": "group-synthetic",
        "order": 0,
        "entrypoint": "game.rom",
        "files": [
            {
                "path": "game.rom",
                "role": "content",
                "size": len(data),
                "sha256": digest,
            }
        ],
        "companions": companion_graph,
        "identity_evidence": "owner_approved_expectation_match",
    }
    fixture_manifest = {
        "schema_version": 1,
        "plan_sha256": _canonical_sha256(plan),
        "rules_sha256": _canonical_sha256(rules),
        "coverage_mode": "mandatory_full_plan",
        "selected_fixture_ids": ["fixture-synthetic"],
        "fixtures": [fixture],
    }
    return plan, fixture_manifest

class FixtureStagingTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.directory = Path(self.temporary_directory.name)
        self.production_stage_fixtures = fixture_staging.stage_fixtures
        self.production_cleanup_fixture_staging = fixture_staging.cleanup_fixture_staging
        self.plan_document, self.fixture_document = _fixture_documents()
        self.plan_path = write_private_json(
            self.directory, "plan.json", self.plan_document
        )
        self.fixture_path = write_private_json(
            self.directory, "fixtures.json", self.fixture_document
        )
        self.authorization_document = authorization_document()
        self.authorization_document["plan"] = {
            "plan_sha256": _canonical_sha256(self.plan_document),
            "rules_sha256": _canonical_sha256(self.plan_document["rules"]),
            "scenario_ids": ["scenario-synthetic"],
        }
        self.authorization_document["fixture_manifest_sha256"] = _canonical_sha256(
            self.fixture_document
        )
        self.authorization_document["operations"].append(
            {
                "operation_id": "fixture-stage-synthetic",
                "category": "fixture_staging",
                "phase": "admission",
                "target_serial": "private-serial-synthetic",
                "package_name": QUALIFICATION_PACKAGE,
                "timeout_seconds": 30,
                "permission_name": None,
                "expected_prior_state": None,
                "desired_state": None,
                "restoration": None,
            }
        )
        self.authorization_path = write_private_json(
            self.directory,
            "authorization.json",
            self.authorization_document,
        )
        self.authorization = manifest.load_authorization(self.authorization_path)
        self.approval_path = write_private_json(
            self.directory,
            "approval.json",
            approval_document(self.authorization.canonical_sha256),
        )
        self.approval = manifest.load_owner_approval(
            self.approval_path, self.authorization, now=NOW
        )
        self.staging_now = [NOW]
        self.staging_clock_patch = patch.object(staging_manifest, "_utc_now",
            side_effect=lambda: self.staging_now[0],
            create=True,
        )
        self.staging_clock_patch.start()
        self.addCleanup(self.staging_clock_patch.stop)
        self.staging_monotonic = [time.monotonic()]

        def test_monotonic_clock():
            return self.staging_monotonic[0]

        self.synthetic_owner = object()
        self.synthetic_capability = (
            staging_ownership._issue_synthetic_namespace_capability(
                owner=self.synthetic_owner,
                monotonic_clock=test_monotonic_clock
            )
        )
        self.staging_boot = (
            "01234567-89ab-cdef-0123-456789abcdef",
            "linux-boot-id",
        )
        self.staging_boot_patch = patch.object(
            staging_model,
            "_boot_identity",
            side_effect=lambda: self.staging_boot,
        )
        self.staging_boot_patch.start()
        self.addCleanup(self.staging_boot_patch.stop)

    def _require_staging_module(self):
        self.assertIsNotNone(
            fixture_staging,
            "the owner-authorized fixture staging interface is not implemented",
        )
        return fixture_staging

    def _authorize(self, *, authorization=None, approval=None, operation_id=None):
        api = self._require_staging_module()
        return api.authorize_fixture_staging(
            self.authorization if authorization is None else authorization,
            self.approval if approval is None else approval,
            plan_path=self.plan_path,
            fixture_manifest_path=self.fixture_path,
            operation_id=(
                "fixture-stage-synthetic" if operation_id is None else operation_id
            ),
        )

    def _rebind_inputs(self, *, plan=None, fixture_manifest=None) -> None:
        if plan is not None:
            self.plan_document = plan
        if fixture_manifest is not None:
            self.fixture_document = fixture_manifest
        self.fixture_document["plan_sha256"] = _canonical_sha256(self.plan_document)
        self.fixture_document["rules_sha256"] = _canonical_sha256(
            self.plan_document["rules"]
        )
        self.plan_path = write_private_json(
            self.directory, "plan.json", self.plan_document
        )
        self.fixture_path = write_private_json(
            self.directory, "fixtures.json", self.fixture_document
        )
        self.authorization_document["plan"] = {
            "plan_sha256": _canonical_sha256(self.plan_document),
            "rules_sha256": _canonical_sha256(self.plan_document["rules"]),
            "scenario_ids": self.plan_document["scenario_ids"],
        }
        self.authorization_document["fixture_manifest_sha256"] = _canonical_sha256(
            self.fixture_document
        )
        self.authorization_path = write_private_json(
            self.directory,
            "authorization.json",
            self.authorization_document,
        )
        self.authorization = manifest.load_authorization(self.authorization_path)
        self.approval_path = write_private_json(
            self.directory,
            "approval.json",
            approval_document(self.authorization.canonical_sha256),
        )
        self.approval = manifest.load_owner_approval(
            self.approval_path, self.authorization, now=NOW
        )

    def _make_staging_inputs(
        self,
        *,
        capability,
        capacity_observer=None,
        destination_type=None,
        session_id_factory=None,
        source_entries=None,
        grant=None,
        suffix="",
    ):
        api = self._require_staging_module()
        source_root = self.directory / f"source{suffix}"
        source_root.mkdir(mode=0o700)
        entries = {"game.rom": b"synthetic-rom-content-v1"}
        if source_entries is not None:
            entries = source_entries
        for relative_path, content in entries.items():
            path = source_root / relative_path
            path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
            path.write_bytes(content)
        destination_root = self.directory / f"destination{suffix}"
        destination_root.mkdir(mode=0o700)
        observer = capacity_observer or (
            lambda _root: api.CapacityObservation(10**12, 10**12)
        )
        if destination_type is None:
            destination_class = _SyntheticFilesystemFixtureDestination
        else:
            destination_class = type(
                f"_Synthetic{destination_type.__name__}",
                (
                    _SyntheticCapacityObserverMixin,
                    _SyntheticAdmissionMixin,
                    destination_type,
                ),
                {},
            )
        destination = destination_class(
            destination_root,
            capability=capability,
            session_id_factory=session_id_factory,
        )
        destination._synthetic_capacity_observer = observer
        authority = self._authorize() if grant is None else grant
        return api, source_root, destination, authority

    def _make_synthetic_ownership(
        self,
        root: Path,
        *,
        session_id_factory=None,
    ):
        return _SyntheticFixtureStagingOwnership(
            root,
            capability=self.synthetic_capability,
            session_id_factory=session_id_factory,
        )
