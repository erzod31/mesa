import base64
from io import BytesIO
import json

from PIL import Image
from server.importer import extract_recipe
from server.photos import hydrate_photos
from server.test_api import api, send, recipe


def photo_bytes():
    buf = BytesIO()
    Image.new('RGB', (20, 12), color='red').save(buf, 'PNG')
    return buf.getvalue()


def test_jsonld_all_recipe_and_step_photos_and_quantities():
    data = extract_recipe(json.dumps({
        '@type': 'Recipe', 'name': 'Pan',
        'recipeIngredient': ['500 g de harina', '1½ tazas de agua'],
        'image': ['/pan.jpg', {'contentUrl': '/otra.jpg', 'creator': {'name': 'Ana'}, 'license': 'https://creativecommons.org/licenses/by/4.0/'}],
        'recipeInstructions': [{'@type': 'HowToSection', 'itemListElement': [{'text': 'Amasar.', 'image': ['/pan.jpg', '/paso.jpg']}]}],
    }), 'https://example.org/recetas/pan')
    assert data['ingredients'] == ['500 g de harina', '1½ tazas de agua']
    assert [p['url'] for p in data['photos']] == ['https://example.org/pan.jpg', 'https://example.org/otra.jpg', 'https://example.org/paso.jpg']
    assert data['photos'][1]['artist'] == 'Ana'
    assert data['photos'][1]['license_url'].endswith('/by/4.0/')


def test_import_preserves_all_references_without_requesting_images(monkeypatch):
    def fetch(url):
        raise AssertionError('Image bytes must not be requested')
    monkeypatch.setattr('server.fetcher.fetch_image', fetch)
    data = {'photos': [{'url': 'https://example.org/good.jpg', 'artist': 'Ana'},
                       {'url': 'https://example.org/bad.jpg', 'artist': 'Bea'}]}
    hydrate_photos(data)
    assert len(data['photos']) == 2
    assert all('image' not in p and 'error' not in p for p in data['photos'])
    assert data['photos'][1]['artist'] == 'Bea'


def test_photos_survive_sync_export_and_validation(api):
    data = recipe() | {'photos': [
        {'image': base64.b64encode(photo_bytes()).decode(), 'artist': 'Ana', 'license': 'CC BY 4.0'},
        {'image': '', 'url': 'https://example.org/paso.jpg', 'caption': 'Paso dos'},
    ]}
    assert send(api, data=data).status_code == 200
    saved = api.get('/v1/export').json()['entities'][0]['data']
    assert saved['photos'] == [{'url': 'https://example.org/paso.jpg', 'caption': 'Paso dos'}]
    assert 'image' not in saved
    assert send(api, data=data).json()['results'][0]['entity']['data'] == saved
    assert send(api, eid='invalid', oid='bad', data=recipe() | {'photos': [{'image': 'not-base64'}]}).status_code == 422
    assert send(api, eid='invalidtype', oid='badtype', data=recipe() | {'photos': [{'image': 123}]}).status_code == 422
