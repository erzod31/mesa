# Mesa 1.18.0 (código 35) · actualización desde la app

Windows y Android incluyen `Mi espacio > Actualizar Mesa`: versión instalada,
búsqueda, descarga verificada y confirmación para el instalador de su sistema.
Windows añade canal firmado y asistente independiente para cerrar y reabrir
Mesa conservando datos. Android conserva el certificado familiar. Los canales
candidatos no se han publicado: Android sigue anunciando 1.16.0+32 y el feed
Windows queda pendiente de activación. Las copias Windows antiguas necesitan
una primera instalación manual. [Flujo, transición y límites](docs/IN-APP-UPDATES.md).

## Indra OCR

La lectura de fotos usa Indra OCR en el ordenador de Mesa, con modelos CPU
incluidos y reutilizados entre lecturas. Funciona desde archivos en Windows
y cámara, archivos o Compartir en Android. Android necesita conexión con ese
ordenador; las fotos no se guardan ni se envían a un servicio OCR externo.
El texto se añade a notas con su atribución y licencia. Revisa cantidades y
pasos. [Funcionamiento y condiciones](docs/OCR-INDRA.md).

La APK de esta entrega se construye localmente; el canal de actualización
publicado no se cambia automáticamente.

## Instalador Windows por usuario

Toda entrega incluye instalador Windows. El paquete vigente se identifica en
`dist/windows-installer.json`. Incluye la app, el servidor y sus componentes de ejecución y traducción básica;
no exige Python ni herramientas de desarrollo. Tiene accesos directos y
desinstalación que conserva los datos. La versión Android publicada sigue siendo
1.16.0+32 hasta publicar explícitamente la nueva APK; sus paquetes anteriores se conservan. Detalles de uso y compilación:
[docs/WINDOWS-INSTALLER.md](docs/WINDOWS-INSTALLER.md). La opción de perfil aislado
permite comprobar el arranque sin usar las recetas, credenciales ni notificaciones
del perfil normal.

---

# Mesa 1.16.0 (código 32) · catálogo por países y cocina paso a paso

Descubrir reúne las **11 fuentes habilitadas** en una búsqueda conjunta, con un único selector por país de la publicación. El registro conserva **25 fuentes**: 11 catálogos con licencia publicada y 14 sitios originales pendientes de autorización. El país describe la ubicación o edición de la fuente, no el origen de cada plato. Recetas para encantar se añade bajo CC BY-NC 3.0, con cantidades, preparación, autoría y fotos originales. Las adaptaciones conservan el acceso al original; no se activan editores por el mero envío de solicitudes.

Las búsquedas intercalan fuentes, limitan a tres las consultas simultáneas por búsqueda, conservan cursores independientes y permiten recuperar una fuente fallida sin bloquear las demás. Cambiar de país mantiene el término buscado y descarta resultados antiguos. Las tarjetas se crean al desplazarse y muestran las imágenes completas para conservar marcas de agua.

**Paso a paso** está disponible en las recetas guardadas y desde la vista previa, sin guardar antes. Incluye anterior/siguiente, índice de instrucciones, ingredientes marcables y reanudación; al terminar se reinicia el avance. Se mantienen los temporizadores de la aplicación. No se inventan instrucciones ni fotografías cuando faltan en la fuente.

Validación: análisis Flutter limpio, **172 pruebas del cliente y 129 del servidor**, tres fuentes españolas comprobadas en vivo y pruebas de interfaz con texto ampliado a 320, 390 y 1360 píxeles. La prueba en un teléfono ARM64 físico sigue pendiente. Actualiza Android desde Mi espacio → Actualizar Mesa o instala `dist/Mesa-Android-1.16.0-32.apk` encima de la versión anterior.

Las fotos siguen siendo referencias en línea sin archivos persistentes en la aplicación; las de Mesa polaca requieren el servidor familiar conectado. Las secciones siguientes describen versiones anteriores.

---

# Mesa 1.15.0 (código 31) · fuentes con permisos verificables

La versión actual es **Mesa 1.15.0**. Se añaden CreatiVegan, con lector de sus tarjetas y formatos antiguos, y **12 fichas fotografiadas de Mesa polaca** en español. Se conservan cantidades originales, créditos y licencias. El registro contiene 24 fuentes: 10 catálogos habilitados y 14 sitios de consulta pendientes de autorización del editor. Descubrir empieza con La cocina delokos. Las recetas ya guardadas no se eliminan.

Los textos de Mesa polaca se incluyen en Windows y Android y se abren sin conexión. Sus fotografías requieren el ordenador conectado: este descarga el PDF oficial (21 MB) en RAM, comprueba SHA-256 y extrae la imagen de una página revisada. Se admite un solo documento en RAM durante cinco minutos, con descarga limitada a 30 MB y salida de imagen limitada a 10 MB. No hay copias de fotos en disco. Las fotos web se consultan directamente. La primera foto del PDF puede esperar a su descarga; el texto aparece antes.

Las fuentes comerciales no se consideran autorizadas por tener una página legible. Con autorización expresa del usuario, se enviaron cuatro solicitudes por Gmail a Petitchef, Anna Recetas Fáciles, Food Hero y FAO. **Las respuestas y las autorizaciones siguen pendientes.** Una petición enviada no equivale a un permiso concedido. La revisión visual dejó FAO Chile fuera del catálogo fotográfico porque usa ilustraciones. Alberta y AGROSAVIA siguen pendientes de resolver sus descargas oficiales y revisar contenidos. Las otras decisiones están en [estado-fuentes-mesa.html](estado-fuentes-mesa.html) y [aplicacion-fuentes-2026-10-16.html](aplicacion-fuentes-2026-10-16.html).

Validación de esta publicación: análisis Flutter sin incidencias, **162 pruebas del cliente y 121 del servidor**, prueba adicional con CreatiVegan real, APK ARM64 y firma comprobadas por HTTPS y prueba nativa release en el emulador dedicado MesaTest (crear, guardar, cantidades, cocinar, reiniciar y navegar). No se ha instalado en un teléfono ARM64 físico.

Actualiza Android desde Mi espacio → Actualizar Mesa o instala `dist/Mesa-Android-1.15.0-31.apk` encima de la versión anterior. El servidor requiere `pypdf==6.10.0`, registrado en requirements.txt y requirements-lock.txt. Las secciones siguientes conservan el historial de versiones anteriores; sus recuentos y disponibilidades no describen la política actual.

---

# Mesa · Recetario familiar

**Mesa 1.14.2+30 refuerza la estabilidad y el uso con recetarios grandes.** La importación completa y su cola se guardan en una sola transacción; se rechazan identificadores duplicados o ausentes y se mantienen categorías y referencias. La sincronización agrupa hasta 25 entidades independientes, conserva reintentos sin duplicados y detecta respuestas equivocadas o descargas sin avance. Se alinean fechas y datos válidos entre cliente y servidor. Los diálogos conservan sus controles hasta terminar de cerrarse; un borrador o temporizador dañado no rompe la apertura. Las imágenes y archivos se leen con límites; el OCR Android reduce fotos grandes fuera del hilo de interfaz. Los catálogos excluyen categorías y noticias. Validación actual: 157 pruebas Flutter, 113 Python, análisis limpio, 2.000 recetas en pruebas de carga, 53 bases de laboratorio íntegras, OCR nativo de 64 millones de píxeles, cinco traducciones reales, Windows abierto y Android de lanzamiento verificado en emulador. APK ARM64 firmada y descarga HTTPS comprobada. El teléfono físico, las fuentes con límites externos y la traducción exclusivamente en la nube conservan pendientes. Informe: [auditoria-estabilidad-mesa.html](auditoria-estabilidad-mesa.html).

**Mesa 1.14.0+28 aplica la investigación de menús y botones a Windows y Android.** Crear e importar están juntos y a un clic, sin cubrir las tarjetas. Android abre las acciones secundarias en un panel inferior con grupos y cierre explícito; escritorio usa un menú anclado que recibe foco y se cierra con Escape. Compra y edición se muestran directamente si la ficha dispone de ancho suficiente. La navegación conserva búsquedas y filtros; las páginas ocultas dejan de recibir foco y liberan sus fotografías. Se mantienen permisos, originales y cantidades. Validación: análisis limpio, 144 pruebas Flutter, seis pruebas de menús repetidas con el tema de Mesa, Windows respondiendo y recorridos nativos en Android de lanzamiento x86_64. APK ARM64 firmada y descarga HTTPS verificadas. El teléfono físico sigue pendiente. Investigación, capturas y límites: [investigacion-menus-mesa.html](investigacion-menus-mesa.html).

**Mesa 1.13.0+27 renueva la interfaz, el logo, los iconos y el inicio.** Navegación inferior móvil, panel lateral en Windows, filtros frecuentes visibles, vista previa de receta a pantalla completa y acciones agrupadas. Identidad original de cuenco y m, icono adaptativo/monocromo Android y un estado de inicio sin espera decorativa. Se corrige además la eliminación del icono de notificación durante la optimización de Android. La revisión de espacios y clics comprueba que favorito y tarjeta ejecutan acciones separadas y que los destinos no se solapan. Validación: 138 pruebas Flutter, análisis limpio y 92 pruebas de servidor. Investigación, encuestas publicadas, evidencias y límites: [identidad-y-comprobacion-mesa.html](identidad-y-comprobacion-mesa.html). Dossier de la fase funcional: [auditoria-rediseno-mesa.html](auditoria-rediseno-mesa.html). La prueba en teléfono físico y la traducción exclusivamente remota siguen pendientes.

La geometría maestra del logo está en `branding/mesa-mark.json`; a partir de ella se generan los activos comunes. Después de generar, se formatea `client/lib/brand_paths.dart`. El emulador usa una APK x86_64 de laboratorio y no sustituye la prueba de la APK ARM64 en el teléfono. La traducción no cambia en esta entrega: se mantienen los motores existentes; los proveedores remotos investigados todavía no están configurados.

**Mesa 1.11.2+25 corrige el traductor Android de lanzamiento.** R8 eliminaba constructores necesarios para registrar ML Kit; ahora se conservan y se verifican dentro de la APK. Se probó una compilación de lanzamiento en un emulador Android real con cinco recetas completas y con lectura/cocina en español. Las recetas guardadas se traducen para lectura sin sobrescribir tus ediciones. Android utiliza su motor local tras una espera de 30 s al PC; el glosario y los errores de descarga permiten reintentar. Se corrige una duplicación consecutiva de cantidades únicamente cuando se recuperan todas las cifras originales. Validación: 130 pruebas Flutter, 92 Python, firma original y descarga HTTPS verificadas; Windows actualizado en ejecución. Android físico pendiente.

La comparación con las mismas cinco recetas encontró 3/5 resultados válidos para TranslateGemma 4B y 5/5 para 12B en una sola solicitud. Se conserva 12B y se prepara al abrir o reanudar Mesa para adelantar el coste de carga. DeepL, Azure y CTranslate2 se analizan en [investigacion-traduccion-rapida.html](investigacion-traduccion-rapida.html); no se ha activado una API externa ni se ha demostrado su equivalencia de calidad para estas recetas.

**Mesa 1.11.1+24 corrige la traducción y simplifica la lectura.** La traducción no se pierde al llegar los metadatos de fotos; una respuesta sin traducir no se acepta como terminada. Los fallos permiten reintentar sin volver a descargar la receta. Las importaciones extranjeras sin idioma declarado y las vistas antiguas de esos catálogos usan el idioma de la fuente. Ingredientes y preparación tienen prioridad; **Original, medidas y fuente** reúne los controles secundarios. La fuente y la actualización están en el menú de la ficha, y abajo quedan Cerrar y Guardar. Se conservan todas las fotos como referencias en línea y las cantidades originales. No se sobrescriben automáticamente recetas personales editadas. Validación final: 123 pruebas Flutter y 92 Python, Windows actualizado en ejecución, firma original y descarga HTTPS verificadas. La prueba en un teléfono Android físico sigue pendiente.

**Mesa 1.11.0+23 mejora la apertura de recetas.** La ficha se abre sin esperar a la traducción; el texto, las fotos y el español se completan de forma independiente. Las vistas ya consultadas se muestran primero desde el dispositivo y se pueden actualizar mediante el botón de la fuente. No se actualizan automáticamente los pasos mientras se leen. La caché privada del servidor reutiliza traducciones validadas incluso después de reiniciarlo; al explorar fuentes extranjeras prepara el modelo en segundo plano. Las fotos siguen sin almacenarse en disco: portada y miniatura visibles comparten una consulta temporal, las miniaturas usan menos resolución y la galería limita las descargas simultáneas. Investigación, decisiones y mediciones en [investigacion-apertura-recetas.html](investigacion-apertura-recetas.html). Validación final: 114 pruebas Flutter y 89 Python, Windows en ejecución, APK con firma original y descarga HTTPS verificada. La prueba en Android físico sigue pendiente.

Primera aplicación funcional para Windows y Android, con datos locales y servidor familiar privado a través de Tailscale. La investigación de funciones y catálogos españoles está en `investigacion-mejoras-mesa.html`. La revisión de importación del 11 de octubre de 2026, con 47 sitios probados y cinco revisiones documentales adicionales, está en [investigacion-importacion-recetas.html](investigacion-importacion-recetas.html). La investigación inicial está en `investigacion-app-recetas.html`; las decisiones y fuentes utilizadas durante la construcción, en `docs/DECISIONES.md`.

Mesa 1.10.2 añade Based Cooking (textos y fotos de dominio público) y Wikibooks en inglés, francés, italiano, portugués y alemán (CC BY-SA; cada foto necesita licencia libre comprobada). Conserva las 16 fuentes seleccionadas y mantiene retiradas las otras 22: ahora hay 22 fuentes, 21 con consulta dentro de Mesa. Los nuevos totales figuran como no verificados, nunca como cero ni con una posición inventada. Los sitios editoriales existentes mantienen consulta/importación individual y sus derechos; su accesibilidad no equivale a permiso de republicación.

**Mesa 1.10.3+22 corrige la traducción.** El ordenador utiliza TranslateGemma local; Android lo consulta por la conexión privada de Mesa y conserva ML Kit con glosario culinario como alternativa sin ordenador. La primera descarga del modelo Android necesita Internet y admite datos móviles. **Volver a traducir** permite rehacer una traducción antigua desde el original, revisar el resultado y aplicarlo. Las cantidades y sus unidades se protegen antes de traducir; las equivalencias europeas se calculan después, al mostrar la receta. No se envían recetas a un traductor web. Los textos generados por Mesa en español se conservan. Las traducciones automáticas siguen necesitando revisión.

En este ordenador está instalado TranslateGemma 12B, ejecutado solo en `127.0.0.1:11435`. En otra instalación con Ollama disponible, ejecuta `scripts/setup_quality_translation.ps1 -Size 4b` (modelo de unos 3,3 GB) o `-Size 12b` (unos 8,1 GB y más memoria). **Iniciar-Mesa.cmd** inicia también el traductor configurado. Los modelos permanecen en `.tools/ollama-models`, fuera de la APK. El respaldo básico se prepara con `scripts/setup_opus_translation.py`, `scripts/setup_translation.py` y `requirements.txt`. Consulta [la revisión de traducción](docs/TRADUCCION.md).

Las medidas europeas aparecen por defecto en consulta, cocina y compra: equivalencias prácticas y redondeadas, por ejemplo 1 libra → 450 g y 350 °F → 180 °C. La harina, el azúcar y la mantequilla tienen equivalencias de taza por ingrediente; los alimentos desconocidos mantienen volumen, sin inventar densidades. Al cambiar raciones, se escala antes de redondear. Activa **Medidas originales** para consultar las cantidades guardadas. Las cantidades por confirmar permanecen por confirmar.

La transmisión privada comprime respuestas, descarga el recetario por páginas y conserva los datos locales hasta recibirlo completo. Los reintentos de envío usan el mismo identificador para evitar duplicados. Ninguna foto se incorpora como archivo a la APK, caché persistente, sincronización o exportación: se consultan sus URLs y se muestran con memoria temporal. Se han corregido cantidades mezcladas con recetas relacionadas, pasos abreviados y galerías incompletas en los formatos revisados. La versión anterior pasó 94 pruebas Flutter y 66 Python. La revisión 1.10.3 amplía las pruebas de traducción. No se ha probado un Android físico.

## Empezar en este ordenador

1. Abre **Iniciar-Mesa.cmd**. Inicia el servidor y conecta el escritorio como administrador. Conserva esta carpeta completa: el ejecutable por sí solo no incluye el servidor ni sus datos.
2. Crea una receta. Solo el nombre es obligatorio. Ingredientes y pasos: uno por línea. Los borradores se guardan mientras escribes.
3. En **Mi espacio**, puedes añadir ejemplos, importar enlaces o texto, exportar, ver la papelera y crear copias.
4. Abre **dist/Mesa-Android.apk** en un Android de 64 bits. Permite la instalación desde la aplicación con la que abras el APK. Es una distribución familiar firmada, no una publicación en Google Play.
   La selección de fuentes introducida en **1.7.2 (código 14)** conserva únicamente las primeras 16 fuentes del ranking, retirando todas desde el puesto 17 y las tres sin posición, con filtros por país, orden por recetas, disponibilidad o nombre y enlace de comprobación de cada cifra publicada. Se retiraron Cocina del Caribe, Arracacha y Sabores Andantes. La base conserva las primeras 16 fuentes del ranking en español; 1.10.0 añade seis fuentes libres según la petición posterior. Todas las fotos se consultan directamente desde sus enlaces públicos; no se incluyen en la APK ni se guardan en recetas, borradores, caché de catálogo, sincronización o exportaciones. Los textos guardados funcionan sin conexión; las fotos necesitan Internet. Instala encima de la anterior para conservar el recetario. La construcción verifica actividad, plugins y JNI.
5. Activa Tailscale en el teléfono, con acceso a la red o al ordenador compartido. En Windows entra en **Mi espacio → Familia y conexión → Invitar familiar**, crea un código y escanea el QR o introduce la dirección y el código en Android. El código caduca en 10 minutos y se usa una vez.

La versión actual es **Mesa 1.10.2 (código 21)**. Instala esta APK una vez encima de la anterior, sin desinstalar. Para las siguientes versiones entra en **Mi espacio → Actualizar Mesa → Descargar actualización → Instalar actualización**. Se muestran la versión instalada, las novedades y el progreso; puedes cancelar y reintentar. La descarga usa el servicio privado HTTPS del ordenador y verifica tamaño, SHA-256, paquete, versión superior, compatibilidad y la misma firma antes de abrir el instalador. Android puede pedir que permitas a Mesa instalar aplicaciones; al volver sin conceder el permiso, la app permite reintentar sin reabrir los ajustes en bucle. Confirma la instalación en Android. Se mantienen los datos y las credenciales porque no se desinstala la app ni se cambia su identidad.

Mesa 1.9.1 abre las recetas de **Descubrir dentro de la app**, aunque Android no esté conectado al servidor familiar. Lee directamente cantidades, preparación y fotografías por URL de las fuentes disponibles; Kiwilimón usa su API pública y el resto los datos estructurados o las secciones de la receta. Si el servidor familiar falla, intenta la lectura pública. La página original solo se abre al pulsar **Ver fuente original**. Los errores se muestran dentro de Mesa con **Reintentar**. Se mantienen revisión y guardado, galerías y vistas guardadas sin conexión. Validación de la publicación: análisis limpio, **87 pruebas del cliente y 55 del servidor**, 16 muestras reales con ingredientes, pasos y enlaces de fotos de las 13 fuentes web seleccionables y tres recetas iniciales de Petitchef. La investigación posterior detecta contenido ajeno entre los ingredientes de Rechupete, Hogarmania y RecetasGratis, y galerías incompletas de Bon Viveur y RecetasGratis. Estos fallos siguen pendientes; la presencia de campos no acredita una importación íntegra. No se ha ensayado en un Android físico ni se ha auditado el catálogo completo. Registro: [investigacion-importacion-recetas.html](investigacion-importacion-recetas.html).

Mesa 1.9.0 simplifica la interfaz de Windows y Android. La biblioteca empieza con búsqueda y recetas; filtros, categorías, catálogos, etiquetas, orden y vista están en **Filtros**. En Descubrir, pulsa **Cambiar fuente** para elegir otra fuente, ver detalles o abrir el ranking. La ficha mantiene **Cocinar** como acción principal y reúne compra, planificación, edición, favoritas, historial y papelera en **Opciones**. El formulario deja visibles los campos principales y despliega fotos, organización y notas. Mi espacio agrupa conexión, copias, apariencia y temporizadores; el actualizador Android sigue visible. Análisis limpio, **79 pruebas del cliente y 55 del servidor**, compilaciones firmadas y descarga privada verificada. Capturas de pruebas, sin teléfono físico: [investigacion-diseno-mesa.html](investigacion-diseno-mesa.html).

Mesa 1.8.1 abre **Recetas → Descubrir** con Petitchef y muestra directamente 50 recetas con foto, sin introducir una búsqueda. El selector ordena las fuentes por tamaño de catálogo, con Petitchef primero; «Cargar más recetas» consulta un segundo bloque de 50 del listado público de últimas recetas. El buscador usa el formulario público de Petitchef. No se descargan copias de fotografías: se mantienen las URLs directas. Si el sitio no responde, se muestra un aviso y se puede reintentar; no se inventan recetas para alcanzar 50.

Mesa 1.8.0 reorganiza búsqueda, ficha y modo cocina para Windows y Android: bloques de ingredientes y preparación, controles persistentes, vista ampliada de escritorio, tarjetas adaptadas al ancho y letra grande. Paleta verde, crema y terracota con modo oscuro, contraste comprobado y formas compartidas. Compra y planificación tienen texto visible en Android; los ingredientes marcados pasan al modo cocina y cambiar de paso vuelve al inicio. Investigación de 13 webs, comparaciones visuales y evaluación de las herramientas: [investigacion-diseno-mesa.html](investigacion-diseno-mesa.html). Se mantienen las 16 fuentes seleccionadas y las fotografías por URLs directas.

Dirección privada configurada en este ordenador: **https://starfly.tailc69897.ts.net:9443**. La dirección también queda en `data/public-url.txt`. El escritorio conecta por `http://127.0.0.1:8765`; el teléfono usa HTTPS. No añadas `/v1` a la dirección. Para las actualizaciones también se necesitan Tailscale activo y el ordenador encendido, pero no el emparejamiento familiar. `Iniciar-Mesa.cmd` inicia el servicio de descargas en segundo plano junto al servidor.

El ordenador debe permanecer encendido para sincronizar. Los textos de las recetas guardadas, los borradores y la lista de compra funcionan sin conexión. Las fotos se consultan en línea y necesitan Internet. Al volver, la app transmite las operaciones pendientes y descarga cambios. Sincroniza al abrir o reanudar la app y cada 15 segundos mientras está abierta. No depende de ejecución continua en segundo plano de Android.

El servidor continúa activo al cerrar la ventana del recetario para que el teléfono pueda acceder. Para detenerlo: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/stop_server.ps1`. Tras reiniciar Windows, vuelve a abrir el lanzador. Para retirar solo el acceso de Mesa de Tailscale: `tailscale serve --https=9443 off`.

## Qué incluye

- Recetas, fotos, etiquetas, favoritos personales, valoración y búsqueda por título, ingredientes y notas; filtros combinables, orden y tema claro/oscuro.
- Trece categorías incluidas, categorías y catálogos familiares propios, organización múltiple por receta, renombrado y papelera.
- **Recetas → Descubrir → Cambiar fuente**: selector de 15 fuentes con lectores disponibles (Wikilibros, delokos y 13 catálogos web), botón **Ranking de fuentes · 16 fuentes**. Se conservan solo los puestos 1–16 del ranking revisado: de Petitchef a Wikilibros. Se retiraron las fuentes del puesto 17 en adelante y las tres sin posición. Nestlé Cocina España permanece como consulta del original. Búsqueda, filtro por país y orden por cantidad, país, disponibilidad o nombre; posiciones estables al filtrar, con fecha y enlace de comprobación. Los recuentos combinan cifras del editor, índices y entradas de catálogos; el orden es orientativo. Las recetas personales guardadas se conservan. Las fichas disponibles de Descubrir se pueden leer sin emparejamiento familiar; el importador genérico de enlaces utiliza el servidor. Estado detallado: `estado-fuentes-mesa.html`.
- Importador: límites de página de 4 MB, TLS estándar, DNS público fijado y redirecciones verificadas; JSON-LD y adaptadores WPRM/Tasty/HTML/Drupal. Extrae las referencias reconocidas de portada y pasos, con créditos individuales. La revisión posterior documenta galerías incompletas; no se garantiza recuperar todas las fotos de cada fuente. No descarga imágenes al importar ni al sincronizar.
- Galería por receta: deslizar, ampliar, elegir portada, añadir enlaces HTTPS o quitar fotos. Cada vista consulta la imagen desde su fuente con una conexión sin credenciales, sin caché persistente ni ImageCache de Flutter. Se usa RAM temporal para mostrarla y se libera al cerrar la vista o poner la app en segundo plano. Una foto que falla ofrece reintento; no impide leer la receta. Fotos antiguas sin URL dejan de adjuntarse; su texto permanece. La cámara y las imágenes compartidas se usan para OCR temporal.
- Cantidades originales conservadas, incluidas tablas con cantidad e ingrediente en celdas distintas. Los ingredientes sin cantidad muestran un aviso. En **Editar → Buscar receta con cantidades**, puedes revisar e incorporar ingredientes y raciones de otra receta española, manteniendo los créditos de ambas fuentes. Guarda después de revisarlos.
- El rendimiento distingue raciones de unidades. Si la fuente no declara rendimiento, se indica como pendiente de revisión. No se calcula una duración total sumando los tiempos de pasos.
- Creación sencilla, edición y borradores; importación de enlaces públicos con Recipe JSON-LD, texto y archivos Mesa. Siempre permite revisar antes de guardar.
- Android: cámara, recibir texto o imágenes desde Compartir, e Indra OCR en el ordenador familiar conectado que añade el texto a notas sin guardar la imagen ni usar servicios OCR de terceros.
- Cambio de raciones: interpreta cantidades al principio de cada línea, decimales y fracciones. Conserva expresiones ambiguas. Revisa unidades, cantidades y tiempos.
- Modo cocina con pasos grandes, ingredientes marcados, progreso personal guardado y pantalla encendida opcional.
- Varios temporizadores, pausa, reanudación y +1 minuto. Android solicita permisos al programarlos. Windows avisa mientras Mesa está abierta. En Android, negar alarmas exactas puede retrasar el aviso; forzar la detención de la app también afecta a las alarmas.
- Menú semanal, comida y cena, varias recetas por franja, raciones y envío de ingredientes a Compra.
- Compra compartida: productos manuales y de recetas; marcas de comprado sincronizadas. Conserva líneas separadas para evitar sumar unidades incompatibles. Quitar un plato del menú conserva lo que ya se añadió a Compra.
- Invitaciones de un uso, editor/lector, revocación, conflictos revisables, historial de las últimas 25 versiones por elemento, papelera, exportación e importación.
- Copia SQLite diaria mientras el servidor está activo, copia manual y restauración con copia de seguridad previa.

Las preferencias, favoritos, borradores, temporizadores y progreso de cocina pertenecen a cada dispositivo. Las recetas, categorías, catálogos, el menú y Compra se comparten. Las valoraciones de recetas también son compartidas; no hay votos independientes por miembro. La revocación impide sincronizar, pero no borra datos previamente descargados en otro dispositivo.

La galería conserva URLs y créditos, sin archivos de imagen. Una fuente sin foto o sin cantidad no permite inventar los datos ausentes. Las recetas antiguas de Wikilibros intentan recuperar su galería al abrirse; para otros enlaces usa **Editar → Recuperar fotos de la fuente**. Los lectores disponibles pueden recuperar referencias directamente; el lector del servidor valida las direcciones públicas. Mostrar fotografías requiere Internet y memoria temporal, sin caché persistente.

## Copias y recuperación

**Exportar datos** guarda un JSON con recetas, categorías, catálogos, menú, compra, fotos y propuestas en conflicto, sin credenciales. Importar crea nuevas copias de los elementos activos y conserva los vínculos de las recetas con el menú, categorías y catálogos. Las propuestas en conflicto incluidas en el JSON sirven como respaldo para revisión manual; no se importan automáticamente. La papelera tampoco se incorpora al importar.

**Copia del servidor** guarda todo el servidor, incluidos miembros e historial, en `data/backups`. Se hace además una copia cada día que está en ejecución. Las copias permanecen en el mismo disco: guarda alguna fuera del ordenador. No se eliminan automáticamente; revisa su tamaño y antigüedad. Las fotos actuales se representan mediante enlaces, sin archivos de imagen.

Para restaurar una copia **de esta instalación**:

1. Exporta el recetario en los dispositivos con cambios pendientes. Cierra Mesa en todos ellos.
2. Ejecuta `scripts/stop_server.ps1` desde PowerShell.
3. Ejecuta `.\.venv\Scripts\python.exe -m server.maintenance data/backups/NOMBRE.sqlite` desde esta carpeta.
4. Abre `Iniciar-Mesa.cmd` y después los clientes. La restauración cambia la generación del servidor para que descarguen el estado completo. Sus cambios pendientes se conservan y pueden producir conflictos que tendrás que revisar.

El restaurador valida integridad y formato y crea `antes-restaurar-*.sqlite` antes de sustituir los datos. No borres `data/desktop-connection.json` ni compartas ese archivo: contiene la credencial de administración. Conserva también `.tools/signing` de forma privada: su clave permite instalar futuras actualizaciones Android sobre esta versión.

## Construcción y pruebas

Entorno verificado: Flutter **3.47.7**, Dart **3.13.5**, Python **3.12**, Visual Studio Build Tools 2022 con C++ y Windows SDK, JDK de Android Studio, Android SDK 36 y NDK **28.2.13676358**. Dependencias Dart fijadas en `client/pubspec.lock`; Python en `requirements-lock.txt`.

Preparación en un nuevo checkout:

```powershell
git clone --depth 1 --branch 3.47.7 https://github.com/flutter/flutter.git .tools/flutter
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-lock.txt
```

El script de firma usa el JDK en `C:/Program Files/Android/Android Studio/jbr`; ajústalo si lo tienes en otro lugar. Instala los componentes C++ y ATL de Visual Studio antes de compilar Windows. Para esta instalación se preparó además ATL oficial dentro de `.tools/atl`, sin modificar archivos del compilador; CMake utiliza ese directorio si existe. Puedes reproducir su preparación con `.\.venv\Scripts\python.exe scripts/prepare_atl.py` (compilador MSVC 14.44). Se conservan las licencias del SDK Android en `.tools/android/licenses`.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1
.\.venv\Scripts\python.exe -m pytest server -q --basetemp=output/tests-nueva-ejecucion
```

`build.ps1` obtiene la ruta corta de Windows para evitar un fallo de native assets con espacios y prepara junctions locales para los plugins si Developer Mode está desactivado. Si el volumen no ofrece rutas cortas, usa un checkout sin espacios. No cambia la configuración global de Windows.

Validación de Mesa 1.4.1: **49 pruebas del cliente y 46 del servidor**, análisis Flutter limpio y compilaciones Windows/Android correctas. Se comprueban los 107 registros y 197 imágenes de los paquetes incluidos, cantidades, categorías, paginación, lectura sin red, atribución, redirecciones verificadas y exclusión de enlaces ajenos. Las muestras completas de 21 fuentes editoriales se contrastan con páginas públicas; la nueva carga directa devuelve fichas con foto en las 23 fuentes web seleccionables sin ninguna conexión familiar; cinco galerías se descargan en vivo sin imágenes pendientes. Las imágenes son renderizaciones de pruebas, no capturas de un teléfono físico.

Validación del actualizador 1.5.0: **58 pruebas del cliente y 48 del servidor**, análisis Flutter limpio. Las pruebas del flujo incluyen metadatos inválidos, redirecciones ajenas, fallos de red/verificación, progreso, cancelación, ausencia de instalación automática, versión/compatibilidad y permiso concedido o denegado al volver de los ajustes. El servicio se comprueba con descargas y cabeceras HTTP reales sobre un puerto temporal. La publicación conserva los APK anteriores con nombre inmutable y cambia atómicamente el manifiesto; rechaza reutilizar un número de versión para un archivo diferente.

Para publicar una versión nueva, incrementa el código en `client/pubspec.yaml`, escribe sus novedades en `client/update_notes.json` y ejecuta `scripts/build.ps1 -Target android`. Tras firmar y comprobar la APK, el script genera `dist/android-update.json`, un APK versionado y el enlace habitual `dist/Mesa-Android.apk`. Los clientes con 1.5.0 o posterior la encontrarán desde la app. Conserva la clave de firma privada. Si cambia el ordenador distribuidor, configura `MESA_UPDATE_FEED` mediante `--dart-define` al compilar el cliente. No borres APK versionados que todavía puedan estar descargándose. Para reiniciar el servicio de descargas: `scripts/start_download_server.ps1 -Restart`; solo gestiona el Python de esta instalación con la ruta absoluta de su script.

**Pendiente de comprobación en tu teléfono:** actualización con el instalador real de Android, compartir desde otras apps, cámara, precisión del OCR, notificaciones con pantalla bloqueada y sincronización entre Windows y Android. No había un teléfono conectado por ADB durante la construcción. No hay un instalador Windows independiente ni publicación en las tiendas; el servidor se ejecuta desde este proyecto.

## Estructura

La investigación ampliada de fuentes está en [investigacion-fuentes-recetas.html](investigacion-fuentes-recetas.html). delokos se conecta desde 1.3.0 para el uso familiar no comercial. Bon Viveur ya admite consulta e importación individual; Alberta permanece como consulta del original por bloqueo de acceso. En 1.4.0 se corrigen las galerías ausentes en JSON-LD, los ingredientes fusionados en Food Hero y los formatos de tiempo/rendimiento identificados en la investigación.

La revisión regional está en [investigacion-fuentes-latinoamerica.html](investigacion-fuentes-latinoamerica.html): 19 páginas HTML, cinco PDF examinados y ocho cabeceras de fotos comprobadas. Sabores Andantes se incluye desde 1.3.0 bajo CC BY 4.0: se preservan los créditos, las cantidades, las instrucciones y todas las fotos de sus fichas, excluyendo una receta sin foto. El paquete se prepara a partir del PDF revisado y su SHA-256. En 1.4.0 se incorporan los paquetes de Arracacha y Caribe; el directorio actualizado diferencia las otras fuentes según su disponibilidad real. El informe documenta diferencias de licencias, fotos de terceros, imágenes generadas con Firefly y declaraciones contradictorias.

`client/`: Flutter y SQLite local. `server/`: FastAPI, SQLite familiar y pruebas. `scripts/`: preparación, inicio, compilación y conexión Tailscale. `dist/`: ejecutables. `data/`: datos privados del servidor. `output/`: logs y verificaciones. `.tools/`: SDK y firma local. No se suben datos, claves o SDK a Git.

Los cambios locales se guardan con una operación en cola dentro de la misma transacción. Los envíos ya intentados quedan inmutables, incluso si se pierde su respuesta. El servidor aplica operaciones con identificador idempotente y compara la revisión base. Ante edición concurrente, se conserva la propuesta local y la versión familiar hasta que se elige conservar, duplicar o reemplazar. Marcar Compra asigna el estado deseado; no alterna a ciegas. Si el producto fue borrado, devuelve un conflicto sin resucitarlo.

La API pública V6 de Kiwilimón respondió sin cuenta en dos muestras con ingredientes, pasos e imágenes; es una candidata técnica al conector, pendiente de condiciones de reutilización y almacenamiento.

Validación de Mesa 1.6.1: análisis Flutter limpio, 63 pruebas del cliente y 51 del servidor. Consulta real de imágenes de Wikilibros y delokos con el transporte HTTPS y DNS fijado; APK firmada con la identidad anterior y descarga privada íntegra verificada. Los tres paquetes retirados están ausentes de la APK y de Windows. No se ha probado en un Android físico.

Ranking ampliado de Mesa 1.7.2: `server/source_counts.json` cubre todas las fuentes actuales. Las cifras revisadas de los editores se registran en server/reviewed_source_counts.json; el generador compartido comprueba la cobertura y genera el registro. Los totales no verificados no se representan como cero ni como recetas importadas. La selección del usuario queda fijada en server/source_selection.json para impedir que regenerar el registro restaure fuentes retiradas.

Validación de Mesa 1.7.2: análisis limpio, 68 pruebas del cliente y 52 del servidor. Windows actualizado y APK firmada publicada; descarga completa por Tailscale verificada. Sin prueba en un Android físico.
