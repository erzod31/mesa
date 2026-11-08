"""Verify one image URL per successful publisher using HEAD only."""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import json
from pathlib import Path
from urllib.request import Request, urlopen
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from scripts.audit_importable_sites import fetch_checked, UA
from server.fetcher import public_target


def head(pair):
    key,url=pair
    record={'id':key,'url':url,'method':'HEAD','checked_at':datetime.now(timezone.utc).isoformat()}
    try:
        public_target(url)
        with urlopen(Request(url,method='HEAD',headers={'User-Agent':UA}),timeout=10) as response:
            record.update(status=response.status,content_type=response.headers.get_content_type(),content_length=response.headers.get('Content-Length'),final_url=response.geturl())
    except Exception as e: record['error']=str(e)
    return record


if __name__=='__main__':
    audit=json.loads((ROOT/'output/importable-sites-audit-2026-10-11.json').read_text(encoding='utf-8'))
    pairs=[]
    for s in audit['sites']:
        if s['id']=='en-kingarthur': continue  # Policy explicitly forbids scraping; no more probes.
        photo=next((p['mesa_server_parser']['photo_sample_url'] for p in s['samples'] if p.get('mesa_server_parser',{}).get('photo_sample_url')),None)
        if photo: pairs.append((s['id'],photo))
    with ThreadPoolExecutor(max_workers=4) as pool: results=list(pool.map(head,pairs))
    policy_page,final,policy=fetch_checked('https://foodhero.org/es/media-center',{})
    if policy_page:
        from server.html_dom import DOM
        dom=DOM(); dom.feed(policy_page)
        policy['relevant_excerpts']=[n.text()[:400] for n in dom.root.nodes() if n.tag=='p' and any(x in n.text().lower() for x in ['permission','permiso','copyright','commercial','comercial','free to','uso'])][:3]
    data={'checked_at':datetime.now(timezone.utc).isoformat(),'method':'One sample photo HEAD per publisher; no image bodies read or stored. A HEAD response does not establish completeness or image rights. No further King Arthur probes after reading its policy.','image_heads':results,'foodhero_policy':policy}
    dest=ROOT/'output/importable-sites-photo-heads-2026-10-11.json'
    dest.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({'photo_checks':len(results),'image_head_200':sum(r.get('status')==200 and r.get('content_type','').startswith('image/') for r in results),'failures':[r for r in results if r.get('status')!=200 or not r.get('content_type','').startswith('image/')],'foodhero_policy':policy},ensure_ascii=False),flush=True)
