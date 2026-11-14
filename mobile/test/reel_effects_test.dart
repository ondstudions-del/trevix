import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trevix/core/reel_effects.dart';

void main() {
  test('cada efecto dibuja todos sus fotogramas en formato vertical y 4:5', () {
    for (final effect in reelEffectNames.keys) {
      expect(reelEffectFrameCount(effect), greaterThan(0));
      expect(reelEffectFrameMs(effect), greaterThan(0));
      for (final size in const [Size(540, 960), Size(540, 675)]) {
        for (var frame = 0; frame < reelEffectFrameCount(effect); frame++) {
          final recorder = ui.PictureRecorder();
          paintReelEffect(Canvas(recorder), size, effect, frame);
          recorder.endRecording().dispose();
        }
      }
    }
  });

  test('los efectos animados tienen varios fotogramas y los estáticos uno', () {
    expect(reelEffectFrameCount('grain'), greaterThan(1));
    expect(reelEffectFrameCount('hearts'), greaterThan(1));
    expect(reelEffectFrameCount('vignette'), 1);
    expect(reelEffectFrameCount('frame'), 1);
  });
}
