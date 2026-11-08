"""Inventory Mesa without reading family data, credentials or signing secrets."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import platform
import re
import shutil
import struct
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
LAB = ROOT / 'output/auditoria-mesa-2026-10-12'
SECTIONS = ['00_alcance', '01_originales', '02_inventario', '03_observacion_ui',
            '04_analisis_estatico', '05_analisis_dinamico', '06_datos_y_red',
            '07_especificacion', '08_reconstruccion', '09_validacion', '10_informe']


def digest(path):
    with path.open('rb') as handle:
        return hashlib.file_digest(handle, 'sha256').hexdigest()


def identity(path):
    return {'path': str(path.relative_to(ROOT)), 'bytes': path.stat().st_size,
            'sha256': digest(path), 'obtained_utc': datetime.now(timezone.utc).isoformat()}


def pe(path):
    with path.open('rb') as handle:
        header = handle.read(64)
        if header[:2] != b'MZ':
            return {'format': 'unknown'}
        handle.seek(struct.unpack_from('<I', header, 60)[0])
        signature = handle.read(24)
        assert signature[:4] == b'PE\0\0'
        machine, sections = struct.unpack_from('<HH', signature, 4)
    return {'format': 'PE', 'machine': hex(machine), 'architecture': {0x8664: 'x86_64', 0xaa64: 'ARM64'}.get(machine, 'unknown'),
            'sections': sections, 'limit': 'Headers do not establish the original source language.'}


def apk(path):
    with zipfile.ZipFile(path) as package:
        names = package.namelist()
        libraries = [name for name in names if name.startswith('lib/') and name.endswith('.so')]
        native = {}
        for name in libraries:
            with package.open(name) as handle:
                header = handle.read(20)
            if header[:4] == b'\x7fELF':
                native[name] = {'format': 'ELF', 'machine': struct.unpack_from('<H', header, 18)[0]}
        return {'format': 'ZIP/APK', 'manifest': 'AndroidManifest.xml' in names,
                'dex': [name for name in names if re.fullmatch(r'classes\d*\.dex', name)],
                'abis': sorted({name.split('/')[1] for name in libraries}),
                'native': native, 'flutter_assets': sum(name.startswith('assets/flutter_assets/') for name in names),
                'limit': 'DEX represents native bridges and libraries; it does not reconstruct release Dart AOT source.'}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--stage', choices=['baseline', 'candidate'], required=True)
    args = parser.parse_args()
    for section in SECTIONS:
        (LAB / section).mkdir(parents=True, exist_ok=True)
    version = re.search(r'^version:\s*(\S+)', (ROOT/'client/pubspec.yaml').read_text(encoding='utf-8'), re.M)[1]
    report = {'scope': 'Mesa Windows/Android; synthetic tests; no family databases or secrets inspected.',
              'stage': args.stage, 'source_version': version,
              'host': {'os': platform.platform(), 'python': platform.python_version()},
              'artifacts': [], 'source_hashes': []}
    paths = ([ROOT/'dist/Mesa-Android-1.11.2-25.apk', ROOT/'dist/Mesa-Windows/mesa.exe']
             if args.stage == 'baseline' else
             [ROOT/'dist/Mesa-Android.apk', ROOT/'dist/Mesa-Windows/mesa.exe'])
    for path in paths:
        if not path.exists():
            report['artifacts'].append({'path': str(path.relative_to(ROOT)), 'status': 'PENDIENTE'})
            continue
        item = identity(path)
        item['static'] = apk(path) if path.suffix == '.apk' else pe(path)
        if args.stage == 'baseline':
            name = path.name if path.suffix == '.apk' else 'Mesa-Windows-1.11.2-25.exe'
            copy = LAB / '01_originales' / name
            if copy.exists():
                assert digest(copy) == item['sha256'], 'Refusing to replace an original with different bytes.'
            else:
                shutil.copyfile(path, copy)
            assert digest(copy) == item['sha256']
            item['preserved_copy'] = str(copy.relative_to(ROOT))
        report['artifacts'].append(item)
    for folder, pattern in [('client/lib', '*.dart'), ('server', '*.py')]:
        for path in sorted((ROOT/folder).glob(pattern)):
            report['source_hashes'].append(identity(path))
    aapt = ROOT/'.tools/android/build-tools/36.0.0/aapt.exe'
    apk_path = paths[0]
    if aapt.exists() and apk_path.exists():
        badging = subprocess.check_output([str(aapt), 'dump', 'badging', str(apk_path)], text=True, encoding='utf-8')
        manifest = subprocess.check_output([str(aapt), 'dump', 'xmltree', str(apk_path), 'AndroidManifest.xml'], text=True, encoding='utf-8')
        (LAB/'04_analisis_estatico'/f'{args.stage}-badging.txt').write_text(badging, encoding='utf-8')
        (LAB/'04_analisis_estatico'/f'{args.stage}-manifest.txt').write_text(manifest, encoding='utf-8')
        report['apk_identity'] = next(line for line in badging.splitlines() if line.startswith('package:'))
    source = (ROOT/'server/app.py').read_text(encoding='utf-8')
    report['server_routes_static'] = [{'method': method.upper(), 'path': path, 'evidence': 'server/app.py; OBSERVADO en código, no implica petición real.'}
                                    for method, path in re.findall(r"@api\.(get|post|delete)\('([^']+)'", source)]
    output = LAB/'02_inventario'/f'{args.stage}.json'
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({'inventory': str(output), 'artifacts': len(report['artifacts']),
                      'sources': len(report['source_hashes']), 'routes_static': len(report['server_routes_static'])}, ensure_ascii=False))


if __name__ == '__main__':
    main()
