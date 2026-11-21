package com.ondsc.trevix

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri

/** Tono de llamada en bucle mientras suena la notificación entrante (Android). */
object CallRing {
  private var player: MediaPlayer? = null
  private var activeSession: String? = null

  @Synchronized
  fun start(c: Context, sessionId: String) {
    if (sessionId == activeSession && player?.isPlaying == true) return
    stop()
    activeSession = sessionId
    try {
      val p = MediaPlayer()
      val uri = Uri.parse("android.resource://${c.packageName}/${R.raw.trevix_llamada}")
      p.setDataSource(c, uri)
      p.setAudioAttributes(
        AudioAttributes.Builder()
          .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
          .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
          .build(),
      )
      p.isLooping = true
      p.prepare()
      p.start()
      player = p
    } catch (_: Exception) {
      stop()
    }
  }

  @Synchronized
  fun stop() {
    try {
      player?.stop()
    } catch (_: Exception) {
    }
    try {
      player?.release()
    } catch (_: Exception) {
    }
    player = null
    activeSession = null
  }
}