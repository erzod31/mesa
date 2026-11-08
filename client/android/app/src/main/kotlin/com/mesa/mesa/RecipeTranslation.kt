package com.mesa.mesa

import com.google.android.gms.tasks.Tasks
import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.common.MlKitException
import com.google.mlkit.nl.translate.TranslateLanguage
import com.google.mlkit.nl.translate.Translation
import com.google.mlkit.nl.translate.Translator
import com.google.mlkit.nl.translate.TranslatorOptions
import io.flutter.plugin.common.MethodChannel

/** Text remains on the device. Only language models are downloaded. */
class RecipeTranslation {
    private val active = mutableSetOf<Translator>()
    fun translate(arguments: Any?, result: MethodChannel.Result) {
        val input = arguments as? Map<*, *>
        val source = input?.get("source") as? String
        val texts = input?.get("texts") as? List<*>
        if (source !in setOf("en", "fr", "it", "de", "pt") || texts == null ||
            texts.size > 4000 || texts.any { it !is String || it.length > 2500 } ||
            texts.sumOf { (it as String).length } > 120000) {
            result.error("translation", "Idioma o texto de receta no válido.", null); return
        }
        val translator = Translation.getClient(TranslatorOptions.Builder()
            .setSourceLanguage(TranslateLanguage.fromLanguageTag(source!!)!!)
            .setTargetLanguage(TranslateLanguage.SPANISH).build())
        active.add(translator)
        val output = mutableListOf<String>()
        var done = false
        fun finish(error: Exception? = null, stage: String = "translate") {
            if (done) return
            done = true
            active.remove(translator); translator.close()
            if (error != null) result.error("translation_$stage",
                if (stage == "download") "No se pudo descargar el idioma para traducir en el teléfono. Comprueba Internet y reintenta."
                else "El traductor del teléfono no pudo completar la receta. Puedes reintentar o conectar el ordenador.",
                mapOf("stage" to stage, "error_code" to (error as? MlKitException)?.errorCode, "cause" to error.message))
            else result.success(output)
        }
        fun batch(offset: Int) {
            if (done) return
            if (offset >= texts.size) { finish(); return }
            val chunk = texts.drop(offset).take(8).map { translator.translate(it as String) }
            Tasks.whenAllSuccess<String>(chunk)
                .addOnSuccessListener { values -> output.addAll(values); batch(offset + chunk.size) }
                .addOnFailureListener { finish(it) }
        }
        translator.downloadModelIfNeeded(DownloadConditions.Builder().build())
            .addOnSuccessListener { batch(0) }
            .addOnFailureListener { finish(it, "download") }
    }
    fun close() { active.toList().forEach { it.close() }; active.clear() }
}
