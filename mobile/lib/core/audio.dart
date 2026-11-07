import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/models.dart';

/// Un solo reproductor para toda la app: al reproducir una canción se detiene la anterior.
/// En publicaciones e historias suena solo el fragmento (clip); en la biblioteca y los mensajes, la canción entera.
class SongPlayer extends ChangeNotifier {
  SongPlayer._() {
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _player.pause();
        _player.seek(Duration.zero);
      }
      notifyListeners();
    });
  }

  static final SongPlayer instance = SongPlayer._();

  final AudioPlayer _player = AudioPlayer();
  String? currentKey;
  bool _configured = false;
  String? error;

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
        await _player.pause();
      } else {
        await _player.play();
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
    try {
      await _player.stop();
      await _player.setUrl(song.audioUrl);
      if (clip && song.hasClip) {
        await _player.setClip(start: Duration(seconds: song.clipStart!), end: Duration(seconds: song.clipEnd!));
      } else {
        await _player.setClip();
      }
      await _player.setLoopMode(loop ? LoopMode.one : LoopMode.off);
      if (currentKey == key) unawaited(_player.play());
    } catch (_) {
      if (currentKey == key) {
        error = 'No se pudo reproducir la canción.';
        currentKey = null;
      }
    }
    notifyListeners();
  }

  Future<void> seek(Duration to) => _player.seek(to);

  Future<void> pause() => _player.pause();

  Future<void> stop([String? key]) async {
    if (key != null && currentKey != key) return;
    currentKey = null;
    await _player.stop();
    notifyListeners();
  }
}

final songPlayer = SongPlayer.instance;
