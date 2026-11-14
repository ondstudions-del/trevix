import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trevix/core/api.dart';
import 'package:trevix/core/private_chats.dart';
import 'package:trevix/models/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(privateChats.lock);

  test('la bandeja marca los chats privados', () {
    final user = {'id': 2, 'username': 'ana', 'display_name': 'Ana'};
    expect(Conversation.fromJson({'id': 1, 'user': user, 'private': true}).isPrivate, isTrue);
    expect(Conversation.fromJson({'id': 1, 'user': user}).isPrivate, isFalse);
  });

  test('el desbloqueo viaja en la API hasta que se bloquea', () {
    privateChats.unlock('7.123.abc');
    expect(api.privateToken, '7.123.abc');
    expect(privateChats.unlocked.value, isTrue);
    privateChats.lock();
    expect(api.privateToken, isNull);
    expect(privateChats.unlocked.value, isFalse);
  });

  test('se bloquea tras más de un minuto en segundo plano, no en un vistazo', () {
    privateChats.unlock('7.123.abc');
    privateChats.didChangeAppLifecycleState(AppLifecycleState.paused);
    privateChats.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(privateChats.unlocked.value, isTrue);
  });
}
