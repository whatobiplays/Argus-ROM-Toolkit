"""Test host validation, private session admission, and simulated safe admission.

Device observations and permission state are supplied by deterministic fakes;
these tests never access an Android device.
"""

from __future__ import annotations

import copy
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import threading
import textwrap
from concurrent.futures import ThreadPoolExecutor
from dataclasses import replace
from datetime import timedelta
import unittest
from pathlib import Path
from unittest import mock

from scripts.android_qualification import admission, evidence, manifest
from scripts.android_qualification.physical import ui
from scripts.android_qualification.test_manifest import (
    MANAGE_EXTERNAL_STORAGE,
    NOW,
    QUALIFICATION_PACKAGE,
    approval_document,
    authorization_document,
    write_private_json,
)



class AdmissionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.directory = Path(self.temporary_directory.name)
        self.manifest_path = self.directory / "manifest.json"
        self.manifest_path.write_text(
            json.dumps(
                {
                    "schema_version": 1,
                    "authorization_ref": "authorization-synthetic",
                    "target_ref": "target-synthetic",
                    "artifact_ref": "artifact-synthetic",
                    "plan_ref": "plan-synthetic",
                    "scope_ref": "scope-synthetic",
                    "state_mode": "fresh",
                    "inherited_state_session_ref": None,
                }
            ),
            encoding="utf-8",
        )

    def test_host_validation_returns_only_structural_result(self) -> None:
        result = admission.admit_host_only(self.manifest_path, manifest.StateMode.FRESH)
        self.assertIsInstance(result, admission.HostValidationResult)
        self.assertEqual(result.manifest.state_mode, manifest.StateMode.FRESH)
        self.assertFalse(hasattr(result, "admitted"))
        self.assertIn(
            "does not establish session authorization or admission",
            admission.admit_host_only.__doc__ or "",
        )

    def test_live_handoff_fails_closed_with_required_message(self) -> None:
        validation = admission.admit_host_only(
            self.manifest_path, manifest.StateMode.FRESH
        )
        with self.assertRaises(admission.LiveExecutionBlocked) as caught:
            admission.request_live_execution(validation)
        self.assertEqual(
            str(caught.exception),
            "live authorization/device admission not implemented",
        )

    def test_host_and_live_paths_have_no_subprocess_boundary(self) -> None:
        validation = admission.admit_host_only(
            self.manifest_path, manifest.StateMode.FRESH
        )
        with mock.patch("subprocess.run", side_effect=AssertionError("subprocess")), \
             mock.patch("subprocess.Popen", side_effect=AssertionError("subprocess")), \
             mock.patch("os.system", side_effect=AssertionError("subprocess")):
            admission.admit_host_only(self.manifest_path, manifest.StateMode.FRESH)
            with self.assertRaises(admission.LiveExecutionBlocked):
                admission.request_live_execution(validation)

    def test_implementation_has_no_device_or_legacy_runner_reference(self) -> None:
        module_directory = Path(__file__).resolve().parent
        names = (
            "manifest.py",
            "admission.py",
            "cli.py",
            "fresh.py",
            "no_reset.py",
        )
        for name in names:
            with self.subTest(name=name):
                source = (module_directory / name).read_text(encoding="utf-8")
                self.assertNotIn("adb", source.casefold())
                self.assertNotIn("subprocess", source)
                self.assertNotIn("Popen(", source)
                self.assertNotIn("os.system", source)
                self.assertNotIn("phase_" + "003", source)
                self.assertNotIn("run_phase_", source)
                self.assertNotIn("keyring", source)
                if name in {"cli.py", "fresh.py", "no_reset.py"}:
                    self.assertNotIn("ADMITTED", source)


# Simulated read-only admission tests.
class FakeAdmissionTransport:
    """Synthetic read-only observations; this is not device evidence."""

    def __init__(self, observation: admission.FreshAdmissionObservation | None = None) -> None:
        self.observation = observation or valid_observation()
        self.observation_calls = 0
        self.mutation_calls = 0

    def observe_fresh_admission(self) -> admission.FreshAdmissionObservation:
        self.observation_calls += 1
        return self.observation

    def observe_no_reset_baseline(self, _authorization):
        raise AssertionError("no-reset admission must not treat this synthetic interface as proof")


def valid_observation() -> admission.FreshAdmissionObservation:
    return admission.FreshAdmissionObservation(
        connected_serials=("private-serial-synthetic",),
        android_api_level=35,
        abi="arm64-v8a",
        capabilities=frozenset(
            {
                "foreground_package_observation",
                "installed_signer_observation",
                "permission_app_op_observation",
                "permission_app_op_mutation",
                "storage_reserve_observation",
            }
        ),
        installation=admission.InstallationObservation(
            status=admission.InstallationStatus.PRESENT,
            package_name=QUALIFICATION_PACKAGE,
            version_code=123,
            certificate_sha256="b" * 64,
        ),
        foreground_package=QUALIFICATION_PACKAGE,
        interference_free=True,
        available_storage_bytes=2_000_000_000,
    )


class DeviceAdmissionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.directory = Path(self.temporary_directory.name)
        self.registry_path = self.directory / "host-state" / "session-registry.json"
        self.registry_path_patch = mock.patch.object(
            admission,
            "_SESSION_REGISTRY_PATH",
            self.registry_path,
            create=True,
        )
        self.registry_path_patch.start()
        self.addCleanup(self.registry_path_patch.stop)
        self.safety_path = self.directory / "host-state" / "device-restoration.json"
        self.safety_path_patch = mock.patch.object(
            admission,
            "_DEVICE_SAFETY_PATH",
            self.safety_path,
            create=True,
        )
        self.safety_path_patch.start()
        self.addCleanup(self.safety_path_patch.stop)
        self.document = authorization_document()
        self.session_counter = 0
        self.auth = self._load_auth(self.document)
        self.approval = self._load_approval(self.auth)
        self.artifact = admission.HostArtifactFacts(
            apk_sha256="a" * 64,
            package_name=QUALIFICATION_PACKAGE,
            version_code=123,
            signature_verified=True,
            signer_count=1,
            certificate_sha256="b" * 64,
            source_revision="c" * 40,
            declared_permissions=frozenset({MANAGE_EXTERNAL_STORAGE}),
        )

    def _load_auth(self, document) -> manifest.SessionAuthorization:
        return manifest.load_authorization(
            write_private_json(self.directory, "authorization.json", document)
        )

    def _load_approval(self, auth) -> manifest.OwnerApproval:
        self.approval_path = write_private_json(
            self.directory,
            "approval.json",
            approval_document(auth.canonical_sha256),
        )
        return manifest.load_owner_approval(self.approval_path, auth, now=NOW)

    def _admit(self, transport, *, auth=None, artifact=None, approval=None, now=NOW):
        return admission.admit_session(
            auth or self.auth,
            approval or self.approval,
            artifact or self.artifact,
            transport,
            now=now,
        )

    def _start_distinct_test_session(self, *, fresh_authorization: bool = True) -> None:
        if fresh_authorization:
            self.session_counter += 1
            document = authorization_document()
            document["authorization_id"] = f"authorization-synthetic-{self.session_counter}"
            self.auth = self._load_auth(document)
            self.approval = self._load_approval(self.auth)
    def test_fresh_simulated_admission_requires_exact_read_only_observations(self) -> None:
        transport = FakeAdmissionTransport()
        result = self._admit(transport)
        self.assertEqual(result.status, admission.AdmissionStatus.ADMITTED)
        self.assertIsNotNone(result.session)
        self.assertEqual(transport.observation_calls, 1)
        self.assertEqual(transport.mutation_calls, 0)

    def test_caller_constructed_authorization_is_rejected_before_side_effects(self) -> None:
        constructed = replace(self.auth)
        transport = FakeAdmissionTransport()

        result = self._admit(transport, auth=constructed)

        self.assertEqual(result.status, admission.AdmissionStatus.BLOCKED)
        self.assertEqual(result.code, admission.AdmissionCode.APPROVAL_INVALID)
        self.assertEqual(transport.observation_calls, 0)
        self.assertFalse(self.registry_path.exists())

    def test_forged_authorization_cannot_reuse_copied_loader_markers(self) -> None:
        forged = replace(self.auth, target_serial="forged-target-synthetic")
        object.__setattr__(
            forged,
            "_loader_provenance",
            getattr(self.auth, "_loader_provenance", None),
        )
        object.__setattr__(
            forged,
            "_loader_integrity",
            manifest._authorization_integrity_value(forged),
        )
        transport = FakeAdmissionTransport()

        result = self._admit(transport, auth=forged)

        self.assertEqual(result.status, admission.AdmissionStatus.BLOCKED)
        self.assertEqual(result.code, admission.AdmissionCode.APPROVAL_INVALID)
        self.assertEqual(transport.observation_calls, 0)
        self.assertEqual(transport.mutation_calls, 0)
        self.assertFalse(self.registry_path.exists())

    def test_altered_authorization_cannot_reseal_its_loader_integrity(self) -> None:
        object.__setattr__(self.auth, "target_serial", "forged-target-synthetic")
        object.__setattr__(
            self.auth,
            "_loader_integrity",
            manifest._authorization_integrity_value(self.auth),
        )
        transport = FakeAdmissionTransport()

        result = self._admit(transport)

        self.assertEqual(result.status, admission.AdmissionStatus.BLOCKED)
        self.assertEqual(result.code, admission.AdmissionCode.APPROVAL_INVALID)
        self.assertEqual(transport.observation_calls, 0)
        self.assertEqual(transport.mutation_calls, 0)
        self.assertFalse(self.registry_path.exists())

    def test_modified_authorization_target_is_rejected_before_side_effects(self) -> None:
        object.__setattr__(self.auth, "target_serial", "forged-target-synthetic")
        transport = FakeAdmissionTransport()

        result = self._admit(transport)

        self.assertEqual(result.status, admission.AdmissionStatus.BLOCKED)
        self.assertEqual(result.code, admission.AdmissionCode.APPROVAL_INVALID)
        self.assertEqual(transport.observation_calls, 0)
        self.assertFalse(self.registry_path.exists())

    def test_modified_authorization_operation_is_rejected_before_side_effects(self) -> None:
        altered_operation = replace(self.auth.operations[0], operation_id="forged-operation-synthetic")
        object.__setattr__(self.auth, "operations", (altered_operation, *self.auth.operations[1:]))
        transport = FakeAdmissionTransport()

        result = self._admit(transport)

        self.assertEqual(result.status, admission.AdmissionStatus.BLOCKED)
        self.assertEqual(result.code, admission.AdmissionCode.APPROVAL_INVALID)
        self.assertEqual(transport.observation_calls, 0)
        self.assertFalse(self.registry_path.exists())

    def test_global_session_registry_is_private_and_stores_only_opaque_identity_and_digest(self) -> None:
        first_transport = FakeAdmissionTransport()
        first_result = self._admit(first_transport)
        self.assertEqual(first_result.status, admission.AdmissionStatus.ADMITTED)

        registry_directory = self.registry_path.parent
        self.assertEqual(registry_directory.stat().st_mode & 0o777, 0o700)
        self.assertEqual(self.registry_path.stat().st_mode & 0o777, 0o600)
        lock_path = registry_directory / "session-registry.lock"
        self.assertEqual(lock_path.stat().st_mode & 0o777, 0o600)
        registry = json.loads(self.registry_path.read_text(encoding="utf-8"))
        self.assertEqual(set(registry), {"schema_version", "sessions"})
        self.assertEqual(registry["schema_version"], 1)
        self.assertEqual(
            registry["sessions"],
            [
                {
                    "authorization_id": self.auth.authorization_id,
                    "authorization_sha256": self.auth.canonical_sha256,
                }
            ],
        )
        self.assertNotIn(self.auth.owner_identity, self.registry_path.read_text(encoding="utf-8"))
        self.assertNotIn(self.auth.target_serial, self.registry_path.read_text(encoding="utf-8"))

        reopened_approval = manifest.load_owner_approval(self.approval_path, self.auth, now=NOW)
        retry_transport = FakeAdmissionTransport()
        retry_result = self._admit(retry_transport, approval=reopened_approval)

        self.assertEqual(retry_result.status, admission.AdmissionStatus.BLOCKED)
        self.assertEqual(retry_result.code, admission.AdmissionCode.SESSION_ALREADY_USED)
        self.assertEqual(retry_transport.observation_calls, 0)

    def test_session_use_survives_restart_and_sidecar_copy(self) -> None:
        first_result = self._admit(FakeAdmissionTransport())
        self.assertEqual(first_result.status, admission.AdmissionStatus.ADMITTED)

        copied_directory = self.directory / "copied-private-inputs"
        copied_directory.mkdir(mode=0o700)
        copied_authorization_path = copied_directory / "authorization.json"
        copied_approval_path = copied_directory / "approval.json"
        copied_authorization_path.write_bytes((self.directory / "authorization.json").read_bytes())
        copied_approval_path.write_bytes(self.approval_path.read_bytes())
        copied_authorization_path.chmod(0o600)
        copied_approval_path.chmod(0o600)

        # A fresh interpreter has no shared process memory or registry.
        child = """
import sys
from pathlib import Path
from scripts.android_qualification import admission, manifest
from scripts.android_qualification.test_admission import FakeAdmissionTransport
from scripts.android_qualification.test_manifest import NOW

admission._SESSION_REGISTRY_PATH = Path(sys.argv[3])
authorization = manifest.load_authorization(Path(sys.argv[1]))
approval = manifest.load_owner_approval(Path(sys.argv[2]), authorization, now=NOW)
artifact = admission.HostArtifactFacts(
    apk_sha256="a" * 64,
    package_name="com.argusromtoolkit.argus.qualification",
    version_code=123,
    signature_verified=True,
    signer_count=1,
    certificate_sha256="b" * 64,
    source_revision="c" * 40,
    declared_permissions=frozenset({"android.permission.MANAGE_EXTERNAL_STORAGE"}),
)
transport = FakeAdmissionTransport()
result = admission.admit_session(authorization, approval, artifact, transport, now=NOW)
print(f"{result.code.value}:{transport.observation_calls}")
"""
        completed = subprocess.run(
            [
                sys.executable,
                "-c",
                child,
                str(copied_authorization_path),
                str(copied_approval_path),
                str(self.registry_path),
            ],
            check=False,
            capture_output=True,
            text=True,
        )

        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(completed.stdout.strip(), "SESSION_ALREADY_USED:0")

    def test_concurrent_admission_atomically_claims_only_one_session(self) -> None:
        barrier = threading.Barrier(2)
        transports = (FakeAdmissionTransport(), FakeAdmissionTransport())

        def admit(transport):
            barrier.wait()
            return self._admit(transport)

        with ThreadPoolExecutor(max_workers=2) as executor:
            results = list(executor.map(admit, transports))

        self.assertEqual(
            sorted(result.code for result in results),
            sorted((admission.AdmissionCode.ADMITTED, admission.AdmissionCode.SESSION_ALREADY_USED)),
        )
        self.assertEqual(sum(transport.observation_calls for transport in transports), 1)
        registry = json.loads(self.registry_path.read_text(encoding="utf-8"))
        self.assertEqual(len(registry["sessions"]), 1)

    def test_admission_fails_closed_when_approval_directory_is_not_private(self) -> None:
        public_directory = self.directory / "public"
        public_directory.mkdir(mode=0o700)
        approval_path = write_private_json(
            public_directory,
            "approval.json",
            approval_document(self.auth.canonical_sha256),
        )
        public_approval = manifest.load_owner_approval(approval_path, self.auth, now=NOW)
        public_directory.chmod(0o755)
        transport = FakeAdmissionTransport()

        try:
            result = self._admit(transport, approval=public_approval)
        finally:
            public_directory.chmod(0o700)

        self.assertEqual(result.status, admission.AdmissionStatus.BLOCKED)
        self.assertEqual(result.code, admission.AdmissionCode.SESSION_STATE_UNAVAILABLE)
        self.assertEqual(transport.observation_calls, 0)

        original_stat = self.approval_path.stat()
        document = json.loads(self.approval_path.read_text(encoding="utf-8"))
        document["owner_identity"] = document["owner_identity"][::-1]
        changed = json.dumps(document, separators=(",", ":")).encode("utf-8")
        with self.approval_path.open("r+b") as sidecar:
            sidecar.write(changed)
            sidecar.truncate()
        self.assertEqual(self.approval_path.stat().st_ino, original_stat.st_ino)

        changed_sidecar_transport = FakeAdmissionTransport()
        changed_sidecar_result = self._admit(changed_sidecar_transport)
        self.assertEqual(changed_sidecar_result.status, admission.AdmissionStatus.BLOCKED)
        self.assertEqual(
            changed_sidecar_result.code,
            admission.AdmissionCode.SESSION_STATE_UNAVAILABLE,
        )
        self.assertEqual(changed_sidecar_transport.observation_calls, 0)

    def test_admission_fails_closed_when_session_registry_path_is_a_symlink(self) -> None:
        self.registry_path.parent.mkdir(mode=0o700)
        outside_path = self.directory / "outside-registry.json"
        outside_path.write_text('{"schema_version":1,"sessions":[]}', encoding="utf-8")
        outside_path.chmod(0o600)
        self.registry_path.symlink_to(outside_path)
        transport = FakeAdmissionTransport()

        result = self._admit(transport)

        self.assertEqual(result.status, admission.AdmissionStatus.BLOCKED)
        self.assertIn(
            result.code,
            {admission.AdmissionCode.SESSION_ALREADY_USED, admission.AdmissionCode.SESSION_STATE_UNAVAILABLE},
        )
        self.assertEqual(transport.observation_calls, 0)

    def test_synthesized_owner_approval_cannot_admit_a_session(self) -> None:
        synthesized = manifest.OwnerApproval(
            self.approval.authorization_sha256,
            self.approval.owner_identity,
            self.approval.valid_from,
            self.approval.valid_until,
        )
        transport = FakeAdmissionTransport()

        result = self._admit(transport, approval=synthesized)

        self.assertEqual(result.status, admission.AdmissionStatus.BLOCKED)
        self.assertEqual(result.code, admission.AdmissionCode.APPROVAL_INVALID)
        self.assertEqual(transport.observation_calls, 0)

    def test_mutated_owner_approval_fields_are_rejected_before_consumption(self) -> None:
        later_in_session = NOW + timedelta(minutes=3, seconds=30)
        for field, value, attempt_time in (
            ("authorization_sha256", "0" * 64, NOW),
            ("owner_identity", "forged-owner-synthetic", NOW),
            ("valid_from", self.auth.issued_at, NOW),
            ("valid_until", self.auth.session_deadline, later_in_session),
        ):
            with self.subTest(field=field):
                self._start_distinct_test_session()
                object.__setattr__(self.approval, field, value)
                registry_path = (
                    self.directory / f"approval-state-{field}" / "session-registry.json"
                )
                transport = FakeAdmissionTransport()

                with mock.patch.object(admission, "_SESSION_REGISTRY_PATH", registry_path):
                    result = self._admit(transport, now=attempt_time)

                self.assertEqual(result.status, admission.AdmissionStatus.BLOCKED)
                self.assertEqual(result.code, admission.AdmissionCode.APPROVAL_INVALID)
                self.assertEqual(transport.observation_calls, 0)
                self.assertEqual(transport.mutation_calls, 0)
                self.assertFalse(registry_path.exists())

    def test_forged_owner_approval_cannot_copy_loader_markers_or_reseal_fields(self) -> None:
        forged = replace(self.approval, valid_until=self.auth.session_deadline)
        for field in (
            "_loader_provenance",
            "_source_path",
            "_source_directory_identity",
            "_source_file_identity",
            "_source_bytes_sha256",
        ):
            object.__setattr__(forged, field, getattr(self.approval, field, None))
        registry_path = self.directory / "forged-approval-state" / "session-registry.json"
        transport = FakeAdmissionTransport()

        with mock.patch.object(admission, "_SESSION_REGISTRY_PATH", registry_path):
            result = self._admit(
                transport,
                approval=forged,
                now=NOW + timedelta(minutes=3, seconds=30),
            )

        self.assertEqual(result.status, admission.AdmissionStatus.BLOCKED)
        self.assertEqual(result.code, admission.AdmissionCode.APPROVAL_INVALID)
        self.assertEqual(transport.observation_calls, 0)
        self.assertEqual(transport.mutation_calls, 0)
        self.assertFalse(registry_path.exists())

    def test_no_reset_is_blocked_without_independent_baseline_observer(self) -> None:
        document = authorization_document()
        document["state"] = {
            "mode": "no-reset",
            "inherited_state_session_id": "private-prior-session",
            "no_reset_baseline": {
                "library_fixture_ids": ["private-fixture"],
                "job_states": [{"job_id": "private-job", "state": "pending"}],
                "pending_cleanup_ids": [],
            },
        }
        auth = self._load_auth(document)
        approval = self._load_approval(auth)
        transport = FakeAdmissionTransport()
        result = self._admit(transport, auth=auth, approval=approval)
        self.assertEqual(result.status, admission.AdmissionStatus.BLOCKED)
        self.assertEqual(result.code, admission.AdmissionCode.NO_RESET_OBSERVATION_UNAVAILABLE)
        self.assertEqual(transport.observation_calls, 0)
        self.assertEqual(transport.mutation_calls, 0)

    def test_missing_and_incompatible_fresh_installations_have_distinct_blocks(self) -> None:
        absent = replace(valid_observation(), installation=admission.InstallationObservation.absent())
        absent_result = self._admit(FakeAdmissionTransport(absent))
        self.assertEqual(absent_result.code, admission.AdmissionCode.QUALIFICATION_APP_ABSENT)

        incompatible = replace(
            valid_observation(),
            installation=admission.InstallationObservation(
                status=admission.InstallationStatus.PRESENT,
                package_name="com.example.foreign",
                version_code=123,
                certificate_sha256="b" * 64,
            ),
        )
        self._start_distinct_test_session()
        incompatible_result = self._admit(FakeAdmissionTransport(incompatible))
        self.assertEqual(incompatible_result.code, admission.AdmissionCode.QUALIFICATION_APP_INCOMPATIBLE)

    def test_target_os_abi_and_capability_mismatches_are_blocked_without_mutation(self) -> None:
        cases = (
            (replace(valid_observation(), connected_serials=()), admission.AdmissionCode.NO_TARGET),
            (replace(valid_observation(), connected_serials=("other", "private-serial-synthetic")), admission.AdmissionCode.AMBIGUOUS_TARGET),
            (replace(valid_observation(), connected_serials=("other",)), admission.AdmissionCode.TARGET_MISMATCH),
            (replace(valid_observation(), android_api_level=29), admission.AdmissionCode.OS_UNSUPPORTED),
            (replace(valid_observation(), abi="x86_64"), admission.AdmissionCode.ABI_MISMATCH),
            (replace(valid_observation(), capabilities=frozenset()), admission.AdmissionCode.CAPABILITY_UNAVAILABLE),
        )
        for observation, expected in cases:
            with self.subTest(expected=expected):
                self._start_distinct_test_session()
                transport = FakeAdmissionTransport(observation)
                result = self._admit(transport)
                self.assertEqual(result.status, admission.AdmissionStatus.BLOCKED)
                self.assertEqual(result.code, expected)
                self.assertEqual(transport.mutation_calls, 0)

    def test_artifact_properties_are_only_admitted_when_exact_host_facts_match(self) -> None:
        for field, value in (
            ("apk_sha256", "0" * 64),
            ("package_name", "com.example.foreign"),
            ("version_code", 124),
            ("signature_verified", False),
            ("signer_count", 2),
            ("certificate_sha256", "0" * 64),
            ("source_revision", "0" * 40),
            ("declared_permissions", frozenset()),
        ):
            with self.subTest(field=field):
                self._start_distinct_test_session()
                result = self._admit(
                    FakeAdmissionTransport(),
                    artifact=replace(self.artifact, **{field: value}),
                )
                self.assertEqual(result.status, admission.AdmissionStatus.BLOCKED)
                self.assertEqual(result.code, admission.AdmissionCode.ARTIFACT_MISMATCH)

    def test_artifact_signer_count_rejects_boolean_impostors(self) -> None:
        result = self._admit(
            FakeAdmissionTransport(),
            artifact=replace(self.artifact, signer_count=True),
        )

        self.assertEqual(result.status, admission.AdmissionStatus.BLOCKED)
        self.assertEqual(result.code, admission.AdmissionCode.ARTIFACT_MISMATCH)

    def test_connected_serial_observation_requires_a_sequence(self) -> None:
        document = authorization_document()
        document["target"]["device_serial"] = "A"
        document["operations"][0]["target_serial"] = "A"
        document["operations"][0]["restoration"]["target_serial"] = "A"
        authorization = self._load_auth(document)
        approval = self._load_approval(authorization)
        observation = replace(valid_observation(), connected_serials="A")
        transport = FakeAdmissionTransport(observation)

        result = self._admit(transport, auth=authorization, approval=approval)

        self.assertEqual(result.status, admission.AdmissionStatus.BLOCKED)
        self.assertEqual(result.code, admission.AdmissionCode.OBSERVATION_UNAVAILABLE)
        self.assertEqual(transport.mutation_calls, 0)

    def test_foreground_interference_storage_and_unknown_observations_fail_closed(self) -> None:
        cases = (
            (replace(valid_observation(), foreground_package="com.example.foreign"), admission.AdmissionCode.FOREGROUND_MISMATCH),
            (replace(valid_observation(), foreground_package=None), admission.AdmissionCode.FOREGROUND_UNAVAILABLE),
            (replace(valid_observation(), interference_free=False), admission.AdmissionCode.INTERFERENCE_DETECTED),
            (replace(valid_observation(), interference_free=None), admission.AdmissionCode.INTERFERENCE_UNKNOWN),
            (replace(valid_observation(), available_storage_bytes=0), admission.AdmissionCode.STORAGE_RESERVE_UNAVAILABLE),
            (replace(valid_observation(), available_storage_bytes=None), admission.AdmissionCode.STORAGE_OBSERVATION_UNAVAILABLE),
        )
        for observation, expected in cases:
            with self.subTest(expected=expected):
                self._start_distinct_test_session()
                transport = FakeAdmissionTransport(observation)
                result = self._admit(transport)
                self.assertEqual(result.status, admission.AdmissionStatus.BLOCKED)
                self.assertEqual(result.code, expected)
                self.assertEqual(transport.mutation_calls, 0)

    def test_observation_exceptions_are_sanitized_and_session_cannot_be_reused(self) -> None:
        class BrokenTransport(FakeAdmissionTransport):
            def observe_fresh_admission(self):
                raise RuntimeError("private serial and command output")

        broken = self._admit(BrokenTransport())
        self.assertEqual(broken.status, admission.AdmissionStatus.BLOCKED)
        self.assertEqual(broken.code, admission.AdmissionCode.OBSERVATION_UNAVAILABLE)
        self.assertNotIn("private serial", broken.message)
        repeated = self._admit(FakeAdmissionTransport())
        self.assertEqual(repeated.code, admission.AdmissionCode.SESSION_ALREADY_USED)




# Simulated permission-operation and restoration tests.
class FakeOperationAdmissionTransport:
    """Synthetic admission facts used only to construct a test session."""

    def __init__(self):
        self.calls = []

    def observe_fresh_admission(self):
        self.calls.append("observe_fresh_admission")
        return admission.FreshAdmissionObservation(
            connected_serials=("private-serial-synthetic",),
            android_api_level=35,
            abi="arm64-v8a",
            capabilities=frozenset(
                {
                    "foreground_package_observation",
                    "installed_signer_observation",
                    "permission_app_op_observation",
                    "permission_app_op_mutation",
                    "storage_reserve_observation",
                }
            ),
            installation=admission.InstallationObservation(
                admission.InstallationStatus.PRESENT,
                QUALIFICATION_PACKAGE,
                123,
                "b" * 64,
            ),
            foreground_package=QUALIFICATION_PACKAGE,
            interference_free=True,
            available_storage_bytes=2_000_000_000,
        )


class FakeOperationTransport:
    """In-memory permission state; it never communicates with Android."""

    def __init__(self) -> None:
        self.calls: list[str] = []
        self.default_effective_access = admission.EffectiveAccess.ALLOWED
        self.configuration = admission.PermissionConfigurationSnapshot(
            effective_access=admission.EffectiveAccess.ALLOWED,
            stored_configuration=admission.StoredAppOpConfiguration(
                mode=admission.AppOpMode.ALLOWED,
                override_present=True,
            ),
        )
        self.target_matches = True
        self.foreground_matches = True
        self.package_matches = True
        self.mutation_calls: list[tuple[str, int]] = []
        self.read_calls = 0
        self.fail_after_state_change: set[str] = set()
        self.fail_without_state_change: set[str] = set()
        self.fail_read_call: int | None = None
        self.interrupt_read_call: int | None = None
        self.configuration_mutation_calls: list[tuple[object, int]] = []
        self.pending_before_setter: list[object | None] = []

    @property
    def permission_state(self):
        return self.configuration.effective_access.value

    @permission_state.setter
    def permission_state(self, value):
        access = admission.EffectiveAccess(value)
        mode = admission.AppOpMode.ALLOWED if access is admission.EffectiveAccess.ALLOWED else admission.AppOpMode.DENIED
        self.configuration = admission.PermissionConfigurationSnapshot(
            effective_access=access,
            stored_configuration=admission.StoredAppOpConfiguration(
                mode=mode,
                override_present=True,
            ),
        )

    def verify_target(self, serial, target_ref, timeout_seconds):
        self.calls.append("verify_target")
        return serial == "private-serial-synthetic" and target_ref == "target-ref-synthetic" and self.target_matches

    def verify_foreground(self, package_name, timeout_seconds):
        self.calls.append("verify_foreground")
        return package_name == QUALIFICATION_PACKAGE and self.foreground_matches

    def verify_installed_package(self, serial, package_name, version_code, certificate_sha256, timeout_seconds):
        self.calls.append("verify_installed_package")
        return (
            serial == "private-serial-synthetic"
            and package_name == QUALIFICATION_PACKAGE
            and version_code == 123
            and certificate_sha256 == "b" * 64
            and self.package_matches
        )

    def read_permission_state(self, serial, package_name, permission_name, timeout_seconds):
        self.calls.append("read_permission_state")
        self.read_calls += 1
        if self.fail_read_call == self.read_calls:
            raise RuntimeError("synthetic read failure with private serial")
        if self.interrupt_read_call == self.read_calls:
            raise KeyboardInterrupt
        if (
            serial != "private-serial-synthetic"
            or package_name != QUALIFICATION_PACKAGE
            or permission_name != MANAGE_EXTERNAL_STORAGE
        ):
            return None
        return self.configuration

    def set_permission_state(self, serial, package_name, permission_name, configuration, timeout_seconds):
        self.calls.append("set_permission_state")
        try:
            pending = admission.pending_for_device(
                serial,
                path=admission._DEVICE_SAFETY_PATH,
            )
        except admission.SafetyStateError:
            pending = None
        self.pending_before_setter.append(pending)
        self.configuration_mutation_calls.append((configuration, timeout_seconds))
        label = {
            admission.AppOpMode.ALLOWED: "allowed",
            admission.AppOpMode.DENIED: "denied",
            admission.AppOpMode.IGNORED: "denied",
            admission.AppOpMode.ERRORED: "denied",
        }.get(configuration.mode, self.default_effective_access.value)
        self.mutation_calls.append((label, timeout_seconds))
        if label in self.fail_without_state_change:
            raise RuntimeError("synthetic mutation failure with private serial")
        access = admission.EffectiveAccess(label)
        self.configuration = admission.PermissionConfigurationSnapshot(
            effective_access=access,
            stored_configuration=configuration,
        )
        if label in self.fail_after_state_change:
            raise KeyboardInterrupt


class TypedFakeOperationTransport(FakeOperationTransport):
    """Model effective access separately from the exact stored app-op state."""

    def __init__(self, configuration):
        super().__init__()
        self.configuration = configuration
        self.default_effective_access = configuration.effective_access


def assert_mutation_calls(test_case, actual, expected):
    """Assert mutation order and ensure each timeout stays within its grant."""
    test_case.assertEqual([state for state, _ in actual], [state for state, _ in expected])
    for (_, timeout), (_, maximum) in zip(actual, expected):
        test_case.assertGreater(timeout, 0)
        test_case.assertLessEqual(timeout, maximum)


class PermissionOperationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.directory = Path(self.temporary_directory.name)
        self.registry_path_patch = mock.patch.object(
            admission,
            "_SESSION_REGISTRY_PATH",
            self.directory / "host-state" / "session-registry.json",
            create=True,
        )
        self.registry_path_patch.start()
        self.addCleanup(self.registry_path_patch.stop)
        self.safety_path_patch = mock.patch.object(
            admission,
            "_DEVICE_SAFETY_PATH",
            self.directory / "host-state" / "device-restoration.json",
            create=True,
        )
        self.safety_path_patch.start()
        self.addCleanup(self.safety_path_patch.stop)
        self.safety_state_root = self.directory / "host-state"
        self.safety_state_path = self.safety_state_root / "device-restoration.json"
        self.authorization, self.approval, self.session = self._create_test_session(authorization_document())
        self.transport = FakeOperationTransport()
        self.executor = admission.PermissionOperationExecutor(self.session, self.transport)

    def _create_test_session(self, document, *, enter_phase=True):
        authorization = self._load_authorization(document)
        approval = self._load_approval(authorization)
        artifact = admission.HostArtifactFacts(
            apk_sha256="a" * 64,
            package_name=QUALIFICATION_PACKAGE,
            version_code=123,
            signature_verified=True,
            signer_count=1,
            certificate_sha256="b" * 64,
            source_revision="c" * 40,
            declared_permissions=frozenset({MANAGE_EXTERNAL_STORAGE}),
        )
        result = admission.admit_session(
            authorization,
            approval,
            artifact,
            FakeOperationAdmissionTransport(),
            now=NOW,
        )
        self.assertEqual(result.status, admission.AdmissionStatus.ADMITTED)
        if enter_phase:
            operation = next(
                (item for item in authorization.operations if item.category is manifest.OperationCategory.PERMISSION_APP_OP),
                None,
            )
            if operation is not None:
                phase_executor = admission.PermissionOperationExecutor(
                    result.session,
                    FakeOperationTransport(),
                )
                self.assertTrue(phase_executor.enter_qualification_phase(operation.operation_id))
        return authorization, approval, result.session

    def _load_authorization(self, document):
        return manifest.load_authorization(
            write_private_json(
                self.directory,
                f"authorization-{document['authorization_id']}.json",
                document,
            )
        )

    def _load_approval(self, authorization):
        path = write_private_json(
            self.directory,
            f"approval-{authorization.authorization_id}.json",
            approval_document(authorization.canonical_sha256),
        )
        return manifest.load_owner_approval(path, authorization, now=NOW)

    def _typed_configuration(self, access, mode, override_present):
        return admission.PermissionConfigurationSnapshot(
            effective_access=access,
            stored_configuration=admission.StoredAppOpConfiguration(
                mode=mode,
                override_present=override_present,
            ),
        )

    def _set_safety_state_path(self, suffix):
        self.safety_state_path = self.safety_state_root / f"device-restoration-{suffix}.json"
        admission._DEVICE_SAFETY_PATH = self.safety_state_path

    def _create_unresolved_cleanup(self, authorization_id, original):
        transport = TypedFakeOperationTransport(original)
        transport.fail_after_state_change.add("denied")
        transport.fail_without_state_change.add("allowed")
        document = authorization_document()
        document["authorization_id"] = authorization_id
        authorization, approval, session = self._create_test_session(
            document,
            enter_phase=False,
        )
        executor = admission.PermissionOperationExecutor(session, transport)
        self.assertTrue(executor.enter_qualification_phase("permission-loss-synthetic"))

        failed = executor.execute("permission-loss-synthetic", now=NOW)

        self.assertEqual(failed.code, admission.OperationCode.RESTORATION_FAILED)
        self.assertEqual(len(transport.configuration_mutation_calls), 2)
        return authorization, approval, session, executor, transport

    def test_default_and_explicit_allow_with_same_access_restore_distinct_stored_state(self) -> None:
        app_op = admission.AppOpMode
        access = admission.EffectiveAccess.ALLOWED
        initial_states = (
            self._typed_configuration(access, app_op.DEFAULT, False),
            self._typed_configuration(access, app_op.ALLOWED, True),
        )

        for index, initial_state in enumerate(initial_states):
            with self.subTest(initial_state=initial_state):
                document = authorization_document()
                document["authorization_id"] = f"authorization-exact-state-{index}-synthetic"
                _, _, session = self._create_test_session(document, enter_phase=False)
                transport = TypedFakeOperationTransport(initial_state)
                executor = admission.PermissionOperationExecutor(session, transport)
                self.assertTrue(executor.enter_qualification_phase("permission-loss-synthetic"))

                changed = executor.execute("permission-loss-synthetic", now=NOW)

                self.assertEqual(changed.code, admission.OperationCode.PERMISSION_CHANGED)
                self.assertEqual(len(transport.configuration_mutation_calls), 1)
                self.assertEqual(transport.pending_before_setter[0].snapshot, initial_state)
                restored = executor.restore("permission-restore-synthetic", now=NOW)

                self.assertEqual(restored.code, admission.OperationCode.PERMISSION_RESTORED)
                self.assertEqual(transport.configuration, initial_state)
                self.assertEqual(
                    transport.configuration_mutation_calls[-1][0],
                    initial_state.stored_configuration,
                )

    def test_missing_or_ambiguous_stored_state_blocks_before_setter(self) -> None:
        document = authorization_document()
        document["authorization_id"] = "authorization-ambiguous-state-synthetic"
        _, _, session = self._create_test_session(document, enter_phase=False)
        unknown = self._typed_configuration(
            admission.EffectiveAccess.ALLOWED,
            None,
            None,
        )
        transport = TypedFakeOperationTransport(unknown)
        executor = admission.PermissionOperationExecutor(session, transport)
        self.assertTrue(executor.enter_qualification_phase("permission-loss-synthetic"))

        result = executor.execute("permission-loss-synthetic", now=NOW)

        self.assertEqual(result.code, admission.OperationCode.PERMISSION_STATE_UNKNOWN)
        self.assertEqual(transport.configuration_mutation_calls, [])
        self.assertEqual(session.lifecycle, admission.SessionLifecycle.BLOCKED)

    def test_corrupt_owner_safety_state_blocks_before_transport(self) -> None:
        state_path = admission._DEVICE_SAFETY_PATH
        state_path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        state_path.write_text("{invalid", encoding="utf-8")
        state_path.chmod(0o600)
        transport = FakeOperationTransport()
        executor = admission.PermissionOperationExecutor(self.session, transport)

        result = executor.execute("permission-loss-synthetic", now=NOW)

        self.assertEqual(result.code, admission.OperationCode.DEVICE_SAFETY_STATE_UNAVAILABLE)
        self.assertEqual(transport.calls, [])
        self.assertNotIn("private-serial-synthetic", result.message)

    def test_unwritable_owner_safety_directory_blocks_before_transport(self) -> None:
        admission._DEVICE_SAFETY_PATH.parent.chmod(0o755)
        transport = FakeOperationTransport()
        executor = admission.PermissionOperationExecutor(self.session, transport)

        result = executor.execute("permission-loss-synthetic", now=NOW)

        self.assertEqual(result.code, admission.OperationCode.DEVICE_SAFETY_STATE_UNAVAILABLE)
        self.assertEqual(transport.calls, [])

    def test_restoration_rejects_same_effective_access_with_wrong_stored_override(self) -> None:
        original = self._typed_configuration(
            admission.EffectiveAccess.ALLOWED,
            admission.AppOpMode.DEFAULT,
            False,
        )

        class WrongOverrideTransport(TypedFakeOperationTransport):
            def set_permission_state(transport, serial, package_name, permission_name, configuration, timeout_seconds):
                super().set_permission_state(
                    serial,
                    package_name,
                    permission_name,
                    configuration,
                    timeout_seconds,
                )
                if configuration.mode is admission.AppOpMode.DEFAULT:
                    transport.configuration = self._typed_configuration(
                        admission.EffectiveAccess.ALLOWED,
                        admission.AppOpMode.ALLOWED,
                        True,
                    )

        document = authorization_document()
        document["authorization_id"] = "authorization-wrong-stored-restore-synthetic"
        authorization, approval, session = self._create_test_session(document, enter_phase=False)
        transport = WrongOverrideTransport(original)
        executor = admission.PermissionOperationExecutor(session, transport)
        self.assertTrue(executor.enter_qualification_phase("permission-loss-synthetic"))
        changed = executor.execute("permission-loss-synthetic", now=NOW)
        self.assertEqual(changed.code, admission.OperationCode.PERMISSION_CHANGED)

        restored = executor.restore("permission-restore-synthetic", now=NOW)

        self.assertEqual(restored.code, admission.OperationCode.RESTORATION_FAILED)
        self.assertNotEqual(transport.configuration, original)
        self.assertEqual(session.lifecycle, admission.SessionLifecycle.BLOCKED)
        restoration_approval = admission.load_pending_restoration_approval(
            authorization,
            now=NOW,
        )
        recovered = admission.recover_pending_restoration(
            authorization,
            restoration_approval,
            "permission-restore-synthetic",
            transport,
            now=NOW,
        )
        self.assertEqual(recovered.code, admission.OperationCode.RESTORATION_FAILED)
        self.assertIsNotNone(
            admission.pending_for_device(
                authorization.target_serial,
                path=admission._DEVICE_SAFETY_PATH,
            )
        )

    def test_mutation_requires_trusted_qualification_phase_entry(self) -> None:
        document = authorization_document()
        document["authorization_id"] = "authorization-no-phase-synthetic"
        _, _, session = self._create_test_session(document, enter_phase=False)
        transport = FakeOperationTransport()
        executor = admission.PermissionOperationExecutor(session, transport)

        result = executor.execute("permission-loss-synthetic", now=NOW)

        self.assertEqual(result.code, admission.OperationCode.QUALIFICATION_PHASE_NOT_ENTERED)
        self.assertEqual(transport.calls, [])
        self.assertEqual(transport.mutation_calls, [])

    def test_uncertain_product_mutation_attempts_exact_cleanup_once(self) -> None:
        transport = TypedFakeOperationTransport(
            self._typed_configuration(
                admission.EffectiveAccess.ALLOWED,
                admission.AppOpMode.DEFAULT,
                False,
            )
        )
        transport.fail_after_state_change.add("denied")
        document = authorization_document()
        document["authorization_id"] = "authorization-auto-restore-synthetic"
        _, _, session = self._create_test_session(document, enter_phase=False)
        executor = admission.PermissionOperationExecutor(session, transport)
        self.assertTrue(executor.enter_qualification_phase("permission-loss-synthetic"))

        result = executor.execute("permission-loss-synthetic", now=NOW)

        self.assertEqual(result.code, admission.OperationCode.SESSION_FAILED_RESTORED)
        self.assertEqual(session.lifecycle, admission.SessionLifecycle.BLOCKED)
        self.assertEqual(len(transport.configuration_mutation_calls), 2)
        self.assertEqual(
            transport.configuration_mutation_calls[1][0],
            self._typed_configuration(
                admission.EffectiveAccess.ALLOWED,
                admission.AppOpMode.DEFAULT,
                False,
            ).stored_configuration,
        )
        calls_after_cleanup = list(transport.calls)
        retried = executor.restore("permission-restore-synthetic", now=NOW)
        self.assertEqual(retried.code, admission.OperationCode.SESSION_TERMINAL)
        self.assertEqual(transport.calls, calls_after_cleanup)

    def test_setter_failure_before_apply_still_runs_bounded_cleanup_once(self) -> None:
        original = self._typed_configuration(
            admission.EffectiveAccess.ALLOWED,
            admission.AppOpMode.DEFAULT,
            False,
        )
        transport = TypedFakeOperationTransport(original)
        transport.fail_without_state_change.add("denied")
        document = authorization_document()
        document["authorization_id"] = "authorization-setter-failed-before-apply-synthetic"
        _, _, session = self._create_test_session(document, enter_phase=False)
        executor = admission.PermissionOperationExecutor(session, transport)
        self.assertTrue(executor.enter_qualification_phase("permission-loss-synthetic"))

        result = executor.execute("permission-loss-synthetic", now=NOW)

        self.assertEqual(result.code, admission.OperationCode.SESSION_FAILED_RESTORED)
        self.assertEqual(transport.configuration, original)
        self.assertEqual([state for state, _ in transport.mutation_calls], ["denied"])
        self.assertEqual(session.lifecycle, admission.SessionLifecycle.BLOCKED)

    def test_failed_automatic_cleanup_keeps_durable_blocker_for_new_admission(self) -> None:
        transport = TypedFakeOperationTransport(
            self._typed_configuration(
                admission.EffectiveAccess.ALLOWED,
                admission.AppOpMode.ALLOWED,
                True,
            )
        )
        transport.fail_after_state_change.add("denied")
        transport.fail_without_state_change.add("allowed")
        document = authorization_document()
        document["authorization_id"] = "authorization-pending-cleanup-synthetic"
        authorization, approval, session = self._create_test_session(document, enter_phase=False)
        executor = admission.PermissionOperationExecutor(session, transport)
        self.assertTrue(executor.enter_qualification_phase("permission-loss-synthetic"))

        result = executor.execute("permission-loss-synthetic", now=NOW)

        self.assertEqual(result.code, admission.OperationCode.RESTORATION_FAILED)
        self.assertNotIn("private-serial-synthetic", result.message)
        self.assertEqual(len(transport.configuration_mutation_calls), 2)
        state_path = admission._DEVICE_SAFETY_PATH
        self.assertEqual(state_path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(state_path.stat().st_uid, os.geteuid())
        self.assertEqual(state_path.parent.stat().st_mode & 0o777, 0o700)
        self.assertEqual(state_path.parent.stat().st_uid, os.geteuid())
        self.assertIn("private-serial-synthetic", state_path.read_text(encoding="utf-8"))
        document = authorization_document()
        document["authorization_id"] = "authorization-after-unresolved-cleanup-synthetic"
        authorization = self._load_authorization(document)
        approval = self._load_approval(authorization)
        artifact = admission.HostArtifactFacts(
            "a" * 64,
            QUALIFICATION_PACKAGE,
            123,
            True,
            1,
            "b" * 64,
            "c" * 40,
            frozenset({MANAGE_EXTERNAL_STORAGE}),
        )
        fresh_transport = FakeOperationAdmissionTransport()

        blocked = admission.admit_session(
            authorization,
            approval,
            artifact,
            fresh_transport,
            now=NOW,
        )

        self.assertEqual(blocked.code, admission.AdmissionCode.DEVICE_RESTORATION_PENDING)
        self.assertEqual(fresh_transport.calls, [])

    def test_explicit_owner_recovery_restores_before_clearing_pending_state(self) -> None:
        original = self._typed_configuration(
            admission.EffectiveAccess.ALLOWED,
            admission.AppOpMode.DEFAULT,
            False,
        )
        transport = TypedFakeOperationTransport(original)
        transport.fail_after_state_change.add("denied")
        transport.fail_without_state_change.add("allowed")
        document = authorization_document()
        document["authorization_id"] = "authorization-explicit-recovery-synthetic"
        authorization, approval, session = self._create_test_session(document, enter_phase=False)
        executor = admission.PermissionOperationExecutor(session, transport)
        self.assertTrue(executor.enter_qualification_phase("permission-loss-synthetic"))
        failed = executor.execute("permission-loss-synthetic", now=NOW)
        self.assertEqual(failed.code, admission.OperationCode.RESTORATION_FAILED)

        new_document = authorization_document()
        new_document["authorization_id"] = "authorization-new-owner-approval-synthetic"
        new_authorization = self._load_authorization(new_document)
        new_approval = self._load_approval(new_authorization)
        rejected = admission.recover_pending_restoration(
            new_authorization,
            new_approval,
            "permission-restore-synthetic",
            transport,
            now=NOW,
        )
        self.assertEqual(rejected.code, admission.OperationCode.OPERATION_UNAUTHORIZED)
        self.assertIsNotNone(
            admission.pending_for_device(
                authorization.target_serial,
                path=admission._DEVICE_SAFETY_PATH,
            )
        )

        transport.fail_without_state_change.clear()
        restoration_approval = admission.load_pending_restoration_approval(
            authorization,
            now=NOW,
        )
        recovered = admission.recover_pending_restoration(
            authorization,
            restoration_approval,
            "permission-restore-synthetic",
            transport,
            now=NOW,
        )

        self.assertEqual(recovered.code, admission.OperationCode.PERMISSION_RESTORED)
        self.assertEqual(transport.configuration, original)
        self.assertIsNone(
            admission.pending_for_device(
                authorization.target_serial,
                path=admission._DEVICE_SAFETY_PATH,
            )
        )
        document = authorization_document()
        document["authorization_id"] = "authorization-after-owner-recovery-synthetic"
        _, _, recovered_session = self._create_test_session(document)
        self.assertIs(recovered_session.lifecycle, admission.SessionLifecycle.ACTIVE)

    def test_fresh_process_restores_after_session_deadline_before_cleanup_deadline(self) -> None:
        original = self._typed_configuration(
            admission.EffectiveAccess.ALLOWED,
            admission.AppOpMode.DEFAULT,
            False,
        )
        authorization, _, _, _, _ = self._create_unresolved_cleanup(
            "authorization-recovery-after-session-deadline-synthetic",
            original,
        )
        authorization_path = self.directory / f"authorization-{authorization.authorization_id}.json"
        approval_path = self.directory / f"approval-{authorization.authorization_id}.json"
        recovery_now = NOW.replace(minute=6)

        new_document = authorization_document()
        new_document["authorization_id"] = "authorization-admission-blocked-by-pending-synthetic"
        new_authorization = self._load_authorization(new_document)
        new_approval = self._load_approval(new_authorization)
        new_authorization_path = self.directory / f"authorization-{new_authorization.authorization_id}.json"
        new_approval_path = self.directory / f"approval-{new_authorization.authorization_id}.json"
        script = textwrap.dedent(
            """\
            from datetime import datetime
            from pathlib import Path
            import sys

            from scripts.android_qualification import admission, manifest
            from scripts.android_qualification.test_manifest import MANAGE_EXTERNAL_STORAGE, NOW

            authorization_path, approval_path, safety_path, registry_path, new_auth_path, new_approval_path, when = sys.argv[1:]
            admission._DEVICE_SAFETY_PATH = Path(safety_path)
            admission._SESSION_REGISTRY_PATH = Path(registry_path)
            authorization = manifest.load_authorization(Path(authorization_path))
            new_authorization = manifest.load_authorization(Path(new_auth_path))
            recovery_now = datetime.fromisoformat(when)

            class AdmissionFacts:
                def observe_fresh_admission(self):
                    return admission.FreshAdmissionObservation(
                        connected_serials=(new_authorization.target_serial,),
                        android_api_level=35,
                        abi="arm64-v8a",
                        capabilities=new_authorization.required_capabilities,
                        installation=admission.InstallationObservation(
                            admission.InstallationStatus.PRESENT,
                            new_authorization.application_package,
                            new_authorization.version_code,
                            new_authorization.certificate_sha256,
                        ),
                        foreground_package=new_authorization.application_package,
                        interference_free=True,
                        available_storage_bytes=2_000_000_000,
                    )

            new_approval = manifest.load_owner_approval(Path(new_approval_path), new_authorization, now=NOW)
            artifact = admission.HostArtifactFacts(
                apk_sha256=new_authorization.apk_sha256,
                package_name=new_authorization.application_package,
                version_code=new_authorization.version_code,
                signature_verified=True,
                signer_count=1,
                certificate_sha256=new_authorization.certificate_sha256,
                source_revision=new_authorization.source_revision,
                declared_permissions=new_authorization.declared_permissions,
            )
            blocked = admission.admit_session(
                new_authorization,
                new_approval,
                artifact,
                AdmissionFacts(),
                now=NOW,
            )
            assert blocked.code is admission.AdmissionCode.DEVICE_RESTORATION_PENDING

            pending = admission.pending_for_device(
                authorization.target_serial,
                path=admission._DEVICE_SAFETY_PATH,
            )
            assert pending is not None
            assert Path(approval_path) == pending.approval_sidecar_path
            restoration_approval = admission.load_pending_restoration_approval(
                authorization,
                now=recovery_now,
            )

            class PermissionTransport:
                def __init__(self):
                    self.configuration = admission.PermissionConfigurationSnapshot(
                        effective_access=admission.EffectiveAccess.DENIED,
                        stored_configuration=admission.StoredAppOpConfiguration(
                            mode=admission.AppOpMode.DENIED,
                            override_present=True,
                        ),
                    )
                    self.setter_calls = 0

                def verify_target(self, serial, target_ref, timeout_seconds):
                    return serial == authorization.target_serial and target_ref == authorization.target_ref

                def verify_installed_package(self, serial, package_name, version_code, certificate_sha256, timeout_seconds):
                    return (
                        serial == authorization.target_serial
                        and package_name == authorization.application_package
                        and version_code == authorization.version_code
                        and certificate_sha256 == authorization.certificate_sha256
                    )

                def read_permission_state(self, serial, package_name, permission_name, timeout_seconds):
                    if (
                        serial != authorization.target_serial
                        or package_name != authorization.application_package
                        or permission_name != MANAGE_EXTERNAL_STORAGE
                    ):
                        return None
                    return self.configuration

                def set_permission_state(self, serial, package_name, permission_name, configuration, timeout_seconds):
                    self.setter_calls += 1
                    self.configuration = admission.PermissionConfigurationSnapshot(
                        effective_access=pending.snapshot.effective_access,
                        stored_configuration=configuration,
                    )

            transport = PermissionTransport()
            recovered = admission.recover_pending_restoration(
                authorization,
                restoration_approval,
                pending.restoration_operation_id,
                transport,
                now=recovery_now,
            )
            assert recovered.code is admission.OperationCode.PERMISSION_RESTORED
            assert transport.setter_calls == 1
            assert transport.configuration == pending.snapshot
            assert admission.pending_for_device(
                authorization.target_serial,
                path=admission._DEVICE_SAFETY_PATH,
            ) is None
            print(blocked.code.value)
            print(recovered.code.value)
            print(transport.setter_calls)
            """
        )
        result = subprocess.run(
            [
                sys.executable,
                "-c",
                script,
                str(authorization_path),
                str(approval_path),
                str(self.safety_state_path),
                str(self.directory / "host-state" / "session-registry.json"),
                str(new_authorization_path),
                str(new_approval_path),
                recovery_now.isoformat(),
            ],
            capture_output=True,
            text=True,
            check=False,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout.splitlines(),
            [
                admission.AdmissionCode.DEVICE_RESTORATION_PENDING.value,
                admission.OperationCode.PERMISSION_RESTORED.value,
                "1",
            ],
        )
        self.assertIsNone(
            admission.pending_for_device(
                authorization.target_serial,
                path=self.safety_state_path,
            )
        )

    def test_restoration_loader_rejects_expired_deadline_and_wrong_pending_bindings(self) -> None:
        original = self._typed_configuration(
            admission.EffectiveAccess.ALLOWED,
            admission.AppOpMode.DEFAULT,
            False,
        )
        authorization, _, _, _, transport = self._create_unresolved_cleanup(
            "authorization-recovery-binding-checks-synthetic",
            original,
        )
        pending = admission.pending_for_device(
            authorization.target_serial,
            path=self.safety_state_path,
        )
        self.assertIsNotNone(pending)
        after_session_deadline = NOW.replace(minute=6)

        with self.assertRaises(manifest.ApprovalError):
            admission.load_pending_restoration_approval(
                authorization,
                now=NOW.replace(minute=8, second=50),
            )
        with self.assertRaises(manifest.ApprovalError):
            admission.load_pending_restoration_approval(
                authorization,
                now=NOW.replace(minute=10),
            )

        wrong_approval_path = write_private_json(
            self.directory,
            "approval-without-original-sidecar-provenance.json",
            approval_document(authorization.canonical_sha256),
        )
        context = admission._restoration_approval_context(authorization, pending)
        with self.assertRaises(manifest.ApprovalError):
            manifest.load_owner_approval_for_restoration(
                wrong_approval_path,
                authorization,
                context=context,
                now=after_session_deadline,
            )

        original_sidecar = pending.approval_sidecar_path.read_bytes()
        changed_approval = approval_document(authorization.canonical_sha256)
        changed_approval["valid_until_utc"] = "2030-01-01T00:03:59Z"
        pending.approval_sidecar_path.write_text(
            json.dumps(changed_approval),
            encoding="utf-8",
        )
        with self.assertRaises(manifest.ApprovalError):
            admission.load_pending_restoration_approval(
                authorization,
                now=after_session_deadline,
            )
        pending.approval_sidecar_path.write_bytes(original_sidecar)

        wrong_record_context = replace(context, authorization_id="different-pending-session-synthetic")
        with self.assertRaises(manifest.ApprovalError):
            manifest.load_owner_approval_for_restoration(
                pending.approval_sidecar_path,
                authorization,
                context=wrong_record_context,
                now=after_session_deadline,
            )

        restoration_approval = admission.load_pending_restoration_approval(
            authorization,
            now=after_session_deadline,
        )
        self.assertFalse(manifest._is_loaded_owner_approval(restoration_approval))
        mutation_count_before_recovery = len(transport.configuration_mutation_calls)
        wrong_snapshot = self._typed_configuration(
            admission.EffectiveAccess.ALLOWED,
            admission.AppOpMode.ALLOWED,
            True,
        )
        wrong_pending = replace(pending, snapshot=wrong_snapshot)
        self.safety_state_path.write_text(
            json.dumps(
                {
                    "schema_version": admission._DEVICE_SAFETY_SCHEMA_VERSION,
                    "pending": [admission._record_to_document(wrong_pending)],
                },
                sort_keys=True,
                separators=(",", ":"),
            ),
            encoding="utf-8",
        )
        rejected = admission.recover_pending_restoration(
            authorization,
            restoration_approval,
            pending.restoration_operation_id,
            transport,
            now=after_session_deadline,
        )

        self.assertEqual(rejected.code, admission.OperationCode.OPERATION_UNAUTHORIZED)
        self.assertEqual(
            len(transport.configuration_mutation_calls),
            mutation_count_before_recovery,
        )
        self.assertIsNotNone(
            admission.pending_for_device(
                authorization.target_serial,
                path=self.safety_state_path,
            )
        )

    def test_manual_recovery_setter_is_one_shot_and_failed_automatic_restore_is_not_retried(self) -> None:
        original = self._typed_configuration(
            admission.EffectiveAccess.ALLOWED,
            admission.AppOpMode.DEFAULT,
            False,
        )
        authorization, _, _, executor, transport = self._create_unresolved_cleanup(
            "authorization-recovery-setter-once-synthetic",
            original,
        )
        automatic_calls = len(transport.configuration_mutation_calls)
        terminal_retry = executor.restore("permission-restore-synthetic", now=NOW)
        self.assertEqual(terminal_retry.code, admission.OperationCode.SESSION_TERMINAL)
        self.assertEqual(len(transport.configuration_mutation_calls), automatic_calls)

        recovery_now = NOW.replace(minute=6)
        restoration_approval = admission.load_pending_restoration_approval(
            authorization,
            now=recovery_now,
        )
        first_manual_attempt = admission.recover_pending_restoration(
            authorization,
            restoration_approval,
            "permission-restore-synthetic",
            transport,
            now=recovery_now,
        )
        self.assertEqual(first_manual_attempt.code, admission.OperationCode.RESTORATION_FAILED)
        self.assertEqual(len(transport.configuration_mutation_calls), automatic_calls + 1)
        pending_after_attempt = admission.pending_for_device(
            authorization.target_serial,
            path=self.safety_state_path,
        )
        self.assertIsNotNone(pending_after_attempt)
        self.assertTrue(pending_after_attempt.recovery_setter_attempted)

        authorization_path = self.directory / f"authorization-{authorization.authorization_id}.json"
        script = textwrap.dedent(
            """\
            from datetime import datetime
            from pathlib import Path
            import sys

            from scripts.android_qualification import admission, manifest
            from scripts.android_qualification.test_manifest import MANAGE_EXTERNAL_STORAGE

            authorization_path, safety_path, when = sys.argv[1:]
            admission._DEVICE_SAFETY_PATH = Path(safety_path)
            authorization = manifest.load_authorization(Path(authorization_path))
            recovery_approval = admission.load_pending_restoration_approval(
                authorization,
                now=datetime.fromisoformat(when),
            )

            class Transport:
                def __init__(self):
                    self.configuration = admission.PermissionConfigurationSnapshot(
                        effective_access=admission.EffectiveAccess.DENIED,
                        stored_configuration=admission.StoredAppOpConfiguration(
                            mode=admission.AppOpMode.DENIED,
                            override_present=True,
                        ),
                    )
                    self.setter_calls = 0

                def verify_target(self, serial, target_ref, timeout_seconds):
                    return serial == authorization.target_serial and target_ref == authorization.target_ref

                def verify_installed_package(self, serial, package_name, version_code, certificate_sha256, timeout_seconds):
                    return (
                        serial == authorization.target_serial
                        and package_name == authorization.application_package
                        and version_code == authorization.version_code
                        and certificate_sha256 == authorization.certificate_sha256
                    )

                def read_permission_state(self, serial, package_name, permission_name, timeout_seconds):
                    if (
                        serial != authorization.target_serial
                        or package_name != authorization.application_package
                        or permission_name != MANAGE_EXTERNAL_STORAGE
                    ):
                        return None
                    return self.configuration

                def set_permission_state(self, serial, package_name, permission_name, configuration, timeout_seconds):
                    self.setter_calls += 1
                    raise AssertionError("a consumed recovery setter must not run again")

            transport = Transport()
            pending = admission.pending_for_device(
                authorization.target_serial,
                path=admission._DEVICE_SAFETY_PATH,
            )
            assert pending is not None and pending.recovery_setter_attempted
            result = admission.recover_pending_restoration(
                authorization,
                recovery_approval,
                pending.restoration_operation_id,
                transport,
                now=datetime.fromisoformat(when),
            )
            assert result.code is admission.OperationCode.RESTORATION_FAILED
            assert transport.setter_calls == 0
            print(result.code.value)
            print(transport.setter_calls)
            """
        )
        repeated_process = subprocess.run(
            [
                sys.executable,
                "-c",
                script,
                str(authorization_path),
                str(self.safety_state_path),
                recovery_now.isoformat(),
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(repeated_process.returncode, 0, repeated_process.stderr)
        self.assertEqual(
            repeated_process.stdout.splitlines(),
            [admission.OperationCode.RESTORATION_FAILED.value, "0"],
        )
        self.assertEqual(len(transport.configuration_mutation_calls), automatic_calls + 1)

        transport.configuration = original
        verified_after_owner_restoration = admission.recover_pending_restoration(
            authorization,
            restoration_approval,
            "permission-restore-synthetic",
            transport,
            now=recovery_now,
        )
        self.assertEqual(
            verified_after_owner_restoration.code,
            admission.OperationCode.PERMISSION_RESTORED,
        )
        self.assertEqual(len(transport.configuration_mutation_calls), automatic_calls + 1)
        self.assertIsNone(
            admission.pending_for_device(
                authorization.target_serial,
                path=self.safety_state_path,
            )
        )

    def _assert_unsupported_category_is_rejected_before_transport(self, category: str) -> None:
        operation_id = f"{category.replace('_', '-')}-synthetic"
        document = authorization_document()
        document["authorization_id"] = f"authorization-{operation_id}"
        document["operations"] = [
            {
                "operation_id": operation_id,
                "category": category,
                "phase": "qualification",
                "target_serial": "private-serial-synthetic",
                "package_name": QUALIFICATION_PACKAGE,
                "timeout_seconds": 10,
                "permission_name": None,
                "expected_prior_state": None,
                "desired_state": None,
                "restoration": None,
            }
        ]
        document["approved_remediation"] = []
        _, _, session = self._create_test_session(document)
        transport = FakeOperationTransport()
        executor = admission.PermissionOperationExecutor(session, transport)

        denied = executor.execute(operation_id, now=NOW)

        self.assertEqual(denied.status, admission.OperationStatus.BLOCKED)
        self.assertEqual(denied.code, admission.OperationCode.OPERATION_UNSUPPORTED)
        self.assertEqual(transport.calls, [])
        self.assertEqual(transport.mutation_calls, [])

    def test_permission_change_requires_snapshot_and_exact_verified_restore(self) -> None:
        changed = self.executor.execute("permission-loss-synthetic", now=NOW)
        self.assertEqual(changed.status, admission.OperationStatus.RESTORE_REQUIRED)
        self.assertEqual(changed.code, admission.OperationCode.PERMISSION_CHANGED)
        self.assertEqual(self.transport.permission_state, "denied")
        assert_mutation_calls(self, self.transport.mutation_calls, [("denied", 30)])

        restored = self.executor.restore("permission-restore-synthetic", now=NOW)
        self.assertEqual(restored.status, admission.OperationStatus.RESTORED)
        self.assertEqual(restored.code, admission.OperationCode.PERMISSION_RESTORED)
        self.assertEqual(self.transport.permission_state, "allowed")
        assert_mutation_calls(self, self.transport.mutation_calls, [("denied", 30), ("allowed", 20)])
        self.assertEqual(self.session.lifecycle, admission.SessionLifecycle.COMPLETED)

        document = authorization_document()
        document["authorization_id"] = "authorization-concurrency-synthetic"
        self.authorization, self.approval, self.session = self._create_test_session(document)
        entered_validation = threading.Event()
        release_validation = threading.Event()

        class PausedFirstCallTransport(FakeOperationTransport):
            def __init__(self):
                super().__init__()
                self.target_verification_calls = 0

            def verify_target(self, serial, target_ref, timeout_seconds):
                self.target_verification_calls += 1
                if self.target_verification_calls == 1:
                    entered_validation.set()
                    if not release_validation.wait(timeout=5):
                        raise TimeoutError("synthetic test barrier expired")
                return super().verify_target(serial, target_ref, timeout_seconds)

        concurrent_transport = PausedFirstCallTransport()
        concurrent_executor = admission.PermissionOperationExecutor(
            self.session,
            concurrent_transport,
        )
        with ThreadPoolExecutor(max_workers=1) as pool:
            first_call = pool.submit(
                concurrent_executor.execute,
                "permission-loss-synthetic",
                now=NOW,
            )
            self.assertTrue(entered_validation.wait(timeout=5))
            try:
                duplicate = concurrent_executor.execute(
                    "permission-loss-synthetic",
                    now=NOW,
                )
            finally:
                release_validation.set()
            first_result = first_call.result(timeout=5)

        self.assertEqual(duplicate.status, admission.OperationStatus.BLOCKED)
        self.assertEqual(duplicate.code, admission.OperationCode.OPERATION_IN_PROGRESS)
        self.assertEqual(concurrent_transport.target_verification_calls, 1)
        self.assertEqual(first_result.code, admission.OperationCode.PERMISSION_CHANGED)
        self.assertEqual(
            [state for state, _ in concurrent_transport.mutation_calls],
            ["denied"],
        )
        self.assertEqual(self.session.lifecycle, admission.SessionLifecycle.RESTORE_ONLY)

    def test_executor_rejects_forged_and_copied_sessions_before_transport(self) -> None:
        forged = admission.AdmittedSession(self.authorization, self.approval)
        copied = copy.copy(self.session)

        for candidate in (forged, copied):
            with self.subTest(candidate=candidate):
                transport = FakeOperationTransport()
                executor = admission.PermissionOperationExecutor(candidate, transport)
                result = executor.execute("permission-loss-synthetic", now=NOW)

                self.assertEqual(result.status, admission.OperationStatus.BLOCKED)
                self.assertEqual(result.code, admission.OperationCode.OPERATION_UNAUTHORIZED)
                self.assertEqual(transport.calls, [])
                self.assertEqual(transport.mutation_calls, [])

    def test_restore_rejects_forged_and_copied_sessions_before_transport(self) -> None:
        self.executor.execute("permission-loss-synthetic", now=NOW)
        forged = admission.AdmittedSession(self.authorization, self.approval)
        forged.enter_restore_only("permission-loss-synthetic", "allowed", failed=False)
        copied = copy.copy(self.session)

        for candidate in (forged, copied):
            with self.subTest(candidate=candidate):
                transport = FakeOperationTransport()
                executor = admission.PermissionOperationExecutor(candidate, transport)
                result = executor.restore("permission-restore-synthetic", now=NOW)

                self.assertEqual(result.status, admission.OperationStatus.BLOCKED)
                self.assertEqual(result.code, admission.OperationCode.OPERATION_UNAUTHORIZED)
                self.assertEqual(transport.calls, [])
                self.assertEqual(transport.mutation_calls, [])

    def test_restore_rejects_tampered_session_state_and_typed_fields_before_transport(self) -> None:
        tampered_fields = (
            ("lifecycle", admission.SessionLifecycle.ACTIVE),
            ("permission_operation_id", 123),
            ("permission_snapshot", False),
            ("failure_pending", 1),
            ("_operation_lock", threading.Lock()),
        )
        for index, (field, value) in enumerate(tampered_fields):
            with self.subTest(field=field):
                self._set_safety_state_path(f"session-tamper-{index}")
                document = authorization_document()
                document["authorization_id"] = f"authorization-session-tamper-{index}-synthetic"
                _, _, session = self._create_test_session(document)
                transport = FakeOperationTransport()
                executor = admission.PermissionOperationExecutor(session, transport)
                changed = executor.execute("permission-loss-synthetic", now=NOW)
                self.assertEqual(changed.code, admission.OperationCode.PERMISSION_CHANGED)
                calls_before_tampering = list(transport.calls)
                mutations_before_tampering = list(transport.mutation_calls)
                object.__setattr__(session, field, value)

                result = executor.restore("permission-restore-synthetic", now=NOW)

                self.assertEqual(result.status, admission.OperationStatus.BLOCKED)
                self.assertEqual(result.code, admission.OperationCode.OPERATION_UNAUTHORIZED)
                self.assertEqual(transport.calls, calls_before_tampering)
                self.assertEqual(transport.mutation_calls, mutations_before_tampering)

    def test_executor_rejects_rebinding_to_other_loader_validated_objects(self) -> None:
        replacement_authorization = self._load_authorization(authorization_document())
        replacement_approval = self._load_approval(replacement_authorization)
        object.__setattr__(self.session, "authorization", replacement_authorization)
        object.__setattr__(self.session, "approval", replacement_approval)
        transport = FakeOperationTransport()

        result = admission.PermissionOperationExecutor(self.session, transport).execute(
            "permission-loss-synthetic",
            now=NOW,
        )

        self.assertEqual(result.status, admission.OperationStatus.BLOCKED)
        self.assertEqual(result.code, admission.OperationCode.OPERATION_UNAUTHORIZED)
        self.assertEqual(transport.calls, [])
        self.assertEqual(transport.mutation_calls, [])

    def test_executor_rejects_tampered_loaded_authorization_and_approval_before_transport(self) -> None:
        for index, field in enumerate(("authorization", "approval")):
            with self.subTest(field=field):
                document = authorization_document()
                document["authorization_id"] = f"authorization-tamper-{index}-synthetic"
                authorization, approval, session = self._create_test_session(document)
                if field == "authorization":
                    object.__setattr__(authorization, "version_code", True)
                else:
                    object.__setattr__(
                        approval,
                        "valid_until",
                        approval.valid_until - timedelta(seconds=1),
                    )
                transport = FakeOperationTransport()

                result = admission.PermissionOperationExecutor(session, transport).execute(
                    "permission-loss-synthetic",
                    now=NOW,
                )

                self.assertEqual(result.status, admission.OperationStatus.BLOCKED)
                self.assertEqual(result.code, admission.OperationCode.OPERATION_UNAUTHORIZED)
                self.assertEqual(transport.calls, [])
                self.assertEqual(transport.mutation_calls, [])

    def test_executor_rejects_tampered_lifecycle_before_a_second_mutation(self) -> None:
        first = self.executor.execute("permission-loss-synthetic", now=NOW)
        self.assertEqual(first.code, admission.OperationCode.PERMISSION_CHANGED)
        calls_before_tampering = list(self.transport.calls)
        mutations_before_tampering = list(self.transport.mutation_calls)
        object.__setattr__(self.session, "lifecycle", admission.SessionLifecycle.ACTIVE)
        self.transport.permission_state = "allowed"

        result = self.executor.execute("permission-loss-synthetic", now=NOW)

        self.assertEqual(result.status, admission.OperationStatus.BLOCKED)
        self.assertEqual(result.code, admission.OperationCode.OPERATION_UNAUTHORIZED)
        self.assertEqual(self.transport.calls, calls_before_tampering)
        self.assertEqual(self.transport.mutation_calls, mutations_before_tampering)

    def test_executor_rejects_tampered_snapshot_before_restore_transport(self) -> None:
        self.executor.execute("permission-loss-synthetic", now=NOW)
        calls_before_tampering = list(self.transport.calls)
        mutations_before_tampering = list(self.transport.mutation_calls)
        object.__setattr__(self.session, "permission_snapshot", "denied")

        result = self.executor.restore("permission-restore-synthetic", now=NOW)

        self.assertEqual(result.status, admission.OperationStatus.BLOCKED)
        self.assertEqual(result.code, admission.OperationCode.OPERATION_UNAUTHORIZED)
        self.assertEqual(self.transport.calls, calls_before_tampering)
        self.assertEqual(self.transport.mutation_calls, mutations_before_tampering)

    def test_tampering_during_validation_stops_before_the_next_transport_call(self) -> None:
        approval = self.approval

        class TamperingTransport(FakeOperationTransport):
            def verify_target(transport, serial, target_ref, timeout_seconds):
                matched = super(TamperingTransport, transport).verify_target(
                    serial,
                    target_ref,
                    timeout_seconds,
                )
                object.__setattr__(approval, "owner_identity", True)
                return matched

        transport = TamperingTransport()
        result = admission.PermissionOperationExecutor(self.session, transport).execute(
            "permission-loss-synthetic",
            now=NOW,
        )

        self.assertEqual(result.status, admission.OperationStatus.BLOCKED)
        self.assertEqual(result.code, admission.OperationCode.OPERATION_UNAUTHORIZED)
        self.assertEqual(transport.calls, ["verify_target"])
        self.assertEqual(transport.mutation_calls, [])

    def test_wrong_restore_id_does_not_consume_exact_cleanup_opportunity(self) -> None:
        self.executor.execute("permission-loss-synthetic", now=NOW)
        expired = self.executor.execute(
            "permission-loss-synthetic",
            now=NOW.replace(minute=6),
        )
        self.assertEqual(expired.status, admission.OperationStatus.BLOCKED)
        self.assertEqual(self.session.lifecycle, admission.SessionLifecycle.RESTORE_ONLY)
        self.assertEqual(len(self.transport.mutation_calls), 1)

        restoration_deadline = self.session.authorization.operations[0].restoration.deadline
        calls_before_wrong_id = list(self.transport.calls)
        wrong_restore = self.executor.restore("permission-loss-synthetic", now=NOW.replace(minute=6))
        self.assertEqual(wrong_restore.status, admission.OperationStatus.BLOCKED)
        self.assertEqual(wrong_restore.code, admission.OperationCode.RESTORATION_NOT_AUTHORIZED)
        self.assertEqual(self.session.lifecycle, admission.SessionLifecycle.RESTORE_ONLY)
        self.assertEqual(self.transport.calls, calls_before_wrong_id)
        self.assertEqual(len(self.transport.mutation_calls), 1)
        self.assertEqual(
            self.session.authorization.operations[0].restoration.deadline,
            restoration_deadline,
        )
        restored = self.executor.restore("permission-restore-synthetic", now=NOW.replace(minute=6))
        self.assertEqual(restored.status, admission.OperationStatus.RESTORED)
        self.assertEqual(restored.code, admission.OperationCode.PERMISSION_RESTORED)
        self.assertEqual(self.session.lifecycle, admission.SessionLifecycle.COMPLETED)
        self.assertEqual(self.transport.permission_state, "allowed")
        assert_mutation_calls(self, self.transport.mutation_calls, [("denied", 30), ("allowed", 20)])

    def test_exact_restore_readback_or_verification_failure_is_terminal_without_retry(self) -> None:
        for index, failure in enumerate(("readback", "package_verification")):
            with self.subTest(failure=failure):
                self._set_safety_state_path(f"restore-failure-{index}")
                document = authorization_document()
                document["authorization_id"] = f"authorization-restore-failure-{index}-synthetic"
                _, _, session = self._create_test_session(document)
                transport = FakeOperationTransport()
                executor = admission.PermissionOperationExecutor(session, transport)
                changed = executor.execute("permission-loss-synthetic", now=NOW)
                self.assertEqual(changed.code, admission.OperationCode.PERMISSION_CHANGED)
                if failure == "readback":
                    transport.fail_read_call = transport.read_calls + 2
                else:
                    transport.package_matches = False

                failed = executor.restore("permission-restore-synthetic", now=NOW)

                self.assertEqual(failed.status, admission.OperationStatus.BLOCKED)
                expected_calls = list(transport.calls)
                expected_mutations = list(transport.mutation_calls)
                self.assertEqual(session.lifecycle, admission.SessionLifecycle.BLOCKED)
                self.assertEqual(failed.code, admission.OperationCode.RESTORATION_FAILED if failure == "readback" else admission.OperationCode.PACKAGE_IDENTITY_CHANGED)

                retried = executor.restore("permission-restore-synthetic", now=NOW)

                self.assertEqual(retried.status, admission.OperationStatus.BLOCKED)
                self.assertEqual(retried.code, admission.OperationCode.SESSION_TERMINAL)
                self.assertEqual(transport.calls, expected_calls)
                self.assertEqual(transport.mutation_calls, expected_mutations)

    def test_action_timeout_is_cumulative_across_transport_calls(self) -> None:
        elapsed = [0.0]

        class SlowTransport(FakeOperationTransport):
            def _consume(self, timeout_seconds):
                self.timeouts.append(timeout_seconds)
                elapsed[0] += 9.0

            def __init__(self):
                super().__init__()
                self.timeouts = []

            def verify_target(self, serial, target_ref, timeout_seconds):
                result = super().verify_target(serial, target_ref, timeout_seconds)
                self._consume(timeout_seconds)
                return result

            def verify_foreground(self, package_name, timeout_seconds):
                result = super().verify_foreground(package_name, timeout_seconds)
                self._consume(timeout_seconds)
                return result

            def verify_installed_package(self, serial, package_name, version_code, certificate_sha256, timeout_seconds):
                result = super().verify_installed_package(
                    serial, package_name, version_code, certificate_sha256, timeout_seconds
                )
                self._consume(timeout_seconds)
                return result

            def read_permission_state(self, serial, package_name, permission_name, timeout_seconds):
                result = super().read_permission_state(serial, package_name, permission_name, timeout_seconds)
                self._consume(timeout_seconds)
                return result

        transport = SlowTransport()
        executor = admission.PermissionOperationExecutor(self.session, transport)
        with mock.patch("time.monotonic", side_effect=lambda: elapsed[0]):
            result = executor.execute("permission-loss-synthetic", now=NOW)

        self.assertEqual(result.status, admission.OperationStatus.BLOCKED)
        self.assertEqual(self.session.lifecycle, admission.SessionLifecycle.BLOCKED)
        self.assertEqual(transport.timeouts, [30, 21, 12, 3])
        self.assertEqual(transport.mutation_calls, [])

    def test_restoration_timeout_is_cumulative_and_cleanup_remains_bounded(self) -> None:
        self.executor.execute("permission-loss-synthetic", now=NOW)
        elapsed = [0.0]

        class SlowTransport(FakeOperationTransport):
            def _consume(self, timeout_seconds):
                self.timeouts.append(timeout_seconds)
                elapsed[0] += 6.0

            def __init__(self):
                super().__init__()
                self.permission_state = "denied"
                self.timeouts = []

            def verify_target(self, serial, target_ref, timeout_seconds):
                result = super().verify_target(serial, target_ref, timeout_seconds)
                self._consume(timeout_seconds)
                return result

            def verify_installed_package(self, serial, package_name, version_code, certificate_sha256, timeout_seconds):
                result = super().verify_installed_package(
                    serial, package_name, version_code, certificate_sha256, timeout_seconds
                )
                self._consume(timeout_seconds)
                return result

            def read_permission_state(self, serial, package_name, permission_name, timeout_seconds):
                result = super().read_permission_state(serial, package_name, permission_name, timeout_seconds)
                self._consume(timeout_seconds)
                return result

            def set_permission_state(self, serial, package_name, permission_name, state, timeout_seconds):
                super().set_permission_state(serial, package_name, permission_name, state, timeout_seconds)
                self._consume(timeout_seconds)

        transport = SlowTransport()
        executor = admission.PermissionOperationExecutor(self.session, transport)
        with mock.patch("time.monotonic", side_effect=lambda: elapsed[0]):
            result = executor.restore("permission-restore-synthetic", now=NOW)

        self.assertEqual(result.status, admission.OperationStatus.BLOCKED)
        self.assertEqual(result.code, admission.OperationCode.RESTORATION_FAILED)
        self.assertEqual(self.session.lifecycle, admission.SessionLifecycle.BLOCKED)
        self.assertEqual(transport.timeouts, [20, 14, 8, 2])
        self.assertEqual(transport.mutation_calls, [("allowed", 2)])

    def test_product_mutation_is_never_retried_after_interruption(self) -> None:
        self.transport.fail_after_state_change.add("denied")
        interrupted = self.executor.execute("permission-loss-synthetic", now=NOW)
        self.assertEqual(interrupted.status, admission.OperationStatus.BLOCKED)
        self.assertEqual(interrupted.code, admission.OperationCode.SESSION_FAILED_RESTORED)
        self.assertEqual(self.transport.permission_state, "allowed")
        assert_mutation_calls(self, self.transport.mutation_calls, [("denied", 30), ("allowed", 20)])
        self.assertEqual(self.session.lifecycle, admission.SessionLifecycle.BLOCKED)
        calls_before_retry = list(self.transport.calls)
        restored = self.executor.restore("permission-restore-synthetic", now=NOW.replace(minute=6))
        self.assertEqual(restored.code, admission.OperationCode.SESSION_TERMINAL)
        self.assertEqual(self.transport.calls, calls_before_retry)

    def test_failed_restore_is_terminal_and_is_not_retried(self) -> None:
        self.executor.execute("permission-loss-synthetic", now=NOW)
        self.transport.fail_without_state_change.add("allowed")
        result = self.executor.restore("permission-restore-synthetic", now=NOW)
        self.assertEqual(result.status, admission.OperationStatus.BLOCKED)
        self.assertFalse(result.restoration_permitted)
        assert_mutation_calls(self, self.transport.mutation_calls, [("denied", 30), ("allowed", 20)])
        second = self.executor.restore("permission-restore-synthetic", now=NOW)
        self.assertEqual(second.status, admission.OperationStatus.BLOCKED)
        self.assertEqual(len(self.transport.mutation_calls), 2)
        self.assertEqual(self.session.lifecycle, admission.SessionLifecycle.BLOCKED)

    def test_cleanup_deadline_is_independent_but_strictly_bounded(self) -> None:
        self.executor.execute("permission-loss-synthetic", now=NOW)
        too_late = NOW.replace(minute=8, second=50)
        result = self.executor.restore("permission-restore-synthetic", now=too_late)
        self.assertEqual(result.code, admission.OperationCode.RESTORATION_WINDOW_CLOSED)
        assert_mutation_calls(self, self.transport.mutation_calls, [("denied", 30)])
        self.assertEqual(self.session.lifecycle, admission.SessionLifecycle.BLOCKED)

    def test_target_drift_blocks_before_product_mutation(self) -> None:
        self.transport.target_matches = False
        target = self.executor.execute("permission-loss-synthetic", now=NOW)
        self.assertEqual(target.code, admission.OperationCode.TARGET_IDENTITY_CHANGED)
        self.assertEqual(self.transport.mutation_calls, [])

    def test_foreground_drift_blocks_before_product_mutation(self) -> None:
        self.transport.foreground_matches = False
        foreground = self.executor.execute("permission-loss-synthetic", now=NOW)
        self.assertEqual(foreground.code, admission.OperationCode.FOREGROUND_IDENTITY_CHANGED)
        self.assertEqual(self.transport.mutation_calls, [])

    def test_package_identity_drift_blocks_before_product_mutation(self) -> None:
        self.transport.package_matches = False

        result = self.executor.execute("permission-loss-synthetic", now=NOW)

        self.assertEqual(result.code, admission.OperationCode.PACKAGE_IDENTITY_CHANGED)
        self.assertEqual(self.transport.mutation_calls, [])

    def test_interrupted_permission_readback_allows_only_failed_session_restoration(self) -> None:
        self.transport.interrupt_read_call = 2

        try:
            result = self.executor.execute("permission-loss-synthetic", now=NOW)
        except KeyboardInterrupt:
            result = None

        self.assertIsNotNone(result, "readback interruption must trigger bounded automatic restoration")
        self.assertEqual(result.status, admission.OperationStatus.BLOCKED)
        self.assertEqual(result.code, admission.OperationCode.SESSION_FAILED_RESTORED)
        self.assertTrue(self.session.failure_pending)
        self.assertEqual(self.session.lifecycle, admission.SessionLifecycle.BLOCKED)
        assert_mutation_calls(self, self.transport.mutation_calls, [("denied", 30), ("allowed", 20)])

    def test_interruption_and_failed_restoration_preserve_issue23_obligation_and_block_add_scan(self) -> None:
        self.transport.interrupt_read_call = 2
        self.transport.fail_without_state_change.add("allowed")

        result = self.executor.execute("permission-loss-synthetic", now=NOW)

        self.assertEqual(result.code, admission.OperationCode.RESTORATION_FAILED)
        self.assertTrue(self.session.failure_pending)
        self.assertEqual(self.session.lifecycle, admission.SessionLifecycle.BLOCKED)
        assert_mutation_calls(self, self.transport.mutation_calls, [("denied", 30), ("allowed", 20)])
        pending = admission.pending_for_device(
            self.authorization.target_serial,
            path=admission._DEVICE_SAFETY_PATH,
        )
        self.assertIsNotNone(pending)
        calls_after_failure = list(self.transport.calls)
        second_restore = self.executor.restore("permission-restore-synthetic", now=NOW)
        self.assertIn(
            second_restore.code,
            {admission.OperationCode.RESTORATION_FAILED, admission.OperationCode.SESSION_TERMINAL},
        )
        self.assertEqual(self.transport.calls, calls_after_failure)
        self.assertEqual(len(self.transport.configuration_mutation_calls), 2)

        document = _first_add_scan_plan(installation="absent")
        document["authorization_id"] = "authorization-after-interrupted-unresolved-restore-synthetic"
        authorization = self._load_authorization(document)
        approval = manifest.load_owner_approval(
            write_private_json(
                self.directory,
                "approval-after-restoration.json",
                _first_add_scan_approval_document(authorization),
            ),
            authorization,
            now=NOW,
        )
        artifact = admission.HostArtifactFacts(
            apk_sha256="a" * 64,
            package_name=QUALIFICATION_PACKAGE,
            version_code=123,
            signature_verified=True,
            signer_count=1,
            certificate_sha256="b" * 64,
            source_revision="c" * 40,
            declared_permissions=frozenset({MANAGE_EXTERNAL_STORAGE}),
            source_dirty=False,
        )
        admission_transport = FakeAddScanAdmissionTransport(
            FirstAddScanAdmissionTests.observation(
                admission.InstallationObservation.absent(),
                foreground=LAUNCHER,
            )
        )

        first_scan = admission.admit_first_add_scan_session(
            authorization,
            approval,
            artifact,
            admission_transport,
            now=NOW,
        )

        self.assertEqual(first_scan.code, admission.AdmissionCode.DEVICE_RESTORATION_PENDING)
        self.assertIsNone(first_scan.session)
        self.assertEqual(admission_transport.observation_calls, 0)

    def test_noop_permission_state_finishes_without_mutation(self) -> None:
        document = authorization_document()
        document["authorization_id"] = "authorization-noop-synthetic"
        document["operations"][0]["expected_prior_state"] = "denied"
        document["operations"][0]["desired_state"] = "denied"
        self.authorization, self.approval, self.session = self._create_test_session(document)
        self.transport = FakeOperationTransport()
        self.transport.permission_state = "denied"
        self.executor = admission.PermissionOperationExecutor(self.session, self.transport)
        result = self.executor.execute("permission-loss-synthetic", now=NOW)
        self.assertEqual(result.status, admission.OperationStatus.NO_CHANGE)
        self.assertEqual(self.transport.mutation_calls, [])
        self.assertEqual(self.session.lifecycle, admission.SessionLifecycle.COMPLETED)

    def test_unexpected_permission_baseline_blocks_before_mutation(self) -> None:
        self.transport.permission_state = "denied"
        result = self.executor.execute("permission-loss-synthetic", now=NOW)
        self.assertEqual(result.code, admission.OperationCode.PERMISSION_BASELINE_MISMATCH)
        self.assertEqual(self.transport.mutation_calls, [])
        self.assertEqual(self.session.lifecycle, admission.SessionLifecycle.BLOCKED)

    def test_unsupported_categories_and_unapproved_ids_never_reach_transport(self) -> None:
        unapproved = self.executor.execute("arbitrary-operation", now=NOW)
        self.assertEqual(unapproved.status, admission.OperationStatus.BLOCKED)
        self.assertEqual(self.transport.mutation_calls, [])

        document = authorization_document()
        document["authorization_id"] = "authorization-unsupported-synthetic"
        document["operations"] = [
            {
                "operation_id": "reset-synthetic",
                "category": "reset_data",
                "phase": "qualification",
                "target_serial": "private-serial-synthetic",
                "package_name": QUALIFICATION_PACKAGE,
                "timeout_seconds": 10,
                "permission_name": None,
                "expected_prior_state": None,
                "desired_state": None,
                "restoration": None,
            }
        ]
        document["approved_remediation"] = []
        auth = self._load_authorization(document)
        approval = self._load_approval(auth)
        artifact = admission.HostArtifactFacts(
            "a" * 64,
            QUALIFICATION_PACKAGE,
            123,
            True,
            1,
            "b" * 64,
            "c" * 40,
            frozenset({MANAGE_EXTERNAL_STORAGE}),
        )
        session_result = admission.admit_session(
            auth,
            approval,
            artifact,
            FakeOperationAdmissionTransport(),
            now=NOW,
        )
        self.assertEqual(session_result.status, admission.AdmissionStatus.ADMITTED)
        denied_transport = FakeOperationTransport()
        executor = admission.PermissionOperationExecutor(session_result.session, denied_transport)
        denied = executor.execute("reset-synthetic", now=NOW)
        self.assertEqual(denied.code, admission.OperationCode.OPERATION_UNSUPPORTED)
        self.assertEqual(denied_transport.mutation_calls, [])

    def test_path_mutation_category_is_rejected_before_transport(self) -> None:
        self._assert_unsupported_category_is_rejected_before_transport("path_mutation")

    def test_shell_category_is_rejected_before_transport(self) -> None:
        self._assert_unsupported_category_is_rejected_before_transport("shell")

# First fresh Add & Scan authorization and execution tests.
def operation(category: str, arguments: dict[str, str], *, phase: str = "admission"):
    return {
        "operation_id": f"{category}-synthetic",
        "category": category,
        "phase": phase,
        "target_serial": "private-serial-synthetic",
        "package_name": QUALIFICATION_PACKAGE,
        "timeout_seconds": 10,
        "permission_name": None,
        "expected_prior_state": None,
        "desired_state": None,
        "restoration": None,
        "arguments": arguments,
    }


class AddScanAuthorizationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.directory = Path(self.temporary_directory.name)

    def load(self, value):
        path = write_private_json(self.directory, "authorization.json", value)
        return manifest.load_authorization(path)

    def authorize(self, operation_value):
        document = authorization_document()
        document["operations"] = [operation_value]
        document["approved_remediation"] = []
        return document

    def test_absent_install_is_typed_to_exact_pinned_artifact_and_foreground(self):
        value = self.authorize(operation(
            "install_absent",
            {
                "action": "install_qualification_apk",
                "artifact_sha256": "a" * 64,
                "expected_foreground_package": "com.android.launcher3",
            },
        ))

        parsed = self.load(value)

        self.assertEqual(
            parsed.operations[0].category,
            manifest.OperationCategory.INSTALL_ABSENT,
        )
        self.assertEqual(
            dict(parsed.operations[0].arguments),
            {
                "action": "install_qualification_apk",
                "artifact_sha256": "a" * 64,
                "expected_foreground_package": "com.android.launcher3",
            },
        )

    def test_absent_install_rejects_wrong_artifact_or_ordinary_foreground(self):
        for arguments in (
            {
                "action": "install_qualification_apk",
                "artifact_sha256": "0" * 64,
                "expected_foreground_package": "com.android.launcher3",
            },
            {
                "action": "install_qualification_apk",
                "artifact_sha256": "a" * 64,
                "expected_foreground_package": "com.argusromtoolkit.argus",
            },
        ):
            with self.subTest(arguments=arguments):
                with self.assertRaises(manifest.AuthorizationError):
                    self.load(self.authorize(operation("install_absent", arguments)))

    def test_fresh_reset_is_a_fixed_qualification_package_operation(self):
        parsed = self.load(self.authorize(operation(
            "reset_data", {
                "action": "clear_qualification_data",
                "expected_foreground_package": QUALIFICATION_PACKAGE,
                "expected_foreground_after": "com.android.launcher3",
            }
        )))

        self.assertEqual(dict(parsed.operations[0].arguments), {
            "action": "clear_qualification_data",
            "expected_foreground_package": QUALIFICATION_PACKAGE,
            "expected_foreground_after": "com.android.launcher3",
        })

    def test_reset_cannot_name_a_different_package_or_generic_path(self):
        for arguments in (
            {
                "action": "clear_qualification_data",
                "expected_foreground_package": QUALIFICATION_PACKAGE,
                "expected_foreground_after": "com.android.launcher3",
                "package_name": "com.argusromtoolkit.argus",
            },
            {
                "action": "clear_qualification_data",
                "expected_foreground_package": QUALIFICATION_PACKAGE,
                "expected_foreground_after": "com.android.launcher3",
                "path": "/data/user/0/other.package",
            },
        ):
            with self.subTest(arguments=arguments):
                with self.assertRaises(manifest.AuthorizationError):
                    self.load(self.authorize(operation("reset_data", arguments)))

    def test_fixture_staging_uses_only_manifest_bound_symbolic_destination(self):
        parsed = self.load(self.authorize(operation(
            "fixture_staging",
            {
                "action": "stage_approved_fixture_set",
                "destination": "qualification_fixture_root",
                "fixture_manifest_sha256": "f" * 64,
                "expected_foreground_package": "com.android.launcher3",
            },
            phase="qualification",
        )))

        self.assertEqual(parsed.operations[0].arguments[1], (
            "destination", "qualification_fixture_root"
        ))

    def test_fixture_staging_rejects_generic_path_and_wrong_manifest(self):
        for arguments in (
            {
                "action": "stage_approved_fixture_set",
                "destination": "/sdcard/anywhere",
                "fixture_manifest_sha256": "f" * 64,
                "expected_foreground_package": "com.android.launcher3",
            },
            {
                "action": "stage_approved_fixture_set",
                "destination": "qualification_fixture_root",
                "fixture_manifest_sha256": "0" * 64,
                "expected_foreground_package": "com.android.launcher3",
            },
        ):
            with self.subTest(arguments=arguments):
                with self.assertRaises(manifest.AuthorizationError):
                    self.load(self.authorize(operation(
                        "fixture_staging", arguments, phase="qualification"
                    )))

    def test_first_add_scan_navigation_is_a_single_closed_action(self):
        parsed = self.load(self.authorize(operation(
            "navigation", {"action": "add_and_scan"}, phase="qualification"
        )))

        self.assertEqual(dict(parsed.operations[0].arguments), {
            "action": "add_and_scan",
        })

    def test_shell_category_cannot_receive_arguments(self):
        with self.assertRaises(manifest.AuthorizationError):
            self.load(self.authorize(operation("shell", {"command": "pm clear"})))


def _first_add_scan_plan(*, installation: str):
    target = "private-serial-synthetic"
    operations = []

    def add(op_id: str, category: str, phase: str, arguments: dict[str, str]):
        operations.append({
            "operation_id": op_id,
            "category": category,
            "phase": phase,
            "target_serial": target,
            "package_name": QUALIFICATION_PACKAGE,
            "timeout_seconds": 10,
            "permission_name": None,
            "expected_prior_state": None,
            "desired_state": None,
            "restoration": None,
            "arguments": arguments,
        })

    if installation == "absent":
        add("install-synthetic", "install_absent", "admission", {
            "action": "install_qualification_apk",
            "artifact_sha256": "a" * 64,
            "expected_foreground_package": "com.android.launcher3",
        })
    else:
        add("reset-synthetic", "reset_data", "admission", {
            "action": "clear_qualification_data",
            "expected_foreground_package": QUALIFICATION_PACKAGE,
            "expected_foreground_after": "com.android.launcher3",
        })
    add("stage-synthetic", "fixture_staging", "qualification", {
        "action": "stage_approved_fixture_set",
        "destination": "qualification_fixture_root",
        "fixture_manifest_sha256": "f" * 64,
        "expected_foreground_package": "com.android.launcher3",
    })
    add("launch-synthetic", "launch", "qualification", {
        "action": "launch_qualification_main",
        "expected_foreground_package": "com.android.launcher3",
    })
    for action in (
        "accept_terms", "preferences", "skip_provider", "add_root", "storage_root",
        "open_qualification_root", "open_fixture_root", "select_folder", "add_and_scan",
    ):
        add(f"navigate-{action}-synthetic", "navigation", "qualification", {"action": action})
    add("read-scan-admission-synthetic", "read_only", "qualification", {
        "observation": "scan_admission",
    })
    add("navigate-view-job-synthetic", "navigation", "qualification", {"action": "view_job"})
    add("read-job-status-synthetic", "read_only", "qualification", {
        "observation": "job_status",
    })
    add("read-terminal-scan-synthetic", "read_only", "qualification", {
        "observation": "terminal_scan",
    })
    add("navigate-library-synthetic", "navigation", "qualification", {
        "action": "library_navigation",
    })
    add("read-fixture-library-synthetic", "read_only", "qualification", {
        "observation": "fixture_library",
    })
    add("cleanup-synthetic", "fixture_staging", "cleanup", {
        "action": "remove_session_owned_fixture_set",
        "destination": "qualification_fixture_root",
        "fixture_manifest_sha256": "f" * 64,
        "expected_foreground_package": QUALIFICATION_PACKAGE,
    })
    document = authorization_document()
    document["operations"] = operations
    document["approved_remediation"] = []
    return document


def _first_add_scan_approval_document(authorization):
    """Approve the fixed plan budget and cleanup reserve within one window."""
    document = approval_document(authorization.canonical_sha256)
    document["valid_until_utc"] = authorization.session_deadline.strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )
    return document


class FakeAddScanAdmissionTransport:
    """Synthetic read-only observations; this transport has no device bridge."""

    def __init__(self, observation):
        self.observation = observation
        self.observation_calls = 0

    def observe_fresh_admission(self):
        self.observation_calls += 1
        return self.observation


class FirstAddScanAdmissionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.directory = Path(self.temporary_directory.name)
        self.registry_path_patch = mock.patch.object(
            admission, "_SESSION_REGISTRY_PATH", self.directory / "sessions.json"
        )
        self.safety_path_patch = mock.patch.object(
            admission, "_DEVICE_SAFETY_PATH", self.directory / "restoration.json"
        )
        self.registry_path_patch.start()
        self.safety_path_patch.start()
        self.addCleanup(self.registry_path_patch.stop)
        self.addCleanup(self.safety_path_patch.stop)

    def inputs(self, installation: str):
        document = _first_add_scan_plan(installation=installation)
        auth_path = write_private_json(self.directory, "authorization.json", document)
        authorization = manifest.load_authorization(auth_path)
        approval_path = write_private_json(
            self.directory,
            "approval.json",
            _first_add_scan_approval_document(authorization),
        )
        approval = manifest.load_owner_approval(approval_path, authorization, now=NOW)
        artifact = admission.HostArtifactFacts(
            apk_sha256="a" * 64,
            package_name=QUALIFICATION_PACKAGE,
            version_code=123,
            signature_verified=True,
            signer_count=1,
            certificate_sha256="b" * 64,
            source_revision="c" * 40,
            declared_permissions=frozenset({MANAGE_EXTERNAL_STORAGE}),
            source_dirty=False,
        )
        return authorization, approval, artifact

    @staticmethod
    def observation(installation, *, foreground=QUALIFICATION_PACKAGE, serials=("private-serial-synthetic",)):
        return admission.FreshAdmissionObservation(
            connected_serials=serials,
            android_api_level=35,
            abi="arm64-v8a",
            capabilities=frozenset({
                "foreground_package_observation",
                "installed_signer_observation",
                "permission_app_op_observation",
                "permission_app_op_mutation",
                "storage_reserve_observation",
            }),
            installation=installation,
            foreground_package=foreground,
            interference_free=True,
            available_storage_bytes=2_000_000_000,
        )

    def test_absent_installation_is_admitted_only_with_explicit_pinned_install(self):
        authorization, approval, artifact = self.inputs("absent")
        transport = FakeAddScanAdmissionTransport(self.observation(
            admission.InstallationObservation.absent(),
            foreground="com.android.launcher3",
        ))

        result = admission.admit_first_add_scan_session(
            authorization, approval, artifact, transport, now=NOW,
        )

        self.assertEqual(result.status, admission.AdmissionStatus.ADMITTED)
        self.assertIsNotNone(result.session)
        self.assertEqual(transport.observation_calls, 1)

    def test_short_approval_cannot_admit_plan_without_cleanup_reserve(self):
        authorization, _approval, artifact = self.inputs("absent")
        session_seconds = sum(
            operation.timeout_seconds
            for operation in authorization.operations
            if operation.phase != "cleanup"
        )
        cleanup_seconds = sum(
            operation.timeout_seconds
            for operation in authorization.operations
            if operation.phase == "cleanup"
        )
        short_valid_until = NOW + timedelta(
            seconds=session_seconds + cleanup_seconds - 1
        )
        short_document = approval_document(authorization.canonical_sha256)
        short_document["valid_until_utc"] = short_valid_until.strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        )
        short_approval = manifest.load_owner_approval(
            write_private_json(self.directory, "approval-short.json", short_document),
            authorization,
            now=NOW,
        )
        transport = FakeAddScanAdmissionTransport(self.observation(
            admission.InstallationObservation.absent(),
            foreground="com.android.launcher3",
        ))

        result = admission.admit_first_add_scan_session(
            authorization, short_approval, artifact, transport, now=NOW,
        )

        self.assertEqual(result.code, admission.AdmissionCode.ADD_SCAN_PLAN_INVALID)
        self.assertIsNone(result.session)
        self.assertEqual(transport.observation_calls, 0)
        self.assertFalse((self.directory / "sessions.json").exists())

        long_document = approval_document(authorization.canonical_sha256)
        long_document["valid_until_utc"] = authorization.session_deadline.strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        )
        long_approval = manifest.load_owner_approval(
            write_private_json(self.directory, "approval-long.json", long_document),
            authorization,
            now=NOW,
        )
        retry_transport = FakeAddScanAdmissionTransport(self.observation(
            admission.InstallationObservation.absent(),
            foreground="com.android.launcher3",
        ))
        retry = admission.admit_first_add_scan_session(
            authorization, long_approval, artifact, retry_transport, now=NOW,
        )

        self.assertEqual(retry.status, admission.AdmissionStatus.ADMITTED)
        self.assertEqual(retry_transport.observation_calls, 1)

    def test_compatible_installation_requires_explicit_data_reset(self):
        authorization, approval, artifact = self.inputs("compatible")
        transport = FakeAddScanAdmissionTransport(self.observation(
            admission.InstallationObservation(
                admission.InstallationStatus.PRESENT,
                QUALIFICATION_PACKAGE,
                123,
                "b" * 64,
                "a" * 64,
            )
        ))

        result = admission.admit_first_add_scan_session(
            authorization, approval, artifact, transport, now=NOW,
        )

        self.assertEqual(result.status, admission.AdmissionStatus.ADMITTED)
        self.assertIsNotNone(result.session)

    def test_compatible_version_and_signer_with_wrong_artifact_digest_blocks(self):
        authorization, approval, artifact = self.inputs("compatible")
        transport = FakeAddScanAdmissionTransport(self.observation(
            admission.InstallationObservation(
                admission.InstallationStatus.PRESENT,
                QUALIFICATION_PACKAGE,
                123,
                "b" * 64,
                "0" * 64,
            )
        ))

        result = admission.admit_first_add_scan_session(
            authorization, approval, artifact, transport, now=NOW,
        )

        self.assertEqual(result.code, admission.AdmissionCode.QUALIFICATION_APP_INCOMPATIBLE)
        self.assertIsNone(result.session)

    def test_incompatible_installation_blocks_before_any_operation(self):
        authorization, approval, artifact = self.inputs("compatible")
        transport = FakeAddScanAdmissionTransport(self.observation(
            admission.InstallationObservation(
                admission.InstallationStatus.PRESENT,
                QUALIFICATION_PACKAGE,
                122,
                "b" * 64,
            )
        ))

        result = admission.admit_first_add_scan_session(
            authorization, approval, artifact, transport, now=NOW,
        )

        self.assertEqual(result.code, admission.AdmissionCode.QUALIFICATION_APP_INCOMPATIBLE)
        self.assertIsNone(result.session)
        self.assertEqual(transport.observation_calls, 1)

    def test_absent_installation_rejects_compatible_reset_plan(self):
        authorization, approval, artifact = self.inputs("compatible")
        transport = FakeAddScanAdmissionTransport(self.observation(
            admission.InstallationObservation.absent(),
            foreground="com.android.launcher3",
        ))

        result = admission.admit_first_add_scan_session(
            authorization, approval, artifact, transport, now=NOW,
        )

        self.assertEqual(result.code, admission.AdmissionCode.ADD_SCAN_PLAN_INVALID)
        self.assertIsNone(result.session)

    def test_wrong_foreground_blocks_absent_install_before_mutation(self):
        authorization, approval, artifact = self.inputs("absent")
        transport = FakeAddScanAdmissionTransport(self.observation(
            admission.InstallationObservation.absent(),
            foreground="com.argusromtoolkit.argus.qualification",
        ))

        result = admission.admit_first_add_scan_session(
            authorization, approval, artifact, transport, now=NOW,
        )

        self.assertEqual(result.code, admission.AdmissionCode.FOREGROUND_MISMATCH)
        self.assertIsNone(result.session)

    def test_multiple_targets_block_add_scan_admission(self):
        authorization, approval, artifact = self.inputs("absent")
        transport = FakeAddScanAdmissionTransport(self.observation(
            admission.InstallationObservation.absent(),
            foreground="com.android.launcher3",
            serials=("private-serial-synthetic", "another-device"),
        ))

        result = admission.admit_first_add_scan_session(
            authorization, approval, artifact, transport, now=NOW,
        )

        self.assertEqual(result.code, admission.AdmissionCode.AMBIGUOUS_TARGET)
        self.assertIsNone(result.session)

    def test_dirty_provenance_artifact_blocks_before_device_observation(self):
        authorization, approval, artifact = self.inputs("absent")
        artifact = admission.HostArtifactFacts(
            apk_sha256=artifact.apk_sha256,
            package_name=artifact.package_name,
            version_code=artifact.version_code,
            signature_verified=artifact.signature_verified,
            signer_count=artifact.signer_count,
            certificate_sha256=artifact.certificate_sha256,
            source_revision=artifact.source_revision,
            declared_permissions=artifact.declared_permissions,
            source_dirty=True,
        )
        transport = FakeAddScanAdmissionTransport(self.observation(
            admission.InstallationObservation.absent(),
            foreground="com.android.launcher3",
        ))

        result = admission.admit_first_add_scan_session(
            authorization, approval, artifact, transport, now=NOW,
        )

        self.assertEqual(result.code, admission.AdmissionCode.ARTIFACT_MISMATCH)
        self.assertEqual(transport.observation_calls, 0)

LAUNCHER = "com.android.launcher3"


def alias(kind: str, value: str) -> str:
    digest = hashlib.sha256(f"{kind}:{value}".encode()).hexdigest()[:32]
    return f"{kind}-{digest}"


def evidence_session_id(authorization) -> str:
    return hashlib.sha256(
        f"argus-add-scan:{authorization.authorization_id}:{authorization.canonical_sha256}".encode()
    ).hexdigest()[:32]


def session_spec(authorization) -> evidence.SessionSpec:
    return evidence.SessionSpec(
        session_id=evidence_session_id(authorization),
        scenario_id=alias("scenario", authorization.scenario_ids[0]),
        artifact=evidence.ArtifactPin(
            alias("artifact", authorization.apk_sha256),
            authorization.apk_sha256,
            evidence.ArtifactClass.QUALIFICATION_VARIANT,
        ),
        authorization=evidence.AuthorizationPin(1, authorization.canonical_sha256),
        fixtures=evidence.FixturePin(
            2,
            authorization.fixture_manifest_sha256,
            alias("corpus", authorization.fixture_manifest_sha256),
        ),
        plan=evidence.PlanPin(
            alias("plan", authorization.plan_sha256), 1, authorization.plan_sha256
        ),
        rules=evidence.AcceptanceRulesPin(
            alias("rules", authorization.rules_sha256), "1.0.0", authorization.rules_sha256
        ),
        environment=evidence.EnvironmentPin(
            evidence.Platform.ANDROID,
            alias("platform-version", "api-35"),
            alias("environment", "synthetic-api-35"),
            alias("target", authorization.target_ref),
        ),
        review_requirements=evidence.ReviewRequirements(
            required_evidence_refs=(alias("evidence", "synthetic-add-scan"),),
            objective_review_allowed=True,
            direct_owner_observation_allowed=True,
            retrospective_allowed=False,
        ),
    )


def xml_frame(*labels: str) -> str:
    nodes = "".join(
        f'<node package="{QUALIFICATION_PACKAGE}" text="{label}" content-desc="" '
        'enabled="true" clickable="true" visible-to-user="true" '
        f'bounds="[{index * 120},20][{index * 120 + 100},80]" />'
        for index, label in enumerate(labels)
    )
    return f'<hierarchy rotation="0">{nodes}</hierarchy>'


class FakeAddScanTransport:
    """A poisoned-ADB fake: every call is a typed in-memory operation."""

    def __init__(self, installation: str):
        self.installation = installation
        self.foreground = LAUNCHER if installation == "absent" else QUALIFICATION_PACKAGE
        self.calls: list[tuple] = []
        self.mutations: list[str] = []
        self.nav_actions: list[str] = []
        self.capture_count = 0
        self.captures_by_navigation_count: dict[int, int] = {}
        self.staged = False
        self.install_calls = 0
        self.reset_calls = 0
        self.stage_calls = 0
        self.cleanup_calls = 0
        self.install_uncertain = False
        self.install_deadline_expired = False
        self.launch_uncertain = False
        self.stage_uncertain = False
        self.stage_interrupted = False
        self.stage_receipt_override = None
        self.cleanup_receipt_override = None
        self.cleanup_uncertain = False
        self.cleanup_interrupted = False
        self.cleanup_interrupted_error = False
        self.navigation_uncertain_action: str | None = None
        self.ambiguous_navigation_action: str | None = None
        self.interrupt_action: str | None = None
        self.interrupted_action: str | None = None
        self.cleanup_succeeds = True
        self.scan_admission_succeeds = True
        self.scan_admission_uncertain = False
        self.job_status_label = "Completed"
        self.scan_status_label = "Complete"
        self.job_status_frames: list[tuple[str, ...]] | None = None
        self.job_status_repeat_last_frame = True
        self.job_status_interrupt_at: int | None = None
        self.job_status_capture_count = 0
        self.job_status_capture_clock = None
        self.job_status_capture_times: list[float] = []
        self.fixture_library_label = "Metroid, NES"
        self.target_matches = True
        self.foreground_drift = False
        self.installed_package_override = None
        self.transacted_packages: list[str] = []
        self.capture_slots: list[str] = []

    def observe_fresh_admission(self):
        installed = admission.InstallationObservation.absent()
        if self.installation == "compatible":
            installed = admission.InstallationObservation(
                admission.InstallationStatus.PRESENT,
                QUALIFICATION_PACKAGE,
                123,
                "b" * 64,
                "a" * 64,
            )
        return admission.FreshAdmissionObservation(
            connected_serials=("private-serial-synthetic",),
            android_api_level=35,
            abi="arm64-v8a",
            capabilities=frozenset({
                "foreground_package_observation",
                "installed_signer_observation",
                "permission_app_op_observation",
                "permission_app_op_mutation",
                "storage_reserve_observation",
            }),
            installation=installed,
            foreground_package=self.foreground,
            interference_free=True,
            available_storage_bytes=2_000_000_000,
        )

    def verify_target(self, serial, target_ref, timeout_seconds):
        self.calls.append(("verify_target", serial, target_ref))
        return self.target_matches

    def verify_foreground(self, package_name, timeout_seconds):
        self.calls.append(("verify_foreground", package_name))
        if self.foreground_drift:
            return False
        return self.foreground == package_name

    def observe_installed_package(
        self, serial, package_name, version_code, certificate_sha256, timeout_seconds
    ):
        self.calls.append(("observe_installed_package", package_name))
        if self.installation == "absent":
            return admission.InstallationObservation.absent()
        if self.installed_package_override is not None:
            return self.installed_package_override
        return admission.InstallationObservation(
            admission.InstallationStatus.PRESENT,
            QUALIFICATION_PACKAGE,
            123,
            "b" * 64,
            "a" * 64,
        )

    def install_qualification_artifact(
        self, serial, package_name, apk_sha256, certificate_sha256, version_code, timeout_seconds
    ):
        self.mutations.append("install_absent")
        self.transacted_packages.append(package_name)
        self.install_calls += 1
        if self.install_uncertain:
            self.installation = "compatible"
            raise TimeoutError("synthetic install response lost")
        self.installation = "compatible"
        if self.install_deadline_expired:
            raise admission._OperationDeadlineExpired

    def reset_qualification_data(self, serial, package_name, timeout_seconds):
        self.mutations.append("reset_data")
        self.transacted_packages.append(package_name)
        self.reset_calls += 1
        if self.install_uncertain:
            raise TimeoutError("synthetic reset response lost")
        self.foreground = LAUNCHER
        return True

    def stage_approved_fixture_set(
        self, serial, package_name, session_id, fixture_plan, destination, timeout_seconds
    ):
        self.mutations.append("stage_fixtures")
        self.transacted_packages.append(package_name)
        self.stage_calls += 1
        self.staged = True
        if self.stage_interrupted:
            raise InterruptedError("synthetic interrupted staging response contains private details")
        if self.stage_uncertain:
            raise TimeoutError("synthetic fixture staging response lost")
        if self.stage_receipt_override is not None:
            return self.stage_receipt_override
        return admission.FixtureStageReceipt(
            session_id=session_id,
            fixture_manifest_sha256=fixture_plan.fixture_manifest_sha256,
            file_count=fixture_plan.file_count,
            byte_count=fixture_plan.byte_count,
            content_sha256=fixture_plan.content_sha256,
        )

    def launch_qualification_main(self, serial, package_name, timeout_seconds):
        self.mutations.append("launch")
        self.transacted_packages.append(package_name)
        self.foreground = QUALIFICATION_PACKAGE
        if self.launch_uncertain:
            raise TimeoutError("synthetic launch response lost")

    def capture_accessibility(self, serial, package_name, session_id, capture_slot, timeout_seconds):
        self.calls.append(("capture_accessibility", session_id))
        self.capture_slots.append(capture_slot)
        self.capture_count += 1
        nav_actions = (
            "accept_terms", "preferences", "skip_provider", "add_root", "storage_root",
            "open_qualification_root", "open_fixture_root", "select_folder", "add_and_scan",
            "view_job", "library_navigation",
        )
        index = len(self.nav_actions)
        captures_at_index = self.captures_by_navigation_count.get(index, 0)
        self.captures_by_navigation_count[index] = captures_at_index + 1
        if index < 9:
            label = nav_actions[index]
            if label == self.ambiguous_navigation_action:
                return xml_frame(
                    "Unexpected synthetic surface Metroid private-serial-synthetic "
                    "synthetic-credential-canary"
                )
            frames = {
                "accept_terms": ("Set up your Library", "Accept current terms"),
                "preferences": ("Use current preferences",),
                "skip_provider": ("Skip SteamGridDB",),
                "add_root": ("Add Library Folder",),
                "storage_root": ("Choose a storage volume", "Internal shared storage"),
                "open_qualification_root": ("ArgusQualification",),
                "open_fixture_root": ("fixtures",),
                "select_folder": ("Select this folder",),
                "add_and_scan": (
                    "Add Library Folder?",
                    "/storage/emulated/0/ArgusQualification/fixtures",
                    "Add &amp; Scan",
                ),
            }
            return xml_frame(*frames[label])
        if index == 9:
            if self.scan_admission_uncertain:
                return xml_frame("Scan not confirmed")
            if self.scan_admission_succeeds:
                return xml_frame("Scanning in progress", "View Job")
            return xml_frame(
                "Folder added, but the scan could not start. You can scan it from the folder details."
            )
        if index == 10 and self.job_status_frames is not None:
            frame_index = self.job_status_capture_count
            if frame_index >= len(self.job_status_frames) and not self.job_status_repeat_last_frame:
                return xml_frame("Library", "Search Library")
            if self.job_status_capture_clock is not None:
                self.job_status_capture_times.append(self.job_status_capture_clock())
            self.job_status_capture_count += 1
            if self.job_status_interrupt_at == frame_index + 1:
                raise InterruptedError("synthetic job poll interruption contains private details")
            if frame_index < len(self.job_status_frames):
                return xml_frame(*self.job_status_frames[frame_index])
            return xml_frame(*self.job_status_frames[-1])
        if index == 10 and captures_at_index == 0:
            return xml_frame(
                "Library Scan",
                f"Job status: {self.job_status_label}",
                self.scan_status_label,
            )
        if index == 10:
            return xml_frame("Library", "Search Library")
        if index == 11:
            return xml_frame("Search Library", self.fixture_library_label)
        if index == 12:
            return xml_frame("Library Scan", "Job status: Completed", "Complete")
        raise AssertionError("unexpected synthetic UI capture")

    def tap_accessibility_control(self, serial, package_name, action, bounds, timeout_seconds):
        self.mutations.append(f"navigation:{action}")
        self.transacted_packages.append(package_name)
        self.nav_actions.append(action)
        if action == self.interrupted_action:
            raise InterruptedError("synthetic interrupted tap response contains private details")
        if action == self.interrupt_action:
            raise KeyboardInterrupt
        if action == self.navigation_uncertain_action:
            raise TimeoutError("synthetic tap result lost")

    def cleanup_session_fixture_set(
        self, serial, package_name, session_id, fixture_manifest_sha256, destination, timeout_seconds
    ):
        self.mutations.append("cleanup_fixtures")
        self.transacted_packages.append(package_name)
        self.cleanup_calls += 1
        if self.cleanup_uncertain:
            self.staged = False
            raise TimeoutError("synthetic cleanup response lost")
        if self.cleanup_interrupted:
            self.staged = False
            raise KeyboardInterrupt
        if self.cleanup_interrupted_error:
            self.staged = False
            raise InterruptedError("synthetic interrupted cleanup response contains private details")
        if self.cleanup_succeeds:
            self.staged = False
            if self.cleanup_receipt_override is not None:
                return self.cleanup_receipt_override
            return admission.FixtureCleanupReceipt(
                session_id=session_id,
                fixture_manifest_sha256=fixture_manifest_sha256,
                removed_file_count=1,
                remaining_file_count=0,
            )
        return None


class FailingWriter:
    def __init__(self, writer, *, fail_method):
        self.writer = writer
        self.fail_method = fail_method

    def __getattr__(self, name):
        value = getattr(self.writer, name)
        if name != self.fail_method:
            return value

        def fail(*_args, **_kwargs):
            raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNAVAILABLE)

        return fail


class RecordingWriter:
    """Capture successfully appended observations while preserving facade writes."""

    def __init__(self, writer):
        self.writer = writer
        self.assertions = []
        self.lifecycles = []
        self.terminals = []
        self.events = []

    def __getattr__(self, name):
        value = getattr(self.writer, name)
        if name == "append_assertion":
            def append_assertion(*args, **kwargs):
                receipt = value(*args, **kwargs)
                self.assertions.append(args[1])
                self.events.append(("assertion", args[1], args[2]))
                return receipt

            return append_assertion
        if name == "append_lifecycle":
            def append_lifecycle(*args, **kwargs):
                receipt = value(*args, **kwargs)
                self.lifecycles.append(args[1])
                self.events.append(("lifecycle", args[1], args[2]))
                return receipt

            return append_lifecycle
        if name == "append_terminal":
            def append_terminal(*args, **kwargs):
                receipt = value(*args, **kwargs)
                self.terminals.append(args[1])
                self.events.append(("terminal", args[1], args[2]))
                return receipt

            return append_terminal
        return value


class FailingAssertionRefWriter:
    """Fail one selected assertion append while forwarding all other writes."""

    def __init__(self, writer, *, assertion_ref):
        self.writer = writer
        self.assertion_ref = assertion_ref
        self.failed = False

    def append_assertion(self, session_id, observation, request):
        if observation.assertion_ref == self.assertion_ref and not self.failed:
            self.failed = True
            raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNAVAILABLE)
        return self.writer.append_assertion(session_id, observation, request)

    def __getattr__(self, name):
        return getattr(self.writer, name)


class AppendThenRaiseTerminalWriter:
    """Model an append that became durable before its acknowledgement failed."""

    def __init__(self, writer):
        self.writer = writer
        self.calls = 0

    def append_terminal(self, *args, **kwargs):
        self.calls += 1
        self.writer.append_terminal(*args, **kwargs)
        raise evidence.EvidenceError(evidence.EvidenceErrorCode.UNAVAILABLE)

    def __getattr__(self, name):
        return getattr(self.writer, name)


class NonIntegerCountImpostor:
    """Compare equal to one receipt count while retaining a non-integer type."""

    def __init__(self, expected: int) -> None:
        self.expected = expected

    def __eq__(self, other: object) -> bool:
        return type(other) is int and other == self.expected


class AddScanExecutorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.directory = Path(self.temporary_directory.name)
        mock.patch.object(
            admission, "_SESSION_REGISTRY_PATH", self.directory / "sessions.json"
        ).start()
        self.addCleanup(mock.patch.stopall)
        mock.patch.object(
            admission, "_DEVICE_SAFETY_PATH", self.directory / "restoration.json"
        ).start()
        self.evidence_store = evidence.EvidenceStore(self.directory / "evidence")

    def admitted(self, installation: str, *, authorization_id: str | None = None):
        document = _first_add_scan_plan(installation=installation)
        if authorization_id is not None:
            document["authorization_id"] = authorization_id
        authorization = manifest.load_authorization(
            write_private_json(
                self.directory,
                f"authorization-{document['authorization_id']}.json",
                document,
            )
        )
        approval = manifest.load_owner_approval(
            write_private_json(
                self.directory,
                f"approval-{authorization.authorization_id}.json",
                _first_add_scan_approval_document(authorization),
            ),
            authorization,
            now=NOW,
        )
        artifact = admission.HostArtifactFacts(
            apk_sha256="a" * 64,
            package_name=QUALIFICATION_PACKAGE,
            version_code=123,
            signature_verified=True,
            signer_count=1,
            certificate_sha256="b" * 64,
            source_revision="c" * 40,
            declared_permissions=frozenset({MANAGE_EXTERNAL_STORAGE}),
            source_dirty=False,
        )
        transport = FakeAddScanTransport(installation)
        result = admission.admit_first_add_scan_session(
            authorization, approval, artifact, transport, now=NOW
        )
        self.assertEqual(result.status, admission.AdmissionStatus.ADMITTED)
        return authorization, result.session, transport

    def fixture_plan(self, authorization):
        return admission.FixtureTransferPlan(
            fixture_manifest_sha256=authorization.fixture_manifest_sha256,
            file_count=1,
            byte_count=4,
            content_sha256="1" * 64,
        )

    def expectations(self):
        return (ui.LibraryExpectation("fixture-synthetic", "Metroid", "NES"),)

    def executor(
        self,
        session,
        transport,
        *,
        writer=None,
        installation="absent",
        library_expectations=None,
        monotonic=None,
        sleeper=None,
    ):
        clock_options = {}
        if monotonic is not None:
            clock_options["monotonic"] = monotonic
        if sleeper is not None:
            clock_options["sleeper"] = sleeper
        return admission._AddScanOperationExecutor(
            session=session,
            transport=transport,
            writer=writer or self.evidence_store.execution_writer(),
            evidence_spec=session_spec(session.authorization),
            fixture_plan=self.fixture_plan(session.authorization),
            library_expectations=library_expectations or self.expectations(),
            **clock_options,
        )

    def assert_uncertain_evidence_is_durable(self, result, writer):
        self.assertTrue(any(
            item.actual_outcome is evidence.AssertionOutcome.BLOCKED
            for item in writer.assertions
        ))
        self.assertEqual(
            writer.terminals[-1].outcome,
            evidence.TerminalOutcome.BLOCKED,
        )
        self.assertIsNotNone(result.execution_manifest_sha256)

    def assert_no_owner_verdict_and_sanitized_output(
        self,
        authorization,
        result,
        *,
        execution_manifest_sha256=None,
    ):
        reviewer = self.evidence_store.owner_reviewer(
            admission._add_scan_alias("owner", "synthetic-reviewer")
        )
        scenario_ref = session_spec(authorization).scenario_id
        self.assertIsNone(reviewer.latest_verdict(scenario_ref))
        manifest_sha256 = execution_manifest_sha256 or result.execution_manifest_sha256
        self.assertIsNotNone(manifest_sha256)
        packet = reviewer.review_packet(manifest_sha256).decode("utf-8")
        safe_output = repr(result) + packet
        for private_value in (
            "private-serial-synthetic",
            str(self.directory),
            "/storage/emulated/0/ArgusQualification/fixtures",
            "Metroid",
            "Unexpected synthetic surface",
            "synthetic-credential-canary",
        ):
            self.assertNotIn(private_value, safe_output)

    def test_fake_session_observes_all_stages_and_finishes_blocked_on_synthetic_identity(self):
        authorization, session, transport = self.admitted("absent")
        writer = self.evidence_store.execution_writer()

        with mock.patch("subprocess.run", side_effect=AssertionError("ADB")), \
             mock.patch("subprocess.Popen", side_effect=AssertionError("ADB")), \
             mock.patch("os.system", side_effect=AssertionError("ADB")):
            result = self.executor(session, transport, writer=writer).execute(now=NOW)

        self.assertEqual(result.status, admission.AddScanExecutionStatus.BLOCKED)
        self.assertTrue(result.workflow_completed)
        self.assertEqual(result.scan_admission, "admitted")
        self.assertEqual(result.job_status, "completed")
        self.assertEqual(result.terminal_scan_status, "complete")
        self.assertEqual(result.fixture_result_indices, (0,))
        self.assertEqual(result.cleanup_status, "verified")
        self.assertEqual(transport.install_calls, 1)
        self.assertEqual(transport.stage_calls, 1)
        self.assertEqual(transport.cleanup_calls, 1)
        self.assertFalse(transport.staged)
        execution = writer.verify_execution(evidence_session_id(authorization))
        self.assertGreater(execution.record_count, 10)
        snapshot = writer.snapshot(execution.session_id)
        self.assertEqual(snapshot.state, "finalized")
        self.assertEqual(snapshot.records[-1].event_type, "terminal")
        self.assertEqual(snapshot.records[-3].event_type, "lifecycle")
        self.assertEqual(snapshot.records[-2].event_type, "assertion")
        self.assertTrue(all(package == QUALIFICATION_PACKAGE for package in transport.transacted_packages))
        self.assertTrue(all(
            slot == admission.QUALIFICATION_CAPTURE_SLOT
            for slot in transport.capture_slots
        ))
        self.assertEqual(result.scope_extensions, ())
        self.assertIn("identity", result.blocker.lower())
        self.assertIn("physical", result.blocker.lower())

    def test_compatible_install_requires_one_explicit_reset_and_never_reinstalls(self):
        _authorization, session, transport = self.admitted("compatible")

        result = self.executor(session, transport, installation="compatible").execute(now=NOW)

        self.assertEqual(result.status, admission.AddScanExecutionStatus.BLOCKED)
        self.assertEqual(transport.reset_calls, 1)
        self.assertEqual(transport.install_calls, 0)

    def test_uncertain_install_blocks_without_retry_or_later_product_mutation(self):
        _authorization, session, transport = self.admitted("absent")
        transport.install_uncertain = True
        writer = RecordingWriter(self.evidence_store.execution_writer())

        result = self.executor(session, transport, writer=writer).execute(now=NOW)

        self.assertEqual(result.status, admission.AddScanExecutionStatus.BLOCKED)
        self.assertEqual(transport.install_calls, 1)
        self.assertEqual(transport.stage_calls, 0)
        self.assertEqual(transport.mutations, ["install_absent"])
        self.assertTrue(any(
            item.actual_outcome is evidence.AssertionOutcome.BLOCKED
            for item in writer.assertions
        ))
        self.assert_uncertain_evidence_is_durable(result, writer)
        self.assertTrue(any("install" in item.area for item in result.scope_extensions))

    def test_install_deadline_timeout_is_uncertain_and_never_retried(self):
        authorization, session, transport = self.admitted("absent")
        transport.install_deadline_expired = True
        writer = RecordingWriter(self.evidence_store.execution_writer())

        result = self.executor(session, transport, writer=writer).execute(now=NOW)

        self.assertEqual(result.status, admission.AddScanExecutionStatus.BLOCKED)
        self.assertEqual(transport.install_calls, 1)
        self.assertEqual(transport.stage_calls, 0)
        self.assertEqual(transport.mutations, ["install_absent"])
        self.assertTrue(any(
            item.actual_outcome is evidence.AssertionOutcome.BLOCKED
            for item in writer.assertions
        ))
        self.assertEqual(writer.terminals[-1].outcome, evidence.TerminalOutcome.BLOCKED)
        self.assert_uncertain_evidence_is_durable(result, writer)
        self.assert_no_owner_verdict_and_sanitized_output(authorization, result)

    def test_interrupted_fixture_stage_is_not_replayed_or_cleaned_without_receipt(self):
        authorization, session, transport = self.admitted("absent")
        transport.stage_interrupted = True
        writer = RecordingWriter(self.evidence_store.execution_writer())

        result = self.executor(session, transport, writer=writer).execute(now=NOW)

        self.assertEqual(result.status, admission.AddScanExecutionStatus.BLOCKED)
        self.assertEqual(result.cleanup_status, "blocked")
        self.assertEqual(transport.stage_calls, 1)
        self.assertEqual(transport.cleanup_calls, 0)
        self.assertEqual(transport.mutations, ["install_absent", "stage_fixtures"])
        self.assertEqual(writer.terminals[-1].outcome, evidence.TerminalOutcome.INTERRUPTED)
        self.assertTrue(any(
            item.actual_outcome is evidence.AssertionOutcome.BLOCKED
            for item in writer.assertions
        ))
        self.assertTrue(any(
            item.area == "fixture staging ownership and cleanup"
            for item in result.scope_extensions
        ))
        execution = writer.verify_execution(evidence_session_id(authorization))
        self.assertEqual(writer.snapshot(execution.session_id).state, "finalized")
        self.assertNotIn("synthetic interrupted staging response", repr(result))
        self.assert_no_owner_verdict_and_sanitized_output(authorization, result)

    def test_interrupted_add_and_scan_tap_stops_observation_and_withholds_cleanup(self):
        authorization, session, transport = self.admitted("absent")
        transport.interrupted_action = "add_and_scan"
        writer = RecordingWriter(self.evidence_store.execution_writer())

        result = self.executor(session, transport, writer=writer).execute(now=NOW)

        self.assertEqual(result.status, admission.AddScanExecutionStatus.BLOCKED)
        self.assertEqual(transport.nav_actions.count("add_and_scan"), 1)
        self.assertEqual(transport.nav_actions.count("view_job"), 0)
        self.assertEqual(transport.nav_actions.count("library_navigation"), 0)
        self.assertEqual(transport.cleanup_calls, 0)
        self.assertEqual(writer.terminals[-1].outcome, evidence.TerminalOutcome.INTERRUPTED)
        self.assertTrue(any(
            item.area == "uncertain Add & Scan tap recovery"
            for item in result.scope_extensions
        ))
        self.assertEqual(transport.mutations.count("navigation:add_and_scan"), 1)
        execution = writer.verify_execution(evidence_session_id(authorization))
        self.assertEqual(writer.snapshot(execution.session_id).state, "finalized")
        self.assertNotIn("synthetic interrupted tap response", repr(result))
        self.assert_no_owner_verdict_and_sanitized_output(authorization, result)

    def test_uncertain_reset_blocks_without_retry_or_reinstall(self):
        _authorization, session, transport = self.admitted("compatible")
        transport.install_uncertain = True
        writer = RecordingWriter(self.evidence_store.execution_writer())

        result = self.executor(session, transport, writer=writer, installation="compatible").execute(now=NOW)

        self.assertEqual(result.status, admission.AddScanExecutionStatus.BLOCKED)
        self.assertEqual(transport.reset_calls, 1)
        self.assertEqual(transport.install_calls, 0)
        self.assertEqual(transport.stage_calls, 0)
        self.assertEqual(transport.mutations, ["reset_data"])
        self.assertTrue(any(
            item.actual_outcome is evidence.AssertionOutcome.BLOCKED
            for item in writer.assertions
        ))
        self.assert_uncertain_evidence_is_durable(result, writer)
        self.assertTrue(any("reset" in item.area for item in result.scope_extensions))

    def test_uncertain_fixture_staging_is_not_retried_or_cleaned_without_readback_ownership(self):
        _authorization, session, transport = self.admitted("absent")
        transport.stage_uncertain = True
        writer = RecordingWriter(self.evidence_store.execution_writer())

        result = self.executor(session, transport, writer=writer).execute(now=NOW)

        self.assertEqual(result.status, admission.AddScanExecutionStatus.BLOCKED)
        self.assertEqual(transport.stage_calls, 1)
        self.assertEqual(transport.cleanup_calls, 0)
        self.assertIn("fixture staging ownership is uncertain", result.blocker.lower())
        self.assertTrue(any(
            item.actual_outcome is evidence.AssertionOutcome.BLOCKED
            for item in writer.assertions
        ))
        self.assert_uncertain_evidence_is_durable(result, writer)

    def test_mismatched_stage_receipt_is_durably_blocked_without_retry_or_cleanup(self):
        receipt_changes = [
            ("session_id", "f" * 32, "mismatch"),
            ("fixture_manifest_sha256", "0" * 64, "mismatch"),
            ("file_count", 2, "mismatch"),
            ("byte_count", 5, "mismatch"),
            ("content_sha256", "0" * 64, "mismatch"),
        ]
        for field, expected in (("file_count", 1), ("byte_count", 4)):
            receipt_changes.extend(
                (field, value, case)
                for case, value in (
                    ("bool_true", True),
                    ("bool_false", False),
                    ("float", float(expected)),
                    ("string", str(expected)),
                    ("non_integer_equal", NonIntegerCountImpostor(expected)),
                )
            )
        for index, (field, wrong_value, case) in enumerate(receipt_changes):
            with self.subTest(field=field, case=case):
                authorization, session, transport = self.admitted(
                    "absent",
                    authorization_id=f"issue26-receipt-mismatch-{index}",
                )
                plan = self.fixture_plan(authorization)
                valid_receipt = admission.FixtureStageReceipt(
                    session_id=evidence_session_id(authorization),
                    fixture_manifest_sha256=plan.fixture_manifest_sha256,
                    file_count=plan.file_count,
                    byte_count=plan.byte_count,
                    content_sha256=plan.content_sha256,
                )
                transport.stage_receipt_override = replace(
                    valid_receipt,
                    **{field: wrong_value},
                )
                writer = RecordingWriter(self.evidence_store.execution_writer())

                result = self.executor(session, transport, writer=writer).execute(now=NOW)

                self.assertEqual(result.status, admission.AddScanExecutionStatus.BLOCKED)
                self.assertEqual(result.cleanup_status, "blocked")
                self.assertEqual(transport.stage_calls, 1)
                self.assertEqual(transport.cleanup_calls, 0)
                self.assertEqual(transport.nav_actions, [])
                self.assertTrue(any(
                    item.actual_outcome is evidence.AssertionOutcome.BLOCKED
                    for item in writer.assertions
                ))
                self.assert_uncertain_evidence_is_durable(result, writer)
                self.assertTrue(any("staging" in item.area for item in result.scope_extensions))
                self.assertEqual(
                    writer.snapshot(evidence_session_id(authorization)).state,
                    "finalized",
                )

    def test_uncertain_launch_is_recorded_and_not_retried(self):
        _authorization, session, transport = self.admitted("absent")
        transport.launch_uncertain = True
        writer = RecordingWriter(self.evidence_store.execution_writer())

        result = self.executor(session, transport, writer=writer).execute(now=NOW)

        self.assertEqual(result.status, admission.AddScanExecutionStatus.BLOCKED)
        self.assertEqual(transport.mutations.count("launch"), 1)
        self.assertEqual(transport.nav_actions, [])
        self.assertTrue(any(
            item.actual_outcome is evidence.AssertionOutcome.BLOCKED
            for item in writer.assertions
        ))
        self.assert_uncertain_evidence_is_durable(result, writer)
        self.assertTrue(any("launch" in item.area for item in result.scope_extensions))

    def test_uncertain_navigation_tap_is_recorded_and_not_retried(self):
        _authorization, session, transport = self.admitted("absent")
        transport.navigation_uncertain_action = "preferences"
        writer = RecordingWriter(self.evidence_store.execution_writer())

        result = self.executor(session, transport, writer=writer).execute(now=NOW)

        self.assertEqual(result.status, admission.AddScanExecutionStatus.BLOCKED)
        self.assertEqual(transport.nav_actions, ["accept_terms", "preferences"])
        self.assertEqual(transport.nav_actions.count("preferences"), 1)
        self.assertTrue(any(
            item.actual_outcome is evidence.AssertionOutcome.BLOCKED
            for item in writer.assertions
        ))
        self.assert_uncertain_evidence_is_durable(result, writer)
        self.assertTrue(any("navigation" in item.area for item in result.scope_extensions))

    def test_wrong_installed_package_or_signer_blocks_before_fixture_mutation(self):
        wrong_installations = (
            admission.InstallationObservation(
                admission.InstallationStatus.PRESENT,
                "com.argusromtoolkit.argus",
                123,
                "b" * 64,
                "a" * 64,
            ),
            admission.InstallationObservation(
                admission.InstallationStatus.PRESENT,
                QUALIFICATION_PACKAGE,
                123,
                "0" * 64,
                "a" * 64,
            ),
            admission.InstallationObservation(
                admission.InstallationStatus.PRESENT,
                QUALIFICATION_PACKAGE,
                123,
                "b" * 64,
                "0" * 64,
            ),
        )
        for index, wrong_installation in enumerate(wrong_installations):
            with self.subTest(wrong_installation=wrong_installation):
                with mock.patch.object(
                    admission,
                    "_SESSION_REGISTRY_PATH",
                    self.directory / f"sessions-{index}.json",
                ):
                    _authorization, session, transport = self.admitted("absent")
                    transport.installed_package_override = wrong_installation
                    writer = RecordingWriter(self.evidence_store.execution_writer())

                    result = self.executor(session, transport, writer=writer).execute(now=NOW)

                    self.assertEqual(result.status, admission.AddScanExecutionStatus.BLOCKED)
                    self.assertEqual(transport.install_calls, 1)
                    self.assertEqual(transport.stage_calls, 0)
                    self.assertTrue(any(
                        item.actual_outcome is evidence.AssertionOutcome.BLOCKED
                        for item in writer.assertions
                    ))
                    self.assert_uncertain_evidence_is_durable(result, writer)
                    self.assertTrue(any("installation" in item.area for item in result.scope_extensions))

    def test_cleanup_uncertainty_is_not_retried_and_requests_owner_recovery(self):
        _authorization, session, transport = self.admitted("absent")
        transport.cleanup_uncertain = True

        result = self.executor(session, transport).execute(now=NOW)

        self.assertEqual(result.status, admission.AddScanExecutionStatus.BLOCKED)
        self.assertEqual(transport.cleanup_calls, 1)
        self.assertEqual(result.cleanup_status, "blocked")
        self.assertTrue(any("cleanup" in item.area for item in result.scope_extensions))

    def test_interrupt_after_add_and_scan_does_not_clean_possible_scan_input(self):
        _authorization, session, transport = self.admitted("absent")
        transport.interrupt_action = "add_and_scan"
        writer = self.evidence_store.execution_writer()

        result = self.executor(session, transport, writer=writer).execute(now=NOW)

        self.assertEqual(result.status, admission.AddScanExecutionStatus.BLOCKED)
        self.assertEqual(transport.nav_actions.count("add_and_scan"), 1)
        self.assertEqual(transport.cleanup_calls, 0)
        self.assertTrue(any("uncertain scan admission" in item.area for item in result.scope_extensions))
        self.assertEqual(writer.snapshot(evidence_session_id(session.authorization)).state, "finalized")

    def test_terminal_session_cannot_be_reexecuted(self):
        _authorization, session, transport = self.admitted("absent")
        executor = self.executor(session, transport)
        first = executor.execute(now=NOW)
        mutation_count = len(transport.mutations)

        second = executor.execute(now=NOW)

        self.assertEqual(first.status, admission.AddScanExecutionStatus.BLOCKED)
        self.assertEqual(second.status, admission.AddScanExecutionStatus.BLOCKED)
        self.assertEqual(len(transport.mutations), mutation_count)

    def test_cleanup_failure_is_recorded_after_one_attempt_and_blocks_session(self):
        _authorization, session, transport = self.admitted("absent")
        transport.cleanup_succeeds = False
        writer = self.evidence_store.execution_writer()

        result = self.executor(session, transport, writer=writer).execute(now=NOW)

        self.assertEqual(result.cleanup_status, "blocked")
        self.assertEqual(transport.cleanup_calls, 1)
        self.assertEqual(result.status, admission.AddScanExecutionStatus.BLOCKED)
        writer.verify_execution(evidence_session_id(session.authorization))

    def test_evidence_failure_before_mutation_stops_transport(self):
        _authorization, session, transport = self.admitted("absent")
        writer = FailingWriter(
            self.evidence_store.execution_writer(), fail_method="append_assertion"
        )

        result = self.executor(session, transport, writer=writer).execute(now=NOW)

        self.assertEqual(result.status, admission.AddScanExecutionStatus.BLOCKED)
        self.assertEqual(transport.mutations, [])


    def test_uncertain_add_and_scan_tap_is_not_retried_and_cleanup_waits_for_terminal_read(self):
        _authorization, session, transport = self.admitted("absent")
        transport.navigation_uncertain_action = "add_and_scan"

        result = self.executor(session, transport).execute(now=NOW)

        self.assertEqual(result.status, admission.AddScanExecutionStatus.BLOCKED)
        self.assertEqual(transport.nav_actions.count("add_and_scan"), 1)
        self.assertEqual(transport.cleanup_calls, 1)
        self.assertFalse(transport.staged)

    def test_resolved_uncertain_add_and_scan_tap_has_no_stale_recovery_blocker(self):
        _authorization, session, transport = self.admitted("absent")
        transport.navigation_uncertain_action = "add_and_scan"
        writer = RecordingWriter(self.evidence_store.execution_writer())

        result = self.executor(session, transport, writer=writer).execute(now=NOW)

        self.assertEqual(result.status, admission.AddScanExecutionStatus.BLOCKED)
        self.assertTrue(result.workflow_completed)
        self.assertEqual(result.cleanup_status, "verified")
        self.assertEqual(transport.nav_actions.count("add_and_scan"), 1)
        self.assertEqual(result.scope_extensions, ())
        self.assertNotIn("uncertain", result.blocker.lower())
        self.assertTrue(any(
            item.actual_outcome is evidence.AssertionOutcome.BLOCKED
            for item in writer.assertions
        ))

    def test_explicit_scan_admission_failure_is_recorded_and_owned_fixtures_are_cleaned(self):
        authorization, session, transport = self.admitted("absent")
        transport.scan_admission_succeeds = False
        writer = self.evidence_store.execution_writer()

        result = self.executor(session, transport, writer=writer).execute(now=NOW)

        self.assertEqual(result.status, admission.AddScanExecutionStatus.BLOCKED)
        self.assertEqual(result.scan_admission, "not_admitted")
        self.assertIsNone(result.job_status)
        self.assertEqual(transport.nav_actions.count("view_job"), 0)
        self.assertEqual(transport.cleanup_calls, 1)
        self.assertFalse(transport.staged)
        self.assertEqual(writer.snapshot(evidence_session_id(authorization)).state, "finalized")

    def test_ambiguous_scan_admission_blocks_and_withholds_fixture_cleanup(self):
        _authorization, session, transport = self.admitted("absent")
        transport.scan_admission_uncertain = True

        result = self.executor(session, transport).execute(now=NOW)

        self.assertEqual(result.status, admission.AddScanExecutionStatus.BLOCKED)
        self.assertIsNone(result.scan_admission)
        self.assertEqual(transport.cleanup_calls, 0)
        self.assertTrue(any("uncertain scan admission" in item.area for item in result.scope_extensions))

    def test_failed_terminal_result_stops_library_navigation_and_cleans_after_terminal(self):
        authorization, session, transport = self.admitted("absent")
        transport.job_status_label = "Failed"
        transport.scan_status_label = "Failed"
        writer = RecordingWriter(self.evidence_store.execution_writer())

        result = self.executor(session, transport, writer=writer).execute(now=NOW)

        self.assertEqual(result.status, admission.AddScanExecutionStatus.BLOCKED)
        self.assertEqual(result.job_status, "failed")
        self.assertEqual(result.terminal_scan_status, "failed")
        self.assertEqual(transport.nav_actions.count("library_navigation"), 0)
        self.assertEqual(transport.cleanup_calls, 1)
        self.assertFalse(transport.staged)
        self.assertEqual(writer.terminals[-1].outcome, evidence.TerminalOutcome.FAILED)
        self.assertTrue(any(
            item.actual_outcome is evidence.AssertionOutcome.FAILED
            for item in writer.assertions
        ))
        cleanup_lifecycles = [item.lifecycle for item in writer.lifecycles]
        self.assertIn(evidence.Lifecycle.CLEANUP_STARTED, cleanup_lifecycles)
        self.assertIn(evidence.Lifecycle.CLEANUP_COMPLETED, cleanup_lifecycles)
        primary_failure_event = next(
            index
            for index, (event_type, observation, _request) in enumerate(writer.events)
            if event_type == "assertion"
            and observation.actual_outcome is evidence.AssertionOutcome.FAILED
        )
        cleanup_start_event = next(
            index
            for index, (event_type, observation, _request) in enumerate(writer.events)
            if event_type == "lifecycle"
            and observation.lifecycle is evidence.Lifecycle.CLEANUP_STARTED
        )
        cleanup_result_ref = admission._add_scan_alias(
            "assertion", f"{evidence_session_id(authorization)}:cleanup-synthetic:result"
        )
        cleanup_result = next(
            observation
            for observation in writer.assertions
            if observation.assertion_ref == cleanup_result_ref
        )
        self.assertLess(primary_failure_event, cleanup_start_event)
        self.assertEqual(cleanup_result.actual_outcome, evidence.AssertionOutcome.PASSED)
        execution = writer.verify_execution(evidence_session_id(authorization))
        self.assertEqual(writer.snapshot(execution.session_id).state, "finalized")
        self.assert_no_owner_verdict_and_sanitized_output(authorization, result)

    def test_primary_product_failure_and_cleanup_receipt_failure_keep_failed_terminal(self):
        receipt_changes = []
        for field, expected in (("removed_file_count", 1), ("remaining_file_count", 0)):
            receipt_changes.extend(
                (field, value, case)
                for case, value in (
                    ("bool_true", True),
                    ("bool_false", False),
                    ("float", float(expected)),
                    ("string", str(expected)),
                    ("non_integer_equal", NonIntegerCountImpostor(expected)),
                )
            )

        for index, (field, wrong_value, case) in enumerate(receipt_changes):
            with self.subTest(field=field, case=case):
                authorization, session, transport = self.admitted(
                    "absent",
                    authorization_id=f"issue26-cleanup-receipt-type-{index}",
                )
                transport.job_status_label = "Failed"
                transport.scan_status_label = "Failed"
                plan = self.fixture_plan(authorization)
                valid_receipt = admission.FixtureCleanupReceipt(
                    session_id=evidence_session_id(authorization),
                    fixture_manifest_sha256=plan.fixture_manifest_sha256,
                    removed_file_count=plan.file_count,
                    remaining_file_count=0,
                )
                transport.cleanup_receipt_override = replace(
                    valid_receipt,
                    **{field: wrong_value},
                )
                writer = RecordingWriter(self.evidence_store.execution_writer())

                result = self.executor(session, transport, writer=writer).execute(now=NOW)

                self.assertEqual(result.status, admission.AddScanExecutionStatus.BLOCKED)
                self.assertEqual(result.job_status, "failed")
                self.assertEqual(result.terminal_scan_status, "failed")
                self.assertEqual(result.cleanup_status, "blocked")
                self.assertEqual(transport.cleanup_calls, 1)
                self.assertEqual(transport.mutations.count("cleanup_fixtures"), 1)
                self.assertFalse(any(
                    item.lifecycle is evidence.Lifecycle.CLEANUP_COMPLETED
                    for item in writer.lifecycles
                ))
                cleanup_result_ref = admission._add_scan_alias(
                    "assertion", f"{evidence_session_id(authorization)}:cleanup-synthetic:result"
                )
                cleanup_result = next(
                    observation
                    for observation in writer.assertions
                    if observation.assertion_ref == cleanup_result_ref
                )
                self.assertEqual(cleanup_result.actual_outcome, evidence.AssertionOutcome.FAILED)
                self.assertEqual(writer.terminals[-1].outcome, evidence.TerminalOutcome.FAILED)
                execution = writer.verify_execution(evidence_session_id(authorization))
                self.assertEqual(writer.snapshot(execution.session_id).state, "finalized")
                self.assert_no_owner_verdict_and_sanitized_output(authorization, result)

    def test_prerequisite_block_and_uncertain_cleanup_are_recorded_separately(self):
        authorization, session, transport = self.admitted("absent")
        transport.ambiguous_navigation_action = "open_fixture_root"
        transport.cleanup_uncertain = True
        writer = RecordingWriter(self.evidence_store.execution_writer())

        result = self.executor(session, transport, writer=writer).execute(now=NOW)

        self.assertEqual(result.status, admission.AddScanExecutionStatus.BLOCKED)
        self.assertEqual(result.cleanup_status, "blocked")
        self.assertEqual(transport.cleanup_calls, 1)
        self.assertEqual(transport.nav_actions.count("add_and_scan"), 0)
        self.assertTrue(any(
            item.actual_outcome is evidence.AssertionOutcome.BLOCKED
            for item in writer.assertions
        ))
        cleanup_recovery_ref = admission._add_scan_alias(
            "assertion", f"{evidence_session_id(authorization)}:cleanup-recovery:blocked"
        )
        cleanup_recovery = next(
            item
            for item in writer.assertions
            if item.assertion_ref == cleanup_recovery_ref
        )
        self.assertEqual(cleanup_recovery.actual_outcome, evidence.AssertionOutcome.BLOCKED)
        self.assertEqual(writer.terminals[-1].outcome, evidence.TerminalOutcome.BLOCKED)
        self.assertFalse(any(
            item.lifecycle is evidence.Lifecycle.CLEANUP_COMPLETED
            for item in writer.lifecycles
        ))
        execution = writer.verify_execution(evidence_session_id(authorization))
        self.assertEqual(writer.snapshot(execution.session_id).state, "finalized")
        self.assert_no_owner_verdict_and_sanitized_output(authorization, result)

    def test_cleanup_result_append_failure_records_blocked_recovery_without_retry(self):
        authorization, session, transport = self.admitted("absent")
        transport.job_status_label = "Failed"
        transport.scan_status_label = "Failed"
        recording_writer = RecordingWriter(self.evidence_store.execution_writer())
        failed_result_ref = admission._add_scan_alias(
            "assertion", f"{evidence_session_id(authorization)}:cleanup-synthetic:result"
        )
        writer = FailingAssertionRefWriter(
            recording_writer,
            assertion_ref=failed_result_ref,
        )

        result = self.executor(session, transport, writer=writer).execute(now=NOW)

        self.assertTrue(writer.failed)
        self.assertEqual(result.status, admission.AddScanExecutionStatus.BLOCKED)
        self.assertEqual(result.cleanup_status, "blocked")
        self.assertEqual(transport.cleanup_calls, 1)
        self.assertEqual(transport.mutations.count("cleanup_fixtures"), 1)
        self.assertFalse(transport.staged)
        self.assertTrue(any(
            item.actual_outcome is evidence.AssertionOutcome.FAILED
            for item in recording_writer.assertions
        ))
        cleanup_recovery_ref = admission._add_scan_alias(
            "assertion", f"{evidence_session_id(authorization)}:cleanup-recovery:blocked"
        )
        cleanup_recovery = next(
            item
            for item in recording_writer.assertions
            if item.assertion_ref == cleanup_recovery_ref
        )
        self.assertEqual(cleanup_recovery.actual_outcome, evidence.AssertionOutcome.BLOCKED)
        self.assertEqual(recording_writer.terminals[-1].outcome, evidence.TerminalOutcome.FAILED)
        execution = recording_writer.verify_execution(evidence_session_id(authorization))
        self.assertEqual(recording_writer.snapshot(execution.session_id).state, "finalized")
        self.assert_no_owner_verdict_and_sanitized_output(authorization, result)

    def test_terminal_ack_failure_keeps_primary_failure_and_durable_append_verifies(self):
        authorization, session, transport = self.admitted("absent")
        transport.job_status_label = "Failed"
        transport.scan_status_label = "Failed"
        recording_writer = RecordingWriter(self.evidence_store.execution_writer())
        writer = AppendThenRaiseTerminalWriter(recording_writer)

        result = self.executor(session, transport, writer=writer).execute(now=NOW)

        self.assertEqual(result.status, admission.AddScanExecutionStatus.BLOCKED)
        self.assertIn("Add & Scan observation", result.blocker)
        self.assertIsNone(result.execution_manifest_sha256)
        self.assertEqual(writer.calls, 1)
        self.assertEqual(len(recording_writer.terminals), 1)
        self.assertEqual(recording_writer.terminals[-1].outcome, evidence.TerminalOutcome.FAILED)
        execution = recording_writer.verify_execution(evidence_session_id(authorization))
        self.assertEqual(recording_writer.snapshot(execution.session_id).state, "finalized")
        self.assert_no_owner_verdict_and_sanitized_output(
            authorization,
            result,
            execution_manifest_sha256=execution.manifest_sha256,
        )

    def test_cleanup_uncertainty_after_durable_product_failure_preserves_failure_order(self):
        authorization, session, transport = self.admitted("absent")
        transport.job_status_label = "Failed"
        transport.scan_status_label = "Failed"
        transport.cleanup_uncertain = True
        writer = RecordingWriter(self.evidence_store.execution_writer())

        result = self.executor(session, transport, writer=writer).execute(now=NOW)

        self.assertEqual(result.status, admission.AddScanExecutionStatus.BLOCKED)
        self.assertEqual(result.cleanup_status, "blocked")
        self.assertEqual(transport.cleanup_calls, 1)
        self.assertEqual(transport.mutations.count("cleanup_fixtures"), 1)
        product_failure_event = next(
            index
            for index, (event_type, observation, _request) in enumerate(writer.events)
            if event_type == "assertion"
            and observation.actual_outcome is evidence.AssertionOutcome.FAILED
        )
        cleanup_intent_ref = admission._add_scan_alias(
            "assertion", f"{evidence_session_id(authorization)}:cleanup-synthetic:intent"
        )
        cleanup_intent_event = next(
            index
            for index, (event_type, observation, _request) in enumerate(writer.events)
            if event_type == "assertion"
            and observation.assertion_ref == cleanup_intent_ref
        )
        self.assertLess(product_failure_event, cleanup_intent_event)
        cleanup_recovery_ref = admission._add_scan_alias(
            "assertion", f"{evidence_session_id(authorization)}:cleanup-recovery:blocked"
        )
        cleanup_recovery = next(
            item
            for item in writer.assertions
            if item.assertion_ref == cleanup_recovery_ref
        )
        self.assertEqual(cleanup_recovery.actual_outcome, evidence.AssertionOutcome.BLOCKED)
        self.assertEqual(writer.terminals[-1].outcome, evidence.TerminalOutcome.FAILED)
        execution = writer.verify_execution(evidence_session_id(authorization))
        self.assertEqual(writer.snapshot(execution.session_id).state, "finalized")
        self.assert_no_owner_verdict_and_sanitized_output(authorization, result)

    def test_cleanup_interrupt_after_product_failure_keeps_failed_terminal_and_recovery(self):
        authorization, session, transport = self.admitted("absent")
        transport.job_status_label = "Failed"
        transport.scan_status_label = "Failed"
        transport.cleanup_interrupted = True
        writer = RecordingWriter(self.evidence_store.execution_writer())

        result = self.executor(session, transport, writer=writer).execute(now=NOW)

        self.assertEqual(result.status, admission.AddScanExecutionStatus.BLOCKED)
        self.assertEqual(result.cleanup_status, "blocked")
        self.assertEqual(transport.cleanup_calls, 1)
        self.assertEqual(transport.mutations.count("cleanup_fixtures"), 1)
        self.assertTrue(any(
            item.actual_outcome is evidence.AssertionOutcome.FAILED
            for item in writer.assertions
        ))
        cleanup_recovery_ref = admission._add_scan_alias(
            "assertion", f"{evidence_session_id(authorization)}:cleanup-recovery:blocked"
        )
        cleanup_recovery = next(
            item
            for item in writer.assertions
            if item.assertion_ref == cleanup_recovery_ref
        )
        self.assertEqual(cleanup_recovery.actual_outcome, evidence.AssertionOutcome.BLOCKED)
        self.assertEqual(writer.terminals[-1].outcome, evidence.TerminalOutcome.FAILED)
        execution = writer.verify_execution(evidence_session_id(authorization))
        self.assertEqual(writer.snapshot(execution.session_id).state, "finalized")
        self.assert_no_owner_verdict_and_sanitized_output(authorization, result)

    def test_cleanup_interrupted_error_after_product_failure_preserves_both_classifications(self):
        authorization, session, transport = self.admitted("absent")
        transport.job_status_label = "Failed"
        transport.scan_status_label = "Failed"
        transport.cleanup_interrupted_error = True
        writer = RecordingWriter(self.evidence_store.execution_writer())

        result = self.executor(session, transport, writer=writer).execute(now=NOW)

        self.assertEqual(result.status, admission.AddScanExecutionStatus.BLOCKED)
        self.assertEqual(result.cleanup_status, "blocked")
        self.assertEqual(transport.cleanup_calls, 1)
        self.assertEqual(transport.mutations.count("cleanup_fixtures"), 1)
        self.assertTrue(any(
            item.actual_outcome is evidence.AssertionOutcome.FAILED
            for item in writer.assertions
        ))
        self.assertTrue(any(
            extension.area == "interrupted fixture cleanup"
            for extension in result.scope_extensions
        ))
        cleanup_recovery_ref = admission._add_scan_alias(
            "assertion", f"{evidence_session_id(authorization)}:cleanup-recovery:blocked"
        )
        cleanup_recovery = next(
            item
            for item in writer.assertions
            if item.assertion_ref == cleanup_recovery_ref
        )
        self.assertEqual(cleanup_recovery.actual_outcome, evidence.AssertionOutcome.BLOCKED)
        self.assertEqual(writer.terminals[-1].outcome, evidence.TerminalOutcome.FAILED)
        execution = writer.verify_execution(evidence_session_id(authorization))
        self.assertEqual(writer.snapshot(execution.session_id).state, "finalized")
        self.assertNotIn("synthetic interrupted cleanup response", repr(result))
        self.assert_no_owner_verdict_and_sanitized_output(authorization, result)

    def test_active_parent_and_child_job_state_is_blocked_without_cleanup(self):
        authorization, session, transport = self.admitted("absent")
        transport.job_status_frames = [
            ("Library Scan", "Job status: Running", "Scanning"),
        ]
        transport.job_status_repeat_last_frame = True
        clock = [0.0]
        waits: list[float] = []

        def sleep(seconds):
            waits.append(seconds)
            clock[0] += seconds

        job_timeout = next(
            operation.timeout_seconds
            for operation in authorization.operations
            if operation.category is admission.OperationCategory.READ_ONLY
            and dict(operation.arguments).get("observation") == "job_status"
        )
        transport.job_status_capture_clock = lambda: clock[0]
        writer = RecordingWriter(self.evidence_store.execution_writer())

        result = self.executor(
            session,
            transport,
            writer=writer,
            monotonic=lambda: clock[0],
            sleeper=sleep,
        ).execute(now=NOW)

        self.assertEqual(result.status, admission.AddScanExecutionStatus.BLOCKED)
        self.assertEqual(result.job_status, "running")
        self.assertIsNone(result.terminal_scan_status)
        self.assertEqual(transport.cleanup_calls, 0)
        self.assertEqual(result.cleanup_status, "blocked")
        self.assertEqual(transport.job_status_capture_count, len(waits))
        self.assertEqual(clock[0], job_timeout)
        self.assertTrue(all(value < job_timeout for value in transport.job_status_capture_times))
        self.assertTrue(any(
            item.actual_outcome is evidence.AssertionOutcome.BLOCKED
            for item in writer.assertions
        ))
        self.assertEqual(writer.terminals[-1].outcome, evidence.TerminalOutcome.BLOCKED)
        self.assertFalse(any(
            item.actual_outcome is evidence.AssertionOutcome.FAILED
            for item in writer.assertions
        ))

    def test_job_status_polls_async_loading_then_active_and_terminal_snapshots(self):
        _authorization, session, transport = self.admitted("absent")
        transport.job_status_frames = [
            ("Loading job details",),
            ("Library Scan", "Job status: Running", "Scanning"),
            ("Library Scan", "Job status: Completed", "Complete"),
        ]
        transport.job_status_repeat_last_frame = False
        clock = [0.0]
        waits: list[float] = []

        def sleep(seconds):
            self.assertGreater(seconds, 0)
            waits.append(seconds)
            clock[0] += seconds

        transport.job_status_capture_clock = lambda: clock[0]
        with mock.patch.object(
            ui,
            "observe_scan_job_detail",
            wraps=ui.observe_scan_job_detail,
        ) as observe_job:
            result = self.executor(
                session,
                transport,
                monotonic=lambda: clock[0],
                sleeper=sleep,
            ).execute(now=NOW)

        self.assertTrue(result.workflow_completed)
        self.assertEqual(result.job_status, "completed")
        self.assertEqual(result.terminal_scan_status, "complete")
        self.assertEqual(transport.job_status_capture_count, 3)
        self.assertEqual(waits, [0.25, 0.25])
        self.assertEqual(observe_job.call_count, 3)
        self.assertEqual(transport.nav_actions.count("add_and_scan"), 1)
        self.assertEqual(transport.nav_actions.count("view_job"), 1)
        self.assertLess(
            transport.nav_actions.index("add_and_scan"),
            transport.nav_actions.index("view_job"),
        )
        self.assertLess(
            transport.nav_actions.index("view_job"),
            transport.nav_actions.index("library_navigation"),
        )
        self.assertEqual(result.cleanup_status, "verified")

    def test_conflicting_parent_child_snapshot_blocks_without_poll_or_cleanup(self):
        _authorization, session, transport = self.admitted("absent")
        transport.job_status_frames = [
            ("Library Scan", "Job status: Completed", "Scanning"),
        ]
        transport.job_status_repeat_last_frame = False

        result = self.executor(
            session,
            transport,
        ).execute(now=NOW)

        self.assertEqual(transport.job_status_capture_count, 1)
        self.assertEqual(result.status, admission.AddScanExecutionStatus.BLOCKED)
        self.assertEqual(result.terminal_scan_status, None)
        self.assertEqual(result.cleanup_status, "blocked")
        self.assertEqual(transport.cleanup_calls, 0)

    def test_unknown_job_detail_is_ambiguous_and_not_polled(self):
        _authorization, session, transport = self.admitted("absent")
        transport.job_status_frames = [("Library Scan",)]
        transport.job_status_repeat_last_frame = True
        writer = RecordingWriter(self.evidence_store.execution_writer())

        result = self.executor(
            session,
            transport,
            writer=writer,
        ).execute(now=NOW)

        self.assertEqual(transport.job_status_capture_count, 1)
        self.assertEqual(result.status, admission.AddScanExecutionStatus.BLOCKED)
        self.assertEqual(writer.terminals[-1].outcome, evidence.TerminalOutcome.BLOCKED)
        self.assertEqual(transport.cleanup_calls, 0)

    def test_job_poll_rejects_a_different_route_without_retry_or_cleanup(self):
        _authorization, session, transport = self.admitted("absent")
        transport.job_status_frames = [("Library", "Search Library")]
        transport.job_status_repeat_last_frame = True

        result = self.executor(
            session,
            transport,
        ).execute(now=NOW)

        self.assertEqual(transport.job_status_capture_count, 1)
        self.assertEqual(transport.nav_actions.count("add_and_scan"), 1)
        self.assertEqual(transport.nav_actions.count("view_job"), 1)
        self.assertEqual(result.status, admission.AddScanExecutionStatus.BLOCKED)
        self.assertEqual(result.terminal_scan_status, None)
        self.assertEqual(result.cleanup_status, "blocked")
        self.assertEqual(transport.cleanup_calls, 0)

    def test_product_failure_in_job_snapshot_stops_immediately_as_failed(self):
        _authorization, session, transport = self.admitted("absent")
        transport.job_status_frames = [("Retry Library setup",)]
        transport.job_status_repeat_last_frame = True
        writer = RecordingWriter(self.evidence_store.execution_writer())

        result = self.executor(
            session,
            transport,
            writer=writer,
        ).execute(now=NOW)

        self.assertEqual(transport.job_status_capture_count, 1)
        self.assertEqual(result.status, admission.AddScanExecutionStatus.BLOCKED)
        self.assertEqual(writer.terminals[-1].outcome, evidence.TerminalOutcome.FAILED)
        self.assertTrue(any(
            item.actual_outcome is evidence.AssertionOutcome.FAILED
            for item in writer.assertions
        ))
        self.assertEqual(transport.cleanup_calls, 0)

    def test_unresolved_job_loading_stops_at_operation_deadline_without_late_capture(self):
        authorization, session, transport = self.admitted("absent")
        transport.job_status_frames = [("Loading job details",)]
        transport.job_status_repeat_last_frame = True
        clock = [0.0]
        waits: list[float] = []

        def sleep(seconds):
            self.assertGreater(seconds, 0)
            waits.append(seconds)
            clock[0] += seconds

        transport.job_status_capture_clock = lambda: clock[0]
        job_timeout = next(
            operation.timeout_seconds
            for operation in authorization.operations
            if operation.category is admission.OperationCategory.READ_ONLY
            and dict(operation.arguments).get("observation") == "job_status"
        )
        result = self.executor(
            session,
            transport,
            monotonic=lambda: clock[0],
            sleeper=sleep,
        ).execute(now=NOW)

        self.assertEqual(result.status, admission.AddScanExecutionStatus.BLOCKED)
        self.assertEqual(result.terminal_scan_status, None)
        self.assertLessEqual(clock[0], job_timeout)
        self.assertEqual(clock[0], sum(waits))
        self.assertTrue(all(value < job_timeout for value in transport.job_status_capture_times))
        self.assertEqual(transport.job_status_capture_count, len(waits))
        self.assertEqual(transport.cleanup_calls, 0)

    def test_interrupted_job_poll_is_not_replayed_and_does_not_clean_unresolved_fixtures(self):
        _authorization, session, transport = self.admitted("absent")
        transport.job_status_frames = [("Library Scan", "Job status: Running", "Scanning")]
        transport.job_status_repeat_last_frame = True
        transport.job_status_interrupt_at = 2
        clock = [0.0]
        waits: list[float] = []
        writer = RecordingWriter(self.evidence_store.execution_writer())

        result = self.executor(
            session,
            transport,
            writer=writer,
            monotonic=lambda: clock[0],
            sleeper=lambda seconds: (waits.append(seconds), clock.__setitem__(0, clock[0] + seconds)),
        ).execute(now=NOW)

        self.assertEqual(result.status, admission.AddScanExecutionStatus.BLOCKED)
        self.assertEqual(writer.terminals[-1].outcome, evidence.TerminalOutcome.INTERRUPTED)
        self.assertEqual(transport.job_status_capture_count, 2)
        self.assertEqual(transport.nav_actions.count("add_and_scan"), 1)
        self.assertEqual(transport.nav_actions.count("view_job"), 1)
        self.assertEqual(transport.cleanup_calls, 0)
        self.assertEqual(result.cleanup_status, "blocked")
        self.assert_no_owner_verdict_and_sanitized_output(
            session.authorization,
            result,
        )

    def test_missing_fixture_specific_result_is_failed_but_owned_cleanup_completes(self):
        _authorization, session, transport = self.admitted("absent")
        transport.fixture_library_label = "Different Game, NES"

        result = self.executor(session, transport).execute(now=NOW)

        self.assertEqual(result.status, admission.AddScanExecutionStatus.BLOCKED)
        self.assertEqual(result.terminal_scan_status, "complete")
        self.assertEqual(result.fixture_result_indices, ())
        self.assertEqual(result.cleanup_status, "verified")

    def test_individual_fixture_library_receipt_mismatch_is_failed_and_cleanup_remains_exact(self):
        authorization, session, transport = self.admitted("absent")
        writer = RecordingWriter(self.evidence_store.execution_writer())
        expected = (
            ui.LibraryExpectation("fixture-metroid", "Metroid", "NES"),
            ui.LibraryExpectation("fixture-zelda", "Zelda", "SNES"),
        )

        result = self.executor(
            session,
            transport,
            writer=writer,
            library_expectations=expected,
        ).execute(now=NOW)

        self.assertEqual(result.status, admission.AddScanExecutionStatus.BLOCKED)
        self.assertEqual(result.fixture_result_indices, (0,))
        self.assertEqual(result.cleanup_status, "verified")
        self.assertEqual(transport.cleanup_calls, 1)
        self.assertFalse(transport.staged)
        expected_fixture_result_refs = {
            admission._add_scan_alias(
                "assertion", f"{evidence_session_id(authorization)}:fixture-result-{index:03d}"
            )
            for index in range(2)
        }
        fixture_results = [
            item for item in writer.assertions
            if item.assertion_ref in expected_fixture_result_refs
        ]
        self.assertEqual(len(fixture_results), 2)
        self.assertEqual(
            [item.actual_outcome for item in fixture_results],
            [evidence.AssertionOutcome.PASSED, evidence.AssertionOutcome.FAILED],
        )
        self.assertEqual(writer.terminals[-1].outcome, evidence.TerminalOutcome.FAILED)
        execution = writer.verify_execution(evidence_session_id(authorization))
        self.assertEqual(writer.snapshot(execution.session_id).state, "finalized")
        self.assert_no_owner_verdict_and_sanitized_output(authorization, result)

    def test_wrong_foreground_drift_blocks_before_reset_or_install(self):
        _authorization, session, transport = self.admitted("absent")
        transport.foreground_drift = True

        result = self.executor(session, transport).execute(now=NOW)

        self.assertEqual(result.status, admission.AddScanExecutionStatus.BLOCKED)
        self.assertEqual(transport.mutations, [])


if __name__ == "__main__":
    unittest.main()
