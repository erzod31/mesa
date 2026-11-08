"""Build the Windows installer without publishing or overwriting old releases."""
from pathlib import Path
import argparse
import hashlib
import importlib.metadata
import json
import os
import shutil
import subprocess
import sys
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.release_signing import sign_android
TOOLS = ROOT / '.tools/windows-installer'
MODELS = ('opus-en-es', 'opus-fr-es', 'opus-it-es', 'opus-de-es', 'pt-en')


def digest(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def nsis_quote(value):
    return str(value).replace('$', '$$').replace('"', '$\\"')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--client-dir', type=Path, required=True)
    parser.add_argument('--android-apk', type=Path, help='Bundle a locally built APK without changing the published update feed.')
    parser.add_argument('--skip-freeze', action='store_true')
    parser.add_argument('--freeze-only', action='store_true')
    parser.add_argument('--output-dir', type=Path, help='Directory for candidate artifacts; defaults to dist.')
    parser.add_argument('--candidate', action='store_true', help='Write an index beside the candidate, never advance dist/windows-installer.json.')
    args = parser.parse_args()
    version = next(line.split(':', 1)[1].strip() for line in (ROOT/'client/pubspec.yaml').read_text().splitlines() if line.startswith('version:'))
    semantic, code = version.split('+')
    slug = version.replace('+', '-')
    work = ROOT/f'output/windows-installer-{slug}'
    work.mkdir(parents=True, exist_ok=True)
    stage = work/'freeze/Mesa'
    destination=args.output_dir.resolve() if args.output_dir else ROOT/'dist'
    destination.mkdir(parents=True,exist_ok=True)
    installer = destination/f'Mesa-Setup-{slug}-x64.exe'
    if installer.exists():
        index = 2
        while (destination/f'Mesa-Setup-{slug}-x64-{index}.exe').exists():
            index += 1
        installer = destination/f'Mesa-Setup-{slug}-x64-{index}.exe'
    runtime_sites = ROOT/'.venv/Lib/site-packages'
    build_sites = TOOLS/'build-venv/Lib/site-packages'
    env = dict(os.environ, PYTHONPATH=os.pathsep.join((str(build_sites), str(runtime_sites), str(ROOT))))
    # Only inference modules are needed. Model converters require unrelated ML
    # development frameworks and are deliberately excluded from the runtime.
    if not args.skip_freeze:
        command = [sys.executable, '-m', 'PyInstaller', '--noconfirm', '--onedir', '--windowed', '--name', 'Mesa', '--icon', str(ROOT/'client/windows/runner/resources/app_icon.ico'), '--distpath', str(work/'freeze'), '--workpath', str(work/'pyinstaller'), '--specpath', str(work), '--paths', str(ROOT), '--paths', str(runtime_sites), '--collect-binaries', 'ctranslate2', '--copy-metadata', 'ctranslate2', '--hidden-import', 'ctranslate2', '--hidden-import', 'sentencepiece', '--hidden-import', 'uvicorn.loops.asyncio', '--hidden-import', 'uvicorn.protocols.http.h11_impl', '--hidden-import', 'uvicorn.lifespan.on']
        for excluded in ('torch', 'tensorflow', 'transformers', 'ctranslate2.converters', 'ctranslate2.specs', 'pytest', 'matplotlib', 'pandas', 'scipy', 'IPython', 'tkinter'):
            command += ['--exclude-module', excluded]
        ocr_models = ROOT/'.tools/ocr/indra-v1.1.0'
        ocr_manifest = json.loads((ocr_models/'mesa-model-manifest.json').read_text(encoding='utf-8'))
        for item in ocr_manifest['files']:
            if digest(ocr_models/item['path']) != item['sha256']:
                raise ValueError('Los modelos Indra OCR no coinciden con su manifiesto.')
        command += ['--collect-all', 'indra_ocr', '--collect-binaries', 'onnxruntime',
                    '--collect-data', 'onnxruntime', '--collect-all', 'pypdfium2_raw',
                    '--hidden-import', 'cv2', '--hidden-import', 'pypdfium2',
                    '--add-data', f'{ocr_models};.tools/ocr/indra-v1.1.0']
        for source, target in ((ROOT/'server', 'server'), (ROOT/'client/assets/translation', 'client/assets/translation')):
            command += ['--add-data', f'{source};{target}']
        for model in MODELS:
            source = ROOT/'.tools/translation'/model
            if not source.is_dir():
                raise FileNotFoundError(source)
            command += ['--add-data', f'{source};.tools/translation/{model}']
        command += [str(ROOT/'scripts/windows_launcher.py')]
        (work/'freeze-command.json').write_text(json.dumps(command, ensure_ascii=False, indent=2), encoding='utf-8')
        subprocess.run(command, cwd=ROOT, env=env, check=True)
        # A separate minimal one-file process survives replacement of the main
        # installation. QA builds it but never executes its real handoff.
        helper_command=[sys.executable,'-m','PyInstaller','--noconfirm','--onefile','--windowed',
            '--name','MesaUpdateHelper','--icon',str(ROOT/'client/windows/runner/resources/app_icon.ico'),
            '--distpath',str(work/'helper'),'--workpath',str(work/'helper-build'),'--specpath',str(work),
            '--paths',str(ROOT),'--paths',str(runtime_sites),
            '--add-data',f'{ROOT / "server/windows_update_key.pub"};server',
            str(ROOT/'scripts/windows_update_helper.py')]
        (work/'helper-freeze-command.json').write_text(json.dumps(helper_command,ensure_ascii=False,indent=2),encoding='utf-8')
        subprocess.run(helper_command,cwd=ROOT,env=env,check=True)
        shutil.copy2(work/'helper/MesaUpdateHelper.exe',stage/'MesaUpdateHelper.exe')
    if args.freeze_only:
        print(f'Runtime preparado: {stage}')
        return
    client = args.client_dir.resolve()
    if not (client/'mesa.exe').is_file():
        raise FileNotFoundError(client/'mesa.exe')
    if not (stage/'MesaUpdateHelper.exe').is_file():
        raise FileNotFoundError('Falta el asistente de actualización Windows incluido.')
    # importlib.metadata identifies the translation runtime in persisted cache
    # keys. Include it also when reusing a previously frozen staging directory.
    distribution=importlib.metadata.distribution('ctranslate2')
    metadata_dir=next(file.parts[0] for file in distribution.files if file.parts[0].endswith('.dist-info'))
    shutil.copytree(distribution.locate_file(metadata_dir),stage/'_internal'/metadata_dir,dirs_exist_ok=True)
    shutil.copytree(client, stage/'app', dirs_exist_ok=True)
    # App-local CRT avoids requiring elevation or an external runtime install.
    crt_root = Path(r'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Redist\MSVC')
    candidates = sorted(crt_root.glob('*/x64/Microsoft.VC143.CRT'), reverse=True)
    if not candidates:
        raise FileNotFoundError('Falta el runtime redistribuible Visual C++ x64.')
    for dll in candidates[0].glob('*.dll'):
        for target in (stage, stage/'app', stage/'_internal'):
            shutil.copy2(dll, target/dll.name)
    updates = stage/'updates'
    updates.mkdir(exist_ok=True)
    manifest = json.loads((ROOT/'dist/android-update.json').read_text(encoding='utf-8-sig'))
    apk = args.android_apk.resolve() if args.android_apk else ROOT/'dist'/Path(manifest['apk_path']).name
    if args.android_apk:
        manifest.update(version=semantic, version_code=int(code),
                        apk_path=f'/descargar/{apk.name}', sha256=digest(apk),
                        size=apk.stat().st_size, notes=json.loads((ROOT/'client/update_notes.json').read_text(encoding='utf-8')))
        manifest.pop('published_at', None)
    if digest(apk) != manifest['sha256']:
        raise ValueError('La APK vigente no coincide con su manifiesto.')
    manifest = sign_android(manifest)
    (updates/'android-update.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    shutil.copy2(apk, updates/apk.name)
    # The server supports the versioned path in the feed and the stable alias.
    shutil.copy2(apk, updates/'Mesa-Android.apk')
    licenses = stage/'licenses'
    licenses.mkdir(exist_ok=True)
    ocr_models = ROOT/'.tools/ocr/indra-v1.1.0'
    for name in ('LICENSE','CODE-LICENSE.txt','README.md','mesa-model-manifest.json'):
        shutil.copy2(ocr_models/name, licenses/('Indra-OCR-'+name))
    for package in ('fastapi', 'uvicorn', 'starlette', 'pydantic', 'pydantic_core', 'httpx', 'httpcore', 'anyio', 'h11', 'click', 'typing_extensions', 'annotated-types', 'annotated-doc', 'typing-inspection', 'pillow', 'pypdf', 'ctranslate2', 'sentencepiece', 'numpy', 'certifi', 'idna', 'indra-ocr', 'onnxruntime', 'opencv-python-headless', 'pypdfium2', 'flatbuffers', 'protobuf', 'packaging', 'cryptography', 'cffi', 'pycparser'):
        distribution = importlib.metadata.distribution(package)
        destination = licenses/package
        destination.mkdir(exist_ok=True)
        for file in distribution.files or []:
            if any(part.lower().startswith(('license', 'copying', 'notice')) for part in file.parts):
                source = Path(distribution.locate_file(file))
                if source.is_file():
                    name = '__'.join(file.parts[1:])
                    shutil.copy2(source, destination/name)
    python_license = Path(sys.base_prefix)/'LICENSE.txt'
    if python_license.exists():
        shutil.copy2(python_license, licenses/'Python-LICENSE.txt')
    model_sources = {
        'opus-en-es': 'https://huggingface.co/Helsinki-NLP/opus-mt-tc-big-en-es/raw/main/README.md',
        'opus-fr-es': 'https://huggingface.co/Helsinki-NLP/opus-mt-fr-es/raw/main/README.md',
        'opus-it-es': 'https://huggingface.co/Helsinki-NLP/opus-mt-it-es/raw/main/README.md',
        'opus-de-es': 'https://huggingface.co/Helsinki-NLP/opus-mt-de-es/raw/main/README.md',
        'pt-en': 'https://raw.githubusercontent.com/uav4geo/LibreTranslate-Models/3d5ca0a2c3c302287339b2944329f767ac1673f4/LICENSE',
    }
    for model, url in model_sources.items():
        target = licenses/f'{model}-source.txt'
        if not target.exists():
            with urllib.request.urlopen(url, timeout=40) as response:
                target.write_bytes(response.read())
    (licenses/'translation-models.txt').write_text('Helsinki-NLP / OPUS-MT: en-es CC BY 4.0; fr-es, it-es y de-es, tarjetas Apache 2.0. Modelos originales convertidos a CTranslate2 CPU int8; se conservan cantidades y tokenizadores. Portuguese-English: UAV4GEO / LibreTranslate-Models, MIT; se incluyen los archivos del paquete pt_en 1.0 usados por el motor existente. No se incluyen Stanza ni modelos TranslateGemma. Las tarjetas y procedencias se conservan junto a este aviso.\nhttps://creativecommons.org/licenses/by/4.0/\nhttps://www.apache.org/licenses/LICENSE-2.0\n', encoding='utf-8')
    for name, url in {'CC-BY-4.0.txt': 'https://creativecommons.org/licenses/by/4.0/legalcode.txt', 'Apache-2.0.txt': 'https://www.apache.org/licenses/LICENSE-2.0.txt'}.items():
        if not (licenses/name).exists():
            request = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0 Mesa installer license copy'})
            with urllib.request.urlopen(request, timeout=40) as response:
                (licenses/name).write_bytes(response.read())
    shutil.copy2(TOOLS/'nsis-3.12/COPYING', licenses/'NSIS-COPYING.txt')
    (licenses/'Visual-C++-runtime.txt').write_text('Microsoft Visual C++ Runtime x64, redistribuibles oficiales de Visual Studio Build Tools 2022 (14.44.35112). Despliegue local en la carpeta de la aplicación, sin instalar componentes globales. Copyright Microsoft Corporation.\nhttps://learn.microsoft.com/cpp/windows/redistributing-visual-cpp-files\n', encoding='utf-8')
    shutil.copy2(ROOT/'docs/WINDOWS-INSTALLER.md', stage/'LEEME-Windows.txt')
    # Never distribute fixtures, laboratory scripts, databases or credentials.
    resources = stage/'_internal/server'
    for path in resources.glob('test_*.py'):
        path.unlink()
    fixture_dir = resources/'fixtures'
    if fixture_dir.exists():
        if not fixture_dir.resolve().is_relative_to(stage.resolve()):
            raise ValueError('Ruta de staging incorrecta.')
        shutil.rmtree(fixture_dir)
    for cache in sorted(resources.rglob('__pycache__'), reverse=True):
        if not cache.resolve().is_relative_to(stage.resolve()):
            raise ValueError('Ruta de caché de staging incorrecta.')
        shutil.rmtree(cache)
    # A checksum manifest cannot include its own previous hash on a rebuild.
    files = sorted(p for p in stage.rglob('*') if p.is_file() and p != stage/'payload-manifest.json')
    payload = [{'path': p.relative_to(stage).as_posix(), 'bytes': p.stat().st_size, 'sha256': digest(p)} for p in files]
    (stage/'payload-manifest.json').write_text(json.dumps({'appVersion': version, 'architecture': 'x64', 'files': payload}, ensure_ascii=False, indent=2), encoding='utf-8')
    files.append(stage/'payload-manifest.json')
    install_lines = []
    for path in files:
        relative = path.relative_to(stage)
        parent = str(relative.parent)
        output = '$INSTDIR' + ('\\' + nsis_quote(parent) if parent != '.' else '')
        install_lines += [f'SetOutPath "{output}"', f'File "{nsis_quote(path)}"']
    remove_lines = [f'Delete "$INSTDIR\\{nsis_quote(p.relative_to(stage))}"' for p in files]
    directories = sorted({parent for p in files for parent in p.parents if parent != stage and parent.is_relative_to(stage)}, key=lambda p: len(p.parts), reverse=True)
    remove_lines += [f'RMDir "$INSTDIR\\{nsis_quote(p.relative_to(stage))}"' for p in directories]
    include = work/'install-files.nsh'
    uninstall = work/'uninstall-files.nsh'
    include.write_text('\n'.join(install_lines), encoding='utf-8-sig')
    uninstall.write_text('\n'.join(remove_lines), encoding='utf-8-sig')
    compiler = TOOLS/'nsis-3.12/makensis.exe'
    command = [str(compiler), '/V3', f'/DINSTALLER={installer}', f'/DAPP_VERSION={semantic}', f'/DVERSION_DOTS={semantic}.{code}', f'/DICON={ROOT / "client/windows/runner/resources/app_icon.ico"}', f'/DINSTALL_FILES={include}', f'/DUNINSTALL_FILES={uninstall}', f'/DOCR_LICENSE={ocr_models / "LICENSE"}', str(ROOT/'scripts/windows-installer.nsi')]
    (work/'installer-command.json').write_text(json.dumps(command, ensure_ascii=False, indent=2), encoding='utf-8')
    subprocess.run(command, cwd=ROOT, check=True)
    result = {'appVersion': version, 'architecture': 'x64', 'installer': str(installer), 'bytes': installer.stat().st_size, 'sha256': digest(installer), 'stage': str(stage)}
    index_path=destination/'windows-installer.json' if args.candidate else ROOT/'dist/windows-installer.json'
    index_path.write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
