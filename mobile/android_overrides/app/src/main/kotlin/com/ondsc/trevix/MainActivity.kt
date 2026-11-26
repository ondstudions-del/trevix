package com.ondsc.trevix

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Canal «trevix/push» (lib/core/push.dart): iniciar o detener los avisos al instante, limpiar los avisos ya vistos y
 * entregar o borrar la clave de los chats cifrados para las notificaciones. Canal «trevix/fcm» (lib/core/fcm.dart):
 * iniciar Firebase con los datos del servidor, obtener el token del teléfono y activar o borrar los avisos push.
 * Canal «trevix/share» (lib/core/share_in.dart): lo compartido desde otras apps (ShareIn).
 * Canal «trevix/app_icon»: iconos alternativos del lanzador (activity-alias).
 *
 * Extiende FlutterFragmentActivity para local_auth (Face ID / huella del bloqueo de app).
 */
class MainActivity : FlutterFragmentActivity() {
    /** Alias LAUNCHER con el que se abrió esta sesión (p. ej. MainActivityHeart). */
    private var sessionLaunchAlias: String? = null

    /** Alias que no se desactivan hasta cerrar la app: evita «desinstalada» y cierre abrupto. */
    private val pendingDisableAliases = linkedSetOf<String>()

    companion object {
        @Volatile private var fcmChannel: MethodChannel? = null

        /** Avisa a Flutter de una llamada LiveKit (app en primer plano o al abrir la notificación). */
        fun forwardLiveKitCall(sessionId: String, extra: android.os.Bundle? = null) {
            if (sessionId.isEmpty()) return
            val map = mutableMapOf<String, String>("session_id" to sessionId)
            extra?.let { b ->
                for (key in listOf("kind", "caller_name", "caller_username", "caller_avatar", "trevix_link")) {
                    b.getString(key)?.takeIf { it.isNotEmpty() }?.let { map[key] = it }
                }
            }
            fcmChannel?.invokeMethod("livekit_call", map)
        }

        /** Actualiza contadores en Flutter (solo con motor activo; hilo principal). */
        fun forwardActivitySync() {
            val ch = fcmChannel ?: return
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                try {
                    ch.invokeMethod("activity_sync", null)
                } catch (_: Exception) {
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        captureSessionLaunchAlias()
        reconcileLauncherIconsFromPrefs()
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) ShareIn.handle(this, intent)
    }

    override fun onDestroy() {
        if (isFinishing) {
            flushPendingAliasDisables()
        }
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        ShareIn.handle(this, intent)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        ShareIn.channel = null
        fcmChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ShareIn.channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "trevix/share").apply {
            setMethodCallHandler { call, result ->
                if (call.method == "take") result.success(ShareIn.take()) else result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "trevix/app_icon").setMethodCallHandler { call, result ->
            when (call.method) {
                "supported" -> result.success(true)
                "current" -> result.success(currentLauncherAlias())
                "set" -> {
                    try {
                        val alias = call.argument<String>("alias")
                        val applied = setLauncherAlias(alias)
                        result.success(applied)
                    } catch (e: Exception) {
                        result.error("icon", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "trevix/push").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val token = call.argument<String>("token").orEmpty()
                    val api = call.argument<String>("api").orEmpty()
                    if (token.isEmpty() || api.isEmpty()) {
                        result.success(false)
                    } else {
                        Push.configure(this, token, api)
                        Fcm.setActive(this, false)
                        PushService.start(this)
                        result.success(true)
                    }
                }
                "stop" -> {
                    val forget = call.argument<Boolean>("forget") ?: false
                    Push.disable(this, forget)
                    PushService.stop(this)
                    if (forget) Push.cancelAll(this)
                    result.success(null)
                }
                "activeChat" -> {
                    val id = (call.argument<Number>("id") ?: 0).toLong()
                    Push.activeChat = id
                    if (id > 0) Push.cancelChat(this, id)
                    result.success(null)
                }
                "e2eeKey" -> {
                    val uid = (call.argument<Number>("uid") ?: 0).toLong()
                    val keyId = (call.argument<Number>("keyId") ?: 0).toLong()
                    E2ee.store(this, uid, keyId, call.argument<String>("seed").orEmpty())
                    result.success(null)
                }
                "e2eeForget" -> {
                    E2ee.forget(this)
                    result.success(null)
                }
                "clearActivity" -> {
                    Push.cancelActivity(this)
                    result.success(null)
                }
                "cancelIncomingCall" -> {
                    val sessionId = call.argument<String>("sessionId").orEmpty()
                    if (sessionId.isNotEmpty()) Push.cancelIncomingCall(this, sessionId)
                    result.success(null)
                }
                "batteryRestricted" -> {
                    result.success(!getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(packageName))
                }
                "openBatterySettings" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                    } catch (_: Exception) {
                        startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
                    }
                    result.success(null)
                }
                "openChannelSettings" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName))
                    } catch (_: Exception) {
                        startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        fcmChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "trevix/fcm").also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "register" -> {
                        val token = call.argument<String>("token").orEmpty()
                        val api = call.argument<String>("api").orEmpty()
                        if (token.isEmpty() || api.isEmpty()) {
                            result.success(null)
                        } else {
                            Push.configure(this, token, api)
                            Fcm.save(
                                this,
                                call.argument<String>("app_id").orEmpty(),
                                call.argument<String>("api_key").orEmpty(),
                                call.argument<String>("project_id").orEmpty(),
                                call.argument<String>("sender_id").orEmpty(),
                            )
                            Fcm.token(this) { fcmToken -> runOnUiThread { result.success(fcmToken) } }
                        }
                    }
                    "activate" -> {
                        Fcm.setActive(this, true)
                        PushService.stop(this)
                        Push.consumePendingLiveKitCall(this)?.let { (sid, meta) ->
                            runOnUiThread { forwardLiveKitCall(sid, meta) }
                        }
                        result.success(null)
                    }
                    "delete" -> {
                        Fcm.delete(this)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private val launcherAliases = listOf(
        "com.ondsc.trevix.MainActivityDefault",
        "com.ondsc.trevix.MainActivityWave",
        "com.ondsc.trevix.MainActivityHeart",
        "com.ondsc.trevix.MainActivityMessages",
        "com.ondsc.trevix.MainActivityMark",
    )

    private fun captureSessionLaunchAlias() {
        val cn = intent?.component?.className ?: return
        if (cn == MainActivity::class.java.name) return
        if (launcherAliases.any { cn == it }) {
            sessionLaunchAlias = cn
        }
    }

    private fun readIconPref(): String {
        val p = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        return p.getString("flutter.trevix_app_icon", "original") ?: "original"
    }

    private fun aliasClassForPref(choice: String): String = when (choice) {
        "wave" -> "com.ondsc.trevix.MainActivityWave"
        "heart" -> "com.ondsc.trevix.MainActivityHeart"
        "messages" -> "com.ondsc.trevix.MainActivityMessages"
        "mark" -> "com.ondsc.trevix.MainActivityMark"
        else -> "com.ondsc.trevix.MainActivityDefault"
    }

    private fun resolveWantClass(alias: String?): String = when {
        alias.isNullOrEmpty() || alias == "MainActivityDefault" || alias == "com.ondsc.trevix.MainActivityDefault" ->
            "com.ondsc.trevix.MainActivityDefault"
        alias.startsWith("com.") -> alias
        else -> "com.ondsc.trevix.$alias"
    }

    /** Icono elegido en Ajustes (puede diferir del alias de la sesión hasta cerrar la app). */
    private fun currentLauncherAlias(): String? =
        resolveWantClass(
            when (readIconPref()) {
                "wave" -> "MainActivityWave"
                "heart" -> "MainActivityHeart"
                "messages" -> "MainActivityMessages"
                "mark" -> "MainActivityMark"
                else -> "MainActivityDefault"
            },
        ).substringAfterLast('.')

    private fun reconcileLauncherIconsFromPrefs() {
        applyLauncherAlias(aliasClassForPref(readIconPref()))
    }

    private fun setLauncherAlias(alias: String?): String {
        applyLauncherAlias(resolveWantClass(alias))
        return resolveWantClass(alias).substringAfterLast('.')
    }

    /**
     * Un solo alias LAUNCHER activo (salvo el de esta sesión, que se apaga al salir).
     * Si se desactiva el alias con el que el usuario abrió la app mientras sigue dentro,
     * Android muestra «aplicación desinstalada» y cierra TREVIX.
     */
    private fun applyLauncherAlias(want: String) {
        val pm = packageManager
        pm.setComponentEnabledSetting(
            ComponentName(this, MainActivity::class.java),
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            PackageManager.DONT_KILL_APP,
        )
        pm.setComponentEnabledSetting(
            ComponentName(this, want),
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            PackageManager.DONT_KILL_APP,
        )
        for (name in launcherAliases) {
            if (name == want) continue
            disableLauncherAlias(name)
        }
        if (!isComponentEnabled(want)) {
            throw IllegalStateException("No se pudo activar ${want.substringAfterLast('.')}")
        }
    }

    private fun shouldDeferDisable(aliasFull: String): Boolean {
        val launch = sessionLaunchAlias ?: return false
        return launch == aliasFull ||
            launch.endsWith(".${aliasFull.substringAfterLast('.')}")
    }

    private fun disableLauncherAlias(aliasFull: String) {
        if (shouldDeferDisable(aliasFull)) {
            pendingDisableAliases.add(aliasFull)
            return
        }
        packageManager.setComponentEnabledSetting(
            ComponentName(this, aliasFull),
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            PackageManager.DONT_KILL_APP,
        )
    }

    private fun flushPendingAliasDisables() {
        if (pendingDisableAliases.isEmpty()) return
        val pm = packageManager
        for (name in pendingDisableAliases) {
            pm.setComponentEnabledSetting(
                ComponentName(this, name),
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP,
            )
        }
        pendingDisableAliases.clear()
    }

    private fun isComponentEnabled(className: String): Boolean {
        val state = packageManager.getComponentEnabledSetting(ComponentName(this, className))
        return state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED ||
            (state == PackageManager.COMPONENT_ENABLED_STATE_DEFAULT && className.endsWith("MainActivityDefault"))
    }

    override fun onResume() {
        super.onResume()
        Push.appVisible = true
        Push.consumePendingLiveKitCall(this)?.let { (sid, meta) ->
            forwardLiveKitCall(sid, meta)
        }
    }

    override fun onPause() {
        Push.appVisible = false
        super.onPause()
    }
}
