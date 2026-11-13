import '../models/models.dart';
import 'api.dart';

/// Señales para los intereses de «Para ti»: cuánto tiempo estuvo una publicación en pantalla y si se compartió
/// fuera de TREVIX. Las propias no se envían; si falla la red no se reintenta (es una pista, no un dato crítico).
class Signals {
  Signals._();

  static const _minSeconds = 3;
  static final Map<int, int> _sent = {};

  static void view(Post post, Duration shown) {
    if (post.isAuthor) return;
    final seconds = shown.inSeconds;
    if (seconds < _minSeconds || seconds <= (_sent[post.id] ?? 0)) return;
    _sent[post.id] = seconds;
    api.post('posts/${post.id}/view', {'seconds': seconds}).then((_) {}, onError: (_) {});
  }

  static void share(Post post) {
    if (post.isAuthor) return;
    api.post('posts/${post.id}/share').then((_) {}, onError: (_) {});
  }
}

/// Mide el tiempo que algo está en pantalla: [start] al mostrarse, [stop] al dejar de verse (devuelve lo acumulado).
class ScreenTime {
  final Stopwatch _watch = Stopwatch();

  bool get running => _watch.isRunning;

  void start() {
    if (!_watch.isRunning) _watch.start();
  }

  Duration stop() {
    _watch.stop();
    return _watch.elapsed;
  }
}
