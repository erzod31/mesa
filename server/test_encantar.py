import copy
import json
from pathlib import Path
import pytest
from .encantar import parse_post, recipe_url, catalog, import_recipe

FIXTURES=Path(__file__).with_name('fixtures')

def post():
    return json.loads((FIXTURES/'encantar-post.json').read_text(encoding='utf-8'))

def test_original_amounts_steps_photos_and_license():
    recipe=parse_post(post())
    assert len(recipe['ingredients'])==4
    assert recipe['ingredients'][0]=='750g de judías verdes o vainas, muy frescas'
    assert len(recipe['steps'])==4
    assert len(recipe['photos'])==4
    assert not recipe['servings_declared']
    assert recipe['origin']['license']=='CC BY-NC 3.0'
    assert all(p['artist'] and p['source']==recipe['source'] for p in recipe['photos'])
    assert recipe['source'].startswith('https://recetasparaencantar.com/')
    assert all(not p['image'] for p in recipe['photos'])

@pytest.mark.parametrize('url',[
    'https://evil.example/2020/04/26/test/',
    'https://recetasparaencantar.com@evil.example/2020/04/26/test/',
    'https://recetasparaencantar.com:444/2020/04/26/test/',
    'https://recetasparaencantar.com/bienvenida/',
])
def test_rejects_non_recipe_urls(url):
    with pytest.raises(ValueError): recipe_url(url)

def test_news_missing_amounts_or_external_photos_are_excluded():
    for content in [
        '<p>Esta semana hablamos de cocina.</p>',
        '<h2>Ingredientes</h2><ul><li>Arroz</li></ul><h2>Preparación</h2><p>Cocer.</p>',
        '<h2>Ingredientes</h2><ul><li>200 g de arroz</li></ul><h2>Preparación</h2><p>Cocer.</p><img src="https://evil.example/2020/04/foto.jpg">',
    ]:
        value=copy.deepcopy(post()); value['content']=content
        assert parse_post(value) is None

def test_catalog_and_import_use_public_api_and_keep_original_credit(monkeypatch):
    from . import encantar
    calls=[]
    def fetch(url):
        calls.append(url)
        if '/slug:' in url: return json.dumps(post()),url
        return json.dumps({'found':17,'posts':[post()]}),url
    monkeypatch.setattr(encantar,'fetch_page',fetch)
    result=catalog('judías')
    assert result['cursor']=='2'
    recipe=import_recipe(result['items'][0]['id'])
    assert recipe['origin']['attribution']=='Dana Madiana · Recetas para encantar'
    assert all(u.startswith(encantar.API) for u in calls)

def test_live_sample_contains_only_complete_original_cards():
    data=json.loads((FIXTURES/'encantar-posts.json').read_text(encoding='utf-8'))
    recipes=[r for p in data['posts'] if (r:=parse_post(p))]
    assert len(recipes)>=12
    assert all(r['ingredients'] and r['steps'] and r['photos'] for r in recipes)
