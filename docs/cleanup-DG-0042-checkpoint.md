# DG-0042 · nueva limpieza del 2 de noviembre de 2026

Objetivo actual: retirar sólo residuos regenerables del proyecto Mesa, con
manifiesto previo, protecciones y comprobación de uso/rutas antes de cada borrado.

Estado observado: código/candidato 1.18.2+37; transición DG-0036 pendiente de
Computer Use app approval. No se reintenta esa operación en esta limpieza.
El helper propio de descargas figura activo; no se cierra ni modifica.

Se han leído AGENTS y los tres registros del coordinador en modo lectura.
Hay 111 rutas registradas para DG-0042. Se amplían protecciones para datos,
claves, modelos, informes, binarios finales, staging/payloads y respaldos de
instalación/perfiles de DG-0030–DG-0036. Se conservan todos los registros previos.

La revisión empieza por cachés Python/Flutter/Gradle y objetos de compilación.
Los entornos Android sólo son elegibles si la evidencia demuestra que son
sintéticos, están cerrados y sus herramientas/informes/capturas permanecen.
Las dudas se conservan. SDK, dependencias y modelos compartidos quedan fuera.

Entregables: docs/cleanup-DG-0042-manifest.json (previo e inmutable), registro
de operaciones y docs/cleanup-DG-0042.json. No builds, suites, instalaciones,
publicaciones, cambios de permisos/red/servicios, AppData ni LG.
