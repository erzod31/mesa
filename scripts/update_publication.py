"""Stage, activate or roll back reviewed files; never manages network/services.

Preparation is read-only for the serving directory. Activation is a separate
explicit command, not used on the real serving directory during DG-0033.
"""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from server.windows_updates import canonical, parse_release

MUTABLE=('windows-update.json','android-update.json','Mesa-Android.apk')


def digest(path):
    with path.open('rb') as stream: return hashlib.file_digest(stream,'sha256').hexdigest()


def state(path):
    if path.is_symlink() or path.is_junction() or (path.exists() and not path.is_file()): raise ValueError('Archivo enlazado o no regular.')
    return {'bytes':path.stat().st_size,'sha256':digest(path)} if path.is_file() else None


def validate(bundle):
    windows=json.loads((bundle/'windows-update.json').read_text(encoding='utf-8'))
    release=parse_release(windows,'https://starfly.tailc69897.ts.net:9443/descargar/windows-update.json')
    android=json.loads((bundle/'android-update.json').read_text(encoding='utf-8'))
    signature=android.pop('signature')
    public=Ed25519PublicKey.from_public_bytes(bytes.fromhex((ROOT/'server/windows_update_key.pub').read_text().strip()))
    public.verify(base64.b64decode(signature,validate=True),canonical(android))
    if android['package']!='com.mesa.mesa' or android['platform']!='android' or android['architecture']!='arm64-v8a': raise ValueError('Producto Android incorrecto.')
    if (release['version'],release['version_code'])!=(android['version'],android['version_code']): raise ValueError('Canales de versiones distintas.')
    names=[]
    for data,key in ((windows['release'],'installer_path'),(android,'apk_path')):
        name=Path(data[key]).name
        if data[key]!='/descargar/'+name: raise ValueError('Ruta incorrecta.')
        if state(bundle/name)!={'bytes':data['size'],'sha256':data['sha256']}: raise ValueError('Paquete alterado o ausente.')
        names.append(name)
    return names


def safe_target(target):
    target=target.absolute()
    for path in (target,*target.parents):
        if path.exists() and (path.is_symlink() or path.is_junction()): raise ValueError('Destino enlazado no permitido.')
    return target.resolve()


def prepare(channel,artifacts,bundle,target):
    target=safe_target(target)
    if bundle.exists(): raise ValueError('El bundle ya existe; no se sobrescribe evidencia.')
    bundle.mkdir(parents=True)
    for name in MUTABLE[:2]: shutil.copyfile(channel/name,bundle/name)
    windows=json.loads((bundle/'windows-update.json').read_text(encoding='utf-8'))['release']
    android=json.loads((bundle/'android-update.json').read_text(encoding='utf-8'))
    for data,key in ((windows,'installer_path'),(android,'apk_path')):
        name=Path(data[key]).name
        shutil.copyfile(artifacts/name,bundle/name)
    names=validate(bundle)
    backup=bundle/'rollback'; backup.mkdir()
    before={}
    for name in (*MUTABLE,*names):
        path=target/name
        if path.exists() and (path.is_symlink() or path.is_junction() or not path.is_file()): raise ValueError('Destino no regular.')
        before[name]=state(path)
        if name in MUTABLE and before[name]: shutil.copyfile(path,backup/name)
    plan={'target':str(target),'before':before,'packages':names,'version':android['version'],'versionCode':android['version_code'],
          'prepared':True,'activated':False,'serviceRestarted':False,'impact':'Advances both update offers and the APK alias. Does not install on any device; existing helpers may require a separately scheduled restart.',
          'rollbackImpact':'Restores prior offers/alias, leaves immutable packages and user data. Already upgraded clients reject older binaries; no downgrade installation.'}
    (bundle/'publication.json').write_text(json.dumps(plan,indent=2),encoding='utf-8')
    return plan


def replace(source,target):
    # Same-directory atomic replacement; unique temp prevents unrelated .part loss.
    with tempfile.NamedTemporaryFile(dir=target.parent,prefix='.mesa-stage-',delete=False) as out:
        temp=Path(out.name)
        with source.open('rb') as inp: shutil.copyfileobj(inp,out)
        out.flush(); os.fsync(out.fileno())
    try: os.replace(temp,target)
    finally:
        if temp.exists(): temp.unlink()


def activate(bundle):
    plan=json.loads((bundle/'publication.json').read_text())
    target=safe_target(Path(plan['target']))
    names=validate(bundle)
    for name,expected in plan['before'].items():
        if state(target/name)!=expected: raise ValueError('El destino cambió desde la preparación; vuelve a revisar.')
    # All validation occurs before the first operational write.
    for name in names:
        if (target/name).exists() and digest(target/name)!=digest(bundle/name): raise ValueError('Versión inmutable ya ocupada por otro paquete.')
    target.mkdir(parents=True,exist_ok=True)
    for name in names:
        if not (target/name).exists(): replace(bundle/name,target/name)
    replace(bundle/names[1],target/'Mesa-Android.apk')
    # Each offer is atomic and points only to an already verified immutable file.
    for name in MUTABLE[:2]: replace(bundle/name,target/name)
    receipt={'activated':True,'after':{name:state(target/name) for name in MUTABLE},'serviceRestarted':False}
    (bundle/'activation.json').write_text(json.dumps(receipt,indent=2),encoding='utf-8')
    return receipt


def rollback(bundle):
    plan=json.loads((bundle/'publication.json').read_text())
    target=safe_target(Path(plan['target']))
    # Works even after a partial activation: allow only old or reviewed new bytes.
    names=validate(bundle)
    sources={'windows-update.json':bundle/'windows-update.json','android-update.json':bundle/'android-update.json','Mesa-Android.apk':bundle/names[1]}
    for name in MUTABLE:
        if state(target/name) not in (plan['before'][name],state(sources[name])): raise ValueError('Hay cambios posteriores; rollback detenido.')
        if plan['before'][name] and state(bundle/'rollback'/name)!=plan['before'][name]: raise ValueError('Copia de rollback alterada.')
    for name in MUTABLE:
        if plan['before'][name]: replace(bundle/'rollback'/name,target/name)
        elif (target/name).exists(): (target/name).unlink()
    return {'rolledBack':True,'immutablePackagesRetained':True,'serviceRestarted':False}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=['prepare','activate','rollback'])
    parser.add_argument('--bundle',type=Path,required=True)
    parser.add_argument('--channel',type=Path)
    parser.add_argument('--artifacts',type=Path)
    parser.add_argument('--target',type=Path)
    args=parser.parse_args()
    if args.action=='prepare':
        if not all((args.channel,args.artifacts,args.target)): parser.error('prepare necesita channel/artifacts/target')
        result=prepare(args.channel,args.artifacts,args.bundle,args.target)
    else: result=(activate if args.action=='activate' else rollback)(args.bundle)
    print(json.dumps(result,indent=2))


if __name__=='__main__': main()
