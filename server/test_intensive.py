"""Invalid input, concurrent edits and large-family traffic in isolated stores."""
from concurrent.futures import ThreadPoolExecutor
import json
import pytest
from fastapi.testclient import TestClient
from server.app import create_app


@pytest.fixture
def api(tmp_path):
    client = TestClient(create_app(tmp_path))
    token = json.loads((tmp_path / 'desktop-connection.json').read_text())['token']
    client.headers['Authorization'] = 'Bearer ' + token
    return client


def op(i, kind='recipe', data=None):
    return {'id':f'op-{i}', 'entity_id':f'entity-{i}', 'kind':kind, 'base':0,
            'data':data or {'title':f'Receta {i}','ingredients':['2 huevos'],'steps':['Cocer.'],'servings':2}}


@pytest.mark.parametrize('kind,field,value', [
    ('recipe','notes',123), ('recipe','source',{}), ('recipe','notes','x'*120001),
    ('recipe','source','x'*4001), ('meal','title',None), ('meal','title',''),
    ('recipe','notes',None), ('meal','date','0000-01-01'),
    ('meal','title',123), ('meal','recipe_id',[]), ('meal','servings',0),
    ('meal','servings',True), ('meal','servings',10001),
    ('meal','date','2026-02-30'), ('meal','date','2026-1-1'),
], ids=lambda value: value[:30] if isinstance(value, str) else type(value).__name__)
def test_invalid_values_never_enter_shared_store(api, kind, field, value):
    data = {'title':'Sopa','ingredients':['2 huevos'],'steps':['Cocer.']} if kind == 'recipe' else {
        'title':'Sopa','date':'2026-10-14','slot':'Comida','servings':2}
    data[field] = value
    generation = api.get('/v1/snapshot').json()['generation']
    response = api.post('/v1/push',json={'generation':generation,'operations':[op('invalid',kind,data)]})
    assert response.status_code == 422
    assert api.get('/v1/snapshot').json()['entities'] == []


def test_four_concurrent_editors_preserve_one_winner_and_three_proposals(api):
    generation = api.get('/v1/snapshot').json()['generation']
    operations = [op(i) | {'entity_id':'shared'} for i in range(4)]
    with ThreadPoolExecutor(max_workers=4) as workers:
        replies = list(workers.map(lambda operation: api.post('/v1/push',json={
            'generation':generation,'operations':[operation]}), operations))
    assert all(r.status_code == 200 for r in replies)
    results = [r.json()['results'][0] for r in replies]
    assert sum(r['status'] == 'applied' for r in results) == 1
    assert sum(r['status'] == 'conflict' for r in results) == 3
    current = api.get('/v1/snapshot').json()['entities'][0]
    assert current['revision'] == 1
    assert all(r['server']['data'] == current['data'] for r in results if r['status'] == 'conflict')


@pytest.mark.parametrize('field,value',[('recipe_title',123),('source',[])])
def test_invalid_shopping_references_cannot_crash_other_devices(api,field,value):
    generation=api.get('/v1/snapshot').json()['generation']
    response=api.post('/v1/push',json={'generation':generation,'operations':[
        op('bad-shopping','shopping',{'name':'Leche','checked':False,field:value})]})
    assert response.status_code==422
    assert api.get('/v1/snapshot').json()['entities']==[]


def test_two_thousand_recipes_paginate_replay_and_back_up(api):
    generation = api.get('/v1/snapshot').json()['generation']
    for start in range(0,2000,25):
        body = {'generation':generation,'operations':[op(i) for i in range(start,start+25)]}
        first = api.post('/v1/push',json=body)
        assert first.status_code == 200
        assert api.post('/v1/push',json=body).json() == first.json()
    records=[]; after=''; initial=None
    while True:
        params={'limit':50,'after':after}
        if initial is not None: params |= {'epoch':generation,'start_cursor':initial}
        page=api.get('/v1/snapshot',params=params).json()
        initial=page['cursor'] if initial is None else initial
        records.extend(page['entities'])
        if not page['next']: break
        after=page['next']
    assert len(records)==2000 and len({r['id'] for r in records})==2000
    assert all(r['revision']==1 and r['data']['ingredients']==['2 huevos'] for r in records)
    assert api.post('/v1/backup').status_code==200
    assert api.get('/v1/export').status_code==200
