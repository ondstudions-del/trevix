package com.ondsc.trevix

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
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
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) ShareIn.handle(this, intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        ShareIn.handle(this, intent)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        ShareIn.channel = null
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
                        setLauncherAlias(alias)
                        // Algunos launchers cachean el icono; un segundo intento ayuda a que se vea.
                        Handler(Looper.getMainLooper()).postDelayed({
                            try {
                                setLauncherAlias(alias)
                            } catch (_: Exception) {
                            }
                        }, 800)
                        result.success(null)
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "trevix/fcm").setMethodCallHandler { call, result ->
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

    private val launcherAliases = listOf(
        "com.ondsc.trevix.MainActivityDefault",
        "com.ondsc.trevix.MainActivityWave",
        "com.ondsc.trevix.MainActivityHeart",
        "com.ondsc.trevix.MainActivityMessages",
        "com.ondsc.trevix.MainActivityMark",
    )

    private fun currentLauncherAlias(): String? {
        val pm = packageManager
        for (name in launcherAliases) {
            val state = pm.getComponentEnabledSetting(ComponentName(this, name))
            if (state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED ||
                (state == PackageManager.COMPONENT_ENABLED_STATE_DEFAULT && name.endsWith("MainActivityDefault"))
            ) {
                return name.substringAfterLast('.')
            }
        }
        return "MainActivityDefault"
    }

    /**
     * Cambia solo activity-alias del lanzador. MainActivity nunca se desactiva (si se desactiva,
     * Android muestra «aplicación desinstalada» al tocar el icono anterior).
     */
    private fun setLauncherAlias(alias: String?) {
        val pm = packageManager
        // Siempre dejar MainActivity habilitada (deeplinks, share, FCM).
        pm.setComponentEnabledSetting(
            ComponentName(this, MainActivity::class.java),
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            PackageManager.DONT_KILL_APP,
        )
        val want = when {
            alias.isNullOrEmpty() || alias == "MainActivityDefault" || alias == "com.ondsc.trevix.MainActivityDefault" ->
                "com.ondsc.trevix.MainActivityDefault"
            alias.startsWith("com.") -> alias
            else -> "com.ondsc.trevix.$alias"
        }
        for (name in launcherAliases) {
            pm.setComponentEnabledSetting(
                ComponentName(this, name),
                if (name == want) PackageManager.COMPONENT_ENABLED_STATE_ENABLED else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP,
            )
        }
    }

    override fun onResume() {
        super.onResume()
        Push.appVisible = true
    }

    override fun onPause() {
        Push.appVisible = false
        super.onPause()
    }
}
