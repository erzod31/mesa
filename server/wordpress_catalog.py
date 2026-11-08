"""Public delokos adapter: post text plus image references only."""
import json
import re
from urllib.parse import urlsplit,urlencode,quote
from .fetcher import fetch_page
from .html_dom import DOM

API='https://public-api.wordpress.com/rest/v1.1/sites/delokos.wordpress.com/posts/'
LICENSE='https://creativecommons.org/licenses/by-nc-sa/2.5/es/'

def parse_post(post):
    source=post.get('URL','')
    if urlsplit(source).hostname!='delokos.wordpress.com': return None
    dom=DOM();dom.feed(post.get('content',''))
    ingredients=[];steps=[];notes=[];section='';servings=None
    for node in dom.root.nodes():
        if node.tag not in {'p','li','h1','h2','h3','h4','h5','h6'}:continue
        if node.tag=='li' and any(n.tag=='li' for n in list(node.nodes())[1:]):continue
        if node.tag=='p' and node.parent and node.parent.tag=='li':continue
        text=node.text()
        if not text:continue
        if re.match(r'^ingredientes\b',text,re.I):
            section='ingredients';match=re.search(r'para\s+(\d+)\s+(?:personas|raciones|porciones)',text,re.I)
            servings=int(match[1]) if match else None;continue
        if re.match(r'^preparaci[oó]n\b|^elaboraci[oó]n\b',text,re.I):section='steps';continue
        if re.fullmatch(r'o{2,}O{2,}o{2,}',text):section='notes';continue
        if section=='ingredients' and ingredients and node.tag!='li':section='steps'
        if section=='ingredients':
            ingredients.extend(re.split(r'\s+[–—-]\s+',text))
            if node.tag!='li':section='steps'
        elif section=='steps':steps.append(text)
        else:notes.append(text)
    images={}
    for node in dom.root.nodes():
        if node.tag!='img':continue
        raw=node.attrs.get('data-orig-file') or node.attrs.get('src','');parsed=urlsplit(raw)
        if parsed.scheme!='https' or parsed.hostname not in {'delokos.files.wordpress.com','delokos.wordpress.com','i0.wp.com','i1.wp.com','i2.wp.com'}:continue
        if not re.search(r'/(?:wp-content/uploads/)?\d{4}/\d{2}/',parsed.path):continue
        url=raw.split('?')[0]
        images[url]={'url':url,'source':source,'caption':node.attrs.get('alt',''),'artist':'Eugenio García González · La cocina delokos','license':'CC BY-NC-SA 2.5 ES','license_url':LICENSE,'image':''}
    if not ingredients or not steps or not images or not any(re.search(r'\d|[½¼¾]',v) for v in ingredients):return None
    title=DOM();title.feed(post.get('title','Receta'))
    return {'title':title.root.text()[:250],'ingredients':ingredients[:500],'steps':steps[:500],'servings':servings or 1,
            'servings_declared':servings is not None,'minutes':0,'language':'es','yield_unit':'raciones','tags':[],
            'image':'','photos':list(images.values()),'source':source,'notes':'Uso no comercial; conserva los créditos.\n\n'+'\n\n'.join(notes),
            'origin':{'provider':'delokos-es','id':str(post['ID']),'url':source,'language':'es','attribution':'Eugenio García González · La cocina delokos','license':'CC BY-NC-SA 2.5 ES','license_url':LICENSE}}

def import_recipe(url):
    parsed=urlsplit(url)
    if parsed.scheme!='https' or parsed.hostname!='delokos.wordpress.com':raise ValueError('El enlace no pertenece a delokos.')
    slug=parsed.path.strip('/').split('/')[-1]
    if not re.fullmatch(r'[\w%_-]+',slug):raise ValueError('El enlace de receta no es válido.')
    body,_=fetch_page(API+'slug:'+quote(slug,safe=''))
    result=parse_post(json.loads(body))
    if not result:raise ValueError('La publicación no contiene una receta completa con foto y cantidades.')
    return result

def catalog(query='',cursor=None):
    page=int(cursor or 1)
    if not 1<=page<=10000:raise ValueError('Página incorrecta.')
    body,_=fetch_page(API+'?'+urlencode({'number':16,'page':page,'search':query,'order':'DESC','type':'post'}))
    data=json.loads(body);recipes=[r for post in data.get('posts',[]) if (r:=parse_post(post))]
    return {'items':[{'id':r['origin']['id'],'title':r['title'],'provider':'delokos-es','image':r['photos'][0]['url']} for r in recipes],
            'cursor':str(page+1) if page*16<data.get('found',0) else None,'notice':''}
