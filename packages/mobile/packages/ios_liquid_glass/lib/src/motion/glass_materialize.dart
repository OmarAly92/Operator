import 'dart:math' as math;

import 'package:ios_liquid_glass/src/motion/glass_animation.dart';
import 'package:ios_liquid_glass/src/motion/ios27_motion.dart';
import 'package:meta/meta.dart';

@internal
@immutable
class GlassMaterializeMapping {
  const GlassMaterializeMapping({
    required this.disappearExponent,
    required double appearGain,
    double? lightAppearGain,
    double? reduceMotionAppearGain,
    double? lightReduceMotionAppearGain,
  }) : darkAppearGain = appearGain,
       lightAppearGain = lightAppearGain ?? appearGain,
       darkReduceMotionAppearGain = reduceMotionAppearGain ?? appearGain,
       lightReduceMotionAppearGain = lightReduceMotionAppearGain ?? reduceMotionAppearGain ?? lightAppearGain ?? appearGain;

  static const GlassMaterializeMapping defaultSpring = GlassMaterializeMapping(
    disappearExponent: ios27DefaultDisappearExponent,
    appearGain: ios27DefaultDarkAppearGain,
    lightAppearGain: ios27DefaultLightAppearGain,
    reduceMotionAppearGain: ios27DefaultDarkReduceMotionAppearGain,
    lightReduceMotionAppearGain: ios27DefaultLightReduceMotionAppearGain,
  );
  static const GlassMaterializeMapping snappy = GlassMaterializeMapping(
    disappearExponent: ios27SnappyDisappearExponent,
    appearGain: ios27SnappyDarkAppearGain,
    lightAppearGain: ios27SnappyLightAppearGain,
    reduceMotionAppearGain: ios27SnappyDarkReduceMotionAppearGain,
    lightReduceMotionAppearGain: ios27SnappyLightReduceMotionAppearGain,
  );
  static const GlassMaterializeMapping bouncy = GlassMaterializeMapping(
    disappearExponent: ios27BouncyDisappearExponent,
    appearGain: ios27BouncyDarkAppearGain,
    lightAppearGain: ios27BouncyLightAppearGain,
    reduceMotionAppearGain: ios27BouncyDarkReduceMotionAppearGain,
    lightReduceMotionAppearGain: ios27BouncyLightReduceMotionAppearGain,
  );

  final double disappearExponent;
  final double darkAppearGain;
  final double lightAppearGain;
  final double darkReduceMotionAppearGain;
  final double lightReduceMotionAppearGain;

  double gain({required bool reduceMotion, bool dark = true}) => switch ((reduceMotion, dark)) {
    (false, true) => darkAppearGain,
    (false, false) => lightAppearGain,
    (true, true) => darkReduceMotionAppearGain,
    (true, false) => lightReduceMotionAppearGain,
  };

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
    bool dark = true,
  }) {
    if (presence <= 0) return 0;
    if (!appearing) return math.pow(math.min(presence, 1.0), mapping.disappearExponent).toDouble();
    return presence <= 1 ? presence : 1 + mapping.gain(reduceMotion: reduceMotion, dark: dark) * (presence - 1);
  }

  static double visibility(double progress, {List<double> table = ios27VisibilityForProgress, List<double> above = ios27VisibilityAboveFull}) {
    final last = table.length - 1;
    if (progress <= 0) return table.first;
    if (progress < 1) {
      final p = progress * last;
      final low = p.floor();
      return table[low] + (table[low + 1] - table[low]) * (p - low);
    }
    if (above.isEmpty) return table[last] + (table[last] - table[last - 1]) * last * (progress - 1);
    double point(int index) => index == 0 ? table[last] : above[index - 1];
    final q = (progress - 1) * last;
    final top = above.length;
    if (q >= top) return point(top) + (point(top) - point(top - 1)) * (q - top);
    final low = q.floor();
    return point(low) + (point(low + 1) - point(low)) * (q - low);
  }

  static (double, double) reverse(
    double presence,
    double velocity, {
    required bool toAppearing,
    GlassMaterializeMapping from = GlassMaterializeMapping.defaultSpring,
    GlassMaterializeMapping to = GlassMaterializeMapping.defaultSpring,
    bool reduceMotion = false,
    bool dark = true,
  }) {
    if (toAppearing) {
      final p = presence.clamp(0.0, 1.0);
      final alpha = math.pow(p, from.disappearExponent).toDouble();
      final rate = from.disappearExponent * math.pow(p, from.disappearExponent - 1).toDouble() * velocity;
      return (alpha, math.max(0, rate));
    }
    final alpha = progress(presence, appearing: true, mapping: from, reduceMotion: reduceMotion, dark: dark).clamp(0.0, 1.0);
    if (alpha <= 0) return (0, 0);
    final rate = velocity * (presence > 1 ? from.gain(reduceMotion: reduceMotion, dark: dark) : 1);
    final root = math.pow(alpha, 1 / to.disappearExponent).toDouble();
    return (root, math.min(0, rate / (to.disappearExponent * math.pow(root, to.disappearExponent - 1).toDouble())));
  }
}
