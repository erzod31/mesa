import base64
import json
from pathlib import Path
import pytest
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives import serialization
from scripts import update_publication as publication
from server import windows_updates


@pytest.fixture
def staged(tmp_path,monkeypatch):
    key=Ed25519PrivateKey.generate()
    public=key.public_key().public_bytes(serialization.Encoding.Raw,serialization.PublicFormat.Raw).hex()
    root=tmp_path/'root'; (root/'server').mkdir(parents=True)
    (root/'server/windows_update_key.pub').write_text(public)
    monkeypatch.setattr(publication,'ROOT',root)
    # parse_release's public key is an explicit runtime dependency for this lab.
    original=windows_updates.parse_release
    monkeypatch.setattr(publication,'parse_release',lambda value,url:original(value,url,public))
    target=tmp_path/'serving';target.mkdir()
    (target/'android-update.json').write_text('{"old":true}')
    (target/'Mesa-Android.apk').write_bytes(b'old signed apk stand-in')
    channel=tmp_path/'channel';channel.mkdir()
    artifacts=tmp_path/'artifacts';artifacts.mkdir()
    names=['Mesa-Setup-1.18.1-36-x64.exe','Mesa-Android-1.18.1-36.apk']
    for name in names: (artifacts/name).write_bytes(('fixture '+name).encode())
    win={'product':windows_updates.PRODUCT,'platform':'windows','architecture':'x64','version':'1.18.1','version_code':36,
         'installer_path':'/descargar/'+names[0],**{'size':(artifacts/names[0]).stat().st_size,'sha256':publication.digest(artifacts/names[0])},
         'notes':['Prueba sintética.'],'authenticode_required':False,'authenticode_thumbprint':None}
    android={'package':'com.mesa.mesa','product':'com.mesa.mesa','platform':'android','architecture':'arm64-v8a','version':'1.18.1','version_code':36,
             'apk_path':'/descargar/'+names[1],'size':(artifacts/names[1]).stat().st_size,'sha256':publication.digest(artifacts/names[1]),'notes':['Prueba sintética.'],'abis':['arm64-v8a'],'min_sdk':24}
    sign=lambda value:base64.b64encode(key.sign(windows_updates.canonical(value))).decode()
    (channel/'windows-update.json').write_text(json.dumps({'release':win,'signature':sign(win)}),encoding='utf-8')
    (channel/'android-update.json').write_text(json.dumps({**android,'signature':sign(android)}),encoding='utf-8')
    bundle=tmp_path/'bundle'
    plan=publication.prepare(channel,artifacts,bundle,target)
    return bundle,target,plan


def test_staging_does_not_publish_and_activation_rollback_keep_immutable_files(staged):
    bundle,target,plan=staged
    assert not (target/'windows-update.json').exists()
    assert (target/'android-update.json').read_text()=='{"old":true}'
    result=publication.activate(bundle)
    assert result['activated'] and not result['serviceRestarted']
    assert json.loads((target/'android-update.json').read_text())['version_code']==36
    assert publication.rollback(bundle)['rolledBack']
    assert not (target/'windows-update.json').exists()
    assert (target/'android-update.json').read_text()=='{"old":true}'
    assert all((target/name).exists() for name in plan['packages'])


def test_changed_destination_refuses_activation(staged):
    bundle,target,_=staged
    (target/'android-update.json').write_text('changed by operator')
    with pytest.raises(ValueError,match='cambió'): publication.activate(bundle)
    assert not (target/'windows-update.json').exists()


def test_tampered_staging_refuses_before_any_write(staged):
    bundle,target,plan=staged
    (bundle/plan['packages'][0]).write_bytes(b'tampered')
    with pytest.raises(ValueError): publication.activate(bundle)
    assert not (target/'windows-update.json').exists()


def test_partial_publication_can_roll_back_without_deleting_user_files(staged):
    bundle,target,plan=staged
    (target/'user-file').write_text('preserve')
    publication.replace(bundle/'windows-update.json',target/'windows-update.json')
    publication.rollback(bundle)
    assert not (target/'windows-update.json').exists()
    assert (target/'user-file').read_text()=='preserve'


def test_rollback_refuses_overwriting_later_publication(staged):
    bundle,target,_=staged
    publication.activate(bundle)
    (target/'windows-update.json').write_text('later offer')
    with pytest.raises(ValueError,match='posteriores'): publication.rollback(bundle)
    assert (target/'windows-update.json').read_text()=='later offer'
