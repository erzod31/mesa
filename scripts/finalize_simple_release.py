"""Record the verified 1.9.0 interface release and update its documentation."""
import json
import re
from pathlib import Path

root = Path(__file__).resolve().parent.parent
android = json.loads((root / 'output/android-updates-190-17-release.json').read_text(encoding='utf-8'))
windows = json.loads((root / 'output/windows-simple-1.9.0.json').read_text(encoding='utf-8-sig'))
assert android['version'] == '1.9.0' and android['version_code'] == 17
assert android['https_download_verified'] and windows['responding']
assert windows['version'] == '1.9.0+17'
result = {
    'version': '1.9.0', 'version_code': 17,
    'client_tests': 79, 'server_tests': 55, 'analyzer': 'No issues found',
    'changes': [
        'Biblioteca: búsqueda, recuento y un botón de filtros; sin cabecera decorativa ni filas de categorías.',
        'Filtros: categorías, catálogos, etiquetas, exclusión, favoritas, tiempo, orden y vista en un panel; cancelar no aplica cambios.',
        'Descubrir: Petitchef y 50 recetas, tarjetas de foto y título; fuente, ranking y detalles desde un control.',
        'Ficha: secciones sin recuadros, datos en texto, Cocinar y Opciones; compra, planificación, edición, favoritas, historial y papelera siguen disponibles.',
        'Formulario: campos principales visibles y detalles opcionales desplegables.',
        'Menú semanal: una acción por día que permite elegir comida o cena.',
        'Compra: controles de productos comprados solo cuando hay comprados.',
        'Mi espacio: herramientas agrupadas por tarea; actualizador Android visible.',
        'Estado de sincronización en Mi espacio, avisos relevantes visibles en la pantalla principal.',
        'Selección de navegación y pestañas en verde; márgenes y contraste conservados.'
    ],
    'screenshots': [f'output/screenshots/mesa-simple-{view}-{width}.png'
                    for view in ['editor', 'ajustes', 'menu'] for width in [320, 390, 1360]]
                   + [f'output/screenshots/mesa-simple-{width}.png' for width in [320, 390, 1360]],
    'physical_android_test': False,
    'preserved': ['16 fuentes', 'Petitchef primero y 50 recetas', 'Fotos por URLs directas', 'Ingredientes originales y ajuste de raciones', 'Datos familiares', 'Firma Android existente'],
    'android': android, 'windows': windows,
}
(root / 'output/simple-interface-1.9.0-release.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')

p = root / 'README.md'
s = p.read_text(encoding='utf-8')
s = s.replace('La versión actual es **Mesa 1.8.1 (código 16)**', 'La versión actual es **Mesa 1.9.0 (código 17)**')
s = s.replace('**Mi espacio → Invitar familiar**', '**Mi espacio → Familia y conexión → Invitar familiar**')
marker = 'Mesa 1.8.1 abre **Recetas → Descubrir**'
paragraph = '''Mesa 1.9.0 simplifica la interfaz de Windows y Android. La biblioteca empieza con búsqueda y recetas; filtros, categorías, catálogos, etiquetas, orden y vista están en **Filtros**. En Descubrir, pulsa **Cambiar fuente** para elegir otra fuente, ver detalles o abrir el ranking. La ficha mantiene **Cocinar** como acción principal y reúne compra, planificación, edición, favoritas, historial y papelera en **Opciones**. El formulario deja visibles los campos principales y despliega fotos, organización y notas. Mi espacio agrupa conexión, copias, apariencia y temporizadores; el actualizador Android sigue visible. Análisis limpio, **79 pruebas del cliente y 55 del servidor**, compilaciones firmadas y descarga privada verificada. Capturas de pruebas, sin teléfono físico: [investigacion-diseno-mesa.html](investigacion-diseno-mesa.html). Registro: `output/simple-interface-1.9.0-release.json`.

'''
if paragraph not in s:
    s = s.replace(marker, paragraph + marker)
p.write_text(s, encoding='utf-8')

p = root / 'docs/DECISIONES.md'
s = p.read_text(encoding='utf-8')
entry = '''
## 11 de octubre de 2026 · Mesa 1.9.0: menos complejidad visual

La revisión parte de las pantallas implementadas y de la observación del usuario: demasiados controles antes del contenido, repeticiones por tarjeta y recuadros sin una función clara. Se retiran cabeceras decorativas y controles duplicados; las funciones secundarias se agrupan sin retirar filtros ni acciones. Los campos principales del formulario permanecen visibles; fotos, organización y notas son desplegables. El menú usa una acción por día y mantiene la elección entre comida y cena. Mi espacio agrupa las herramientas por tarea y deja visible la actualización Android. Las selecciones usan verde para reducir acentos simultáneos.

Se conserva Petitchef por defecto con 50 recetas, las 16 fuentes, cantidades originales, galerías por URL y datos locales/familiares. La firma Android permanece igual. El estado normal se consulta en Mi espacio; cambios pendientes de un servidor configurado, errores y conflictos siguen visibles en la pantalla principal. Los temporizadores existentes despliegan su sección al entrar.

Validación: análisis sin incidencias, 79 pruebas Flutter y 55 del servidor, filtros con Aplicar/Cancelar, limpieza, navegación, controles secundarios accesibles, ingredientes y raciones, cocina y ampliación de la ficha. Capturas de biblioteca, formulario, menú y ajustes a 320, 390 y 1360 píxeles; ficha a 320 con texto al 200% en oscuro. Windows responde y la APK firmada se descarga íntegra por HTTPS. No se ha probado en un Android físico. Registro: output/simple-interface-1.9.0-release.json.
'''
if entry not in s:
    p.write_text(s + entry, encoding='utf-8')

p = root / 'estado-fuentes-mesa.html'
s = p.read_text(encoding='utf-8').replace('Mesa 1.8.1', 'Mesa 1.9.0')
s = s.replace('Recetas → Descubrir → Ranking de fuentes', 'Recetas → Descubrir → Cambiar fuente → Ranking de fuentes')
p.write_text(s, encoding='utf-8')

p = root / 'investigacion-diseno-mesa.html'
s = p.read_text(encoding='utf-8')
s = s.replace('Investigación y aplicación · 11 de octubre de 2026 · Mesa 1.8.0', 'Investigación y aplicación · 11 de octubre de 2026 · Mesa 1.9.0')
s = s.replace('<p>Mejora concreta tras esta revisión: compra y planificación pasan de iconos solos a botones con texto en Android. Los controles se redistribuyen o apilan para conservar las etiquetas con letra grande. No se añaden cuadros de confirmación a cada acción cotidiana.</p>', '<p>Revisión 1.9.0: compra, planificación y edición tienen etiquetas dentro de Opciones. Cocinar queda como acción principal. La biblioteca reúne los filtros en un panel y las tarjetas de Descubrir eliminan controles repetidos. El formulario y Mi espacio despliegan las opciones secundarias por tarea.</p>')
section = '''<section id="simplificacion"><h2>Menos controles, contenido primero · 1.9.0</h2><p>La revisión anterior mostraba demasiadas herramientas a la vez. Esta versión elimina la cabecera decorativa del recetario, las filas permanentes de filtros y los botones repetidos por tarjeta. Las funciones siguen disponibles en Filtros, Cambiar fuente, Opciones y los apartados desplegables de Mi espacio.</p><figure><img src="output/screenshots/mesa-simple-1360.png" alt="Biblioteca simplificada de Mesa en Windows"><figcaption>Windows: búsqueda, recetas y filtros desde un único control.</figcaption></figure><div class="grid"><figure><img class="phone" src="output/screenshots/mesa-simple-390.png" alt="Biblioteca simplificada en teléfono"><figcaption>Recetas en el primer tramo de la pantalla.</figcaption></figure><figure><img class="phone" src="output/screenshots/mesa-simple-editor-390.png" alt="Formulario sencillo con campos principales"><figcaption>Nombre, ingredientes, pasos y cantidades; los detalles se despliegan.</figcaption></figure><figure><img class="phone" src="output/screenshots/mesa-simple-ajustes-390.png" alt="Mi espacio con herramientas agrupadas"><figcaption>Herramientas organizadas por tarea.</figcaption></figure><figure><img class="phone" src="output/screenshots/mesa-simple-menu-390.png" alt="Menú semanal con un botón por día"><figcaption>Una acción por día, con elección de comida o cena.</figcaption></figure></div><p>Estas capturas proceden de widgets Flutter con datos de prueba. No representan un ensayo con un teléfono físico.</p></section>'''
if 'id="simplificacion"' not in s:
    s = s.replace('<section id="resultado">', section + '<section id="resultado">')
s = re.sub(r'<p id="release-status">.*?</p>', '<p id="release-status">Mesa 1.9.0 (código 17): análisis limpio, 79 pruebas del cliente y 55 del servidor aprobadas. Windows actualizado y respondiendo. APK firmada con la misma identidad; componentes nativos, feed privado y descarga HTTPS completa verificados. <a href="output/simple-interface-1.9.0-release.json">Registro de validación</a>. Actualiza desde Mi espacio o <a href="dist/Mesa-Android-1.9.0-17.apk">abre la APK local</a>.</p>', s)
p.write_text(s, encoding='utf-8')
print(json.dumps({'version': '1.9.0', 'client_tests': 79, 'server_tests': 55, 'documented': True}, ensure_ascii=False))
