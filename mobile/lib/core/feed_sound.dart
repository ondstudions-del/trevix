import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'audio.dart';

/// Música de las fotos y textos con canción en el feed: suena sola, en bucle, la de la última publicación que quedó a
/// la vista, y se calla al salir de la pantalla, al abrir otra pantalla o al pasar la app a segundo plano.
/// El botón de sonido la silencia en todas las publicaciones (se guarda en el teléfono).
class FeedSound extends ChangeNotifier with WidgetsBindingObserver {
  FeedSound._() {
    WidgetsBinding.instance.addObserver(this);
    SharedPreferences.getInstance().then((prefs) {
      _muted = prefs.getBool(_prefKey) ?? false;
      notifyListeners();
    }).catchError((_) {});
  }

  static final FeedSound instance = FeedSound._();
  static const _prefKey = 'feed_sound_muted';

  bool _muted = false;
  bool _foreground = true;

  /// Publicaciones a la vista con canción, de la que apareció antes a la última.
  final List<String> _visible = [];
  final Map<String, Song> _songs = {};

  bool get muted => _muted;

  void show(String key, Song song) {
    if (!song.available || song.audioUrl.isEmpty) return;
    songPlayer.prefetch(song);
    _songs[key] = song;
    if (_visible.isNotEmpty && _visible.last == key) return;
    _visible
      ..remove(key)
      ..add(key);
    _sync();
  }

  void hide(String key) {
    if (!_visible.remove(key)) return;
    _songs.remove(key);
    songPlayer.stop(key);
    _sync();
  }

  Future<void> toggleMute() async {
    _muted = !_muted;
    notifyListeners();
    if (_muted) {
      for (final key in _visible) {
        songPlayer.stop(key);
      }
    } else {
      _sync();
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, _muted);
    } catch (_) {}
  }

  void _sync() {
    if (_muted || !_foreground || _visible.isEmpty) return;
    final key = _visible.last;
    final song = _songs[key];
    if (song == null || songPlayer.currentKey == key) return;
    songPlayer.play(key, song, clip: true, loop: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _foreground) return;
    _foreground = foreground;
    if (!foreground) {
      for (final key in _visible) {
        songPlayer.stop(key);
      }
    } else {
      _sync();
    }
  }
}

final feedSound = FeedSound.instance;
