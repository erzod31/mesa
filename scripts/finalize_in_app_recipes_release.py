"""Document the verified release that opens public recipes inside Mesa."""
import json
import re
from pathlib import Path
from zipfile import ZipFile

root = Path(__file__).resolve().parent.parent
android = json.loads((root / 'output/android-updates-191-18-release.json').read_text(encoding='utf-8'))
windows = json.loads((root / 'output/windows-in-app-1.9.1.json').read_text(encoding='utf-8-sig'))
live = json.loads((root / 'output/public-detail-live-results.json').read_text(encoding='utf-8'))
comparison = json.loads((root / 'output/public-detail-parser-comparison.json').read_text(encoding='utf-8'))
assert android['version'] == '1.9.1' and android['version_code'] == 18
assert android['https_download_verified'] and windows['responding']
assert windows['version'] == '1.9.1+18'
assert len(live) == 16 and all(row['ok'] for row in live.values())
assert comparison['compared'] == 12 and not comparison['differences']
with ZipFile(root / 'dist/Mesa-Android-1.9.1-18.apk') as archive:
    app = archive.read('lib/arm64-v8a/libapp.so')
    markers = {text: text.encode() in app for text in ['No se pudo abrir la receta', '/v6/recipe', 'Ver fuente original']}
    assert all(markers.values())
record = {
    'version': '1.9.1', 'version_code': 18,
    'analyzer': 'No issues found', 'client_tests': 87, 'server_tests': 55,
    'cause': 'El catálogo abría automáticamente la página original si el dispositivo no tenía URL y credencial del servidor familiar.',
    'changes': [
        'Sin redirección automática al navegador al pulsar una receta.',
        'Lectura directa sin emparejamiento: JSON-LD, secciones visibles y API pública de Kiwilimón.',
        'Servidor familiar disponible como lector; si falla se intenta la consulta pública sin credenciales.',
        'Fotos por enlaces directos y cantidades originales; no se descargan archivos de fotografía.',
        'Ver fuente original solo como acción explícita; errores con Reintentar, Cerrar y enlace opcional.',
        'Recuperación de fotos en el editor también funciona sin servidor cuando existe origen de catálogo.'
    ],
    'live_samples_checked': len(live),
    'live_sample_results': live,
    'client_server_field_counts': comparison,
    'new_reader_present_in_apk': markers,
    'coverage': 'Una muestra por cada una de las 13 fuentes web seleccionables y tres recetas iniciales de Petitchef; no representa una auditoría del catálogo completo.',
    'physical_android_test': False,
    'android': android, 'windows': windows,
    'research': ['https://schema.org/Recipe', 'https://www.petitchef.es/las-ultimas-recetas'],
}
(root / 'output/in-app-recipes-1.9.1-release.json').write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding='utf-8')
p = root / 'README.md'
s = p.read_text(encoding='utf-8').replace('La versión actual es **Mesa 1.9.0 (código 17)**', 'La versión actual es **Mesa 1.9.1 (código 18)**')
paragraph = '''Mesa 1.9.1 abre las recetas de **Descubrir dentro de la app**, aunque Android no esté conectado al servidor familiar. Lee directamente cantidades, preparación y fotografías por URL de las fuentes disponibles; Kiwilimón usa su API pública y el resto los datos estructurados o las secciones de la receta. Si el servidor familiar falla, intenta la lectura pública. La página original solo se abre al pulsar **Ver fuente original**. Los errores se muestran dentro de Mesa con **Reintentar**. Se mantienen revisión y guardado, galerías y vistas guardadas sin conexión. Validación: análisis limpio, **87 pruebas del cliente y 55 del servidor**, 16 muestras reales correctas de las 13 fuentes web seleccionables y tres recetas iniciales de Petitchef. No se ha ensayado en un Android físico ni se ha auditado el catálogo completo. Registro: `output/in-app-recipes-1.9.1-release.json`.

'''
if paragraph not in s:
    s = s.replace('Mesa 1.9.0 simplifica la interfaz', paragraph + 'Mesa 1.9.0 simplifica la interfaz')
p.write_text(s, encoding='utf-8')
p = root / 'docs/DECISIONES.md'
s = p.read_text(encoding='utf-8')
entry = '''
## 11 de octubre de 2026 · Mesa 1.9.1: recetas dentro de la app sin emparejamiento

La APK usaba un desvío intencional al navegador para fuentes editoriales cuando no había servidor familiar configurado. El catálogo ya consultaba las fuentes directamente, pero la lectura del detalle requería una llamada privada de importación. Se elimina el desvío y se añade lectura pública de detalle al cliente: JSON-LD Recipe, cantidades y pasos de secciones visibles, fotos principales y de pasos, y API pública de Kiwilimón. Se conservan la atribución, el rendimiento declarado y las cantidades originales; no se inventan recetas si la página está bloqueada o incompleta.

Si existe lector del servidor se utiliza, y un fallo permite consultar directamente la fuente. No se envían credenciales familiares a las fuentes públicas. Se verifican dominio, protocolo, redirecciones y límites de lectura con el transporte existente. La fuente original queda en un botón explícito y los errores ofrecen Reintentar sin abandonar Mesa. El editor puede recuperar las fotografías del origen sin emparejarse.

Referencias comprobadas: https://schema.org/Recipe y https://www.petitchef.es/las-ultimas-recetas. Consulta real del cliente: 16 muestras correctas, una por las 13 fuentes web seleccionables y las tres primeras de Petitchef. Se leen HTML/JSON y enlaces a fotos; no se descargan archivos de imagen. Las 12 páginas editoriales revisadas disponibles como fixtures también se interpretan correctamente. No se supone que todas las recetas de cada web tengan idéntico formato.

Validación: análisis limpio, 87 pruebas Flutter y 55 del servidor. Las pruebas de Android sin servidor comprueban Petitchef y Kiwilimón dentro de Mesa, cantidades, pasos, galerías, revisión/guardado y apertura de la web solo al pulsar el enlace. Una receta incompleta conserva al usuario dentro de Mesa y permite reintentar. Compilaciones Windows/Android, firma existente, componentes nativos y descarga HTTPS completa verificados. No hay prueba con Android físico. Registro: output/in-app-recipes-1.9.1-release.json.
'''
if entry not in s:
    p.write_text(s + entry, encoding='utf-8')
p = root / 'estado-fuentes-mesa.html'
p.write_text(p.read_text(encoding='utf-8').replace('Mesa 1.9.0', 'Mesa 1.9.1'), encoding='utf-8')
p = root / 'investigacion-diseno-mesa.html'
s = p.read_text(encoding='utf-8')
tag = '<p class="tag">Corrección 1.9.1: las recetas se leen dentro de Mesa sin emparejamiento familiar. La página original se abre solo mediante un botón explícito.</p>'
if tag not in s:
    s = s.replace('<nav>', tag + '<nav>', 1)
s = re.sub(r'<p id="release-status">.*?</p>', '<p id="release-status">Mesa 1.9.1 (código 18): análisis limpio, 87 pruebas del cliente y 55 del servidor. Lectura interna comprobada sin servidor, 16 muestras públicas correctas, Windows respondiendo y descarga HTTPS de la APK firmada verificada. <a href="output/in-app-recipes-1.9.1-release.json">Registro</a> · <a href="dist/Mesa-Android-1.9.1-18.apk">APK</a>. Pendiente prueba en Android físico.</p>', s)
p.write_text(s, encoding='utf-8')
print(json.dumps({'version': '1.9.1', 'client_tests': 87, 'server_tests': 55, 'live_samples': 16, 'documented': True}))
