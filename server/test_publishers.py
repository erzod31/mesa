"""Regresiones de cantidades, contenido ajeno y propiedad de fuente."""
import json
import pytest

from server.importer import extract_recipe, duration_minutes
from server.catalogs import publisher_catalog, publisher_origin
from server.photos import hydrate_photos
from server.test_api import api


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


def test_free_source_origin_keeps_license_and_rejects_foreign_or_photoless_recipes():
    r=extract_recipe(schema(image='/pan.jpg'),'https://based.cooking/pan/',language='en')
    origin=publisher_origin(r,'open-based')
    assert origin['origin']['language']=='en' and origin['origin']['provider']=='open-based'
    assert 'Dominio público' in origin['origin']['license']
    with pytest.raises(ValueError): publisher_origin(r,'es-creativegan')
    with pytest.raises(ValueError): publisher_origin({**r,'photos':[]},'open-based')


def test_catalogue_endpoint_requires_auth_and_forwards_bounded_query(api,monkeypatch):
    calls=[]
    monkeypatch.setattr('server.catalogs.publisher_catalog',lambda p,q,c: calls.append((p,q,c)) or {'items':[],'cursor':None})
    assert api.get('/v1/catalog/wiki-es?q=pan').status_code==200
    assert calls==[('wiki-es','pan',None)]
    assert api.get('/v1/catalog/wiki-es?q='+('x'*4001)).status_code==422
    api.headers.pop('Authorization')
    assert api.get('/v1/catalog/wiki-es').status_code==401


def test_photo_retry_does_not_repeat_already_saved_downloads(monkeypatch):
    calls=[]
    monkeypatch.setattr('server.fetcher.fetch_image',lambda url: calls.append(url) or (_ for _ in ()).throw(ValueError('offline')))
    r={'photos':[{'url':'https://example.org/saved.jpg'},{'url':'https://example.org/missing.jpg'}]}
    hydrate_photos(r,skip_urls={'https://example.org/saved.jpg'})
    assert calls==[] and len(r['photos'])==2


def test_registry_only_holds_sources_with_in_app_content():
    from server.catalogs import SOURCES
    assert not {'sabores-uy', 'agro-arracacha', 'agro-caribe'} & SOURCES.keys()
    assert len(SOURCES) == 12
    assert [s['id'] for s in SOURCES.values() if s['mode']=='asset']==['book-polaca']
    assert all(s['mode']!='book' for s in SOURCES.values())
    for removed in ('es-petitchef','mx-kiwilimon','ar-paulina','es-gratis'):
        with pytest.raises(ValueError): publisher_catalog(removed)


def test_mealdb_catalog_browses_letters_and_searches_with_photos(monkeypatch):
    payload = json.dumps({'meals': [
        {'idMeal': '52772', 'strMeal': 'Spicy Arrabiata Penne', 'strMealThumb': 'https://www.themealdb.com/images/media/meals/a.jpg'},
        {'idMeal': '52893', 'strMeal': 'Apple Tart', 'strMealThumb': ''},
    ]})
    calls = []
    def fetch(url):
        calls.append(url)
        return payload, url
    monkeypatch.setattr('server.open_catalogs.fetch_page', fetch)
    result = publisher_catalog('open-mealdb')
    assert len(result['items']) == 1 and result['items'][0]['title'] == 'Spicy Arrabiata Penne'
    assert result['items'][0]['id'].endswith('i=52772') and result['cursor'] == 'b'
    searched = publisher_catalog('open-mealdb', query='pasta')
    assert searched['items'][0]['title'] == 'Spicy Arrabiata Penne' and searched['cursor'] is None
    assert calls[0].endswith('?f=a') and 'search.php' in calls[1]
    with pytest.raises(ValueError): publisher_catalog('open-mealdb', cursor='zz')
    with pytest.raises(ValueError): publisher_catalog('open-mealdb', query='https://www.themealdb.com/meal/52772')


def test_mealdb_detail_builds_recipe_with_measures_and_origin(monkeypatch):
    from server.open_catalogs import mealdb_recipe
    payload = json.dumps({'meals': [{'idMeal': '52772', 'strMeal': 'Spicy Arrabiata Penne',
        'strMealThumb': 'https://www.themealdb.com/images/media/meals/a.jpg',
        'strIngredient1': 'Penne rigate', 'strMeasure1': '1 pound',
        'strIngredient2': 'Olive oil', 'strMeasure2': '1/4 cup',
        'strIngredient3': '', 'strMeasure3': '',
        'strInstructions': 'Heat the oil.\r\nAdd the pasta.'}]})
    monkeypatch.setattr('server.open_catalogs.fetch_page', lambda u: (payload, u))
    recipe = mealdb_recipe('https://www.themealdb.com/api/json/v1/1/lookup.php?i=52772')
    assert recipe['language'] == 'en'
    assert recipe['ingredients'] == ['1 pound Penne rigate', '1/4 cup Olive oil']
    assert recipe['steps'] == ['Heat the oil.', 'Add the pasta.']
    assert recipe['origin']['provider'] == 'open-mealdb'
    assert recipe['origin']['license'] == 'Gratuita · atribución requerida'
    assert recipe['photos'][0]['url'] == 'https://www.themealdb.com/images/media/meals/a.jpg'
    with pytest.raises(ValueError): mealdb_recipe('https://www.themealdb.com/meal/52772')
    with pytest.raises(ValueError): mealdb_recipe('https://evil.example/api/json/v1/1/lookup.php?i=52772')
    with pytest.raises(ValueError): mealdb_recipe('https://www.themealdb.com/api/json/v1/1/lookup.php?i=abc')
