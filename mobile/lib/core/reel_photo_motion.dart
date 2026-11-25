/// Opacidad de cada foto en un reel con fundido entre ellas (sin Ken Burns: el movimiento sale del clip LIVE).
typedef PhotoMotionFrame = ({double x, double y, double zoom, double rotation, double alpha});

/// [per] = duración visible de cada foto en ms; [t] = tiempo global del reel en ms.
PhotoMotionFrame reelPhotoSlideAt(int photoIndex, int photoCount, int perMs, int tMs, {int fadeMs = 300}) {
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

  return (x: 0.5, y: 0.5, zoom: 1.0, rotation: 0.0, alpha: alpha);
}