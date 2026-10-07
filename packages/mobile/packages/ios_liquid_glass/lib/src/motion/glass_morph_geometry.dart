import 'dart:math' as math;
import 'dart:ui';

import 'package:ios_liquid_glass/src/liquid_shape.dart';
import 'package:meta/meta.dart';

@internal
sealed class GlassMorphGeometry {
  static double sdf(LiquidShape shape, Rect rect, Offset point) {
    final p = point - rect.center;
    final hx = rect.width / 2, hy = rect.height / 2;
    if (shape is LiquidOval) {
      final rx = math.max(hx, 1e-4), ry = math.max(hy, 1e-4);
      final k1 = math.sqrt(p.dx * p.dx / (rx * rx) + p.dy * p.dy / (ry * ry));
      final k2 = math.sqrt(p.dx * p.dx / (rx * rx * rx * rx) + p.dy * p.dy / (ry * ry * ry * ry));
      return k1 * (k1 - 1) / math.max(k2, 1e-4);
    }
    final radius = math.min(
      switch (shape) {
        LiquidRoundedRectangle(:final borderRadius) => borderRadius,
        LiquidRoundedSuperellipse(:final borderRadius) => borderRadius,
        LiquidOval() => 0.0,
      },
      math.min(hx, hy),
    );
    final qx = p.dx.abs() - hx + radius, qy = p.dy.abs() - hy + radius;
    return math.min(math.max(qx, qy), 0.0) + math.sqrt(math.pow(math.max(qx, 0.0), 2) + math.pow(math.max(qy, 0.0), 2)) - radius;
  }

  static double extent(LiquidShape shape, Rect rect, Offset direction) {
    if (rect.isEmpty) return 0;
    var low = 0.0, high = math.sqrt(rect.width * rect.width + rect.height * rect.height) / 2 + 1;
    for (var i = 0; i < 40; i++) {
      final mid = (low + high) / 2;
      if (sdf(shape, rect, rect.center + direction * mid) < 0) {
        low = mid;
      } else {
        high = mid;
      }
    }
    return (low + high) / 2;
  }

  static double gap(Rect a, LiquidShape shapeA, Rect b, LiquidShape shapeB) {
    final delta = b.center - a.center;
    final distance = delta.distance;
    if (distance < 1e-9) return -(a.shortestSide + b.shortestSide) / 2;
    final direction = delta / distance;
    return distance - extent(shapeA, a, direction) - extent(shapeB, b, -direction);
  }
}
