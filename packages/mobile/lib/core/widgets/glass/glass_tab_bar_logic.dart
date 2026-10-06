import 'package:flutter/widgets.dart';
import 'package:operator_mobile/core/widgets/glass/glass_metrics.dart';

sealed class GlassTabBarLogic {
  static const double pillWidthScale = 1.05;

  static double pillWidth(double width, int count) {
    final track = width - GlassMetrics.dropletInset * 2;
    return (track / count * pillWidthScale).clamp(0, track).toDouble();
  }

  static double slotCenter(int index, double width, int count) {
    if (count <= 1) return width / 2;
    final pill = pillWidth(width, count);
    final step = (width - GlassMetrics.dropletInset * 2 - pill) / (count - 1);
    return GlassMetrics.dropletInset + pill / 2 + index * step;
  }

  static int slotAt(double x, double width, int count) {
    var nearest = 0;
    var best = double.infinity;
    for (var i = 0; i < count; i++) {
      final distance = (x - slotCenter(i, width, count)).abs();
      if (distance < best) {
        best = distance;
        nearest = i;
      }
    }
    return nearest;
  }

  static double lensCenter(double x, double width, int count) =>
      x.clamp(slotCenter(0, width, count), slotCenter(count - 1, width, count)).toDouble();

  static double proximity(double itemCenter, double lensCenter, double lensWidth) =>
      (1 - (itemCenter - lensCenter).abs() / (lensWidth / 2)).clamp(0.0, 1.0).toDouble();

  static (double, double) springStep({
    required double value,
    required double velocity,
    required double target,
    required double omega,
    required double damping,
    required double seconds,
  }) {
    const step = 1 / 240;
    var x = value;
    var v = velocity;
    var remaining = seconds;
    while (remaining > 0) {
      final dt = remaining < step ? remaining : step;
      final acceleration = -omega * omega * (x - target) - 2 * damping * omega * v;
      v += acceleration * dt;
      x += v * dt;
      remaining -= dt;
    }
    return (x, v);
  }

  static bool releaseSelects(Offset position, double width, double height) =>
      Rect.fromLTWH(0, 0, width, height).inflate(GlassMetrics.hitTarget).contains(position);
}
