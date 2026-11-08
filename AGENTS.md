# Entregas de Mesa

- Toda entrega debe incluir un instalador Windows utilizable (`.exe` o `.msi`), preferentemente x64 y por usuario. Un portable o ZIP no sustituye al instalador.
- Incluir la aplicación y sus componentes locales de ejecución; no exigir Python, Node ni herramientas de desarrollo al usuario final.
- Las actualizaciones y la desinstalación deben conservar recetas, colas, credenciales y copias del usuario. Verificar con un perfil aislado y registrar las limitaciones de la prueba.
- Todas las plataformas realmente distribuidas deben permitir actualizar su propio binario desde la interfaz de la app: búsqueda, descarga verificada, confirmación e instalación nativa, con reapertura cuando la plataforma lo permita. Conservar identidad, firmas, datos y configuración; rechazar paquetes ajenos y downgrades. Documentar canales no activados y la primera instalación manual de versiones antiguas sin actualizador. Un enlace, catálogo actualizado o recarga no sustituye este flujo.
- Durante DG-0021 no publicar candidatos ni modificar servicios/red o instalaciones del usuario. No ejecutar instaladores, actualizadores o desinstaladores reales en este Windows, aunque se use carpeta temporal o modo QA; comprobar el handoff mediante adaptadores falsos y extracción.
