# DG-0021 · objetivo y continuidad

Implementar/completar la actualización de la propia aplicación desde su interfaz
en todas las plataformas realmente distribuidas de Mesa (inventariar primero).
Encargo activo: actualizaciones de apps; no retomar Gmail ni tareas históricas.

- [x] Inventariar versiones, plataformas, interfaz y canales existentes.
- [x] Conservar reglas existentes y registrar autoactualización en AGENTS.md.
- [x] Completar Windows y corregir helper Android si es necesario.
- [x] Verificar versión/producto/origen/tamaño/hash/firma, cancelación y handoff
  con adaptadores falsos; nunca ejecutar instaladores en este Windows.
- [x] Generar candidatos coherentes sin publicar ni cambiar servicios/red o
  instalaciones/dispositivos del usuario; conservar artefactos anteriores.
- [x] Entregar docs/in-app-updates-DG-0021.json con projectKey exacto
  programa_de_recetas, matriz, pruebas, hashes, límites y pendientes.

No se permiten instaladores/actualizadores/desinstaladores reales, registro,
accesos o perfiles habituales, incluso en modo QA. Preservar el incidente previo
y su limitación: no hubo instantánea inmediata completa de AppData/registro.

Estado: Windows x64 y Android ARM64 realmente entregados. SDK de otras
plataformas sin paquetes distribuidos; no se inventan clientes webOS/iOS/etc.
Baseline: Windows 1.17.0+34, Android APK local 1.17.0+34, feed Android
publicado 1.16.0+32. Candidato nuevo 1.18.0+35. Windows usa canal HTTPS
existente /descargar/windows-update.json, aún no activado; muestras firmadas
se guardarán en output/in-app-updates-DG-0021/channel, sin publicar.
167 pruebas Python y 16 pruebas UI/protocolo de actualizaciones pasan.
Pendiente: análisis y regresión Flutter, JVM Android, builds, extracción,
helper empaquetado sin stderr y JSON final. Nunca ejecutar el updater real.

Cierre DG-0021: candidatos 1.18.0+35 fuera de dist; 169 Python, 184 Flutter,
9 JVM pasan, extracción y helper Android empaquetado comprobados. Manifiestos
firmados preparados sin publicar. Reporte final docs/in-app-updates-DG-0021.json.
Pendientes de operación: publicación/activación autorizada y validación de
instalación real en VM independiente. No se han tocado instalaciones del usuario.
