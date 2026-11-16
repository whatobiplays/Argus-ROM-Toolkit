"""Bounded Readiness wire operations with injected, deadline-aware transport.

This module cannot execute ADB. Adapters must honor absolute monotonic deadlines
and close by the supplied release deadline. A successful response proves only
standalone probe readiness.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import stat
import struct
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol, Callable

PROTOCOL = 'argus.product-observer'
REQUEST_CAP, RESPONSE_CAP, CANCEL_CAP = 274, 393, 227
STAGES = frozenset('Accept AuthenticatePeer Parse Validate Read Assemble Serialize Cancel Transport'.split())
CODES = frozenset('Busy Cancelled TimedOut StaleLibraryView InvalidLibraryViewToken UnauthorizedPeer UnsupportedVersion UnsupportedOperation MalformedRequest IncompleteEvidence IncompleteHistory IncompleteMembership IntegrityConflict ResourceLimitExceeded NotReady InternalError'.split())
HEX = re.compile(r'[0-9a-f]{32}\Z')

class ProbeError(ValueError):
    """Carries closed failure codes, never raw transport or payload text.

    Secondary codes describe host request and release failures only. They are
    retained in the private record envelope, not the wire or receipt schema.
    """
    def __init__(self, code='MalformedRequest', stage='Validate', *,
                 request_failure_code=None, cleanup_failure_code=None):
        self.code, self.stage = code, stage
        self.request_failure_code = request_failure_code
        self.cleanup_failure_code = cleanup_failure_code
        super().__init__(code)

def require(ok, code='MalformedRequest', stage='Validate'):
    if not ok:
        raise ProbeError(code, stage)

@dataclass(frozen=True)
class Identity:
    request_id: str
    connection_id: str
    attempt_id: str
    def __post_init__(self):
        values = (self.request_id, self.connection_id, self.attempt_id)
        require(all(isinstance(x,str) and HEX.fullmatch(x) for x in values) and len(set(values)) == 3)

def base(ids):
    return dict(protocol_id=PROTOCOL, protocol_version=1, **vars(ids))

def uint(value, bits):
    return type(value) is int and 0 <= value < 2**bits

def request(ids, remaining_budget_ms):
    require(uint(remaining_budget_ms,32) and remaining_budget_ms > 0)
    return {**base(ids), 'remaining_budget_ms':remaining_budget_ms, 'operation':{'kind':'Readiness'}}

def cancel(ids):
    return {**base(ids), 'control':'Cancel'}

def success(ids, started, finished):
    require(uint(started,64) and uint(finished,64) and started <= finished)
    return {**base(ids), 'outcome':{'kind':'CompleteSuccess','result':{'state':'Ready'}},
            'observer_started_elapsed_realtime_ms':started, 'observer_finished_elapsed_realtime_ms':finished}

def compact(value):
    return json.dumps(value, ensure_ascii=True, separators=(',',':'), allow_nan=False).encode('ascii')

def frame(value, cap):
    data = compact(value)
    require(0 < len(data) <= cap, 'ResourceLimitExceeded','Serialize')
    return struct.pack('>I',len(data)) + data

def decode(body, cap):
    require(0 < len(body) <= cap, 'ResourceLimitExceeded','Parse')
    def pairs(items):
        require(len(items) <= 8 and len(dict(items)) == len(items))
        return dict(items)
    def bad(_):
        raise ProbeError('MalformedRequest','Parse')
    try:
        value=json.loads(body.decode('utf-8'), object_pairs_hook=pairs, parse_float=bad, parse_constant=bad)
        count=0
        def visit(node, depth):
            nonlocal count
            require(depth <= 3)
            if isinstance(node,dict):
                count += len(node)
                for key,item in node.items():
                    key.encode('utf-8',errors='strict')
                    visit(item, depth+1 if isinstance(item,dict) else depth)
            elif isinstance(node,str): node.encode('utf-8',errors='strict')
            else: require(type(node) is int)
        require(isinstance(value,dict))
        visit(value,1)
        require(count <= 11)
        return value
    except (UnicodeError, ValueError, RecursionError, TypeError):
        raise ProbeError('MalformedRequest','Parse') from None

def validate_response(value, ids):
    expected=base(ids)
    require(all(type(value.get(k)) is type(v) and value.get(k)==v for k,v in expected.items()),'IntegrityConflict')
    outcome=value.get('outcome')
    require(isinstance(outcome,dict))
    if outcome.get('kind') == 'CompleteSuccess':
        require(set(value)==set(success(ids,0,0)))
        require(outcome == {'kind':'CompleteSuccess','result':{'state':'Ready'}})
        started=value['observer_started_elapsed_realtime_ms']
        finished=value['observer_finished_elapsed_realtime_ms']
        require(uint(started,64) and uint(finished,64) and started<=finished)
    else:
        require(set(value)==set(expected)|{'outcome'})
        require(set(outcome)=={'kind','code','stage'} and outcome['kind']=='Failure')
        require(outcome['code'] in CODES and outcome['stage'] in STAGES)
    return value

# Receipt fields are deliberately closed. Private references remain opaque aliases.
RECEIPT_FIELDS=frozenset('protocol_id protocol_version request_id connection_id attempt_id operation_kind assertion_alias failure_code failure_stage host_started host_deadline host_finished request_body_bytes response_body_bytes target_ref artifact_ref authorization_ref rules_ref sanitizer_version evidence_ref'.split())

def validate_receipt(receipt):
    """Validate complete B1 failure provenance on both write and readback."""
    require(type(receipt) is dict and set(receipt)==RECEIPT_FIELDS,'IntegrityConflict')
    require(receipt['protocol_id']==PROTOCOL and type(receipt['protocol_id']) is str,'IntegrityConflict')
    require(type(receipt['protocol_version']) is int and receipt['protocol_version']==1,'IntegrityConflict')
    require(receipt['operation_kind']=='Readiness' and receipt['sanitizer_version']=='1','IntegrityConflict')
    Identity(receipt['request_id'],receipt['connection_id'],receipt['attempt_id'])
    require(type(receipt['failure_code']) is str
            and receipt['failure_code'] in CODES | {'Disconnected','ProcessLost'},'IntegrityConflict')
    require(type(receipt['failure_stage']) is str and receipt['failure_stage'] in STAGES,'IntegrityConflict')
    for key in ('target_ref','artifact_ref','authorization_ref','rules_ref','evidence_ref','assertion_alias'):
        require(type(receipt[key]) is str and re.fullmatch(r'[A-Za-z0-9_-]{1,256}',receipt[key]) is not None,'IntegrityConflict')
    for key in ('host_started','host_deadline','host_finished','request_body_bytes','response_body_bytes'):
        require(uint(receipt[key],64),'IntegrityConflict')
    require(receipt['host_started'] < receipt['host_deadline'] <= receipt['host_started']+5000
            and receipt['host_finished']>=receipt['host_started'],'IntegrityConflict')
    require(0<receipt['request_body_bytes']<=REQUEST_CAP
            and receipt['response_body_bytes']<=RESPONSE_CAP,'IntegrityConflict')
    require(len(compact(receipt))<=4096,'ResourceLimitExceeded')


def validate_host_failures(causes, receipt):
    """Validate optional private host metadata beside the unchanged receipt."""
    require(type(causes) is dict
            and set(causes) in ({'cleanup_code'}, {'cleanup_code','request_code'}),
            'IntegrityConflict')
    require(receipt['failure_code']=='IncompleteEvidence'
            and receipt['failure_stage']=='Transport'
            and type(causes['cleanup_code']) is str
            and causes['cleanup_code']=='IncompleteEvidence','IntegrityConflict')
    if 'request_code' in causes:
        require(type(causes['request_code']) is str
                and causes['request_code'] in CODES | {'Disconnected','ProcessLost'},
                'IntegrityConflict')


class EvidenceStore:
    """Private, non-evicting hash chain; retain the returned head separately.

    A hash chain detects edits and reordering. Detecting tail deletion requires
    the caller's separately retained expected head. It is not an authenticity
    signature and does not protect against a malicious filesystem owner.

    Optional host_failures metadata preserves request and cleanup causes beside
    the closed receipt. It is covered by the record hash. Earlier records
    without that metadata remain readable.
    """
    def __init__(self, root: Path):
        self.root=Path(root)
        if not self.root.exists(): self.root.mkdir(mode=0o700)
        info=self.root.lstat()
        require(stat.S_ISDIR(info.st_mode) and info.st_mode & 0o077 == 0,'IntegrityConflict')
        self.records=self.verify()
        self.reserved=set()
        self.next_slot=len(self.records)
    def reserve(self):
        require(self.next_slot < 8,'ResourceLimitExceeded')
        slot=self.next_slot
        self.next_slot+=1
        self.reserved.add(slot)
        return slot
    def release(self, slot):
        """Release only the latest unused reservation; stored receipts never move."""
        require(slot in self.reserved and slot==self.next_slot-1,'IntegrityConflict')
        self.reserved.remove(slot)
        self.next_slot-=1
    def append(self, slot, receipt, *, host_failures=None):
        require(slot in self.reserved and slot == len(self.records),'IntegrityConflict')
        validate_receipt(receipt)
        previous=self.records[-1]['digest'] if self.records else '0'*64
        entry={'sequence':slot,'previous':previous,'receipt':receipt}
        if host_failures is not None:
            validate_host_failures(host_failures, receipt)
            entry['host_failures']=dict(host_failures)
        entry['digest']=hashlib.sha256(compact(entry)).hexdigest()
        path=self.root/f'{slot:02d}.json'
        fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
        with os.fdopen(fd,'wb') as stream:
            stream.write(compact(entry)); stream.flush(); os.fsync(stream.fileno())
        directory=os.open(self.root,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
        self.records.append(entry)
        self.reserved.remove(slot)
        return entry['digest']
    def verify(self, expected_head=None):
        records=[]
        previous='0'*64
        for i,path in enumerate(sorted(self.root.iterdir())):
            require(path.name==f'{i:02d}.json' and i<8,'IntegrityConflict')
            info=path.lstat()
            require(stat.S_ISREG(info.st_mode) and info.st_mode&0o077==0 and info.st_size<=8192,'IntegrityConflict')
            try:
                def unique_pairs(pairs):
                    require(len(pairs)==len(dict(pairs)),'IntegrityConflict')
                    return dict(pairs)
                entry=json.loads(path.read_bytes(),object_pairs_hook=unique_pairs)
                digest=entry.pop('digest')
                require(set(entry) in ({'sequence','previous','receipt'},
                                      {'sequence','previous','receipt','host_failures'})
                        and type(entry['sequence']) is int and entry['sequence']==i
                        and entry['previous']==previous,'IntegrityConflict')
                require(hashlib.sha256(compact(entry)).hexdigest()==digest,'IntegrityConflict')
                validate_receipt(entry['receipt'])
                if 'host_failures' in entry:
                    validate_host_failures(entry['host_failures'], entry['receipt'])
                entry['digest']=digest
            except (KeyError,ValueError,TypeError): raise ProbeError('IntegrityConflict') from None
            records.append(entry); previous=digest
        require(expected_head is None or expected_head==previous,'IntegrityConflict')
        return records

class Transport(Protocol):
    """Every method must honor its absolute host-monotonic deadline."""
    def write(self, data: bytes, deadline: float) -> None: ...
    def read(self, count: int, deadline: float) -> bytes: ...
    def close(self, deadline: float) -> None: ...

class AttemptRunner:
    """Single-use identities and no retries; receipt reservation precedes I/O."""
    def __init__(self, store, clock: Callable[[],float]):
        self.store,self.clock=store,clock
        self.used=set()
        self.active=False
    def run(self, ids, transport, session_deadline, references, cancelled=lambda:False):
        require(not self.active,'Busy')
        require(not self.used.intersection(vars(ids).values()),'IntegrityConflict')
        required={'target_ref','artifact_ref','authorization_ref','rules_ref','assertion_alias','evidence_ref'}
        require(set(references)==required)
        # Restrict all references to opaque ASCII labels, never paths or payloads.
        require(all(isinstance(v,str) and re.fullmatch(r'[A-Za-z0-9_-]{1,256}',v) for v in references.values()))
        started=self.clock(); deadline=min(started+5,session_deadline)
        require(int((deadline-started)*1000)>0,'TimedOut')
        slot=self.store.reserve()
        self.used.update(vars(ids).values()); self.active=True
        body_count=0; sent_cancel=False; result=None; failure=None; cleanup_failure=None
        payload=frame(request(ids,min(5000,int((deadline-started)*1000))),REQUEST_CAP)
        def checkpoint():
            nonlocal sent_cancel
            require(self.clock()<deadline,'TimedOut','Transport')
            if cancelled() and not sent_cancel:
                transport.write(frame(cancel(ids),CANCEL_CAP),deadline)
                sent_cancel=True
        def read_exact(count, body=False):
            nonlocal body_count
            chunks=bytearray()
            while len(chunks)<count:
                checkpoint()
                chunk=transport.read(count-len(chunks),deadline)
                require(bool(chunk),'Disconnected','Transport')
                require(len(chunk)<=count-len(chunks),'IntegrityConflict','Transport')
                chunks.extend(chunk)
                if body: body_count+=len(chunk)
            return bytes(chunks)
        try:
            transport.write(payload,deadline)
            header=read_exact(4)
            size=struct.unpack('>I',header)[0]
            require(0<size<=RESPONSE_CAP,'ResourceLimitExceeded','Parse')
            body=read_exact(size,body=True)
            checkpoint()
            result=validate_response(decode(body,RESPONSE_CAP),ids)
            require(self.clock()<deadline,'TimedOut','Transport')
            if sent_cancel: raise ProbeError('Cancelled','Cancel')
            if result['outcome']['kind']=='Failure':
                raise ProbeError(result['outcome']['code'],result['outcome']['stage'])
        except ProbeError as exc: failure=exc
        except TimeoutError: failure=ProbeError('TimedOut','Transport')
        except Exception: failure=ProbeError('Disconnected','Transport')
        finally:
            release_deadline=self.clock()+1
            try:
                transport.close(release_deadline)
                require(self.clock()<=release_deadline,'IncompleteEvidence','Transport')
            except Exception: cleanup_failure=ProbeError('IncompleteEvidence','Transport')
            self.active=False
        finished=self.clock()
        if finished>=deadline and failure is None:
            failure=ProbeError('TimedOut','Transport')
        if cleanup_failure is not None:
            # Unverified release takes precedence. The receipt's existing host
            # interval retains deadline overrun evidence; callers also receive
            # both closed codes without exposing raw cleanup exceptions.
            failure=ProbeError('IncompleteEvidence','Transport',
                               request_failure_code=failure.code if failure else None,
                               cleanup_failure_code=cleanup_failure.code)
        if failure is None:
            self.store.release(slot)
            return result
        receipt={**base(ids),**references,'operation_kind':'Readiness',
                 'failure_code':failure.code if failure else 'CompleteSuccess',
                 'failure_stage':failure.stage if failure else 'Read',
                 'host_started':int(started*1000),'host_deadline':int(deadline*1000),'host_finished':int(finished*1000),
                 'request_body_bytes':len(payload)-4,'response_body_bytes':body_count,'sanitizer_version':'1'}
        causes=None
        if cleanup_failure is not None:
            causes={'cleanup_code':cleanup_failure.code}
            if failure.request_failure_code is not None:
                causes['request_code']=failure.request_failure_code
        self.store.append(slot,receipt,host_failures=causes)
        if failure: raise failure
        return result
