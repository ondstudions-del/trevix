import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import 'vincode_codec.dart';

/// Muestrea el anillo VINCODE en un frame de cámara (YUV → luminancia aproximada).
Future<String?> decodeVincodeFromCameraImage(CameraImage image) async {
  try {
    final w = image.width;
    final h = image.height;
    if (w < 64 || h < 64) return null;

    // Usar plano Y (luminancia) + muestreo de color aproximado desde UV si hay.
    final yPlane = image.planes.first;
    final y = yPlane.bytes;
    final yRow = yPlane.bytesPerRow;

    Uint8List? uBytes;
    Uint8List? vBytes;
    var uvRow = 0;
    var uvPixel = 1;
    if (image.planes.length >= 3) {
      uBytes = image.planes[1].bytes;
      vBytes = image.planes[2].bytes;
      uvRow = image.planes[1].bytesPerRow;
      uvPixel = image.planes[1].bytesPerPixel ?? 1;
    }

    final cx = w / 2;
    final cy = h / 2;
    final R = math.min(w, h) * 0.42;
    final bits = <int>[];

    for (var i = 0; i < vincodeModules; i++) {
      final a = i / vincodeModules * math.pi * 2 - math.pi / 2;
      var cyan = 0.0;
      var violet = 0.0;
      var n = 0;
      for (var dr = -3; dr <= 3; dr++) {
        for (var da = -0.012; da <= 0.012; da += 0.006) {
          final x = (cx + math.cos(a + da) * (R + dr)).round();
          final yPix = (cy + math.sin(a + da) * (R + dr)).round();
          if (x < 0 || yPix < 0 || x >= w || yPix >= h) continue;
          final yi = yPix * yRow + x;
          if (yi < 0 || yi >= y.length) continue;
          final yy = y[yi];
          var r = yy.toDouble();
          var g = yy.toDouble();
          var b = yy.toDouble();
          if (uBytes != null && vBytes != null) {
            final uxi = (yPix ~/ 2) * uvRow + (x ~/ 2) * uvPixel;
            if (uxi >= 0 && uxi < uBytes.length && uxi < vBytes.length) {
              final u = uBytes[uxi] - 128;
              final v = vBytes[uxi] - 128;
              // BT.601 aproximado
              r = (yy + 1.402 * v).clamp(0, 255);
              g = (yy - 0.344 * u - 0.714 * v).clamp(0, 255);
              b = (yy + 1.772 * u).clamp(0, 255);
            }
          }
          cyan += g + b - r;
          violet += r + b - g;
          n++;
        }
      }
      bits.add(n == 0 ? 0 : (cyan / n > violet / n ? 1 : 0));
    }
    return bitsToCode(bits);
  } catch (e, st) {
    debugPrint('VINCODE decode: $e\n$st');
    return null;
  }
}

/// Decodifica desde un [ui.Image] (p. ej. captura web/test).
Future<String?> decodeVincodeFromUiImage(ui.Image image) async {
  final bd = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (bd == null) return null;
  final w = image.width;
  final h = image.height;
  final data = bd.buffer.asUint8List();
  final cx = w / 2;
  final cy = h / 2;
  final R = math.min(w, h) * 0.42;
  final bits = <int>[];
  for (var i = 0; i < vincodeModules; i++) {
    final a = i / vincodeModules * math.pi * 2 - math.pi / 2;
    var cyan = 0.0;
    var violet = 0.0;
    var n = 0;
    for (var dr = -2; dr <= 2; dr++) {
      for (var da = -0.01; da <= 0.01; da += 0.005) {
        final x = (cx + math.cos(a + da) * (R + dr)).round();
        final y = (cy + math.sin(a + da) * (R + dr)).round();
        if (x < 0 || y < 0 || x >= w || y >= h) continue;
        final o = (y * w + x) * 4;
        final r = data[o].toDouble();
        final g = data[o + 1].toDouble();
        final b = data[o + 2].toDouble();
        cyan += g + b - r;
        violet += r + b - g;
        n++;
      }
    }
    bits.add(n == 0 ? 0 : (cyan / n > violet / n ? 1 : 0));
  }
  return bitsToCode(bits);
}
