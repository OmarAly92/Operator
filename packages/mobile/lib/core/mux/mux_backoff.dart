import 'dart:math' as math;

sealed class MuxBackoff {
  static const int initialMs = 1000;
  static const int maxMs = 15000;

  static int next(int currentMs) => math.min(currentMs * 2, maxMs);
}
