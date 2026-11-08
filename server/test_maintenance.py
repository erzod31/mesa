import json
import sqlite3
from contextlib import closing
from fastapi.testclient import TestClient
from server.app import create_app
from server.maintenance import restore

def test_restore_preserves_safety_copy_and_invalidates_receipts(tmp_path,monkeypatch):
    root=tmp_path/'data';api=TestClient(create_app(root))
    config=json.loads((root/'desktop-connection.json').read_text())
    api.headers['Authorization']='Bearer '+config['token']
    epoch=api.get('/v1/snapshot').json()['generation']
    operation={'id':'op','entity_id':'r','kind':'recipe','base':0,'data':{'title':'Primera','ingredients':[],'steps':[],'tags':[],'servings':4}}
    api.post('/v1/push',json={'generation':epoch,'operations':[operation]}).raise_for_status()
    backup=root/'backups'/api.post('/v1/backup').json()['name']
    api.post('/v1/push',json={'generation':epoch,'operations':[{**operation,'id':'op2','base':1,'data':{**operation['data'],'title':'Segunda'}}]}).raise_for_status()
    class Offline:
        def __enter__(self):return self
        def __exit__(self,*args):pass
        def connect_ex(self,*args):return 1
    monkeypatch.setattr('server.maintenance.socket.socket',Offline)
    safety=restore(backup,root)
    with closing(sqlite3.connect(safety)) as con:assert json.loads(con.execute('SELECT data FROM entities').fetchone()[0])['title']=='Segunda'
    with closing(sqlite3.connect(root/'recetario.sqlite')) as con:
        assert json.loads(con.execute('SELECT data FROM entities').fetchone()[0])['title']=='Primera'
        assert con.execute("SELECT value FROM meta WHERE key='generation'").fetchone()[0]!=epoch
        assert con.execute('SELECT COUNT(*) FROM operations').fetchone()[0]==0
        assert con.execute('PRAGMA integrity_check').fetchone()[0]=='ok'
