"""Source-specific DOM contrast and public photo HEAD checks; no images saved."""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import json
import re
from urllib.request import Request, urlopen
from auditar_fuentes_recetas import ROOT, fetch
from probar_integridad_fuentes import DOM

def inspect(row):
    result = {'id': row['id'], 'url': row['requested_url']}
    try:
        raw, final, status, _, enc = fetch(row['requested_url'])
        dom = DOM(); dom.feed(raw.decode(enc, errors='replace'))
        nodes = list(dom.root.nodes())
        containers = [n for n in nodes if 'entry-content' in (n.attrs.get('class') or '').split() or 'article-content' in (n.attrs.get('class') or '').split()]
        if containers:
            result['article_img_elements'] = sum(n.tag == 'img' for n in containers[0].nodes())
            result['article_scope'] = containers[0].attrs.get('class')
        wprm = [n for n in nodes if 'wprm-recipe-ingredient' in (n.attrs.get('class') or '').split()]
        if wprm:
            result['visible_ingredient_rows'] = len(wprm)
            result['visible_rows_with_numeric_tokens'] = sum(bool(re.search(r'[0-9¼½¾⅓⅔⅛⅜⅝⅞]', n.text())) for n in wprm)
        if row['id'] == 'ar-paulina':
            start = next(i for i,n in enumerate(nodes) if n.tag == 'h2' and n.text().strip().startswith('Ingredientes'))
            end = next(i for i,n in enumerate(nodes[start+1:],start+1) if n.tag == 'h2')
            li = [n for n in nodes[start+1:end] if n.tag == 'li']
            result['visible_ingredient_rows'] = len(li)
            result['visible_rows_with_numeric_tokens'] = sum(bool(re.search(r'[0-9¼½¾⅓⅔⅛⅜⅝⅞]', n.text())) for n in li)
            result['visible_yield_kind'] = '12 empanadas (heading), not 4 people from schema'
        photos = row.get('recipe', {}).get('photo_urls') or [row.get('open_graph_image')]
        if photos and photos[0]:
            with urlopen(Request(photos[0], method='HEAD', headers={'User-Agent':'Mesa-Source-Research/1.0'}), timeout=20) as response:
                result['cover_head'] = {'url':photos[0], 'status':response.status, 'content_type':response.headers.get_content_type()}
    except Exception as exc:
        result['error'] = str(exc)
    return result

if __name__ == '__main__':
    ids = {'mx-mely','ec-laylita','cl-pilar','ar-paulina','mx-larousse','co-erica','cu-vero','gt-pepian','pe-buenazo'}
    data = json.loads((ROOT/'output/fuentes-latinoamerica-auditoria-2026-10-11.json').read_text(encoding='utf-8'))
    with ThreadPoolExecutor(max_workers=3) as pool:
        results = list(pool.map(inspect, [r for r in data['pages'] if r['id'] in ids]))
    dest = ROOT/'output/fuentes-latinoamerica-integridad-2026-10-11.json'
    dest.write_text(json.dumps({'checked_at':datetime.now(timezone.utc).isoformat(), 'method':'Bounded public GET and HEAD only. Image element counts include duplicates and are not verified gallery sizes. Numeric tokens are not a proof of valid amounts. No recipe text or image content saved.', 'pages':results},ensure_ascii=False,indent=2),encoding='utf-8')
    for row in results:
        print(row['id'], 'DOM ingredients',row.get('visible_ingredient_rows'), 'numeric',row.get('visible_rows_with_numeric_tokens'), 'article image elements',row.get('article_img_elements'), 'HEAD',row.get('cover_head',{}).get('status'), row.get('error',''))
