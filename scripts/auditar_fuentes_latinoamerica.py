"""Public, bounded sample research; does not connect sources to Mesa."""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import sys
from urllib.request import Request, urlopen

from auditar_fuentes_recetas import ROOT, Page, audit, fetch

SEEDS = [
    ('mx-mely', 'https://www.mexicoenmicocina.com/receta-de-enchiladas-rojas/'),
    ('mx-kiwilimon', 'https://www.kiwilimon.com/receta/desayunos/chilaquiles-rojos'),
    ('mx-larousse', 'https://laroussecocina.mx/receta/pozole-rojo/'),
    ('mx-nestle', 'https://www.recetasnestle.com.mx/recetas/chilaquiles-rojos'),
    ('ec-laylita', 'https://www.laylita.com/recetas/bolon-de-verde/'),
    ('co-erica', 'https://www.mycolombianrecipes.com/es/arepas-rellenas-de-queso/'),
    ('cl-pilar', 'https://cocinachilena.cl/PASTEL-DE-CHOCLO-CHILEAN-CORN-PIE/'),
    ('ar-paulina', 'https://www.paulinacocina.net/como-hacer-empanadas-de-carne/9220'),
    ('ar-cocineros', 'https://cocinerosargentinos.com/recetas/carne/empanadas-de-carne'),
    ('pe-buenazo', 'https://buenazo.pe/recetas/platos-de-fondo/lomo-saltado-ingredientes-preparacion-61'),
    ('gt-pepian', 'https://www.guatemala.com/aprende/cultura-guatemalteca/cocina/receta-para-hacer-pepian-guatemalteco'),
    ('ve-pabellon', 'https://www.venezuelatuya.com/cocina/pabellon2.htm'),
    ('caribe-goya', 'https://www.goya.com/es/recipes/ropa-vieja/'),
    ('cu-vero', 'https://lacocinadevero.com/ropa-vieja/'),
    ('co-agro-510', 'https://editorial.agrosavia.co/index.php/publicaciones/catalog/book/510'),
    ('co-agro-186', 'https://editorial.agrosavia.co/index.php/publicaciones/catalog/book/186'),
    ('co-agro-475', 'https://editorial.agrosavia.co/index.php/publicaciones/catalog/book/475'),
    ('cl-uchile', 'https://libros.uchile.cl/1203'),
    ('cr-patrimonio', 'https://www.mcj.go.cr/index.php/sala-de-prensa/noticias/descargue-los-recetarios-del-centro-de-patrimonio-y-redescubra-la-cocina'),
]

PDFS = [
    ('uy-sabores-andantes', 'https://www.gub.uy/ministerio-desarrollo-social/sites/ministerio-desarrollo-social/files/documentos/publicaciones/Libro-Recetario%20Sabores%20Andantes.pdf'),
    ('rd-iddi', 'https://iddi.org/wp-content/uploads/2024/08/RERecetario-Gastronomico-vFINAL-IMPRENTA.pdf'),
    ('co-picante', 'https://editorial.agrosavia.co/index.php/publicaciones/catalog/download/475/585/2678?inline=1'),
    ('co-caribe', 'https://editorial.agrosavia.co/index.php/publicaciones/catalog/download/510/620/2803?inline=1'),
    ('co-arracacha', 'https://editorial.agrosavia.co/index.php/publicaciones/catalog/download/186/172/1212?inline=1'),
    ('cr-ucr', 'https://tradicionescostarica.ucr.ac.cr/wp-content/uploads/2022/01/Recetario-costarricense-Accesible-para-todos.pdf'),
]

def pdf_download(seed):
    key, url = seed
    result = {'id': key, 'requested_url': url}
    try:
        req = Request(url, headers={'User-Agent': 'Mesa-Source-Research/1.0 (public sample audit)'})
        with urlopen(req, timeout=40) as response:
            raw = response.read(30_000_001)
            result.update(status=response.status, final_url=response.geturl(), bytes=len(raw))
        if len(raw) > 30_000_000:
            raise ValueError('Document exceeds bounded 30 MB download')
        if not raw.startswith(b'%PDF-'):
            result['error'] = 'Not PDF bytes; document endpoint needs inspection'
            return result
        dest = ROOT/'output'/'research'/'latinamerica'/f'{key}.pdf'
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(raw)
        result.update(local_path=str(dest), sha256=hashlib.sha256(raw).hexdigest())
    except Exception as exc:
        result['error'] = str(exc)
    return result

if __name__ == '__main__':
    pdf_mode = '--pdf' in sys.argv
    seeds = PDFS if pdf_mode else SEEDS
    selected = set(sys.argv[1:]) - {'--pdf'}
    if selected:
        seeds = [seed for seed in seeds if seed[0] in selected]
    with ThreadPoolExecutor(max_workers=3) as pool:
        rows = list(pool.map(pdf_download if pdf_mode else audit, seeds))
    if not pdf_mode:
        for row in rows:
            if 'agro-' in row['id'] or row['id'] == 'cr-patrimonio':
                try:
                    raw, final, _, _, encoding = fetch(row['requested_url'])
                    page = Page(); page.feed(raw.decode(encoding, errors='replace'))
                    from urllib.parse import urljoin
                    row['document_links'] = list(dict.fromkeys(urljoin(final, link) for link in page.links if 'catalog/view/' in link or '.pdf' in link or 'drive.google' in link))
                except Exception as exc:
                    row['document_links_error'] = str(exc)
    dest = ROOT/'output'/('fuentes-latinoamerica-documentos-2026-10-11.json' if pdf_mode else 'fuentes-latinoamerica-auditoria-2026-10-11.json')
    if selected and dest.exists():
        old_rows = json.loads(dest.read_text(encoding='utf-8'))['pages']
        rows = [row for row in old_rows if row['id'] not in selected] + rows
    dest.write_text(json.dumps({'checked_at': datetime.now(timezone.utc).isoformat(), 'method': 'Small public samples, no credentials or bulk crawl. PDF source documents are unchanged. Recipe HTML/images are not saved. Counts are sample evidence, not whole-source guarantees.', 'pages': rows}, ensure_ascii=False, indent=2), encoding='utf-8')
    for row in rows:
        recipe = row.get('recipe', {})
        print(row['id'], row.get('status'), row.get('bytes_sampled', row.get('bytes')), 'Recipe', row.get('recipe_jsonld'), 'ingredients', recipe.get('ingredient_count'), 'numeric', recipe.get('numeric_quantity_lines'), 'photos', recipe.get('jsonld_photo_count'), row.get('error', ''))
        if 'document_links' in row: print('Documents:', row['document_links'])
        if 'licence_urls' in row and row['licence_urls']: print('Licences:', row['licence_urls'])
    print(dest)
