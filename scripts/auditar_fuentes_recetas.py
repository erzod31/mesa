"""Read-only, bounded audit of public recipe pages. No photos or full texts saved."""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import sys
from urllib.error import HTTPError
from urllib.parse import urljoin
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from server.importer import Scripts, find, instructions, recipe_photos, extract_recipe

SEEDS = [
    ('alberta-index', 'https://pressbooks.openeducationalberta.ca/proteincookbookforcancerspanish/'),
    ('alberta-panqueques', 'https://pressbooks.openeducationalberta.ca/proteincookbookforcancerspanish/chapter/panqueques-hotcakes-altos-en-proteinas/'),
    ('alberta-shakshuka', 'https://pressbooks.openeducationalberta.ca/proteincookbookforcancerspanish/chapter/shakshuka/'),
    ('alberta-licencia', 'https://pressbooks.openeducationalberta.ca/proteincookbookforcancerspanish/front-matter/informacion/'),
    ('delokos-arroz', 'https://delokos.wordpress.com/2019/12/30/arroz-con-bacalao/'),
    ('delokos-vegetarianas', 'https://delokos.wordpress.com/recetas-publicadas-todas/recetas-vegetarianas/'),
    ('delokos-licencia', 'https://delokos.wordpress.com/no-robes-mi-trabajo/'),
    ('delokos-api', 'https://public-api.wordpress.com/rest/v1.1/sites/delokos.wordpress.com/posts/?number=3'),
    ('delokos-categorias', 'https://public-api.wordpress.com/rest/v1.1/sites/delokos.wordpress.com/categories/?number=10'),
    ('foodhero-enchiladas', 'https://foodhero.org/es/recipes/enchiladas-faciles-con-queso'),
    ('foodhero-granola', 'https://foodhero.org/es/recipes/granola-al-sarten'),
    ('foodhero-cookbook', 'https://foodhero.org/cookbook'),
    ('myplate-maiz', 'https://www.myplate.gov/es/recipes/salteado-de-maiz-y-frijoles'),
    ('bonviveur-tortilla', 'https://www.bonviveur.es/recetas/tortilla-de-betanzos'),
    ('hogarmania-tortilla', 'https://www.hogarmania.com/cocina/recetas/tortilla-de-patatas-al-horno.html'),
    ('directopaladar-tortilla', 'https://www.directoalpaladar.com/recetas-de-huevos-y-tortillas/empezando-en-la-cocina-receta-de-tortilla-de-patatas-con-cebolla'),
    ('recetinas-tortilla', 'https://recetinas.com/tortilla-de-patatas/'),
    ('recetinas-tortitas', 'https://recetinas.com/tortitas-de-patata/'),
    ('petitchef-editorial', 'https://www.petitchef.es/recetas/plato/tortilla-espanola-de-patatas-con-cebolla-fid-1560920'),
    ('petitchef-comunidad', 'https://www.petitchef.es/recetas/plato/tortilla-de-patatas-con-algo-mas-fid-799118'),
    ('recetasgratis-lentejas', 'https://www.recetasgratis.net/receta-de-lentejas-con-arroz-y-tomate-59773.html'),
    ('colombian-arepas', 'https://www.mycolombianrecipes.com/es/arepas-rellenas-de-queso/'),
    ('rechupete-tortilla', 'https://www.recetasderechupete.com/tortilla-de-patatas-espanola-receta-paso-a-paso/5182/'),
    ('nestle-tortilla', 'https://www.nestlecocina.es/receta/tortilla-de-patatas-con-cebolla'),
    ('delokos-raxo', 'https://delokos.wordpress.com/2026/10/05/raxo-en-freidora-de-aire/'),
    ('delokos-caponata', 'https://delokos.wordpress.com/2026/09/07/caponata/'),
    ('delokos-categorias-completas', 'https://public-api.wordpress.com/rest/v1.1/sites/delokos.wordpress.com/categories/?number=100'),
    ('foodhero-media', 'https://foodhero.org/es/media-center'),
    ('canarias-tollos', 'https://ashley4181recetasycosascanarias.blogspot.com/2026/02/tollos-asados.html'),
    ('hf-abuela-config', 'https://datasets-server.huggingface.co/splits?dataset=somosnlp%2FRecetasDeLaAbuela'),
    ('hf-abuela-version1', 'https://datasets-server.huggingface.co/rows?dataset=somosnlp%2FRecetasDeLaAbuela&config=version_1&split=train&offset=0&length=3'),
    ('hf-abuela-inicial', 'https://datasets-server.huggingface.co/rows?dataset=somosnlp%2FRecetasDeLaAbuela&config=version_inicial&split=train&offset=0&length=3'),
    ('hf-recetas-cocina', 'https://datasets-server.huggingface.co/rows?dataset=somosnlp%2Frecetas-cocina&config=default&split=train&offset=0&length=5'),
    ('hf-abuela', 'https://datasets-server.huggingface.co/rows?dataset=somosnlp%2FRecetasDeLaAbuela&config=default&split=train&offset=0&length=5'),
]

class Page(HTMLParser):
    def __init__(self):
        super().__init__(); self.images=[]; self.links=[]; self.title=[]; self.in_title=False; self.meta={}
    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == 'title': self.in_title=True
        if tag == 'img':
            self.images.append({'url': a.get('data-src') or a.get('data-original') or a.get('src') or '', 'alt': (a.get('alt') or '')[:130]})
        if tag == 'a' and a.get('href'): self.links.append(a['href'])
        if tag == 'meta': self.meta[a.get('property') or a.get('name', '')] = a.get('content', '')
    def handle_data(self, data):
        if self.in_title: self.title.append(data)
    def handle_endtag(self, tag):
        if tag == 'title': self.in_title=False

def fetch(url):
    req = Request(url, headers={'User-Agent': 'Mesa-Source-Research/1.0 (public read-only sample audit)', 'Accept': 'text/html,application/json'})
    with urlopen(req, timeout=25) as response:
        raw = response.read(2_000_001)
        return raw, response.geturl(), response.status, response.headers.get_content_type(), response.headers.get_content_charset() or 'utf-8'

def audit(seed):
    key, url = seed
    result={'id': key, 'requested_url': url}
    try:
        raw, final, status, mime, encoding = fetch(url)
        result.update(status=status, final_url=final, bytes_sampled=len(raw), truncated=len(raw)>2_000_000, content_type=mime)
        if result['truncated']: return result
        text=raw.decode(encoding, errors='replace')
        if mime == 'application/json' or text.lstrip().startswith('{'):
            data=json.loads(text)
            result['keys']=list(data)
            result['total']=data.get('found', data.get('num_rows_total'))
            result['features']=[x.get('name') for x in data.get('features', [])]
            if 'posts' in data:
                result['posts']=[{'id':p.get('ID'), 'title':p.get('title'), 'url':p.get('URL'), 'featured_image':p.get('featured_image'), 'attachment_count':len(p.get('attachments',{})), 'categories':list(p.get('categories',{}))} for p in data['posts']]
            if 'categories' in data:
                result['categories']=[{'name':c.get('name'), 'count':c.get('post_count')} for c in data['categories']]
            if 'rows' in data:
                result['sample_rows']=len(data['rows'])
                result['sample_source_urls']=[r['row'].get('url') or r['row'].get('URL') for r in data['rows'] if r['row'].get('url') or r['row'].get('URL')]
            return result
        page=Page(); page.feed(text)
        scripts=Scripts(); scripts.feed(text)
        recipe=None
        for part in scripts.parts:
            try: recipe=find(json.loads(part))
            except (ValueError, RecursionError): continue
            if recipe: break
        result.update(title=''.join(page.title).strip(), jsonld_blocks=len(scripts.parts), recipe_jsonld=bool(recipe), html_image_elements=len(page.images), open_graph_image=page.meta.get('og:image'))
        result['licence_urls']=list(dict.fromkeys(urljoin(final,x) for x in page.links if 'creativecommons.org/licenses' in x))
        result['policy_links']=list(dict.fromkeys(urljoin(final,x) for x in page.links if re.search(r'legal|privac|copyright|media-center|contact|terms|licenc', x, re.I)))[:25]
        result['chapter_urls']=list(dict.fromkeys(urljoin(final,x) for x in page.links if '/chapter/' in x))
        result['image_candidates']=[{'url':urljoin(final,x['url']), 'alt':x['alt']} for x in page.images if x['url'].startswith(('http', '/', '//')) and not re.search(r'logo|icon|avatar|gravatar|badge|banner|pixel|flag', x['url']+' '+x['alt'], re.I)][:24]
        if recipe:
            ingredients=recipe.get('recipeIngredient', [])
            if isinstance(ingredients, str): ingredients=ingredients.splitlines()
            authors=recipe.get('author', [])
            if not isinstance(authors,list): authors=[authors]
            authors=[{'name':x.get('name'), 'url':x.get('url') or x.get('@id')} if isinstance(x,dict) else x for x in authors]
            result['recipe']={'name':recipe.get('name'), 'ingredient_count':len(ingredients), 'numeric_quantity_lines':sum(bool(re.search(r'[0-9¼½¾⅓⅔⅛⅜⅝⅞]', str(x))) for x in ingredients), 'ingredient_examples':ingredients[:1], 'steps':len(instructions(recipe.get('recipeInstructions'))), 'yield':recipe.get('recipeYield'), 'total_time':recipe.get('totalTime'), 'author':authors, 'jsonld_photo_count':len(recipe_photos(recipe,final)), 'photo_urls':[p['url'] for p in recipe_photos(recipe,final)]}
            extracted=extract_recipe(text,final)
            result['mesa_parser']={'ingredients':len(extracted['ingredients']), 'steps':len(extracted['steps']), 'servings':extracted['servings'], 'minutes':extracted['minutes'], 'photo_count':len(extracted['photos'])}
        result['current_500kb_limit_exceeded']=len(raw)>500_000
        if key == 'delokos-vegetarianas':
            result['dated_post_links']=len(set(x for x in page.links if re.search(r'/\d{4}/\d{2}/\d{2}/',x)))
    except HTTPError as e: result.update(status=e.code, error=str(e))
    except Exception as e: result['error']=str(e)
    return result

if __name__ == '__main__':
    dest=ROOT/'output'/'fuentes-recetas-auditoria-2026-10-11.json'
    selected = set(sys.argv[1:])
    if selected and dest.exists():
        results = json.loads(dest.read_text(encoding='utf-8'))['pages']
        results = [x for x in results if x['id'] not in selected]
        seeds = [x for x in SEEDS if x[0] in selected]
    else:
        results=[]; seeds=SEEDS
    for x in results:
        if 'recipe' in x:
            authors=x['recipe'].get('author', [])
            if not isinstance(authors,list): authors=[authors]
            x['recipe']['author']=[{'name':a.get('name'), 'url':a.get('url') or a.get('@id')} if isinstance(a,dict) else a for a in authors]
    with ThreadPoolExecutor(max_workers=3) as pool: results.extend(pool.map(audit, seeds))
    dest.write_text(json.dumps({'checked_at':datetime.now(timezone.utc).isoformat(), 'method':'Bounded public GET, no credentials, no photos downloaded, no full recipe text saved. Sample is not a statistical coverage estimate.', 'pages':results}, ensure_ascii=False, indent=2), encoding='utf-8')
    for x in results:
        print(x['id'], x.get('status'), x.get('bytes_sampled'), 'Recipe',x.get('recipe_jsonld'), 'total',x.get('total'), 'qty/ingredients',f"{x.get('recipe',{}).get('numeric_quantity_lines')}/{x.get('recipe',{}).get('ingredient_count')}", 'photos',x.get('recipe',{}).get('jsonld_photo_count'), x.get('error',''))
    print(dest)
