import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'glsl_function.dart';
import 'scene_sdf_mirror.dart';

final String _source = File('lib/assets/shaders/sdf.glsl').readAsStringSync();
final GlslFunction _union = GlslFunction.parse(_source, 'angleSmoothUnion');

List<double> _vec(Sdf s) => [s.d, s.nx, s.ny];

List<double> _shaderFold(List<MirrorShape> shapes, double x, double y, double k) {
  var result = _vec(shapeSdfWithNormal(shapes.first, x, y));
  for (final shape in shapes.skip(1)) {
    result = _union.call([result, _vec(shapeSdfWithNormal(shape, x, y)), [k]]);
  }
  return result;
}

const List<MirrorShape> _clusterOfThree = [
  MirrorShape.circle(0, 0, 44),
  MirrorShape.circle(52, 0, 44),
  MirrorShape.circle(-7.68, 17.77, 44),
];

const List<List<MirrorShape>> _scenes = [
  [MirrorShape.circle(-30, 0, 44), MirrorShape.circle(30, 0, 44)],
  [MirrorShape.circle(-30, 0, 44), MirrorShape(3, 34, 4, 70, 44, 12)],
  [MirrorShape(1, -34, 0, 70, 44, 14), MirrorShape.circle(30, 6, 60)],
  _clusterOfThree,
  [MirrorShape.circle(0, 0, 44), MirrorShape.circle(48, 0, 44), MirrorShape(3, 24, 40, 80, 36, 10), MirrorShape.circle(-40, 30, 30)],
];

double _largestDifference(List<MirrorShape> shapes, double k) {
  var worst = 0.0;
  for (var y = -70.0; y <= 70; y += 2.3) {
    for (var x = -90.0; x <= 110; x += 2.3) {
      final shader = _shaderFold(shapes, x, y, k);
      final mirror = sceneSdfWithNormal(shapes, x, y, k);
      worst = math.max(worst, math.max((shader[0] - mirror.d).abs(), math.max((shader[1] - mirror.nx).abs(), (shader[2] - mirror.ny).abs())));
    }
  }
  return worst;
}

void main() {
  test('the shader source still has the shape the interpreter and the mirror were written for', () {
    expect(_union.parameters, ['a', 'b', 'k']);
    expect(_union.normalized, hasLength(7));
    expect(_source.replaceAll(RegExp(r'\s+'), ' '), contains('blended = angleSmoothUnion(blended, getShapeSDFGradFromArray(i, p, shapeData), blend);'));
    expect(_source.replaceAll(RegExp(r'\s+'), ' '), contains('vec3 blended = getShapeSDFGradFromArray(0, p, shapeData);'));
  });

  for (final k in [8.0, 20.0, 40.0]) {
    for (var i = 0; i < _scenes.length; i++) {
      test('angleSmoothUnion in sdf.glsl and its Dart mirror give the same distance and normal: scene $i at k = $k', () {
        expect(_largestDifference(_scenes[i], k), lessThan(1e-9));
      });
    }
  }

  test('the parity scenes exercise both the weight and the near and far order', () {
    var weighted = 0, swapped = 0, samples = 0;
    final shapes = _clusterOfThree;
    for (var y = -50.0; y <= 50; y += 2.3) {
      for (var x = -50.0; x <= 90; x += 2.3) {
        final a = shapeSdfWithNormal(shapes[0], x, y), b = shapeSdfWithNormal(shapes[1], x, y);
        samples++;
        if ((a.d - b.d).abs() < 8 && (1 - (a.nx * b.nx + a.ny * b.ny)) * 0.5 > 0.05) weighted++;
        if (a.d > b.d) swapped++;
      }
    }
    expect(weighted, greaterThan(samples ~/ 20));
    expect(swapped, inInclusiveRange(samples ~/ 5, samples * 4 ~/ 5));
  });

  test('a change to either side alone is seen: the shader with another weight reads differently from the mirror', () {
    final changed = GlslFunction.parse(_source.replaceFirst('* 0.5;\n    vec3 near', '* 0.7;\n    vec3 near'), 'angleSmoothUnion');
    expect(changed.normalized, isNot(_union.normalized));
    final a = _vec(shapeSdfWithNormal(_clusterOfThree[0], 26, 3)), b = _vec(shapeSdfWithNormal(_clusterOfThree[1], 26, 3));
    final mirror = angleSmoothUnion(Sdf(a[0], a[1], a[2]), Sdf(b[0], b[1], b[2]), 20);
    expect((changed.call([a, b, [20]])[0] - mirror.d).abs(), greaterThan(1e-3));
    expect((_union.call([a, b, [20]])[0] - mirror.d).abs(), lessThan(1e-12));
  });
}
