# DG-0033 · Mesa

Objetivo: corregir alemán; probar colas pobladas y reinicio con credenciales
sintéticas; preparar canales firmados, despliegue y rollback sin activarlos.

Prioridad añadida del usuario: acelerar la traducción en el flujo real.
Medir antes/después con API autenticada, receta corta y habitual, carga fría,
modelo caliente y caché; no tocar servicios habituales ni enviar recetas reales.
Investigar carga/cola/disponibilidad/reintentos/validación antes de optimizar.

- [x] Reproducir 422 con contrato/modelo real y recetas sintéticas.
- [x] Corregir la causa y cubrir validación conservadora de cantidades.
- [x] Probar SQLite real con operaciones intentadas, respuesta perdida,
  cambios pendientes, credenciales falsas y handoff falso de actualización.
- [x] Preparar canales Windows/Android autenticados y despliegue reversible.
- [x] Compilar Windows/Android e instalador nuevo; extraer y verificar payload.
- [x] Registrar artefactos, pruebas nuevas, límites e impacto en informe JSON.
- [x] Medir y acelerar la traducción real: sondas acotadas y caché persistente,
  invalidación por modelo/contenido/idioma y deduplicación concurrente.

Resultado: 1.18.1+36, 187 pruebas Python, 186 Flutter y 9 JVM nuevas.
Instalador extraído y ejecutable con perfil aislado verificados; reinicio en
puerto estable con cola poblada e idempotencia correctos. Publicación y
rollback ensayados con los paquetes reales en un directorio de laboratorio.
El canal habitual sigue sin activarse y devuelve 502 en ambos endpoints.
No se han ejecutado instaladores/actualizadores/desinstaladores reales.

Límites: ninguna LG/teléfono/Shield; ningún instalador, actualizador o
desinstalador real; ningún cambio de registro/perfil habitual/red ni reinicio
de servicios existentes. No publicar. Conservar candidatos anteriores.

Versión inicial: 1.18.0+35 candidata. Evidencia histórica DG-0021 demuestra
el arreglo de RemoteDisconnected; no se considera pendiente por DG-0014.
