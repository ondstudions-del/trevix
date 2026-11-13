import FirebaseCore
import FirebaseMessaging
import Flutter
import UIKit
import UserNotifications

/// Avisos push en iPhone: inicia Firebase con los datos públicos que entrega el servidor (sin GoogleService-Info.plist),
/// registra el teléfono en APNs y devuelve el token de Firebase para guardarlo en TREVIX. Los avisos los arma el
/// servidor y Apple los muestra aunque la app esté cerrada; al tocarlos se abre la pantalla con trevix://open/<enlace>
/// (lib/core/deeplinks.dart). Solo atiende los avisos propios (con «trevix_link»): los locales siguen en su plugin.
public class TrevixFcmPlugin: NSObject, FlutterPlugin, MessagingDelegate {
  private var channel: FlutterMethodChannel?
  private var waiting: [Int: FlutterResult] = [:]
  private var nextWait = 0
  private var apnsReady = false
  private var activeChat = 0

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = TrevixFcmPlugin()
    let channel = FlutterMethodChannel(name: "trevix/fcm", binaryMessenger: registrar.messenger())
    instance.channel = channel
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.addApplicationDelegate(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "register":
      register(args, result)
    case "activate":
      result(nil)
    case "delete":
      guard FirebaseApp.app() != nil else { return result(nil) }
      Messaging.messaging().deleteToken { _ in DispatchQueue.main.async { result(nil) } }
    case "activeChat":
      activeChat = (args["id"] as? NSNumber)?.intValue ?? 0
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func register(_ args: [String: Any], _ result: @escaping FlutterResult) {
    let appId = args["app_id"] as? String ?? ""
    let apiKey = args["api_key"] as? String ?? ""
    let sender = args["sender_id"] as? String ?? ""
    let project = args["project_id"] as? String ?? ""
    guard !appId.isEmpty, !apiKey.isEmpty, !sender.isEmpty else { return result(nil) }
    if FirebaseApp.app() == nil {
      let options = FirebaseOptions(googleAppID: appId, gcmSenderID: sender)
      options.apiKey = apiKey
      if !project.isEmpty { options.projectID = project }
      options.bundleID = Bundle.main.bundleIdentifier ?? "com.ondsc.trevix"
      FirebaseApp.configure(options: options)
    }
    Messaging.messaging().delegate = self
    if apnsReady {
      fetchToken(result)
      return
    }
    // Firebase necesita el token de APNs antes de dar el suyo: se espera a que Apple lo entregue (máximo 15 s).
    let id = nextWait
    nextWait += 1
    waiting[id] = result
    UIApplication.shared.registerForRemoteNotifications()
    DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
      if let pending = self?.waiting.removeValue(forKey: id) { pending(nil) }
    }
  }

  private func fetchToken(_ result: @escaping FlutterResult) {
    Messaging.messaging().token { token, _ in
      DispatchQueue.main.async { result(token) }
    }
  }

  public func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    guard FirebaseApp.app() != nil else { return }
    Messaging.messaging().apnsToken = deviceToken
    apnsReady = true
    let pending = waiting
    waiting.removeAll()
    for (_, result) in pending { fetchToken(result) }
  }

  public func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    let pending = waiting
    waiting.removeAll()
    for (_, result) in pending { result(nil) }
  }

  /// Firebase renovó el token: la app lo vuelve a registrar en TREVIX.
  public func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    guard let token = fcmToken, apnsReady else { return }
    DispatchQueue.main.async { [weak self] in self?.channel?.invokeMethod("token", arguments: token) }
  }

  /// Con la app abierta se muestra el aviso, salvo los del chat que está en pantalla.
  public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                     withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    guard let link = notification.request.content.userInfo["trevix_link"] as? String else { return }
    if activeChat > 0 && link == "messages.php?c=\(activeChat)" {
      completionHandler([])
      return
    }
    completionHandler([.banner, .list, .sound])
  }

  public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                     withCompletionHandler completionHandler: @escaping () -> Void) {
    guard let link = response.notification.request.content.userInfo["trevix_link"] as? String else { return }
    if !link.isEmpty, let url = URL(string: "trevix://open/" + link) {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
      }
    }
    completionHandler()
  }
}
