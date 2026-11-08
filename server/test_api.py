import json
import sqlite3
from pathlib import Path
import pytest
from fastapi.testclient import TestClient
from server.app import create_app
from server.importer import extract_recipe


@pytest.fixture
def api(tmp_path):
    app = create_app(tmp_path)
    client = TestClient(app)
    token = json.loads((tmp_path / 'desktop-connection.json').read_text())['token']
    client.headers['Authorization'] = 'Bearer ' + token
    return client


def recipe(title='Tortilla'):
    return {'title': title, 'ingredients': ['2 huevos'], 'steps': ['Batir.'], 'servings': 2, 'tags': []}


def send(api, eid='r1', base=0, data=None, oid='op1', kind='recipe', **kwargs):
    epoch = api.get('/v1/snapshot').json()['generation']
    return api.post('/v1/push', json={'generation': epoch, 'operations': [{'id': oid, 'entity_id': eid, 'kind': kind, 'base': base, 'data': data or recipe(), **kwargs}]})


def test_auth_and_protocol(api):
    assert api.get('/health').json()['protocol'] == 1
    with TestClient(api.app) as anonymous:
        assert anonymous.get('/v1/snapshot').status_code == 401


def test_idempotency_and_misused_id(api):
    first = send(api).json()
    assert send(api).json() == first
    assert len(api.get('/v1/changes', params={'epoch': api.get('/v1/snapshot').json()['generation']}).json()['entities']) == 1
    assert send(api, data=recipe('Otro título')).status_code == 409


def test_concurrent_recipe_is_not_overwritten(api):
    send(api)
    response = send(api, data=recipe('Mi propuesta'), oid='op2').json()['results'][0]
    assert response['status'] == 'conflict'
    assert response['server']['data']['title'] == 'Tortilla'
    assert api.get('/v1/snapshot').json()['entities'][0]['data']['title'] == 'Tortilla'


def test_check_is_assignment_and_preserves_other_fields(api):
    send(api, kind='shopping', data={'name': 'Leche', 'checked': False, 'section': 'Lácteos'})
    assert send(api, kind='shopping', data={'checked': True}, action='check', oid='op2').status_code == 200
    assert send(api, kind='shopping', data={'checked': True}, action='check', oid='op2').status_code == 200
    current = api.get('/v1/snapshot').json()['entities'][0]
    assert current['data'] == {'name': 'Leche', 'checked': True, 'section': 'Lácteos'}
    assert current['revision'] == 2


def test_deleted_item_cannot_be_checked_or_resurrected_by_stale_edit(api):
    send(api, kind='shopping', data={'name': 'Leche', 'checked': False})
    send(api, kind='shopping', data={'name': 'Leche', 'checked': False}, base=1, deleted=True, oid='delete')
    assert send(api, kind='shopping', data={'checked': True}, action='check', oid='check').json()['results'][0]['status'] == 'conflict'
    result = send(api, kind='shopping', data={'name': 'Leche nueva', 'checked': False}, base=1, oid='edit').json()['results'][0]
    assert result['status'] == 'conflict'
    assert result['server']['deleted'] is True


def test_invite_is_one_use_and_reader_cannot_write(api):
    code = api.post('/v1/invites', json={'name': 'Ana', 'role': 'reader'}).json()['code']
    pair = api.post('/v1/pair', json={'name': 'Ana', 'code': code})
    assert pair.status_code == 200
    assert api.post('/v1/pair', json={'name': 'Ana', 'code': code}).status_code == 401
    api.headers['Authorization'] = 'Bearer ' + pair.json()['token']
    assert send(api).status_code == 403
    assert api.post('/v1/backup').status_code == 403


def test_revocation(api):
    code = api.post('/v1/invites', json={'name': 'Ana'}).json()['code']
    paired = api.post('/v1/pair', json={'name': 'Ana', 'code': code}).json()
    assert api.delete('/v1/members/' + paired['id']).status_code == 200
    api.headers['Authorization'] = 'Bearer ' + paired['token']
    assert api.get('/v1/export').status_code == 401


def test_history_and_backup(api):
    send(api)
    send(api, base=1, oid='op2', data=recipe('Tortilla con cebolla'))
    assert api.get('/v1/history/r1').json()[0]['entity']['data']['title'] == 'Tortilla'
    backup = api.post('/v1/backup').json()['name']
    with sqlite3.connect(api.app.state.root / 'backups' / backup) as con:
        assert con.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
        assert con.execute('SELECT COUNT(*) FROM entities').fetchone()[0] == 1


def test_generation_and_validation(api):
    assert api.get('/v1/changes?epoch=old').status_code == 409
    assert send(api, data=recipe() | {'servings': -1}).status_code == 422
    assert send(api, data=recipe() | {'image': 'not-base64'}).status_code == 422


def test_import_graph_sections_and_no_network(api):
    value = {'@graph': [{'@type': ['Recipe'], 'name': 'Sopa', 'recipeYield': '4 raciones', 'recipeIngredient': ['1 l de agua'], 'recipeInstructions': [{'@type': 'HowToSection', 'itemListElement': [{'text': 'Hervir.'}]}]}]}
    assert extract_recipe('<script type="application/ld+json">' + json.dumps(value) + '</script>')['steps'] == ['Hervir.']
    assert api.post('/v1/import', json={'text': 'https://127.0.0.1/private'}).status_code == 422


def test_batch_rolls_back_on_invalid_record(api):
    epoch = api.get('/v1/snapshot').json()['generation']
    operations = [{'id': 'first', 'entity_id': 'one', 'kind': 'recipe', 'base': 0, 'data': recipe()}, {'id': 'second', 'entity_id': 'two', 'kind': 'recipe', 'base': 0, 'data': recipe() | {'title': ''}}]
    assert api.post('/v1/push', json={'generation': epoch, 'operations': operations}).status_code == 422
    assert api.get('/v1/snapshot').json()['entities'] == []


def test_collections_and_recipe_membership_sync_and_rename(api):
    assert send(api, eid='book', kind='collection', data={'title': 'Recetas familiares', 'type': 'catalog'}).status_code == 200
    assert send(api, eid='r2', oid='recipe', data=recipe() | {'catalog_ids': ['book'], 'category_ids': ['category:postres'], 'rating': 5}).status_code == 200
    assert send(api, eid='book', oid='rename', base=1, kind='collection', data={'title': 'Nuestra cocina', 'type': 'catalog'}).status_code == 200
    exported = api.get('/v1/export').json()['entities']
    assert next(e for e in exported if e['id'] == 'r2')['data']['catalog_ids'] == ['book']
    assert send(api, eid='book', oid='delete', base=2, kind='collection', deleted=True, data={'title': 'Nuestra cocina', 'type': 'catalog'}).status_code == 200
    assert not next(e for e in api.get('/v1/snapshot').json()['entities'] if e['id'] == 'r2')['deleted']


def test_invalid_collection_rating_and_attribution_are_rejected(api):
    assert send(api, kind='collection', data={'title': '', 'type': 'catalog'}).status_code == 422
    assert send(api, kind='collection', data={'title': 'Test', 'type': 'unknown'}).status_code == 422
    assert send(api, data=recipe() | {'rating': 6}).status_code == 422
    assert send(api, data=recipe() | {'origin': {'license': 'CC'}}).status_code == 422
