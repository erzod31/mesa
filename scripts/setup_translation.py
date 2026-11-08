"""Install bounded Argos model data inside this project; no cloud translation API."""
import hashlib
import json
from pathlib import Path
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / '.tools' / 'translation'
PAIRS = [('en','es'), ('fr','en'), ('it','en'), ('de','en'), ('pt','en')]

def main():
    DEST.mkdir(parents=True, exist_ok=True)
    # Official development index points to the authors' immutable public model mirror.
    with urllib.request.urlopen('https://raw.githubusercontent.com/argosopentech/argospm-index-dev/main/index.json', timeout=40) as response:
        index = json.loads(response.read(2_000_000))
    installed = []
    for source, target in PAIRS:
        folder = DEST / f'{source}-{target}'
        if not all((folder / name).is_file() for name in ('model/model.bin','sentencepiece.model','metadata.json','download.json')):
            package = next(p for p in index if p.get('from_code')==source and p.get('to_code')==target)
            url = next(u for u in package['links'] if u.startswith('https://github.com/uav4geo/LibreTranslate-Models/raw/'))
            archive = DEST / f'{source}-{target}.download'
            print(f'Descargando modelo {source} → {target}', flush=True)
            digest = hashlib.sha256()
            size = 0
            with urllib.request.urlopen(url, timeout=90) as response, archive.open('wb') as out:
                while block := response.read(1024*1024):
                    size += len(block)
                    if size > 350_000_000: raise ValueError('Modelo demasiado grande.')
                    digest.update(block); out.write(block)
            with zipfile.ZipFile(archive) as data:
                members = data.infolist()
                if sum(m.file_size for m in members) > 750_000_000: raise ValueError('Paquete demasiado grande.')
                prefix = Path(next(m.filename for m in members if m.filename.endswith('/metadata.json'))).parent
                for member in members:
                    item = Path(member.filename)
                    if member.is_dir(): continue
                    relative = item.relative_to(prefix)
                    # Sentence splitting is performed locally; no Stanza/Torch runtime needed.
                    if relative.parts[0] not in ('model','sentencepiece.model','metadata.json','README','README.md','LICENSE','LICENSE.txt'): continue
                    output = (folder / relative).resolve()
                    if not output.is_relative_to(folder.resolve()): raise ValueError('Ruta de paquete incorrecta.')
                    output.parent.mkdir(parents=True, exist_ok=True)
                    with data.open(member) as inp, output.open('wb') as out:
                        while block := inp.read(1024*1024): out.write(block)
            (folder/'download.json').write_text(json.dumps({'url':url,'sha256':digest.hexdigest(),'bytes':size,'package_version':package['package_version']},indent=2),encoding='utf-8')
            archive.unlink()
        if not (folder/'model/model.bin').is_file() or not (folder/'sentencepiece.model').is_file(): raise ValueError('Modelo incompleto.')
        installed.append({'from':source,'to':target,'folder':str(folder.relative_to(ROOT))})
        print(f'Listo: {source} → {target}',flush=True)
    (ROOT/'output/translation-models-installed.json').write_text(json.dumps(installed,indent=2),encoding='utf-8')

if __name__=='__main__': main()
