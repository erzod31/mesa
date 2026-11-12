import json
from pathlib import Path

import pytest

from server import licensed_collections as books
from server.catalogs import SOURCES, publisher_catalog
from server.creativegan import parse_recipe
from server.test_api import api


def test_creativegan_keeps_original_amounts_and_stops_before_copyright():
    text = Path(__file__).with_name('fixtures').joinpath('creativegan-arroz.html').read_text(encoding='utf8')
    row = parse_recipe(text, 'https://creativegan.net/archives/arroz-con-leche-de-soja/')
    assert len(row['ingredients']) == 6 and len(row['steps']) == 2
    assert row['ingredients'][1] == '3/4 l. de leche de soja'
    assert row['servings'] == 4 and row['servings_declared']
    assert 'fusilado' not in ' '.join(row['steps'])
    assert row['origin']['license'] == 'CC BY-NC-SA 3.0 ES'


def test_creativegan_print_cards_do_not_duplicate_prose_or_mix_recipes():
    posts = json.loads(Path(__file__).with_name('fixtures').joinpath('creativegan-recipes.json').read_text(encoding='utf8'))
    by_slug = {}
    for post in posts:
        if post['link'].endswith('/parmigiana-vegana-de-zaraida/'):
            with pytest.raises(ValueError):parse_recipe(post['content']['rendered'],post['link'],post['title']['rendered'])
            continue
        try:row=parse_recipe(post['content']['rendered'],post['link'],post['title']['rendered'])
        except ValueError:continue
        by_slug[post['link'].split('/')[-2]]=row
        assert not any('Precalienta' in s or 'En una cacerola' in s for s in row['ingredients'])
    assert len(by_slug)>=9
    assert len(by_slug['flan-de-platano']['ingredients'])==3
    assert len(by_slug['soja-stroganoff']['ingredients'])==15
    assert not any('sobras de mujaddara' in s for s in by_slug['mujaddara']['ingredients'])


def test_pdf_selection_contains_only_reviewed_pages_quantities_and_photo_pairs():
    selection=books.collection('book-polaca')
    assert len(selection['recipes'])==12
    assert selection['document']['photo_pages']==list(range(91,114,2))
    for row in selection['recipes']:
        assert row['ingredients'] and row['steps'] and row['photos']
        assert row['origin']['license']=='CC BY 4.0'
        assert books.recipe('book-polaca',row['source'])==row
    assert '350 g de patatas' in books.recipe('book-polaca','100')['ingredients']
    assert '500–600 g de ciruelas' in books.recipe('book-polaca','100')['ingredients']
    assert '650 ml de agua' in books.recipe('book-polaca','94')['ingredients']
    assert len(books.catalog('book-polaca','ñOQuis')['items'])==1
    assert not books.catalog('book-polaca','inexistente')['items']
    with pytest.raises(ValueError):books.recipe('book-polaca','128')
    with pytest.raises(ValueError):books.photo('book-polaca',128)
    with pytest.raises(ValueError):books.collection('../../data')


def test_removed_publishers_are_unknown_and_rejected(api,monkeypatch):
    page='<script type="application/ld+json">{"@type":"Recipe","name":"Pan","recipeIngredient":["500 g de harina"],"recipeInstructions":["Amasar."],"image":["/pan.jpg"]}</script>'
    monkeypatch.setattr('server.fetcher.fetch_page',lambda u:(page,u))
    monkeypatch.setattr('server.photos.hydrate_photos',lambda r,**kw:None)
    assert not [s for s in SOURCES.values() if s['mode']=='book']
    for source_id in ('es-petitchef','mx-kiwilimon','es-gratis','ar-paulina'):
        with pytest.raises(ValueError,match='desconocida'):publisher_catalog(source_id)
        assert api.post('/v1/import-url',json={'url':'https://www.petitchef.es/recetas/plato/pan-fid-1','provider':source_id}).status_code==422


def test_unregistered_recipe_url_uses_generic_extraction(api,monkeypatch):
    page='<script type="application/ld+json">{"@type":"Recipe","name":"Pan","recipeIngredient":["500 g de harina"],"recipeInstructions":["Amasar."],"image":["/pan.jpg"]}</script>'
    monkeypatch.setattr('server.fetcher.fetch_page',lambda u:(page,u))
    monkeypatch.setattr('server.photos.hydrate_photos',lambda r,**kw:None)
    response=api.post('/v1/import-url',json={'url':'https://recetas.elperiodico.com/receta-pan.html'})
    assert response.status_code==200
    assert response.json()['ingredients']==['500 g de harina']


def test_document_photo_authentication_no_store_and_immutable_fingerprint(api,monkeypatch):
    calls=[]
    monkeypatch.setattr(books,'photo',lambda provider,page:calls.append((provider,page)) or b'jpeg')
    response=api.get('/v1/source-photo/book-polaca/91')
    assert response.status_code==200 and response.content==b'jpeg'
    assert response.headers['cache-control']=='no-store'
    api.headers.pop('Authorization')
    assert api.get('/v1/source-photo/book-polaca/91').status_code==401
    assert calls==[('book-polaca',91)]


def test_changed_document_is_rejected_without_decoding(monkeypatch):
    monkeypatch.setattr(books,'_document',None)
    monkeypatch.setattr(books,'fetch_document',lambda url:(b'%PDF unexpected revision',url))
    with pytest.raises(ValueError,match='cambiado'):books.photo('book-polaca',91)
    assert books._document is None


def test_missing_featured_media_keeps_complete_recipes(monkeypatch):
    from server import creativegan
    posts=json.loads(Path(__file__).with_name('fixtures').joinpath('creativegan-recipes.json').read_text(encoding='utf8'))
    for post in posts:post['_embedded']={'wp:featuredmedia':[]}
    monkeypatch.setattr(creativegan,'fetch_page',lambda url:(json.dumps(posts),url))
    result=creativegan.catalog()
    assert len(result['items'])==11 and result['cursor']=='2'
    assert all(item['image'].startswith('https://') for item in result['items'])


def test_licensed_recipes_round_trip_through_family_sync_and_export(api):
    rows=books.collection('book-polaca')['recipes']
    generation=api.get('/v1/snapshot').json()['generation']
    operations=[{'id':f'licensed-op-{i}','entity_id':f'licensed-{i}','kind':'recipe','base':0,'data':row} for i,row in enumerate(rows)]
    response=api.post('/v1/push',json={'generation':generation,'operations':operations})
    assert response.status_code==200,response.text
    exported=api.get('/v1/export').json()['entities']
    assert len(exported)==12
    for entity in exported:
        row=entity['data']
        assert row['origin']['license']=='CC BY 4.0'
        assert row['photos'][0]['url'].startswith('https://bunkatura.pl/pdf/mesa_polaca.pdf?mesa_recipe_image=')
        assert 'image' not in row and 'image' not in row['photos'][0]
