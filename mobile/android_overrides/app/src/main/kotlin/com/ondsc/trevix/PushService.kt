package com.ondsc.trevix

import android.app.AlarmManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Servicio en primer plano (con su aviso fijo y silencioso) que consulta los avisos nuevos: cada 20 s con la
 * pantalla encendida y cada minuto con la pantalla apagada. Con el teléfono dormido una alarma lo despierta; en
 * reposo profundo (Doze) Android la espacia hasta unos minutos. Sin Firebase ni servicios de Google.
 */
class PushService : Service() {
    companion object {
        @Volatile var instance: PushService? = null

        fun start(c: Context) {
            try {
                val intent = Intent(c, PushService::class.java)
                if (Build.VERSION.SDK_INT >= 26) c.startForegroundService(intent) else c.startService(intent)
            } catch (_: Exception) {
                // Android 12+ no deja iniciarlo desde segundo plano salvo excepciones; se reintenta al abrir la app.
            }
        }

        fun stop(c: Context) {
            c.stopService(Intent(c, PushService::class.java))
            c.getSystemService(AlarmManager::class.java).cancel(alarm(c))
        }

        private fun alarm(c: Context): PendingIntent = PendingIntent.getBroadcast(
            c, 1, Intent(c, PushReceiver::class.java).setAction(PushReceiver.TICK),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private val handler = Handler(Looper.getMainLooper())
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private val busy = AtomicBoolean(false)
    private val tick = Runnable { pollNow() }
    @Volatile private var failures = 0

    private val screen = object : BroadcastReceiver() {
        override fun onReceive(c: Context, intent: Intent) = pollNow()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        goForeground()
        val filter = IntentFilter(Intent.ACTION_SCREEN_ON).apply { addAction(Intent.ACTION_USER_PRESENT) }
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(screen, filter, RECEIVER_NOT_EXPORTED) else registerReceiver(screen, filter)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        goForeground()
        if (!Push.enabled(this)) {
            stopSelf()
            return START_NOT_STICKY
        }
        pollNow()
        return START_STICKY
    }

    override fun onDestroy() {
        instance = null
        handler.removeCallbacks(tick)
        try {
            unregisterReceiver(screen)
        } catch (_: Exception) {
        }
        executor.shutdownNow()
        super.onDestroy()
    }

    private fun goForeground() {
        Push.ensureChannels(this)
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val b = Push.builder(this, Push.CHANNEL_SERVICE)
            .setContentTitle("TREVIX")
            .setContentText("Atento a tus mensajes y avisos")
            .setOngoing(true)
            .setShowWhen(false)
        if (launch != null) {
            b.setContentIntent(PendingIntent.getActivity(this, 0, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
        }
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(Push.SERVICE_ID, b.build(), ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING)
        } else {
            startForeground(Push.SERVICE_ID, b.build())
        }
    }

    /** Consulta ahora (si no hay otra en curso), con un wakelock breve para terminar aunque se apague la pantalla. */
    fun pollNow() {
        if (!busy.compareAndSet(false, true)) return
        val wake = getSystemService(PowerManager::class.java).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "trevix:avisos").apply {
            setReferenceCounted(false)
            acquire(60_000)
        }
        try {
            executor.execute {
                var valid = true
                try {
                    valid = Push.poll(this)
                    failures = 0
                } catch (_: Exception) {
                    failures++
                } finally {
                    busy.set(false)
                    if (wake.isHeld) wake.release()
                }
                handler.post {
                    if (valid) {
                        schedule()
                    } else {
                        Push.disable(this, forget = true)
                        stop(this)
                    }
                }
            }
        } catch (_: Exception) {
            busy.set(false)
            if (wake.isHeld) wake.release()
        }
    }

    private fun schedule() {
        if (instance == null) return
        handler.removeCallbacks(tick)
        val interactive = getSystemService(PowerManager::class.java).isInteractive
        val base = if (interactive) 20_000L else 60_000L
        val delay = if (failures > 0) minOf(base shl minOf(failures, 4), 300_000L) else base
        handler.postDelayed(tick, delay)
        getSystemService(AlarmManager::class.java).setAndAllowWhileIdle(
            AlarmManager.ELAPSED_REALTIME_WAKEUP,
            SystemClock.elapsedRealtime() + maxOf(delay, 60_000L) + 5_000L,
            alarm(this),
        )
    }
}
