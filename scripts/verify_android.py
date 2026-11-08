"""Reject Android packages missing Mesa's activity or native plugin registration."""
import argparse
import json
import struct
import subprocess
import zipfile
from pathlib import Path


def uleb(data, offset):
    value = shift = 0
    while True:
        byte = data[offset]
        offset += 1
        value |= (byte & 127) << shift
        if byte < 128:
            return value, offset
        shift += 7
        if shift > 35:
            raise ValueError('Invalid DEX integer')


def dex_classes(data):
    def uint(offset):
        return struct.unpack_from('<I', data, offset)[0]

    strings = []
    for i in range(uint(56)):
        offset = uint(uint(60) + i * 4)
        _, offset = uleb(data, offset)
        end = data.index(b'\0', offset)
        strings.append(data[offset:end].decode('utf-8', errors='replace'))
    types = [strings[uint(uint(68) + i * 4)] for i in range(uint(64))]
    methods = [strings[uint(uint(92) + i * 8 + 4)] for i in range(uint(88))]
    result = {}
    for i in range(uint(96)):
        offset = uint(100) + i * 32
        descriptor = types[uint(offset)]
        class_data = uint(offset + 24)
        code = {}
        if class_data:
            sizes = []
            for _ in range(4):
                size, class_data = uleb(data, class_data)
                sizes.append(size)
            for _ in range(sizes[0] + sizes[1]):
                _, class_data = uleb(data, class_data)
                _, class_data = uleb(data, class_data)
            for size in sizes[2:]:
                index = 0
                for _ in range(size):
                    delta, class_data = uleb(data, class_data)
                    index += delta
                    _, class_data = uleb(data, class_data)
                    code_offset, class_data = uleb(data, class_data)
                    code[methods[index]] = uint(code_offset + 12) if code_offset else 0
        result[descriptor] = code
    return result


def verify(apk):
    classes = {}
    with zipfile.ZipFile(apk) as package:
        for name in package.namelist():
            if name.startswith('classes') and name.endswith('.dex'):
                classes.update(dex_classes(package.read(name)))
        native = [n for n in package.namelist() if n.startswith('lib/') and n.endswith('.so')]
    activity = 'Lcom/mesa/mesa/MainActivity;'
    registry = 'Lio/flutter/plugins/GeneratedPluginRegistrant;'
    if activity not in classes:
        raise ValueError('MainActivity is missing from the APK')
    size = classes.get(registry, {}).get('registerWith', 0)
    if size <= 1:
        raise ValueError('Android native plugin registration is empty in the APK')
    registrars = (
        'com.google.mlkit.nl.translate.NaturalLanguageTranslateRegistrar',
        'com.google.mlkit.common.internal.CommonComponentRegistrar',
    )
    for registrar in registrars:
        descriptor = 'L'+registrar.replace('.', '/')+';'
        if classes.get(descriptor, {}).get('<init>', 0) < 1:
            raise ValueError(f'ML Kit registrar constructor is missing: {registrar}')
    if 'Lcom/google/mlkit/vision/text/TextRecognition;' in classes:
        raise ValueError('The retired ML Kit OCR engine is still present; Mesa now uses private-server Indra OCR.')
    for name in ('jni.JniPlugin', 'jni_flutter.JniFlutterPlugin'):
        descriptor = 'Lcom/github/dart_lang/' + name.replace('.', '/') + ';'
        if descriptor not in classes:
            raise ValueError(f'{name} is missing from the APK')
    abis = sorted({n.split('/')[1] for n in native})
    for abi in abis:
        for library in ('libflutter.so', 'libapp.so', 'libdartjni.so'):
            if f'lib/{abi}/{library}' not in native:
                raise ValueError(f'{library} missing for {abi}')
    aapt = Path(__file__).resolve().parents[1] / '.tools/android/build-tools/36.0.0/aapt.exe'
    resources = subprocess.check_output([str(aapt), 'dump', 'resources', str(apk)], encoding='utf-8')
    if 'com.mesa.mesa:drawable/ic_notification' not in resources:
        raise ValueError('Notification icon resolved at runtime is missing from the release APK')
    return {'activity': True, 'plugin_registry_code_units': size, 'abis': abis,
            'ocr': 'private-server-indra', 'legacy_ocr_present': False,
            'notification_icon': True}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('apk', type=Path)
    args = parser.parse_args()
    print(json.dumps(verify(args.apk)))
