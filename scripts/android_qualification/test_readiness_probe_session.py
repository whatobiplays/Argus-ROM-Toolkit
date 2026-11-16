"""Forward ownership, correlation and bounded diagnostic tests."""
import unittest
from . import readiness_probe_session as s
from .readiness_probe import ProbeError


def parse_diagnostic(chunks,profile,clock,deadline,**kwargs):
    """Fixture approval record; mismatch tests call the production API directly."""
    binding=None
    if isinstance(profile,s.DiagnosticProfile):
        binding=s.DiagnosticBinding(profile.build,profile.package,profile.source,s.profile_digest(profile))
    return s.parse_diagnostic(chunks,profile,clock,deadline,binding=binding,**kwargs)

class FakeADB:
    def __init__(self): self.forwards={}; self.removed=[]; self.deadlines=[]
    def identity(self,target,*,deadline):
        self.deadlines.append(deadline); return (target,"build")
    def lookup(self,target,local,*,deadline):
        self.deadlines.append(deadline); return self.forwards.get((target,local))
    def create_no_rebind(self,target,local,remote,*,deadline):
        self.deadlines.append(deadline)
        if (target,local) in self.forwards: raise RuntimeError()
        self.forwards[target,local]=remote
    def remove(self,target,local,*,deadline):
        self.deadlines.append(deadline); self.removed.append((target,local)); del self.forwards[target,local]

class SessionTests(unittest.TestCase):
    def session(self): return s.ForwardSession(FakeADB(),'target','build','a'*32,'tcp:12345','localabstract:probe_session',0,600,clock=lambda:2,obligation=lambda record:None)
    def test_owner_correlation(self):
        x=self.session(); x.create(); x.arm('b'*32,1)
        x.correlate(s.Discovery('a'*32,'b'*32,'localabstract:probe_session',1,2000,100,200),1.1,1.2,0,True)
        with self.assertRaises(ProbeError): x.enforce(2000,False)
        x.enforce(2000,True)
        with self.assertRaises(ProbeError): x.enforce(2000,True)
        x.cleanup(); self.assertEqual(len(x.adb.removed),1)
    def test_unsolicited_and_stale(self):
        for count,session in [(2,'a'*32),(1,'c'*32)]:
            x=self.session(); x.create(); x.arm('b'*32,1)
            with self.assertRaises(ProbeError):
                x.correlate(s.Discovery(session,'b'*32,'localabstract:probe_session',count,2000,100,200),1.1,1.2,0,True)
            with self.assertRaises(ProbeError): x.enforce(2000,True)
    def test_collision_and_replacement(self):
        x=self.session(); x.adb.forwards[x.target,x.local]='other'
        with self.assertRaises(ProbeError): x.create()
        x=self.session(); x.create(); x.adb.forwards[x.target,x.local]='other'
        with self.assertRaises(ProbeError): x.cleanup()
        self.assertEqual(x.adb.removed,[])
    def test_parser_no_default_profile(self):
        with self.assertRaises(ProbeError): parse_diagnostic([b'secret'],None,lambda:0,5)
    def test_parser_immediate_filter_and_bounds(self):
        profile=s.DiagnosticProfile('profile','build','com.example.probe',
            r'^TARGET (?P<package>com\.example\.probe) task=(?P<task>[0-9]+) resumed=(?P<resumed>true|false)$', 'END')
        r=parse_diagnostic([b'unrelated secret\nTARGET com.example.probe task=42 resumed=true\nEND\n'],profile,lambda:0,5,exit_code=lambda:0)
        self.assertEqual(r,{'profile':'profile','build':'build','package':'com.example.probe','task_id':42,'resumed':True})
        with self.assertRaises(ProbeError): parse_diagnostic([b'x'*16385],profile,lambda:0,5)
        with self.assertRaises(ProbeError): parse_diagnostic([b'END\n'],profile,lambda:0,5)

class ExpiryTests(SessionTests):
    def test_enforcement_expiry_and_owned_obligation(self):
        journal=[]
        now=[0]
        x=s.ForwardSession(FakeADB(),'target','build','a'*32,'tcp:12345','localabstract:probe_session',0,600,clock=lambda:now[0],obligation=journal.append)
        x.create()
        self.assertEqual(journal[0]['state'],'creation-pending')
        self.assertEqual(journal[1]['state'],'owned')
        now[0]=2
        x.arm('b'*32,1)
        x.correlate(s.Discovery('a'*32,'b'*32,'localabstract:probe_session',1,2000,100,200),1.1,1.2,0,True)
        now[0]=601
        with self.assertRaises(ProbeError): x.enforce(2000,True)

class DiagnosticCompletionTests(unittest.TestCase):
    def setUp(self):
        self.profile=s.DiagnosticProfile('profile','build','com.example.probe',
            r'^TARGET (?P<package>com\.example\.probe) task=(?P<task>[0-9]+) resumed=(?P<resumed>true|false)$', 'END')
        self.output=b'TARGET com.example.probe task=42 resumed=true\nEND\n'
    def test_trailing_output_never_publishes(self):
        for tail in (b'x', b'foreign application', b'unsupported\n', b'END\n',
                     b'TARGET com.example.probe task=43 resumed=false\n', b'\xff', b'\n'):
            for chunks in ([self.output+tail], [self.output,tail]):
                with self.subTest(tail=tail,chunks=len(chunks)), self.assertRaises(ProbeError):
                    parse_diagnostic(chunks,self.profile,lambda:0,5,exit_code=lambda:0)
    def test_requires_successful_exit_after_exhaustion(self):
        events=[]
        def chunks():
            yield self.output
            events.append('exhausted')
        def exit_code():
            events.append('exit')
            return 1
        with self.assertRaises(ProbeError):
            parse_diagnostic(chunks(),self.profile,lambda:0,5,exit_code=exit_code)
        self.assertEqual(events,['exhausted','exit'])
    def test_absent_exit_proof_blocks_complete_marker(self):
        with self.assertRaises(ProbeError): parse_diagnostic([self.output],self.profile,lambda:0,5)
    def test_cap_applies_to_acquisition(self):
        chunks=[b'x'*16383+b'\n']*64+[self.output]
        with self.assertRaises(ProbeError):
            parse_diagnostic(chunks,self.profile,lambda:0,5,exit_code=lambda:0)

    def test_success_waits_for_exhaustion_and_exit(self):
        events=[]
        def chunks():
            yield self.output[:10]
            yield self.output[10:]
            events.append('exhausted')
        def exit_code():
            events.append('exit')
            return 0
        result=parse_diagnostic(chunks(),self.profile,lambda:0,5,exit_code=exit_code)
        self.assertEqual(events,['exhausted','exit'])
        self.assertEqual(result['task_id'],42)
    def test_exit_timeout_and_unavailable_status(self):
        for status in (None,True,-1):
            with self.subTest(status=status),self.assertRaises(ProbeError):
                parse_diagnostic([self.output],self.profile,lambda:0,5,exit_code=lambda:status)
        now=[0]
        def exit_code():
            now[0]=5
            return 0
        with self.assertRaises(ProbeError) as caught:
            parse_diagnostic([self.output],self.profile,lambda:now[0],5,exit_code=exit_code)
        self.assertEqual(caught.exception.code,'TimedOut')

class ForwardDeadlineTests(unittest.TestCase):
    def setUp(self):
        self.now=[0]
        self.adb=FakeADB()
        self.session=s.ForwardSession(self.adb,'target','build','a'*32,'tcp:12345',
            'localabstract:probe_session',0,600,clock=lambda:self.now[0],obligation=lambda row:None)
        self.session.create()
    def test_expired_cleanup_never_removes(self):
        self.now[0]=660
        with self.assertRaises(ProbeError): self.session.cleanup()
        self.assertEqual(self.adb.removed,[])
        self.assertTrue(self.session.owned)
    def test_cleanup_reserve_usable_after_session_expiry(self):
        self.now[0]=601
        self.session.cleanup()
        self.assertEqual(len(self.adb.removed),1)
        self.assertTrue(all(deadline<=606 for deadline in self.adb.deadlines))
    def test_late_lookup_never_removes(self):
        original=self.adb.lookup
        def lookup(target,local,*,deadline):
            result=original(target,local,deadline=deadline)
            self.now[0]=deadline
            return result
        self.adb.lookup=lookup
        with self.assertRaises(ProbeError): self.session.cleanup()
        self.assertEqual(self.adb.removed,[])
        self.assertTrue(self.session.owned)
    def test_late_or_wrong_identity_never_removes(self):
        for late in (True,False):
            self.now[0]=0
            def identity(target,*,deadline):
                if late: self.now[0]=deadline
                return ('target','build') if late else ('target','other-build')
            self.adb.identity=identity
            with self.subTest(late=late),self.assertRaises(ProbeError): self.session.cleanup()
            self.assertEqual(self.adb.removed,[])
    def test_late_post_removal_readback_keeps_obligation(self):
        original=self.adb.lookup
        def lookup(target,local,*,deadline):
            result=original(target,local,deadline=deadline)
            if self.adb.removed: self.now[0]=deadline
            return result
        self.adb.lookup=lookup
        with self.assertRaises(ProbeError): self.session.cleanup()
        self.assertEqual(len(self.adb.removed),1)
        self.assertTrue(self.session.owned)
        self.assertNotEqual(self.session.state,'Closed')
    def test_expired_arm_uses_clock_despite_old_supplied_time(self):
        self.now[0]=600
        with self.assertRaises(ProbeError): self.session.arm('b'*32,1)
    def test_expired_correlation_uses_clock_despite_old_interval(self):
        self.now[0]=1
        self.session.arm('b'*32,1)
        self.now[0]=600
        with self.assertRaises(ProbeError):
            self.session.correlate(s.Discovery('a'*32,'b'*32,'localabstract:probe_session',1,2000,100,200),1.1,1.2,0,True)
    def test_cleanup_call_deadlines_clip_to_reserve_end(self):
        self.now[0]=659
        self.adb.deadlines.clear()
        self.session.cleanup()
        self.assertTrue(self.adb.deadlines)
        self.assertEqual(set(self.adb.deadlines),{660})
    def test_late_post_removal_identity_keeps_obligation(self):
        def identity(target,*,deadline):
            if self.adb.removed: self.now[0]=deadline
            return (target,'build')
        self.adb.identity=identity
        with self.assertRaises(ProbeError): self.session.cleanup()
        self.assertEqual(len(self.adb.removed),1)
        self.assertTrue(self.session.owned)
        self.assertNotEqual(self.session.state,'Closed')

class DiagnosticBindingTests(DiagnosticCompletionTests):
    def test_missing_approval_binding(self):
        with self.assertRaises(ProbeError):
            s.parse_diagnostic([self.output],self.profile,lambda:0,5,exit_code=lambda:0)
    def test_mismatched_build_package_source_or_digest(self):
        from dataclasses import replace
        approved=s.DiagnosticBinding('build','com.example.probe',s.DIAGNOSTIC_COMMAND,s.profile_digest(self.profile))
        for binding in (replace(approved,build='other-build'),replace(approved,package='com.other.probe'),
                        replace(approved,source=('shell','other')),replace(approved,profile_sha256='0'*64)):
            with self.subTest(binding=binding),self.assertRaises(ProbeError):
                s.parse_diagnostic([self.output],self.profile,lambda:0,5,exit_code=lambda:0,binding=binding)
    def test_invalid_profile_fields(self):
        from dataclasses import replace
        approved=s.DiagnosticBinding('build','com.example.probe',s.DIAGNOSTIC_COMMAND,s.profile_digest(self.profile))
        for field,value in (('name',''),('build','bad\nprivate'),('package','com..probe'),
                            ('source',('shell','other')),('target_line_pattern','.*'),
                            ('target_line_pattern','['),('completion_line',''),('completion_line','END\n')):
            with self.subTest(field=field),self.assertRaises(ProbeError):
                s.parse_diagnostic([self.output],replace(self.profile,**{field:value}),lambda:0,5,
                                   exit_code=lambda:0,binding=approved)
    def test_task_id_must_fit_android_signed_integer(self):
        approved=s.DiagnosticBinding('build','com.example.probe',s.DIAGNOSTIC_COMMAND,s.profile_digest(self.profile))
        output=self.output.replace(b'task=42',b'task=9999999999')
        with self.assertRaises(ProbeError):
            s.parse_diagnostic([output],self.profile,lambda:0,5,exit_code=lambda:0,binding=approved)

class DiscoveryIntervalTests(unittest.TestCase):
    def test_invalid_android_intervals(self):
        for started,finished in ((-1,0),(2,1),(0,6001),(False,1),(0,1.5),(0,2**64)):
            with self.subTest(started=started,finished=finished),self.assertRaises(ProbeError):
                s.Discovery('a'*32,'b'*32,'localabstract:probe_session',1,2000,started,finished)
    def test_records_source_bound_android_interval_without_clock_conversion(self):
        now=[1]; records=[]
        session=s.ForwardSession(FakeADB(),'target','build','a'*32,'tcp:12345',
            'localabstract:probe_session',0,600,clock=lambda:now[0],obligation=records.append)
        session.create(); session.arm('b'*32,1)
        now[0]=2
        observation=s.Discovery('a'*32,'b'*32,'localabstract:probe_session',1,2000,9000000,9006000)
        session.correlate(observation,1.1,1.2,0,True)
        record=next(row for row in records if row['state']=='discovery-correlated')
        self.assertEqual((record['android_started_ms'],record['android_finished_ms']),(9000000,9006000))
        self.assertEqual((record['host_started'],record['host_finished']),(1.1,1.2))
        self.assertEqual(record['connection_count'],1)

    def test_release_allowance_does_not_extend_host_admission_gate(self):
        now=[1]
        session=s.ForwardSession(FakeADB(),'target','build','a'*32,'tcp:12345',
            'localabstract:probe_session',0,600,clock=lambda:now[0],obligation=lambda row:None)
        session.create(); session.arm('b'*32,1)
        observation=s.Discovery('a'*32,'b'*32,'localabstract:probe_session',1,2000,9000000,9005001)
        now[0]=6
        with self.assertRaises(ProbeError): session.correlate(observation,1.1,1.2,0,True)
