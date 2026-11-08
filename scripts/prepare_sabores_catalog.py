"""Extract the reviewed CC BY 4.0 recipe collection from the unchanged source PDF.

Run with the bundled Python (pdfplumber, pypdf, Pillow). Spatial columns and
continued spreads are read separately to avoid joining unrelated ingredients.
"""
import base64
import hashlib
import io
import json
import re
from pathlib import Path

import pdfplumber
from pypdf import PdfReader
from PIL import ImageOps

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'output/research/latinamerica/uy-sabores-andantes.pdf'
URL = ('https://www.gub.uy/ministerio-desarrollo-social/sites/ministerio-desarrollo-social/'
       'files/documentos/publicaciones/Libro-Recetario%20Sabores%20Andantes.pdf')
LICENSE = 'https://creativecommons.org/licenses/by/4.0/deed.es'
AUTHORS = ('Sabores Andantes (2019) · Udelar / INDA-MIDES · Agustina Vitola, Vanessa Gugliucci, '
           'Leticia Varela, Viviana Santín, Valentina Iragola, Luciana Bonilla, Alejandra Girona, '
           'María Rosa Curutchet, Daiana Magnani y Gastón Ares')


def text_region(page, box):
    return page.crop(box).extract_text() or ''


def paragraphs(page, box):
    lines = page.crop(box).extract_text_lines()
    groups = []
    previous = None
    for line in lines:
        if previous is None or line['top'] - previous['bottom'] > 6:
            groups.append(line['text'])
        else:
            groups[-1] += ' ' + line['text']
        previous = line
    return groups


def ingredients(text):
    entries = []
    group = ''
    for line in text.splitlines():
        line = line.strip()
        if line.startswith('Para ') and line.endswith(':'):
            group = line.rstrip(':').lower()
        elif line.startswith('•'):
            entries.append([line[1:].strip(), group])
        elif line and entries:
            entries[-1][0] += ' ' + line
    result = []
    for item, group in entries:
        item = item.replace('²/3', '2/3').replace('¹/3', '1/3')
        if ',' in item:
            name, amount = item.split(',', 1)
            amount = amount.strip()
            if re.match(r'[\d½¼¾⅓⅔⅛]', amount):
                item = f'{amount} de {name.lower()}'
        if group:
            item += f' ({group})'
        result.append(item)
    return result


def category(title):
    if any(s in title for s in ['BUDÍN', 'BROWNIE', 'MUFFIN', 'GALLET', 'MANZANA']):
        return 'category:postres'
    if any(s in title for s in ['HUMMUS', 'MAYONESA']):
        return 'category:salsas'
    if any(s in title for s in ['GRISINES', 'PAN ']):
        return 'category:panes'
    if 'ENSALADA' in title:
        return 'category:ensaladas'
    if any(s in title for s in ['LENTEJA', 'GARBANZO', 'POROTOS']):
        return 'category:legumbres'
    return 'category:verduras'


def build():
    expected = 'ca9951aceb4de385b9fe07af527b0748d627d705962dc8cf41d5b0f371eb5b77'
    if hashlib.sha256(SOURCE.read_bytes()).hexdigest() != expected:
        raise ValueError('The reviewed source PDF has changed')
    reader = PdfReader(SOURCE)
    recipes = []
    excluded = []
    contact_sheets = []
    with pdfplumber.open(SOURCE) as pdf:
        for index in range(19, 36):
            page = pdf.pages[index]
            words = page.extract_words()
            yields = [w for w in words if w['text'] == 'Rendimiento:']
            if not yields:
                continue
            for yield_word in sorted(yields, key=lambda w: w['x0']):
                side = int(yield_word['x0'] > page.width / 2)
                start = page.width * side / 2
                end = page.width * (side + 1) / 2
                title = ' '.join(text_region(page, (start, 65, end, yield_word['top'] - 1)).split())
                declaration = text_region(page, (start, yield_word['top'] - 1, end, yield_word['bottom'] + 1))
                match = re.search(r'Rendimiento:\s*(\d+)\s*(porciones|unidades)', declaration)
                assert match, declaration
                ing = next(w for w in words if w['text'] == 'INGREDIENTES' and start < w['x0'] < end)
                prep = next(w for w in words if w['text'] == 'PREPARACIÓN' and start < w['x0'] < end)
                ing_text = text_region(page, (ing['x0'] - 1, ing['bottom'] + 1, prep['x0'] - 8, 554))
                suggestions = [w for w in words if w['text'] == 'SUGERENCIA' and prep['x0'] - 2 < w['x0'] < end]
                bottom = min([w['top'] - 1 for w in suggestions] + [554])
                steps = paragraphs(page, (prep['x0'] - 1, prep['bottom'] + 1, end - 25, bottom))
                notes = []
                if suggestions:
                    notes += paragraphs(page, (prep['x0'] - 1, suggestions[0]['bottom'] + 1, end - 25, 554))
                if len(yields) == 1:
                    # Three preparations continue into the facing printed page.
                    continuation_x = page.width / 2 + 62
                    suggestion = next((w for w in words if w['text'] == 'SUGERENCIA' and w['x0'] > page.width / 2), None)
                    right_steps = paragraphs(page, (continuation_x, 108, continuation_x + 177, suggestion['top'] - 1 if suggestion else 554))
                    if index in (21, 25):
                        steps[-1] += ' ' + right_steps.pop(0)
                    steps += right_steps
                    if suggestion:
                        notes += paragraphs(page, (continuation_x, suggestion['bottom'] + 1, continuation_x + 177, 554))
                photo_entries = []
                for image in page.images:
                    if len(yields) > 1 and int(image['x0'] > page.width / 2) != side:
                        continue
                    original = reader.pages[index].images['/' + image['name']].image
                    photo = ImageOps.exif_transpose(original).convert('RGB')
                    photo.thumbnail((1000, 1000))
                    stream = io.BytesIO()
                    photo.save(stream, format='JPEG', quality=85)
                    caption = title.capitalize()
                    photo_entries.append({
                        'image': base64.b64encode(stream.getvalue()).decode('ascii'),
                        'caption': f'{caption} · Foto {len(photo_entries) + 1}',
                        'artist': 'Agustina Vitola y Leticia Varela (créditos del recetario)',
                        'license': 'CC BY 4.0', 'license_url': LICENSE,
                        'source': URL + f'#page={index + 1}',
                    })
                    if len(photo_entries) == 1:
                        contact_sheets.append((caption, photo.copy()))
                if not photo_entries:
                    excluded.append({'title': title, 'pdf_page': index + 1, 'reason': 'La ficha no tiene foto propia.'})
                    continue
                assert steps and ingredients(ing_text), title
                recipe = {
                    'title': title.capitalize(), 'ingredients': ingredients(ing_text), 'steps': steps,
                    'servings': int(match[1]), 'yield_unit': match[2], 'minutes': 0,
                    'tags': ['Uruguay'], 'category_ids': [category(title)], 'catalog_ids': [],
                    'image': '', 'photos': photo_entries,
                    'source': URL + f'#page={index + 1}',
                    'notes': ('Rendimiento original: ' + match[0].split(':', 1)[1].strip() + '. '
                              'Las unidades no indican personas. El libro no declara duración total. '
                              'Se conserva la preparación y las cantidades originales; se reordenan las líneas de ingredientes para facilitar el ajuste.\n\n'
                              + '\n\n'.join(notes)),
                    'origin': {'provider': 'sabores-uy', 'id': f'{index + 1}-{side}', 'url': URL + f'#page={index + 1}',
                               'attribution': AUTHORS, 'license': 'CC BY 4.0', 'license_url': LICENSE,
                               'language': 'es', 'modified': True},
                }
                recipes.append(recipe)
    assert len(recipes) + len(excluded) == 25, (len(recipes), len(excluded))
    target = ROOT / 'client/assets/catalogs/sabores-andantes.json'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps({'source_sha256': expected, 'excluded_without_photo': excluded, 'recipes': recipes}, ensure_ascii=False, indent=2), encoding='utf-8')
    review = [{k: v for k, v in r.items() if k not in ['photos', 'image']} for r in recipes]
    (ROOT / 'output/sabores-catalog-review.json').write_text(json.dumps(review, ensure_ascii=False, indent=2), encoding='utf-8')
    from PIL import Image, ImageDraw
    for batch in range(0, len(contact_sheets), 10):
        sheet = Image.new('RGB', (1100, 5 * 220), 'white')
        draw = ImageDraw.Draw(sheet)
        for i, (title, photo) in enumerate(contact_sheets[batch:batch + 10]):
            x, y = (i % 2) * 550, (i // 2) * 220
            photo.thumbnail((195, 175))
            sheet.paste(photo, (x + 5, y + 5))
            draw.text((x + 205, y + 25), f'{batch+i+1}. {title}', fill='black')
        sheet.save(ROOT / f'output/research/latinamerica/sabores-contact-{batch//10+1}.png')
    print(f'{len(recipes)} recetas, {sum(len(r["photos"]) for r in recipes)} fotos; {target.stat().st_size} bytes')
    print('Excluidas sin foto:', excluded)


if __name__ == '__main__':
    build()
