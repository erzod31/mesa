"""Finalize the Mesa redesign dossier from release and test evidence, without family data."""
import csv
from datetime import datetime, timezone
import hashlib
import html
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
LAB = ROOT / 'output/auditoria-mesa-2026-10-12'


def read(path):
    return json.loads((ROOT / path).read_text(encoding='utf-8-sig'))


def main():
    release = read('output/android-updates-1120-26-release.json')
    native = read('output/auditoria-mesa-2026-10-12/09_validacion/android-native-smoke.json')
    windows = read('output/auditoria-mesa-2026-10-12/09_validacion/windows-start.json')
    assert release['https_download_verified'] and release['version_code'] == 26
    assert release['client_tests'] == 133 and release['server_tests'] == 92
    assert native['status'] == 'APROBADO' and windows['running'] and windows['version'] == '1.12.0+26'
    captures = []
    for name in ['mesa-simple-390.png', 'mesa-simple-1360.png',
                 'mesa-modern-320-dark-large.png', 'mesa-simple-editor-390.png',
                 'mesa-layout-android.png', 'mesa-simple-menu-320.png',
                 'mesa-cocinar-320-letra-grande.png', 'fast-preview-android.png']:
        source = ROOT / 'output/screenshots' / name
        target = LAB / '03_observacion_ui' / name
        shutil.copyfile(source, target)
        captures.append(dict(file=str(target.relative_to(ROOT)),
                             sha256=hashlib.sha256(target.read_bytes()).hexdigest(),
                             scope='Real Flutter widget render, synthetic data; not a physical phone.'))
    (LAB / '03_observacion_ui/capturas.json').write_text(json.dumps(captures, ensure_ascii=False, indent=2), encoding='utf-8')
    cases = [
        ('V01', 'Crear, editar, validar y guardar recetas', 'APROBADO', 'Widgets y reglas; ensayo nativo acotado', 'client/test/widget_test.dart; client/test/store_test.dart; android-native-smoke.json'),
        ('V02', 'Buscar, favoritas, filtros y categorías', 'APROBADO', 'Widgets a 320/390/1360 px', 'client/test/layout_research_test.dart; client/test/widget_test.dart'),
        ('V03', 'Recetas, Semana, Compra y Mi espacio', 'APROBADO', 'Widgets, oscuro y texto grande; ensayo nativo', 'client/test/modern_design_test.dart; android-native-smoke.json'),
        ('V04', 'Abrir, importar y guardar un catálogo', 'APROBADO', 'HTTP simulado; no todos los sitios reales', 'client/test/widget_test.dart; client/test/public_publisher_test.dart'),
        ('V05', 'Apertura progresiva y recuperación', 'APROBADO', 'HTTP simulado, cancelación y respuestas tardías', 'client/test/recipe_opening_test.dart; client/test/fast_recipe_preview_test.dart'),
        ('V06', 'Cantidades y medidas originales/europeas', 'APROBADO', 'Reglas y widgets, muestras representativas', 'client/test/recipe_conversion_translation_test.dart; client/test/layout_research_test.dart'),
        ('V07', 'Galerías y consulta temporal de fotos', 'APROBADO', 'Fixtures; sesión, descarga y liberación', 'client/test/photos_test.dart; client/test/gallery_photo_session_test.dart; client/test/online_photos_test.dart'),
        ('V08', 'Cocinar, raciones y temporizadores', 'APROBADO', 'Widgets; pasos y controles; cocina nativa según ficha', 'client/test/layout_research_test.dart; client/test/widget_test.dart; android-native-smoke.json'),
        ('V09', 'Plan semanal y lista de compra', 'APROBADO', 'Widget y servidor simulado', 'client/test/widget_test.dart; server/test_api.py'),
        ('V10', 'Persistencia sin conexión', 'APROBADO', 'SQLite real cerrado/reabierto; ensayo nativo según ficha', '05_analisis_dinamico/persistencia-offline.json; android-native-smoke.json'),
        ('V11', 'Sincronizar sin duplicados ni perder ediciones', 'APROBADO', 'Mock HTTP y FastAPI TestClient', 'client/test/store_test.dart; client/test/open_catalog_and_transmission_test.dart; server/test_api.py'),
        ('V12', 'Roles, invitaciones, conflictos, historial y recuperación', 'APROBADO', 'Datos sintéticos; API en proceso', 'server/test_api.py; client/test/store_test.dart'),
        ('V13', 'Traducción: original, números y revisión', 'APROBADO', 'Mocks de traductor; no certifica calidad lingüística universal', 'client/test/saved_recipe_translation_test.dart; client/test/translation_review_test.dart; server/test_translation_cache.py'),
        ('V14', 'Feed, firma, SHA-256 y descarga completa', 'APROBADO', 'HTTPS real; instalador simulado en widget', 'output/android-updates-1120-26-release.json; client/test/updates_test.dart'),
        ('V15', 'Inicio de Windows 1.12.0 y servidor', 'APROBADO', 'Proceso y ventana reales; no todos los recorridos', '09_validacion/windows-start.json'),
        ('V16', 'Inicio de Android de lanzamiento', 'APROBADO', 'Android 36 x86_64, MesaTest; main.dart de producción', '09_validacion/android-native-smoke.json'),
        ('V17', 'Contraste y distribución adaptable', 'APROBADO', 'Roles de texto 4.5:1 y contorno 3:1; capturas concretas', 'output/design-contrast.json; client/test/layout_research_test.dart'),
        ('V18', 'Primera receta en una pantalla corta', 'APROBADO', '320 × 640; acción accesible sin FAB redundante', 'client/test/modern_design_test.dart'),
        ('V19', 'Uso completo en teléfono ARM64 físico', 'PENDIENTE', 'Ningún teléfono conectado', ''),
        ('V20', 'Ciclo familiar entre dos dispositivos físicos por Tailscale', 'PENDIENTE', 'HTTPS de distribución verificado; ciclo familiar no repetido', ''),
        ('V21', 'TalkBack, Narrador y conformidad completa WCAG 2.2 AA', 'PENDIENTE', 'Contraste parcial y semánticas no certifican conformidad completa', ''),
        ('V22', 'Comparativa antes/después de rendimiento release', 'PENDIENTE', 'Sin series en un mismo dispositivo físico', ''),
        ('V23', 'Traducción exclusivamente remota y gratuita', 'PENDIENTE', 'Investigada; proveedor y credenciales sin configurar', ''),
        ('V24', 'iOS, web, macOS y reconstrucción de app ajena', 'NO APLICA', 'Mesa Windows/Android con código fuente disponible', ''),
    ]
    with (LAB / '09_validacion/matriz-funcional.csv').open('w', encoding='utf-8-sig', newline='') as output:
        writer = csv.writer(output)
        writer.writerow(['Caso', 'Requisito', 'Resultado', 'Alcance', 'Evidencia'])
        writer.writerows(cases)
    counts = {state: sum(case[2] == state for case in cases)
              for state in ['APROBADO', 'FALLIDO', 'PENDIENTE', 'NO APLICA']}
    summary = dict(version='1.12.0+26', created_utc=datetime.now(timezone.utc).isoformat(),
                   client_tests=133, server_tests=92, functional_matrix=counts,
                   scope='Grouped acceptance cases, not all possible app states.',
                   android_release=release, android_native=native, windows=windows,
                   remote_translation_configured=False, physical_android_test=False)
    (LAB / '09_validacion/resultado-final.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding='utf-8')
    scope = dict(product='Mesa', platforms=['Windows x86_64', 'Android ARM64'],
                 mode='Análisis del proyecto y rediseño implementado',
                 reference_binary='1.11.2+25', candidate='1.12.0+26',
                 authorized='Código, artefactos del proyecto, laboratorio sintético y arranque de Mesa',
                 excluded='Contenido de bases familiares, tokens, claves de firma y cuentas externas',
                 limitation='Hashes iniciales de fuentes capturados durante el rediseño; no representan un checkout intacto de la versión 25.')
    (LAB / '00_alcance/alcance.json').write_text(json.dumps(scope, ensure_ascii=False, indent=2), encoding='utf-8')
    schema = dict(classification='OBSERVADO en código', confidence='alta',
                  evidence=['client/lib/models.dart', 'client/lib/store.dart', 'server/app.py'],
                  local_tables={'entities': 'id PK, kind, revision, data JSON, deleted',
                                'outbox': 'seq, id UNIQUE, entity_id, payload JSON, attempted',
                                'conflicts': 'id, payload', 'prefs': 'key, value'},
                  recipe_fields={'title': 'string obligatorio, 1..250 caracteres',
                                 'ingredients_steps_tags_category_ids_catalog_ids': 'listas de strings; hasta 500 elementos, hasta 10000 caracteres por elemento',
                                 'servings': 'número finito >0 y <=10000; defecto 4',
                                 'minutes': 'entero 0..100000; defecto 0 (tiempo pendiente)',
                                 'rating': 'entero 0..5',
                                 'photos': 'hasta 500 referencias con URL pública HTTPS y metadatos; bytes no persistidos',
                                 'original_translation_origin': 'objetos opcionales con validación propia'},
                  kinds=['recipe', 'collection', 'shopping', 'meal'],
                  null_absent_zero='No equivalen: minutes 0 es tiempo pendiente; campo ausente puede aplicar un valor por defecto; title vacío es inválido.',
                  secrets='Token en almacenamiento seguro; solo hashes de usuarios/invitaciones en servidor. No se inspecciona su contenido.')
    (LAB / '06_datos_y_red/diccionario-datos.json').write_text(json.dumps(schema, ensure_ascii=False, indent=2), encoding='utf-8')
    candidate = read('output/auditoria-mesa-2026-10-12/02_inventario/candidate.json')
    (LAB / '06_datos_y_red/contratos-estaticos.json').write_text(json.dumps(candidate['server_routes_static'], ensure_ascii=False, indent=2), encoding='utf-8')
    specification = dict(classification='OBSERVADO en código y pruebas; simulaciones etiquetadas en matriz',
                         invariants=['Originales conservados al convertir medidas', 'Fotos como URL, sin bytes en exportación',
                                     'Una operación intentada conserva ID al reintentar', 'Snapshot incompleto no sustituye datos locales',
                                     'Un lector no puede escribir en servidor', 'Traducción tardía no reemplaza una edición posterior'],
                         acceptance_cases=[dict(id=c[0], requirement=c[1], status=c[2], scope=c[3], evidence=c[4]) for c in cases],
                         fidelity='Rediseño de Mesa con fuente disponible, no reconstrucción independiente de un binario ajeno.')
    (LAB / '07_especificacion/funciones.json').write_text(json.dumps(specification, ensure_ascii=False, indent=2), encoding='utf-8')
    rows = ''.join('<tr>' + ''.join('<td>' + html.escape(str(cell)) + '</td>' for cell in case) + '</tr>' for case in cases)
    report = '''<!doctype html><html lang="es"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Mesa 1.12 · Rediseño y comprobación funcional</title><style>
:root{color-scheme:light dark;--bg:#f6f7f2;--surface:#fffefb;--ink:#242b26;--muted:#515c53;--green:#25634b;--line:#dce3dc}*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.65 system-ui,Segoe UI,sans-serif}main{max-width:1160px;margin:auto;padding:40px 24px 80px}
header,section{background:var(--surface);border:1px solid var(--line);border-radius:28px;padding:28px;margin:20px 0}
h1{font-size:clamp(30px,5vw,50px);line-height:1.15;letter-spacing:-1.2px;margin:12px 0}h2{line-height:1.25;color:var(--green)}h3{line-height:1.3}p{max-width:85ch}
a{color:var(--green);text-underline-offset:3px}nav{display:flex;flex-wrap:wrap;gap:12px;margin:24px 0}nav a,.badge{display:inline-block;background:#e1efe6;border-radius:30px;padding:8px 16px;color:#123b2b}
small,figcaption{color:var(--muted)}figure{margin:0}img{display:block;width:100%;border-radius:20px;border:1px solid var(--line)}.gallery{display:grid;grid-template-columns:minmax(0,2fr) minmax(0,1fr);gap:20px}.gallery img{max-height:650px;object-fit:contain;background:var(--bg)}
.table{overflow:auto}table{width:100%;border-collapse:collapse;min-width:740px;font-size:14px}td,th{padding:12px;text-align:left;border-bottom:1px solid var(--line);vertical-align:top}
code,pre{font:14px/1.6 ui-monospace,Consolas,monospace}pre{overflow:auto;padding:18px;background:var(--bg);border-radius:20px}li{margin:8px 0}.notice{border-left:4px solid #a54f32;padding-left:20px}
@media(max-width:650px){main{padding:16px 12px 48px}header,section{padding:20px}.gallery{grid-template-columns:1fr}}
@media(prefers-color-scheme:dark){:root{--bg:#171d19;--surface:#1d2923;--ink:#edf3ed;--muted:#bbc8bd;--green:#9ed8b8;--line:#415047}}
</style><main><header><span class="badge">Mesa · 1.12.0+26 · 12 octubre 2026</span><h1>Más clara para guardar.<br>Más cómoda para cocinar.</h1><p>Rediseño implementado para Windows y Android, con comprobación funcional y dossier reproducible. La entrega supera las pruebas ejecutadas; los ensayos pendientes quedan separados. Esto no certifica todos los dispositivos ni todos los estados posibles.</p><p><a href="https://starfly.tailc69897.ts.net:9443/descargar/Mesa-Android-1.12.0-26.apk">APK ARM64 firmada</a> · <a href="output/auditoria-mesa-2026-10-12/09_validacion/resultado-final.json">Resultado JSON</a> · <a href="output/auditoria-mesa-2026-10-12/09_validacion/matriz-funcional.csv">Matriz CSV</a></p></header>
<nav><a href="#transformacion">Transformación</a><a href="#sistema">Diseño</a><a href="#pruebas">Comprobación final</a><a href="#dossier">Dossier de Mesa</a><a href="#fuentes">Fuentes</a></nav>
<section id="transformacion"><h2>1. Transformación realizada</h2><p>La navegación se organiza alrededor de cuatro tareas: Recetas, Semana, Compra y Mi espacio. Dentro de Recetas se distingue el contenido propio de Descubrir. Búsqueda y filtros frecuentes quedan a mano; las opciones avanzadas aparecen al abrir su grupo. Las acciones principales conservan texto visible y una posición estable.</p><div class="gallery"><figure><img src="output/screenshots/mesa-simple-1360.png" alt="Recetario de Mesa en escritorio con barra lateral y filtros"><figcaption>Render real Flutter, 1360 × 900; datos sintéticos.</figcaption></figure><figure><img src="output/screenshots/mesa-simple-390.png" alt="Recetario móvil con navegación inferior redondeada"><figcaption>Render real Flutter, 390 × 844. Las recetas sintéticas sin foto usan un marcador.</figcaption></figure></div>
<h2>2. Problemas visuales corregidos</h2><p>Se redujo la competencia entre herramientas, se sustituyó el selector rectangular por pestañas redondeadas y se unificaron cabeceras, formularios, menús y superficies. Crear en escritorio pasa a la barra lateral; en móvil queda cerca del pulgar. Guardar destaca en el editor. En la receta guardada, Cocinar es la acción primaria y Opciones reúne las secundarias.</p><p>La vista previa móvil ocupa la pantalla completa, con cierre y guardado al pie. Los ajustes se dividen en grupos plegables. Se corrigieron estilos de texto ilegibles en el render de pruebas. El ensayo nativo de 320 × 640 detectó además un FAB sobre el mensaje de recetario vacío: ahora queda una sola acción de primera receta y espacio inferior desplazable.</p>
<h2>3. Nueva navegación y funciones conservadas</h2><p>Escritorio: panel lateral de 224 px con destinos, Nueva receta y estado del recetario. Móvil: barra inferior de cuatro destinos; con texto grande aumenta la altura y se etiqueta el destino activo. Se evaluó plegar manualmente la barra lateral: con cuatro destinos se eligió adaptación automática al ancho para no añadir otro control ni ocultar la ubicación.</p><p>Se conservan creación/edición, favoritos, categorías y colecciones, catálogo/importación individual, originales y medidas, traducción revisable, galerías, cocina y temporizadores, planificación, compra, familia, roles, conflictos, historial, exportación, recuperación y actualización. La matriz precisa qué se ejercitó con fixtures y qué requiere prueba física.</p></section>
<section id="sistema"><h2>4. Sistema de diseño</h2><p>Identidad: verde #25634B, crema #F6F7F2 y arcilla #A54F32; modo oscuro con superficie #1D2923 y fondo #171D19. Los roles semánticos se apoyan en ColorScheme Material 3. Radios centralizados: campos 24, botones 26, tarjetas 28, diálogos 32; píldoras en navegación y filtros. Son decisiones de Mesa, no medidas atribuidas a otras aplicaciones.</p><p>Espaciado basado en 4/8, separaciones de 8/12/16/24/32, lectura limitada a 1200 px y objetivos táctiles configurados de 48 px. Títulos 28 px, secciones 21 px, ingredientes/pasos 17 px con interlineado generoso. Segoe UI en Windows y sustitución por el sistema cuando no existe en Android. El tamaño depende de la función, no se agrandan todos los controles.</p>
<h2>5. Componentes</h2><p>MesaPageHeader reúne título, subtítulo y acción secundaria. MesaInteractiveCard aporta superficie, contorno, ratón y foco. MesaNavigationItem señala la sección actual. RecipeSection organiza bloques de lectura. El tema común configura botones, entradas, chips, menús, diálogos, hojas inferiores y avisos. Se conservan indicadores, estados vacíos y errores recuperables de recetas.</p>
<h2>6. Animaciones e interacciones</h2><p>Transiciones breves de 180 ms para selección, tarjetas y pasos de cocina. Las nuevas animaciones consultan disableAnimations y usan duración cero al reducir movimiento. Los controles Material mantienen respuesta a presión, foco, selección y desactivación. La compra muestra progreso al marcar elementos; los campos tienen foco destacado. No se añade movimiento permanente.</p>
<h2>7. Rendimiento</h2><p>Se reutilizan Flutter y las dependencias existentes. El rediseño evita desenfoques, vídeo y animación continua. Se preservan apertura progresiva y consultas de fotos: texto, imágenes y traducción avanzan independientemente. Las URLs se guardan; los bytes de fotos no se añaden a base de datos, sincronización ni exportación. Decodificar una foto visible sí necesita memoria temporal.</p><p class="notice">No se ha medido una distribución de tiempos de cuadro o de apertura antes/después en el mismo dispositivo físico. Compilar y superar pruebas no demuestra por sí solo rendimiento idéntico.</p>
<h2>8. Archivos importantes</h2><p><code>client/lib/design.dart</code> (tokens/componentes), <code>ui.dart</code> (tema/navegación), <code>library.dart</code> (recetario/catálogo), <code>pages.dart</code> (receta/cocina/semana/compra/ajustes), <code>editor.dart</code>, <code>recipe_preview.dart</code>, <code>photos.dart</code>. Versión/notas: <code>client/pubspec.yaml</code> y <code>client/update_notes.json</code>. Pruebas: <code>modern_design_test.dart</code> y <code>layout_research_test.dart</code>. Dossier: <code>scripts/audit_mesa.py</code> y <code>scripts/finalize_modern_design.py</code>.</p></section>
<section id="pruebas"><h2>9. Comprobación final</h2><p><strong>133 pruebas Flutter aprobadas y análisis sin incidencias; 92 pruebas Python aprobadas.</strong> Starlette/httpx emite una advertencia de deprecación sin fallo de pruebas. Se compilaron Windows x86_64 y Android ARM64 release; se verificaron firma familiar, registro de plugins, manifiesto, descarga HTTPS completa y SHA-256. Windows se abrió con su proceso y ventana. Android se probó adicionalmente en MesaTest x86_64 con main.dart de producción; los recorridos exactos están en la ficha nativa.</p><p>La variante del emulador inicialmente mantuvo el filtro ARM64 y falló por ausencia de libflutter.so. Se conservó la evidencia y se compiló con <code>-PmesaAbis=x86_64</code> explícito. Ese ensayo fallido no se atribuye a la APK ARM64 publicada. Las capturas Flutter usan fuentes de Windows y datos sintéticos; no se presentan como teléfono físico.</p><p>La matriz agrupa criterios de aceptación, no todos los comportamientos posibles. APROBADO se limita al entorno indicado.</p><div class="table"><table><thead><tr><th>Caso</th><th>Requisito</th><th>Estado</th><th>Alcance ejecutado</th><th>Evidencia</th></tr></thead><tbody>__ROWS__</tbody></table></div>
<h2>10. Limitaciones pendientes</h2><p>Uso e instalación en teléfono físico, ciclo familiar entre dos dispositivos físicos por Tailscale, revisión con TalkBack/Narrador y conformidad completa WCAG 2.2 AA, comparación reproducible de rendimiento. Los adaptadores externos pueden cambiar: los fixtures no certifican cada receta de todos los sitios.</p><p class="notice">La traducción exclusivamente remota y gratuita aún no está implementada. Mesa conserva el motor local Windows y ML Kit Android. Azure Translator F0 y un proxy remoto fueron investigados, pero falta configurar proveedor y credenciales. La investigación no equivale a una conexión activa y el rediseño no sustituye ese trabajo.</p></section>
<section id="dossier"><h2>Metodología aplicada a Mesa</h2><p>Modo: análisis del proyecto disponible y rediseño implementado. Caja negra estudia entradas/resultados sin conocer el interior; caja gris combina observación con paquetes y registros. Aquí hay además código fuente, que permite contrastar la implementación. El análisis estático examina código y paquetes sin ejecutarlos; el dinámico observa una ejecución. Caracterización transforma reglas observadas en pruebas repetibles.</p><p>Desensamblar representa instrucciones de bajo nivel; descompilar reconstruye una representación de código más alto, sin garantizar repositorio, nombres ni comentarios originales. No se usaron JADX, Apktool o Ghidra: el código disponible responde mejor a las preguntas de este alcance. DEX contiene puentes Kotlin/SDK; Dart release usa AOT en bibliotecas nativas. No se promete recuperar el fuente Dart desde DEX.</p>
<h3>Originales, identidad y entorno</h3><p>Laboratorio: <code>output/auditoria-mesa-2026-10-12</code>, dividido en 00_alcance, 01_originales, 02_inventario, 03_observacion_ui, 04_analisis_estatico, 05_analisis_dinamico, 06_datos_y_red, 07_especificacion, 08_reconstruccion, 09_validacion y 10_informe. Copias APK/EXE 1.11.2+25 preservadas con SHA-256. El hash acredita identidad de bytes, no confianza universal en un archivo.</p><p>Inventarios baseline/candidate: tamaño, fecha, versión, arquitectura y hashes de fuentes. Cabeceras reales: Windows PE x86_64; APK ZIP con manifiesto, DEX y ELF ARM64. aapt registra permisos/componentes, apksigner verifica certificado. La línea inicial de hashes de fuentes se capturó durante el rediseño: no es un checkout intacto de 25. Tampoco hay referencia visual anterior congelada; no se afirma comparación de píxel con la versión vieja.</p>
<h3>Modelo y datos observados</h3><pre>Flutter → Cookbook/estado → reglas/validación
              ↓                   ↓
         SQLite local       API familiar FastAPI
         entidades/outbox   SQLite, cambios/historial
              ↓                   ↓
         reintentos         deduplicación y conflictos
Fotos: URL → descarga visible → memoria temporal → liberación
Traducción actual: API familiar → Ollama local; alternativa Android ML Kit
Actualización: feed HTTPS → APK verificada → instalador del sistema</pre>
<p>OBSERVADO en código, confianza alta: entities almacena id/tipo/revisión/JSON/borrado; outbox conserva operaciones; conflicts contiene propuestas; prefs guarda preferencias. El token usa almacenamiento seguro separado. El servidor conserva entidades, cambios, operaciones, historial, usuarios e invitaciones. Confianza alta expresa lectura directa respaldada por casos de prueba, no porcentajes inventados.</p><p>Guardar valida y serializa escrituras en una transacción local. Una operación ya intentada conserva su identidad al reintentar. La sincronización se inicia y se repite cada 15 s, evitando llamadas simultáneas. Snapshot por páginas conserva datos locales hasta completarse. El servidor rechaza escrituras de lectores, IDs reutilizados con contenido distinto y generación antigua. La revisión conflictiva conserva propuesta; los ensayos usan datos sintéticos.</p>
<h3>Estados y reglas de aceptación</h3><div class="table"><table><tr><th>Evento</th><th>Precondición / salida</th><th>Efecto / recuperación</th></tr>
<tr><td>Guardar</td><td>Datos válidos → receta visible</td><td>Transacción local + outbox; sin red sigue pendiente</td></tr>
<tr><td>Importar</td><td>URL pública admitida → ficha dentro de Mesa</td><td>Original/procedencia; fallo permite reintento</td></tr>
<tr><td>Traducir</td><td>Idioma extranjero → español revisable</td><td>Cifras comprobadas; original conservado; respuesta tardía no sustituye una edición nueva</td></tr>
<tr><td>Raciones</td><td>Factor válido → cantidades ajustadas</td><td>Escala antes de redondear; originales guardados intactos</td></tr>
<tr><td>Push</td><td>Conexión + token → envío</td><td>Mismo ID al reintentar; conflicto conserva propuesta</td></tr>
<tr><td>Actualizar</td><td>Feed válido + versión posterior</td><td>HTTPS/tamaño/hash/paquete; permiso y confirmación del instalador</td></tr></table></div>
<p>Persistencia offline: una receta sintética se guarda en SQLite, se cierra/reabre la base y se reconstruye Cookbook dentro del mismo proceso Dart. Eso demuestra ese caso de persistencia en disco, no cualquier cierre forzado. El ensayo de reinicio nativo adicional se documenta en su propia ficha, sin extrapolar al recetario familiar.</p>
<h3>Contratos y red</h3><p>Inventario estático: 17 rutas respaldadas por server/app.py, para salud, identidad, invitación, emparejamiento, miembros, snapshot, cambios, push, historial, importación texto/URL, traducción, preparación del modelo, catálogo, exportación y backup. No es HAR ni demuestra todas esas llamadas en una sesión real. TestClient ejecuta peticiones en proceso y los mocks del cliente simulan respuestas concretas. La descarga pública HTTPS de esta entrega sí es tráfico real. No se copiaron bases familiares, claves ni tokens al informe.</p>
<p>INFERIDO, confianza media: agrupar opciones avanzadas probablemente reduce esfuerzo de búsqueda. Evidencia: menos controles simultáneos y ubicación estable; alternativa: un usuario experto puede preferir todos abiertos. Prueba que podría refutarlo: tiempo/errores de tareas con usuarios familiares. DESCONOCIDO: tasa de fallos en teléfonos no ensayados, precisión de traducción de todas las recetas y rendimiento físico comparado.</p>
<h3>Procedimiento reproducible</h3><p>Versiones efectivas: 02_inventario/flutter-version.json, python-dependencies.json, aapt-version.txt y test-environment.json. Flutter/Dart prueban y compilan; Python/pytest contrastan reglas/API; aapt inspecciona paquetes; apksigner firma/certificado; adb observa el emulador; SHA-256 compara bytes. No se necesita root en el teléfono familiar. Los comandos siguientes se ejecutaron; los logs guardan resultados y el script nativo registra cada acción:</p><pre>powershell -File scripts/check_client.ps1
.venv/Scripts/python.exe -m pytest -q
powershell -File scripts/build.ps1 -Target both -SkipPublish
.venv/Scripts/python.exe scripts/audit_mesa.py --stage baseline
.venv/Scripts/python.exe scripts/publish_android_update.py [APK ARM64 preservada]
.venv/Scripts/python.exe scripts/verify_update_release.py --client-tests 133 --server-tests 92
.venv/Scripts/python.exe scripts/audit_mesa.py --stage candidate</pre>
<p>Para repetir se usan SQLite temporal/memoria, fixtures y tokens sintéticos; el ensayo nativo usa MesaTest. No se debe limpiar una base real para reproducirlo. Las pruebas de fidelidad son funcionales acotadas con fuente disponible, no reconstrucción independiente ni recuperación de una infraestructura desconocida.</p></section>
<section id="fuentes"><h2>Referencias primarias y su adaptación</h2><p>Se estudiaron principios publicados, no cuentas privadas. Las fechas difieren: los diseños históricos no se presentan como versión exacta actual de cada app. La adaptación siguiente es criterio de Mesa, no una copia literal.</p><ul>
<li><a href="https://developer.apple.com/design/tips/">Apple: legibilidad, contraste, espacio y precisión táctil</a> → jerarquía y objetivos de interacción.</li>
<li><a href="https://linear.app/changelog/2024-03-20-new-linear-ui">Linear: jerarquía, equilibrio y densidad</a> y <a href="https://linear.app/changelog/2019-12-18-new-command-menu">agrupación contextual</a> → Opciones y énfasis por tarea. No se implementa una paleta de comandos equivalente.</li>
<li><a href="https://www.notion.com/help/navigate-with-the-sidebar">Notion: destinos y grupos laterales</a> → separación entre navegación, contenido y ajustes.</li>
<li><a href="https://newsroom.spotify.com/2021-04-29/listeners-can-explore-their-spotify-collections-faster-and-easier-with-a-new-your-library-2/">Spotify: búsqueda, filtros y cuadrícula</a> → favoritas/rápidas visibles; resto en Filtros.</li>
<li><a href="https://news.airbnb.com/en-au/a-new-airbnb-for-a-new-world-of-travel-launching-the-biggest-change-to-the-platform-in-a-decade">Airbnb: descubrir por categorías</a> → explorar separado de guardar, tarjetas reconocibles y categorías.</li>
<li><a href="https://www.revolut.com/blog/post/revolut-10/">Revolut 10: simplificación y accesos frecuentes</a> → acción principal clara y navegación estable.</li>
<li><a href="https://api.flutter.dev/flutter/material/NavigationBar-class.html">Material 3 / Flutter NavigationBar</a> → destinos principales y estados. m3.material.io no devolvió texto legible; se contrasta con la API oficial accesible.</li>
<li><a href="https://blog.duolingo.com/core-tabs-redesign/">Duolingo: coherencia con propósito</a> → cabeceras/espacios consistentes, progreso útil y transiciones breves.</li>
<li><a href="https://samsungfood.com/recipe-box-app/">Samsung Food</a> y <a href="https://pages.kitchenstories.com/en/app">Kitchen Stories</a> → tareas de recetas/cocina que complementan referencias visuales.</li>
<li><a href="https://docs.flutter.dev/testing/overview">Flutter: clases de pruebas</a>, <a href="https://developer.android.com/tools/apksigner">Android: apksigner</a>, <a href="https://www.sqlite.org/wal.html">SQLite: WAL</a> → validación y límites.</li></ul><p>Se intentaron artículos antiguos de Spotify Design y Airbnb Design; devolvieron 404. Se usan las referencias primarias accesibles anteriores, sin atribuirles el contenido de páginas fallidas.</p></section><footer>Mesa 1.12.0+26 · Las evidencias de cada caso definen el alcance de su aprobación.</footer></main></html>'''.replace('__ROWS__', rows)
    target = ROOT / 'auditoria-rediseno-mesa.html'
    target.write_text(report, encoding='utf-8')
    (LAB / '10_informe/auditoria-rediseno-mesa.html').write_text(
        report.replace('href="output/', 'href="../../../output/').replace('src="output/', 'src="../../../output/'), encoding='utf-8')
    print(json.dumps(dict(report=str(target), cases=counts, screenshots=len(captures)), ensure_ascii=False))


if __name__ == '__main__':
    main()

