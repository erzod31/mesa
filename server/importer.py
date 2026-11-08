"""Extract recipe JSON-LD without making any network requests."""
from html import unescape
from html.parser import HTMLParser
import json
import re
from urllib.parse import urljoin,urlsplit
from .html_dom import DOM


class Scripts(HTMLParser):
    def __init__(self):
        super().__init__()
        self.active = False
        self.parts = []
        self.current = []

    def handle_starttag(self, tag, attrs):
        if tag == 'script' and dict(attrs).get('type', '').lower() == 'application/ld+json':
            self.active = True
            self.current = []

    def handle_data(self, data):
        if self.active:
            self.current.append(data)

    def handle_endtag(self, tag):
        if tag == 'script' and self.active:
            self.parts.append(''.join(self.current))
            self.active = False


def clean(text):
    return unescape(re.sub('<[^>]+>', '', str(text))).strip()


def find(value):
    if isinstance(value, dict):
        types = value.get('@type', [])
        if isinstance(types, str):
            types = [types]
        if 'Recipe' in types:
            return value
        for nested in value.values():
            result = find(nested)
            if result:
                return result
    elif isinstance(value, list):
        for nested in value:
            result = find(nested)
            if result:
                return result


def instructions(value):
    if isinstance(value, str):
        return [clean(x) for x in value.split('\n') if clean(x)]
    if isinstance(value, list):
        return [x for item in value for x in instructions(item)]
    if isinstance(value, dict):
        if 'itemListElement' in value:
            return instructions(value['itemListElement'])
        return instructions(value.get('text', ''))
    return []


def recipe_photos(recipe, source):
    photos = {}
    def add(value):
        if isinstance(value, list):
            for item in value: add(item)
        elif isinstance(value, str):
            url = urljoin(source, value)
            target = urlsplit(url)
            if target.scheme in ('http', 'https') and target.hostname and not target.username and not target.password:
                photos.setdefault(url, {'url': url, 'source': source, 'caption': '', 'artist': '', 'license': '', 'license_url': '', 'image': ''})
        elif isinstance(value, dict):
            raw = value.get('contentUrl') or value.get('url')
            if raw:
                add(raw)
                url = urljoin(source, str(raw))
                if url in photos:
                    author = value.get('creator') or value.get('author') or ''
                    if isinstance(author, dict): author = author.get('name', '')
                    if isinstance(author, list): author = ', '.join(str(x.get('name', '') if isinstance(x, dict) else x) for x in author)
                    license = value.get('license', '')
                    if isinstance(license, dict): license = license.get('url', '')
                    photos[url].update(caption=clean(value.get('caption') or value.get('name', ''))[:10000], artist=clean(value.get('creditText') or author)[:10000], license_url=str(license)[:10000])
    add(recipe.get('image', []))
    def steps(value):
        if isinstance(value, list):
            for item in value: steps(item)
        elif isinstance(value, dict):
            add(value.get('image', []))
            steps(value.get('itemListElement', []))
    steps(recipe.get('recipeInstructions', []))
    return list(photos.values())


def recipe_entities(value):
    if isinstance(value, dict):
        types = value.get('@type', [])
        if 'Recipe' in ([types] if isinstance(types, str) else types):
            yield value
        for nested in value.values():
            yield from recipe_entities(nested)
    elif isinstance(value, list):
        for nested in value:
            yield from recipe_entities(nested)


def duration_minutes(value):
    match = re.fullmatch(r'P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?', str(value or ''))
    if not match:
        return 0
    days, hours, minutes, seconds = (int(x or 0) for x in match.groups())
    return min(100000, days * 1440 + hours * 60 + minutes + (seconds + 59) // 60)


def image_url(node, source):
    attrs = node.attrs
    raw = attrs.get('data-lazy-src') or attrs.get('data-src') or attrs.get('src') or ''
    # srcset resolves a real image when lazy loading uses a data placeholder.
    if not raw or raw.startswith('data:'):
        raw = (attrs.get('data-srcset') or attrs.get('srcset') or '').split(',')[-1].strip().split(' ')[0]
    url = urljoin(source, raw)
    target = urlsplit(url)
    if target.scheme not in ('http', 'https') or not target.hostname or target.username or target.password:
        return ''
    if re.search(r'(logo|avatar|gravatar|icon|banner|pixel|emoji|signature)', url, re.I):
        return ''
    for dimension in ('width', 'height'):
        size = str(attrs.get(dimension) or '')
        if size.isdigit() and int(size) < 80:
            return ''
    return url if re.search(r'\.(jpg|jpeg|png|webp)(?:[?/#]|$)', url, re.I) else ''


def excluded(node):
    while node:
        if node.tag in ('body', 'html'):
            return False
        label = (node.attrs.get('class') or '') + ' ' + (node.attrs.get('id') or '')
        if node.tag in ('nav', 'footer', 'aside') or node.has('sidebar') or node.attrs.get('id') in ('sidebar', 'secondary') or re.search(r'(related|relacionad|recommend|recomendad|comment|comentari|author-bio|social|advert|promo)', label, re.I):
            return True
        node = node.parent
    return False


def recipe_scope(dom, source=''):
    nodes=list(dom.root.nodes())
    host=urlsplit(source).hostname or ''
    if host in ('bonviveur.com','www.bonviveur.com'):
        return next((n for n in nodes if n.has('text') and n.parent and n.parent.has('main')),None)
    if host in ('www.recetasgratis.net','recetas.elperiodico.com'):
        return next((n for n in nodes if n.tag=='article' and n.has('columna-post')),None)
    if host=='www.hogarmania.com':
        return next((n for n in nodes if n.tag=='main' and n.has('recipe')),None)
    if host=='based.cooking':
        return next((n for n in nodes if n.tag=='main'),None)
    return next((n for n in nodes if n.has('entry-content') or n.has('article-content') or (n.has('elementor-widget-container') and any(x.tag=='h2' and x.text()=='Ingredientes' for x in n.nodes()))),None)

def visible_fields(dom, source=''):
    nodes = list(dom.root.nodes())
    ingredients = [n.text() for n in nodes if n.has('wprm-recipe-ingredient')]
    steps = [n.text() for n in nodes if n.has('wprm-recipe-instruction-text')]
    foodhero = next((n for n in nodes if n.has('field_ingredients')), None)
    if foodhero:
        ingredients = [n.text() for n in foodhero.nodes() if n.has('ingredient')]
        block = next((n for n in nodes if n.has('field_instructions')), None)
        if block:
            steps = [n.text() for n in block.nodes() if n.tag == 'li']
    if not ingredients:
        block = next((n for n in nodes if n.has('tasty-recipes-ingredients')), None)
        if block:
            ingredients = [n.text() for n in block.nodes() if n.tag == 'li']
    if not steps:
        block = next((n for n in nodes if n.has('tasty-recipes-instructions')), None)
        if block:
            steps = [n.text() for n in block.nodes() if n.tag == 'li']
    # Section-aware fallback for publishers with absent or empty Recipe JSON-LD.
    if not ingredients or not steps:
        scope = recipe_scope(dom,source) or dom.root
        fields = {'ingredients': [], 'steps': []}
        mode = None
        section_nodes = list(scope.nodes())
        for n in section_nodes:
            if excluded(n):
                continue
            text = n.text()
            if n.tag in ('h2', 'h3', 'h4') or (n.tag in ('p','strong','b') and re.fullmatch(r'(Ingredientes|Ingredients|Preparaci[oó]n|Procedimiento|Directions)', text, re.I)):
                if re.search(r'\b(ingredientes|ingredients)\b', text, re.I) and not re.search(r'(m[aá]s recetas|otras recetas|estos ingredientes)', text, re.I):
                    mode = 'ingredients'
                elif (not fields['steps'] or mode == 'steps') and (re.search(r'\b(preparaci[oó]n|instrucciones|elaboraci[oó]n|procedimiento|paso a paso|c[oó]mo (hacer|preparar)|directions|instructions|method|pasos a seguir)\b', text, re.I) or (mode == 'ingredients' and n.tag == 'h2' and text.lower().startswith('receta de'))):
                    mode = 'steps'
                elif n.tag == 'h2' or re.search(r'(m[aá]s recetas|consejos|preguntas|otras recetas|comentarios|video|servir|resumen|summary|contribution)', text, re.I):
                    mode = None
            elif mode and n.tag == 'li' and text and not any(x is not n and x.tag=='li' for x in n.nodes()):
                fields[mode].append(text)
            elif mode == 'steps' and n.tag == 'p' and len(text) > 20 and not any(x.tag == 'li' for x in n.nodes()):
                fields[mode].append(text)
            elif mode == 'ingredients' and n.tag == 'p' and text:
                # Older blogs use one ingredient per paragraph or explicit BR separators.
                chunks = []
                current = []
                for child in n.children:
                    if getattr(child, 'tag', '') == 'br':
                        chunks.append(' '.join(current).strip()); current=[]
                    else:
                        current.append(child.text() if hasattr(child,'text') else child)
                chunks.append(' '.join(current).strip())
                fields[mode].extend(x for x in chunks if x and not x.lower().startswith('para '))
        ingredients = ingredients or fields['ingredients']
        steps = steps or fields['steps']
    ingredients = [x for x in ingredients if not re.match(r'^Porciones\s*:', x, re.I)]
    group = ''
    grouped = []
    for item in ingredients:
        item = item.lstrip('\uf0b7• ').strip()
        if item.lower().rstrip(':') in ('relleno', 'masa', 'armado'):
            group = item.rstrip(':').lower()
        else:
            grouped.append(item + (' ('+group+')' if group else ''))
    ingredients = grouped
    return list(dict.fromkeys(ingredients)), list(dict.fromkeys(steps))


def extract_recipe(text, source="", *, language="es"):
    parser = Scripts()
    parser.feed(text)
    dom = DOM()
    dom.feed(text)
    entities = []
    for candidate in [text] + parser.parts:
        try:
            entities.extend(recipe_entities(json.loads(candidate)))
        except (ValueError, RecursionError):
            continue
    value = max(entities, key=lambda r: len(r.get('recipeIngredient') or []) + len(instructions(r.get('recipeInstructions', []))), default={})
    ingredients = value.get('recipeIngredient') or []
    if isinstance(ingredients, str):
        ingredients = ingredients.split('\n')
    ingredients = [clean(x) for x in ingredients if clean(x)]
    steps = instructions(value.get('recipeInstructions', []))
    visible_ingredients, visible_steps = visible_fields(dom,source)
    # Visible recipe widgets retain rows and groups that some schemas merge or omit.
    widget = any(n.has('wprm-recipe-ingredient') or n.has('tasty-recipes-ingredients') or n.has('field_ingredients') for n in dom.root.nodes())
    if visible_ingredients and (widget or not ingredients or (urlsplit(source).hostname or '').endswith('paulinacocina.net')):
        ingredients = visible_ingredients
    if visible_steps and (widget or not steps or urlsplit(source).hostname in ('bonviveur.com','www.bonviveur.com')):
        steps = visible_steps
    if not ingredients or not steps:
        raise ValueError('La fuente no contiene ingredientes y preparación completos. Abre el original y conserva la receta como borrador.')
    servings_text = value.get('recipeYield', '')
    if isinstance(servings_text, list):
        servings_text = next((x for x in servings_text if re.search(r'[a-záéíóú]', str(x), re.I)), servings_text[0] if servings_text else '')
    nodes = list(dom.root.nodes())
    declared = next((n.text() for n in nodes if n.has('wprm-recipe-servings-container') or n.has('tasty-recipes-yield')), '')
    if declared and (re.search(r'(arepas|empanadas|unidades|tazas|raciones|personas|porciones)', declared, re.I) or not re.search(r'[a-záéíóú]', str(servings_text), re.I)):
        servings_text = declared
    if not servings_text:
        declared = next((re.search(r'(?:Da para|Para)\s+(\d+)\s+(raciones|porciones|personas)', n.text(), re.I)
                         for n in nodes if n.tag in ('p','span') and re.search(r'^(Da para|Para)\s+\d+\s+(raciones|porciones|personas)',n.text(),re.I)), None)
        if declared:
            servings_text = declared[1]+' '+declared[2]
    # Paulina's visible yield can contradict her structured metadata.
    if 'paulinacocina.net' in urlsplit(source).netloc:
        heading = next((n.text() for n in nodes if n.tag in ('h2', 'h3', 'h4') and re.search(r'(\d+\s+empanadas|docena)', n.text(), re.I)), '')
        if heading:
            servings_text = '12 empanadas' if 'docena' in heading.lower() else heading
    match = re.search(r'\d+(?:[.,]\d+)?', str(servings_text))
    servings = min(10000, max(1, float(match[0].replace(',', '.')))) if match else 1
    unit_match = re.search(r'(arepas|empanadas|enchiladas|galletas|piezas|unidades|tazas|vasos|panes|porciones|raciones|personas)', str(servings_text), re.I)
    unit = unit_match[0].lower() if unit_match else 'raciones'
    title = clean(value.get('name') or next((n.text() for n in nodes if n.tag == 'h1'), 'Receta importada'))[:250]
    photos = recipe_photos(value, source or str(value.get('url', '')))
    article = recipe_scope(dom,source)
    if article:
        known = {p['url'] for p in photos}
        for n in article.nodes():
            if n.tag != 'img' or excluded(n):
                continue
            url = image_url(n, source)
            parent = n.parent
            linked_elsewhere = False
            while parent and parent is not article:
                if parent.tag == 'a' and parent.attrs.get('href'):
                    link = urljoin(source, parent.attrs['href']).split('#')[0].rstrip('/')
                    if link != source.split('#')[0].rstrip('/') and not re.search(r'\.(jpg|jpeg|png|webp)([?]|$)',link,re.I):
                        linked_elsewhere = True
                        break
                parent = parent.parent
            if linked_elsewhere:
                continue
            if url and url not in known:
                known.add(url)
                photos.append({'url': url, 'source': source, 'caption': (n.attrs.get('alt') or title)[:10000], 'artist': '', 'license': '', 'license_url': '', 'image': ''})
    if not photos:
        for n in nodes:
            if n.tag == 'meta' and n.attrs.get('property') == 'og:image':
                photos = recipe_photos({'image': n.attrs.get('content')}, source)
                break
    if not photos:
        image = next((image_url(n,source) for n in nodes if n.tag == 'img' and
                      title.casefold() in (n.attrs.get('alt') or '').casefold() and image_url(n,source)), '')
        if image:
            photos = recipe_photos({'image':image},source)
    # Responsive variants of the same photograph do not become extra gallery entries.
    unique = {}
    for photo in photos:
        key = re.sub(r'-\d+x\d+(?=\.(?:jpe?g|png|webp))', '', photo['url'], flags=re.I)
        if '.pagespeed.' in key:
            key = key.split('.pagespeed.')[0]
            key = re.sub(r'/x([^/]+)$',r'/\1',key)
        if key not in unique or '.pagespeed.' in unique[key]['url']:
            unique[key] = photo
    photos = list(unique.values())
    return {'title': title, 'ingredients': ingredients[:500], 'steps': steps[:500], 'servings': servings,
            'servings_declared': bool(match), 'yield_unit': unit, 'yield_original': str(servings_text),
            'minutes': (next((int(m[1]) for n in nodes if n.has('recipe-data-row') and (m := re.fullmatch(r'Tiempo total\s+(\d+)\s*m',n.text(),re.I))), 0) if (urlsplit(source).hostname or '').endswith('hogarmania.com') else 0) or duration_minutes(value.get('totalTime')),
            'language': str(value.get('inLanguage') or next((n.attrs.get('lang','') for n in nodes if n.tag=='html'),'') or language).lower().split('-')[0].split('_')[0],
            'notes': clean(value.get('description', '')),
            'source': source or str(value.get('url', '')), 'tags': [], 'image': '', 'photos': photos[:500]}
