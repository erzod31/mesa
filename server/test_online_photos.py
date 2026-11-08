import base64
import json

from fastapi.testclient import TestClient

from server.app import create_app
from server.online_photos import online_recipe_data, online_photo_url
from server.test_api import api, send, recipe
from server.test_photos import photo_bytes


def test_photo_references_select_legacy_cover_and_reject_private_urls():
    data = recipe() | {'image': 'cover', 'photos': [
        {'image': 'first', 'url': 'https://example.org/first.jpg', 'artist': 'Ana'},
        {'image': 'cover', 'url': 'https://example.org/cover.jpg', 'artist': 'Bea'},
        {'image': 'personal'},
        {'url': 'https://127.0.0.1/private.jpg'},
    ]}
    clean = online_recipe_data(data)
    assert clean['image_url'] == 'https://example.org/cover.jpg'
    assert len(clean['photos']) == 2 and clean['photos'][1]['artist'] == 'Bea'
    assert all('image' not in p for p in clean['photos']) and 'image' not in clean
    for url in ('http://example.org/photo.jpg', 'https://user:pw@example.org/p.jpg',
                'https://100.100.100.100/p.jpg', 'https://mesa.tail123.ts.net/p.jpg',
                'https://localhost/p.jpg'):
        assert not online_photo_url(url)


def test_import_url_does_not_download_image_bytes(api, monkeypatch):
    url = 'https://example.org/receta'
    html = json.dumps({'@type': 'Recipe', 'name': 'Pan',
        'recipeIngredient': ['500 g de harina'],
        'recipeInstructions': 'Amasar.', 'image': ['/uno.jpg', '/dos.jpg']})
    monkeypatch.setattr('server.fetcher.fetch_page', lambda _: (html, url))
    def fail(_):
        raise AssertionError('No image request allowed during import')
    monkeypatch.setattr('server.fetcher.fetch_image', fail)
    response = api.post('/v1/import-url', json={'url': url})
    assert response.status_code == 200
    photos = response.json()['photos']
    assert [p['url'] for p in photos] == ['https://example.org/uno.jpg', 'https://example.org/dos.jpg']
    assert all('image' not in p for p in photos)


def test_database_migration_strips_live_history_and_receipts_without_breaking_retry(api):
    raw = base64.b64encode(photo_bytes()).decode()
    data = recipe() | {'image': raw, 'photos': [
        {'image': raw, 'url': 'https://example.org/photo.jpg', 'artist': 'Ana'}]}
    response = send(api, data=data).json()
    # Reconstruct legacy persisted state and receipts from a previous release.
    with api.app.state.db() as con:
        con.execute("DELETE FROM meta WHERE key='online-photos-v1'")
        con.execute('UPDATE entities SET data=?', (json.dumps(data),))
        old = response['results'][0]['entity'] | {'data': data}
        con.execute('UPDATE changes SET entity=?', (json.dumps(old),))
        con.execute('UPDATE operations SET result=?', (json.dumps({
            'id': 'op1', 'status': 'applied', 'entity': old}),))
        con.execute('INSERT INTO history(entity_id,snapshot,at,author) VALUES (?,?,?,?)',
                    ('r1', json.dumps(old), '2026-10-11', 'Test'))
    fresh = TestClient(create_app(api.app.state.root))
    fresh.headers.update(api.headers)
    snapshot = fresh.get('/v1/snapshot').json()['entities'][0]
    assert snapshot['data']['image_url'] == 'https://example.org/photo.jpg'
    assert snapshot['data']['ingredients'] == data['ingredients']
    assert snapshot['revision'] == 1
    assert send(fresh, data=data).json() == response
    with fresh.app.state.db() as con:
        for table, column in [('entities', 'data'), ('changes', 'entity'),
                              ('history', 'snapshot'), ('operations', 'result')]:
            assert all(raw not in row[column] for row in con.execute(f'SELECT {column} FROM {table}'))
        assert con.execute('SELECT COUNT(*) FROM changes').fetchone()[0] == 2
