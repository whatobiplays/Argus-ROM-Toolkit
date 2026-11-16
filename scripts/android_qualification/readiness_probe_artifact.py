"""Verify a signed standalone probe APK offline. Never installs or runs it."""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import zipfile
from pathlib import Path
from .readiness_probe import require, ProbeError
from .packaging import parse_xmltree, manifest_facts, parse_badging

PACKAGE='com.argusromtoolkit.argus.readinessprobe'
METADATA='assets/readiness-probe-build.json'

def verify_inventory(apk,source_commit):
    require(re.fullmatch('[0-9a-f]{40}',source_commit) is not None)
    require(apk.is_file() and not apk.is_symlink() and apk.stat().st_size<=32*1024*1024,'IntegrityConflict')
    try:
        with zipfile.ZipFile(apk) as z:
            entries=z.infolist(); names=[i.filename for i in entries]
            require(len(names)==len(set(names)) and len(names)<=4096,'IntegrityConflict')
            require(all(not n.startswith(('/', 'lib/', 'assets/flutter_assets/')) and '..' not in n.split('/') for n in names),'IntegrityConflict')
            require({'AndroidManifest.xml','classes.dex',METADATA}<=set(names),'IncompleteEvidence')
            require(z.getinfo(METADATA).file_size<=256,'ResourceLimitExceeded')
            raw=z.read(METADATA)
            expected={'source_commit':source_commit,'variant':'probe'}
            require(json.loads(raw)==expected,'IntegrityConflict')
    except (OSError,zipfile.BadZipFile,ValueError,KeyError): raise ProbeError('IntegrityConflict') from None
    return hashlib.sha256(apk.read_bytes()).hexdigest()

def verify_signature(text,certificate):
    require(re.fullmatch('[0-9a-f]{64}',certificate) is not None)
    digests=re.findall(r'^Signer #[0-9]+ certificate SHA-256 digest: ([0-9a-fA-F]{64})$',text,re.M)
    require(len(digests)==1 and digests[0].lower()==certificate,'IntegrityConflict')

def verify_manifest(text,badging):
    text=re.sub(r'\(type 0x12\)0xffffffff', 'true', text)
    text=re.sub(r'\(type 0x12\)0x0\b', 'false', text)
    tree=parse_xmltree(text); facts=manifest_facts(tree); package=parse_badging(re.sub(r"^sdkVersion:", "minSdkVersion:", badging, flags=re.M))
    require(package.package_id==PACKAGE and package.min_sdk==30 and package.target_sdk==36 and not package.debuggable_line,'IntegrityConflict')
    require(facts.application_name in (None,'android.app.Application') and facts.debuggable is not True,'IntegrityConflict')
    require(not (facts.permissions or facts.services or facts.providers or facts.receivers),'IntegrityConflict')
    require(len(facts.activities)==2,'IntegrityConflict')
    activities={c.name:c for c in facts.activities}
    def component(name): return activities.get('.'+name) or activities.get(PACKAGE+'.'+name)
    launcher,control=component('LauncherActivity'),component('ProbeControlActivity')
    require(launcher is not None and control is not None,'IntegrityConflict')
    require(launcher.exported is True and control.exported is False,'IntegrityConflict')
    require(launcher.intent_actions==('android.intent.action.MAIN',) and launcher.intent_categories==('android.intent.category.LAUNCHER',),'IntegrityConflict')
    require(not control.intent_actions and not control.intent_categories,'IntegrityConflict')
    # The generic product facts omit aliases; inspect the parsed tree too.
    def walk(node):
        require(node.name not in ('activity-alias','instrumentation','uses-permission','permission'),'IntegrityConflict')
        if node.name=='application': require(node.attributes.get('allowBackup')=='false','IntegrityConflict')
        for child in node.children: walk(child)
    walk(tree)

def run_tool(args):
    try:
        result=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,timeout=30,check=True)
        require(len(result.stdout)<=4*1024*1024,'ResourceLimitExceeded')
        return result.stdout.decode('utf-8',errors='strict')
    except (OSError,subprocess.SubprocessError,UnicodeError): raise ProbeError('IncompleteEvidence') from None

def parser():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--apk',required=True,type=Path)
    p.add_argument('--source-commit',required=True)
    p.add_argument('--certificate-sha256',required=True)
    p.add_argument('--aapt2',default='aapt2')
    p.add_argument('--apksigner',default='apksigner')
    return p

def main(argv=None):
    args=parser().parse_args(argv)
    try:
        digest=verify_inventory(args.apk,args.source_commit)
        for name in (args.aapt2,args.apksigner): require(shutil.which(name) is not None,'IncompleteEvidence')
        apk=str(args.apk.resolve())
        signature=run_tool([args.apksigner,'verify','--print-certs','--verbose','--min-sdk-version','30',apk])
        verify_signature(signature,args.certificate_sha256)
        manifest=run_tool([args.aapt2,'dump','xmltree','--file','AndroidManifest.xml',apk])
        badging=run_tool([args.aapt2,'dump','badging',apk])
        verify_manifest(manifest,badging)
        print(json.dumps({'apk_sha256':digest,'source_commit':args.source_commit,'verification':'offline-only'}))
        return 0
    except Exception:
        print('Probe artifact verification failed')
        return 1

if __name__=='__main__': raise SystemExit(main())
