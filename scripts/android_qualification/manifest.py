"""Structural validation for the private Android qualification manifest.

This module reads an owner-supplied manifest and validates only its versioned
host-side shape. It does not perform SPEC-X-003 session admission, validate
artifacts or fixtures, prove target identity, or authorize device operations.
Those responsibilities remain with the live qualification admission design.
"""

from __future__ import annotations

import json
import stat
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Any, NoReturn


SCHEMA_VERSION = 1
MAX_MANIFEST_BYTES = 64 * 1024
MAX_REFERENCE_CHARS = 256

REFERENCE_FIELDS = (
    "authorization_ref",
    "target_ref",
    "artifact_ref",
    "plan_ref",
    "scope_ref",
)
REQUIRED_FIELDS = (
    "schema_version",
    *REFERENCE_FIELDS,
    "state_mode",
    "inherited_state_session_ref",
)


class StateMode(str, Enum):
    """The two separately invocable qualification state modes."""

    FRESH = "fresh"
    NO_RESET = "no-reset"


class ManifestErrorCode(str, Enum):
    """Stable error codes returned without manifest values or paths."""

    UNAVAILABLE = "MANIFEST_UNAVAILABLE"
    NOT_REGULAR_FILE = "MANIFEST_NOT_REGULAR_FILE"
    TOO_LARGE = "MANIFEST_TOO_LARGE"
    ENCODING_INVALID = "MANIFEST_ENCODING_INVALID"
    JSON_INVALID = "MANIFEST_JSON_INVALID"
    DUPLICATE_KEY = "MANIFEST_DUPLICATE_KEY"
    ROOT_INVALID = "MANIFEST_ROOT_INVALID"
    MISSING_FIELD = "MANIFEST_MISSING_FIELD"
    UNKNOWN_FIELD = "MANIFEST_UNKNOWN_FIELD"
    SCHEMA_VERSION_UNSUPPORTED = "MANIFEST_SCHEMA_VERSION_UNSUPPORTED"
    INVALID_REFERENCE = "MANIFEST_INVALID_REFERENCE"
    INVALID_STATE_MODE = "MANIFEST_INVALID_STATE_MODE"
    STATE_MODE_MISMATCH = "MANIFEST_STATE_MODE_MISMATCH"
    INHERITED_STATE_REQUIRED = "MANIFEST_INHERITED_STATE_REQUIRED"
    INHERITED_STATE_UNEXPECTED = "MANIFEST_INHERITED_STATE_UNEXPECTED"


_ERROR_MESSAGES = {
    ManifestErrorCode.UNAVAILABLE: "Qualification manifest is unavailable",
    ManifestErrorCode.NOT_REGULAR_FILE: "Qualification manifest is not a regular file",
    ManifestErrorCode.TOO_LARGE: "Qualification manifest exceeds the supported size",
    ManifestErrorCode.ENCODING_INVALID: "Qualification manifest is not valid UTF-8",
    ManifestErrorCode.JSON_INVALID: "Qualification manifest is not valid JSON",
    ManifestErrorCode.DUPLICATE_KEY: "Qualification manifest contains duplicate keys",
    ManifestErrorCode.ROOT_INVALID: "Qualification manifest must be a JSON object",
    ManifestErrorCode.MISSING_FIELD: "Qualification manifest is missing a required field",
    ManifestErrorCode.UNKNOWN_FIELD: "Qualification manifest contains an unknown field",
    ManifestErrorCode.SCHEMA_VERSION_UNSUPPORTED: "Qualification manifest schema version is unsupported",
    ManifestErrorCode.INVALID_REFERENCE: "Qualification manifest contains an invalid identity reference",
    ManifestErrorCode.INVALID_STATE_MODE: "Qualification manifest state mode is invalid",
    ManifestErrorCode.STATE_MODE_MISMATCH: "Qualification manifest does not match the selected entrypoint",
    ManifestErrorCode.INHERITED_STATE_REQUIRED: "No-reset qualification requires an inherited session reference",
    ManifestErrorCode.INHERITED_STATE_UNEXPECTED: "Fresh qualification must not name an inherited session",
}


class ManifestError(Exception):
    """A bounded manifest error that never includes private input values."""

    def __init__(self, code: ManifestErrorCode) -> None:
        self.code = code
        super().__init__(_ERROR_MESSAGES[code])


@dataclass(frozen=True)
class QualificationManifest:
    """The minimal version-1 host-validation envelope."""

    schema_version: int
    authorization_ref: str
    target_ref: str
    artifact_ref: str
    plan_ref: str
    scope_ref: str
    state_mode: StateMode
    inherited_state_session_ref: str | None


class _DuplicateKey(ValueError):
    pass


class _NonFiniteConstant(ValueError):
    pass


def _object_without_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    document: dict[str, Any] = {}
    for key, value in pairs:
        if key in document:
            raise _DuplicateKey
        document[key] = value
    return document


def _reject_non_finite_constant(_value: str) -> NoReturn:
    raise _NonFiniteConstant


def _invalid_reference() -> NoReturn:
    raise ManifestError(ManifestErrorCode.INVALID_REFERENCE)


def _validate_reference(value: object) -> str:
    if type(value) is not str or not 1 <= len(value) <= MAX_REFERENCE_CHARS:
        _invalid_reference()
    if value != value.strip() or any(ord(character) < 0x20 or ord(character) == 0x7F for character in value):
        _invalid_reference()
    return value


def _parse_state_mode(value: object) -> StateMode:
    if type(value) is not str:
        raise ManifestError(ManifestErrorCode.INVALID_STATE_MODE)
    try:
        return StateMode(value)
    except ValueError:
        raise ManifestError(ManifestErrorCode.INVALID_STATE_MODE) from None


def _validate_document(
    document: object,
    expected_state_mode: StateMode,
) -> QualificationManifest:
    if type(document) is not dict:
        raise ManifestError(ManifestErrorCode.ROOT_INVALID)

    supplied_fields = set(document)
    required_fields = set(REQUIRED_FIELDS)
    if required_fields - supplied_fields:
        raise ManifestError(ManifestErrorCode.MISSING_FIELD)
    if supplied_fields - required_fields:
        raise ManifestError(ManifestErrorCode.UNKNOWN_FIELD)

    version = document["schema_version"]
    if type(version) is not int or version != SCHEMA_VERSION:
        raise ManifestError(ManifestErrorCode.SCHEMA_VERSION_UNSUPPORTED)

    state_mode = _parse_state_mode(document["state_mode"])
    if state_mode is not expected_state_mode:
        raise ManifestError(ManifestErrorCode.STATE_MODE_MISMATCH)

    references = {field: _validate_reference(document[field]) for field in REFERENCE_FIELDS}

    inherited_reference = document["inherited_state_session_ref"]
    if state_mode is StateMode.FRESH:
        if inherited_reference is not None:
            raise ManifestError(ManifestErrorCode.INHERITED_STATE_UNEXPECTED)
        inherited_session: str | None = None
    else:
        if inherited_reference is None:
            raise ManifestError(ManifestErrorCode.INHERITED_STATE_REQUIRED)
        inherited_session = _validate_reference(inherited_reference)

    return QualificationManifest(
        schema_version=SCHEMA_VERSION,
        authorization_ref=references["authorization_ref"],
        target_ref=references["target_ref"],
        artifact_ref=references["artifact_ref"],
        plan_ref=references["plan_ref"],
        scope_ref=references["scope_ref"],
        state_mode=state_mode,
        inherited_state_session_ref=inherited_session,
    )


def load_manifest(
    manifest_path: Path,
    expected_state_mode: StateMode,
) -> QualificationManifest:
    """Load and structurally validate one owner-private manifest.

    Only a readable regular file is accepted. The file is bounded before
    parsing, and all failures omit its path, contents, and arbitrary parser
    output.
    """

    if type(expected_state_mode) is not StateMode:
        raise TypeError("expected_state_mode must be a StateMode")

    try:
        file_status = manifest_path.stat()
    except OSError:
        raise ManifestError(ManifestErrorCode.UNAVAILABLE) from None

    if not stat.S_ISREG(file_status.st_mode):
        raise ManifestError(ManifestErrorCode.NOT_REGULAR_FILE)
    if file_status.st_size > MAX_MANIFEST_BYTES:
        raise ManifestError(ManifestErrorCode.TOO_LARGE)

    try:
        with manifest_path.open("rb") as stream:
            encoded = stream.read(MAX_MANIFEST_BYTES + 1)
    except OSError:
        raise ManifestError(ManifestErrorCode.UNAVAILABLE) from None
    if len(encoded) > MAX_MANIFEST_BYTES:
        raise ManifestError(ManifestErrorCode.TOO_LARGE)

    try:
        text = encoded.decode("utf-8")
    except UnicodeDecodeError:
        raise ManifestError(ManifestErrorCode.ENCODING_INVALID) from None

    try:
        document = json.loads(
            text,
            object_pairs_hook=_object_without_duplicate_keys,
            parse_constant=_reject_non_finite_constant,
        )
    except _DuplicateKey:
        raise ManifestError(ManifestErrorCode.DUPLICATE_KEY) from None
    except (json.JSONDecodeError, ValueError):
        raise ManifestError(ManifestErrorCode.JSON_INVALID) from None

    return _validate_document(document, expected_state_mode)
