import hashlib
import json
from pathlib import Path
import sqlite3
import pytest
from server.server_profile import select_server_data,validate_existing
from server.app import create_app
from fastapi.testclient import TestClient


def family(path):
    app=create_app(path)
    config=json.loads((path/'desktop-connection.json').read_text())
    return app,config


def test_saved_family_selection_authenticates_original_credential_without_merging(tmp_path):
    original=tmp_path/'original';other=tmp_path/'local/server'
    original_app,config=family(original);other_app,_=family(other)
    token=config['token']
    with TestClient(other_app) as api:
        assert api.get('/v1/me',headers={'Authorization':'Bearer '+token}).status_code==401
    settings=tmp_path/'local/server-profile.json'
    settings.write_text(json.dumps({'schema':1,'server_data_directory':str(original)}))
    selected=select_server_data(tmp_path/'local',environ={})
    assert selected==original
    with TestClient(create_app(selected)) as api:
        response=api.get('/v1/me',headers={'Authorization':'Bearer '+token})
        assert response.status_code==200
        assert api.get('/v1/snapshot',headers={'Authorization':'Bearer '+token}).json()['entities']==[]
    for path in (original,other):
        with sqlite3.connect(path/'recetario.sqlite') as con:assert con.execute('SELECT COUNT(*) FROM users').fetchone()[0]==1
    assert json.loads((original/'desktop-connection.json').read_text())['token']==token


def test_default_and_isolation_do_not_pick_external_selection(tmp_path):
    root=tmp_path/'profile'
    assert select_server_data(root,environ={})==root/'server'
    assert select_server_data(root,isolated=True,environ={'MESA_SERVER_DATA':'C:/unrelated'})==root/'server'
    assert not root.exists()


def test_explicit_and_legacy_environment_select_existing_data(tmp_path):
    path=tmp_path/'family';family(path)
    for variable in ['MESA_SERVER_DATA','RECETARIO_DATA']:
        assert select_server_data(tmp_path/'local',environ={variable:str(path)})==path


@pytest.mark.parametrize('selection',['relative/path','missing'])
def test_invalid_explicit_selection_never_initializes_new_family(tmp_path,selection):
    path=selection if selection.startswith('relative') else str(tmp_path/selection)
    with pytest.raises(ValueError):select_server_data(tmp_path/'local',environ={'MESA_SERVER_DATA':path})
    assert not (tmp_path/'local').exists()


def test_corrupt_settings_and_revoked_profile_fail_closed(tmp_path):
    local=tmp_path/'local';local.mkdir();settings=local/'server-profile.json';settings.write_text('broken')
    with pytest.raises(ValueError):select_server_data(local,environ={})
    path=tmp_path/'family';family(path)
    with sqlite3.connect(path/'recetario.sqlite') as con:con.execute('UPDATE users SET revoked=1')
    settings.write_text(json.dumps({'schema':1,'server_data_directory':str(path)}))
    with pytest.raises(ValueError):select_server_data(local,environ={})
