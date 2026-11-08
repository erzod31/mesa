# OCR de Mesa 1.17.0+34

Indra OCR 1.1.2, de https://github.com/datalab-to/indra, sustituye el OCR
Android de ML Kit. Se mantienen los traductores existentes; son otra función.
El servidor familiar comparte una sola instancia CPU, cargada al leer la
primera foto, con un máximo de cuatro hilos y una lectura simultánea. No hay
procesos de inferencia por foto ni GPU. Una segunda petición recibe un aviso
para reintentar, sin acumular fotos en una cola.

Windows lee archivos mediante su servidor local. Android envía la cámara,
los archivos y las imágenes compartidas al ordenador emparejado con Mesa:
requiere conexión con ese ordenador. Sin conexión se conserva la escritura
manual. No se envían fotos a Datalab, Google ni a una API OCR de terceros.
Las fotos se procesan en memoria y no se guardan en el servidor o recetario.
La captura temporal de cámara se retira de la caché de la app al terminar;
los archivos originales elegidos por el usuario se conservan.

El endpoint autenticado `POST /v1/ocr` recibe bytes directamente, sin el coste
de base64 dentro de JSON. Admite hasta 10 MB y 25 millones de píxeles, corrige
la orientación EXIF, compone transparencias sobre blanco y limita el lado
mayor a 2400 píxeles. El texto se añade a notas para su revisión; no se
inventan ingredientes ni pasos a partir del reconocimiento. El texto recibido
se limita a 100.000 caracteres. El cliente no reenvía automáticamente fotos
cuando hay errores o el servidor está ocupado.

Los modelos se incluyen en el instalador, en lugar de descargarlos al leer
una imagen. El conjunto sin modelos matemáticos ocupa 76.127.253 bytes,
incluidos sus avisos. Versión de modelos v1.1.0, revisión inmutable
`bd02167fdf2005a19962cc15188f8496a2c87d3b`. El script
`scripts/setup_indra_ocr.py` los prepara en `.tools/ocr/indra-v1.1.0`, con
manifiesto SHA-256. El empaquetador comprueba esas huellas antes de incluirlos.
`INDRA_OCR_MODEL_DIR` permite una ubicación local alternativa; no activa
descargas de red durante el reconocimiento.

El código tiene licencia Apache 2.0. Los pesos, sin modificar, y sus salidas
están sujetos a AI PUBS Open RAIL-M modificada: incluye atribución, compartir
la licencia y restricciones de uso y de competencia comercial. No es una
licencia comercial sin restricciones. El instalador muestra el texto completo
y conserva su copia y procedencia en `licenses`. Las notas OCR conservan la
atribución a Datalab y los enlaces de modelo/licencia para acompañar el texto
al copiarlo o exportarlo. Fuente de la licencia:
https://huggingface.co/datalab-to/indra-ocr/blob/bd02167fdf2005a19962cc15188f8496a2c87d3b/LICENSE

La primera prueba sintética en este equipo reconoció título, cantidades y
cuatro líneas en 990 ms con carga inicial y 51 ms con el motor ya cargado.
Estos tiempos no garantizan rendimiento ni exactitud en fotos reales,
manuscritos, documentos degradados o dispositivos distintos. Revisa siempre
las cantidades y los pasos. La comprobación de entrega se registra en
`output/indra-ocr-2026-10-28/validation.json`.
