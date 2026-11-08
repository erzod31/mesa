# Actualizar Mesa desde la app · DG-0021

Las plataformas entregadas son Windows x64 y Android ARM64. Los directorios
SDK para otros destinos no son clientes distribuidos. En ambos clientes,
`Mi espacio > Actualizar Mesa` muestra la versión instalada, busca el canal,
ofrece una versión posterior compatible y permite cancelar la descarga.

## Windows

La copia instalada abre el control local del lanzador, protegido por una
capacidad efímera diferente del token familiar. El canal predeterminado es
`https://starfly.tailc69897.ts.net:9443/descargar/windows-update.json`.
`MESA_WINDOWS_UPDATE_FEED` permite configurar otro origen HTTPS al arrancar
el lanzador. El cliente directo/portable sin sesión de lanzador explica que
necesita la primera instalación manual.

El manifiesto tiene firma Ed25519 y una clave pública incluida en la app.
Producto, plataforma, arquitectura, versión, código, nombre inmutable,
tamaño y SHA-256 están dentro de la firma. Solo se siguen redirecciones HTTPS
al mismo origen. Se rechazan versiones iguales/anteriores y retrocesos de
versión semántica. La descarga es acotada y el instalador se comprueba de nuevo
antes de cada handoff: recursos PE, versión/código y política Authenticode.
Los instaladores actuales no tienen Authenticode; su origen se autentica por
el manifiesto firmado y su hash. Una versión que anuncie Authenticode debe
tener firma válida y el certificado declarado; no se ignoran firmas inválidas.

Tras confirmar, se esperan las escrituras de la base local y su checkpoint.
Se copia el asistente mínimo independiente fuera de la instalación, se
prepara su petición y se cierra la ventana. El asistente espera la salida del
lanzador original; no mata procesos. Vuelve a verificar el paquete y abre el
instalador NSIS interactivo por usuario, con sus confirmaciones y licencia.
Comprueba la versión resultante y solicita reabrir Mesa. Si se cancela el
instalador, solicita reabrir la copia anterior. La ruta debe coincidir con la
instalación registrada de Mesa; no se fuerza un `/D` experimental ni se usa
una desinstalación previa. Recetario, cola, credenciales y copias permanecen
fuera de la carpeta de instalación.

**Transición inicial:** los binarios Windows antiguos carecen de este flujo.
Necesitan una primera instalación manual del candidato nuevo; actualizar el
código fuente no cambia retroactivamente el ejecutable ya instalado.

## Android

Se conserva packageName `com.mesa.mesa`, el certificado familiar y el canal
HTTPS existente `/descargar/update.json`. Puede configurarse al compilar con
`--dart-define=MESA_UPDATE_FEED=URL_HTTPS`. Se comprueban versión/código,
tamaño, SHA-256, paquete, certificado, SDK y ABI. La política compartida por
el adaptador nativo y sus pruebas JVM rechaza también retrocesos semánticos.
La descarga no cambia de origen ni se reintenta sin intervención del usuario.
Android mantiene el permiso de instalar desde Mesa y su confirmación de
instalación. Después se abre Mesa mediante la acción normal del instalador;
no se fuerza un reinicio en segundo plano ni se desinstala la app.

## Canales, candidatos y comprobación

En la inspección de este encargo, el feed Android activo devuelve 1.16.0+32
y el feed Windows devuelve HTTP 404. El canal Windows está configurado en el
código, pero **no está activado en producción**. Los manifiestos candidatos
se preparan con `scripts/prepare_update_candidates.py` bajo
`output/in-app-updates-DG-0021/channel`. Publicar esos manifiestos y desplegar
el helper actualizado requiere un paso posterior autorizado. No se ha hecho
en DG-0021, ni se han cambiado servicios de red del ordenador. El helper
empaquetado ya soporta los dos canales y no falla cuando `sys.stderr` es None.
La APK candidata también acompaña al instalador como recurso local, sin
activar el feed externo ni cambiar la APK estable publicada.

Las pruebas de aplicar/reabrir utilizan adaptadores falsos. Se generan y
extraen los paquetes, y se abre exclusivamente su payload con perfil temporal.
**No se ejecutan instaladores, el asistente de actualización ni desinstaladores
reales en este Windows.** La instalación normal y la reapertura tras instalar
quedan pendientes de una VM independiente. Android no se instala en teléfonos
del usuario. Se conservan `isolation-incident.json`, `recovery-state.json` y
la limitación del incidente anterior: no existió una instantánea inmediata
completa de AppData/registro. Informe: `docs/in-app-updates-DG-0021.json`.

## Preparación DG-0033 · 1 de noviembre de 2026

La versión candidata es 1.18.1+36. El canal Android incorpora firma Ed25519
con la misma identidad pública del canal Windows; el certificado nativo APK
familiar se mantiene. Los clientes nuevos rechazan feeds sin firma válida.
El JSON sigue siendo plano para permitir que clientes Android anteriores
lean sus campos habituales y actualicen cuando se active el nuevo canal.
El instalador incluye el feed Android firmado junto a la APK. La clave
privada de firma queda únicamente en `.tools/signing`, fuera del payload.

La comprobación HTTPS nueva devuelve 502 para ambos feeds, no el estado
200/404 del informe DG-0021. No se ha arrancado ni reiniciado el servicio
habitual, ni se han activado candidatos. El arreglo de `RemoteDisconnected`
permanece vigente y se verifica con el helper empaquetado sin consola.

`scripts/update_publication.py prepare` produce un bundle revisable, con
paquetes, ambos manifiestos y copia de los feeds/alias anteriores. No escribe
en el directorio servido. `activate` es un paso operativo separado: valida
firmas/hashes y el estado anterior, copia primero paquetes inmutables y
reemplaza cada oferta/alias de forma atómica. Rechaza colisiones y cambios
posteriores. No modifica Tailscale, firewall ni servicios. `rollback` restaura
las ofertas previas y conserva paquetes inmutables y datos; funciona también
tras una activación parcial. No instala versiones antiguas en clientes ya
actualizados. Un nuevo cliente rechazará un antiguo feed sin firma tras el
rollback, hasta publicar de nuevo un canal válido.

La preparación concreta y los comandos absolutos están en
`output/implementation-DG-0033/publication/publication.json` y en el informe
`docs/implementation-DG-0033.json`. Para activar de verdad hace falta revisar
su impacto y programar el arranque/relevo del helper existente. Restaurar el
servicio serviría los archivos por la ruta privada ya configurada; no es una
prueba de instalación Android/Windows ni requiere tocar la LG.

El lanzador permite `--isolated-api-port` exclusivamente junto con un perfil
aislado. Esto permite probar reapertura en el mismo puerto sin usar 8765 ni
interrumpir la instancia habitual. Se conservan los límites: sin instaladores,
actualizadores o desinstaladores reales en este Windows compartido.
