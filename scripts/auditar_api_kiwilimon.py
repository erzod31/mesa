"""Two public read-only recipe POST lookups, no accounts or image downloads."""
from datetime import datetime, timezone
import json
import re
from urllib.parse import urlencode
from urllib.request import Request, urlopen
from auditar_fuentes_recetas import ROOT
from server.importer import clean

def inspect(path):
    endpoint = 'https://gr.kiwilimon.com/v6/recipe'
    args = {'language':'es', 'device':'pc', 'path':path, 'ingredients':'1'}
    result = {'endpoint':endpoint, 'parameters':args}
    try:
        request = Request(endpoint, data=urlencode(args).encode(), headers={'Content-Type':'application/x-www-form-urlencoded','User-Agent':'Mesa-Source-Research/1.0'})
        with urlopen(request, timeout=25) as response:
            raw=response.read(500_001)
            result.update(status=response.status, bytes=len(raw), content_type=response.headers.get_content_type())
        if len(raw)>500_000: raise ValueError('Bounded response exceeded')
        data=json.loads(raw)
        ingredients=data.get('ingredients') or []
        result.update(name=data.get('name'), language=data.get('language'), ingredient_entries=len(ingredients), steps=len(data.get('steps') or []), image_entries=len(data.get('images') or []), portions=data.get('portions'), total_time=data.get('totaltime'), ingredient_fields=list(ingredients[0]) if ingredients and isinstance(ingredients[0],dict) else [], image_fields=list(data['images'][0]) if data.get('images') and isinstance(data['images'][0],dict) else [])
        result['ingredient_schema']=[{k:type(v).__name__ for k,v in item.items()} for item in ingredients[:2] if isinstance(item,dict)]
        lines=[clean(item.get('text') or '') for item in ingredients if isinstance(item,dict)]
        result['ingredient_lines_with_numeric_tokens']=sum(bool(re.search(r'[0-9¼½¾⅓⅔⅛⅜⅝⅞]',line)) for line in lines)
        result['quantity_example']=next((line for line in lines if re.search(r'[0-9¼½¾⅓⅔⅛⅜⅝⅞]',line)),None)
        steps=data.get('steps') or []
        result['step_fields']=list(steps[0]) if steps and isinstance(steps[0],dict) else ['text']
        # Preserve only quantity/metric evidence, never the full recipe or user profile.
        result['amount_fields']=[{k:v for k,v in item.items() if re.search('quantity|amount|metric|measure|unit',k,re.I)} for item in ingredients if isinstance(item,dict)]
        result['image_identity_fields']=[{k:v for k,v in item.items() if k in {'key','image','url','path','rkey','ikey'}} for item in data.get('images',[]) if isinstance(item,dict)]
        result['cover_image']=data.get('image')
    except Exception as exc:
        result['error']=str(exc)
    return result

if __name__=='__main__':
    paths=['/receta/desayunos/chilaquiles-rojos','/receta/desayunos/chilaquiles-rojos-con-pollo']
    results=[inspect(path) for path in paths]
    out=ROOT/'output/fuentes-latinoamerica-api-2026-10-11.json'
    out.write_text(json.dumps({'checked_at':datetime.now(timezone.utc).isoformat(),'method':'Documented POST recipe lookup, read-only, no credentials, no photo bytes, no full texts. Successful access does not grant content redistribution rights.','pages':results},ensure_ascii=False,indent=2),encoding='utf-8')
    for result in results:print(json.dumps(result,ensure_ascii=False))
