"""Validate provenance for fixture identity expectations.

The oracle distinguishes generated synthetic expectations from references to
independently maintained sources. It records whether evidence is missing,
synthetic, or pinned, but a manifest hash alone never qualifies a game.
"""

from __future__ import annotations

import hashlib
import json
import unicodedata
from dataclasses import dataclass
from typing import Mapping


@dataclass(frozen=True)
class IdentityAssessment:
    """Report evidence tier without turning it into a qualification verdict."""

    identity_support: str
    qualification_status: str = "not_qualified"
    reference_sha256: str | None = None


class OracleError(ValueError):
    """Raised when an identity evidence record is malformed or conflicting."""


def canonical_sha256(value: object) -> str:
    """Hash one JSON value using stable UTF-8 canonical encoding."""

    try:
        encoded = json.dumps(
            value,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
            allow_nan=False,
        ).encode("utf-8")
    except (TypeError, ValueError, UnicodeError, RecursionError):
        raise OracleError("invalid identity value") from None
    return hashlib.sha256(encoded).hexdigest()


def _text(value: object, maximum: int = 2048) -> str:
    if (
        type(value) is not str or not value or len(value) > maximum
        or value != value.strip()
        or unicodedata.normalize("NFC", value) != value
        or any(unicodedata.category(char) == "Cc" for char in value)
    ):
        raise OracleError("invalid evidence text")
    return value


def _digest(value: object) -> str:
    if (
        type(value) is not str or len(value) != 64
        or any(char not in "0123456789abcdef" for char in value)
    ):
        raise OracleError("invalid evidence digest")
    return value


def _string_list(value: object, *, allow_empty: bool) -> tuple[str, ...]:
    if type(value) is not list or (not allow_empty and not value):
        raise OracleError("invalid evidence list")
    result = tuple(_text(item, 1024) for item in value)
    if len(set(result)) != len(result):
        raise OracleError("duplicate evidence entry")
    return result


def assess_identity_evidence(
    expected_identity: Mapping[str, object], evidence: object
) -> IdentityAssessment:
    """Classify evidence while keeping identity qualification owner-reviewed."""

    if type(expected_identity) is not dict or not expected_identity:
        raise OracleError("invalid expected identity")
    if evidence is None:
        return IdentityAssessment("not_independently_verified")
    if type(evidence) is not dict or type(evidence.get("schema_version")) is not int:
        raise OracleError("invalid identity evidence")
    if evidence["schema_version"] != 1:
        raise OracleError("unsupported identity evidence schema")
    tier = evidence.get("tier")
    if tier == "synthetic":
        if set(evidence) != {"schema_version", "tier", "provenance"}:
            raise OracleError("invalid synthetic evidence")
        _text(evidence["provenance"])
        return IdentityAssessment("synthetic_only")
    if tier != "independent_reference":
        raise OracleError("unsupported identity evidence tier")
    required = {
        "schema_version", "tier", "source", "reference", "revision",
        "reference_sha256", "method", "provenance",
        "expected_identity_sha256", "limitations", "conflicts",
    }
    if set(evidence) != required:
        raise OracleError("incomplete independent reference")
    for field in ("source", "reference", "revision", "method", "provenance"):
        _text(evidence[field])
    reference_digest = _digest(evidence["reference_sha256"])
    if _digest(evidence["expected_identity_sha256"]) != canonical_sha256(expected_identity):
        raise OracleError("reference does not bind expected identity")
    _string_list(evidence["limitations"], allow_empty=True)
    conflicts = _string_list(evidence["conflicts"], allow_empty=True)
    if conflicts:
        raise OracleError("conflicting identity evidence")
    return IdentityAssessment("pinned_unverified", reference_sha256=reference_digest)
