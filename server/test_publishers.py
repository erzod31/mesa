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
    assert len(SOURCES) == 22
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


def test_cocktaildb_browses_and_builds_cocktails_with_measures(monkeypatch):
    from server.catalogs import publisher_catalog
    payload = json.dumps({'drinks': [
        {'idDrink': '11007', 'strDrink': 'Margarita', 'strDrinkThumb': 'https://www.thecocktaildb.com/images/media/drink/a.jpg'},
        {'idDrink': '11008', 'strDrink': 'Apple Mojito', 'strDrinkThumb': ''},
    ]})
    calls = []
    monkeypatch.setattr('server.open_catalogs.fetch_page', lambda u: calls.append(u) or (payload, u))
    result = publisher_catalog('open-cocktaildb')
    assert len(result['items']) == 1 and result['items'][0]['title'] == 'Margarita'
    assert result['items'][0]['id'].endswith('i=11007') and result['cursor'] == 'b'
    assert calls[0].endswith('?f=a') and 'cocktaildb.com' in calls[0]
    searched = publisher_catalog('open-cocktaildb', query='mojito')
    assert searched['items'][0]['title'] == 'Margarita' and searched['cursor'] is None
    from server.open_catalogs import mealdb_recipe
    detail = json.dumps({'drinks': [{'idDrink': '11007', 'strDrink': 'Margarita',
        'strDrinkThumb': 'https://www.thecocktaildb.com/images/media/drink/a.jpg',
        'strIngredient1': 'Tequila', 'strMeasure1': '1 1/2 oz',
        'strIngredient2': 'Lime juice', 'strMeasure2': '1 oz',
        'strIngredient3': '', 'strMeasure3': '',
        'strInstructions': 'Rub the rim of the glass with the lime slice.\r\nShake the other ingredients.'}]})
    monkeypatch.setattr('server.open_catalogs.fetch_page', lambda u: (detail, u))
    recipe = mealdb_recipe('https://www.thecocktaildb.com/api/json/v1/1/lookup.php?i=11007')
    assert recipe['origin']['provider'] == 'open-cocktaildb'
    assert recipe['ingredients'] == ['1 1/2 oz Tequila', '1 oz Lime juice']
    assert recipe['steps'] == ['Rub the rim of the glass with the lime slice.', 'Shake the other ingredients.']
    with pytest.raises(ValueError): mealdb_recipe('https://www.themealdb.com/api/json/v1/1/lookup.php?i=11007')



def test_chowdown_catalog_and_detail_parse_front_matter(monkeypatch):
    from server.catalogs import publisher_catalog
    from server.open_catalogs import github_recipe
    def fetch(url):
        if 'git/trees' in url:
            return json.dumps({'tree': [
                {'path': '_recipes/banana-bread.md', 'type': 'blob'},
                {'path': '_recipes/sin-foto.md', 'type': 'blob'},
                {'path': 'images/banana-bread.jpg', 'type': 'blob'},
            ]}), url
        if url.endswith('banana-bread.md'):
            return ('---\ntitle: "Banana Bread"\nimage: banana-bread.jpg\ningredients:\n- 4 bananas\n- 2 cups flour\ndirections:\n- Mash and mix.\n---\nResto'), url
        if url.endswith('sin-foto.md'):
            return ('---\ntitle: Sin foto\ningredients:\n- 2 cups flour\ndirections:\n- Mix.\n---'), url
        raise AssertionError('no esperado: ' + url[:100])
    monkeypatch.setattr('server.open_catalogs.fetch_page', fetch)
    result = publisher_catalog('open-chowdown')
    assert len(result['items']) == 1 and result['items'][0]['title'] == 'Banana Bread'
    assert result['items'][0]['image'].endswith('images/banana-bread.jpg')
    recipe = github_recipe('open-chowdown', result['items'][0]['id'])
    assert recipe['ingredients'] == ['4 bananas', '2 cups flour']
    assert recipe['steps'] == ['Mash and mix.']
    assert recipe['origin']['license'] == 'Unlicense · dominio público'
    with pytest.raises(ValueError): github_recipe('open-chowdown', 'https://raw.githubusercontent.com/otro/repo/main/x.md')


def test_freemeals_browses_and_builds_recipes(monkeypatch):
    from server.catalogs import publisher_catalog
    from server.open_catalogs import freemeals_recipe
    payload = json.dumps({'data': {'data': [
        {'idMeal': '52785', 'strMeal': 'Dal fry', 'strMealThumb': 'https://www.themealdb.com/images/media/meals/x.jpg',
         'strIngredient1': 'Toor dal', 'strMeasure1': '1 cup', 'strIngredient2': '', 'strMeasure2': '',
         'strInstructions': 'Wash the dal.\r\nBoil it.'}], 'nextPage': False}})
    monkeypatch.setattr('server.open_catalogs.fetch_page', lambda u: (payload, u))
    result = publisher_catalog('open-freemeals')
    assert len(result['items']) == 1 and result['items'][0]['title'] == 'Dal fry'
    assert result['items'][0]['id'].endswith('|52785')
    searched = publisher_catalog('open-freemeals', query='dal')
    assert searched['items'] == [] and 'no permite buscar' in searched['notice']
    recipe = freemeals_recipe('https://freeapi.app/api/v1/public/meals?page=1&i=52785')
    assert recipe['ingredients'] == ['1 cup Toor dal'] and recipe['language'] == 'en'
    assert recipe['origin']['provider'] == 'open-freemeals'
    with pytest.raises(ValueError): freemeals_recipe('https://freeapi.app/api/v1/public/meals?page=1&i=abc')
