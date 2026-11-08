"""Prepare signed candidate feed files outside the live dist feed. No publish."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
from cryptography.hazmat.primitives import serialization

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from server.windows_updates import canonical, parse_release, WindowsPlatform, PRODUCT
from scripts.release_signing import sign_android


def digest(path):
    with path.open('rb') as stream: return hashlib.file_digest(stream,'sha256').hexdigest()


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--installer',type=Path,required=True)
    parser.add_argument('--apk',type=Path,required=True)
    parser.add_argument('--output',type=Path,default=ROOT/'output/in-app-updates-DG-0021/channel')
    args=parser.parse_args()
    version,code=re.search(r'^version: (\d+\.\d+\.\d+)\+(\d+)',(ROOT/'client/pubspec.yaml').read_text(),re.M).groups()
    code=int(code);installer=args.installer.resolve();apk=args.apk.resolve()
    if installer.name!=f'Mesa-Setup-{version}-{code}-x64.exe' or apk.name!=f'Mesa-Android-{version}-{code}.apk':
        raise ValueError('Los candidatos no coinciden con la versión actual.')
    meta=WindowsPlatform().inspect(installer)
    if meta['product']!='Mesa' or meta['version']!=version or meta['code']!=code:
        raise ValueError('El instalador no corresponde a esta entrega.')
    if meta['signature'] not in ('Valid','NotSigned'): raise ValueError('Firma Authenticode inválida.')
    aapt=ROOT/'.tools/android/build-tools/36.0.0/aapt.exe'
    badging=subprocess.check_output([str(aapt),'dump','badging',str(apk)],text=True,encoding='utf-8')
    if not re.search(rf"package: name='com.mesa.mesa' versionCode='{code}' versionName='{re.escape(version)}'",badging):
        raise ValueError('La APK no corresponde a esta entrega.')
    notes=json.loads((ROOT/'client/update_notes.json').read_text())
    release={'product':PRODUCT,'platform':'windows','architecture':'x64','version':version,'version_code':code,
        'installer_path':'/descargar/'+installer.name,'size':installer.stat().st_size,'sha256':digest(installer),'notes':notes,
        'authenticode_required':meta['signature']=='Valid','authenticode_thumbprint':meta['thumbprint'] if meta['signature']=='Valid' else None}
    key=serialization.load_pem_private_key((ROOT/'.tools/signing/windows-updates-ed25519.pem').read_bytes(),password=None)
    envelope={'release':release,'signature':base64.b64encode(key.sign(canonical(release))).decode()}
    parse_release(envelope,'https://starfly.tailc69897.ts.net:9443/descargar/windows-update.json')
    android={'version':version,'version_code':code,'package':'com.mesa.mesa','min_sdk':int(re.search(r"sdkVersion:'(\d+)'",badging)[1]),
        'abis':['arm64-v8a'],'apk_path':'/descargar/'+apk.name,'sha256':digest(apk),'size':apk.stat().st_size,'notes':notes}
    android=sign_android(android)
    args.output.mkdir(parents=True,exist_ok=True)
    for name,data in (('windows-update.json',envelope),('android-update.json',android)):
        (args.output/name).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'candidateChannelDirectory':str(args.output.resolve()),'productionPublished':False},indent=2))


if __name__=='__main__': main()
