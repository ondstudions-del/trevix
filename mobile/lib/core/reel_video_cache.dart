import 'dart:async';
import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Caché y precarga de videos de Reels: evita descargas duplicadas y no bloquea la reproducción.
final class ReelVideoCache {
  ReelVideoCache._();

  static final BaseCacheManager _cache = DefaultCacheManager();
  static final Map<String, Future<FileInfo>> _inflight = {};
  static const _maxConcurrent = 4;

  /// Archivo local listo para reproducir, si ya está en caché.
  static Future<File?> localFile(String url) async {
    if (url.isEmpty) return null;
    try {
      final hit = await _cache.getFileFromCache(url);
      if (hit != null && hit.validTill.isAfter(DateTime.now())) {
        return hit.file;
      }
    } catch (_) {}
    return null;
  }

  /// Descarga en segundo plano (una sola tarea por URL).
  static void prefetchVideo(String? url) {
    if (url == null || url.isEmpty) return;
    if (_inflight.containsKey(url)) return;
    if (_inflight.length >= _maxConcurrent) return;
    final job = _cache.downloadFile(url, key: url).whenComplete(() => _inflight.remove(url));
    _inflight[url] = job;
    unawaited(job);
  }

  static void prefetchPoster(String? url) {
    if (url == null || url.isEmpty) return;
    unawaited(_cache.downloadFile(url, key: url));
  }
}