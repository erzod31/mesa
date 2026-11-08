# Traducción · DG-0033

Se mantiene OPUS-MT/CTranslate2 CPU int8 y el proveedor opcional TranslateGemma.
No se envían recetas a servicios externos. El modelo alemán admite de → es;
el 422 no era un idioma no soportado: OPUS devolvía «Mezclar dos huevos.» y la
validación esperaba la cifra 2. Se restauran únicamente cardinales pequeños
inequívocos con idéntico valor y orden; cambios, cantidades nuevas, artículos,
compuestos o fracciones ambiguas siguen rechazándose. Se conserva el original.

La medición previa encontró dos comprobaciones del worker opcional apagado,
unos 4,08 s por petición. Ahora la sonda usa 250 ms, comparte resultado durante
10 s y cambia inmediatamente al modificar la configuración del modelo.
No se arranca ningún worker. La selección de proveedor no cambia a ciegas.

El flujo real `/v1/translate-recipe` reutiliza resultados OPUS validados en
SQLite privado. La clave incluye idioma, contenido completo, hash de pesos y
tokenizadores, versión CTranslate2, código y glosario. Un modelo modificado
también invalida la instancia cargada. Peticiones iguales concurrentes
comparten inferencia; se revalida cada lectura, no se almacenan fallos y se
respetan los límites anteriores de 256 entradas, 250 KB y 30 días. La caché
del proveedor opcional también invalida código/glosario y ya no conserva una
segunda caché de memoria independiente de su identidad de modelo.

| Receta sintética | Antes, primer uso | Después, primer uso | Después, repetición | Modelo caliente, texto nuevo |
|---|---:|---:|---:|---:|
| Corta, 4 campos | 4,58 s | 0,89 s | 11 ms | 0,13 s |
| Habitual, 18 campos | 5,93 s | 1,56 s | 11 ms | 0,77 s |

Con proceso nuevo y caché persistida, primera respuesta: 0,45–0,46 s, sin
inferencia.
Frío significa proceso/modelo no cargado; no se vació la caché del sistema
operativo. Son muestras pequeñas en este PC, con carga de compilación variable.
La eliminación de las sondas se midió directamente; no se atribuye toda la
variación de inferencia al código. El benchmark usa API HTTP autenticada en
proceso: incluye preparación/validación/serialización, pero no red del móvil
ni renderizado. No es una promesa de esos tiempos para toda la app.

La UI conserva llamadas asíncronas y muestra el texto original mientras
traduce; las pruebas de vista previa prueban interacción, cierre y resultados
tardíos. El servidor ejecuta el endpoint síncrono en el pool de FastAPI, no
en el hilo UI. Cerrar una vista descarta el resultado tardío; no cancela una
inferencia nativa ya comenzada. No se ha cambiado esa semántica.

Límites: recetas largas, espera detrás de otra receta y hardware más lento
pueden tardar más. TranslateGemma 12B no estaba disponible: no se midió ni se
reinició para esta prueba. En copias empaquetadas sin su configuración, la
sonda ya se omite; la caché persistente sigue aportando a las repeticiones.
Android sin PC conserva su traducción local ML Kit; no se atribuyen los
tiempos del servidor a ese motor ni a un teléfono físico.

Referencias del contrato: [modelo oficial alemán](https://huggingface.co/Helsinki-NLP/opus-mt-de-es),
[CTranslate2](https://opennmt.net/CTranslate2/python/ctranslate2.Translator.html).
