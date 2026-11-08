"""Licensed catalogues: only text and image URL metadata, never image bodies."""
import json
import re
import unicodedata
from urllib.parse import urlencode, urlsplit, unquote, parse_qs
from .fetcher import fetch_page
from .html_dom import DOM

EDITIONS = {'es': ('Artes culinarias/Recetas/', 0), 'en': ('Cookbook:', 102),
            'fr': ('Livre de cuisine/', 0), 'it': ('Libro di cucina/Ricette/', 0),
            'pt': ('Livro de receitas/', 0), 'de': ('Kochbuch/', 0)}

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
    dom = DOM(); dom.feed(page['text'])
    ingredients,steps=[],[]; section=''
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
        if re.match(r'^(pour|para|per|fur)\s+(\d+|six)\s+(personnes|personas|persone|personen)',normal(text)):continue
        heading=normal(text)
        if node.tag.startswith('h') or node.tag=='p' and len(text)<80 and text.endswith(':'):
            if re.search(r'ingredientes|ingredients|ingredienti|zutaten',heading): section='ingredients'
            elif re.search(r'preparation|preparacion|preparazione|preparo|confeccao|zubereitung|elaboracion|procedimiento|instructions|directions|method',heading): section='steps'
            elif node.tag in {'h1','h2'}: section=''
        elif section=='ingredients' and len(ingredients)<200: ingredients.append(text[:10000])
        elif section=='steps' and len(steps)<200: steps.append(text[:10000])
    gallery=list(photos(language,['File:'+n if ':' not in n else n for n in page.get('images',[])]).values())
    if not ingredients or not steps or not gallery or not any(re.search(r'\d|[½¼¾⅓⅔]',x) for x in ingredients):
        raise ValueError('La página no contiene una receta completa con cantidades y fotos libres.')
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
