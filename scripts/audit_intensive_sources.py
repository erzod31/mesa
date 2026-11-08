"""One live catalogue and at most one sample per source, with no family secrets."""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import json
from pathlib import Path
import sys
import time

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from server.catalogs import SOURCES, publisher_catalog
from server.fetcher import fetch_page
from server.importer import extract_recipe
from server.open_catalogs import wiki_recipe
from server.wordpress_catalog import API, parse_post


def audit(source):
    row={'id':source['id'],'name':source['name']}; clock=time.monotonic()
    if source['id']=='es-nestle':
        return row|{'status':'CONSULTA ORIGINAL','reason':'La app ya identifica esta fuente como consulta en el navegador.'}
    try:
        listing=publisher_catalog(source['id'])
        row['items']=len(listing['items']);row['notice']=listing.get('notice','')
        if not listing['items']:
            row['status']='SIN RESULTADOS EN ESTE TRAMO';return row
        target=listing['items'][0]['id']
        row['sample_target']=target
        if source['id'].startswith('wiki-'): value=wiki_recipe(source,target)
        elif source['id']=='delokos-es':
            body,_=fetch_page(API+str(target));value=parse_post(json.loads(body))
        elif source['id']=='mx-kiwilimon':
            from server.publisher_adapters import kiwilimon_recipe
            body,url=fetch_page(target);value=kiwilimon_recipe(url,body)
        else:
            body,url=fetch_page(target);value=extract_recipe(body,url)
        if not value: raise ValueError('La publicación no es una receta completa con foto.')
        row.update(status='LECTURA VERIFICADA',sample=value.get('source',''),title=value['title'],
                   ingredients=len(value['ingredients']),steps=len(value['steps']),photos=len(value.get('photos',[])))
    except Exception as error: row.update(status='INCIDENCIA',error=str(error))
    finally: row['seconds']=round(time.monotonic()-clock,2)
    print(row['id'],row['status'],row.get('error',''),flush=True)
    return row


if __name__=='__main__':
    selected=set(sys.argv[1:])
    with ThreadPoolExecutor(max_workers=3) as pool: results=list(pool.map(audit,[s for s in SOURCES.values() if not selected or s['id'] in selected]))
    path=ROOT/'output/auditoria-intensiva-2026-10-14/sources-all-live.json'
    if selected and path.exists():
        previous=json.loads(path.read_text(encoding='utf-8'))['sources']
        results=[r for r in previous if r['id'] not in selected]+results
    path.write_text(json.dumps({'checked_at':datetime.now(timezone.utc).isoformat(),'sources':results},ensure_ascii=False,indent=2),encoding='utf-8')
