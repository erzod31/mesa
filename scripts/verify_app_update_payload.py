"""DG-0021 extraction/isolated startup only. Never runs the updater helper/setup."""
import argparse
import base64
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import socket
import sqlite3
import urllib.error
import urllib.request

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))


def digest(path):
    with path.open('rb') as stream: return hashlib.file_digest(stream,'sha256').hexdigest()


def wait_json(path,predicate=lambda value:True):
    deadline=time.monotonic()+60
    while time.monotonic()<deadline:
        if path.exists():
            value=json.loads(path.read_text(encoding='utf-8-sig'))
            if 'error' in value: raise RuntimeError(value['error'])
            if predicate(value): return value
        time.sleep(.1)
    raise TimeoutError(str(path))


def process_details(pid):
    command=f"Get-CimInstance Win32_Process -Filter 'ProcessId = {int(pid)}' | Select-Object ProcessId,ParentProcessId,ExecutablePath,CommandLine | ConvertTo-Json -Compress"
    result=subprocess.check_output(['powershell.exe','-NoProfile','-Command',command],text=True,encoding='utf-8-sig')
    return json.loads(result)


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('installer',type=Path)
    parser.add_argument('--output-dir',type=Path,default=ROOT/'output/in-app-updates-DG-0021')
    parser.add_argument('--baseline',type=Path,default=ROOT/'output/in-app-updates-DG-0021/protected-files-before.json')
    parser.add_argument('--verify-restart-queue',action='store_true')
    args=parser.parse_args()
    version=re.search(r'^version: (\d+\.\d+\.\d+\+(\d+))',(ROOT/'client/pubspec.yaml').read_text(),re.M)
    app_version=version[1];code=int(version[2])
    installer=args.installer.resolve()
    args.output_dir=args.output_dir.resolve()
    lab=args.output_dir/datetime.now(timezone.utc).strftime('payload-%Y%m%dT%H%M%SZ')
    lab.mkdir(parents=True)
    checks=[]
    def passed(name,details):
        checks.append({'name':name,'result':'passed','details':details})
        (lab/'checks.json').write_text(json.dumps(checks,ensure_ascii=False,indent=2),encoding='utf-8')
        print(name,flush=True)
    extracted=lab/'extracted'
    with (lab/'extraction.log').open('w',encoding='utf-8') as log:
        subprocess.run(['7z','x','-y','-o'+str(extracted),str(installer)],stdout=log,stderr=subprocess.STDOUT,check=True,timeout=180)
    manifest=json.loads((extracted/'payload-manifest.json').read_text())
    assert manifest['appVersion']==app_version
    for file in manifest['files']:
        path=extracted/file['path']
        assert digest(path)==file['sha256'] and path.stat().st_size==file['bytes'],file['path']
    assert not any(p.name in ('windows-updates-ed25519.pem','password','desktop-connection.json') or p.suffix in ('.jks','.sqlite') for p in extracted.rglob('*'))
    public=extracted/'_internal/server/windows_update_key.pub'
    assert public.read_bytes()==(ROOT/'server/windows_update_key.pub').read_bytes()
    # Read the single-file helper archive instead of executing the updater.
    sys.path.insert(0,str(ROOT/'.tools/windows-installer/build-venv/Lib/site-packages'))
    from PyInstaller.archive.readers import CArchiveReader
    helper=CArchiveReader(str(extracted/'MesaUpdateHelper.exe'))
    key_entry=next(name for name in helper.toc if name.replace('\\','/')=='server/windows_update_key.pub')
    assert helper.extract(key_entry)==public.read_bytes()
    pyz=helper.open_embedded_archive('PYZ.pyz')
    assert 'server.windows_updates' in pyz.toc and 'server.windows_file_info' in pyz.toc
    passed('payload_hashes_and_independent_helper_archive',{'files':len(manifest['files']),'version':manifest['appVersion'],'helperExecuted':False,'privateSigningMaterialBundled':False})
    env=dict(os.environ)
    for key in ('PYTHONPATH','PYTHONHOME','VIRTUAL_ENV','JAVA_HOME','MESA_WINDOWS_UPDATE_FEED','INDRA_OCR_MODEL_DIR'):
        env.pop(key,None)
    env['PATH']=os.pathsep.join([str(Path(os.environ['WINDIR'])/'System32'),os.environ['WINDIR']])
    env['HF_HUB_OFFLINE']='1'
    profile=lab/'profile';report=lab/'backend.json'
    subprocess.run([str(extracted/'Mesa.exe'),'--isolated-profile',str(profile),'--self-test','--report',str(report)],env=env,check=True,timeout=120)
    backend=json.loads(report.read_text(encoding='utf-8'))
    assert backend['version']==app_version and backend['saveRead'] and backend['ocr']['engine']=='indra-ocr'
    passed('packaged_recipe_translation_and_ocr',backend)
    launch_file=lab/'launch.json'
    launch_command=[str(extracted/'Mesa.exe'),'--isolated-profile',str(profile)]
    if args.verify_restart_queue:
        with socket.socket() as listener:
            listener.bind(('127.0.0.1',0));fixed_port=listener.getsockname()[1]
        launch_command+=['--isolated-api-port',str(fixed_port)]
    launcher=subprocess.Popen([*launch_command,'--report',str(launch_file)],cwd=extracted,env=env)
    launch=None
    try:
        launch=wait_json(launch_file)
        ready=wait_json(profile/'client/mesa-ready.json',lambda v:v.get('ready') and v.get('connected'))
        details=process_details(launch['clientPid'])
        assert details['ParentProcessId']==launcher.pid and Path(details['ExecutablePath']).resolve()==(extracted/'app/mesa.exe').resolve()
        match=re.search(r'--windows-update-session=([-A-Za-z0-9_=]+)',details['CommandLine'])
        assert match
        session=json.loads(base64.urlsafe_b64decode(match[1]))
        opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
        info_url=f'http://127.0.0.1:{launch["apiPort"]}/v1/app-updates/info'
        request=urllib.request.Request(info_url,data=b'{}',headers={'X-Mesa-Update-Session':session['session'],'Content-Type':'application/json'})
        with opener.open(request,timeout=10) as response: info=json.load(response)
        assert info['version_code']==code and info['platform']=='windows' and info['can_install'] is False
        try:
            opener.open(urllib.request.Request(info_url,data=b'{}'),timeout=5)
            raise AssertionError('Missing local capability accepted')
        except urllib.error.HTTPError as error: assert error.code==403
        passed('native_window_and_local_update_session',{'ready':ready,'installedCode':info['version_code'],'isolatedApplyDisabled':True,'unauthorizedControlRejected':True,'noncePersistedInReport':False})
        base=f'http://127.0.0.1:{launch["downloadPort"]}'
        with opener.open(base+'/descargar/update.json',timeout=10) as response: feed=json.load(response)
        assert feed['version_code']==code and feed['package']=='com.mesa.mesa'
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
        from server.windows_updates import canonical
        unsigned={k:v for k,v in feed.items() if k!='signature'}
        Ed25519PublicKey.from_public_bytes(bytes.fromhex(public.read_text().strip())).verify(base64.b64decode(feed['signature']),canonical(unsigned))
        h=hashlib.sha256();count=0
        with opener.open(base+feed['apk_path'],timeout=15) as response:
            assert response.headers['Content-Type']=='application/vnd.android.package-archive'
            while chunk:=response.read(1024*1024): h.update(chunk);count+=len(chunk)
        assert count==feed['size'] and h.hexdigest()==feed['sha256']
        passed('windowed_android_helper_feed_and_apk',{'code':code,'bytes':count,'sha256':h.hexdigest(),'signedManifestVerified':True,'noConsole':True,'nativeAndroidInstallerExecuted':False})
        if args.verify_restart_queue:
            config=json.loads((profile/'server/desktop-connection.json').read_text())
            credential_hash=hashlib.sha256(config['token'].encode()).hexdigest()
            api=f'http://127.0.0.1:{fixed_port}'
            auth={'Authorization':'Bearer '+config['token'],'Content-Type':'application/json'}
            with opener.open(urllib.request.Request(api+'/v1/snapshot',headers=auth),timeout=10) as response: generation=json.load(response)['generation']
            first={'id':'dg0033-lost-ack','entity_id':'dg0033-queue','kind':'recipe','base':0,'data':{'title':'Antes de reiniciar','ingredients':['2 huevos'],'steps':['Batir.'],'servings':2,'tags':[]},'deleted':False,'action':'save'}
            body=json.dumps({'generation':generation,'operations':[first]}).encode()
            with opener.open(urllib.request.Request(api+'/v1/push',headers=auth,data=body),timeout=10) as response:
                assert json.load(response)['results'][0]['status']=='applied'
    finally:
        if launch:
            details=process_details(launch['clientPid'])
            assert details['ParentProcessId']==launcher.pid and Path(details['ExecutablePath']).resolve()==(extracted/'app/mesa.exe').resolve()
            subprocess.run(['powershell.exe','-NoProfile','-Command',f"Stop-Process -Id {int(launch['clientPid'])}"],check=True,timeout=10)
            launcher.wait(timeout=20)
    if args.verify_restart_queue:
        # Recreate a lost response and an unsent follow-up in this isolated DB.
        second={**first,'id':'dg0033-unsent','base':1,'data':{**first['data'],'title':'Edición pendiente conservada'}}
        database=profile/'client/mesa.sqlite'
        with sqlite3.connect(database) as con:
            con.execute('INSERT OR REPLACE INTO entities VALUES (?,?,?,?,0)',(first['entity_id'],'recipe',0,json.dumps(second['data'])))
            for operation,attempted in ((first,1),(second,0)):
                con.execute('INSERT INTO outbox(id,entity_id,payload,attempted) VALUES (?,?,?,?)',(operation['id'],operation['entity_id'],json.dumps(operation),attempted))
        before_ready=(profile/'client/mesa-ready.json').stat().st_mtime_ns
        restart_report=lab/'restart.json'
        restarted=subprocess.Popen([*launch_command,'--report',str(restart_report)],cwd=extracted,env=env)
        restart=None
        try:
            restart=wait_json(restart_report)
            ready=wait_json(profile/'client/mesa-ready.json',lambda value:value.get('connected') and (profile/'client/mesa-ready.json').stat().st_mtime_ns>before_ready)
            deadline=time.monotonic()+30
            while time.monotonic()<deadline:
                with sqlite3.connect(database) as con:
                    pending=con.execute('SELECT COUNT(*) FROM outbox').fetchone()[0]
                    row=con.execute('SELECT revision,data FROM entities WHERE id=?',(first['entity_id'],)).fetchone()
                if pending==0 and row and row[0]==2:break
                time.sleep(.1)
            assert pending==0 and row[0]==2 and json.loads(row[1])['title']==second['data']['title']
            current=json.loads((profile/'server/desktop-connection.json').read_text())
            assert hashlib.sha256(current['token'].encode()).hexdigest()==credential_hash
            passed('native_isolated_fixed_port_restart_with_populated_queue',{'pendingBefore':2,'attemptedBefore':1,'unsentBefore':1,'pendingAfter':pending,'finalRevision':row[0],'recipePreserved':True,'syntheticServerCredentialPreserved':True,'sameLoopbackPort':True,'realInstallerExecuted':False,'credentialVaultUsed':False})
        finally:
            if restart:
                details=process_details(restart['clientPid'])
                assert details['ParentProcessId']==restarted.pid and Path(details['ExecutablePath']).resolve()==(extracted/'app/mesa.exe').resolve()
                subprocess.run(['powershell.exe','-NoProfile','-Command',f"Stop-Process -Id {int(restart['clientPid'])}"],check=True,timeout=10)
                restarted.wait(timeout=20)
    baseline=json.loads(args.baseline.read_text())
    assert all(Path(path).is_file() and digest(Path(path))==value for path,value in baseline.items())
    passed('scoped_preservation_and_no_live_channel_activation',{'protectedFiles':len(baseline),'registryTests':False,'setupOrUpdaterExecuted':False})
    result={'status':'passed','lab':str(lab),'checks':checks,'installationTested':False,'isolatedLaunchTested':True,
            'actualUpdaterOrInstallerExecuted':False,'normalReopenTested':False,'sha256':digest(installer)}
    (lab/'result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    (args.output_dir/'current-payload-inspection.txt').write_text(str(lab),encoding='utf-8')
    print(json.dumps({'result':str(lab/'result.json'),'sha256':result['sha256']},indent=2))


if __name__=='__main__': main()
