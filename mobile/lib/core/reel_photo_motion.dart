import 'dart:math' as math;

/// Interpolación suave entre 0 y 1 (estilo Ken Burns de TikTok).
double _ease(double p) => p * p * (3 - 2 * p);

/// Un fotograma de la foto en el instante [t]: centro, zoom, rotación y opacidad.
typedef PhotoMotionFrame = ({double x, double y, double zoom, double rotation, double alpha});

/// Estilos globales de movimiento o [auto] (uno distinto por cada foto).
const reelPhotoMotionModes = ['auto', 'motion', 'loop', 'static', 'zoom_in', 'zoom_out', 'pan_left', 'pan_right', 'pan_up', 'drift'];

/// Etiquetas e iconos los define la pantalla; aquí solo la lógica de movimiento.

const _autoCycle = ['zoom_in', 'pan_right', 'drift', 'zoom_out', 'pan_left', 'pan_up', 'zoom_in', 'drift'];

String _resolvedMode(String mode, int photoIndex) =>
    mode == 'auto' ? _autoCycle[photoIndex % _autoCycle.length] : mode;

/// [per] = duración visible de cada foto en ms; [t] = tiempo global del reel en ms.
PhotoMotionFrame photoMotionAt(String mode, int photoIndex, int photoCount, int perMs, int tMs, {int fadeMs = 300}) {
  final start = photoIndex * perMs;
  final end = (photoIndex + 1) * perMs;
  final last = photoIndex == photoCount - 1;

  double alpha;
  if (tMs < start || (!last && tMs > end + fadeMs)) {
    alpha = 0;
  } else if (photoIndex > 0 && tMs < start + fadeMs) {
    alpha = (tMs - start) / fadeMs;
  } else {
    alpha = 1;
  }

  final p = perMs > 0 ? _ease(((tMs - start) / perMs).clamp(0.0, 1.0)) : 0.0;
  final resolved = _resolvedMode(mode, photoIndex);

  final frame = switch (resolved) {
    'zoom_in' => (x: 0.5, y: 0.5, zoom: 1 + .24 * p, rotation: 0.0),
    'zoom_out' => (x: 0.5, y: 0.5, zoom: 1.24 - .24 * p, rotation: 0.0),
    'pan_left' => (x: 0.56 - .14 * p, y: 0.5, zoom: 1.08, rotation: 0.0),
    'pan_right' => (x: 0.44 + .14 * p, y: 0.5, zoom: 1.08, rotation: 0.0),
    'pan_up' => (x: 0.5, y: 0.56 - .12 * p, zoom: 1.1, rotation: 0.0),
    'drift' => (
        x: 0.48 + .08 * p,
        y: 0.52 - .10 * p,
        zoom: 1 + .16 * p,
        rotation: -1.2 + 2.4 * p,
      ),
    'loop' => (x: 0.5, y: 0.5, zoom: 1 + .15 * (1 - (2 * p - 1).abs()), rotation: 0.0),
    'static' => (x: 0.5, y: 0.5, zoom: 1.0, rotation: 0.0),
    'motion' => () {
        final dir = photoIndex.isEven ? 1.0 : -1.0;
        return (x: 0.5 + dir * .035 * (p * 2 - 1), y: 0.5, zoom: 1 + .18 * p, rotation: dir * .6 * p);
      }(),
    _ => (x: 0.5, y: 0.5, zoom: 1.0, rotation: 0.0),
  };

  return (
    x: frame.x.clamp(0.2, 0.8),
    y: frame.y.clamp(0.2, 0.8),
    zoom: math.max(1.0, frame.zoom),
    rotation: frame.rotation,
    alpha: alpha,
  );
}