package com.ondsc.trevix

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Person
import android.app.RemoteInput
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Shader
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.util.LruCache
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

/**
 * Avisos al instante sin Firebase: PushService consulta GET me/push cada pocos segundos y aquí se convierten en
 * notificaciones del sistema (una por chat con sus últimos mensajes, y una por cada aviso de actividad).
 * El token de la sesión llega desde Flutter (MainActivity) y se guarda en las preferencias privadas de la app.
 */
object Push {
    const val CHANNEL_MESSAGES = "trevix_mensajes"
    const val CHANNEL_ACTIVITY = "trevix_actividad"
    const val CHANNEL_SERVICE = "trevix_conexion"
    const val SERVICE_ID = 7000
    const val KEY_REPLY = "reply"
    const val EXTRA_CONVERSATION = "conversation_id"
    private const val TAG_ACTIVITY = "actividad"
    private const val PREFS = "trevix_push"
    private const val COLOR = 0xFF8B5CF6.toInt()

    @Volatile var appVisible = false
    @Volatile var activeChat = 0L

    private class Line(val sender: String, val text: String, val time: Long)

    private val history = HashMap<Long, MutableList<Line>>()
    private val avatars = LruCache<String, Bitmap>(40)

    fun prefs(c: Context): SharedPreferences = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun token(c: Context) = prefs(c).getString("token", null)
    private fun api(c: Context) = prefs(c).getString("api", null)

    fun enabled(c: Context) = prefs(c).getBoolean("enabled", false) && !token(c).isNullOrEmpty() && !api(c).isNullOrEmpty()

    /** Otra cuenta (otro token) empieza de cero: sin cursores, no avisa de lo que ya existía. */
    fun configure(c: Context, token: String, api: String) {
        val p = prefs(c)
        val e = p.edit()
        if (p.getString("token", null) != token) {
            e.remove("n").remove("m").remove("f").remove("r")
            synchronized(history) { history.clear() }
        }
        e.putString("token", token).putString("api", api).putBoolean("enabled", true).apply()
    }

    /** forget: al cerrar sesión se borran el token y los cursores. */
    fun disable(c: Context, forget: Boolean) {
        if (forget) prefs(c).edit().clear().apply() else prefs(c).edit().putBoolean("enabled", false).apply()
    }

    class Result(val code: Int, val body: String)

    fun request(c: Context, method: String, path: String, json: JSONObject? = null): Result {
        val conn = URL(api(c) + path).openConnection() as HttpURLConnection
        try {
            conn.requestMethod = method
            conn.connectTimeout = 15_000
            conn.readTimeout = 20_000
            conn.setRequestProperty("Accept", "application/json")
            conn.setRequestProperty("Authorization", "Bearer " + token(c))
            if (json != null) {
                conn.doOutput = true
                conn.setRequestProperty("Content-Type", "application/json; charset=utf-8")
                conn.outputStream.use { it.write(json.toString().toByteArray(Charsets.UTF_8)) }
            }
            val code = conn.responseCode
            val stream = if (code in 200..299) conn.inputStream else conn.errorStream
            return Result(code, stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() } ?: "")
        } finally {
            conn.disconnect()
        }
    }

    /** Una consulta: guarda los cursores nuevos y muestra lo que llegó. Devuelve false si la sesión ya no vale. */
    fun poll(c: Context): Boolean {
        val p = prefs(c)
        val since = p.getString("r", "") ?: ""
        val path = if (since.isEmpty()) "me/push" else
            "me/push?n=${p.getLong("n", 0)}&m=${p.getLong("m", 0)}&f=${p.getLong("f", 0)}&r=" + URLEncoder.encode(since, "UTF-8")
        val res = request(c, "GET", path)
        if (res.code == 401) return false
        if (res.code != 200) throw IllegalStateException("HTTP ${res.code}")
        val root = JSONObject(res.body)
        val cursor = root.optJSONObject("meta")?.optJSONObject("cursor") ?: return true
        p.edit()
            .putLong("n", cursor.optLong("n"))
            .putLong("m", cursor.optLong("m"))
            .putLong("f", cursor.optLong("f"))
            .putString("r", cursor.optString("r"))
            .apply()
        if (since.isEmpty()) return true
        val items = root.optJSONArray("data") ?: return true
        for (i in 0 until items.length()) {
            try {
                show(c, items.getJSONObject(i))
            } catch (_: Exception) {
            }
        }
        return true
    }

    private fun JSONObject.str(key: String) = if (isNull(key)) "" else optString(key)

    private fun manager(c: Context) = c.getSystemService(NotificationManager::class.java)

    fun ensureChannels(c: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        manager(c).createNotificationChannels(listOf(
            NotificationChannel(CHANNEL_MESSAGES, "Mensajes", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Mensajes y reacciones en tus chats"
            },
            NotificationChannel(CHANNEL_ACTIVITY, "Actividad", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Me gusta, comentarios, menciones, seguidores y avisos de TREVIX"
            },
            NotificationChannel(CHANNEL_SERVICE, "Conexión en segundo plano", NotificationManager.IMPORTANCE_MIN).apply {
                description = "Mantiene TREVIX atento a tus mensajes y avisos con la app cerrada"
                setShowBadge(false)
            },
        ))
    }

    @Suppress("DEPRECATION")
    fun builder(c: Context, channel: String): Notification.Builder {
        val b = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(c, channel) else Notification.Builder(c)
        b.setSmallIcon(R.drawable.ic_stat_trevix).setColor(COLOR)
        if (Build.VERSION.SDK_INT < 26) {
            b.setPriority(if (channel == CHANNEL_SERVICE) Notification.PRIORITY_MIN else Notification.PRIORITY_HIGH)
            if (channel != CHANNEL_SERVICE) b.setDefaults(Notification.DEFAULT_ALL)
        }
        return b
    }

    /** Abre la pantalla de la app (trevix://open/<link>, lo resuelve lib/core/deeplinks.dart). */
    fun open(c: Context, link: String, code: Int): PendingIntent {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse("trevix://open/$link"), c, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(c, code, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    fun show(c: Context, item: JSONObject) {
        val kind = item.str("kind")
        val conversation = item.optLong("conversation_id")
        val chat = kind == "message" || kind == "reaction"
        if (chat && appVisible && conversation == activeChat) return
        ensureChannels(c)
        val title = item.str("title").ifEmpty { "TREVIX" }
        val text = item.str("text")
        val avatar = avatar(item.str("avatar_url"))
        val link = item.str("link").ifEmpty { "notifications.php" }
        if (kind == "message") {
            showMessage(c, conversation, title, text, avatar, link)
            return
        }
        val key = item.str("key")
        val b = builder(c, if (chat) CHANNEL_MESSAGES else CHANNEL_ACTIVITY)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setAutoCancel(true)
            .setWhen(System.currentTimeMillis())
            .setShowWhen(true)
            .setCategory(if (chat) Notification.CATEGORY_MESSAGE else Notification.CATEGORY_SOCIAL)
            .setContentIntent(open(c, link, key.hashCode()))
        if (avatar != null) b.setLargeIcon(avatar)
        manager(c).notify(if (chat) "chat:$conversation" else TAG_ACTIVITY, key.hashCode(), b.build())
    }

    private fun showMessage(c: Context, conversation: Long, title: String, text: String, avatar: Bitmap?, link: String) {
        val now = System.currentTimeMillis()
        val lines = synchronized(history) {
            val list = history.getOrPut(conversation) { mutableListOf() }
            list.add(Line(title, text, now))
            while (list.size > 6) list.removeAt(0)
            list.toList()
        }
        val code = conversation.toInt()
        val b = builder(c, CHANNEL_MESSAGES)
            .setContentTitle(title)
            .setContentText(text)
            .setAutoCancel(true)
            .setWhen(now)
            .setShowWhen(true)
            .setCategory(Notification.CATEGORY_MESSAGE)
            .setContentIntent(open(c, link, code))
            .setNumber(lines.size)
        if (avatar != null) b.setLargeIcon(avatar)
        if (Build.VERSION.SDK_INT >= 28) {
            val icon = avatar?.let { Icon.createWithBitmap(it) }
            val style = Notification.MessagingStyle(Person.Builder().setName("Tú").build())
            for (l in lines) {
                val sender = Person.Builder().setName(l.sender).apply { if (icon != null) setIcon(icon) }.build()
                style.addMessage(Notification.MessagingStyle.Message(l.text, l.time, sender))
            }
            b.setStyle(style)
        } else if (Build.VERSION.SDK_INT >= 24) {
            @Suppress("DEPRECATION")
            val style = Notification.MessagingStyle("Tú")
            @Suppress("DEPRECATION")
            for (l in lines) style.addMessage(l.text, l.time, l.sender)
            b.setStyle(style)
        } else {
            b.setStyle(Notification.BigTextStyle().bigText(lines.joinToString("\n") { it.text }))
        }

        val mutable = if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0
        val reply = PendingIntent.getBroadcast(
            c, code,
            Intent(c, PushReceiver::class.java).setAction(PushReceiver.REPLY).putExtra(EXTRA_CONVERSATION, conversation),
            PendingIntent.FLAG_UPDATE_CURRENT or mutable,
        )
        val read = PendingIntent.getBroadcast(
            c, code,
            Intent(c, PushReceiver::class.java).setAction(PushReceiver.READ).putExtra(EXTRA_CONVERSATION, conversation),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val actionIcon = Icon.createWithResource(c, R.drawable.ic_stat_trevix)
        b.addAction(
            Notification.Action.Builder(actionIcon, "Responder", reply)
                .addRemoteInput(RemoteInput.Builder(KEY_REPLY).setLabel("Escribe una respuesta…").build())
                .build()
        )
        b.addAction(Notification.Action.Builder(actionIcon, "Marcar como leído", read).build())
        manager(c).notify("chat:$conversation", 0, b.build())
    }

    /** La respuesta desde la notificación no se pudo enviar: se avisa en el mismo lugar. */
    fun replyFailed(c: Context, conversation: Long) {
        val b = builder(c, CHANNEL_MESSAGES)
            .setContentTitle("No se envió tu respuesta")
            .setContentText("Toca para abrir el chat e intentarlo de nuevo.")
            .setAutoCancel(true)
            .setContentIntent(open(c, "messages.php?c=$conversation", conversation.toInt()))
        manager(c).notify("chat:$conversation", 0, b.build())
    }

    fun cancelChat(c: Context, conversation: Long) {
        synchronized(history) { history.remove(conversation) }
        cancelTag(c, "chat:$conversation")
    }

    fun cancelActivity(c: Context) = cancelTag(c, TAG_ACTIVITY)

    fun cancelAll(c: Context) {
        synchronized(history) { history.clear() }
        val nm = manager(c)
        for (n in nm.activeNotifications) if (n.id != SERVICE_ID) nm.cancel(n.tag, n.id)
    }

    private fun cancelTag(c: Context, tag: String) {
        val nm = manager(c)
        for (n in nm.activeNotifications) if (n.tag == tag) nm.cancel(n.tag, n.id)
    }

    /** Foto de perfil redonda para la notificación (en caché; sin foto si no se puede descargar). */
    private fun avatar(url: String): Bitmap? {
        if (url.isEmpty()) return null
        avatars.get(url)?.let { return it }
        return try {
            val conn = URL(url).openConnection() as HttpURLConnection
            conn.connectTimeout = 8_000
            conn.readTimeout = 8_000
            val bytes = try {
                conn.inputStream.use { it.readBytes() }
            } finally {
                conn.disconnect()
            }
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
            var sample = 1
            while (bounds.outWidth / (sample * 2) >= 192 && bounds.outHeight / (sample * 2) >= 192) sample *= 2
            val src = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample })
                ?: return null
            circle(src).also { avatars.put(url, it) }
        } catch (_: Exception) {
            null
        }
    }

    private fun circle(src: Bitmap): Bitmap {
        val size = minOf(src.width, src.height)
        val out = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val shader = BitmapShader(src, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP).apply {
            setLocalMatrix(Matrix().apply { setTranslate(-(src.width - size) / 2f, -(src.height - size) / 2f) })
        }
        Canvas(out).drawCircle(size / 2f, size / 2f, size / 2f, Paint(Paint.ANTI_ALIAS_FLAG).apply { this.shader = shader })
        return out
    }
}
