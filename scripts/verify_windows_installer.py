"""Extract NSIS and launch an isolated profile; never execute setup or uninstall."""
from pathlib import Path
import argparse
import configparser
from datetime import datetime, timezone
import hashlib
import json
import os
import sqlite3
import subprocess
import sys
import time
import urllib.request
import winreg

ROOT = Path(__file__).resolve().parents[1]


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def registry_snapshot():
    paths = [r'Software\Microsoft\Windows\CurrentVersion\Uninstall\Mesa', r'Software\Classes\AppUserModelId\Mesa.Recetario.Familiar', r'Software\Classes\CLSID\{165ab3ae-8d53-43dd-9a6c-a3a6c5ee7891}', r'Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Mesa.Recetario.Familiar']
    def read(path, view):
        try:
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, path, 0, winreg.KEY_READ | view) as key:
                result = {'values': [], 'children': {}}
                index = 0
                while True:
                    try:
                        name, value, kind = winreg.EnumValue(key, index)
                        result['values'].append([name, repr(value), kind]); index += 1
                    except OSError:
                        break
                index = 0
                while True:
                    try:
                        child = winreg.EnumKey(key, index)
                        result['children'][child] = read(path + '\\' + child, view); index += 1
                    except OSError:
                        break
                return result
        except FileNotFoundError:
            return None
    return {f'{view}:{path}': read(path, view) for view in (winreg.KEY_WOW64_64KEY, winreg.KEY_WOW64_32KEY) for path in paths}


def protected_snapshot():
    folders = [ROOT/'data', ROOT/'.tools/signing', Path(os.environ['APPDATA'])/'com.mesa', Path(os.environ['LOCALAPPDATA'])/'Mesa']
    files = [ROOT/'Mesa.lnk', Path(os.environ['USERPROFILE'])/'Desktop/Mesa.lnk', Path(os.environ['APPDATA'])/'Microsoft/Windows/Start Menu/Programs/Mesa/Mesa.lnk', Path(os.environ['APPDATA'])/'Microsoft/Windows/Start Menu/Programs/Mesa/Desinstalar Mesa.lnk']
    result = {}
    for folder in folders:
        result[str(folder)] = 'directory' if folder.is_dir() else None
        if folder.is_dir():
            for path in folder.rglob('*'):
                if path.is_file():
                    result[str(path)] = sha(path)
    for path in files:
        result[str(path)] = sha(path) if path.is_file() else None
    # The private Android distribution and prior Windows portable stay unchanged.
    for path in (ROOT/'dist').rglob('*'):
        if path.is_file() and 'Setup-' not in path.name:
            result[str(path)] = sha(path)
    return result


def wait_json(path, predicate=lambda value: True, timeout=60, newer_than=0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if path.is_file() and path.stat().st_mtime > newer_than:
            value = json.loads(path.read_text(encoding='utf-8-sig'))
            if 'error' in value:
                raise RuntimeError(value['error'])
            if predicate(value):
                return value
        time.sleep(.2)
    raise TimeoutError(str(path))


def recipe_state(profile):
    with sqlite3.connect((profile/'client/mesa.sqlite').as_uri()+'?mode=ro', uri=True) as con:
        return {'entities': con.execute('SELECT id,kind,data,deleted FROM entities ORDER BY id').fetchall(), 'outbox': con.execute('SELECT id,entity_id,payload FROM outbox ORDER BY seq').fetchall(), 'integrity': con.execute('PRAGMA quick_check').fetchone()[0]}


def stop_own_client(launcher, launch, installed):
    # This is lifecycle management of the process created by this QA launcher,
    # not window automation or termination of the user's existing Mesa.
    client_id = int(launch['clientPid'])
    expected = str(installed/'app/mesa.exe').replace("'", "''")
    command = f"$p=Get-CimInstance Win32_Process -Filter 'ProcessId = {client_id}'; if (!$p -or $p.ParentProcessId -ne {launcher.pid} -or $p.ExecutablePath -ine '{expected}') {{ throw 'No se ha verificado el proceso de laboratorio; no se cierra.' }}; Stop-Process -Id {client_id}"
    subprocess.run(['powershell.exe', '-NoProfile', '-Command', command], check=True, timeout=15)
    launcher.wait(timeout=20)


def main():
    parser=argparse.ArgumentParser(description='Solo extracción y arranque aislado; nunca ejecuta instaladores.')
    parser.add_argument('installer',type=Path)
    parser.add_argument('--pause-for-ui',action='store_true')
    args=parser.parse_args()
    installer=args.installer.resolve()
    lab=ROOT/'output'/('windows-installer-inspection-'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ'))
    lab.mkdir(exist_ok=False)
    (ROOT/'output/windows-installer-current-lab.txt').write_text(str(lab),encoding='utf-8')
    before_files,before_registry=protected_snapshot(),registry_snapshot()
    (lab/'before.json').write_text(json.dumps({'files':before_files,'registry':before_registry},ensure_ascii=False,indent=2),encoding='utf-8')
    checks=[]
    def passed(name,details):
        checks.append({'name':name,'result':'passed','details':details})
        (lab/'checks.json').write_text(json.dumps(checks,ensure_ascii=False,indent=2),encoding='utf-8')
    listing=subprocess.check_output(['7z','l','-slt',str(installer)],text=True,encoding='utf-8',errors='replace')
    (lab/'archive-listing.txt').write_text(listing,encoding='utf-8')
    assert 'Type = Nsis' in listing
    output=lab/'extracted'
    with (lab/'extraction.log').open('w',encoding='utf-8') as log:
        subprocess.run(['7z','x','-y','-o'+str(output),str(installer)],stdout=log,stderr=subprocess.STDOUT,check=True,timeout=180)
    manifests=list(output.rglob('payload-manifest.json'))
    assert len(manifests)==1
    extracted=manifests[0].parent
    manifest=json.loads(manifests[0].read_text(encoding='utf-8'))
    for item in manifest['files']:
        q=extracted/item['path']
        assert q.is_file() and q.stat().st_size==item['bytes'] and sha(q)==item['sha256'],item['path']
    assert not any(q.suffix in ('.sqlite','.jks') or q.name in ('desktop-connection.json','key.properties','password') for q in extracted.rglob('*'))
    passed('nsis_extraction_and_payload_sha256',{'files':len(manifest['files']),'version':manifest['appVersion'],'architecture':manifest['architecture'],'privateDatabasesOrKeysBundled':False,'extracted':str(extracted)})
    clean_env=dict(os.environ)
    for name in ('PYTHONPATH','PYTHONHOME','VIRTUAL_ENV','JAVA_HOME'):
        clean_env.pop(name,None)
    clean_env['PATH']=os.pathsep.join((str(Path(os.environ['WINDIR'])/'System32'),os.environ['WINDIR']))
    profile=lab/'profile'
    backend=lab/'backend.json'
    subprocess.run([str(extracted/'Mesa.exe'),'--isolated-profile',str(profile),'--self-test','--report',str(backend)],check=True,timeout=120,env=clean_env)
    passed('frozen_backend_save_read_translation',json.loads(backend.read_text(encoding='utf-8')))
    launch_file=lab/'launch.json'
    launcher=subprocess.Popen([str(extracted/'Mesa.exe'),'--isolated-profile',str(profile),'--report',str(launch_file)],cwd=extracted,env=clean_env)
    launch=wait_json(launch_file)
    ready_file=profile/'client/mesa-ready.json'
    ready=wait_json(ready_file,lambda v:v.get('ready') and v.get('connected'))
    opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
    config=json.loads((profile/'server/desktop-connection.json').read_text(encoding='utf-8'))
    url=f'http://127.0.0.1:{launch["apiPort"]}'
    headers={'Authorization':'Bearer '+config['token'],'Content-Type':'application/json'}
    structured={'@type':'Recipe','name':'Sopa','recipeIngredient':['2 huevos'],'recipeInstructions':['Batir.']}
    body=json.dumps({'text':'<script type="application/ld+json">'+json.dumps(structured)+'</script>'}).encode()
    with opener.open(urllib.request.Request(url+'/v1/import',data=body,headers=headers),timeout=10) as response:
        imported=json.load(response)
        assert imported['steps']==['Batir.'] and imported['ingredients']==['2 huevos']
    with opener.open(f'http://127.0.0.1:{launch["downloadPort"]}/descargar/update.json',timeout=5) as response:
        feed=json.load(response)
        assert feed['version_code']==32
    for language,text in {'en':'Mix 2 eggs.','fr':'Mélanger 2 œufs.','it':'Mescolare 2 uova.','de':'2 Eier mischen.','pt':'Misture 2 ovos.'}.items():
        recipe={'title':text,'language':language,'ingredients':['2 huevos'],'steps':[text],'servings':2,'tags':[]}
        body=json.dumps({'recipe':recipe,'source':language}).encode()
        with opener.open(urllib.request.Request(url+'/v1/translate-recipe',data=body,headers=headers),timeout=90) as response:
            translated=json.load(response)
            assert translated['language']=='es' and '2' in translated['steps'][0] and translated['original']['steps']==[text]
        passed('translation_'+language,{'steps':translated['steps'],'originalPreserved':True})
    state=recipe_state(profile)
    assert state['entities'] and state['integrity']=='ok'
    passed('isolated_native_first_frame_api_and_import',{'ready':ready,'process':launch,'steps':imported['steps'],'androidFeed':feed['version']})
    print('READY_FOR_UI '+str(lab),flush=True)
    if args.pause_for_ui:
        deadline=time.monotonic()+240
        while not (lab/'continue-qa').exists() and time.monotonic()<deadline:time.sleep(1)
    stop_own_client(launcher,launch,extracted)
    previous=ready_file.stat().st_mtime
    next_launch=lab/'relaunch.json'
    child=subprocess.Popen([str(extracted/'Mesa.exe'),'--isolated-profile',str(profile),'--report',str(next_launch)],cwd=extracted,env=clean_env)
    process=wait_json(next_launch)
    again=wait_json(ready_file,lambda v:v.get('connected'),newer_than=previous)
    assert recipe_state(profile)['entities']==state['entities']
    stop_own_client(child,process,extracted)
    passed('isolated_restart_preserves_recipes_and_queue',{'ready':again,'entities':len(state['entities']),'pending':len(state['outbox'])})
    after_files,after_registry=protected_snapshot(),registry_snapshot()
    (lab/'after.json').write_text(json.dumps({'files':after_files,'registry':after_registry},ensure_ascii=False,indent=2),encoding='utf-8')
    assert after_files==before_files and after_registry==before_registry
    passed('normal_registry_appid_shortcuts_and_data_unchanged',{'protectedFiles':len(before_files),'registrySnapshots':len(before_registry)})
    summary={'installer':str(installer),'sha256':sha(installer),'lab':str(lab),'checks':checks,'installationTested':False,'isolatedLaunchTested':True,'limitations':['Solo extracción y arranque del contenido extraído; no se han ejecutado el instalador ni el desinstalador finales.','Instalación, actualización y desinstalación normales no validadas.','No se ha probado una máquina limpia sin Python ni Visual C++ previamente instalados; se incluyen runtimes privados.']}
    (lab/'result.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(summary,ensure_ascii=False,indent=2),flush=True)


if __name__=='__main__':
    main()
