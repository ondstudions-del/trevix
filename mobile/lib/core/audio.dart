import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../models/models.dart';
import 'i18n.dart';

/// Canciones guardadas en la caché del teléfono: la primera vez suenan desde internet mientras se descargan aparte;
/// las siguientes, desde el archivo (empiezan al instante y no se cortan con mala señal). Se borran las más antiguas
/// al pasar de [_maxBytes].
class SongCache {
  SongCache._();

  static const _maxBytes = 200 * 1024 * 1024;
  static const _maxPrefetch = 2;
  static Directory? _dir;
  static final Map<String, Future<File?>> _inflight = {};
  static final http.Client _client = http.Client();

  static Future<Directory> _folder() async =>
      _dir ??= await Directory('${(await getApplicationCacheDirectory()).path}/songs').create(recursive: true);

  /// Nombre estable del archivo: FNV-1a (32 bits) y largo de la dirección, y su extensión.
  static String _name(String url) {
    var h = 0x811c9dc5;
    for (final unit in url.codeUnits) {
      h = ((h ^ unit) * 0x01000193) & 0xFFFFFFFF;
    }
    final path = Uri.tryParse(url)?.path ?? '';
    final dot = path.lastIndexOf('.');
    final ext = dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
    return '${h.toRadixString(16)}_${url.length}.${RegExp(r'^[a-z0-9]{2,4}$').hasMatch(ext) ? ext : 'audio'}';
  }

  static bool _remote(String url) => url.startsWith('https://') || url.startsWith('http://');

  /// El archivo ya descargado de [url], si está.
  static Future<File?> cached(String url) async {
    if (!_remote(url)) return null;
    try {
      final file = File('${(await _folder()).path}/${_name(url)}');
      if (await file.exists()) {
        file.setLastModified(DateTime.now()).ignore();
        return file;
      }
    } catch (_) {}
    return null;
  }

  /// Descarga [url] a la caché (una sola vez aunque se pida varias). Con [prefetch], solo si hay pocas en curso.
  static Future<File?> fetch(String url, {bool prefetch = false}) {
    if (!_remote(url)) return Future.value(null);
    final running = _inflight[url];
    if (running != null) return running;
    if (prefetch && _inflight.length >= _maxPrefetch) return Future.value(null);
    final job = _download(url).whenComplete(() => _inflight.remove(url));
    _inflight[url] = job;
    return job;
  }

  static Future<File?> _download(String url) async {
    final done = await cached(url);
    if (done != null) return done;
    final folder = await _folder();
    final target = File('${folder.path}/${_name(url)}');
    final part = File('${target.path}.part');
    try {
      final res = await _client.send(http.Request('GET', Uri.parse(url))).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) return null;
      final sink = part.openWrite();
      try {
        await res.stream.timeout(const Duration(seconds: 30)).pipe(sink);
      } catch (_) {
        await sink.close().catchError((_) {});
        rethrow;
      }
      final expected = res.contentLength;
      if (expected != null && await part.length() != expected) throw const FileSystemException('incompleta');
      await part.rename(target.path);
      unawaited(_trim(folder));
      return target;
    } catch (_) {
      part.delete().ignore();
      return null;
    }
  }

  static Future<void> _trim(Directory folder) async {
    try {
      final files = await folder.list().where((e) => e is File && !e.path.endsWith('.part')).cast<File>().toList();
      final stats = [for (final f in files) (f, await f.stat())];
      var total = stats.fold<int>(0, (sum, e) => sum + e.$2.size);
      if (total <= _maxBytes) return;
      stats.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
      for (final (file, stat) in stats) {
        if (total <= _maxBytes * .8) break;
        await file.delete().catchError((_) => file);
        total -= stat.size;
      }
    } catch (_) {}
  }
}

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

  /// Canción y fragmento que tiene cargados el reproductor: si se vuelve a pedir, solo se busca la posición.
  String? _loaded;

  /// Carga [song] (desde la caché si ya se descargó; si no, desde internet mientras se descarga aparte) y la deja
  /// en [at]. Si es la misma canción y fragmento que ya está cargada, no se vuelve a cargar.
  Future<void> _load(Song song, bool clip, {Duration at = Duration.zero}) async {
    final clipped = clip && song.hasClip;
    final signature = '${song.audioUrl}|${clipped ? '${song.clipStart}-${song.clipEnd}' : 'full'}';
    if (_loaded == signature && _player.processingState != ProcessingState.idle) {
      await _player.seek(at);
      return;
    }
    _loaded = null;
    final file = await SongCache.cached(song.audioUrl);
    if (file == null) unawaited(SongCache.fetch(song.audioUrl));
    Future<void> set(UriAudioSource base) => _player.setAudioSource(
          clipped ? ClippingAudioSource(child: base, start: Duration(seconds: song.clipStart!), end: Duration(seconds: song.clipEnd!)) : base,
          initialPosition: at,
        );
    if (file == null) {
      await set(AudioSource.uri(Uri.parse(song.audioUrl)));
    } else {
      try {
        await set(AudioSource.file(file.path));
      } catch (_) {
        // Archivo de la caché dañado: se borra y suena desde internet.
        await file.delete().catchError((_) => file);
        await set(AudioSource.uri(Uri.parse(song.audioUrl)));
      }
    }
    _loaded = signature;
  }

  /// Descarga por adelantado la canción que está por sonar (publicación a la vista, siguiente reel o historia).
  void prefetch(Song? song) {
    if (song == null || !song.available || song.audioUrl.isEmpty) return;
    unawaited(SongCache.fetch(song.audioUrl, prefetch: true));
  }

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
        await _load(song, clip);
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
        await _load(song, clip, at: at);
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
        _loaded = null;
        await _player.setAudioSource(AudioSource.asset(asset));
        _loaded = 'asset:$asset';
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
