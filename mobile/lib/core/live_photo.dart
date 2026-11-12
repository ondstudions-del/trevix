import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Fotos en movimiento de Android (Google Motion Photo, Samsung y similares): el video MP4 va pegado al final del
/// JPEG. Se busca su caja «ftyp» y se guarda desde ahí como un .mp4 aparte. En iPhone las Live Photos traen su
/// video como recurso propio (photo_manager), así que esto solo se usa en Android.
class MotionPhoto {
  MotionPhoto._();

  /// Marcas de MP4/QuickTime que usan las cámaras de Android para el video de la foto en movimiento.
  static const _brands = {'isom', 'iso2', 'iso4', 'iso5', 'iso6', 'mp41', 'mp42', 'avc1', 'hvc1', 'MSNV', 'qt  ', '3gp4', '3gp5'};

  /// Ruta del .mp4 extraído o null si la foto no tiene video.
  static Future<String?> extract(String jpegPath) async {
    try {
      final file = File(jpegPath);
      final length = await file.length();
      if (length < 64 * 1024 || length > 80 * 1024 * 1024) return null;
      final bytes = await file.readAsBytes();
      final start = await compute(_findVideo, bytes);
      if (start == null) return null;
      final dir = await getTemporaryDirectory();
      final out = File('${dir.path}/live_${DateTime.now().microsecondsSinceEpoch}.mp4');
      await out.writeAsBytes(Uint8List.sublistView(bytes, start), flush: true);
      return out.path;
    } catch (_) {
      return null;
    }
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
