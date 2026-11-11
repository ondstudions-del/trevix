import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../models/models.dart';
import 'api.dart';
import 'device.dart';
import 'i18n.dart';
import 'push.dart';

/// Avisos con la app cerrada o en segundo plano, sin Firebase ni cuenta de Apple:
/// iOS despierta la app con «Actualización en segundo plano» (BGAppRefreshTask) y Android con WorkManager
/// cuando lo consideran oportuno —según el uso, la batería y la red, desde cada 15 minutos— y TREVIX consulta
/// notificaciones y mensajes nuevos para mostrarlos como avisos locales. En Android, mientras estén activos los
/// avisos al instante (core/push.dart), esta revisión se cancela.
class BackgroundNotices {
  BackgroundNotices._();

  /// Debe coincidir con BGTaskSchedulerPermittedIdentifiers (Info.plist) y AppDelegate.
  static const task = 'com.ondsc.trevix.avisos';
  static const _lastNotification = 'trevix_bg_last_notification';
  static const _lastMessages = 'trevix_bg_last_messages';

  /// En Android con «Avisos al instante» activos los muestra PushService (y no hace falta WorkManager ni el aviso
  /// genérico del sondeo de la app).
  static bool instant = false;

  static Future<void> start() async {
    if (AndroidPush.supported) {
      final granted = await DeviceAccess.state(Access.notifications) == AccessState.granted;
      instant = granted && await AndroidPush.wanted() && await AndroidPush.start(api.token ?? '');
      if (!instant) await AndroidPush.stop();
    }
    try {
      await Workmanager().initialize(backgroundDispatcher);
      if (instant) {
        await Workmanager().cancelByUniqueName(task);
        return;
      }
      await Workmanager().registerPeriodicTask(
        task,
        task,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    } catch (_) {
      // Sin «Actualización en segundo plano» (o en el simulador) la app sigue avisando mientras está abierta.
    }
  }

  /// Al cambiar de cuenta: la revisión vuelve a empezar desde lo más reciente de la nueva cuenta.
  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastNotification);
    await prefs.remove(_lastMessages);
  }

  /// Con la app abierta lo visto ya no debe avisarse después.
  static Future<void> markSeen({int? notificationId, String? messagesAt}) async {
    final prefs = await SharedPreferences.getInstance();
    if (notificationId != null && notificationId > (prefs.getInt(_lastNotification) ?? 0)) {
      await prefs.setInt(_lastNotification, notificationId);
    }
    if (messagesAt != null && messagesAt.compareTo(prefs.getString(_lastMessages) ?? '') > 0) {
      await prefs.setString(_lastMessages, messagesAt);
    }
  }

  static Future<void> check() async {
    const storage = FlutterSecureStorage(iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock));
    final token = await storage.read(key: 'trevix_token');
    if (token == null || token.isEmpty) return;
    api.token = token;
    final prefs = await SharedPreferences.getInstance();

    final notifications = (await api.get('notifications')).list;
    final lastId = prefs.getInt(_lastNotification);
    final newest = notifications.isEmpty ? 0 : notifications.map((n) => asInt(n['id'])).reduce((a, b) => a > b ? a : b);
    if (lastId != null) {
      final fresh = notifications.where((n) => !asBool(n['read']) && asInt(n['id']) > lastId).take(3).toList().reversed;
      for (final n in fresh) {
        final actor = asMap(n['actor']);
        final type = asStr(n['type']);
        final who = actor.isEmpty && !type.startsWith('song_') ? 'TREVIX' : asStr(actor['display_name']);
        final text = asStr(n['text']);
        final excerpt = asStr(n['excerpt']).trim();
        await DeviceAccess.notify(1000 + asInt(n['id']) % 100000, 'TREVIX',
            [if (who.isNotEmpty) '$who $text' else text, if (excerpt.isNotEmpty) tr('«{text}»', {'text': excerpt})].join(' '));
      }
    }
    if (newest > (lastId ?? 0)) await prefs.setInt(_lastNotification, newest);

    final conversations = (await api.get('conversations')).list;
    final lastAt = prefs.getString(_lastMessages);
    var latest = lastAt ?? '';
    for (final c in conversations) {
      final at = asStr(c['last_message_at']);
      if (at.compareTo(latest) > 0) latest = at;
      if (lastAt == null || asInt(c['unread']) == 0 || asBool(c['muted']) || at.compareTo(lastAt) <= 0) continue;
      final user = asMap(c['user']);
      await DeviceAccess.notify(500000 + asInt(c['id']) % 100000, asStr(user['display_name'], tr('Mensaje nuevo')),
          asStr(c['preview'], tr('Te envió un mensaje.')));
    }
    if (latest.isNotEmpty) await prefs.setString(_lastMessages, latest);
  }
}

@pragma('vm:entry-point')
void backgroundDispatcher() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await Lang.instance.load();
      await BackgroundNotices.check();
    } catch (_) {}
    return true;
  });
}
