from concurrent.futures import ThreadPoolExecutor
import sqlite3
import time
import pytest
import server.translation_cache as cache
import server.quality_translation as quality
from server.test_api import api

@pytest.fixture(autouse=True)
def isolated_cache(tmp_path,monkeypatch):
    monkeypatch.setattr(cache,'PATH',tmp_path/'translations.sqlite')

def test_translation_survives_memory_cache_reset_and_avoids_model_execution(monkeypatch):
    calls=[]
    monkeypatch.setattr(quality,'_translate_group',lambda texts,source,model:calls.append(texts) or ('Pan','2 huevos'))
    assert quality.translate_group(('Bread','2 eggs'),'en')==('Pan','2 huevos')
    monkeypatch.setattr(quality,'_translate_group',lambda *args:pytest.fail('Must reuse persisted translation after a restart'))
    assert quality.translate_group(('Bread','2 eggs'),'en')==('Pan','2 huevos')
    assert len(calls)==1

def test_cache_checks_quantities_source_and_model():
    texts=('2 eggs',)
    key=cache.key(texts,'en','model-a')
    cache.write(key,texts,('3 huevos',));assert cache.read(key,texts) is None
    cache.write(key,texts,('2 huevos',));assert cache.read(key,texts)==('2 huevos',)
    assert cache.read(cache.key(texts,'en','model-b'),texts) is None
    with sqlite3.connect(cache.PATH) as con:con.execute('UPDATE translations SET payload=?',('["10 huevos"]',))
    assert cache.read(key,texts) is None

def test_cache_is_bounded_and_keeps_no_photo_or_original_image_data(monkeypatch):
    monkeypatch.setattr(cache,'MAX_ENTRIES',2)
    for i in range(4):cache.write(str(i),('2 eggs',),('2 huevos',))
    with sqlite3.connect(cache.PATH) as con:
        rows=con.execute('SELECT payload FROM translations').fetchall()
        assert len(rows)==2 and all(row[0]=='["2 huevos"]' for row in rows)

def test_duplicate_requests_share_one_inference(monkeypatch):
    calls=[]
    def translate(texts,source,model):calls.append(texts);time.sleep(.03);return ('Pan',)
    monkeypatch.setattr(quality,'_translate_group',translate)
    with ThreadPoolExecutor(max_workers=2) as executor:
        futures=[executor.submit(quality.translate_group,('Bread',),'en') for _ in range(2)]
        assert [f.result() for f in futures]==[('Pan',),('Pan',)]
    assert len(calls)==1

def test_preparing_model_is_authenticated_and_sends_no_recipe(api,monkeypatch):
    calls=[]
    monkeypatch.setattr(quality,'available',lambda:True)
    monkeypatch.setattr(quality,'warm_model',lambda:calls.append('warm'))
    response=api.post('/v1/translation/warm')
    assert response.status_code==202 and calls==['warm']
    api.headers.clear();assert api.post('/v1/translation/warm').status_code==401

def test_warm_request_has_empty_prompt_and_cannot_block_busy_inference(monkeypatch):
    requests=[]
    monkeypatch.setattr(quality,'_last_warm',0)
    monkeypatch.setattr(quality,'request',lambda path,body,**kwargs:requests.append((path,body)) or {})
    quality.warm_model();assert requests[0][0]=='/api/generate' and requests[0][1]['prompt']==''
    monkeypatch.setattr(quality,'_last_warm',0)
    quality.INFERENCE_LOCK.acquire()
    try:quality.warm_model()
    finally:quality.INFERENCE_LOCK.release()
    assert len(requests)==1
