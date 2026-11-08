"""Recipe-only reading of CreatiVegan's licensed WordPress content."""
import json
import re
from urllib.parse import urlencode, urlsplit
from .fetcher import fetch_page
from .html_dom import DOM, Node
from .importer import image_url, excluded

BASE = 'https://creativegan.net'
LICENSE = 'https://creativecommons.org/licenses/by-nc-sa/3.0/es/'
CATEGORIES = '3,4,5,13,6,7,816,8,958,815,2119,10,11,12,742,14,15,16,817,18'


def lines(node):
    if not isinstance(node, Node):
        return node
    if node.tag == 'br':
        return '\n'
    return ''.join(lines(c) for c in node.children)


def parse_recipe(text, url, title=''):
    target=urlsplit(url)
    if target.scheme!='https' or target.hostname not in {'creativegan.net','www.creativegan.net'} or target.username or target.password or target.port not in (None,443):
        raise ValueError('El enlace no pertenece a CreatiVegan.')
    if '/parmigiana-vegana-de-zaraida/' in url:
        raise ValueError('Receta de una obra de terceros; falta verificar su autorización específica.')
    dom = DOM(); dom.feed(text)
    scope = next((n for n in dom.root.nodes() if n.has('entry-content')), dom.root)
    title = title or next((n.text() for n in dom.root.nodes() if n.tag == 'h1'), '')
    ingredients, steps, photos = [], [], {}
    cards=[n for n in scope.nodes() if n.has('wprm-fallback-recipe')]
    card=next((c for c in cards if any(n.has('wprm-fallback-recipe-name') and n.text().casefold()==title.casefold() for n in c.nodes())), cards[0] if len(cards)==1 else None)
    if card:
        ingredient_block=next((n for n in card.nodes() if n.has('wprm-fallback-recipe-ingredients')),None)
        step_block=next((n for n in card.nodes() if n.has('wprm-fallback-recipe-instructions')),None)
        if ingredient_block and step_block:
            ingredients=[n.text() for n in ingredient_block.nodes() if n.tag in {'li','h4'}]
            steps=[n.text() for n in step_block.nodes() if n.tag=='li']
    structured=bool(ingredients and steps)
    mode = ''; header = ''
    for n in scope.nodes():
        if n.tag == 'img' and not excluded(n):
            photo = image_url(n, url)
            if photo and not any(s in photo.lower() for s in ('pinterest','logo','avatar','pixel','curso_','bizcochos_veganos','poster_','i_can.jpg','cooking_school_text_book')) and not ('/mujaddara/' in url and 'hamburguesa_' in photo):
                photos.setdefault(photo, {'url':photo,'source':url,'caption':n.attrs.get('alt') or title,
                    'artist':'Virginia García · CreatiVegan','license':'CC BY-NC-SA 3.0 ES','license_url':LICENSE})
        if structured:
            continue
        if n.tag not in {'p','li','h2','h3','h4'}:
            continue
        if n.parent and n.parent.tag in {'p','li'}:
            continue
        value = n.text()
        if re.search(r'esta foto es|fusilad|licencias? creative commons|comp[aá]rtelo|publicaciones similares|comentarios|https?://', value, re.I) and mode == 'steps':
            break
        if re.match(r'^ingredientes\b',value,re.I) or ('ingredientes' in value.lower() and re.match(r'^(?:dificultad|tiempo|raciones)\s*:',value,re.I) and len(value)<300):
            header = value; mode = 'ingredients'
            continue
        if re.match(r'^(preparaci[oó]n|instrucciones|elaboraci[oó]n|procedimiento)', value, re.I):
            mode='steps'; continue
        parts = [re.sub(r'^[♥♡•*\s]+','',s).strip() for s in lines(n).split('\n')]
        parts = [s for s in parts if s]
        if mode == 'ingredients':
            if n.tag == 'p' and parts and '♥' not in lines(n) and '♡' not in lines(n) and not re.match(r'^(?:[\d¼½¾⅓⅔⅛]|una?\b)', value, re.I):
                mode = 'steps'
            else:
                ingredients.extend(parts); continue
        if mode == 'steps' and value:
            if n.tag.startswith('h'): break
            steps.extend(parts)
    if not title or not ingredients or not steps or not photos or not any(re.search(r'[0-9¼½¾⅓⅔⅛]',s) for s in ingredients):
        raise ValueError('Esta publicación de CreatiVegan no es una receta completa con cantidades y foto.')
    preferred=next((n.attrs.get('content','') for n in dom.root.nodes() if n.tag=='meta' and n.attrs.get('property')=='og:image'),'')
    if preferred in photos:
        photos={preferred:photos[preferred],**photos}
    portions = re.search(r'(?:raciones|porciones)\s*:?\s*(\d+)',header,re.I)
    minutes = re.search(r'(?:preparaci[oó]n|tiempo)\s*:?\s*(\d+)\s*min',header,re.I)
    return {'title':title[:250], 'ingredients':ingredients[:500], 'steps':steps[:500],
        'servings':int(portions[1]) if portions else 1,'servings_declared':bool(portions),
        'yield_unit':'porciones','yield_original':portions[1] if portions else '',
        'minutes':int(minutes[1]) if minutes else 0,'source':url,'language':'es',
        'tags':['España','Cocina vegetal'],'notes':'Virginia García · CreatiVegan. CC BY-NC-SA 3.0 ES. Se conserva el texto culinario; formato adaptado a Mesa.',
        'photos':list(photos.values()),'origin':{'provider':'es-creativegan','id':url,'url':url,
        'attribution':'Virginia García · CreatiVegan','license':'CC BY-NC-SA 3.0 ES','license_url':LICENSE,'language':'es'}}


def catalog(query='',cursor=None):
    page=int(cursor or '1')
    if page<1 or page>10000:raise ValueError('Página incorrecta.')
    args={'per_page':12,'page':page,'categories':CATEGORIES,'_fields':'id,link,title,content,_links,_embedded','_embed':'wp:featuredmedia','search':query.strip()}
    raw,_=fetch_page(BASE+'/wp-json/wp/v2/posts?'+urlencode(args))
    posts=json.loads(raw)
    if not isinstance(posts,list):raise ValueError('La fuente devolvió un índice incorrecto.')
    items=[]
    for post in posts:
        try:
            title=DOM();title.feed(post['title']['rendered'])
            recipe=parse_recipe(post['content']['rendered'],post['link'],title.root.text())
            embedded=post.get('_embedded',{})
            media=embedded.get('wp:featuredmedia',[]) if isinstance(embedded,dict) else []
            featured=media[0].get('source_url','') if isinstance(media,list) and media and isinstance(media[0],dict) else ''
            if not featured.startswith(('https://creativegan.net/wp-content/uploads/','https://www.creativegan.net/wp-content/uploads/')):featured=''
            items.append({'id':recipe['source'],'title':recipe['title'],'provider':'es-creativegan','image':featured or recipe['photos'][0]['url']})
        except (ValueError,KeyError,TypeError):continue
    return {'items':items,'cursor':str(page+1) if len(posts)==12 else None,
        'notice':'Virginia García · CC BY-NC-SA 3.0 ES. Solo publicaciones con cantidades, preparación y foto.'}
