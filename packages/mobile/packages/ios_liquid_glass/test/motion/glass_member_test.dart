import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';
import 'package:ios_liquid_glass/src/motion/glass_materialize.dart';
import 'package:ios_liquid_glass/src/motion/glass_motion_coordinator.dart';
import 'package:ios_liquid_glass/src/motion/ios27_motion.dart';

class _Tripwire extends RenderProxyBox {
  _Tripwire({RenderBox? child}) : super(child);

  bool armed = false;

  @override
  void applyPaintTransform(RenderObject child, Matrix4 transform) {
    if (armed) throw StateError('a transform was read');
    super.applyPaintTransform(child, transform);
  }
}

class _Space {
  _Space(GlassMotionCoordinator coordinator) {
    box = RenderConstrainedBox(additionalConstraints: BoxConstraints.tight(const Size(100, 40)));
    holder = RenderPositionedBox(alignment: Alignment.topLeft, child: box);
    tripwire = _Tripwire(child: holder);
    root = RenderConstrainedBox(additionalConstraints: BoxConstraints.tight(const Size(400, 400)), child: tripwire);
    owner.rootNode = root;
    root.layout(const BoxConstraints());
    coordinator.marker = holder;
    lay();
  }

  late final RenderConstrainedBox box;
  late final RenderPositionedBox holder;
  late final _Tripwire tripwire;
  late final RenderConstrainedBox root;
  final PipelineOwner owner = PipelineOwner();

  void lay({Size size = const Size(100, 40), Alignment alignment = Alignment.topLeft}) {
    box.additionalConstraints = BoxConstraints.tight(size);
    holder.alignment = alignment;
    owner.flushLayout();
  }
}

void main() {
  tearDown(debugResetGlassAnimation);

  testWidgets('an inserted member appears from 0 along its spring and settles at full visibility', (tester) async {
    await tester.pump();
    final coordinator = GlassMotionCoordinator(vsync: const TestVSync());
    addTearDown(coordinator.dispose);
    final member = coordinator.join(inserted: true);
    expect(member.presence, GlassPresence.appearing);
    expect(member.visibility.value, 0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(member.visibility.value, inExclusiveRange(0, 1));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 16));
    expect(member.presence, GlassPresence.present);
    expect(member.visibility.value, 1);
    expect(member.isMoving, isFalse);
  });

  testWidgets('a member inserted under Reduce Motion overshoots by the Reduce Motion gain of its preset', (tester) async {
    await tester.pump();
    final coordinator = GlassMotionCoordinator(vsync: const TestVSync());
    addTearDown(coordinator.dispose);
    final normal = coordinator.join(inserted: true, scope: GlassAnimation.bouncy);
    final reduced = coordinator.join(inserted: true, scope: GlassAnimation.bouncy, reduceMotion: true);
    await tester.pump();
    var peak = (normal: 0.0, reduced: 0.0);
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      peak = (normal: math.max(peak.normal, normal.progress), reduced: math.max(peak.reduced, reduced.progress));
    }
    final overshoot = peak.normal - 1;
    expect(overshoot, greaterThan(0));
    expect(peak.reduced - 1, closeTo(overshoot * ios27BouncyReduceMotionAppearGain / ios27BouncyAppearGain, 1e-3));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 16));
  });

  testWidgets('a member that was not inserted, or joins under GlassAnimation.none, is present at once', (tester) async {
    await tester.pump();
    final coordinator = GlassMotionCoordinator(vsync: const TestVSync());
    addTearDown(coordinator.dispose);
    expect(coordinator.join().presence, GlassPresence.present);
    expect(coordinator.join(inserted: true, scope: GlassAnimation.none).presence, GlassPresence.present);
    expect(coordinator.join(inserted: true, animate: false).presence, GlassPresence.present);
  });

  testWidgets('a leaving member becomes a ghost at its last on-screen rect, fades to the mapped power and is dropped', (tester) async {
    await tester.pump();
    final coordinator = GlassMotionCoordinator(vsync: const TestVSync());
    addTearDown(coordinator.dispose);
    final space = _Space(coordinator);
    final member = coordinator.join()
      ..attachBox(space.box)
      ..shape = const LiquidRoundedRectangle(borderRadius: 20)
      ..sharedSettings = const LiquidGlassSettings();
    member.sized(space.box.size);
    expect(member.drawn, const Rect.fromLTWH(0, 0, 100, 40));
    expect(coordinator.leave(member, animate: true), isTrue);
    expect(coordinator.ghosts, isEmpty);
    final ghost = coordinator.takeGhosts().single;
    expect(ghost.rect, const Rect.fromLTWH(0, 0, 100, 40));
    expect(ghost.snapshot, isNull);
    expect(member.presence, GlassPresence.disappearing);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final presence = member.progress;
    expect(presence, inExclusiveRange(0, 1));
    expect(member.visibility.value, closeTo(GlassMaterialize.visibility(presence), 1e-12));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 16));
    expect(coordinator.ghosts, isEmpty);
  });

  testWidgets('leaving reads no transform, so a removal during build never touches an ancestor that is not laid out yet', (tester) async {
    await tester.pump();
    final coordinator = GlassMotionCoordinator(vsync: const TestVSync());
    addTearDown(coordinator.dispose);
    final space = _Space(coordinator);
    space.lay(alignment: Alignment.center);
    final member = coordinator.join()
      ..attachBox(space.box)
      ..shape = const LiquidRoundedRectangle(borderRadius: 20)
      ..sharedSettings = const LiquidGlassSettings();
    member.sized(space.box.size);
    expect(member.drawn, const Rect.fromLTWH(150, 180, 100, 40));
    space.tripwire.armed = true;
    expect(coordinator.leave(member, animate: true), isTrue);
    expect(coordinator.takeGhosts().single.rect, const Rect.fromLTWH(150, 180, 100, 40));
    space.tripwire.armed = false;
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 16));
  });

  testWidgets('a member that leaves and rejoins in the same frame keeps its state and leaves no ghost', (tester) async {
    await tester.pump();
    final coordinator = GlassMotionCoordinator(vsync: const TestVSync());
    addTearDown(coordinator.dispose);
    final space = _Space(coordinator);
    final member = coordinator.join()
      ..attachBox(space.box)
      ..shape = const LiquidRoundedRectangle(borderRadius: 20)
      ..sharedSettings = const LiquidGlassSettings();
    member.sized(space.box.size);
    member.drawn;
    expect(coordinator.leave(member, animate: true), isTrue);
    coordinator.rejoin(member);
    expect(coordinator.takeGhosts(), isEmpty);
    expect(member.presence, GlassPresence.present);
    expect(coordinator.members, contains(member));
  });

  testWidgets('a member that was never drawn, or leaves without an animation, leaves no ghost', (tester) async {
    await tester.pump();
    final coordinator = GlassMotionCoordinator(vsync: const TestVSync());
    addTearDown(coordinator.dispose);
    final undrawn = coordinator.join()..shape = const LiquidRoundedRectangle(borderRadius: 20);
    expect(coordinator.leave(undrawn, animate: true), isFalse);
    final space = _Space(coordinator);
    final member = coordinator.join()
      ..attachBox(space.box)
      ..shape = const LiquidRoundedRectangle(borderRadius: 20)
      ..sharedSettings = const LiquidGlassSettings();
    member.sized(space.box.size);
    expect(coordinator.leave(member, animate: false), isFalse);
    expect(coordinator.takeGhosts(), isEmpty);
    expect(coordinator.leave(member, animate: true), isFalse);
  });

  testWidgets('a layout change after a rebuild springs the drawn rect from where it was; without one it jumps', (tester) async {
    await tester.pump();
    final coordinator = GlassMotionCoordinator(vsync: const TestVSync());
    addTearDown(coordinator.dispose);
    final space = _Space(coordinator);
    final member = coordinator.join()..attachBox(space.box);
    member.sized(space.box.size);
    expect(member.drawn, const Rect.fromLTWH(0, 0, 100, 40));
    member.rebuilt();
    space.lay(size: const Size(200, 40), alignment: Alignment.center);
    member.sized(space.box.size);
    expect(member.drawn, const Rect.fromLTWH(0, 0, 100, 40));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final mid = member.drawn!;
    expect(mid.width, inExclusiveRange(100, 200));
    expect(mid.left, inExclusiveRange(0, 100));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 16));
    expect(member.drawn, const Rect.fromLTWH(100, 180, 200, 40));
    space.lay(size: const Size(200, 40));
    member.sized(space.box.size);
    expect(member.drawn, const Rect.fromLTWH(0, 0, 200, 40));
    expect(member.isMoving, isFalse);
  });

  testWidgets('reversing a removal mid-appear keeps the visible progress and never rises', (tester) async {
    await tester.pump();
    final coordinator = GlassMotionCoordinator(vsync: const TestVSync());
    addTearDown(coordinator.dispose);
    final space = _Space(coordinator);
    final member = coordinator.join(inserted: true)
      ..attachBox(space.box)
      ..shape = const LiquidRoundedRectangle(borderRadius: 20)
      ..sharedSettings = const LiquidGlassSettings();
    member.sized(space.box.size);
    expect(member.drawn, const Rect.fromLTWH(0, 0, 100, 40));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final before = member.progress;
    coordinator.leave(member, animate: true);
    coordinator.takeGhosts();
    expect(member.progress, closeTo(before, 1e-9));
    var last = member.progress;
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      if (coordinator.ghosts.isEmpty) break;
      expect(member.progress, lessThanOrEqualTo(last + 1e-12));
      last = member.progress;
    }
    expect(math.min(last, 1), lessThan(before));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 16));
    expect(coordinator.ghosts, isEmpty);
  });
}
