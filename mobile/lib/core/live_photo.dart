import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Fotos en movimiento de Android (Google Motion Photo, Samsung y similares): el video MP4 va pegado al final del
/// JPEG. Se busca su caja «ftyp» y se guarda desde ahí como un .mp4 aparte. En iPhone las Live Photos traen su
/// video como recurso propio (photo_manager), así que esto solo se usa en Android.
class MotionPhoto {
  MotionPhoto._();

  /// Marcas de MP4/QuickTime que usan las cámaras de Android para el video de la foto en movimiento.
  static const _brands = {'isom', 'iso2', 'iso4', 'iso5', 'iso6', 'mp41', 'mp42', 'avc1', 'hvc1', 'MSNV', 'qt  ', '3gp4', '3gp5'};

  /// Comprueba si el JPEG trae video sin leerlo entero (evita cierres por falta de memoria).
  static Future<bool> likely(String jpegPath) async {
    try {
      final file = File(jpegPath);
      final length = await file.length();
      if (length < 64 * 1024 || length > 80 * 1024 * 1024) return false;
      final start = await _locateMp4Start(file, length);
      return start != null;
    } catch (_) {
      return false;
    }
  }

  /// Ruta del .mp4 extraído o null si la foto no tiene video.
  static Future<String?> extract(String jpegPath) async {
    try {
      final file = File(jpegPath);
      final length = await file.length();
      if (length < 64 * 1024 || length > 80 * 1024 * 1024) return null;
      final start = await _locateMp4Start(file, length);
      if (start == null) return null;
      final dir = await getTemporaryDirectory();
      final out = File('${dir.path}/live_${DateTime.now().microsecondsSinceEpoch}.mp4');
      final sink = out.openWrite();
      await for (final chunk in file.openRead(start)) {
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
      if (await out.length() < 20 * 1024) {
        await out.delete();
        return null;
      }
      return out.path;
    } catch (_) {
      return null;
    }
  }

  static Future<int?> _locateMp4Start(File file, int length) async {
    if (length < 64 * 1024) return null;
    if (length <= 8 * 1024 * 1024) {
      final bytes = await file.readAsBytes();
      return compute(_findVideo, bytes);
    }
    const tailBytes = 4 * 1024 * 1024;
    final from = math.max(0, length - tailBytes);
    final tail = await _readRange(file, from, length);
    if (tail == null || tail.length < 32) return null;
    final inTail = await compute(_findVideoBox, tail);
    if (inTail == null) return null;
    return from + inTail;
  }

  static Future<Uint8List?> _readRange(File file, int start, int end) async {
    try {
      final out = <int>[];
      await for (final chunk in file.openRead(start, end)) {
        out.addAll(chunk);
      }
      return Uint8List.fromList(out);
    } catch (_) {
      return null;
    }
  }

  static int? _findVideoBox(Uint8List b) {
    if (b.length < 32) return null;
    for (var i = 4; i < b.length - 12; i++) {
      if (b[i] != 0x66 || b[i + 1] != 0x74 || b[i + 2] != 0x79 || b[i + 3] != 0x70) continue;
      final size = (b[i - 4] << 24) | (b[i - 3] << 16) | (b[i - 2] << 8) | b[i - 1];
      if (size < 8 || size > 128) continue;
      final brand = String.fromCharCodes(b.sublist(i + 4, i + 8));
      if (!_brands.contains(brand)) continue;
      if (b.length - (i - 4) < 20 * 1024) return null;
      return i - 4;
    }
    return null;
  }

  /// Desplazamiento donde empieza el MP4 (4 bytes antes de «ftyp», donde está el tamaño de la caja).
  static int? _findVideo(Uint8List b) {
    // El JPEG empieza por FF D8; si no, no es una foto en movimiento.
    if (b.length < 16 || b[0] != 0xFF || b[1] != 0xD8) return null;
    for (var i = 4; i < b.length - 12; i++) {
      if (b[i] != 0x66 || b[i + 1] != 0x74 || b[i + 2] != 0x79 || b[i + 3] != 0x70) continue;
      final size = (b[i - 4] << 24) | (b[i - 3] << 16) | (b[i - 2] << 8) | b[i - 1];
      if (size < 8 || size > 128) continue;
      final brand = String.fromCharCodes(b.sublist(i + 4, i + 8));
      if (!_brands.contains(brand)) continue;
      // Un video de verdad ocupa más que unos pocos kilobytes.
      if (b.length - (i - 4) < 20 * 1024) return null;
      return i - 4;
    }
    return null;
  }
}
