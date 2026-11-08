"""Live authenticated translation smoke; uses public fixtures, never prints credentials."""
import json
from pathlib import Path
from time import perf_counter
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
connection = json.loads((ROOT/'data/desktop-connection.json').read_text(encoding='utf-8-sig'))
fixtures = json.loads((ROOT/'output/translation-final-full-recipes.json').read_text(encoding='utf-8'))
results = []
for fixture in fixtures:
    raw = fixture['original']
    request = Request('http://127.0.0.1:8765/v1/translate-recipe',
        data=json.dumps({'recipe':raw, 'source':fixture['language']}).encode(),
        headers={'Authorization':'Bearer '+connection['token'], 'Content-Type':'application/json'})
    start = perf_counter()
    with urlopen(request, timeout=180) as response:
        value = json.loads(response.read())
    assert value['language']=='es' and value['translation']['target_language']=='es'
    for key in ('title','ingredients','steps','notes'):
        assert value['original'][key] == raw.get(key,'' if key in ('title','notes') else [])
    assert len(value['ingredients'])==len(raw['ingredients']) and len(value['steps'])==len(raw['steps'])
    assert value['photos']==raw['photos']
    results.append({'language':fixture['language'],'title':value['title'],'seconds':round(perf_counter()-start,3),
        'ingredients':len(value['ingredients']),'steps':len(value['steps']),'original_preserved':True,'photo_metadata_preserved':True})
(ROOT/'output/translation-display-live.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(results,ensure_ascii=False))
