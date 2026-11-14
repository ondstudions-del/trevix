package com.ondsc.trevix

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.webkit.MimeTypeMap
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Fotos, videos y textos compartidos desde otras apps (ACTION_SEND y ACTION_SEND_MULTIPLE). Los archivos se copian a
 * la caché de la app y quedan pendientes hasta que Flutter los pide con «take» por el canal «trevix/share»; si la app
 * ya está abierta se le avisa con «shared». Solo se aceptan URIs content:// de otras apps (nunca archivos propios).
 */
object ShareIn {
    private const val MAX_FILES = 10
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pending: Map<String, Any?>? = null
    var channel: MethodChannel? = null

    fun take(): Map<String, Any?>? {
        val p = pending
        pending = null
        return p
    }

    fun handle(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) return
        val uris = mutableListOf<Uri>()
        if (action == Intent.ACTION_SEND) {
            stream(intent)?.let { uris.add(it) }
        } else {
            streams(intent)?.let { uris.addAll(it) }
        }
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)?.take(5000)
        val type = intent.type.orEmpty()
        // El mismo intent no se procesa dos veces (al volver a la actividad, por ejemplo).
        intent.action = null
        val app = context.applicationContext
        io.execute {
            val dir = File(app.cacheDir, "shared").apply { mkdirs() }
            dir.listFiles()?.forEach { if (System.currentTimeMillis() - it.lastModified() > 86_400_000L) it.delete() }
            val files = mutableListOf<Map<String, String>>()
            val stamp = System.currentTimeMillis()
            for ((i, uri) in uris.take(MAX_FILES).withIndex()) {
                if (uri.scheme != "content" || uri.authority.orEmpty().startsWith(app.packageName)) continue
                val mime = app.contentResolver.getType(uri) ?: type
                if (!mime.startsWith("image/") && !mime.startsWith("video/")) continue
                val ext = MimeTypeMap.getSingleton().getExtensionFromMimeType(mime) ?: if (mime.startsWith("video/")) "mp4" else "jpg"
                val out = File(dir, "${stamp}_$i.$ext")
                try {
                    app.contentResolver.openInputStream(uri)?.use { input -> out.outputStream().use { input.copyTo(it) } }
                    if (out.length() > 0) files.add(mapOf("path" to out.absolutePath, "mime" to mime)) else out.delete()
                } catch (_: Exception) {
                    out.delete()
                }
            }
            if (files.isEmpty() && text.isNullOrBlank()) return@execute
            main.post {
                pending = mapOf("files" to files, "text" to text)
                channel?.invokeMethod("shared", null)
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun stream(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        else intent.getParcelableExtra(Intent.EXTRA_STREAM)

    @Suppress("DEPRECATION")
    private fun streams(intent: Intent): List<Uri>? =
        if (Build.VERSION.SDK_INT >= 33) intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        else intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
}
