"""Extract a release and exercise its own OCR runtime; never run setup/uninstall."""
import argparse
from datetime import datetime, timezone
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream,'sha256').hexdigest()


def protected_files():
    result={}
    for folder in (ROOT/'data',ROOT/'.tools/signing',Path(os.environ['APPDATA'])/'com.mesa',Path(os.environ['LOCALAPPDATA'])/'Mesa'):
        result[str(folder)]='directory' if folder.is_dir() else None
        if folder.is_dir():
            for file in folder.rglob('*'):
                if file.is_file(): result[str(file)]=digest(file)
    for file in (ROOT/'dist').glob('*'):
        if file.is_file() and ('1.16.' in file.name or file.name in ('Mesa-Android.apk','android-update.json')):
            result[str(file)]=digest(file)
    return result


def wait_json(path, predicate=lambda value: True, timeout=60):
    deadline=time.monotonic()+timeout
    while time.monotonic()<deadline:
        if path.exists():
            try: value=json.loads(path.read_text(encoding='utf-8-sig'))
            except json.JSONDecodeError: time.sleep(.1); continue
            if 'error' in value: raise RuntimeError(value['error'])
            if predicate(value): return value
        time.sleep(.1)
    raise TimeoutError(str(path))


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('installer',type=Path)
    args=parser.parse_args()
    installer=args.installer.resolve()
    lab=ROOT/'output/indra-ocr-2026-10-28'/datetime.now(timezone.utc).strftime('payload-%Y%m%dT%H%M%SZ')
    lab.mkdir(parents=True)
    baseline=protected_files()
    (lab/'protected-before.json').write_text(json.dumps(baseline,indent=2),encoding='utf-8')
    checks=[]
    def passed(name, details):
        checks.append({'name':name,'result':'passed','details':details})
        (lab/'checks.json').write_text(json.dumps(checks,ensure_ascii=False,indent=2),encoding='utf-8')
        print(name,flush=True)
    listing=subprocess.check_output(['7z','l','-slt',str(installer)],text=True,encoding='utf-8',errors='replace')
    assert 'Type = Nsis' in listing
    (lab/'archive-listing.txt').write_text(listing,encoding='utf-8')
    extracted=lab/'extracted'
    with (lab/'extraction.log').open('w',encoding='utf-8') as log:
        subprocess.run(['7z','x','-y','-o'+str(extracted),str(installer)],stdout=log,stderr=subprocess.STDOUT,check=True,timeout=180)
    manifest=json.loads((extracted/'payload-manifest.json').read_text(encoding='utf-8'))
    assert manifest['appVersion']=='1.17.0+34' and manifest['architecture']=='x64'
    for entry in manifest['files']:
        file=extracted/entry['path']
        assert file.stat().st_size==entry['bytes'] and digest(file)==entry['sha256'],entry['path']
    assert not any(p.suffix in ('.sqlite','.jks') or p.name in ('desktop-connection.json','key.properties','password') for p in extracted.rglob('*'))
    models=json.loads((extracted/'_internal/.tools/ocr/indra-v1.1.0/mesa-model-manifest.json').read_text())
    assert models['modelRevision']=='bd02167fdf2005a19962cc15188f8496a2c87d3b'
    assert (extracted/'licenses/Indra-OCR-LICENSE').is_file()
    passed('extraction_manifest_and_ocr_models',{'files':len(manifest['files']),'version':manifest['appVersion'],'modelRevision':models['modelRevision'],'privateDataBundled':False})
    env=dict(os.environ)
    for name in ('PYTHONPATH','PYTHONHOME','VIRTUAL_ENV','JAVA_HOME','INDRA_OCR_MODEL_DIR'):
        env.pop(name,None)
    env['PATH']=os.pathsep.join((str(Path(os.environ['WINDIR'])/'System32'),os.environ['WINDIR']))
    env['HF_HUB_OFFLINE']='1';env['HF_HUB_DISABLE_TELEMETRY']='1'
    profile=lab/'profile'
    report=lab/'backend.json'
    executable=extracted/'Mesa.exe'
    subprocess.run([str(executable),'--isolated-profile',str(profile),'--self-test','--report',str(report)],env=env,check=True,timeout=120)
    backend=json.loads(report.read_text(encoding='utf-8'))
    assert backend['ocr']['engine']=='indra-ocr'
    passed('private_runtime_ocr_and_recipe_self_test',backend)
    launch_file=lab/'launch.json'
    launcher=subprocess.Popen([str(executable),'--isolated-profile',str(profile),'--report',str(launch_file)],cwd=extracted,env=env)
    launch=None
    try:
        launch=wait_json(launch_file)
        ready=wait_json(profile/'client/mesa-ready.json',lambda v:v.get('ready') and v.get('connected'))
        passed('native_client_first_frame',ready)
        # This host only generates synthetic input; all inference uses the
        # extracted private runtime and its pinned model files.
        from PIL import Image, ImageDraw, ImageFont
        picture=Image.new('RGB',(1100,330),'white');draw=ImageDraw.Draw(picture)
        font=ImageFont.load_default(size=38)
        for i,text in enumerate(('Tortilla de patatas','2 huevos y 250 g de patatas','1. Batir los huevos.','2. Cocinar durante 10 minutos.')):
            draw.text((30,20+i*70),text,fill='black',font=font)
        buffer=io.BytesIO();picture.save(buffer,format='PNG');payload=buffer.getvalue()
        config=json.loads((profile/'server/desktop-connection.json').read_text())
        url=f'http://127.0.0.1:{launch["apiPort"]}/v1/ocr'
        opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
        try:
            opener.open(urllib.request.Request(url,data=payload),timeout=5)
            raise AssertionError('Anonymous OCR accepted')
        except urllib.error.HTTPError as error:
            assert error.code==401
        readings=[]
        for _ in range(2):
            request=urllib.request.Request(url,data=payload,headers={'Authorization':'Bearer '+config['token'],'Content-Type':'application/octet-stream'})
            with opener.open(request,timeout=90) as response:
                answer=json.load(response)
            assert answer['engine']=='indra-ocr'
            assert all(fragment in answer['text'] for fragment in ('2 huevos','250','Batir','10 minutos'))
            readings.append({'elapsed_ms':answer['elapsed_ms'],'text':answer['text']})
        passed('authenticated_binary_ocr_cold_and_warm',{'readings':readings,'anonymousRejected':True,'modelsOffline':True})
    finally:
        if launch:
            expected=str(extracted/'app/mesa.exe').replace("'","''")
            pid=int(launch['clientPid'])
            command=f"$p=Get-CimInstance Win32_Process -Filter 'ProcessId = {pid}'; if (!$p -or $p.ParentProcessId -ne {launcher.pid} -or $p.ExecutablePath -ine '{expected}') {{ throw 'QA child identity mismatch; no process closed' }}; Stop-Process -Id {pid}"
            subprocess.run(['powershell.exe','-NoProfile','-Command',command],check=True,timeout=15)
            launcher.wait(timeout=20)
    after=protected_files()
    (lab/'protected-after.json').write_text(json.dumps(after,indent=2),encoding='utf-8')
    assert after==baseline
    assert not list(profile.rglob('*.png')) and not list(profile.rglob('*.jpg'))
    passed('protected_data_and_previous_deliveries_unchanged',{'protectedEntries':len(baseline),'photoFilesSaved':0,'scope':'Listed files only; no registry tests or installation executed.'})
    result={'status':'passed','appVersion':manifest['appVersion'],'installerPath':str(installer),
            'sha256':digest(installer),'bytes':installer.stat().st_size,'checks':checks,
            'installationTested':False,'isolatedLaunchTested':True,
            'limitations':['No normal installation/update/uninstall or registry tests performed.',
                           'Android ARM64 package built and verified; no physical camera/share test in this run.',
                           'Windows file picker interaction not exercised; client request path is covered by Flutter tests.',
                           'OCR timings and accuracy are for a synthetic recipe, not a representative photo benchmark.',
                           'Previous Android helper and German translation limitations are outside this OCR change.']}
    (lab/'result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    (ROOT/'output/indra-ocr-2026-10-28/current-inspection.txt').write_text(str(lab),encoding='utf-8')
    print(json.dumps({'result':str(lab/'result.json'),'sha256':result['sha256']},indent=2),flush=True)


if __name__=='__main__':
    main()
