"""Licensed catalogues: only text and image URL metadata, never image bodies."""
import json
import re
import unicodedata
from functools import lru_cache
from urllib.parse import urlencode, urlsplit, unquote, parse_qs, quote
from .fetcher import fetch_page
from .html_dom import DOM

EDITIONS = {'es': ('Artes culinarias/Recetas/', 0), 'en': ('Cookbook:', 102),
            'fr': ('Livre de cuisine/', 0), 'it': ('Libro di cucina/Ricette/', 0),
            'pt': ('Livro de receitas/', 0), 'de': ('Kochbuch/', 0),
            'ca': ('Llibre de cuina/Receptes/', 0), 'nl': ('Kookboek/', 0),
            'pl': ('Książka kucharska/', 0), 'ja': ('料理本/', 0), 'zh': ('食谱/', 0),
            'fi': ('Keittokirja/', 0), 'sv': ('Kokboken/Recept/', 0)}

def wiki(language, **params):
    if language not in EDITIONS:
        raise ValueError('Edición desconocida.')
    body, _ = fetch_page(f'https://{language}.wikibooks.org/w/api.php?' + urlencode(
        {'format':'json','formatversion':2, **params}))
    data = json.loads(body)
    if 'error' in data:
        raise ValueError('Wikilibros no pudo completar la consulta.')
    return data

def clean(text):
    dom = DOM(); dom.feed(str(text)); return dom.root.text()

def freely_licensed(license_name, license_url):
    name = license_name.lower().strip()
    host = urlsplit(license_url).hostname
    return (name in {'public domain','cc0','cc0 1.0','pd','dominio público'} or
            name.startswith(('cc by ', 'cc by-sa ')) and host in {'creativecommons.org','www.creativecommons.org'})

def photo_metadata(info):
    url = info.get('thumburl') or info.get('url','')
    if urlsplit(url).scheme != 'https' or urlsplit(url).hostname not in {'upload.wikimedia.org','thumb.wikimedia.org'}:
        return None
    meta = info.get('extmetadata',{})
    field = lambda key: clean(meta.get(key,{}).get('value',''))[:10000]
    license_name, license_url = field('LicenseShortName'), field('LicenseUrl')
    if not freely_licensed(license_name,license_url):
        return None
    return {'url':url,'source':info.get('descriptionurl',''),'caption':field('ImageDescription'),
            'artist':field('Artist') or field('Credit'),'license':license_name,'license_url':license_url,'image':''}

def photo_names(names):
    return list(dict.fromkeys(n for n in names if re.search(r'\.(?:jpe?g|png|webp)$',n,re.I)
        and not re.search(r'noia|xclock|flag|logo|icon|wikibooks|wikimedia|ambox|commons-logo|question',n,re.I)))[:80]

def photos(language,names):
    names = photo_names(names); result = {}
    for offset in range(0,len(names),20):
        pages = wiki(language,action='query',prop='imageinfo',titles='|'.join(names[offset:offset+20]),
                     iiprop='url|extmetadata',iiurlwidth=1000)['query']['pages']
        for page in pages:
            for info in page.get('imageinfo',[]):
                photo = photo_metadata(info)
                if photo: result[page['title']] = photo
    return result

def wiki_catalog(source,query='',cursor=None):
    language = source['id'][5:]; prefix,namespace = EDITIONS[language]
    params = {'action':'query','list':'search' if query else 'allpages'}
    if query:
        params.update(srsearch=f'prefix:{prefix} {query}',srnamespace=namespace,srlimit=24)
        if cursor: params['sroffset']=int(cursor)
        key, continuation = 'search','sroffset'
    else:
        params.update(apnamespace=namespace,apprefix='' if language=='en' else prefix,aplimit=24,apfilterredir='nonredirects')
        if cursor: params['apcontinue']=cursor
        key, continuation = 'allpages','apcontinue'
    for _ in range(6):
        data = wiki(language,**params)
        titles = [p['title'] for p in data['query'][key] if p['title'].startswith(prefix)]
        metadata = wiki(language,action='query',prop='images',titles='|'.join(titles),imlimit=100) if titles else {'query':{'pages':[]}}
        pages = metadata['query']['pages']
        licensed = photos(language,[i['title'] for p in pages for i in p.get('images',[])])
        items = []
        for page in pages:
            cover = next((licensed[i['title']] for i in page.get('images',[]) if i['title'] in licensed),None)
            if cover:
                items.append({'id':page['title'],'title':page['title'][len(prefix):].strip(),
                              'provider':source['id'],'image':cover['url']})
        more = data.get('continue',{}).get(continuation)
        if items or more is None:
            return {'items':items,'cursor':str(more) if more is not None else None,
                    'notice':'Textos libres; fotos con licencia comprobada. Busca en el idioma de la fuente.'}
        params[continuation]=more
    return {'items':[],'cursor':str(more),'notice':'No hay fotos libres en este tramo. Continúa con la siguiente página.'}

def parse_recipe_sections(text, ingredient_terms, step_terms):
    dom = DOM(); dom.feed(str(text))
    ingredients, steps = [], []; section=''
    normal = lambda value: ''.join(c for c in unicodedata.normalize('NFD',value.lower()) if unicodedata.category(c)!='Mn')
    for node in dom.root.nodes():
        if node.tag not in {'h1','h2','h3','h4','p','li'}: continue
        ancestor=node; skip=False
        while ancestor:
            if any(ancestor.has(c) for c in ('mw-editsection','noprint')) or section=='ingredients' and (ancestor.has('gallery') or ancestor.has('thumb') or ancestor.tag=='figure'):skip=True;break
            ancestor=ancestor.parent
        if skip:continue
        if node.tag=='li' and any(n.tag=='li' for n in list(node.nodes())[1:]): continue
        if node.tag=='p' and node.parent and node.parent.tag=='li': continue
        text=node.text()
        if not text: continue
        if re.match(r'^(pour|para|per|fur|für|dla)\s+(\d+|six)\s+(personnes|personas|persone|personen|osob)',normal(text)):continue
        heading=normal(text)
        if node.tag.startswith('h') or node.tag=='p' and len(text)<80 and text.endswith(':'):
            if re.search(ingredient_terms,heading): section='ingredients'
            elif re.search(step_terms,heading): section='steps'
            elif node.tag in {'h1','h2'}: section=''
        elif section=='ingredients' and len(ingredients)<200: ingredients.append(text[:10000])
        elif section=='steps' and len(steps)<200: steps.append(text[:10000])
    return ingredients, steps


def wiki_recipe(source,url_or_title):
    language = source['id'][5:]; prefix,_ = EDITIONS[language]
    title = url_or_title
    revision = None
    if title.startswith('https://'):
        parsed = urlsplit(title)
        if parsed.hostname != f'{language}.wikibooks.org': raise ValueError('El enlace pertenece a otra edición.')
        query = parse_qs(parsed.query)
        title = query.get('title',[unquote(parsed.path.removeprefix('/wiki/')).replace('_',' ')])[0]
        revision = query.get('oldid',[None])[0]
    if not title.startswith(prefix): raise ValueError('El enlace no pertenece al recetario.')
    params = {'action':'parse','prop':'text|images|revid','page':title}
    if revision:
        params.pop('page'); params['oldid']=int(revision)
    page = wiki(language,**params)['parse']
    ingredients, steps = parse_recipe_sections(
        page['text'],
        r'ingredients|ingredienti|ingrediënten|ingrediens|zutaten|składniki|材料|用料|食材|ainekset|aineksia|raaka-aineet',
        r'preparacio|preparation|preparacion|preparazione|preparo|confeccao|zubereitung|elaboracion|procedimiento|instructions|directions|method|bereiding|przygotowanie|wykonanie|作り方|制作方法|做法|步骤|步驟|valmistus|ohje|tillagning')
    gallery=list(photos(language,['File:'+n if ':' not in n else n for n in page.get('images',[])]).values())
    if not ingredients or not steps or not gallery or not any(re.search(r'\d|[½¼¾⅓⅔]',x) for x in ingredients):
        raise ValueError('La página no contiene una receta completa con cantidades y fotos libres.')
    dom = DOM(); dom.feed(page['text'])
    normal = lambda value: ''.join(c for c in unicodedata.normalize('NFD',value.lower()) if unicodedata.category(c)!='Mn')
    declared=re.search(r'(?:pour|para|per|fur)\s+(\d+|six)\s+(?:personnes|personas|persone|personen)',normal(dom.root.text()))
    servings=(6 if declared[1]=='six' else int(declared[1])) if declared else 1
    url=f'https://{language}.wikibooks.org/w/index.php?'+urlencode({'title':page['title'],'oldid':page['revid']})
    return {'title':page['title'][len(prefix):].strip()[:250],'ingredients':ingredients,'steps':steps,
            'servings':servings,'servings_declared':declared is not None,'yield_unit':'raciones','minutes':0,'language':language,
            'photos':gallery,'image':'','source':url,'notes':'Comprueba el rendimiento y el tiempo en la fuente.','notes_language':'es',
            'tags':[],'origin':{'provider':source['id'],'id':page['title'],'url':url,'language':language,
            'attribution':source['name']+' · colaboradores, revisión '+str(page['revid']),
            'license':'CC BY-SA 4.0','license_url':'https://creativecommons.org/licenses/by-sa/4.0/deed.es'}}

def based_catalog(query='',cursor=None):
    offset=int(cursor or 0)
    if not 0<=offset<=10000: raise ValueError('Página incorrecta.')
    body,_=fetch_page('https://based.cooking/')
    tree,_=fetch_page('https://api.github.com/repos/LukeSmithxyz/based.cooking/git/trees/master?recursive=1')
    tree=json.loads(tree)
    if tree.get('truncated'): raise ValueError('El índice de fotos está incompleto.')
    files={'/'+p['path'].removeprefix('static/') for p in tree['tree'] if p['path'].startswith('static/pix/')}
    dom=DOM();dom.feed(body);items={}
    for link in dom.root.nodes():
        url=link.attrs.get('href','');slug=urlsplit(url).path.strip('/')
        if link.tag!='a' or urlsplit(url).hostname!='based.cooking' or not re.fullmatch(r'[a-z0-9-]+',slug): continue
        if query and not all(w in link.text().lower() for w in query.lower().split()): continue
        cover=next((f'/pix/{slug}.{ext}' for ext in ('webp','jpg','png','jpeg') if f'/pix/{slug}.{ext}' in files),None)
        if cover: items[url]={'id':url,'title':link.text(),'provider':'open-based','image':'https://based.cooking'+cover}
    rows=list(items.values())
    return {'items':rows[offset:offset+24],'cursor':str(offset+24) if offset+24<len(rows) else None,
            'notice':'Textos y fotos de dominio público. Busca en inglés.'}


MEALDB_API = 'https://www.themealdb.com/api/json/v1/1'
COCKTAILDB_API = 'https://www.thecocktaildb.com/api/json/v1/1'
MEALDB_LETTERS = 'abcdefghijklmnopqrstuvwxyz'
MEALDB_SOURCES = {
    'open-mealdb': {'api': MEALDB_API, 'key': 'meals', 'id': 'idMeal', 'name': 'strMeal',
                    'thumb': 'strMealThumb', 'host': 'www.themealdb.com', 'kind': 'receta', 'site': 'TheMealDB',
                    'browse': 'Catálogo internacional en inglés; se traduce al español al abrir la receta.'},
    'open-cocktaildb': {'api': COCKTAILDB_API, 'key': 'drinks', 'id': 'idDrink', 'name': 'strDrink',
                        'thumb': 'strDrinkThumb', 'host': 'www.thecocktaildb.com', 'kind': 'cóctel', 'site': 'TheCocktailDB',
                        'browse': 'Catálogo de cócteles en inglés; se traduce al español al abrir la receta.'},
}


def _db_config(source_id):
    config = MEALDB_SOURCES.get(source_id)
    if not config:
        raise ValueError('Fuente desconocida.')
    return config


def _db_meals(config, page):
    return (json.loads(page) or {}).get(config['key']) or []


def mealdb_catalog(source_id, query='', cursor=None):
    config = _db_config(source_id)
    query = query.strip()
    if query.startswith('https://'):
        raise ValueError(f'Pega el enlace de una {config["kind"]} concreta para consultarla.')
    if query:
        body, _ = fetch_page(config['api'] + '/search.php?' + urlencode({'s': query}))
        meals = _db_meals(config, body)
        items = [{'id': f"{config['api']}/lookup.php?i={m[config['id']]}", 'title': m[config['name']],
                  'provider': source_id, 'image': m[config['thumb']]}
                 for m in meals if m.get(config['thumb'])]
        return {'items': items, 'cursor': None,
                'notice': '' if items else 'No hay resultados con ese nombre en inglés. Prueba otra búsqueda.'}
    if cursor in (None, ''):
        current = 0
    elif cursor in MEALDB_LETTERS:
        current = MEALDB_LETTERS.index(cursor)
    else:
        raise ValueError('Página incorrecta.')
    body, _ = fetch_page(f"{config['api']}/search.php?f={MEALDB_LETTERS[current]}")
    meals = _db_meals(config, body)
    items = [{'id': f"{config['api']}/lookup.php?i={m[config['id']]}", 'title': m[config['name']],
              'provider': source_id, 'image': m[config['thumb']]}
             for m in meals if m.get(config['thumb'])]
    next_cursor = MEALDB_LETTERS[current + 1] if current + 1 < len(MEALDB_LETTERS) else None
    return {'items': items, 'cursor': next_cursor, 'notice': config['browse']}


def mealdb_recipe(url):
    parts = urlsplit(url)
    config = next((c for c in MEALDB_SOURCES.values()
                   if parts.hostname == c['host'] and parts.path == '/api/json/v1/1/lookup.php'), None)
    if not config:
        raise ValueError('Usa el enlace de una receta de esta fuente.')
    recipe_id = parse_qs(parts.query).get('i', [None])[0]
    if not recipe_id or not recipe_id.isdigit():
        raise ValueError(f'Receta de {config["site"]} incorrecta.')
    body, _ = fetch_page(f"{config['api']}/lookup.php?i={recipe_id}")
    meals = _db_meals(config, body)
    if not meals:
        raise ValueError(f'La {config["kind"]} no existe en {config["site"]}.')
    meal = meals[0]
    ingredients = []
    for index in range(1, 21):
        ingredient = (meal.get(f'strIngredient{index}') or '').strip()
        if not ingredient:
            continue
        measure = (meal.get(f'strMeasure{index}') or '').strip()
        ingredients.append(f'{measure} {ingredient}'.strip())
    steps = [line.strip() for line in (meal.get('strInstructions') or '').split('\r\n') if line.strip()]
    if not ingredients or not steps or not meal.get(config['thumb']):
        raise ValueError(f'La {config["kind"]} no está completa en {config["site"]}.')
    return {'title': (meal.get(config['name']) or '').strip(),
            'language': 'en',
            'ingredients': ingredients,
            'steps': steps,
            'tags': ['Internacional'],
            'servings': 1 if config['key'] == 'drinks' else 4,
            'servings_declared': False,
            'minutes': 0,
            'notes': '',
            'source': url,
            'image': '',
            'photos': [{'url': meal[config['thumb']], 'source': url, 'caption': '', 'artist': '',
                        'license': '', 'license_url': '', 'image': ''}],
            'origin': {'provider': next(k for k, c in MEALDB_SOURCES.items() if c is config), 'id': recipe_id, 'url': url,
                       'language': 'en', 'attribution': config['site'],
                       'license': 'Gratuita · atribución requerida',
                       'license_url': 'https://www.themealdb.com/api.php'}}




GITHUB_SOURCES = {
    'open-chowdown': {'repo': 'clarklab/chowdown', 'branch': 'gh-pages', 'dir': '_recipes/',
                      'site': 'Chowdown', 'format': 'chowdown',
                      'license': 'Unlicense · dominio público', 'license_url': 'https://github.com/clarklab/chowdown/blob/gh-pages/LICENSE',
                      'notice': 'Colección de código abierto en inglés; recetas con foto y cantidades.'},
    'open-ugandan': {'repo': 'DesireNabunya/ugandan_local_food-dataset', 'branch': 'main', 'dir': 'Recipes/',
                     'site': 'Ugandan Local Food', 'format': 'ugandan',
                     'license': 'CC BY 4.0', 'license_url': 'https://github.com/DesireNabunya/ugandan_local_food-dataset/blob/main/LICENSE',
                     'notice': 'Recetas ugandesas en inglés con foto y cantidades.'},
}


@lru_cache(maxsize=4)
def _github_tree(repo, branch):
    body, _ = fetch_page(f'https://api.github.com/repos/{repo}/git/trees/{branch}?recursive=1')
    tree = json.loads(body)
    if tree.get('truncated'):
        raise ValueError('El índice de la colección está incompleto.')
    return tuple((p['path'], p.get('type', '')) for p in tree.get('tree', []))


def _github_files(config):
    return sorted(path for path, kind in _github_tree(config['repo'], config['branch'])
                  if kind == 'blob' and path.startswith(config['dir'])
                  and path.split('/')[-1].lower().endswith(('.md', '.json')))


def _normal_key(value):
    return ''.join(c for c in value.lower() if c.isalnum())


def _github_photo(config, path, url, caption=''):
    return {'url': f'https://raw.githubusercontent.com/{config["repo"]}/{config["branch"]}/{quote(path)}',
            'source': url, 'caption': caption, 'artist': '', 'license': '', 'license_url': '', 'image': ''}


def _github_recipe(config, source_id, path):
    url = f'https://raw.githubusercontent.com/{config["repo"]}/{config["branch"]}/{quote(path)}'
    body, _ = fetch_page(url)
    if config['format'] == 'chowdown':
        match = re.match(r'\A---\s*\n(.*?)\n---\s*(?:\n|\Z)', body, re.S)
        if not match:
            raise ValueError('La página no es una receta de Chowdown.')
        fields = {}
        current = None
        for line in match.group(1).splitlines():
            stripped = line.strip()
            head = re.match(r'^([a-z_]+):\s*(.*)$', stripped)
            if head:
                current = head.group(1)
                value = head.group(2).strip().strip('"').strip("'")
                if value:
                    fields[current] = value
            elif stripped.startswith('-') and current:
                fields.setdefault(current, [])
                if isinstance(fields[current], str):
                    fields[current] = [fields[current]] if fields[current] else []
                fields[current].append(stripped[1:].strip())
        title = fields.get('title') or path.split('/')[-1].removesuffix('.md')
        ingredients = list(fields.get('ingredients') or [])
        steps = list(fields.get('directions') or [])
        image = fields.get('image') or ''
        photos = [_github_photo(config, f'images/{image}', url)] if image else []
    else:
        data = json.loads(body)
        name = data.get('name') or {}
        title = name.get('en') or path.split('/')[-1].removesuffix('.json')
        ingredients = []
        groups = data.get('ingredients') or {}
        if isinstance(groups, dict):
            rows = [row for group in groups.values() for row in (group if isinstance(group, list) else [group])]
        elif isinstance(groups, list):
            rows = groups
        else:
            rows = []
        for row in rows:
            if isinstance(row, dict):
                parts = [str(row.get(k)) for k in ('quantity', 'unit', 'name') if row.get(k) is not None]
                ingredients.append(' '.join(parts).strip())
            elif isinstance(row, str):
                ingredients.append(row.strip())
        steps = []
        for row in data.get('steps') or []:
            if isinstance(row, dict) and row.get('instruction'):
                steps.append(str(row['instruction']).strip())
            elif isinstance(row, str):
                steps.append(row.strip())
        stem = _normal_key(title)
        photos = []
        for tree_path, kind in _github_tree(config['repo'], config['branch']):
            if kind != 'blob' or not tree_path.lower().endswith(('.jpg', '.jpeg', '.png', '.webp')):
                continue
            parts = tree_path.split('/')
            if len(parts) >= 3 and _normal_key(parts[-2]) == stem:
                photos.append(_github_photo(config, tree_path, url))
        photos = photos[:20]
    if not ingredients or not steps or not photos or not any(re.search(r'\d|[½¼¾⅓⅔]', x) for x in ingredients):
        raise ValueError('La receta no está completa con cantidades y foto.')
    return {'title': title[:250], 'language': 'en', 'ingredients': ingredients[:200], 'steps': steps[:200],
            'servings': 4, 'servings_declared': False, 'minutes': 0, 'notes': '', 'source': url, 'image': '',
            'photos': photos, 'tags': ['Internacional'],
            'origin': {'provider': source_id, 'id': path, 'url': url, 'language': 'en',
                       'attribution': config['site'] + ' · colaboradores',
                       'license': config['license'], 'license_url': config['license_url']}}


def github_catalog(source_id, query='', cursor=None):
    config = GITHUB_SOURCES[source_id]
    offset = int(cursor or 0)
    if not 0 <= offset <= 10000:
        raise ValueError('Página incorrecta.')
    files = _github_files(config)
    terms = [t for t in query.lower().split() if t]
    page = [f for f in files if not terms or all(t in f.lower() for t in terms)][offset:offset + 24]
    items = []
    for path in page:
        try:
            recipe = _github_recipe(config, source_id, path)
        except (ValueError, json.JSONDecodeError):
            continue
        items.append({'id': f'https://raw.githubusercontent.com/{config["repo"]}/{config["branch"]}/{quote(path)}',
                      'title': recipe['title'], 'provider': source_id, 'image': recipe['photos'][0]['url']})
    more = offset + 24 < len(files)
    return {'items': items, 'cursor': str(offset + 24) if more else None, 'notice': config['notice']}


def github_recipe(source_id, url):
    config = GITHUB_SOURCES.get(source_id)
    if not config:
        raise ValueError('Fuente desconocida.')
    prefix = f'https://raw.githubusercontent.com/{config["repo"]}/{config["branch"]}/'
    if not url.startswith(prefix):
        raise ValueError('El enlace pertenece a otra fuente.')
    path = unquote(url[len(prefix):])
    if not path.startswith(config['dir']) or not path.split('/')[-1].lower().endswith(('.md', '.json')):
        raise ValueError('El enlace no es una receta de esta colección.')
    return _github_recipe(config, source_id, path)

FREEAPI_MEALS = 'https://prod-main-api-704464-00tre1p1erm.compute.instacloud-edge.com/api/v1/public/meals'


def freemeals_catalog(query='', cursor=None):
    if query.strip():
        return {'items': [], 'cursor': None,
                'notice': 'Este catálogo no permite buscar por nombre; navega por sus páginas.'}
    page = int(cursor or 1)
    if not 1 <= page <= 10000:
        raise ValueError('Página incorrecta.')
    body, _ = fetch_page(f'{FREEAPI_MEALS}?page={page}&limit=24')
    data = json.loads(body)
    rows = ((data or {}).get('data') or {}).get('data') or []
    items = [{'id': f'{page}|{m["idMeal"]}', 'title': m['strMeal'], 'provider': 'open-freemeals',
              'image': m['strMealThumb']} for m in rows if m.get('strMealThumb')]
    more = bool(((data or {}).get('data') or {}).get('nextPage'))
    return {'items': items, 'cursor': str(page + 1) if more else None,
            'notice': 'Catálogo internacional en inglés, servido por la API libre FreeAPI; se traduce al español al abrir la receta.'}


def freemeals_recipe(url):
    parts = urlsplit(url)
    page = parts.query and parse_qs(parts.query).get('page', [None])[0]
    meal_id = parts.query and parse_qs(parts.query).get('i', [None])[0]
    if parts.hostname not in ('prod-main-api-704464-00tre1p1erm.compute.instacloud-edge.com', 'freeapi.app') or not meal_id or not meal_id.isdigit():
        raise ValueError('Usa el enlace de una receta de FreeAPI.')
    if not page or not page.isdigit():
        page = '1'
    body, _ = fetch_page(f'{FREEAPI_MEALS}?page={page}&limit=24')
    rows = ((json.loads(body) or {}).get('data') or {}).get('data') or []
    meal = next((m for m in rows if str(m.get('idMeal')) == meal_id), None)
    if not meal:
        raise ValueError('La receta no está en esta página de FreeAPI.')
    ingredients = []
    for index in range(1, 21):
        ingredient = (meal.get(f'strIngredient{index}') or '').strip()
        if not ingredient:
            continue
        measure = (meal.get(f'strMeasure{index}') or '').strip()
        ingredients.append(f'{measure} {ingredient}'.strip())
    steps = [line.strip() for line in (meal.get('strInstructions') or '').split('\r\n') if line.strip()]
    if not ingredients or not steps or not meal.get('strMealThumb'):
        raise ValueError('La receta no está completa en FreeAPI.')
    return {'title': (meal.get('strMeal') or '').strip(), 'language': 'en',
            'ingredients': ingredients, 'steps': steps, 'tags': ['Internacional'],
            'servings': 4, 'servings_declared': False, 'minutes': 0, 'notes': '', 'source': url, 'image': '',
            'photos': [{'url': meal['strMealThumb'], 'source': url, 'caption': '', 'artist': '',
                        'license': '', 'license_url': '', 'image': ''}],
            'origin': {'provider': 'open-freemeals', 'id': meal_id, 'url': url, 'language': 'en',
                       'attribution': 'FreeAPI · TheMealDB', 'license': 'Gratuita · atribución requerida',
                       'license_url': 'https://github.com/hiteshchoudhary/apihub/blob/main/LICENSE'}}
