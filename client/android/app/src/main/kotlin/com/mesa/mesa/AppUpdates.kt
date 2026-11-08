package com.mesa.mesa

import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicBoolean
import javax.net.ssl.HttpsURLConnection

class UpdateFileProvider : FileProvider()

@Suppress("DEPRECATION")
class AppUpdates(private val activity: FlutterActivity, private val channel: MethodChannel) {
    private val downloading = AtomicBoolean(false)
    private val cancelled = AtomicBoolean(false)
    @Volatile private var connection: HttpsURLConnection? = null
    private val flags get() = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
    private fun installed() = activity.packageManager.getPackageInfo(activity.packageName, flags)
    private fun version(info: PackageInfo) = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
    private fun permitted() = Build.VERSION.SDK_INT < 26 || activity.packageManager.canRequestPackageInstalls()
    private fun apk(code: Long): File {
        require(code > 0) { "Versión incorrecta." }
        return File(File(activity.cacheDir, "updates"), "mesa-update-$code.apk")
    }
    private fun hash(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(65536)
            while (true) { val n = input.read(buffer); if (n < 0) break; digest.update(buffer, 0, n) }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }
    private fun signers(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures
        return signatures?.map { signature ->
            MessageDigest.getInstance("SHA-256").digest(signature.toByteArray()).joinToString("") { "%02x".format(it) }
        }?.toSet() ?: emptySet()
    }
    private fun verify(file: File, code: Long, expected: String, size: Long, expectedVersion: String) {
        require(size in 1..120_000_000L && expected.matches(Regex("[a-f0-9]{64}"))) { "Datos de actualización incorrectos." }
        require(file.isFile && file.length() == size && hash(file) == expected) { "La descarga no está completa o ha cambiado. Vuelve a descargarla." }
        val archive = activity.packageManager.getPackageArchiveInfo(file.path, flags)
            ?: throw IllegalArgumentException("El archivo no es una APK válida.")
        val current = installed()
        UpdatePolicy.verify(UpdateIdentity(current.packageName, version(current), current.versionName ?: "", signers(current), 0),
            UpdateIdentity(archive.packageName, version(archive), archive.versionName ?: "", signers(archive), archive.applicationInfo?.minSdkVersion ?: Int.MAX_VALUE),
            code, expectedVersion, Build.VERSION.SDK_INT)
    }

    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "info" -> {
                        val current = installed()
                        result.success(mapOf("version" to current.versionName, "version_code" to version(current),
                            "sdk" to Build.VERSION.SDK_INT, "abis" to Build.SUPPORTED_ABIS.toList(), "can_install" to permitted()))
                    }
                    "permission" -> {
                        if (!permitted()) activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                            Uri.parse("package:${activity.packageName}")))
                        result.success(permitted())
                    }
                    "cancel" -> { cancelled.set(true); connection?.disconnect(); result.success(null) }
                    "download", "install" -> {
                        val args = call.arguments as? Map<*, *> ?: throw IllegalArgumentException("Datos de actualización ausentes.")
                        val code = (args["version_code"] as? Number)?.toLong() ?: 0
                        val size = (args["size"] as? Number)?.toLong() ?: 0
                        val expected = args["sha256"] as? String ?: ""
                        val expectedVersion = args["version"] as? String ?: ""
                        val file = apk(code)
                        if (call.method == "install") {
                            require(permitted()) { "Permite a Mesa instalar actualizaciones en los ajustes de Android." }
                            // Hashing and archive verification run off the UI thread, including before every installation.
                            Thread {
                                try {
                                    verify(file, code, expected, size, expectedVersion)
                                    activity.runOnUiThread {
                                        try {
                                            val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updates", file)
                                            val intent = Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
                                            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                            intent.clipData = ClipData.newRawUri("Actualización Mesa", uri)
                                            activity.startActivity(intent)
                                            result.success(null)
                                        } catch (error: Exception) { result.error("install", "No se pudo abrir el instalador de Android.", null) }
                                    }
                                } catch (error: Exception) { activity.runOnUiThread { result.error("verify", error.message, null) } }
                            }.start()
                        } else {
                            val url = URL(args["url"] as? String ?: "")
                            val origin = URL(args["feed_origin"] as? String ?: "")
                            require(url.protocol == "https" && url.userInfo == null && url.ref == null) { "La descarga debe usar HTTPS." }
                            require(origin.protocol == "https" && origin.userInfo == null && url.host == origin.host && url.port == origin.port && url.query == null &&
                                url.path == "/descargar/Mesa-Android-$expectedVersion-$code.apk") { "La descarga no pertenece al origen o versión anunciados." }
                            require(size in 1..120_000_000L && expected.matches(Regex("[a-f0-9]{64}")) && code > version(installed())) { "Datos de actualización incorrectos." }
                            require(downloading.compareAndSet(false, true)) { "Ya hay una descarga en curso." }
                            cancelled.set(false)
                            Thread {
                                val part = File(file.path + ".part")
                                try {
                                    file.parentFile!!.mkdirs()
                                    if (file.exists()) {
                                        try { verify(file, code, expected, size, expectedVersion) } catch (_: Exception) { file.delete() }
                                    }
                                    if (!file.exists()) {
                                        var target = url
                                        var response: HttpsURLConnection? = null
                                        for (redirect in 0..3) {
                                            if (cancelled.get()) throw InterruptedException()
                                            require(target.protocol == "https" && target.host == url.host && target.port == url.port && target.userInfo == null) { "Redirección de descarga no permitida." }
                                            val conn = target.openConnection() as HttpsURLConnection
                                            connection = conn
                                            conn.instanceFollowRedirects = false
                                            conn.connectTimeout = 15000; conn.readTimeout = 15000
                                            conn.setRequestProperty("Accept-Encoding", "identity")
                                            val status = conn.responseCode
                                            if (status in listOf(301,302,303,307,308)) {
                                                val location = conn.getHeaderField("Location") ?: throw IllegalArgumentException("Redirección sin destino.")
                                                target = URL(target,location); conn.disconnect(); continue
                                            }
                                            require(status == 200) { "No se pudo descargar la actualización (HTTP $status)." }
                                            require(conn.contentLengthLong == size) { "El tamaño de la descarga no coincide. Busca actualizaciones otra vez." }
                                            response = conn; break
                                        }
                                        val conn = response ?: throw IllegalArgumentException("Demasiadas redirecciones.")
                                        val started = System.nanoTime()
                                        var read = 0L; var lastProgress = 0L
                                        conn.inputStream.use { input -> part.outputStream().use { output ->
                                            val buffer = ByteArray(65536)
                                            while (true) {
                                                if (cancelled.get()) throw InterruptedException()
                                                require(System.nanoTime()-started < 600_000_000_000L) { "La descarga tardó demasiado. Reintenta." }
                                                val n = input.read(buffer); if (n < 0) break
                                                read += n; require(read <= size) { "La descarga supera el tamaño esperado." }; output.write(buffer,0,n)
                                                val now = System.nanoTime()
                                                if (now-lastProgress > 150_000_000L || read == size) {
                                                    lastProgress = now
                                                    val value = read
                                                    activity.runOnUiThread { channel.invokeMethod("progress", mapOf("received" to value,"total" to size)) }
                                                }
                                            }
                                        } }
                                        verify(part, code, expected, size, expectedVersion)
                                        if (cancelled.get()) throw InterruptedException()
                                        file.delete()
                                        require(part.renameTo(file)) { "No se pudo preparar la instalación." }
                                    }
                                    if (cancelled.get()) throw InterruptedException()
                                    activity.runOnUiThread { result.success(null) }
                                } catch (error: Exception) {
                                    val stopped = cancelled.get() || error is InterruptedException
                                    activity.runOnUiThread { result.error(if (stopped) "cancelled" else "download", if (stopped) "Descarga cancelada." else error.message ?: "No se pudo descargar la actualización.", null) }
                                } finally {
                                    part.delete(); connection?.disconnect(); connection = null; downloading.set(false)
                                }
                            }.start()
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) { result.error("update", error.message ?: "No se pudo completar la actualización.", null) }
        }
    }

    fun close() { cancelled.set(true); connection?.disconnect(); channel.setMethodCallHandler(null) }
}
