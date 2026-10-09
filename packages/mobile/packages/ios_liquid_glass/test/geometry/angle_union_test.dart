import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'pair_topology.dart';
import 'scene_sdf_mirror.dart';

double _model(double gap, double k, double x, double y) {
  final cx = pairRadius + gap / 2;
  final r1 = math.sqrt((x + cx) * (x + cx) + y * y), r2 = math.sqrt((x - cx) * (x - cx) + y * y);
  final a = r1 - pairRadius, b = r2 - pairRadius;
  if (k <= 0) return math.min(a, b);
  final h = math.max(k - (a - b).abs(), 0.0) / k;
  final dot = ((x + cx) * (x - cx) + y * y) / math.max(r1 * r2, 1e-9);
  return math.min(a, b) - h * h * k / 4 * (1 - dot) / 2;
}

List<MirrorShape> _pair(double gap) {
  final cx = pairRadius + gap / 2;
  return [MirrorShape.circle(-cx, 0, 2 * pairRadius), MirrorShape.circle(cx, 0, 2 * pairRadius)];
}

void main() {
  test('two 80 pt circles at k = 40 and gap 0 join with the model neck of 50 pt', () {
    final field = PairField(0, 40);
    expect(field.count, 1);
    expect(field.neck, closeTo(50, 1e-9));
  });

  test('the neck narrows with the gap as the model draws it: 45.33 pt at 4, 12 pt at 19', () {
    expect(PairField(4, 40).neck, closeTo(136 / 3, 1e-9));
    expect(PairField(19, 40).neck, closeTo(12, 1e-9));
  });

  test('at gap 20 and k = 40 the circles still touch through a pinch two pixels wide', () {
    final field = PairField(20, 40);
    expect(field.count, 1);
    expect(field.neck, closeTo(2 / 3, 1e-9));
  });

  test('from gap 21 the circles are apart, and at gap 24 each inner edge bulges 3 pt past its circle', () {
    expect(PairField(21, 40).count, 2);
    final field = PairField(24, 40);
    expect(field.count, 2);
    expect(field.tip, closeTo(3, 1e-9));
  });

  test('two shapes draw the angle-weighted smooth union exactly', () {
    for (final (gap, k) in [(0.0, 40.0), (12.0, 40.0), (24.0, 40.0), (4.0, 8.0), (30.0, 80.0)]) {
      final shapes = _pair(gap);
      var worst = 0.0;
      for (var y = -52.0; y <= 52; y += 1.25) {
        for (var x = -100.0; x <= 100; x += 1.25) {
          worst = math.max(worst, (sceneSdf(shapes, x, y, k) - _model(gap, k, x, y)).abs());
        }
      }
      expect(worst, lessThan(1e-9), reason: 'gap $gap, k $k');
    }
  });

  test('a blend of 0 is the plain minimum of the shapes', () {
    final shapes = _pair(0);
    for (var x = -60.0; x <= 60; x += 3.5) {
      for (var y = -50.0; y <= 50; y += 3.5) {
        expect(sceneSdf(shapes, x, y, 0), math.min(shapeSdf(shapes[0], x, y), shapeSdf(shapes[1], x, y)));
      }
    }
  });

  group('known carry-in to project 3: the carried gradient of a fold of three different shapes flips at the first pair\'s bisector', () {
    const cluster = [MirrorShape.circle(0, 0, 44), MirrorShape.circle(52, 0, 44), MirrorShape.circle(-7.68, 17.77, 44)];
    const row = [MirrorShape.circle(0, 0, 44), MirrorShape.circle(52, 0, 44), MirrorShape.circle(104, 0, 44)];

    double step(List<MirrorShape> shapes, double k) {
      var worst = 0.0;
      for (var y = -60.0; y <= 60; y += 0.05) {
        worst = math.max(worst, (sceneSdf(shapes, 26 - 1e-5, y, k) - sceneSdf(shapes, 26 + 1e-5, y, k)).abs());
      }
      return worst;
    }

    test('the field steps by 0.877 at k = 8 and 2.159 at k = 20 across x = 26; h * 0.5 in the carried gradient (sdf.glsl and the mirror) removes it and moves every fold of three or more shapes', () {
      expect(step(cluster, 8), closeTo(0.877, 0.002));
      expect(step(cluster, 20), closeTo(2.159, 0.002));
    });

    test('a row of three equal circles at k = 8 or 20 and any two shapes are unaffected', () {
      expect(step(row, 8), lessThan(1e-9));
      expect(step(row, 20), lessThan(1e-9));
      expect(step(cluster.sublist(0, 2), 20), lessThan(1e-9));
    });
  });
}
