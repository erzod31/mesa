"""Verify the published HTTPS feed, full APK download and public signing certificate."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
from urllib.request import Request, urlopen
import zipfile
import argparse

from verify_android import verify, dex_classes

ROOT = Path(__file__).resolve().parents[1]
BASE = 'https://starfly.tailc69897.ts.net:9443'
APK = ROOT/'dist/Mesa-Android.apk'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--client-tests', type=int)
    parser.add_argument('--server-tests', type=int)
    args = parser.parse_args()
    manifest = json.loads((ROOT/'dist/android-update.json').read_text(encoding='utf-8'))
    with urlopen(BASE+'/descargar/update.json', timeout=20) as response:
        remote = json.loads(response.read(16001))
        assert response.status == 200 and response.headers['Cache-Control'] == 'no-store'
    assert remote == manifest
    digest, total = hashlib.sha256(), 0
    with urlopen(BASE+remote['apk_path'], timeout=30) as response:
        assert response.headers['Content-Type'] == 'application/vnd.android.package-archive'
        assert int(response.headers['Content-Length']) == remote['size']
        while chunk := response.read(1024*1024):
            total += len(chunk)
            assert total <= remote['size']
            digest.update(chunk)
    assert total == remote['size'] and digest.hexdigest() == remote['sha256']
    with APK.open('rb') as source:
        assert hashlib.file_digest(source, 'sha256').hexdigest() == remote['sha256']
    with urlopen(Request(BASE+'/descargar/Mesa-Android.apk', method='HEAD'), timeout=20) as response:
        assert response.status == 200 and int(response.headers['Content-Length']) == total
    aapt = ROOT/'.tools/android/build-tools/36.0.0/aapt.exe'
    xml = subprocess.check_output([str(aapt),'dump','xmltree',str(APK),'AndroidManifest.xml'], encoding='utf-8')
    assert 'android.permission.REQUEST_INSTALL_PACKAGES' in xml
    assert 'com.mesa.mesa.UpdateFileProvider' in xml and 'com.mesa.mesa.updates' in xml
    # Release resource shrinking renames files; resolve the compiled resource's real ZIP path.
    resources = subprocess.check_output([str(aapt),'dump','resources',str(APK)], encoding='utf-8')
    entry = re.search(r'resource (0x[0-9a-f]+) com\.mesa\.mesa:xml/update_file_paths: t=0x03 d=(0x[0-9a-f]+)', resources)
    assert entry and '@'+entry[1] in xml
    strings = subprocess.check_output([str(aapt),'dump','strings',str(APK)], encoding='utf-8')
    resource_path = re.search(r'^String #'+str(int(entry[2],16))+r': (.+)$', strings, re.M)[1].strip()
    paths = subprocess.check_output([str(aapt),'dump','xmltree',str(APK),resource_path], encoding='utf-8')
    assert 'updates/' in paths and 'cache-path' in paths
    classes = {}
    with zipfile.ZipFile(APK) as package:
        retired = ['sabores-andantes.json', 'agro-arracacha.json', 'agro-caribe.json']
        assert not any(any(name.endswith(asset) for asset in retired)
                       for name in package.namelist())
        for name in package.namelist():
            if name.startswith('classes') and name.endswith('.dex'):
                classes.update(dex_classes(package.read(name)))
    assert 'Lcom/mesa/mesa/UpdateFileProvider;' in classes
    env = {**os.environ, 'JAVA_HOME':r'C:\Program Files\Android\Android Studio\jbr'}
    signer = ROOT/'.tools/android/build-tools/36.0.0/apksigner.bat'
    cert = subprocess.check_output([str(signer),'verify','--verbose','--print-certs',str(APK)], env=env, encoding='utf-8')
    certificate = re.search(r'Signer #1 certificate SHA-256 digest: ([a-f0-9]+)', cert)[1]
    assert certificate == 'cfac930697914840904bfa97aa30f4c763cd8138858fe7ff9339ab69e2474d18'
    suffix = remote['version'].replace('.', '') + '-' + str(remote['version_code'])
    (ROOT/f'output/apk-updates-{suffix}-cert.txt').write_text(cert, encoding='utf-8')
    result = dict(version=remote['version'], version_code=remote['version_code'],
        size=total, sha256=digest.hexdigest(), certificate_sha256=certificate,
        download_url=BASE+remote['apk_path'], feed_url=BASE+'/descargar/update.json',
        https_download_verified=True, update_permission=True, scoped_provider=True,
        native=verify(APK), retired_catalogues_absent=True,
        client_tests=args.client_tests, server_tests=args.server_tests, physical_android_test=False)
    (ROOT/f'output/android-updates-{suffix}-release.json').write_text(json.dumps(result,ensure_ascii=False,indent=2), encoding='utf-8')
    print(json.dumps(result,ensure_ascii=False))


if __name__ == '__main__':
    main()
