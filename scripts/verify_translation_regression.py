"""Synthetic authenticated API regression with actual bundled CPU models."""
import json
from pathlib import Path
import sys
import tempfile
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from fastapi.testclient import TestClient
from server import translation as tr,quality_translation as quality,translation_cache
from server.app import create_app


def main():
    out=ROOT/'output/implementation-DG-0033';out.mkdir(parents=True,exist_ok=True)
    # Explicitly select packaged OPUS, never connect to the usual Ollama worker.
    quality.available=lambda:False
    raw=tr.translate_batch(['2 Eier mischen.'],'de')[0]
    profile=Path(tempfile.mkdtemp(prefix='translation-',dir=out))
    translation_cache.PATH=profile/'translation-cache.sqlite'
    app=create_app(profile)
    api=TestClient(app)
    api.headers['Authorization']='Bearer '+json.loads((profile/'desktop-connection.json').read_text())['token']
    original={'title':'Test','language':'de','ingredients':['2 Eier'],'steps':['2 Eier mischen.'],'servings':2,'notes':''}
    modern=tr.restore_numbers
    tr.restore_numbers=lambda a,b,**kwargs:modern(a,b)
    before=api.post('/v1/translate-recipe',json={'recipe':original,'source':'de'})
    assert before.status_code==422
    tr.restore_numbers=modern
    results={}
    for source,text in {'de':'2 Eier mischen.','en':'Mix 2 eggs.','fr':'Mélanger 2 œufs.','it':'Mescolare 2 uova.','pt':'Misture 2 ovos.'}.items():
        recipe={**original,'language':source,'ingredients':[text],'steps':[text]}
        response=api.post('/v1/translate-recipe',json={'recipe':recipe,'source':source})
        assert response.status_code==200,response.text
        result=response.json()
        assert result['original']['steps']==[text] and '2' in result['steps'][0]
        results[source]={'status':response.status_code,'translatedSteps':result['steps'],'originalPreserved':True}
    assert not api.get('/v1/snapshot').json()['entities']
    unsupported=api.post('/v1/translate-recipe',json={'recipe':original,'source':'ja'})
    assert unsupported.status_code==422
    result={'provider':'Helsinki-NLP/opus-mt-de-es (original 2020-01-15 converted CPU int8)',
            'providerContract':'German de -> Spanish es; normalized SentencePiece tokens; local CTranslate2, no external translation API',
            'modelCard':'https://huggingface.co/Helsinki-NLP/opus-mt-de-es','syntheticOnly':True,'userRecipesSent':False,
            'rawGermanModelOutput':raw,'before':{'status':before.status_code,'detail':before.json()['detail']},'after':results,
            'unsupportedRejected':True,'noRecipePersisted':True,'profile':str(profile)}
    (out/'translation-regression.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(result,ensure_ascii=False))


if __name__=='__main__':main()
