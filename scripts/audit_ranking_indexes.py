"""Bounded read-only inspection of public indexes; never fetches photos."""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from hashlib import sha256
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import sys
from urllib.parse import urlsplit, urljoin
from urllib.request import Request, urlopen
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT/'output/research/ranking-indexes'
DEST.mkdir(parents=True, exist_ok=True)


def fetch(key, url):
    result = dict(key=key, requested_url=url)
    try:
        request = Request(url, headers={'User-Agent': 'Mesa-Recipe-Count-Audit/1.0', 'Accept': 'text/html,application/xml,application/json,text/plain'})
        with urlopen(request, timeout=18) as response:
            raw = response.read(12_000_001)
            if len(raw) > 12_000_000:
                raise ValueError('Index exceeds bounded 12 MB')
            result.update(status=response.status, final_url=response.geturl(), bytes=len(raw), sha256=sha256(raw).hexdigest(), headers={k:v for k,v in response.headers.items() if k.lower() in ('x-wp-total', 'x-wp-totalpages', 'content-type')})
            text=raw.decode(response.headers.get_content_charset() or 'utf-8', errors='replace')
        path=DEST/(key+'.txt')
        path.write_text(text, encoding='utf-8')
        result['local_path']=str(path)
        try:
            node=ET.fromstring(text)
            result['xml_root']=node.tag.split('}')[-1]
            locs=[n.text for n in node.findall('./{*}sitemap/{*}loc') or node.findall('./{*}url/{*}loc')]
            result['loc_count']=len(locs)
            result['loc_sample']=locs[:8]
        except ET.ParseError:
            pass
        result['sitemap_links']=re.findall(r'(?im)^sitemap:\s*(\S+)',text)
        return result
    except Exception as exc:
        result['error']=str(exc)
        return result


def probe(row):
    base=urlsplit(row['url']); origin=base.scheme+'://'+base.netloc
    tasks=[(row['id']+'-home',row['url']), (row['id']+'-robots',origin+'/robots.txt')]
    results=[fetch(*task) for task in tasks]
    maps=results[-1].get('sitemap_links',[])
    sitemap=maps[0] if maps else origin+'/sitemap_index.xml'
    results.append(fetch(row['id']+'-sitemap',sitemap))
    print(row['id'], [(r['key'].split('-')[-1],r.get('status'),r.get('xml_root'),r.get('loc_count'),r.get('error','')[:55]) for r in results],flush=True)
    return dict(id=row['id'],results=results)


def main():
    if len(sys.argv)==4 and sys.argv[1]=='--url':
        result=fetch(sys.argv[2], sys.argv[3]); print(json.dumps(result,ensure_ascii=False)); return
    rows=json.loads((ROOT/'server/sources.json').read_text(encoding='utf-8'))
    selected=set(sys.argv[1:])
    rows=[r for r in rows if r['mode']!='book' and r['recipe_count'] is None and (not selected or r['id'] in selected)]
    with ThreadPoolExecutor(max_workers=3) as pool:
        results=list(pool.map(probe,rows))
    path=ROOT/'output/ranking-index-probes.json'
    path.write_text(json.dumps(dict(checked_at=datetime.now(timezone.utc).isoformat(),sources=results),ensure_ascii=False,indent=2),encoding='utf-8')


if __name__=='__main__':
    main()
