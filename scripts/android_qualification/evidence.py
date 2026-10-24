"""Public interfaces for durable Android qualification evidence.

The store exposes two independent capabilities. An execution writer can add
typed execution records and a separate owner reviewer can add qualification
verdicts. The capability split keeps routine execution code from implying an
owner decision.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from scripts.android_qualification._evidence_review import OwnerReviewer
    from scripts.android_qualification._evidence_storage import ExecutionWriter


DEFAULT_EVIDENCE_ROOT = Path.home() / ".argus-rom-toolkit" / "qualification-evidence"


class EvidenceErrorCode(str, Enum):
    """Stable failures that never include private paths or field values."""

    UNAVAILABLE = "EVIDENCE_UNAVAILABLE"
    UNSAFE_PATH = "EVIDENCE_UNSAFE_PATH"
    INVALID_INPUT = "EVIDENCE_INVALID_INPUT"
    UNSUPPORTED_SCHEMA = "EVIDENCE_SCHEMA_VERSION_UNSUPPORTED"
    DUPLICATE_KEY = "EVIDENCE_DUPLICATE_KEY"
    NON_FINITE_NUMBER = "EVIDENCE_NON_FINITE_NUMBER"
    FLOAT_REJECTED = "EVIDENCE_FLOAT_REJECTED"
    PRIVATE_DATA_REJECTED = "EVIDENCE_PRIVATE_DATA_REJECTED"
    EXPECTED_HEAD_CONFLICT = "EVIDENCE_EXPECTED_HEAD_CONFLICT"
    OPERATION_CONFLICT = "EVIDENCE_OPERATION_CONFLICT"
    BUSY = "EVIDENCE_STREAM_BUSY"
    FINALIZED = "EVIDENCE_ALREADY_FINALIZED"
    CORRUPT = "EVIDENCE_CORRUPT"
    MANIFEST_MISSING = "EVIDENCE_MANIFEST_MISSING"
    MANIFEST_MISMATCH = "EVIDENCE_MANIFEST_MISMATCH"
    VERDICT_BINDING_INVALID = "EVIDENCE_VERDICT_BINDING_INVALID"
    VERDICT_SUFFICIENCY_INVALID = "EVIDENCE_VERDICT_SUFFICIENCY_INVALID"


_ERROR_MESSAGES = {
    EvidenceErrorCode.UNAVAILABLE: "The requested evidence is unavailable.",
    EvidenceErrorCode.UNSAFE_PATH: "The evidence path failed a private-storage check.",
    EvidenceErrorCode.INVALID_INPUT: "The evidence input is invalid.",
    EvidenceErrorCode.UNSUPPORTED_SCHEMA: "The evidence schema version is unsupported.",
    EvidenceErrorCode.DUPLICATE_KEY: "The evidence JSON contains a duplicate key.",
    EvidenceErrorCode.NON_FINITE_NUMBER: "The evidence JSON contains a non-finite number.",
    EvidenceErrorCode.FLOAT_REJECTED: "The evidence JSON contains a floating-point number.",
    EvidenceErrorCode.PRIVATE_DATA_REJECTED: "The evidence value is not an allowed opaque reference.",
    EvidenceErrorCode.EXPECTED_HEAD_CONFLICT: "The evidence stream head changed.",
    EvidenceErrorCode.OPERATION_CONFLICT: "The operation identifier has different content.",
    EvidenceErrorCode.BUSY: "Another cooperating evidence writer is active.",
    EvidenceErrorCode.FINALIZED: "The execution evidence is already finalized.",
    EvidenceErrorCode.CORRUPT: "The evidence chain is corrupt.",
    EvidenceErrorCode.MANIFEST_MISSING: "The execution evidence manifest is missing.",
    EvidenceErrorCode.MANIFEST_MISMATCH: "The execution evidence manifest does not match its records.",
    EvidenceErrorCode.VERDICT_BINDING_INVALID: "The owner verdict does not bind the selected evidence.",
    EvidenceErrorCode.VERDICT_SUFFICIENCY_INVALID: "The owner verdict basis is not sufficient.",
}


class EvidenceError(Exception):
    """Report an evidence failure by stable bounded code."""

    def __init__(self, code: EvidenceErrorCode) -> None:
        self.code = code
        super().__init__(_ERROR_MESSAGES[code])


class ArtifactClass(str, Enum):
    QUALIFICATION_VARIANT = "qualification_variant"
    DISTRIBUTABLE_RELEASE = "distributable_release"


class Platform(str, Enum):
    ANDROID = "android"
    MACOS = "macos"


@dataclass(frozen=True)
class ArtifactPin:
    artifact_ref: str
    artifact_sha256: str
    artifact_class: ArtifactClass


@dataclass(frozen=True)
class AuthorizationPin:
    manifest_version: int
    manifest_sha256: str


@dataclass(frozen=True)
class FixturePin:
    manifest_version: int
    manifest_sha256: str
    corpus_ref: str


@dataclass(frozen=True)
class PlanPin:
    plan_ref: str
    plan_version: int
    plan_sha256: str


@dataclass(frozen=True)
class AcceptanceRulesPin:
    """Pin one exact acceptance-rule identity and display version."""

    rules_ref: str
    rules_version: str
    rules_sha256: str


@dataclass(frozen=True)
class EnvironmentPin:
    platform: Platform
    platform_version: str
    environment_ref: str
    target_ref: str


@dataclass(frozen=True)
class ReviewRequirements:
    required_evidence_refs: tuple[str, ...]
    objective_review_allowed: bool
    direct_owner_observation_allowed: bool
    retrospective_allowed: bool


@dataclass(frozen=True)
class SessionSpec:
    """Bind an execution to field-specific, typed opaque provenance aliases."""

    session_id: str
    scenario_id: str
    artifact: ArtifactPin
    authorization: AuthorizationPin
    fixtures: FixturePin
    plan: PlanPin
    rules: AcceptanceRulesPin
    environment: EnvironmentPin
    review_requirements: ReviewRequirements


@dataclass(frozen=True)
class WriteRequest:
    """Request one append using an `operation-<32 hex>` idempotency alias."""

    operation_id: str
    occurred_at: str | None = None
    expected_head_sha256: str | None = None


class AssertionOutcome(str, Enum):
    PASSED = "passed"
    FAILED = "failed"
    BLOCKED = "blocked"
    NOT_RUN = "not_run"


class MeasurementUnit(str, Enum):
    COUNT = "count"
    BYTES = "bytes"
    MILLISECONDS = "milliseconds"
    SECONDS = "seconds"
    DEVICE_INDEPENDENT_PIXELS = "device_independent_pixels"


@dataclass(frozen=True)
class Measurement:
    name: str
    value: int
    unit: MeasurementUnit


@dataclass(frozen=True)
class AssertionObservation:
    """Describe one machine-observed assertion tied to a pinned rule.

    Reference values use their field-specific typed aliases, and measurement
    names use `measurement-<32 hex>`. The storage boundary validates these
    values again when loading persisted bytes.
    """

    assertion_ref: str
    rules_ref: str
    rules_version: str
    rules_sha256: str
    observed_at: str
    expected_outcome: AssertionOutcome
    actual_outcome: AssertionOutcome
    evidence_refs: tuple[str, ...]
    measurements: tuple[Measurement, ...]


class Lifecycle(str, Enum):
    PREPARATION_STARTED = "preparation_started"
    PREPARATION_COMPLETED = "preparation_completed"
    EXECUTION_STARTED = "execution_started"
    CLEANUP_STARTED = "cleanup_started"
    CLEANUP_COMPLETED = "cleanup_completed"


@dataclass(frozen=True)
class LifecycleObservation:
    lifecycle: Lifecycle
    evidence_refs: tuple[str, ...]


class TerminalOutcome(str, Enum):
    COMPLETED = "completed"
    FAILED = "failed"
    BLOCKED = "blocked"
    INTERRUPTED = "interrupted"


class TerminalReason(str, Enum):
    PLAN_COMPLETE = "plan_complete"
    ASSERTION_FAILED = "assertion_failed"
    PREREQUISITE_BLOCKED = "prerequisite_blocked"
    DEADLINE_EXCEEDED = "deadline_exceeded"
    OPERATOR_TERMINATED = "operator_terminated"
    RECOVERY_ABANDONED = "recovery_abandoned"


@dataclass(frozen=True)
class TerminalObservation:
    outcome: TerminalOutcome
    reason: TerminalReason
    ended_at: str
    evidence_refs: tuple[str, ...]


@dataclass(frozen=True)
class AppendReceipt:
    operation_id: str
    session_id: str
    sequence: int
    record_sha256: str
    head_sha256: str
    idempotent: bool


@dataclass(frozen=True)
class RecordSummary:
    sequence: int
    record_sha256: str
    previous_record_sha256: str | None
    event_type: str


@dataclass(frozen=True)
class SessionSnapshot:
    session_id: str
    state: str
    record_count: int
    head_sha256: str
    records: tuple[RecordSummary, ...]


@dataclass(frozen=True)
class ExecutionManifest:
    session_id: str
    scenario_id: str
    record_count: int
    head_sha256: str
    terminal_record_sha256: str
    manifest_sha256: str


class RecoveryState(str, Enum):
    FINALIZED = "finalized"
    INTERRUPTED = "interrupted"
    INCOMPLETE = "incomplete"
    BUSY = "busy"


@dataclass(frozen=True)
class RecoveryResult:
    session_id: str
    state: RecoveryState
    appended_interruption: bool
    manifest_sha256: str | None


class OwnerVerdictOutcome(str, Enum):
    PASS = "PASS"
    FAIL = "FAIL"
    BLOCKED = "BLOCKED"
    NOT_RUN = "NOT_RUN"


class ReviewBasis(str, Enum):
    OBJECTIVE_REVIEW = "objective_review"
    DIRECT_OWNER_OBSERVATION = "direct_owner_observation"


class Sufficiency(str, Enum):
    SUFFICIENT = "sufficient"
    INSUFFICIENT = "insufficient"


@dataclass(frozen=True)
class SelectedRecord:
    sequence: int
    record_sha256: str


@dataclass(frozen=True)
class VerdictRequest:
    """Describe an owner decision and the exact execution evidence it assesses."""

    evidence_manifest_sha256: str
    selected_records: tuple[SelectedRecord, ...]
    artifact_ref: str
    artifact_sha256: str
    rules_ref: str
    rules_version: str
    rules_sha256: str
    verdict: OwnerVerdictOutcome
    basis: ReviewBasis
    sufficiency: Sufficiency
    retrospective: bool
    direct_observation_declared: bool
    reviewed_at: str
    supersedes_verdict_sha256: str | None = None


@dataclass(frozen=True)
class OwnerVerdict:
    sequence: int
    owner_alias: str
    verdict: OwnerVerdictOutcome
    basis: ReviewBasis
    sufficiency: Sufficiency
    evidence_manifest_sha256: str
    verdict_sha256: str
    previous_verdict_sha256: str | None
    supersedes_verdict_sha256: str | None


@dataclass(frozen=True)
class VerdictReceipt:
    operation_id: str
    sequence: int
    verdict_sha256: str
    idempotent: bool


class EvidenceStore:
    """Coordinate execution and owner-review evidence under one private root."""

    def __init__(self, root: Path | None = None) -> None:
        self._root = DEFAULT_EVIDENCE_ROOT if root is None else Path(root)

    def execution_writer(self) -> ExecutionWriter:
        """Return the capability that writes execution records only."""

        from scripts.android_qualification._evidence_storage import ExecutionWriter

        return ExecutionWriter(self._root)

    def owner_reviewer(self, owner_alias: str) -> OwnerReviewer:
        """Return the capability that appends explicit owner verdicts only."""

        from scripts.android_qualification._evidence_review import OwnerReviewer

        return OwnerReviewer(self._root, owner_alias)
