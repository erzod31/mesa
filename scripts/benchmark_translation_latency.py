"""Measure real authenticated recipe API, isolated data, synthetic text only."""
import argparse
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import tempfile
import time

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/implementation-DG-0033/performance'
FIXTURES={
    'short':{'title':'Eggs','ingredients':['2 eggs'],'steps':['Mix 2 eggs.'],'servings':2,'language':'en','notes':''},
    'usual':{'title':'Family vegetable rice','language':'en','servings':4,'notes':'Serve warm with the family.',
        'ingredients':['200 g rice','2 carrots','1 onion','2 tablespoons olive oil','500 ml vegetable broth','100 g peas','1 teaspoon salt'],
        'steps':['Wash the rice with cold water.','Peel the carrots and cut them into small pieces.','Chop the onion and heat the olive oil in a large pan.',
                 'Add the onion and carrots and cook for 5 minutes.','Add the rice and stir carefully.','Pour in 500 ml vegetable broth and bring to a boil.',
                 'Add the peas and cook over low heat for 20 minutes.','Remove from heat and let rest for 5 minutes.','Serve warm.']}}


def worker(args):
    profile=Path(args.profile);os.environ['RECETARIO_DATA']=str(profile)
    sys.path.insert(0,str(ROOT))
    from fastapi.testclient import TestClient
    from server import translation as tr,quality_translation as q,translation_cache
    from server.app import create_app
    translation_cache.PATH=profile/'translation-cache.sqlite'
    stats={}
    def add(name,seconds): stats[name]=stats.get(name,0)+seconds*1000
    available=q.available
    def measured_available():
        start=time.perf_counter()
        try: return available()
        finally:add('providerAvailabilityMs',time.perf_counter()-start)
    q.available=measured_available
    engine=tr.engine
    def measured_engine(*a):
        start=time.perf_counter()
        result=engine(*a)
        add('modelLookupLoadMs',time.perf_counter()-start)
        class Translator:
            def translate_batch(self,*a,**k):
                start=time.perf_counter()
                try:return result[0].translate_batch(*a,**k)
                finally:
                    add('inferenceMs',time.perf_counter()-start)
                    stats['inferenceCalls']=stats.get('inferenceCalls',0)+1
        return (Translator(),*result[1:])
    tr.engine=measured_engine
    lock=tr.LOCK
    class TimedLock:
        def __enter__(self):
            start=time.perf_counter();lock.acquire();add('queueWaitMs',time.perf_counter()-start)
        def __exit__(self,*a):lock.release()
    tr.LOCK=TimedLock()
    api=TestClient(create_app(profile))
    api.headers['Authorization']='Bearer '+json.loads((profile/'desktop-connection.json').read_text())['token']
    recipe=FIXTURES[args.fixture]
    rows=[]
    for index in range(4 if args.phase=='after' else 3):
        if index==3: recipe={**recipe,'notes':recipe['notes']+(' A new family dish.' if not args.reopen else ' A different family dish.')}
        stats={};start=time.perf_counter()
        response=api.post('/v1/translate-recipe',json={'recipe':recipe,'source':'en'})
        elapsed=(time.perf_counter()-start)*1000
        assert response.status_code==200,response.text
        result=response.json()
        for name in ('title','ingredients','steps','notes'):assert result['original'][name]==recipe[name]
        for a,b in zip(recipe['ingredients']+recipe['steps'],result['ingredients']+result['steps']):tr.restore_numbers(a,b)
        stats.update(totalApiMs=elapsed,iteration=index,status=response.status_code,fields=len(recipe['ingredients'])+len(recipe['steps'])+2,
                     characters=len(json.dumps(recipe,ensure_ascii=False)),originalPreserved=True,quantitiesValidated=True)
        stats['preparationValidationTransportMs']=max(0,elapsed-sum(stats.get(k,0) for k in ('providerAvailabilityMs','modelLookupLoadMs','inferenceMs','queueWaitMs')))
        rows.append(stats)
    print(json.dumps({'fixture':args.fixture,'restartWithExistingCache':args.reopen,'measurements':rows}))


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--phase',choices=['before','after'])
    parser.add_argument('--worker',action='store_true')
    parser.add_argument('--fixture',choices=FIXTURES)
    parser.add_argument('--profile')
    parser.add_argument('--reopen',action='store_true')
    args=parser.parse_args()
    if args.worker: return worker(args)
    OUT.mkdir(parents=True,exist_ok=True)
    rows=[]
    for fixture in FIXTURES:
        profile=tempfile.mkdtemp(prefix=args.phase+'-'+fixture+'-',dir=OUT)
        for reopen in (False,True):
            command=[sys.executable,__file__,'--worker','--phase',args.phase,'--fixture',fixture,'--profile',profile]
            if reopen:command.append('--reopen')
            value=json.loads(subprocess.check_output(command,cwd=ROOT,text=True,encoding='utf-8',timeout=90))
            rows.append(value);print(json.dumps(value),flush=True)
    result={'phase':args.phase,'environment':{'os':platform.platform(),'cpu':platform.processor(),'logicalCpus':os.cpu_count(),'python':platform.python_version(),'engine':'CPU int8 OPUS-MT, existing automatic quality-provider detection; no service restart'},
            'scope':'Authenticated in-process HTTP API via TestClient; includes serialization/auth/validation and actual inference, excludes physical Android/network latency and widget rendering.',
            'syntheticOnly':True,'realUserData':False,'results':rows}
    (OUT/(args.phase+'.json')).write_text(json.dumps(result,indent=2),encoding='utf-8')


if __name__=='__main__':main()
