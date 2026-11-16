"""Offline probe APK inventory and signing identity tests."""
import tempfile
import unittest
import zipfile
from pathlib import Path
from . import readiness_probe_artifact as a
from .readiness_probe import ProbeError

class ArtifactTests(unittest.TestCase):
    def apk(self,root,metadata=b'{"source_commit":"'+b'a'*40+b'","variant":"probe"}',extra=None):
        path=Path(root)/'probe.apk'
        with zipfile.ZipFile(path,'w') as z:
            z.writestr('AndroidManifest.xml',b'manifest')
            z.writestr('classes.dex',b'dex')
            z.writestr(a.METADATA,metadata)
            if extra: z.writestr(extra,b'x')
        return path
    def test_metadata(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(len(a.verify_inventory(self.apk(d),'a'*40)),64)
            with self.assertRaises(ProbeError): a.verify_inventory(self.apk(d),'b'*40)
    def test_product_and_native_payload_rejected(self):
        for name in ['lib/arm64-v8a/libargus.so','assets/flutter_assets/kernel_blob.bin']:
            with tempfile.TemporaryDirectory() as d, self.assertRaises(ProbeError): a.verify_inventory(self.apk(d,extra=name),'a'*40)
    def test_signer_digest(self):
        a.verify_signature('Signer #1 certificate SHA-256 digest: '+'b'*64+'\n', 'b'*64)
        with self.assertRaises(ProbeError): a.verify_signature('Signer #1 certificate SHA-256 digest: '+'c'*64,'b'*64)
    def test_cli_help(self):
        self.assertIsNotNone(a.parser().parse_args(['--apk','x','--source-commit','a'*40,'--certificate-sha256','b'*64]))

class ManifestTests(unittest.TestCase):
    def test_manifest_closed_components(self):
        text='''E: manifest (line=1)
  E: application (line=2)
    A: android:allowBackup(0x01010280)=(type 0x12)0x0
    E: activity (line=3)
      A: android:name(0x01010003)=".LauncherActivity" (Raw: ".LauncherActivity")
      A: android:exported(0x01010010)=(type 0x12)0xffffffff
      E: intent-filter (line=4)
        E: action (line=5)
          A: android:name(0x01010003)="android.intent.action.MAIN" (Raw: "android.intent.action.MAIN")
        E: category (line=6)
          A: android:name(0x01010003)="android.intent.category.LAUNCHER" (Raw: "android.intent.category.LAUNCHER")
    E: activity (line=7)
      A: android:name(0x01010003)=".ProbeControlActivity" (Raw: ".ProbeControlActivity")
      A: android:exported(0x01010010)=(type 0x12)0x0
'''
        badging="package: name='com.argusromtoolkit.argus.readinessprobe' versionCode='1' versionName='1.0'\nsdkVersion:'30'\ntargetSdkVersion:'36'\n"
        a.verify_manifest(text,badging)
        with self.assertRaises(ProbeError): a.verify_manifest(text.replace('0x0\n','0xffffffff\n'),badging)
