"""On-demand publisher consultation. No bulk ingestion or persistent remote copies."""
import json
import re
from pathlib import Path
from urllib.parse import urlsplit, urljoin, urlencode

from .fetcher import fetch_page
from .html_dom import DOM
from .importer import image_url, excluded, extract_recipe

SOURCES = {row['id']: row for row in json.loads(Path(__file__).with_name('sources.json').read_text(encoding='utf-8'))}


def publisher_catalog(provider, query='', cursor=None):
    query = query.strip()
    source = SOURCES.get(provider)
    if source and provider=='es-encantar':
        from .encantar import catalog
        return catalog(query,cursor)
    if source and source['mode']=='asset':
        from .licensed_collections import catalog
        return catalog(provider,query,cursor)
    if source and provider=='es-creativegan':
        from .creativegan import catalog
        return catalog(query,cursor)
    if source and source['mode']=='book':
        raise ValueError('Catálogo pendiente de autorización del editor. Puedes consultar el sitio original.')
    if source and provider=='delokos-es':
        from .wordpress_catalog import catalog
        return catalog(query,cursor)
    if source and provider.startswith('wiki-'):
        from .open_catalogs import wiki_catalog
        return wiki_catalog(source,query,cursor)
    if not source or source['mode'] != 'web':
        raise ValueError('Fuente web desconocida.')
    if provider=='open-based' and not query.startswith('https://'):
        from .open_catalogs import based_catalog
        return based_catalog(query,cursor)
    if provider == 'mx-kiwilimon' and not query.startswith('https://'):
        from .publisher_adapters import kiwilimon_search
        page = int(cursor or '1')
        if page < 1 or page > 10000:
            raise ValueError('Página incorrecta.')
        return kiwilimon_search(query, page)
    petitchef_initial = provider == 'es-petitchef' and not query
    offset = 0
    if petitchef_initial:
        try:
            offset = int(cursor or '0')
        except (ValueError, TypeError) as error:
            raise ValueError('Página incorrecta.') from error
        if str(offset) != str(cursor or '0') or offset not in (0, 50):
            raise ValueError('Página incorrecta.')
    elif cursor is not None:
        raise ValueError('Esta fuente no ofrece paginación desde Mesa; consulta el sitio original.')
    # A pasted recipe URL goes straight to its metadata, within the selected publisher.
    if petitchef_initial:
        target = 'https://www.petitchef.es/las-ultimas-recetas'
    elif query.startswith('https://'):
        if urlsplit(query).hostname not in {urlsplit(source['url']).hostname, *source.get('aliases',[])}:
            raise ValueError('El enlace pertenece a otra fuente. Selecciona su catálogo.')
        target = query
    elif query.strip():
        target = (urljoin(source['url'], '/index.php') + '?' + urlencode({'obj':'feed', 'action':'list', 'q':query})) if provider == 'es-petitchef' else source['url'] + ('&' if '?' in source['url'] else '?') + urlencode({'s': query})
    else:
        target = source['url']
    try:
        text, final = fetch_page(target)
    except (ValueError, OSError, TimeoutError):
        if query.startswith('https://') or source['seed'] == source['url']:
            raise
        # A large or blocked landing page need not block an accessible recipe URL.
        target = source['seed']
        text, final = fetch_page(target)
    dom = DOM(); dom.feed(text)
    nodes = list(dom.root.nodes())
    items = {}
    limit = 100 if petitchef_initial else 24
    hosts = {urlsplit(source['url']).hostname, *source.get('aliases', [])}
    for image in nodes:
        if image.tag != 'img' or excluded(image):
            continue
        photo = image_url(image, final)
        if not photo:
            continue
        container = image.parent
        for _ in range(5):
            if container is None:
                break
            candidates = [n for n in container.nodes() if n.tag == 'a' and n.attrs.get('href')]
            for link in candidates:
                url = urljoin(final, link.attrs['href']).split('#')[0]
                parsed = urlsplit(url)
                if parsed.scheme != 'https' or parsed.hostname not in hosts or parsed.query or parsed.path.rstrip('/') == urlsplit(source['url']).path.rstrip('/'):
                    continue
                prefix = urlsplit(source['url']).path.rstrip('/')
                if prefix and not parsed.path.startswith(prefix+'/'):
                    continue
                if provider == 'es-petitchef' and not re.fullmatch(r'/recetas/.+-fid-\d+/?', parsed.path):
                    continue
                if provider == 'es-hogarmania' and not parsed.path.endswith('.html'):
                    continue
                if provider == 'es-bonviveur' and not re.fullmatch(r'/(?:es/)?recetas/[^/]+/?', parsed.path):
                    continue
                required_prefix = {'es-gratis':'/receta-', 'ar-cocineros':'/recetas/',
                                   'mx-nestle':'/recetas/', 'mx-larousse':'/receta/'}.get(provider)
                if required_prefix and not parsed.path.startswith(required_prefix):
                    continue
                if any(x in parsed.path.lower() for x in ('/tag/', '/category/', '/categoria/', '/autor/', '/chef/', '/contact', '/privacy', '/licencia', '/wp-content/')):
                    continue
                title = link.text() or image.attrs.get('alt') or ''
                if len(title) < 8 or len(title) > 250:
                    continue
                if query.strip() and not query.startswith('https://'):
                    import unicodedata
                    norm = lambda x: ''.join(c for c in unicodedata.normalize('NFD', x.lower()) if unicodedata.category(c) != 'Mn')
                    if not all(w in norm(title) for w in norm(query).split()):
                        continue
                items.setdefault(url, {'id': url, 'title': title, 'provider': provider, 'image': photo})
                break
            if len(items) >= limit:
                break
            if candidates and any(x.attrs.get('href') and urljoin(final, x.attrs['href']).split('#')[0] in items for x in candidates):
                break
            container = container.parent
        if len(items) >= limit:
            break
    # Some publishers put the recipe on the landing URL itself.
    if not items and not petitchef_initial:
        if not query.startswith('https://') and final != source['seed']:
            text, final = fetch_page(source['seed'])
        if provider == 'mx-kiwilimon':
            from .publisher_adapters import kiwilimon_recipe
            recipe = kiwilimon_recipe(final,text)
        else:
            recipe = extract_recipe(text, final, language=source.get('language_code','es'))
        if recipe['photos'] and (not query or query.startswith('https://') or query.casefold() in recipe['title'].casefold()):
            items[final] = {'id': final, 'title': recipe['title'], 'provider': provider, 'image': recipe['photos'][0]['url']}
    if petitchef_initial:
        rows = list(items.values())
        page = rows[offset:offset+50]
        return {'items':page, 'cursor':str(offset+len(page)) if offset+len(page)<len(rows) else None,
                'notice':'' if page else 'Petitchef no devolvió recetas con foto. Reintenta o abre el sitio original.'}
    return {'items': list(items.values()), 'cursor': None,
            'notice': 'Se muestra una receta comprobada. Pega un enlace para consultar otra.' if items and final == source['seed'] else '' if items else 'La web no devolvió fichas con foto para esta consulta. Abre la fuente o pega un enlace de receta.'}


def publisher_origin(recipe, provider):
    source = SOURCES.get(provider)
    if not source or source['mode'] != 'web' or urlsplit(recipe['source']).hostname not in {urlsplit(source['url']).hostname, *source.get('aliases', [])}:
        raise ValueError('El enlace no pertenece a la fuente seleccionada.')
    if not recipe['photos']:
        raise ValueError('Esta receta no tiene foto; no se incorpora al catálogo.')
    import re
    if not any(re.search(r'[0-9½¼¾⅓⅔⅛⅜⅝⅞]|al gusto|a gusto|cantidad necesaria',x,re.I) for x in recipe['ingredients']):
        raise ValueError('La fuente no indica cantidades. Consulta el original y completa una receta propia antes de guardarla.')
    recipe['origin'] = {'provider': provider, 'id': recipe['source'], 'url': recipe['source'],
                        'attribution': source['name'], 'license': source.get('license') or 'Derechos del editor · consulta e importación individual',
                        'license_url': source.get('license_url') or source['url'], 'language': recipe.get('language') or source.get('language_code','es')}
    recipe['tags'] = [source['country']]
    return recipe
