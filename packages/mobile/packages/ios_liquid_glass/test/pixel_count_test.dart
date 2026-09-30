import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/src/internal/snap_rect_to_pixels.dart';

void main() {
  test('a pixel-snapped geometry of an outlined glass is exactly as many pixels as its bounds', () {
    for (final (x, y, w, h, pixelsWide, pixelsTall) in [(76.0, 329.0, 250.0, 88.0, 760, 274), (126.0, 237.0, 150.0, 44.0, 460, 142), (21.0, 465.0, 360.0, 200.0, 1090, 610)]) {
      final local = Rect.fromLTWH(0, 0, w, h).inflate(1.55).snapToPixels(3);
      final screen = local.shift(Offset(x, y)).snapToPixels(3);
      expect((screen.width * 3).toPixelCount(), pixelsWide);
      expect((screen.height * 3).toPixelCount(), pixelsTall);
    }
  });
}
