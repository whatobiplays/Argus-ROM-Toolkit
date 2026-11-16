"""Readiness host boundary tests; all transports are in-memory."""
import json
import tempfile
import unittest
from pathlib import Path
from . import readiness_probe as p

class CodecTests(unittest.TestCase):
    def setUp(self):
        self.ids = p.Identity('a'*32, 'b'*32, 'c'*32)
    def test_caps(self):
        request = p.request(self.ids, 4294967295)
        self.assertEqual(len(p.frame(request, p.REQUEST_CAP)), 278)
        self.assertEqual(len(p.frame(p.cancel(self.ids), p.CANCEL_CAP)), 231)
        self.assertEqual(len(p.frame(p.success(self.ids, 2**64-1, 2**64-1), p.RESPONSE_CAP)), 397)
    def test_strict_decode(self):
        for body in [b'{"x":1,"x":2}', b'[]', b'{"x":NaN}', b'{"x":1.0}', b'{"x":"\\ud800"}', b'{} trailing']:
            with self.subTest(body=body), self.assertRaises(p.ProbeError):
                p.decode(body, p.RESPONSE_CAP)
    def test_response_binding(self):
        r = p.success(self.ids, 1, 2)
        self.assertEqual(p.validate_response(r, self.ids), r)
        r['request_id']='d'*32
        with self.assertRaises(p.ProbeError): p.validate_response(r,self.ids)
    def test_failure_closure(self):
        for code in ['ApplicationFailure','Disconnected','Bogus']:
            with self.assertRaises(p.ProbeError):
                p.validate_response({**p.base(self.ids),'outcome':{'kind':'Failure','code':code,'stage':'Read'}},self.ids)

class EvidenceTests(unittest.TestCase):
    def test_capacity_and_tamper(self):
        with tempfile.TemporaryDirectory() as d:
            store=p.EvidenceStore(Path(d)/'private')
            slots=[store.reserve() for _ in range(8)]
            with self.assertRaises(p.ProbeError): store.reserve()
            store.append(slots[0],complete_receipt())
            self.assertEqual(len(store.verify()),1)
            f=next(store.root.glob('*.json'))
            f.write_bytes(f.read_bytes().replace(b'TimedOut',b'Cancelled'))
            with self.assertRaises(p.ProbeError): store.verify()
    def test_unsafe_fields(self):
        with tempfile.TemporaryDirectory() as d:
            store=p.EvidenceStore(Path(d)/'private')
            with self.assertRaises(p.ProbeError): store.append(store.reserve(),{'raw':'secret'})

if __name__=='__main__': unittest.main()

class MemoryTransport:
    def __init__(self,data): self.data=data; self.writes=[]; self.closed=False
    def write(self,data,deadline): self.writes.append(data)
    def read(self,count,deadline):
        data=self.data[:min(count,7)]; self.data=self.data[len(data):]; return data
    def close(self,deadline): self.closed=True

class AttemptTests(unittest.TestCase):
    def setUp(self):
        self.ids=p.Identity('a'*32,'b'*32,'c'*32)
        self.refs={key:'opaque' for key in ('target_ref','artifact_ref','authorization_ref','rules_ref','assertion_alias','evidence_ref')}
        self.temp=tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.store=p.EvidenceStore(Path(self.temp.name)/'private')
        self.runner=p.AttemptRunner(self.store,lambda:1)
    def transport(self): return MemoryTransport(p.frame(p.success(self.ids,1,2),p.RESPONSE_CAP))
    def test_fragmentation_and_no_identity_reuse(self):
        t=self.transport(); self.runner.run(self.ids,t,10,self.refs)
        self.assertTrue(t.closed)
        with self.assertRaises(p.ProbeError): self.runner.run(self.ids,self.transport(),10,self.refs)
    def test_cancel_discards_success(self):
        t=self.transport()
        with self.assertRaises(p.ProbeError) as caught: self.runner.run(self.ids,t,10,self.refs,lambda:True)
        self.assertEqual(caught.exception.code,'Cancelled')
        self.assertEqual(len(t.writes),2)
        self.assertTrue(t.closed)
    def test_oversized_header_never_reads_body(self):
        t=MemoryTransport((394).to_bytes(4,'big')+b'secret')
        with self.assertRaises(p.ProbeError): self.runner.run(self.ids,t,10,self.refs)
        self.assertEqual(t.data,b'secret')
    def test_eof_receipt_no_raw_exception(self):
        t=MemoryTransport(b'')
        with self.assertRaises(p.ProbeError): self.runner.run(self.ids,t,10,self.refs)
        self.assertEqual(self.store.verify()[0]['receipt']['failure_code'],'Disconnected')
    def test_exhaustion_before_dispatch(self):
        for _ in range(8): self.store.reserve()
        t=self.transport()
        with self.assertRaises(p.ProbeError): self.runner.run(self.ids,t,10,self.refs)
        self.assertEqual(t.writes,[])
    def test_deadline_after_read(self):
        runner=p.AttemptRunner(self.store,lambda:1)
        t=self.transport()
        original=t.read
        def read(count,deadline):
            data=original(count,deadline)
            if not t.data: runner.clock=lambda:7
            return data
        t.read=read
        with self.assertRaises(p.ProbeError) as caught: runner.run(self.ids,t,10,self.refs)
        self.assertEqual(caught.exception.code,'TimedOut')
    def test_max_receipt_and_tail_deletion(self):
        refs={k:'x'*256 for k in self.refs}
        with self.assertRaises(p.ProbeError): self.runner.run(self.ids,MemoryTransport(b''),10,refs)
        records=self.store.verify(); head=records[-1]['digest']
        self.assertLessEqual(len(p.compact(records[0]['receipt'])),4096)
        next(self.store.root.glob('*.json')).unlink()
        with self.assertRaises(p.ProbeError): self.store.verify(expected_head=head)

class ReservationTests(AttemptTests):
    def test_success_releases_unused_failure_capacity(self):
        self.runner.run(self.ids,self.transport(),10,self.refs)
        self.assertEqual(self.store.verify(),[])
        self.assertEqual(self.store.reserve(),0)
    def test_submillisecond_budget_never_dispatches(self):
        t=self.transport()
        with self.assertRaises(p.ProbeError): self.runner.run(self.ids,t,1.0001,self.refs)
        self.assertFalse(self.runner.active)
        self.assertEqual(t.writes,[])

class PartialReceiptTests(AttemptTests):
    def test_partial_response_byte_count(self):
        t=MemoryTransport((10).to_bytes(4,'big')+b'abc')
        with self.assertRaises(p.ProbeError): self.runner.run(self.ids,t,10,self.refs)
        self.assertEqual(self.store.verify()[0]['receipt']['response_body_bytes'],3)
    def test_close_overrun_is_incomplete_evidence(self):
        t=self.transport()
        def close(deadline): self.runner.clock=lambda:2.1
        t.close=close
        with self.assertRaises(p.ProbeError) as caught: self.runner.run(self.ids,t,10,self.refs)
        self.assertEqual(caught.exception.code,'IncompleteEvidence')

class ValidationDeadlineTests(AttemptTests):
    def test_validation_at_or_after_deadline_never_succeeds(self):
        from unittest.mock import patch
        original=p.validate_response
        for finished in (6,6.1):
            with self.subTest(finished=finished),tempfile.TemporaryDirectory() as d:
                store=p.EvidenceStore(Path(d)/'private')
                now=[1]
                runner=p.AttemptRunner(store,lambda:now[0])
                def validate(value,ids):
                    result=original(value,ids)
                    now[0]=finished
                    return result
                with patch.object(p,'validate_response',validate),self.assertRaises(p.ProbeError) as caught:
                    runner.run(self.ids,self.transport(),10,self.refs)
                self.assertEqual(caught.exception.code,'TimedOut')
                self.assertEqual(store.verify()[0]['receipt']['failure_code'],'TimedOut')

def complete_receipt():
    return {**p.base(p.Identity('a'*32,'b'*32,'c'*32)),
            'operation_kind':'Readiness','assertion_alias':'assertion',
            'failure_code':'TimedOut','failure_stage':'Transport',
            'host_started':1000,'host_deadline':6000,'host_finished':6000,
            'request_body_bytes':274,'response_body_bytes':0,
            'target_ref':'target','artifact_ref':'artifact','authorization_ref':'authorization',
            'rules_ref':'rules','sanitizer_version':'1','evidence_ref':'evidence'}

class ReceiptSchemaTests(unittest.TestCase):
    def test_every_required_field_is_required(self):
        for missing in p.RECEIPT_FIELDS:
            with self.subTest(missing=missing),tempfile.TemporaryDirectory() as d:
                store=p.EvidenceStore(Path(d)/'private')
                receipt=complete_receipt(); del receipt[missing]
                with self.assertRaises(p.ProbeError): store.append(store.reserve(),receipt)
                self.assertEqual(list(store.root.iterdir()),[])
    def test_fixed_values_and_bounds(self):
        bad={'protocol_id':'other','protocol_version':True,'operation_kind':'GetJob',
             'failure_code':'CompleteSuccess','failure_stage':'Other','request_id':'bad',
             'connection_id':'a'*32,'host_started':6001,'host_deadline':1000,
             'host_finished':999,'request_body_bytes':275,'response_body_bytes':394,
             'sanitizer_version':'unknown','target_ref':'/private/path','evidence_ref':''}
        for field,value in bad.items():
            with self.subTest(field=field),tempfile.TemporaryDirectory() as d:
                store=p.EvidenceStore(Path(d)/'private')
                receipt={**complete_receipt(),field:value}
                with self.assertRaises(p.ProbeError): store.append(store.reserve(),receipt)
    def test_hash_consistent_invalid_receipt_is_rejected(self):
        import hashlib
        for mutate in (lambda r:r.pop('target_ref'), lambda r:r.update(operation_kind='GetJob'),
                       lambda r:r.update(response_body_bytes=394)):
            with tempfile.TemporaryDirectory() as d:
                store=p.EvidenceStore(Path(d)/'private')
                store.append(store.reserve(),complete_receipt())
                file=next(store.root.iterdir()); entry=json.loads(file.read_bytes())
                mutate(entry['receipt']); del entry['digest']
                entry['digest']=hashlib.sha256(p.compact(entry)).hexdigest()
                file.write_bytes(p.compact(entry))
                with self.assertRaises(p.ProbeError): store.verify()
    def test_directory_fsync_precedes_durable_state(self):
        import os
        import stat
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as d:
            store=p.EvidenceStore(Path(d)/'private'); calls=[]
            original=os.fsync
            def fsync(fd):
                is_directory=stat.S_ISDIR(os.fstat(fd).st_mode)
                calls.append(is_directory)
                if is_directory: self.assertEqual(store.records,[])
                original(fd)
            with patch.object(p.os,'fsync',fsync): store.append(store.reserve(),complete_receipt())
            self.assertEqual(calls,[False,True])
    def test_directory_fsync_failure_retains_reservation(self):
        import os
        import stat
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as d:
            store=p.EvidenceStore(Path(d)/'private'); slot=store.reserve()
            original=os.fsync
            def fsync(fd):
                if stat.S_ISDIR(os.fstat(fd).st_mode): raise OSError('directory sync failed')
                original(fd)
            with patch.object(p.os,'fsync',fsync),self.assertRaises(OSError):
                store.append(slot,complete_receipt())
            self.assertEqual(store.records,[])
            self.assertIn(slot,store.reserved)

class CleanupFailurePrecedenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.store = p.EvidenceStore(Path(self.temp.name)/'private')
        self.now = [1]
        self.runner = p.AttemptRunner(self.store, lambda: self.now[0])
        self.ids = p.Identity('a'*32, 'b'*32, 'c'*32)
        self.refs = {key: 'opaque' for key in (
            'target_ref', 'artifact_ref', 'authorization_ref', 'rules_ref',
            'assertion_alias', 'evidence_ref')}
        self.transport = MemoryTransport(p.frame(p.success(self.ids, 1, 2), p.RESPONSE_CAP))

    def timeout_request(self):
        def read(count, deadline):
            self.now[0] = deadline
            raise TimeoutError()
        self.transport.read = read

    def assert_failure(self, code):
        with self.assertRaises(p.ProbeError) as caught:
            self.runner.run(self.ids, self.transport, 10, self.refs)
        self.assertEqual(caught.exception.code, code)
        receipt = self.store.verify()[0]['receipt']
        self.assertEqual(receipt['failure_code'], code)
        self.assertFalse(self.runner.active)
        return caught.exception, receipt

    def test_timeout_with_verified_cleanup_remains_timeout(self):
        self.timeout_request()
        self.assert_failure('TimedOut')
        self.assertTrue(self.transport.closed)

    def test_cleanup_failure_before_request_deadline_is_not_success(self):
        def close(deadline):
            raise OSError('private cleanup detail')
        self.transport.close = close
        error, _ = self.assert_failure('IncompleteEvidence')
        self.assertIsNone(error.request_failure_code)
        self.assertEqual(error.cleanup_failure_code, 'IncompleteEvidence')
        self.assertEqual(self.store.verify()[0]['host_failures'],
                         {'cleanup_code': 'IncompleteEvidence'})
        self.assertFalse(self.transport.closed)
        self.assertNotIn('private cleanup detail', str(error))

    def test_timeout_cannot_hide_failed_resource_release(self):
        self.timeout_request()
        def close(deadline):
            raise OSError('private cleanup detail')
        self.transport.close = close
        error, receipt = self.assert_failure('IncompleteEvidence')
        self.assertEqual(error.request_failure_code, 'TimedOut')
        self.assertEqual(error.cleanup_failure_code, 'IncompleteEvidence')
        self.assertEqual(self.store.verify()[0]['host_failures'], {
            'request_code': 'TimedOut', 'cleanup_code': 'IncompleteEvidence'})
        self.assertGreaterEqual(receipt['host_finished'], receipt['host_deadline'])
        self.assertFalse(self.transport.closed)

    def test_cleanup_overrun_after_request_timeout_remains_unverified(self):
        self.timeout_request()
        def close(deadline):
            self.now[0] = deadline + 0.1
        self.transport.close = close
        error, receipt = self.assert_failure('IncompleteEvidence')
        self.assertEqual(error.request_failure_code, 'TimedOut')
        self.assertEqual(error.cleanup_failure_code, 'IncompleteEvidence')
        self.assertGreater(receipt['host_finished'], receipt['host_deadline'])
        self.assertFalse(self.transport.closed)

class VerifiedLateCleanupTests(unittest.TestCase):
    def run_attempt(self, request_failure, finished):
        with tempfile.TemporaryDirectory() as directory:
            store = p.EvidenceStore(Path(directory)/'private')
            now = [1]
            runner = p.AttemptRunner(store, lambda: now[0])
            ids = p.Identity('a'*32, 'b'*32, 'c'*32)
            refs = {key: 'opaque' for key in (
                'target_ref', 'artifact_ref', 'authorization_ref', 'rules_ref',
                'assertion_alias', 'evidence_ref')}
            response = p.success(ids, 1, 2)
            if request_failure == 'Busy':
                response = {**p.base(ids), 'outcome': {
                    'kind': 'Failure', 'code': 'Busy', 'stage': 'Read'}}
            transport = MemoryTransport(p.frame(response, p.RESPONSE_CAP))
            original_read = transport.read
            def read(count, deadline):
                result = original_read(count, deadline)
                if not transport.data:
                    now[0] = 5.5
                return result
            def close(deadline):
                self.assertEqual(deadline, 6.5)
                now[0] = finished
                transport.closed = True
            transport.read = read
            transport.close = close
            expected = request_failure or 'TimedOut'
            with self.assertRaises(p.ProbeError) as caught:
                runner.run(ids, transport, 10, refs,
                           lambda: request_failure == 'Cancelled')
            self.assertEqual(caught.exception.code, expected)
            self.assertEqual(store.verify()[0]['receipt']['failure_code'], expected)
            self.assertTrue(transport.closed)

    def test_late_verified_close_preserves_observer_failure(self):
        for finished in (6, 6.1):
            with self.subTest(finished=finished):
                self.run_attempt('Busy', finished)

    def test_late_verified_close_preserves_cancellation(self):
        for finished in (6, 6.1):
            with self.subTest(finished=finished):
                self.run_attempt('Cancelled', finished)

    def test_late_completion_cannot_turn_success_into_a_verified_attempt(self):
        for finished in (6, 6.1):
            with self.subTest(finished=finished):
                self.run_attempt(None, finished)

class HostFailureEnvelopeTests(unittest.TestCase):
    def test_both_failure_causes_survive_durable_readback(self):
        with tempfile.TemporaryDirectory() as directory:
            store = p.EvidenceStore(Path(directory)/'private')
            receipt = {**complete_receipt(), 'failure_code': 'IncompleteEvidence'}
            causes = {'request_code': 'TimedOut', 'cleanup_code': 'IncompleteEvidence'}
            store.append(store.reserve(), receipt, host_failures=causes)
            replay = p.EvidenceStore(store.root).verify()[0]
            self.assertEqual(replay['host_failures'], causes)
            self.assertEqual(set(replay['receipt']), p.RECEIPT_FIELDS)

    def test_unknown_or_inconsistent_host_causes_are_rejected(self):
        for causes in ({'raw': 'private detail'}, {'request_code': 'TimedOut'},
                       {'cleanup_code': 'TimedOut'},
                       {'cleanup_code': 'IncompleteEvidence', 'request_code': '/private/path'}):
            with self.subTest(causes=causes), tempfile.TemporaryDirectory() as directory:
                store = p.EvidenceStore(Path(directory)/'private')
                receipt = {**complete_receipt(), 'failure_code': 'IncompleteEvidence'}
                with self.assertRaises(p.ProbeError):
                    store.append(store.reserve(), receipt, host_failures=causes)
                self.assertEqual(list(store.root.iterdir()), [])

    def test_recomputed_hash_cannot_authorize_invalid_host_causes(self):
        import hashlib
        with tempfile.TemporaryDirectory() as directory:
            store = p.EvidenceStore(Path(directory)/'private')
            receipt = {**complete_receipt(), 'failure_code': 'IncompleteEvidence'}
            store.append(store.reserve(), receipt,
                         host_failures={'cleanup_code': 'IncompleteEvidence'})
            path = next(store.root.iterdir())
            entry = json.loads(path.read_bytes())
            entry['host_failures']['request_code'] = 'Unrecognized'
            del entry['digest']
            entry['digest'] = hashlib.sha256(p.compact(entry)).hexdigest()
            path.write_bytes(p.compact(entry))
            with self.assertRaises(p.ProbeError):
                store.verify()

    def test_maximal_private_record_still_fits_existing_bound(self):
        with tempfile.TemporaryDirectory() as directory:
            store = p.EvidenceStore(Path(directory)/'private')
            receipt = {**complete_receipt(), 'failure_code': 'IncompleteEvidence',
                       'host_started': 2**64-5001, 'host_deadline': 2**64-1,
                       'host_finished': 2**64-1, 'response_body_bytes': p.RESPONSE_CAP}
            for key in ('target_ref', 'artifact_ref', 'authorization_ref',
                        'rules_ref', 'assertion_alias', 'evidence_ref'):
                receipt[key] = 'x'*256
            store.append(store.reserve(), receipt, host_failures={
                'cleanup_code': 'IncompleteEvidence', 'request_code': 'InvalidLibraryViewToken'})
            self.assertLessEqual(next(store.root.iterdir()).stat().st_size, 4096)

    def test_private_causes_are_not_wire_response_fields(self):
        ids = p.Identity('a'*32, 'b'*32, 'c'*32)
        response = {**p.base(ids), 'outcome': {
            'kind': 'Failure', 'code': 'IncompleteEvidence', 'stage': 'Transport'},
            'host_failures': {'request_code': 'TimedOut', 'cleanup_code': 'IncompleteEvidence'}}
        with self.assertRaises(p.ProbeError):
            p.validate_response(response, ids)
