"""Run the attended, single-forward Readiness exchange."""

import json
import os
import re
import secrets
from pathlib import Path

from . import _evidence_storage
from .readiness_probe import AttemptRunner, ProbeError, compact, require
from .readiness_probe_session import ForwardSession


_FORWARD_RECORD = re.compile(r"readiness-b1-forward-([a-f0-9]{32})-([a-z-]+)\.json")


def _require_closed_forward_obligations(directory):
    fd = _evidence_storage._directory_descriptor(directory)
    try:
        names = os.listdir(fd)
    finally:
        os.close(fd)
    require(len(names) <= 256, "ResourceLimitExceeded", "Transport")
    attempts = {}
    for name in names:
        if not name.startswith("readiness-b1-forward-"):
            continue
        match = _FORWARD_RECORD.fullmatch(name)
        require(match is not None, "IncompleteEvidence", "Transport")
        attempt, state = match.groups()
        attempts.setdefault(attempt, set()).add(state)
    for attempt, states in attempts.items():
        require({"creation-pending", "cleanup-pending", "closed"} <= states,
                "IntegrityConflict", "Transport")
        bindings = []
        try:
            for state in ("creation-pending", "cleanup-pending", "closed"):
                raw = _evidence_storage._read_private_file(
                    directory, f"readiness-b1-forward-{attempt}-{state}.json",
                )
                require(len(raw) <= 4096, "ResourceLimitExceeded", "Transport")
                event = json.loads(raw)
                require(event["state"] == state and event["session"] == attempt,
                        "IntegrityConflict", "Transport")
                bindings.append(tuple(event[key] for key in ("target", "build", "local", "remote")))
        except (KeyError, TypeError, UnicodeError, json.JSONDecodeError):
            raise ProbeError("IncompleteEvidence", "Transport") from None
        require(bindings[0] == bindings[1] == bindings[2], "IntegrityConflict", "Transport")


def run_readiness_exchange(
    adapter, *, target, build, session_id, local, remote, started, deadline,
    clock, outcomes_directory, receipts, ids, discovery_attempt, references,
    arm_on_device, confirm_discovery, approve_uid,
):
    """Run the transport phase after admission and before the C2 checkpoint.

    Owner callbacks operate the on-device controls and respect the supplied
    host deadline. The confirmation returns the completed Android observation.
    UID approval returns the exact value the owner approved and entered.
    An interruption can leave an open record for the bound tuple. Only the
    current session may use its verified in-memory ownership to remove it.
    """
    directory = Path(outcomes_directory)

    def record(event):
        name = f"readiness-b1-forward-{session_id}-{event['state']}.json"
        temporary = f".readiness-forward-{secrets.token_hex(16)}.tmp"
        try:
            fd = _evidence_storage._directory_descriptor(directory)
            try:
                _evidence_storage._publish_no_replace(directory, temporary, name, compact(event))
            finally:
                try:
                    os.unlink(temporary, dir_fd=fd)
                except FileNotFoundError:
                    pass
                finally:
                    os.close(fd)
        except Exception:
            raise ProbeError("IncompleteEvidence", "Transport") from None

    # Leave the final minute of the ordinary session for restoration.
    operation_deadline = deadline - 60
    session = ForwardSession(
        adapter, target, build, session_id, local, remote, started, deadline,
        clock=clock, obligation=record, operation_deadline=operation_deadline,
    )
    with _evidence_storage._stream_lock(directory, lock_name=".readiness-forward.lock"):
        _require_closed_forward_obligations(directory)
        session.check_time(operation_deadline)
        return _exchange(session, operation_deadline, discovery_attempt, ids, references,
                         receipts, arm_on_device, confirm_discovery, approve_uid)


def _exchange(session, operation_deadline, discovery_attempt, ids, references,
              receipts, arm_on_device, confirm_discovery, approve_uid):
    clock = session.clock
    try:
        session.create()
        armed = clock()
        discovery_deadline = min(armed + 5, operation_deadline)
        session.call(arm_on_device, deadline=discovery_deadline)
        session.arm(discovery_attempt, armed)
        host_started = clock()
        transport = session.open_discovery_transport()
        try:
            response = transport.read(1, discovery_deadline)
            host_finished = clock()
            require(response == b"", "IntegrityConflict", "Transport")
        finally:
            transport.close(min(armed + 6, operation_deadline + 1))
        observation = session.call(confirm_discovery, deadline=operation_deadline)
        session.correlate(observation, host_started, host_finished, 0, True)
        uid = session.call(approve_uid, observation.uid, deadline=operation_deadline)
        session.enforce(uid, owner_approved=type(uid) is int and uid == observation.uid)
        request_deadline = session.phase_deadline(limit=operation_deadline)
        transport = session.open_readiness_transport()
        try:
            return AttemptRunner(receipts, clock).run(ids, transport, request_deadline, references)
        finally:
            # Also release if AttemptRunner fails before entering its I/O block.
            transport.close(request_deadline + 1)
    finally:
        if session.owned:
            session.cleanup()
