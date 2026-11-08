"""Bounded live verification of each selected publisher, with no family credentials."""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from server.catalogs import SOURCES, publisher_catalog, publisher_origin
from server.fetcher import fetch_page
from server.importer import extract_recipe


def audit(source):
    result = dict(id=source['id'], name=source['name'], mode=source['mode'])
    if source['mode'] != 'web':
        return result
    try:
        listing = publisher_catalog(source['id'])
        result.update(listed=len(listing['items']), notice=listing['notice'], photo_hosts=sorted({__import__('urllib.parse',fromlist=['urlsplit']).urlsplit(i['image']).hostname for i in listing['items']}))
        # Only one recipe is fetched for verification; never an automatic full-source import.
        target = source['seed'] if source['seed'] != source['url'] else (listing['items'][0]['id'] if listing['items'] else '')
        if target:
            page, final = fetch_page(target)
            dest = ROOT/'output/research/source-pages'/f'{source["id"]}.html'
            dest.parent.mkdir(parents=True, exist_ok=True); dest.write_text(page,encoding='utf-8')
            if source['id'] == 'mx-kiwilimon':
                from server.publisher_adapters import kiwilimon_recipe
                recipe = kiwilimon_recipe(final,page)
            else:
                recipe = extract_recipe(page, final)
            publisher_origin(recipe, source['id'])
            result.update(sample_url=final, title=recipe['title'], ingredients=len(recipe['ingredients']), steps=len(recipe['steps']), photos=len(recipe['photos']),
                          yield_original=recipe['yield_original'], minutes=recipe['minutes'])
    except Exception as exc:
        result['error'] = str(exc)
    print(result['id'], 'listing', result.get('listed'), 'recipe', result.get('ingredients'), 'photos', result.get('photos'), result.get('error',''), flush=True)
    return result


if __name__ == '__main__':
    selected = set(sys.argv[1:])
    rows = [s for s in SOURCES.values() if not selected or s['id'] in selected]
    with ThreadPoolExecutor(max_workers=3) as pool:
        results = list(pool.map(audit, rows))
    target=ROOT/'output/connected-publishers-live.json'
    if selected and target.exists():
        old=json.loads(target.read_text(encoding='utf-8'))['sources']
        results=[r for r in old if r['id'] not in selected]+results
    target.write_text(json.dumps(dict(checked_at=datetime.now(timezone.utc).isoformat(), sources=results),ensure_ascii=False,indent=2),encoding='utf-8')
    print(target,flush=True)
