# Mesa para Windows

Windows 1.18.2+37 incluye instalador x64 por usuario, cliente Flutter, servidor
familiar, Python privado y bibliotecas nativas, modelos de traducción básica
para inglés, francés, italiano, alemán y portugués, y la actualización Android
que el empaquetador seleccione. Incluye Indra OCR y sus modelos CPU para leer
fotos sin descargas al reconocerlas. No necesita Python, Node, Flutter ni
Visual Studio instalados. Véase `docs/OCR-INDRA.md` para conexión y licencias.

Ejecuta el instalador y abre Mesa desde el escritorio o el menú Inicio. Los
servicios locales funcionan mientras la ventana de Mesa está abierta; cerrar
Mesa detiene únicamente los servicios que ha iniciado esta instancia.
Tailscale sigue siendo opcional y externo para compartir fuera del ordenador.
TranslateGemma/Ollama es una mejora opcional y no forma parte de este paquete.

El programa se instala en `%LOCALAPPDATA%\Programs\Mesa`. El servidor conserva
sus datos en `%LOCALAPPDATA%\Mesa\server`; el cliente mantiene su carpeta habitual
de soporte de aplicación. Actualizar o desinstalar no borra estas carpetas.

Desde 1.18.2+37 se puede seleccionar explícitamente un servidor existente sin
importar, copiar o mezclar familias. Con Mesa cerrada, guarda
`%LOCALAPPDATA%\Mesa\server-profile.json` con `schema: 1` y
`server_data_directory` como ruta absoluta de su carpeta de datos. Esa carpeta
debe contener su `recetario.sqlite` y `desktop-connection.json` originales,
con la credencial aún vigente en esa base. La selección se valida antes de
abrir el servidor; una ruta o identidad incorrecta detiene el arranque, sin
crear otra familia. El cliente conserva su carpeta y credenciales habituales;
las descargas/actualizaciones siguen usando `%LOCALAPPDATA%\Mesa\updates`.

También se admiten las variables de proceso `MESA_SERVER_DATA` (prioritaria)
y `RECETARIO_DATA` (si no hay selección persistente). El perfil de laboratorio
`--isolated-profile` ignora ambas y la selección normal. No debe usarse como
mecanismo de producción. Para deshacer una selección, cierra normalmente Mesa
y restaura la copia anterior de `server-profile.json`; no copies bases de una
familia sobre otra. Este ajuste no cambia Tailscale, puertos ni tokens.

La actualización desde `Mi espacio > Actualizar Mesa` se describe en
`docs/IN-APP-UPDATES.md`. Los candidatos DG-0021 se conservan fuera de `dist`,
en `output/in-app-updates-DG-0021/artifacts`, y no activan los canales de producción.
La primera instalación no importa automáticamente las bases privadas de un
checkout portable anterior: conserva ese proyecto y exporta/importa o empareja
explícitamente el recetario que quieras compartir. No se distribuyen recetas
personales, credenciales, catálogos privados ni colas dentro del instalador.

No se cierran aplicaciones ajenas al instalar. Si Mesa está abierta, ciérrala
antes de actualizar para que Windows pueda sustituir sus archivos. Conserva
una exportación del recetario como copia adicional.

Para compiladores: `scripts/build_windows_installer.py --client-dir RUTA`
empaqueta un cliente release vigente con PyInstaller 6.22.3 y NSIS 3.12.
El compilador NSIS se conserva en `.tools/windows-installer/nsis-3.12`; su ZIP
oficial tiene SHA-256
`56581f90db321581c5381193d796fffcf2d24b2f8fed2160a6c6a3baa67f2c4f`.
Las dependencias de empaquetado se aíslan en `.tools/windows-installer/build-venv`.
Las licencias y procedencias de bibliotecas y modelos acompañan al programa.

La verificación de este encargo extrae el instalador con 7-Zip/NanaZip y abre
el contenido extraído mediante `Mesa.exe --isolated-profile C:\ruta\laboratorio`.
Usa bases separadas, puertos libres, credenciales en memoria y notificaciones
del sistema desactivadas. No ejecuta el instalador ni el desinstalador.
El antiguo parámetro experimental `/ISOLATED` del instalador está retirado:
el instalador final lo rechaza antes de modificar el sistema. La instalación,
actualización y desinstalación normales quedan pendientes de una prueba en una
VM o un perfil de Windows independiente; una carpeta distinta no basta.

Resultado DG-0014: el candidato conservado es
`dist/Mesa-Setup-1.16.1-33-x64-4.exe` (1.16.1+33). Se verificaron los 311
archivos del payload, el arranque nativo aislado, guardado/lectura de una receta
y traducción de inglés, francés, italiano y portugués. La petición de traducción
alemana devolvió HTTP 422; el servicio auxiliar de descarga Android cerró la
conexión sin respuesta. Al reiniciar el perfil aislado se conservó la receta,
pero el cliente no reconectó al cambiar el puerto aleatorio del laboratorio.
Se conserva el paquete sin recompilar. No está firmado con Authenticode y no
se ha probado en una máquina limpia. La instalación, actualización y
desinstalación normales no están validadas.

La evidencia completa está en `docs/windows-installer-DG-0014.json`. Incluye el
incidente del primer prototipo y el estado de recuperación observado: no se
persistió una instantánea completa inmediata de AppData/registro antes de ese
intento, por lo que no se afirma conservación completa del sistema.
