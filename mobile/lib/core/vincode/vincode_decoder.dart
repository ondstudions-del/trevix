import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import 'vincode_codec.dart';

/// Radio del anillo de datos (coincide con [VincodePainter] y vincode.js).
const _dataRadiusFactors = <double>[0.455, 0.448, 0.462, 0.435];

List<int> _bitsAtRadius(
  int w,
  int h,
  double radiusFactor,
  int Function(int x, int y) rgbAt,
) {
  final cx = w / 2;
  final cy = h / 2;
  final R = math.min(w, h) * radiusFactor;
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
        final rgb = rgbAt(x, yPix);
        final r = (rgb >> 16) & 0xff;
        final g = (rgb >> 8) & 0xff;
        final b = rgb & 0xff;
        cyan += g + b - r;
        violet += r + b - g;
        n++;
      }
    }
    bits.add(n == 0 ? 0 : (cyan / n > violet / n ? 1 : 0));
  }
  return bits;
}

String? _decodeWithRgbAt(int w, int h, int Function(int x, int y) rgbAt) {
  for (final factor in _dataRadiusFactors) {
    final code = bitsToCode(_bitsAtRadius(w, h, factor, rgbAt));
    if (code != null) return code;
  }
  return null;
}

/// Muestrea el anillo VINCODE en un frame de cámara.
Future<String?> decodeVincodeFromCameraImage(CameraImage image) async {
  try {
    final w = image.width;
    final h = image.height;
    if (w < 64 || h < 64) return null;

    final yPlane = image.planes.first;
    final y = yPlane.bytes;
    final yRow = yPlane.bytesPerRow;

  // BGRA (iOS y algunos Android): un solo plano RGBA/BGRA.
    if (image.planes.length == 1) {
      final bpp = yPlane.bytesPerPixel ?? 4;
      if (bpp >= 3) {
        return _decodeWithRgbAt(w, h, (x, yPix) {
          final idx = yPix * yRow + x * bpp;
          if (idx + 2 >= y.length) return 0;
          int r;
          int g;
          int b;
          if (bpp == 4) {
            // BGRA en iOS.
            b = y[idx];
            g = y[idx + 1];
            r = y[idx + 2];
          } else {
            r = y[idx];
            g = y[idx + 1];
            b = y[idx + 2];
          }
          return (r << 16) | (g << 8) | b;
        });
      }
    }

    // NV21 / NV12: Y + chroma interleaved.
    if (image.planes.length == 2) {
      final uv = image.planes[1].bytes;
      final uvRow = image.planes[1].bytesPerRow;
      return _decodeWithRgbAt(w, h, (x, yPix) {
        final yi = yPix * yRow + x;
        if (yi < 0 || yi >= y.length) return 0;
        final yy = y[yi];
        final uvi = (yPix ~/ 2) * uvRow + (x ~/ 2) * 2;
        if (uvi + 1 >= uv.length) return (yy << 16) | (yy << 8) | yy;
        final v = uv[uvi] - 128;
        final u = uv[uvi + 1] - 128;
        final r = (yy + 1.402 * v).round().clamp(0, 255);
        final g = (yy - 0.344 * u - 0.714 * v).round().clamp(0, 255);
        final b = (yy + 1.772 * u).round().clamp(0, 255);
        return (r << 16) | (g << 8) | b;
      });
    }

    // YUV420 planar (tres planos).
    if (image.planes.length >= 3) {
      final uBytes = image.planes[1].bytes;
      final vBytes = image.planes[2].bytes;
      final uRow = image.planes[1].bytesPerRow;
      final vRow = image.planes[2].bytesPerRow;
      final uPixel = image.planes[1].bytesPerPixel ?? 1;
      final vPixel = image.planes[2].bytesPerPixel ?? 1;
      return _decodeWithRgbAt(w, h, (x, yPix) {
        final yi = yPix * yRow + x;
        if (yi < 0 || yi >= y.length) return 0;
        final yy = y[yi];
        final uxi = (yPix ~/ 2) * uRow + (x ~/ 2) * uPixel;
        final vxi = (yPix ~/ 2) * vRow + (x ~/ 2) * vPixel;
        if (uxi >= uBytes.length || vxi >= vBytes.length) {
          return (yy << 16) | (yy << 8) | yy;
        }
        final u = uBytes[uxi] - 128;
        final v = vBytes[vxi] - 128;
        final r = (yy + 1.402 * v).round().clamp(0, 255);
        final g = (yy - 0.344 * u - 0.714 * v).round().clamp(0, 255);
        final b = (yy + 1.772 * u).round().clamp(0, 255);
        return (r << 16) | (g << 8) | b;
      });
    }

    return null;
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
  return _decodeWithRgbAt(w, h, (x, yPix) {
    final o = (yPix * w + x) * 4;
    if (o + 2 >= data.length) return 0;
    final r = data[o];
    final g = data[o + 1];
    final b = data[o + 2];
    return (r << 16) | (g << 8) | b;
  });
}