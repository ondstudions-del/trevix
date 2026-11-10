package com.ondsc.trevix

import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Canal «trevix/push» (lib/core/push.dart): iniciar o detener los avisos al instante y limpiar los avisos ya vistos. */
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
