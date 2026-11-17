package com.ondsc.trevix_app_icon

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * En Android el cambio de icono lo atiende MainActivity (trevix/app_icon).
 * Este stub evita que el registrador del plugin falle al incluir la dependencia.
 */
class TrevixAppIconPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
  private var channel: MethodChannel? = null

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(binding.binaryMessenger, "trevix/app_icon_plugin_stub").also {
      it.setMethodCallHandler(this)
    }
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    result.notImplemented()
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel?.setMethodCallHandler(null)
    channel = null
  }
}
