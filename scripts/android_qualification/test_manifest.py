"""Host-validation tests for the private qualification manifest envelope."""

from __future__ import annotations

import json
import stat
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


if __name__ == "__main__":
    unittest.main()
