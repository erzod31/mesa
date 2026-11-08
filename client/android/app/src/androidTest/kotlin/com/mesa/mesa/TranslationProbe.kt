package com.mesa.mesa

import android.app.Activity
import android.app.Instrumentation
import android.os.Bundle
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Real Android model download and inference. Public sample text only; no user data. */
class TranslationProbe : Instrumentation() {
    override fun onCreate(arguments: Bundle?) { super.onCreate(arguments); start() }
    override fun onStart() {
        val report = Bundle()
        val latch = CountDownLatch(1)
        val started = System.currentTimeMillis()
        val translator = RecipeTranslation()
        sendStatus(0, Bundle().apply { putString("phase", "native_translation_started") })
        runOnMainSync {
            try {
                translator.translate(mapOf("source" to "en", "texts" to listOf("Bread", "2 eggs", "Mix and bake for 20 minutes.")), object : MethodChannel.Result {
                    override fun success(value: Any?) { report.putString("translated", value.toString()); report.putBoolean("success", true); latch.countDown() }
                    override fun error(code: String, message: String?, details: Any?) { report.putString("error", "$code: $message; $details"); latch.countDown() }
                    override fun notImplemented() { report.putString("error", "not_implemented"); latch.countDown() }
                })
            } catch (error: Throwable) { report.putString("error", "${error.javaClass.name}: ${error.message}"); latch.countDown() }
        }
        if (!latch.await(240, TimeUnit.SECONDS)) report.putString("error", "native_timeout_240s")
        runOnMainSync { translator.close() }
        report.putLong("elapsed_ms", System.currentTimeMillis() - started)
        finish(if (report.getBoolean("success")) Activity.RESULT_OK else Activity.RESULT_CANCELED, report)
    }
}
