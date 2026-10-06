import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

const _glass2a = [
  (3.0, [0, 0, 0, 13, 0, 0, 0, 77, 0, 0, 0, 96, 191, 191, 191, 217, 255, 253, 255, 255, 255, 192, 248, 255, 252, 116, 150, 255, 234, 56, 198, 255, 234, 56, 198, 255, 234, 56, 198, 255, 234, 56, 198, 255, 234, 56, 198, 255, 200, 93, 203, 255, 234, 69, 157, 255, 234, 56, 198, 255, 234, 56, 198, 255]),
  (9.0, [0, 0, 0, 11, 0, 0, 0, 79, 0, 0, 0, 96, 191, 182, 191, 217, 255, 177, 255, 255, 255, 142, 255, 255, 255, 114, 255, 255, 255, 95, 237, 255, 255, 82, 224, 255, 252, 73, 215, 255, 246, 67, 209, 255, 242, 63, 205, 255, 214, 107, 217, 255, 241, 62, 204, 255, 235, 56, 198, 255, 234, 56, 198, 255]),
  (24.0, [0, 0, 0, 13, 0, 0, 0, 80, 8, 7, 8, 101, 200, 178, 200, 223, 255, 177, 255, 255, 255, 140, 255, 255, 255, 114, 255, 255, 255, 95, 237, 255, 255, 82, 224, 255, 252, 73, 215, 255, 246, 67, 209, 255, 242, 63, 205, 255, 235, 99, 133, 255, 248, 69, 211, 255, 244, 65, 207, 255, 241, 62, 204, 255]),
];

Future<ui.Image> _pixels(List<int> rgba, int width) async {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(Uint8List.fromList(rgba), width, 1, ui.PixelFormat.rgba8888, completer.complete);
  return completer.future;
}

int _encoded(double signedDistancePx, double reachPx) => ((0.5 - 0.5 * signedDistancePx / reachPx) * 255).round().clamp(0, 255);

Future<List<int>> _strip({required double thicknessPx, required double fullThicknessPx, required double reachPx, bool flat = false}) async {
  const width = 16;
  final geometry = <int>[];
  for (var i = 0; i < width; i++) {
    geometry.addAll([128 + (i * 5) % 60, 200 - i * 3, _encoded(2.0 - i * 0.75, reachPx), 255]);
  }
  final backdrop = <int>[for (var i = 0; i < width; i++) ...(flat ? [90, 120, 150, 255] : [20 + i * 14, 240 - i * 13, 90 + (i * 37) % 120, 255])];
  final program = await ui.FragmentProgram.fromAsset('lib/assets/shaders/liquid_glass_final_render.frag');
  final shader = program.fragmentShader();
  final uniforms = [
    16.0, 1.0, 0.0, 0.0, 16.0, 1.0,
    0.2, 0.4, 0.9, 0.1,
    thicknessPx, 0.02, 1.2, fullThicknessPx,
    0.05, 0.55, 0.95, 0.0,
    0.9, 1.1, 0.3, 4.0,
    0.8, 0.3, 1.65, 0.0,
    0.5, 2.0, 2.0, 0.6,
    0.0, 1.0,
  ];
  for (var i = 0; i < uniforms.length; i++) {
    shader.setFloat(i, uniforms[i]);
  }
  shader
    ..setImageSampler(0, await _pixels(backdrop, width))
    ..setImageSampler(1, await _pixels(geometry, width));
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(const ui.Rect.fromLTWH(0, 0, 16, 1), ui.Paint()..shader = shader);
  final image = await recorder.endRecording().toImage(16, 1);
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  return bytes.buffer.asUint8List().toList();
}

double _reach(double thicknessPx) => thicknessPx > 2.65 ? thicknessPx : 2.65;

void main() {
  test('still glass at full visibility draws the 2A bytes pixel for pixel', () async {
    for (final (thickness, bytes) in _glass2a) {
      final strip = await _strip(thicknessPx: thickness, fullThicknessPx: thickness, reachPx: _reach(thickness));
      expect(strip, bytes, reason: 'thickness $thickness');
    }
  });

  test('over a flat backdrop a ramped lens lights its edge exactly as the full lens does, wider than its own thickness', () async {
    final full = await _strip(thicknessPx: 24, fullThicknessPx: 24, reachPx: 24, flat: true);
    final ramped = await _strip(thicknessPx: 3, fullThicknessPx: 24, reachPx: 24, flat: true);
    final coupled = await _strip(thicknessPx: 3, fullThicknessPx: 3, reachPx: _reach(3), flat: true);
    expect(ramped, full);
    expect(ramped[9 * 4], greaterThan(coupled[9 * 4]));
  });
}
