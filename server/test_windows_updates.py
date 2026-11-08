import base64
import io
import json
import hashlib
from pathlib import Path
from types import SimpleNamespace

import pytest
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives import serialization
from fastapi.testclient import TestClient

from server.app import create_app
from server import windows_updates as updates


@pytest.fixture
def signing():
    private=Ed25519PrivateKey.generate()
    public=private.public_key().public_bytes(serialization.Encoding.Raw,serialization.PublicFormat.Raw).hex()
    def sign(data):
        return {'release':data,'signature':base64.b64encode(private.sign(updates.canonical(data))).decode()}
    return public,sign


def release(raw=b'candidate-installer'):
    return {'product':updates.PRODUCT,'platform':'windows','architecture':'x64','version':'1.18.0','version_code':35,
            'size':len(raw),'sha256':hashlib.sha256(raw).hexdigest(),'installer_path':'/descargar/Mesa-Setup-1.18.0-35-x64.exe',
            'notes':['Actualización desde Mesa.'],'authenticode_required':False,'authenticode_thumbprint':None}


FEED='https://family.example:9443/descargar/windows-update.json'


class FakePlatform:
    def __init__(self):
        self.events=[];self.exit=0;self.installed=34
        self.meta={'product':'Mesa','description':'Instalador de Mesa para Windows x64','version':'1.18.0','code':35,'signature':'NotSigned','thumbprint':None}
    def inspect(self,path): return dict(self.meta)
    def registered_installation(self,path): return True
    def installed_code(self,installation): return self.installed
    def spawn_helper(self,helper,request): self.events.append(('spawn_fake',helper,request))
    def wait_parent(self,pid,expected): self.events.append(('wait_fake',pid,expected))
    def run_installer(self,path):
        self.events.append(('installer_fake',path))
        if self.exit==0:
            (self.installation/'mesa-install.ini').write_text('[Mesa]\nVersion=1.18.0\n')
            self.installed=35
        return self.exit
    def reopen(self,path): self.events.append(('reopen_fake',path))


def service(tmp_path,signing,raw=b'candidate-installer'):
    public,sign=signing
    installation=tmp_path/'installed';installation.mkdir()
    (installation/'mesa-install.ini').write_text('[Mesa]\nVersion=1.17.0\n')
    (installation/'Mesa.exe').write_bytes(b'not executed')
    (installation/'MesaUpdateHelper.exe').write_bytes(b'never executed updater')
    platform=FakePlatform();platform.installation=installation
    manifest=sign(release(raw))
    def transport(url,feed):
        data=json.dumps(manifest).encode() if url==feed else raw
        response=io.BytesIO(data);response.headers={'Content-Length':str(len(data))};response.status=200
        return response
    value=updates.WindowsUpdateService(installation,tmp_path/'cache','1.17.0+34',feed=FEED,platform=platform,transport=transport,public_key=public)
    value.check()
    args={k:value.release[k] for k in ('version_code','size','sha256','url')}
    return value,args,platform,manifest


def test_signed_manifest_and_tampering(signing):
    public,sign=signing
    envelope=sign(release())
    assert updates.parse_release(envelope,FEED,public)['version_code']==35
    envelope['release']['size']+=1
    with pytest.raises(updates.UpdateError,match='firma'): updates.parse_release(envelope,FEED,public)
    other,_=signing
    with pytest.raises(updates.UpdateError): updates.parse_release({'release':release()},FEED,other)


@pytest.mark.parametrize('bad',[{'product':'another.app'},{'platform':'android'},{'architecture':'arm64'},{'installer_path':'https://attacker.example/file.exe'},{'installer_path':'/descargar/../file.exe'},{'size':updates.MAX_PACKAGE+1},{'sha256':'bad'},{'version_code':True},{'authenticode_required':'false'},{'authenticode_required':True,'authenticode_thumbprint':None}])
def test_rejects_wrong_product_platform_metadata_even_if_signed(signing,bad):
    public,sign=signing
    with pytest.raises(updates.UpdateError): updates.parse_release(sign({**release(),**bad}),FEED,public)


def test_https_and_cross_origin_redirect_guard(monkeypatch):
    assert not updates.same_origin('http://family.example:9443/file',FEED)
    assert not updates.same_origin('https://family.example:9444/file',FEED)
    assert not updates.same_origin('https://u:p@family.example:9443/file',FEED)
    calls=[]
    class Opener:
        def open(self,request,timeout):
            calls.append(request.full_url)
            raise updates.urllib.error.HTTPError(request.full_url,302,'redirect',{'Location':'https://attacker.example/update'},io.BytesIO())
    monkeypatch.setattr(updates.urllib.request,'build_opener',lambda *args:Opener())
    with pytest.raises(updates.UpdateError,match='Redirección'): updates.open_https(FEED,FEED)
    assert len(calls)==1


def test_bounded_download_verified_then_handoff_only_to_fake(tmp_path,signing):
    svc,args,platform,_=service(tmp_path,signing)
    assert svc.download(args,background=False)['status']=='ready'
    assert svc.apply(args)['close_app'] is True
    assert [e[0] for e in platform.events]==['spawn_fake']
    copied,request=platform.events[0][1:]
    assert copied.parent.is_relative_to(svc.cache) and not copied.is_relative_to(svc.installation)
    assert copied.read_bytes()==b'never executed updater'
    result=updates.apply_request(request,platform=platform,public_key=signing[0])
    assert result=={'installer_exit':0,'reopen_requested':True,'updated':True}
    assert [e[0] for e in platform.events]==['spawn_fake','wait_fake','installer_fake','reopen_fake']


@pytest.mark.parametrize('bad',[{'product':'foreign'},{'version':'9.0.0'},{'code':36},{'signature':'HashMismatch'},{'signature':'Valid'}])
def test_download_pe_identity_and_existing_signature_checks(tmp_path,signing,bad):
    svc,args,platform,_=service(tmp_path,signing)
    platform.meta.update(bad)
    assert svc.download(args,background=False)['status']=='error'
    with pytest.raises(updates.UpdateError): svc.apply(args)
    assert not platform.events


def test_hash_rechecked_before_apply_and_before_fake_installer(tmp_path,signing):
    svc,args,platform,_=service(tmp_path,signing)
    svc.download(args,background=False)
    svc.package().write_bytes(b'tampered')
    with pytest.raises(updates.UpdateError,match='SHA-256'): svc.apply(args)
    assert not platform.events


def test_manifest_download_size_and_hash_errors(tmp_path,signing):
    svc,args,platform,_=service(tmp_path,signing)
    original=svc.transport
    def broken(url,feed):
        r=original(url,feed);r.headers['Content-Length']='999';return r
    svc.transport=broken
    assert svc.download(args,background=False)['status']=='error'
    assert not list(svc.cache.glob('*.part'))
    assert not platform.events


def test_cancellation_does_not_prepare_installer(tmp_path,signing):
    svc,args,platform,_=service(tmp_path,signing)
    original=svc.transport
    def cancelled(url,feed):
        r=original(url,feed);svc.cancel();return r
    svc.transport=cancelled
    assert svc.download(args,background=False)['status']=='cancelled'
    assert not svc.package().exists() and not platform.events


def test_native_cancel_reopens_previous_app_with_fake(tmp_path,signing):
    svc,args,platform,_=service(tmp_path,signing)
    svc.download(args,background=False);svc.apply(args);platform.exit=2
    request=platform.events[0][2]
    assert updates.apply_request(request,platform=platform,public_key=signing[0])['updated'] is False
    assert platform.events[-1][0]=='reopen_fake'
    assert updates.installed_marker(svc.installation)=='1.17.0'


def test_initial_manual_transition_and_isolated_apply_disabled(tmp_path,signing):
    svc,args,platform,_=service(tmp_path,signing)
    svc.download(args,background=False);svc.allow_apply=False
    with pytest.raises(updates.UpdateError,match='manual'): svc.apply(args)
    assert not platform.events
    (svc.installation/'mesa-install.ini').unlink();svc.allow_apply=True
    assert svc.info()['managed_install'] is False
    with pytest.raises(updates.UpdateError): svc.apply(args)


def test_downgrade_and_installed_version_change_block_apply(tmp_path,signing):
    svc,args,platform,_=service(tmp_path,signing)
    with pytest.raises(updates.UpdateError): updates.verify_artifact(tmp_path/'missing',svc.release,35,platform)
    with pytest.raises(updates.UpdateError,match='retroceso'): updates.verify_artifact(tmp_path/'missing',svc.release,34,platform,'9.0.0')
    svc.download(args,background=False);svc.apply(args)
    platform.installed=36
    with pytest.raises(updates.UpdateError,match='cambiado'):
        updates.apply_request(platform.events[0][2],platform=platform,public_key=signing[0])
    assert not any(e[0]=='installer_fake' for e in platform.events)


def test_authenticode_signature_required_when_declared(tmp_path,signing):
    svc,args,platform,_=service(tmp_path,signing)
    path=tmp_path/'candidate.exe';path.write_bytes(b'candidate-installer')
    signed={**svc.release,'authenticode_required':True,'authenticode_thumbprint':'A'*40}
    with pytest.raises(updates.UpdateError,match='Authenticode'): updates.verify_artifact(path,signed,34,platform)
    platform.meta.update(signature='Valid',thumbprint='A'*40)
    updates.verify_artifact(path,signed,34,platform)


def test_local_capability_required_not_family_api_credentials(tmp_path):
    app=create_app(tmp_path)
    client=TestClient(app)
    token=json.loads((tmp_path/'desktop-connection.json').read_text())['token']
    assert client.post('/v1/app-updates/info',headers={'Authorization':'Bearer '+token}).status_code==403
    app.state.windows_update_session='isolated-capability'
    app.state.windows_updater=SimpleNamespace(info=lambda:{'platform':'windows','version_code':35})
    assert client.post('/v1/app-updates/info',headers={'X-Mesa-Update-Session':'wrong'}).status_code==403
    assert client.post('/v1/app-updates/info',headers={'X-Mesa-Update-Session':'isolated-capability'}).json()['version_code']==35


def test_utf16_nsis_marker_and_missing_network(tmp_path,signing):
    svc,args,platform,_=service(tmp_path,signing)
    (svc.installation/'mesa-install.ini').write_text('[Mesa]\nVersion=1.17.0\n',encoding='utf-16')
    assert svc.info()['managed_install'] is True
    def offline(*args): raise OSError('offline')
    svc.transport=offline
    with pytest.raises(OSError): svc.check()
    assert not platform.events


def test_tamper_during_wait_is_rechecked_before_fake_install(tmp_path,signing):
    svc,args,platform,_=service(tmp_path,signing)
    svc.download(args,background=False);svc.apply(args)
    request=platform.events[0][2]
    platform.wait_parent=lambda pid,expected: svc.package().write_bytes(b'changed while waiting')
    with pytest.raises(updates.UpdateError,match='SHA-256'):
        updates.apply_request(request,platform=platform,public_key=signing[0])
    assert not any(e[0]=='installer_fake' for e in platform.events)
