"""Local culinary translation; immutable originals and verified quantities."""
from copy import deepcopy
from fractions import Fraction
from functools import lru_cache
import json
import hashlib
from importlib.metadata import version as package_version
from pathlib import Path
import re
from threading import BoundedSemaphore

PROJECT = Path(__file__).resolve().parents[1]
ROOT = PROJECT / '.tools/translation'
SUPPORTED = {'en', 'fr', 'it', 'de', 'pt'}
REVISION = 5
LOCK = BoundedSemaphore(1)
FLIGHT_LOCK = BoundedSemaphore(1)
NUMBER = re.compile(r'\d+(?:[.,]\d+)?(?:\s*[/⁄]\s*\d+)?|[½¼¾⅓⅔⅛⅜⅝⅞]')
# OPUS models mangle digit ranges ("30–40" -> "30,540"): normalize the dash to a
# comma before translating; the model preserves "30, 40" in every language.
RANGE = re.compile(r'(?<=\d)\s*[–—−\-]\s*(?=\d)')
FRACTIONS = dict(zip('½¼¾⅓⅔⅛⅜⅝⅞', ['1/2','1/4','3/4','1/3','2/3','1/8','3/8','5/8','7/8']))
# OPUS de-es sometimes spells small integer quantities (2 -> dos). Accept
# exact lexical equivalents only in the local fallback, then restore digits.
# Articles un/una and compound/fractional number words remain fail-closed.
CARDINALS = dict(zip('dos tres cuatro cinco seis siete ocho nueve diez once doce trece catorce quince dieciséis diecisiete dieciocho diecinueve veinte'.split(), range(2, 21)))
WORD_NUMBER = re.compile(r'\b(?:' + '|'.join(CARDINALS) + r'|cero|un|uno|una|veinti\w+|treinta|cuarenta|cincuenta|sesenta|setenta|ochenta|noventa|cien\w*|doscientos|trescientos|mil\w*|medio|media|tercio|cuarto)\b', re.I)
GLOSSARY = json.loads((PROJECT / 'client/assets/translation/culinary-glossary.json').read_text(encoding='utf-8'))
LETTERS = 'A-Za-zÀ-ÖØ-öø-ÿ'

def number_value(value):
    try: return Fraction(FRACTIONS.get(value, value).replace(',', '.').replace('⁄', '/').replace(' ', ''))
    except ZeroDivisionError as exc: raise ValueError('La receta contiene una fracción no válida.') from exc

def restore_numbers(original, translated, *, allow_words=False):
    before, after = list(NUMBER.finditer(original)), list(NUMBER.finditer(translated))
    if allow_words and len(after) < len(before):
        words = list(WORD_NUMBER.finditer(translated))
        # Only exact cardinals 2-20 count; compound numbers, fractions and
        # ambiguous articles are never guessed. The candidate count and value
        # equality below guarantee the repair is exact, so conjunctions such as
        # "harina y tres huevos" are safe.
        if all(m[0].lower() in CARDINALS for m in words):
            candidates = sorted([*after, *words], key=lambda m: m.start())
            values = [CARDINALS[m[0].lower()] if m in words else number_value(m[0]) for m in candidates]
            if len(candidates) == len(before) and values == [number_value(m[0]) for m in before]:
                for a, b in reversed(list(zip(before, candidates))):
                    translated = translated[:b.start()] + a[0] + translated[b.end():]
                after = list(NUMBER.finditer(translated))
    if len(before) != len(after) or any(number_value(a[0]) != number_value(b[0]) for a, b in zip(before, after)):
        raise ValueError('La traducción alteró una cantidad, temperatura o tiempo. Se conserva el original.')
    for a, b in reversed(list(zip(before, after))):
        translated = translated[:b.start()] + a[0] + translated[b.end():]
    return translated

def text_parts(text, source):
    """Keep reviewed culinary phrases intact; never split a sentence at a number."""
    terms = GLOSSARY[source]
    pattern = re.compile(f'(?<![{LETTERS}])(' + '|'.join(re.escape(t) for t in sorted(terms, key=len, reverse=True)) + f')(?![{LETTERS}])', re.I)
    lookup = {key.lower(): value for key, value in terms.items()}
    start = 0
    for match in pattern.finditer(text):
        yield from sentence_parts(text[start:match.start()])
        yield True, lookup[match[0].lower()]
        start = match.end()
    yield from sentence_parts(text[start:])

def sentence_parts(text):
    start = 0
    for boundary in re.finditer(r'\n+|(?<=[.!?])\s+(?=[A-ZÀ-ÖØ-Þ])', text):
        chunk = text[start:boundary.start()]
        if chunk: yield from bounded_parts(chunk)
        yield True, boundary[0]
        start = boundary.end()
    if start < len(text): yield from bounded_parts(text[start:])

def bounded_parts(text):
    while len(text) > 1800:
        cut = text.rfind(' ', 0, 1801)
        if cut < 1: raise ValueError('Un texto sin separadores es demasiado largo para traducir.')
        yield False, text[:cut]
        yield True, ' '
        text = text[cut+1:]
    if text: yield False, text

def model_folder(source,target):
    direct=ROOT/f'opus-{source}-{target}'
    return direct if (direct/'download.json').is_file() else ROOT/f'{source}-{target}'


@lru_cache(maxsize=16)
def _model_digest(files):
    # Full weights/tokenizer hashes are calculated once per file generation.
    # The generation is part of the memo key, and loaded engines use the digest
    # too: a changed model cannot reuse another model's cached output/instance.
    digest=hashlib.sha256()
    for name,_,_ in files:
        with Path(name).open('rb') as stream:
            digest.update(hashlib.file_digest(stream,'sha256').digest())
    return digest.hexdigest()


def model_identity(source,target):
    folder=model_folder(source,target)
    paths=[p for p in sorted(folder.rglob('*')) if p.is_file() and (p.suffix in ('.bin','.spm','.model','.json') or 'vocabulary' in p.name)]
    if not paths: raise ValueError(f'La traducción local {source} → {target} no está disponible en esta copia de Mesa. Actualiza Mesa o conserva el original.')
    return _model_digest(tuple((str(p),p.stat().st_size,p.stat().st_mtime_ns) for p in paths))


def engine(source,target):
    return _engine(source,target,model_identity(source,target))


@lru_cache(maxsize=5)
def _engine(source, target, identity):
    import ctranslate2
    import sentencepiece
    direct = ROOT / f'opus-{source}-{target}'
    if (direct / 'download.json').is_file():
        return (ctranslate2.Translator(str(direct/'model'), device='cpu', compute_type='int8', intra_threads=2),
                sentencepiece.SentencePieceProcessor(model_file=str(direct/'source.spm')),
                sentencepiece.SentencePieceProcessor(model_file=str(direct/'target.spm')), '')
    folder = ROOT / f'{source}-{target}'
    if not (folder / 'model/model.bin').is_file():
        raise ValueError(f'La traducción local {source} → {target} no está disponible en esta copia de Mesa. Actualiza Mesa o conserva la receta en su idioma original.')
    metadata = json.loads((folder/'metadata.json').read_text(encoding='utf-8'))
    tokenizer = sentencepiece.SentencePieceProcessor(model_file=str(folder/'sentencepiece.model'))
    return (ctranslate2.Translator(str(folder/'model'), device='cpu', compute_type='int8', intra_threads=2),
            tokenizer, tokenizer, metadata.get('target_prefix', ''))

def translate_batch(texts, source):
    if not texts: return []
    direct = (ROOT / f'opus-{source}-es/download.json').is_file()
    chain = [(source, 'es')] if direct or source == 'en' else [(source, 'en'), ('en', 'es')]
    with LOCK:
        for language, target in chain:
            translator, encoder, decoder, prefix = engine(language, target)
            tokens = [encoder.encode(t, out_type=str) for t in texts]
            if any(len(t) > 900 for t in tokens): raise ValueError('Un texto excede el límite; no se ha truncado.')
            results = translator.translate_batch(tokens, target_prefix=[[prefix]]*len(tokens) if prefix else None,
                beam_size=4, max_batch_size=512, batch_type='tokens', max_input_length=0,
                max_decoding_length=1024, replace_unknowns=True)
            if len(results) != len(texts) or any(len(r.hypotheses[0]) >= 1024 for r in results):
                raise ValueError('La traducción está incompleta; se conserva el original.')
            texts = [decoder.decode(r.hypotheses[0]).removeprefix(prefix).strip() for r in results]
            if any(not t for t in texts): raise ValueError('La traducción omitió texto; se conserva el original.')
    return texts

def translate_texts(texts, source):
    if source == 'es': return list(texts)
    if source not in SUPPORTED: raise ValueError('Idioma no compatible. Mesa traduce inglés, francés, italiano, alemán y portugués al español; se conserva el original.')
    if len(texts) > 1100 or sum(len(t) for t in texts) > 120000: raise ValueError('La receta es demasiado larga.')
    from . import quality_translation
    if quality_translation.available():
        try:
            return quality_translation.translate_texts(texts, source)
        except (ValueError, RuntimeError, OSError):
            # The dedicated worker rejected the output (incomplete markers,
            # altered quantities or timeout): use the local OPUS engine as
            # backup instead of failing the translation.
            pass
    from . import translation_cache
    direct=(ROOT/f'opus-{source}-es/download.json').is_file()
    route=[(source,'es')] if direct or source=='en' else [(source,'en'),('en','es')]
    identities=[model_identity(a,b) for a,b in route]
    implementation=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    cache_key=hashlib.sha256(json.dumps(['opus-v1',source,'es',identities,implementation,GLOSSARY[source],package_version('ctranslate2'),texts],ensure_ascii=False,sort_keys=True).encode()).hexdigest()
    cached=translation_cache.read(cache_key,texts)
    if cached is not None:return list(cached)
    # Deduplicate simultaneous misses. Another caller may have written the
    # identical valid recipe while this request waited; never infer it twice.
    with FLIGHT_LOCK:
        cached=translation_cache.read(cache_key,texts)
        if cached is not None:return list(cached)
        output=_translate_local(texts,source)
        translation_cache.write(cache_key,texts,output)
        return output


def _translate_local(texts,source):
    fragments, layouts = [], []
    for text in texts:
        layout = []
        for fixed, part in text_parts(RANGE.sub(', ', text), source):
            if fixed or not re.search(f'[{LETTERS}]', part):
                layout.append((None, part)); continue
            leading, trailing = re.match(r'^\s*', part)[0], re.search(r'\s*$', part)[0]
            layout.append((len(fragments), (leading, trailing)))
            fragments.append(part.strip())
        layouts.append(layout)
    if len(fragments) > 4000: raise ValueError('La receta es demasiado larga.')
    translated = translate_batch(fragments, source)
    output = []
    for text, layout in zip(texts, layouts):
        value = ''.join(part if index is None else part[0] + translated[index] + part[1] for index, part in layout)
        output.append(polish_culinary(text, restore_numbers(text, value, allow_words=True)))
    return output

def polish_culinary(original, value):
    value = re.sub(r'\b(tazas?|cucharadas?|cucharaditas?|onzas?|libras?)\s+(?=(?:harina|leche|azúcar|mantequilla|aceite|agua|nata|sal)\b)', r'\1 de ', value, flags=re.I)
    value = re.sub(r'(?<=[a-zà-öø-ÿ0-9])\s+(De|La|Las|El|Los|Con|En|Durante|Hasta|Para)\b', lambda m: m[0].lower(), value)
    if original[:1].isupper() and value: value = value[:1].upper() + value[1:]
    return value

def translate_recipe(recipe, source, *, force=False):
    if recipe.get('translation', {}).get('target_language') == 'es' and not force: return deepcopy(recipe)
    saved = recipe.get('original')
    base = saved if force and isinstance(saved, dict) else recipe
    source = base.get('language', source).lower().split('-')[0].split('_')[0]
    if source == 'es': return deepcopy(recipe)
    original = {key: deepcopy(base.get(key, '' if key in ('title','notes') else [])) for key in ('title','ingredients','steps','notes')}
    notes_es = base.get('notes_language') == 'es' or (
        str(recipe.get('origin', {}).get('provider', '')).startswith('wiki-') and
        original['notes'].startswith(('Comprueba el rendimiento', 'Rendimiento no declarado:', 'Raciones declaradas por la fuente:')))
    texts = [original['title'], *original['ingredients'], *original['steps'], '' if notes_es else original['notes']]
    translated = translate_texts(texts, source)
    if len(translated) != len(texts): raise ValueError('La traducción está incompleta.')
    if len(translated[0]) > 250: raise ValueError('El título traducido es demasiado largo; se conserva el original.')
    result = deepcopy(recipe)
    count, steps = len(original['ingredients']), len(original['steps'])
    result.update(language='es', title=translated[0], ingredients=translated[1:1+count],
                  steps=translated[1+count:1+count+steps], notes=original['notes'] if notes_es else translated[-1])
    result['original'] = {**original, 'language': source, **({'notes_language': 'es'} if notes_es else {})}
    from . import quality_translation
    backend = f'TranslateGemma {quality_translation.selected_model().split(":")[1].upper()} local' if quality_translation.available() else 'OPUS-MT / Argos local + glosario culinario'
    result['translation'] = {'source_language': source, 'target_language': 'es', 'engine': backend, 'revision': REVISION, 'review_required': True}
    result['notes_language'] = 'es'
    if isinstance(result.get('origin'), dict): result['origin']['modified'] = True
    return result
