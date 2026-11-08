from copy import deepcopy
from pathlib import Path
import pytest
from server.open_catalogs import photo_metadata
from server.importer import extract_recipe
from server.translation import translate_recipe
from server.test_api import api, send, recipe

def test_licensed_images_exclude_fair_use_and_unknown():
    info={'url':'https://upload.wikimedia.org/wikipedia/commons/a/a1/Food.jpg','extmetadata':{}}
    assert photo_metadata(info) is None
    info['extmetadata']={'LicenseShortName':{'value':'Fair use'}}
    assert photo_metadata(info) is None
    info['extmetadata']={'LicenseShortName':{'value':'CC BY-SA 4.0'},'LicenseUrl':{'value':'https://creativecommons.org/licenses/by-sa/4.0/'}}
    assert photo_metadata(info)['license']=='CC BY-SA 4.0'
    info['url']='https://thumb.wikimedia.org/wikipedia/commons/thumb/a/a1/Food.jpg/960px-Food.jpg'
    assert photo_metadata(info) is not None

def test_translation_preserves_quantities_and_metadata(monkeypatch):
    import server.translation as translation
    monkeypatch.setattr(translation,'translate_texts',lambda texts,source:[t.replace('eggs','huevos').replace('Mix','Mezclar') for t in texts])
    original={**recipe(),'ingredients':['1/2 cup flour','2 eggs'],'language':'en','photos':[{'url':'https://based.cooking/pix/food.webp'}]}
    saved=deepcopy(original)
    result=translate_recipe(original,'en')
    assert result['ingredients']==['1/2 cup flour','2 huevos']
    assert result['original']['ingredients']==original['ingredients']
    assert result['photos']==original['photos'] and original==saved
    assert translate_recipe(result,'en')==result

def test_pagination_retains_initial_cursor_and_captures_concurrent_edit(api):
    for eid in ['a','b','c']: assert send(api,eid=eid,oid=eid).status_code==200
    first=api.get('/v1/snapshot?limit=2').json()
    assert [e['id'] for e in first['entities']]==['a','b'] and first['next']=='b'
    assert send(api,eid='a',base=1,oid='a2',data=recipe('Editada')).status_code==200
    page=api.get('/v1/snapshot',params={'limit':2,'after':first['next'],'epoch':first['generation'],'start_cursor':first['cursor']}).json()
    assert page['cursor']==first['cursor'] and page['next'] is None
    assert [e['id'] for e in page['entities']]==['c']
    changes=api.get('/v1/changes',params={'epoch':first['generation'],'cursor':first['cursor']}).json()
    assert changes['entities'][0]['data']['title']=='Editada'
    assert len(api.get('/v1/export').json()['entities'])==3
    assert api.get('/v1/snapshot?limit=2&epoch=wrong').status_code==409

def test_truncated_translation_original_rejected(api):
    assert send(api,data={**recipe(),'original':{'language':'en','title':'Cake'}}).status_code==422

@pytest.mark.parametrize('provider,expected,photos,minutes',[
    ('es-rechupete',5,10,50),('es-hogarmania',4,13,40),('es-bonviveur',4,18,80),('es-gratis',12,10,30),('ar-paulina',11,1,0)])
def test_real_recipe_scope_does_not_mix_related_content(provider,expected,photos,minutes):
    from server.catalogs import SOURCES
    path=Path('client/test/fixtures/publishers')/(provider+'.html')
    value=extract_recipe(path.read_text(encoding='utf-8'),SOURCES[provider]['seed'])
    assert len(value['ingredients'])==expected
    assert len(value['photos'])>=photos
    if minutes: assert value['minutes']==minutes


def test_delokos_adapter_uses_real_public_post_structure():
    import json
    from server.wordpress_catalog import parse_post
    posts=json.loads(Path('client/test/fixtures/delokos-posts.json').read_text(encoding='utf-8'))
    recipes=[parse_post(post) for post in posts]
    assert all(r and r['photos'] and r['steps'] and r['ingredients'] for r in recipes)
    assert recipes[0]['ingredients'][0]=='800g de raxo de cerdo'
    assert len(recipes[0]['steps'])==2
    assert all(r['origin']['license']=='CC BY-NC-SA 2.5 ES' for r in recipes)


def test_wiki_recipe_keeps_illustrated_steps_and_all_licensed_photos(monkeypatch):
    import json
    import server.open_catalogs as adapter
    from server.catalogs import SOURCES
    page=json.loads(Path('client/test/fixtures/wiki-en-cake.json').read_text(encoding='utf-8'))
    monkeypatch.setattr(adapter,'wiki',lambda *args,**kwargs:{'parse':page})
    monkeypatch.setattr(adapter,'photos',lambda language,names:{name:{'url':'https://upload.wikimedia.org/wikipedia/commons/Food.jpg'} for name in adapter.photo_names(names)})
    result=adapter.wiki_recipe(SOURCES['wiki-en'],'Cookbook:1-2-3-4 Cake')
    assert len(result['steps'])>=15 and len(result['photos'])==15
    assert len(result['ingredients'])==8
