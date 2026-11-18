import Flutter
import UIKit

public class TrevixAppIconPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "trevix/app_icon", binaryMessenger: registrar.messenger())
    let instance = TrevixAppIconPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "supported":
      result(UIApplication.shared.supportsAlternateIcons)
    case "current":
      result(UIApplication.shared.alternateIconName)
    case "set":
      let args = call.arguments as? [String: Any]
      var name = args?["name"] as? String
      if name?.isEmpty == true { name = nil }
      guard UIApplication.shared.supportsAlternateIcons else {
        result(FlutterError(code: "unsupported", message: "Este dispositivo no admite iconos alternativos.", details: nil))
        return
      }
      // Ya está el icono pedido: no volver a mostrar el diálogo del sistema.
      if UIApplication.shared.alternateIconName == name {
        result(nil)
        return
      }
      UIApplication.shared.setAlternateIconName(name) { error in
        if let error = error {
          result(FlutterError(code: "icon", message: error.localizedDescription, details: nil))
        } else {
          result(nil)
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
