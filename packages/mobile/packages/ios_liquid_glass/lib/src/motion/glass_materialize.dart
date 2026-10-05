import 'dart:math' as math;

import 'package:ios_liquid_glass/src/motion/glass_animation.dart';
import 'package:ios_liquid_glass/src/motion/ios27_motion.dart';
import 'package:meta/meta.dart';

@internal
@immutable
class GlassMaterializeMapping {
  const GlassMaterializeMapping({required this.disappearExponent, required this.appearGain, double? reduceMotionAppearGain})
    : reduceMotionAppearGain = reduceMotionAppearGain ?? appearGain;

  static const GlassMaterializeMapping defaultSpring = GlassMaterializeMapping(
    disappearExponent: ios27DefaultDisappearExponent,
    appearGain: ios27DefaultAppearGain,
    reduceMotionAppearGain: ios27DefaultReduceMotionAppearGain,
  );
  static const GlassMaterializeMapping snappy = GlassMaterializeMapping(
    disappearExponent: ios27SnappyDisappearExponent,
    appearGain: ios27SnappyAppearGain,
    reduceMotionAppearGain: ios27SnappyReduceMotionAppearGain,
  );
  static const GlassMaterializeMapping bouncy = GlassMaterializeMapping(
    disappearExponent: ios27BouncyDisappearExponent,
    appearGain: ios27BouncyAppearGain,
    reduceMotionAppearGain: ios27BouncyReduceMotionAppearGain,
  );

  final double disappearExponent;
  final double appearGain;
  final double reduceMotionAppearGain;

  double gain({required bool reduceMotion}) => reduceMotion ? reduceMotionAppearGain : appearGain;

  static GlassMaterializeMapping of(GlassAnimation animation) {
    final presets = [
      (GlassAnimation.defaultSpring.dampingFraction, defaultSpring),
      (GlassAnimation.snappy.dampingFraction, snappy),
      (GlassAnimation.bouncy.dampingFraction, bouncy),
    ];
    var chosen = presets.first;
    for (final preset in presets.skip(1)) {
      if ((animation.dampingFraction - preset.$1).abs() < (animation.dampingFraction - chosen.$1).abs()) chosen = preset;
    }
    return chosen.$2;
  }
}

@internal
sealed class GlassMaterialize {
  static double progress(
    double presence, {
    required bool appearing,
    GlassMaterializeMapping mapping = GlassMaterializeMapping.defaultSpring,
    bool reduceMotion = false,
  }) {
    if (presence <= 0) return 0;
    if (!appearing) return math.pow(math.min(presence, 1.0), mapping.disappearExponent).toDouble();
    return presence <= 1 ? presence : 1 + mapping.gain(reduceMotion: reduceMotion) * (presence - 1);
  }

  static double visibility(double progress, {List<double> table = ios27VisibilityForProgress}) {
    final last = table.length - 1;
    if (progress <= 0) return table.first;
    if (progress >= 1) return table[last] + (table[last] - table[last - 1]) * last * (progress - 1);
    final p = progress * last;
    final low = p.floor();
    return table[low] + (table[low + 1] - table[low]) * (p - low);
  }

  static (double, double) reverse(
    double presence,
    double velocity, {
    required bool toAppearing,
    GlassMaterializeMapping from = GlassMaterializeMapping.defaultSpring,
    GlassMaterializeMapping to = GlassMaterializeMapping.defaultSpring,
    bool reduceMotion = false,
  }) {
    if (toAppearing) {
      final p = presence.clamp(0.0, 1.0);
      final alpha = math.pow(p, from.disappearExponent).toDouble();
      final rate = from.disappearExponent * math.pow(p, from.disappearExponent - 1).toDouble() * velocity;
      return (alpha, math.max(0, rate));
    }
    final alpha = progress(presence, appearing: true, mapping: from, reduceMotion: reduceMotion).clamp(0.0, 1.0);
    if (alpha <= 0) return (0, 0);
    final rate = velocity * (presence > 1 ? from.gain(reduceMotion: reduceMotion) : 1);
    final root = math.pow(alpha, 1 / to.disappearExponent).toDouble();
    return (root, math.min(0, rate / (to.disappearExponent * math.pow(root, to.disappearExponent - 1).toDouble())));
  }
}
