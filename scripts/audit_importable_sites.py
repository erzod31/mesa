"""Bounded research: public pages, robots respected, metadata only, no photo GETs.

This does not alter Mesa's selected sources or download recipe catalogues.
"""
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from hashlib import sha256
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import sys
import time
import zlib
from urllib.error import HTTPError
from urllib.parse import urljoin, urlsplit
from urllib.request import Request, urlopen, build_opener, HTTPRedirectHandler
from urllib.robotparser import RobotFileParser

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from server.fetcher import public_target
from server.importer import Scripts, recipe_entities, extract_recipe, instructions, visible_fields
from server.html_dom import DOM

UA = 'Mesa-Source-Research/1.0 (public read-only sample audit)'
DEST = ROOT / 'output/importable-sites-audit-2026-10-11.json'

EXTRA = [
 ('mx-mely', 'México en mi Cocina', 'es', 'https://www.mexicoenmicocina.com/', ['https://www.mexicoenmicocina.com/receta-de-enchiladas-rojas/']),
 ('ec-laylita', 'Laylita · español', 'es', 'https://www.laylita.com/recetas/', ['https://www.laylita.com/recetas/bolon-de-verde/']),
 ('co-erica', 'My Colombian Recipes · español', 'es', 'https://www.mycolombianrecipes.com/es/', ['https://www.mycolombianrecipes.com/es/arepas-rellenas-de-queso/', 'https://www.mycolombianrecipes.com/es/bandeja-paisa/']),
 ('cl-pilar', 'La cocina chilena de Pilar', 'es', 'https://cocinachilena.cl/', ['https://cocinachilena.cl/PASTEL-DE-CHOCLO-CHILEAN-CORN-PIE/']),
 ('us-foodhero', 'Food Hero · español', 'es', 'https://foodhero.org/es/recipes', ['https://foodhero.org/es/recipes/enchiladas-faciles-con-queso', 'https://foodhero.org/es/recipes/granola-al-sarten']),
 ('us-myplate', 'MyPlate · español', 'es', 'https://www.myplate.gov/es/recipes', ['https://www.myplate.gov/es/recipes/salteado-de-maiz-y-frijoles']),
 ('mx-cocinafacil', 'Cocina Fácil', 'es', 'https://www.cocinafacil.com.mx/', []),
 ('es-anna', 'Anna Recetas Fáciles', 'es', 'https://www.annarecetasfaciles.com/', []),
 ('es-javi', 'Javi Recetas', 'es', 'https://www.javirecetas.com/', ['https://www.javirecetas.com/arroz-con-leche/']),
 ('es-comedera', 'Comedera', 'es', 'https://www.comedera.com/', []),
 ('en-allrecipes', 'Allrecipes', 'en', 'https://www.allrecipes.com/', ['https://www.allrecipes.com/recipe/21014/good-old-fashioned-pancakes/', 'https://www.allrecipes.com/recipe/10813/best-chocolate-chip-cookies/']),
 ('en-simply', 'Simply Recipes', 'en', 'https://www.simplyrecipes.com/', ['https://www.simplyrecipes.com/recipes/banana_bread/', 'https://www.simplyrecipes.com/recipes/lasagna/']),
 ('en-serious', 'Serious Eats', 'en', 'https://www.seriouseats.com/', ['https://www.seriouseats.com/the-best-roast-potatoes-ever-recipe', 'https://www.seriouseats.com/foolproof-pan-pizza-recipe']),
 ('en-recipetin', 'RecipeTin Eats', 'en', 'https://www.recipetineats.com/', ['https://www.recipetineats.com/spaghetti-bolognese/', 'https://www.recipetineats.com/chocolate-cake/']),
 ('en-sally', "Sally’s Baking", 'en', 'https://sallysbakingaddiction.com/', ['https://sallysbakingaddiction.com/best-banana-bread-recipe/', 'https://sallysbakingaddiction.com/chewy-chocolate-chip-cookies/']),
 ('en-budget', 'Budget Bytes', 'en', 'https://www.budgetbytes.com/', ['https://www.budgetbytes.com/one-pot-creamy-pesto-chicken-pasta/', 'https://www.budgetbytes.com/basic-chili/']),
 ('en-kingarthur', 'King Arthur Baking', 'en', 'https://www.kingarthurbaking.com/', ['https://www.kingarthurbaking.com/recipes/classic-sandwich-bread-recipe', 'https://www.kingarthurbaking.com/recipes/chocolate-chip-cookies-recipe']),
 ('en-tasty', 'Tasty', 'en', 'https://tasty.co/', ['https://tasty.co/recipe/one-pot-swedish-meatballs', 'https://tasty.co/recipe/the-best-chewy-chocolate-chip-cookies']),
 ('en-foodnetwork', 'Food Network', 'en', 'https://www.foodnetwork.com/recipes', []),
 ('en-eatingwell', 'EatingWell', 'en', 'https://www.eatingwell.com/', ['https://www.eatingwell.com/gurkensalat-german-cucumber-salad-12016917','https://www.eatingwell.com/strawberry-oatmeal-smoothie-12016909']),
 ('en-food52', 'Food52', 'en', 'https://food52.com/recipes', []),
 ('en-kitchn', 'The Kitchn', 'en', 'https://www.thekitchn.com/recipes', []),
 ('es-cookpad', 'Cookpad · español', 'es', 'https://cookpad.com/es', []),
 ('es-thermomix', 'Recetas para Thermomix', 'es', 'https://recetasparathermomix.com/', []),
 ('es-velocidad', 'Velocidad Cuchara', 'es', 'https://www.velocidadcuchara.com/', ['https://www.velocidadcuchara.com/pudin-de-pan-huevos-leche-y-pasas-con-thermomix/','https://www.velocidadcuchara.com/tarta-de-queso-la-vina-thermomix/']),
 ('es-amimanera', 'A mi manera cocinando', 'es', 'https://amimaneracocinando.com/', []),
 ('mx-directo', 'Directo al Paladar · México', 'es', 'https://www.directoalpaladar.com.mx/', []),
 ('mx-vital', 'Cocina Vital', 'es', 'https://www.cocinavital.mx/recetas/', []),
 ('it-giallo', 'GialloZafferano', 'it', 'https://www.giallozafferano.it/', ['https://ricette.giallozafferano.it/Spaghetti-alla-Carbonara.html','https://ricette.giallozafferano.it/Lasagne-alla-Bolognese.html']),
 ('en-taste', 'Taste of Home', 'en', 'https://www.tasteofhome.com/recipes/', []),
 ('en-bbcfood', 'BBC Food', 'en', 'https://www.bbc.co.uk/food/recipes', []),
]


class Links(HTMLParser):
    def __init__(self):
        super().__init__(); self.links = []; self.lang = ''
    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == 'a' and a.get('href'): self.links.append(a['href'])
        if tag == 'html': self.lang = a.get('lang', '')


def robot_check(url, cache):
    parts = urlsplit(url)
    base = f'{parts.scheme}://{parts.netloc}'
    if base not in cache:
        robot_url = base + '/robots.txt'
        info = {'url': robot_url}
        parser = None
        try:
            req = Request(robot_url, headers={'User-Agent': UA, 'Accept': 'text/plain'})
            with urlopen(req, timeout=10) as response:
                raw = response.read(256001)
                info.update(status=response.status, final_url=response.geturl(), bytes=len(raw))
                if len(raw) > 256000: raise ValueError('robots.txt supera el límite de investigación')
                if response.headers.get_content_type() not in ('text/plain', 'text/html'):
                    raise ValueError('robots.txt no textual')
                parser = RobotFileParser(); parser.parse(raw.decode('utf-8', errors='replace').splitlines())
                info['sha256'] = sha256(raw).hexdigest()
        except HTTPError as e:
            info.update(status=e.code)
            if e.code == 404:
                parser = RobotFileParser(); parser.parse([])
            else: info['error'] = str(e)
        except Exception as e: info['error'] = str(e)
        cache[base] = (parser, info)
    parser, info = cache[base]
    if parser is None:
        return False, dict(info, decision='No se consulta la receta: robots no verificable')
    allowed = parser.can_fetch(UA, url)
    return allowed, dict(info, decision='allowed' if allowed else 'disallowed', crawl_delay=parser.crawl_delay(UA))


def fetch_checked(url, cache):
    allowed, robots = robot_check(url, cache)
    if not allowed: return None, url, {'url': url, 'robots': robots, 'status': 'not_requested'}
    record = {'url': url, 'robots': robots}
    try:
        class GuardedRedirect(HTTPRedirectHandler):
            def redirect_request(self, req, fp, code, msg, headers, newurl):
                public_target(newurl)
                permitted, _ = robot_check(newurl, cache)
                if not permitted:
                    raise ValueError('Redirección no permitida por robots o robots no verificable')
                if urlsplit(newurl).hostname.startswith('tollbit.'):
                    raise ValueError('Redirección a un servicio de acceso/licencia para agentes; no se continúa')
                return super().redirect_request(req, fp, code, msg, headers, newurl)
        public_target(url)
        req = Request(url, headers={'User-Agent':UA, 'Accept':'text/html,application/json', 'Accept-Encoding':'identity'})
        with build_opener(GuardedRedirect()).open(req, timeout=20) as response:
            raw = response.read(4_000_001)
            if len(raw)>4_000_000: raise ValueError('HTML supera 4 MB')
            if response.headers.get_content_type() not in ('text/html','application/json','application/ld+json'):
                raise ValueError('Página no HTML/JSON')
            encoding = response.headers.get('Content-Encoding', 'identity').lower()
            if encoding in ('gzip', 'deflate'):
                decoder = zlib.decompressobj(16+zlib.MAX_WBITS if encoding=='gzip' else zlib.MAX_WBITS)
                raw = decoder.decompress(raw, 4_000_001)
                if len(raw)>4_000_000 or decoder.unconsumed_tail or not decoder.eof:
                    raise ValueError('HTML descomprimido supera 4 MB o es inválido')
            elif encoding != 'identity': raise ValueError('Compresión no compatible: '+encoding)
            page = raw.decode(response.headers.get_content_charset() or 'utf-8', errors='replace')
            final = response.geturl()
        final_allowed, final_robots = robot_check(final, cache)
        record.update(final_url=final, bytes=len(page.encode('utf-8')), sha256=sha256(page.encode('utf-8')).hexdigest(), status=200)
        if final_robots != robots: record['final_robots'] = final_robots
        if not final_allowed:
            record['error'] = 'Destino final no permitido por robots; no se analiza'
            return None, final, record
        return page, final, record
    except Exception as e:
        record.update(status='failed', error=str(e))
        return None, url, record


def candidate_links(page, final, source):
    links = Links(); links.feed(page)
    allowed_hosts = {urlsplit(source['url']).hostname, urlsplit(final).hostname, *source.get('aliases', [])}
    candidates = []
    for href in links.links:
        url = urljoin(final, href).split('#')[0]
        p = urlsplit(url)
        if p.scheme != 'https' or p.hostname not in allowed_hosts or p.query: continue
        path = p.path
        if len(path) < 12 or url.rstrip('/') == final.rstrip('/'): continue
        if re.search(r'(category|categoria|tag/|author|autor|contact|privacy|privacidad|terms|legal|politicas|necesidades/|recetas-publicadas|subscribe|login|search|collection|index|about|quienes|wp-content|wp-admin|\.jpg|\.png|\.webp|\.pdf|/amp/|/video/)', path, re.I): continue
        if source['id']=='ar-paulina' and not re.search(r'/\d+/?$', path): continue
        if source['id']=='mx-kiwilimon' and not path.startswith('/receta/'): continue
        if source['id']=='en-eatingwell' and not re.search(r'/recipe/\d+/', path): continue
        if source['id'] == 'en-foodnetwork' and not path.startswith('/recipes/'): continue
        if source['id'] == 'en-food52' and not re.search(r'/recipes/\d+', path): continue
        if source['id'] == 'es-cookpad' and '/recipes/' not in path: continue
        if source['id'] == 'es-gratis' and 'receta-de-' not in path: continue
        if source['id'] == 'es-petitchef' and '-fid-' not in path: continue
        if source['id'] == 'co-erica' and not path.startswith('/es/'): continue
        if source['id'] == 'ec-laylita' and not path.startswith('/recetas/'): continue
        if source['id'] == 'wiki-es' and '/Artes_culinarias/Recetas/' not in path: continue
        if source['id'] == 'delokos-es' and not re.search(r'/\d{4}/\d{2}/\d{2}/', path): continue
        if source['id'] == 'mx-nestle' and not path.startswith('/recetas/'): continue
        if source['id'] == 'es-hogarmania' and not path.startswith('/cocina/recetas/'): continue
        if source['id'] == 'pe-buenazo' and not path.startswith('/recetas/'): continue
        if source['id'] == 'mx-larousse' and not path.startswith('/receta/'): continue
        if source['id'] == 'ar-cocineros' and not path.startswith('/recetas/'): continue
        if source['id'] == 'es-bonviveur' and not path.startswith('/es/recetas/'): continue
        if source['id'] == 'en-tasty' and not path.startswith('/recipe/'): continue
        if source['id'] == 'en-kingarthur' and not path.startswith('/recipes/'): continue
        if source['id'] == 'us-foodhero' and not path.startswith('/es/recipes/'): continue
        if source['id'] == 'us-myplate' and not path.startswith('/es/recipes/'): continue
        if url not in candidates: candidates.append(url)
    # Prefer obvious recipe pages over navigation and commercial material.
    def score(u):
        path = urlsplit(u).path
        return (bool(re.search(r'recipe|receta|/\d{4}/\d{2}/|tortilla|pollo|chicken|cake|pasta|bread|arroz|patata', path, re.I)), len(path.split('-')))
    return sorted(candidates, key=score, reverse=True)


def analyze(page, url):
    scripts = Scripts(); scripts.feed(page)
    entities = []
    for block in scripts.parts:
        try: entities.extend(recipe_entities(json.loads(block)))
        except (ValueError, RecursionError): pass
    dom = DOM(); dom.feed(page)
    visible_ingredients, visible_steps = visible_fields(dom)
    links = Links(); links.feed(page)
    result = {'recipe_jsonld_entities': len(entities), 'html_language': links.lang,
              'visible_ingredient_rows': len(visible_ingredients), 'visible_step_rows': len(visible_steps),
              'widget': 'wprm' if 'wprm-recipe-ingredient' in page else ('tasty-recipes' if 'tasty-recipes-ingredients' in page else ('foodhero' if 'field_ingredients' in page else 'other')),
              'policy_links': list(dict.fromkeys(urljoin(url, x) for x in links.links if re.search(r'copyright|terms|terminos|términos|legal|licen|permission|media-center|no-robes', x, re.I)))[:12],
              'cc_license_links': list(dict.fromkeys(urljoin(url, x) for x in links.links if 'creativecommons.org/licenses/' in x)),
              'schema': [{'ingredients':len(x.get('recipeIngredient') or []), 'steps':len(instructions(x.get('recipeInstructions')))} for x in entities][:3]}
    try:
        data = extract_recipe(page, url)
        ingredients, steps, photos = data['ingredients'], data['steps'], data['photos']
        result['mesa_server_parser'] = {'ok':True, 'title': data['title'], 'ingredients':len(ingredients), 'steps':len(steps), 'photo_urls':len(photos),
              'ingredient_rows_with_number':sum(bool(re.search(r'[0-9¼½¾⅓⅔⅛⅜⅝⅞]', x)) for x in ingredients),
              'ingredient_rows_without_number':sum(not bool(re.search(r'[0-9¼½¾⅓⅔⅛⅜⅝⅞]', x)) for x in ingredients),
              'ingredient_rows_over_350_chars':sum(len(x)>350 for x in ingredients),
              'yield_declared':data['servings_declared'], 'yield_original':data['yield_original'], 'minutes':data['minutes'],
              'photo_hosts':sorted({urlsplit(p['url']).hostname for p in photos}),
              'photos_with_explicit_license':sum(bool(p.get('license_url')) for p in photos),
              'photo_sample_url':photos[0]['url'] if photos else None,
              'manual_quantity_verification':False}
        result['candidate_complete'] = bool(ingredients and steps and photos and result['mesa_server_parser']['ingredient_rows_with_number'])
    except Exception as e:
        result['mesa_server_parser'] = {'ok':False, 'error':str(e)}
        result['candidate_complete'] = False
    return result


def audit(source):
    result = dict(source, samples=[], discovery=[], checked_at=datetime.now(timezone.utc).isoformat())
    robots = {}
    queue = list(source.get('samples', []))
    if not queue or queue[0].rstrip('/') == source['url'].rstrip('/'):
        page, final, entry = fetch_checked(source['url'], robots)
        result['discovery'].append(entry)
        if page:
            queue = candidate_links(page, final, source)[:2]
        else: queue = []
    attempted = set()
    while queue and len(result['samples']) < 2:
        url = queue.pop(0)
        if url in attempted: continue
        attempted.add(url)
        delay = max(1.0, float(robot_check(url, robots)[1].get('crawl_delay') or 0))
        if delay > 30:
            result['samples'].append({'url':url, 'status':'not_requested', 'error':'Crawl-delay elevado: consulta aplazada'}); continue
        time.sleep(delay)
        page, final, entry = fetch_checked(url, robots)
        if page:
            entry.update(analyze(page, final))
            if len(result['samples']) == 0 and len(queue) < 1:
                queue.extend(x for x in candidate_links(page, final, source) if x not in attempted)
        result['samples'].append(entry)
    result['robots_checks'] = [v[1] for v in robots.values()]
    result['candidate_complete_samples'] = sum(bool(s.get('candidate_complete')) for s in result['samples'])
    result['samples_attempted'] = len(result['samples'])
    return result


def main():
    current = json.loads((ROOT/'server/sources.json').read_text(encoding='utf-8'))
    live = json.loads((ROOT/'output/public-detail-live-results.json').read_text(encoding='utf-8'))
    sources = []
    for s in current:
        seed = live.get(s['id'], {}).get('url') or s.get('seed') or s['url']
        if s['id']=='delokos-es': seed='https://delokos.wordpress.com/2026/10/05/raxo-en-freidora-de-aire/'
        sources.append({'id':s['id'], 'name':s['name'], 'language':'es', 'url':s['url'], 'aliases':s.get('aliases',[]), 'samples':[seed], 'selected_in_mesa':True})
    sources += [{'id':i,'name':n,'language':lang,'url':url,'samples':seeds,'selected_in_mesa':False} for i,n,lang,url,seeds in EXTRA]
    selected = next((x.split('=',1)[1].split(',') for x in sys.argv[1:] if x.startswith('--ids=')), [])
    previous = json.loads(DEST.read_text(encoding='utf-8')) if selected and DEST.exists() else None
    if selected: sources=[s for s in sources if s['id'] in selected]
    audit_data = {'checked_at':datetime.now(timezone.utc).isoformat(), 'method':{
      'limit':'Up to two public recipe pages per site; no catalogue downloads; four different sites at a time.',
      'robots':'Check robots.txt before each candidate; unknown/non-404 failure means skip; no account, cookies, bypass or proxy.',
      'parser':'Current Mesa server.importer.extract_recipe; this is not proof of an Android client adapter.',
      'amounts':'Count numeric tokens only. No inference of missing quantities; manual verification required.',
      'photos':'URLs only; no image bodies downloaded. Number of URLs does not prove all photos, reachability or reproduction rights.',
      'coverage':'A small convenience sample cannot establish catalogue-wide reliability or a traffic ranking.',
      'storage':'Metadata, counts, links and response digests only; no full recipe texts saved.'}, 'sites':[]}
    DEST.parent.mkdir(exist_ok=True)
    with ThreadPoolExecutor(max_workers=4) as pool:
        futures = {pool.submit(audit, s):s for s in sources}
        for future in as_completed(futures):
            try: r=future.result()
            except Exception as e: r=dict(futures[future],error=str(e),samples=[],candidate_complete_samples=0,samples_attempted=0)
            audit_data['sites'].append(r)
            DEST.write_text(json.dumps(audit_data,ensure_ascii=False,indent=2),encoding='utf-8')
            print(json.dumps({'id':r['id'],'samples':r['samples_attempted'],'candidate_complete':r['candidate_complete_samples'],
                              'outcomes':[s.get('mesa_server_parser',{}).get('title') or s.get('error') or s.get('robots',{}).get('decision') for s in r['samples']],
                              'discovery_errors':[x.get('error') or x.get('robots',{}).get('decision') for x in r.get('discovery',[]) if x.get('status')!=200]},ensure_ascii=False),flush=True)
    audit_data['sites'].sort(key=lambda x:next(i for i,s in enumerate(sources) if s['id']==x['id']))
    if previous:
        updated={s['id']:s for s in audit_data['sites']}
        prior_sites=[]
        for s in previous['sites']:
            if s['id'] in updated:
                updated[s['id']]['earlier_probe']={'checked_at':s.get('checked_at'),'samples':s.get('samples',[]),'discovery':s.get('discovery',[])}
                prior_sites.append(updated.pop(s['id']))
            else: prior_sites.append(s)
        audit_data['sites']=prior_sites+list(updated.values())
    audit_data['finished_at']=datetime.now(timezone.utc).isoformat()
    DEST.write_text(json.dumps(audit_data,ensure_ascii=False,indent=2),encoding='utf-8')
    print(f'COMPLETE {len(sources)} sites: {DEST}',flush=True)


if __name__=='__main__': main()
