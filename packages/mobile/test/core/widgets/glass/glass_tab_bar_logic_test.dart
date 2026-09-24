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

  test('slotCenter is the middle of each slot', () {
    expect(GlassTabBarLogic.slotCenter(0, 300, 3), 50);
    expect(GlassTabBarLogic.slotCenter(2, 300, 3), 250);
  });

  test('dropletLeft keeps the droplet inside the bar', () {
    expect(GlassTabBarLogic.dropletLeft(centerX: 10, dropletWidth: 100, barWidth: 300), 0);
    expect(GlassTabBarLogic.dropletLeft(centerX: 150, dropletWidth: 100, barWidth: 300), 100);
    expect(GlassTabBarLogic.dropletLeft(centerX: 295, dropletWidth: 100, barWidth: 300), 200);
  });

  test('stretchFor grows with speed and is capped', () {
    expect(GlassTabBarLogic.stretchFor(0), 1.0);
    expect(GlassTabBarLogic.stretchFor(8), greaterThan(1.0));
    expect(GlassTabBarLogic.stretchFor(-8), GlassTabBarLogic.stretchFor(8));
    expect(GlassTabBarLogic.stretchFor(1000), 1.2);
  });

  test('a release selects only within a hit target of the bar', () {
    expect(GlassTabBarLogic.releaseSelects(const Offset(10, 10), 300, 62), isTrue);
    expect(GlassTabBarLogic.releaseSelects(const Offset(10, -40), 300, 62), isTrue);
    expect(GlassTabBarLogic.releaseSelects(const Offset(10, -50), 300, 62), isFalse);
    expect(GlassTabBarLogic.releaseSelects(const Offset(10, 110), 300, 62), isFalse);
    expect(GlassTabBarLogic.releaseSelects(const Offset(-50, 10), 300, 62), isFalse);
  });
}
