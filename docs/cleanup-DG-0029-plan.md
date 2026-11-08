# DG-0029 · limpieza vigente

Objetivo: limpiar exclusivamente cachés y temporales inequívocos del proyecto
Programa de recetas, sin reconstruir productos ni tocar instalaciones o red.

- [x] Leer AGENTS.md y protecciones de limpieza.json del coordinador.
- [x] Inventariar rutas, tamaños, archivos, utilidad y procesos activos.
- [x] Guardar docs/cleanup-DG-0029-manifest.json antes de cualquier eliminación.
- [x] Borrar únicamente destinos seguros con PowerShell y LiteralPath,
  validando raíz, enlaces, protecciones y uso activo antes de cada operación.
- [x] Comprobar fuentes, artefactos y requisitos conservados mediante hashes.
- [x] Entregar docs/cleanup-DG-0029.json con resultados y omisiones.

Conservar datos y respaldos, claves, modelos, SDK/runtimes, dependencias,
informes y evidencias, paquetes finales y anteriores, candidatos y staging
pendiente, especialmente DG-0016 a DG-0023. No cerrar procesos ni forzar
archivos ocupados; conservar destinos ambiguos. Sin cambios operativos.

Resultado: 17 cachés eliminadas, 5.903 archivos, 1.279.348.371 bytes lógicos.
60 protecciones del coordinador y 2.241 archivos verificados por SHA-256,
sin diferencias. Se conservan todos los candidatos, staging, modelos y datos.
Una caché inexistente omitida; cero errores. Informe cleanup-DG-0029.json.
