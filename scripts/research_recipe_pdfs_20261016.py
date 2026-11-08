"""Bounded public PDF research; temporary documents, metadata-only final evidence."""
from concurrent.futures import ThreadPoolExecutor
from hashlib import sha256
import json
from pathlib import Path
import re
from urllib.request import Request, urlopen
from pypdf import PdfReader

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'tmp/pdfs/fuentes-20261016'
OUT = ROOT / 'output/fuentes-fiables-2026-10-16'
SOURCES = [
    ('mesa-polaca', 'https://bunkatura.pl/pdf/mesa_polaca.pdf'),
    ('unlp', 'https://sedici.unlp.edu.ar/bitstream/handle/10915/124488/Documento_completo._Encuentro_Multicultural_de_recetas._Agosto.pdf-PDFA.pdf?isAllowed=y&sequence=1'),
    ('fao-chile', 'https://www.fao.org/4/cb5960es/cb5960es.pdf'),
    ('fao-saberes', 'https://www.fao.org/4/i8269es/i8269es.pdf'),
]


def inspect(pair):
    name, url = pair
    record = {'id': name, 'url': url, 'access': 'pending'}
    try:
        path = DEST / (name + '.pdf')
        if path.exists():
            raw = path.read_bytes()
            record['access_method'] = 'Previously downloaded public research document; no network request'
        else:
            req = Request(url, headers={'User-Agent': 'Mesa-Source-Research/1.0 (single public document review)', 'Accept': 'application/pdf'})
            with urlopen(req, timeout=20) as response:
                raw = response.read(30_000_001)
                record['final_url'] = response.geturl()
            if len(raw) > 30_000_000 or not raw.startswith(b'%PDF'):
                raise ValueError('Not a PDF within the 30 MB research limit')
            path.write_bytes(raw)
        reader = PdfReader(path)
        rights, sample_pages = [], []
        for i, page in enumerate(reader.pages):
            content = page.extract_text() or ''
            if re.search(r'Creative Commons|\blicencia\b|derechos reservados', content, re.I):
                # Store short license identifiers only, not the book text.
                identifiers = list(dict.fromkeys(re.findall(r'CC\s*BY[^\n.]{0,50}|creativecommons\.org/[^\s)>]{1,90}', content, re.I)))
                rights.append({'pdf_page': i + 1, 'identifiers': identifiers})
        # Manually checked page references; an image count or matching word is
        # never presented as evidence that a page is a complete recipe.
        pages = {'mesa-polaca': [(90, 'Receta con cantidades y preparación'), (91, 'Fotografía del plato')],
                 'unlp': [(10, 'Byrek: cantidades, preparación y fotografía; créditos de foto pendientes')],
                 'fao-chile': [(10, 'Lentejas con quinua: cantidades y preparación'), (11, 'Fotografía del plato')],
                 'fao-saberes': [(9, 'Sopa de bolitas: equivalencia de elote discordante; revisar')]}[name]
        sample_pages = [{'pdf_page': n, 'kind': kind} for n, kind in pages]
        record.update(access='PDF read', pages=len(reader.pages), bytes=len(raw), sha256=sha256(raw).hexdigest(), rights_pages=rights, recipe_sample_pages=sample_pages)
        record['manual_review_date'] = '2026-10-16'
        record['manual_findings'] = {
            'mesa-polaca': ['Página 128: CC BY 4.0, créditos diferenciados de fotografías; no API ni URL individual de cada foto verificada.'],
            'unlp': ['La licencia CC BY-NC 4.0 se publica en la ficha SEDICI; no atribuir automáticamente a cada imagen de terceros.'],
            'fao-chile': ['Página 4: CC BY-NC-SA 3.0 IGO con excepción de materiales de terceros.'],
            'fao-saberes': ['Página 3: permiso no comercial propio; adaptación y traducción requieren solicitud.', 'Página 9: 4 tazas de elote (50 g), equivalencia discordante. No convertir automáticamente.'],
        }[name]
    except Exception as error:
        record.update(access='not verified', error=str(error))
    return record


if __name__ == '__main__':
    DEST.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(inspect, SOURCES))
    (OUT / 'documentos-pdf.json').write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(results, ensure_ascii=False, indent=2))
