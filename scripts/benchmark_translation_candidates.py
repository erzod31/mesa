"""Compare installed local candidates with identical public recipes. Never changes selection."""
import json
from pathlib import Path
import statistics
import sys
from time import perf_counter

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from server import quality_translation as quality

fixtures=json.loads((ROOT/'output/translation-final-full-recipes.json').read_text(encoding='utf-8'))
results=[]
for model in ('translategemma:4b','translategemma:12b'):
    start=perf_counter()
    quality.request('/api/generate',{'model':model,'prompt':'','stream':False,'keep_alive':'15m','options':{'num_ctx':8192}},timeout=150)
    warm_seconds=round(perf_counter()-start,3)
    rows=[]
    for fixture in fixtures:
        raw=fixture['original']
        texts=(raw['title'],*raw['ingredients'],*raw['steps'])
        start=perf_counter()
        row={'language':fixture['language'],'source':raw['source'],'fields':len(texts)}
        try:
            output=quality._translate_group(texts,fixture['language'],model)
            row.update(success=True,output=list(output))
        except (ValueError,RuntimeError) as error:row.update(success=False,error=str(error))
        row['seconds']=round(perf_counter()-start,3)
        rows.append(row)
        print(json.dumps({'model':model,**{k:v for k,v in row.items() if k!='output'}},ensure_ascii=False),flush=True)
    valid=[r['seconds'] for r in rows if r['success']]
    results.append({'model':model,'warm_seconds':warm_seconds,'valid_recipes':len(valid),'total_recipes':len(rows),
        'median_success_seconds':statistics.median(valid) if valid else None,'rows':rows,
        'quality_note':'Field/quantity validation is not a semantic equivalence guarantee. Outputs require review.'})
(ROOT/'output/translation-candidates-local.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
