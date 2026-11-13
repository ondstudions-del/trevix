package com.ondsc.trevix

import android.content.Context
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.messaging.FirebaseMessaging

/**
 * Firebase Cloud Messaging sin google-services.json: los datos públicos del proyecto (identificador de la app, clave
 * de API, proyecto y remitente) llegan del servidor (GET app/config → push) y se guardan en las preferencias privadas
 * para iniciar Firebase en cada arranque del proceso (TrevixApp), también cuando un aviso despierta la app cerrada.
 * Con «fcm» activo, PushService no hace falta: el aviso de Firebase despierta la app y Push.poll muestra lo nuevo.
 */
object Fcm {
    fun save(c: Context, appId: String, apiKey: String, project: String, sender: String) {
        Push.prefs(c).edit()
            .putString("fcm_app_id", appId)
            .putString("fcm_api_key", apiKey)
            .putString("fcm_project", project)
            .putString("fcm_sender", sender)
            .apply()
    }

    private fun options(c: Context): FirebaseOptions? {
        val p = Push.prefs(c)
        val appId = p.getString("fcm_app_id", null).orEmpty()
        val apiKey = p.getString("fcm_api_key", null).orEmpty()
        val sender = p.getString("fcm_sender", null).orEmpty()
        if (appId.isEmpty() || apiKey.isEmpty() || sender.isEmpty()) return null
        return FirebaseOptions.Builder()
            .setApplicationId(appId)
            .setApiKey(apiKey)
            .setGcmSenderId(sender)
            .setProjectId(p.getString("fcm_project", null).orEmpty().ifEmpty { null })
            .build()
    }

    /** Inicia Firebase con los datos guardados. false si aún no hay datos o el teléfono no tiene servicios de Google. */
    fun init(c: Context): Boolean = try {
        if (FirebaseApp.getApps(c).isNotEmpty()) {
            true
        } else {
            val o = options(c)
            if (o == null) false else {
                FirebaseApp.initializeApp(c, o)
                true
            }
        }
    } catch (_: Exception) {
        false
    }

    /** Token de este teléfono en Firebase (null si no se pudo obtener: sin servicios de Google o sin red). */
    fun token(c: Context, done: (String?) -> Unit) {
        if (!init(c)) return done(null)
        try {
            FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
                done(if (task.isSuccessful) task.result else null)
            }
        } catch (_: Exception) {
            done(null)
        }
    }

    fun active(c: Context) = Push.prefs(c).getBoolean("fcm", false)

    fun setActive(c: Context, value: Boolean) {
        Push.prefs(c).edit().putBoolean("fcm", value).apply()
    }

    /** Al salir de la cuenta: el token deja de valer y Firebase ya no entrega avisos de ella a este teléfono. */
    fun delete(c: Context) {
        setActive(c, false)
        try {
            if (FirebaseApp.getApps(c).isNotEmpty()) FirebaseMessaging.getInstance().deleteToken()
        } catch (_: Exception) {
        }
    }
}
