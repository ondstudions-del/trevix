package com.ondsc.trevix

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Contestar / rechazar desde la notificación de llamada. */
class LiveKitCallReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    val sessionId = intent.getStringExtra(EXTRA_SESSION).orEmpty()
    if (sessionId.isEmpty()) return
        when (intent.action) {
      ACTION_DECLINE -> {
        CallRing.stop()
        Push.cancelIncomingCall(context, sessionId)
        if (Push.enabled(context)) {
          Push.request(context, "POST", "livekit/calls/$sessionId/decline")
        }
      }
      ACTION_ANSWER -> {
        CallRing.stop()
        Push.cancelIncomingCall(context, sessionId)
        val link = "livekit-call.php?id=$sessionId&answer=1"
        val open = Intent(Intent.ACTION_VIEW, android.net.Uri.parse("trevix://open/$link"), context, MainActivity::class.java)
          .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        context.startActivity(open)
        MainActivity.forwardLiveKitCall(sessionId, intent.extras)
      }
    }
  }

  companion object {
    const val ACTION_ANSWER = "com.ondsc.trevix.CALL_ANSWER"
    const val ACTION_DECLINE = "com.ondsc.trevix.CALL_DECLINE"
    const val EXTRA_SESSION = "session_id"
  }
}