from concurrent.futures import ThreadPoolExecutor
import json
import time
import pytest
from server import translation as tr, translation_cache as cache, quality_translation as quality


@pytest.fixture(autouse=True)
def isolated(tmp_path,monkeypatch):
    monkeypatch.setattr(cache,'PATH',tmp_path/'translations.sqlite')
    monkeypatch.setattr(quality,'available',lambda:False)
    monkeypatch.setattr(tr,'model_identity',lambda source,target:source+'-'+target+'-model-a')


def test_fallback_cache_deduplicates_concurrent_calls_and_keeps_blank_notes(monkeypatch):
    calls=[]
    def infer(texts,source):
        calls.append((texts,source));time.sleep(.03)
        return [t.replace('eggs','huevos') for t in texts]
    monkeypatch.setattr(tr,'translate_batch',infer)
    texts=['2 eggs','']
    with ThreadPoolExecutor(max_workers=3) as pool:
        values=list(pool.map(lambda _:tr.translate_texts(texts,'en'),range(3)))
    assert values==[['2 huevos','']]*3 and len(calls)==1
    monkeypatch.setattr(tr,'translate_batch',lambda *a:pytest.fail('must reuse disk cache'))
    assert tr.translate_texts(texts,'en')==['2 huevos','']


def test_fallback_cache_invalidates_source_content_model_and_glossary(monkeypatch):
    calls=[]
    monkeypatch.setattr(tr,'translate_batch',lambda texts,source:calls.append((texts,source)) or texts)
    tr.translate_texts(['Synthetic 2'],'en');tr.translate_texts(['Synthetic 2'],'en')
    assert len(calls)==1
    tr.translate_texts(['Synthetic 3'],'en')
    tr.translate_texts(['Synthetic 2'],'de')
    monkeypatch.setattr(tr,'model_identity',lambda *a:'model-b')
    tr.translate_texts(['Synthetic 2'],'en')
    monkeypatch.setitem(tr.GLOSSARY,'en',{**tr.GLOSSARY['en'],'SYNTHETIC-TERM':'término'})
    tr.translate_texts(['Synthetic 2'],'en')
    assert len(calls)==5


def test_failed_quantity_validation_never_populates_cache(monkeypatch):
    monkeypatch.setattr(tr,'translate_batch',lambda *a:['3 huevos'])
    with pytest.raises(ValueError): tr.translate_texts(['2 eggs'],'en')
    monkeypatch.setattr(tr,'translate_batch',lambda *a:['2 huevos'])
    assert tr.translate_texts(['2 eggs'],'en')==['2 huevos']


def test_optional_provider_probe_is_coalesced_bounded_and_invalidates_config(tmp_path,monkeypatch):
    # Restore actual availability function overridden by the common fixture.
    # Function saved from module load below is independent of mock fixtures.
    monkeypatch.setattr(quality,'available',REAL_AVAILABLE)
    root=tmp_path/'worker';folder=root/'.tools/translation';folder.mkdir(parents=True)
    config=folder/'translategemma.json';config.write_text(json.dumps({'model':'translategemma:4b'}))
    monkeypatch.setattr(quality,'ROOT',root)
    monkeypatch.setattr(quality,'_availability_state',None)
    calls=[]
    def request(path,**kwargs):
        calls.append(kwargs['timeout']);time.sleep(.01);return {'models':[]}
    monkeypatch.setattr(quality,'request',request)
    with ThreadPoolExecutor(max_workers=3) as pool:
        assert list(pool.map(lambda _:quality.available(),range(3)))==[False]*3
    assert calls==[.25]
    config.write_text(json.dumps({'model':'translategemma:12b'}))
    assert quality.available() is False and calls==[.25,.25]


REAL_AVAILABLE=quality.available
