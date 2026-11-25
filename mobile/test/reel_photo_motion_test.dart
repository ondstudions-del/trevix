import 'package:flutter_test/flutter_test.dart';
import 'package:trevix/core/reel_photo_motion.dart';

void main() {
  test('auto alterna zoom y desplazamiento por foto', () {
    const per = 3000;
  final a0 = photoMotionAt('auto', 0, 3, per, 1500);
    final a1 = photoMotionAt('auto', 1, 3, per, per + 1500);
    expect(a0.alpha, 1);
    expect(a1.alpha, 1);
    expect(a0.zoom, greaterThan(1));
    expect((a0.x - a1.x).abs(), greaterThan(0.01));
  });

  test('estática sin zoom', () {
    final s = photoMotionAt('static', 0, 1, 5000, 2000);
    expect(s.zoom, 1);
    expect(s.x, 0.5);
    expect(s.y, 0.5);
  });
}