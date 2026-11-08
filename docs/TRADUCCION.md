# Revisión de traducción · Mesa 1.11.2

Actualización Android del 12 de octubre de 2026: se conserva el registro ML Kit que R8 eliminaba en lanzamiento. La prueba nativa en un emulador de lanzamiento tradujo las cinco recetas y verificó lectura/cocina en español. Las recetas guardadas se traducen automáticamente para lectura, conservando tus ediciones. La comparación de velocidad y candidatos está en [investigacion-traduccion-rapida.html](../investigacion-traduccion-rapida.html).

Revisión anterior del 12 de octubre de 2026: se corrigen la aplicación de resultados al llegar fotos, los reintentos y la detección de idioma en importaciones y vistas antiguas. Originales y re-traducción se encuentran ahora en **Original, medidas y fuente**. La comprobación privada con cinco recetas completas está en `output/translation-display-live.json`.

Revisión inicial del 11 de octubre de 2026. El fallo afectaba tanto a la calidad del lenguaje culinario como a la posibilidad de reparar recetas ya traducidas.

## Fallos reproducidos

El motor antiguo traducía `Pain` como «dolor», `Faites revenir` como «traer de vuelta» y las claras como «blancos». Cuando cambiaba `1.5` a `1,5`, el proceso fragmentaba toda la receta alrededor de sus números. Los modelos antiguos usaban inglés como idioma intermedio. Las notas generadas por Mesa en español también pasaban por el motor del idioma extranjero. Una vez marcada como traducida, una receta no podía traducirse otra vez.

Las pruebas están en `output/translation-before.json`. Los cambios de motor se contrastaron con las mismas frases y con recetas completas de Wikibooks en cinco idiomas. Los modelos genéricos OPUS y NLLB también produjeron errores culinarios; no se seleccionó NLLB. El respaldo OPUS conserva un glosario revisado y validación de cifras, pero no ofrece la misma calidad que el motor especializado.

## Implementación

El ordenador usa TranslateGemma 12B mediante el Ollama instalado, en un proceso privado dedicado al proyecto y accesible exclusivamente en `127.0.0.1:11435`. Los archivos del modelo están en `.tools/ollama-models`. El manifiesto y su hash se registran en `.tools/translation/translategemma.json`. No se envían recetas a Google, Ollama ni a un traductor público: la red externa se utiliza para descargar el modelo y consultar las fuentes originales.

El traductor recibe campos completos con separación comprobable. Antes de traducir, las cantidades y unidades reconocidas se delimitan; después se recuperan de los originales y se verifica cada campo. No puede introducir conversiones como 350 °F → 175 °C en los datos guardados. Las equivalencias prácticas de Mesa, por ejemplo 350 °F → 180 °C, se aplican únicamente en presentación. Las fracciones y el formato decimal originales se conservan. Si el motor omite un campo, se reintenta ese grupo como campos completos individuales. Una respuesta incompleta o con cantidades diferentes se descarta.

Android consulta primero el ordenador conectado a Mesa. Sin ordenador utiliza ML Kit local con el mismo glosario culinario compartido. Los modelos móviles se descargan la primera vez que se necesita un idioma; ya no se exige Wi-Fi. La conexión al servidor tiene un plazo corto para establecerse y una espera mayor para traducir: un primer arranque del modelo en PC puede tardar más. El respaldo móvil puede ser menos preciso y se identifica en la vista de originales.

**Volver a traducir** aparece en recetas guardadas y vistas del catálogo que conservan un original extranjero. Rehace la traducción desde ese original, muestra ingredientes y pasos para revisar y exige **Aplicar traducción** antes de guardar. **Descartar** conserva la receta actual. La vista guardada comprueba que la receta no cambió mientras se preparaba el resultado. No se modifican automáticamente las recetas personales ya editadas. Las notas generadas en español y las referencias a fotos se conservan.

## Validación y límites

Se prueban decimales, fracciones, temperaturas, cifras añadidas u omitidas, técnicas culinarias, instrucciones largas, saltos de párrafo, notas en español, re-traducción desde originales, separación de campos, cantidades dentro de cada campo, selección del servidor en Android, alternativa móvil y revisión con aplicar/descartar. Las pruebas de interfaz ejecutan Flutter; no equivalen a una prueba en un teléfono físico.

Los ejemplos completos revisados proceden de las páginas públicas de pastel 1-2-3-4, aligot, bigoli con pato, strudel de manzana y ambotic. Las muestras y los tiempos están en `output/translation-final-full-recipes.json` y `output/translation-final-italian.json`. Se conservan los metadatos de sus fotos sin descargar archivos de imagen. Esto comprueba muestras concretas, no certifica todas las recetas de un catálogo. Un modelo automático puede interpretar mal una expresión o perder un matiz; el original y la revisión siguen siendo necesarios.

## Documentación primaria consultada

- [ML Kit: traducción local y limitaciones de calidad](https://developers.google.com/ml-kit/language/translation): explica el uso del inglés como intermediario para otras parejas.
- [ML Kit en Android](https://developers.google.com/ml-kit/language/translation/android): descarga de modelos y ejecución local.
- [TranslateGemma de Google](https://huggingface.co/google/translategemma-12b-it): modelo y condiciones Gemma.
- [TranslateGemma en Ollama y formato de entrada](https://ollama.com/library/translategemma): variante local y pauta de traducción.
- [Informe técnico de TranslateGemma](https://arxiv.org/abs/2601.09012).
- [CTranslate2: conversión y ejecución de modelos](https://opennmt.net/CTranslate2/conversion.html): respaldo local sin Torch durante la ejecución.
- [Modelo francés-español de Helsinki-NLP](https://huggingface.co/Helsinki-NLP/opus-mt-fr-es).
- [NLLB de Meta](https://huggingface.co/facebook/nllb-200-distilled-600M): alternativa evaluada y descartada para esta corrección.
