package com.ondsc.trevix

import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Canal «trevix/push» (lib/core/push.dart): iniciar o detener los avisos al instante, limpiar los avisos ya vistos y
 * entregar o borrar la clave de los chats cifrados para las notificaciones. Canal «trevix/fcm» (lib/core/fcm.dart):
 * iniciar Firebase con los datos del servidor, obtener el token del teléfono y activar o borrar los avisos push.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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

    override fun onResume() {
        super.onResume()
        Push.appVisible = true
    }

    override fun onPause() {
        Push.appVisible = false
        super.onPause()
    }
}
