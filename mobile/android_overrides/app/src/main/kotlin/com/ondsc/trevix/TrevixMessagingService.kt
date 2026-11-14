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
                if (!Push.poll(this)) {
                    Push.disable(this, forget = true)
                    Push.cancelAll(this)
                }
            } catch (_: Exception) {
            }
            "show" -> Push.showBroadcast(this, data["key"].orEmpty(), data["title"].orEmpty(), data["body"].orEmpty(), data["link"].orEmpty())
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
