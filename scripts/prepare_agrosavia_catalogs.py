"""Extract recipe tables by ruled rows; keep publisher photos and exclude iStock pages.

No quantities, times or images are generated. The source PDFs remain unchanged.
"""
import base64
from collections import Counter
import hashlib
import io
import json
from pathlib import Path
import re
import sys

import pdfplumber
from pypdf import PdfReader
from PIL import Image, ImageDraw, ImageOps

ROOT = Path(__file__).resolve().parents[1]
META = {
    'co-arracacha': dict(provider='agro-arracacha', url='https://editorial.agrosavia.co/index.php/publicaciones/catalog/download/186/172/1212?inline=1',
                        license='CC BY-NC-SA 4.0', license_url='https://creativecommons.org/licenses/by-nc-sa/4.0/deed.es',
                        attribution='Johanna Paola Garnica Montaña, Jorge Luis Gómez Tovar y Adriana Lucía Ballesteros Bahamón · AGROSAVIA / SENA (2021)',
                        artist='Matawa producciones (créditos del recetario)'),
    'co-caribe': dict(provider='agro-caribe', url='https://editorial.agrosavia.co/index.php/publicaciones/catalog/download/510/620/2803?inline=1',
                     license='CC BY-NC-SA (declaración del PDF; versión no indicada)', license_url='https://co.creativecommons.net/tipos-de-licencias/',
                     attribution='Isueh Arenas-Rubio, María Elvira Rúa Barrios, Miguel Ángel Rolong Bruno, Teresa de Jesús Altamar Pérez y Yaceris Mercedes Castro Escorcia · AGROSAVIA (2025)',
                     artist='Agustín Consuegra y Jossie Esteban Rojano (créditos del recetario)'),
}


def region(page, box):
    return (page.crop(box).extract_text() or '').strip()


def normalized(text):
    return ' '.join(text.replace('\n', ' ').split())


def category(title):
    t = title.lower()
    for words, cat in [(['salsa', 'dip', 'mojo', 'humus', 'babaganoush', 'adobo'], 'salsas'),
                       (['crema de', 'sancocho', 'sopa'], 'sopas'),
                       (['dulce', 'galleta', 'arequipe', 'alfajor', 'torta', 'mantecada', 'napoleón', 'cocada', 'gomita', 'pastelera'], 'postres'),
                       (['chicha', 'batido', 'avena'], 'bebidas'),
                       (['ensalada'], 'ensaladas'),
                       (['pan ', 'focaccia', 'crakers', 'arepa', 'empanada', 'wafle', 'panqueque'], 'panes'),
                       (['ñoqui', 'pasta', 'arroz'], 'arroz-pasta'),
                       (['róbalo', 'salmón', 'camarones'], 'pescados'),
                       (['res', 'cerdo', 'pollo', 'chorizo', 'salchicha', 'costilla'], 'carnes')]:
        if any(w in t for w in words):
            return 'category:' + cat
    return 'category:verduras'


def rows_from_lines(page, left, right, top, bottom, splits):
    ys = sorted(set(round(line['top'], 1) for line in page.lines
                    if abs(line['top'] - line['bottom']) < .5 and line['x1'] - line['x0'] > 20
                    and line['x0'] >= left-2 and line['x1'] <= right+2 and top < line['top'] < bottom))
    bounds = [top] + ys + [bottom]
    result = []
    for y0, y1 in zip(bounds, bounds[1:]):
        if y1-y0 < 5:
            continue
        cells = [normalized(region(page, (x0, y0+.1, x1, y1-.1))) for x0, x1 in zip(splits, splits[1:])]
        if any(cells):
            result.append(cells)
    return result


def arracacha_ingredients(page, words, procedure):
    header = next(w for w in words if w['text'] == 'Ingredientes')
    total = next(w for w in words if w['text'] == 'TOTAL')
    segments = [l for l in page.lines if abs(l['top']-l['bottom']) < .5 and header['top']+20 < l['top'] < total['top'] and l['x0'] < procedure['x0'] and l['x1']-l['x0'] > 20]
    xs = Counter(round(l[k], 1) for l in segments for k in ['x0', 'x1'])
    # The source draws four contiguous ruled cells per row, giving stable column boundaries.
    candidates = sorted(x for x, count in xs.items() if count >= 3)
    assert len(candidates) == 5, candidates
    rows = rows_from_lines(page, candidates[0], candidates[-1], header['top']+27, total['top']-.5, candidates)
    ingredients = []
    for name, unit, amount, equivalence in rows:
        if not name or not amount:
            raise ValueError(f'Incomplete ingredient table row: {name, unit, amount, equivalence}')
        if amount.lower() == 'c/n':
            line = name + ' (cantidad necesaria)'
        else:
            line = f'{amount} {unit} de {name.lower()}'
        if equivalence and amount.lower() != 'c/n':
            line += ' (' + equivalence + ')'
        ingredients.append(line)
    return ingredients


def caribe_ingredients(page, words, procedure):
    headers = [w for w in words if w['text'] == 'INGREDIENTES']
    amounts = [w for w in words if w['text'] == 'CANTIDAD']
    ingredients = []
    for header, amount in zip(headers, amounts):
        table_bottom = procedure['top'] if procedure['x0'] < header['x0'] else page.height-60
        segments = [l for l in page.lines if abs(l['top']-l['bottom']) < .5 and header['bottom'] < l['top'] < table_bottom
                    and header['x0']-90 < l['x0'] < amount['x1'] and l['x1']-l['x0'] < 300]
        if not segments:
            raise ValueError('Ingredient row rules not found')
        left, right = min(l['x0'] for l in segments), max(l['x1'] for l in segments)
        endpoints = Counter(round(l[k],1) for l in segments for k in ('x0','x1'))
        candidates = sorted(x for x, count in endpoints.items() if count >= 2)
        split = candidates[1] if len(candidates) == 3 else amount['x0']-6
        last_line = max(l['top'] for l in segments)
        rows = rows_from_lines(page, left, right, header['bottom']+4, last_line+.2, [left, split, right])
        for name, quantity in rows:
            if not name or not quantity:
                raise ValueError(f'Incomplete ingredient: {name, quantity}')
            # Colombian thousands punctuation must not be read as a decimal when scaling.
            quantity = re.sub(r'(?<=\d)\.(?=\d{3}(?:\D|$))', '', quantity)
            if quantity.lower() == 'al gusto':
                ingredients.append(name + ' al gusto')
            else:
                ingredients.append(quantity + ' de ' + name.lower())
    return ingredients


def split_steps(text):
    text = re.sub(r'(\w)-\s*\n\s*(\w)', r'\1\2', text)
    parts = re.split(r'(?:^|\n)\s*\d+[.]?\s+', text)
    return [normalized(x) for x in parts if normalized(x)]


def photos(reader, pdf, indexes, meta, title):
    result = []
    for index in indexes:
        for img in pdf.pages[index].images:
            # Recipe photographs fill the page or its side strip. Small decorative plants are excluded.
            if img['width'] * img['height'] < pdf.pages[index].width * pdf.pages[index].height * .09:
                continue
            original = reader.pages[index].images['/' + img['name']].image
            photo = ImageOps.exif_transpose(original).convert('RGB')
            photo.thumbnail((1000, 1000))
            buffer = io.BytesIO(); photo.save(buffer, format='JPEG', quality=82)
            if buffer.tell() > 180000:
                buffer = io.BytesIO(); photo.save(buffer, format='JPEG', quality=60)
            assert buffer.tell() <= 180000
            result.append(dict(image=base64.b64encode(buffer.getvalue()).decode('ascii'), caption=title+' · Foto '+str(len(result)+1),
                               artist=meta['artist'], license=meta['license'], license_url=meta['license_url'],
                               source=meta['url']+'#page='+str(index+1)))
    return result


def build(name, meta):
    path = ROOT/'output/research/latinamerica'/f'{name}.pdf'
    reader = PdfReader(path)
    selected_page = next((int(x.split('=')[1]) for x in sys.argv if x.startswith('--page=')), None)
    dest = ROOT/'client/assets/catalogs'/f'{meta["provider"]}.json'
    recipes, excluded, contact = [], [], []
    if selected_page and dest.exists():
        previous=json.loads(dest.read_text(encoding='utf-8'))
        recipes=[r for r in previous['recipes'] if r['origin']['id'] != str(selected_page)]
        excluded=[r for r in previous['excluded'] if r['pdf_page'] != selected_page]
    with pdfplumber.open(path) as pdf:
        for i, page in enumerate(pdf.pages):
            if selected_page and i+1 != selected_page:
                continue
            # Cheap text eligibility before expensive spatial reading.
            raw = reader.pages[i].extract_text()
            if 'Procedimiento' not in raw or 'Cantidad:' not in raw:
                continue
            words = page.extract_words()
            proc = next((w for w in words if w['text'] == 'Procedimiento'), None)
            if not proc:
                continue
            yield_word = next(w for w in words if w['text'] == 'Cantidad:')
            title = normalized(region(page, (95 if name == 'co-arracacha' else 150, 65 if name == 'co-arracacha' else 30,
                                              950 if name == 'co-arracacha' else 680, min(265,yield_word['top']-5) if name == 'co-arracacha' else yield_word['top']-5)))
            title = title.replace('Jorge Luis Gómez Tovar', '').strip()
            source_url = meta['url'] + f'#page={i+1}'
            try:
                if name == 'co-arracacha' and 'Encurtido' in title:
                    raise ValueError('La tabla del original contiene equivalencias y cantidades incongruentes; se conserva únicamente en el libro original.')
                # Stock pages are printed numbers, so their PDF positions have a +1 offset.
                indexes = [i-1, i]
                if name == 'co-caribe':
                    if i-1 in {3,8,50,78,104,124,128}:
                        raise ValueError('La foto principal está acreditada a iStock; también se excluye su variante lateral.')
                gallery = photos(reader, pdf, indexes, meta, title)
                if not gallery:
                    raise ValueError('Sin fotografía propia reutilizable.')
                ing = arracacha_ingredients(page, words, proc) if name == 'co-arracacha' else caribe_ingredients(page, words, proc)
                steps_text = region(page, (proc['x0']-1, proc['bottom']+1, 950 if name == 'co-arracacha' else 680,
                                          page.height-40 if name == 'co-arracacha' else 550))
                steps = split_steps(steps_text)
                assert ing and steps and len(title) > 8, title
                match = re.search(r'Cantidad:\s*(\d+)\s*porciones', raw)
                assert match, raw[:100]
                data = dict(title=title, ingredients=ing, steps=steps, servings=int(match[1]), yield_unit='porciones',
                            servings_declared=True, minutes=0, tags=['Colombia'], category_ids=[category(title)], catalog_ids=[],
                            image='', photos=gallery, source=source_url,
                            notes='Se conservan cantidades y rendimiento del original. No se declara duración total. '+
                                  'Las equivalencias entre paréntesis son las del libro; no se recalculan.\n'+
                                  ('El PDF declara BY-NC-SA sin versión, mientras la ficha editorial indica BY-SA 4.0. Se conserva la condición no comercial del PDF. Se excluyen las páginas acreditadas a iStock.\n' if name == 'co-caribe' else '')+
                                  'Adaptación de formato: tabla convertida a lista y fotos optimizadas; licencia del contenido independiente de la app.',
                            origin=dict(provider=meta['provider'], id=str(i+1), url=source_url, attribution=meta['attribution'],
                                        license=meta['license'], license_url=meta['license_url'], language='es', modified=True))
                recipes.append(data)
                cover = Image.open(io.BytesIO(base64.b64decode(gallery[0]['image']))).copy()
                contact.append((title, cover))
                print(name, i+1, title, len(ing), len(steps), len(gallery), flush=True)
            except (ValueError, AssertionError, StopIteration) as exc:
                excluded.append(dict(pdf_page=i+1, title=title, reason=str(exc)))
                print('EXCLUDE', name, i+1, title, str(exc), flush=True)
    recipes.sort(key=lambda r:int(r['origin']['id']))
    dest.write_text(json.dumps(dict(source_sha256=hashlib.sha256(path.read_bytes()).hexdigest(), recipes=recipes, excluded=excluded), ensure_ascii=False, indent=2), encoding='utf-8')
    review = [{k:v for k,v in row.items() if k not in ('photos','image')} for row in recipes]
    (ROOT/'output'/f'{name}-catalog-review.json').write_text(json.dumps(dict(recipes=review, excluded=excluded),ensure_ascii=False,indent=2),encoding='utf-8')
    for batch in range(0, len(contact), 12):
        sheet = Image.new('RGB', (1200, 6*180), 'white'); draw=ImageDraw.Draw(sheet)
        for j, (title, photo) in enumerate(contact[batch:batch+12]):
            x,y=(j%2)*600,(j//2)*180
            photo.thumbnail((240,150)); sheet.paste(photo,(x,y)); draw.text((x+245,y+20),title[:45],fill='black')
        sheet.save(ROOT/'output/research/latinamerica'/f'{name}-contact-{"page"+str(selected_page) if selected_page else str(batch//12+1)}.png')
    print(name, len(recipes), 'recipes;', sum(len(r['photos']) for r in recipes), 'photos;', len(excluded), 'excluded', flush=True)


if __name__ == '__main__':
    for name, meta in META.items():
        if len(sys.argv) == 1 or name in sys.argv[1:]:
            build(name, meta)
