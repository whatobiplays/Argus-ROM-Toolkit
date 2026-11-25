"""Injected forward ownership and discovery correlation.

No implementation here invokes ADB. The caller supplies a reviewed adapter and
exact target/build identity. Discovery correlation is operational evidence under
the trusted-host model, not cryptographic proof of the connecting host.
"""
from dataclasses import dataclass
from enum import Enum
import re
from typing import Optional, Protocol
from .readiness_probe import require, ProbeError, HEX, Transport, uint

@dataclass(frozen=True)
class Discovery:
    """Private probe-source transcription, not independent OS evidence.

    Android elapsed endpoints must cover the five-second discovery window and
    may include its one-second release allowance. The six-second cap does not
    extend the five-second admission gate. Host and Android times stay separate;
    these source-bound values provide no cryptographic host authentication.
    """
    session: str
    attempt: str
    endpoint: str
    count: int
    uid: int
    android_started_ms: int
    android_finished_ms: int

    def __post_init__(self):
        require(uint(self.android_started_ms,64) and uint(self.android_finished_ms,64)
                and self.android_started_ms<=self.android_finished_ms
                and 5000<=self.android_finished_ms-self.android_started_ms<=6000,'IncompleteEvidence')


class _TransportPhase(Enum):
    """The two connections a qualification session may authorize."""

    DISCOVERY = 'discovery'
    READINESS = 'readiness'


@dataclass(frozen=True)
class _TransportPolicy:
    """Phase-specific admission, release and write permissions."""

    session_state: str
    opening_window_seconds: Optional[int]
    release_after_arm_seconds: Optional[int]
    release_after_phase_seconds: int
    writes_allowed: bool

    def opening_limit(self, armed):
        if self.opening_window_seconds is None:
            return None
        return armed+self.opening_window_seconds

    def release_deadline(self, armed, phase_deadline):
        if self.release_after_arm_seconds is not None:
            return armed+self.release_after_arm_seconds
        return phase_deadline+self.release_after_phase_seconds


_TRANSPORT_POLICIES = {
    _TransportPhase.DISCOVERY: _TransportPolicy('Armed',5,6,0,False),
    _TransportPhase.READINESS: _TransportPolicy('Enforcing',None,None,1,True),
}


class _TransportState(Enum):
    """Allowed states for one phase's single transport attempt."""

    NEW = 'new'
    AUTHORIZED = 'authorized'
    OPENING = 'opening'
    CONNECTING = 'connecting'
    OPENED = 'opened'
    OPENED_LATE = 'opened_late'
    UNCERTAIN = 'uncertain'
    CLOSED = 'closed'
    CLOSED_LATE = 'closed_late'
    CLOSED_UNQUALIFIED = 'closed_unqualified'


@dataclass
class _TransportLifecycle:
    """Own transport authorization and enforce one-way lifecycle transitions."""

    policy: _TransportPolicy
    state: _TransportState = _TransportState.NEW
    authorization: Optional[object] = None
    deadline: Optional[float] = None
    close_deadline: Optional[float] = None

    @property
    def attempted(self):
        return self.state is not _TransportState.NEW

    @property
    def opened(self):
        return self.state in {
            _TransportState.OPENED,
            _TransportState.OPENED_LATE,
            _TransportState.UNCERTAIN,
            _TransportState.CLOSED,
            _TransportState.CLOSED_LATE,
        }

    @property
    def admitted(self):
        return self.state in {
            _TransportState.OPENED,
            _TransportState.CLOSED,
        }

    @property
    def closed(self):
        return self.state in {
            _TransportState.CLOSED,
            _TransportState.CLOSED_LATE,
            _TransportState.CLOSED_UNQUALIFIED,
        }

    @property
    def has_release_obligation(self):
        return self.state in {
            _TransportState.AUTHORIZED,
            _TransportState.OPENING,
            _TransportState.CONNECTING,
            _TransportState.OPENED,
            _TransportState.OPENED_LATE,
            _TransportState.UNCERTAIN,
        }

    def authorize(self, token, *, deadline, close_deadline):
        require(self.state is _TransportState.NEW,'IntegrityConflict','Transport')
        self.state=_TransportState.AUTHORIZED
        self.authorization=token
        self.deadline=deadline
        self.close_deadline=close_deadline

    def consume(self, token, *, deadline):
        require(self.state is _TransportState.AUTHORIZED
                and self.authorization is token and self.deadline==deadline,
                'IntegrityConflict','Transport')
        self.authorization=None
        self.state=_TransportState.OPENING

    def mark_socket_created(self):
        if self.state is _TransportState.OPENING:
            self.state=_TransportState.CONNECTING

    def mark_opened(self, *, now, started, session_deadline):
        require(self.state in {
            _TransportState.OPENING,
            _TransportState.CONNECTING,
        },'IntegrityConflict','Transport')
        admitted=(
            self.deadline is not None
            and started<=now<self.deadline
            and now<session_deadline
        )
        self.state=(
            _TransportState.OPENED
            if admitted else _TransportState.OPENED_LATE
        )

    def mark_late(self):
        if self.state in {
            _TransportState.AUTHORIZED,
            _TransportState.OPENING,
            _TransportState.CONNECTING,
            _TransportState.OPENED,
        }:
            self.state=_TransportState.OPENED_LATE

    def mark_uncertain(self):
        if self.state in {
            _TransportState.AUTHORIZED,
            _TransportState.OPENING,
            _TransportState.CONNECTING,
            _TransportState.OPENED,
            _TransportState.OPENED_LATE,
        }:
            self.state=_TransportState.UNCERTAIN

    def mark_closed(self, *, now):
        if self.close_deadline is None or now>=self.close_deadline:
            return
        if self.state in {
            _TransportState.OPENING,
            _TransportState.CONNECTING,
        }:
            self.state=_TransportState.CLOSED_UNQUALIFIED
        elif self.state is _TransportState.OPENED:
            self.state=_TransportState.CLOSED
        elif self.state in {
            _TransportState.OPENED_LATE,
            _TransportState.UNCERTAIN,
        }:
            self.state=_TransportState.CLOSED_LATE

    def mark_failed(self):
        if self.state in {
            _TransportState.AUTHORIZED,
            _TransportState.OPENING,
        }:
            self.state=_TransportState.CLOSED_UNQUALIFIED
        elif self.state is _TransportState.CONNECTING:
            self.state=_TransportState.UNCERTAIN

    def clear_attempt_deadline(self):
        self.authorization=None
        self.deadline=None


class ForwardAdapter(Protocol):
    """All calls honor the absolute host-monotonic deadline, including I/O.

    identity returns the independently read target/build pair. Implementations
    must stop their own blocking work at the deadline. The session checks return
    times but cannot interrupt a noncompliant adapter. The bounded host ADB
    implementation is in adb_forward.py; callers must use it through this
    session so durable ownership obligations remain authoritative.
    """
    def identity(self, target, *, deadline): ...
    def lookup(self, target, local, *, deadline): ...
    def create_no_rebind(self, target, local, remote, *, deadline): ...
    def remove(self, target, local, *, deadline): ...
    def open_transport(
        self, session: "ForwardSession", authorization: object, *, deadline
    ) -> Transport: ...


class ForwardSession:
    """One bounded phase at a time, with a fixed 60-second cleanup reserve.

    Each phase shares a five-second call budget, shortened by remaining session
    authority. Cleanup alone can use the reserve after the session deadline.
    Obligation callbacks must durably finish within that same phase deadline.
    Failed or late readback never clears the outstanding ownership obligation.
    """
    def __init__(self,adb: ForwardAdapter,target,build,session,local,remote,started,deadline,*,clock,obligation,
                 operation_deadline=None):
        require(HEX.fullmatch(session) is not None)
        require(0<deadline-started<=600)
        require(re.fullmatch(r'tcp:[1-9][0-9]{0,4}',local) is not None and int(local[4:])<=65535)
        require(re.fullmatch(r'localabstract:[A-Za-z0-9_-]{1,100}',remote) is not None)
        self.adb,self.target,self.build,self.session=adb,target,build,session
        self.local,self.remote,self.started,self.deadline=local,remote,started,deadline
        self.operation_deadline = deadline if operation_deadline is None else operation_deadline
        require(started < self.operation_deadline <= deadline)
        self.cleanup_deadline=deadline+60
        self.state='New'; self.owned=False; self.uid=None
        self._transport_lifecycles={
            phase:_TransportLifecycle(policy)
            for phase,policy in _TRANSPORT_POLICIES.items()
        }
        self._discovery_transport=self._transport_lifecycles[
            _TransportPhase.DISCOVERY
        ]
        self._readiness_transport=self._transport_lifecycles[
            _TransportPhase.READINESS
        ]
        self.clock,self.obligation=clock,obligation

    @property
    def discovery_transport_attempted(self):
        return self._discovery_transport.attempted

    @property
    def discovery_transport_opened(self):
        return (
            self._discovery_transport.opened
            and self._discovery_transport.admitted
        )

    @property
    def discovery_transport_closed(self):
        return self._discovery_transport.closed

    @property
    def readiness_transport_attempted(self):
        return self._readiness_transport.attempted

    @property
    def readiness_transport_opened(self):
        return self._readiness_transport.opened and self._readiness_transport.admitted

    def phase_deadline(self, *, cleanup=False, limit=None):
        now=self.clock()
        authority=self.cleanup_deadline if cleanup else self.operation_deadline
        if limit is not None: authority=min(authority,limit)
        require(self.started<=now<authority,'TimedOut')
        return min(now+5,authority)

    def check_time(self, deadline):
        require(self.started<=self.clock()<deadline,'TimedOut')

    def call(
        self, method, *args, deadline, close_late=False, on_late_result=None
    ):
        self.check_time(deadline)
        try:
            result=method(*args,deadline=deadline)
        except ProbeError:
            raise
        except TimeoutError:
            raise ProbeError('TimedOut') from None
        except Exception:
            raise ProbeError('IncompleteEvidence') from None
        try:
            self.check_time(deadline)
        except ProbeError as request_error:
            if close_late:
                if on_late_result is not None:
                    on_late_result(result)
                try:
                    result.close(deadline+1)
                except ProbeError as cleanup_error:
                    raise ProbeError('IncompleteEvidence','Transport',
                        request_failure_code=request_error.code,
                        cleanup_failure_code=cleanup_error.code) from None
                except Exception:
                    raise ProbeError('IncompleteEvidence','Transport',
                        request_failure_code=request_error.code,
                        cleanup_failure_code='IncompleteEvidence') from None
            raise
        return result

    def check_identity(self, deadline):
        observed=self.call(self.adb.identity,self.target,deadline=deadline)
        require(observed==(self.target,self.build),'IntegrityConflict')

    def record(self,state,deadline,**facts):
        self.check_time(deadline)
        self.obligation(dict(state=state,target=self.target,build=self.build,session=self.session,
                             local=self.local,remote=self.remote,deadline=deadline,**facts))
        self.check_time(deadline)

    def create(self):
        require(self.state=='New')
        deadline=self.phase_deadline()
        self.state='Uncertain'
        self.record('creation-pending',deadline)
        self.check_identity(deadline)
        require(self.call(self.adb.lookup,self.target,self.local,deadline=deadline) is None,'IntegrityConflict')
        self.call(self.adb.create_no_rebind,self.target,self.local,self.remote,deadline=deadline)
        require(self.call(self.adb.lookup,self.target,self.local,deadline=deadline)==self.remote,'IntegrityConflict')
        self.owned=True
        self.record('owned',deadline)
        self.state='Forwarded'

    def arm(self,attempt,now):
        deadline=self.phase_deadline()
        require(self.state=='Forwarded' and HEX.fullmatch(attempt) is not None and attempt!=self.session)
        require(self.started<=now<=self.clock() and self.clock()<now+5,'TimedOut')
        self.check_identity(deadline)
        require(self.call(self.adb.lookup,self.target,self.local,deadline=deadline)==self.remote,'IntegrityConflict')
        self.attempt,self.armed=attempt,now
        self.state='Armed'

    def _open_transport(self,phase):
        lifecycle=self._transport_for_phase(phase)
        if lifecycle is None:
            raise ProbeError('IntegrityConflict','Transport')
        policy=lifecycle.policy
        require(self.state==policy.session_state and not lifecycle.attempted,
                'UnauthorizedPeer')
        armed=getattr(self,'armed',self.started)
        deadline=self.phase_deadline(limit=policy.opening_limit(armed))
        lifecycle.authorize(
            object(),
            deadline=deadline,
            close_deadline=policy.release_deadline(armed,deadline),
        )
        try:
            try:
                self.check_identity(deadline)
                require(self.call(self.adb.lookup,self.target,self.local,
                                  deadline=deadline)==self.remote,
                        'IntegrityConflict')
                transport=self.call(
                    self.adb.open_transport,
                    self,
                    lifecycle.authorization,
                    deadline=deadline,
                    close_late=True,
                    on_late_result=lambda _result: self._mark_transport_late(phase),
                )
                if lifecycle.authorization is not None:
                    self._mark_transport_late(phase)
                    try:
                        transport.close(deadline+1)
                    except ProbeError as cleanup_error:
                        self._mark_transport_uncertain(phase)
                        raise ProbeError(
                            'IncompleteEvidence','Transport',
                            request_failure_code='IntegrityConflict',
                            cleanup_failure_code=cleanup_error.code,
                        ) from None
                    except Exception:
                        self._mark_transport_uncertain(phase)
                        raise ProbeError(
                            'IncompleteEvidence','Transport',
                            request_failure_code='IntegrityConflict',
                            cleanup_failure_code='IncompleteEvidence',
                        ) from None
                    self._mark_transport_closed(phase)
                    raise ProbeError('IntegrityConflict','Transport')
                if lifecycle.state is _TransportState.OPENING:
                    self._mark_transport_opened(phase)
                require(lifecycle.state is _TransportState.OPENED,
                        'IntegrityConflict','Transport')
                return transport
            except ProbeError:
                lifecycle.mark_failed()
                raise
        finally:
            lifecycle.clear_attempt_deadline()

    def open_discovery_transport(self):
        """Open the single deny-only discovery connection before admission closes."""
        return self._open_transport(_TransportPhase.DISCOVERY)

    def _consume_transport_authorization(self,authorization,*,deadline):
        """Consume the one-shot authority for a phase-bound socket open."""
        if authorization is None:
            raise ProbeError('IntegrityConflict','Transport')
        found=next(
            (
                (phase,candidate)
                for phase,candidate in self._transport_lifecycles.items()
                if authorization is candidate.authorization
            ),
            None,
        )
        if found is None:
            raise ProbeError('IntegrityConflict','Transport')
        phase,lifecycle=found
        now=self.clock()
        require(lifecycle.deadline==deadline
                and lifecycle.state is _TransportState.AUTHORIZED,
                'IntegrityConflict','Transport')
        require(self.state==lifecycle.policy.session_state,
                'IntegrityConflict','Transport')
        armed=getattr(self,'armed',self.started)
        opening_limit=lifecycle.policy.opening_limit(armed)
        require(self.started<=now<self.deadline and deadline<=self.deadline,
                'IntegrityConflict','Transport')
        require(opening_limit is None or deadline<=opening_limit,
                'IntegrityConflict','Transport')
        lifecycle.consume(authorization,deadline=deadline)
        return phase

    def _mark_transport_socket_created(self,phase):
        """Record the local socket before connecting it to the owned forward."""
        lifecycle=self._transport_for_phase(phase)
        if lifecycle is not None:
            lifecycle.mark_socket_created()

    def _mark_transport_opened(self,phase):
        """Record a socket that connected within its open-phase deadline."""
        lifecycle=self._transport_for_phase(phase)
        if lifecycle is None:
            return
        lifecycle.mark_opened(
            now=self.clock(),
            started=self.started,
            session_deadline=self.deadline,
        )

    def _mark_transport_late(self,phase):
        """Record a returned transport as ineligible after its open deadline."""
        lifecycle=self._transport_for_phase(phase)
        if lifecycle is not None:
            lifecycle.mark_late()

    def _mark_transport_uncertain(self,phase):
        """Keep cleanup blocked when socket release cannot be confirmed."""
        lifecycle=self._transport_for_phase(phase)
        if lifecycle is not None:
            lifecycle.mark_uncertain()

    def _mark_transport_closed(self,phase):
        """Record a transport that closed within its phase release deadline."""
        lifecycle=self._transport_for_phase(phase)
        if lifecycle is not None:
            lifecycle.mark_closed(now=self.clock())

    def _transport_for_phase(self,phase):
        return self._transport_lifecycles.get(phase)

    def open_readiness_transport(self):
        """Open one Readiness connection after the owner pins the observed UID."""
        return self._open_transport(_TransportPhase.READINESS)

    def correlate(self,observation,host_started,host_finished,response_bytes,owner_confirmed):
        """Review completed discovery within the original session authority.

        The deny-only connection must have opened and closed within its release
        limit before its observation can be correlated.
        The host interval describes the connection attempt, not owner review.
        It must finish inside the five-second admission window. The probe's
        full-window result and owner confirmation can arrive later; neither
        starts a new window or extends the authorized session.
        """
        require(self.state=='Armed')
        self.state='Rejected'
        require(self.discovery_transport_attempted and self.discovery_transport_opened
                and self.discovery_transport_closed,'IncompleteEvidence','Transport')
        require(isinstance(observation,Discovery),'IncompleteEvidence')
        deadline=self.phase_deadline()
        require(owner_confirmed is True
                and self.clock()>=self.armed+5
                and self.armed<=host_started<=host_finished<self.armed+5
                and host_finished<=self.clock(),'IncompleteEvidence')
        require(observation.session==self.session and observation.attempt==self.attempt and observation.endpoint==self.remote,'IntegrityConflict')
        require(observation.count==1 and type(observation.uid) is int and 0<=observation.uid<2**32 and response_bytes==0,'IntegrityConflict')
        self.check_identity(deadline)
        require(self.call(self.adb.lookup,self.target,self.local,deadline=deadline)==self.remote,'IntegrityConflict')
        self.record('discovery-correlated',deadline,attempt=self.attempt,uid=observation.uid,
                    host_started=host_started,host_finished=host_finished,connection_count=observation.count,
                    response_bytes=response_bytes,owner_confirmed=True,
                    android_started_ms=observation.android_started_ms,
                    android_finished_ms=observation.android_finished_ms)
        self.uid=observation.uid; self.state='Correlated'

    def enforce(self,uid,owner_approved):
        deadline=self.phase_deadline()
        require(self.state=='Correlated' and self.discovery_transport_attempted
                and self.discovery_transport_opened and self.discovery_transport_closed
                and owner_approved is True and type(uid) is int and uid==self.uid,
                'UnauthorizedPeer')
        self.check_identity(deadline)
        require(self.call(self.adb.lookup,self.target,self.local,deadline=deadline)==self.remote,'IntegrityConflict')
        self.record('owner-pin-approved',deadline,attempt=self.attempt,uid=uid,owner_approved=True)
        self.state='Enforcing'

    def cleanup(self):
        deadline=self.phase_deadline(cleanup=True)
        require(not self._discovery_transport.has_release_obligation
                and not self._readiness_transport.has_release_obligation,
                'IncompleteEvidence','Transport')
        require(self.owned,'IntegrityConflict')
        self.check_identity(deadline)
        require(self.call(self.adb.lookup,self.target,self.local,deadline=deadline)==self.remote,'IntegrityConflict')
        self.record('cleanup-pending',deadline)
        self.call(self.adb.remove,self.target,self.local,deadline=deadline)
        self.check_identity(deadline)
        require(self.call(self.adb.lookup,self.target,self.local,deadline=deadline) is None,'IncompleteEvidence')
        self.record('closed',deadline)
        self.owned=False; self.state='Closed'

DIAGNOSTIC_COMMAND=('shell','dumpsys','-t','3','activity','activities')
WINDOW_DISPLAY_COMMAND=('shell','dumpsys','-t','3','window','displays')
