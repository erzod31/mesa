import hashlib
import json
import threading
from http.server import ThreadingHTTPServer
from urllib.error import HTTPError
from urllib.request import Request, urlopen

import pytest

from scripts.publish_android_update import publish
from scripts import serve_apk


def metadata(code=9):
    return dict(version='1.5.0', version_code=code, min_sdk=24,
                abis=['arm64-v8a'], notes=['Actualizaciones desde Mesa.'])


def test_publication_is_immutable_and_alias_advances(tmp_path):
    source = tmp_path/'build.apk'
    source.write_bytes(b'first release')
    dist = tmp_path/'dist'
    first = publish(source, dist, metadata())
    assert first['sha256'] == hashlib.sha256(source.read_bytes()).hexdigest()
    assert first['size'] == len(b'first release')
    publish(source, dist, metadata())  # Idempotent publication of identical bytes.
    source.write_bytes(b'second release')
    with pytest.raises(ValueError, match='ya está publicada'):
        publish(source, dist, metadata())
    assert json.loads((dist/'android-update.json').read_text())['sha256'] == first['sha256']
    assert (dist/'Mesa-Android.apk').read_bytes() == b'first release'
    second = publish(source, dist, metadata(10))
    assert (dist/'Mesa-Android-1.5.0-9.apk').read_bytes() == b'first release'
    assert (dist/'Mesa-Android.apk').read_bytes() == b'second release'
    assert json.loads((dist/'android-update.json').read_text()) == second
    assert not list(dist.glob('*.part'))


def test_feed_and_apk_download_over_http(tmp_path, monkeypatch):
    source = tmp_path/'build.apk'
    source.write_bytes(b'APK test bytes')
    dist = tmp_path/'dist'
    manifest = publish(source, dist, metadata())
    monkeypatch.setattr(serve_apk, 'DIST', dist)
    server = ThreadingHTTPServer(('127.0.0.1', 0), serve_apk.Download)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    base = f'http://127.0.0.1:{server.server_port}'
    try:
        with urlopen(base+'/descargar/update.json') as response:
            assert response.headers['Cache-Control'] == 'no-store'
            remote = json.load(response)
        assert remote == manifest
        with urlopen(base+remote['apk_path']) as response:
            raw = response.read()
            assert response.headers['Content-Type'] == 'application/vnd.android.package-archive'
            assert int(response.headers['Content-Length']) == len(raw) == remote['size']
        assert hashlib.sha256(raw).hexdigest() == remote['sha256']
        with urlopen(Request(base+remote['apk_path'], method='HEAD')) as response:
            assert response.read() == b''
            assert int(response.headers['Content-Length']) == len(raw)
        with urlopen(base+'/health') as response:
            assert json.load(response)['product'] == 'mesa-downloads'
        for path in ('/../data/desktop-connection.json', '/descargar/%2e%2e/data/secret',
                     '/descargar/Mesa-Android-1.5.0-9.apk?x=1', '/android-update.json',
                     '/descargar/Mesa-Android-1.5.0-8.apk'):
            with pytest.raises(HTTPError) as error:
                urlopen(base+path)
            assert error.value.code == 404
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)


def test_windowed_helper_no_stderr_and_windows_channel(tmp_path,monkeypatch):
    monkeypatch.setattr(serve_apk,'DIST',tmp_path)
    monkeypatch.setattr(serve_apk.sys,'stderr',None)
    (tmp_path/'windows-update.json').write_text('{"candidate":true}')
    (tmp_path/'Mesa-Setup-1.18.0-35-x64.exe').write_bytes(b'PE candidate bytes')
    server=ThreadingHTTPServer(('127.0.0.1',0),serve_apk.Download)
    thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
    try:
        base=f'http://127.0.0.1:{server.server_port}'
        with urlopen(base+'/descargar/windows-update.json') as response:
            assert json.load(response)=={'candidate':True}
        with urlopen(base+'/descargar/Mesa-Setup-1.18.0-35-x64.exe') as response:
            assert response.read()==b'PE candidate bytes'
        with urlopen(base+'/health') as response:
            assert json.load(response)['product']=='mesa-downloads'
    finally:
        server.shutdown();server.server_close();thread.join(timeout=2)
