import 'package:flutter/services.dart';

/// Cara encontrada por el sistema (Vision en iOS, FaceDetector en Android), en fracciones de la imagen desde la
/// esquina superior izquierda. Android solo da el punto entre los ojos; iOS también cada ojo, la nariz y la boca.
class DetectedFace {
  const DetectedFace(this.box, {this.eyes, this.leftEye, this.rightEye, this.nose, this.mouth});

  final Rect box;
  final Offset? eyes;
  final Offset? leftEye;
  final Offset? rightEye;
  final Offset? nose;
  final Offset? mouth;

  static DetectedFace fromMap(Map<Object?, Object?> m) {
    double? n(String k) => (m[k] as num?)?.toDouble();
    Offset? at(String x, String y) => n(x) == null || n(y) == null ? null : Offset(n(x)!, n(y)!);
    return DetectedFace(
      Rect.fromLTWH(n('x') ?? 0, n('y') ?? 0, n('w') ?? 0, n('h') ?? 0),
      eyes: at('ex', 'ey'),
      leftEye: at('lx', 'ly'),
      rightEye: at('rx', 'ry'),
      nose: at('nx', 'ny'),
      mouth: at('mx', 'my'),
    );
  }
}

/// Posición de una superposición en un instante del video. [x] e [y] son el centro (0–1 desde la esquina superior
/// izquierda del video final), [width] el ancho en fracción del ancho del video y [rotation] el giro en grados en
/// sentido antihorario. Entre dos claves se interpola en línea recta.
class OverlayKey {
  const OverlayKey(this.ms, {required this.x, required this.y, required this.width, this.rotation = 0, this.alpha = 1});

  final int ms;
  final double x;
  final double y;
  final double width;
  final double rotation;
  final double alpha;

  Map<String, Object> toMap() => {'ms': ms, 'x': x, 'y': y, 'width': width, 'rotation': rotation, 'alpha': alpha};
}

/// Imagen PNG (con transparencia) que se dibuja encima del video siguiendo sus [keys].
class VideoOverlay {
  const VideoOverlay(this.image, this.keys);

  final String image;
  final List<OverlayKey> keys;

  Map<String, Object> toMap() => {'image': image, 'keys': [for (final k in keys) k.toMap()]};
}

/// Trabajo de edición: [input] → [output] (MP4 H.264/AAC).
class VideoRenderJob {
  const VideoRenderJob({
    required this.input,
    required this.output,
    this.imageMs = 0,
    this.aspect,
    this.contain = false,
    this.maxWidth = 1080,
    this.colorMatrix,
    this.overlays = const [],
    this.outroImage,
    this.outroMs = 0,
    this.audio,
    this.audioStartMs = 0,
    this.keepAudio = true,
  });

  final String input;
  final String output;

  /// Mayor que 0: [input] es una imagen (PNG o JPEG) que se convierte en un video de esa duración.
  final int imageMs;

  /// Proporción ancho/alto del video final. Sin ella se conserva la del original.
  final double? aspect;

  /// Con [aspect]: encajar el original entero con franjas negras en vez de recortarlo al centro.
  final bool contain;

  /// Ancho máximo del video final en píxeles (nunca se agranda el original).
  final int maxWidth;

  /// Matriz 4×5 de ColorFilter.matrix (desplazamientos en 0–255).
  final List<double>? colorMatrix;

  final List<VideoOverlay> overlays;

  /// Imagen que se muestra al final durante [outroMs] (cierre con el autor y la web).
  final String? outroImage;
  final int outroMs;

  /// Sonido que sustituye al del video (la canción de un reel grabado a su compás), desde [audioStartMs].
  final String? audio;
  final int audioStartMs;

  /// Sin [audio]: conservar el sonido propio del video.
  final bool keepAudio;

  Map<String, Object?> toMap() => {
        'input': input,
        'output': output,
        'imageMs': imageMs,
        'aspect': aspect,
        'contain': contain,
        'maxWidth': maxWidth,
        'colorMatrix': colorMatrix,
        'overlays': [for (final o in overlays) o.toMap()],
        'outroImage': outroImage,
        'outroMs': outroMs,
        'audio': audio,
        'audioStartMs': audioStartMs,
        'keepAudio': keepAudio,
      };
}

/// Fotograma extraído de un video (JPEG ya girado como se ve en pantalla).
class VideoFrame {
  const VideoFrame(this.ms, this.path, this.width, this.height);

  final int ms;
  final String path;
  final int width;
  final int height;
}

/// Edición de video nativa: Media3 Transformer en Android y AVFoundation en iOS. Un trabajo a la vez.
class TrevixVideo {
  static const _channel = MethodChannel('trevix_video');

  /// Fotogramas exactos cada [intervalMs] (lado mayor ≤ [maxSide]) guardados en [dir].
  static Future<List<VideoFrame>> frames(String input, String dir, {int intervalMs = 200, int maxSide = 480}) async {
    final list = await _channel.invokeListMethod<Map<Object?, Object?>>('frames', {
      'input': input,
      'dir': dir,
      'intervalMs': intervalMs,
      'maxSide': maxSide,
    });
    return [
      for (final f in list ?? const <Map<Object?, Object?>>[])
        VideoFrame((f['ms'] as num).toInt(), f['path'] as String, (f['width'] as num).toInt(), (f['height'] as num).toInt()),
    ];
  }

  /// Ejecuta el trabajo y devuelve la ruta del video final. Lanza [PlatformException] si falla o se cancela.
  static Future<String> render(VideoRenderJob job) async {
    final out = await _channel.invokeMethod<String>('render', job.toMap());
    return out ?? job.output;
  }

  /// Caras de una imagen: un archivo ([path]) o una imagen en gris de [width]×[height] ya derecha ([gray], un byte
  /// por píxel, ancho par). Todo en el teléfono, sin servicios externos.
  static Future<List<DetectedFace>> faces({String? path, Uint8List? gray, int width = 0, int height = 0}) async {
    final list = await _channel.invokeListMethod<Map<Object?, Object?>>('faces', {
      'path': path,
      'gray': gray,
      'width': width,
      'height': height,
    });
    return [for (final m in list ?? const <Map<Object?, Object?>>[]) DetectedFace.fromMap(m)];
  }

  /// Avance del trabajo en curso (0–1) o null si aún no se conoce.
  static Future<double?> progress() async {
    final p = await _channel.invokeMethod<num>('progress');
    return p == null || p < 0 ? null : p.toDouble().clamp(0.0, 1.0);
  }

  static Future<void> cancel() => _channel.invokeMethod('cancel');

  /// Brillo de la pantalla (0–1) mientras dura el flash frontal; null devuelve el anterior.
  static Future<void> brightness(double? value) => _channel.invokeMethod('brightness', {'value': value});

  /// iPhone: sube la linterna ya encendida de la cámara trasera a su nivel máximo (en Android no hace nada).
  static Future<void> torchMax() => _channel.invokeMethod('torchMax');
}
