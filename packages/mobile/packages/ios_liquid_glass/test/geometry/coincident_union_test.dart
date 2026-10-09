import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'scene_sdf_mirror.dart';

const double _k = 20;
const double _cy = 84;
const double _bisector = 338;

const _back = MirrorShape.circle(38, _cy, 44);
const _capsule1 = MirrorShape(3, 312, _cy, 44, 44, 999);
const _circle1 = MirrorShape.circle(312, _cy, 44);
const _capsule2 = MirrorShape(3, 364, _cy, 44, 44, 999);
const _circle2 = MirrorShape.circle(364, _cy, 44);

final List<MirrorShape> _doubled = [_back, _capsule1, _circle1, _capsule2, _circle2];
final List<MirrorShape> _single = [_back, _circle1, _circle2];

double _field(List<MirrorShape> shapes, double x, double y) => sceneSdf(shapes, x, y, _k);

double _reach(List<MirrorShape> shapes, double x, double direction) {
  if (_field(shapes, x, _cy) >= 0) return 0;
  var lo = 0.0, hi = 60.0;
  for (var i = 0; i < 80; i++) {
    final mid = (lo + hi) / 2;
    if (_field(shapes, x, _cy + direction * mid) < 0) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return lo;
}

double _column(List<MirrorShape> shapes, double x) => _reach(shapes, x, -1) + _reach(shapes, x, 1);

double _largestStep(List<MirrorShape> shapes, {required bool acrossBisector}) {
  var worst = 0.0;
  for (var row = 0; row < 132; row++) {
    final y = 62 + (row + 0.5) / 3;
    for (var col = 960; col < 1068; col++) {
      final x0 = (col + 0.5) / 3, x1 = (col + 1.5) / 3;
      final f0 = _field(shapes, x0, y), f1 = _field(shapes, x1, y);
      if (f0 > 0 || f1 > 0 || f0 < -10 || f1 < -10) continue;
      if ((x0 < _bisector && x1 > _bisector) != acrossBisector) continue;
      worst = math.max(worst, (f1 - f0).abs() * 3);
    }
  }
  return worst;
}

void main() {
  test('one glass per trailing action gives the layout circles: 44 pt tall at their centres', () {
    expect(_column(_single, 312.001), closeTo(44, 0.01));
    expect(_column(_single, 364.001), closeTo(44, 0.01));
  });

  test('the field is continuous across the bisector of the two trailing circles', () {
    expect(_largestStep(_single, acrossBisector: true), lessThan(1e-9));
  });

  test('the neck of the two trailing circles is 12.41 pt at the bisector and 15.82 pt at x = 335', () {
    expect(_column(_single, _bisector - 1e-4), closeTo(12.41, 0.01));
    expect(_column(_single, _bisector + 1e-4), closeTo(12.41, 0.01));
    expect(_column(_single, 335), closeTo(15.82, 0.01));
  });

  test('the neck is the same on both sides of the bisector', () {
    for (final offset in [1.0, 3.0, 5.0, 8.0]) {
      expect(_column(_single, _bisector - offset), closeTo(_column(_single, _bisector + offset), 1e-6));
    }
  });

  test('hazard: the same buttons drawn twice steps by more than 7 px across the bisector and thins the neck', () {
    expect(_largestStep(_doubled, acrossBisector: true), greaterThan(7));
    expect(_largestStep(_single, acrossBisector: true), lessThan(1e-9));
    var worst = 0.0;
    for (var x = 330.0; x <= 346; x += 0.5) {
      worst = math.max(worst, (_column(_doubled, x) - _column(_single, x)).abs());
    }
    expect(worst, greaterThan(2));
  });

  test('two coincident shapes add nothing: the angle weight is zero for parallel normals', () {
    for (final x in [300.0, 320.0, 338.0]) {
      for (final y in [60.0, 84.0, 100.0]) {
        final alone = sceneSdf([_circle1], x, y, _k);
        expect(sceneSdf([_circle1, _capsule1], x, y, _k), closeTo(alone, 1e-9));
      }
    }
  });
}
