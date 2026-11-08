"""Reviewed text and a bounded, transient reader for licensed PDF photographs."""
from functools import lru_cache
from hashlib import sha256
from io import BytesIO
import json
from pathlib import Path
from threading import Lock, Timer, BoundedSemaphore
from time import monotonic
import unicodedata

from pypdf import PdfReader
from .fetcher import fetch_document

DIRECTORY = Path(__file__).with_name('licensed_collections')
PROVIDERS = frozenset({'book-polaca'})
_lock = Lock()
_slots = BoundedSemaphore(8)
_document = None
_expiry = None


def _expire_document():
    global _document
    with _lock:
        _document = None


@lru_cache(maxsize=2)
def collection(provider):
    if provider not in PROVIDERS:
        raise ValueError('Recetario desconocido.')
    return json.loads((DIRECTORY / f'{provider}.json').read_text(encoding='utf-8'))


def normalized(value):
    return ''.join(c for c in unicodedata.normalize('NFD', value.casefold()) if unicodedata.category(c) != 'Mn')


def catalog(provider, query='', cursor=None):
    if cursor is not None:
        raise ValueError('Esta selección se muestra completa en una sola página.')
    rows = collection(provider)['recipes']
    terms = normalized(query).split()
    rows = [r for r in rows if all(t in normalized(r['title']+' '+' '.join(r['ingredients'])) for t in terms)]
    return {'items':[{'id':r['origin']['id'], 'title':r['title'], 'provider':provider,
                      'image':r['photos'][0]['url']} for r in rows], 'cursor':None,
            'notice':'Texto disponible sin conexión. Las fotos del PDF necesitan el ordenador conectado; no se guardan en disco.'}


def recipe(provider, identifier):
    for row in collection(provider)['recipes']:
        if str(identifier) in {row['origin']['id'], row['source']}:
            return json.loads(json.dumps(row))
    raise ValueError('Esta página no pertenece a la selección revisada.')


def photo(provider, page):
    """No arbitrary URL/page, no disk cache and at most one PDF in RAM for 5 min."""
    global _document, _expiry
    doc = collection(provider)['document']
    if page not in doc['photo_pages']:
        raise ValueError('Esta página no es una foto revisada.')
    if not _slots.acquire(blocking=False):
        raise ValueError('El lector de fotos está ocupado; reintenta en unos segundos.')
    if not _lock.acquire(timeout=50):
        _slots.release()
        raise ValueError('El lector de fotos está ocupado; reintenta en unos segundos.')
    try:
        now = monotonic()
        if _document and now - _document[2] > 300:
            _document = None
        if not _document or _document[0] != provider:
            # Release the previous PDF before fetching another large document.
            _document = None
            raw, _ = fetch_document(doc['url'])
            if sha256(raw).hexdigest() != doc['sha256']:
                raise ValueError('El documento ha cambiado; la foto necesita una nueva revisión.')
            _document = (provider, raw, now)
            if _expiry:_expiry.cancel()
            _expiry = Timer(300, _expire_document)
            _expiry.daemon = True
            _expiry.start()
        reader = PdfReader(BytesIO(_document[1]), strict=True)
        images = reader.pages[page-1].images
        candidates = []
        for name in images.keys():
            item = images[name]
            image = item.image
            if image.width * image.height > 40_000_000:
                raise ValueError('La foto supera el tamaño permitido.')
            candidates.append((image.width * image.height, image))
        if not candidates:
            raise ValueError('El documento no contiene la foto revisada.')
        image = max(candidates, key=lambda item:item[0])[1]
        image.thumbnail((1600,1600))
        output = BytesIO()
        image.convert('RGB').save(output, format='JPEG', quality=85)
        result = output.getvalue()
        if len(result) > 10_000_000:
            raise ValueError('La foto supera el tamaño permitido.')
        return result
    finally:
        _lock.release()
        _slots.release()
