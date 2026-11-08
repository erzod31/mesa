"""Real candidate files, isolated loopback HTTP, activation/rollback; no setup."""
from datetime import datetime,timezone
import hashlib
from http.server import ThreadingHTTPServer
import json
from pathlib import Path
import shutil
import sys
import threading
import urllib.request
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from scripts import serve_apk,update_publication as publication


def main():
    root=ROOT/'output/implementation-DG-0033'
    prepared=root/'publication'
    lab=root/datetime.now(timezone.utc).strftime('publication-lab-%Y%m%dT%H%M%SZ')
    target=lab/'served';target.mkdir(parents=True)
    plan=json.loads((prepared/'publication.json').read_text())
    for name in publication.MUTABLE:
        if plan['before'][name]:shutil.copyfile(prepared/'rollback'/name,target/name)
    qa=lab/'bundle'
    publication.prepare(root/'channel',root/'release',qa,target)
    activation=publication.activate(qa)
    serve_apk.DIST=target
    class Quiet(serve_apk.Download):
        def log_message(self,*args):pass
    server=ThreadingHTTPServer(('127.0.0.1',0),Quiet)
    thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
    opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
    rows=[]
    try:
        base=f'http://127.0.0.1:{server.server_port}'
        for endpoint in ('windows-update.json','update.json'):
            with opener.open(base+'/descargar/'+endpoint,timeout=10) as response:
                data=json.load(response)
            release=data.get('release',data)
            path=release.get('installer_path',release.get('apk_path'))
            h=hashlib.sha256();size=0
            with opener.open(base+path,timeout=15) as response:
                while chunk:=response.read(1024*1024):h.update(chunk);size+=len(chunk)
            assert size==release['size'] and h.hexdigest()==release['sha256']
            rows.append({'endpoint':endpoint,'code':release['version_code'],'bytes':size,'sha256':h.hexdigest(),'completeDownloadVerified':True})
    finally:
        server.shutdown();server.server_close();thread.join(timeout=5)
    rollback=publication.rollback(qa)
    assert all(publication.state(target/name)==plan['before'][name] for name in publication.MUTABLE)
    # Ensure preparation/QA did not alter a single reviewed production target.
    production=Path(plan['target'])
    assert all(publication.state(production/name)==expected for name,expected in plan['before'].items())
    result={'taskId':'DG-0033','scope':'real candidate files, staging, fake serving directory and ephemeral loopback HTTP; no native installer',
            'activation':activation['activated'],'downloads':rows,'rollback':rollback,'priorOffersAndAliasRestored':True,'productionUntouched':True,'usualServiceRestarted':False,'realInstallerExecuted':False,'lgRealDeviceTouched':False,'lab':str(lab)}
    (root/'publication-verification.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps(result,indent=2))


if __name__=='__main__':main()
