import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/src/motion/glass_animation.dart';
import 'package:ios_liquid_glass/src/motion/glass_spring.dart';
import 'package:motor/motor.dart';

void main() {
  tearDown(debugResetGlassAnimation);

  test("presets are SwiftUI's springs, the values motor's CupertinoMotion uses", () {
    double response(CupertinoMotion motion) => motion.duration.inMicroseconds / Duration.microsecondsPerSecond;
    double damping(CupertinoMotion motion) => motion.bounce > 0 ? 1 - motion.bounce : 1 / (1 + motion.bounce);
    for (final (animation, motion) in [
      (GlassAnimation.defaultSpring, const CupertinoMotion()),
      (GlassAnimation.smooth, const CupertinoMotion.smooth()),
      (GlassAnimation.snappy, const CupertinoMotion.snappy()),
      (GlassAnimation.bouncy, const CupertinoMotion.bouncy()),
    ]) {
      expect(animation.response, response(motion));
      expect(animation.dampingFraction, damping(motion));
    }
    expect((GlassAnimation.defaultSpring.response, GlassAnimation.defaultSpring.dampingFraction), (0.55, 1.0));
    expect(GlassAnimation.snappy.response, 0.5);
    expect(GlassAnimation.snappy.dampingFraction, closeTo(0.85, 1e-12));
    expect(GlassAnimation.bouncy.response, 0.5);
    expect(GlassAnimation.bouncy.dampingFraction, closeTo(0.7, 1e-12));
    const custom = GlassAnimation.dampedSpring(response: 0.3, dampingFraction: 0.75);
    expect((custom.response, custom.dampingFraction), (0.3, 0.75));
    expect(const GlassAnimation.spring(duration: Duration(milliseconds: 400), bounce: -0.5).dampingFraction, 2.0);
    expect(GlassAnimation.none.isNone, isTrue);
  });

  test('the spring is the one the lab fits: stiffness 4π²/response², damping 2ζ√k', () {
    final spring = const GlassAnimation.dampedSpring(response: 0.55, dampingFraction: 1).description;
    expect(spring.mass, 1);
    expect(spring.stiffness, closeTo(130.5, 0.1));
    expect(spring.damping, closeTo(2 * 1.0 * 11.424, 0.01));
  });

  test('a retargeted spring keeps its value and velocity', () {
    final spring = GlassSpring(0)..animateTo(100, GlassAnimation.defaultSpring, Duration.zero);
    spring.sample(const Duration(milliseconds: 80));
    final value = spring.value, velocity = spring.velocity;
    expect(velocity, greaterThan(0));
    spring.animateTo(-50, GlassAnimation.bouncy, const Duration(milliseconds: 80));
    expect(spring.value, value);
    expect(spring.velocity, velocity);
    spring.sample(const Duration(milliseconds: 88));
    expect(spring.value, greaterThan(value));
    spring.sample(const Duration(seconds: 5));
    expect(spring.value, -50);
    expect(spring.isMoving, isFalse);
  });

  test('GlassAnimation.none jumps', () {
    final spring = GlassSpring(0)..animateTo(10, GlassAnimation.none, Duration.zero);
    expect(spring.value, 10);
    expect(spring.isMoving, isFalse);
  });

  testWidgets('withGlassAnimation applies to the next frame, then the scope, then the default', (tester) async {
    GlassAnimation? seen;
    late StateSetter rebuild;
    await tester.pumpWidget(GlassAnimationScope(
      animation: GlassAnimation.snappy,
      child: StatefulBuilder(builder: (context, setState) {
        rebuild = setState;
        seen = resolveGlassAnimation(GlassAnimationScope.maybeOf(context));
        return const SizedBox();
      }),
    ));
    expect(seen, GlassAnimation.snappy);
    withGlassAnimation(GlassAnimation.bouncy, () => rebuild(() {}));
    await tester.pump();
    expect(seen, GlassAnimation.bouncy);
    rebuild(() {});
    await tester.pump();
    expect(seen, GlassAnimation.snappy);
    await tester.pumpWidget(StatefulBuilder(builder: (context, setState) {
      seen = resolveGlassAnimation(GlassAnimationScope.maybeOf(context));
      return const SizedBox();
    }));
    expect(seen, GlassAnimation.defaultSpring);
  });
}
