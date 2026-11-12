import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:trevix_video/trevix_video.dart';

import 'i18n.dart';

/// Punto de la cara al que se ancla una pieza del efecto.
enum FaceAnchor { eyes, nose, mouth, top }

/// Pieza de un efecto: un dibujo de ancho [width] (en anchos de cara) y alto [width] × [aspect], centrado en su
/// [anchor] desplazado [dx] anchos y [dy] altos de cara (hacia la derecha y hacia el mentón de la cara).
class FacePart {
  const FacePart(this.anchor, {this.dx = 0, this.dy = 0, required this.width, required this.aspect, required this.paint});

  final FaceAnchor anchor;
  final double dx;
  final double dy;
  final double width;
  final double aspect;
  final void Function(Canvas canvas, Size size) paint;
}

/// Efecto de cara de la cámara de reels (como los de TikTok): sigue la cara en la vista previa y se graba en el video.
class FaceEffect {
  const FaceEffect(this.id, this.emoji, this.parts);

  final String id;
  final String emoji;
  final List<FacePart> parts;

  String get name => switch (id) {
        'glasses' => tr('Gafas de sol'),
        'cat' => tr('Gatito'),
        'bunny' => tr('Conejito'),
        'crown' => tr('Corona'),
        'hearts' => tr('Corazones'),
        'blush' => tr('Rubor'),
        'freckles' => tr('Pecas'),
        'mustache' => tr('Bigote'),
        _ => id,
      };
}

final List<FaceEffect> faceEffects = [
  const FaceEffect('glasses', '😎', [FacePart(FaceAnchor.eyes, width: 1.05, aspect: .38, paint: _glasses)]),
  const FaceEffect('cat', '🐱', [
    FacePart(FaceAnchor.top, dy: -.12, width: 1.25, aspect: .5, paint: _catEars),
    FacePart(FaceAnchor.nose, dy: .02, width: 1.0, aspect: .38, paint: _catNose),
  ]),
  const FaceEffect('bunny', '🐰', [
    FacePart(FaceAnchor.top, dy: -.4, width: .85, aspect: 1.0, paint: _bunnyEars),
    FacePart(FaceAnchor.nose, dy: .06, width: .42, aspect: .62, paint: _bunnyNose),
  ]),
  const FaceEffect('crown', '👑', [FacePart(FaceAnchor.top, dy: -.22, width: .85, aspect: .6, paint: _crown)]),
  const FaceEffect('hearts', '💕', [FacePart(FaceAnchor.top, dy: -.24, width: 1.5, aspect: .5, paint: _hearts)]),
  const FaceEffect('blush', '😊', [FacePart(FaceAnchor.nose, dy: -.02, width: 1.0, aspect: .32, paint: _blush)]),
  const FaceEffect('freckles', '✨', [FacePart(FaceAnchor.nose, dy: -.04, width: .78, aspect: .26, paint: _freckles)]),
  const FaceEffect('mustache', '🥸', [FacePart(FaceAnchor.mouth, dy: -.1, width: .62, aspect: .3, paint: _mustache)]),
];

FaceEffect? faceEffectById(String? id) => id == null ? null : faceEffects.where((e) => e.id == id).firstOrNull;

/// Cara detectada en píxeles de la imagen (ya derecha): centro, tamaño, giro (grados, antihorario) y puntos.
class FaceBox {
  const FaceBox(this.center, this.size, this.roll, {this.eyes, this.nose, this.mouth});

  final Offset center;
  final Size size;
  final double roll;
  final Offset? eyes;
  final Offset? nose;
  final Offset? mouth;

  /// [f] viene en fracciones de la imagen; [image] es su tamaño en píxeles.
  static FaceBox from(DetectedFace f, Size image) {
    Offset? px(Offset? p) => p == null ? null : Offset(p.dx * image.width, p.dy * image.height);
    final l = px(f.leftEye);
    final r = px(f.rightEye);
    var roll = 0.0;
    var eyes = px(f.eyes);
    if (l != null && r != null) {
      final a = l.dx <= r.dx ? l : r;
      final b = l.dx <= r.dx ? r : l;
      eyes = (a + b) / 2;
      roll = math.atan2(-(b.dy - a.dy), b.dx - a.dx) * 180 / math.pi;
    }
    final box = Rect.fromLTWH(f.box.left * image.width, f.box.top * image.height, f.box.width * image.width, f.box.height * image.height);
    return FaceBox(box.center, box.size, roll, eyes: eyes, nose: px(f.nose), mouth: px(f.mouth));
  }
}

/// La más grande de las caras encontradas.
DetectedFace? largestFace(List<DetectedFace> faces) {
  DetectedFace? best;
  for (final f in faces) {
    if (best == null || f.box.width * f.box.height > best.box.width * best.box.height) best = f;
  }
  return best;
}

/// Posición de una pieza en fracciones de la imagen: centro, ancho (fracción del ancho) y giro antihorario.
class PartPlacement {
  const PartPlacement(this.x, this.y, this.width, this.rotation);

  final double x;
  final double y;
  final double width;
  final double rotation;

  PartPlacement mirrored() => PartPlacement(1 - x, y, width, -rotation);

  PartPlacement blend(PartPlacement to, double k) => PartPlacement(
        x + (to.x - x) * k,
        y + (to.y - y) * k,
        width + (to.width - width) * k,
        rotation + (to.rotation - rotation) * k,
      );
}

PartPlacement placePart(FacePart part, FaceBox face, Size image) {
  final t = face.roll * math.pi / 180;
  final right = Offset(math.cos(t), -math.sin(t));
  final down = Offset(math.sin(t), math.cos(t));
  final h = face.size.height;
  final eyes = face.eyes ?? face.center + down * (-.1 * h);
  final base = switch (part.anchor) {
    FaceAnchor.eyes => eyes,
    FaceAnchor.nose => face.nose ?? eyes + down * (.26 * h),
    FaceAnchor.mouth => face.mouth ?? eyes + down * (.42 * h),
    FaceAnchor.top => eyes + down * (-.45 * h),
  };
  final c = base + right * (part.dx * face.size.width) + down * (part.dy * h);
  return PartPlacement(c.dx / image.width, c.dy / image.height, part.width * face.size.width / image.width, face.roll);
}

/// Fotograma de la cámara en gris, pequeño (≈[target] px de ancho, par) y derecho como se ve en pantalla, para el
/// detector de caras. En Android llega del sensor (NV21, girado [CameraDescription.sensorOrientation] y sin espejo);
/// en iOS llega ya derecho y en espejo con la cámara frontal (BGRA), igual que la vista previa.
(Uint8List, int, int)? grayFrame(CameraImage image, CameraDescription camera, {int target = 240}) {
  if (image.planes.isEmpty) return null;
  final plane = image.planes.first;
  final bytes = plane.bytes;
  final row = plane.bytesPerRow;
  final srcW = image.width;
  final srcH = image.height;
  final bgra = Platform.isIOS;
  final rotation = bgra ? 0 : camera.sensorOrientation % 360;
  final sideways = rotation == 90 || rotation == 270;
  final upW = sideways ? srcH : srcW;
  final upH = sideways ? srcW : srcH;
  final step = math.max(1, upW ~/ target);
  final w = (upW ~/ step) & ~1;
  final h = upH ~/ step;
  if (w <= 0 || h <= 0) return null;
  final out = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    final uy = y * step;
    for (var x = 0; x < w; x++) {
      final ux = x * step;
      final int sx, sy;
      switch (rotation) {
        case 90:
          sx = uy;
          sy = srcH - 1 - ux;
        case 180:
          sx = srcW - 1 - ux;
          sy = srcH - 1 - uy;
        case 270:
          sx = srcW - 1 - uy;
          sy = ux;
        default:
          sx = ux;
          sy = uy;
      }
      if (bgra) {
        final i = sy * row + sx * 4;
        if (i + 2 >= bytes.length) continue;
        out[y * w + x] = (bytes[i] * 29 + bytes[i + 1] * 150 + bytes[i + 2] * 77) >> 8;
      } else {
        final i = sy * row + sx;
        if (i >= bytes.length) continue;
        out[y * w + x] = bytes[i];
      }
    }
  }
  return (out, w, h);
}

/// La vista previa de Android sale en espejo con la cámara frontal pero sus fotogramas no.
bool previewMirrored(CameraDescription camera) => Platform.isAndroid && camera.lensDirection == CameraLensDirection.front;

/// Dibuja las piezas del efecto en la vista previa de la cámara.
class FaceEffectPainter extends CustomPainter {
  FaceEffectPainter(this.effect, this.placements);

  final FaceEffect effect;
  final List<PartPlacement?> placements;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < effect.parts.length && i < placements.length; i++) {
      final p = placements[i];
      if (p == null) continue;
      final part = effect.parts[i];
      final w = p.width * size.width;
      final box = Size(w, w * part.aspect);
      canvas.save();
      canvas.translate(p.x * size.width, p.y * size.height);
      canvas.rotate(-p.rotation * math.pi / 180);
      canvas.translate(-box.width / 2, -box.height / 2);
      part.paint(canvas, box);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(FaceEffectPainter old) => true;
}

/// PNG con transparencia de una pieza (para grabarla en el video).
Future<String> facePartPng(FacePart part, String dir, String name, {double width = 512}) async {
  final size = Size(width, (width * part.aspect).roundToDouble());
  final recorder = ui.PictureRecorder();
  part.paint(Canvas(recorder), size);
  final image = await recorder.endRecording().toImage(size.width.round(), size.height.round());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  final file = File('$dir/$name.png');
  await file.writeAsBytes(data!.buffer.asUint8List());
  return file.path;
}

/// Sigue la cara en los fotogramas del video grabado y devuelve las superposiciones de cada pieza, ya en fracciones
/// del video final (recortado al centro a [aspect] si se indica). [onProgress] va de 0 a 1.
Future<List<VideoOverlay>> faceOverlays(
  FaceEffect effect,
  String video,
  String dir, {
  required int durationMs,
  double? aspect,
  void Function(double)? onProgress,
  bool Function()? cancelled,
}) async {
  final interval = durationMs <= 20000 ? 200 : (durationMs <= 40000 ? 250 : 333);
  final frames = await TrevixVideo.frames(video, dir, intervalMs: interval, maxSide: 480);
  final keys = List.generate(effect.parts.length, (_) => <OverlayKey>[]);
  final last = List<PartPlacement?>.filled(effect.parts.length, null);
  var lastSeen = -100000;
  for (var i = 0; i < frames.length; i++) {
    if (cancelled?.call() ?? false) break;
    final f = frames[i];
    DetectedFace? face;
    try {
      face = largestFace(await TrevixVideo.faces(path: f.path));
    } catch (_) {
      face = null;
    }
    File(f.path).delete().ignore();
    final size = Size(f.width.toDouble(), f.height.toDouble());
    for (var p = 0; p < effect.parts.length; p++) {
      if (face != null) {
        var placed = _crop(placePart(effect.parts[p], FaceBox.from(face, size), size), size, aspect);
        final prev = last[p];
        if (prev != null && f.ms - lastSeen <= 600) placed = prev.blend(placed, .6);
        last[p] = placed;
        keys[p].add(OverlayKey(f.ms, x: placed.x, y: placed.y, width: placed.width, rotation: placed.rotation));
      } else if (last[p] != null) {
        final prev = last[p]!;
        // Sin cara un momento: la pieza se queda; si tarda en volver, desaparece.
        final alpha = f.ms - lastSeen <= 600 ? 1.0 : 0.0;
        keys[p].add(OverlayKey(f.ms, x: prev.x, y: prev.y, width: prev.width, rotation: prev.rotation, alpha: alpha));
      }
    }
    if (face != null) lastSeen = f.ms;
    onProgress?.call((i + 1) / frames.length);
  }
  final out = <VideoOverlay>[];
  for (var p = 0; p < effect.parts.length; p++) {
    if (keys[p].isEmpty) continue;
    final first = keys[p].first;
    // Antes de encontrar la cara por primera vez no se dibuja.
    if (first.ms > 0) {
      keys[p].insert(0, OverlayKey(first.ms - 1, x: first.x, y: first.y, width: first.width, rotation: first.rotation, alpha: 0));
    }
    out.add(VideoOverlay(await facePartPng(effect.parts[p], dir, 'part_${effect.id}_$p'), keys[p]));
  }
  return out;
}

/// Fracciones de la imagen completa → fracciones del video recortado al centro a [aspect].
PartPlacement _crop(PartPlacement p, Size image, double? aspect) {
  if (aspect == null) return p;
  final src = image.width / image.height;
  if (src > aspect) {
    final fx = aspect / src;
    return PartPlacement((p.x - (1 - fx) / 2) / fx, p.y, p.width / fx, p.rotation);
  }
  final fy = src / aspect;
  return PartPlacement(p.x, (p.y - (1 - fy) / 2) / fy, p.width, p.rotation);
}

// ---------- Dibujos ----------

void _glasses(Canvas c, Size s) {
  final w = s.width, h = s.height;
  final lens = Paint()
    ..shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xF0111827), Color(0xD84C1D95)],
    ).createShader(Offset.zero & s);
  final frame = Paint()
    ..color = const Color(0xFF0A0A0A)
    ..style = PaintingStyle.stroke
    ..strokeWidth = h * .09
    ..strokeCap = StrokeCap.round;
  final left = RRect.fromRectAndRadius(Rect.fromLTWH(w * .06, h * .12, w * .38, h * .76), Radius.circular(h * .32));
  final right = RRect.fromRectAndRadius(Rect.fromLTWH(w * .56, h * .12, w * .38, h * .76), Radius.circular(h * .32));
  c.drawRRect(left, lens);
  c.drawRRect(right, lens);
  c.drawRRect(left, frame);
  c.drawRRect(right, frame);
  c.drawLine(Offset(w * .44, h * .34), Offset(w * .56, h * .34), frame);
  c.drawLine(Offset(w * .06, h * .3), Offset(w * .01, h * .24), frame);
  c.drawLine(Offset(w * .94, h * .3), Offset(w * .99, h * .24), frame);
  final shine = Paint()
    ..color = const Color(0x88FFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = h * .06
    ..strokeCap = StrokeCap.round;
  c.drawLine(Offset(w * .13, h * .36), Offset(w * .2, h * .24), shine);
  c.drawLine(Offset(w * .63, h * .36), Offset(w * .7, h * .24), shine);
}

void _catEars(Canvas c, Size s) {
  final w = s.width, h = s.height;
  final outer = Paint()..color = const Color(0xFF3F3F46);
  final inner = Paint()..color = const Color(0xFFF9A8D4);
  for (final side in [-1.0, 1.0]) {
    final cx = w * (.5 + side * .32);
    c.drawPath(
      Path()
        ..moveTo(cx - w * .17, h)
        ..quadraticBezierTo(cx + side * w * .02, -h * .1, cx + side * w * .04, h * .02)
        ..quadraticBezierTo(cx + side * w * .1, h * .4, cx + w * .17, h)
        ..close(),
      outer,
    );
    c.drawPath(
      Path()
        ..moveTo(cx - w * .09, h)
        ..lineTo(cx + side * w * .03, h * .3)
        ..lineTo(cx + w * .09, h)
        ..close(),
      inner,
    );
  }
}

void _catNose(Canvas c, Size s) {
  final w = s.width, h = s.height;
  final whisker = Paint()
    ..color = const Color(0xFF27272A)
    ..style = PaintingStyle.stroke
    ..strokeWidth = h * .035
    ..strokeCap = StrokeCap.round;
  for (final side in [-1.0, 1.0]) {
    final x0 = w * (.5 + side * .12);
    c.drawLine(Offset(x0, h * .38), Offset(w * (.5 + side * .48), h * .16), whisker);
    c.drawLine(Offset(x0, h * .5), Offset(w * (.5 + side * .5), h * .5), whisker);
    c.drawLine(Offset(x0, h * .62), Offset(w * (.5 + side * .48), h * .84), whisker);
  }
  final nose = Path()
    ..moveTo(w * .43, h * .2)
    ..quadraticBezierTo(w * .5, h * .14, w * .57, h * .2)
    ..quadraticBezierTo(w * .56, h * .3, w * .5, h * .42)
    ..quadraticBezierTo(w * .44, h * .3, w * .43, h * .2)
    ..close();
  c.drawPath(nose, Paint()..color = const Color(0xFFF472B6));
  c.drawPath(
    nose,
    Paint()
      ..color = const Color(0xFF831843)
      ..style = PaintingStyle.stroke
      ..strokeWidth = h * .025,
  );
}

void _bunnyEars(Canvas c, Size s) {
  final w = s.width, h = s.height;
  for (final side in [-1.0, 1.0]) {
    c.save();
    c.translate(w * (.5 + side * .2), h * .98);
    c.rotate(side * .2);
    c.drawOval(Rect.fromCenter(center: Offset(0, -h * .45), width: w * .27, height: h * .88), Paint()..color = const Color(0xFFF5F5F4));
    c.drawOval(Rect.fromCenter(center: Offset(0, -h * .43), width: w * .13, height: h * .68), Paint()..color = const Color(0xFFFBCFE8));
    c.restore();
  }
}

void _bunnyNose(Canvas c, Size s) {
  final w = s.width, h = s.height;
  final teeth = Paint()..color = Colors.white;
  final line = Paint()
    ..color = const Color(0xFFD4D4D8)
    ..style = PaintingStyle.stroke
    ..strokeWidth = h * .03;
  final t1 = RRect.fromRectAndCorners(Rect.fromLTWH(w * .3, h * .45, w * .19, h * .45), bottomLeft: Radius.circular(w * .06), bottomRight: Radius.circular(w * .06));
  final t2 = RRect.fromRectAndCorners(Rect.fromLTWH(w * .51, h * .45, w * .19, h * .45), bottomLeft: Radius.circular(w * .06), bottomRight: Radius.circular(w * .06));
  c.drawRRect(t1, teeth);
  c.drawRRect(t2, teeth);
  c.drawRRect(t1, line);
  c.drawRRect(t2, line);
  c.drawOval(Rect.fromLTWH(w * .3, h * .05, w * .4, h * .36), Paint()..color = const Color(0xFFF472B6));
}

void _crown(Canvas c, Size s) {
  final w = s.width, h = s.height;
  final top = h * .12;
  final crown = Path()
    ..moveTo(w * .08, h * .96)
    ..lineTo(w * .04, top + h * .18)
    ..lineTo(w * .28, h * .55)
    ..lineTo(w * .5, top)
    ..lineTo(w * .72, h * .55)
    ..lineTo(w * .96, top + h * .18)
    ..lineTo(w * .92, h * .96)
    ..close();
  c.drawPath(
    crown,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFDE68A), Color(0xFFF59E0B)],
      ).createShader(Offset.zero & s),
  );
  c.drawPath(
    crown,
    Paint()
      ..color = const Color(0xFFB45309)
      ..style = PaintingStyle.stroke
      ..strokeWidth = h * .04
      ..strokeJoin = StrokeJoin.round,
  );
  c.drawRect(Rect.fromLTWH(w * .08, h * .76, w * .84, h * .08), Paint()..color = const Color(0x66B45309));
  final r = h * .07;
  c.drawCircle(Offset(w * .5, top), r, Paint()..color = const Color(0xFFF43F5E));
  c.drawCircle(Offset(w * .04, top + h * .18), r * .8, Paint()..color = const Color(0xFF3B82F6));
  c.drawCircle(Offset(w * .96, top + h * .18), r * .8, Paint()..color = const Color(0xFF3B82F6));
  c.drawCircle(Offset(w * .5, h * .8), r, Paint()..color = const Color(0xFF10B981));
  c.drawCircle(Offset(w * .3, h * .8), r * .7, Paint()..color = const Color(0xFFF43F5E));
  c.drawCircle(Offset(w * .7, h * .8), r * .7, Paint()..color = const Color(0xFFF43F5E));
}

Path _heartPath(Offset c, double s) => Path()
  ..moveTo(c.dx, c.dy + s * .45)
  ..cubicTo(c.dx - s * 1.0, c.dy - s * .15, c.dx - s * .45, c.dy - s * .85, c.dx, c.dy - s * .3)
  ..cubicTo(c.dx + s * .45, c.dy - s * .85, c.dx + s * 1.0, c.dy - s * .15, c.dx, c.dy + s * .45)
  ..close();

void _hearts(Canvas c, Size s) {
  final w = s.width, h = s.height;
  const spots = [(.1, .66, .1), (.3, .36, .13), (.5, .26, .15), (.7, .36, .13), (.9, .66, .1)];
  const colors = [Color(0xFFF43F5E), Color(0xFFEC4899), Color(0xFFF43F5E), Color(0xFFEC4899), Color(0xFFF43F5E)];
  for (var i = 0; i < spots.length; i++) {
    final (x, y, size) = spots[i];
    final path = _heartPath(Offset(w * x, h * y), w * size * .5);
    c.drawPath(path, Paint()..color = colors[i]);
    c.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * .008,
    );
  }
}

void _blush(Canvas c, Size s) {
  final w = s.width, h = s.height;
  for (final x in [.17, .83]) {
    final rect = Rect.fromCenter(center: Offset(w * x, h * .5), width: w * .32, height: h * .9);
    c.drawOval(
      rect,
      Paint()
        ..shader = const RadialGradient(colors: [Color(0x99FB7185), Color(0x00FB7185)]).createShader(rect),
    );
  }
}

void _freckles(Canvas c, Size s) {
  final w = s.width, h = s.height;
  final dot = Paint()..color = const Color(0x99784421);
  const spots = [(.08, .4), (.15, .7), (.2, .3), (.26, .58), (.32, .38), (.12, .2), (.29, .82)];
  for (final (x, y) in spots) {
    c.drawCircle(Offset(w * x, h * y), h * .055, dot);
    c.drawCircle(Offset(w * (1 - x), h * (y + .04).clamp(0, 1)), h * .05, dot);
  }
}

void _mustache(Canvas c, Size s) {
  final w = s.width, h = s.height;
  final paint = Paint()..color = const Color(0xFF292524);
  for (final side in [-1.0, 1.0]) {
    double x(double f) => w * (.5 + side * f);
    c.drawPath(
      Path()
        ..moveTo(x(0), h * .3)
        ..cubicTo(x(.15), h * -.02, x(.38), h * .05, x(.48), h * .55)
        ..cubicTo(x(.4), h * .4, x(.3), h * .5, x(.22), h * .72)
        ..cubicTo(x(.14), h * .9, x(.04), h * .8, x(0), h * .62)
        ..close(),
      paint,
    );
  }
}
