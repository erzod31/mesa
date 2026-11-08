"""Publisher-specific structured lookups. Public data only, no accounts or PRO content."""
import json
import re
from urllib.parse import urlencode, urlsplit

from .fetcher import _fetch_public
from .importer import clean


def kiwilimon_search(query='', page=1):
    body = urlencode({'q': query.strip() or 'pollo', 'language':'es', 'device':'pc', 'quantity':'24', 'page':str(page)}).encode()
    raw, _ = _fetch_public('https://gr.kiwilimon.com/v6/search', post_data=body)
    data = json.loads(raw)
    items = []
    for row in data.get('payload', []):
        image, key, path = row.get('imagen',''), row.get('c'), row.get('ruta','')
        if row.get('t') != 'receta' or not isinstance(key,int) or not path.startswith('/receta/') or not re.fullmatch(r'[\w.-]+\.(jpe?g|png)',image,re.I):
            continue
        items.append(dict(id='https://www.kiwilimon.com'+path, title=clean(row.get('nombre','')),provider='mx-kiwilimon',
                          image=f'https://cdn7.kiwilimon.com/recetaimagen/{key}/960x640/{image}.jpg'))
    return dict(items=items,cursor=str(page+1) if data.get('more') else None,notice='Recetas con pollo para empezar. Busca otro plato o ingrediente.' if not query.strip() else 'Consulta individual de la API pública en español.')


def kiwilimon_recipe(url, html):
    parsed = urlsplit(url)
    if parsed.hostname != 'www.kiwilimon.com' or not parsed.path.startswith('/receta/'):
        raise ValueError('Usa el enlace de una receta de Kiwilimón.')
    body = urlencode({'language': 'es', 'device': 'pc', 'path': parsed.path, 'ingredients': '1'}).encode()
    raw, _ = _fetch_public('https://gr.kiwilimon.com/v6/recipe', post_data=body)
    data = json.loads(raw)
    if data.get('language') != 'es' or not data.get('ingredients') or not data.get('steps'):
        raise ValueError('La API pública no ofrece esta receta completa en español.')
    ingredients = [clean(x.get('text','')) for x in data['ingredients'] if x.get('text')]
    steps = [clean(x.get('text','')) for x in data['steps'] if x.get('text')]
    key = data.get('key')
    if not isinstance(key, int):
        raise ValueError('La fuente no devuelve un identificador de receta válido.')
    photos = []
    seen = set()
    for image in [data.get('image')] + [x.get('image') for x in data.get('images', [])]:
        if not isinstance(image, str) or not re.fullmatch(r'[\w.-]+\.jpe?g',image,re.I) or image in seen:
            continue
        seen.add(image)
        photos.append(dict(url=f'https://cdn7.kiwilimon.com/recetaimagen/{key}/960x640/{image}.jpg', source=url,
                           caption=data.get('name',''), artist='', license='', license_url='', image=''))
    return dict(title=clean(data.get('name',''))[:250], ingredients=ingredients, steps=steps, servings=data.get('portions') or 1,
                servings_declared=bool(data.get('portions')), yield_unit='porciones', yield_original=str(data.get('portions') or ''),
                minutes=data.get('totaltime') if isinstance(data.get('totaltime'),int) else 0,
                source=url, tags=[], image='', photos=photos,
                notes=clean(data.get('description',''))+'\nConsulta individual mediante API pública documentada; no constituye una base con licencia libre. Revisa cantidades abiertas y fotos de usuarios.')
