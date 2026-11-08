# Investigación aplicada durante la construcción de Mesa

Fecha: 10 de octubre de 2026. Objetivo: una primera app Windows/Android para una familia, sencilla de usar y recuperable. La investigación se aplica a problemas observados, con decisiones y verificaciones concretas.

| Problema o duda | Decisión aplicada | Verificación y fuente primaria |
|---|---|---|
| Dos equipos editan la misma receta | Comparación de revisión; propuesta local preservada para revisión. No reemplazo silencioso. | Pruebas servidor/cliente de edición concurrente. [Guía Flutter offline first](https://docs.flutter.dev/app-architecture/design-patterns/offline-first), [transacciones SQLite](https://www.sqlite.org/lang_transaction.html). |
| Se pierde la respuesta después de guardar | Identificadores idempotentes; una operación intentada nunca se modifica. Una edición posterior crea otra operación. | Prueba que simula recepción perdida y edición durante un envío. [HTTP: operaciones idempotentes](https://www.rfc-editor.org/rfc/rfc9110.html#section-9.2.2). |
| El ordenador está apagado o se corta Tailscale | SQLite local y cola durable; sincronización al reanudar y cada 15 s con la app visible. | Reapertura de archivo SQLite y cambio de generación tras restauración. [Android: tareas en segundo plano](https://developer.android.com/develop/background-work/background-tasks). |
| Tailscale ya tiene servicios en 443, 8443 y 10000 | Añadir solamente HTTPS 9443, verificado libre, con proxy a loopback 8765. No configurar Funnel. | Comparación de los mapas anteriores y posteriores; `/health` HTTPS responde. [CLI Serve](https://tailscale.com/docs/reference/tailscale-cli/serve), [Serve privado](https://tailscale.com/docs/features/tailscale-serve). |
| Instalar SDK Android con herramientas nuevas devuelve éxito sin instalar plataformas | Usar `android.exe sdk install` por paquete, en lugar del wrapper `sdkmanager.bat` de herramientas 23. Añadir explícitamente NDK y CMake. | APK release compilado. [Nueva CLI Android](https://developer.android.com/tools/agents/android-cli). |
| Compilación de native assets falla por espacios en la ruta SDK | Usar la ruta corta del proyecto al invocar Flutter/Dart. Preparar junctions locales de plugins cuando no hay privilegio de symlink. | Windows release compilado y pruebas nativas SQLite. [Incidencias del proyecto Dart native](https://github.com/dart-lang/native/issues/3026), [corrección de rutas Windows](https://github.com/dart-lang/native/pull/3466). El error se observó en esta instalación; las incidencias describen problemas relacionados, no prueban por sí solas esta causa concreta. |
| `FilePicker.platform` ya no existe en versión 13 | Usar `FilePicker.pickFile`, leer `PlatformFile.readAsBytes` y guardar con `saveFile(bytes:)`. Este último ya escribe el archivo. | Análisis limpio y compilación. [API oficial del paquete](https://pub.dev/packages/file_picker). |
| Notificaciones Windows canceladas no se cancelan sin identidad MSIX | No dejar alarmas programadas en Windows: verificar temporizadores dentro de la app y emitir el aviso al terminar. Documentar que la app debe permanecer abierta. | Compilación y revisión de API. [Limitación Windows del paquete](https://pub.dev/documentation/flutter_local_notifications/latest/). Queda comprobación manual de notificaciones nativas. |
| Android necesita avisos al bloquear la pantalla | Canal local, receptores de arranque y permisos de notificaciones/alarmas exactas pedidos al crear temporizador. Si no se autorizan alarmas exactas, aviso de posible retraso. | Lint release y APK firmado; pendiente prueba física. [Alarmas Android](https://developer.android.com/develop/background-work/services/alarms/schedule), [permiso de notificaciones](https://developer.android.com/develop/ui/views/notifications/notification-permission). |
| Dependencias incompatibles de wakelock y almacenamiento seguro/notificaciones | Implementar el pequeño canal nativo de pantalla encendida en Windows y Android. Mantener el almacenamiento de credenciales del sistema. | Ambas compilaciones release. [Android KEEP_SCREEN_ON](https://developer.android.com/develop/background-work/background-tasks/awake/screen-on), [Windows SetThreadExecutionState](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-setthreadexecutionstate). |
| OCR debería funcionar desde el primer uso sin subir fotos | ML Kit Text Recognition latino 16.0.1 integrado en el APK. El resultado se añade a notas y requiere revisión de cantidades. | Integración Kotlin compilada; pendiente precisión y fotos reales. [ML Kit Android](https://developers.google.com/ml-kit/vision/text-recognition/v2/android). |
| Importar cualquier URL desde un servidor privado puede alcanzar servicios locales | Admitir solo HTTP/HTTPS estándar; validar todas las IP resueltas como públicas, conectar a una IP validada y mantener verificación TLS del hostname. Repetir en cada redirección; limitar bytes, tiempo y saltos. | Pruebas de direcciones privadas, respuestas DNS mixtas, IP fijada y redirección local. [OWASP SSRF](https://cheatsheetseries.owasp.org/cheatsheets/Server_Side_Request_Forgery_Prevention_Cheat_Sheet.html). |
| Muchas páginas no permiten extracción fiable | Extraer únicamente datos Recipe JSON-LD; conservar enlace/texto como borrador cuando falla. No descargar automáticamente imágenes de páginas. | Prueba de `@graph`, instrucciones por secciones y HTML. [Schema.org Recipe](https://schema.org/Recipe), [datos de receta Google](https://developers.google.com/search/docs/appearance/structured-data/recipe). |
| Sumar ingredientes puede mezclar unidades o variantes | Conservar líneas separadas por receta/plato, con origen visible y claves estables para evitar añadir dos veces el mismo origen. Escalar solo cantidades iniciales inequívocas. | Pruebas de decimales, fracciones, intervalos y cantidades informales. La agregación semántica se pospone hasta contar con un modelo de unidades e ingredientes revisable. |
| Copiar una base SQLite activa puede producir una copia incompleta | API de backup SQLite, copia diaria y manual. Restaurar con servidor detenido, comprobación de integridad, copia previa y generación nueva. | Prueba real de restauración, integridad y preservación de versión previa. [SQLite Online Backup](https://www.sqlite.org/backup.html), [PRAGMA integrity_check](https://www.sqlite.org/pragma.html#pragma_integrity_check). |
| Credenciales administrativas y firma del APK | Tokens aleatorios, solo hashes en servidor, archivo inicial limitado por ACL, credenciales del cliente en almacenamiento seguro y firma privada fuera de Git. | Pruebas de permisos, revocación y compilación firmada. [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage), [firmar Android](https://developer.android.com/studio/publish/app-signing). |

## Límites conscientes de esta primera entrega

### Corrección de arranque Android, 1.0.1+2 (11 de octubre)

La APK 1.0.0 incluía `MainActivity`, pero su `GeneratedPluginRegistrant.registerWith` solo contenía `return`: ningún componente nativo se registraba. Un `pub get` anterior había fallado por permisos de symlink y el proceso seguía compilando con `--no-pub`. Esto deja JNI sin inicializar al llamar a `path_provider_android` durante la apertura de SQLite; es un fallo capaz de cerrar el proceso antes de mostrar la interfaz. La evidencia procede del bytecode de la APK entregada y del código instalado de `jni` 1.1.0, no de un registro del teléfono.

Se regeneró el registro mediante `flutter pub get` completado correctamente. El script de construcción ahora reintenta después de preparar junctions y exige éxito; además inspecciona los DEX del APK antes de publicarlo y rechaza registros vacíos, actividad ausente o librerías nativas incompletas. La APK corregida contiene 122 unidades de bytecode en el registro, conserva el identificador y la firma privada y aumenta la versión a 1.0.1+2. Referencias: [registro de componentes en Flutter](https://github.com/flutter/flutter/blob/stable/packages/flutter_tools/lib/src/flutter_plugins.dart), [implementación JNI](https://github.com/dart-lang/native/tree/main/pkgs/jni/src).

Es una base funcional, no una certificación de producción. La app debe probarse en un teléfono real: acceso privado familiar, alarmas con pantalla apagada, cámara, OCR y recepción de contenido compartido. No tiene escáner de códigos de productos, despensa automática, cálculo nutricional, importación de redes sociales protegidas, dictado o gestión compleja de varios hogares. No se incorporaron cifras nutricionales ni interpretación de alérgenos inferidas de texto libre.

El servidor conserva historial, operaciones y fotos en SQLite. No hay paginación de la descarga inicial ni política automática de retención: para una biblioteca muy grande habrá que medir memoria, red y crecimiento de copias antes de aumentar el uso. No se implementa cifrado adicional de la base local: la protección en reposo depende del usuario de Windows/Android y del cifrado del dispositivo.

La revisión automática no autorizó transmitir la credencial administrativa ni descargar el snapshot mediante el endpoint Tailscale durante esta sesión. Se sustituyó por una comprobación HTTPS sin credenciales y pruebas locales de autenticación. La conexión autenticada desde el teléfono queda pendiente de uso real.


### Biblioteca y fuentes españolas, 1.1.0+3 (11 de octubre)

La comparación y decisiones están en `investigacion-mejoras-mesa.html`, con fuentes en español. Se incorporan categorías y catálogos propios como entidades `collection`; las recetas almacenan identificadores estables. Renombrar conserva vínculos y eliminar grupos conserva recetas. El servidor valida datos nuevos sin cambiar el esquema genérico SQLite.

Solo se conectan Wikilibros en español y Recetas Españolas de belenarbizu. La colección comunitaria comprobada tiene 109 registros, aunque el README anuncia 100; declara CC BY 4.0. Se fija una revisión, se omiten dietas y nutrición por incoherencias comprobadas y se pide completar cantidades. Navarra respondió, pero sus descripciones truncadas no sirven como receta completa. Las fuentes inglesas se retiran; no se traducen automáticamente.

Las consultas públicas no reciben credenciales de Mesa. La caché local mantiene veinte consultas/vistas previas recientes. Recetas ya guardadas funcionan sin conexión y conservan atribución al editar y exportar. Pruebas: 22 cliente y 25 servidor, incluida importación desde catálogo y biblioteca de 320 px con texto al 150 %.

La compilación Windows encontró `atlbase.h` y `atlstr.h` ausentes en Build Tools. Se obtuvieron ATL Headers y X64 14.44.35208 del catálogo oficial local de Visual Studio, verificando SHA-256, y se extrajeron dentro de `.tools/atl`. El cambio CMake utiliza estas rutas solo cuando existen; una instalación con ATL puede compilar sin ese directorio.

El reinicio controlado detectó que PowerShell 7 deserializa fechas ISO de JSON como `DateTime`, mientras el script comparaba cadenas. Se cambió a comparación exacta de ticks UTC, manteniendo la comprobación de ruta y evitando detener un PID reutilizado. El servidor reinició con los datos existentes y `/health` respondió versión 0.2.0 y las capacidades nuevas.


### Galerías y cantidades, 1.2.0+4 (11 de octubre)

El fallo de cantidades tiene dos causas confirmadas: Recetas Españolas contiene nombres de ingredientes sin cantidades y el extractor de Wikilibros no contemplaba tablas. Se retira la colección incompleta del selector; las recetas guardadas se conservan. Se unen celdas de cantidad e ingrediente, se reconocen raciones declaradas y se avisa por líneas sin cantidad. El editor permite revisar ingredientes y raciones de otra receta española. Mantiene la atribución de la receta anterior y añade la nueva en notas y `ingredient_origin`; no sustituye pasos automáticamente ni inventa cantidades.

Las recetas usan `photos` como galería y mantienen `image` como portada compatible. Se importan las imágenes rasterizadas de Wikilibros, excluyendo iconos de plantilla, y todas las declaradas en Recipe JSON-LD, incluidas las de los pasos. La API Imageinfo conserva metadatos individuales de autor/licencia. Prueba real: la tortilla descarga una foto de Tamorlan bajo CC BY-SA 3.0, distinta de la licencia del texto. Referencias: [Imageinfo en español](https://www.mediawiki.org/wiki/API:Imageinfo/es), [reutilización de Commons](https://commons.wikimedia.org/wiki/Commons:Reutilizaci%C3%B3n_del_contenido_fuera_de_Wikimedia).

Las fotos se optimizan a JPEG de hasta 1.000 px y 180 KB para la importación; se almacenan y exportan con sus créditos. El servidor descarga imágenes de enlaces externos validando DNS y redirecciones, sin aceptar redes privadas ni transmitir credenciales. Las consultas Wikimedia desde el cliente se restringen a sus hosts oficiales. La galería conserva referencias pendientes ante fallos o límite de espacio y permite reintentar. La receta admite 8 MB, la petición 12 MB; el protocolo sigue en 1 y el servidor pasa a 0.3.0.

Validación: 29 pruebas del servidor y 27 del cliente, galería interactiva, cantidades en tablas, exportación/reimportación y sincronización. Consulta real de gazpacho y tortilla. Captura de pantalla de teléfono renderizada por pruebas, sin verificación física Android.

### Investigación ampliada de fuentes, 11 de octubre de 2026

Informe: `investigacion-fuentes-recetas.html`. Investigación sin cambios de versión ni conectores nuevos.

La API pública WordPress de delokos respondió sin autenticación, con 1.754 publicaciones y 55 categorías; la categoría vegetariana confirma 1.209 entradas. No todos los posts ni categorías son recetas utilizables. El autor permite recetas y fotos con CC BY-NC-SA 2.5 ES; el pie actual también enlaza a 4.0, por lo que se debe conservar la licencia declarada por entrada. Es el primer candidato a conector no comercial con extracción propia, filtrado de artículos y firmas, y revisión de medidas aproximadas. Bon Viveur permite ciertos usos personales y privados y ofrece fotos del proceso, pero no una licencia de redistribución del catálogo. Alberta publica 66 recetas españolas con medidas y CC BY 4.0 y fotos acreditadas a Anissa Armet; el acceso directo devolvió 403, por lo que falta verificar una descarga autorizada para preparar un paquete local especializado.

Fallos medidos para la siguiente integración: Bon Viveur entrega solo una foto en JSON-LD pese a tener galería en HTML; Food Hero fusiona ocho ingredientes visibles en cuatro entradas y siete en dos; una tortilla de Recetinas tiene Recipe JSON-LD con cero ingredientes y pasos; Rechupete supera 500.000 bytes; las duraciones P0DT0H45M y Duration/P0DT0H40M0S de Directo al Paladar y Hogarmania se pierden en el parser actual. Los rendimientos «8 enchiladas», «5 tazas» y «4 arepas» no deben tratarse como personas. El permiso de uso debe validarse aparte de la compatibilidad técnica: Hogarmania y My Colombian Recipes exigen autorización para reproducción/distribución.

No se recomienda recuperar los datasets como catálogo principal: recetas-cocina contiene 28.238 filas sin fotos; RecetasDeLaAbuela devuelve 20.236 y 20.085 filas de dos versiones, no 40.321 recetas distintas demostradas. Sus licencias de repositorio no acreditan por sí solas permisos de los editores originales. Bueno y Barato tiene una edición española gratuita cuya página de derechos no autoriza asumir CC para toda la edición. No se contactó a autores ni se descargaron catálogos completos.


## 2026-10-11 · Investigación de fuentes latinoamericanas

Informe: `investigacion-fuentes-latinoamerica.html`, con filtros por fuente y uso. Investigación sin cambios en la app, APK, procesos ni conectores. Se revisaron 19 páginas HTML públicas, cinco PDF completos y ocho portadas mediante HEAD, sin descargar imágenes web ni rastrear catálogos masivamente. Los PDF originales se conservan con SHA-256.

Prioridad regional: Sabores Andantes (Udelar/INDA-MIDES, Uruguay), CC BY 4.0, 25 fichas con rendimiento detectadas; dos fichas revisadas visualmente tienen cantidades, porciones y fotos. AGROSAVIA Arracacha (Colombia) aporta tablas métricas, equivalencias y fotografías acreditadas: el PDF declara BY-NC-SA 4.0 y la ficha web enlaza BY-NC 4.0. AGROSAVIA Caribe tiene 57 preparaciones indexadas; el PDF muestra el icono BY-NC-SA sin fijar versión en su enlace genérico y la ficha web BY-SA 4.0. Los créditos listan fotos iStock en páginas impresas 3, 8, 50, 78, 104, 124 y 128: no presumir que sean reutilizables. Conservar la declaración del documento y las excepciones por imagen; aclarar discrepancias para el uso que se pretenda.

No elegir Picante pero sabroso como fuente de fotos del resultado: declara imágenes generadas con Adobe Firefly. Su PDF declara BY-NC-SA 4.0 frente a BY-SA 4.0 en la ficha web. IDDI/TourCert Cocina con chines (República Dominicana) tiene CC BY 4.0 en página PDF 2, prohibición de reproducción en página 56 y fotos de fuentes externas: pendiente de aclaración, no catálogo plenamente autorizado. UChile Cocina de integración chileno-haitiana declara BY-NC-ND 4.0 en su ficha. El PDF de UCR Costa Rica no se pudo descargar en dos intentos y no se verificó su licencia. No se contactó a autores.

Fuentes editoriales prometedoras: México en mi Cocina/Mely, Laylita, My Colombian Recipes/Erica y La Cocina Chilena de Pilar. Los permisos de colección y fotos deben comprobarse por separado. Pilar declara CC BY-NC 3.0 y además pide autorización para fotos, sin asumir licencia uniforme. Paulina tiene 11 ingredientes visibles y una docena de empanadas, pero JSON-LD da uno sin cantidad y cuatro raciones; no guardar esa extracción como completa. Nestlé México devuelve un Recipe sin ingredientes, pasos ni fotos en la muestra. Laylita, Paulina, Kiwilimón y Buenazo superan el límite actual de 500.000 bytes. El artículo puede tener más imágenes que el schema y muchos elementos repetidos; contar imágenes no valida una galería. Se propone preparar paquetes revisados, añadir país culinario y categorías independientes, mejorar adaptadores por editor y conservar medidas abiertas, unidades de rendimiento, créditos por foto y procedencia de imágenes generadas.

Hallazgo posterior de API: Kiwilimón V6 documenta consultas públicas por POST de lectura. Dos muestras sin cuenta ni credenciales respondieron HTTP 200: chilaquiles rojos, 7.545 bytes, 18 entradas de ingrediente (10 con cifras), cinco pasos, cuatro porciones, 40 minutos y tres identificadores de foto; chilaquiles con pollo, 6.318 bytes, 14 entradas (nueve con cifras), cuatro pasos, seis porciones, 75 minutos y dos fotos. Cantidades en `text`, sin campo numérico separado; la portada repite un identificador de galería. Es la mejor candidata técnica a conector encontrada, sin asumir permiso de redistribución ni coste contractual garantizado: la portada para desarrolladores menciona relación comercial y su enlace de términos devuelve una página de error 404, aunque V6 permite consultas públicas. No se solicitó clave ni se contactó al proveedor.

## 2026-10-11 · Descubrir solo recetas con foto · Mesa 1.2.1+5

Se retiran los resultados sin foto disponible de Wikilibros, también al leer búsquedas guardadas. Los iconos de plantilla no cuentan como fotos; se revisan las demás imágenes cuando la primera referencia no tiene datos. Se avanza automáticamente hasta tres páginas vacías y se mantiene el cursor para continuar con «Cargar más». Un fallo de conexión conserva la posibilidad de recuperar resultados de la caché, sin interpretar la incidencia como ausencia permanente de foto.

Las referencias antiguas no permiten importar detalles sin foto; la caché de detalles debe tener imagen guardada o una URL de foto válida. No se modifica el servidor ni se borra contenido personal: el recetario activo del servidor estaba vacío al comprobarlo. La ausencia de un teléfono conectado impide revisar recetas locales no sincronizadas y confirmar la ejecución física de Android.

Validación: 32 pruebas del cliente y análisis limpio. Consulta con el código de producción a Wikilibros: cuatro resultados en la primera página, todos con foto. Comprobación reproducible: `client/tool/audit_photo_catalog.dart` (Dart directo con `--packages=.dart_tool/package_config.json`, desde `client`, evita los hooks de rutas con espacios).

Entrega completada: Windows release 1.2.1+5 sustituido tras cerrar su ventana de forma normal y vuelto a abrir. APK Android ARM64 con versionName 1.2.1 y versionCode 5; actividad, registro de plugins y JNI verificados. Firma válida e idéntica a la entrega anterior, apta para instalar encima. Enlace privado de descarga comprobado por HEAD, HTTP 200, sin credenciales. El servidor local sigue respondiendo al estado público.

## 2026-10-11 · Tres catálogos conectados · Mesa 1.3.0+6

El selector solo mostraba Wikilibros porque las fuentes investigadas no estaban implementadas. Se añaden dos catálogos reales: La cocina delokos mediante su API pública WordPress y Sabores Andantes de Uruguay como colección incluida, accesible sin servidor ni red. Los informes conservan los resultados de su investigación y añaden el estado posterior de la implementación.

delokos se restringe al sitio del autor; no solicita cuenta ni clave y no transmite credenciales familiares. Se separan los ingredientes delimitados por guiones, las listas y los pasos hasta el separador del blog, excluyendo firmas, cabeceras y artículos sin cantidades, pasos o fotos. Se descargan todas las imágenes de receta presentes en el contenido, conservando marcas de agua, atribución y CC BY-NC-SA 2.5 ES. Las redirecciones de imágenes solo admiten los hosts y rutas de su alojamiento WordPress; no se autorizan otros sitios de la API. La declaración de licencia se volvió a verificar en la página del autor. Raciones no declaradas: aviso y base editable 1, sin inventar un rendimiento; si el encabezado declara personas, se conserva.

Sabores Andantes: 24 recetas con 31 fotos originales. Se excluye la tarta de vegetales con masa de garbanzo, cuya ficha no tiene foto propia. Las columnas de ingredientes y preparación se extraen separadas; las hamburguesas, el falafel y los grisines continúan en la cara derecha de sus pliegos y conservan todas las instrucciones y fotografías. Fracciones ¹/3 y ²/3 se normalizan, sin alterar las cantidades. Se distinguen porciones y unidades, con categorías existentes, búsqueda por ingrediente y paginación. Se preservan autores, fotógrafas, CC BY 4.0 y página del PDF por receta/foto. SHA-256 del documento revisado fijado en el generador. El JSON se incluye en la APK y Windows; no necesita Python en el teléfono.

Validación: 42 pruebas Flutter y análisis limpio; incluye selección de los tres catálogos, guardado de la galería de grisines sin red, validez de las 24 recetas/31 fotos, ingredientes de publicaciones reales, cantidades, paginación, exclusión de artículos/firmas y bloqueo de redirecciones ajenas. Consulta real: cuatro recetas con foto en la primera página de Wikilibros, 16 de delokos y 16 de Sabores Andantes. Una muestra real de delokos descarga toda su galería y conserva ingredientes, pasos y licencia. APK 1.3.0, código 6, ARM64: firma coincidente, actividad/registro/JNI comprobados y paquete incluido con las 24 recetas/31 fotos. No cambia el servidor ni la configuración de Tailscale. Sin prueba física en Android.

Entrega: ejecutable Windows actualizado y versión 1.3.0+6 comprobada; APK disponible por el mismo enlace privado, HTTP 200, tamaño coincidente y caché no-store. Instalar la actualización sobre la anterior para que aparezcan las nuevas opciones del selector en el teléfono.


### Directorio y fuentes conectadas, Mesa 1.4.0+7 (11 de octubre de 2026)

Se sustituye el selector limitado por un directorio común de 38 fuentes en español con países, búsqueda y estados diferenciados. Cinco catálogos completos: Wikilibros, delokos y tres paquetes locales. Sabores Andantes conserva 24 recetas/31 imágenes; los paquetes colombianos AGROSAVIA incorporan Arracacha (28/56) y Caribe (55/110). Total sin conexión: 107 recetas y 197 imágenes originales, incluidas variantes recortadas del propio libro, no 197 fotografías distintas. Se conservan cantidades, rendimiento, unidades de producto, autoría, página de origen, créditos y licencias de cada obra. El punto de miles colombiano se normaliza para que el escalado interprete 4.000 como 4000. Se excluye una tabla incongruente de Arracacha y dos fichas caribeñas con imágenes iStock. No se rellenan cantidades inventadas. Los avisos/licencias de cada paquete están en client/assets/catalogs/NOTICE.md. Se añade la categoría bebidas (13 categorías iniciales).

Los 25 conectores editoriales consultan bajo demanda una página de resultados y permiten importar una receta por enlace con revisión previa, a través del servidor familiar autenticado. No se redistribuyen los sitios como bases de datos completas. Kiwilimón utiliza su API pública en español para búsqueda paginada y detalle individual, excluyendo contenido PRO; no se presupone una licencia abierta general. La comprobación en vivo encuentra una receta completa con cantidades y referencias de fotos en 21 fuentes. Las muestras de Venezuela Tuya y Canarias están incompletas; Nestlé España devuelve 403 y MyPlate un certificado no válido. Las ocho fuentes documentales restantes se identifican como consulta del original, con el motivo de no tener un paquete incorporado. La descarga de Alberta sigue bloqueada. Estos límites externos no se presentan como importaciones operativas.

Se corrige el transporte HTTPS fijando la negociación estándar ALPN y post-handshake auth sin desactivar TLS ni la validación de IP pública. Páginas limitadas a 4 MB; compresión y redirecciones acotadas; lectura con plazo total. El extractor admite WPRM, Tasty, HTML visible y Drupal; combina cantidades, ingredientes y pasos completos, interpreta tiempos ISO y conserva galerías del artículo y pasos sin fotos de recomendaciones, firmas, anuncios o iconos. El reintento de fotos omite las ya guardadas. Windows y Android abren el sitio original mediante sus componentes nativos. Se admiten las redirecciones comprobadas de Bon Viveur y RecetasGratis, y el dominio de miniaturas imgmedia.buenazo.pe para que las fichas de Buenazo aparezcan en el catálogo. Los importadores conservan las referencias pendientes y los avisos. El servidor pasa a 0.4.0 manteniendo protocolo 1 y el esquema de datos existente.

Validación: análisis Flutter limpio, 44 pruebas del cliente y 45 del servidor. Los tres paquetes incluidos en la APK coinciden byte por byte con los activos comprobados; todas sus recetas tienen ingredientes, pasos y fotos. Compilación Windows y APK ARM64 correctas; versión 1.4.0+7 y firma coincidente con la actualización anterior. Descarga privada HTTPS 200, 52.229.003 bytes y no-store. Servidor local reiniciado con /health 0.4.0. Descarga real de 15/15 imágenes de la muestra de México en mi Cocina y 3/3 de Kiwilimón. No se ha verificado el arranque en un dispositivo Android físico.

Estado navegable de todas las fuentes: estado-fuentes-mesa.html. Los documentos de investigación anteriores enlazan al estado actualizado y mantienen su historial.


### Catálogos vacíos desde Kiwilimón, Mesa 1.4.1+8

Se reproduce el fallo: la búsqueda inicial de Kiwilimón con «recetas» devuelve cero fichas, mientras «pollo» devuelve 16. El resto de fuentes web tenía una dependencia común con el servidor familiar autenticado, a diferencia de Wikilibros, delokos y los paquetes incluidos. Un dispositivo sin emparejar no podía mostrar sus fichas. Se añade una consulta pública directa y acotada desde el cliente, sin URL familiar ni credenciales, con validación de dominios, redirecciones, tamaño y plazos. Se comparte la lista de destinos originales, ejemplos y dominios alternativos mediante el generador del registro. El adaptador del servidor también corrige la búsqueda inicial para clientes anteriores.

La prueba real desde Dart devuelve fichas con foto en las 23 fuentes web seleccionables. Se comprueban también la interfaz sin emparejar, la búsqueda paginada de Kiwilimón, las redirecciones verificadas y el rechazo de destinos ajenos. Se normalizan enlaces con espacios y se ignoran logos y navegación. Las fuentes documentales y los dos servicios bloqueados se retiran del selector de recetas y siguen accesibles en el directorio completo de 38 fuentes. Esto no convierte los documentos pendientes en bases de recetas completas. Pulsar una ficha web sin emparejar abre el original; la importación para guardar en Mesa continúa utilizando el servidor familiar y su extractor validado.

Cliente 1.4.1+8, servidor 0.4.1, protocolo 1 y datos existentes conservados. Validación: análisis Flutter limpio, 49 pruebas del cliente y 46 del servidor. Las consultas iniciales de las 23 fuentes devuelven 359 fichas con foto; esta cifra describe tarjetas de consulta y no una colección de 359 recetas completas empaquetadas. Sin prueba física de instalación Android.

### Actualizaciones desde Android, Mesa 1.5.0+9

Se añade Mi espacio → Actualizar Mesa, descarga privada HTTPS por Tailscale, progreso/cancelación/reintento y apertura del instalador de Android. Se verifica versión, compatibilidad, tamaño, SHA-256, paquete y firma idéntica; el permiso denegado al volver de ajustes no provoca bucles. La publicación usa APK versionados inmutables y manifiesto atómico. Se añade la ruta privada /descargar a Serve conservando todas las rutas existentes, y un servicio oculto de descargas iniciado por el lanzador. Se instala 1.5.0 una vez por enlace; las siguientes versiones se descargan desde la app.

Análisis limpio, 58 pruebas Flutter y 48 Python; APK y Windows compilados. Descarga completa real por Tailscale y firma coincidente comprobadas. Sin teléfono conectado para probar el instalador real. Arquitectura, referencias oficiales y límites: docs/ACTUALIZACIONES.md.


### Fotos por enlace y retirada de catálogos, Mesa 1.6.1+11

Se retiran Cocina del Caribe (agro-caribe), Arracacha (agro-arracacha) y Sabores Andantes (sabores-uy) del registro compartido, selector, directorio y activos de la app. El registro pasa a 35 fuentes y el selector a 25. Se conservan las recetas que el usuario ya guardó; los paquetes originales quedan únicamente como archivo de investigación fuera del cliente y de la APK.

Las fotos se almacenan solo como URL y créditos. La importación, sincronización, exportación, historial y borradores no generan nuevos datos de imagen. Todas las superficies usan el mismo componente: conexión HTTPS propia sin credenciales, DNS público verificado y fijado, redirecciones comprobadas, máximo 10 MB/40 Mpx y decodificación acotada. RawImage evita el ImageCache de Flutter. Las imágenes, codecs y buffers se liberan al cerrar o cambiar la vista y al pasar la app a segundo plano; verlas requiere RAM temporal e Internet.

La migración elimina adjuntos antiguos de entidades, borradores, caché y conflictos. Los mensajes de sincronización de una versión anterior que ya se habían intentado enviar mantienen temporalmente su contenido original hasta recibir confirmación, porque modificarlo rompería el reintento idempotente. Se eliminan al confirmarse. Los mensajes aún no enviados sí se convierten inmediatamente en referencias. Las copias de seguridad históricas no se alteran. Las fotos personales antiguas sin URL no pueden consultarse en línea y dejan de adjuntarse; no se borran los archivos originales del usuario.

La cámara, archivos y compartir mantienen el OCR local, sin adjuntar la imagen a la receta; una captura temporal creada por ImagePicker se elimina después del reconocimiento dentro de la caché de la app. El servidor pasa a 0.5.0 y conserva protocolo 1.

Validación de Mesa 1.6.1: análisis Flutter limpio, 63 pruebas del cliente y 51 del servidor. Consulta real de imágenes de Wikilibros y delokos con el transporte HTTPS y DNS fijado; APK firmada con la identidad anterior y descarga privada íntegra verificada. Los tres paquetes retirados están ausentes de la APK y de Windows. No se ha probado en un Android físico.


### Ranking y clasificación de todas las fuentes, Mesa 1.7.0+12

El directorio anterior no implementaba el ranking solicitado. Se añade Recetas → Descubrir → Ranking y clasificación · 35 fuentes. Se incluyen todas las fuentes actuales, con búsqueda, filtro por país y orden por cifra publicada descendente, país, disponibilidad o nombre. De las 38 originales permanecen 35 tras las tres retiradas; no se restauran los catálogos eliminados. Se clasifican 25 catálogos operativos, ocho documentos y dos webs de consulta.

Se revisan seis cifras publicadas: Kiwilimón más de 21.000, RecetasGratis más de 20.000, Cocineros Argentinos 10.000+, Hogarmania más de 7.000, Larousse más de 5.000 y Nestlé España 3.238 en su listado. Las otras 29 fuentes permanecen visibles con total sin verificar, nunca cero. Los mínimos no garantizan un orden real exacto ni un total de recetas importables con foto y cantidades. Cada fuente muestra fecha, motivo, descripción y enlace de comprobación cuando hay cifra. No se utiliza la cifra histórica multilingüe de Petitchef como un recuento actual en español.

El registro de cifras se mantiene en server/source_counts.json; el generador compartido exige cobertura exacta de todos los identificadores. El directorio incluye filtros y tarjetas en una lista desplazable, con controles apilados en teléfonos estrechos. Las pruebas cubren búsqueda, acceso a evidencia, cobertura, orden, categorías de disponibilidad, fuentes retiradas, texto ampliado y teclado abierto. El informe estado-fuentes-mesa.html también muestra las 35 fuentes y los recuentos actuales.

Validación: análisis Flutter limpio, 68 pruebas del cliente y 52 del servidor. Windows 1.7.0+12 compilado, copia del ejecutable coincidente y proceso respondiendo. APK ARM64 con versión 1.7.0/código 12, firma coincidente y actividad, plugins, JNI y proveedor de actualización comprobados. Publicación inmutable y descarga completa HTTPS por Tailscale verificadas. Catálogos retirados ausentes en Android y Windows. Las fotos continúan por enlaces directos. No se ha probado en un Android físico.


### Ranking ampliado y numerado, Mesa 1.7.1+13

La solicitud se refiere al ranking por cantidad, no solamente a agrupar las fuentes. Se sustituyen las seis cifras iniciales por 32 recuentos documentados y se numeran las posiciones descendentes. La posición global se conserva al buscar y filtrar; otros órdenes ocultan el número de ranking. Permanecen 35 fuentes actuales (38 originales menos las tres retiradas). MyPlate y UCR quedan sin posición por acceso no verificable; SENATUR queda fuera por no ser un recetario.

La investigación cuenta URLs únicas de mapas específicos de recetas, totales de APIs públicas del propio sitio, uniones de categorías sin duplicarlas, índices completos paginados y recetas en libros. Se excluyen idiomas distintos del español, navegación, noticias y categorías cuando el índice lo permite. Las fichas de catálogos pueden incluir recopilaciones. Los archivos públicos y los resultados auditados se conservan; no se descargan fotos ni se añaden copias a la app. Los libros escaneados se contrastan por índice y páginas, sin asumir que una página equivale a una receta.

El orden es orientativo: se diferencia cifra declarada, ficha de índice, registro de receta, entrada de catálogo, mínimo identificado y recetas del libro. Un mínimo puede ocupar realmente una posición superior. No se confunden estos números con recetas importadas ni se garantiza foto y cantidades en cada ficha del sitio. No se inventan ceros ni se desactiva la comprobación TLS para las fuentes inaccesibles. Metadatos revisados: server/reviewed_source_counts.json; cobertura compartida: server/source_counts.json; ranking completo: estado-fuentes-mesa.html.


Validación final de Mesa 1.7.1+13: análisis Flutter limpio, 68 pruebas del cliente y 52 del servidor aprobadas. Revisión visual del ranking a 320×640 con letra al 150% y a 1360×900; las tarjetas pequeñas muestran posición junto al nombre y mantienen los detalles accesibles. Windows actualizado y proceso respondiendo, copia del ejecutable coincidente con la compilación. APK ARM64 firmada con la misma identidad, versión 1.7.1/código 13, componentes nativos y proveedor de actualización comprobados. Publicación inmutable, feed y descarga completa HTTPS por Tailscale verificados. Catálogos retirados ausentes. No se ha probado en un Android físico.


### Retirar desde el puesto 17, Mesa 1.7.2+14

Se aplica el corte al ranking documentado de Mesa 1.7.1: permanecen las 16 primeras fuentes, de Petitchef a Wikilibros, y se retiran los puestos 17–32 y las tres fuentes sin posición. El catálogo, el ranking, el registro del servidor y el informe actual usan la misma selección. La selección queda fijada en server/source_selection.json; el generador comprueba que ninguna fuente retirada reaparezca. Se conservan las recetas personales ya guardadas, sus créditos y enlaces de fotografías. No se modifican datos familiares ni credenciales. De las 38 fuentes originales quedan 16 (22 retiradas en total).


Validación de la retirada: análisis limpio, 68 pruebas Flutter y 52 del servidor aprobadas; las 22 fuentes retiradas no pertenecen al registro y sus consultas desde el cliente se rechazan antes de realizar solicitudes. Ranking, HTML y JSON contienen exactamente las primeras 16 posiciones. Windows 1.7.2+14 compilado y abierto, ejecutable coincidente con la distribución y proceso respondiendo. Servidor reiniciado para activar la selección. APK 1.7.2/código 14 con misma firma y componentes nativos verificados; publicación inmutable, feed y descarga completa HTTPS privada comprobados. Las recetas personales se conservan. No se ha probado en un teléfono físico.

### Espacios, colores, formas y utilidad de controles · Mesa 1.8.0+15

Se estudian 13 webs de recetas con contenido público y se comparan visualmente Cookpad, Cookidoo, Bon Viveur y Recetas Nestlé México a 1440×1000 y 390×844. Similarweb septiembre de 2026 sirve para escoger referencias por popularidad, sin confundir tráfico estimado con calidad de uso. Android, Microsoft y W3C sustentan recomendaciones de tamaño táctil, navegación, foco y contraste. Se registran limitaciones de acceso: Allrecipes responde 402 en navegador, y Kiwilimón, Giallozafferano y Recetas para Thermomix no aportan suficiente evidencia visual. Las referencias no modifican la selección de 16 fuentes en español.

Se introduce design.dart con paleta, formas y espacios compartidos: verde profundo, crema, terracota; radios 12/14/20/24; escala 8/12/16/24/32. Temas claros y oscuros usan roles de color con contraste mínimo 4,5:1 en las parejas principales de texto verificadas; contornos comprobados a 3:1. No equivale a auditoría completa de accesibilidad ni a prueba de superioridad con usuarios.

La búsqueda precede a los catálogos. La fuente externa actual queda visible y sus detalles se despliegan. La ficha separa ingredientes, preparación, notas y créditos, con accesos directos y controles de cocina persistentes. PC permite ampliar la receta, con ingredientes y preparación en dos columnas desde 900 de ancho disponible. El contenido se limita a 1200 y el modo cocina a 900. En teléfono, las tarjetas pasan a una columna cuando falta espacio o aumenta el texto.

Se reevalúan las herramientas por tarea y prioridad. Cocinar sigue como acción principal; compra y planificación tienen etiquetas visibles también en Android. Historial y papelera se agrupan en Más. Los temporizadores automáticos y manuales se conservan porque resuelven duraciones diferentes. Las marcas de ingredientes pasan al modo cocina, que conserva el progreso; cambiar de paso devuelve la lectura al inicio. Cocina sin pasos y compra sin ingredientes quedan desactivadas. La lista de compra no duplica ingredientes de la misma receta; una futura comparación de cantidades deberá evitar sobrescribir ediciones familiares al cambiar raciones.

Las pruebas detectaron y corrigieron una barra inferior que consumía el alto del modo cocina. Se verifica tamaño real del contenido y navegación, además de ausencia de desbordamientos. Los casos nuevos cubren 320×740 al 200% en oscuro, 390×844 y 1360×900, raciones sin modificar el original, marcas, controles visibles, pasos y ampliación en PC. Capturas del cliente con datos de prueba, no de un Android físico. Informe: investigacion-diseno-mesa.html.

Validación: análisis limpio, 73 pruebas Flutter y 52 del servidor aprobadas. Windows 1.8.0+15 compilado y abierto. APK ARM64 con la misma identidad y firma, actividad, plugins y JNI verificados; publicación inmutable y descarga HTTPS privada completa comprobadas. Las recetas personales y fotos por enlaces directos se conservan. Pendientes prueba en Android físico y evaluación con usuarios.

### Petitchef primero y 50 recetas iniciales · Mesa 1.8.1+16

Descubrir deja de iniciar Wikilibros y abre Petitchef por defecto. El selector usa la misma clasificación descendente por cifra de recetas que el ranking, con Petitchef primero. Se sustituye la portada genérica limitada a 24 resultados por el listado público de últimas recetas: 50 fichas únicas con foto al entrar y otro bloque de 50 mediante Cargar más. Se excluyen enlaces de artículos, navegación, duplicados y recetas sin foto. Si la fuente devuelve menos fichas, se muestra el número real; los fallos permiten reintentar y no se inventan resultados. La búsqueda de Petitchef emplea su formulario público obj=feed, action=list, q, verificado en el HTML actual.

Se comprueban en vivo el lector Dart usado por Windows/Android y el lector del servidor: ambos devuelven las mismas 50 recetas iniciales y una segunda página de 50, con 100 identificadores distintos. Las consultas solo recuperan HTML y URLs; no descargan fotografías ni utilizan credenciales familiares. El catálogo conserva las 16 fuentes elegidas y las recetas familiares ya guardadas.

Pruebas: 76 del cliente y 55 del servidor aprobadas; incluyen fuente inicial, orden del selector, 50 fichas sin interacción previa, paginación sin duplicados, exclusión de fotos ausentes, cursor inválido sin acceso de red y formulario de búsqueda.

## 11 de octubre de 2026 · Mesa 1.9.0: menos complejidad visual

La revisión parte de las pantallas implementadas y de la observación del usuario: demasiados controles antes del contenido, repeticiones por tarjeta y recuadros sin una función clara. Se retiran cabeceras decorativas y controles duplicados; las funciones secundarias se agrupan sin retirar filtros ni acciones. Los campos principales del formulario permanecen visibles; fotos, organización y notas son desplegables. El menú usa una acción por día y mantiene la elección entre comida y cena. Mi espacio agrupa las herramientas por tarea y deja visible la actualización Android. Las selecciones usan verde para reducir acentos simultáneos.

Se conserva Petitchef por defecto con 50 recetas, las 16 fuentes, cantidades originales, galerías por URL y datos locales/familiares. La firma Android permanece igual. El estado normal se consulta en Mi espacio; cambios pendientes de un servidor configurado, errores y conflictos siguen visibles en la pantalla principal. Los temporizadores existentes despliegan su sección al entrar.

Validación: análisis sin incidencias, 79 pruebas Flutter y 55 del servidor, filtros con Aplicar/Cancelar, limpieza, navegación, controles secundarios accesibles, ingredientes y raciones, cocina y ampliación de la ficha. Capturas de biblioteca, formulario, menú y ajustes a 320, 390 y 1360 píxeles; ficha a 320 con texto al 200% en oscuro. Windows responde y la APK firmada se descarga íntegra por HTTPS. No se ha probado en un Android físico.

## 11 de octubre de 2026 · Mesa 1.9.1: recetas dentro de la app sin emparejamiento

La APK usaba un desvío intencional al navegador para fuentes editoriales cuando no había servidor familiar configurado. El catálogo ya consultaba las fuentes directamente, pero la lectura del detalle requería una llamada privada de importación. Se elimina el desvío y se añade lectura pública de detalle al cliente: JSON-LD Recipe, cantidades y pasos de secciones visibles, fotos principales y de pasos, y API pública de Kiwilimón. Se conservan la atribución, el rendimiento declarado y las cantidades originales; no se inventan recetas si la página está bloqueada o incompleta.

Si existe lector del servidor se utiliza, y un fallo permite consultar directamente la fuente. No se envían credenciales familiares a las fuentes públicas. Se verifican dominio, protocolo, redirecciones y límites de lectura con el transporte existente. La fuente original queda en un botón explícito y los errores ofrecen Reintentar sin abandonar Mesa. El editor puede recuperar las fotografías del origen sin emparejarse.

Referencias comprobadas: https://schema.org/Recipe y https://www.petitchef.es/las-ultimas-recetas. Consulta real del cliente: 16 muestras correctas, una por las 13 fuentes web seleccionables y las tres primeras de Petitchef. Se leen HTML/JSON y enlaces a fotos; no se descargan archivos de imagen. Las 12 páginas editoriales revisadas disponibles como fixtures también se interpretan correctamente. No se supone que todas las recetas de cada web tengan idéntico formato.

Validación: análisis limpio, 87 pruebas Flutter y 55 del servidor. Las pruebas de Android sin servidor comprueban Petitchef y Kiwilimón dentro de Mesa, cantidades, pasos, galerías, revisión/guardado y apertura de la web solo al pulsar el enlace. Una receta incompleta conserva al usuario dentro de Mesa y permite reintentar. Compilaciones Windows/Android, firma existente, componentes nativos y descarga HTTPS completa verificados. No hay prueba con Android físico.

## 11 de octubre de 2026 · Investigación rigurosa de fuentes importables

Se examinan 47 sitios mediante consultas públicas identificadas y cinco entradas adicionales mediante documentación oficial: 52 entradas evaluadas. La muestra final contiene 86 URLs candidatas, que incluyen algunos índices y artículos; no equivale a 86 recetas válidas. Se revisan robots, TLS, redirecciones, acceso, cantidades, preparación, rendimiento, referencias de imágenes y condiciones publicadas. La importancia de los sitios se contrasta con los rankings de Similarweb de septiembre de 2026, distinguiendo tráfico estimado, tamaño de catálogo e importabilidad.

El importador genérico devuelve campos, alguna cifra y foto en 66 candidatos, pero esto no certifica su integridad. La comparación con las fichas originales detecta contaminación de ingredientes: Rechupete 5 ingredientes frente a 14 filas, Hogarmania 4 frente a 14 y RecetasGratis 12 frente a 13. Bon Viveur y RecetasGratis pierden fotos y detalles del procedimiento. La afirmación anterior de muestras «correctas» debe entenderse como presencia de campos, no validación semántica completa. Estos problemas se documentan y siguen pendientes de corrección en producción.

Como prioridad técnica en español se mantienen Petitchef, Nestlé México, Directo al Paladar, Larousse, Paulina, Cocineros Argentinos, Buenazo y Recetinas; cada fuente necesita ampliar las pruebas de plantillas y revisar permisos. México en mi Cocina, Comedera, Anna Recetas Fáciles y Pilar son alternativas estudiadas, sin activarlas. Allrecipes, Simply Recipes y Sally’s Baking resultan prometedoras para una traducción futura; no se ha implementado traducción automática. Kiwilimón, delokos y Wikilibros requieren distinguir sus adaptadores específicos del lector HTML genérico.

Delokos publica licencia CC BY-NC-SA 2.5 ES para recetas y fotos. RecipeTin Eats y Budget Bytes limitan la reutilización; King Arthur prohíbe scraping/crawling y no se realizan más sondas tras conocer esa condición. Cookpad restringe materiales fuera de su plataforma. ATK permite enlaces individuales de regalo durante 30 días, sin acreditar un conector de catálogo gratuito. Los términos no verificables quedan como pendientes, sin atribuir una licencia abierta por disponibilidad pública.

Se comprueban 37 fotos de muestra por HEAD, todas con respuesta 200 y tipo de contenido de imagen. No se descargan cuerpos de imagen; esto no demuestra cobertura de galerías ni decodificación en Android. El informe también compara documentalmente TheMealDB, Edamam y Spoonacular: Edamam no entrega las instrucciones de las recetas web en su oferta de búsqueda, y las demás requieren revisar producción, cobertura española, integridad y permisos.

La investigación no cambia la selección de 16 fuentes, los datos familiares, la APK ni el código de producción. Informe: investigacion-importacion-recetas.html. El informe distingue fallos del lector, restricciones editoriales y acceso inconcluyente.

## 11 de octubre de 2026 · Mesa 1.10.2: fuentes libres, traducción y medidas prácticas

La nueva autorización permite ampliar las fuentes libres sin recuperar las 22 retiradas. Se añaden Based Cooking y las ediciones inglesa, francesa, italiana, portuguesa y alemana de Wikibooks. Referencias: https://github.com/LukeSmithxyz/based.cooking (dominio público de textos y fotos), https://foundation.wikimedia.org/wiki/Policy:Terms_of_Use (atribución y compartir igual), https://developers.google.com/ml-kit/language/translation/android (traducción local Android), https://opennmt.net/CTranslate2/python/ctranslate2.Translator.html (motor local Windows) y https://github.com/argosopentech/argospm-index-dev (índice oficial de modelos). Los sitios con pago, restricciones explícitas o permiso de reutilización no comprobado no se activan como catálogos libres.

Los adaptadores manejan los espacios de nombres MediaWiki y el árbol público de fotos de Based Cooking. El recetario italiano usa Libro di cucina/Ricette/, no los capítulos sobre ingredientes. Portugués reconoce Confecção; cada foto Wikimedia debe declarar CC BY, CC BY-SA, CC0 o dominio público. Los errores HTTP 429 detectados al auditar no se convierten en recetas inexistentes: la app mantiene el original y permite reintentar. Se verifica una receta completa por fuente, no la totalidad del catálogo.

La traducción usa frases completas para conservar gramática. Comprueba todas las cifras y fracciones antes de aceptar; guarda original y metadatos de traducción. El motor Windows tiene un recurso conservador por fragmentos cuando altera cifras; Android conserva el original ante un fallo y puede recurrir al servidor privado. Los modelos Android necesitan Wi-Fi inicialmente; Windows ya tiene instalados los cinco pares locales. No se envían recetas a un servicio de traducción externo. La traducción es automática y revisable, no una traducción culinaria certificada.

Las conversiones son de uso culinario, con aviso aproximado y sin modificar datos guardados. Se escala primero y se redondea después. No se transforman unidades indefinidas como una pizca o una cucharada colmada, ni se inventan densidades de alimentos desconocidos. Originales disponibles en vista previa, receta guardada y cocina; el texto previo a traducir permanece accesible.

Sincronización: gzip, reintentos limitados solo para lectura y envío idempotente, páginas con límites de bytes, cursor inicial estable y sustitución local atómica tras completar la descarga. Exportación completa preservada. Los textos y enlaces de fotos se transmiten; no los bytes de las imágenes.

Se corrige la selección de ingredientes estructurados cuando el HTML mezclaba recetas relacionadas, el cuerpo completo de Bon Viveur, las galerías de pasos y el total visible de Hogarmania (40 min frente a 10 min estructurados de preparación). Fixtures reales comparados y pruebas de interrupción y envío duplicado incluidas. Windows 1.10.2+21 compilado y abierto; APK firmada con el certificado familiar existente, actualización privada verificada. 94 pruebas de cliente y 66 de servidor. No hay ensayo de Android físico.


## 1.10.3+22 · Corrección de traducciones

Se sustituye como primera opción el motor genérico por TranslateGemma 12B local en este ordenador, servido por Ollama solo en 127.0.0.1:11435. Android consulta el servidor de Mesa por la conexión privada antes de utilizar ML Kit. Los modelos permanecen fuera de la APK; el glosario culinario sí se incluye. Se conservan originales, cifras y unidades mediante campos comprobados y marcado de cantidades. Las notas generadas en español no pasan por el traductor extranjero. Volver a traducir usa el original y permite revisar y aplicar o descartar; no se sobrescriben automáticamente recetas editadas.

Validación final: 102 pruebas Flutter, 83 Python, cinco recetas completas en cinco idiomas, API privada de traducción y re-traducción, Windows 1.10.3+22 abierto y respondiendo, APK con firma familiar original y descarga HTTPS verificada. La variante 12B mejora las muestras revisadas frente a modelos genéricos y 4B. La traducción sigue siendo automática; la alternativa móvil puede ser menos precisa. No se ha probado un teléfono Android físico. Detalles y fuentes: docs/TRADUCCION.md.


## 1.11.0+23 · Apertura progresiva y reutilización

Se elimina la espera modal previa a la receta. La ficha abre desde la información del catálogo o una vista guardada, el texto de Wikibooks se comunica antes de terminar la comprobación de fotos y la traducción avanza en paralelo. Las fotos completas y sus créditos se incorporan antes de permitir guardar. La vista guardada se actualiza a petición del usuario para no cambiar pasos mientras lee. El recetario personal no se sobrescribe con actualizaciones del catálogo.

El servidor conserva resultados de traducción comprobados en data/translation-cache.sqlite, con límite de 256 grupos, caducidad de 30 días e invalidación por texto, modelo, manifiesto e implementación. Las consultas iguales se agrupan para evitar trabajo de IA duplicado. Explorar fuentes extranjeras prepara el modelo en segundo plano mediante un endpoint autenticado que no recibe recetas.

Las fotos se comparten temporalmente solo entre consumidores activos de una galería, con un máximo de tres descargas y prioridad para la foto principal pendiente. Las miniaturas se decodifican a 180 píxeles, se construyen al entrar en pantalla y no se guardan archivos ni se utiliza ImageCache global. Una nueva apertura después de liberar la última referencia vuelve a consultar la foto.

Investigación y mediciones: investigacion-apertura-recetas.html. Cinco muestras públicas recuperaron la traducción desde disco en 54–65 ms, frente a 6–23 s para generarla; estas medidas no incluyen fuente ni descargas de fotografías. Un proceso Python nuevo la recuperó sin inferencia en 96 ms. Pruebas de interfaz en tamaños de Windows y Android, con red y traducción pendientes, conservaron lectura, cierre y cantidades. La prueba de Android físico sigue pendiente.


## 1.11.1+24 · Traducción visible y lectura sencilla

Se identifica una traducción por el texto original solicitado, sin depender de etiquetas de idioma de notas que el motor puede añadir. El resultado conserva los metadatos de fotos que llegan antes o después. Una respuesta HTTP correcta debe contener una traducción española completa, originales y las mismas cantidades; una respuesta vacía o extranjera no se marca como terminada. Los fallos liberan el intento y ofrecen Reintentar traducción sin volver a descargar la fuente.

Las páginas extranjeras sin etiqueta de idioma utilizan el idioma del catálogo seleccionado, tanto en el importador del cliente como en el servidor. Las vistas antiguas de catálogos extranjeros sin un original traducido recuperan ese idioma antes de decidir si se traduce. No se aplican automáticamente cambios a recetas personales editadas: su traducción se revisa antes de guardar.

Ingredientes y preparación tienen prioridad en Windows y Android. El original, las medidas, las notas y los créditos de la fuente se agrupan bajo una opción plegada. Las advertencias sobre cantidades ausentes y los fallos de traducción siguen accesibles. Se eliminan avisos repetidos de almacenamiento de fotos; una foto única no necesita contador. Fuente y actualización se encuentran en el menú secundario; Cerrar y Guardar son las acciones principales. Se mantienen todas las referencias a fotos y originales.

La validación incluye los dos órdenes de llegada de fotos/traducción en tamaños de PC y Android, reintento sin nueva descarga, rechazo de respuesta sin traducir, reparación de vistas anteriores e importación de enlaces con/sin fuente declarada. El endpoint privado respondió con cinco recetas públicas completas en inglés, francés, alemán, portugués e italiano. No se ha ejecutado la APK en un teléfono físico.


## 1.11.2+25 · Traducción Android de lanzamiento y velocidad

La prueba de Android real en emulador detecta que R8 conserva nombres pero elimina constructores de registradores ML Kit. La compilación de depuración funciona, la de lanzamiento no inicializa TranslatorImpl.Factory. Se conservan los registradores y se comprueban sus constructores dentro de cada APK antes de publicar. La corrección también cubre los registradores de reconocimiento de texto.

Se ejecutan cinco recetas públicas completas en el motor nativo. El modelo alemán repite 3 cm consecutivamente y la validación descartaba todo el resultado. Se recupera únicamente una duplicación consecutiva idéntica cuya eliminación haga coincidir todas las cifras originales; otras alteraciones siguen fallando o se reintentan con cantidades y unidades protegidas. La prueba de lanzamiento corregida confirma los cinco idiomas, la vista de receta guardada y Cocinar en español, sin escribir traducciones automáticas sobre las recetas personales ni añadir operaciones de sincronización.

La vista guardada inicia traducción automática, Android utiliza el respaldo local tras una espera total de 30 s al PC, y una carga fallida del glosario se puede reintentar. Al abrir o reanudar Mesa se prepara en segundo plano el mismo TranslateGemma 12B. No se sustituye por 4B: en las mismas recetas, 4B superó 3/5 y 12B 5/5 comprobaciones de campos/cantidades. Las pruebas no certifican equivalencia semántica en todos los textos. DeepL y Azure requieren cuenta/clave para evaluar sus API; no están activados. CTranslate2 es una alternativa de ejecución investigada, sin conversión ni medición local todavía.

Investigación: investigacion-traduccion-rapida.html. La APK para entrega continúa siendo ARM64 con la firma familiar; la prueba de ejecución usa x86_64 en emulador y no equivale a comprobar el teléfono físico del usuario.
## 12 de octubre de 2026 · Mesa 1.12 y 1.13: rediseño, identidad y comprobación

Se implementan tokens visuales y componentes comunes, navegación por tareas, filtros rápidos, lectura móvil a pantalla completa y acciones contextuales. La verificación nativa detecta una superposición del botón flotante en el recetario vacío: queda una sola acción de primera receta y margen inferior desplazable. También se comprueba que el optimizador Android elimina ic_notification, resuelto con res/raw/keep.xml y una verificación del recurso dentro de cada APK de lanzamiento.

La identidad 1.13 usa geometría original de cuenco y m, con nombre/verde conservados. Una sola fuente vectorial alimenta SVG, Flutter, Android adaptativo/monocromo y Windows ICO. El inicio muestra el estado real de preparación sin añadir una espera mínima. No se añaden dependencias de framework. Los estudios Ipsos/JKR 2023, Westerman 2012 y Walsh/Winterich/Mittal 2011 sustentan principios de reconocimiento, curvas y continuidad; no demuestran aceptación del logo por los usuarios de Mesa y no se realizó una encuesta propia.

El análisis y las pruebas de interfaz cubren espacios, áreas táctiles, foco de teclado, diferenciación entre tarjeta/favorito y movimiento reducido. La fase funcional 1.12 supera 133 pruebas Flutter; la identidad y auditoría añaden cinco pruebas y la suite final pasa 138, con 92 pruebas del servidor conservadas porque su código no cambió. El ensayo Android usa main.dart de producción en release x86_64 dentro de MesaTest: creación, cantidades, cocina, persistencia tras cerrar el proceso, búsqueda y cuatro destinos. No acredita un teléfono ARM64, todas las alarmas, todos los catálogos ni accesibilidad completa. La traducción exclusivamente remota/gratuita todavía necesita configuración.

Informes: auditoria-rediseno-mesa.html e identidad-y-comprobacion-mesa.html. Se conservan los binarios originales 1.11.2+25 y la publicación 1.12.0+26. Los fallos de pruebas e infraestructura del laboratorio se documentan separados de los defectos de producto corregidos.



## 13 de octubre de 2026 · Mesa 1.14: disposición de menús y comandos

Se revisan fuentes primarias de Microsoft, Android y W3C y estudios de Nielsen Norman Group. Se mantienen cuatro destinos visibles; las acciones principales crear e importar permanecen a un clic. La fila de creación sustituye al botón flotante y reserva su propio espacio: deja de tapar tarjetas, a cambio de consumir altura en pantallas compactas. Se oculta al escribir, en Descubrir y en otras secciones. Windows conserva estos comandos en el lateral y añade Ctrl+N/Ctrl+I.

Un componente común adapta comandos a panel inferior en ventanas menores de 600 puntos lógicos y a menú anclado en ventanas amplias. Los grupos mantienen iconos, texto, permisos y confirmación de papelera. Compra y edición se promueven al pie de la ficha si hay suficiente ancho útil, sin duplicarse en el menú. Se corrige el foco del menú para cerrar con Escape. Importación usa el mismo nombre en botón y diálogo.

Las páginas visitadas se conservan al cambiar de sección; las ocultas excluyen foco y suspenden imágenes mediante TickerMode. No se añade caché de fotos. La conservación comprobada cubre navegación entre secciones, no todo cambio interno de modo ni ampliación de ficha. W3C 2.5.8 exige 24 píxeles CSS con excepciones; los 48 puntos lógicos elegidos por Mesa son una decisión de ergonomía, no una certificación WCAG.

El análisis está limpio y pasan 144 pruebas Flutter. Las seis de menús se repiten con el tema real. Windows 1.14.0+28 está abierto y responde. Android release x86_64, main.dart de producción, verifica crear/guardar, abrir importación, cantidades, panel de acciones, cocina, persistencia tras reiniciar el proceso, cuatro destinos y búsqueda conservada entre secciones. La selección del laboratorio se corrige para no confundir el título de ruta y el texto del buscador con controles y tarjetas. La APK ARM64 con firma original y su descarga HTTPS quedan verificadas; no se prueba en teléfono físico. El servidor no cambia: las 92 pruebas Python son el resultado previo conservado, no una nueva ejecución.

Informe: investigacion-menus-mesa.html. No se realiza una encuesta de usuarios propia ni se modifica la configuración de traducción remota.


## 14 de octubre de 2026 · Mesa 1.14.1: auditoría de estabilidad y carga

Se reproducen identificadores duplicados, fallo de escritura durante la segunda importación, cambio indebido de tipo y confirmación de otra receta. Se corrigen con validación previa, transacción única para archivo/cola y verificación de identidad de recibos. La importación emite una sola recarga/notificación. La cola tiene índice por entidad y secuencia; cada envío contiene hasta 25 primeras operaciones de entidades distintas y unos 10 MB de payload, por debajo del límite del servidor. Los recibos preservan su fingerprint y las ediciones posteriores se rebasan tras confirmar la anterior. Un cursor sin avance y generaciones que cambian repetidamente terminan con aviso, conservando los datos.

Se alinean notas, enlaces, fechas reales (sin normalizar fechas imposibles), raciones, títulos y referencias de compra. Las notas son de hasta 120.000 caracteres y los enlaces de hasta 4.000. La copia de conflictos respeta el límite del título. Los temporizadores JSON inválidos no impiden el inicio y las duraciones nuevas se limitan a 24 horas. El borrador maneja valores no finitos y errores de escritura.

Una prueba descubre que la Future de DialogRoute termina antes de desmontar la animación: disponer los controladores al terminar showDialog provoca su uso después de dispose. ManagedDialogBuilder los posee hasta su desmontaje; respuestas tardías y operaciones que regresan de otro diálogo comprueban la vida y ruta actual. Se usa en importación, fotos, categorías, menú, conexión, invitaciones y temporizadores. El editor conserva el dispose de sus propios campos.

Los archivos se leen como flujo y se detienen al exceder sus límites: fotos 10 MB, importación 50 MB y configuración de conexión 32 KB. El OCR Android inspecciona dimensiones y reduce cada lado a unos 1.600 píxeles en una tarea separada; un fallo de OCR al compartir permite continuar manualmente. Los flujos reales excluyen categorías de Hogarmania y noticias de Bon Viveur. Las páginas de pruebas revisadas se fijan bajo client/test/fixtures/publishers con su URL real, en lugar de depender de informes de investigación que se sobrescriben.

Pasan 157 pruebas Flutter y 113 de servidor; el analizador queda limpio. Se importan 2.101 elementos, se conserva el archivo/cola al reabrir y se prueba transmisión de 250 recetas con una respuesta perdida: 11 peticiones, 250 recibos, sin duplicación. La API recibe 2.000 recetas con replay, descarga por páginas y backup. Cuatro solicitudes simultáneas al mismo elemento producen una aplicación y tres conflictos. 53 bases sintéticas pasan integrity_check. Windows 1.14.1+29 abre y responde; el servidor se reinicia con las correcciones.

La APK de laboratorio de OCR usa componentes nativos de producción y otro punto de entrada; reconoce 2 huevos de una imagen sintética de 8.000x8.000 y rechaza bytes inválidos y más de 10 MB. Se corrige un fallo del ensayo de almacenamiento externo usando una imagen incorporada únicamente al punto de entrada de laboratorio. La APK normal x86_64 con main.dart verifica creación, cantidades, acciones, cocina, reinicio, destinos y estado de búsqueda. La distribución es ARM64, con firma familiar original y descarga HTTPS verificada. Los códigos AOT ARM64 difieren del anterior e incluyen las correcciones; no se distribuye el laboratorio.

Quince fuentes entregan una muestra legible; cinco Wikilibros extranjeros devuelven HTTP 429 y una muestra del índice Wikilibros español no cumple receta completa. El catálogo español usado por la app es distinto de ese índice web; esas muestras no se marcan aprobadas. Nestlé España conserva consulta original. El traductor del PC produce cinco muestras completas con originales/cantidades conservados: 27,06 s la primera y 1,23-1,27 s las demás, sin generalizar a recetas largas. Persisten la comprobación del teléfono ARM64 real, disponibilidad externa y traducción exclusivamente en nube.

Informe: auditoria-estabilidad-mesa.html. No se consultan recetas ni credenciales de la familia para el laboratorio.


La entrega definitiva de esta auditoría es Mesa 1.14.2+30: el último ajuste muestra los límites de archivos pequeños en KB, evitando el texto 0 MB. Se repiten análisis, 157 pruebas Flutter y recorrido Android de producción tras actualización. El servidor no cambia y conserva la ejecución final de 113 pruebas. Se verifican Windows 1.14.2+30, firma y descarga; se conservan las publicaciones previas.


## Indra OCR · 1.17.0+34

El OCR de ML Kit se sustituye por Indra OCR 1.1.2 en el servidor familiar.
Windows y Android usan el mismo motor CPU con carga diferida y reutilizada,
fotos solo en memoria y modelos incluidos en el instalador. Android necesita
conexión con el ordenador para leer fotos; permanece la entrada manual.
Se conservan atribución y licencia del texto OCR. Los traductores anteriores
no cambian. Detalles y condiciones: [OCR-INDRA.md](OCR-INDRA.md).
La sonda antigua `client/tool/native_reliability.dart` documenta el anterior
OCR nativo y queda histórica; la verificación vigente es
`scripts/verify_indra_release.py`, junto con `server/test_ocr.py` y
`client/test/ocr_test.dart`.
