#!/usr/bin/env bash
# Iconos alternativos + canal MethodChannel + Face ID (bloqueo de app). Ejecutar desde mobile/ con ios/ generado.
set -euo pipefail

python3 tool/prepare_alternate_icons.py --ios ios

PLIST=ios/Runner/Info.plist
pb() { /usr/libexec/PlistBuddy -c "$1" "$PLIST" 2>/dev/null || true; }
set_key() {
  /usr/libexec/PlistBuddy -c "Set :$1 $3" "$PLIST" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :$1 $2 $3" "$PLIST"
}

set_key NSFaceIDUsageDescription string "TREVIX usa Face ID para desbloquear la app cuando activas el bloqueo de app."

# Iconos alternativos (nombres = sets en Assets.xcassets).
pb "Delete :CFBundleIcons"
pb "Add :CFBundleIcons dict"
pb "Add :CFBundleIcons:CFBundlePrimaryIcon dict"
pb "Add :CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconFiles array"
pb "Add :CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconFiles:0 string AppIcon"
pb "Add :CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconName string AppIcon"
pb "Add :CFBundleIcons:CFBundleAlternateIcons dict"
for name in AppIconWave AppIconHeart AppIconMessages AppIconMark; do
  pb "Add :CFBundleIcons:CFBundleAlternateIcons:$name dict"
  pb "Add :CFBundleIcons:CFBundleAlternateIcons:$name:CFBundleIconName string $name"
  pb "Add :CFBundleIcons:CFBundleAlternateIcons:$name:UIPrerenderedIcon bool false"
done
# iPad
pb "Delete :CFBundleIcons~ipad"
pb "Add :CFBundleIcons~ipad dict"
pb "Add :CFBundleIcons~ipad:CFBundlePrimaryIcon dict"
pb "Add :CFBundleIcons~ipad:CFBundlePrimaryIcon:CFBundleIconFiles array"
pb "Add :CFBundleIcons~ipad:CFBundlePrimaryIcon:CFBundleIconFiles:0 string AppIcon"
pb "Add :CFBundleIcons~ipad:CFBundleAlternateIcons dict"
for name in AppIconWave AppIconHeart AppIconMessages AppIconMark; do
  pb "Add :CFBundleIcons~ipad:CFBundleAlternateIcons:$name dict"
  pb "Add :CFBundleIcons~ipad:CFBundleAlternateIcons:$name:CFBundleIconName string $name"
done

# Canal Dart «trevix/app_icon» en AppDelegate.
APPD=ios/Runner/AppDelegate.swift
if ! grep -q 'trevix/app_icon' "$APPD"; then
  cat >> "$APPD" <<'SWIFT'

// MARK: - Icono de la app (Ajustes › Apariencia)
extension AppDelegate {
  func registerAppIconChannel(controller: FlutterViewController) {
    let channel = FlutterMethodChannel(name: "trevix/app_icon", binaryMessenger: controller.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "supported":
        result(UIApplication.shared.supportsAlternateIcons)
      case "set":
        let name = (call.arguments as? [String: Any])?["name"] as? String
        UIApplication.shared.setAlternateIconName(name?.isEmpty == true ? nil : name) { error in
          if let error = error { result(FlutterError(code: "icon", message: error.localizedDescription, details: nil)) }
          else { result(nil) }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
SWIFT
  # Registrar el canal al arrancar.
  if grep -q 'GeneratedPluginRegistrant.register' "$APPD"; then
    perl -0pi -e 's/(GeneratedPluginRegistrant\.register\(with: self\))/$1\n    if let controller = window?.rootViewController as? FlutterViewController {\n      registerAppIconChannel(controller: controller)\n    }/' "$APPD" || true
  fi
  # Con escenas, window puede ser nil al principio: también en didFinish tras super.
  if ! grep -q 'registerAppIconChannel' "$APPD" || ! grep -q 'FlutterViewController' "$APPD"; then
    perl -0pi -e 's/(return super\.application\(application, didFinishLaunchingWithOptions: launchOptions\))/\n    DispatchQueue.main.async {\n      if let controller = self.window?.rootViewController as? FlutterViewController {\n        self.registerAppIconChannel(controller: controller)\n      } else if let controller = UIApplication.shared.windows.first?.rootViewController as? FlutterViewController {\n        self.registerAppIconChannel(controller: controller)\n      }\n    }\n    $1/' "$APPD"
  fi
fi

echo "iOS: iconos alternativos y Face ID listos"
