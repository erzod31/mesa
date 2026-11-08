"""Original recipes/photos under the author's published CC BY-NC 3.0 license."""
import json
import re
from urllib.parse import urlsplit, urlunsplit, urlencode, quote
from .fetcher import fetch_page
from .html_dom import DOM

SITE = 'recetasparaencantar.wordpress.com'
HOSTS = {'recetasparaencantar.com', SITE}
API = f'https://public-api.wordpress.com/rest/v1.1/sites/{SITE}/posts/'
LICENSE = 'https://creativecommons.org/licenses/by-nc/3.0/'


def recipe_url(value):
    p = urlsplit(value)
    if (p.scheme not in {'http', 'https'} or p.hostname not in HOSTS or
            p.username or p.password or p.port or
            not re.fullmatch(r'/\d{4}/\d{2}/\d{2}/[^/]+/', p.path)):
        raise ValueError('El enlace no es una receta de Recetas para encantar.')
    return urlunsplit(('https', 'recetasparaencantar.com', p.path, '', ''))


def parse_post(post):
    try:
        source = recipe_url(post.get('URL', ''))
    except ValueError:
        return None
    dom = DOM(); dom.feed(post.get('content', ''))
    ingredients, steps, photos = [], [], {}
    section = ''; portions = None
    for node in dom.root.nodes():
        if node.tag not in {'h1','h2','h3','h4','p','li'}:
            continue
        parent = node.parent
        nested = False
        while parent:
            if parent.tag == 'li': nested = True; break
            parent = parent.parent
        if nested or (node.tag == 'li' and any(n.tag == 'li' for n in list(node.nodes())[1:])):
            continue
        text = node.text()
        if not text: continue
        if re.match(r'^ingredientes\b', text, re.I):
            section = 'ingredients'
            m = re.search(r'para\s+(\d+)\s+(?:personas|raciones|porciones)', text, re.I)
            portions = int(m[1]) if m else None
        elif re.match(r'^(preparaci[oó]n|elaboraci[oó]n)\b', text, re.I):
            section = 'steps'
        elif node.tag.startswith('h'):
            section = ''
        elif section == 'ingredients' and node.tag == 'li': ingredients.append(text)
        elif section == 'steps' and 'wp-caption-text' not in node.attrs.get('class',''):
            steps.append(text)
    for node in dom.root.nodes():
        if node.tag != 'img': continue
        raw = node.attrs.get('data-orig-file') or node.attrs.get('src','')
        p = urlsplit(raw)
        if (p.scheme != 'https' or p.hostname not in HOSTS | {'recetasparaencantar.files.wordpress.com'} or
                p.username or p.password or p.port or
                not re.search(r'/(?:wp-content/uploads/)?\d{4}/\d{2}/.+\.(?:jpe?g|png|webp)$',p.path,re.I)):
            continue
        url = urlunsplit((p.scheme,p.netloc,p.path,'',''))
        photos[url] = {'url':url,'source':source,'caption':node.attrs.get('alt',''),
            'artist':'Dana Madiana · Recetas para encantar','license':'CC BY-NC 3.0',
            'license_url':LICENSE,'image':''}
    if not ingredients or not steps or not photos or not any(re.search(r'[0-9½¼¾⅓⅔]',s) for s in ingredients):
        return None
    title=DOM(); title.feed(post.get('title',''))
    return {'title':title.root.text()[:250],'ingredients':ingredients[:500],'steps':steps[:500],
        'servings':portions or 1,'servings_declared':portions is not None,'minutes':0,
        'language':'es','yield_unit':'raciones','tags':[],'image':'','photos':list(photos.values()),
        'source':source,'notes':'Uso no comercial. Conserva autoría, licencia y enlace original. '
        'Se mantienen cantidades y pasos originales; confirma el rendimiento antes de escalar.',
        'origin':{'provider':'es-encantar','id':source,'url':source,'language':'es',
            'attribution':'Dana Madiana · Recetas para encantar','license':'CC BY-NC 3.0',
            'license_url':LICENSE,'modified':True}}


def import_recipe(url):
    source = recipe_url(url)
    slug = urlsplit(source).path.strip('/').split('/')[-1]
    body,_ = fetch_page(API+'slug:'+quote(slug,safe=''))
    recipe = parse_post(json.loads(body))
    if not recipe: raise ValueError('La publicación no contiene cantidades, preparación y fotografías propias.')
    return recipe


def catalog(query='',cursor=None):
    page = int(cursor or '1')
    if not 1 <= page <= 10000: raise ValueError('Página incorrecta.')
    body,_ = fetch_page(API+'?'+urlencode({'number':16,'page':page,'search':query.strip(),'type':'post'}))
    data=json.loads(body)
    recipes=[r for post in data.get('posts',[]) if (r:=parse_post(post))]
    return {'items':[{'id':r['source'],'provider':'es-encantar','title':r['title'],
        'image':r['photos'][0]['url']} for r in recipes],
        'cursor':str(page+1) if page*16<data.get('found',0) else None,'notice':''}
