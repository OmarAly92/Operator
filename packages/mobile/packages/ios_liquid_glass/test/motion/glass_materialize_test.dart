import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/src/motion/glass_animation.dart';
import 'package:ios_liquid_glass/src/motion/glass_materialize.dart';
import 'package:ios_liquid_glass/src/motion/ios27_motion.dart';

void main() {
  const mapping = GlassMaterializeMapping(disappearExponent: 3, appearGain: 0.5);

  test('appearing glass follows its spring and overshoots by the fitted gain; disappearing glass follows the remainder to the fitted power', () {
    expect(GlassMaterialize.progress(0.4, appearing: true, mapping: mapping), 0.4);
    expect(GlassMaterialize.progress(1.08, appearing: true, mapping: mapping), closeTo(1.04, 1e-12));
    expect(GlassMaterialize.progress(-0.05, appearing: true, mapping: mapping), 0);
    expect(GlassMaterialize.progress(0.4, appearing: false, mapping: mapping), closeTo(math.pow(0.4, 3), 1e-12));
    expect(GlassMaterialize.progress(-0.05, appearing: false, mapping: mapping), 0);
    expect(GlassMaterialize.progress(1.2, appearing: false, mapping: mapping), 1);
  });

  test('under Reduce Motion an appearing glass overshoots by its own fitted gain', () {
    const both = GlassMaterializeMapping(disappearExponent: 3, appearGain: 0.3, reduceMotionAppearGain: 0.8);
    expect(GlassMaterialize.progress(1.1, appearing: true, mapping: both), closeTo(1.03, 1e-12));
    expect(GlassMaterialize.progress(1.1, appearing: true, mapping: both, reduceMotion: true), closeTo(1.08, 1e-12));
    expect(const GlassMaterializeMapping(disappearExponent: 3, appearGain: 0.3).reduceMotionAppearGain, 0.3);
    expect(GlassMaterializeMapping.bouncy.reduceMotionAppearGain, ios27BouncyReduceMotionAppearGain);
  });

  test('each preset uses its own fitted mapping, and a custom spring the preset nearest its damping', () {
    expect(GlassMaterializeMapping.of(GlassAnimation.defaultSpring), GlassMaterializeMapping.defaultSpring);
    expect(GlassMaterializeMapping.of(GlassAnimation.smooth), GlassMaterializeMapping.defaultSpring);
    expect(GlassMaterializeMapping.of(GlassAnimation.snappy), GlassMaterializeMapping.snappy);
    expect(GlassMaterializeMapping.of(GlassAnimation.bouncy), GlassMaterializeMapping.bouncy);
    expect(GlassMaterializeMapping.of(const GlassAnimation.dampedSpring(response: 0.3, dampingFraction: 0.5)), GlassMaterializeMapping.bouncy);
    expect(GlassMaterializeMapping.of(const GlassAnimation.dampedSpring(response: 0.3, dampingFraction: 0.9)), GlassMaterializeMapping.snappy);
    expect(GlassMaterializeMapping.of(const GlassAnimation.dampedSpring(response: 0.3, dampingFraction: 1.4)), GlassMaterializeMapping.defaultSpring);
    expect(GlassMaterializeMapping.defaultSpring.disappearExponent, ios27DefaultDisappearExponent);
    expect(GlassMaterializeMapping.snappy.appearGain, ios27SnappyAppearGain);
    expect(GlassMaterializeMapping.bouncy.disappearExponent, ios27BouncyDisappearExponent);
  });

  test('visibility interpolates the fitted table, stays at 0 below it and extends its last slope above 1', () {
    const table = [0.0, 0.2, 1.0];
    expect(GlassMaterialize.visibility(0, table: table), 0);
    expect(GlassMaterialize.visibility(0.25, table: table), closeTo(0.1, 1e-12));
    expect(GlassMaterialize.visibility(0.75, table: table), closeTo(0.6, 1e-12));
    expect(GlassMaterialize.visibility(1, table: table), 1);
    expect(GlassMaterialize.visibility(1.05, table: table), closeTo(1.08, 1e-12));
    expect(GlassMaterialize.visibility(-1, table: table), 0);
    expect(ios27VisibilityForProgress.first, 0);
    expect(ios27VisibilityForProgress.last, 1);
    for (var i = 1; i < ios27VisibilityForProgress.length; i++) {
      expect(ios27VisibilityForProgress[i], greaterThanOrEqualTo(ios27VisibilityForProgress[i - 1]));
    }
  });

  test('reversing keeps the visible progress, and a falling rate stays continuous', () {
    for (final (presence, velocity) in [(0.6, -2.0), (0.3, -1.5), (0.9, -0.4)]) {
      final before = GlassMaterialize.progress(presence, appearing: true, mapping: mapping);
      final (next, nextVelocity) = GlassMaterialize.reverse(presence, velocity, toAppearing: false, from: mapping, to: mapping);
      expect(GlassMaterialize.progress(next, appearing: false, mapping: mapping), closeTo(before, 1e-9));
      final rate = 3 * math.pow(next, 2) * nextVelocity;
      expect(rate, closeTo(velocity, 1e-9));
    }
    for (final (presence, velocity) in [(0.6, 2.0), (0.3, 1.5)]) {
      final before = GlassMaterialize.progress(presence, appearing: false, mapping: mapping);
      final (next, nextVelocity) = GlassMaterialize.reverse(presence, velocity, toAppearing: true, from: mapping, to: mapping);
      expect(GlassMaterialize.progress(next, appearing: true, mapping: mapping), closeTo(before, 1e-9));
      expect(nextVelocity, closeTo(3 * math.pow(presence, 2) * velocity, 1e-9));
    }
  });

  test('a removal never reverses into a rise, and an insertion never into a fall, however early', () {
    for (final presence in [0.0035, 0.05, 0.4, 1.03]) {
      final (_, removed) = GlassMaterialize.reverse(presence, 6, toAppearing: false, from: mapping, to: mapping);
      expect(removed, lessThanOrEqualTo(0));
      final (_, inserted) = GlassMaterialize.reverse(presence, -6, toAppearing: true, from: mapping, to: mapping);
      expect(inserted, greaterThanOrEqualTo(0));
    }
  });
}
