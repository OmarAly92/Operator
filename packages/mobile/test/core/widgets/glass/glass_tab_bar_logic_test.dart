import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/widgets/glass/glass_tab_bar_logic.dart';

void main() {
  test('slotAt maps x to a clamped slot', () {
    expect(GlassTabBarLogic.slotAt(0, 300, 3), 0);
    expect(GlassTabBarLogic.slotAt(150, 300, 3), 1);
    expect(GlassTabBarLogic.slotAt(299, 300, 3), 2);
    expect(GlassTabBarLogic.slotAt(-40, 300, 3), 0);
    expect(GlassTabBarLogic.slotAt(900, 300, 3), 2);
  });

  test('the end pills sit one inset from the bar ends and the rest spread evenly', () {
    final pill = GlassTabBarLogic.pillWidth(300, 3);
    expect(pill, closeTo(292 / 3 * GlassTabBarLogic.pillWidthScale, 1e-9));
    expect(GlassTabBarLogic.slotCenter(0, 300, 3) - pill / 2, closeTo(4, 1e-9));
    expect(GlassTabBarLogic.slotCenter(1, 300, 3), closeTo(150, 1e-9));
    expect(GlassTabBarLogic.slotCenter(2, 300, 3) + pill / 2, closeTo(296, 1e-9));
    expect(GlassTabBarLogic.slotCenter(0, 300, 1), 150);
  });

  test('the lens center stays between the first and last item centers', () {
    expect(GlassTabBarLogic.lensCenter(0, 300, 3), GlassTabBarLogic.slotCenter(0, 300, 3));
    expect(GlassTabBarLogic.lensCenter(150, 300, 3), 150);
    expect(GlassTabBarLogic.lensCenter(300, 300, 3), GlassTabBarLogic.slotCenter(2, 300, 3));
  });

  test('proximity is 1 under the lens center and 0 past its edge', () {
    expect(GlassTabBarLogic.proximity(100, 100, 120), 1);
    expect(GlassTabBarLogic.proximity(130, 100, 120), 0.5);
    expect(GlassTabBarLogic.proximity(200, 100, 120), 0);
  });

  test('a critically damped spring reaches its target without overshoot', () {
    var (x, v) = (0.0, 0.0);
    var peak = 0.0;
    for (var i = 0; i < 60; i++) {
      (x, v) = GlassTabBarLogic.springStep(value: x, velocity: v, target: 100, omega: 25, damping: 1, seconds: 1 / 60);
      if (x > peak) peak = x;
    }
    expect(x, closeTo(100, 0.5));
    expect(peak, lessThanOrEqualTo(100.01));
  });

  test('an underdamped spring overshoots and settles', () {
    var (x, v) = (0.0, 0.0);
    var peak = 0.0;
    for (var i = 0; i < 120; i++) {
      (x, v) = GlassTabBarLogic.springStep(value: x, velocity: v, target: 1, omega: 14, damping: 0.45, seconds: 1 / 60);
      if (x > peak) peak = x;
    }
    expect(peak, greaterThan(1.1));
    expect(x, closeTo(1, 0.02));
  });

  test('a release selects only within a hit target of the bar', () {
    expect(GlassTabBarLogic.releaseSelects(const Offset(10, 10), 300, 62), isTrue);
    expect(GlassTabBarLogic.releaseSelects(const Offset(10, -40), 300, 62), isTrue);
    expect(GlassTabBarLogic.releaseSelects(const Offset(10, -50), 300, 62), isFalse);
    expect(GlassTabBarLogic.releaseSelects(const Offset(10, 110), 300, 62), isFalse);
    expect(GlassTabBarLogic.releaseSelects(const Offset(-50, 10), 300, 62), isFalse);
  });
}
