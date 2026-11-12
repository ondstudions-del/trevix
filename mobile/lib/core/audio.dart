import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/models.dart';
import 'i18n.dart';

/// Un solo reproductor para toda la app: al reproducir una canción se detiene la anterior.
/// En publicaciones e historias suena solo el fragmento (clip); en la biblioteca y los mensajes, la canción entera.
class SongPlayer extends ChangeNotifier {
  SongPlayer._() {
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _serial(() async {
          await _player.pause();
          await _player.seek(Duration.zero);
        });
      }
      notifyListeners();
    });
  }

  static final SongPlayer instance = SongPlayer._();

  final AudioPlayer _player = AudioPlayer();
  String? currentKey;
  bool _configured = false;
  String? error;

  /// just_audio en iOS cierra la app (NSRangeException al quitar el observador «status» de un IndexedPlayerItem)
  /// si se desmonta el reproductor nativo con stop() o se cambia la fuente mientras otra carga sigue en curso.
  /// Por eso las operaciones nativas se encadenan una tras otra y el reproductor nunca se detiene: solo se pausa.
  Future<void> _queue = Future.value();

  Future<void> _serial(Future<void> Function() task) {
    final next = _queue.then((_) => task()).catchError((_) {});
    _queue = next;
    return next;
  }

  Stream<Duration> get position => _player.positionStream;
  Duration? get duration => _player.duration;
  bool get playing => _player.playing;
  bool get buffering =>
      _player.processingState == ProcessingState.loading || _player.processingState == ProcessingState.buffering;

  bool isPlaying(String key) => currentKey == key && playing;
  bool isLoading(String key) => currentKey == key && buffering;

  Future<void> _configure() async {
    if (_configured) return;
    _configured = true;
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
    } catch (_) {}
  }

  /// [key] identifica dónde suena (p. ej. «post:48»), para que solo ese botón se vea activo.
  Future<void> toggle(String key, Song song, {bool clip = false}) async {
    if (!song.available || song.audioUrl.isEmpty) return;
    if (currentKey == key) {
      if (playing) {
        await pause();
      } else {
        await _serial(() async {
          if (currentKey == key) unawaited(_player.play());
        });
      }
      return;
    }
    await play(key, song, clip: clip);
  }

  Future<void> play(String key, Song song, {bool clip = false, bool loop = false}) async {
    if (!song.available || song.audioUrl.isEmpty) return;
    await _configure();
    error = null;
    currentKey = key;
    notifyListeners();
    await _serial(() async {
      if (currentKey != key) return;
      try {
        if (_player.playing) await _player.pause();
        final uri = AudioSource.uri(Uri.parse(song.audioUrl));
        await _player.setAudioSource(
          clip && song.hasClip
              ? ClippingAudioSource(child: uri, start: Duration(seconds: song.clipStart!), end: Duration(seconds: song.clipEnd!))
              : uri,
        );
        if (currentKey != key) return;
        await _player.setLoopMode(loop ? LoopMode.one : LoopMode.off);
        await _player.setVolume(1);
        if (currentKey == key) unawaited(_player.play());
      } catch (_) {
        if (currentKey == key) {
          error = tr('No se pudo reproducir el audio. Revisa tu conexión e inténtalo de nuevo.');
          currentKey = null;
        }
      }
    });
    notifyListeners();
  }

  /// Deja la canción cargada y en pausa en [at] (dentro del fragmento si [clip]) para arrancarla al instante con
  /// [resume]: la cámara de reels la sincroniza así con el inicio de cada toma.
  Future<bool> prepare(String key, Song song, {bool clip = false, Duration at = Duration.zero}) async {
    if (!song.available || song.audioUrl.isEmpty) return false;
    await _configure();
    error = null;
    currentKey = key;
    notifyListeners();
    var ok = false;
    await _serial(() async {
      if (currentKey != key) return;
      try {
        if (_player.playing) await _player.pause();
        final uri = AudioSource.uri(Uri.parse(song.audioUrl));
        await _player.setAudioSource(
          clip && song.hasClip
              ? ClippingAudioSource(child: uri, start: Duration(seconds: song.clipStart!), end: Duration(seconds: song.clipEnd!))
              : uri,
          initialPosition: at,
        );
        await _player.setLoopMode(LoopMode.off);
        await _player.setVolume(1);
        ok = currentKey == key;
      } catch (_) {
        if (currentKey == key) {
          error = tr('No se pudo reproducir el audio. Revisa tu conexión e inténtalo de nuevo.');
          currentKey = null;
        }
      }
    });
    notifyListeners();
    return ok;
  }

  /// Posición actual de lo que suena (relativa al fragmento si se cargó con clip).
  Duration get positionNow => _player.position;

  /// Audio incluido en la app (p. ej. la música de la bienvenida). Usa el mismo reproductor por lo explicado en [_queue].
  Future<void> playAsset(String key, String asset, {bool loop = false, double volume = 1}) async {
    if (currentKey == key && playing) return;
    await _configure();
    error = null;
    currentKey = key;
    notifyListeners();
    await _serial(() async {
      if (currentKey != key) return;
      try {
        if (_player.playing) await _player.pause();
        await _player.setAudioSource(AudioSource.asset(asset));
        if (currentKey != key) return;
        await _player.setLoopMode(loop ? LoopMode.one : LoopMode.off);
        await _player.setVolume(volume);
        if (currentKey == key) unawaited(_player.play());
      } catch (_) {
        if (currentKey == key) currentKey = null;
      }
    });
    notifyListeners();
  }

  /// Reanuda lo que suena con [key] si quedó en pausa (al volver a la app).
  Future<void> resume(String key) => _serial(() async {
        if (currentKey == key && !_player.playing) unawaited(_player.play());
      });

  Future<void> setVolume(double volume) => _serial(() => _player.setVolume(volume));

  /// Vuelve a la sesión de reproducción por el altavoz después de grabar una nota de voz.
  Future<void> restoreSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      _configured = true;
    } catch (_) {}
  }

  Future<void> seek(Duration to) => _serial(() => _player.seek(to));

  Future<void> pause() => _serial(() => _player.pause());

  Future<void> stop([String? key]) async {
    if (key != null && currentKey != key) return;
    currentKey = null;
    notifyListeners();
    await _serial(() async {
      if (currentKey == null && _player.playing) await _player.pause();
    });
    notifyListeners();
  }
}

final songPlayer = SongPlayer.instance;
