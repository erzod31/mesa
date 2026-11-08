"""Regressions for lost amounts, unrelated content, compressed pages and source identity."""
import json
from pathlib import Path
import pytest

from server.importer import extract_recipe, duration_minutes
from server.catalogs import publisher_catalog, publisher_origin
from server.photos import hydrate_photos
from server.test_api import api


@pytest.fixture(autouse=True)
def publisher_adapter_fixtures(monkeypatch):
    # Exercise dormant adapters against synthetic fixtures. This grants no
    # permission and never enables the production registry or network access.
    from server.catalogs import SOURCES
    for key,row in list(SOURCES.items()):
        if row['mode']=='book':monkeypatch.setitem(SOURCES,key,{**row,'mode':'web'})


def schema(**fields):
    return '<script type="application/ld+json">'+json.dumps({'@type':'Recipe','name':'Pan','recipeIngredient':['500 g de harina'],
                                                           'recipeInstructions':[{'text':'Amasar.'}],**fields})+'</script>'

def test_foreign_publisher_without_language_uses_the_selected_catalogue():
    r=extract_recipe(schema(name='Bread',recipeIngredient=['2 eggs'],recipeInstructions=['Mix.'],image='/bread.jpg'),
                     'https://based.cooking/bread/',language='en')
    assert r['language']=='en'
    assert publisher_origin(r,'open-based')['origin']['language']=='en'

@pytest.mark.parametrize('explicit',[True,False])
def test_foreign_url_import_keeps_language_even_without_html_lang(api,monkeypatch,explicit):
    url='https://based.cooking/bread/'
    page=schema(name='Bread',recipeIngredient=['2 eggs'],recipeInstructions=['Mix.'],image='/bread.jpg')
    monkeypatch.setattr('server.fetcher.fetch_page',lambda u:(page,url))
    monkeypatch.setattr('server.photos.hydrate_photos',lambda r,**kw:None)
    body={'url':url,**({'provider':'open-based'} if explicit else {})}
    response=api.post('/v1/import-url',json=body)
    assert response.status_code==200
    assert response.json()['language']=='en' and response.json()['origin']['provider']=='open-based'


def test_empty_schema_is_not_accepted_instead_of_complete_recipe():
    data=extract_recipe(schema(recipeIngredient=[],recipeInstructions=[])+schema(recipeYield='8 arepas',totalTime='P0DT0H45M0S'), 'https://example.org/pan')
    assert data['ingredients']==['500 g de harina']
    assert data['minutes']==45 and data['yield_unit']=='arepas' and data['servings']==8
    with pytest.raises(ValueError): extract_recipe(schema(recipeIngredient=[],recipeInstructions=[]))


@pytest.mark.parametrize('value,expected',[('P1DT2H3M4S',1564),('PT45M',45),('PT1H',60),('',0),('unknown',0)])
def test_day_hour_minute_second_durations(value,expected):
    assert duration_minutes(value)==expected


def test_visible_amounts_and_gallery_survive_layout_and_lazy_loading():
    text=schema(recipeIngredient=['harina'],image='/pan.jpg')+'''<body class="content-sidebar comments-open"><div class="content-sidebar-wrap"><div class="entry-content">
      <li class="wprm-recipe-ingredient"><span>500</span><span>g</span><span>de harina</span></li>
      <div class="wprm-recipe-instruction-text">Amasar.</div>
      <img src="data:image/svg+xml,x" data-lazy-src="/paso-300x200.jpg" alt="Paso">
      <img src="/paso-1024x683.jpg" alt="Paso">
      <a href="/otro-plato"><img src="/otro.jpg" alt="Otra receta"></a>
      <div class="related-posts"><img src="/relacionada.jpg"></div>
    </div></div></body>'''
    r=extract_recipe(text,'https://example.org/pan')
    assert r['ingredients']==['500 g de harina']
    assert len(r['photos'])==2 and all('otro' not in p['url'] for p in r['photos'])


def test_regional_yield_and_section_boundaries_override_broken_schema():
    text=schema(recipeIngredient=['carne'],recipeInstructions=[],recipeYield='4 personas')+'''<div class="elementor-widget-container">
    <h2>Ingredientes</h2><h3>para 1 docena de empanadas</h3><ul><li>12 tapas para empanadas</li><li>1/2 kg de carne</li></ul>
    <h2>Receta de empanadas de carne</h2><ol><li>Preparar el relleno.</li><li>Hornear.</li></ol></div>
    <h4>Más recetas con estos ingredientes</h4><ul><li>999 g de otra receta</li></ul>'''
    r=extract_recipe(text,'https://www.paulinacocina.net/empanadas/')
    assert len(r['ingredients'])==2 and len(r['steps'])==2
    assert r['servings']==12 and r['yield_unit']=='empanadas'


def test_publisher_links_keep_amounts_and_editor_ownership():
    r=extract_recipe(schema(image='/pan.jpg'),'https://www.paulinacocina.net/pan/')
    publisher_origin(r,'ar-paulina')
    assert r['origin']['language']=='es' and r['origin']['provider']=='ar-paulina'
    assert 'libre' not in r['origin']['license']
    with pytest.raises(ValueError): publisher_origin(r,'ec-laylita')
    with pytest.raises(ValueError): publisher_origin({**r,'photos':[]},'ar-paulina')


@pytest.mark.parametrize('provider,url',[
    ('es-bonviveur','https://bonviveur.com/es/recetas/tortilla-de-betanzos'),
    ('es-gratis','https://recetas.elperiodico.com/receta-de-lentejas-con-arroz-y-tomate-59773.html'),
])
def test_verified_publisher_redirects_keep_the_selected_source(provider,url,monkeypatch):
    page=schema(image='https://cdn0.recetasgratis.net/pan.jpg')
    monkeypatch.setattr('server.catalogs.fetch_page',lambda target:(page,url))
    result=publisher_catalog(provider,url)
    assert result['items'][0]['id']==url
    recipe=publisher_origin(extract_recipe(page,url),provider)
    assert recipe['origin']['provider']==provider and recipe['origin']['url']==url
    with pytest.raises(ValueError): publisher_catalog(provider,'https://example.org/receta')


def test_catalogue_excludes_navigation_without_photo_and_other_publishers(monkeypatch):
    monkeypatch.setattr('server.catalogs.fetch_page',lambda url: ('''<main><article><a href="/pan/"><img src="/uploads/pan.jpg" alt="Pan con arracacha"></a></article>
      <nav><a href="/contacto/"><img src="/contacto.jpg" alt="Contacto del editor"></a></nav>
      <article><a href="https://evil.example/receta"><img src="/bad.jpg" alt="Receta falsa"></a></article></main>''','https://www.paulinacocina.net/'))
    result=publisher_catalog('ar-paulina')
    assert [x['id'] for x in result['items']]==['https://www.paulinacocina.net/pan/']
    with pytest.raises(ValueError): publisher_catalog('not-a-source')
    with pytest.raises(ValueError): publisher_catalog('ar-paulina','https://example.com/pan/')


def test_catalogue_endpoint_requires_auth_and_forwards_bounded_query(api,monkeypatch):
    calls=[]
    monkeypatch.setattr('server.catalogs.publisher_catalog',lambda p,q,c: calls.append((p,q,c)) or {'items':[],'cursor':None})
    assert api.get('/v1/catalog/ar-paulina?q=pan').status_code==200
    assert calls==[('ar-paulina','pan',None)]
    assert api.get('/v1/catalog/ar-paulina?q='+('x'*4001)).status_code==422
    api.headers.pop('Authorization')
    assert api.get('/v1/catalog/ar-paulina').status_code==401


def test_photo_retry_does_not_repeat_already_saved_downloads(monkeypatch):
    calls=[]
    monkeypatch.setattr('server.fetcher.fetch_image',lambda url: calls.append(url) or (_ for _ in ()).throw(ValueError('offline')))
    r={'photos':[{'url':'https://example.org/saved.jpg'},{'url':'https://example.org/missing.jpg'}]}
    hydrate_photos(r,skip_urls={'https://example.org/saved.jpg'})
    assert calls==[] and len(r['photos'])==2


def test_retired_sources_are_removed_from_shared_directory():
    from server.catalogs import SOURCES
    assert not {'sabores-uy', 'agro-arracacha', 'agro-caribe'} & SOURCES.keys()
    assert len(SOURCES) == 25
    assert [s['id'] for s in SOURCES.values() if s['mode']=='asset']==['book-polaca']


def test_shared_kiwilimon_url_automatically_uses_public_adapter(api,monkeypatch):
    url='https://www.kiwilimon.com/receta/desayunos/chilaquiles-rojos'
    monkeypatch.setattr('server.fetcher.fetch_page',lambda u: ('<html></html>',url))
    monkeypatch.setattr('server.publisher_adapters.kiwilimon_recipe',lambda u,h: {'title':'Chilaquiles rojos',
      'ingredients':['4 jitomates'],'steps':['Cocinar.'],'servings':4,'minutes':40,'source':u,'photos':[{'url':'https://cdn7.kiwilimon.com/foto.jpg'}]})
    monkeypatch.setattr('server.photos.hydrate_photos',lambda r,**kw: None)
    result=api.post('/v1/import-url',json={'url':url}).json()
    assert result['origin']['provider']=='mx-kiwilimon' and result['ingredients']==['4 jitomates']


def test_kiwilimon_initial_query_returns_recipes_instead_of_empty_generic_search(monkeypatch):
    from urllib.parse import parse_qs
    from server.publisher_adapters import kiwilimon_search
    calls=[]
    def search(url, *, post_data):
        calls.append(parse_qs(post_data.decode()))
        return json.dumps({'more':True,'payload':[{'t':'receta','c':123,'ruta':'/receta/pollo','imagen':'123.jpg','nombre':'Pollo al horno'}]}).encode(),url
    monkeypatch.setattr('server.publisher_adapters._fetch_public',search)
    result=kiwilimon_search()
    assert calls[0]['q']==['pollo'] and len(result['items'])==1 and result['cursor']=='2'
    assert 'pollo' in result['notice']
    kiwilimon_search('pan')
    assert calls[1]['q']==['pan']


def test_petitchef_initial_catalog_returns_fifty_distinct_photo_recipes(monkeypatch):
    calls=[]
    cards=''.join(f'<article><a href="/recetas/plato/prueba-fid-{i}"><img src="/uploads/foto-{i}.jpg" alt="Receta de prueba {i}"></a></article>' for i in range(1,101))
    cards+='<a href="/recetas/plato/prueba-fid-1"><img src="/uploads/dup.jpg" alt="Duplicada"></a><a href="/articulos/prueba-fid-333"><img src="/uploads/art.jpg" alt="Articulo ajeno"></a><a href="/recetas/plato/sin-foto-fid-333">Sin fotografia</a>'
    def fetch(url):
        calls.append(url)
        return cards,url
    monkeypatch.setattr('server.catalogs.fetch_page',fetch)
    first=publisher_catalog('es-petitchef')
    assert len(first['items'])==50 and first['cursor']=='50'
    assert first['items'][0]['title']=='Receta de prueba 1' and first['items'][-1]['title']=='Receta de prueba 50'
    second=publisher_catalog('es-petitchef',cursor=first['cursor'])
    assert len(second['items'])==50 and second['cursor'] is None
    assert len({x['id'] for x in first['items']+second['items']})==100
    assert calls==['https://www.petitchef.es/las-ultimas-recetas']*2


def test_petitchef_invalid_cursor_does_not_fetch(monkeypatch):
    monkeypatch.setattr('server.catalogs.fetch_page',lambda url: pytest.fail('Invalid cursor fetched'))
    for cursor in ('-1','1','100','https://example.org'):
        with pytest.raises(ValueError): publisher_catalog('es-petitchef',cursor=cursor)


def test_petitchef_search_uses_public_form_and_empty_results_are_not_invented(monkeypatch):
    from urllib.parse import parse_qs,urlsplit
    calls=[]
    def fetch(url):
        calls.append(url)
        return '<main></main>',url
    monkeypatch.setattr('server.catalogs.fetch_page',fetch)
    initial=publisher_catalog('es-petitchef')
    assert not initial['items'] and initial['cursor'] is None
    monkeypatch.setattr('server.catalogs.fetch_page',lambda url: (calls.append(url) or '<article><a href="/recetas/plato/pollo-fid-1"><img src="/uploads/pollo.jpg" alt="Pollo al horno"></a></article>',url))
    result=publisher_catalog('es-petitchef',query='pollo')
    assert len(result['items'])==1
    assert urlsplit(calls[-1]).path=='/index.php' and parse_qs(urlsplit(calls[-1]).query)=={'obj':['feed'],'action':['list'],'q':['pollo']}
