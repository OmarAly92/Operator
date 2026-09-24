import 'package:flutter/widgets.dart';
import 'package:operator_mobile/core/widgets/glass/glass_metrics.dart';

sealed class GlassTabBarLogic {
  static int slotAt(double x, double width, int count) => (x / (width / count)).floor().clamp(0, count - 1);

  static double slotCenter(int index, double width, int count) => (index + 0.5) * width / count;

  static double dropletLeft({required double centerX, required double dropletWidth, required double barWidth}) =>
      (centerX - dropletWidth / 2).clamp(0, barWidth - dropletWidth).toDouble();

  static double stretchFor(double dx) => 1 + (dx.abs() / 40).clamp(0.0, 0.2);

  static bool releaseSelects(Offset position, double width, double height) =>
      Rect.fromLTWH(0, 0, width, height).inflate(GlassMetrics.hitTarget).contains(position);
}
