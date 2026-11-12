"""Catálogos bajo demanda de fuentes con licencia. Sin ingesta masiva ni copias remotas persistentes."""
import json
import re
from pathlib import Path
from urllib.parse import urlsplit

SOURCES = {row['id']: row for row in json.loads(Path(__file__).with_name('sources.json').read_text(encoding='utf-8'))}


def publisher_catalog(provider, query='', cursor=None):
    query = query.strip()
    source = SOURCES.get(provider)
    if not source:
        raise ValueError('Fuente desconocida.')
    if provider == 'es-encantar':
        from .encantar import catalog
        return catalog(query, cursor)
    if source['mode'] == 'asset':
        from .licensed_collections import catalog
        return catalog(provider, query, cursor)
    if provider == 'es-creativegan':
        from .creativegan import catalog
        return catalog(query, cursor)
    if provider == 'delokos-es':
        from .wordpress_catalog import catalog
        return catalog(query, cursor)
    if provider.startswith('wiki-'):
        from .open_catalogs import wiki_catalog
        return wiki_catalog(source, query, cursor)
    if provider == 'open-based':
        from .open_catalogs import based_catalog
        return based_catalog(query, cursor)
    if provider in ('open-mealdb', 'open-cocktaildb'):
        from .open_catalogs import mealdb_catalog
        return mealdb_catalog(provider, query, cursor)
    if provider == 'open-chowdown':
        from .open_catalogs import github_catalog
        return github_catalog(provider, query, cursor)
    if provider == 'open-freemeals':
        from .open_catalogs import freemeals_catalog
        return freemeals_catalog(query, cursor)
    raise ValueError('Esta fuente no ofrece catálogo en Mesa. Consulta el sitio original.')


def publisher_origin(recipe, provider):
    source = SOURCES.get(provider)
    if not source or source['mode'] != 'web' or urlsplit(recipe['source']).hostname not in {urlsplit(source['url']).hostname, *source.get('aliases', [])}:
        raise ValueError('El enlace no pertenece a la fuente seleccionada.')
    if not recipe['photos']:
        raise ValueError('Esta receta no tiene foto; no se incorpora al catálogo.')
    if not any(re.search(r'[0-9½¼¾⅓⅔⅛⅜⅝⅞]|al gusto|a gusto|cantidad necesaria', x, re.I) for x in recipe['ingredients']):
        raise ValueError('La fuente no indica cantidades. Consulta el original y completa una receta propia antes de guardarla.')
    recipe['origin'] = {'provider': provider, 'id': recipe['source'], 'url': recipe['source'],
                        'attribution': source['name'], 'license': source.get('license') or 'Derechos del editor · consulta e importación individual',
                        'license_url': source.get('license_url') or source['url'], 'language': recipe.get('language') or source.get('language_code', 'es')}
    recipe['tags'] = [source['country']]
    return recipe
