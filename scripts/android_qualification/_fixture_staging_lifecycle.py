"""Persist owner-side lifecycle facts for an authenticated native session.

The journal records an attempt durably before a native request may be sent.
It never retries an interrupted operation. A caller may resolve an unknown
attempt only with the matching durable receipt returned through the
authenticated installed broker path.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Mapping
import errno
import fcntl
import hashlib
import json
import os
import secrets
import stat

from .fixture_oracle import canonical_json


_JOURNAL_NAME = "lifecycle.jsonl"
_RECOVERY_NAME = "recovery-required.json"
_MAX_JOURNAL_BYTES = 8 * 1024 * 1024
_MEMBERS_DIGEST_DOMAIN = b"argus.fixture-staging.export-members.v1\0"
_DIGEST_FIELDS = (
    "authorization_sha256",
    "consent_sha256",
    "manifest_sha256",
    "request_sha256",
)
_BINDING_FIELDS = (
    "owner_id",
    "installation_id",
    "broker_revision",
    "owner_key_id",
    "authorization_sha256",
    "consent_sha256",
    "service_boot_id",
    "session_id",
    "deadline_ns",
)
_ATTEMPT_FIELDS = frozenset(
    (
        *_BINDING_FIELDS,
        "manifest_sha256",
        "generation",
        "members",
        "connection_id",
        "request_id",
        "request_sha256",
        "operation",
        "nonce",
        "sequence",
    )
)


class JournalError(RuntimeError):
    """A requested lifecycle transition is invalid or unsafe."""


class JournalCorrupt(JournalError):
    """The journal cannot establish a trustworthy native-session history."""


@dataclass(frozen=True)
class RecoveryObligation:
    """An operation that must be reconciled before another mutation begins."""

    request_id: str
    sequence: int
    status: str
    reason: str


class OwnerPrivateLifecycleJournal:
    """Append-only, owner-private record of native session attempts and receipts.

    The containing directory must already exist, belong to the current user,
    and have no group or world permissions. Each record is canonical JSON,
    linked to the preceding record by SHA-256, appended under an OS file lock,
    and synced before the transition returns. The hash chain detects accidental
    corruption but is not tamper-resistant against another process running as
    the same user. This journal is recovery bookkeeping, never authority for a
    native mutation; only a matching receipt over the authenticated native
    service connection can confirm an operation. Recovery reads recheck the
    durable marker after locking so concurrent marker creation cannot make an
    unresolved attempt appear eligible.
    """

    def __init__(self, directory: Path) -> None:
        self.directory = Path(directory).absolute()
        self._journal = self.directory / _JOURNAL_NAME
        self._recovery_marker = self.directory / _RECOVERY_NAME
        self._fsync_completed = False
        self._validate_directory()

    @property
    def fsync_completed(self) -> bool:
        """Report whether this instance completed a durable append."""

        return self._fsync_completed

    def begin_attempt(self, attempt: Mapping[str, Any], *, now_ns: int) -> None:
        """Persist one attempt before dispatch, preserving the session deadline."""

        normalized = self._validate_attempt(attempt, now_ns=now_ns)
        with self._locked_file(create=True) as descriptor:
            records = self._read_records(descriptor)
            if self._recovery_marker.exists():
                raise JournalCorrupt("journal has an unresolved recovery marker")
            prior_attempt, prior_receipt = self._last_attempt_and_receipt(records)
            if prior_attempt is not None and prior_receipt is None:
                if self._last_unknown(records, prior_attempt["request_id"]) is None:
                    self._append_record(
                        descriptor,
                        records,
                        "unknown",
                        {
                            "request_id": prior_attempt["request_id"],
                            "sequence": prior_attempt["sequence"],
                            "reason": "interrupted_attempt",
                        },
                    )
                raise JournalError("unresolved native operation requires reconciliation")
            prior_attempts = [
                record["payload"] for record in records if record["event"] == "attempt"
            ]
            if any(
                normalized["request_id"] == item["request_id"]
                or normalized["nonce"] == item["nonce"]
                for item in prior_attempts
            ):
                raise JournalError("native request or nonce was replayed")
            if prior_attempt is not None:
                self._validate_successor(prior_attempt, prior_receipt, normalized)
            self._append_record(descriptor, records, "attempt", normalized)

    def dispatch(
        self,
        attempt: Mapping[str, Any],
        *,
        now_ns: int,
        send: Callable[[], Mapping[str, Any]],
        verify_receipt: Callable[[Mapping[str, Any], Mapping[str, Any]], bool],
        clock_ns: Callable[[], int],
    ) -> Mapping[str, Any]:
        """Dispatch once after durable ATTEMPT and accept only verified receipt.

        ``send`` is the native session transport. Its result is untrusted data
        until ``verify_receipt`` authenticates the native receipt against the
        exact attempt. Transport errors, malformed results, failed receipt
        verification, and deadline expiry all become UNKNOWN; none is retried.
        """

        self.begin_attempt(attempt, now_ns=now_ns)
        request_id = str(attempt["request_id"])
        try:
            response = send()
            if not isinstance(response, Mapping):
                raise JournalError("native transport returned an invalid response")
            if clock_ns() >= attempt["deadline_ns"]:
                raise JournalError("native receipt arrived after the immutable deadline")
            if not verify_receipt(attempt, response):
                raise JournalError("native durable receipt failed authentication")
            receipt = response.get("receipt")
            if not isinstance(receipt, Mapping):
                raise JournalError("native response has no durable receipt")
            self.record_native_receipt(
                request_id=receipt["request_id"],
                sequence=receipt["sequence"],
                deadline_ns=receipt["deadline_ns"],
                manifest_sha256=receipt["manifest_sha256"],
                generation=receipt["generation"],
                members_sha256=receipt["members_sha256"],
                receipt_sha256=receipt["receipt_sha256"],
                durable=receipt["durable"],
                now_ns=clock_ns(),
            )
            return response
        except Exception as error:
            try:
                self.mark_unknown(request_id=request_id, reason="native_outcome_unverified")
            except JournalError:
                pass
            raise JournalError("native outcome is UNKNOWN; recovery is required") from error

    def record_native_receipt(
        self,
        *,
        request_id: str,
        sequence: int,
        deadline_ns: int,
        manifest_sha256: str,
        generation: int,
        members_sha256: str,
        receipt_sha256: str,
        durable: bool,
        now_ns: int,
    ) -> None:
        """Resolve the latest attempt with its matching durable native receipt.

        Callers must obtain these fields from the authenticated installed
        broker after its receiver has verified complete framing, member order,
        member digests, generation, receipt, and durable delivery. This method
        checks binding and completeness; it does not manufacture that authority.
        """

        self._record_native_receipt(
            request_id=request_id,
            sequence=sequence,
            deadline_ns=deadline_ns,
            manifest_sha256=manifest_sha256,
            generation=generation,
            members_sha256=members_sha256,
            receipt_sha256=receipt_sha256,
            durable=durable,
            now_ns=now_ns,
            allow_expired=False,
        )

    def _record_reconciled_native_receipt(
        self,
        *,
        request_id: str,
        sequence: int,
        deadline_ns: int,
        manifest_sha256: str,
        generation: int,
        members_sha256: str,
        receipt_sha256: str,
        durable: bool,
        observed_ns: int,
    ) -> None:
        """Resolve an expired obligation from a read-only authenticated receipt.

        The original mutation deadline remains in the attempt and receipt
        binding. This records no new mutation authority and is called only
        after the owner client verifies the installed broker and service reply.
        """

        self._record_native_receipt(
            request_id=request_id,
            sequence=sequence,
            deadline_ns=deadline_ns,
            manifest_sha256=manifest_sha256,
            generation=generation,
            members_sha256=members_sha256,
            receipt_sha256=receipt_sha256,
            durable=durable,
            now_ns=observed_ns,
            allow_expired=True,
        )

    def _record_native_receipt(
        self,
        *,
        request_id: str,
        sequence: int,
        deadline_ns: int,
        manifest_sha256: str,
        generation: int,
        members_sha256: str,
        receipt_sha256: str,
        durable: bool,
        now_ns: int,
        allow_expired: bool,
    ) -> None:

        receipt = {
            "request_id": request_id,
            "sequence": sequence,
            "deadline_ns": deadline_ns,
            "manifest_sha256": manifest_sha256,
            "generation": generation,
            "members_sha256": members_sha256,
            "receipt_sha256": receipt_sha256,
            "durable": durable,
        }
        with self._locked_file(create=False) as descriptor:
            records = self._read_records(descriptor)
            attempt, prior_receipt = self._last_attempt_and_receipt(records)
            if attempt is None or prior_receipt is not None:
                raise JournalError("there is no unresolved native attempt")
            expected_members = _members_sha256(attempt["members"])
            if (
                not isinstance(durable, bool)
                or not durable
                or isinstance(now_ns, bool)
                or not isinstance(now_ns, int)
                or isinstance(deadline_ns, bool)
                or not isinstance(deadline_ns, int)
                or (not allow_expired and deadline_ns <= now_ns)
                or request_id != attempt["request_id"]
                or isinstance(sequence, bool)
                or not isinstance(sequence, int)
                or sequence != attempt["sequence"]
                or deadline_ns != attempt["deadline_ns"]
                or manifest_sha256 != attempt["manifest_sha256"]
                or isinstance(generation, bool)
                or not isinstance(generation, int)
                or generation != attempt["generation"]
                or members_sha256 != expected_members
                or not _is_digest(receipt_sha256)
            ):
                raise JournalError("native receipt does not bind the pending attempt")
            self._append_record(descriptor, records, "receipt", receipt)

    def mark_unknown(self, *, request_id: str, reason: str) -> RecoveryObligation:
        """Persist an unknown result and block automatic replay or redelivery."""

        if not isinstance(reason, str) or not reason or len(reason) > 128:
            raise JournalError("invalid recovery reason")
        with self._locked_file(create=False) as descriptor:
            records = self._read_records(descriptor)
            attempt, receipt = self._last_attempt_and_receipt(records)
            if attempt is None or receipt is not None or request_id != attempt["request_id"]:
                raise JournalError("unknown result does not match a pending attempt")
            self._append_record(
                descriptor,
                records,
                "unknown",
                {"request_id": request_id, "sequence": attempt["sequence"], "reason": reason},
            )
            return RecoveryObligation(request_id, attempt["sequence"], "UNKNOWN", reason)

    def recovery_obligations(self) -> tuple[RecoveryObligation, ...]:
        """Return unresolved operations, recording interrupted attempts as unknown."""

        if self._recovery_marker.exists():
            raise JournalCorrupt("journal corruption requires owner reconciliation")
        if not self._journal.exists():
            return ()
        try:
            with self._locked_file(create=False) as descriptor:
                if self._recovery_marker.exists():
                    raise JournalCorrupt(
                        "journal corruption requires owner reconciliation"
                    )
                records = self._read_records(descriptor)
                attempt, receipt = self._last_attempt_and_receipt(records)
                if attempt is None or receipt is not None:
                    return ()
                unknown = self._last_unknown(records, attempt["request_id"])
                if unknown is None:
                    reason = "interrupted_attempt"
                    self._append_record(
                        descriptor,
                        records,
                        "unknown",
                        {
                            "request_id": attempt["request_id"],
                            "sequence": attempt["sequence"],
                            "reason": reason,
                        },
                    )
                else:
                    reason = unknown["reason"]
                return (
                    RecoveryObligation(
                        attempt["request_id"], attempt["sequence"], "UNKNOWN", reason
                    ),
                )
        except JournalCorrupt:
            self._write_recovery_marker("journal_corrupt")
            raise

    def recovery_attempt(self, request_id: str) -> Mapping[str, Any]:
        """Load the validated durable attempt for an unresolved request."""

        if self._recovery_marker.exists():
            raise JournalCorrupt("journal corruption requires owner reconciliation")
        with self._locked_file(create=False) as descriptor:
            if self._recovery_marker.exists():
                raise JournalCorrupt("journal corruption requires owner reconciliation")
            records = self._read_records(descriptor)
            attempt, receipt = self._last_attempt_and_receipt(records)
            unknown = self._last_unknown(records, request_id)
            if (
                attempt is None
                or receipt is not None
                or attempt["request_id"] != request_id
                or unknown is None
            ):
                raise JournalError("no matching export recovery obligation")
            return dict(attempt)

    def _validate_directory(self) -> None:
        try:
            metadata = os.lstat(self.directory)
        except OSError as error:
            raise JournalError("journal directory is unavailable") from error
        if (
            not stat.S_ISDIR(metadata.st_mode)
            or metadata.st_uid != os.geteuid()
            or stat.S_IMODE(metadata.st_mode) & 0o077
        ):
            raise JournalError("journal directory is not owner-private")

    def _locked_file(self, *, create: bool):
        class LockedFile:
            def __init__(inner, owner: OwnerPrivateLifecycleJournal) -> None:
                inner.owner = owner
                inner.descriptor = -1

            def __enter__(inner) -> int:
                flags = os.O_RDWR | os.O_APPEND | getattr(os, "O_NOFOLLOW", 0)
                if create:
                    flags |= os.O_CREAT
                try:
                    inner.descriptor = os.open(inner.owner._journal, flags, 0o600)
                    metadata = os.fstat(inner.descriptor)
                    if (
                        not stat.S_ISREG(metadata.st_mode)
                        or metadata.st_uid != os.geteuid()
                        or stat.S_IMODE(metadata.st_mode) & 0o077
                        or metadata.st_nlink != 1
                    ):
                        os.close(inner.descriptor)
                        inner.descriptor = -1
                        raise JournalCorrupt("journal file is not owner-private")
                    fcntl.flock(inner.descriptor, fcntl.LOCK_EX)
                    return inner.descriptor
                except FileNotFoundError as error:
                    raise JournalError("journal has no dispatched attempt") from error
                except OSError as error:
                    if error.errno in (errno.ELOOP, errno.EACCES, errno.EPERM):
                        raise JournalCorrupt("journal file cannot be opened safely") from error
                    raise JournalError("journal file is unavailable") from error

            def __exit__(inner, _kind, _value, _traceback) -> None:
                if inner.descriptor >= 0:
                    fcntl.flock(inner.descriptor, fcntl.LOCK_UN)
                    os.close(inner.descriptor)

        return LockedFile(self)

    def _read_records(self, descriptor: int) -> list[dict[str, Any]]:
        os.lseek(descriptor, 0, os.SEEK_SET)
        chunks = bytearray()
        while True:
            block = os.read(descriptor, 65536)
            if not block:
                break
            chunks.extend(block)
            if len(chunks) > _MAX_JOURNAL_BYTES:
                raise self._corrupt("journal exceeds its size limit")
        if not chunks:
            return []
        if not chunks.endswith(b"\n"):
            raise self._corrupt("journal ends with an incomplete record")
        records: list[dict[str, Any]] = []
        previous = "0" * 64
        for line in chunks.splitlines():
            try:
                item = json.loads(line)
                if not isinstance(item, dict) or set(item) != {
                    "event", "payload", "previous_sha256", "record_sha256"
                }:
                    raise ValueError("record shape")
                body = {
                    "event": item["event"],
                    "payload": item["payload"],
                    "previous_sha256": item["previous_sha256"],
                }
                if (
                    item["previous_sha256"] != previous
                    or canonical_json(item) != line
                    or not secrets.compare_digest(
                        item["record_sha256"], hashlib.sha256(canonical_json(body)).hexdigest()
                    )
                ):
                    raise ValueError("record digest")
                if item["event"] not in {"attempt", "receipt", "unknown"}:
                    raise ValueError("event kind")
                if not isinstance(item["payload"], dict):
                    raise ValueError("record payload")
                self._validate_history_transition(records, item)
                previous = item["record_sha256"]
                records.append(item)
            except (UnicodeDecodeError, json.JSONDecodeError, TypeError, KeyError, ValueError):
                raise self._corrupt("journal record failed integrity validation") from None
        return records

    def _validate_history_transition(
        self, records: list[dict[str, Any]], record: dict[str, Any]
    ) -> None:
        """Reject hash-valid records that do not form a bound lifecycle."""

        event = record["event"]
        payload = record["payload"]
        attempt, receipt = self._last_attempt_and_receipt(records)
        try:
            if event == "attempt":
                deadline = payload.get("deadline_ns")
                if isinstance(deadline, bool) or not isinstance(deadline, int):
                    raise JournalError("invalid replayed deadline")
                normalized = self._validate_attempt(payload, now_ns=deadline - 1)
                previous_attempts = [
                    item["payload"] for item in records if item["event"] == "attempt"
                ]
                if any(
                    normalized["request_id"] == prior["request_id"]
                    or normalized["nonce"] == prior["nonce"]
                    for prior in previous_attempts
                ):
                    raise JournalError("replayed request or nonce")
                if attempt is not None:
                    self._validate_successor(attempt, receipt, normalized)
                elif records:
                    raise JournalError("attempt follows a non-attempt event")
                return

            if attempt is None:
                raise JournalError("lifecycle event has no attempt")
            if event == "receipt":
                if set(payload) != {
                    "request_id", "sequence", "deadline_ns", "manifest_sha256",
                    "generation", "members_sha256", "receipt_sha256", "durable",
                } or receipt is not None:
                    raise JournalError("receipt transition is invalid")
                expected_members = _members_sha256(attempt["members"])
                if (
                    not isinstance(payload["request_id"], str)
                    or isinstance(payload["sequence"], bool)
                    or not isinstance(payload["sequence"], int)
                    or isinstance(payload["deadline_ns"], bool)
                    or not isinstance(payload["deadline_ns"], int)
                    or isinstance(payload["generation"], bool)
                    or not isinstance(payload["generation"], int)
                    or not isinstance(payload["manifest_sha256"], str)
                    or not isinstance(payload["members_sha256"], str)
                    or payload["request_id"] != attempt["request_id"]
                    or payload["sequence"] != attempt["sequence"]
                    or payload["deadline_ns"] != attempt["deadline_ns"]
                    or payload["manifest_sha256"] != attempt["manifest_sha256"]
                    or payload["generation"] != attempt["generation"]
                    or payload["members_sha256"] != expected_members
                    or not _is_digest(payload["receipt_sha256"])
                    or payload["durable"] is not True
                ):
                    raise JournalError("receipt binding is invalid")
                return

            if set(payload) != {"request_id", "sequence", "reason"}:
                raise JournalError("unknown transition fields are invalid")
            if (
                receipt is not None
                or self._last_unknown(records, attempt["request_id"]) is not None
                or payload["request_id"] != attempt["request_id"]
                or payload["sequence"] != attempt["sequence"]
                or not isinstance(payload["reason"], str)
                or not payload["reason"]
                or len(payload["reason"]) > 128
            ):
                raise JournalError("unknown transition is invalid")
        except (JournalError, KeyError, TypeError, ValueError) as error:
            raise self._corrupt("journal lifecycle transition failed validation") from error

    def _append_record(
        self,
        descriptor: int,
        records: list[dict[str, Any]],
        event: str,
        payload: dict[str, Any],
    ) -> None:
        previous = records[-1]["record_sha256"] if records else "0" * 64
        body = {"event": event, "payload": payload, "previous_sha256": previous}
        record = {**body, "record_sha256": hashlib.sha256(canonical_json(body)).hexdigest()}
        data = canonical_json(record) + b"\n"
        if os.fstat(descriptor).st_size + len(data) > _MAX_JOURNAL_BYTES:
            raise JournalError("journal capacity is exhausted")
        view = memoryview(data)
        try:
            while view:
                written = os.write(descriptor, view)
                if written <= 0:
                    raise JournalError("journal append failed")
                view = view[written:]
            os.fsync(descriptor)
            self._fsync_completed = True
            self._sync_directory()
        except (OSError, JournalError) as error:
            self._write_recovery_marker("journal_append_uncertain")
            if isinstance(error, JournalError):
                raise
            raise JournalError("journal append failed") from error
        records.append(record)

    @staticmethod
    def _last_attempt_and_receipt(
        records: list[dict[str, Any]],
    ) -> tuple[dict[str, Any] | None, dict[str, Any] | None]:
        attempt = None
        receipt = None
        for record in records:
            if record["event"] == "attempt":
                attempt = record["payload"]
                receipt = None
            elif record["event"] == "receipt" and attempt is not None:
                receipt = record["payload"]
        return attempt, receipt

    @staticmethod
    def _last_unknown(
        records: list[dict[str, Any]], request_id: str
    ) -> dict[str, Any] | None:
        result = None
        for record in records:
            if record["event"] == "attempt":
                result = None
            elif record["event"] == "unknown" and record["payload"].get("request_id") == request_id:
                result = record["payload"]
            elif record["event"] == "receipt" and record["payload"].get("request_id") == request_id:
                result = None
        return result

    def _validate_attempt(self, value: Mapping[str, Any], *, now_ns: int) -> dict[str, Any]:
        if not isinstance(value, Mapping) or set(value) != _ATTEMPT_FIELDS:
            raise JournalError("native attempt fields are invalid")
        result = dict(value)
        for key in _ATTEMPT_FIELDS - {"sequence", "deadline_ns", "generation", "members"}:
            item = result[key]
            if not isinstance(item, str) or not item or len(item) > 512:
                raise JournalError("native attempt binding is invalid")
        for key in _DIGEST_FIELDS:
            if not _is_digest(result[key]):
                raise JournalError("native attempt digest is invalid")
        if (
            isinstance(now_ns, bool)
            or not isinstance(now_ns, int)
            or isinstance(result["deadline_ns"], bool)
            or not isinstance(result["deadline_ns"], int)
            or result["deadline_ns"] <= now_ns
            or isinstance(result["sequence"], bool)
            or not isinstance(result["sequence"], int)
            or result["sequence"] < 1
            or isinstance(result["generation"], bool)
            or not isinstance(result["generation"], int)
            or result["generation"] < 0
            or result["operation"] not in {
                "readiness", "hello", "consent", "admit", "stage", "inspect", "export", "cleanup"
            }
            or not _valid_members(result["members"])
        ):
            raise JournalError("native attempt values are invalid or expired")
        return result

    @staticmethod
    def _validate_successor(
        previous: dict[str, Any], receipt: dict[str, Any] | None, current: dict[str, Any]
    ) -> None:
        if receipt is None:
            raise JournalError("unresolved native operation requires reconciliation")
        immutable_fields = (*_BINDING_FIELDS, "manifest_sha256", "generation", "members")
        if any(previous[field] != current[field] for field in immutable_fields):
            raise JournalError("successor changed immutable session or export binding")
        if current["connection_id"] == previous["connection_id"]:
            # A continuing connection may issue the next sequence without changing its ID.
            pass
        if current["sequence"] != previous["sequence"] + 1:
            raise JournalError("native request sequence is not consecutive")
        if current["request_id"] == previous["request_id"] or current["nonce"] == previous["nonce"]:
            raise JournalError("native request or nonce was replayed")

    def _corrupt(self, message: str) -> JournalCorrupt:
        self._write_recovery_marker("journal_corrupt")
        return JournalCorrupt(message)

    def _write_recovery_marker(self, reason: str) -> None:
        payload = canonical_json({"status": "UNKNOWN", "reason": reason}) + b"\n"
        try:
            descriptor = os.open(
                self._recovery_marker,
                os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0),
                0o600,
            )
        except FileExistsError:
            # An earlier attempt may have created this marker before syncing its directory entry.
            self._sync_directory()
            return
        except OSError as error:
            raise JournalCorrupt("could not persist journal recovery marker") from error
        try:
            view = memoryview(payload)
            while view:
                written = os.write(descriptor, view)
                if written <= 0:
                    raise JournalCorrupt("could not write journal recovery marker")
                view = view[written:]
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
        self._sync_directory()

    def _sync_directory(self) -> None:
        descriptor = os.open(
            self.directory,
            os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0),
        )
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)


def _valid_members(value: Any) -> bool:
    if not isinstance(value, list) or not value:
        return False
    seen: set[str] = set()
    for member in value:
        if not isinstance(member, dict) or set(member) != {"path", "size", "sha256"}:
            return False
        path = member["path"]
        if (
            not isinstance(path, str)
            or not path
            or path.startswith("/")
            or any(part in {"", ".", ".."} for part in path.split("/"))
            or path in seen
            or isinstance(member["size"], bool)
            or not isinstance(member["size"], int)
            or member["size"] < 0
            or not _is_digest(member["sha256"])
        ):
            return False
        seen.add(path)
    return True


def _is_digest(value: Any) -> bool:
    return (
        isinstance(value, str)
        and len(value) == 64
        and all(character in "0123456789abcdef" for character in value)
    )


def _members_sha256(members: Any) -> str:
    """Match the native export-members digest over the ordered member array."""

    return hashlib.sha256(
        _MEMBERS_DIGEST_DOMAIN + canonical_json(members)
    ).hexdigest()
