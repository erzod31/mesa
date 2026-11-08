"""Publish immutable signed APK releases and atomically advance the update feed."""
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def file_hash(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def publish(source, destination, metadata, *, signer=None):
    version, code = metadata['version'], metadata['version_code']
    if not re.fullmatch(r'\d+\.\d+\.\d+', version) or not isinstance(code, int) or code <= 0:
        raise ValueError('Versión Android incorrecta.')
    destination.mkdir(parents=True, exist_ok=True)
    name = f'Mesa-Android-{version}-{code}.apk'
    raw_hash = file_hash(source)
    release = destination/name
    if release.exists() and file_hash(release) != raw_hash:
        raise ValueError('Esta versión ya está publicada con otro contenido. Incrementa el código de versión.')
    if not release.exists():
        staged = destination/(name+'.part')
        shutil.copyfile(source, staged)
        os.replace(staged, release)
    staged = destination/'Mesa-Android.apk.part'
    shutil.copyfile(release, staged)
    os.replace(staged, destination/'Mesa-Android.apk')
    data = {**metadata, 'package':'com.mesa.mesa', 'apk_path':f'/descargar/{name}',
            'sha256':raw_hash, 'size':release.stat().st_size,
            'published_at':datetime.now(timezone.utc).isoformat()}
    if signer is not None: data=signer(data)
    staged = destination/'android-update.json.part'
    staged.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
    os.replace(staged, destination/'android-update.json')
    return data


def main():
    sys.path.insert(0,str(ROOT))
    from scripts.release_signing import sign_android
    source = Path(sys.argv[1]).resolve()
    aapt = ROOT/'.tools/android/build-tools/36.0.0/aapt.exe'
    text = subprocess.check_output([str(aapt),'dump','badging',str(source)],encoding='utf-8')
    package = re.search(r"package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'",text)
    if not package or package[1] != 'com.mesa.mesa':
        raise ValueError('La APK no pertenece a Mesa.')
    declared = re.search(r'^version: (\d+\.\d+\.\d+)\+(\d+)',(ROOT/'client/pubspec.yaml').read_text(encoding='utf-8'),re.M)
    if not declared or (package[3],package[2]) != (declared[1],declared[2]):
        raise ValueError('La APK no coincide con la versión declarada en el proyecto.')
    notes = json.loads((ROOT/'client/update_notes.json').read_text(encoding='utf-8'))
    data = publish(source, ROOT/'dist', dict(version=package[3],version_code=int(package[2]),
        min_sdk=int(re.search(r"sdkVersion:'(\d+)'",text)[1]),
        abis=re.findall(r"'([^']+)'",re.search(r'^native-code:(.*)$',text,re.M)[1]),notes=notes), signer=sign_android)
    print(json.dumps({key:data[key] for key in ('version','version_code','size','sha256','apk_path')},ensure_ascii=False))


if __name__ == '__main__':
    main()
