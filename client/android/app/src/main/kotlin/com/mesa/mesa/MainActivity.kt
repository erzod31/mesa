package com.mesa.mesa

import android.content.Intent
import android.net.Uri
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var updates: AppUpdates? = null
    private var consumed = false
    private val recipeTranslation = RecipeTranslation()
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        updates = AppUpdates(this, MethodChannel(engine.dartExecutor.binaryMessenger, "mesa/updates"))
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, "mesa/native")
        channel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "translateRecipeTexts" -> recipeTranslation.translate(call.arguments, result)
                "awake" -> {
                    if (call.arguments == true) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    result.success(null)
                }
                "initialShare" -> {
                    if (consumed) result.success(null)
                    else { consumed = true; readShare(intent) { result.success(it) } }
                }
                "openUrl" -> {
                    val url = call.arguments as? String
                    val target = url?.let { Uri.parse(it) }
                    if (target?.scheme != "https" || target.host.isNullOrEmpty() || !target.userInfo.isNullOrEmpty()) {
                        result.error("url", "Enlace de fuente incorrecto.", null)
                    } else {
                        try {
                            startActivity(Intent(Intent.ACTION_VIEW, target))
                            result.success(null)
                        } catch (_: Exception) {
                            result.error("browser", "No se pudo abrir el navegador.", null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        consumed = true
        readShare(intent) { if (it != null) channel?.invokeMethod("shared", it) }
    }
    override fun onDestroy() { recipeTranslation.close(); updates?.close(); super.onDestroy() }
    @Suppress("DEPRECATION")
    private fun readShare(intent: Intent, done: (Map<String, Any>?) -> Unit) {
        if (intent.action == Intent.ACTION_VIEW && intent.data?.scheme == "mesa") {
            done(mapOf("text" to intent.data.toString())); return
        }
        if (intent.action != Intent.ACTION_SEND) { done(null); return }
        val text = intent.getStringExtra(Intent.EXTRA_TEXT) ?: ""
        val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        if (uri == null || intent.type?.startsWith("image/") != true) { done(mapOf("text" to text)); return }
        Thread {
            val payload = mutableMapOf<String, Any>("text" to text)
            try {
                contentResolver.openInputStream(uri)?.use { stream ->
                    val output = java.io.ByteArrayOutputStream()
                    val buffer = ByteArray(8192)
                    while (true) {
                        val count = stream.read(buffer)
                        if (count < 0) break
                        if (output.size() + count > 10_000_000) throw IllegalArgumentException("Imagen grande")
                        output.write(buffer, 0, count)
                    }
                    payload["image"] = output.toByteArray()
                }
            } catch (_: Exception) { payload["text"] = "$text\nNo se pudo abrir la foto compartida. Añádela desde la receta." }
            runOnUiThread { done(payload) }
        }.start()
    }
}
