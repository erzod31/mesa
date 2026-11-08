"""Translate complete recipe fields using the dedicated local TranslateGemma worker."""
import json
from pathlib import Path
import re
import urllib.error
import urllib.request
from threading import BoundedSemaphore, Lock
import time

ROOT = Path(__file__).resolve().parents[1]
URL = 'http://127.0.0.1:11435'
def selected_model():
    try:
        value=json.loads((ROOT/'.tools/translation/translategemma.json').read_text(encoding='utf-8-sig')).get('model')
        return value if value in ('translategemma:4b','translategemma:12b') else 'translategemma:4b'
    except (OSError,ValueError): return 'translategemma:4b'
LANGUAGES = {'en':'English','fr':'French','it':'Italian','de':'German','pt':'Portuguese'}
INFERENCE_LOCK=BoundedSemaphore(1)
_last_warm=0.0
_availability_lock=Lock()
_availability_state=None
# Only quantities and explicit units are protected. No recipe image is downloaded.
NUMBER = r'\d+(?:[.,]\d+)?(?:\s*[/⁄]\s*\d+)?|[½¼¾⅓⅔⅛⅜⅝⅞]'
UNITS = {
    'cup':'taza','cups':'tazas','teaspoon':'cucharadita','teaspoons':'cucharaditas',
    'tsp':'cucharadita','tablespoon':'cucharada','tablespoons':'cucharadas','tbsp':'cucharada',
    'pound':'libra','pounds':'libras','ounce':'onza','ounces':'onzas','inches':'pulgadas','inch':'pulgada',
    'cuillère à café':'cucharadita','cuillères à café':'cucharaditas',
    'cuillère à soupe':'cucharada','cuillères à soupe':'cucharadas',
    'cucchiaino':'cucharadita','cucchiaini':'cucharaditas','cucchiaio':'cucharada','cucchiai':'cucharadas',
    'teelöffel':'cucharadita','esslöffel':'cucharada','el':'cucharada','tl':'cucharadita',
    'kl':'cucharadita','kaffeelöffel':'cucharadita','msp':'pizca','msp.':'pizca',
    'xícara':'taza','xícaras':'tazas','chávena':'taza','chávenas':'tazas',
    'colher de sopa':'cucharada','colheres de sopa':'cucharadas','colher de chá':'cucharadita','colheres de chá':'cucharaditas',
    'minutes':'minutos','minute':'minuto','minuti':'minutos','minuto':'minuto','minuten':'minutos',
    'hours':'horas','hour':'hora','heures':'horas','heure':'hora','ore':'horas','stunde':'hora','stunden':'horas',
    'seconds':'segundos','second':'segundo','secondes':'segundos','seconde':'segundo','secondi':'segundos','sekunden':'segundos',
    'litre':'litro','litres':'litros','liter':'litro','liters':'litros','litri':'litros',
    '°f':'°F','f':'F','c':'C','°c':'°C','° f':'°F','° c':'°C',
}
UNITS.update({k:k for k in ['g','kg','mg','ml','l','cl','dl','cm','mm','m','oz','lb','lbs','min']})
UNITS.update({'costa':'rama','coste':'ramas','persone':'personas','personnes':'personas','personen':'personas','pessoas':'personas','persons':'personas','people':'personas','servings':'raciones','portions':'raciones'})
# Validate translated unit names too, without allowing unrelated ingredient text
# to be swallowed inside a quantity tag.
for unit in list(UNITS.values()):
    UNITS.setdefault(unit.lower(),unit)
    if unit in ('taza','cucharada','cucharadita','libra','onza','pulgada','hora','minuto','segundo','litro','pizca'):
        UNITS.setdefault(unit+'s',unit+'s')
UNIT_PATTERN = '|'.join(re.escape(k) for k in sorted(UNITS, key=len, reverse=True))
QUANTITY = re.compile(rf'({NUMBER})(?:\s*({UNIT_PATTERN})(?![A-Za-zÀ-ÖØ-öø-ÿ]))?', re.I)
CODE = re.compile(r'<code\s+data-mesa=["\'](Q\d{4})["\']\s*>(.*?)</code>', re.S)
FIELD = re.compile(r'\[MESA_FIELD_(\d{4})\]')

def request(path, body=None, timeout=3):
    data = None if body is None else json.dumps(body, ensure_ascii=False).encode('utf-8')
    req = urllib.request.Request(URL+path, data=data, headers={'Content-Type':'application/json'})
    # The worker is loopback-only. Ignore externally configured HTTP proxies.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    try:
        with opener.open(req, timeout=timeout) as response:
            value = response.read(1_000_001)
    except (OSError, TimeoutError) as exc:
        raise RuntimeError('El traductor local no respondió. Reintenta; el texto original sigue disponible.') from exc
    if len(value)>1_000_000: raise ValueError('La respuesta del traductor es demasiado grande.')
    result=json.loads(value)
    if not isinstance(result,dict): raise ValueError('El traductor local devolvió una respuesta no válida.')
    return result

def available():
    global _availability_state
    config=ROOT/'.tools/translation/translategemma.json'
    if not config.is_file(): return False
    info=config.stat()
    identity=(info.st_mtime_ns,info.st_size,selected_model())
    # A stopped optional worker must not add two multi-second TCP probes to
    # every recipe. Coalesce probes; configuration changes invalidate at once.
    with _availability_lock:
        if _availability_state and _availability_state[0]==identity and time.monotonic()<_availability_state[1]:
            return _availability_state[2]
        try: ready=any(m.get('name')==identity[2] for m in request('/api/tags',timeout=.25).get('models', []))
        except (OSError, ValueError, RuntimeError): ready=False
        _availability_state=(identity,time.monotonic()+10,ready)
        return ready

def protect_quantities(text, protected):
    def replace(match):
        marker = f'Q{len(protected):04d}'
        unit = match[2]
        translated_unit=UNITS[unit.lower()] if unit else ''
        from .translation import number_value
        if translated_unit in ('taza','cucharada','cucharadita','libra','onza','pulgada','hora','minuto','segundo','litro','pizca') and number_value(match[1])>1:
            translated_unit+='s'
        protected[marker] = match[1] + (' '+translated_unit if unit else '')
        return f'<code data-mesa="{marker}">{match[0]}</code>'
    return QUANTITY.sub(replace, text)

def restore_quantities(text, protected):
    matches=list(CODE.finditer(text))
    # Some translations strip markup around bare item counts ("1 celery stalk").
    # Accept only numerically identical counts, with no newly introduced units.
    if protected and not matches and 'data-mesa' not in text and all(re.fullmatch(NUMBER,v) for v in protected.values()):
        from .translation import restore_numbers
        count_units={'rama','ramas','persona','personas','raciones'}
        if not any(m[2] and UNITS[m[2].lower()] not in count_units for m in QUANTITY.finditer(text)):
            return restore_numbers(' '.join(protected.values()),text)
    if [m[1] for m in matches] != list(protected): raise ValueError('El traductor omitió, repitió o reordenó una cantidad; se conserva el original.')
    if any(not QUANTITY.fullmatch(m[2].strip()) for m in matches):
        raise ValueError('El traductor mezcló texto con una medida; se conserva el original.')
    return CODE.sub(lambda m: protected[m[1]], text)

def parse_fields(text, indexes):
    matches=list(FIELD.finditer(text))
    if len(indexes)==1 and not matches and text.strip() and '[MESA_FIELD_' not in text:
        return [text.strip()]
    if [int(m[1]) for m in matches]!=indexes or (matches and text[:matches[0].start()].strip()):
        raise ValueError('La traducción está incompleta o cambió el orden de los campos.')
    values=[]
    for offset, match in enumerate(matches):
        end=matches[offset+1].start() if offset+1<len(matches) else len(text)
        value=text[match.end():end].strip()
        if not value: raise ValueError('El traductor omitió un ingrediente o paso.')
        values.append(value)
    return values

def translate_group(texts, source):
    from . import translation_cache
    model=selected_model();cache_key=translation_cache.key(texts,source,model)
    cached=translation_cache.read(cache_key,texts)
    if cached is not None:return cached
    with INFERENCE_LOCK:
        cached=translation_cache.read(cache_key,texts)
        if cached is not None:return cached
        result=_translate_group(texts,source,model)
        translation_cache.write(cache_key,texts,result)
        return result

def warm_model():
    global _last_warm
    if time.monotonic()-_last_warm<60 or not INFERENCE_LOCK.acquire(blocking=False):return
    try:
        _last_warm=time.monotonic()
        request('/api/generate',{'model':selected_model(),'prompt':'','stream':False,'keep_alive':'15m','options':{'num_ctx':8192}},timeout=150)
    except (OSError,ValueError,RuntimeError):pass
    finally:INFERENCE_LOCK.release()

def _translate_group(texts, source, model):
    if any('[MESA_' in t or 'data-mesa' in t for t in texts): raise ValueError('El texto contiene una marca reservada del traductor.')
    protected={};expected=[];fields=[]
    for i,text in enumerate(texts):
        before=len(protected)
        fields.append(f'[MESA_FIELD_{i:04d}]\n'+protect_quantities(text,protected))
        expected.append(list(protected)[before:])
    body='\n'.join(fields)
    language=LANGUAGES[source]
    prompt=(f'You are a professional {language} ({source}) to Spanish (es) translator. Your goal is to accurately convey '
            f'the meaning and nuances of the original {language} text while adhering to Spanish grammar, vocabulary, and cultural sensitivities.\n'
            'This is a cooking recipe. Preserve every [MESA_FIELD_...] marker and every HTML code tag with its data-mesa attribute exactly. '
            'Do not add or omit ingredients or instructions. Do not convert measurements.\n'
            f'Produce only the Spanish translation, without any additional explanations or commentary. Please translate the following {language} text into Spanish:\n\n\n'+body)
    value=request('/api/chat', {'model':model,'messages':[{'role':'user','content':prompt}],
        'stream':False,'keep_alive':'15m','options':{'temperature':0,'num_ctx':8192,'num_predict':4096}}, timeout=150)
    if value.get('done_reason')=='length': raise ValueError('La traducción excedió el límite; se conserva el original completo.')
    translated=parse_fields(value.get('message',{}).get('content',''),list(range(len(texts))))
    # Validate all placeholders before changing any field.
    return tuple(restore_quantities(t,{k:protected[k] for k in keys}) for t,keys in zip(translated,expected))

def translate_texts(texts, source):
    from .translation import restore_numbers, polish_culinary, GLOSSARY
    output=list(texts)
    groups=[];group=[];size=0
    for i,text in enumerate(texts):
        if not text.strip(): continue
        # Fixed culinary names need no inference.
        exact=next((v for k,v in GLOSSARY[source].items() if k.lower()==text.strip().lower()), None)
        if exact is not None:
            output[i]=polish_culinary(text,exact);continue
        if len(text)>10000: raise ValueError('Un paso es demasiado largo para el traductor de calidad.')
        if group and (size+len(text)>6500 or len(group)>=40):groups.append(group);group=[];size=0
        group.append((i,text));size+=len(text)
    if group:groups.append(group)
    for group in groups:
        try:
            result=translate_group(tuple(t for _,t in group),source)
        except ValueError:
            if len(group)==1: raise
            # Retry complete individual fields, never splice an incomplete model output.
            result=tuple(translate_group((t,),source)[0] for _,t in group)
        for (i,original),translated in zip(group,result):
            output[i]=polish_culinary(original,restore_numbers(original,translated))
    return output
