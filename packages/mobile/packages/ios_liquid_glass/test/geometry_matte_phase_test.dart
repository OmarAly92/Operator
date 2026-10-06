import 'dart:typed_data';
import 'dart:ui';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/src/internal/render_liquid_glass_geometry.dart';

const _size = Size(48, 40);
const _matteBounds = Rect.fromLTWH(0, 0, 24, 20);
const _translations = [Offset(5.375, 3.625), Offset(9.125, 2), Offset(4, 6.5), Offset(7, 3)];

Picture _edges() {
  final recorder = PictureRecorder();
  Canvas(recorder)
    ..drawRect(const Rect.fromLTWH(3.5, 2.25, 15.25, 1.5), Paint()..color = const Color(0xFF00FF00))
    ..drawRect(const Rect.fromLTWH(5.125, 6.75, 9.5, 8.375), Paint()..color = const Color(0xFFFF0000));
  return recorder.endRecording();
}

Picture _field() {
  final recorder = PictureRecorder();
  Canvas(recorder).drawRect(
    _matteBounds,
    Paint()..shader = ui.Gradient.radial(const Offset(10.25, 9.5), 6.5, const [Color(0xFFFF0000), Color(0x00000000)]),
  );
  return recorder.endRecording();
}

RenderedGeometryCache _cache(Picture matte) => UnrenderedGeometryCache(
  matte: matte,
  matteBounds: _matteBounds,
  bounds: _matteBounds,
  shapes: const [],
  path: Path(),
).render();

Future<Uint8List> _pixels(void Function(Canvas canvas) draw) async {
  final recorder = PictureRecorder();
  draw(Canvas(recorder));
  final picture = recorder.endRecording();
  final image = await picture.toImage(_size.width.toInt(), _size.height.toInt());
  final bytes = await image.toByteData();
  image.dispose();
  picture.dispose();
  return bytes!.buffer.asUint8List();
}

Offset _centroid(Uint8List pixels) {
  var sum = 0.0, x = 0.0, y = 0.0;
  for (var i = 0; i < pixels.length; i += 4) {
    final value = pixels[i].toDouble();
    final index = i ~/ 4;
    sum += value;
    x += value * (index % _size.width + 0.5);
    y += value * (index ~/ _size.width + 0.5);
  }
  return Offset(x / sum, y / sum);
}

int _largestDifference(Uint8List a, Uint8List b) {
  var largest = 0;
  for (var i = 0; i < a.length; i++) {
    final difference = (a[i] - b[i]).abs();
    if (difference > largest) largest = difference;
  }
  return largest;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a cached matte drawn at a fractional offset is the picture drawn there, pixel for pixel, for antialiased edges', () async {
    for (final translation in _translations) {
      final cache = _cache(_edges());
      final exact = await _pixels((canvas) => canvas
        ..translate(translation.dx, translation.dy)
        ..drawPicture(cache.picture));
      final cached = await _pixels((canvas) => drawMatteAt(canvas, cache, translation));
      expect(cached, exact, reason: 'at $translation');
      cache.dispose();
    }
  });

  test('a cached matte of a field evaluated per pixel lands within 0.01 px of the picture and one level of its values', () async {
    for (final translation in _translations) {
      final cache = _cache(_field());
      final exact = await _pixels((canvas) => canvas
        ..translate(translation.dx, translation.dy)
        ..drawPicture(cache.picture));
      final cached = await _pixels((canvas) => drawMatteAt(canvas, cache, translation));
      expect(_largestDifference(cached, exact), lessThanOrEqualTo(1), reason: 'at $translation');
      expect((_centroid(cached) - _centroid(exact)).distance, lessThan(0.01), reason: 'at $translation');
      cache.dispose();
    }
  });

  test('the image rasterized on its own grid and drawn at a fractional offset snaps, the defect this replaces', () async {
    const translation = Offset(5.375, 3.625);
    final cache = _cache(_field());
    final exact = await _pixels((canvas) => canvas
      ..translate(translation.dx, translation.dy)
      ..drawPicture(cache.picture));
    final snapped = await _pixels((canvas) => canvas
      ..translate(translation.dx, translation.dy)
      ..drawImage(cache.matteAt(Offset.zero), Offset.zero, Paint()));
    expect((_centroid(snapped) - _centroid(exact)).distance, greaterThan(0.3));
    cache.dispose();
  });

  test('a cached matte drawn again at the same phase keeps its image, and a new phase rasterizes it again', () {
    final cache = _cache(_field());
    final first = cache.matteAt(const Offset(0.375, 0.5));
    expect(identical(cache.matteAt(const Offset(0.375, 0.5)), first), isTrue);
    expect(identical(cache.matteAt(const Offset(0.376, 0.5)), first), isTrue);
    final second = cache.matteAt(const Offset(0.625, 0.5));
    expect(identical(second, first), isFalse);
    expect(first.debugDisposed, isTrue);
    expect(cache.phase, const Offset(0.625, 0.5));
    expect((second.width, second.height), (25, 21));
    expect((cache.matteAt(Offset.zero).width, cache.matte.height), (24, 20));
    cache.dispose();
    expect(cache.matte.debugDisposed, isTrue);
  });

  test('only a pure translation is drawn on the pixel grid', () {
    expect(pixelTranslation(Matrix4.translationValues(973.164, 181, 0)), const Offset(973.164, 181));
    expect(pixelTranslation(Matrix4.diagonal3Values(3, 3, 1)..scaleByDouble(1 / 3, 1 / 3, 1, 1)..translateByDouble(2.5, 1, 0, 1)), const Offset(2.5, 1));
    expect(pixelTranslation(Matrix4.diagonal3Values(0.9, 0.9, 1)), isNull);
    expect(pixelTranslation(Matrix4.rotationZ(0.1)), isNull);
  });
}
