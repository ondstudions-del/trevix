package com.ondsc.trevix

import android.app.RemoteInput
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import org.json.JSONObject

/**
 * Reinicio del teléfono, alarma de los avisos y las acciones «Responder» (cifrada en los chats cifrados, E2ee) y
 * «Marcar como leído» de un chat.
 */
class PushReceiver : BroadcastReceiver() {
    companion object {
        const val TICK = "com.ondsc.trevix.avisos.TICK"
        const val REPLY = "com.ondsc.trevix.avisos.REPLY"
        const val READ = "com.ondsc.trevix.avisos.READ"
    }

    override fun onReceive(c: Context, intent: Intent) {
        when (intent.action) {
            // Con Firebase activo los avisos llegan solos: no hace falta el servicio.
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED -> if (Push.enabled(c) && !Fcm.active(c)) PushService.start(c)
            TICK -> {
                val service = PushService.instance
                if (service != null) service.pollNow() else if (Push.enabled(c) && !Fcm.active(c)) PushService.start(c)
            }
            REPLY, READ -> chatAction(c, intent)
        }
    }

    private fun chatAction(c: Context, intent: Intent) {
        val conversation = intent.getLongExtra(Push.EXTRA_CONVERSATION, 0)
        if (conversation <= 0 || !Push.enabled(c)) return
        val text = if (intent.action == REPLY) {
            RemoteInput.getResultsFromIntent(intent)?.getCharSequence(Push.KEY_REPLY)?.toString()?.trim().orEmpty()
        } else {
            null
        }
        if (text != null && text.isEmpty()) return
        val pending = goAsync()
        Thread {
            try {
                val sent = text == null || E2ee.reply(c, conversation, text) in 200..299
                if (sent) {
                    Push.request(c, "POST", "conversations/$conversation/read", JSONObject())
                    Push.cancelChat(c, conversation)
                } else {
                    Push.replyFailed(c, conversation)
                }
            } catch (_: Exception) {
                if (text != null) Push.replyFailed(c, conversation)
            } finally {
                pending.finish()
            }
        }.start()
    }
}
