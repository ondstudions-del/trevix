import 'package:flutter_test/flutter_test.dart';
import 'package:trevix/core/reel_photo_motion.dart';

void main() {
  test('fundido entre fotos', () {
    const per = 3000;
    final mid = reelPhotoSlideAt(0, 2, per, 1500);
    final next = reelPhotoSlideAt(1, 2, per, per + 100);
    expect(mid.alpha, 1);
    expect(next.alpha, greaterThan(0));
    expect(mid.zoom, 1);
  });

  test('estática centrada', () {
    final s = reelPhotoSlideAt(0, 1, 5000, 2000);
    expect(s.zoom, 1);
    expect(s.x, 0.5);
    expect(s.y, 0.5);
  });
}