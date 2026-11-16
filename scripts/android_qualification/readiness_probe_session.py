"""Injected forward ownership and ephemeral Q7 diagnostic filtering.

No implementation here invokes ADB. The caller supplies a reviewed adapter and
exact target/build identity. Discovery correlation is operational evidence under
the trusted-host model, not cryptographic proof of the connecting host.
"""
from dataclasses import dataclass
import re
import hashlib
from typing import Protocol
from .readiness_probe import require, ProbeError, HEX, compact, uint

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

class ForwardAdapter(Protocol):
    """All calls honor the absolute host-monotonic deadline, including I/O.

    identity returns the independently read target/build pair. Implementations
    must stop their own blocking work at the deadline. The session checks return
    times but cannot interrupt a noncompliant adapter. No real adapter is shipped.
    """
    def identity(self, target, *, deadline): ...
    def lookup(self, target, local, *, deadline): ...
    def create_no_rebind(self, target, local, remote, *, deadline): ...
    def remove(self, target, local, *, deadline): ...


class ForwardSession:
    """One bounded phase at a time, with a fixed 60-second cleanup reserve.

    Each phase shares a five-second call budget, shortened by remaining session
    authority. Cleanup alone can use the reserve after the session deadline.
    Obligation callbacks must durably finish within that same phase deadline.
    Failed or late readback never clears the outstanding ownership obligation.
    """
    def __init__(self,adb: ForwardAdapter,target,build,session,local,remote,started,deadline,*,clock,obligation):
        require(HEX.fullmatch(session) is not None)
        require(0<deadline-started<=600)
        require(re.fullmatch(r'tcp:[1-9][0-9]{0,4}',local) is not None and int(local[4:])<=65535)
        require(re.fullmatch(r'localabstract:[A-Za-z0-9_-]{1,100}',remote) is not None)
        self.adb,self.target,self.build,self.session=adb,target,build,session
        self.local,self.remote,self.started,self.deadline=local,remote,started,deadline
        self.cleanup_deadline=deadline+60
        self.state='New'; self.owned=False; self.uid=None
        self.clock,self.obligation=clock,obligation

    def phase_deadline(self, *, cleanup=False, limit=None):
        now=self.clock()
        authority=self.cleanup_deadline if cleanup else self.deadline
        if limit is not None: authority=min(authority,limit)
        require(self.started<=now<authority,'TimedOut')
        return min(now+5,authority)

    def check_time(self, deadline):
        require(self.started<=self.clock()<deadline,'TimedOut')

    def call(self, method, *args, deadline):
        self.check_time(deadline)
        try:
            result=method(*args,deadline=deadline)
        except ProbeError:
            raise
        except TimeoutError:
            raise ProbeError('TimedOut') from None
        except Exception:
            raise ProbeError('IncompleteEvidence') from None
        self.check_time(deadline)
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

    def correlate(self,observation,host_started,host_finished,response_bytes,owner_confirmed):
        """Review completed discovery within the original session authority.

        The host interval describes the connection attempt, not owner review.
        It must finish inside the five-second admission window. The probe's
        full-window result and owner confirmation can arrive later; neither
        starts a new window or extends the authorized session.
        """
        require(self.state=='Armed')
        self.state='Rejected'
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
        require(self.state=='Correlated' and owner_approved is True and type(uid) is int and uid==self.uid,'UnauthorizedPeer')
        self.check_identity(deadline)
        require(self.call(self.adb.lookup,self.target,self.local,deadline=deadline)==self.remote,'IntegrityConflict')
        self.record('owner-pin-approved',deadline,attempt=self.attempt,uid=uid,owner_approved=True)
        self.state='Enforcing'

    def cleanup(self):
        deadline=self.phase_deadline(cleanup=True)
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

@dataclass(frozen=True)
class DiagnosticProfile:
    """Reviewed target/build-specific grammar, never an automatic fallback.

    The selected OS command must supply complete output with a known terminator.
    No profile is shipped as qualified; fixtures establish parser behavior only.
    """
    name: str
    build: str
    package: str
    target_line_pattern: str
    completion_line: str
    source: tuple[str, ...] = DIAGNOSTIC_COMMAND

@dataclass(frozen=True)
class DiagnosticBinding:
    """Expected identities and profile digest from the reviewed approval record.

    This record is supplied independently of diagnostic output. A digest binds
    reviewed configuration; it does not authenticate a host or qualify a source.
    """
    build: str
    package: str
    source: tuple[str, ...]
    profile_sha256: str

def validate_profile(profile):
    require(isinstance(profile,DiagnosticProfile),'IncompleteEvidence')
    def matches(value, pattern):
        return type(value) is str and re.fullmatch(pattern,value) is not None
    require(matches(profile.name,r'[a-z][a-z0-9_-]{0,63}'),'IncompleteEvidence')
    require(matches(profile.build,r'[A-Za-z0-9][A-Za-z0-9._:/+\-]{0,255}'),'IncompleteEvidence')
    require(matches(profile.package,r'[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+')
            and len(profile.package)<=255,'IncompleteEvidence')
    require(type(profile.source) is tuple and profile.source==DIAGNOSTIC_COMMAND,'IncompleteEvidence')
    for value,limit in ((profile.target_line_pattern,2048),(profile.completion_line,256)):
        require(type(value) is str and 0<len(value)<=limit and value.isascii()
                and all(32<=ord(c)<127 for c in value) and value==value.strip(),'IncompleteEvidence')
    require(profile.target_line_pattern.startswith('^') and profile.target_line_pattern.endswith('$'),'IncompleteEvidence')
    try:
        pattern=re.compile(profile.target_line_pattern)
    except re.error:
        raise ProbeError('IncompleteEvidence') from None
    require(set(pattern.groupindex)=={'package','task','resumed'}
            and pattern.fullmatch(profile.completion_line) is None,'IncompleteEvidence')
    return pattern

def profile_digest(profile):
    """Hash validated, reviewed grammar; no raw diagnostic bytes enter this hash."""
    validate_profile(profile)
    return hashlib.sha256(compact(vars(profile))).hexdigest()

def parse_diagnostic(chunks,profile,clock,deadline,*,exit_code=None,binding=None):
    """Filter streaming bytes immediately; return only one unambiguous target.

    Adapters must bound each read by the deadline. No raw stdout or stderr may
    be retained by the adapter. After exhausting stdout, exit_code must confirm
    successful command exit within the same deadline. A marker alone is not
    proof of completion. This function never returns raw diagnostic text.
    The binding must come from the reviewed owner record, not from these bytes.
    Regex grammar is trusted reviewed configuration, not untrusted input; no
    shipped profile is physically qualified. The source/build match is required.
    """
    pattern=validate_profile(profile)
    require(isinstance(binding,DiagnosticBinding),'IncompleteEvidence')
    require((binding.build,binding.package,binding.source)==(profile.build,profile.package,profile.source)
            and binding.profile_sha256==profile_digest(profile),'IntegrityConflict')
    total=0; pending=bytearray(); found=[]; complete=False
    def line(raw):
        nonlocal complete
        require(not complete,'IncompleteEvidence')
        try: text=raw.decode('utf-8',errors='strict')
        except UnicodeError: raise ProbeError('IncompleteEvidence') from None
        if text==profile.completion_line: complete=True; return
        match=pattern.fullmatch(text)
        if match:
            fields=match.groupdict()
            require(set(fields)=={'package','task','resumed'} and fields['package']==profile.package,'IncompleteEvidence')
            require(fields['resumed'] in ('true','false') and re.fullmatch(r'[0-9]{1,10}',fields['task']) is not None,'IncompleteEvidence')
            require(0<=int(fields['task'])<=2147483647,'IncompleteEvidence')
            found.append((int(fields['task']),fields['resumed']=='true'))
            require(len(found)==1,'IncompleteEvidence')
    for chunk in chunks:
        require(clock()<deadline,'TimedOut')
        require(type(chunk) is bytes and len(chunk)<=16384,'ResourceLimitExceeded')
        total+=len(chunk)
        require(total<=1048576,'ResourceLimitExceeded')
        for byte in chunk:
            require(not complete,'IncompleteEvidence')
            if byte==10: line(bytes(pending)); pending.clear()
            else:
                pending.append(byte)
                require(len(pending)<=16384,'ResourceLimitExceeded')
    require(clock()<deadline,'TimedOut')
    require(not pending and complete and len(found)==1,'IncompleteEvidence')
    require(callable(exit_code),'IncompleteEvidence')
    try:
        status=exit_code()
    except Exception:
        raise ProbeError('IncompleteEvidence') from None
    require(clock()<deadline,'TimedOut')
    require(type(status) is int and status==0,'IncompleteEvidence')
    return dict(profile=profile.name,build=profile.build,package=profile.package,task_id=found[0][0],resumed=found[0][1])
