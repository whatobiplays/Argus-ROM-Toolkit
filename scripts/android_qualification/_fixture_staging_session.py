"""Coordinate owner journaling with an authenticated native XPC session.

The transport owns the live XPC connection and authenticates the installed
service and broker process identities. Python persists request attempts before
calling it and records completion only from a receipt queried through that
authenticated connection. No subprocess JSON is accepted as receipt authority.
"""

from __future__ import annotations

from dataclasses import dataclass
import base64
import binascii
import hashlib
import json
import os
import stat
import threading
import time
from typing import Callable, Mapping, Protocol

from . import fixture_oracle
from ._fixture_staging_lifecycle import (
    JournalError,
    OwnerPrivateLifecycleJournal,
    _is_digest,
    _members_sha256,
)
from .fixture_oracle import canonical_json


_AUTHENTICATED_XPC_SEAL = object()
_CLIENT_CONSTRUCTION_SEAL = object()
_PREPARED_XPC_SEAL = object()


def _receipt_matches_attempt(
    attempt: Mapping[str, object], receipt: object
) -> bool:
    """Validate the complete durable receipt binding for one journal attempt."""

    required_fields = {
        "schema_version", "status", "code", "request_id", "session_id",
        "service_boot_id", "sequence", "deadline_ns", "manifest_sha256",
        "generation", "authorization_sha256", "members", "members_sha256",
        "member_count", "frame_sha256", "receipt_sha256", "receipt_path",
        "durable",
    }
    if not isinstance(receipt, Mapping) or set(receipt) != required_fields:
        return False
    members = attempt.get("members")
    if not isinstance(members, list):
        return False
    if (
        type(receipt["schema_version"]) is not int
        or receipt["schema_version"] != 1
        or receipt["status"] != "VERIFIED_RECEIVER_COMPLETION"
        or receipt["code"] != "BROKER_RECEIVER_RECEIPT_DURABLE"
        or receipt["request_id"] != attempt.get("request_id")
        or receipt["session_id"] != attempt.get("session_id")
        or receipt["service_boot_id"] != attempt.get("service_boot_id")
        or type(receipt["sequence"]) is not int
        or receipt["sequence"] != attempt.get("sequence")
        or type(receipt["deadline_ns"]) is not int
        or receipt["deadline_ns"] != attempt.get("deadline_ns")
        or receipt["manifest_sha256"] != attempt.get("manifest_sha256")
        or type(receipt["generation"]) is not int
        or receipt["generation"] != attempt.get("generation")
        or receipt["authorization_sha256"] != attempt.get("authorization_sha256")
        or receipt["members"] != members
        or type(receipt["member_count"]) is not int
        or receipt["member_count"] != len(members)
        or not _is_digest(receipt["members_sha256"])
        or receipt["members_sha256"] != _members_sha256(members)
        or not _is_digest(receipt["frame_sha256"])
        or not _is_digest(receipt["receipt_sha256"])
        or not isinstance(receipt["receipt_path"], str)
        or not os.path.isabs(receipt["receipt_path"])
        or "\0" in receipt["receipt_path"]
        or receipt["durable"] is not True
    ):
        return False

    digest_payload = {
        key: value
        for key, value in receipt.items()
        if key not in {
            "service_boot_id", "sequence", "receipt_sha256", "receipt_path"
        }
    }
    try:
        expected_receipt_sha256 = hashlib.sha256(
            canonical_json(
                digest_payload,
                maximum_bytes=fixture_oracle.MAX_RECEIPT_DOCUMENT_BYTES,
            )
        ).hexdigest()
    except (TypeError, ValueError):
        return False
    return receipt["receipt_sha256"] == expected_receipt_sha256


@dataclass(frozen=True)
class AuthenticatedXPCReply:
    """A response decoded from a peer-authenticated native XPC message."""

    service_identity: str
    broker_identity: str
    receipt: Mapping[str, object]
    _authenticated_xpc: object


@dataclass(frozen=True)
class PreparedOwnerExport:
    """Native prepared export whose authenticated broker session is still open."""

    attempt: Mapping[str, object]
    signed_request: Mapping[str, object]
    workflow: tuple[Mapping[str, object], ...]
    continuation: object
    _authenticated_xpc: object


class NativeXPCSessionTransport(Protocol):
    """Narrow native boundary for dispatch and receipt-only recovery queries.

    Implementations must attach already-open descriptors to XPC messages,
    validate the remote code identity on each connection, and return replies
    only after validating the expected service and broker peer identities.
    """

    def dispatch_export(
        self,
        attempt: Mapping[str, object],
        signed_request: Mapping[str, object],
        source_fds: Mapping[str, int],
        workflow: tuple[Mapping[str, object], ...] = (),
        documents: Mapping[str, object] | None = None,
        delivery_fd: int | None = None,
    ) -> AuthenticatedXPCReply: ...

    def prepare_export(
        self,
        intent: Mapping[str, object],
        source_fds: Mapping[str, int],
        documents: Mapping[str, object],
        delivery_fd: int,
    ) -> PreparedOwnerExport: ...

    def dispatch_prepared_export(
        self,
        prepared: PreparedOwnerExport,
        source_fds: Mapping[str, int],
        documents: Mapping[str, object],
        delivery_fd: int,
    ) -> AuthenticatedXPCReply: ...

    def query_export_receipt(
        self, attempt: Mapping[str, object]
    ) -> AuthenticatedXPCReply | None: ...


class OwnerSessionExportClient:
    """Dispatch exports once and reconcile uncertain outcomes without replay."""

    def __init__(
        self,
        journal: OwnerPrivateLifecycleJournal,
        transport: NativeXPCSessionTransport,
        *,
        service_identity: str,
        broker_identity: str,
        _construction_seal: object,
    ) -> None:
        if _construction_seal is not _CLIENT_CONSTRUCTION_SEAL:
            raise TypeError("use a verified installation or the test-only constructor")
        if not service_identity or not broker_identity:
            raise ValueError("installed XPC peer identities are required")
        self._journal = journal
        self._transport = transport
        self._service_identity = service_identity
        self._broker_identity = broker_identity
        self._installation = None
        self._verified_export_attempt = None
        self._verified_export_reply = None
        self._prepared_export = None
        self._clock_ns = time.monotonic_ns
        self._session_operation_lock = threading.Lock()
        self._preparation_in_progress = False
        self._dispatch_in_progress = False

    @classmethod
    def from_verified_installation(
        cls,
        journal: OwnerPrivateLifecycleJournal,
        transport: NativeXPCSessionTransport,
        installation,
    ) -> "OwnerSessionExportClient":
        """Bind the client to the sealed native installation selected by probes."""

        from ._fixture_staging_native import (
            InstalledBrokerXPCSessionTransport,
            VerifiedNativeInstallation,
        )

        if (
            not isinstance(installation, VerifiedNativeInstallation)
            or not installation.operation_enabled
            or type(transport) is not InstalledBrokerXPCSessionTransport
            or transport.installation != installation
            or transport.installation._seal is not installation._seal
        ):
            raise JournalError("verified native session installation is required")
        client = cls(
            journal,
            transport,
            service_identity=installation.installation_id,
            broker_identity=installation.broker_revision,
            _construction_seal=_CLIENT_CONSTRUCTION_SEAL,
        )
        client._installation = installation
        return client

    @classmethod
    def _for_testing(
        cls,
        journal: OwnerPrivateLifecycleJournal,
        transport: NativeXPCSessionTransport,
        installation=None,
        *,
        service_identity: str | None = None,
        broker_identity: str | None = None,
        clock_ns: Callable[[], int] | None = None,
    ) -> "OwnerSessionExportClient":
        """Create a synthetic transport client for isolated protocol tests only."""

        if installation is not None:
            from ._fixture_staging_native import VerifiedNativeInstallation

            if not isinstance(installation, VerifiedNativeInstallation):
                raise TypeError("test installation must use the sealed test fixture")
            service_identity = installation.installation_id
            broker_identity = installation.broker_revision
        if not service_identity or not broker_identity:
            raise TypeError("synthetic tests must provide explicit fixture identities")
        client = cls(
            journal,
            transport,
            service_identity=service_identity,
            broker_identity=broker_identity,
            _construction_seal=_CLIENT_CONSTRUCTION_SEAL,
        )
        client._installation = installation
        client._test_transport = True
        client._synthetic_installation = True
        client._clock_ns = clock_ns or (lambda: 200)
        return client

    def dispatch_export(
        self,
        attempt: Mapping[str, object],
        signed_request: Mapping[str, object],
        source_fds: Mapping[str, int],
        *,
        workflow: tuple[Mapping[str, object], ...] = (),
        documents: Mapping[str, object] | None = None,
        delivery_fd: int | None = None,
    ) -> AuthenticatedXPCReply:
        """Persist ATTEMPT, send descriptor attachments once, then journal ACK."""

        with self._session_operation_lock:
            prepared = self._prepared_export
            if prepared is None:
                if self._preparation_in_progress or self._dispatch_in_progress:
                    raise JournalError("another owner session operation is in progress")
                self._dispatch_in_progress = True
        if prepared is not None:
            if (
                self._prepared_value(prepared, "attempt") != attempt
                or self._prepared_value(prepared, "signed_request") != signed_request
            ):
                raise JournalError("dispatch differs from the native prepared export")
            return self.dispatch_prepared_export(
                prepared,
                source_fds,
                documents or {},
                delivery_fd,
            )
        try:
            now_ns = self._clock_ns()
            self._validate_signed_request(attempt, signed_request)
            if self._installation is not None and not getattr(self, "_test_transport", False):
                self._validate_workflow(attempt, workflow, signed_request)
            if delivery_fd is None and self._installation is not None and not getattr(
                self, "_test_transport", False
            ):
                raise JournalError("private durable delivery descriptor is required")
            response = self._journal.dispatch(
                attempt,
                now_ns=now_ns,
                send=lambda: self._as_mapping(
                    self._dispatch_transport(
                        attempt, signed_request, source_fds, workflow, documents, delivery_fd
                    )
                ),
                verify_receipt=lambda expected, response: self._verify_reply(
                    expected, response, delivery_fd=delivery_fd
                ),
                clock_ns=self._clock_ns,
            )
            reply = response.get("_xpc_reply")
            if not isinstance(reply, AuthenticatedXPCReply):
                raise JournalError("authenticated XPC reply was not retained")
            self._verified_export_attempt = dict(attempt)
            self._verified_export_reply = reply
            return reply
        finally:
            with self._session_operation_lock:
                self._dispatch_in_progress = False

    def prepare_export(
        self,
        intent: Mapping[str, object],
        source_fds: Mapping[str, int],
        documents: Mapping[str, object],
        delivery_fd: int,
    ):
        """Ask the native broker to authenticate hello and prepare an export."""

        with self._session_operation_lock:
            if (
                self._prepared_export is not None
                or self._preparation_in_progress
                or self._dispatch_in_progress
            ):
                raise JournalError("an authenticated broker session is already reserved")
            self._preparation_in_progress = True
        try:
            prepared = self._prepare_export_once(
                intent, source_fds, documents, delivery_fd
            )
            with self._session_operation_lock:
                self._prepared_export = prepared
            return prepared
        finally:
            with self._session_operation_lock:
                self._preparation_in_progress = False

    def _prepare_export_once(
        self,
        intent: Mapping[str, object],
        source_fds: Mapping[str, int],
        documents: Mapping[str, object],
        delivery_fd: int,
    ):
        """Perform one reserved broker preparation and validate its bindings."""

        if self._prepared_export is not None:
            raise JournalError("an authenticated broker session is already prepared")
        self._validate_export_inputs(
            intent,
            source_fds,
            documents,
            delivery_fd,
            require_open_descriptors=(
                self._installation is not None
                and not getattr(self, "_test_transport", False)
            ),
        )
        prepare = getattr(self._transport, "prepare_export", None)
        if not callable(prepare):
            raise JournalError("native broker prepare continuation is unavailable")
        try:
            prepared = prepare(intent, source_fds, documents, delivery_fd)
        except Exception as error:
            raise JournalError("native broker rejected export preparation") from error
        if prepared is None:
            raise JournalError("native broker returned no prepared export")
        attempt = self._prepared_value(prepared, "attempt")
        signed_request = self._prepared_value(prepared, "signed_request")
        workflow = self._prepared_value(prepared, "workflow")
        continuation = self._prepared_value(prepared, "continuation")
        if (
            not isinstance(attempt, Mapping)
            or not isinstance(signed_request, Mapping)
            or continuation is None
        ):
            raise JournalError("native broker prepared export is malformed")
        if self._installation is not None and not getattr(self, "_test_transport", False):
            if (
                not isinstance(prepared, PreparedOwnerExport)
                or prepared._authenticated_xpc is not _PREPARED_XPC_SEAL
                or not isinstance(workflow, tuple)
            ):
                raise JournalError("prepared export lacks authenticated session binding")
            for key, installation_key in (
                ("installation_id", "installation_id"),
                ("service_boot_id", "service_boot_id"),
                ("broker_revision", "broker_revision"),
                ("owner_key_id", "owner_key_id"),
            ):
                if attempt.get(key) != getattr(self._installation, installation_key):
                    raise JournalError("prepared export differs from verified installation")
            self._validate_workflow(attempt, workflow, signed_request)
        self._validate_signed_request(attempt, signed_request)
        if workflow:
            self._validate_workflow(attempt, workflow, signed_request)
        return prepared

    def prepare_and_dispatch_export(
        self,
        intent: Mapping[str, object],
        source_fds: Mapping[str, int],
        documents: Mapping[str, object],
        delivery_fd: int,
    ) -> AuthenticatedXPCReply:
        """Prepare through native hello, journal, then continue the same session."""

        prepared = self.prepare_export(intent, source_fds, documents, delivery_fd)
        attempt = self._prepared_value(prepared, "attempt")
        signed_request = self._prepared_value(prepared, "signed_request")
        return self.dispatch_export(
            attempt,
            signed_request,
            source_fds,
            workflow=self._prepared_value(prepared, "workflow") or (),
            documents=documents,
            delivery_fd=delivery_fd,
        )

    def dispatch_prepared_export(
        self,
        prepared,
        source_fds: Mapping[str, int],
        documents: Mapping[str, object],
        delivery_fd: int,
    ) -> AuthenticatedXPCReply:
        """Journal the broker-prepared attempt before one continuation dispatch."""

        with self._session_operation_lock:
            if self._prepared_export is not prepared or self._dispatch_in_progress:
                raise JournalError("prepared export is not owned by this client")
            self._prepared_export = None
            self._dispatch_in_progress = True
        try:
            return self._dispatch_prepared_export_once(
                prepared, source_fds, documents, delivery_fd
            )
        finally:
            with self._session_operation_lock:
                self._dispatch_in_progress = False

    def _dispatch_prepared_export_once(
        self,
        prepared,
        source_fds: Mapping[str, int],
        documents: Mapping[str, object],
        delivery_fd: int,
    ) -> AuthenticatedXPCReply:
        self._validate_export_inputs(
            {},
            source_fds,
            documents,
            delivery_fd,
            require_open_descriptors=(
                self._installation is not None
                and not getattr(self, "_test_transport", False)
            ),
        )
        attempt = self._prepared_value(prepared, "attempt")
        signed_request = self._prepared_value(prepared, "signed_request")
        if not isinstance(attempt, Mapping) or not isinstance(signed_request, Mapping):
            raise JournalError("prepared export is malformed")
        deadline_ns = attempt.get("deadline_ns")
        current_ns = self._clock_ns()
        if (
            isinstance(deadline_ns, bool)
            or not isinstance(deadline_ns, int)
            or deadline_ns <= 0
            or isinstance(current_ns, bool)
            or not isinstance(current_ns, int)
            or current_ns >= deadline_ns
        ):
            raise JournalError("prepared export deadline has expired")
        self._validate_signed_request(attempt, signed_request)
        if self._installation is not None and not getattr(self, "_test_transport", False):
            if (
                not isinstance(prepared, PreparedOwnerExport)
                or prepared._authenticated_xpc is not _PREPARED_XPC_SEAL
            ):
                raise JournalError("prepared export lacks authenticated session binding")
            self._validate_workflow(
                attempt, self._prepared_value(prepared, "workflow"), signed_request
            )
        dispatch = getattr(self._transport, "dispatch_prepared_export", None)
        if not callable(dispatch):
            raise JournalError("native broker dispatch continuation is unavailable")
        try:
            response = self._journal.dispatch(
                attempt,
                now_ns=current_ns,
                send=lambda: self._as_mapping(
                    dispatch(prepared, source_fds, documents, delivery_fd)
                ),
                verify_receipt=lambda expected, result: self._verify_reply(
                    expected, result, delivery_fd=delivery_fd
                ),
                clock_ns=self._clock_ns,
            )
        except Exception:
            self._prepared_export = None
            raise
        reply = response.get("_xpc_reply")
        if not isinstance(reply, AuthenticatedXPCReply):
            raise JournalError("authenticated XPC reply was not retained")
        self._verified_export_attempt = dict(attempt)
        self._verified_export_reply = reply
        self._prepared_export = None
        return reply

    @staticmethod
    def _prepared_value(prepared, key: str):
        if isinstance(prepared, Mapping):
            return prepared.get(key)
        return getattr(prepared, key, None)

    @staticmethod
    def _validate_export_inputs(
        intent, source_fds, documents, delivery_fd, *, require_open_descriptors=False
    ) -> None:
        if not isinstance(intent, Mapping):
            raise JournalError("export intent is malformed")
        if not isinstance(source_fds, Mapping) or not source_fds:
            raise JournalError("source descriptors are required")
        if any(
            not isinstance(path, str)
            or not path
            or isinstance(descriptor, bool)
            or not isinstance(descriptor, int)
            or descriptor < 0
            for path, descriptor in source_fds.items()
        ):
            raise JournalError("source descriptor mapping is malformed")
        if not isinstance(documents, Mapping):
            raise JournalError("export documents are malformed")
        if (
            isinstance(delivery_fd, bool)
            or not isinstance(delivery_fd, int)
            or delivery_fd < 0
        ):
            raise JournalError("private delivery descriptor is required")
        if require_open_descriptors:
            import fcntl
            import stat

            try:
                source_stats = {
                    descriptor: os.fstat(descriptor)
                    for descriptor in source_fds.values()
                }
                delivery_stat = os.fstat(delivery_fd)
                delivery_flags = fcntl.fcntl(delivery_fd, fcntl.F_GETFL)
            except OSError as error:
                raise JournalError("export descriptor is unavailable") from error
            if any(not stat.S_ISREG(info.st_mode) for info in source_stats.values()):
                raise JournalError("source descriptor must reference a regular file")
            if not stat.S_ISREG(delivery_stat.st_mode):
                raise JournalError("delivery descriptor must reference a regular file")
            if delivery_flags & os.O_ACCMODE == os.O_RDONLY:
                raise JournalError("delivery descriptor must be writable")
            source_inodes = {(info.st_dev, info.st_ino) for info in source_stats.values()}
            if (delivery_stat.st_dev, delivery_stat.st_ino) in source_inodes:
                raise JournalError("source and delivery descriptors must be distinct")

    def verify_and_admit(self, evidence):
        """Admit only evidence bound to this installed client's verified reply."""

        if (
            self._installation is None
            or getattr(self, "_test_transport", False)
            or getattr(self, "_synthetic_installation", False)
        ):
            raise JournalError("installed native admission authority is unavailable")
        from ._fixture_staging_export_evidence import ExportEvidenceV1

        attempt = self._verified_export_attempt
        reply = self._verified_export_reply
        if (
            not isinstance(attempt, Mapping)
            or not isinstance(reply, AuthenticatedXPCReply)
            or reply._authenticated_xpc is not _AUTHENTICATED_XPC_SEAL
            or not self._verify_reply(
                attempt, {"_xpc_reply": reply, "receipt": reply.receipt}
            )
        ):
            raise JournalError("authenticated native admission evidence is unavailable")
        expected = ExportEvidenceV1.from_native(attempt, reply.receipt)
        if evidence != expected:
            raise JournalError("native admission evidence differs from the verified reply")
        return evidence

    def _dispatch_transport(
        self, attempt, signed_request, source_fds, workflow, documents, delivery_fd
    ):
        if not workflow and delivery_fd is None:
            return self._transport.dispatch_export(attempt, signed_request, source_fds)
        return self._transport.dispatch_export(
            attempt, signed_request, source_fds, workflow, documents, delivery_fd
        )

    @staticmethod
    def _validate_workflow(attempt, workflow, signed_request):
        if not isinstance(workflow, tuple) or len(workflow) != 4:
            raise JournalError("production dispatch requires hello, admit, stage, and export")
        expected = ("hello", "admit", "stage", "export")
        if tuple(item.get("operation") for item in workflow) != expected:
            raise JournalError("native session operations are not in the required order")
        if workflow[-1] != signed_request:
            raise JournalError("workflow export differs from the journaled signed request")
        hello, admit, stage, export = workflow
        for request in (hello, admit, stage, export):
            if not isinstance(request, Mapping):
                raise JournalError("native session request is malformed")
        for key in (
            "installation_id", "service_boot_id", "broker_revision", "owner_key_id",
            "authorization_sha256",
        ):
            if hello.get(key) != attempt.get(key):
                raise JournalError("hello request differs from durable installation binding")
        for request in (admit, stage, export):
            freshness = OwnerSessionExportClient._decode_freshness(request)
            for key in (
                "installation_id", "service_boot_id", "broker_revision", "owner_key_id",
                "connection_id", "session_id", "authorization_sha256", "consent_sha256",
            ):
                if freshness.get(key) != attempt.get(key):
                    raise JournalError("session workflow freshness identities do not match")

    @staticmethod
    def _decode_freshness(request):
        encoded = request.get("freshness_envelope")
        if not isinstance(encoded, str):
            raise JournalError("signed freshness envelope is required")
        try:
            data = base64.b64decode(encoded, validate=True)
            value = json.loads(data)
        except (ValueError, binascii.Error) as error:
            raise JournalError("signed freshness envelope is invalid") from error
        if not isinstance(value, Mapping) or canonical_json(value) != data:
            raise JournalError("signed freshness envelope is not canonical")
        return value

    def recover_export(
        self, attempt: Mapping[str, object]
    ) -> AuthenticatedXPCReply | None:
        """Reconcile a receipt using OS time; never resend an uncertain export."""

        if not isinstance(attempt, Mapping):
            raise JournalError("native recovery attempt is invalid")
        request_id = attempt.get("request_id")
        obligations = self._journal.recovery_obligations()
        if not any(item.request_id == request_id for item in obligations):
            raise JournalError("no matching export recovery obligation")
        durable_attempt = self._journal.recovery_attempt(request_id)
        try:
            supplied_bytes = canonical_json(dict(attempt))
            durable_bytes = canonical_json(dict(durable_attempt))
        except (TypeError, ValueError) as error:
            raise JournalError("native recovery attempt is invalid") from error
        if supplied_bytes != durable_bytes:
            raise JournalError("caller attempt differs from the durable recovery binding")

        reply = self._transport.query_export_receipt(durable_attempt)
        if reply is None:
            return None
        if not self._verify_reply(
            durable_attempt, {"_xpc_reply": reply, "receipt": reply.receipt}
        ):
            raise JournalError("native receipt query returned an unauthenticated reply")
        receipt = reply.receipt
        observed_ns = self._clock_ns()
        deadline_ns = durable_attempt.get("deadline_ns")
        if (
            isinstance(observed_ns, bool)
            or not isinstance(observed_ns, int)
            or isinstance(deadline_ns, bool)
            or not isinstance(deadline_ns, int)
        ):
            raise JournalError("native receipt reconciliation clock or deadline is invalid")
        record_receipt = (
            self._journal.record_native_receipt
            if observed_ns < deadline_ns
            else self._journal._record_reconciled_native_receipt
        )
        receipt_time_key = "now_ns" if observed_ns < deadline_ns else "observed_ns"
        record_receipt(
            request_id=receipt["request_id"],
            sequence=receipt["sequence"],
            deadline_ns=receipt["deadline_ns"],
            manifest_sha256=receipt["manifest_sha256"],
            generation=receipt["generation"],
            members_sha256=receipt["members_sha256"],
            receipt_sha256=receipt["receipt_sha256"],
            durable=receipt["durable"],
            **{receipt_time_key: observed_ns},
        )
        return reply

    @staticmethod
    def _as_mapping(reply: AuthenticatedXPCReply) -> Mapping[str, object]:
        return {"_xpc_reply": reply, "receipt": reply.receipt}

    @staticmethod
    def _validate_signed_request(
        attempt: Mapping[str, object], signed_request: Mapping[str, object]
    ) -> None:
        if not isinstance(signed_request, Mapping):
            raise JournalError("owner-signed native request is required")
        if attempt.get("operation") != "export" or signed_request.get("operation") != "export":
            raise JournalError("export dispatch accepts only the export operation")
        digest = hashlib.sha256(canonical_json(signed_request)).hexdigest()
        if digest != attempt.get("request_sha256"):
            raise JournalError("signed request differs from durable attempt binding")
        for request_key, attempt_key in (
            ("operation", "operation"),
            ("request_id", "request_id"),
            ("session_id", "session_id"),
            ("service_boot_id", "service_boot_id"),
            ("sequence", "sequence"),
            ("nonce", "nonce"),
            ("deadline_ns", "deadline_ns"),
            ("manifest_sha256", "manifest_sha256"),
            ("authorization_sha256", "authorization_sha256"),
            ("generation", "generation"),
            ("members", "members"),
        ):
            if signed_request.get(request_key) != attempt.get(attempt_key):
                raise JournalError("signed request does not bind the durable attempt")
        freshness = OwnerSessionExportClient._decode_freshness(signed_request)
        for signed_key, attempt_key in (
            ("installation_id", "installation_id"),
            ("service_boot_id", "service_boot_id"),
            ("broker_revision", "broker_revision"),
            ("owner_key_id", "owner_key_id"),
            ("connection_id", "connection_id"),
            ("session_id", "session_id"),
            ("request_id", "request_id"),
            ("operation", "operation"),
            ("sequence", "sequence"),
            ("deadline_ns", "deadline_ns"),
            ("authorization_sha256", "authorization_sha256"),
            ("consent_sha256", "consent_sha256"),
        ):
            if freshness.get(signed_key) != attempt.get(attempt_key):
                raise JournalError("signed freshness differs from durable attempt identity")
        if not all(
            isinstance(signed_request.get(field), str)
            and signed_request[field]
            for field in ("freshness_envelope", "freshness_signature", "consent_signature")
        ):
            raise JournalError("signed freshness and consent fields are required")

    def _verify_reply(
        self,
        attempt: Mapping[str, object],
        response: Mapping[str, object],
        *,
        delivery_fd: int | None = None,
    ) -> bool:
        reply = response.get("_xpc_reply")
        if (
            not isinstance(reply, AuthenticatedXPCReply)
            or (
                reply._authenticated_xpc is not _AUTHENTICATED_XPC_SEAL
                and not (
                    (
                        getattr(self, "_test_transport", False)
                    )
                    and reply._authenticated_xpc is True
                )
            )
        ):
            return False
        if (
            reply.service_identity != self._service_identity
            or reply.broker_identity != self._broker_identity
            or reply.service_identity != attempt.get("installation_id")
            or reply.broker_identity != attempt.get("broker_revision")
        ):
            return False
        receipt = reply.receipt
        if not _receipt_matches_attempt(attempt, receipt):
            return False
        if delivery_fd is not None and not self._verify_delivered_frame(
            attempt, receipt, delivery_fd
        ):
            return False
        return True

    @staticmethod
    def _verify_delivered_frame(
        attempt: Mapping[str, object], receipt: Mapping[str, object], delivery_fd: int
    ) -> bool:
        """Bind the synced owner delivery bytes to member and frame digests."""

        members = attempt.get("members")
        if not isinstance(members, list):
            return False
        try:
            metadata = os.fstat(delivery_fd)
            expected_size = sum(member["size"] for member in members)
            if (
                not stat.S_ISREG(metadata.st_mode)
                or metadata.st_uid != os.getuid()
                or metadata.st_nlink != 1
                or stat.S_IMODE(metadata.st_mode) != 0o600
                or metadata.st_size != expected_size
            ):
                return False
            os.fsync(delivery_fd)
            header = canonical_json(
                {
                    "schema_version": 1,
                    "session_id": attempt["session_id"],
                    "manifest_sha256": attempt["manifest_sha256"],
                    "generation": attempt["generation"],
                    "members": members,
                }
            )
            frame_digest = hashlib.sha256()
            frame_digest.update(b"AQSNAP1\n")
            frame_digest.update(len(header).to_bytes(8, "big"))
            frame_digest.update(header)
            offset = 0
            for member in members:
                size = member["size"]
                if isinstance(size, bool) or not isinstance(size, int) or size < 0:
                    return False
                member_digest = hashlib.sha256()
                remaining = size
                while remaining:
                    chunk = os.pread(delivery_fd, min(64 * 1024, remaining), offset)
                    if not chunk:
                        return False
                    member_digest.update(chunk)
                    frame_digest.update(chunk)
                    offset += len(chunk)
                    remaining -= len(chunk)
                if member_digest.hexdigest() != member["sha256"]:
                    return False
            return frame_digest.hexdigest() == receipt.get("frame_sha256")
        except (KeyError, OSError, TypeError, ValueError):
            return False


@dataclass(frozen=True)
class OwnerExportDispatch:
    """Complete signed export request and open descriptors for public dispatch."""

    client: OwnerSessionExportClient
    attempt: Mapping[str, object]
    signed_request: Mapping[str, object]
    source_fds: Mapping[str, int]
    delivery_fd: int | None = None
    workflow: tuple[Mapping[str, object], ...] = ()
    documents: Mapping[str, object] | None = None

    def dispatch(self) -> AuthenticatedXPCReply:
        """Send once through the journaled client using the captured deadline."""

        stage_request = self.workflow[2] if len(self.workflow) == 4 else self.signed_request
        source_paths = stage_request.get("source_paths")
        if (
            not isinstance(source_paths, list)
            or len(source_paths) != len(self.source_fds)
            or set(source_paths) != set(self.source_fds)
        ):
            raise JournalError("signed source paths do not match descriptor attachments")
        descriptors = [self.source_fds[path] for path in source_paths]
        if len(set(descriptors)) != len(descriptors):
            raise JournalError("source descriptor attachment was reused")
        for descriptor in descriptors:
            if (
                isinstance(descriptor, bool)
                or not isinstance(descriptor, int)
                or descriptor < 0
                or not stat.S_ISREG(os.fstat(descriptor).st_mode)
            ):
                raise JournalError("source attachment is not an open regular-file descriptor")
        if self.delivery_fd is None and not getattr(
            self.client, "_test_transport", False
        ):
            raise JournalError("private durable delivery descriptor is required")
        if self.delivery_fd is not None:
            try:
                delivery = os.fstat(self.delivery_fd)
                offset = os.lseek(self.delivery_fd, 0, os.SEEK_CUR)
            except OSError as error:
                raise JournalError("private delivery descriptor is invalid") from error
            if (
                not stat.S_ISREG(delivery.st_mode)
                or delivery.st_uid != os.getuid()
                or delivery.st_nlink != 1
                or stat.S_IMODE(delivery.st_mode) != 0o600
                or delivery.st_size != 0
                or offset != 0
            ):
                raise JournalError("private delivery descriptor is not a new owner-only file")
        if self.workflow:
            self.client._validate_workflow(
                self.attempt, self.workflow, self.signed_request
            )
        return self.client.dispatch_export(
            self.attempt,
            self.signed_request,
            self.source_fds,
            workflow=self.workflow,
            documents=self.documents,
            delivery_fd=self.delivery_fd,
        )
