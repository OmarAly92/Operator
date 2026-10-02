import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

Future<ui.Image> _solid(List<int> rgba) async {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(Uint8List.fromList([for (var i = 0; i < 16; i++) ...rgba]), 4, 4, ui.PixelFormat.rgba8888, completer.complete);
  return completer.future;
}

int _encodedDistance(double signedDistancePx, double reachPx) => ((0.5 - 0.5 * signedDistancePx / reachPx) * 255).round();

Future<List<int>> _pixel({required double thicknessPx, required List<int> geometry}) async {
  const outlineWidthPx = 1.65;
  final program = await ui.FragmentProgram.fromAsset('lib/assets/shaders/liquid_glass_final_render.frag');
  final shader = program.fragmentShader();
  final uniforms = [4.0, 4.0, 0.0, 0.0, 4.0, 4.0, 0.0, 0.0, 0.0, 0.0, thicknessPx, 0.0, 1.0, 0.0, 0.0, 0.5, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0, 0.8, 0.0, outlineWidthPx, 0.0, 0.0, 1.0, 2.0, 1.0, 0.0, 1.0];
  for (var i = 0; i < uniforms.length; i++) {
    shader.setFloat(i, uniforms[i]);
  }
  shader
    ..setImageSampler(0, await _solid([128, 128, 128, 255]))
    ..setImageSampler(1, await _solid(geometry));
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(const ui.Rect.fromLTWH(0, 0, 4, 4), ui.Paint()..shader = shader);
  final image = await recorder.endRecording().toImage(4, 4);
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  return [for (var i = 0; i < 4; i++) bytes.getUint8((2 * 4 + 2) * 4 + i)];
}

void main() {
  test('glass thinner than its outline band covers its interior fully, with no outline over it', () async {
    final pixel = await _pixel(thicknessPx: 0.3, geometry: [128, 128, 255, 255]);
    expect(pixel[3], 255);
    expect(pixel.take(3), everyElement(inInclusiveRange(126, 130)));
  });

  test('a pixel one pixel outside thin glass draws only the outline', () async {
    final pixel = await _pixel(thicknessPx: 0.3, geometry: [255, 128, _encodedDistance(1, 2.65), 255]);
    expect(pixel.take(3), everyElement(0));
    expect(pixel[3], inInclusiveRange(202, 206));
  });

  test('thick glass decodes its interior and its outline the same way', () async {
    final interior = await _pixel(thicknessPx: 30, geometry: [128, 128, 255, 255]);
    expect(interior[3], 255);
    expect(interior.take(3), everyElement(inInclusiveRange(126, 130)));
    final outline = await _pixel(thicknessPx: 30, geometry: [255, 128, _encodedDistance(1, 30), 255]);
    expect(outline.take(3), everyElement(0));
    expect(outline[3], inInclusiveRange(202, 206));
  });
}
