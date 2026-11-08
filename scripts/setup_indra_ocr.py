"""Fetch the pinned Indra CPU model set and notices for offline packaging."""
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
REVISION = 'bd02167fdf2005a19962cc15188f8496a2c87d3b'
FILES = ('det.onnx', 'rec.onnx', 'order.onnx', 'orient.onnx', 'script.onnx',
         'rec_cjk.onnx', 'rec_rtl.onnx', 'rec_world.onnx', 'meta.json',
         'lm.npz', 'lm_cjk.npz', 'lm_world.npz', 'LICENSE', 'README.md')
DESTINATION = ROOT/'.tools/ocr/indra-v1.1.0'


def main():
    DESTINATION.mkdir(parents=True, exist_ok=True)
    def fetch(name):
        target = DESTINATION/name
        if not target.exists():
            request = urllib.request.Request(f'https://huggingface.co/datalab-to/indra-ocr/resolve/{REVISION}/{name}', headers={'User-Agent': 'Mesa Indra OCR build'})
            temporary = target.with_suffix(target.suffix+'.part')
            with urllib.request.urlopen(request, timeout=90) as source, temporary.open('wb') as output:
                while chunk := source.read(1024*1024):
                    output.write(chunk)
            temporary.replace(target)
        with target.open('rb') as stream:
            digest = hashlib.file_digest(stream, 'sha256').hexdigest()
        return {'path':name, 'bytes':target.stat().st_size, 'sha256':digest}
    with ThreadPoolExecutor(max_workers=3) as pool:
        files = list(pool.map(fetch, FILES))
    code_license = DESTINATION/'CODE-LICENSE.txt'
    if not code_license.exists():
        code_license.write_bytes(urllib.request.urlopen('https://raw.githubusercontent.com/datalab-to/indra/v1.1.2/LICENSE', timeout=30).read())
    manifest = {'engine':'indra-ocr', 'packageVersion':'1.1.2', 'modelRevision':REVISION,
                'modelTag':'v1.1.0', 'source':'https://github.com/datalab-to/indra',
                'models':'https://huggingface.co/datalab-to/indra-ocr', 'files':files,
                'weightsModified':False, 'mathModelsIncluded':False}
    (DESTINATION/'mesa-model-manifest.json').write_text(json.dumps(manifest, indent=2)+'\n', encoding='utf-8')
    print(json.dumps({'directory':str(DESTINATION), 'bytes':sum(x['bytes'] for x in files), 'files':len(files)}, indent=2))


if __name__ == '__main__':
    main()
