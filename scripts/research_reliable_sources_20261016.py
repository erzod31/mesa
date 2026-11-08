"""Read-only convenience sample. Stores metadata only, never image bodies/catalogues."""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.audit_importable_sites import audit


def main():
    previous = json.loads((ROOT / 'output/importable-sites-audit-2026-10-11.json').read_text(encoding='utf-8'))
    wanted = {'es-anna', 'es-comedera', 'mx-mely', 'ec-laylita', 'co-erica', 'us-foodhero'}
    sources = []
    for source in previous['sites']:
        if source['id'] in wanted:
            sources.append({k: source[k] for k in ('id', 'name', 'url', 'language')} | {'samples': [r['url'] for r in source['samples']][:2]})
    sources.extend([
        {'id': 'ca-alberta', 'name': 'Universidad de Alberta · español', 'language': 'es',
         'url': 'https://pressbooks.openeducationalberta.ca/proteincookbookforcancerspanish/',
         'samples': ['https://pressbooks.openeducationalberta.ca/proteincookbookforcancerspanish/chapter/omelette-occidental/', 'https://pressbooks.openeducationalberta.ca/proteincookbookforcancerspanish/chapter/fajitas-de-pollo-preparadas-en-una-sarten/']},
        {'id': 'es-creativegan', 'name': 'CreatiVegan', 'language': 'es', 'url': 'https://creativegan.net/',
         'samples': ['https://creativegan.net/archives/arroz-con-leche-de-soja/']},
        {'id': 'es-gastronomiavegana', 'name': 'Gastronomía Vegana', 'language': 'es', 'url': 'https://www.gastronomiavegana.org/',
         'samples': ['https://www.gastronomiavegana.org/recetas/mousse-de-chocolate-vegana/']},
    ])
    selection = json.loads((ROOT / 'server/source_selection.json').read_text(encoding='utf-8'))
    retired = set(selection['retired_ids'])
    def check(source):
        result = audit(source)
        result['previously_retired'] = source['id'] in retired
        print(source['id'], result['candidate_complete_samples'], '/', result['samples_attempted'], flush=True)
        return result
    with ThreadPoolExecutor(max_workers=3) as pool:
        results = list(pool.map(check, sources))
    dest = ROOT / 'output/fuentes-fiables-2026-10-16'
    dest.mkdir(parents=True, exist_ok=True)
    (dest / 'muestras-web.json').write_text(json.dumps({
        'checked_at': datetime.now(timezone.utc).isoformat(),
        'method': 'Hasta dos páginas por fuente, tres dominios simultáneos; robots y redirecciones revisados; metadatos y URLs únicamente. Sin imágenes descargadas ni cambios al catálogo.',
        'limits': 'Muestra de conveniencia; el lector genérico del servidor no prueba el adaptador Android. Conteos automáticos no certifican fidelidad, licencia ni integridad de todas las fotos. Un bloqueo de robots o red no demuestra ausencia de recetas.',
        'sites': results,
    }, ensure_ascii=False, indent=2), encoding='utf-8')


if __name__ == '__main__':
    main()
