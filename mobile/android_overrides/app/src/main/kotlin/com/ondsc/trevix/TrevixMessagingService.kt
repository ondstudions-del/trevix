package com.ondsc.trevix

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import org.json.JSONObject

/**
 * Avisos de Firebase con la app abierta, en segundo plano o cerrada. «sync»: hay algo nuevo; los mensajes que vienen
 * dentro («items») se muestran al instante y después se consulta GET me/push con los cursores guardados, que solo
 * muestra lo que no se había mostrado (los avisos que se juntan llegan como uno).
 * «show»: aviso del panel de administración, se muestra tal cual.
 */
class TrevixMessagingService : FirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        if (!Push.enabled(this)) return
        val data = message.data
        when (data["type"]) {
            "sync" -> try {
                data["items"]?.let { Push.showInline(this, it) }
                val ok = Push.poll(this)
                if (!ok) {
                    Push.disable(this, forget = true)
                    Push.cancelAll(this)
                } else {
                    MainActivity.forwardActivitySync()
                }
            } catch (_: Exception) {
            }
            "show" -> Push.showBroadcast(this, data["key"].orEmpty(), data["title"].orEmpty(), data["body"].orEmpty(), data["link"].orEmpty())
            "livekit_call" -> try {
                val sessionId = data["session_id"].orEmpty()
                Push.showIncomingCall(
                    this,
                    sessionId,
                    data["kind"].orEmpty(),
                    data["caller_name"].orEmpty(),
                    data["trevix_link"].orEmpty(),
                )
                val extra = android.os.Bundle().apply {
                    putString("kind", data["kind"].orEmpty())
                    putString("caller_name", data["caller_name"].orEmpty())
                    putString("caller_username", data["caller_username"].orEmpty())
                    putString("caller_avatar", data["caller_avatar"].orEmpty())
                    putString("trevix_link", data["trevix_link"].orEmpty())
                }
                MainActivity.forwardLiveKitCall(sessionId, extra)
            } catch (_: Exception) {
            }
            "livekit_live" -> try {
                val sid = data["session_id"].orEmpty()
                val link = data["trevix_link"].orEmpty()
                val name = data["username"].orEmpty()
                Push.showBroadcast(
                    this,
                    "live:$sid",
                    if (name.isNotEmpty()) "@$name · EN VIVO" else "EN VIVO",
                    "Alguien que sigues está transmitiendo ahora",
                    link,
                )
            } catch (_: Exception) {
            }
        }
    }

    /** Firebase cambió el token del teléfono: se registra el nuevo para seguir recibiendo avisos. */
    override fun onNewToken(token: String) {
        if (!Push.enabled(this) || !Fcm.active(this)) return
        try {
            val version = packageManager.getPackageInfo(packageName, 0).versionName.orEmpty()
            Push.request(this, "POST", "me/push/devices", JSONObject()
                .put("token", token)
                .put("platform", "android")
                .put("app_version", version))
        } catch (_: Exception) {
        }
    }
}
