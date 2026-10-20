"""Test schema-v1 host manifests and private session authorization contracts."""

from __future__ import annotations

import json
import os
import stat
from datetime import datetime, timezone
from typing import Any
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

from scripts.android_qualification import manifest



class ManifestTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.directory = Path(self.temporary_directory.name)

    def _fresh_document(self) -> dict[str, object]:
        return {
            "schema_version": 1,
            "authorization_ref": "authorization-synthetic",
            "target_ref": "target-synthetic",
            "artifact_ref": "artifact-synthetic",
            "plan_ref": "plan-synthetic",
            "scope_ref": "scope-synthetic",
            "state_mode": "fresh",
            "inherited_state_session_ref": None,
        }

    def _write_json(self, document: object, name: str = "manifest.json") -> Path:
        path = self.directory / name
        path.write_text(json.dumps(document), encoding="utf-8")
        return path

    def _load(self, document: object, mode: manifest.StateMode = manifest.StateMode.FRESH) -> manifest.QualificationManifest:
        return manifest.load_manifest(self._write_json(document), mode)

    def _assert_code(self, expected: str, action) -> None:
        with self.assertRaises(manifest.ManifestError) as caught:
            action()
        self.assertEqual(caught.exception.code.value, expected)

    def test_valid_fresh_manifest(self) -> None:
        parsed = self._load(self._fresh_document())
        self.assertEqual(parsed.schema_version, 1)
        self.assertEqual(parsed.state_mode, manifest.StateMode.FRESH)
        self.assertIsNone(parsed.inherited_state_session_ref)
        self.assertEqual(parsed.scope_ref, "scope-synthetic")

    def test_valid_no_reset_manifest(self) -> None:
        document = self._fresh_document()
        document["state_mode"] = "no-reset"
        document["inherited_state_session_ref"] = "prior-session-synthetic"
        parsed = self._load(document, manifest.StateMode.NO_RESET)
        self.assertEqual(parsed.state_mode, manifest.StateMode.NO_RESET)
        self.assertEqual(parsed.inherited_state_session_ref, "prior-session-synthetic")

    def test_missing_field_is_rejected(self) -> None:
        for field in manifest.REQUIRED_FIELDS:
            with self.subTest(field=field):
                document = self._fresh_document()
                del document[field]
                self._assert_code(
                    "MANIFEST_MISSING_FIELD",
                    lambda: self._load(document),
                )

    def test_unknown_field_is_rejected(self) -> None:
        document = self._fresh_document()
        document["owner_approval"] = True
        self._assert_code(
            "MANIFEST_UNKNOWN_FIELD",
            lambda: self._load(document),
        )

    def test_unsupported_or_invalid_version_is_rejected(self) -> None:
        for version in (2, 0, "1", True):
            with self.subTest(version=version):
                document = self._fresh_document()
                document["schema_version"] = version
                self._assert_code(
                    "MANIFEST_SCHEMA_VERSION_UNSUPPORTED",
                    lambda: self._load(document),
                )

    def test_malformed_json_is_rejected(self) -> None:
        path = self.directory / "manifest.json"
        path.write_text("{not-json", encoding="utf-8")
        self._assert_code(
            "MANIFEST_JSON_INVALID",
            lambda: manifest.load_manifest(path, manifest.StateMode.FRESH),
        )

    def test_non_finite_json_constants_are_rejected(self) -> None:
        path = self.directory / "manifest.json"
        path.write_text('{"schema_version": NaN}', encoding="utf-8")
        self._assert_code(
            "MANIFEST_JSON_INVALID",
            lambda: manifest.load_manifest(path, manifest.StateMode.FRESH),
        )

    def test_duplicate_json_key_is_rejected(self) -> None:
        path = self.directory / "manifest.json"
        path.write_text(
            '{"schema_version":1,"authorization_ref":"a","authorization_ref":"b"}',
            encoding="utf-8",
        )
        self._assert_code(
            "MANIFEST_DUPLICATE_KEY",
            lambda: manifest.load_manifest(path, manifest.StateMode.FRESH),
        )

    def test_non_object_root_is_rejected(self) -> None:
        self._assert_code(
            "MANIFEST_ROOT_INVALID",
            lambda: self._load([]),
        )

    def test_invalid_utf8_is_rejected(self) -> None:
        path = self.directory / "manifest.json"
        path.write_bytes(b"\xff\xfe")
        self._assert_code(
            "MANIFEST_ENCODING_INVALID",
            lambda: manifest.load_manifest(path, manifest.StateMode.FRESH),
        )

    def test_unavailable_and_non_regular_files_are_rejected(self) -> None:
        missing = self.directory / "missing-private-device-serial.json"
        self._assert_code(
            "MANIFEST_UNAVAILABLE",
            lambda: manifest.load_manifest(missing, manifest.StateMode.FRESH),
        )
        self._assert_code(
            "MANIFEST_NOT_REGULAR_FILE",
            lambda: manifest.load_manifest(self.directory, manifest.StateMode.FRESH),
        )

    def test_manifest_size_is_bounded(self) -> None:
        path = self.directory / "manifest.json"
        path.write_bytes(b" " * (manifest.MAX_MANIFEST_BYTES + 1))
        self._assert_code(
            "MANIFEST_TOO_LARGE",
            lambda: manifest.load_manifest(path, manifest.StateMode.FRESH),
        )

    def test_references_are_bounded_opaque_strings(self) -> None:
        invalid_values = (
            "",
            " leading",
            "trailing ",
            "control\x01value",
            "x" * (manifest.MAX_REFERENCE_CHARS + 1),
            1,
            None,
        )
        for value in invalid_values:
            with self.subTest(value=value):
                document = self._fresh_document()
                document["artifact_ref"] = value
                self._assert_code(
                    "MANIFEST_INVALID_REFERENCE",
                    lambda: self._load(document),
                )

    def test_entrypoint_state_mode_mismatch_is_rejected(self) -> None:
        document = self._fresh_document()
        document["state_mode"] = "no-reset"
        document["inherited_state_session_ref"] = "prior-session-synthetic"
        self._assert_code(
            "MANIFEST_STATE_MODE_MISMATCH",
            lambda: self._load(document, manifest.StateMode.FRESH),
        )

    def test_no_reset_requires_inherited_session_reference(self) -> None:
        document = self._fresh_document()
        document["state_mode"] = "no-reset"
        self._assert_code(
            "MANIFEST_INHERITED_STATE_REQUIRED",
            lambda: self._load(document, manifest.StateMode.NO_RESET),
        )

    def test_fresh_rejects_inherited_session_reference(self) -> None:
        document = self._fresh_document()
        document["inherited_state_session_ref"] = "prior-session-synthetic"
        self._assert_code(
            "MANIFEST_INHERITED_STATE_UNEXPECTED",
            lambda: self._load(document),
        )

    def test_invalid_state_mode_is_rejected(self) -> None:
        document = self._fresh_document()
        document["state_mode"] = "preserve"
        self._assert_code(
            "MANIFEST_INVALID_STATE_MODE",
            lambda: self._load(document),
        )

    def test_non_string_state_mode_and_inherited_reference_are_rejected(self) -> None:
        document = self._fresh_document()
        document["state_mode"] = 1
        self._assert_code(
            "MANIFEST_INVALID_STATE_MODE",
            lambda: self._load(document),
        )

        document = self._fresh_document()
        document["state_mode"] = "no-reset"
        document["inherited_state_session_ref"] = 1
        self._assert_code(
            "MANIFEST_INVALID_REFERENCE",
            lambda: self._load(document, manifest.StateMode.NO_RESET),
        )

    def test_expected_state_mode_type_is_enforced(self) -> None:
        path = self._write_json(self._fresh_document())
        with self.assertRaises(TypeError):
            manifest.load_manifest(path, "fresh")  # type: ignore[arg-type]

    def test_open_failure_does_not_disclose_the_path(self) -> None:
        secret = "PRIVATE_ROM_NAME_AND_SERIAL"
        path = self._write_json(self._fresh_document(), f"{secret}.json")
        with mock.patch.object(Path, "open", side_effect=PermissionError(secret)):
            with self.assertRaises(manifest.ManifestError) as caught:
                manifest.load_manifest(path, manifest.StateMode.FRESH)
        rendered = f"{caught.exception!s} {caught.exception!r}"
        self.assertEqual(caught.exception.code.value, "MANIFEST_UNAVAILABLE")
        self.assertNotIn(secret, rendered)
        self.assertNotIn(str(path), rendered)

    def test_file_growth_after_stat_is_bounded(self) -> None:
        path = self.directory / "manifest.json"
        path.write_bytes(b" " * (manifest.MAX_MANIFEST_BYTES + 1))
        initial_status = SimpleNamespace(st_mode=stat.S_IFREG | 0o600, st_size=1)
        with mock.patch.object(Path, "stat", return_value=initial_status):
            self._assert_code(
                "MANIFEST_TOO_LARGE",
                lambda: manifest.load_manifest(path, manifest.StateMode.FRESH),
            )

    def test_errors_do_not_disclose_paths_or_values(self) -> None:
        secret = "PRIVATE_ROM_NAME_AND_SERIAL"
        path = self.directory / f"{secret}.json"
        path.write_text(
            json.dumps({**self._fresh_document(), "artifact_ref": secret + "\x01"}),
            encoding="utf-8",
        )
        with self.assertRaises(manifest.ManifestError) as caught:
            manifest.load_manifest(path, manifest.StateMode.FRESH)
        rendered = f"{caught.exception!s} {caught.exception!r}"
        self.assertNotIn(secret, rendered)


# Synthetic owner-private inputs shared by manifest and admission tests.
QUALIFICATION_PACKAGE = "com.argusromtoolkit.argus.qualification"
MANAGE_EXTERNAL_STORAGE = "android.permission.MANAGE_EXTERNAL_STORAGE"
NOW = datetime(2030, 1, 1, 0, 1, tzinfo=timezone.utc)


def authorization_document() -> dict[str, Any]:
    """Return a complete synthetic authorization for host-only tests."""
    return {
        "schema_version": 1,
        "authorization_id": "session-synthetic-1",
        "owner_identity": "owner-synthetic",
        "issued_at_utc": "2030-01-01T00:00:00Z",
        "session_deadline_utc": "2030-01-01T00:05:00Z",
        "cleanup_deadline_utc": "2030-01-01T00:10:00Z",
        "target": {
            "device_serial": "private-serial-synthetic",
            "device_alias": "synthetic-test-device",
            "target_ref": "target-ref-synthetic",
            "minimum_android_api": 30,
            "required_abi": "arm64-v8a",
            "required_capabilities": [
                "foreground_package_observation",
                "installed_signer_observation",
                "permission_app_op_observation",
                "permission_app_op_mutation",
                "storage_reserve_observation",
            ],
        },
        "application": {"package_name": QUALIFICATION_PACKAGE},
        "artifact": {
            "apk_sha256": "a" * 64,
            "certificate_sha256": "b" * 64,
            "source_revision": "c" * 40,
            "version_code": 123,
            "declared_permissions": [MANAGE_EXTERNAL_STORAGE],
        },
        "plan": {
            "plan_sha256": "d" * 64,
            "rules_sha256": "e" * 64,
            "scenario_ids": ["scenario-synthetic"],
        },
        "fixture_manifest_sha256": "f" * 64,
        "state": {
            "mode": "fresh",
            "inherited_state_session_id": None,
            "no_reset_baseline": None,
        },
        "operations": [
            {
                "operation_id": "permission-loss-synthetic",
                "category": "permission_app_op",
                "phase": "qualification",
                "target_serial": "private-serial-synthetic",
                "package_name": QUALIFICATION_PACKAGE,
                "timeout_seconds": 30,
                "permission_name": MANAGE_EXTERNAL_STORAGE,
                "expected_prior_state": "allowed",
                "desired_state": "denied",
                "restoration": {
                    "operation_id": "permission-restore-synthetic",
                    "category": "permission_app_op_restore",
                    "phase": "cleanup",
                    "target_serial": "private-serial-synthetic",
                    "package_name": QUALIFICATION_PACKAGE,
                    "permission_name": MANAGE_EXTERNAL_STORAGE,
                    "deadline_utc": "2030-01-01T00:09:00Z",
                    "timeout_seconds": 20,
                },
            }
        ],
        "approved_remediation": ["restore_permission_snapshot"],
        "reserves": {"storage_bytes": 1_073_741_824, "cleanup_seconds": 60},
    }


def write_private_json(directory: Path, name: str, document: object) -> Path:
    """Write a synthetic mode-0600 JSON input for a parser test."""
    path = directory / name
    path.write_text(json.dumps(document), encoding="utf-8")
    os.chmod(path, 0o600)
    return path


def approval_document(digest: str) -> dict[str, Any]:
    """Return a synthetic approval sidecar for parser tests."""
    return {
        "schema_version": 1,
        "authorization_sha256": digest,
        "owner_identity": "owner-synthetic",
        "valid_from_utc": "2030-01-01T00:00:30Z",
        "valid_until_utc": "2030-01-01T00:04:00Z",
    }

class SessionAuthorizationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.directory = Path(self.temporary_directory.name)

    def _load_authorization(self, document: object | None = None) -> manifest.SessionAuthorization:
        return manifest.load_authorization(
            write_private_json(
                self.directory,
                "manifest.json",
                authorization_document() if document is None else document,
            )
        )

    def _load_approval(
        self,
        auth: manifest.SessionAuthorization,
        document: object | None = None,
        now: datetime = NOW,
    ) -> manifest.OwnerApproval:
        approval = approval_document(auth.canonical_sha256) if document is None else document
        path = write_private_json(self.directory, "approval.json", approval)
        return manifest.load_owner_approval(path, auth, now=now)

    def test_canonical_digest_ignores_object_key_order(self) -> None:
        document = authorization_document()
        reordered = dict(reversed(tuple(document.items())))
        first = self._load_authorization(document)
        second = self._load_authorization(reordered)
        self.assertEqual(first.canonical_sha256, second.canonical_sha256)
        self.assertEqual(first.application_package, "com.argusromtoolkit.argus.qualification")
        self.assertEqual(first.minimum_android_api, 30)
        self.assertEqual(first.required_abi, "arm64-v8a")
        self.assertIn("installed_signer_observation", first.required_capabilities)

    def test_approval_is_bound_to_exact_authorization_and_owner(self) -> None:
        auth = self._load_authorization()
        approved = self._load_approval(auth)
        self.assertEqual(approved.authorization_sha256, auth.canonical_sha256)
        self.assertEqual(approved.owner_identity, auth.owner_identity)

    def test_owner_path_traversal_injection_is_rejected_by_strict_schema(self) -> None:
        auth = self._load_authorization()
        hostile = approval_document(auth.canonical_sha256)
        hostile["owner_path"] = "../../../../etc/passwd"

        with self.assertRaises(manifest.ApprovalError) as caught:
            self._load_approval(auth, hostile)

        self.assertEqual(caught.exception.code, manifest.ApprovalErrorCode.UNKNOWN_FIELD)

    def test_owner_approval_provenance_comes_from_the_private_sidecar_loader(self) -> None:
        auth = self._load_authorization()
        sidecar_path = write_private_json(
            self.directory,
            "approval-provenance.json",
            approval_document(auth.canonical_sha256),
        )
        loaded = manifest.load_owner_approval(sidecar_path, auth, now=NOW)
        constructed = manifest.OwnerApproval(
            loaded.authorization_sha256,
            loaded.owner_identity,
            loaded.valid_from,
            loaded.valid_until,
        )

        self.assertTrue(manifest._is_loaded_owner_approval(loaded))
        self.assertEqual(loaded._source_path, sidecar_path.absolute())
        self.assertIsInstance(loaded._source_file_identity, tuple)
        self.assertFalse(manifest._is_loaded_owner_approval(constructed))

    def test_owner_approval_sidecar_requires_exact_mode_0600(self) -> None:
        auth = self._load_authorization()
        path = write_private_json(
            self.directory,
            "approval-owner-read-only.json",
            approval_document(auth.canonical_sha256),
        )
        os.chmod(path, 0o400)

        with self.assertRaises(manifest.ApprovalError) as caught:
            manifest.load_owner_approval(path, auth, now=NOW)

        self.assertEqual(caught.exception.code, manifest.ApprovalErrorCode.UNSAFE_FILE)

        for replacement in ("0" * 64, auth.canonical_sha256):
            document = approval_document(replacement)
            if replacement == auth.canonical_sha256:
                document["owner_identity"] = "different-private-owner"
            with self.subTest(replacement=replacement[:8], owner=document["owner_identity"]):
                with self.assertRaises(manifest.ApprovalError):
                    self._load_approval(auth, document)

    def test_approval_window_is_inclusive_at_start_and_exclusive_at_expiry(self) -> None:
        auth = self._load_authorization()
        self._load_approval(
            auth,
            now=datetime(2030, 1, 1, 0, 0, 30, tzinfo=timezone.utc),
        )
        with self.assertRaises(manifest.ApprovalError) as caught:
            self._load_approval(
                auth,
                now=datetime(2030, 1, 1, 0, 4, tzinfo=timezone.utc),
            )
        self.assertEqual(caught.exception.code, manifest.ApprovalErrorCode.WINDOW_CLOSED)

    def test_approval_cannot_precede_issue_or_outlive_session(self) -> None:
        auth = self._load_authorization()
        early = approval_document(auth.canonical_sha256)
        early["valid_from_utc"] = "2029-12-31T23:59:00Z"
        with self.assertRaises(manifest.ApprovalError):
            self._load_approval(auth, early)

        late = approval_document(auth.canonical_sha256)
        late["valid_until_utc"] = "2030-01-01T00:06:00Z"
        with self.assertRaises(manifest.ApprovalError):
            self._load_approval(auth, late)

    def test_unknown_fields_duplicate_keys_and_floats_are_rejected(self) -> None:
        document = authorization_document()
        document["owner_approval"] = True
        with self.assertRaises(manifest.AuthorizationError) as caught:
            self._load_authorization(document)
        self.assertEqual(caught.exception.code, manifest.AuthorizationErrorCode.UNKNOWN_FIELD)

        duplicate_path = self.directory / "duplicate.json"
        duplicate_path.write_text(
            '{"schema_version":1,"schema_version":1}', encoding="utf-8"
        )
        os.chmod(duplicate_path, 0o600)
        with self.assertRaises(manifest.AuthorizationError) as caught:
            manifest.load_authorization(duplicate_path)
        self.assertEqual(caught.exception.code, manifest.AuthorizationErrorCode.DUPLICATE_KEY)

        floating = authorization_document()
        floating["reserves"]["storage_bytes"] = 1.5
        with self.assertRaises(manifest.AuthorizationError) as caught:
            self._load_authorization(floating)
        self.assertEqual(caught.exception.code, manifest.AuthorizationErrorCode.FLOAT_NOT_ALLOWED)

    def test_json_integer_limit_is_reported_as_sanitized_invalid_json(self) -> None:
        oversized_integer = self.directory / "oversized-integer.json"
        oversized_integer.write_bytes(b'{"schema_version":' + b"9" * 5000 + b"}")
        os.chmod(oversized_integer, 0o600)

        with self.assertRaises(manifest.AuthorizationError) as caught:
            manifest.load_authorization(oversized_integer)

        self.assertEqual(caught.exception.code, manifest.AuthorizationErrorCode.JSON_INVALID)

    def test_no_reset_authorization_requires_explicit_baseline_but_is_not_admitted_here(self) -> None:
        document = authorization_document()
        document["state"] = {
            "mode": "no-reset",
            "inherited_state_session_id": "private-prior-session",
            "no_reset_baseline": {
                "library_fixture_ids": ["private-fixture-id"],
                "job_states": [{"job_id": "private-job-id", "state": "pending"}],
                "pending_cleanup_ids": [],
            },
        }
        parsed = self._load_authorization(document)
        self.assertEqual(parsed.state_mode, manifest.SessionStateMode.NO_RESET)
        self.assertEqual(parsed.inherited_state_session_id, "private-prior-session")

        document["state"]["no_reset_baseline"] = None
        with self.assertRaises(manifest.AuthorizationError):
            self._load_authorization(document)

    def test_input_files_must_be_private_regular_nonsymlink_and_bounded(self) -> None:
        document = authorization_document()
        public_path = write_private_json(self.directory, "public.json", document)
        os.chmod(public_path, 0o644)
        with self.assertRaises(manifest.AuthorizationError) as caught:
            manifest.load_authorization(public_path)
        self.assertEqual(caught.exception.code, manifest.AuthorizationErrorCode.UNSAFE_FILE)

        target = write_private_json(self.directory, "target.json", document)
        link = self.directory / "link.json"
        link.symlink_to(target)
        with self.assertRaises(manifest.AuthorizationError) as caught:
            manifest.load_authorization(link)
        self.assertEqual(caught.exception.code, manifest.AuthorizationErrorCode.UNSAFE_FILE)

        oversized = self.directory / "oversized.json"
        oversized.write_bytes(b" " * (manifest.MAX_SESSION_AUTH_INPUT_BYTES + 1))
        os.chmod(oversized, 0o600)
        with self.assertRaises(manifest.AuthorizationError) as caught:
            manifest.load_authorization(oversized)
        self.assertEqual(caught.exception.code, manifest.AuthorizationErrorCode.TOO_LARGE)

    def test_private_error_text_does_not_disclose_paths_or_input_values(self) -> None:
        missing = self.directory / "private-serial-do-not-print.json"
        with self.assertRaises(manifest.AuthorizationError) as caught:
            manifest.load_authorization(missing)
        self.assertNotIn(str(missing), str(caught.exception))
        self.assertNotIn("private-serial", str(caught.exception))

    def test_typed_unsupported_categories_are_representable_but_unknown_commands_are_not(self) -> None:
        document = authorization_document()
        document["operations"] = [
            {
                "operation_id": "reset-synthetic",
                "category": "reset_data",
                "phase": "qualification",
                "target_serial": "private-serial-synthetic",
                "package_name": "com.argusromtoolkit.argus.qualification",
                "timeout_seconds": 10,
                "permission_name": None,
                "expected_prior_state": None,
                "desired_state": None,
                "restoration": None,
            }
        ]
        document["approved_remediation"] = []
        parsed = self._load_authorization(document)
        self.assertEqual(parsed.operations[0].category, manifest.OperationCategory.RESET_DATA)

        unknown = dict(document)
        unknown["operations"] = [dict(document["operations"][0], category="arbitrary_operation")]
        with self.assertRaises(manifest.AuthorizationError):
            self._load_authorization(unknown)

        command = dict(document)
        command["operations"] = [dict(document["operations"][0], command="pm clear package")]
        with self.assertRaises(manifest.AuthorizationError) as caught:
            self._load_authorization(command)
        self.assertEqual(caught.exception.code, manifest.AuthorizationErrorCode.UNKNOWN_FIELD)

    def test_ordinary_app_and_undeclared_permission_are_rejected(self) -> None:
        ordinary = authorization_document()
        ordinary["application"]["package_name"] = "com.argusromtoolkit.argus"
        with self.assertRaises(manifest.AuthorizationError):
            self._load_authorization(ordinary)

        undeclared = authorization_document()
        undeclared["artifact"]["declared_permissions"] = []
        with self.assertRaises(manifest.AuthorizationError):
            self._load_authorization(undeclared)

if __name__ == "__main__":
    unittest.main()
