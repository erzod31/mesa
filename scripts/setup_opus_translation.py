"""Install direct OPUS-MT models from Helsinki-NLP's published original weights.

No torch or executable pickle is needed: convert Marian npz weights to CPU int8.
Old Argos models remain available as a fallback. Recipe text never leaves Mesa.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / '.tools' / 'translation'
MODELS = {
    'en': ('Tatoeba-MT-models/eng-spa/opusTCv20210807+bt_transformer-big_2022-03-13.zip', 'Helsinki-NLP/opus-mt-tc-big-en-es'),
    'fr': ('OPUS-MT-models/fr-es/opus-2020-01-09.zip', 'Helsinki-NLP/opus-mt-fr-es'),
    'it': ('OPUS-MT-models/it-es/opus-2020-01-26.zip', 'Helsinki-NLP/opus-mt-it-es'),
    'de': ('OPUS-MT-models/de-es/opus-2020-01-15.zip', 'Helsinki-NLP/opus-mt-de-es'),
}

def install(source):
    from ctranslate2.converters import OpusMTConverter
    path, author = MODELS[source]
    folder = DEST / f'opus-{source}-es'
    if all((folder / name).is_file() for name in ('model/model.bin', 'source.spm', 'target.spm', 'download.json')):
        print(f'Listo: {source} → es (directo)', flush=True)
        return
    url = 'https://object.pouta.csc.fi/' + path
    archive = DEST / f'opus-{source}-es.zip'
    staging = DEST / f'opus-{source}-es-staging'
    staging.mkdir(parents=True, exist_ok=True)
    digest = hashlib.sha256()
    size = 0
    print(f'Descargando OPUS-MT {source} → es', flush=True)
    with urllib.request.urlopen(url, timeout=90) as response, archive.open('wb') as output:
        while block := response.read(1024 * 1024):
            size += len(block)
            if size > 1_000_000_000: raise ValueError('Modelo demasiado grande.')
            digest.update(block); output.write(block)
    with zipfile.ZipFile(archive) as data:
        if sum(m.file_size for m in data.infolist()) > 1_600_000_000:
            raise ValueError('Paquete demasiado grande.')
        for member in data.infolist():
            item = Path(member.filename)
            if member.is_dir(): continue
            target = (staging / item).resolve()
            if not target.is_relative_to(staging.resolve()): raise ValueError('Ruta de paquete incorrecta.')
            if not (item.suffix in ('.npz', '.spm', '.yml') or item.name.lower().startswith(('license', 'readme'))): continue
            target.parent.mkdir(parents=True, exist_ok=True)
            with data.open(member) as inp, target.open('wb') as out:
                shutil.copyfileobj(inp, out)
    decoder = next(staging.rglob('decoder.yml'))
    model_dir = decoder.parent
    folder.mkdir(parents=True, exist_ok=True)
    OpusMTConverter(str(model_dir)).convert(str(folder / 'model'), quantization='int8', force=True)
    for name in ('source.spm', 'target.spm'):
        shutil.copyfile(model_dir / name, folder / name)
    (folder / 'download.json').write_text(json.dumps({
        'url': url, 'sha256': digest.hexdigest(), 'bytes': size,
        'author': author, 'model_card': 'https://huggingface.co/' + author,
        'original_weights_license': 'CC BY 4.0 (OPUS-MT)',
        'converted_with': 'CTranslate2 4.8.2, CPU int8',
    }, indent=2), encoding='utf-8')
    # Both resolved paths were created explicitly within the translation directory.
    if not staging.resolve().is_relative_to(DEST.resolve()): raise ValueError('Ruta incorrecta.')
    shutil.rmtree(staging)
    archive.unlink()
    print(f'Instalado: {source} → es (directo)', flush=True)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', choices=MODELS)
    args = parser.parse_args()
    DEST.mkdir(parents=True, exist_ok=True)
    for source in ([args.source] if args.source else MODELS): install(source)

if __name__ == '__main__': main()
