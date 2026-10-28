"""Version and validate owner evidence at the native export boundary.

This module validates bindings and canonical form. It cannot create owner
authority: production admission requires a provider that obtains and verifies
all authority through the installed native service and authenticated IPC.
"""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass
import hashlib
import os
from typing import Protocol

from . import fixture_oracle
from ._fixture_staging_model import FixtureStagingError, FixtureStagingErrorCode
from .fixture_oracle import canonical_json


_NATIVE_RECEIPT_FIELDS = frozenset(
    {
        "schema_version",
        "status",
        "code",
        "request_id",
        "session_id",
        "service_boot_id",
        "sequence",
        "deadline_ns",
        "manifest_sha256",
        "authorization_sha256",
        "generation",
        "members",
        "members_sha256",
        "member_count",
        "frame_sha256",
        "receipt_sha256",
        "receipt_path",
        "durable",
    }
)


_EVIDENCE_FIELDS = (
    "request_id",
    "session",
    "service_boot_epoch",
    "sequence",
    "nonce",
    "deadline",
    "manifest_digest",
    "generation",
    "ordered_member_digests",
    "authenticated_native_receipt",
    "durable_receiver_completion",
)


def _blocked() -> FixtureStagingError:
    return FixtureStagingError(
        FixtureStagingErrorCode.BLOCKED_UNSUPPORTED_EXCLUSIVITY
    )


@dataclass(frozen=True)
class ExportEvidenceV1:
    """Canonical schema-1 evidence binding an export to its native receipt."""

    request_id: str
    session: str
    service_boot_epoch: str
    sequence: int
    nonce: str
    deadline: int
    manifest_digest: str
    generation: int
    ordered_member_digests: tuple[str, ...]
    authenticated_native_receipt: Mapping[str, object]
    durable_receiver_completion: bool

    @classmethod
    def from_native(
        cls,
        attempt: Mapping[str, object],
        receipt: Mapping[str, object],
    ) -> "ExportEvidenceV1":
        """Validate the native receipt against the immutable journal attempt."""

        try:
            if not isinstance(receipt, Mapping) or set(receipt) != _NATIVE_RECEIPT_FIELDS:
                raise _blocked()
            members = attempt["members"]
            if not isinstance(members, list) or not members:
                raise _blocked()
            digests = tuple(member["sha256"] for member in members)
            if any(not _is_sha256(value) for value in digests):
                raise _blocked()
            expected = {
                "request_id": attempt["request_id"],
                "session_id": attempt["session_id"],
                "service_boot_id": attempt["service_boot_id"],
                "sequence": attempt["sequence"],
                "deadline_ns": attempt["deadline_ns"],
                "manifest_sha256": attempt["manifest_sha256"],
                "authorization_sha256": attempt["authorization_sha256"],
                "generation": attempt["generation"],
                "members": members,
            }
            if any(receipt.get(key) != value for key, value in expected.items()):
                raise _blocked()
            if (
                type(receipt.get("schema_version")) is not int
                or receipt["schema_version"] != 1
                or receipt.get("status") != "VERIFIED_RECEIVER_COMPLETION"
                or receipt.get("code") != "BROKER_RECEIVER_RECEIPT_DURABLE"
                or receipt.get("durable") is not True
                or type(receipt.get("sequence")) is not int
                or type(receipt.get("deadline_ns")) is not int
                or type(receipt.get("generation")) is not int
                or type(receipt.get("member_count")) is not int
                or receipt["member_count"] != len(members)
                or not _is_sha256(receipt.get("members_sha256"))
                or receipt["members_sha256"]
                != hashlib.sha256(
                    canonical_json(
                        members,
                        maximum_bytes=fixture_oracle.MAX_RECEIPT_DOCUMENT_BYTES,
                    )
                ).hexdigest()
                or not _is_sha256(receipt.get("frame_sha256"))
                or not _is_sha256(receipt.get("receipt_sha256"))
                or not isinstance(receipt.get("receipt_path"), str)
                or not os.path.isabs(receipt["receipt_path"])
                or "\0" in receipt["receipt_path"]
                or receipt.get("durable") is not True
            ):
                raise _blocked()
            identifiers = ("request_id", "session_id", "service_boot_id")
            if (
                any(not isinstance(expected[key], str) or not expected[key] for key in identifiers)
                or not isinstance(attempt["nonce"], str)
                or not attempt["nonce"]
            ):
                raise _blocked()
            for key in ("sequence", "deadline_ns", "generation"):
                if type(expected[key]) is not int or expected[key] < 0:
                    raise _blocked()
            if not _is_sha256(expected["manifest_sha256"]):
                raise _blocked()
            if not _is_sha256(expected["authorization_sha256"]):
                raise _blocked()
            # The native receipt omits the nonce field. Its signed freshness
            # value is bound through the authorization digest in this receipt.
            digest_payload = {
                key: value
                for key, value in receipt.items()
                if key
                not in {
                    "service_boot_id",
                    "sequence",
                    "receipt_sha256",
                    "receipt_path",
                }
            }
            expected_receipt_sha256 = hashlib.sha256(
                canonical_json(
                    digest_payload,
                    maximum_bytes=fixture_oracle.MAX_RECEIPT_DOCUMENT_BYTES,
                )
            ).hexdigest()
            if receipt["receipt_sha256"] != expected_receipt_sha256:
                raise _blocked()
            native_receipt = dict(receipt)
            canonical_json(
                native_receipt,
                maximum_bytes=fixture_oracle.MAX_RECEIPT_DOCUMENT_BYTES,
            )
            return cls(
                request_id=expected["request_id"],
                session=expected["session_id"],
                service_boot_epoch=expected["service_boot_id"],
                sequence=expected["sequence"],
                nonce=attempt["nonce"],
                deadline=expected["deadline_ns"],
                manifest_digest=expected["manifest_sha256"],
                generation=expected["generation"],
                ordered_member_digests=digests,
                authenticated_native_receipt=native_receipt,
                durable_receiver_completion=True,
            )
        except (KeyError, TypeError, ValueError) as error:
            raise _blocked() from error

    @property
    def payload(self) -> dict[str, object]:
        """Return the schema-versioned canonical JSON value."""

        return {
            "schema_version": 1,
            **{
                key: (
                    list(self.ordered_member_digests)
                    if key == "ordered_member_digests"
                    else getattr(self, key)
                )
                for key in _EVIDENCE_FIELDS
            },
        }

    @property
    def schema_version(self) -> int:
        """Return this immutable record's schema version."""

        return 1

    @property
    def canonical_bytes(self) -> bytes:
        """Serialize this evidence using the repository's canonical JSON rules."""

        return canonical_json(self.payload)

    @property
    def sha256(self) -> str:
        """Return the digest of the canonical evidence record."""

        return hashlib.sha256(self.canonical_bytes).hexdigest()


class NativeAdmissionProvider(Protocol):
    """Native authority boundary for admission and receipt-only recovery.

    A production implementation obtains and verifies reviewed authorization,
    owner consent and signing, installed service and broker identities, the
    authenticated peer, and current-session freshness itself. It must not
    accept those authority values as caller-provided evidence.
    """

    def verify_and_admit(self, evidence: ExportEvidenceV1) -> object:
        """Acquire and verify all authority in native code before admission."""
        ...

    def query_export_receipt(self) -> Mapping[str, object] | None:
        """Query the authenticated service journal without dispatching an export."""
        ...


class ProductionAdmissionIssuer:
    """Issue admission only after the installed native authority provider accepts."""

    def __init__(self, provider: NativeAdmissionProvider | None) -> None:
        self._provider = provider

    def issue(
        self,
        attempt: Mapping[str, object],
        receipt: Mapping[str, object],
    ) -> ExportEvidenceV1:
        """Validate evidence and delegate every authority decision to native IPC."""

        if self._provider is None:
            raise _blocked()
        evidence = ExportEvidenceV1.from_native(attempt, receipt)
        try:
            accepted = self._provider.verify_and_admit(evidence)
        except Exception as error:
            raise _blocked() from error
        if accepted is not evidence:
            raise _blocked()
        return evidence

    def recover(self) -> Mapping[str, object] | None:
        """Resolve recovery using a receipt query; never dispatch or replay."""

        if self._provider is None:
            raise _blocked()
        try:
            return self._provider.query_export_receipt()
        except Exception as error:
            raise _blocked() from error


def _is_sha256(value: object) -> bool:
    if not isinstance(value, str) or len(value) != 64:
        return False
    try:
        return len(bytes.fromhex(value)) == 32 and value == value.lower()
    except ValueError:
        return False
