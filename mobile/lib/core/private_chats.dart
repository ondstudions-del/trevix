import 'package:flutter/widgets.dart';

import 'api.dart';

/// Desbloqueo de los chats privados mientras se usan: va en la cabecera X-Private-Chats de cada consulta. Se pierde al
/// cerrar la lista de privados, al cambiar de cuenta o si la app pasa más de un minuto en segundo plano (elegir una
/// foto o contestar una notificación no la cierra).
class PrivateChats with WidgetsBindingObserver {
  PrivateChats._();

  static final PrivateChats instance = PrivateChats._();

  static const _grace = Duration(minutes: 1);

  final ValueNotifier<bool> unlocked = ValueNotifier(false);
  DateTime? _pausedAt;
  bool _installed = false;

  void install() {
    if (_installed) return;
    _installed = true;
    WidgetsBinding.instance.addObserver(this);
  }

  void unlock(String token) {
    api.privateToken = token;
    unlocked.value = true;
  }

  void lock() {
    api.privateToken = null;
    unlocked.value = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _pausedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final since = _pausedAt;
      _pausedAt = null;
      if (since != null && DateTime.now().difference(since) > _grace) lock();
    }
  }
}

final privateChats = PrivateChats.instance;
